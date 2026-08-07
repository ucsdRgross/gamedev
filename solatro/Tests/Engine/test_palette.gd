extends TestSuite
# res://Tests/Engine/test_palette.gd
# Universal-palette suite (ARCHITECTURE_REVIEW §4i, FX_SHADER_PLAN T21).
#
# The point of the feature is that EVERY colour resolves to a palette entry and reassigning one is
# editing a single named role. Two things can quietly break that, and both are checked here rather
# than left to review:
#   * a role pointing outside the palette (survives as a clamped wrong colour, looks deliberate);
#   * a ramp producing an in-between colour (the old fire ramp had 64 colours, ZERO of them palette
#     entries, precisely because its bands were interpolated).
#
# ⚠ This suite emits TWO DELIBERATE push_errors ("Palette index -5 / 131 out of range — clamped")
# while proving the clamp path reports rather than crashing. Like LEAK CANARY's, they are expected
# noise in test_output_errors.log; the verdict is the FAIL lines and the banner.
#
# CATEGORY MAP (see TestSuite):
#   BEHAVIOR — roles resolve, ramps are on-palette, a palette swap moves every colour. These are the
#     promises the feature makes to the game.
#   IMPLEMENTATION — width comes from the image, out-of-range is reported not silent, the roles
#     resource previews against the SAME palette the game draws with.

func suite_name() -> String:
	return "PALETTE"

func _ready() -> void:
	TestLog.line("============ UNIVERSAL PALETTE TEST PASS ============")
	run_palette_tests()
	run_role_tests()
	run_ramp_tests()
	run_swap_tests()
	run_drift_scan()
	finish()


# ==============================================================================
# 1. THE PALETTE ITSELF
# ==============================================================================

func run_palette_tests() -> void:
	implementation_section("PALETTE — width and lookup come from the image")
	var w := PaletteDB.width()
	check(w > 0, "palette has entries", "width=%d" % w)
	check(w == PaletteDB.PALETTE.texture.get_image().get_width(),
			"width() is the texture width, not a written-down number", "width=%d" % w)
	check_behavior(w >= 32, "palette is at least 32 wide (owner: it never shrinks below 32)",
			"width=%d" % w)

	# Out of range is a BUG, not a crash: reported and clamped, never a silent wrong colour.
	#
	# ⚠ THE TWO `push_error`s THESE PRINT ARE THE BEHAVIOUR UNDER TEST, NOT A FAILURE — "Palette index
	# -5 out of range 0..31 — clamped", then 131. `Palette.color` REPORTS and clamps rather than
	# returning a silent wrong colour or crashing on load, so pinning that contract necessarily writes
	# to stderr. Same status as LEAK CANARY's deliberate sentinel report, and called out in the check
	# text for the same reason: an unexplained error in a green run is what teaches people to stop
	# reading the log. ⚠ Neither reaches `test_output_errors.log` — that is the suite's OWN channel and
	# stays empty, which is what keeps "empty = green" true (HEADLESS_TESTING §0).
	check(PaletteDB.color(0) == PaletteDB.color(-5),
			"a negative index clamps to the first entry (the push_error above is deliberate)")
	check(PaletteDB.color(w - 1) == PaletteDB.color(w + 99),
			"a past-the-end index clamps to the last entry (the push_error above is deliberate)")

	var cols := PaletteDB.PALETTE.colors()
	check(cols.size() == w, "colors() returns one entry per texel", "%d" % cols.size())


# ==============================================================================
# 2. ROLES — the resource of pointers
# ==============================================================================

func run_role_tests() -> void:
	behavior_section("ROLES — every role resolves inside the palette")
	var w := PaletteDB.width()
	var roles := PaletteDB.ROLES
	for role : StringName in PaletteRoles.ROLE_NAMES:
		var idx : int = roles.index_of(role)
		check(idx >= 0 and idx < w, "role %s in range" % role, "index=%d width=%d" % [idx, w])

	implementation_section("ROLES — bookkeeping")
	# There is no "roles preview against the SAME palette the game draws with" check any more, and its
	# removal is the point rather than a loss of coverage: PaletteRoles and PaletteRamp each used to hold
	# their own `palette` pointer, so the preview and the game were two facts that a test had to pin
	# together. Both now read PaletteDB.PALETTE, so they are one fact and there is nothing left to drift
	# — including on the three ramps, whose pointers this check never covered.
	# A role declared but left out of ROLE_NAMES would never be range-checked again.
	var declared := 0
	for prop : Dictionary in roles.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.type == TYPE_INT:
			declared += 1
	check(declared == PaletteRoles.ROLE_NAMES.size(),
			"every declared role int is listed in ROLE_NAMES",
			"declared=%d listed=%d" % [declared, PaletteRoles.ROLE_NAMES.size()])

	# Suits keep the indices they shipped with — this step was a rename, not a recolour.
	check(roles.suit_hoop == 30 and roles.suit_knife == 11 and roles.suit_ball == 8
			and roles.suit_fire == 2 and roles.suit_firework == 14,
			"suit roles still hold the pre-T21 indices [30, 11, 8, 2, 14]")


# ==============================================================================
# 3. RAMPS — the whole point: SAMPLED, never lerped
# ==============================================================================

func run_ramp_tests() -> void:
	behavior_section("RAMPS — every colour a ramp emits is exactly a palette entry")
	var entries := PaletteDB.PALETTE.colors()
	var ramps : Array[PaletteRamp] = [PaletteDB.RAMP_FIRE, PaletteDB.RAMP_BALL, PaletteDB.RAMP_EMBER]
	var names : Array[String] = ["ramp_fire", "ramp_ball", "ramp_ember"]
	var w := PaletteDB.width()
	for i : int in range(ramps.size()):
		var ramp := ramps[i]
		check(ramp.size() > 0, "%s has entries" % names[i])
		var in_range := true
		for idx : int in ramp.indices:
			if idx < 0 or idx >= w: in_range = false
		check(in_range, "%s indices all inside the palette" % names[i], str(ramp.indices))

	# The fire ramp built the way FxStyle builds it: every opaque pixel must BE a palette entry.
	var tex := PaletteDB.RAMP_FIRE.window_texture(4, 16, PackedFloat32Array(), 0.18)
	check(tex != null, "fire ramp texture builds")
	if tex:
		var img := tex.get_image()
		var bad := 0
		var transparent := 0
		for y : int in range(img.get_height()):
			for x : int in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if c.a <= 0.0:
					transparent += 1
					continue
				if not _is_entry(c, entries): bad += 1
		check(bad == 0, "every opaque fire-ramp pixel is exactly a palette entry",
				"%d off-palette pixels" % bad)
		check(transparent > 0, "the ramp keeps its transparent cut (the ragged flame outline)",
				"%d transparent pixels" % transparent)

	# The window SLIDES: a high stack level must reach hotter entries than a low one, or the
	# level axis would be decoration.
	if tex:
		var img := tex.get_image()
		check_behavior(img.get_pixel(img.get_width() - 1, 0)
				!= img.get_pixel(img.get_width() - 1, img.get_height() - 1),
				"the hot end differs between the lowest and highest stack level")

	# Ball tones: one texel per band, sampled by the shader — no mix() between two endpoints.
	var tones := PaletteDB.RAMP_BALL.tones_texture()
	check(tones != null, "ball tones texture builds")
	if tones:
		var img := tones.get_image()
		check(img.get_width() == PaletteDB.RAMP_BALL.size(),
				"one texel per ball band", "%d" % img.get_width())
		var bad := 0
		for x : int in range(img.get_width()):
			if not _is_entry(img.get_pixel(x, 0), entries): bad += 1
		check(bad == 0, "every ball tone is exactly a palette entry", "%d off-palette" % bad)


# ==============================================================================
# 4. THE SWAP TEST — does a different palette actually move every colour?
# ==============================================================================

func run_swap_tests() -> void:
	behavior_section("SWAP — a different palette moves every role")
	var w := PaletteDB.width()
	var img := Image.create_empty(w, 1, false, Image.FORMAT_RGBA8)
	for i : int in range(w):
		# Deliberately unlike the live palette: a pure blue-green ramp.
		img.set_pixel(i, 0, Color(0.0, float(i) / float(w), 1.0 - float(i) / float(w)))
	var swapped := Palette.new()
	swapped.texture = ImageTexture.create_from_image(img)

	check(swapped.width() == w, "the swapped palette reports its own width", "%d" % swapped.width())
	var moved := 0
	for role : StringName in PaletteRoles.ROLE_NAMES:
		var idx : int = PaletteDB.ROLES.index_of(role)
		if not swapped.color(idx).is_equal_approx(PaletteDB.color(idx)): moved += 1
	check(moved == PaletteRoles.ROLE_NAMES.size(),
			"every role resolves to a different colour under a different palette",
			"%d of %d moved" % [moved, PaletteRoles.ROLE_NAMES.size()])

	# A ramp follows the palette too — the indices are the pointer, the colours are not stored. Swapping
	# means moving the ONE storage slot every reader shares, which is why PaletteDB.PALETTE is a static
	# var and not a const (palette_db.gd:17-22); a ramp has no palette pointer of its own to set.
	var live_cols := PaletteDB.RAMP_FIRE.colors()
	var original := PaletteDB.PALETTE
	PaletteDB.PALETTE = swapped
	var swapped_cols := PaletteDB.RAMP_FIRE.colors()
	PaletteDB.PALETTE = original
	check(PaletteDB.PALETTE == original, "the swap test put the live palette back")
	check(swapped_cols.size() == live_cols.size(), "the swapped ramp has the same length")
	check(swapped_cols != live_cols, "the swapped ramp resolves to different colours")


# ==============================================================================
# 5. ANTI-DRIFT SCAN — warnings, never failures
# ==============================================================================
#
# The only thing that stops a colour literal creeping back in. It reports rather than fails (owner
# ruling): a WARN says "this surface is still a placeholder", which is true of the map and the UI
# chrome today — their art is being redrawn, and they were deliberately left OFF the allowlist so
# they keep saying so every run.

## Directories whose drawing code is expected to be on the palette.
## ⚠ `res://tools` IS IN THE LIST DELIBERATELY. The tuning editors used to live under `res://Cards`
## and `res://UI` and were scanned as a side effect of sitting there; consolidating them into one
## folder (owner, 2026-08-04) would otherwise have dropped them out of the scan silently, which is
## the kind of coverage loss a green run cannot show you.
## ⚠ **LOWERCASE `tools`, MATCHING THE DIRECTORY ON DISK.** It read `res://Tools`, which resolves on a
## case-insensitive filesystem but makes every path this scan yields disagree with `ALLOW_FILES`
## below — so the exemptions silently stopped matching and six exempt files started warning again.
## The whole project was normalised to the on-disk case on 2026-08-06 (see below).
const SCAN_DIRS : Array[String] = [
	"res://Cards", "res://Scripts", "res://UI", "res://Levels", "res://Shaders", "res://tools",
]
const SCAN_EXTS : Array[String] = ["gd", "tscn", "tres"]

## Files exempt entirely, with the reason. Editor/debug tooling and art that does not exist yet.
const ALLOW_FILES : Array[String] = [
	"res://tools/formation_editor.gd",                 # @tool debug overlay, never shipped
	# @tool review surface, never shipped. Its colours are the BACKDROPS an authored outline ink is
	# judged against, plus its own label chrome — deliberately arbitrary and deliberately editable,
	# since the whole point of the tool is holding an ink up against more than one background.
	"res://tools/outline_atlas.gd",
	"res://Cards/Props/Visuals/firework_visual.gd",    # placeholder polygon; no art authored
	"res://Scripts/palette.gd",                        # the palette machinery itself
	"res://Scripts/palette_ramp.gd",
	"res://Scripts/palette_roles.gd",
	"res://Scripts/palette_db.gd",
]

## Line fragments that are not colour CHOICES: >1 modulate multipliers are a brightness operation,
## set_pixel packs data into an image, and a bare WHITE is the IDENTITY of a tint (no recolour at
## all), not a colour picked off any palette. None of these can be a palette entry.
const ALLOW_LINES : Array[String] = [
	"modulate = Color(1.825", "modulate = Color(1.0, 1.0, 1.0)", "modulate = Color(2, 2, 2, 1)",
	"quad.modulate = Color(1.0, 1.0, 1.0, 0.0)", "img.set_pixel(",
	"\"modulate\", Color.WHITE",                       # tween back to no tint
	"else Color.WHITE", "return Color.WHITE",          # untinted fallbacks (no ramp = no tint)
	"@export var color : Color = Color.WHITE",         # untinted default; set by the visual
	"color = Color(0, 0, 0, 0)",                       # fully transparent = NO colour at all
	# ⚠ **THE LIGHT LAYER'S OFF-PALETTE EXCEPTION — GRANTED ONCE, SCOPED HERE, DOES NOT TRAVEL.**
	# `DESIGN.md` v8 / GAP-003: `Q134`=(b) *"light gets freedom to use off-palette colour from the
	# start"* and `Q135`=(b) *"an off-palette exception for the light layer only"*. Light is the ONLY
	# thing in this game outside the palette contract. These two are allowlisted BY NAME rather than
	# by file, so any OTHER colour appearing in the spotlight style still trips the scan.
	"var dim_color : Color", "dim_color = Color(",
	"var light_color : Color", "light_color = Color(",
]

func run_drift_scan() -> void:
	behavior_section("DRIFT — colours still hardcoded outside the palette")
	var hits : Array[String] = []
	for path : String in _scan_files():
		if path in ALLOW_FILES: continue
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty(): continue
		var lines := text.split("\n")
		for i : int in range(lines.size()):
			var line := lines[i]
			if not ("Color(" in line or "Color." in line): continue
			if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"): continue
			var allowed := false
			for frag : String in ALLOW_LINES:
				if frag in line: allowed = true
			if allowed: continue
			hits.append("%s:%d  %s" % [path, i + 1, line.strip_edges()])
	for hit : String in hits:
		warn(false, "hardcoded colour", hit)
	# One summary line so a clean scan is visible in the log rather than silent.
	warn(hits.is_empty(), "every in-scope colour resolves through PaletteDB",
			"%d placeholder(s) still to migrate (map + UI chrome are deferred by design)"
			% hits.size())

## Every scannable file under SCAN_DIRS. Flat stack walk, no recursion (coding charter).
func _scan_files() -> Array[String]:
	var out : Array[String] = []
	var stack : Array[String] = SCAN_DIRS.duplicate()
	while not stack.is_empty():
		var dir_path : String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if not dir: continue
		for sub : String in dir.get_directories():
			stack.append(dir_path.path_join(sub))
		for file : String in dir.get_files():
			if file.get_extension() in SCAN_EXTS:
				out.append(dir_path.path_join(file))
	return out


## Is `c` exactly one of the palette's entries? Alpha is ignored: the recolour path replaces RGB only.
func _is_entry(c : Color, entries : PackedColorArray) -> bool:
	for e : Color in entries:
		if is_equal_approx(c.r, e.r) and is_equal_approx(c.g, e.g) and is_equal_approx(c.b, e.b):
			return true
	return false
