import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { PRESETS, presetParams } from '../src/core/presets.js';
import { defaultParams } from '../src/core/params.js';

const here = dirname(fileURLToPath(import.meta.url));
const SNAPSHOT_DIR = join(here, 'snapshots');
const ROOT = join(here, '..');

// Any algorithm change surfaces here as a diff. Review it, then re-record with:
//   UPDATE_SNAPSHOTS=1 npm test
const UPDATE = process.env.UPDATE_SNAPSHOTS === '1';

/** Read a golden snapshot, or write it when re-recording. */
function golden(name, produce) {
  const path = join(SNAPSHOT_DIR, `${name}.json`);
  if (UPDATE || !existsSync(path)) {
    mkdirSync(SNAPSHOT_DIR, { recursive: true });
    writeFileSync(path, `${JSON.stringify(produce(), null, 2)}\n`);
  }
  return JSON.parse(readFileSync(path, 'utf8'));
}

test('every preset matches its golden snapshot', () => {
  for (const preset of PRESETS) {
    const palette = generatePalette(presetParams(preset.id));
    const actual = { seed: palette.seed, colors: paletteHexes(palette) };
    const expected = golden(`preset-${preset.id}`, () => actual);
    assert.deepEqual(
      actual.colors, expected.colors,
      `preset "${preset.id}" changed — review the diff, then re-record with UPDATE_SNAPSHOTS=1`,
    );
    assert.equal(actual.seed, expected.seed, `preset "${preset.id}" seed changed`);
  }
});

test('the default palette matches its golden snapshot at several sizes', () => {
  const sizes = [4, 8, 12, 16, 24, 32, 48, 64];
  const actual = Object.fromEntries(sizes.map((k) => {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    return [k, paletteHexes(p)];
  }));
  const expected = golden('default-sizes', () => actual);
  for (const k of sizes) {
    assert.deepEqual(actual[k], expected[k], `K=${k} changed — re-record with UPDATE_SNAPSHOTS=1`);
  }
});

test('a fresh process produces byte-identical output', () => {
  const script = `
    import { generatePalette, paletteHexes } from './src/core/generate.js';
    import { presetParams } from './src/core/presets.js';
    const out = {};
    for (const id of ['snes', 'neon-cyberpunk', 'gameboy', 'monochrome-ink']) {
      const p = generatePalette(presetParams(id));
      out[id] = { seed: p.seed, colors: paletteHexes(p) };
    }
    process.stdout.write(JSON.stringify(out));
  `;
  const raw = execFileSync(process.execPath, ['--input-type=module', '-e', script], {
    cwd: ROOT,
    encoding: 'utf8',
  });
  const fromChild = JSON.parse(raw);
  for (const [id, child] of Object.entries(fromChild)) {
    const local = generatePalette(presetParams(id));
    assert.deepEqual(child.colors, paletteHexes(local), `${id} differs across processes`);
    assert.equal(child.seed, local.seed, `${id} seed differs across processes`);
  }
});

test('snapshots cover every preset', () => {
  for (const preset of PRESETS) {
    assert.ok(
      existsSync(join(SNAPSHOT_DIR, `preset-${preset.id}.json`)),
      `preset "${preset.id}" has no snapshot`,
    );
  }
});
