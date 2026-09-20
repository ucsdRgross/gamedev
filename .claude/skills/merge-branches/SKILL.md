---
name: merge-branches
description: Combine one or more finished feature branches into a single reviewed change ready for main — read what the branches say about each other, merge with a base-showing conflict style, split comment sweeps from real edits mechanically, then hunt the breakage git cannot see. Use when asked to merge branches together, to land parallel work, or to prepare a branch for main.
---

# Merging parallel branches

The textual conflicts are the easy half. The half that breaks the build is semantic: branch A
deleted a field that branch B's new files still read, and git merges both without a word.

Run this even for ONE branch — it has the same collision with whatever `main` moved.

Invoke as `/merge-branches <branch> [<branch> ...]`.

**Shape of the run:** steps 1–3 once, then **steps 4–7 and a commit per branch**, then steps 8–10
once over the combined tree. Doing the semantic pass after the first merge reads a tree the second
branch is not in yet.

## 1. Survey

```bash
git branch -a -vv && git status --short
git log --oneline $(git merge-base main <branch-a>)..main        # main moved too
comm -12 <(git diff --name-only $(git merge-base <a> <b>) <a> | sort) \
         <(git diff --name-only $(git merge-base <a> <b>) <b> | sort)
```

A `+` means the branch is checked out in a worktree — you cannot check it out again, but you can
merge it. Work in the main worktree, on a new branch.

⚠ The `comm` uses the branches' **pairwise** base. Against `main`'s base it also lists everything
they merely inherited together: measured 52 files vs 43 on one real merge.

## 2. Read what the branches say about each other — this is the whole job

Parallel runs that knew about each other **wrote down how to resolve the overlap**, and that note
outranks any judgement you would make at the conflict.

```bash
git grep -n -iE "<other-branch>|when .* lands" <branch> \
  -- '*/design/*/gaps/*.md' '*/HANDOFF_*.md' '*/todo.md'
```

- **`gaps/GAP-*.md`** — a gap raised *because* the other branch owned the thing has a
  `resolution:` block with the owner's verbatim ruling. That block is the answer.
- **`HANDOFF_*.md`** — the step table's `notes:` say which steps are stand-ins.
- **`todo.md`** — an ordering note names which branch is the authority.

⚠ **A stand-in says so**, in words like "deleted when X lands". That is an instruction. Collect
every one before merging; each is a step 8 task.

## 3. Order: the OWNER of a shared mechanism goes first

Merge the branch that really implements the shared thing first, so it is `ours` for the rest and
the other branch's stand-in is what gets retired.

## 4. Merge with the base showing

```bash
git checkout -b combine-<a>-<b> main
git -c merge.conflictStyle=zdiff3 merge --no-ff -X diff-algorithm=histogram <branch>
```

`histogram` separates a comment change from an adjacent code change instead of reporting one coarse
hunk. `zdiff3` writes the merge base into every conflict — **step 5 cannot run without it.**

## 5. Split the comment sweeps off, mechanically

A branch that ran a close sweep rewrote comments in the files the other branch rewrote code in.
The tool proves which is which against the base:

```bash
py .claude/tools/merge_split.py            # report
py .claude/tools/merge_split.py --apply    # resolve the hunks where one side had no code
```

It takes the side whose code moved, and the second branch's where neither side's did. Where **both**
changed code it leaves the conflict. ⚠ In every hunk it resolves the losing side's comment edits
are discarded — a comment can be rewritten, a dropped code line cannot be noticed. 187 of 236 hunks
on the sidebar/board-plan merge.

## 6. Resolve the rest by hand

| Situation | Take |
|---|---|
| One side deleted the code, the other swept its comment | the deletion — an orphaned comment is a dead reference |
| Both sides ADDED to a registry (suites, input actions, palette roles, numbered list) | **both**, renumbering if numbered |
| A generated file (`.translation`, `.import`, `.uid`) | whichever side matches `main`'s POLICY for that class — see step 8.4 |
| A doc hard-codes a count both branches changed | the form carrying no number, or re-derive it |
| Both changed real logic | read both, keep both intents in one statement |

⚠ **A hunk you resolve to one side DELETES whatever the other side defined inside it**, and nothing
reports it. Per file, list what the losing side introduced and check each name survived:

```bash
git diff $(git merge-base <a> <b>) <losing-branch> -- <file> \
  | grep -E '^\+\s*(func|const|var|signal|class_name)' 
```

⚠ **Match the file's line endings** — much of this repo is CRLF, so a literal replacement written
with `\n` matches nothing. Work line-wise, or detect `\r\n` first.

Then finish the merge: `git add` the files you resolved (not `-A` — the Godot runs in step 9 leave
untracked output), and commit. ⚠ **A merge commit always trips `commit-gate.ps1`**, whose diff is
the whole branch replayed. Put `[dup-ok]` in the message and say why — *a merge commit authors no
logic*. The hook matches the commit COMMAND's text, so the message must be inline (`-m`, or a
heredoc in the same command), not `-F <file>`.

The message is the only record of the decisions: each semantic collision and the note that decided
it, the split counts, and the gate result.

## 7. Registries collide silently

Both branches appending to one registry merges "cleanly" and is wrong when the entries claim the
same slot. Make each check ANSWER, not print:

```bash
grep -o 'id="[^"]*"' solatro/Tests/all_tests.tscn | sort | uniq -d            # suite ids
grep -o 'button_index":[0-9]*' solatro/project.godot | sort | uniq -d         # pad buttons
grep -c 'ext_resource type="PackedScene"' solatro/Tests/all_tests.tscn        # vs the same grep
                                                                              # on each branch tip
```

A duplicate binding is an **owner call**. Report it with the free slots beside it.

⚠ **An ORDERING registry hangs instead of failing.** Solatro's suites name every suite that runs
AFTER them (`await_siblings_except`; the rule is `Tests/Support/test_base.gd` "SUITE ORDERING").
Two branches each adding a suite produce two lists neither of which names the other's, so each
waits for the other. Measured: two missing names hung the run twice with an empty errors log.
The lists must be one total order — check that, not just for 2-cycles:

```bash
py - <<'EOF'
import io, re, glob
w = {}
for p in glob.glob('solatro/Tests/**/*.gd', recursive=True):
    if 'test_base.gd' in p: continue
    s = io.open(p, encoding='utf-8', errors='replace').read()
    m = re.search(r'await_siblings_except\(\[(.*?)\]\)', s, re.S)
    n = re.search(r'func suite_name.*?return "([^"]+)"', s, re.S)
    if m and n: w[n.group(1)] = set(re.findall(r'"([^"]+)"', m.group(1)))
order = sorted(w, key=lambda k: -len(w[k]))
bad = [k for i, k in enumerate(order) if w[k] != set(order[i + 1:])]
print(bad or 'one total order')
EOF
```

## 8. The semantic merge — what git could not see

1. **Retire the stand-ins** from step 2. Delete the temporary helper, point its callers at the real
   one, and adapt the types — a stand-in built on the old shape returns the old shape.
2. **Find every reader of what the other branch DELETED.** Its *new* files never conflicted, so
   they still read it. Get the list, then grep each name:
   ```bash
   git diff $(git merge-base <a> <b>) <branch> -- '*.gd' \
     | grep -E '^-\s*(var|const|func|signal|@export)'
   ```
3. **Fixtures predate the other branch's conventions.** A suite written before the other branch
   made a call `await`, added an auto-end on a met goal, or split one pile per slot will compile and
   then fail or hang. Adopt that branch's own fixture constants — grep its suites for what they use.
4. **Generated files: match `main`'s POLICY, do not merge or blindly regenerate.** A class `main`
   untracked comes back when one branch adds NEW members of it — those are clean adds git never
   asks about. For each pattern a side stopped tracking, `git ls-files <pattern>` must be empty.
   Measured: five `EFFECTS.*.translation` rode in this way. Where regeneration IS the policy,
   `--headless --import` writes them; `importer="keep"` in a `.import` is a deliberate freeze and
   must survive.

5. **A RULE ONE BRANCH ENFORCED AT ONE SEAM, where the other branch added more seams.** This is the
   merge defect no test on either branch can fail on, and the most expensive one here. Branch A
   wrote "no signal that grabs a card fires while the viewer is open" and guarded the one signal
   it had; branch B added three more signals it never saw. Take every rule stated as a
   quantifier -- *no*, *every*, *always*, *the one place* -- and re-derive the set it ranges over
   on the MERGED tree:
   ```bash
   grep -rn 'signal ' <the file that states the rule>   # then grep each name's emit sites
   ```
   If the rule now has more members than the guard covers, give it ONE home and route them all
   through it. Then prove it red-then-green: neutralise the guard and watch the new row fail.

6. **Duplication the MERGE created.** Two branches writing the same helper never conflict.
   `dup_check.py` over each branch tip (`git archive <branch> | tar -x -C <dir>`, then run **that
   copy** of the tool — it resolves its root from its own path) and over the combine branch: pairs
   on neither input are the merge's own.

## 9. Verify in widening passes

1. **`--headless --import`** — parses scenes and resources. Seconds.
2. **`py .claude/tools/doc_check.py`** — the cross-branch dead reference: A renamed a file, B's new
   doc names the old one. Neither branch can see it.
3. **`run_tests.py --logic`** — the headless tier, and what actually type-checks GDScript. A
   `Parse Error: the property X is not present` is step 8.2 coming back.
4. **The FULL windowed run** — the only verdict; a filtered run voids the suite count.

Every run: a private `APPDATA`, one at a time, no editor open — [[running-godot-scenes]]. A fresh
`APPDATA` also matters here on its own: both branches adding a field to a saved resource merges
cleanly, and an old `user://` save hides the migration that never saw the other's field. **A hang
or missing banner is not yet a defect of this merge: re-run once** ([[one-fix-at-a-time]]).

Before the final commit, `doc_check.py --changed`: where step 5 took the code side, the other
branch's comment sweep went with it, and that file may no longer be compliant.

## 10. Review, then hand the owner what is theirs

Dispatch a **read-only `general-purpose` subagent at the reviewer floor** — the model named in the
merge commits' `Co-Authored-By`, or higher. Brief it on the MERGE, not the branches' own work,
which was already reviewed on its branch: the merge commit messages, the step 2 notes, and the
files where you took one side over the other. `adversarial-review` is the wrong agent here — it
scopes itself to `main...HEAD`, which is both branches entire.

Then report to the owner, separately, **every decision that was theirs**: a duplicate binding, a
test whose premise a merge invalidated, a stand-in whose replacement changed behaviour. Hand them
the combine branch — never merge it to `main` yourself (hard rule 1).

## Traps measured here

- **The overlap notes are in the gap files, not the code**, and are worth more than reading diffs.
- **`--logic` is the cheapest real type-check**; `--import` exits 0 on a project whose scripts do
  not compile.
- **A hang with an EMPTY errors log is an ordering deadlock, not a crash.** The suites that never
  printed a banner name the blocker — not the last line written.
- **A doc can be false without `doc_check` seeing it.** It resolves file references, not function
  names: four docs still described a helper this merge deleted. Grep the docs for every name you
  retired in step 8.
- **A gap file's ruling stays verbatim; its DERIVATION can go stale.** "Only X is unbound" stopped
  being true when the other branch took X. Append the correction, never edit the owner's words.
- **Two branches' features can both be right and still contradict one test.** A branch asserting
  "nothing tints" fails once the other makes a tint reach the pixels. Narrow the claim to what that
  branch owns and name the other's feature as what explains the rest. Deleting the test is a silent
  scope cut.
