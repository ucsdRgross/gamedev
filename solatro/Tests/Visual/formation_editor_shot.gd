extends "res://Tests/Visual/tool_shot.gd"

#The REAL formation_editor.tscn's preview props for the hoop and knife sets, each column over a REAL
#card at the tool's preview scale. Its own card scenery and point markers draw only in the editor
#(its `_draw` returns at runtime), so the real card stands where that scenery would be.

const TOOL_SCENE := preload("res://Tools/formation_editor.tscn")

func stage() -> void:
	var tool : FormationEditor = TOOL_SCENE.instantiate()
	add_child(tool)
	tool.position = get_viewport_rect().size * 0.5
	for kind : FormationEditor.Kind in [FormationEditor.Kind.HOOP, FormationEditor.Kind.KNIFE]:
		tool.kind = kind
		tool._spawn_preview()
		_lay_cards_under(tool)
		await settle()
		save("formation_editor_%s.png" % PropFormationSet.KIND_NAMES[kind])

## One real card per preview column, behind the props, at the tool's stand-in card scale.
func _lay_cards_under(tool : FormationEditor) -> void:
	for col : int in tool._preview_columns:
		var card := CardVisual.CARD_VISUAL.instantiate() as CardVisual
		card.current_context = CardVisual.DisplayContext.PREVIEW
		card.data = CardData.new().with_type(TypePaper.new())
		tool.add_child(card)
		tool.move_child(card, 0)
		card.set_process(false)
		card.floating = false
		card.scale = Vector2.ONE * tool.preview_scale
		card.position = tool._column_origin(col)
