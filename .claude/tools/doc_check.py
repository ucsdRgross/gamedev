#!/usr/bin/env python3
"""Mechanical health check for this repo's docs and memory.

The judgement half lives in .claude/skills/docs/SKILL.md. This half is the seam check:
every finding here is two representations of one fact that stopped agreeing.

    py .claude/tools/doc_check.py [--verbose]

Exit 0 = clean, 1 = at least one ERROR. WARNs never fail the run; they are prompts to look.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEM = ROOT / ".claude" / "memory"
INDEX = MEM / "MEMORY.md"

# Memories allowed to name a single project: they exist to point at projects.
SCOPE_EXEMPT = {"architecture-map", "machine-profiles", "MEMORY"}

# Living docs — the ones a session reads to change something. Plan artifacts under
# design/ are deliberately excluded: they are dated records by nature.
LIVING_GLOBS = ["*.md", "solatro/*.md", "worldgen/*.md", "worldgen/*/*.md",
                "palette/*.md", "designloop/*.md", ".claude/memory/*.md",
                ".claude/skills/*/SKILL.md", ".claude/agents/*.md"]

# Directories whose .md files are not "living docs": plan artifacts are dated by nature,
# vendored trees are not ours. This does NOT limit what a reference may resolve to.
SKIP_PARTS = {".git", "node_modules", "godot-cpp", "addons", "design", ".godot"}
# Only these are skipped when indexing the repo to resolve references.
INDEX_SKIP = {".git", "node_modules", ".godot", ".import"}

# Created at runtime, never on disk in a clean checkout. A doc naming one is correct.
RUNTIME_ARTIFACTS = {
    "run.tres", "settings.tres", "answers.json", "answers.log", "meta.json", "graph.json",
    "status.owner.json", "status.agent.json", "test_output_all.log", "test_output_errors.log",
    "summary.log", "visual_log.log", "visual_log_by_frame.log", "package-lock.json",
    "run.tmp.tres", "annotations.json", "layout.json", "transcript.md", "changelog.md",
}

# Generic stand-ins used in prose ("pin `file.gd:line`"), never real paths.
PLACEHOLDER_NAMES = {"file.gd", "file.md", "name.md", "x.gd", "foo.gd"}

# A line may name a file that is gone when it is explaining that it is gone — "X is DELETED,
# absorbed by Y" is design rationale, not a broken link.
GONE_ON_PURPOSE = re.compile(
    r"\b(deleted|removed|retired|superseded|absorbed|replaces|no longer exists|used to)\b", re.I)

DATE = re.compile(r"20\d\d-\d\d-\d\d")
WIKILINK = re.compile(r"\[\[([a-z0-9-]+)\]\]")
INDEX_ENTRY = re.compile(r"\]\(([a-z0-9-]+)\.md\)")
# A path-ish token with a real extension. Bare words and res:// are not our problem.
FILEREF = re.compile(r"(?<![\w/])((?:[\w.-]+/)*[\w.-]+\.(?:md|py|gd|gdshader|tscn|tres|json|csv|ps1|cmd|mjs|js))(?![\w])")
ABSPATH = re.compile(r"[A-Za-z]:\\[^\s`\"'|)]+")

PROJECTS = ["solatro", "worldgen", "palette", "designloop"]

# --- code comments -------------------------------------------------------------------------
# Comments are docs that happen to live in source files, and they drift the same way. They are
# checked for the same three things a living doc is: references that resolve, no absolute paths,
# no history — plus the two failure modes specific to them (a block that has become an essay, and
# a fact restated at a second site instead of pointed at).
CODE_GLOBS = ["*.gd", "*.gdshader", "*.mjs", "*.py"]
CODE_SKIP = {".git", "node_modules", "godot-cpp", "addons", ".godot", ".import", "dist", "build"}
# Over this many consecutive comment lines, say what the block is FOR and point at the doc that
# carries the detail. Tuned so the surviving long blocks are the ones that earn it (signature
# tables, numbered contracts) rather than a round number.
COMMENT_BLOCK_MAX = 16
# A restated sentence has to be long enough that the repeat is prose, not a shared idiom.
DUP_SENTENCE_MIN = 70
LINE_REF = re.compile(r"\b[\w.-]+\.(?:gd|gdshader|mjs|js|py|tscn|tres)\s*:\s*\d+")
# Narrating how the code got here. Each is a phrase that only appears when a comment is telling a
# story — the rule it produced is what belongs, not the plot.
HISTORY_PHRASE = re.compile(
    r"\b(used to (be|sit|call|live|ask|size)|the (first|old|original) (build|draft|version)|"
    r"cost (me|us|\w+) (a|an|\d+|two|three|several)|wasted|for a whole phase|"
    r"I (had|was|filed|took|reasoned)|we (forgot|assumed)|turned out to be|"
    r"was purged|has been (renamed|retired) )", re.I)
# A DESIGN-PROCESS ID: a questionnaire answer, a gap file, a plan step, a flowchart node, or the
# design documents themselves. These name a conversation the reader of the code cannot see and
# which the code outlives. State the RULE the answer produced; the design docs keep the provenance.
DESIGN_ID = re.compile(
    r"(?<![\w-])(Q\d{1,3}|QR\d{1,2}|GAP-\d{3}|"
    r"PLAN\.md|DESIGN\.md|TEST_PLAN\.md|NAMES\.md|ASSUMPTIONS\.md)(?![\w-])")
# The same ids inside a STRING LITERAL — an Inspector group label, a button caption, a localisation
# value. A layering breach, not a style nit: it puts the design conversation on screen in front of
# someone with no way to read it. Always an error, never summarised.
DESIGN_ID_IN_STRING = re.compile(
    r"""["']([^"'\n]*(?<![\w-])(?:Q\d{1,3}|QR\d{1,2}|GAP-\d{3})(?![\w-])[^"'\n]*)["']""")
# ⚠ Two exemptions from BOTH design-id checks. TEST files: a test's job is defending one decision,
# so naming it — in an assertion message or the comment above it — says which decision just broke,
# and nobody outside the suite reads either. DESIGNLOOP: question ids are that project's SUBJECT
# MATTER, so there is no other layer for them to leak from.
DESIGN_ID_SKIP = ("Tests/", "/test/", "/tests/", "designloop/")
# This file defines the patterns, so it necessarily contains examples of them.
SELF = ".claude/tools/doc_check.py"

errors: list[str] = []
warns: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warns.append(msg)


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def living_docs() -> list[Path]:
    seen: dict[Path, None] = {}
    for g in LIVING_GLOBS:
        for p in ROOT.glob(g):
            if p.is_file() and not (SKIP_PARTS & set(p.relative_to(ROOT).parts)):
                seen[p] = None
    return sorted(seen)


def check_memory_links_and_index() -> None:
    if not INDEX.exists():
        err(f"{rel(INDEX)} is missing — the index is what a session actually loads")
        return

    files = {p.stem for p in MEM.glob("*.md") if p.name != "MEMORY.md"}

    for p in sorted(MEM.glob("*.md")):
        for m in WIKILINK.finditer(p.read_text(encoding="utf-8", errors="replace")):
            if m.group(1) not in files:
                err(f"{rel(p)}: [[{m.group(1)}]] points at no memory file")

    text = INDEX.read_text(encoding="utf-8", errors="replace")
    indexed = set(INDEX_ENTRY.findall(text))
    for name in sorted(indexed - files):
        err(f"MEMORY.md indexes '{name}' but {name}.md is not on disk")
    for name in sorted(files - indexed):
        err(f"{name}.md exists but MEMORY.md does not index it — it will never be recalled")

    # The index is loaded every session. Hooks only.
    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("- ["):
            continue
        if DATE.search(line):
            warn(f"MEMORY.md:{i}: index line carries a date — hooks only, no status")
        if len(line) > 160:
            warn(f"MEMORY.md:{i}: index line is {len(line)} chars — compress to a hook")


def check_memory_scope() -> None:
    for p in sorted(MEM.glob("*.md")):
        if p.stem in SCOPE_EXEMPT:
            continue
        text = p.read_text(encoding="utf-8", errors="replace").lower()
        counts = {proj: text.count(proj) for proj in PROJECTS if proj in text}
        # Citing one project as the example is fine; being ABOUT one project is not.
        if len(counts) == 1:
            proj, n = next(iter(counts.items()))
            if n >= 4:
                warn(f"{rel(p)}: names '{proj}' {n}x and no other project — this may be "
                     f"project guidance that belongs in {proj}/ (SKILL.md step 2 before deleting)")


def repo_filenames() -> set[str]:
    """Every filename in the repo, so a reference resolves by basename even from a partial path."""
    names: set[str] = set()
    for p in ROOT.rglob("*"):
        if p.is_file() and not (INDEX_SKIP & set(p.relative_to(ROOT).parts)):
            names.add(p.name)
    return names


def check_file_refs(docs: list[Path], names: set[str]) -> None:
    for doc in docs:
        for i, line in enumerate(doc.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if line.startswith("    ") or line.lstrip().startswith("```"):
                continue  # code block or indented literal — not prose making a claim
            if GONE_ON_PURPOSE.search(line):
                continue
            for m in FILEREF.finditer(line):
                ref = m.group(1)
                base = Path(ref).name
                if ref.startswith(("res://", "user://", "http")):
                    continue
                if base in RUNTIME_ARTIFACTS or base in PLACEHOLDER_NAMES:
                    continue
                # A template or a range, not a filename: GAP-NNN.md, GAP-00N.md, GAP-001..008.md
                if re.search(r"N{2,}|\d[Nn]\.|\.\.", base):
                    continue
                # Tail of a glob or a wildcard the regex clipped: *.test.js, <name>_visual.gd
                if base.startswith(".") or line[max(0, m.start(1) - 1)] in "*<>":
                    continue
                if base not in names:
                    err(f"{rel(doc)}:{i}: references '{ref}', which does not exist")


def check_dates(docs: list[Path], verbose: bool) -> None:
    for doc in docs:
        hits = []
        lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
        # YAML frontmatter is machine-written metadata, not prose making a claim. It exists only
        # when line 1 is exactly '---'; anywhere else a '---' is a horizontal rule.
        skip_to = 0
        if lines and lines[0].rstrip() == "---":
            for j, line in enumerate(lines[1:], 2):
                if line.rstrip() == "---":
                    skip_to = j
                    break
        in_fence = False
        for i, line in enumerate(lines, 1):
            if i <= skip_to:
                continue
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            # A date inside a code block is sample data, not a claim about when work happened.
            if in_fence or line.startswith("    "):
                continue
            if DATE.search(line):
                hits.append((i, line.strip()))
        if not hits:
            continue
        warn(f"{rel(doc)}: {len(hits)} dated line(s) — history belongs in git, not a living doc")
        if verbose:
            for i, line in hits:
                warns.append(f"    {rel(doc)}:{i}: {line[:110]}")


def check_abs_paths(docs: list[Path]) -> None:
    allowed = (MEM / "machine-profiles.md").resolve()
    for doc in docs:
        if doc.resolve() == allowed:
            continue
        in_fence = False
        for i, line in enumerate(doc.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            # A path inside a command is the command; a path in prose is a claim about a machine.
            if in_fence or line.startswith("    "):
                continue
            m = ABSPATH.search(line)
            if m:
                err(f"{rel(doc)}:{i}: hard-codes '{m.group(0)}' — machine-profiles.md is the only "
                    f"home for absolute paths, everything else points at it")


def changed_files() -> list[Path] | None:
    """Files git reports as modified or untracked, or None if git cannot answer.

    ⚠ None and [] mean different things and the caller must not merge them: [] is "nothing changed"
    (say nothing), None is "the scope could not be established" (say so, and check everything).
    """
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"],
                             capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    paths = []
    for line in out.stdout.splitlines():
        if len(line) < 4:
            continue
        name = line[3:].strip().strip('"')
        # A rename reads `old -> new`; only the new path exists to be checked.
        if " -> " in name:
            name = name.split(" -> ", 1)[1]
        p = ROOT / name
        if p.is_file():
            paths.append(p)
    return paths


def check_changed(paths: list[Path], names: set[str]) -> None:
    """The always-a-bug findings, on a given set of files.

    ⚠ **STYLE FINDINGS ARE DELIBERATELY EXCLUDED.** This runs unattended at a task boundary, and the
    repo carries a standing backlog of hundreds of dated and over-long comments (todo.md). Reporting
    those on every edit trains the reader to skip the report, which costs the findings that are
    always real: a reference that resolves to nothing, an absolute path, and a design-process id
    that has escaped into the code.
    """
    docs = [p for p in paths if p.suffix == ".md"]
    code = [p for p in paths if p.suffix in {".gd", ".gdshader", ".mjs", ".py"}]
    if docs:
        check_file_refs(docs, names)
        check_abs_paths(docs)
    for path in code:
        for i, text in design_ids_in_strings(path):
            err(f"{rel(path)}:{i}: the string \"{text}\" carries a design-process id — it reaches "
                f"a reader who cannot look it up")
        for i, text in comment_lines(path):
            m = None if design_id_exempt(path) else DESIGN_ID.search(text)
            if m:
                err(f"{rel(path)}:{i}: cites '{m.group(0)}' — a design-process id names a document "
                    f"the reader of this code cannot see; state the RULE instead")
            m = ABSPATH.search(text)
            if m:
                err(f"{rel(path)}:{i}: hard-codes '{m.group(0)}' — machine-profiles.md is the only "
                    f"home for absolute paths")
            if GONE_ON_PURPOSE.search(text):
                continue
            for fm in FILEREF.finditer(text):
                ref = fm.group(1)
                base = Path(ref).name
                if ref.startswith(("res://", "user://", "http")) or base in RUNTIME_ARTIFACTS:
                    continue
                if base in PLACEHOLDER_NAMES or re.search(r"N{2,}|\d[Nn]\.|\.\.", base):
                    continue
                if base.startswith(".") or Path(base).stem.endswith("-"):
                    continue
                if text[max(0, fm.start(1) - 1)] in "*<>":
                    continue
                if base not in names:
                    err(f"{rel(path)}:{i}: references '{ref}', which does not exist")


def design_id_exempt(path: Path) -> bool:
    return rel(path) == SELF or any(k in path.as_posix() for k in DESIGN_ID_SKIP)


def design_ids_in_strings(path: Path) -> list[tuple[int, str]]:
    """(line, text) for every design-process id inside a string literal — the layering breach.

    An `@export_group("Content mode (GAP-017=c)")` is an Inspector heading; a localisation value is
    a caption. Either way the design conversation ends up on screen in front of someone with no
    access to it. See DESIGN_ID_STRING_SKIP for the two exemptions.
    """
    if design_id_exempt(path):
        return []
    out = []
    for i, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if raw.strip().startswith(("#", "//", "*")):
            continue
        m = DESIGN_ID_IN_STRING.search(raw)
        if m:
            out.append((i, m.group(1)[:60]))
    return out


def code_files() -> list[Path]:
    seen: dict[Path, None] = {}
    for proj in PROJECTS:
        for g in CODE_GLOBS:
            for p in (ROOT / proj).rglob(g):
                if p.is_file() and not (CODE_SKIP & set(p.relative_to(ROOT).parts)):
                    seen[p] = None
    for g in CODE_GLOBS:
        for p in (ROOT / ".claude").rglob(g):
            if p.is_file():
                seen[p] = None
    return sorted(seen)


def comment_lines(path: Path) -> list[tuple[int, str]]:
    """(line number, comment text) for every comment line, docstrings excluded.

    Deliberately line-based: a `#` or `//` inside a string literal reads as a comment here. That
    costs a rare false positive and buys a checker that cannot itself drift out of step with four
    languages' grammars.
    """
    out = []
    for i, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        s = raw.strip()
        if path.suffix in {".gd", ".py"}:
            if s.startswith("#"):
                out.append((i, s.lstrip("#").strip()))
        elif s.startswith("//") or (s.startswith("*") and not s.startswith("*/")):
            out.append((i, s.lstrip("/*").strip()))
    return out


def check_code_comments(verbose: bool, names: set[str]) -> int:
    """The living-doc rules, applied to comments. Returns the number of files scanned.

    ⚠ The style findings are SUMMARISED unless --verbose. There are hundreds of them, and a wall of
    warnings is a wall nobody reads — the same reason `unclaimed` carries a triage list. Broken
    references and absolute paths are reported individually, because those are always bugs.
    """
    files = code_files()
    seen_sentences: dict[str, tuple[str, int]] = {}
    style: dict[str, list[str]] = {}

    def style_hit(kind: str, detail: str) -> None:
        style.setdefault(kind, []).append(detail)
    for path in files:
        for i, text in design_ids_in_strings(path):
            style_hit("design id in a string", f"{rel(path)}:{i}: {text}")
        comments = comment_lines(path)
        commented = {i for i, _ in comments}

        # A run of comment lines that has become an essay.
        block_start, block_len = 0, 0
        for i in range(1, (max(commented) if commented else 0) + 2):
            if i in commented:
                if not block_len:
                    block_start = i
                block_len += 1
                continue
            if block_len > COMMENT_BLOCK_MAX:
                style_hit("long block", f"{rel(path)}:{block_start} ({block_len} lines)")
            block_len = 0

        for i, text in comments:
            if DATE.search(text):
                style_hit("dated", f"{rel(path)}:{i}")
            if HISTORY_PHRASE.search(text):
                style_hit("history", f"{rel(path)}:{i}: {text[:70]}")
            m = None if design_id_exempt(path) else DESIGN_ID.search(text)
            if m:
                style_hit("design id", f"{rel(path)}:{i} cites {m.group(0)}")
            m = LINE_REF.search(text)
            if m:
                style_hit("line ref", f"{rel(path)}:{i} cites {m.group(0)}")
            m = ABSPATH.search(text)
            if m:
                err(f"{rel(path)}:{i}: hard-codes '{m.group(0)}' — machine-profiles.md is the only "
                    f"home for absolute paths")
            for fm in FILEREF.finditer(text):
                ref = fm.group(1)
                base = Path(ref).name
                if ref.startswith(("res://", "user://", "http")) or base in RUNTIME_ARTIFACTS:
                    continue
                if base in PLACEHOLDER_NAMES or re.search(r"N{2,}|\d[Nn]\.|\.\.", base):
                    continue
                if base.startswith(".") or GONE_ON_PURPOSE.search(text):
                    continue
                # A glob tail or a prose hyphen, not a filename: `<name>_visual.gd`, `non-.tres`.
                if text[max(0, fm.start(1) - 1)] in "*<>" or Path(base).stem.endswith("-"):
                    continue
                if base not in names:
                    err(f"{rel(path)}:{i}: references '{ref}', which does not exist — a comment "
                        f"deferring to a doc is only useful if the doc resolves")

            # ⚠ THE DUPLICATE CHECK IS THE POINT OF THIS WHOLE FUNCTION. Two copies of one fact
            # is the seam behind most of this repo's defects; in comments it shows up as the same
            # explanation written at two sites, where only one of them gets updated.
            #
            # ⚠ **A QUOTED OWNER ANSWER IS EXEMPT, AND THE OPPOSITE RULE APPLIES TO IT.** Repeating
            # the owner's verbatim words at every site that relies on them is REQUIRED — paraphrase
            # is the defect `provenance.mjs` and [[design-answers-need-a-claimant]] exist to catch.
            # The first build of this check flagged one GAP-006 quote at three sites as duplication,
            # which would have argued for exactly the summarising those rules forbid.
            if text.lstrip().startswith(">"):
                continue
            for sentence in re.split(r"(?<=[.!?])\s+", text):
                key = re.sub(r"[^a-z0-9 ]+", "", sentence.lower()).strip()
                key = re.sub(r"\s+", " ", key)
                if len(key) < DUP_SENTENCE_MIN:
                    continue
                if key in seen_sentences:
                    first_file, first_line = seen_sentences[key]
                    if first_file != rel(path) or first_line != i:
                        style_hit("restated", f"{rel(path)}:{i} restates {first_file}:{first_line}")
                else:
                    seen_sentences[key] = (rel(path), i)

    blurb = {
        "dated": "the rule belongs, the date is git's",
        "history": "keep the rule and the number, drop the story",
        "long block": f"over {COMMENT_BLOCK_MAX} lines — say what it is FOR, point at the doc",
        "line ref": "a line number is a dead reference waiting to happen; name the symbol",
        "restated": "state it once, point at that name from the other site",
        "design id": "names a doc the code's reader cannot see; state the rule the answer produced",
        "design id in a string": "on screen in front of a reader who cannot look it up — a "
                                 "layering breach, not a style nit",
    }
    for kind in ("design id in a string", "design id", "restated", "line ref", "history",
                 "long block", "dated"):
        hits = style.get(kind)
        if not hits:
            continue
        warn(f"code comments: {len(hits)} {kind} — {blurb[kind]}"
             + ("" if verbose else "  (--verbose to list)"))
        if verbose:
            for h in hits:
                warns.append(f"    {h}")
    return len(files)


def main() -> int:
    # Findings quote the line they are about, and this repo's docs are full of non-cp1252
    # characters. Without this the checker dies on the first ⚠ it tries to report.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verbose", action="store_true", help="list every dated line")
    ap.add_argument("--docs-only", action="store_true",
                    help="skip the code-comment scan (docs and memory only)")
    ap.add_argument("--changed", action="store_true",
                    help="only files git reports as modified or untracked, and only the findings "
                         "that are always bugs (broken references, absolute paths)")
    ap.add_argument("--warn-only", action="store_true",
                    help="always exit 0 — for a task-boundary hook that reports without blocking")
    args = ap.parse_args()

    names = repo_filenames()

    if args.changed:
        paths = changed_files()
        if paths is None:
            print("[doc-check] git could not list changed files — run the full check by hand")
            return 0 if args.warn_only else 1
        if not paths:
            return 0
        check_changed(paths, names)
        for e in errors:
            print(f"ERROR {e}")
        if errors:
            print(f"[doc-check] {len(errors)} broken reference(s) in the {len(paths)} file(s) you "
                  f"just changed. Nothing is blocked — fix them before you hand off.")
        return 0 if args.warn_only or not errors else 1

    docs = living_docs()
    check_memory_links_and_index()
    check_memory_scope()
    check_file_refs(docs, names)
    check_dates(docs, args.verbose)
    check_abs_paths(docs)
    n_code = 0 if args.docs_only else check_code_comments(args.verbose, names)

    for w in warns:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")

    scanned = f"{len(docs)} living docs"
    if n_code:
        scanned += f" + {n_code} source files"
    print(f"\n{scanned} checked - {len(errors)} error(s), {len(warns)} warning(s)")
    if errors:
        print("Errors are broken references or a memory index out of sync. Fix them.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
