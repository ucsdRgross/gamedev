# -*- coding: utf-8 -*-
"""The name the owner sees in place of an IP name (owner ruling, `GAME_BRIEF.md` "No IP names").

A question's record name is its sort key within its class, and a question id is positional, so
renaming the record would move every question after it. `render.py` sorts by the record name and
shows this one; a non-empty source opens the head as "After <source>:".

eid -> (shown name, source)
"""
SHOWN = {
}
