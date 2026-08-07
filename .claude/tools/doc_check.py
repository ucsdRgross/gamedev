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
    r"\b(deleted|removed|retired|superseded|absorbed|no longer exists|used to)\b", re.I)

DATE = re.compile(r"20\d\d-\d\d-\d\d")
WIKILINK = re.compile(r"\[\[([a-z0-9-]+)\]\]")
INDEX_ENTRY = re.compile(r"\]\(([a-z0-9-]+)\.md\)")
# A path-ish token with a real extension. Bare words and res:// are not our problem.
FILEREF = re.compile(r"(?<![\w/])((?:[\w.-]+/)*[\w.-]+\.(?:md|py|gd|gdshader|tscn|tres|json|csv|ps1|cmd|mjs|js))(?![\w])")
ABSPATH = re.compile(r"[A-Za-z]:\\[^\s`\"'|)]+")

PROJECTS = ["solatro", "worldgen", "palette", "designloop"]

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


def check_file_refs(docs: list[Path]) -> None:
    # Build one index of every filename in the repo, so a reference resolves by basename
    # even when the doc writes a partial path.
    names: set[str] = set()
    for p in ROOT.rglob("*"):
        if p.is_file() and not (INDEX_SKIP & set(p.relative_to(ROOT).parts)):
            names.add(p.name)

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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verbose", action="store_true", help="list every dated line")
    args = ap.parse_args()

    docs = living_docs()
    check_memory_links_and_index()
    check_memory_scope()
    check_file_refs(docs)
    check_dates(docs, args.verbose)
    check_abs_paths(docs)

    for w in warns:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")

    print(f"\n{len(docs)} living docs checked - {len(errors)} error(s), {len(warns)} warning(s)")
    if errors:
        print("Errors are broken references or a memory index out of sync. Fix them.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
