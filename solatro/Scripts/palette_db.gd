@tool
class_name PaletteDB
## The one place the game's palette and its role map are named.

#STATICS, deliberately not an autoload (owner: *"autoload seems kind of overkill and has bad code
#smell ... don't expect colors or ramps to change at runtime"*). Nothing here changes while the
#game runs, so there is no state to hold and no signal to emit.

#The FX hosts and the formation editor are @tool scripts, which run with NO autoloads. `const
#preload` resolves at parse time, so these can never be null and no call site needs a null-check
#(owner: *"should never be null if stuff is working right"*).

#Reassigning ONE colour means editing that role in roles.tres; swapping the WHOLE palette means
#pointing circus_crayon.tres at another N x 1 image, or repointing PALETTE here. Nothing else in
#the project stores a colour value or a palette width.

#⚠ A STATIC VAR, NOT A CONST. A const resource reference is resolved per reading script, so
#mutating the object through one reference is not visible through PaletteDB.PALETTE elsewhere; a
#static var is one storage slot every reader shares.

#It is still initialised once from disk and never assigned during normal play, the owner's "no
#runtime palette swapping". The swap SNAPSHOT is the one thing that assigns it, and it puts the
#original back.
static var PALETTE : Palette = preload("res://Assets/Palette/circus_crayon.tres")
const ROLES : PaletteRoles = preload("res://Assets/Palette/roles.tres")

## Ordered ramps. Effects take a sliding WINDOW of one of these rather than lerping between colours.
const RAMP_FIRE : PaletteRamp = preload("res://Assets/Palette/ramp_fire.tres")
const RAMP_BALL : PaletteRamp = preload("res://Assets/Palette/ramp_ball.tres")
const RAMP_EMBER : PaletteRamp = preload("res://Assets/Palette/ramp_ember.tres")
## The activated match rim's drift, and the ONE ramp that is blended rather than sampled (owner).
const RAMP_MATCH : PaletteRamp = preload("res://Assets/Palette/ramp_match.tres")

## The colour at a palette index — normally `PaletteDB.color(PaletteDB.ROLES.status_flame)`.
static func color(index : int) -> Color:
	return PALETTE.color(index)

#This is what feeds outline.gdshader's `u_num_colors`, so no shader carries a hand-kept default.

## How many entries the live palette has, from the IMAGE.
static func width() -> int:
	return PALETTE.width()
