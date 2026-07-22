// Standalone single-file build (PLAN §7). Inlines index.html, the stylesheet and the
// whole ES-module graph into one double-clickable dist/palette_creator.html.
//
// The "trivial inliner": every module is walked once from the entry point, its relative
// import specifiers are rewritten to unique bare keys (`mod:src/core/oklch.js`), and each
// module is embedded as a base64 `data:` URL in a document-level import map. Because the
// rewritten imports are bare specifiers the import map resolves — not relative paths a
// data: URL cannot resolve — the graph loads natively with no bundler runtime, and each
// module is encoded exactly once (no nesting blow-up).
//
// Seed strings and export/import work in the standalone file; file-backed saves do not,
// because there is no dev server behind /api/saves — the app degrades gracefully.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, relative, posix } from 'node:path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ENTRY = 'src/ui/app.js';
const KEY = (relPath) => `mod:${relPath.split('\\').join('/')}`;

// Matches `from '...'`, side-effect `import '...'`, and `export ... from '...'`.
const SPECIFIER_RE = /(\bfrom\s*|\bimport\s*)(['"])([^'"]+)\2/g;

/** Repo-relative POSIX path for a module file. */
function relKey(absPath) {
  return relative(ROOT, absPath).split('\\').join('/');
}

/** Resolve a relative import specifier against the importing file to a repo-relative key. */
function resolveSpecifier(fromAbs, spec) {
  const abs = resolve(dirname(fromAbs), spec);
  return relKey(abs);
}

/** Walk the module graph from the entry, returning { key -> rewritten source }. */
async function collectModules() {
  const seen = new Map();
  const queue = [join(ROOT, ENTRY)];
  while (queue.length) {
    const abs = queue.shift();
    const key = relKey(abs);
    if (seen.has(key)) continue;
    const src = await readFile(abs, 'utf8');
    const deps = [];
    const rewritten = src.replace(SPECIFIER_RE, (match, kw, quote, spec) => {
      if (!spec.startsWith('.')) return match; // bare/non-relative: leave untouched
      const depKey = resolveSpecifier(abs, spec);
      deps.push(join(ROOT, depKey));
      return `${kw}${quote}${KEY(depKey)}${quote}`;
    });
    seen.set(key, rewritten);
    queue.push(...deps);
  }
  return seen;
}

/** Encode a module source string as a base64 JavaScript data: URL. */
function dataUrl(src) {
  return `data:text/javascript;base64,${Buffer.from(src, 'utf8').toString('base64')}`;
}

async function build() {
  const html = await readFile(join(ROOT, 'index.html'), 'utf8');
  const css = await readFile(join(ROOT, 'src/style.css'), 'utf8');
  const modules = await collectModules();

  const importMap = { imports: {} };
  for (const [key, src] of modules) importMap.imports[KEY(key)] = dataUrl(src);

  const loader =
    `<script type="importmap">\n${JSON.stringify(importMap, null, 0)}\n</script>\n`
    + `  <script type="module">import ${JSON.stringify(KEY(ENTRY))};</script>`;

  let out = html
    // Inline the stylesheet.
    .replace(
      /<link[^>]*rel=["']stylesheet["'][^>]*href=["']src\/style\.css["'][^>]*>/,
      `<style>\n${css}\n</style>`,
    )
    // Replace the module <script src> with the import map + entry import.
    .replace(
      /<script[^>]*type=["']module["'][^>]*src=["']src\/ui\/app\.js["'][^>]*><\/script>/,
      loader,
    );

  if (out === html || !out.includes('importmap')) {
    throw new Error('inliner did not find the stylesheet or module script tag to replace');
  }

  const distDir = join(ROOT, 'dist');
  await mkdir(distDir, { recursive: true });
  const outPath = join(distDir, 'palette_creator.html');
  await writeFile(outPath, out, 'utf8');

  const bytes = Buffer.byteLength(out, 'utf8');
  process.stdout.write(
    `built ${posix.join('dist', 'palette_creator.html')} — ${modules.size} modules, `
    + `${(bytes / 1024).toFixed(0)} KB\n`,
  );
  return outPath;
}

build().catch((err) => {
  process.stderr.write(`build failed: ${err.message}\n`);
  process.exitCode = 1;
});
