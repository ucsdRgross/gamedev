# Duplicate hunt — the Solatro effect-review questionnaire

The questionnaire has ~1,440 live questions, one candidate card effect each, three variants (a/b/c)
per question. It was assembled from many sources by many passes, and the owner has noticed
duplicates (their own example: Q0092 "Cluster" option (c) "a line where no two cards share a rank
or a suit" is the same effect as Q0091 "Bulwark" option (c) "any five cards that share no rank and
no suit", and Q0088 "Badugi" (b)). Your job is to find every such pair in your group and say which
question to retire.

Read first: `C:\richard\gamedev\solatro\design\effect-review\build\GAME_BRIEF.md` (the rulebook,
so you know which words mean the same thing here — e.g. "line", "meld", "hand" all refer to a
completed line of five scored as a poker hand; "spotlit" = uncovered on the grid; "Cue:" = tap to
activate).

Your group file (path in your task) lists your questions in full:
```
Qnnnn | Name | slot | class [ANSWERED]
  mechanic: one-line blurb
  (a) ...
  (b) ...
  (c) ...
```
The file `C:\richard\gamedev\solatro\design\effect-review\build\mine_mods\existing_effects_short.txt`
lists EVERY question in the questionnaire in one line each, so you can also catch a duplicate
whose twin lives outside your group.

## What counts as a duplicate

Two questions are duplicates when a player could not tell the two effects apart in play: same
trigger, same action, same target — even if the names differ, the numbers differ, the flavour
differs, or one is phrased as a skill and the other as a hazard/structure. A question whose
variants are all covered by another question's variants is a duplicate of it. Two questions in
the same class are the usual case, but check the trigger and the action, not the class code.

NOT duplicates: the same trigger with a genuinely different action (retrigger vs +points); the
same action on a different target (this card vs every card in its row vs the whole grid); a
strict generalisation that the owner would want to choose between (once per show vs every time
is a VARIANT, not a duplicate — but if both questions offer both, they are duplicates); a mark
version and a non-mark version of a rule (family Y exists to ask exactly that).

## Which one to retire

Keep the question with the lower id unless the higher one is marked [ANSWERED] and the lower is
not (an answered question is never retired). If both are answered, report the pair but mark it
KEEP-BOTH. Prefer keeping the one whose three variants are the better fork.

## Output

Write ONE tab-separated file at the output path in your task. UTF-8, no header, no markdown, no
tabs inside fields. Write it with a Python script or the Write tool (never PowerShell
`Set-Content`/`Out-File`). One line per pair:

```
DUP<TAB>Qretire<TAB>Qkeep<TAB>confidence HIGH|MEDIUM<TAB>one sentence: which option of each is the same effect
KEEP-BOTH<TAB>Qa<TAB>Qb<TAB>reason (both answered, or you are unsure)
```

HIGH means you would bet on it: a reader of both questions would say "that is the same card".
MEDIUM means the shapes overlap heavily but one option differs. Report both; be exhaustive on
HIGH and honest on MEDIUM. Do not report near-neighbours that are merely in the same class.

When finished, reply with ONLY the counts of HIGH, MEDIUM and KEEP-BOTH lines.
