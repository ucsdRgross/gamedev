extends Node
# res://Tests/Visual/wall_resource_load_spike.gd
# ==============================================================================
# S3 VERIFICATION — "both resources exist with exactly the exported fields above and load in the
# editor" (PLAN.md §2, S3). Not a suite test: TEST_PLAN.md owes nothing for S3 (P1-P12 are S4's),
# so this is a one-off, run-by-hand proof rather than anything registered in all_tests.tscn.
#
# Constructs a real PictureEntry and a real WallLayout, then checks EVERY exported field named in
# PLAN.md §1.1 / §1.2 by NAME against get_property_list() — present, correct Variant TYPE, correct
# default value — and prints PASS/FAIL per field plus one overall verdict. A field that is missing,
# renamed, mistyped or defaulted wrong fails loudly instead of silently loading as "close enough".
#
# No rendering involved (plain Resource construction + reflection), so this runs headless:
#     <console exe> --headless --path solatro res://Tests/Visual/wall_resource_load_spike.tscn
# ==============================================================================

var _fail_count := 0

func _ready() -> void:
	_check_picture_entry()
	_check_wall_layout()
	if _fail_count == 0:
		print("WALL_RESOURCE_LOAD_SPIKE: PASS — both resources load with every specified field")
	else:
		print("WALL_RESOURCE_LOAD_SPIKE: FAIL — %d field(s) did not match" % _fail_count)
	get_tree().quit(0 if _fail_count == 0 else 1)

## One field's expected shape: property name, Variant.Type, and the default value to compare
## against (compared with `==`, which is exact for the primitive/Vector/typed-array types here).
func _field(name: StringName, type: Variant.Type, default_value: Variant) -> Dictionary:
	return {"name": name, "type": type, "default": default_value}

func _check_picture_entry() -> void:
	var res := PictureEntry.new()
	var expected : Array[Dictionary] = [
		_field(&"id", TYPE_STRING_NAME, &""),
		_field(&"scene", TYPE_OBJECT, null),
		_field(&"ring", TYPE_INT, 0),
		_field(&"slot", TYPE_INT, 0),
		_field(&"size_multiplier", TYPE_FLOAT, 1.0),
		_field(&"design_size", TYPE_VECTOR2I, Vector2i(1152, 648)),
		_field(&"frame_px", TYPE_VECTOR4, Vector4(24, 24, 24, 24)),
		_field(&"frame_texture", TYPE_OBJECT, null),
		_field(&"unlocked_by_default", TYPE_BOOL, false),
		_field(&"keep_aspect", TYPE_BOOL, false),
	]
	_check_resource("PictureEntry", res, expected)

func _check_wall_layout() -> void:
	var res := WallLayout.new()
	var expected : Array[Dictionary] = [
		_field(&"pictures", TYPE_ARRAY, [] as Array[PictureEntry]),
		_field(&"home_id", TYPE_STRING_NAME, &"start_menu"),
		_field(&"gap_px", TYPE_FLOAT, 24.0),
		_field(&"ellipse_aspect_min", TYPE_FLOAT, 1.2),
		_field(&"ellipse_aspect_max", TYPE_FLOAT, 2.6),
		_field(&"view_margin", TYPE_FLOAT, 0.06),
	]
	_check_resource("WallLayout", res, expected)
	# The one typed-container export in this step. Confirms Array[PictureEntry] actually accepts a
	# PictureEntry (not merely typed on paper) and that appending one does not trip a
	# warnings-as-errors complaint at runtime — the load-bearing part of "load in the editor" for a
	# typed Array export.
	var entry := PictureEntry.new()
	entry.id = &"probe"
	res.pictures.append(entry)
	var round_trip_ok := res.pictures.size() == 1 and res.pictures[0] == entry
	_report("WallLayout.pictures accepts a PictureEntry (Array[PictureEntry] round-trips)",
			round_trip_ok)

## Reflects `res`'s property list, and for every entry in `expected` checks presence, Variant type
## and default value. Reports one PASS/FAIL line per field via `_report`.
func _check_resource(label: String, res: Resource, expected: Array[Dictionary]) -> void:
	var props : Dictionary[StringName, Dictionary] = {}
	for p : Dictionary in res.get_property_list():
		props[p["name"]] = p
	for exp : Dictionary in expected:
		var name : StringName = exp["name"]
		var where := "%s.%s" % [label, name]
		if not props.has(name):
			_report("%s: present" % where, false)
			continue
		var prop : Dictionary = props[name]
		var type_ok : bool = (prop["type"] as int) == (exp["type"] as int)
		_report("%s: type (want %s)" % [where, type_string(exp["type"] as int)], type_ok)
		var actual : Variant = res.get(name)
		var default_ok : bool = actual == exp["default"]
		_report("%s: default (want %s, got %s)" % [where, str(exp["default"]), str(actual)],
				default_ok)

func _report(label: String, ok: bool) -> void:
	if not ok: _fail_count += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", label])
