"""The visual review's shooter: every manifest shot, AFTER on the working tree and BEFORE on the code
the work started from, each PNG copied byte for byte so the owner sees exactly what the worker saw.

    py solatro/visual-review/review.py shoot                  working tree -> after/
    py solatro/visual-review/review.py shoot --base [<ref>]   <ref> in a temporary worktree -> before/
    py solatro/visual-review/review.py refresh                both; the base is `git merge-base main HEAD`

Standard library only: the repo's `py` is 3.9 with nothing installed.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
REPO = PROJECT.parent
USER_DATA = ("Godot", "app_userdata", "Solatro")
RUN_TIMEOUT_S = 300
IMPORT_TIMEOUT_S = 900


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], check=True, capture_output=True,
                          text=True).stdout.strip()


def default_base():
    return git("merge-base", "main", "HEAD")


# The `_console` exe is a wrapper around the game process, so killing its PID on a timeout would
# orphan the game window. The GUI exe beside it is the process that has to die.
def godot_binary():
    path = os.environ.get("GODOT_BIN")
    if not path:
        sys.exit("set GODOT_BIN - the per-machine path is in .claude/memory/machine-profiles.md")
    return path.replace("_console.exe", ".exe")


def run_godot(project, args, env, timeout):
    """One windowed Godot run on a fresh private APPDATA; returns (exit code or None, that APPDATA)."""
    appdata = Path(tempfile.mkdtemp(prefix="visual-review-appdata-"))
    process = subprocess.Popen([godot_binary(), "--path", str(project), *args],
                               env={**os.environ, **env, "APPDATA": str(appdata)},
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        return process.wait(timeout=timeout), appdata
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        return None, appdata


def log_tail(appdata, lines=15):
    log = appdata.joinpath(*USER_DATA, "logs", "godot.log")
    if not log.is_file():
        return "(no godot.log)"
    return "\n".join(log.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])


def manifest():
    return json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))


def runs_of(shots):
    """Shots grouped by (scene, env): one Godot run writes every PNG its group needs."""
    runs = {}
    for shot in shots:
        assert shot["scene"].startswith("res://") and shot["png"].startswith("user://"), shot["id"]
        runs.setdefault((shot["scene"], tuple(sorted(shot["env"].items()))), []).append(shot)
    return runs


def shoot(project, side):
    """Every shot on `project` into `<side>/<id>.png`; returns the ids that produced no image."""
    out = HERE / side
    if out.exists():
        shutil.rmtree(out)
    out.mkdir()
    missing = []
    for (scene, env), shots in runs_of(manifest()["shots"]).items():
        ids = [shot["id"] for shot in shots]
        if not (project / scene[len("res://"):]).is_file():
            print(f"{side}: {scene} does not exist on this tree - no {side} for {', '.join(ids)}")
            missing += ids
            continue
        print(f"{side}: {scene} {dict(env)} ...", flush=True)
        code, appdata = run_godot(project, [scene], dict(env), RUN_TIMEOUT_S)
        for shot in shots:
            png = appdata.joinpath(*USER_DATA, shot["png"][len("user://"):])
            if code == 0 and png.is_file():
                shutil.copyfile(png, out / f"{shot['id']}.png")
                print(f"  {shot['id']}: {side}/{shot['id']}.png")
            else:
                missing.append(shot["id"])
                print(f"  {shot['id']}: NO {side.upper()} ({shot['png']} not written)")
        if code != 0:
            print(f"  exit {'TIMEOUT - killed' if code is None else code}; godot.log ends:\n{log_tail(appdata)}")
        shutil.rmtree(appdata)
    return missing


def shoot_base(ref):
    """The same shots on `ref`, in a temporary worktree that is removed afterwards."""
    holder = Path(tempfile.mkdtemp(prefix="visual-review-base-"))
    tree = holder / "tree"
    git("worktree", "add", "--detach", str(tree), ref)
    try:
        project = tree / PROJECT.relative_to(REPO)
        print(f"before: importing {ref[:10]} (a fresh worktree has no .godot cache) ...", flush=True)
        code, appdata = run_godot(project, ["--headless", "--import"], {}, IMPORT_TIMEOUT_S)
        shutil.rmtree(appdata)
        print(f"  import exit {'TIMEOUT - killed' if code is None else code}")
        return shoot(project, "before")
    finally:
        git("worktree", "remove", "--force", str(tree))
        shutil.rmtree(holder)


# `run watch -- visual-review/<project>` ignores an owner Done older than this, so a worker parked
# after a refresh waits for the owner's verdict on THESE images, not the last round's.
def mark_ready():
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = json.dumps({"state": "ready", "mode": "visual-review", "at": at}, indent=2) + "\n"
    (HERE / "status.agent.json").write_bytes(body.encode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    shoot_cmd = sub.add_parser("shoot", help="after/ from the working tree, or before/ with --base")
    shoot_cmd.add_argument("--base", nargs="?", const="", default=None, metavar="REF",
                           help="shoot <ref> into before/ instead (default: git merge-base main HEAD)")
    sub.add_parser("refresh", help="before/ from the merge base, then after/ from the working tree")
    args = parser.parse_args()

    failed = []
    if args.command == "refresh":
        shoot_base(default_base())
        failed = shoot(PROJECT, "after")
    elif args.base is not None:
        shoot_base(args.base or default_base())
    else:
        failed = shoot(PROJECT, "after")
    mark_ready()
    if failed:
        sys.exit(f"no AFTER for {', '.join(failed)} - the working tree must produce every shot")


if __name__ == "__main__":
    main()
