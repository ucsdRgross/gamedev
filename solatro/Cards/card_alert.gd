@tool
class_name CardAlert
extends RefCounted
## ONE OUTLINE ALERT a status is asking its card to run - the *this card is about to act* nudge. Built
## in `CardModifierStatus.alert_request()`, mirroring `FxRequest`: the status owns its own presentation,
## so `CardVisual` never learns which alerts exist.
##
## ⚠ **AN ALERT IS A MODE, NOT A COLOUR** (owner 2026-08-04). What makes it read as an alert is that it
## MOVES, so it stays distinguishable whatever colour it lands on - which is why the outline's
## readability guarantee is never traded away to get attention.
##
## ⚠ **EVERY FIELD BELOW DEFAULTS TO THE SENTINEL -1 AND RESOLVES AT PUSH TIME**, against the card's own
## style. That is what gives three layers - shipped style, the TYPE's own, this request - and resolving
## at construction would silently collapse the middle one: a status builds its request without knowing
## which card will read it. See ARCHITECTURE_REVIEW §4j.

## Which alert. `CardOutline.Alert.GLARE` is a thick band sweeping the card's outline and BOUNCING left
## to right; `THROB` toggles the whole rim between its resting ink and this alert's colour.
##
## The owner asked for both rather than one (*"bouncing glare between L R sides kind of like shiny
## effect, but bouncing gives more an alert feel... A throb effect with maybe specific colour like red
## as well so there are multiple notification types to choose from"*), so this is an enumerated set a
## status picks from, not a boolean.
var kind : int = CardOutline.Alert.NONE

## The alert's palette entry, or -1 for the style's own (`glare_color` / `throb_color`).
var color : int = -1
## ONE FULL CYCLE as a fraction of `CardEnvironment.get_delay()`, or -1 for the style's.
## ⚠ A fraction, never a wall-clock number (START_HERE rule 4) — a cue that does not scale with the
## pacing settings desyncs from the cascade it is announcing, which is its one job.
var period_fraction : float = -1.0
## GLARE band thickness in CARD-SPACE art units, or -1 for the style's.
var thickness : float = -1.0
## GLARE dead zone at each side of the card, or -1 for the style's. See `OutlineStyle.glare_buffer` for
## why a card's vertical rims blink without it.
var buffer : float = -1.0

## A bouncing glare band. Naming nothing follows the card's style, which is what almost every caller
## wants; naming a field overrides it for this alert alone.
static func glare(period_fraction := -1.0, thickness := -1.0, color := -1,
		buffer := -1.0) -> CardAlert:
	var a := CardAlert.new()
	a.kind = CardOutline.Alert.GLARE
	a.color = color
	a.period_fraction = period_fraction
	a.thickness = thickness
	a.buffer = buffer
	return a

## A throbbing rim. Its PERIOD resolves against `throb_period_fraction`, not the glare's: a sweeping
## band and a pulsing rim are different cues and there is no reason they should share a tempo
## (owner 2026-08-06).
static func throb(color := -1, period_fraction := -1.0) -> CardAlert:
	var a := CardAlert.new()
	a.kind = CardOutline.Alert.THROB
	a.color = color
	a.period_fraction = period_fraction
	return a

# --- Resolution against a card's style -------------------------------------------------------------

## This alert's palette entry on a card wearing `style`. Kind-dependent, because the two alerts have
## genuinely different colour DEFAULTS — the glare's is a fallback (its identity is the motion), the
## throb's is a statement (the owner asked for it so a notification could name a hue).
func resolved_color(style : OutlineStyle) -> int:
	if color >= 0: return color
	return style.throb_color if kind == CardOutline.Alert.THROB else style.glare_color

## One full cycle in fractions of `get_delay()`, from whichever of the style's two tempos this kind uses.
func resolved_period(style : OutlineStyle) -> float:
	if period_fraction >= 0.0: return period_fraction
	return style.throb_period_fraction if kind == CardOutline.Alert.THROB else \
			style.glare_period_fraction

func resolved_thickness(style : OutlineStyle) -> float:
	return style.glare_thickness if thickness < 0.0 else thickness

func resolved_buffer(style : OutlineStyle) -> float:
	return style.glare_buffer if buffer < 0.0 else buffer
