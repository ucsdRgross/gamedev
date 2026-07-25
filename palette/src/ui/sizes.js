// The colour-count sweep (UX_PLAN U2.6 — item 31).
//
// `color_count` is the one parameter whose effect cannot be judged from a slider: 16 versus
// 32 is not "more of the same", it is a different palette with a different structure. The
// headless renderer has always written this comparison to `out/size-sweep.png`; this puts it
// in the app, where the answer can be clicked.
//
// Every row is the current parameter set at a different size, so what is compared is *this*
// palette at six budgets — not six unrelated palettes.

import { sizeSweep } from '../core/preview.js';
import { stripElement, sceneThumb } from './strip.js';

/**
 * Wire the Sizes button to a popover. `getState()` supplies `{ params, locks, overrides }`;
 * `onPick(size)` is called with the chosen colour count.
 */
export function createSizeSweep({ button, getState, onPick }) {
  if (!button) return { close() {} };

  const pop = document.createElement('div');
  pop.className = 'size-pop';
  pop.hidden = true;
  document.body.appendChild(pop);

  const close = () => { pop.hidden = true; };

  /** Build the six rows for the current parameters and show them under the button. */
  function open() {
    const state = getState();
    pop.innerHTML = '';
    const title = document.createElement('div');
    title.className = 'size-pop-title';
    title.textContent = 'This palette at every size';
    pop.appendChild(title);

    // Locks are deliberately not passed: a lock pins a slot that may not exist at another
    // size, and the question here is "what does the budget do", not "what survives".
    for (const step of sizeSweep(state.params, { overrides: {} })) {
      const row = document.createElement('button');
      row.className = `size-row${step.current ? ' is-current' : ''}`;
      row.title = step.current ? `${step.value} colours — the current size` : `Use ${step.value} colours`;
      const label = document.createElement('span');
      label.className = 'size-label';
      label.textContent = String(step.value);
      const strip = stripElement(step.hexes, { className: 'size-strip' });
      const thumb = sceneThumb(step.palette, { className: 'size-scene' });
      row.append(label, strip, thumb);
      row.addEventListener('click', () => {
        close();
        if (!step.current) onPick(step.value);
      });
      pop.appendChild(row);
    }

    pop.hidden = false;
    const r = button.getBoundingClientRect();
    const w = pop.offsetWidth;
    pop.style.left = `${Math.max(12, Math.min(r.right - w, window.innerWidth - w - 12))}px`;
    pop.style.top = `${Math.min(r.bottom + 6, window.innerHeight - pop.offsetHeight - 12)}px`;
  }

  button.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (pop.hidden) open();
    else close();
  });
  document.addEventListener('click', (ev) => {
    if (!pop.hidden && !pop.contains(ev.target)) close();
  });
  window.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') close(); });

  return { close };
}
