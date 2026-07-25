// The report card (UX_PLAN U7.2 — item 14): what is wrong with this palette, on screen, with
// the fix attached to the sentence that describes the problem.
//
// All the measuring is `src/core/diagnose.js`; this is only the view and the two buttons. The
// two buttons are the point: a diagnostic that tells you a pair collides and leaves you to
// find it among thirty-two swatches has done half a job, and one that tells you which knob to
// turn and by how much has done all of it.
//
// It refreshes on a settle rather than on every change. A full card is 20–120 ms — cheap, but
// not cheap enough to spend on each frame of a slider drag, and a report that flickered
// through a dozen intermediate palettes would be unreadable anyway.

import { diagnose, summarizeFindings } from '../core/diagnose.js';

/** How long the palette has to stop changing before the card is rebuilt. */
const SETTLE_MS = 500;

/** Whether the card is expanded. Remembered, because it is a preference and not a state. */
const OPEN_KEY = 'palette.report.v1';

/**
 * Build the report card and return a controller.
 *
 * `getUsage()` supplies the `sceneUsage` counts for the current palette (the app already
 * caches them per seed for the picker); `usageOf(palette)` re-counts them for a candidate, and
 * is what lets the unused-colour check verify its own fix. `applyFix(patch, label)` puts a
 * parameter patch into the app state as one history step, and `highlight(ids)` flags swatches.
 */
export function createReport(dom, { getPalette, getUsage, usageOf, applyFix, highlight }) {
  let timer = null;
  let shown = null; // the finding whose swatches are currently flagged

  if (dom.root) {
    try { dom.root.open = localStorage.getItem(OPEN_KEY) === '1'; } catch { /* blocked store */ }
    dom.root.addEventListener('toggle', () => {
      try { localStorage.setItem(OPEN_KEY, dom.root.open ? '1' : '0'); } catch { /* blocked store */ }
    });
  }

  /** Rebuild the card from the palette as it stands. */
  function refresh() {
    const palette = getPalette?.();
    if (!palette || !dom.list) return;
    let findings = [];
    try {
      findings = diagnose(palette, { usage: getUsage?.() ?? null, usageOf });
    } catch (err) {
      // A broken diagnostic must not take the palette pane with it.
      dom.summary.textContent = `could not be checked (${err.message})`;
      dom.list.innerHTML = '';
      return;
    }
    dom.summary.textContent = summarizeFindings(findings);
    dom.root?.classList.toggle('is-clean', findings.length === 0);
    dom.list.innerHTML = '';
    for (const finding of findings) dom.list.appendChild(buildRow(finding));
  }

  /** One finding: severity, what it is, and what to do about it. */
  function buildRow(finding) {
    const row = document.createElement('div');
    row.className = `report-item sev-${finding.severity}`;

    const dot = document.createElement('span');
    dot.className = 'report-dot';
    dot.title = `${finding.severity} — ${finding.check}`;

    const body = document.createElement('div');
    body.className = 'report-body';
    const title = document.createElement('div');
    title.className = 'report-item-title';
    title.textContent = finding.title;
    const detail = document.createElement('div');
    detail.className = 'report-item-detail';
    detail.textContent = finding.detail;
    body.append(title, detail);

    const actions = document.createElement('div');
    actions.className = 'report-actions';

    if (finding.entries.length) {
      const show = document.createElement('button');
      show.className = 'btn btn-small';
      show.textContent = 'Show';
      show.title = `Flag ${finding.entries.length} swatch(es) in the palette below`;
      show.addEventListener('click', () => {
        // Clicking the same row again puts the swatches back, so the flag is a toggle rather
        // than something that has to be cleared from somewhere else.
        const off = shown === finding.id;
        shown = off ? null : finding.id;
        highlight?.(off ? [] : finding.entries);
        show.classList.toggle('is-on', !off);
      });
      actions.appendChild(show);
    }

    if (finding.fix) {
      const fix = document.createElement('button');
      fix.className = 'btn btn-small btn-accent';
      fix.textContent = 'Fix';
      // The whole patch, and the measured gain, in the tooltip: the button is one click but it
      // is not a black box, and "8 → 2" is what makes it worth trusting the next time.
      const patch = Object.entries(finding.fix.params)
        .map(([k, v]) => `${k} → ${typeof v === 'number' ? Number(v.toFixed(3)) : v}`)
        .join(' · ');
      fix.title = `${finding.fix.label}\n${patch}\nMeasured: ${fmt(finding.fix.before)} → ${fmt(finding.fix.after)}`;
      fix.addEventListener('click', () => {
        applyFix?.(finding.fix.params, finding.fix.label);
      });
      actions.append(fix);
      const label = document.createElement('span');
      label.className = 'report-fix-label';
      label.textContent = finding.fix.label;
      body.appendChild(label);
    }

    row.append(dot, body, actions);
    return row;
  }

  return {
    /** Re-run the diagnosis once the palette has stopped moving. */
    schedule() {
      clearTimeout(timer);
      timer = setTimeout(refresh, SETTLE_MS);
    },
    /** Re-run it now (used when a tab that owns the card becomes visible). */
    refresh,
  };
}

/** Report a measured cost without pretending to more precision than it has. */
function fmt(v) {
  return Number.isInteger(v) ? String(v) : v.toFixed(2);
}
