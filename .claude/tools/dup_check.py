#!/usr/bin/env python3
"""Duplicate-block detector for this repo's code.

The seam this catches: the same logic written twice because nobody grepped first. It is
the single most-measured regression in assisted codebases -- duplicated blocks rose ~8x
and within-commit copy/paste overtook refactored code -- and no other check here sees it.
A green suite never fails on a duplicate; doc_check stays silent because every NAME in it
resolves.

    py .claude/tools/dup_check.py                     # whole repo
    py .claude/tools/dup_check.py --changed           # only pairs touching a changed file
    py .claude/tools/dup_check.py --staged            # same, scoped to what is staged

Exit 0 = clean, 1 = at least one finding. --warn-only always exits 0.

Comments and blank lines are stripped before hashing, so a copy someone reworded still
matches. Indentation is kept: in GDScript it is the block structure.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

EXT = {".gd", ".py", ".gdshader", ".gdshaderinc", ".mjs", ".js", ".ps1"}
# Vendored, generated, or not ours to shape.
SKIP_PARTS = {".git", "node_modules", "godot-cpp", "addons", ".godot", ".import", "Assets",
              "godot_state_charts_examples"}

# A bucket this crowded is boilerplate (a getter shape, a test preamble), not one copy
# someone made. Reporting every pair of it buries the real finding.
CROWD = 12


def git(*args: str) -> str | None:
    try:
        out = subprocess.run(["git", "-C", str(ROOT), *args],
                             capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 else None


def source_files() -> list[Path]:
    files = []
    for p in ROOT.rglob("*"):
        if p.suffix not in EXT or not p.is_file():
            continue
        if set(p.relative_to(ROOT).parts) & SKIP_PARTS:
            continue
        files.append(p)
    return sorted(files)


def normalize(path: Path) -> list[tuple[int, str]]:
    """(original line number, normalized text) for lines that carry logic.

    Comments and blanks go; a trailing comment on a real line goes with it. Indentation
    stays -- in GDScript it IS the block structure, so two blocks at different nesting
    depths are not the same code.
    """
    try:
        raw = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    out = []
    for i, line in enumerate(raw, 1):
        text = line.rstrip()
        stripped = text.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        # Only strip a trailing # when no quote could be hiding one inside a string.
        if '"' not in text and "'" not in text and "#" in text:
            text = text.split("#", 1)[0].rstrip()
            if not text.strip():
                continue
        out.append((i, text))
    return out


def find_dups(lines: dict[Path, list[tuple[int, str]]], window: int):
    buckets: dict[int, list[tuple[Path, int]]] = defaultdict(list)
    for p, rows in lines.items():
        for i in range(len(rows) - window + 1):
            chunk = tuple(t for _, t in rows[i:i + window])
            # A window that is mostly one repeated line is a data table or a field list,
            # not logic someone copied.
            if len(set(chunk)) < window - 2:
                continue
            buckets[hash(chunk)].append((p, i))

    findings = []
    claimed: set[tuple[Path, int]] = set()
    for bucket in buckets.values():
        if len(bucket) < 2:
            continue
        if len(bucket) > CROWD:
            findings.append((window, bucket[0], bucket[1], len(bucket)))
            continue
        for x in range(len(bucket)):
            for y in range(x + 1, len(bucket)):
                a, b = bucket[x], bucket[y]
                if a[0] == b[0] and abs(a[1] - b[1]) < window:
                    continue  # overlapping windows in one file are the same text
                if a in claimed or b in claimed:
                    continue
                # Extend forward while the two blocks keep agreeing, so one 40-line copy
                # reports once instead of 33 overlapping times.
                ra, rb = lines[a[0]], lines[b[0]]
                n = window
                while (a[1] + n < len(ra) and b[1] + n < len(rb)
                       and ra[a[1] + n][1] == rb[b[1] + n][1]):
                    n += 1
                for k in range(n - window + 1):
                    claimed.add((a[0], a[1] + k))
                    claimed.add((b[0], b[1] + k))
                findings.append((n, a, b, 2))

    findings.sort(reverse=True, key=lambda f: f[0])
    return findings


def project(path: Path) -> str:
    """Top-level directory — this is a monorepo of separate games, not one system.

    A shader copied from one jam project into another is a fact about how they started,
    not a maintenance seam: nothing will ever edit the two together. Only a duplicate
    INSIDE one project has a next edit that will reach one home and miss the other.
    """
    return path.relative_to(ROOT).parts[0]


def scoped_paths(staged: bool) -> set[str] | None:
    """Paths git reports, or None if it cannot answer.

    None and set() differ and must not be merged: None is "scope unknown, check
    everything and say so", set() is "nothing changed".
    """
    if staged:
        out = git("diff", "--cached", "--name-only")
        return None if out is None else set(out.splitlines())
    out = git("status", "--porcelain")
    if out is None:
        return None
    names = set()
    for line in out.splitlines():
        if len(line) < 4:
            continue
        name = line[3:].strip().strip('"')
        if " -> " in name:
            name = name.split(" -> ", 1)[1]
        names.add(name)
    return names


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--changed", action="store_true",
                    help="only report a pair where at least one side is a file you changed")
    ap.add_argument("--staged", action="store_true",
                    help="same, scoped to staged files -- for a gate that runs before a commit")
    ap.add_argument("--min-lines", type=int, default=8,
                    help="shortest block worth reporting, in logic lines (default 8)")
    ap.add_argument("--cross-project", action="store_true",
                    help="also report a block shared between two top-level projects")
    ap.add_argument("--warn-only", action="store_true", help="always exit 0")
    args = ap.parse_args()

    scope = None
    if args.changed or args.staged:
        scope = scoped_paths(args.staged)
        if scope is None:
            print("[dup-check] git could not list changed files -- run the full check by hand")
            return 0 if args.warn_only else 1
        if not scope:
            return 0

    files = source_files()
    lines = {p: normalize(p) for p in files}
    findings = find_dups(lines, args.min_lines)

    if not args.cross_project:
        findings = [f for f in findings if project(f[1][0]) == project(f[2][0])]

    if scope is not None:
        findings = [f for f in findings
                    if f[1][0].relative_to(ROOT).as_posix() in scope
                    or f[2][0].relative_to(ROOT).as_posix() in scope]

    for n, a, b, copies in findings:
        la = lines[a[0]][a[1]][0]
        lb = lines[b[0]][b[1]][0]
        extra = f" and {copies - 2} more place(s)" if copies > 2 else ""
        print(f"FINDING {n} identical logic lines: "
              f"{a[0].relative_to(ROOT).as_posix()}:{la} and "
              f"{b[0].relative_to(ROOT).as_posix()}:{lb}{extra}")

    if findings:
        where = "the files you changed" if scope is not None else f"{len(files)} source files"
        print(f"\n[dup-check] {len(findings)} duplicated block(s) involving {where}. "
              f"Each is one behaviour with two homes -- the next edit will reach only one.")
    return 0 if args.warn_only or not findings else 1


if __name__ == "__main__":
    sys.exit(main())
