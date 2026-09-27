#!/usr/bin/env python3
"""The overseer's windowed gate for solatro, run and read in one call.

Each gate used to be the same long launch line plus three or four greps over the banner,
the errors log, the exit profile and godot.log, with the per-suite comparison against the
last gate done by eye and the intermittent list checked from memory. This does all of it and
prints a short verdict, so a gate costs one tool call and a dozen lines of reading.

    py .claude/tools/gate.py --out <scratchpad> [--handoff solatro/HANDOFF_x.md] [-- --filter Sidebar]
    py .claude/tools/gate.py --out <scratchpad> --parse <scratchpad>/gate_<stamp>   # re-read a run

Every run gets a fresh private APPDATA under --out, so user:// is never the player's. It
refuses to start while any Godot process runs (one Godot at a time; overlapping runs
fabricate failures). GODOT_BIN comes from the environment, else from the machine-profiles
table for whichever repo root this checkout is.

Exit 0 = GREEN: the suite banner passed, the errors log is empty, no SCRIPT ERROR, no RID /
GL texture / PagedAllocator line, and ObjectDB not above the last full gate's. Anything else
exits 1 with the reasons. The wrapper's own exit code is printed, not judged: a green run
exits 1 there because of the standing "resources still in use" line.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "solatro" / "Tools" / "run_tests.py"
PROFILES = ROOT / ".claude" / "memory" / "machine-profiles.md"
LOGS_UNDER_APPDATA = Path("Godot") / "app_userdata" / "Solatro" / "logs"

BANNER = re.compile(r"^=+ ((?:ALL|FILTERED) .*SUITES.*?) =+$")
SUITE_END = re.compile(r"^=+ (?!ALL \d|FILTERED )([A-Z][A-Z0-9 ]*?): (?:ALL (\d+) CHECKS PASSED|(\d+) passed, (\d+) FAILED)")
LEAK = re.compile(r"\bRID\b|GL texture|PagedAllocator")
OBJECTDB = re.compile(r"(\d+) ObjectDB instances were leaked")
RESOURCES = re.compile(r"(\d+) resources still in use")
PLACEHOLDERS = re.compile(r"\[(\d+) placeholder warnings\]")
FAIL_LINE = re.compile(r"^\[FAIL\]\[\w+\] ([A-Z][A-Z0-9 ]*?): (.*)$")
TEST_ID = re.compile(r"\bTP-\d+\b")
RES_PATH = re.compile(r"res://[^\s)]+")
# Randomised by design, so its count is expected to move between identical runs.
MOVES_BY_DESIGN = {"BOARD FUZZ"}


def godot_bin() -> str:
    if os.environ.get("GODOT_BIN"):
        return os.environ["GODOT_BIN"]
    rows = {}
    for line in PROFILES.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] in ("Repo root", "Godot binary"):
            rows[cells[0]] = [re.sub(r"[`*]", "", c).strip() for c in cells[1:]]
    here = os.path.normcase(os.path.normpath(str(ROOT)))
    for i, root in enumerate(rows["Repo root"]):
        if os.path.normcase(os.path.normpath(root)) == here:
            return rows["Godot binary"][i]
    sys.exit("gate: this repo root is in no machine-profiles column - add one, or set GODOT_BIN")


def godot_running() -> list[str]:
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Godot*", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if "Godot" in line]


def run(run_dir: Path, passthrough: list[str]) -> int:
    busy = godot_running()
    if busy:
        sys.exit("gate: a Godot process is running - one Godot at a time:\n  " + "\n  ".join(busy))
    appdata = run_dir / "appdata"
    appdata.mkdir(parents=True)
    args = passthrough if any(a.startswith("--timeout") for a in passthrough) \
        else ["--timeout", "1300", "--stall-timeout", "900"] + passthrough
    env = dict(os.environ, APPDATA=str(appdata), GODOT_BIN=godot_bin())
    with open(run_dir / "wrapper.log", "w", encoding="utf-8", errors="replace") as log:
        return subprocess.run([sys.executable, str(WRAPPER)] + args, cwd=ROOT, env=env,
                              stdout=log, stderr=subprocess.STDOUT).returncode


def grab_focus_sources(godot_log: Path) -> Counter:
    lines = godot_log.read_text(encoding="utf-8", errors="replace").splitlines() if godot_log.exists() else []
    found = Counter()
    for i, line in enumerate(lines):
        if "can't grab focus" in line:
            where = next((m.group(0) for l in lines[i + 1:i + 5] for m in [RES_PATH.search(l)] if m), "?")
            found[where] += 1
    return found


def open_bugs(handoff: Path) -> list[tuple[int, str]]:
    lines = handoff.read_text(encoding="utf-8").splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("## Open bugs"))
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return [(i + 1, lines[i]) for i in range(start, end)]


def listed_in(bugs: list[tuple[int, str]], suite: str, check: str) -> int | None:
    keys = TEST_ID.findall(check) or [check.split(" -- ")[0][:40]]
    for number, text in bugs:
        low = text.lower()
        if suite.lower() in low and any(k.lower() in low for k in keys):
            return number
    return None


def read(run_dir: Path) -> dict:
    wrapper = (run_dir / "wrapper.log").read_text(encoding="utf-8", errors="replace")
    logs = run_dir / "appdata" / LOGS_UNDER_APPDATA
    errors = logs / "test" / "test_output_errors.log"
    all_log = (logs / "test" / "test_output_all.log").read_text(encoding="utf-8", errors="replace")
    banners = [m.group(1) for m in map(BANNER.match, wrapper.splitlines()) if m]
    suites = {}
    for m in map(SUITE_END.match, all_log.splitlines()):
        if m:
            suites[m.group(1)] = int(m.group(2) or 0) + int(m.group(3) or 0) + int(m.group(4) or 0)
    objectdb = OBJECTDB.search(wrapper)
    resources = RESOURCES.search(wrapper)
    placeholders = PLACEHOLDERS.search(banners[-1]) if banners else None
    return {
        "banner": banners[-1] if banners else None,
        "suites": suites,
        "fails": [m.groups() for m in map(FAIL_LINE.match, errors.read_text(encoding="utf-8", errors="replace").splitlines()) if m] if errors.exists() else [],
        "errors_bytes": errors.stat().st_size if errors.exists() else None,
        "script_errors": all_log.count("SCRIPT ERROR"),
        "leaks": [l.strip() for l in wrapper.splitlines() if LEAK.search(l)],
        "objectdb": int(objectdb.group(1)) if objectdb else None,
        "resources": int(resources.group(1)) if resources else None,
        "placeholders": int(placeholders.group(1)) if placeholders else None,
        "grab_focus": dict(grab_focus_sources(logs / "godot.log")),
        "preserved": sorted(str(p) for p in logs.parent.glob("logs-failed-*")),
    }


def report(result: dict, last: dict | None, bugs: list[tuple[int, str]] | None, wrapper_exit) -> bool:
    reasons = []
    banner = result["banner"]
    print(banner or "NO SUITE BANNER - a hang, a crash or a parse error; read wrapper.log")
    if not banner or "CHECKS PASSED" not in banner:
        reasons.append("the banner did not pass")
    if result["errors_bytes"]:
        reasons.append("errors log %d bytes" % result["errors_bytes"])
    if result["script_errors"]:
        reasons.append("%d SCRIPT ERROR" % result["script_errors"])
    if result["leaks"]:
        reasons.append("%d leak line(s)" % len(result["leaks"]))
    if last and result["objectdb"] and last.get("objectdb") and result["objectdb"] > last["objectdb"]:
        reasons.append("ObjectDB %d > last gate's %d" % (result["objectdb"], last["objectdb"]))
    print("exit profile: %s ObjectDB, %s resources, %s placeholder warnings, wrapper exit %s"
          % (result["objectdb"], result["resources"], result["placeholders"], wrapper_exit))
    for line in result["leaks"]:
        print("  LEAK: " + line)
    previous = (None, None)
    for suite, check in result["fails"]:
        where = listed_in(bugs, suite, check) if bugs else None
        if not where and check.startswith("...") and previous[0] == suite and previous[1]:
            where = previous[1]
        previous = (suite, where)
        tag = ("listed in Open bugs, handoff line %d - count it" % where) if where else "NEW - not on the Open bugs list"
        print("  FAIL %s: %s\n       -> %s" % (suite, check[:160], tag))
    if result["grab_focus"]:
        print("grab-focus warnings: " + ", ".join("%s x%d" % kv for kv in sorted(result["grab_focus"].items())))
    if last and last.get("suites"):
        moved = [(s, last["suites"].get(s), n) for s, n in sorted(result["suites"].items()) if last["suites"].get(s) != n]
        for suite, before, now in moved:
            note = " (randomised by design)" if suite in MOVES_BY_DESIGN else ""
            print("  suite %s: %s -> %s%s" % (suite, before, now, note))
        gone = sorted(set(last["suites"]) - set(result["suites"]))
        if gone and banner and banner.startswith("ALL"):
            reasons.append("suites missing since the last gate: " + ", ".join(gone))
    for path in result["preserved"]:
        print("preserved logs: " + path)
    print(("GREEN" if not reasons else "RED - " + "; ".join(reasons)))
    return not reasons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, type=Path, help="a scratch directory; runs and the last-gate state live here")
    parser.add_argument("--handoff", type=Path, help="match failures against this handoff's '## Open bugs'")
    parser.add_argument("--parse", type=Path, help="re-read a finished run directory instead of launching one")
    parser.add_argument("passthrough", nargs="*", help="after --: arguments for run_tests.py")
    args = parser.parse_args()
    state = args.out / "gate_last.json"
    last = json.loads(state.read_text(encoding="utf-8")) if state.exists() else None
    if args.parse:
        run_dir, wrapper_exit = args.parse, "(not run here)"
    else:
        run_dir = args.out / time.strftime("gate_%Y%m%d-%H%M%S")
        wrapper_exit = run(run_dir, args.passthrough)
        print("run directory: %s" % run_dir)
    result = read(run_dir)
    green = report(result, last, open_bugs(args.handoff) if args.handoff else None, wrapper_exit)
    if result["banner"] and result["banner"].startswith("ALL"):
        state.write_text(json.dumps({k: result[k] for k in ("banner", "suites", "objectdb", "resources", "grab_focus")}, indent=1), encoding="utf-8")
    return 0 if green else 1


if __name__ == "__main__":
    sys.exit(main())
