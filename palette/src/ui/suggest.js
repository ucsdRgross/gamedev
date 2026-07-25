// "Colours worth adding" in the palette pane (UX_PLAN U7.4 — item 15).
//
// The dither reference has always known which colour would most close the gaps this palette
// cannot dither its way across. The finding was two tabs deep, behind a Rebuild button, on a
// page nobody opens while tuning — so it was surfaced here, next to the swatches, where the
// decision it informs is actually made.
//
// It is a button rather than something that runs by itself: the search is about 200 ms, which
// is far too much to spend on every frame of a slider drag, and the question ("am I short a
// colour?") is one somebody asks at a particular moment rather than continuously.

import { suggestAdditions, addColorSlot } from '../core/additions.js';
import { colorLabel } from '../core/colornames.js';

export function createSuggest(dom, { getState, getPalette, onAdd }) {
  let seedShown = null; // the palette the results on screen were computed for

  /** Run the search and draw the results. */
  function run() {
    const palette = getPalette?.();
    if (!palette) return;
    dom.run.disabled = true;
    dom.note.textContent = 'looking for the gaps…';
    dom.list.innerHTML = '';
    // Yielding first so the "looking" state is painted before the search blocks the thread.
    setTimeout(() => {
      let found = [];
      try {
        found = suggestAdditions(palette);
      } catch (err) {
        dom.note.textContent = `could not be computed (${err.message})`;
        dom.run.disabled = false;
        return;
      }
      seedShown = palette.seed;
      dom.run.disabled = false;
      dom.run.textContent = 'Look again';
      if (!found.length) {
        // A real answer, not a failure: everything the sampled colour volume asks for is
        // already within dithering reach of the colours this palette has.
        dom.note.textContent = 'nothing missing — dithering already reaches everything';
        return;
      }
      dom.note.textContent = 'widest gaps first';
      for (const s of found) dom.list.appendChild(buildCard(s, palette));
    }, 0);
  }

  /** One suggested colour: the chip, what it is called, and the one button. */
  function buildCard(suggestion, palette) {
    const card = document.createElement('div');
    card.className = 'suggest-item';

    const chip = document.createElement('span');
    chip.className = 'suggest-chip';
    chip.style.background = suggestion.hex;

    const body = document.createElement('div');
    body.className = 'suggest-body';
    const name = document.createElement('div');
    name.className = 'suggest-name';
    name.textContent = `${colorLabel(suggestion.hex).label} · ${suggestion.hex}`;
    const detail = document.createElement('div');
    detail.className = 'suggest-detail';
    detail.textContent = `banding would fall to ΔE ${suggestion.after.mean.toFixed(2)}`
      + ` · ${Math.round(suggestion.after.within * 100)}% of the colour volume band-free`;
    body.append(name, detail);

    const add = document.createElement('button');
    add.className = 'btn btn-small btn-accent';
    add.textContent = 'Add';
    add.title = `Add ${suggestion.hex} as a locked slot: one more colour, pinned to this value`;
    add.addEventListener('click', () => {
      const state = getState();
      const grown = addColorSlot(state.params, suggestion.hex, {
        locks: state.locks, overrides: state.overrides,
      });
      if (!grown) {
        add.disabled = true;
        dom.note.textContent = 'this palette is already at its maximum colour count';
        return;
      }
      onAdd(grown, suggestion.hex);
    });

    // Stale as soon as the palette moves: the gaps were measured against the colours that were
    // on screen when Look was pressed, and offering to add one of them to a different palette
    // would be advice about a palette that no longer exists.
    if (palette.seed !== seedShown) add.disabled = true;

    card.append(chip, body, add);
    return card;
  }

  dom.run?.addEventListener('click', run);

  return {
    /**
     * Drop the results once they no longer describe the palette on screen.
     *
     * Cleared rather than greyed out: they were measured against colours that are gone, and
     * three stale rows would go on holding a third of the palette pane's height hostage while
     * saying nothing true about what is in it.
     */
    invalidate() {
      const palette = getPalette?.();
      if (!seedShown || !palette || palette.seed === seedShown) return;
      seedShown = null;
      dom.list.innerHTML = '';
      dom.note.textContent = 'the palette has changed — look again';
    },
  };
}
