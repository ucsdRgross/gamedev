# PreToolUse gate: check the STAGED diff for maintainability seams before a commit records them.
#
# Why a PreToolUse hook on `git commit` and not a git pre-commit hook:
#   * it fires only on commits an AGENT makes, so the owner's GitHub Desktop flow on `main` is
#     never blocked;
#   * exit 2 puts the findings in Claude's context, where they can be acted on, instead of in a
#     terminal nothing reads;
#   * it costs nothing when no commit is happening.
#
# WHAT BLOCKS, AND WHY ONLY THIS:
#   Duplicated blocks BLOCK. They are precise, rare, and the standing backlog is small (8
#   production-touching pairs in solatro), so a block means something new.
#   Add-only shape WARNS ONLY. The baseline says 34% of this repo's code-touching commits are
#   add-only at the default threshold - blocking on that would fire on a third of all commits and
#   the gate would be switched off within a week. It rides along as context instead.
#   Re-derive both numbers any time with:
#     py .claude/tools/diff_shape.py --history 400
#
# ESCAPE HATCH: put [dup-ok] in the commit message. Intentional duplication exists (a test fixture
# that must not share a helper with the code it tests), and a gate with no way past it gets
# deleted rather than argued with. The marker lands in git history, so the decision is auditable.
#
# Exit 0 = allow, exit 2 = block and show stderr to Claude.

. "$PSScriptRoot\_hook_input.ps1"
if (-not $cmd) { exit 0 }

# `git commit`, allowing flags in between (`git -C x commit`, `git commit -m ...`).
if ($cmd -notmatch '(?i)\bgit\b[^|;&]*\bcommit\b') { exit 0 }
# `git commit --dry-run` records nothing, and neither does asking for the message template.
if ($cmd -match '(?i)--dry-run') { exit 0 }
if ($cmd -match '(?i)\[dup-ok\]') { exit 0 }

$repo = $env:CLAUDE_PROJECT_DIR
if (-not $repo) { $repo = (Get-Location).Path }

$dupTool = Join-Path $repo '.claude\tools\dup_check.py'
if (-not (Test-Path $dupTool)) { exit 0 }

$dup = & py $dupTool --staged 2>&1 | Out-String
$dupFound = ($LASTEXITCODE -ne 0)

if (-not $dupFound) { exit 0 }

# Only gathered when something already blocks - a warn-only check must never cost a clean commit.
$shapeTool = Join-Path $repo '.claude\tools\diff_shape.py'
$shape = ''
if (Test-Path $shapeTool) {
    $shape = & py $shapeTool --staged --warn-only 2>&1 | Out-String
}

[Console]::Error.WriteLine(@"
BLOCKED: the staged diff duplicates logic that already exists.

$($dup.Trim())

Each pair is one behaviour with two homes. The next edit will reach one and miss the other - that
is the defect, and no test will catch it because both copies pass.

DO ONE OF THESE:
  * call the existing code instead of the copy you just wrote (grep the name first - the copy
    usually exists because nobody looked);
  * extract the shared block, if BOTH sides genuinely want to change together;
  * keep the duplicate deliberately and say so: put [dup-ok] in the commit message. Use this when
    the two sides must be free to drift - a test fixture that must not share a helper with the
    code under test is the honest case.

$(if ($shape.Trim()) { "ALSO WORTH A LOOK (does not block):`n$($shape.Trim())" })
"@)
exit 2
