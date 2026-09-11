extends TestSuite
# res://Tests/Wall/test_sidebar.gd
# SIDEBAR: HudContainer and DescriptionPanel as empty shells -- exactly one content
# child visible at a time, HUD by default.

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")

func suite_name() -> String:
	return "SIDEBAR"

func _ready() -> void:
	TestLog.line("============ SIDEBAR TEST PASS ============")
	behavior_section("CONTAINER SHOWS EXACTLY ONE CHILD")
	test_default_state_is_the_hud()
	test_show_hud_shows_only_the_hud_stack()
	test_show_description_shows_only_the_description_panel()
	finish()

func _build_container() -> HudContainer:
	var container : HudContainer = HUD_CONTAINER_SCENE.instantiate()
	add_child(container)
	return container

func _visible_content_children(container: HudContainer) -> int:
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var count := 0
	if hud_stack.visible: count += 1
	if description_panel.visible: count += 1
	return count

## Q170=a: the container shows the HUD by default, with no `Main` and no wall in the tree.
func test_default_state_is_the_hud() -> void:
	var container := _build_container()
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible before any call", str(_visible_content_children(container)))
	check(hud_stack.visible, "the HUD is what shows by default")
	check(not description_panel.visible, "...and the description does not")
	container.queue_free()

func test_show_hud_shows_only_the_hud_stack() -> void:
	var container := _build_container()
	container.show_description(InfoEntry.new())
	container.show_hud()
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible after show_hud()", str(_visible_content_children(container)))
	check(hud_stack.visible, "...and it is HudStack")
	check(not description_panel.visible, "...and DescriptionPanel is hidden")
	container.queue_free()

func test_show_description_shows_only_the_description_panel() -> void:
	var container := _build_container()
	container.show_description(InfoEntry.new())
	var hud_stack : Control = container.get_node(^"%HudStack")
	var description_panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	check(_visible_content_children(container) == 1,
			"exactly one child is visible after show_description()",
			str(_visible_content_children(container)))
	check(description_panel.visible, "...and it is DescriptionPanel")
	check(not hud_stack.visible, "...and HudStack is hidden")
	container.queue_free()
