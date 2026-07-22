import test from 'node:test';
import assert from 'node:assert/strict';
import { EXPORTERS, EXPORTER_BY_ID, runExport } from '../src/core/export/index.js';
import { toGpl, parseGpl } from '../src/core/export/gpl.js';
import { toPal, parsePal } from '../src/core/export/pal.js';
import { toHex, parseHex } from '../src/core/export/hex.js';
import { toLospec, parseLospec } from '../src/core/export/lospec.js';
import { toCss, parseCss } from '../src/core/export/css.js';
import { toJson, parseJson } from '../src/core/export/json.js';
import { toTres, parseTres } from '../src/core/export/tres.js';
import { toPngStrip } from '../src/core/export/png.js';
import { decodePNG } from '../tools/png.mjs';
import { generatePalette, paletteHexes } from '../src/core/generate.js';
import { defaultParams } from '../src/core/params.js';
import { presetParams, PRESETS } from '../src/core/presets.js';
import { rgb8ToHex } from '../src/core/oklch.js';

const SIZES = [4, 5, 12, 16, 33, 64];

test('GPL round-trips to identical colours and carries role names', () => {
  for (const k of SIZES) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const parsed = parseGpl(toGpl(p, { name: 'Test Palette' }));
    assert.equal(parsed.name, 'Test Palette');
    assert.deepEqual(parsed.colors, paletteHexes(p), `K=${k}`);
    assert.deepEqual(parsed.names, p.entries.map((e) => e.role), `K=${k} role names`);
  }
  assert.throws(() => parseGpl('nope'), /not a GIMP palette/);
});

test('JASC PAL round-trips to identical colours', () => {
  for (const k of SIZES) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const text = toPal(p);
    assert.ok(text.startsWith('JASC-PAL\r\n0100\r\n'), 'header must use CRLF');
    assert.deepEqual(parsePal(text), paletteHexes(p), `K=${k}`);
  }
  assert.throws(() => parsePal('nope'), /not a JASC palette/);
  assert.throws(() => parsePal('JASC-PAL\n0100\n3\n1 2 3\n'), /expected 3 colours/);
});

test('hex and Lospec lists round-trip', () => {
  for (const k of SIZES) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    assert.deepEqual(parseHex(toHex(p)), paletteHexes(p), `hex K=${k}`);
    assert.deepEqual(parseLospec(toLospec(p)), paletteHexes(p), `lospec K=${k}`);
    assert.ok(!toLospec(p).includes('#'), 'Lospec output must not contain #');
  }
  assert.throws(() => parseHex('#12345'), /bad hex line/);
  assert.throws(() => parseLospec('zzzzzz'), /bad Lospec line/);
});

test('CSS custom properties carry every slot and every semantic role', () => {
  const p = generatePalette({ ...defaultParams(), color_count: 32 });
  const vars = parseCss(toCss(p));
  const byId = new Map(p.entries.map((e) => [e.id, e.hex]));
  for (const e of p.entries) {
    assert.equal(vars[`pal-${e.role.replace(/_/g, '-')}`], e.hex, e.role);
  }
  for (const [role, id] of Object.entries(p.semantics)) {
    assert.equal(vars[`pal-${role.replace(/_/g, '-')}`], byId.get(id), role);
  }
  assert.ok(toCss(p, { prefix: 'x', selector: '.pal' }).startsWith('.pal {'));
});

test('JSON round-trips colours, parameters, locks and overrides', () => {
  const base = { ...defaultParams(), color_count: 20 };
  const ids = generatePalette(base).entries.map((e) => e.id);
  const p = generatePalette(base, { locks: { [ids[2]]: '#FF8800' }, overrides: { [ids[7]]: '#224466' } });
  const parsed = parseJson(toJson(p, { name: 'Round Trip' }));
  assert.equal(parsed.name, 'Round Trip');
  assert.equal(parsed.seed, p.seed);
  assert.deepEqual(parsed.colors, paletteHexes(p));
  assert.deepEqual(parsed.locks, { [ids[2]]: '#FF8800' });
  assert.deepEqual(parsed.overrides, { [ids[7]]: '#224466' });
  assert.deepEqual(parsed.params, p.params);
  // And regenerating from the parsed JSON reproduces the palette exactly.
  const rebuilt = generatePalette(parsed.params, { locks: parsed.locks, overrides: parsed.overrides });
  assert.deepEqual(paletteHexes(rebuilt), paletteHexes(p));
  assert.throws(() => parseJson('{"format":"other"}'), /unexpected format/);
});

test('the .tres export is valid Godot resource syntax with matching colours', () => {
  for (const k of SIZES) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const text = toTres(p, { name: 'Godot Test' });
    const parsed = parseTres(text);
    assert.equal(parsed.count, k);
    assert.deepEqual(parsed.hexes, paletteHexes(p), `K=${k} hexes`);
    assert.deepEqual(parsed.colors.map(rgb8ToHex), paletteHexes(p), `K=${k} PackedColorArray`);
    assert.deepEqual(parsed.ids, p.entries.map((e) => e.id));
    assert.deepEqual(parsed.roles, p.entries.map((e) => e.role));
    // Every semantic role must point at a slot the file actually contains.
    for (const [role, id] of Object.entries(p.semantics)) {
      assert.ok(text.includes(`"${role}": "${id}"`), `missing semantic role ${role}`);
      assert.ok(parsed.ids.includes(id));
    }
    // Parentheses balance — a malformed literal would break Godot's parser.
    assert.equal((text.match(/\(/g) || []).length, (text.match(/\)/g) || []).length);
    assert.ok(!/[eE][+-]\d/.test(text), 'Godot floats must not use exponent notation');
  }
  assert.throws(() => parseTres('garbage'), /gd_resource header/);
});

test('the PNG strip decodes to exactly K pixels of the right colours', () => {
  for (const k of SIZES) {
    const p = generatePalette({ ...defaultParams(), color_count: k });
    const decoded = decodePNG(Buffer.from(toPngStrip(p)));
    assert.equal(decoded.width, k, `K=${k} width`);
    assert.equal(decoded.height, 1);
    for (let i = 0; i < k; i++) {
      const px = [decoded.rgb[i * 3], decoded.rgb[i * 3 + 1], decoded.rgb[i * 3 + 2]];
      assert.deepEqual(px, p.entries[i].rgb8, `K=${k} pixel ${i}`);
    }
  }
});

test('PNG strip scaling repeats each colour and keeps row order', () => {
  const p = generatePalette({ ...defaultParams(), color_count: 8 });
  const decoded = decodePNG(Buffer.from(toPngStrip(p, { cell: 6, height: 3 })));
  assert.equal(decoded.width, 48);
  assert.equal(decoded.height, 3);
  for (let y = 0; y < 3; y++) {
    for (let x = 0; x < 48; x++) {
      const i = (y * 48 + x) * 3;
      assert.deepEqual(
        [decoded.rgb[i], decoded.rgb[i + 1], decoded.rgb[i + 2]],
        p.entries[Math.floor(x / 6)].rgb8,
      );
    }
  }
});

test('the registry exposes every format and runExport dispatches correctly', () => {
  const p = generatePalette({ ...defaultParams(), color_count: 12 });
  const ids = EXPORTERS.map((e) => e.id);
  assert.deepEqual(
    ids.slice().sort(),
    ['css', 'gpl', 'hex', 'json', 'lospec', 'pal', 'png', 'tres'],
  );
  for (const exporter of EXPORTERS) {
    const out = runExport(exporter.id, p);
    assert.ok(exporter.extension && exporter.mime && exporter.label, exporter.id);
    if (exporter.binary) {
      assert.ok(out instanceof Uint8Array, `${exporter.id} should be binary`);
      assert.ok(out.length > 0);
    } else {
      assert.equal(typeof out, 'string', `${exporter.id} should be text`);
      assert.ok(out.length > 0);
      assert.ok(out.endsWith('\n'), `${exporter.id} should end with a newline`);
    }
    assert.equal(EXPORTER_BY_ID.get(exporter.id), exporter);
  }
  assert.throws(() => runExport('nope', p), /unknown export format/);
});

test('every preset exports cleanly in every format', () => {
  for (const preset of PRESETS) {
    const p = generatePalette(presetParams(preset.id));
    for (const exporter of EXPORTERS) {
      assert.doesNotThrow(() => runExport(exporter.id, p), `${preset.id} / ${exporter.id}`);
    }
    assert.deepEqual(parseGpl(toGpl(p)).colors, paletteHexes(p), preset.id);
    assert.deepEqual(parsePal(toPal(p)), paletteHexes(p), preset.id);
    assert.equal(parseTres(toTres(p)).count, p.entries.length, preset.id);
  }
});
