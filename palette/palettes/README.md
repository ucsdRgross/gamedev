# Your target palettes

Drop a **palette image** here — a horizontal strip of swatches, a lospec-style 1px strip, or
even a whole art piece you want to borrow the colours from — and it becomes a **"Recolour
into"** target on the Recolour tab. Your reference images then get re-rendered in *that*
palette instead of the generated one.

You can drop files onto the tab, use "Add palette…", or copy files in here and hit "Rescan".

How colours are read out of the image (`src/core/recolor/swatches.js`):

- **A 1-or-2px-tall strip is treated as authoritative** — every distinct colour is used, in
  left-to-right order, nothing merged or dropped, white end-blocks kept. This is the clean
  input; a lospec `.png` is exactly this shape.
- **Anything taller** is de-aliased first: near-duplicate/compression noise is merged, and the
  thin blended pixels along swatch edges are dropped by a coverage floor. Wide swatches read
  cleanly; a strip with very narrow swatches may leak a seam or two — prefer the 1px form.

Unlike the generated palette, an external target does **not** change when you move the
parameter sliders — which is the way to keep a reference recolour fixed while you tune.
