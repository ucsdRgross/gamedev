// The two DOM chores every panel in `src/ui/` does.
//
// Seven modules built their own `<option>` loop and two of them carried a byte-identical
// `fillSelect`, which is what happens when a UI grows one tab at a time. Nothing here is
// clever; it exists so that the next tab does not invent an eighth way to fill a dropdown.

/** An `<option>` with a value and a label. */
export function option(value, label) {
  const el = document.createElement('option');
  el.value = value;
  el.textContent = label;
  return el;
}

/** Replace a `<select>`'s contents from `[value, label]` pairs. Missing elements are ignored. */
export function fillSelect(el, pairs) {
  if (!el) return;
  el.innerHTML = '';
  for (const [value, label] of pairs) el.appendChild(option(value, label));
}
