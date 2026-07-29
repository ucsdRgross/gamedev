@tool
class_name PaletteDB
## The one place the game's palette and its role map are named. STATICS, deliberately not an autoload
## (owner 2026-07-28: *"autoload seems kind of overkill and has bad code smell ... don't expect colors
## or ramps to change at runtime"*):
##
##   * nothing here changes while the game runs, so there is no state to hold and no signal to emit;
##   * the FX hosts and the formation editor are @tool scripts, which run with NO autoloads — the
##     precedent trap in ARCHITECTURE_REVIEW §4g;
##   * `const preload` resolves at parse time, so these can never be null and no call site needs a
##     null-check (owner: *"should never be null if stuff is working right"*).
##
## Reassigning ONE colour: edit that role in roles.tres. Swapping the WHOLE palette: point
## circus_crayon.tres at another N x 1 image (or repoint PALETTE here). Nothing else in the project
## stores a colour value or a palette width. See ARCHITECTURE_REVIEW §4i.

## STATIC VAR, not a const, and deliberately: a `const` resource reference is resolved per reading
## script, so mutating the object through one reference is NOT visible through `PaletteDB.PALETTE`
## elsewhere — the palette-swap snapshot came back unchanged and proved it. A static var is one
## storage slot every reader shares. It is still initialised once from disk and never assigned during
## normal play (the owner's "no runtime palette swapping"); the swap SNAPSHOT is the one thing that
## assigns it, and it puts the original back.
static var PALETTE : Palette = preload("res://Assets/Palette/circus_crayon.tres")
const ROLES : PaletteRoles = preload("res://Assets/Palette/roles.tres")

## Ordered ramps. Effects take a sliding WINDOW of one of these rather than lerping between colours.
const RAMP_FIRE : PaletteRamp = preload("res://Assets/Palette/ramp_fire.tres")
const RAMP_BALL : PaletteRamp = preload("res://Assets/Palette/ramp_ball.tres")
const RAMP_EMBER : PaletteRamp = preload("res://Assets/Palette/ramp_ember.tres")

## The colour at a palette index — normally `PaletteDB.color(PaletteDB.ROLES.status_flame)`.
static func color(index : int) -> Color:
	return PALETTE.color(index)

## How many entries the live palette has, from the IMAGE. This is what feeds color_picker.gdshader's
## `num_colors`, which used to be a hand-kept shader default (ARCHITECTURE_REVIEW §4h).
static func width() -> int:
	return PALETTE.width()
