#!/usr/bin/env python3
"""Resolve the conflict hunks where only ONE side changed code, and leave the rest alone.

Two long-running branches over one file usually disagree about two different things at once: a
comment sweep and a real edit. Git cannot tell them apart, so it reports both as one conflict.
This does tell them apart, using the merge base that `zdiff3` writes into the file:

    one side's code == base's code  ->  take the OTHER side whole; its code has to survive
    both sides' code == base        ->  take the SECOND branch's, so its sweep lands
    both changed code               ->  left conflicted, for hands

⚠ In every hunk it resolves, the losing side's COMMENT edits in that hunk are discarded. That is
the trade: a comment can be rewritten, a dropped code line cannot be noticed.

    py .claude/tools/merge_split.py            # report
    py .claude/tools/merge_split.py --apply    # rewrite the resolvable hunks

Exit 0 = every hunk resolved, 1 = some need hands.

⚠ The merge must be made with `zdiff3`, or there is no base to compare against:
    git -c merge.conflictStyle=zdiff3 merge --no-ff -X diff-algorithm=histogram <branch>
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# Extensions whose comment marker is known. Guessing one wrong reads a code line as a comment and
# drops it silently, so anything else goes to hands. Mirrors dup_check.EXT plus the C-family.
MARKER = {".gd": "#", ".py": "#", ".ps1": "#",
          ".gdshader": "//", ".gdshaderinc": "//", ".js": "//", ".mjs": "//",
          ".h": "//", ".cpp": "//", ".cs": "//"}

OURS, THEIRS, HAND = "ours", "theirs", "hand"


def code_of(lines: list[str], marker: str) -> list[str]:
    """The lines carrying logic, INDENTATION KEPT -- in GDScript it is the block structure, so a
    line that moved in or out of a block is a code change like any other (dup_check.normalize).
    A trailing comment goes with its line, which is the shape this repo's comment sweeps produce.
    """
    out = []
    for line in lines:
        text = line.rstrip()
        if not text.lstrip() or text.lstrip().startswith(marker):
            continue
        if '"' not in text and "'" not in text and marker in text:
            text = text.split(marker, 1)[0].rstrip()
            if not text.strip():
                continue
        out.append(text)
    return out


def conflicted_files() -> list[str]:
    done = subprocess.run(["git", "diff", "--name-only", "--diff-filter=U"],
                          capture_output=True, text=True, check=True)
    return [p for p in done.stdout.split("\n") if p.strip()]


def split_file(path: Path, marker: str) -> tuple[list[str], list[str]]:
    """(output lines, one verdict per hunk). Raises ValueError without a zdiff3 base."""
    lines = path.open(encoding="utf-8", newline="").readlines()
    out: list[str] = []
    verdicts: list[str] = []
    i = 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< "):
            out.append(lines[i])
            i += 1
            continue
        head = lines[i]
        i += 1
        ours = []
        while not lines[i].startswith(("||||||| ", "=======")):
            ours.append(lines[i])
            i += 1
        if not lines[i].startswith("||||||| "):
            raise ValueError("no zdiff3 base - re-merge with "
                             "`git -c merge.conflictStyle=zdiff3 merge ...`")
        mid = lines[i]
        i += 1
        base = []
        while not lines[i].startswith("======="):
            base.append(lines[i])
            i += 1
        sep = lines[i]
        i += 1
        theirs = []
        while not lines[i].startswith(">>>>>>> "):
            theirs.append(lines[i])
            i += 1
        tail = lines[i]
        i += 1

        ours_code = code_of(ours, marker)
        base_code = code_of(base, marker)
        theirs_code = code_of(theirs, marker)
        if theirs_code == base_code and ours_code != base_code:
            out += ours
            verdicts.append(OURS)
        elif ours_code == base_code:
            out += theirs
            verdicts.append(THEIRS)
        else:
            out += [head] + ours + [mid] + base + [sep] + theirs + [tail]
            verdicts.append(HAND)
    return out, verdicts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="rewrite the hunks where one side had no code to lose")
    args = ap.parse_args()

    root = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True, check=True).stdout.strip())
    rows: list[tuple[int, str, str]] = []
    total = hands = 0
    for rel in conflicted_files():
        marker = MARKER.get(Path(rel).suffix)
        if marker is None:
            rows.append((-1, rel, "HAND - no comment marker known for this extension"))
            continue
        try:
            out, verdicts = split_file(root / rel, marker)
        except ValueError as exc:
            rows.append((-1, rel, "HAND - %s" % exc))
            continue
        if not verdicts:
            rows.append((-1, rel, "HAND - conflicted with no markers (modify/delete?)"))
            continue
        hand = verdicts.count(HAND)
        total += len(verdicts)
        hands += hand
        if args.apply and hand < len(verdicts):
            (root / rel).open("w", encoding="utf-8", newline="").writelines(out)
        rows.append((hand, rel, "%d hunks: %d split, %d for hands"
                     % (len(verdicts), len(verdicts) - hand, hand)))

    for _, rel, note in sorted(rows, key=lambda r: (-r[0], r[1])):
        print("%-48s %s" % (rel, note))
    print("---")
    print("%d hunks: %d %s, %d need hands"
          % (total, total - hands, "split" if args.apply else "splittable", hands))
    if not args.apply:
        print("(report only - pass --apply to rewrite)")
    return 1 if hands or any(r[0] == -1 for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
