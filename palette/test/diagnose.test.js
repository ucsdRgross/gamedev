import test from 'node:test';
import assert from 'node:assert/strict';
import {
  diagnose, summarizeFindings, entryDivergence, CHECKS, SEVERITY_ORDER, NEAR_DUPE_DE, DIVERGENCE_C,
} from '../src/core/diagnose.js';
import { generatePalette } from '../src/core/generate.js';
import { defaultParams, PARAM_BY_NAME, coerceParam } from '../src/core/params.js';
import { PRESETS, presetParams } from '../src/core/presets.js';

const CHECK_BY_ID = new Map(CHECKS.map((c) => [c.id, c]));
const noUsage = { usageFor: () => null };

/** A context matching the one `diagnose` builds, for measuring a check by hand. */
const ctxWith = (usage) => ({ usageFor: () => usage });

test('every check measures every preset without throwing, and reports a finite cost', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(presetParams(preset.id));
    for (const check of CHECKS) {
      const cost = check.metric(palette, noUsage);
      assert.ok(Number.isFinite(cost) && cost >= 0, `${preset.id}/${check.id} → ${cost}`);
      const found = check.findings(palette, noUsage);
      assert.ok(Array.isArray(found), `${preset.id}/${check.id} findings`);
      // A check that found nothing must also be measuring nothing, and the other way round:
      // a cost with no finding is a fault nobody is told about.
      assert.equal(found.length > 0, cost > 0, `${preset.id}/${check.id} cost ${cost} vs ${found.length} findings`);
    }
  }
});

test('a finding names real slots, is worded, and has a stable unique id', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(presetParams(preset.id));
    const ids = new Set(palette.entries.map((e) => e.id));
    const findings = diagnose(palette, { verify: false });
    const seen = new Set();
    for (const f of findings) {
      assert.ok(f.title && f.detail, `${preset.id}: ${JSON.stringify(f)}`);
      assert.ok(SEVERITY_ORDER.includes(f.severity), `${preset.id}: severity ${f.severity}`);
      assert.ok(!seen.has(f.id), `${preset.id}: duplicate finding id ${f.id}`);
      seen.add(f.id);
      for (const id of f.entries) assert.ok(ids.has(id), `${preset.id}: ${f.id} names unknown slot ${id}`);
    }
    // Two runs over the same palette agree exactly — the card must not reshuffle on a repaint.
    assert.deepEqual(diagnose(palette, { verify: false }).map((f) => f.id), findings.map((f) => f.id));
  }
});

test('findings are ordered worst first', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(presetParams(preset.id));
    const findings = diagnose(palette, { verify: false });
    const ranks = findings.map((f) => SEVERITY_ORDER.indexOf(f.severity));
    assert.deepEqual(ranks, [...ranks].sort((a, b) => a - b), preset.id);
  }
});

// The property the whole module rests on: a fix is a claim that has been tested. This
// re-derives it independently of `verifiedFix` — apply the patch, regenerate, re-measure.
test('every offered fix measurably improves the finding it is attached to', () => {
  const cases = [
    ['defaults', defaultParams()],
    ['no minimum distance', { ...defaultParams(), min_delta_e: 0 }],
    ['greyscale 48', { ...defaultParams(), color_count: 48, chroma_base: 0 }],
    ['wide 64', { ...defaultParams(), color_count: 64, hue_count: 8 }],
    ...PRESETS.map((p) => [p.id, presetParams(p.id)]),
  ];
  let offered = 0;
  for (const [name, params] of cases) {
    const palette = generatePalette(params);
    for (const f of diagnose(palette)) {
      if (!f.fix) continue;
      offered++;
      assert.ok(Object.keys(f.fix.params).length > 0, `${name}/${f.id}: an empty patch is not a fix`);
      const check = CHECK_BY_ID.get(f.check);
      const before = check.metric(palette, noUsage);
      const after = check.metric(
        generatePalette({ ...palette.params, ...f.fix.params }, {
          locks: palette.locks, overrides: palette.overrides,
        }),
        noUsage,
      );
      assert.ok(after < before, `${name}/${f.id}: "${f.fix.label}" left ${before} at ${after}`);
      // …and by enough to be worth a button, not by a rounding error.
      assert.ok(after <= before * 0.75, `${name}/${f.id}: "${f.fix.label}" only moved ${before} → ${after}`);
    }
  }
  assert.ok(offered > 20, `expected the fixes to be exercised, got ${offered}`);
});

test('a fix patch never leaves the parameter schema', () => {
  for (const params of [{ ...defaultParams(), min_delta_e: 0 }, presetParams('neon-cyberpunk')]) {
    const palette = generatePalette(params);
    for (const f of diagnose(palette)) {
      if (!f.fix) continue;
      for (const [name, value] of Object.entries(f.fix.params)) {
        const spec = PARAM_BY_NAME.get(name);
        assert.ok(spec, `${f.id}: patch names unknown parameter ${name}`);
        assert.deepEqual(coerceParam(spec, value), value, `${f.id}: ${name} = ${value} is out of range`);
      }
    }
  }
});

test('turning the minimum distance off produces near-duplicate findings', () => {
  const palette = generatePalette({ ...defaultParams(), min_delta_e: 0 });
  const dupes = diagnose(palette, { verify: false }).filter((f) => f.check === 'duplicates');
  assert.ok(dupes.length > 0, 'a palette with no distance constraint has near-duplicates');
  for (const f of dupes) assert.equal(f.entries.length, 2);
  // …and the default palette, which asks for ΔE 4, does not.
  const clean = diagnose(generatePalette(defaultParams()), { verify: false });
  assert.equal(clean.filter((f) => f.check === 'duplicates').length, 0);
});

test('the threshold is absolute as well as relative', () => {
  // Even with the constraint turned off, a pair has to be genuinely close to be reported.
  const palette = generatePalette({ ...defaultParams(), min_delta_e: 0 });
  const check = CHECK_BY_ID.get('duplicates');
  for (const f of check.findings(palette, noUsage)) {
    const [a, b] = f.entries.map((id) => palette.entries.find((e) => e.id === id));
    const distance = Math.hypot(...a.lab.map((v, i) => v - b.lab[i])) * 100;
    assert.ok(distance < NEAR_DUPE_DE + 1e-9, `${f.id} at ΔE ${distance}`);
  }
});

test('an ordinary hand-tuned palette is not called faulty', () => {
  // The point of the measured thresholds: a diagnostic that fires on everything says nothing.
  // These four presets come back clean, and the rest average a handful of findings.
  for (const id of ['gameboy', 'c64', 'monochrome-ink', 'sepia-western']) {
    assert.deepEqual(diagnose(generatePalette(presetParams(id)), { verify: false }), [], id);
  }
  const counts = PRESETS.map((p) => diagnose(generatePalette(presetParams(p.id)), { verify: false }).length);
  assert.ok(Math.max(...counts) <= 8, `worst preset reported ${Math.max(...counts)} findings`);
});

test('unused colours are reported from the counts the caller passes in', () => {
  const palette = generatePalette(defaultParams());
  const usage = new Int32Array(palette.entries.length).fill(100);
  usage[3] = 0;
  usage[9] = 0;
  const findings = diagnose(palette, { usage, verify: false }).filter((f) => f.check === 'unused');
  assert.equal(findings.length, 1);
  assert.deepEqual(findings[0].entries, [palette.entries[3].id, palette.entries[9].id]);
  assert.match(findings[0].title, /^2 colours/);
  // Without counts the check is silent rather than guessing.
  assert.equal(diagnose(palette, { verify: false }).filter((f) => f.check === 'unused').length, 0);
});

test('the unused check can verify its own fix when given a way to re-count', () => {
  const palette = generatePalette(defaultParams());
  const check = CHECK_BY_ID.get('unused');
  const idle = (p) => {
    const u = new Int32Array(p.entries.length).fill(100);
    // Every slot above 30 is idle, so spending fewer colours genuinely removes idle slots.
    for (let i = 30; i < u.length; i++) u[i] = 0;
    return u;
  };
  const found = diagnose(palette, { usage: idle(palette), usageOf: idle });
  const unused = found.filter((f) => f.check === 'unused');
  assert.equal(unused.length, 1);
  assert.ok(unused[0].fix, 'a fix should be offered once the check can measure a candidate');
  const after = check.metric(
    generatePalette({ ...palette.params, ...unused[0].fix.params }),
    ctxWith(idle(generatePalette({ ...palette.params, ...unused[0].fix.params }))),
  );
  assert.ok(after < 2, `spending fewer colours should leave fewer idle slots, got ${after}`);
});

test('entryDivergence reports only chroma the generator asked for and did not get', () => {
  const palette = generatePalette({ ...defaultParams(), chroma_base: 0.37, chroma_cap: 0.37 });
  const flagged = palette.entries.map(entryDivergence).filter(Boolean);
  assert.ok(flagged.length > 0, 'asking for maximum chroma everywhere must clip somewhere');
  for (const d of flagged) {
    assert.ok(d.chromaLost > DIVERGENCE_C);
    assert.ok(d.requested > d.achieved);
    assert.match(d.note, /chroma reduced 0\.\d+ → 0\.\d+ to fit sRGB/);
  }
  // A greyscale palette asks for nothing sRGB cannot hold.
  const grey = generatePalette({ ...defaultParams(), chroma_base: 0, chroma_cap: 0.05 });
  assert.deepEqual(grey.entries.map(entryDivergence).filter(Boolean), []);
});

test('verify: false costs nothing and offers nothing', () => {
  const palette = generatePalette({ ...defaultParams(), min_delta_e: 0 });
  const findings = diagnose(palette, { verify: false });
  assert.ok(findings.length > 0);
  assert.deepEqual(findings.filter((f) => f.fix).map((f) => f.id), []);
});

test('summarizeFindings says how bad it is, or that it is fine', () => {
  assert.match(summarizeFindings([]), /Nothing to report/);
  const one = summarizeFindings([{ severity: 'high' }]);
  assert.match(one, /^1 finding · 1 high$/);
  const mixed = summarizeFindings([{ severity: 'low' }, { severity: 'high' }, { severity: 'high' }]);
  assert.match(mixed, /^3 findings · 2 high · 1 low$/);
});
