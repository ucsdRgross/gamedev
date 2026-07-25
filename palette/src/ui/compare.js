// Compare A/B (UX_PLAN U6.2 — IMPROVEMENTS item 3).
//
// The variant grid answers "what else could this be?" by showing a dozen. This answers the
// question you have once you are down to two: *what is actually different, and how do I get
// from one to the other?* Three ways, because they answer different halves of it:
//
//   * **Side by side** — the same scene in both, aligned, so the eye does the comparing
//     rather than the memory.
//   * **The difference report** — the parameter moves, biggest first, in the panel's own
//     words. This is the half that teaches: "it is the same palette with the light twenty
//     degrees warmer" is a fact you can reuse.
//   * **The morph** — drag A→B and watch. Numbers travel, enums snap at the halfway mark
//     (see `core/morph.js`), so a palette that jumps rather than slides was separated by a
//     scheme change, and you can see which part of the picture it moved.
//
// B does not have to be a parameter set. A pasted list of colours or a palette image has no
// parameters at all, and for those the morph and the report are honestly unavailable — what
// is offered instead is "fit a palette to these", which is the operation that turns colours
// into parameters in the first place.

import { generatePalette, paletteHexes } from '../core/generate.js';
import { PRESETS, presetParams } from '../core/presets.js';
import { parseJson } from '../core/export/json.js';
import { decodeSeed } from '../core/seed.js';
import { morphParams, morphSnapPoints } from '../core/morph.js';
import { paramDiff, describeChange, describePalette } from '../core/describe.js';
import { paletteFit } from '../core/fit.js';
import { parseHexList, hexListPalette } from '../core/hexlist.js';
import { PARAM_BY_NAME } from '../core/params.js';
import { stripElement, drawScene } from './strip.js';

/** The scene both sides are drawn in. A crowded one, so the difference has room to show. */
const SCENE = 'screenshot';

// Only differences worth a row. Two unrelated presets differ in forty-odd parameters, and a
// list of forty rows buries the three that did the work — the report is meant to teach, and a
// wall of ±0.4% moves teaches nothing. The rest are counted, not hidden.
const NOTABLE = { minMagnitude: 0.02 };
const MAX_ROWS = 14;

/**
 * Build the Compare view. `actions` supplies `getState()`, `applyParams(params, source)`,
 * `fitTo(hexes, opts)` and `listSaves()`/`readSave(name)`.
 * Returns `{ render(), setActive(on), setB(source), pinA(state) }`.
 */
export function createCompare(dom, { actions }) {
  let active = false;
  // A is a *snapshot*: parameters, not a live reference. Comparing against something that
  // moves when you touch a slider is not comparing.
  let a = null;
  let b = null; // { kind: 'params'|'colors', label, params?, hexes, palette }
  // The selector value B came from, remembered separately: the source list is filled
  // asynchronously, so a B chosen from outside (a shift-clicked card) arrives before the
  // option that names it exists, and reading the control back would lose the choice.
  let chosenSource = '';
  let morph = 0;

  /** Take the current palette as A. */
  function pinA(state) {
    a = { label: 'the palette you have', params: { ...state.params }, locks: { ...state.locks }, overrides: { ...state.overrides } };
    render();
  }

  /**
   * The parameters of a side right now.
   *
   * B can be **live** — "the palette you have" tracks the sliders instead of snapshotting
   * them, which is the whole workflow this view is for: pin what you had, then tune and watch
   * the gap open and close. A is never live; comparing against something that moves when you
   * touch a slider is not comparing.
   */
  function sideParams(side) {
    return side.live ? actions.getState().params : side.params;
  }

  /** A palette built from a side's parameters, with that side's locks. */
  function paletteOf(side) {
    const live = side.live ? actions.getState() : side;
    return generatePalette(sideParams(side), { locks: live.locks || {}, overrides: live.overrides || {} });
  }

  /** Set B from one of the sources the selector offers. */
  async function chooseB(value) {
    chosenSource = value || '';
    morph = 0;
    if (dom.morph) dom.morph.value = '0';
    if (!value) { b = null; render(); return; }
    const [kind, rest] = [value.slice(0, value.indexOf(':')), value.slice(value.indexOf(':') + 1)];
    try {
      if (kind === 'current') {
        b = { kind: 'params', live: true, label: 'the palette you have — live, so it follows the sliders' };
      } else if (kind === 'preset') {
        b = { kind: 'params', label: `preset “${PRESETS.find((p) => p.id === rest)?.name || rest}”`, params: presetParams(rest) };
      } else if (kind === 'save') {
        const parsed = parseJson(await actions.readSave(rest));
        b = { kind: 'params', label: `saved “${rest}”`, params: parsed.params, locks: parsed.locks, overrides: parsed.overrides };
      } else if (kind === 'seed') {
        const decoded = decodeSeed(rest);
        b = { kind: 'params', label: 'a pasted seed', params: decoded.params, locks: decoded.locks, overrides: decoded.overrides };
      } else if (kind === 'colors') {
        const hexes = parseHexList(rest);
        if (hexes.length < 1) throw new Error('no colours in that');
        b = { kind: 'colors', label: `${hexes.length} pasted colours`, hexes, palette: hexListPalette('pasted', hexes) };
      } else if (kind === 'external') {
        // A palette image loaded on the Recolour tab. Like pasted colours it has no
        // parameters, so it compares by colour and offers the fit rather than a morph.
        const external = actions.readExternal(rest);
        if (!external) throw new Error('that palette is no longer loaded');
        b = {
          kind: 'colors',
          label: `palette image “${external.name}”`,
          hexes: external.palette.entries.map((e) => e.hex),
          palette: external.palette,
        };
      }
      status('');
    } catch (err) {
      b = null;
      status(`Could not read that: ${err.message}`);
    }
    render();
  }

  function status(text) {
    if (dom.status) dom.status.textContent = text || '';
  }

  /** Draw one side: a scene, the colours, and a line saying what it is. */
  function drawSide(root, side, palette, caption) {
    root.innerHTML = '';
    if (!side) {
      const empty = document.createElement('p');
      empty.className = 'picker-hint';
      empty.textContent = caption;
      root.appendChild(empty);
      return;
    }
    // A colours-only side gets no scene. The scenes address colours through semantic roles
    // (`foliage`, `metal`, the anchors), and an external palette has no role assignment to
    // look them up in — there is nothing to draw a tree *with*. Showing the colours large is
    // the honest alternative to inventing a mapping and presenting the result as a preview.
    if (side.kind !== 'colors') {
      const canvas = document.createElement('canvas');
      canvas.className = 'compare-scene';
      drawScene(canvas, palette, { scene: SCENE, zoom: 2 });
      root.appendChild(canvas);
    }
    const strip = stripElement(palette.entries.map((e) => e.hex), {
      className: side.kind === 'colors' ? 'compare-strip is-tall' : 'compare-strip',
    });
    const label = document.createElement('div');
    label.className = 'compare-label';
    label.textContent = side.label;
    const desc = document.createElement('div');
    desc.className = 'compare-desc';
    desc.textContent = side.kind === 'colors'
      ? `${palette.entries.length} colours, no parameters behind them`
      : describePalette(palette, sideParams(side));
    root.append(strip, label, desc);
  }

  /**
   * The difference report: how far apart the colours are, then what parameters differ.
   * The colour distance comes first because it is the answer to "are these actually
   * different?" — two parameter sets can differ in twenty places and land in the same place.
   */
  function drawReport(aPalette, bPalette) {
    dom.report.innerHTML = '';
    if (!a || !b) return;
    const fit = paletteFit(paletteHexes(aPalette), paletteHexes(bPalette));
    const distance = document.createElement('p');
    distance.className = 'compare-distance';
    // `paletteFit(candidate, target)` was called with A as the candidate, so `coverage` is
    // how near A gets to B's colours and `fidelity` how near B gets to A's. Both are mean
    // ΔE — distances, so lower is closer — and the asymmetry is the interesting part: a big
    // coverage with a small fidelity means B has colours A simply cannot reach.
    distance.textContent = fit.score < 0.5
      ? `Practically the same colours (ΔE ${fit.score.toFixed(2)})`
      : `ΔE ${fit.score.toFixed(2)} apart — A reaches B's colours within ${fit.coverage.toFixed(2)}, `
        + `B reaches A's within ${fit.fidelity.toFixed(2)} (lower is closer)`;
    dom.report.appendChild(distance);

    if (b.kind !== 'params') {
      const note = document.createElement('p');
      note.className = 'picker-hint';
      note.textContent = 'Pasted colours have no parameters behind them, so there is nothing to '
        + 'diff and nothing to morph through. “Fit a palette to B” is the move that changes that.';
      dom.report.appendChild(note);
      return;
    }

    const diff = paramDiff(a.params, sideParams(b), NOTABLE);
    if (!diff.length) {
      const same = document.createElement('p');
      same.className = 'picker-hint';
      same.textContent = 'Identical parameters — these are the same palette.';
      dom.report.appendChild(same);
      return;
    }
    const list = document.createElement('ul');
    list.className = 'compare-diff';
    for (const change of diff.slice(0, MAX_ROWS)) {
      const li = document.createElement('li');
      li.textContent = describeChange(change);
      li.title = `${change.name}: ${format(change.from)} → ${format(change.to)}`;
      // One click takes just this change across, so the report is a set of moves rather
      // than a description of a gap.
      const take = document.createElement('button');
      take.className = 'compare-take';
      take.textContent = 'take';
      take.title = `Apply only this change to the palette you have`;
      take.addEventListener('click', () => {
        actions.applyParams(
          { ...actions.getState().params, [change.name]: change.to },
          `Took “${PARAM_BY_NAME.get(change.name)?.label || change.name}” from B`,
        );
      });
      li.appendChild(take);
      list.appendChild(li);
    }
    dom.report.appendChild(list);
    if (diff.length > MAX_ROWS) {
      const more = document.createElement('p');
      more.className = 'picker-hint';
      more.textContent = `and ${diff.length - MAX_ROWS} smaller change${diff.length - MAX_ROWS === 1 ? '' : 's'}`;
      dom.report.appendChild(more);
    }

    const snaps = morphSnapPoints(a.params, sideParams(b));
    if (snaps.length && dom.morphNote) {
      dom.morphNote.textContent = `jumps at the halfway mark: ${snaps[0].names
        .map((n) => PARAM_BY_NAME.get(n)?.label || n).join(', ')}`;
    } else if (dom.morphNote) {
      dom.morphNote.textContent = 'a smooth morph — nothing here jumps';
    }
  }

  const format = (v) => (typeof v === 'number' ? v.toFixed(3).replace(/\.?0+$/, '') : String(v));

  /** Repaint everything. Cheap enough (two palettes and two small scenes) to do wholesale. */
  function render() {
    if (!active) return;
    const aPalette = a ? paletteOf(a) : null;
    const bPalette = b ? (b.kind === 'colors' ? b.palette : paletteOf(b)) : null;
    drawSide(dom.a, a, aPalette, 'Nothing pinned yet — press “Pin current as A”.');
    drawSide(dom.b, b, bPalette, 'Choose something to compare against.');
    if (a && b) drawReport(aPalette, bPalette);
    else dom.report.innerHTML = '';

    const morphable = Boolean(a && b && b.kind === 'params');
    dom.morphRow.hidden = !morphable;
    dom.howTo.disabled = !(a && b);
    dom.takeAll.disabled = !morphable;
    if (morphable) drawMorph();
  }

  /** The morph preview: the palette `morph` of the way from A to B. */
  function drawMorph() {
    const params = morphParams(a.params, sideParams(b), morph);
    const palette = generatePalette(params, { locks: a.locks || {}, overrides: a.overrides || {} });
    drawScene(dom.morphScene, palette, { scene: SCENE, zoom: 2 });
    dom.morphStrip.innerHTML = '';
    dom.morphStrip.appendChild(stripElement(palette.entries.map((e) => e.hex), { className: 'compare-strip' }));
    dom.morphValue.textContent = `${Math.round(morph * 100)}%`;
  }

  dom.pinA?.addEventListener('click', () => pinA(actions.getState()));
  dom.source?.addEventListener('change', () => chooseB(dom.source.value));
  dom.morph?.addEventListener('input', () => {
    morph = Number(dom.morph.value) / 100;
    if (a && b && b.kind === 'params') drawMorph();
  });
  dom.takeMorph?.addEventListener('click', () => {
    actions.applyParams(morphParams(a.params, sideParams(b), morph), `Morph A→B at ${Math.round(morph * 100)}%`);
  });
  dom.takeAll?.addEventListener('click', () => {
    actions.applyParams(sideParams(b), `Took B (${b.label})`);
  });
  // One field for both, because from the user's side they are the same act: "here is a thing
  // I copied". A `PAL1-` string is a whole parameter set and gives a full comparison; anything
  // else is read as colours.
  dom.pasteB?.addEventListener('change', () => {
    const text = dom.pasteB.value.trim();
    chooseB(/^PAL1-/i.test(text) ? `seed:${text}` : `colors:${text}`);
  });

  // "How to get there": the fitter, started **at A** and aimed at B's colours. Without `from`
  // this would answer a different question — "what parameters make B?" — and hand back a set
  // with nothing of A left in it. Started at A, the diff it returns is a route.
  dom.howTo?.addEventListener('click', () => {
    if (!a || !b) return;
    const target = b.kind === 'colors' ? b.hexes : paletteHexes(paletteOf(b));
    dom.howTo.disabled = true;
    actions.fitTo(target, {
      from: a.params,
      label: `How to get from A to ${b.label}`,
      onDone: () => { dom.howTo.disabled = false; render(); },
    });
  });

  /** Fill the B selector: everything a comparison could reasonably be against. */
  async function fillSources() {
    if (!dom.source) return;
    const groups = [
      ['Live', [['current:', 'The palette you have now']]],
      ['Presets', PRESETS.map((p) => [`preset:${p.id}`, p.name])],
    ];
    let saves = [];
    try { saves = await actions.listSaves(); } catch { /* no store yet */ }
    if (saves.length) groups.push(['Kept', saves.map((n) => [`save:${n}`, n])]);
    const external = actions.listExternal?.() || [];
    if (external.length) {
      groups.push(['Palette images', external.map((t) => [`external:${t.id}`, `${t.name} · ${t.count}`])]);
    }
    dom.source.innerHTML = '<option value="">Compare against…</option>';
    for (const [label, options] of groups) {
      const group = document.createElement('optgroup');
      group.label = label;
      for (const [value, text] of options) {
        const o = document.createElement('option');
        o.value = value;
        o.textContent = text;
        group.appendChild(o);
      }
      dom.source.appendChild(group);
    }
    if (chosenSource) dom.source.value = chosenSource;
  }

  return {
    render,
    pinA,
    /** Choose B from outside — a shift-clicked card on the Start tab. */
    setB(source) {
      chooseB(source);
      fillSources(); // so the option naming this source exists, and the control shows it
    },
    setActive(on) {
      active = on;
      if (!on) return;
      fillSources();
      // Entering with nothing pinned pins what is on screen: the overwhelmingly common
      // intent is "compare this against something", and requiring a click first is a step
      // that only ever gets in the way.
      if (!a) pinA(actions.getState());
      else render();
    },
  };
}
