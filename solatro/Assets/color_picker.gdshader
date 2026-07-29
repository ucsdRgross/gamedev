shader_type canvas_item;
// THE RECOLOUR SHADER — replaces a polygon's RGB with one entry of the universal palette, while the
// polygon's own texture supplies the ALPHA. That is why it may only be used on SUIT-AGNOSTIC art
// (rank pips, card art): it flattens whatever it touches to one flat colour, which would destroy the
// shading already painted into suit_pips.png (ARCHITECTURE_REVIEW §4h).
//
// Replaced the VisualShader version in T21. The old one sampled a palette texture BAKED INTO ITSELF,
// so swapping Assets/Palette/circus_crayon.tres recoloured nothing here — the palette-swap snapshot
// (prop_art_snapshot 16_palette_swap) came back pixel-identical and proved it. The image now arrives
// as a uniform from PaletteDB, so there is exactly ONE place that says which palette the game uses.
//
// filter_nearest, repeat_disable: entries are single texels and must not blend into their neighbours.
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
// Which entry to use — a palette INDEX, pushed from a named role (PipSuit.palette_role()).
uniform int color_x : hint_range(0, 255) = 0;
// The palette's width, pushed from the IMAGE (PaletteDB.width()). It used to be a shader default
// kept in sync with the PNG by hand, which is the duplication T21 removed.
uniform int num_colors = 32;

void fragment() {
	// + 0.5 lands on the CENTRE of entry color_x rather than its left edge.
	COLOR.rgb = texture(palette, vec2((float(color_x) + 0.5) / float(num_colors), 0.5)).rgb;
}
