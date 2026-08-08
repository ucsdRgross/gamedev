"""Run the Solatro suite and gate the EXIT-TIME engine errors the suite cannot see itself.

    py solatro/Tools/run_tests.py                       # GODOT_BIN from the environment
    py solatro/Tools/run_tests.py --godot <path to the _console exe>
    py solatro/Tools/run_tests.py --scene res://Tools/spotlight_tool.tscn -- --verify

Exit code = the suite's own failure count PLUS the exit-time errors found here (capped at 125, the
same cap `all_tests.gd` uses). 0 means both gates are clean.

WHY THIS EXISTS. `all_tests.gd::_scan_engine_errors` fails the run on unexpected engine errors, but
it runs INSIDE `_ready`, before `get_tree().quit()`. Everything the engine prints while tearing
itself down therefore lands after the gate has already reported, and no in-engine check can ever
catch it — by the time those lines exist, every GDScript object is gone. That blind spot was known
(HANDOFF_spotlight "Open bugs"); this is the outer wrapper it asked for.

⚠ **THE EXIT-TIME LINES ARE NOT IN `godot.log`.** The obvious wrapper — re-read `user://logs/godot.log`
after the process exits — is exactly as blind as the in-engine scan, because the engine CLOSES its
log file during the same cleanup that emits these errors. Measured 2026-08-07: a clean-looking run's
`godot.log` ends at the `full logs:` line, while the process streams carried three more lines after it:

    ERROR: 1 RID allocations of type 'N5GLES37TextureE' were leaked at exit.
    WARNING: 14 ObjectDB instances were leaked at exit (run with `--verbose` for details).
    ERROR: 2 resources still in use at exit (run with --verbose for details).

⚠ **THE DISCRIMINATOR IS `godot.log` MEMBERSHIP, NOT POSITION IN THE STREAM.** The first build of
this script scanned for lines appearing after the suite's banner, and that was wrong twice over:
the exit-time errors are split across BOTH stdout and stderr (the `RID allocations` line went to
stdout, `Texture with GL ID` to stderr), and `TestLog.line(..., true)` routes the banner to stderr
only when the run FAILS — so on a green run there is no banner in stderr to anchor to at all.
Both bugs are the same shape: inferring "the gate could not see this" from where a line sits.

So the rule here is definitional instead. `_scan_engine_errors` reads `godot.log` and nothing else,
therefore **an error line in the process streams that is absent from `godot.log` is exactly one the
gate could not have seen.** That is order-independent, survives the stdout/stderr split, and stays
true if the engine's teardown order ever changes. Errors DURING the run are in `godot.log`, were
already gated in-engine, and are not re-counted here.

⚠ **THE ALLOWLIST IS PARSED OUT OF `Tests/all_tests.gd`, NEVER RESTATED.** Two copies of one
allowlist is the seam that produced most of this repo's defects (`.claude/memory/seam-checks-not-
rereading.md`): the copies drift, and the drift shows up as a suite that is green in one gate and red
in the other. If the parse fails, this script FAILS LOUDLY rather than falling back to a built-in
list — a wrong allowlist is worse than no run.

⚠ It gates the engine's stream, not the tests. A green run here still means only "no unexpected
engine error"; the suite's own PASS/FAIL verdict is `all_tests.gd`'s.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
ALL_TESTS_GD = os.path.join(PROJECT, "Tests", "all_tests.gd")
# The engine's own log, and the ONLY thing _scan_engine_errors reads — so it is also the definition
# of what that gate can see. Same root as snapshot_diff.py's.
GODOT_LOG = os.path.join(os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Solatro"),
                         "logs", "godot.log")

# The suite's grand-total line, reported for context only. ⚠ It is NOT the discriminator: it lands on
# stderr when the run fails and stdout when it passes, which is what broke the first build.
BANNER = re.compile(r"={4,}\s*ALL \d+ SUITES:")


def read_allowlist(path):
    """The ENGINE_ERROR_ALLOW fragments from all_tests.gd. Raises if the block cannot be parsed."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    block = re.search(r"const ENGINE_ERROR_ALLOW\s*:\s*Array\[String\]\s*=\s*\[(.*?)\]", text, re.S)
    if not block:
        raise RuntimeError(
            "could not find `const ENGINE_ERROR_ALLOW : Array[String] = [...]` in %s — the gate's "
            "allowlist moved or was renamed. Fix this parse rather than pasting a copy here." % path
        )
    # GDScript string literals, with the escaped quotes the allowlist actually contains
    # (e.g. "Condition \"p_index").
    fragments = [
        raw.encode().decode("unicode_escape")
        for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', block.group(1))
    ]
    if not fragments:
        raise RuntimeError("parsed ENGINE_ERROR_ALLOW in %s but it held no strings" % path)
    return fragments


def error_lines(text):
    """Every engine ERROR / SCRIPT ERROR line in a stream, stripped, in order."""
    out = []
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("ERROR:") or line.startswith("SCRIPT ERROR:"):
            out.append(line)
    return out


def scan_unseen(stream_text, log_text, allowlist):
    """(errors, warnings): error lines the in-engine gate could not have seen.

    An error is "unseen" when it is in the process streams but not in godot.log, which is the only
    thing _scan_engine_errors reads. Counted per-line rather than as a set difference: the same
    error can appear once during the run (gated) and again at exit (not), and a set difference would
    silently drop the second one.
    """
    logged = {}
    for line in error_lines(log_text):
        logged[line] = logged.get(line, 0) + 1
    errors = []
    for line in error_lines(stream_text):
        if logged.get(line, 0) > 0:
            logged[line] -= 1          # accounted for by the in-engine gate
            continue
        if not any(frag in line for frag in allowlist):
            errors.append(line)
    warnings = [raw.strip() for raw in stream_text.splitlines()
                if raw.strip().startswith("WARNING:") and "leaked at exit" in raw]
    # Reported, never counted: LEAK CANARY abandons objects on purpose, so this fires on a healthy
    # run. It is still the first thing anyone chasing the leak wants to see.
    return errors, warnings


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"),
                        help="path to the Godot _console executable (default: $GODOT_BIN)")
    parser.add_argument("--scene", default="res://Tests/all_tests.tscn")
    parser.add_argument("--timeout", type=int, default=600,
                        help="seconds before the run is KILLED (default 600)")
    parser.add_argument("passthrough", nargs="*",
                        help="args for the scene itself, after a bare --")
    args = parser.parse_args()

    if not args.godot:
        parser.error("no Godot binary: pass --godot or set GODOT_BIN. The per-machine path lives in "
                     ".claude/memory/machine-profiles.md and belongs in neither this file nor a doc.")

    allowlist = read_allowlist(ALL_TESTS_GD)

    # ⚠ WINDOWED, never --headless: the PIXELS suite renders through a real renderer and a dummy one
    # cannot compile a shader. See .claude/memory/running-godot-scenes.md.
    command = [args.godot, "--path", PROJECT, args.scene]
    if args.passthrough:
        command += ["--"] + args.passthrough

    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as out, \
         tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as err:
        process = subprocess.Popen(command, stdout=out, stderr=err)
        timed_out = False
        try:
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            # ⚠ ALWAYS kill on timeout — a parse error leaves a blank window open forever and no
            # in-scene watchdog can save it, because the script never loads.
            process.kill()
            process.wait()
            timed_out = True
        err.seek(0)
        stderr_text = err.read()
        out.seek(0)
        stdout_text = out.read()

    suite_failures = process.returncode if process.returncode and process.returncode > 0 else 0

    # ⚠ BOTH streams, because the engine splits its teardown errors across them.
    streams = stdout_text + "\n" + stderr_text
    try:
        with open(GODOT_LOG, encoding="utf-8", errors="replace") as handle:
            log_text = handle.read()
    except OSError as problem:
        # A missing log means the in-engine gate saw NOTHING, so everything in the streams is unseen.
        # Say so — silently treating it as "clean" is the failure mode this whole file exists to end.
        print("[exit-time] WARNING: could not read %s (%s). The in-engine gate's coverage is unknown, "
              "so every error below is reported." % (GODOT_LOG, problem))
        log_text = ""

    errors, warnings = scan_unseen(streams, log_text, allowlist)

    banner_line = next((line for line in streams.splitlines() if BANNER.search(line)), None)
    saw_banner = banner_line is not None
    print(banner_line.strip() if saw_banner else
          "======== NO SUITE BANNER — the run did not reach its own verdict ========")

    for line in warnings:
        print("[exit-time] note: %s" % line)

    if timed_out:
        print("[exit-time] TIMEOUT — killed after %ds. Nothing below is a complete picture."
              % args.timeout)

    if errors:
        print("======== %d ENGINE ERRORS THE IN-RUN GATE COULD NOT SEE ========" % len(errors))
        seen = {}
        for line in errors:
            seen[line] = seen.get(line, 0) + 1
        for line in dict.fromkeys(errors):
            print("  x%-5d %s" % (seen[line], line))
        print("Each line is in the process streams but NOT in godot.log, which is the only thing "
              "`all_tests.gd::_scan_engine_errors` reads — so the in-run gate could not have seen "
              "them however it was written. Only this wrapper can.")
    else:
        print("[exit-time] clean — every engine error this run was already visible to the in-run gate")

    total = suite_failures + len(errors) + (1 if timed_out or not saw_banner else 0)
    return min(total, 125)


if __name__ == "__main__":
    sys.exit(main())
