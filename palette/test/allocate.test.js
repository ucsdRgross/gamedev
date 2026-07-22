import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveHueCount, effectiveHueCount, allocate, buildSlots } from '../src/core/allocate.js';
import { defaultParams } from '../src/core/params.js';

const PRIORITIES = ['standard', 'background-first', 'neutrals-first', 'ramps-first'];

test('derived hue count matches the published table', () => {
  const expect = [
    [4, 1], [7, 1], [8, 2], [11, 2], [12, 3], [15, 3], [16, 4], [23, 4],
    [24, 5], [39, 5], [40, 6], [55, 6], [56, 8], [64, 8],
  ];
  for (const [k, n] of expect) assert.equal(deriveHueCount(k), n, `K=${k}`);
});

test('manual hue count overrides the derived value', () => {
  assert.equal(effectiveHueCount({ ...defaultParams(), color_count: 32, hue_count: 0 }), 5);
  assert.equal(effectiveHueCount({ ...defaultParams(), color_count: 32, hue_count: 2 }), 2);
  // Never ask for more hues than there are slots left after the anchors.
  assert.equal(effectiveHueCount({ ...defaultParams(), color_count: 4, hue_count: 8 }), 2);
});

test('allocation totals exactly K for every budget and priority', () => {
  for (let k = 4; k <= 64; k++) {
    for (const priority of PRIORITIES) {
      for (const hueOverride of [0, 1, 3, 8]) {
        for (const fgLen of [2, 3, 5]) {
          for (const split of [false, true]) {
            const p = {
              ...defaultParams(),
              color_count: k, tier_priority: priority, hue_count: hueOverride,
              fg_ramp_length: fgLen, neutral_split: split,
            };
            const plan = allocate(p);
            assert.equal(plan.total, k, `K=${k} ${priority} hues=${hueOverride} fg=${fgLen}`);
            assert.equal(buildSlots(plan).length, k, `slot expansion for K=${k}`);
          }
        }
      }
    }
  }
});

test('allocation totals exactly K across the whole parameter surface', () => {
  for (let k = 4; k <= 64; k += 1) {
    for (const neutrals of [0, 3, 6]) {
      for (const accents of [0, 4]) {
        for (const bgLen of [1, 3]) {
          const p = {
            ...defaultParams(),
            color_count: k, neutral_count: neutrals, accent_count: accents, bg_ramp_length: bgLen,
          };
          assert.equal(allocate(p).total, k, `K=${k} n=${neutrals} a=${accents} bg=${bgLen}`);
        }
      }
    }
  }
});

test('worked budgets from the plan reproduce exactly', () => {
  const base = defaultParams();

  const k4 = allocate({ ...base, color_count: 4 });
  assert.equal(k4.hueCount, 1);
  assert.deepEqual(k4.fgLen, [2]);
  assert.deepEqual(k4.bgLen, [0]);
  assert.equal(k4.neutrals + k4.accents + k4.bridges, 0);

  const k8 = allocate({ ...base, color_count: 8 });
  assert.equal(k8.hueCount, 2);
  assert.deepEqual(k8.fgLen, [3, 3]);

  const k12 = allocate({ ...base, color_count: 12 });
  assert.equal(k12.hueCount, 3);
  assert.deepEqual(k12.fgLen, [3, 3, 3]);
  assert.equal(k12.neutrals, 1);

  const k16 = allocate({ ...base, color_count: 16 });
  assert.deepEqual(k16.fgLen, [3, 3, 3, 3]);
  assert.equal(k16.neutrals, 2);

  const k32 = allocate({ ...base, color_count: 32 });
  assert.equal(k32.hueCount, 5);
  assert.deepEqual(k32.fgLen, [3, 3, 3, 3, 3]);
  assert.deepEqual(k32.bgLen, [2, 2, 2, 2, 2]);
  assert.equal(k32.neutrals, 3);
  assert.equal(k32.accents, 2);
  assert.equal(k32.bridges, 0);
});

test('leftover budget deepens structure instead of spraying accents', () => {
  const p = { ...defaultParams(), color_count: 64, accent_count: 2 };
  const plan = allocate(p);
  assert.equal(plan.accents, 2, 'accents must stay at the requested count');
  const fgTotal = plan.fgLen.reduce((a, b) => a + b, 0);
  assert.ok(fgTotal > 24, `deepening should lengthen ramps, fg total was ${fgTotal}`);
  // Accent count never exceeds what the user asked for, at any budget.
  for (let k = 4; k <= 64; k++) {
    const q = allocate({ ...defaultParams(), color_count: k, accent_count: 1 });
    assert.ok(q.accents <= 1, `K=${k} sprayed ${q.accents} accents`);
  }
});

test('ramp caps are respected until deepening begins', () => {
  for (let k = 4; k <= 24; k++) {
    const plan = allocate({ ...defaultParams(), color_count: k, fg_ramp_length: 2, bg_ramp_length: 1 });
    assert.equal(plan.total, k);
    // With small budgets the caps hold; the deepening loop only runs once the rounds
    // are exhausted, and there is nothing left over at these sizes with 3 neutrals.
    if (k <= 12) {
      for (const len of plan.fgLen) assert.ok(len <= 2, `fg ramp grew to ${len} at K=${k}`);
    }
  }
});

test('slot ids are unique and ordered by role', () => {
  for (const k of [4, 12, 32, 64]) {
    const slots = buildSlots(allocate({ ...defaultParams(), color_count: k, neutral_split: true }));
    const ids = slots.map((s) => s.id);
    assert.equal(new Set(ids).size, ids.length, `duplicate slot id at K=${k}`);
    assert.equal(ids[0], 'universal_dark');
    assert.equal(ids[ids.length - 1], 'universal_light');
    const rank = { anchor: 0, fg: 1, bridge: 2, neutral: 3, 'neutral-warm': 4, bg: 5, accent: 6 };
    let last = -1;
    for (const s of slots.slice(1, -1)) {
      assert.ok(rank[s.layer] >= last, `layer ${s.layer} out of order at K=${k}`);
      last = rank[s.layer];
    }
  }
});

test('slot ordering is stable when unrelated parameters change', () => {
  const a = buildSlots(allocate({ ...defaultParams(), color_count: 32, root_hue: 0 })).map((s) => s.id);
  const b = buildSlots(allocate({ ...defaultParams(), color_count: 32, root_hue: 300, chroma_base: 0.3 }))
    .map((s) => s.id);
  assert.deepEqual(a, b);
});
