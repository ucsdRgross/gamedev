# Tells the session to run /handoff once, when context use first crosses the threshold, so the
# owner need not watch the meter. A Stop hook, because subagents share the session_id but fire
# SubagentStop instead; exits silent on anything missing.
import json
import os
import sys
import tempfile

# Owner's pick: one measured long session cost least closing at 200-250k (~$54, ~$62 at 500k, $79
# unclosed; the Opus 5 card compacts at 200k) - 500k trades that for fewer restarts.
CLOSE_AT_TOKENS = 500_000
TAIL_BYTES = 262_144


def last_usage(path):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - TAIL_BYTES))
        lines = f.read().splitlines()
    for line in reversed(lines):
        if b'"usage"' not in line or b'"assistant"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        usage = entry.get("message", {}).get("usage")
        if entry.get("type") == "assistant" and usage:
            return usage
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        session = payload["session_id"]
        usage = last_usage(payload["transcript_path"])
    except (ValueError, KeyError, OSError):
        return
    if payload.get("stop_hook_active"):
        return
    if not usage:
        return
    marker = os.path.join(tempfile.gettempdir(), f"claude-handoff-nudge-{session}")
    if os.path.exists(marker):
        return
    used = sum(usage.get(k, 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    if used < CLOSE_AT_TOKENS:
        return
    open(marker, "w").close()
    text = (f"Context at {used} tokens (the 500k close): run /handoff now - update the handoff, Reflect and record, "
            "commit, and end your message with a progress update and the copy-paste opening prompt for the next session.")
    print(json.dumps({"decision": "block", "reason": text}))


main()
