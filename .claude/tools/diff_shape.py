#!/usr/bin/env python3
"""Add/delete shape of a change — the detector for growth that never removes anything.

A change that only adds lines to an EXISTING file is the measured signature of assisted
editing: the new path gets bolted alongside the old one instead of replacing it. Across
public repos the refactored share of changed lines fell from 25% to under 10% while
copy/paste rose, and churn roughly doubled. This is the local instrument for that.

    py .claude/tools/diff_shape.py                 # working tree vs HEAD
    py .claude/tools/diff_shape.py --staged        # what a commit is about to record
    py .claude/tools/diff_shape.py --history 300   # baseline over past commits

Exit 0 = clean, 1 = at least one finding. --warn-only always exits 0.

A NEW file is legitimately add-only and is never flagged. Only code counts; docs and data
grow by nature.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

HEX = re.compile(r"[0-9a-f]{40}")

CODE_EXT = {".gd", ".py", ".ps1", ".gdshader", ".gdshaderinc", ".mjs", ".js"}
# Vendored or generated: not ours to shape.
SKIP_PARTS = {".git", "node_modules", "godot-cpp", "addons", ".godot", ".import"}


def git(*args: str) -> str | None:
    """Run git in the repo, or None if it cannot answer.

    ⚠ None is "no answer", never "no output" — a caller that treats them alike reports a
    broken git as a clean tree.
    """
    try:
        out = subprocess.run(["git", "-C", str(ROOT), *args],
                             capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 else None


def is_code(path: str) -> bool:
    parts = set(Path(path).parts)
    if parts & SKIP_PARTS:
        return False
    return Path(path).suffix in CODE_EXT


def parse_numstat(text: str) -> list[tuple[int, int, str]]:
    """(added, deleted, path) for every code file in a --numstat block.

    Binary files report '-' for both counts and carry no line shape; a rename reports
    'old => new' and only the new path is a thing that exists now.
    """
    rows = []
    for line in text.splitlines():
        bits = line.split("\t")
        if len(bits) != 3 or bits[0] == "-":
            continue
        add, dele, path = int(bits[0]), int(bits[1]), bits[2]
        if "=>" in path:
            # A rename reads `dir/{old => new}/file.gd`, or the two names bare. Either
            # way the surviving name is last.
            path = path.replace("{", "").replace("}", "")
            path = path.split(" => ")[-1].replace("//", "/")
        if is_code(path):
            rows.append((add, dele, path))
    return rows


def existing_files(rev: str) -> set[str] | None:
    """Paths that already existed at `rev` — everything else in the diff is a new file."""
    out = git("ls-tree", "-r", "--name-only", rev)
    return None if out is None else set(out.splitlines())


def report_change(rows, existed, min_added, ratio, label):
    findings = []
    for add, dele, path in rows:
        if existed is not None and path not in existed:
            continue  # new file: add-only by definition
        if add < min_added:
            continue
        if dele / add < ratio:
            findings.append((add, dele, path))
    findings.sort(reverse=True)
    for add, dele, path in findings:
        print(f"FINDING {path}: +{add} / -{dele} — grew by {add} lines and removed {dele}. "
              f"If this replaces existing behaviour, the code it replaces should be gone.")
    if findings:
        print(f"\n[diff-shape] {len(findings)} add-only change(s) to existing files in {label}.")
    return findings


def report_history(n, min_added, ratio):
    """The baseline: what this repo's changes actually look like, before any process."""
    out = git("log", "-M", f"-{n}", "--numstat", "--format=%H")
    if out is None:
        print("[diff-shape] git could not read the log")
        return 1
    commits, cur, sha = [], [], None
    for line in out.splitlines():
        # ⚠ Test the tab, not just the length: a numstat row is "add	del	path" and one of
        # exactly 40 characters looks like a SHA on length alone, splitting a commit in two.
        if "	" not in line and len(line) == 40 and HEX.fullmatch(line):
            if sha:
                commits.append((sha, cur))
            sha, cur = line, []
        elif line.strip():
            cur.extend(parse_numstat(line))
    if sha:
        commits.append((sha, cur))

    total_add = total_del = 0
    add_only = 0
    touched = Counter()
    scored = 0
    for sha, rows in commits:
        if not rows:
            continue
        scored += 1
        a = sum(r[0] for r in rows)
        d = sum(r[1] for r in rows)
        total_add += a
        total_del += d
        if a >= min_added and (d / a) < ratio:
            add_only += 1
        for _, _, p in rows:
            touched[p] += 1

    if not scored:
        print("[diff-shape] no commits touching code in that range")
        return 0
    churn = total_add + total_del
    print(f"[diff-shape] baseline over {scored} code-touching commit(s) of the last {n}")
    print(f"  added {total_add}, deleted {total_del}")
    print(f"  deletions are {100 * total_del / churn:.1f}% of changed lines")
    print(f"  add-only commits (>={min_added} added, <{ratio:.0%} deleted): "
          f"{add_only} of {scored} ({100 * add_only / scored:.0f}%)")
    print("\n  most-churned files:")
    for path, count in touched.most_common(10):
        print(f"    {count:4d}x  {path}")
    print("\n  Deletion share is the number to watch: it is what fell from 25% to under 10%\n"
          "  in public repos as assisted editing spread. Compare future runs against this.")
    return 0


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--staged", action="store_true",
                    help="only what is staged — for a gate that runs before a commit")
    ap.add_argument("--changed", action="store_true",
                    help="working tree vs HEAD (the default); accepted so the flag matches "
                         "doc_check.py in hook configuration")
    ap.add_argument("--history", type=int, metavar="N",
                    help="report the shape of the last N commits instead of checking a diff")
    ap.add_argument("--min-added", type=int, default=25,
                    help="ignore changes smaller than this many added lines (default 25)")
    ap.add_argument("--ratio", type=float, default=0.10,
                    help="flag when deleted/added is below this (default 0.10)")
    ap.add_argument("--warn-only", action="store_true", help="always exit 0")
    args = ap.parse_args()

    if args.history:
        return report_history(args.history, args.min_added, args.ratio)

    scope = ["diff", "-M", "--numstat", "--cached"] if args.staged else ["diff", "-M", "--numstat", "HEAD"]
    out = git(*scope)
    if out is None:
        print("[diff-shape] git could not produce a diff — check by hand")
        return 0 if args.warn_only else 1
    rows = parse_numstat(out)
    if not rows:
        return 0
    existed = existing_files("HEAD")
    findings = report_change(rows, existed, args.min_added, args.ratio,
                             "the staged diff" if args.staged else "your working tree")
    return 0 if args.warn_only or not findings else 1


if __name__ == "__main__":
    sys.exit(main())
