# -*- coding: utf-8 -*-
"""Prove a comment sweep changed no code.

    py .claude/tools/sweep_check.py <repo-relative .gd path> [more paths]

Strips every comment and blank line from HEAD's version and the working copy of each file with
doc_check's own comment splitter and compares the remainders byte for byte. A sweep is accepted
only when every file prints CODE IDENTICAL; a trailing comment's removal edits its code line, which
a diff-shape check cannot tell from a code change and this can.
"""
import io
import os
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(TOOLS))
sys.path.insert(0, TOOLS)
import doc_check


def code_only(text):
    out = []
    fence = None
    for raw in text.split('\n'):
        code, _comment, fence = doc_check.split_code_comment(raw, fence)
        if code.strip():
            out.append(code.rstrip())
    return out


def check(rel):
    old = subprocess.run(['git', '-C', REPO, 'show', 'HEAD:' + rel.replace(os.sep, '/')],
                         capture_output=True, text=True, encoding='utf-8').stdout
    new = io.open(os.path.join(REPO, rel), encoding='utf-8').read()
    before, after = code_only(old), code_only(new)
    if before == after:
        print('CODE IDENTICAL: %s (%d code lines)' % (rel, len(after)))
        return True
    for i, (a, b) in enumerate(zip(before, after)):
        if a != b:
            print('CODE DIFFERS: %s at code line %d\n  HEAD: %s\n  now:  %s' % (rel, i + 1, a, b))
            break
    else:
        print('CODE DIFFERS: %s - %d code lines at HEAD, %d now' % (rel, len(before), len(after)))
    return False


if __name__ == '__main__':
    sys.exit(0 if all([check(p) for p in sys.argv[1:]]) else 1)
