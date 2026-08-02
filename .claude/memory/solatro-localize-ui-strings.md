---
name: solatro-localize-ui-strings
description: "Every UI-facing string in Solatro must come from Locale/localization.csv via TRANSLATION.find, never a literal"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9142ade9-f98d-4441-8895-a93351149aea
---

In Solatro, **any user-facing string must be a localization key**, not a hard-coded literal.
Add the key + English text to `Locale/localization.csv` (columns: `key,en,?context`) and read it in
code via `TRANSLATION.find('MY_KEY')` (`Scripts/translation.gd`, `TranslationServer.translate`).

Reference pattern (`Cards/Types/type_input.gd`):
```
func get_str() -> String: return TRANSLATION.find('INPUT_ZONE_CARD')
func get_description() -> String: return TRANSLATION.find('INPUT_ZONE_CARD_DESCRIPTION')
```
Convention: `NAME` for the short label, `NAME_DESCRIPTION` for the long text; keys are
SCREAMING_SNAKE_CASE. Multi-line English values are quoted in the CSV.

**Why:** the game is fully localized (+ a pseudo-localisation / "revealed" cycler); a literal string
bypasses translation and the reveal mechanic and can't be shipped in other languages.

**How to apply:** when writing/reviewing any `get_str`/`get_description` or other UI text (suits,
statuses, skills, meld names, buttons), route it through `TRANSLATION.find` and add the CSV row.
Pure formatting glyphs/numbers (e.g. `"×%d"`) don't need a key. Note: several Phase-3 suit/status
`get_str`/`get_description` were written as literals and had to be retrofitted — don't repeat that.
Related: [[solatro-project-facts]].
