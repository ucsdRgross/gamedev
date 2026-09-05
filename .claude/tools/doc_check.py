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
# A comment is a doc that lives in a source file, so it gets the living-doc rules: references that
# resolve, no absolute paths, no history — plus the placement and length rules below.
CODE_GLOBS = ["*.gd", "*.gdshader", "*.mjs", "*.py"]
CODE_SKIP = {".git", "node_modules", "godot-cpp", "addons", ".godot", ".import", "dist", "build"}
# Two caps, because the two comment kinds do different jobs. A plain `#` block explains WHY a
# method exists and gets three lines. A `##` doc comment is the text Godot shows beside a knob in
# the Inspector, so it gets one line and has to earn it.
COMMENT_BLOCK_MAX = 3
DOC_COMMENT_MAX = 1
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
# ⚠ Exempt from BOTH design-id checks. A TEST defends one decision, so naming it says which one
# broke, and nobody outside the suite reads it. In DESIGNLOOP question ids are the subject matter.
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
    """Wikilinks resolve, the index matches disk, and index lines stay hooks.

    The index is loaded every session, so a line carrying status or a date costs every later
    session tokens for something git already knows.
    """
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

    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith("- ["):
            continue
        if DATE.search(line):
            warn(f"MEMORY.md:{i}: index line carries a date — hooks only, no status")
        if len(line) > 160:
            warn(f"MEMORY.md:{i}: index line is {len(line)} chars — compress to a hook")


def check_memory_scope() -> None:
    """Memory holds only what applies across projects.

    Citing one project as the example is fine; being ABOUT one project is not — that guidance
    belongs in the project's own docs.
    """
    for p in sorted(MEM.glob("*.md")):
        if p.stem in SCOPE_EXEMPT:
            continue
        text = p.read_text(encoding="utf-8", errors="replace").lower()
        counts = {proj: text.count(proj) for proj in PROJECTS if proj in text}
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


def is_literal_line(line: str) -> bool:
    """An indented literal or a fence marker — the line is sample text, not prose making a claim."""
    return line.startswith("    ") or line.lstrip().startswith("```")


def is_template_ref(base: str) -> bool:
    """A stand-in rather than a filename: GAP-NNN.md, GAP-00N.md, GAP-001..008.md."""
    return bool(re.search(r"N{2,}|\d[Nn]\.|\.\.", base))


def is_clipped_ref(base: str, line: str, start: int) -> bool:
    """The tail of a glob or a wildcard the reference regex clipped: *.test.js, <name>_visual.gd."""
    return base.startswith(".") or line[max(0, start - 1)] in "*<>"


def check_file_refs(docs: list[Path], names: set[str]) -> None:
    for doc in docs:
        for i, line in enumerate(doc.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if is_literal_line(line):
                continue
            if GONE_ON_PURPOSE.search(line):
                continue
            for m in FILEREF.finditer(line):
                ref = m.group(1)
                base = Path(ref).name
                if ref.startswith(("res://", "user://", "http")):
                    continue
                if base in RUNTIME_ARTIFACTS or base in PLACEHOLDER_NAMES:
                    continue
                if is_template_ref(base) or is_clipped_ref(base, line, m.start(1)):
                    continue
                if base not in names:
                    err(f"{rel(doc)}:{i}: references '{ref}', which does not exist")


def check_dates(docs: list[Path], verbose: bool) -> None:
    """Dates in living docs, skipping frontmatter and code blocks.

    Frontmatter is machine-written metadata, not a claim, and it exists only when line 1 is exactly
    '---'; anywhere else a '---' is a horizontal rule. A date inside a fence is sample data.
    """
    for doc in docs:
        hits = []
        lines = doc.read_text(encoding="utf-8", errors="replace").splitlines()
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
        if " -> " in name:
            name = name.split(" -> ", 1)[1]
        p = ROOT / name
        if p.is_file():
            paths.append(p)
    return paths


def check_changed(paths: list[Path], names: set[str]) -> None:
    """The always-a-bug findings, plus the three hard comment rules, on a given set of files.

    ⚠ **THE COMMENT RULES ARE ERRORS HERE AND A SUMMARY ON A FULL RUN**, and the split is the whole
    design. The repo carries thousands of pre-existing violations, so reporting them repo-wide on
    every edit would train the reader to skip the report. Scoped to the files a session actually
    touched, they are exact and few: no comment with whitespace before it, none sharing a line with
    code, none longer than three lines.

    ⚠ **THE REST OF THE STYLE FINDINGS STAY EXCLUDED** — dated lines, history, restatement. Those
    are the standing backlog (todo.md), and mixing them back in costs the findings that are always
    real: a reference that resolves to nothing, an absolute path, and a design-process id that has
    escaped into the code.
    """
    docs = [p for p in paths if p.suffix == ".md"]
    code = [p for p in paths if p.suffix in {".gd", ".gdshader", ".mjs", ".py"}]
    if docs:
        check_file_refs(docs, names)
        check_abs_paths(docs)
    for path in code:
        for i, text in indented_comments(path):
            err(f"{rel(path)}:{i}: comment has whitespace before it — a comment sits at column 0 "
                f"above the method and says WHY it exists: \"{text[:60]}\"")
        for i, text in trailing_comments(path):
            err(f"{rel(path)}:{i}: comment shares a line with code — name the step instead of "
                f"annotating it: \"{text[:60]}\"")
        for start, length, is_doc in comment_blocks(path):
            cap = DOC_COMMENT_MAX if is_doc else COMMENT_BLOCK_MAX
            kind = "doc comment" if is_doc else "comment block"
            err(f"{rel(path)}:{start}: {kind} is {length} lines — the limit is {cap}")
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


def split_code_comment(raw: str, fence: str | None) -> tuple[str, str | None, str | None]:
    """Split one line into (code, comment or None, the triple-quote fence still open after it).

    ⚠ A SCANNER, NOT A REGEX, AND THAT IS THE WHOLE POINT. The comment rules are ERRORS, so a `#`
    inside a docstring or a string literal must not read as a comment — a false positive blocks work
    that is already correct.
    """
    i = 0
    while i < len(raw):
        if fence is not None:
            if raw.startswith(fence, i):
                fence, i = None, i + 3
                continue
            i += 1
            continue
        if raw.startswith('"""', i) or raw.startswith("'''", i):
            fence, i = raw[i:i + 3], i + 3
            continue
        ch = raw[i]
        if ch == "#":
            return raw[:i], raw[i:], fence
        if ch in "\"'":
            i += 1
            while i < len(raw) and raw[i] != ch:
                i += 2 if raw[i] == "\\" else 1
            i += 1
            continue
        i += 1
    return raw, None, fence


def real_comments(path: Path) -> list[tuple[int, str, str]]:
    """(line, code before it, comment text) for every comment that is really a comment."""
    out: list[tuple[int, str, str]] = []
    fence: str | None = None
    for i, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        code, comment, fence = split_code_comment(raw, fence)
        if comment is not None:
            out.append((i, code, comment))
    return out


def indented_comments(path: Path) -> list[tuple[int, str]]:
    """(line, text) for every plain `#` comment that has whitespace before it.

    Owner rule: a plain comment sits at column 0, above the method, and says WHY that method exists.
    Indented prose is commentary inside code, and code needing prose to explain itself wants a NAME.

    ⚠ `##` IS EXEMPT FROM PLACEMENT. It is the label Godot renders beside an exported knob, so it
    lives wherever its knob does — indented inside an inner class included. It pays for that freedom
    with the one-line cap in DOC_COMMENT_MAX.
    """
    if path.suffix not in {".gd", ".py"}:
        return []
    out: list[tuple[int, str]] = []
    for i, code, comment in real_comments(path):
        if code.strip() or comment.startswith("##") or not code:
            continue
        out.append((i, comment.lstrip("#").strip()))
    return out


def comment_blocks(path: Path) -> list[tuple[int, int, bool]]:
    """(first line, length, is_doc) for every run of comment lines that exceeds its own cap.

    A run is a doc run when it opens with `##`, and the two kinds are capped differently: prose
    explaining why a method exists gets COMMENT_BLOCK_MAX, an Inspector knob's label gets
    DOC_COMMENT_MAX.
    """
    doc_at = {i: c.startswith("##") for i, code, c in real_comments(path) if not code.strip()}
    out: list[tuple[int, int, bool]] = []
    start = length = 0
    is_doc = False
    for i in range(1, (max(doc_at) if doc_at else 0) + 2):
        if i in doc_at:
            if not length:
                start, is_doc = i, doc_at[i]
            length += 1
            continue
        if length > (DOC_COMMENT_MAX if is_doc else COMMENT_BLOCK_MAX):
            out.append((start, length, is_doc))
        length = 0
    return out


def trailing_comments(path: Path) -> list[tuple[int, str]]:
    """(line, text) for every comment sharing a line with code.

    A trailing comment is the same defect as an indented one wearing a different hat: it annotates a
    statement instead of naming it.
    """
    if path.suffix not in {".gd", ".py"}:
        return []
    return [(i, c.lstrip("#").strip()) for i, code, c in real_comments(path) if code.strip()]


def is_quoted_answer(text: str) -> bool:
    """A blockquote, which the duplicate check must never flag.

    ⚠ REPEATING AN OWNER'S VERBATIM WORDS AT EVERY SITE THAT RELIES ON THEM IS REQUIRED. Paraphrase
    is the defect the provenance tooling exists to catch, so the duplicate rule inverts here.
    """
    return text.lstrip().startswith(">")


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
        for start, length, is_doc in comment_blocks(path):
            style_hit("long doc" if is_doc else "long block",
                      f"{rel(path)}:{start} ({length} lines)")

        for i, text in indented_comments(path):
            style_hit("indented", f"{rel(path)}:{i}: {text[:70]}")
        for i, text in trailing_comments(path):
            style_hit("trailing", f"{rel(path)}:{i}: {text[:70]}")

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
                if is_clipped_ref(base, text, fm.start(1)) or Path(base).stem.endswith("-"):
                    continue
                if base not in names:
                    err(f"{rel(path)}:{i}: references '{ref}', which does not exist — a comment "
                        f"deferring to a doc is only useful if the doc resolves")

            if is_quoted_answer(text):
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
        "indented": "a comment sits at column 0 above the method — indented prose wants a NAME",
        "trailing": "no comment shares a line with code — name the step instead",
        "history": "keep the rule and the number, drop the story",
        "long block": f"over {COMMENT_BLOCK_MAX} lines — say WHY the method exists, nothing else",
        "long doc": f"over {DOC_COMMENT_MAX} line — a knob's Inspector label is one line",
        "line ref": "a line number is a dead reference waiting to happen; name the symbol",
        "restated": "state it once, point at that name from the other site",
        "design id": "names a doc the code's reader cannot see; state the rule the answer produced",
        "design id in a string": "on screen in front of a reader who cannot look it up — a "
                                 "layering breach, not a style nit",
    }
    for kind in ("design id in a string", "design id", "restated", "line ref", "history",
                 "long block", "long doc", "dated", "indented", "trailing"):
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
    """Entry point. Reconfigures stdout first: findings quote lines full of non-cp1252 characters,
    and without it the checker dies on the first one it tries to report."""
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
