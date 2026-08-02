// The inline markdown every screen renders (Q19=a).
//
// One copy, imported by the question screen, the gap page and the canvas panel. It was three
// copies until 2026-08-02, and the canvas' was the one that had never had it applied — the
// assumptions panel showed `- **Qn**` and `**no backticked gate**` as literal asterisks, because
// it escaped and stopped there. Three copies of a renderer means two of them are wrong eventually.
//
// Inline only, deliberately: a question is one line of prose with code, bold and italics in it.
// Blocks, links and images are not in the grammar and are not rendered.

/**
 * The fence around a lifted code span. A private-use code point, written as an escape so this
 * file stays plain text: it cannot occur in a design document, and anything less exotic (a digit
 * between spaces, say) would match real prose and eat it.
 */
const FENCE = String.fromCharCode(0xE000);

/** Escape HTML. Always first — everything below re-inserts tags into this output on purpose. */
export function esc(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * Escape, then render inline markdown: `code`, **bold**, *italic*.
 *
 * Code spans are lifted out first and put back last, so `**` inside a code span stays literal —
 * the design documents are full of `**Qn**` written as code, and rendering that as bold is how a
 * grammar example stops looking like a grammar example.
 */
export function md(text) {
  const code = [];
  const safe = esc(text).replace(/`([^`]+)`/g, (_, body) => `${FENCE}${code.push(body) - 1}${FENCE}`);
  return safe
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>')
    .replace(new RegExp(`${FENCE}(\\d+)${FENCE}`, 'g'), (_, i) => `<code>${code[Number(i)]}</code>`);
}
