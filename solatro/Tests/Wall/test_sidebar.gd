extends TestSuite
# res://Tests/Wall/test_sidebar.gd
# SIDEBAR: HudContainer and DescriptionPanel as empty shells -- exactly one content
# child visible at a time, HUD by default.

const HUD_CONTAINER_SCENE := preload("res://UI/hud_container.tscn")
const WALL_SCENE := preload("res://UI/Wall/wall.tscn")
const GAME_VIEW_SCENE := preload("res://Levels/game_view.tscn")
const MAIN_SCENE := preload("res://Levels/main.tscn")
const MAP_SCENE := preload("res://Levels/map.tscn")


## Higher than a real deck can score in a handful of placements, so a test about something else never trips the goal's own automatic end.
const GOAL_OUT_OF_REACH : int = 100000000

## Well past the map's own drag threshold, so the press under test becomes a pan and not a click.
const MAP_PAN_DRAG := Vector2(120.0, 80.0)

func suite_name() -> String:
	return "SIDEBAR"

# This suite hosts a real GameView and writes the shared `CardEnvironment.CURRENT`, so it waits
# for every sibling that hosts one too. See TestSuite's DEADLOCK RULE and its ordering chain.
func _ready() -> void:
	await await_siblings_except(["DRAG PLACE", "SETTINGS RANGE", "E2E RUN", "LEAK CANARY",
			"WALL PAUSE"])
	TestLog.line("============ SIDEBAR TEST PASS ============")
	check_all_tests_registered()
	behavior_section("CONTAINER SHOWS EXACTLY ONE CHILD")
	test_default_state_is_the_hud()
	test_show_hud_shows_only_the_hud_stack()
	test_show_description_shows_only_the_description_panel()
	behavior_section("THE GAME SCREEN'S HUD (S2)")
	await test_game_hud_holds_exactly_the_nine_members()
	test_no_retired_furniture_nodes_remain()
	await test_overlay_buttons_draw_above_the_hud_container()
	await test_every_hud_member_is_visible_and_reachable()
	await test_number_captions_and_values_do_not_overlap()
	await test_the_hud_always_shows_goal_total_and_the_score_line()
	await test_game_hud_members_start_below_the_overlay_button_band()
	await test_pressing_end_reaches_the_live_game_views_handler()
	await test_a_second_shows_view_receives_the_press_after_the_first_tears_down()
	await test_the_game_views_hud_container_is_scoped_to_its_own_wall()
	behavior_section("THE CONTAINER'S GEOMETRY")
	await test_game_hud_members_stay_inside_the_container_at_a_side_window()
	await test_the_inset_is_the_sidebars_share_at_the_pictures_own_aspect()
	await test_an_ultrawide_window_clamps_and_narrows()
	await test_a_resize_re_applies_every_overlay_touch_target()
	await test_a_resize_round_trip_shrinks_the_overlay_row_back()
	await test_the_container_moves_to_the_top_when_the_leftover_would_be_taller_than_wide()
	await test_the_boards_region_clears_the_container_on_a_cropped_window()
	await test_board_centre_after_hud_migration_is_the_space_beside_the_resting_sidebar()
	await test_a_real_resize_moves_the_container_and_republishes_the_inset()
	await test_a_top_case_resize_fits_the_board_under_the_band()
	await test_the_top_bands_hud_starts_below_the_overlay_buttons()
	behavior_section("THE OVERLAY SLIDES, IT NEVER INSETS THE PICTURE")
	await test_the_sidebar_is_hidden_on_the_menu_until_the_picker_shows_something()
	await test_every_focused_picture_covers_the_window_edge_to_edge()
	await test_a_focused_picture_is_drawn_unstretched_at_every_window_shape()
	await test_a_wall_view_picture_draws_at_least_a_texel_per_pixel()
	await test_a_visited_picture_shows_its_content_in_wall_view_and_stays_frozen()
	await test_the_wall_view_shows_one_surface_colour_behind_the_pictures()
	await test_the_sidebar_slides_in_after_the_landing_and_the_board_shifts_with_it()
	await test_the_sidebar_is_fully_out_before_the_camera_leaves()
	await test_a_leave_mid_slide_ends_with_the_sidebar_fully_out()
	await test_the_slide_shifts_the_board_without_re_scaling_it()
	await test_freeing_main_mid_slide_strands_no_waiter()
	await test_before_the_slide_each_screen_has_the_whole_picture()
	await test_wall_view_keeps_the_board_centred_in_its_picture()
	behavior_section("S4: THE MAP GETS THE SAME CONTAINER")
	await test_map_hud_holds_exactly_the_four_members_and_maps_own_ui_is_empty_of_them()
	await test_focus_change_drives_which_hud_stack_child_shows()
	await test_map_deck_button_reaches_the_live_maps_handler_then_disconnects()
	await test_maps_camera_offset_moves_beside_the_container_not_under_it()
	await test_the_map_at_rest_fits_the_space_beside_the_sidebar()
	await test_zooming_out_stops_at_the_fit()
	await test_at_the_fit_nothing_pans()
	await test_zoomed_in_the_view_never_passes_the_maps_edge()
	await test_the_maps_background_is_its_sea()
	await test_a_travel_returns_the_map_to_the_fit()
	await test_leaving_and_reentering_the_map_returns_it_to_the_fit()
	await test_a_zoom_stays_through_a_visit_without_a_travel()
	await test_no_frame_is_blended_across_a_return_to_the_fit()
	await test_menus_buttons_lie_outside_the_container_and_inside_the_window()
	await test_menus_title_and_button_row_centre_on_the_remaining_space()
	await test_every_menu_control_draws_at_the_ui_size_inside_the_window_and_none_overlaps()
	await test_the_menus_bottom_row_wraps_beside_the_slid_in_sidebar()
	await test_the_menus_column_only_shifts_while_the_sidebar_slides()
	await test_the_menu_lays_out_for_the_window_after_every_resize()
	await test_the_menus_buttons_stack_wherever_the_whole_column_fits_beside_the_sidebar()
	await test_a_resize_between_the_window_shapes_stacks_the_menu_and_unstacks_it()
	await test_keys_and_the_d_pad_walk_the_stacked_menu_in_order()
	await test_keys_alone_start_a_run_from_the_start_menu_and_find_it_again()
	await test_a_pad_alone_starts_a_run_from_the_start_menu()
	await test_a_show_resumed_through_the_menu_rests_a_key_focus_on_its_board()
	await test_a_resolved_show_resumed_through_the_menu_rests_the_key_focus_on_continue()
	behavior_section("S5: A HIGHLIGHT PUBLISHES AND THE CONTAINER SHOWS")
	await test_a_highlight_opens_the_description()
	await test_the_description_titles_a_card_and_sizes_its_effect_names()
	await test_the_title_names_the_suit_in_the_plural()
	await test_a_hovered_cards_description_draws_inside_the_container()
	await test_the_containers_content_starts_one_inset_inside_its_left_edge()
	await test_the_title_leaves_the_exit_xs_column()
	await test_the_preview_is_drawn_at_the_one_preview_size()
	await test_the_preview_follows_a_resize_to_the_new_preview_size()
	await test_a_hover_describes_a_board_card_without_sticking_it()
	await test_re_hovering_the_focused_card_describes_it_again()
	await test_a_hover_that_moves_the_focus_publishes_once()
	await test_re_hovering_a_stuck_card_keeps_it_stuck()
	await test_a_pad_focus_describes_a_board_card_without_sticking_it()
	await test_leaving_and_returning_restores_the_screens_own_description()
	await test_a_description_dismissed_with_the_x_stays_dismissed_on_return()
	await test_a_description_a_placement_took_down_stays_down_on_return()
	await test_a_focused_card_is_forgotten_across_back_and_forward()
	await test_a_hovered_card_is_forgotten_across_back_and_forward()
	await test_a_new_entry_frees_the_visual_it_replaces()
	behavior_section("S6: THE LOCK AND THE EXIT X")
	await test_a_click_grabs_the_card_and_locks_its_description()
	await test_locking_a_second_card_replaces_the_first()
	await test_the_locked_card_keeps_its_marking_while_focus_moves_on()
	await test_a_board_rebuild_keeps_the_same_cards_description()
	await test_the_exit_x_reverts_to_the_hud()
	await test_the_exit_x_is_a_touch_target_below_the_button_band()
	await test_a_resize_relays_the_description_to_the_new_width()
	behavior_section("S6: FOLLOW, RETURN AND DISMISS")
	await test_the_description_follows_the_hover_while_locked()
	await test_leaving_everything_returns_to_the_locked_card()
	await test_a_stuck_card_survives_hovers_and_the_pointer_reaching_the_sidebar()
	await test_focus_leaving_the_board_returns_to_the_locked_card()
	await test_cancel_reverts_to_the_hud_and_still_reaches_the_wall()
	await test_the_second_button_releases_the_held_card_then_dismisses()
	await test_a_press_on_bare_board_reverts_to_the_hud()
	await test_placing_a_card_closes_the_description()
	await test_replacing_a_displaced_lock_frees_its_visual()
	behavior_section("S7: THE PROCESSING RULE")
	test_the_same_entry_published_again_after_processing_still_shows()
	await test_processing_reverts_to_the_hud_and_drops_the_lock()
	await test_a_real_cascade_holds_the_hud_for_its_whole_length()
	await test_a_hover_during_processing_changes_nothing()
	await test_the_hud_holds_after_processing_until_any_focus_event()
	await test_the_maps_container_does_not_swap_on_the_games_processing()
	behavior_section("S8: SCROLL AND MULTI-MODAL REACH")
	test_the_sidebar_scroll_action_binds_the_non_navigation_stick()
	await test_a_long_description_shows_a_scrollbar_and_rests_at_the_top()
	await test_a_short_description_hides_the_scrollbar()
	await test_page_keys_scroll_the_description_by_a_page()
	await test_the_scroll_stick_scrolls_the_description_and_not_the_hud()
	await test_a_low_stick_deflection_still_scrolls_a_short_description()
	await test_the_arrows_scroll_only_once_the_description_is_locked()
	await test_the_exit_x_joins_navigation_whenever_a_description_shows()
	await test_accepting_the_exit_x_hands_the_focus_back_to_the_board()
	behavior_section("A SCREEN'S STATE BELONGS TO ITS OWN CONTENT")
	await test_a_finished_show_leaves_no_cascade_flag_for_the_next_one()
	await test_a_listed_card_clicked_on_the_outcome_screen_leaves_no_empty_lock()
	await test_a_new_run_does_not_inherit_the_last_shows_lock()
	await test_a_new_run_does_not_inherit_the_last_shows_hand()
	await test_a_new_run_does_not_inherit_the_maps_last_description()
	await test_a_new_run_closes_the_last_runs_possible_cards()
	await test_a_new_run_throws_away_the_last_runs_chooser()
	await test_leaving_while_locked_keeps_the_whole_lock_alive()
	await test_zooming_out_with_a_focused_card_keeps_the_lock()
	await test_every_end_of_a_lock_ends_all_of_it()
	await test_a_cancelled_lock_survives_the_pointer_leaving_every_card()
	await test_a_dropped_card_leaves_no_lock_behind()
	await test_a_finished_show_leaves_the_maps_own_wiring_alive()
	await test_a_remembered_entry_dropped_by_a_cascade_is_freed()
	behavior_section("S9: INFO MODE IS GONE")
	test_no_script_names_the_retired_mode()
	test_the_retired_action_is_unbound()
	behavior_section("S10: THE IN-BOARD POPUP IS GONE")
	test_no_script_names_the_retired_in_board_popup()
	behavior_section("THE VIEWERS PUBLISH TOO")
	await test_the_first_arrow_enters_a_viewer_and_shows_its_first_card()
	await test_closing_a_viewer_leaves_the_focus_somewhere_visible()
	await test_swapping_viewers_falls_back_to_what_the_viewer_covered()
	await test_the_deck_viewer_publishes_into_the_sidebar()
	await test_the_rules_and_discard_viewers_publish_into_the_sidebar()
	await test_every_rules_viewer_card_draws_a_card_face()
	await test_the_choice_viewer_publishes_into_the_sidebar()
	await test_a_reroll_moves_the_sidebar_onto_the_replacement()
	await test_the_choice_viewers_pack_lies_below_the_band_at_a_top_window()
	await test_a_resize_re_fits_the_open_choice_viewer()
	await test_the_deck_viewers_cards_start_beside_the_container()
	await test_the_deck_viewers_cards_lie_below_the_band_at_a_top_window()
	await test_a_resize_re_fits_the_open_viewer()
	await test_a_resize_does_not_re_open_a_dismissed_description()
	await test_a_resize_keeps_a_viewers_preview_at_the_viewers_own_card_size()
	await test_a_board_lock_survives_opening_and_closing_a_viewer()
	behavior_section("A VIEWER IS MODAL, AND A CLICK IS WHAT MAKES ITS CARD STAY")
	await test_an_arrow_in_an_open_viewer_never_moves_the_maps_pick()
	await test_a_click_beneath_an_open_viewer_never_reaches_the_board()
	await test_a_click_outside_a_viewer_on_the_map_closes_it_and_travels_nowhere()
	await test_closing_a_viewer_takes_its_card_out_of_the_sidebar()
	await test_the_exit_x_shows_only_once_a_viewer_card_is_clicked()
	await test_a_board_lock_waits_under_a_stuck_viewer_card_and_comes_back()
	await test_every_arrow_walks_the_viewers_grid_and_the_rim_follows()
	await test_an_edge_arrow_leaves_the_stuck_viewer_for_the_exit_x()
	await test_an_edge_key_in_a_viewer_lands_the_focus_on_the_exit_x()
	await test_the_deck_button_pressed_again_closes_the_viewer_it_opened()
	await test_the_map_shows_no_travel_or_deck_while_it_describes_a_card()
	await test_a_card_on_the_game_screen_shows_no_map_buttons_while_a_node_is_picked()
	await test_travel_goes_by_mouse_while_a_show_is_frozen_behind_the_map()
	await test_closing_a_packs_viewer_returns_to_the_node_while_a_show_is_frozen()
	await test_the_sidebars_x_over_a_viewer_unsticks_and_closes_together()
	await test_an_unstuck_viewer_description_goes_when_the_pointer_leaves_the_card()
	await test_the_deck_button_toggles_by_mouse_while_its_viewer_is_open()
	await test_the_deck_button_toggles_by_pad_while_its_viewer_is_open()
	await test_a_cancel_from_a_sticky_description_leaves_the_focus_in_the_sidebar()
	await test_a_right_click_over_a_stuck_deck_viewer_card_cancels_as_esc_does()
	await test_an_undo_under_an_open_viewer_rests_no_board_card_by_mouse()
	await test_an_undo_under_an_open_viewer_rests_no_board_card_by_keys()
	await test_right_off_the_sidebar_never_reaches_the_board_behind_an_empty_viewer()
	await test_the_sidebar_and_an_open_viewer_are_one_walk_with_nothing_stuck()
	await test_left_off_the_menus_viewer_stays_in_it_with_nothing_to_land_on()
	await test_left_off_the_deck_over_a_stuck_chooser_card_lands_on_close_deck()
	await test_left_off_the_possible_cards_lands_on_the_picks_x_first()
	await test_a_left_before_the_sidebar_slides_in_asks_no_screen_for_it()
	await test_tab_opens_the_wall_on_every_screen_as_the_pad_button_does()
	await test_the_chooser_is_a_fitted_window_with_the_map_around_it()
	await test_the_map_around_the_chooser_ignores_clicks_drags_and_the_wheel()
	await test_a_wheel_over_a_deck_viewer_never_reaches_the_screen_beneath()
	await test_a_click_outside_closes_the_pack_viewer_but_never_the_chooser()
	await test_every_route_leaves_the_chooser_and_comes_back_to_it_in_progress()
	await test_the_choosers_deck_button_opens_over_it_and_closing_returns_to_it()
	await test_closing_the_deck_viewer_over_the_chooser_gives_back_its_stuck_card()
	await test_a_right_click_over_a_stuck_chooser_card_lets_it_go_as_esc_does()
	await test_the_choosers_deck_button_stays_up_and_closes_its_open_deck()
	await test_the_description_row_sits_under_the_band_above_the_described_card()
	await test_the_choosers_deck_button_reads_close_deck_while_its_deck_is_open()
	await test_the_choosers_cards_draw_at_the_ui_size_whatever_the_map_zoom()
	await test_the_chooser_and_its_deck_are_hidden_in_wall_view_and_back_on_return()
	await test_keys_stay_in_the_chooser_on_the_windows_own_viewport()
	await test_the_maps_viewers_draw_at_the_ui_size_whatever_the_map_zoom()
	await test_the_maps_viewer_stack_is_hidden_in_wall_view_and_back_on_return()
	await test_a_card_stuck_in_the_possible_cards_carries_only_the_deck_row()
	await test_deck_from_a_stuck_possible_card_opens_over_the_list()
	await test_the_deck_over_the_possible_cards_hides_the_whole_list()
	await test_closing_the_possible_cards_with_a_card_stuck_returns_to_the_pick()
	await test_the_deck_over_the_possible_cards_by_keys_alone()
	await test_a_click_on_the_viewers_close_tab_closes_it()
	await test_the_viewers_close_tab_by_keys_or_pad_alone()
	await test_the_viewers_close_tab_sticks_out_clear_of_the_sidebar_and_its_cards()
	await test_every_window_kind_draws_its_own_opaque_colour()
	await test_every_pile_opener_reads_close_while_its_viewer_is_open()
	await test_a_keyboard_reaches_every_row_button_from_the_x()
	await test_a_game_viewer_left_open_across_back_changes_nothing_on_the_map()
	await test_the_games_viewers_draw_at_the_ui_size_at_both_window_shapes()
	await test_a_game_viewer_is_hidden_in_wall_view_and_back_on_return()
	await test_the_board_behind_an_open_viewer_answers_no_pointer()
	await test_leaving_mid_walk_onto_a_pack_never_strands_the_chooser()
	await test_the_start_menus_inspect_viewer_lists_beside_the_container()
	await test_a_click_beside_the_menus_viewer_closes_it_and_the_sidebar_slides_out()
	await test_the_start_menus_inspect_viewer_publishes_into_the_container()
	await test_the_start_menus_inspect_viewer_publishes_on_hover()
	await test_the_menus_viewer_draws_at_the_ui_size_at_both_window_shapes()
	await test_the_menus_viewer_fades_with_the_sidebar_across_a_leave()
	await test_picking_a_deck_with_the_viewer_open_closes_it()
	await test_closing_the_picker_drops_the_menus_description()
	await test_the_deck_picker_draws_at_the_ui_size_on_screen_at_both_window_shapes()
	await test_the_deck_pickers_viewer_draws_over_the_picker()
	await test_keys_reach_every_deck_picker_control_in_the_windows_own_viewport()
	await test_the_menu_behind_the_deck_picker_answers_no_pointer()
	await test_the_deck_picker_is_hidden_in_wall_view_and_back_on_return()
	await test_a_return_to_the_menu_leaves_the_focus_to_the_pickers_viewer()
	await test_the_deck_builder_tool_loads_and_stands_up()
	behavior_section("S14: LIFTED, AND CARRIED")
	await test_a_held_card_lifts_and_does_not_follow()
	await test_mouse_motion_with_no_button_down_never_follows()
	await test_a_key_focus_leaves_the_card_resting_in_its_slot()
	await test_the_release_ends_the_follow()
	await test_the_lift_is_the_same_height_in_both_states()
	await test_a_dragged_card_follows_the_cursor()
	await test_a_click_locked_card_keeps_its_description_until_it_is_placed()
	await test_a_following_card_leaving_its_cell_reverts_to_the_hud()
	await test_a_lifted_card_that_is_not_following_keeps_the_description()
	await test_only_the_stuck_entry_carries_the_x_while_a_card_is_lifted()
	await test_only_the_stuck_viewer_card_carries_the_x()
	test_the_choice_viewer_owns_no_inspector_panel()
	behavior_section("S15: NOTHING IS HELD UNTIL THE PLAYER ACTS")
	await test_a_fresh_show_holds_nothing_and_shows_the_hud()
	await test_the_show_rests_the_opening_focus_on_a_board_cell()
	await test_a_placement_leaves_nothing_held()
	await test_a_refill_fills_the_leftmost_slot_and_holds_nothing()
	await test_a_resumed_placement_leaves_nothing_held()
	await test_an_undo_leaves_nothing_held()
	await test_clicking_another_entrance_card_moves_the_hold_onto_it()
	await test_a_click_during_processing_grabs_nothing()
	await test_a_click_on_a_card_no_rule_grabs_leaves_the_hand_empty()
	await test_the_disarm_leaves_nothing_held()
	await test_an_empty_entrance_lifts_nothing()
	await test_the_legal_cell_highlight_follows_what_a_placement_accepts()
	await test_a_direct_rebuild_re_sweeps_the_drop_map()
	behavior_section("S18: CANCEL")
	await test_the_second_button_dismisses_a_description_with_nothing_held()
	await test_the_second_button_with_nothing_to_cancel_does_nothing()
	await test_the_second_button_over_the_panel_still_cancels()
	await test_the_second_button_over_the_overlay_band_still_cancels()
	await test_escape_cancels_everything_and_steps_back_in_one_press()
	await test_releasing_the_held_card_leaves_the_locked_description_up()
	await test_a_cancel_needs_a_click_on_an_entrance_card_to_lift_again()
	behavior_section("PHASE 5: THE ARROW OFF AN ENTRANCE CARD")
	await test_an_arrow_from_an_entrance_card_leaves_the_focus_on_the_board()
	await test_motion_over_the_container_reaches_the_following_card()
	behavior_section("S21: THE ENTRANCE DRAWS FACE DOWN AND FLIPS IN PLACE")
	await test_a_refilled_card_appears_in_its_own_slot()
	await test_only_the_empty_slots_flip()
	await test_the_flip_waits_one_stagger_per_slot()
	await test_a_slot_shows_one_face_down_card_whatever_its_depth()
	await test_the_face_down_card_becomes_the_revealed_one()
	await test_hovering_a_stock_says_how_many_it_has_left()
	await test_one_drained_stock_drops_nothing()
	await test_clicking_a_stock_describes_the_slot_and_locks_nothing()
	await test_accepting_a_stock_describes_the_slot_and_locks_nothing()
	await test_the_deck_viewer_lists_every_stock_as_one_sorted_pile()
	await test_an_arrow_never_stops_on_a_face_down_card()
	await test_a_stocked_slot_draws_its_card_as_flat_as_an_exhausted_one()
	behavior_section("S22: END IS REVEALED ONLY WHEN THE SHOW CAN NO LONGER PROGRESS")
	await test_end_is_revealed_when_no_action_remains()
	await test_a_keyed_end_leaves_no_focus_on_the_disabled_button()
	await test_end_stays_hidden_through_the_shows_first_frames()
	behavior_section("THE RESOLVED SHOW LEAVES NOTHING ARMED")
	await test_the_outcome_screen_leaves_no_card_held()
	behavior_section("THE OUTCOME'S UNDO IS REACHED BY PAD FROM CONTINUE")
	await test_the_outcomes_undo_is_reachable_from_continue_by_pad()
	await test_undo_from_an_end_reached_outcome_with_an_empty_entrance()
	behavior_section("S23: THE MAP NAMES THE NODE AND DESCRIBES IT IN THE SIDEBAR")
	await test_hovering_a_map_node_names_the_dot_and_leaves_the_sidebar_alone()
	await test_the_name_stays_put_while_the_pointer_moves_inside_the_node()
	await test_one_click_picks_the_node_and_only_travel_goes_there()
	await test_a_tap_picks_the_node_and_no_second_tap_enters_it()
	await test_a_finger_drag_pans_the_map()
	await test_a_pad_enters_the_panel_by_up_on_the_map_and_leaves_it_by_the_x()
	await test_a_single_reachable_node_selects_itself_and_a_dismissal_drops_it_like_any_other_clear()
	await test_up_inside_a_hosted_viewer_walks_the_viewer_not_the_x()
	await test_selecting_a_node_by_key_describes_it()
	behavior_section("THE MAP SIDEBAR: A BASIC VIEW, THEN A PICK WITH ITS OWN BUTTONS")
	await test_the_map_rests_with_nothing_picked_and_no_pick_buttons()
	await test_a_pick_brings_up_travel_and_a_deck_button_of_its_own()
	await test_the_decks_viewer_comes_back_to_the_same_pick()
	await test_the_picks_buttons_never_show_on_another_screen()
	await test_cancel_drops_the_pick_before_it_leaves_the_picture()
	await test_a_pick_under_an_open_viewer_is_not_re_shown_on_return()
	await test_a_dropped_pick_leaves_the_map_nothing_to_come_back_to()
	await test_every_new_button_is_written_in_the_locale()
	await test_a_pack_lists_its_possible_cards_on_the_first_pick_only()
	await test_the_possible_cards_list_every_part_as_an_icon_and_no_card()
	await test_the_possible_cards_group_each_kind_under_its_own_header()
	await test_a_possible_rank_is_filled_in_its_own_role_not_the_outlines_ink()
	await test_a_possible_part_is_described_by_its_name_on_a_card_preview()
	await test_travelling_lets_a_pack_list_itself_again()
	await test_no_name_popup_shows_on_the_board()
	behavior_section("THE NAME IS ANCHORED TO THE DOT IT NAMES")
	await test_the_name_follows_its_node_when_the_camera_pans()
	await test_starting_a_run_takes_the_name_off_the_map()
	behavior_section("A CARD LEAVING THE BOARD FLIES TO ITS PILE")
	await test_a_card_leaving_the_board_flies_to_its_pile()
	behavior_section("THE BOARD'S DOOR TO THE SIDEBAR (P40)")
	await test_left_from_the_leftmost_entrance_card_enters_the_sidebar()
	await test_left_from_the_leftmost_grid_cell_enters_the_sidebar()
	await test_right_from_the_sidebars_last_control_returns_to_the_card_it_left()
	await test_left_with_a_stuck_description_lands_on_the_x()
	await test_a_pad_accept_on_the_landed_hud_button_presses_it()
	await test_left_on_the_map_with_nothing_picked_reaches_its_deck_button()
	behavior_section("THE PLAYER'S WINDOW: ITS OWN CONTENT SCALE")
	await test_every_viewer_draws_at_the_ui_size_in_the_players_window()
	await test_the_chooser_fits_its_rows_beside_the_sidebar_in_the_players_window()
	await test_the_menus_column_draws_at_the_ui_scale_beside_the_sidebar_in_the_players_window()
	await test_the_board_is_centred_beside_the_resting_sidebar_in_the_players_window()
	await test_the_outcome_centres_over_the_board_resting_and_slid()
	await test_the_score_lines_draw_inside_the_sidebar_at_a_won_show()
	await test_the_maps_sea_buffer_is_whole_on_screen_in_the_players_window()
	finish()


# ------------------------------------------- S22: THE END BUTTON'S REVEAL

## 7.5: End is the way out of a show that cannot be won, so it stays hidden while the show can still progress.
func test_end_is_revealed_when_no_action_remains() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	var state := view.game.state
	check(not view.submit_button.visible,
			"a live show with cards to draw and empty tiles hides End")
	check(not state.grids_are_full(), "sanity: the dealt board still has an empty tile")
	for stock : ArrayCardData in state.entrance_stocks():
		stock.datas.clear()
	state.revision += 1
	await get_tree().process_frame
	check(view.submit_button.visible,
			"7.5: every stock empty reveals End even with an empty tile left")
	state.entrance_stocks()[0].datas.append(TestFactories.m_card(5, TestFactories.uc()))
	_fill_every_grid_cell(state)
	state.revision += 1
	await get_tree().process_frame
	check(view.submit_button.visible,
			"7.5: no empty tile left reveals End even with a stock still holding a card")
	state.grids[0].cells[0].datas.clear()
	state.revision += 1
	await get_tree().process_frame
	check(not view.submit_button.visible,
			"7.5: a stock with a card AND an empty tile hides End again")
	await _end_main_fixture()

## A keyed End disables the button it was pressed on: the focus leaves it for a live control in the show, and the button takes the focus again once play resumes.
func test_a_keyed_end_leaves_no_focus_on_the_disabled_button() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	for stock : ArrayCardData in view.game.state.entrance_stocks():
		stock.datas.clear()
	view.game.state.revision += 1
	await get_tree().process_frame
	view.submit_button.grab_focus()
	await get_tree().process_frame
	check(view.submit_button.visible and _booted_viewport.gui_get_focus_owner() == view.submit_button,
			"sanity: End is revealed and holds the key focus", str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_ENTER)
	var waited := 0.0
	while not view.game.state.show_ended and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().process_frame
	check(view.game.state.show_ended and view.submit_button.disabled, "sanity: Enter on End ended the show, End disabled")
	check(view.submit_button.focus_mode == Control.FOCUS_NONE and _booted_viewport.gui_get_focus_owner() != view.submit_button,
			"the disabled End is no focus target and gave its focus up", str(_booted_viewport.gui_get_focus_owner()))
	check(_holds_a_live_focus(_game_viewport), "...which rests on a live control in the show",
			str(_game_viewport.gui_get_focus_owner()))
	view.undo_button.pressed.emit()
	waited = 0.0
	while view.game.processing and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().process_frame
	check(not view.submit_button.disabled and view.submit_button.focus_mode == Control.FOCUS_ALL,
			"End enabled again with play is a focus target again")
	check(_holds_a_live_focus(_game_viewport), "...and the show's own focus rests on a live control",
			str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

func _holds_a_live_focus(viewport: Viewport) -> bool:
	var focused := viewport.gui_get_focus_owner()
	return focused != null and focused.is_visible_in_tree() and focused.focus_mode != Control.FOCUS_NONE and not (focused is BaseButton and (focused as BaseButton).disabled)

# The reveal asks about EMPTY tiles, so the fixture above needs a board with none left.
func _fill_every_grid_cell(state: GameData) -> void:
	for grid : GridData in state.grids:
		for cell : ArrayCardData in grid.cells:
			if cell.datas.is_empty():
				var card := TestFactories.m_card(1, TestFactories.uc())
				card.stage = CardData.Stage.PLAY
				cell.datas.append(card)

## End is hidden until the show cannot progress, so it may never appear while the show is starting up.
func test_end_stays_hidden_through_the_shows_first_frames() -> void:
	var seen : Array[bool] = [false, false]
	var samples : Array[int] = [0]
	var sampler := func() -> void:
		if _main == null: return
		samples[0] += 1
		var container := _main.wall.get_node(^"%HudContainer") as HudContainer
		if container.submit_button.visible: seen[0] = true
		if container.submit_button.is_visible_in_tree(): seen[1] = true
	get_tree().process_frame.connect(sampler)
	await _start_game_fixture()
	get_tree().process_frame.disconnect(sampler)
	check(samples[0] > 0, "the sampler read the live HUD during the show's start-up",
			str(samples[0]))
	check(not seen[0], "End is never flagged visible while a fresh show starts up")
	check(not seen[1], "End is never on screen while a fresh show starts up")
	await _end_main_fixture()

## The show ends full stop, so nothing on the board is still held under the outcome screen.
func test_the_outcome_screen_leaves_no_card_held() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to pick up",
			str(entrance.size()))
	if not entrance.is_empty(): await _lift_by_click(entrance[0])
	check(not _play_area.selected_cards.is_empty(), "a click left a card in hand")
	if _container.showing_description():
		await _click(_exit_button().get_global_rect().get_center(), _booted_viewport)
	check(_hud_is_up(), "...and the X put the HUD back, where End is drawn")
	await _end_the_show_by_its_button(view)
	await get_tree().process_frame
	check(view.win_screen.visible or view.lose_screen.visible, "the outcome screen is up")
	check(_play_area.selected_cards.is_empty(), "the resolved show holds no card")
	await _end_main_fixture()

# Row 7.6: the outcome's two buttons live in the game picture's own SubViewport. The step is pushed
# into the ROOT viewport, where a real pad's press arrives, so the walk also proves the wall routes
# it into the picture -- the viewport Godot's focus navigation cannot leave.
func _outcome_pad_step(keycode: Key) -> Control:
	await _tap_key(keycode)
	return _game_viewport.gui_get_focus_owner()

## The outcome screen's own Undo, found the way a player finds it: by looking at the screen that is up.
func _outcome_undo_control(view: GameView) -> Button:
	var screen : Label = view.win_screen if view.win_screen.visible else view.lose_screen
	for button : Button in screen.find_children("*", "Button", true, false):
		if button.text == TRANSLATION.find(&"GAME_UNDO"): return button
	return null

## Row 7.6 (`GAP-009`=b): a pad player reaches Undo from the outcome by walking off Continue, and pressing it there puts the board back.
func test_the_outcomes_undo_is_reachable_from_continue_by_pad() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _end_the_show_by_its_button(view)
	await get_tree().process_frame
	check(view.game.state.show_ended, "sanity: the show is over and its outcome is up")
	check(_game_viewport.gui_get_focus_owner() == view._continue_button,
			"7.6: the outcome opens with Continue holding the focus",
			str(_game_viewport.gui_get_focus_owner()))
	check(TRANSLATION.find(&"GAME_UNDO") != "GAME_UNDO",
			"7.6: the outcome's Undo has a localised label, so looking for it by text means something",
			TRANSLATION.find(&"GAME_UNDO"))
	var undo := _outcome_undo_control(view)
	check(undo != null, "7.6: the outcome screen shows an Undo beside Continue")
	check(view.undo_button.is_visible_in_tree(),
			"7.6: ...and the HUD's own Undo stays up for the mouse (GAP-009=b)")
	var stepped_right : Control = await _outcome_pad_step(KEY_RIGHT)
	check(undo != null and stepped_right == undo,
			"7.6: one d-pad step off Continue lands on the outcome's Undo", str(stepped_right))
	var stepped_back : Control = await _outcome_pad_step(KEY_LEFT)
	check(undo != null and stepped_back == view._continue_button,
			"7.6: ...and the step back returns to Continue", str(stepped_back))
	var back_on_undo : Control = await _outcome_pad_step(KEY_RIGHT)
	check(undo != null and back_on_undo == undo,
			"7.6: the walk reaches the outcome's Undo again, so the accept lands on it",
			str(back_on_undo))
	var row : HBoxContainer = view._outcome_buttons
	await _accept_the_focused_outcome_button(
			func() -> bool: return _game_viewport.gui_get_focus_owner() != null)
	check(not view.win_screen.visible and not view.lose_screen.visible,
			"7.6: the pad's accept on that Undo takes the outcome screen away")
	check(not view.game.state.show_ended and not view.game.processing,
			"7.6: ...leaving the show live again",
			"ended=%s busy=%s" % [view.game.state.show_ended, view.game.processing])
	check(_play_area.selected_cards.is_empty(),
			"7.6: ...on a playable board holding nothing", str(_play_area.selected_cards.size()))
	var owner := _game_viewport.gui_get_focus_owner()
	check(owner != null and _play_area.ui_data.has(owner),
			"7.6: ...with the picture viewport's focus on a board control, not parked on "
			+ "the HUD's Undo in the root viewport (a pad player is back on the live board)",
			"picture=%s root=%s" % [owner, _booted_viewport.gui_get_focus_owner()])
	check(view._outcome_buttons == null and not is_instance_valid(row),
			"7.6: ...and the outcome's button row is freed with the screen, its field cleared",
			"field=%s row_valid=%s" % [view._outcome_buttons, is_instance_valid(row)])
	check(view.undo_button.is_visible_in_tree(),
			"7.6: ...and the HUD's own Undo stayed up throughout")
	await _end_main_fixture()

# The accept lands on a button that rewinds the show, so the rebuild it starts is waited out before
# anything is read: the outcome is dropped on the press and the board is rested on frames later,
# and what "rested" means is the row's to say.
func _accept_the_focused_outcome_button(rested: Callable) -> void:
	_push_key(_booted_viewport, KEY_ENTER, true)
	_push_key(_booted_viewport, KEY_ENTER, false)
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC and (_fixture_game().processing or not rested.call()):
		await get_tree().process_frame
		waited += get_process_delta_time()
#The outcome's own row is queue_free()d, which lands at the end of a frame, so a row reading
#whether it is gone waits one out.
	await get_tree().process_frame
	await get_tree().process_frame

# Row 7.7: the producer of an outcome with NOTHING to arm behind it -- the last dealt card placed
# after the stocks ran dry -- committed as history's top, so undoing the End lands on it.
func _commit_an_empty_entrance(game: Game) -> void:
	_play_area.ungrab_cards()
	var state := game.state
	_drain_the_stocks(state)
	for column : ArrayCardData in state.upper_zone:
		column.datas.clear()
	state.revision += 1
	game.save_state()
	_play_area.setup_gui()
	await get_tree().process_frame

## Row 7.7 (`GAP-009`=b): undoing an End reached with the Entrance EMPTY re-arms nothing, and the pad player still lands on a board control.
func test_undo_from_an_end_reached_outcome_with_an_empty_entrance() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _commit_an_empty_entrance(view.game)
	check(TestGridFixtures.leftmost_entrance_slot() == -1 and view.game.state.stocks_are_empty(),
			"7.7: sanity: the Entrance and every stock are empty before End")
	await _end_the_show_by_its_button(view)
	await get_tree().process_frame
	check(view.game.state.show_ended, "7.7: sanity: End with an empty Entrance ends the show")
	check(_game_viewport.gui_get_focus_owner() == view._continue_button,
			"7.7: the outcome opens with Continue holding the focus",
			str(_game_viewport.gui_get_focus_owner()))
	var undo := _outcome_undo_control(view)
	var stepped_right : Control = await _outcome_pad_step(KEY_RIGHT)
	check(undo != null and stepped_right == undo,
			"7.7: one d-pad step off Continue lands on the outcome's Undo", str(stepped_right))
	await _accept_the_focused_outcome_button(
			func() -> bool: return _game_viewport.gui_get_focus_owner() != null)
	check(not view.win_screen.visible and not view.lose_screen.visible,
			"7.7: the pad's accept on that Undo takes both outcome screens away")
	check(not view.game.state.show_ended and not view.game.processing,
			"7.7: ...leaving the show live again",
			"ended=%s busy=%s" % [view.game.state.show_ended, view.game.processing])
	check(_play_area.selected_cards.is_empty() and TestGridFixtures.leftmost_entrance_slot() == -1,
			"7.7: sanity: the undone End put back an empty Entrance",
			str(_play_area.selected_cards.size()))
	var owner := _game_viewport.gui_get_focus_owner()
	var on_a_cell := owner != null and _play_area.ui_data.has(owner) \
			and _zone_card_of(_play_area.ui_data[owner]) != null
	check(on_a_cell,
			"7.7: the picture viewport's focus owner is a grid cell's control inside the board, "
			+ "so a pad can move from it with nothing in hand",
			"picture=%s root=%s" % [owner, _booted_viewport.gui_get_focus_owner()])
	await _end_main_fixture()

## A card leaving the board lands on its pile, which is drawn in the window, not in the picture.
func test_a_card_leaving_the_board_flies_to_its_pile() -> void:
	await _start_game_fixture(Vector2i(600, 1000))
	var view := _main._pictures[&"game"].screen_root as GameView
	await _await_camera_transform_settled()
	var leaving : Array[CardData] = []
	for data : CardData in _play_area.data_card:
		if data.stage == CardData.Stage.PLAY: leaving.append(data)
	check(leaving.size() >= 2, "the deal puts two cards on the board", str(leaving.size()))
	var discarded := _play_area.data_card[leaving[0]] as CardVisual
	var ruled := _play_area.data_card[leaving[1]] as CardVisual
	await view.game.effect_api.discard_data(leaving[0])
	_check_flight_lands_on(view, discarded, view.discard_ui, "the Discard pile")
	view.game.effect_api.add_rules_card(leaving[1])
	_check_flight_lands_on(view, ruled, view.rules_ui, "the Rules pile")
	await _end_main_fixture()

# The pile's button centre goes through the picture's one owned conversion, so a flight aimed at
# the pile's raw window pixels misses it at any window the picture does not fill 1:1.
func _check_flight_lands_on(view: GameView, flight: CardVisual, pile: Control,
		label: String) -> void:
	flight.move_tween.custom_step(view.game.get_delay())
	var window := _container.get_viewport().get_visible_rect().size
	var picture_window := view.wall_picture.local_rect_beside(window, Rect2(), false)
	var button_centre := (pile.get_node(^"Button") as Control).get_global_rect().get_center()
	var expected := picture_window.position + button_centre / window * picture_window.size
	check(flight.global_position.distance_to(expected) <= 1.0,
			"a card leaving the board lands on %s" % label,
			"%s vs %s" % [flight.global_position, expected])

# The game's one container sits under the wall's ALWAYS overlay and keeps answering input under the
# session-long pause an earlier wall test in this suite leaves on, so a bare one runs the same way.
func _build_container() -> HudContainer:
	var container : HudContainer = HUD_CONTAINER_SCENE.instantiate()
	container.process_mode = Node.PROCESS_MODE_ALWAYS
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

# ------------------------------------------------------------------ fixtures (S2)

# The wall keeps the session-long pause its own `_ready()` sets, so an unfocused screen stays frozen
# as it is in the game.
func _build_wall() -> Wall:
	return TestMainHost.mount(self, self, WALL_SCENE) as Wall

# A real, headless show, parked/restored the same way `_stand_up_grids` (`Tests/UI/test_grid_view.gd`).
# `container` is hand-carried onto the view before it enters the tree, matching how
# `Main.enter_game()` binds a real wall's own `HudContainer` (no `Main` built here).
func _stand_up_view(host: Node, container: HudContainer) -> GameView:
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	view.hud_container = container
	host.add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view.game
	return view

# Leaves the view IN MEMORY, so Godot's own drop-on-free auto-disconnect never fires -- only the
# container's one-shot `tree_exiting` disconnect can discriminate a check on a dropped connection.
func _leave_tree_without_freeing(node: Node) -> void:
	remove_child(node)

func _tear_down_view(view: GameView, prev_run: RunState, prev_save_info: RunState) -> void:
	view.queue_free()
	await get_tree().process_frame
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

func _collect_unique_names(node: Node, owner: Node, out: Array[StringName]) -> void:
	for child : Node in node.get_children():
		if child.owner == owner and child.unique_name_in_owner:
			out.append(child.name)
		_collect_unique_names(child, owner, out)

func _has_named_descendant(node: Node, target: StringName) -> bool:
	if node.name == target: return true
	for child : Node in node.get_children():
		if _has_named_descendant(child, target): return true
	return false

# ------------------------------------------------------------------ the game screen's HUD members

# Read back through the real `wall.tscn`'s own `%Overlay/HudContainer`, never a standalone
# instance, so this fails if the wall stops mounting it.
func test_game_hud_holds_exactly_the_nine_members() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	var expected : Array[StringName] = [
		&"Goal", &"Total", &"Combo", &"Deck", &"Discard", &"Rules", &"Undo", &"Submit",
		&"PlanLayer"]
	names.sort()
	expected.sort()
	check(names == expected,
			"GameHud holds exactly Deck, Discard, Rules, Goal, Total, Combo, Undo, End, Marks (C4)",
			str(names))
	await TestMainHost.unmount(self, wall)

# Checked across BOTH `game_view.tscn` and `wall.tscn` -- the furniture migrated out of the view
# and into the container, so scanning only one would miss a retired node reintroduced in the other.
func test_no_retired_furniture_nodes_remain() -> void:
	var view : GameView = GAME_VIEW_SCENE.instantiate()
	var wall : Wall = WALL_SCENE.instantiate()
	for target : StringName in ([&"MultScore", &"Preview"] as Array[StringName]):
		check(not _has_named_descendant(view, target) and not _has_named_descendant(wall, target),
				"no %%%s node exists anywhere under the game screen" % target)
	view.free()
	wall.free()

# The sidebar draws UNDER the Back/Forward/Wall buttons, which stay on top and stay pressable --
# read as sibling DRAW ORDER inside `%Overlay`, the way the engine decides it.
func test_overlay_buttons_draw_above_the_hud_container() -> void:
	var wall := _build_wall()
	var overlay : CanvasLayer = wall.get_node(^"%Overlay")
	var container : Node = overlay.get_node(^"HudContainer")
	var back_button : Control = overlay.get_node(^"%BackButton")
	var forward_button : Control = overlay.get_node(^"%ForwardButton")
	var wall_button : Control = overlay.get_node(^"%WallButton")
	check(container.get_index() < back_button.get_index()
			and container.get_index() < forward_button.get_index()
			and container.get_index() < wall_button.get_index(),
			"the container sits BEHIND the Back/Forward/Wall buttons in draw order",
			"container=%d back=%d forward=%d wall=%d" % [container.get_index(),
					back_button.get_index(), forward_button.get_index(), wall_button.get_index()])
	await TestMainHost.unmount(self, wall)

# ------------------------------------------------------------------ every control reachable

func _assert_visible_and_sized(control: Control, window_size: Vector2i, ctx: String) -> void:
	check(control.is_visible_in_tree(), "%s is visible" % ctx)
	check(control.size.x > 0.0 and control.size.y > 0.0, "%s has non-zero size" % ctx)
	var window_rect := Rect2(Vector2.ZERO, Vector2(window_size))
	check(window_rect.encloses(control.get_global_rect()),
			"%s's rect sits inside the window" % ctx, str(control.get_global_rect()))

# The five interactive members hit-test through a real mouse-motion event routed through the
# viewport, the way the engine decides hover. `Label`'s engine default is `MOUSE_FILTER_IGNORE`
# (no hover at all), so Goal/Total/Combo are proven reachable geometrically instead.
func test_every_hud_member_is_visible_and_reachable() -> void:
	var booted := await TestMainHost.boot(self, Vector2i(1280, 720), WALL_SCENE)
	var viewport : SubViewport = booted[0]
	var wall : Wall = booted[1]
	var overlay : CanvasLayer = wall.get_node(^"%Overlay")
	var container : HudContainer = overlay.get_node(^"HudContainer")
	container.submit_button.visible = true

	var clickable : Dictionary = {
		"Deck": container.deck_ui.get_node(^"Button") as Control,
		"Discard": container.discard_ui.get_node(^"Button") as Control,
		"Rules": container.rules_ui.get_node(^"Button") as Control,
		"Undo": container.undo_button as Control,
		"Submit": container.submit_button as Control,
	}
	for ctx : String in clickable:
		var control : Control = clickable[ctx]
		_assert_visible_and_sized(control, viewport.size, ctx)
		var motion := InputEventMouseMotion.new()
		motion.position = control.get_global_rect().get_center()
		viewport.push_input(motion)
		await get_tree().process_frame
		check(viewport.gui_get_hovered_control() == control,
				"%s's rect centre hit-tests to itself" % ctx)

	var readable : Dictionary = {
		"Goal": container.goal_label.get_parent() as Control,
		"Total": container.total_label.get_parent() as Control,
		"Combo": container.combo_label as Control,
	}
	for ctx : String in readable:
		_assert_visible_and_sized(readable[ctx] as Control, viewport.size, ctx)

	await _free_booted_main(viewport, wall)

# S2d: the caption and value halves of each number sat on top of each other before `Goal`/`Total`
# became `HBoxContainer`s, so a bare rect-intersection check proves the fix without re-reading
# pixels. A real `SubViewport` frame settles the containers' layout before the rects are read.
func test_number_captions_and_values_do_not_overlap() -> void:
	var booted := await TestMainHost.boot(self, Vector2i(1280, 720), WALL_SCENE)
	var viewport : SubViewport = booted[0]
	var wall : Wall = booted[1]
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	await get_tree().process_frame
	var labels : Array[Control] = [
		container.goal_label.get_parent().get_node(^"Caption") as Control,
		container.goal_label,
		container.total_label.get_parent().get_node(^"Caption") as Control,
		container.total_label,
		container.combo_label,
	]
	for label : Control in labels:
		check(label.size.x > 0.0 and label.size.y > 0.0,
				"%s has non-zero size" % label.name, str(label.size))
	for i : int in labels.size():
		for j : int in range(i + 1, labels.size()):
			check(not labels[i].get_global_rect().intersects(labels[j].get_global_rect()),
					"%s and %s do not overlap" % [labels[i].get_parent().name, labels[j].get_parent().name])
	await _free_booted_main(viewport, wall)

## Goal, Total and board-total-times-combo are on screen from the first frame, combo 1 included, and track GameData after a scoring placement.
func test_the_hud_always_shows_goal_total_and_the_score_line() -> void:
	await _start_game_fixture()
	var state := CardEnvironment.get_current_game().state
	state.goal = GOAL_OUT_OF_REACH
	await _check_the_hud_reads(state, "before any score")
	for attempt : int in ENTRANCE_REFILL_PLACEMENTS:
		if state.board_total() > 0.0: break
		if await _lift_and_place_a_card() == null: break
	check(state.board_total() > 0.0, "a few placements score on the board",
			str(state.board_total()))
	await _check_the_hud_reads(state, "after a scoring placement")
	await _end_main_fixture()

func _check_the_hud_reads(state: GameData, moment: String) -> void:
	await get_tree().process_frame
	var labels : Dictionary[String, Label] = {"Goal": _container.goal_label,
			"Total": _container.total_label, "Score line": _container.combo_label}
	for label_name : String in labels:
		check(labels[label_name].is_visible_in_tree(), "%s: %s is on screen" % [moment, label_name],
				labels[label_name].text)
	check(_container.goal_label.text == str(state.goal), "%s: Goal reads the goal" % moment,
			_container.goal_label.text)
	check(_container.total_label.text == str(state.live_total()),
			"%s: Total reads live_total()" % moment, _container.total_label.text)
	var line := TRANSLATION.find('GAME_SCORE_LINE') % [state.board_total(), state.combo_mult()]
	check(_container.combo_label.text == line,
			"%s: the score line reads board_total x combo_mult" % moment,
			"%s vs %s" % [_container.combo_label.text, line])
	check(_container.combo_label.text != "GAME_SCORE_LINE",
			"%s: the score line's key resolves in the locale" % moment, _container.combo_label.text)

# S2d/Q46: the HUD's CONTENT must start below the overlay's Back/Forward/Wall row -- the panel
# itself may still draw under it (draw order is `test_overlay_buttons_draw_above_the_hud_container`).
## Harness-scale only: the fixture draws at content scale 1, where the player's window does not.
func test_game_hud_members_start_below_the_overlay_button_band() -> void:
	var booted := await TestMainHost.boot(self, Vector2i(1280, 720), WALL_SCENE)
	var viewport : SubViewport = booted[0]
	var wall : Wall = booted[1]
	var overlay : WallOverlay = wall.get_node(^"%Overlay")
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	await get_tree().process_frame
	var band_bottom := overlay.button_band_bottom()
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	for member_name : StringName in names:
		var control : Control = container.get_node(NodePath("%" + member_name)) as Control
		check(control.get_global_rect().position.y >= band_bottom,
				"%s starts below the overlay button band" % member_name, str(control.get_global_rect()))
	await _free_booted_main(viewport, wall)

# A same-aspect window reports the project's own base resolution as its logical size under
# `canvas_items`/`expand` stretch.
## No HUD member reaches past its own container's rect at a 1280x720 window, whatever the container is set to; harness-scale only.
func test_game_hud_members_stay_inside_the_container_at_a_side_window() -> void:
	var booted := await TestMainHost.boot(self, Vector2i(PlayArea.reference_window_size()),
			WALL_SCENE)
	var viewport : SubViewport = booted[0]
	var wall : Wall = booted[1]
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	await get_tree().process_frame
	check(game_hud.get_combined_minimum_size().x <= container.size.x,
			"the HUD's minimum width never exceeds the container",
			"%.1f vs container %.1f" % [game_hud.get_combined_minimum_size().x, container.size.x])
	var container_rect := Rect2(container.global_position, container.size)
	var names : Array[StringName] = []
	_collect_unique_names(game_hud, container, names)
	for member_name : StringName in names:
		var control : Control = container.get_node(NodePath("%" + member_name)) as Control
		check(container_rect.encloses(control.get_global_rect()),
				"%s's rect sits inside the container" % member_name,
				"%s vs container %s" % [control.get_global_rect(), container_rect])
	_check_button_labels_fit_their_own_minimum(container)
	await _free_booted_main(viewport, wall)

# A Button's own TEXT overflows its rect silently (no layout error) once its assigned size is
# squeezed below what the label needs, so this checks each button's OWN minimum, not its
# wrapping Control's.
func _check_button_labels_fit_their_own_minimum(container : HudContainer) -> void:
	var buttons : Dictionary = {
		"Deck": container.deck_ui.get_node(^"Button") as Button,
		"Discard": container.discard_ui.get_node(^"Button") as Button,
		"Rules": container.rules_ui.get_node(^"Button") as Button,
		"Undo": container.undo_button,
		"Submit": container.submit_button,
	}
	for ctx : String in buttons:
		var button : Button = buttons[ctx]
		check(button.get_minimum_size().x <= button.size.x + 0.5,
				"%s's own label fits the space it was given" % ctx,
				"needs %.1f, has %.1f" % [button.get_minimum_size().x, button.size.x])

# ------------------------------------------------------------------ the wiring crosses from a
# per-show GameView to a container node that OUTLIVES it

# Presses the container's own End button via its `pressed` signal and asserts the LIVE
# `GameView`'s own game-side effect -- `end_show()` marking the state ended -- not a test flag.
func test_pressing_end_reaches_the_live_game_views_handler() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var view := await _stand_up_view(self, container)
	check(view.submit_button == container.submit_button,
			"sanity: the live view bound the shared container's own End button")
	check(not view.game.state.show_ended, "sanity: the show has not ended yet")

	container.submit_button.pressed.emit()
	await get_tree().process_frame

	check(view.game.state.show_ended,
			"pressing the container's End button reached the live GameView's own end_show()")
	await _tear_down_view(view, prev_run, prev_save_info)
	await TestMainHost.unmount(self, wall)

# The container OUTLIVES a per-show `GameView`: a first show's view tears down, its connections
# must be gone, and a second view alone receives the next press -- the SAME container, never a
# fresh one.
func test_a_second_shows_view_receives_the_press_after_the_first_tears_down() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")

	var view_one := await _stand_up_view(self, container)
	var connections : Array = container._screen_connections[view_one].duplicate()

	_leave_tree_without_freeing(view_one)
	for pair : Array in connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		check(not sig.is_connected(callable),
				"the first view's container connection is gone once it leaves the tree")

	container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(not view_one.game.state.show_ended,
			"a press after the first view leaves the tree does not reach its handler")
	view_one.free()

	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var view_two : GameView = GAME_VIEW_SCENE.instantiate()
	view_two.hud_container = container
	add_child(view_two)
	await get_tree().process_frame
	await get_tree().process_frame
	CardEnvironment.CURRENT = view_two.game
	check(not view_two.game.state.show_ended, "sanity: the second show's own state starts fresh")

	container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(view_two.game.state.show_ended,
			"one press reaches exactly the second GameView after the first tore down")

	await _tear_down_view(view_two, prev_run, prev_save_info)
	await TestMainHost.unmount(self, wall)

# ------------------------------------------------------------------ scoped to its own wall

# A second, unrelated `Wall`'s `HudContainer` alive FIRST (the shape a concurrent suite's own
# wall takes in the real run) proves the GameView binds to ITS OWN wall's container, never
# whichever one happens to exist first.
func test_the_game_views_hud_container_is_scoped_to_its_own_wall() -> void:
	var other_wall := _build_wall()
	var other_container : HudContainer = other_wall.get_node(^"%Overlay/HudContainer")
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main := TestMainHost.mount(self, self, MAIN_SCENE) as Main
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game

	other_container.submit_button.pressed.emit()
	await get_tree().process_frame
	check(not view.game.state.show_ended,
			"a press on an unrelated container does not reach this wall's GameView")

	view.submit_button.pressed.emit()
	await get_tree().process_frame
	check(view.game.state.show_ended,
			"a press on this wall's own container reaches its GameView")

	await TestMainHost.unmount(self, main)
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info
	await TestMainHost.unmount(self, other_wall)

# ------------------------------------------------------------------ the container's geometry

## The resting inset at the picture's own aspect: the sidebar's fraction of the picture's width.
func _sidebar_share_of_the_picture() -> float:
	var settings := SettingsManager.settings
	return settings.container_size_fraction * float(PlayArea.game_picture_design_size(settings).x)

## At the picture's own aspect the window cancels and the cap never bites -- the board is inset the sidebar's share of the picture at any 16:9 window size, 4K included; harness-scale only.
func test_the_inset_is_the_sidebars_share_at_the_pictures_own_aspect() -> void:
	await _start_game_fixture()
	for window : Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
			Vector2i(3840, 2160)]:
		await _resize_viewport(_booted_viewport, window)
		check(absf(_play_area.board_inset_left - _sidebar_share_of_the_picture()) <= 0.5,
				"the board publishes the sidebar's share of the picture as its inset at %s (3.1)"
				% window, "%.3f vs %.3f" % [_play_area.board_inset_left,
				_sidebar_share_of_the_picture()])
	await _end_main_fixture()

## An ultrawide window clamps the container, flush against the band's inner edge, empty space outboard; harness-scale only.
func test_an_ultrawide_window_clamps_and_narrows() -> void:
	await _start_game_fixture(Vector2i(3840, 1080))
	var settings := PlayerSettings.new()
	var window := Vector2(3840.0, 1080.0)
	var rect := HudContainer.rect_for_window(window, settings)
#The picture covers the window by its width here, so one window px is design.x / window.x of it.
	var clamped := rect.size.x * float(PlayArea.game_picture_design_size(settings).x) / window.x
	check(absf(_play_area.board_inset_left - clamped) <= 0.5,
			"an ultrawide window clamps and narrows the board's published inset (3.2)",
			"%.3f vs %.3f" % [_play_area.board_inset_left, clamped])
	var inner_edge := settings.container_size_fraction * window.x
	check(is_equal_approx(rect.position.x + rect.size.x, inner_edge),
			"the container's right edge is flush against the band's inner edge")
	check(rect.position.x > 0.0,
			"the empty space from the clamp sits outboard of the container")
	await _end_main_fixture()

## The container moves to the top band once the leftover play area would be taller than wide; harness-scale only.
func test_the_container_moves_to_the_top_when_the_leftover_would_be_taller_than_wide() -> void:
	await _start_game_fixture(Vector2i(600, 1000))
	var settings := PlayerSettings.new()
	var window := Vector2(600.0, 1000.0)
	check(HudContainer.container_is_top(window, settings),
			"a portrait window puts the container on the top band")
	var crop : Vector2 = GameView.board_space_beside(window, Rect2(), true).position
	check(_play_area.board_inset_top > crop.y
				and is_equal_approx(_play_area.board_inset_left, crop.x),
			"...and the container's own reserve goes on the top, the left being the crop alone (3.3)",
			"top %.3f, left %.3f, crop %s" % [_play_area.board_inset_top,
				_play_area.board_inset_left, crop])
	var rect := HudContainer.rect_for_window(window, settings)
	check(is_equal_approx(rect.size.x, window.x),
			"the top container spans the window's full width", "%.3f vs %.3f" % [rect.size.x, window.x])
	check(rect.size.y > 0.0 and rect.size.y < window.y,
			"the top container's height is the fractional/clamped container_px", "%.3f" % rect.size.y)
	await _end_main_fixture()

## A covering picture is cropped on every window narrower than its own aspect: the board's region must still clear the container and stay on screen there (3.5); harness-scale only.
func test_the_boards_region_clears_the_container_on_a_cropped_window() -> void:
	await _start_game_fixture()
	for size : Vector2i in [Vector2i(1920, 1200), Vector2i(1600, 1200), Vector2i(600, 1000)]:
		await _resize_viewport(_booted_viewport, size)
		_play_area.flush_rebuild()
		await _settle_scroll_x(_play_area)
		var window := Vector2(size)
		var top := HudContainer.container_is_top(window, PlayArea.settings())
		var visible := GameView.board_space_beside(window, Rect2(), top)
		var remaining := GameView.board_space_beside(window, _container.container_rect(), top)
		var band := _band_rect_in_picture(visible, remaining, top)
		var board := _sidebar_screen_rect(_play_area.scroll_container)
		check(not band.grow(-1.0).intersects(board),
				"no part of the board's region sits under the container at %s (3.5)" % size,
				"board %s vs band %s" % [board, band])
		check(visible.grow(1.0).encloses(board),
				"the board's region stays inside the visible picture at %s (3.5)" % size,
				"board %s vs visible %s" % [board, visible])
		check(absf(board.position.x - remaining.position.x) <= 1.0
					and absf(board.end.x - remaining.end.x) <= 1.0,
				"the board's region FILLS the width left beside the container at %s (3.5)" % size,
				"board %.1f..%.1f vs %.1f..%.1f" % [board.position.x, board.end.x,
					remaining.position.x, remaining.end.x])
	await _end_main_fixture()

# ------------------------------------------------------------------ the board's centre after S2

#Wait for the Entrance to come to REST: a placement commits it and it slides to its grid's columns.

#⚠ THE TRAVELLED FRACTION IS PART OF "AT REST". The two ends of the travel are the same point
#whenever the home grid is the one centred in the window, so the drawn x can stand still through a
#whole slide and an x-only wait hands back a row that is still moving.
func _settle_entrance_x(pa: PlayArea) -> void:
	var last := Vector2.INF
	var waited := 0.0
	while waited < 3.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		var now := Vector2(pa.entrance_h_track.position.x, pa._entrance_slide)
		if now.is_equal_approx(last): return
		last = now

#A fresh show eases in from its landing, so a board read as soon as `enter_game()` returns is read
#part way to its scale.
func _await_the_opening_ease(pa: PlayArea) -> void:
	var waited := 0.0
	while waited < 3.0 and pa._view_ease < 1.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()

func _settle_scroll_x(pa: PlayArea) -> void:
	var last := INF
	var waited := 0.0
	while waited < 2.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		if is_equal_approx(pa.scroll_container.position.x, last): return
		last = pa.scroll_container.position.x

#Derived from the sidebar's own rect and the covering scale, never from the reserve the product
#computed. The set's centring inside that window is GRID VIEW's row.
## The board's window centres on the picture space the RESTING sidebar leaves, the retired controls gone; harness-scale only.
func test_board_centre_after_hud_migration_is_the_space_beside_the_resting_sidebar() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main := TestMainHost.mount(self, self, MAIN_SCENE) as Main
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game
	var pa := view.play_area
	await _await_the_opening_ease(pa)
	pa.flush_rebuild()
	await _settle_scroll_x(pa)

	check(not _has_named_descendant(view, &"MultScore")
			and not _has_named_descendant(view, &"Preview"),
			"sanity: MultScore/Preview are really gone from this show")
	var sidebar : HudContainer = main.wall.get_node(^"%HudContainer")
	var window := sidebar.get_viewport().get_visible_rect().size
	check(is_equal_approx(sidebar.slid_fraction(), 1.0)
			and not HudContainer.container_is_top(window, PlayArea.settings()),
			"precondition: the sidebar rests at the window's side",
			"slid %.3f, window %s" % [sidebar.slid_fraction(), window])
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	var beside := (sidebar.get_global_rect().end.x / picture_scale + design.x) * 0.5
	var centre := _sidebar_screen_rect(pa.scroll_container).get_center().x
	check(absf(centre - beside) <= 0.5,
			"the board is centred (within 0.5px) in the space beside the resting sidebar, "
			+ "the retired controls gone",
			"board centre %.3f vs the space's %.3f picture px" % [centre, beside])

	await TestMainHost.unmount(self, main)
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# ------------------------------------------------------------------ the geometry's own wiring

## A real resize (private `SubViewport`) moves the container and re-publishes `board_inset_left`; harness-scale only.
func test_a_real_resize_moves_the_container_and_republishes_the_inset() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var booted := await _boot_main_at(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game

	viewport.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	await get_tree().process_frame

	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window := Vector2(viewport.size)
	var expected_rect := HudContainer.rect_for_window(window, PlayArea.settings())
	check(Rect2(container.position, container.size).is_equal_approx(expected_rect),
			"the container's own rect follows a real resize",
			"%s vs %s" % [Rect2(container.position, container.size), expected_rect])
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	check(absf(view.play_area.board_inset_left - expected_rect.size.x / picture_scale) <= 0.5,
			"board_inset_left is re-published for the new size")

	await _check_board_inset_left_on_ultrawide_resize(viewport, view, design)

	await _free_booted_main(viewport, main)
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# An aspect off 16:9 is what tells `min` and `max` apart in `picture_scale`, unlike the earlier
# 1920x1080 resize, which shares the picture's own aspect where the two agree.
func _check_board_inset_left_on_ultrawide_resize(viewport : SubViewport, view : GameView, design : Vector2) -> void:
	viewport.size = Vector2i(3840, 1080)
	await get_tree().process_frame
	await get_tree().process_frame
	var ultrawide := Vector2(viewport.size)
	var ultrawide_rect := HudContainer.rect_for_window(ultrawide, PlayArea.settings())
	var ultrawide_scale := maxf(ultrawide.x / design.x, ultrawide.y / design.y)
	check(absf(view.play_area.board_inset_left - ultrawide_rect.size.x / ultrawide_scale) <= 0.5,
			"board_inset_left uses the covering picture_scale off an ultrawide resize",
			"%.3f vs %.3f" % [view.play_area.board_inset_left, ultrawide_rect.size.x / ultrawide_scale])

# A board sized off the whole height spills up under the band.
## The top case fits the board to the height LEFT UNDER the band, as the side case fits it to the width beside the container; harness-scale only.
func test_a_top_case_resize_fits_the_board_under_the_band() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var booted := await _boot_main_at(Vector2i(600, 1000))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	await main.enter_game()
	var game_wp : WallPicture = main._pictures[&"game"]
	var view := game_wp.screen_root as GameView
	CardEnvironment.CURRENT = view.game
	var pa := view.play_area
	await _settle_scroll_x(pa)
	check(view.game.state.grids.size() > 0,
			"a fresh show deals at least one grid for the Entrance to sit beside")

	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window := Vector2(viewport.size)
	check(HudContainer.container_is_top(window, PlayArea.settings()),
			"sanity: this window puts the container on the top band")
	var band := container.container_rect()
	var design := Vector2(PlayArea.game_picture_design_size(SettingsManager.settings))
	var picture_scale := maxf(window.x / design.x, window.y / design.y)
	check(is_equal_approx(pa.board_inset_top, band.size.y / picture_scale),
			"board_inset_top equals the band's height converted to picture px",
			"%.3f vs %.3f" % [pa.board_inset_top, band.size.y / picture_scale])
	var crop := GameView.board_space_beside(window, Rect2(), true).position
	check(is_equal_approx(pa.board_inset_left, crop.x),
			"board_inset_left is the covering picture's own crop in the top case",
			"%.3f vs %.3f" % [pa.board_inset_left, crop.x])

	var grid_rect := _sidebar_screen_rect(pa._cells_root(pa.grid_container.get_child(0) as Control))
	check(grid_rect.position.y >= band.end.y,
			"the grid's top edge sits below the band", "%s vs band bottom %.3f" % [grid_rect, band.end.y])
#ONLY A PLACEMENT gives the Entrance a grid, so the commitment is written here rather than assumed
#from the one-grid show's focus; uncommitted it is centred under no grid, which is GRID VIEW's rule.
	view.game.state.committed_grid = 0
	await _settle_entrance_x(pa)
	var strip_rect := _sidebar_screen_rect(pa.upper_zone_right)
	check(strip_rect.position.y >= band.end.y,
			"the Entrance strip's top edge sits below the band",
			"%s vs band bottom %.3f" % [strip_rect, band.end.y])
	check(pa.entrance_home_grid() == 0,
			"precondition: a commitment to grid 0 gives the Entrance its home, so it is drawn under "
			+ "that grid's columns rather than centred under no grid",
			"home grid %d, committed %d" % [pa.entrance_home_grid(), view.game.state.committed_grid])
	check(absf(grid_rect.get_center().x - strip_rect.get_center().x) <= 2.0,
			"the grid and the Entrance share a centre in the top case",
			"grid %.3f vs strip %.3f" % [grid_rect.get_center().x, strip_rect.get_center().x])

	await _free_booted_main(viewport, main)
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

## A control's rect as drawn -- carries every scale above it, since `global_position` alone drops the board's zoom.
func _sidebar_screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform()
	return Rect2(t.origin, t.get_scale() * c.size)

## The part of a picture the container covers, in that picture's own space: `visible` less `remaining`, the space left beside it.
func _band_rect_in_picture(visible: Rect2, remaining: Rect2, top: bool) -> Rect2:
	if top: return Rect2(visible.position, Vector2(visible.size.x, visible.size.y - remaining.size.y))
	return Rect2(visible.position, Vector2(visible.size.x - remaining.size.x, visible.size.y))

# ------------------------------------------------------------ the overlay slides, it never insets

# The window rect a picture is actually DRAWN into -- its packed rect through the wall camera's
# live zoom and position. ROOT WINDOW space (the booted `SubViewport`'s own), the space the
# container's rects are in; everything read off a board control is in that picture's own space.
func _drawn_picture_rect(main: Main, id: StringName) -> Rect2:
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	var rect : PictureRect = main._rects[id]
	var window : Vector2 = main.hud_container.get_viewport().get_visible_rect().size
	var zoom := camera.zoom.x
	var drawn := rect.size * zoom
	return Rect2((rect.centre - camera.position) * zoom + window / 2.0 - drawn / 2.0, drawn)

## Every edge of `drawn` reaches the window's own or passes it -- no strip of bare wall anywhere, least of all beside the sidebar.
func _check_covers_the_window(drawn: Rect2, window: Vector2, label: String) -> void:
	check(drawn.position.x <= 1.0 and drawn.position.y <= 1.0
				and drawn.end.x >= window.x - 1.0 and drawn.end.y >= window.y - 1.0,
			label, "%s vs window %s" % [drawn, window])

# The container's own fraction, its drawn x and the camera's position, sampled once a frame while
# a route nobody awaited runs to its end. A STILL FRAME CANNOT SHOW A SLIDE: only the sequence can
# say the sidebar passed through the positions between, and that the camera held still while it did.
func _sample_the_slide(main: Main, settled: Callable) -> Array[Array]:
	var samples : Array[Array] = []
	var container := main.hud_container
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	while samples.size() < 900:
		samples.append([container.slid_fraction(), container.position.x, camera.position,
				Time.get_ticks_msec()])
		if settled.call(): break
		await get_tree().process_frame
	return samples

# The samples taken while the container was neither fully in nor fully out -- the slide itself.
# ⚠ `from` DISCARDS EVERYTHING BEFORE IT: a whole enter carries a slide OUT, a camera travel and
# then the slide IN, and reading all three as one run says the sidebar reversed and the camera moved.
func _mid_slide(samples: Array[Array], from: int = 0) -> Array[Array]:
	var mid : Array[Array] = []
	for i : int in range(from, samples.size()):
		var f : float = samples[i][0]
		if f > 0.001 and f < 0.999: mid.append(samples[i])
	return mid

## The last sample at which the container was still fully out -- where the way IN begins.
func _last_fully_out(samples: Array[Array]) -> int:
	var last := 0
	for i : int in samples.size():
		if (samples[i][0] as float) <= 0.001: last = i
	return last

## The menu carries no HUD, so its sidebar is there only while it has something to show: the deck picker, its viewer, or a description.
func test_the_sidebar_is_hidden_on_the_menu_until_the_picker_shows_something() -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var booted := await _boot_main_at(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var band := container.container_rect()
	check(not container.visible, "the menu's sidebar is hidden with nothing to show")
	check(container.published_rect().size.x <= 0.001,
			"...and it insets the menu by nothing at all",
			"%.3f" % container.published_rect().size.x)
	check(not container.get_global_rect().intersects(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))),
			"...and it is drawn wholly off the window, so it is not under the pointer either",
			str(container.get_global_rect()))
	_push_mouse_button(band.get_center(), viewport, true)
	_push_mouse_button(band.get_center(), viewport, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not container.showing_description() and not container.visible,
			"a click where the sidebar would be is not taken by it")

	await _press_new_run(main)
	await _await_the_menus_slide(container, 1.0)
	var hud_stack : Control = container.get_node(^"%HudStack")
	var empty := hud_stack.visible and not (container.get_node(^"%GameHud") as Control).visible 			and not (container.get_node(^"%MapHud") as Control).visible
	check(container.visible and is_equal_approx(container.slid_fraction(), 1.0)
			and not container.showing_description() and empty,
			"the deck picker opening slides the sidebar in, empty: neither HUD, no description",
			"slide %.3f description %s" % [container.slid_fraction(), container.showing_description()])
	var picker : DeckPicker = _the_deck_picker(main)
	var inspect : Button = (picker.rows.get_child(0) as HBoxContainer).get_child(1) as Button
	inspect.pressed.emit()
	await get_tree().process_frame
	check(container.visible and is_equal_approx(container.slid_fraction(), 1.0)
			and not container.showing_description(),
			"the picker's viewer opening keeps the sidebar in, empty",
			"slide %.3f description %s" % [container.slid_fraction(), container.showing_description()])
	var listed := _listed_viewer_cards()
	check(not listed.is_empty(), "the picker's viewer lists cards", str(listed.size()))
	if not listed.is_empty(): listed[0].grab_focus()
	await get_tree().process_frame
	check(container.showing_description(),
			"a highlight in the picker's viewer publishes a description onto the menu's sidebar")

	container.dismiss_description()
	await get_tree().process_frame
	check(container.visible and is_equal_approx(container.slid_fraction(), 1.0)
			and not container.showing_description(),
			"dismissing it leaves the sidebar in, empty, while the viewer is still open",
			"%.3f" % container.slid_fraction())
	await _close_open_viewer(viewport)
	check(container.visible and is_equal_approx(container.slid_fraction(), 1.0),
			"closing the viewer leaves the sidebar in while the picker is still up",
			"%.3f" % container.slid_fraction())
	await _close_open_viewer(viewport)
	await _await_the_menus_slide(container, 0.0)
	check(not container.visible and is_zero_approx(container.slid_fraction()),
			"closing the picker with nothing described slides the sidebar back out and hides it",
			"%.3f" % container.slid_fraction())
	await _end_booted_fixture(viewport, main)

# R1's first half, and it is about the PICTURE, not the sidebar: whatever the sidebar is doing, the
# focused picture reaches every window edge, so no bar of bare wall ever shows beside it.
## Harness-scale only: the fixture draws at content scale 1, where the player's window does not.
func test_every_focused_picture_covers_the_window_edge_to_edge() -> void:
	await _start_map_fixture()
	var window : Vector2 = _container.get_viewport().get_visible_rect().size
	_check_covers_the_window(_drawn_picture_rect(_main, &"map"), window,
			"the map covers the window edge to edge")
	await _main._focus_picture(&"start_menu")
	_check_covers_the_window(_drawn_picture_rect(_main, &"start_menu"), window,
			"the start menu covers the window edge to edge")

	var covered := true
	var worst := Rect2()
	var samples := 0
	_main.enter_game()
	while _main._move_in_flight and samples < 900:
		var drawn := _drawn_picture_rect(_main, _main._transition_dest_id if
				_main._transition_dest_id != &"" else _main._current_focus)
		if drawn.position.x > 1.0 or drawn.end.x < window.x - 1.0:
			covered = false
			worst = drawn
		samples += 1
		await get_tree().process_frame
	check(samples > 0, "sanity: the transition into the game was sampled at all", str(samples))
	check(covered, "the destination picture covers the window at every sampled transition frame",
			"worst %s vs window %s" % [worst, window])
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_check_covers_the_window(_drawn_picture_rect(_main, &"game"), window,
			"the game covers the window edge to edge once landed")
	await _end_main_fixture()

## A focused picture draws its screen at one scale on both axes, whatever the window's shape: the map at a tall window is not squashed, and neither is the game; harness-scale only.
func test_a_focused_picture_is_drawn_unstretched_at_every_window_shape() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		_check_drawn_unstretched(&"map", str(size))
		await _enter_game_fixture()
		_check_drawn_unstretched(&"game", str(size))
		await _end_main_fixture()

## In wall view every picture, the one just left among them, draws what it shows from at least one texel per window pixel on each axis: a cropped picture is no blurrier than the uncropped game.
func test_a_wall_view_picture_draws_at_least_a_texel_per_pixel() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		await _main._go_to_wall_view()
		await _await_the_wall_drawn_at_its_camera_zoom(_main)
		for id : StringName in [&"map", &"game", &"start_menu"] as Array[StringName]:
			var sprite : Sprite2D = _main._pictures[id].get_node(^"%Screen")
			var texels_per_px := Vector2.ONE / sprite.get_global_transform_with_canvas().get_scale()
			var whole_texels := Vector2.ONE - Vector2(0.5, 0.5) / sprite.region_rect.size
			check(texels_per_px.x >= whole_texels.x and texels_per_px.y >= whole_texels.y,
					"in wall view at %s the %s picture draws at least a texel per pixel" % [size, id],
					"%s texels per px, shown %s of %s" % [texels_per_px, sprite.region_rect.size,
							_main._pictures[id].viewport.size])
		await _end_main_fixture()

## Every picture the player visited -- the menu at cold launch, the map, a game -- shows its own content in wall view, frozen: a change to the screen after the leave does not reach its thumbnail.
func test_a_visited_picture_shows_its_content_in_wall_view_and_stays_frozen() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		var map_wp : WallPicture = _main._pictures[&"map"]
		var last_live : Array[Image] = [map_wp.viewport.get_texture().get_image()]
		var keep_the_live_frame := func() -> void:
			if map_wp.is_live: last_live[0] = map_wp.viewport.get_texture().get_image()
		RenderingServer.frame_post_draw.connect(keep_the_live_frame)
		await _enter_game_fixture()
		RenderingServer.frame_post_draw.disconnect(keep_the_live_frame)
		await _main._go_to_wall_view()
		await _await_the_wall_drawn_at_its_camera_zoom(_main)
		for id : StringName in [&"start_menu", &"map", &"game"] as Array[StringName]:
			var thumbnail := _main._pictures[id].viewport.get_texture().get_image()
			check(_opaque_fraction(thumbnail) > THUMBNAIL_OPAQUE_FRACTION
					and _distinct_colours(thumbnail) >= THUMBNAIL_DISTINCT_COLOURS,
					"in wall view at %s the visited %s picture shows its content" % [size, id],
					"opaque %.3f, %d colours, %s" % [_opaque_fraction(thumbnail),
							_distinct_colours(thumbnail), thumbnail.get_size()])
		var thumbnail := _main._pictures[&"map"].viewport.get_texture().get_image()
		last_live[0].resize(thumbnail.get_width(), thumbnail.get_height())
		check(_mean_colour_difference(thumbnail, last_live[0]) < THUMBNAIL_MATCH_DIFFERENCE,
				"...the map's thumbnail is its last live frame at %s" % size,
				"mean difference %.3f" % _mean_colour_difference(thumbnail, last_live[0]))
		_map.sea.color = Color.RED
		for _frame : int in FROZEN_FRAMES: await RenderingServer.frame_post_draw
		check(_mean_colour_difference(
				_main._pictures[&"map"].viewport.get_texture().get_image(), thumbnail) == 0.0,
				"...and it stays frozen: a map repainted after the leave is not re-rendered at %s" % size)
		await _end_main_fixture()

## Everything behind the pictures in wall view is the wall surface's one colour, at rest and while the camera travels out to the wall, at a landscape and a portrait window.
func test_the_wall_view_shows_one_surface_colour_behind_the_pictures() -> void:
	var settings := SettingsManager.settings
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		_booted_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var old_delay := settings.base_delay
		settings.base_delay = TRANSIT_BASE_DELAY
		var surface : ColorRect = _main.wall.get_node(^"%WallSurface")
		var worst_in_transit : Array[String] = []
		var samples := 0
		var informative := 0
		var started_ms := Time.get_ticks_msec()
		_main._go_to_wall_view()
		while _main._move_in_flight and samples < 900:
			await RenderingServer.frame_post_draw
			var uncovered := _uncovered_pixels()
			if not uncovered.is_empty(): informative += 1
			var off := _off_surface_pixels(uncovered, surface.color)
			if off.size() > worst_in_transit.size(): worst_in_transit = off
			samples += 1
		settings.base_delay = old_delay
		TestLog.line("transit at %s: %d frames, %d with wall showing, %.1f ms per sample" % [size,
				samples, informative, float(Time.get_ticks_msec() - started_ms) / maxf(samples, 1.0)])
		check(informative > TRANSIT_MIN_FRAMES,
				"sanity: the move out to the wall showed the wall on enough frames at %s" % size,
				"%d of %d frames" % [informative, samples])
		check(worst_in_transit.is_empty(),
				"in transit to the wall at %s only the surface colour shows behind the pictures" % size,
				"worst frame: %d off, first %s" % [worst_in_transit.size(), worst_in_transit.slice(0, 1)])
		await _await_the_wall_drawn_at_its_camera_zoom(_main)
		await RenderingServer.frame_post_draw
		var at_rest := _off_surface_pixels(_uncovered_pixels(), surface.color)
		check(at_rest.is_empty(),
				"in wall view at %s only the surface colour shows behind the pictures" % size,
				"%d off, first %s, surface %s" % [at_rest.size(), at_rest.slice(0, 1), surface.color])
		await _end_main_fixture()

## The suite's own delay lands the camera move in a frame or two, too few to see it in transit.
const TRANSIT_BASE_DELAY := 1.0
## Frames of the move out to the wall that show the wall, needed for the transit check to mean anything.
const TRANSIT_MIN_FRAMES := 4
## Per-channel difference a sampled window pixel may carry and still be the surface colour.
const SURFACE_COLOUR_TOLERANCE := 0.02
## Window pixels grown around each drawn picture part: its antialiased edge, not the wall.
const PICTURE_EDGE_MARGIN := 2.0

# The window pixels, on a stride, that lie outside every picture part and overlay control: the
# wall itself, wherever it shows.
func _uncovered_pixels() -> Dictionary[Vector2i, Color]:
	var image := _booted_viewport.get_texture().get_image()
	var columns := ceili(float(image.get_width()) / THUMBNAIL_SAMPLE_STEP)
	var rows := ceili(float(image.get_height()) / THUMBNAIL_SAMPLE_STEP)
	var covered := PackedByteArray()
	covered.resize(columns * rows)
	for r : Rect2 in _drawn_wall_view_parts():
		for row : int in range(clampi(ceili(r.position.y / THUMBNAIL_SAMPLE_STEP), 0, rows),
				clampi(ceili(r.end.y / THUMBNAIL_SAMPLE_STEP), 0, rows)):
			for column : int in range(clampi(ceili(r.position.x / THUMBNAIL_SAMPLE_STEP), 0, columns),
					clampi(ceili(r.end.x / THUMBNAIL_SAMPLE_STEP), 0, columns)):
				covered[row * columns + column] = 1
	var uncovered : Dictionary[Vector2i, Color] = {}
	for row : int in rows:
		for column : int in columns:
			if covered[row * columns + column] == 0:
				var at := Vector2i(column, row) * THUMBNAIL_SAMPLE_STEP
				uncovered[at] = image.get_pixel(at.x, at.y)
	return uncovered

# Each uncovered pixel that is not `surface_colour`, as its place and colour.
func _off_surface_pixels(uncovered: Dictionary[Vector2i, Color], surface_colour: Color) -> Array[String]:
	var off : Array[String] = []
	for at : Vector2i in uncovered:
		var d := uncovered[at] - surface_colour
		if maxf(maxf(absf(d.r), absf(d.g)), maxf(absf(d.b), absf(d.a))) > SURFACE_COLOUR_TOLERANCE:
			off.append("%s %s" % [at, uncovered[at]])
	return off

# The window rect of every drawn picture part (screen, frame, shadow) and every shown overlay
# button, through the transform each was just drawn with.
func _drawn_wall_view_parts() -> Array[Rect2]:
	var rects : Array[Rect2] = []
	for wp : WallPicture in _main._pictures.values():
		for sprite : Sprite2D in wp.find_children("*", "Sprite2D", true, false):
			if sprite.is_visible_in_tree():
				rects.append((sprite.get_global_transform_with_canvas() * sprite.get_rect())
						.grow(PICTURE_EDGE_MARGIN))
		for part : Control in wp.find_children("*", "Control", true, false):
			if part.is_visible_in_tree():
				rects.append((part.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, part.size))
						.grow(PICTURE_EDGE_MARGIN))
	for button : Button in _main.wall.get_node(^"%Overlay").find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			rects.append(button.get_global_rect().grow(PICTURE_EDGE_MARGIN))
	return rects

## A thumbnail is the picture's own canvas, which covers its whole render target.
const THUMBNAIL_OPAQUE_FRACTION := 0.99
## More colours than a flat panel or a placeholder: any real screen has dozens.
const THUMBNAIL_DISTINCT_COLOURS := 8
## Mean per-channel difference allowed between a thumbnail and its last live frame shrunk to its size: filtering, not content.
const THUMBNAIL_MATCH_DIFFERENCE := 0.08
## Frames a frozen thumbnail is watched for a re-render.
const FROZEN_FRAMES := 10
## Sampling stride over a thumbnail's pixels.
const THUMBNAIL_SAMPLE_STEP := 4

func _opaque_fraction(image: Image) -> float:
	var opaque := 0
	var samples := 0
	for y : int in range(0, image.get_height(), THUMBNAIL_SAMPLE_STEP):
		for x : int in range(0, image.get_width(), THUMBNAIL_SAMPLE_STEP):
			samples += 1
			if image.get_pixel(x, y).a > 0.5: opaque += 1
	return float(opaque) / float(samples)

func _distinct_colours(image: Image) -> int:
	var colours : Dictionary[Color, bool] = {}
	for y : int in range(0, image.get_height(), THUMBNAIL_SAMPLE_STEP):
		for x : int in range(0, image.get_width(), THUMBNAIL_SAMPLE_STEP):
			colours[image.get_pixel(x, y)] = true
	return colours.size()

func _mean_colour_difference(a: Image, b: Image) -> float:
	var total := 0.0
	var samples := 0
	for y : int in range(0, a.get_height(), THUMBNAIL_SAMPLE_STEP):
		for x : int in range(0, a.get_width(), THUMBNAIL_SAMPLE_STEP):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += (absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)) / 3.0
			samples += 1
	return total / float(samples)

# THE CAMERA IS PHYSICS-INTERPOLATED, so the drawn canvas lags its zoom by a few frames after a
# move lands or a resize -- measured 0.785 drawn against 0.449 two frames on. Bounded, so a lag that never
# closes fails the check rather than hanging.
func _await_the_wall_drawn_at_its_camera_zoom(main: Main) -> void:
	var camera : Camera2D = main.wall.get_node(^"%Camera2D")
	for _frame : int in range(120):
		if is_equal_approx(main.wall.get_viewport().get_canvas_transform().get_scale().x, camera.zoom.x):
			return
		await get_tree().process_frame

## The screen shows whole texels, so the aspect is met to half of one across the narrowest shown width, 389 px at 600x1000.
const UNSTRETCHED_TOLERANCE := 0.0015

# The drawn scale of ONE canvas pixel, per axis: the screen sprite's transform onto the window, times
# the texture pixels a canvas pixel spans, which differ once the render target is clamped.
func _check_drawn_unstretched(id: StringName, where: String) -> void:
	var picture : WallPicture = _main._pictures[id]
	var sprite : Sprite2D = picture.get_node(^"%Screen")
	var texture := Vector2(picture.viewport.size)
	var canvas := Vector2(picture.viewport.size_2d_override) \
			if picture.viewport.size_2d_override != Vector2i.ZERO else texture
	var drawn := sprite.get_global_transform_with_canvas().get_scale() * texture / canvas
	check(absf(drawn.x / drawn.y - 1.0) <= UNSTRETCHED_TOLERANCE,
			"the focused %s is drawn at one scale on both axes at %s" % [id, where],
			"drawn %s sprite %s camera %s" % [drawn, sprite.scale,
					(_main.wall.get_node(^"%Camera2D") as Camera2D).zoom])

# The slide itself, which no still frame can show: after the picture lands the sidebar travels in
# from off the window while the camera holds still, and the board's own window opens up with it.
func test_the_sidebar_slides_in_after_the_landing_and_the_board_shifts_with_it() -> void:
	await _start_map_fixture()
	var width := _container.container_rect().size.x
	_main.enter_game()
	var samples := await _sample_the_slide(_main, func() -> bool:
			return not _main._move_in_flight \
					and is_equal_approx(_main.hud_container.slid_fraction(), 1.0))
	var begins := _last_fully_out(samples)
	var rested : Vector2 = samples[begins][2]
	var mid := _mid_slide(samples, begins)
	check(mid.size() >= 3, "the sidebar passes through the positions between, frame by frame",
			"%d mid-slide samples of %d" % [mid.size(), samples.size()])
	var rising := true
	var moved := 0.0
	for i : int in range(1, mid.size()):
		if (mid[i][0] as float) < (mid[i - 1][0] as float) - 0.001: rising = false
	check(rising, "...and only ever forward, never back")
	for s : Array in mid:
		moved = maxf(moved, ((s[2] as Vector2) - rested).length())
	check(moved <= 1.0, "...while the camera holds still, the picture already landed",
			"%.3f px" % moved)
	var elapsed := float((mid[-1][3] as int) - (mid[0][3] as int)) / 1000.0
	check(elapsed <= PlayerSettings.new().container_slide_duration + 0.2,
			"...and it is done inside its own duration", "%.3f s" % elapsed)
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_play_area = view.play_area
	_game_viewport = _main._pictures[&"game"].viewport
	check(absf(_play_area.board_inset_left - _sidebar_share_of_the_picture()) <= 0.5,
			"the board ends inset by the whole sidebar, exactly where it rests today",
			"%.3f vs %.3f" % [_play_area.board_inset_left, _sidebar_share_of_the_picture()])
	check(absf(_container.position.x - _container.container_rect().position.x) <= 0.5,
			"...and the sidebar ends at its resting rect, not part way",
			"%.3f vs %.3f" % [_container.position.x, _container.container_rect().position.x])
	check(width > 0.0, "sanity: the sidebar has a width to have travelled", "%.1f" % width)
	await _end_main_fixture()

# The exact reverse, and the half that had no hook at all: the wall-view route animated its camera
# first, so the sidebar had to learn to get out of the way before the picture starts moving.
func test_the_sidebar_is_fully_out_before_the_camera_leaves() -> void:
	await _start_game_fixture()
	var camera : Camera2D = _main.wall.get_node(^"%Camera2D")
	var parked := camera.position
	check(is_equal_approx(_container.slid_fraction(), 1.0),
			"sanity: the sidebar is in before the leave", "%.3f" % _container.slid_fraction())
	_main._go_to_wall_view()
	var samples := await _sample_the_slide(_main, func() -> bool:
			return not _main._move_in_flight)
	var mid := _mid_slide(samples)
	check(mid.size() >= 3, "the sidebar travels out frame by frame before the leave",
			"%d mid-slide samples of %d" % [mid.size(), samples.size()])
	var falling := true
	var moved := 0.0
	for i : int in range(1, mid.size()):
		if (mid[i][0] as float) > (mid[i - 1][0] as float) + 0.001: falling = false
	check(falling, "...and only ever outward")
	for s : Array in mid:
		moved = maxf(moved, ((s[2] as Vector2) - parked).length())
	check(moved <= 1.0, "...with the camera still parked on the picture the whole time",
			"%.3f px" % moved)
	check(not _container.visible and is_zero_approx(_container.slid_fraction()),
			"wall view keeps no sidebar at all", "%.3f" % _container.slid_fraction())
	await _end_main_fixture()

# A leave asked for MID-SLIDE, and then a second one on top: the tween is retargeted from where it
# actually is, so the sidebar ends fully out rather than stranded. ⚠ Caught on the way IN, the only
# mid-slide a leave can interrupt -- the way out runs with `_move_in_flight` already true.
func test_a_leave_mid_slide_ends_with_the_sidebar_fully_out() -> void:
	await _start_map_fixture()
	_main.enter_game()
	for _i : int in range(900):
		var f := _main.hud_container.slid_fraction()
		if not _main._move_in_flight and f > 0.05 and f < 0.95: break
		await get_tree().process_frame
	var caught := _container.slid_fraction()
	check(caught > 0.05 and caught < 0.95, "sanity: the leave is asked for MID-slide",
			"%.3f" % caught)
	_main._go_to_wall_view()
	_main._go_to_wall_view()
	for _i : int in range(900):
		if not _main._move_in_flight and is_zero_approx(_container.slid_fraction()): break
		await get_tree().process_frame
	check(is_zero_approx(_container.slid_fraction()) and not _container.visible,
			"two leave requests mid-slide still end with the sidebar fully out, never stranded",
			"%.3f" % _container.slid_fraction())
	await _end_main_fixture()

# R1 asks for a SHIFT, not a re-scale. Fitting the board against the live reserve re-zoomed it by
# up to 1.333x as the window lost the sidebar's quarter: sampled per frame, in both views, the zoom
# must not move at all while its x travels to the centre of the whole picture.
func test_the_slide_shifts_the_board_without_re_scaling_it() -> void:
	await _start_game_fixture()
	await _check_the_slide_only_shifts("focused")
	await _enter_game_fixture()
	_play_area.open_zoomed_out()
	for _i : int in range(120):
		await get_tree().process_frame
	await _check_the_slide_only_shifts("overview")
	await _end_main_fixture()

# Leaves to wall view while sampling, so the whole travel is one direction. Rects are the game
# PICTURE's own space; `container_rect()` is ROOT WINDOW px, converted through the one owned
# conversion before the two are compared.
func _check_the_slide_only_shifts(label: String) -> void:
	var window : Vector2 = _container.get_viewport().get_visible_rect().size
	var top := HudContainer.container_is_top(window, SettingsManager.settings)
	var band := _band_rect_in_picture(GameView.board_space_beside(window, Rect2(), top),
			GameView.board_space_beside(window, _container.container_rect(), top), top)
	var pa := _play_area
	var rest_zoom := pa.board_zoom
	var rest_x := _board_content_x(pa)
	var rest_window := pa._board_window_local()
	var zooms : Array[float] = []
	var windows : Array[Vector2] = []
	var xs : Array[float] = []
	var fractions : Array[float] = []
	_main._go_to_wall_view()
	while _main._move_in_flight and fractions.size() < 900:
		fractions.append(_container.slid_fraction())
		zooms.append(pa.board_zoom)
		windows.append(pa._board_window_local())
		xs.append(_board_content_x(pa))
		await get_tree().process_frame
	var mid := 0
	var worst_zoom := rest_zoom
	var worst_window := rest_window
	for i : int in fractions.size():
		if fractions[i] <= 0.001 or fractions[i] >= 0.999: continue
		mid += 1
		if absf(zooms[i] - rest_zoom) > absf(worst_zoom - rest_zoom): worst_zoom = zooms[i]
		if windows[i].distance_to(rest_window) > worst_window.distance_to(rest_window):
			worst_window = windows[i]
	check(mid >= 3, "%s: the sidebar is sampled part way in" % label,
			"%d of %d samples" % [mid, fractions.size()])
	check(is_equal_approx(worst_zoom, rest_zoom),
			"%s: the board's zoom never moves while the sidebar slides" % label,
			"rest %.6f worst %.6f" % [rest_zoom, worst_zoom])
# The zoom alone passes a re-fit wherever the HEIGHT binds it; the board's window is the fit itself.
	check(worst_window.is_equal_approx(rest_window),
			"%s: ...nor does the board's window, so the slide is a shift and never a re-fit" % label,
			"rest %s worst %s" % [rest_window, worst_window])
	var travel := absf(xs[-1] - rest_x)
# ⚠ THE CONTENT'S OWN CENTRE, NEVER THE SCROLLER'S EDGE: the board follows the centre of the space
# the sidebar leaves, so it travels HALF the sidebar's width and ends centred in the whole picture.
# The zoom and window checks above, not the distance, are what tell a shift from a re-fit.
	check(absf(travel - band.size.x * 0.5) <= 2.0,
			"%s: ...and its content travels half the sidebar's width, centre to centre" % label,
			"%.2f vs half band %.2f" % [travel, band.size.x * 0.5])
	var monotonic := true
	for i : int in range(1, xs.size()):
		if xs[i] > xs[i - 1] + 0.001: monotonic = false
	check(monotonic, "%s: ...one way only, never back" % label)

## The centre of the board's own content, in the game picture's space: where a grid's cells actually sit.
func _board_content_x(pa: PlayArea) -> float:
	var cells := pa._cells_root(pa.grid_container.get_child(
			maxi(pa.pan_grid, 0)) as Control)
	return cells.global_position.x + cells.size.x * pa.scroll_container.scale.x * 0.5

# ⚠ THE SHAPE THAT CRASHED THE PROCESS AT EXIT: a `Main` freed while the sidebar is part way in and
# moves nobody awaited are still running. A wait that outlives its container resumes on freed
# memory, so this drives exactly that and the run's own engine-error gate is the verdict.
func test_freeing_main_mid_slide_strands_no_waiter() -> void:
	await _start_map_fixture()
	var container := _container
	_main.enter_game()
	for _i : int in range(900):
		var f := container.slid_fraction()
		if f > 0.05 and f < 0.95: break
		await get_tree().process_frame
	check(container.slid_fraction() > 0.05 and container.slid_fraction() < 0.95,
			"the sidebar is caught part way in", "%.3f" % container.slid_fraction())
	_main._go_to_wall_view()
	_main._focus_picture(&"map")
	await _end_main_fixture()
	check(not is_instance_valid(container),
			"the container goes with its Main, and nothing is left waiting on it")
	await get_tree().process_frame
	await get_tree().process_frame

# The state R1 names first, and the one nothing measured before: with the sidebar out, the screen
# beside it has the WHOLE picture -- the board's window is the full design width and the map's
# camera carries no shift. What sits under the sidebar once it rests is the board-region rows above.
func test_before_the_slide_each_screen_has_the_whole_picture() -> void:
	await _start_map_fixture()
	check(is_zero_approx(_container.slid_fraction()) \
				or is_equal_approx(_container.slid_fraction(), 1.0),
			"sanity: the map's sidebar is at one end of its travel",
			"%.3f" % _container.slid_fraction())
	await _main._go_to_wall_view()
	check(_map.controller.camera.offset.is_equal_approx(Vector2.ZERO),
			"with no sidebar the map's camera carries no shift at all",
			str(_map.controller.camera.offset))
	await _main._focus_picture(&"map")
	check(not _map.controller.camera.offset.is_equal_approx(Vector2.ZERO),
			"...and the shift comes back when the sidebar slides in for the map",
			str(_map.controller.camera.offset))
	await _end_main_fixture()

# Left by the real Wall click, so the wall-view thumbnail is the frame the player sees.
## With no sidebar the board set -- the grid AND its Entrance row -- sits in the whole picture exactly as it sits beside the resting sidebar, centre to centre; harness-scale only.
func test_wall_view_keeps_the_board_centred_in_its_picture() -> void:
	for size : Vector2i in ([Vector2i(1280, 720), Vector2i(600, 1000)] as Array[Vector2i]):
		await _start_game_fixture(size)
		var window : Vector2 = _container.get_viewport().get_visible_rect().size
		var top := HudContainer.container_is_top(window, SettingsManager.settings)
		var resting := GameView.board_space_beside(window, _container.container_rect(), top)
		var whole := GameView.board_space_beside(window, Rect2(), top)
		var parts_at_rest := _board_set_parts(_play_area)
		await _click_overlay(&"WallButton")
		for _i : int in range(900):
			if not _main._move_in_flight: break
			await get_tree().process_frame
		check(_main._current_focus == &"" and is_zero_approx(_container.slid_fraction()),
				"sanity: the Wall click reached wall view at %s" % size,
				"focus %s slide %.3f" % [_main._current_focus, _container.slid_fraction()])
		var parts_in_wall := _board_set_parts(_play_area)
		for i : int in parts_at_rest.size():
			var at_rest := parts_at_rest[i].get_center() - resting.get_center()
			var in_wall := parts_in_wall[i].get_center() - whole.get_center()
			check(at_rest.distance_to(in_wall) <= 1.0,
					"in wall view the board's %s sits centred in the whole picture as it sits beside the resting sidebar at %s"
					% [["grid", "Entrance row"][i], size],
					"from centre %s in wall view vs %s at rest" % [in_wall, at_rest])
		await _end_main_fixture()

## The board set's two parts as drawn in the game picture's own space: the resting grid's cells, then the Entrance row.
func _board_set_parts(pa: PlayArea) -> Array[Rect2]:
	var cells := pa._cells_root(pa.grid_container.get_child(maxi(pa.pan_grid, 0)) as Control)
	return [cells.get_global_rect(), pa.entrance_h_track.get_global_rect()]

# ------------------------------------------------------------------ S4: the map's own container

# (a) `MapHud` holds exactly Fame, Lap, Luck, Deck, and none of them remain on `map.tscn`'s own
# `$UI` -- the second check reads the packed scene structurally, so it needs no `_ready()`.
func test_map_hud_holds_exactly_the_four_members_and_maps_own_ui_is_empty_of_them() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var map_hud : Control = container.get_node(^"%MapHud")
	var names : Array[StringName] = []
	_collect_unique_names(map_hud, container, names)
	var expected : Array[StringName] = [&"FameLabel", &"LapLabel", &"LuckLabel", &"MapDeckButton"]
	names.sort()
	expected.sort()
	check(names == expected, "MapHud holds exactly Fame, Lap, Luck, Deck (C13)", str(names))
	var map := MAP_SCENE.instantiate()
	for target : StringName in ([&"FameLabel", &"LapLabel", &"LuckLabel", &"DeckButton"] as Array[StringName]):
		check(not _has_named_descendant(map, target),
				"no %%%s node remains under map.tscn's own $UI" % target)
	map.free()
	await TestMainHost.unmount(self, wall)

## (b) The real focus change drives which `HudStack` child shows, for all four screens.
func test_focus_change_drives_which_hud_stack_child_shows() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var main := TestMainHost.mount(self, self, MAIN_SCENE) as Main
	await get_tree().process_frame
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var game_hud : Control = container.get_node(^"%GameHud")
	var map_hud : Control = container.get_node(^"%MapHud")

	check(not container.visible,
			"start menu: the container is hidden -- the menu carries no HUD for it to show")
	check(is_zero_approx(container.slid_fraction()),
			"start menu: and it yields no inset at all", "%.3f" % container.slid_fraction())
	check(not game_hud.visible and not map_hud.visible,
			"start menu: neither GameHud nor MapHud shows")

	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	check(container.visible, "map: the container is visible")
	check(map_hud.visible and not game_hud.visible, "map: MapHud shows, GameHud hidden")

	await main.enter_game()
	check(container.visible, "game: the container is visible")
	check(game_hud.visible and not map_hud.visible, "game: GameHud shows, MapHud hidden")
	CardEnvironment.CURRENT = (main._pictures[&"game"].screen_root as GameView).game

	await main._go_to_wall_view()
	check(not container.visible, "wall overview: no container at all (Q21=b)")

	await TestMainHost.unmount(self, main)
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# (c) The container's Deck button reaches the live map's own handler, and the connection is gone
# once the map leaves the tree -- `remove_child` first, so free-time auto-disconnect cannot mask it.
func test_map_deck_button_reaches_the_live_maps_handler_then_disconnects() -> void:
	var wall := _build_wall()
	var container : HudContainer = wall.get_node(^"%Overlay/HudContainer")
	var map := MAP_SCENE.instantiate() as Map
	map.hud_container = container
	add_child(map)
	await get_tree().process_frame
	check(container.map_deck_button.pressed.is_connected(map._on_deck_clicked),
			"the container's Deck button reaches the live map's own handler")
	var connections : Array = container._screen_connections[map].duplicate()
	_leave_tree_without_freeing(map)
	for pair : Array in connections:
		var sig : Signal = pair[0] as Signal
		var callable : Callable = pair[1] as Callable
		check(not sig.is_connected(callable),
				"the map's container connection is gone once it leaves the tree")
	map.free()
	await TestMainHost.unmount(self, wall)

# Camera2D recomputes its own cached canvas transform on the idle frames AFTER `offset` is
# assigned, never the same one -- two extra frames is what it measures as settled here.
func _await_camera_transform_settled() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

# Converted through the map's own `WallPicture` cover scale and `Camera2D` zoom, never window px
# unconverted. Boots the real `Main`: a side window, a top window, then a zoom in.
## The map fits the space left beside `container_rect()`, and a zoom in keeps its view on the map; harness-scale only.
func test_maps_camera_offset_moves_beside_the_container_not_under_it() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	for size : Vector2i in ([Vector2i(1280, 720), Vector2i(600, 1000)] as Array[Vector2i]):
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		await _focus_map(main, run)
		_check_map_fits_the_space(main, str(size))
		await _free_booted_main(viewport, main)

	var zoom_booted := await _boot_main_at(Vector2i(1280, 720))
	var zoom_viewport : SubViewport = zoom_booted[0]
	var zoom_main : Main = zoom_booted[1]
	await _focus_map(zoom_main, run)
	var fit := zoom_main.map_scene.controller.camera.zoom.x
	await _zoom_the_map_in(zoom_main, 5)
	check(zoom_main.map_scene.controller.camera.zoom.x > 1.9 * fit,
			"5 real wheel-up notches zoom the map in ~2x past its fit",
			"%.3f vs fit %.3f" % [zoom_main.map_scene.controller.camera.zoom.x, fit])
	_check_the_view_stays_on_the_map(zoom_main, "1280x720 after zooming in ~2x")
	await _free_booted_main(zoom_viewport, zoom_main)

	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# Focuses the map with `run`, waiting for both its generation and the settled camera transform
# `Camera2D` needs before its offset/zoom read back correctly.
func _focus_map(main: Main, run: RunState) -> void:
	main.map_scene.start_run(run)
	await main._focus_picture(&"map")
	if not main.map_scene.controller._accepting_input:
		await main.map_scene.controller.map_ready
	await _await_camera_transform_settled()
#⚠ THE TOKEN IS STILL TRAVELLING, and a fixed number of frames is a frame-rate-dependent clock:
#the map's camera eases toward the offset the container publishes, so the measured centre drifted
#run to run. Waited on the value itself, bounded so a map that never settles surfaces as a failure.
	var wp : WallPicture = main._pictures[&"map"]
	var last := Vector2(INF, INF)
	for _i : int in range(180):
		var now : Vector2 = wp.viewport.get_canvas_transform() \
				* main.map_scene.controller.token.position
		if now.is_equal_approx(last): break
		last = now
		await get_tree().process_frame

# The space left over beside the container as far as it has slid in -- all of it at rest -- in the
# map's OWN `WallPicture` local space. `local_rect_beside()` converts the container's window px into
# that same space, the one owned conversion, so both sides of every map framing check share it.
func _map_space(main: Main) -> Rect2:
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window : Vector2 = container.get_viewport().get_visible_rect().size
	var top := HudContainer.container_is_top(window, SettingsManager.settings)
	return main._pictures[&"map"].local_rect_beside(window, container.published_rect(), top)

## The space beside the RESTING container in the overlay's own pixels, where a viewer on the sidebar's layer is fitted.
func _ui_space(main: Main) -> Rect2:
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var window : Vector2 = container.get_viewport().get_visible_rect().size
	var inset := WallPicture.inset_beside(container.container_rect(),
			HudContainer.container_is_top(window, SettingsManager.settings), 1.0)
	return Rect2(inset, window - inset)

## The map image as drawn in its picture's own space, grown by the sea buffer on every edge.
func _framed_map_rect(main: Main) -> Rect2:
	var world := main.map_scene.controller.map
	var corner := world.map_to_local(Vector2.ZERO)
	var drawn := world.get_global_transform_with_canvas() * Rect2(corner, -2.0 * corner)
	return drawn.grow(drawn.size.x * SettingsManager.settings.map_edge_buffer_fraction)

## At rest the map and its sea buffer sit inside the space beside the sidebar, centred, filling it on the binding axis.
func _check_map_fits_the_space(main: Main, label: String) -> void:
	var space := _map_space(main)
	var framed := _framed_map_rect(main)
	check(space.grow(1.0).encloses(framed),
			"the map and its sea buffer lie inside the space beside the sidebar at %s" % label,
			"%s in %s" % [framed, space])
	check(absf(framed.size.x - space.size.x) <= 1.0 or absf(framed.size.y - space.size.y) <= 1.0,
			"...filling it on the binding axis at %s" % label, "%s vs %s" % [framed.size, space.size])
	check(framed.get_center().distance_to(space.get_center()) <= 1.0,
			"...centred in it at %s" % label, "%s vs %s" % [framed.get_center(), space.get_center()])

# On each axis the map either covers the space beside the sidebar -- nothing past its sea buffer
# shows -- or, narrower than that space, sits centred in it as at the fit.
func _check_the_view_stays_on_the_map(main: Main, label: String) -> void:
	var space := _map_space(main)
	var framed := _framed_map_rect(main)
	for axis : int in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		check(_covers_or_centres(framed, space, axis),
				"nothing past the map's sea buffer shows beside the sidebar on axis %d: %s"
				% [axis, label], "%s vs %s" % [framed, space])

func _covers_or_centres(framed: Rect2, space: Rect2, axis: int) -> bool:
	if framed.size[axis] < space.size[axis]:
		return absf(framed.get_center()[axis] - space.get_center()[axis]) <= 1.0
	return framed.position[axis] <= space.position[axis] + 1.0 \
			and framed.end[axis] >= space.end[axis] - 1.0

# Every drawn frame of the LIVE map, with the sidebar at either end of its travel, covers or centres
# on both axes -- so no frame is blended between a zoomed-in view and the fit. Returns the offenders.
func _frames_past_the_map(frames: int, done: Callable) -> Array[String]:
	var wp : WallPicture = _main._pictures[&"map"]
	var past : Array[String] = []
	for f : int in range(frames):
		if done.call(): break
		var slid := _container.slid_fraction()
		if wp.is_live and (is_zero_approx(slid) or is_equal_approx(slid, 1.0)):
			var space := _map_space(_main)
			var framed := _framed_map_rect(_main)
			for axis : int in [Vector2.AXIS_X, Vector2.AXIS_Y]:
				if not _covers_or_centres(framed, space, axis):
					past.append("f%d %s vs %s" % [f, framed, space])
		await get_tree().process_frame
	return past

# THE MAP'S CAMERA RUNS ON PHYSICS INTERPOLATION: a zoom or a pan reaches the drawn transform at the
# next physics tick and eases over the one after, and two process frames with no tick between them
# read the OLD framing as settled. Two ticks first, then the framing itself, bounded.
func _await_map_framing_settled(main: Main) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var last := Rect2()
	for _i : int in range(180):
		await get_tree().process_frame
		var now := _framed_map_rect(main)
		if now.is_equal_approx(last): return
		last = now

## Real wheel-up notches at the window, over the map beside the sidebar, which the wall hands to the focused map.
func _zoom_the_map_in(main: Main, notches: int) -> void:
	for _i : int in range(notches):
		_push_wheel_notch(main.get_viewport(), MOUSE_BUTTON_WHEEL_UP, _ui_space(main).get_center())
	await _await_map_framing_settled(main)

# A VIEWER TAKES EVERY WHEEL AT THE WINDOW, so a map under one is zoomed at the wall's own handler.
func _zoom_the_map_under_a_viewer(main: Main, notches: int) -> void:
	for _i : int in range(notches):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP
		event.pressed = true
		main.wall._unhandled_input(event)
	await _await_map_framing_settled(main)

# A NOTCH IS A PRESS AND ITS RELEASE, as the platform sends it: a press alone keeps the viewport's
# mouse focus on the control under it, and the next click lands there instead of under the pointer.
func _push_wheel_notch(viewport: Viewport, button: MouseButton, at: Vector2) -> void:
	for pressed : bool in [true, false] as Array[bool]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)

const _MENU_BUTTON_PATHS : Array[NodePath] = [
	^"Content/Main/Profile", ^"Content/Play", ^"Content/Main/Options", ^"Content/Main/Quit",
	^"Content/Main/Collection", ^"Content/Main/Language",
]

# Both a portrait (top-case) and an ultrawide (side-case) window, plus the project's own 16:9
# target where the menu's picture and the window coincide 1:1 (`picture_scale` 1.0, no crop).
const _MENU_TEST_WINDOW_SIZES : Array[Vector2i] = [
	Vector2i(600, 1000), Vector2i(1920, 1200), Vector2i(1280, 720),
]

func _menu_buttons(main_menu: Menu) -> Array[Button]:
	var buttons : Array[Button] = []
	for path : NodePath in _MENU_BUTTON_PATHS:
		buttons.append(main_menu.get_node(path) as Button)
	return buttons

# Boots a real `Main` inside a `SubViewport` sized to `size`, or in the player's window; returns
# `[host, main]` so the caller can free both once its own checks are done.
func _boot_main_at(size: Vector2i, in_players_window := false) -> Array:
	if in_players_window: return await TestMainHost.boot_in_players_window(self, size)
	return await TestMainHost.boot(self, size)

func _free_booted_main(viewport: Viewport, node: Node) -> void:
	await TestMainHost.free_booted(self, viewport, node)

# At rest the slid-in band is empty and the whole picture is the menu's. Compared in ONE space via
# `WallPicture.local_rect_beside()`.
## The start menu's buttons lie outside the band the container has actually slid in, and inside the window, at every window shape; harness-scale only.
func test_menus_buttons_lie_outside_the_container_and_inside_the_window() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	for size : Vector2i in _MENU_TEST_WINDOW_SIZES:
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		var wp : WallPicture = main._pictures[&"start_menu"]
		var container : HudContainer = main.wall.get_node(^"%HudContainer")
		var window : Vector2 = container.get_viewport().get_visible_rect().size
		var band_screen : Rect2 = container.published_rect()
		var top := HudContainer.container_is_top(window, SettingsManager.settings)
		var window_local := wp.local_rect_beside(window, Rect2(), top)
		var band_local := _band_rect_in_picture(window_local,
				wp.local_rect_beside(window, band_screen, top), top)
		for button : Button in _menu_buttons(main.menu_scene):
			var button_rect := button.get_global_rect()
			check(not button_rect.intersects(band_local),
					"%s lies outside the reserved container band at %s" % [button.name, size],
					str(button_rect))
			check(window_local.grow(1.0).encloses(button_rect),
					"%s lies inside the window at %s" % [button.name, size], str(button_rect))
		await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

# The container narrows one axis (x on the side case, y on the top case); that is the only axis its
# centring is testable on, so that is the one checked.
## The menu's title and buttons centre on the space beside the container, not merely inset from one edge; harness-scale only.
func test_menus_title_and_button_row_centre_on_the_remaining_space() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	for size : Vector2i in _MENU_TEST_WINDOW_SIZES:
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		var wp : WallPicture = main._pictures[&"start_menu"]
		var container : HudContainer = main.wall.get_node(^"%HudContainer")
		var window : Vector2 = container.get_viewport().get_visible_rect().size
		var band : Rect2 = container.published_rect()
		var top := HudContainer.container_is_top(window, SettingsManager.settings)
		var remaining := wp.local_rect_beside(window, band, top)
		var remaining_centre := remaining.get_center()
		var main_menu : Menu = main.menu_scene
		var title : Label = main_menu.get_node(^"Content/Label")
		var buttons := _menu_buttons(main_menu)
		var content := title.get_global_rect()
		for button : Button in buttons: content = content.merge(button.get_global_rect())
		var content_centre := content.get_center()
		var axis := content_centre.y if top else content_centre.x
		var expected := remaining_centre.y if top else remaining_centre.x
		check(absf(axis - expected) <= MENU_CENTRED_TOLERANCE_PX,
				"the menu's content centres on the remaining space at %s" % size,
				"%.2f vs %.2f" % [axis, expected])
		await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

## Every control in the menu's column draws at the window's UI scale, whatever the picture's cover scale, wholly on screen, and the Play submenu sits below Play, never over it; harness-scale only (the fixture's content scale is 1), the real window is shot.
func test_every_menu_control_draws_at_the_ui_size_inside_the_window_and_none_overlaps() -> void:
	backup_real_save(suite_tag())
	var prev_run : RunState = RunManager.run
	var prev_save_info : RunState = Main.save_info
	for size : Vector2i in [Vector2i(1280, 720), Vector2i(600, 1000), Vector2i(1920, 1080)] as Array[Vector2i]:
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		(main.menu_scene.get_node(^"Content/Play") as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var drawn : Array[Rect2] = []
		for node : Node in main.menu_scene.find_children("*", "Control", true, false):
			var control := node as Control
			if not (control is Button or control is Label) or not control.is_visible_in_tree():
				continue
			var rect := _menu_control_in_window(viewport, main._pictures[&"start_menu"], control)
			_check_drawn_at_the_ui_scale(viewport, rect, control, str(size))
			check(Rect2(Vector2.ZERO, Vector2(size)).grow(1.0).encloses(rect),
					"%s lies inside the window at %s" % [control.name, size], str(rect))
			for other : Rect2 in drawn:
				check(not rect.grow(-0.5).intersects(other),
						"%s overlaps no other menu control at %s" % [control.name, size], "%s vs %s" % [rect, other])
			drawn.append(rect)
		var run_row := main.menu_scene.play_row
		var bottom_row : Container = main.menu_scene.get_node(^"Content/Main")
		check(drawn.size() == 2 + run_row.get_child_count() + bottom_row.get_child_count(),
				"sanity: the title, Play and both rows' buttons were all measured at %s" % size, str(drawn.size()))
		var play := _menu_control_in_window(viewport, main._pictures[&"start_menu"],
				main.menu_scene.get_node(^"Content/Play") as Control)
		var submenu := _menu_control_in_window(viewport, main._pictures[&"start_menu"], run_row)
		check(submenu.position.y >= play.end.y - 0.5, "the Play submenu draws below Play at %s" % size,
				"submenu top %.1f, Play bottom %.1f" % [submenu.position.y, play.end.y])
		await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = prev_run
	Main.save_info = prev_save_info

## The picker slides the sidebar in beside the menu (the side case), leaving less width than the bottom row needs on one line, so the row wraps and stays beside the sidebar; harness-scale only, like the row above.
func test_the_menus_bottom_row_wraps_beside_the_slid_in_sidebar() -> void:
	var opened := await _open_the_deck_picker(Vector2i(1280, 720))
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var window := Vector2(viewport.size)
	check(not HudContainer.container_is_top(window, SettingsManager.settings),
			"sanity: 1280x720 is the side case")
	var row : Container = main.menu_scene.get_node(^"Content/Main")
	var one_line := row.get_theme_constant(&"h_separation") * (row.get_child_count() - 1.0)
	var rows_y : Dictionary[float, bool] = {}
	for button : Button in row.get_children():
		one_line += button.get_combined_minimum_size().x
		rows_y[button.position.y] = true
	check(one_line > row.size.x, "sanity: the row does not fit one line beside the sidebar",
			"%.1f vs %.1f" % [one_line, row.size.x])
	check(rows_y.size() > 1, "the bottom row wraps onto more than one line", str(rows_y.keys()))
	await _end_booted_fixture(viewport, main)

## While the sidebar slides in or out beside the start menu (the picker opening and closing, and the landing back on the menu with the picker up), the column only shifts: one line layout the whole way through the slide, no button moving further in a frame than the sidebar does, and at rest it sits beside the sidebar; harness-scale only, the real window is shot.
func test_the_menus_column_only_shifts_while_the_sidebar_slides() -> void:
	for size : Vector2i in INSET_WINDOWS:
		backup_real_save(suite_tag())
		_prev_run = RunManager.run
		_prev_save_info = Main.save_info
		var booted := await _boot_main_at(size)
		var viewport : SubViewport = booted[0]
		var main : Main = booted[1]
		var opening := await _sample_the_menus_slide(viewport, main, 1.0, _press_new_run.bind(main))
		_check_the_column_only_shifts(opening, "the picker opening at %s" % size)
		_check_the_bottom_row_beside_the_sidebar(viewport, main, "with the picker up at %s" % size)
		await main._go_to_wall_view()
		var landing := await _sample_the_menus_slide(viewport, main, 1.0,
				main._focus_picture.bind(&"start_menu"))
		_check_the_column_only_shifts(landing, "the landing on the menu with the picker up at %s" % size)
		var closing := await _sample_the_menus_slide(viewport, main, 0.0,
				(_the_deck_picker(main) as DeckPicker)._on_close_pressed)
		_check_the_column_only_shifts(closing, "the picker closing at %s" % size)
		_check_the_bottom_row_beside_the_sidebar(viewport, main, "with the picker closed at %s" % size)
		await _end_booted_fixture(viewport, main)

## With the sidebar hidden on the bare menu, every resize between the two window shapes, in either order and in the harness and the player's window alike, leaves the menu's column centred in the whole picture with every control inside the window.
func test_the_menu_lays_out_for_the_window_after_every_resize() -> void:
	for in_players_window : bool in [false, true]:
		for sizes : Array[Vector2i] in [INSET_WINDOWS, [INSET_WINDOWS[1], INSET_WINDOWS[0]] as Array[Vector2i]]:
			backup_real_save(suite_tag())
			_prev_run = RunManager.run
			_prev_save_info = Main.save_info
			var booted := await _boot_main_at(sizes[0], in_players_window)
			var host : Viewport = booted[0]
			var main : Main = booted[1]
			var route := "%s in the %s" % [sizes, "player's window" if in_players_window else "harness"]
			check(main.hud_container.shows_the_bare_menu() and is_zero_approx(main.hud_container.slid_fraction()),
					"sanity: the sidebar is out on the bare menu, %s" % route)
			for size : Vector2i in [sizes[1], sizes[0]] as Array[Vector2i]:
				if host is Window: (host as Window).size = size
				else: (host as SubViewport).size = size
				await get_tree().process_frame
				await _await_the_wall_drawn_at_its_camera_zoom(main)
				_check_the_menu_centred_in_the_window(host, main, "after the resize to %s, %s" % [size, route])
			await _end_booted_fixture(host, main)

func _check_the_menu_centred_in_the_window(host: Viewport, main: Main, what: String) -> void:
	var window := Rect2(Vector2.ZERO, Vector2((host as SubViewport).size if host is SubViewport else (host as Window).size))
	var column := Rect2()
	for node : Node in main.menu_scene.get_node(^"Content").find_children("*", "Control", true, false):
		var control := node as Control
		if not (control is Button or control is Label) or not control.is_visible_in_tree(): continue
		var rect := _menu_control_in_window(host, main._pictures[&"start_menu"], control)
		check(window.grow(1.0).encloses(rect), "%s lies inside the window %s" % [control.name, what],
				"%s in %s" % [rect, window])
		column = rect if column.size == Vector2.ZERO else column.merge(rect)
	var off := column.get_center() - window.get_center()
	var tolerance := MENU_CENTRED_TOLERANCE_PX * host.get_final_transform().get_scale()
	check(absf(off.x) <= tolerance.x and absf(off.y) <= tolerance.y,
			"the menu's column centres in the whole picture %s" % what, "%s in %s" % [column, window])

## Whether the menu's whole column, the Play submenu open, fits beside the resting sidebar at each player's window the layout rows visit.
const _MENU_STACKS_AT : Dictionary[Vector2i, bool] = {
	Vector2i(600, 1000): true, Vector2i(1000, 1000): false, Vector2i(1000, 800): false,
	Vector2i(1280, 720): false,
}

## In the player's window the menu's buttons stack into one centred column where the whole column fits beside the resting sidebar (600x1000) and keep their rows where it does not (near-square, 1280x720); neither Play nor the deck picker's slide changes which.
func test_the_menus_buttons_stack_wherever_the_whole_column_fits_beside_the_sidebar() -> void:
	for size : Vector2i in _MENU_STACKS_AT:
		backup_real_save(suite_tag())
		_prev_run = RunManager.run
		_prev_save_info = Main.save_info
		var booted := await _boot_main_at(size, true)
		var host : Window = booted[0]
		var main : Main = booted[1]
		var stacks := _MENU_STACKS_AT[size]
		await _await_the_menu_laid_out(main)
		_check_the_menus_layout(host, main, stacks, false, "on the bare menu at %s" % size)
		if not stacks: _check_the_bottom_rows_lines(host, main, "on the bare menu at %s" % size)
		(main.menu_scene.get_node(^"Content/Play") as Button).pressed.emit()
		await _await_the_menu_laid_out(main)
		check(main.menu_scene.play_row.visible, "sanity: Play opened its submenu at %s" % size)
		_check_the_menus_layout(host, main, stacks, true, "with the Play submenu open at %s" % size)
		main.menu_scene.new_run_button.pressed.emit()
		await get_tree().process_frame
		await _await_the_menus_slide(main.hud_container, 1.0)
		await _await_the_menu_laid_out(main)
		check(_the_deck_picker(main) != null and is_equal_approx(main.hud_container.slid_fraction(), 1.0),
				"sanity: the deck picker is up and the sidebar rests beside the menu at %s" % size,
				"slid %.3f" % main.hud_container.slid_fraction())
		check(main.menu_scene.play_row.visible, "sanity: the submenu stays open under the deck picker at %s" % size)
		_check_the_menus_layout(host, main, stacks, true, "with the deck picker up at %s" % size)
		await _end_booted_fixture(host, main)

## In the player's window a resize from 1280x720 to 600x1000 stacks the bare menu's buttons, and the resize back lays the bottom row out as one line again.
func test_a_resize_between_the_window_shapes_stacks_the_menu_and_unstacks_it() -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var booted := await _boot_main_at(INSET_WINDOWS[0], true)
	var host : Window = booted[0]
	var main : Main = booted[1]
	for size : Vector2i in [INSET_WINDOWS[0], INSET_WINDOWS[1], INSET_WINDOWS[0]] as Array[Vector2i]:
		host.size = size
		await _await_the_menu_laid_out(main)
		var what := "after the resize to %s" % size
		_check_the_menus_layout(host, main, _MENU_STACKS_AT[size], false, what)
		if not _MENU_STACKS_AT[size]: _check_the_bottom_rows_lines(host, main, what)
	await _end_booted_fixture(host, main)

# A flow reports the height its LAST sort measured, so a change of line count reaches the column
# one sort later; the camera's zoom lags a resize as well.
func _await_the_menu_laid_out(main: Main) -> void:
	await get_tree().process_frame
	await _await_the_wall_drawn_at_its_camera_zoom(main)
	await await_drawn_frames(3)

## The menu's shown title and buttons in the column's own order, as drawn in `host`'s window pixels.
func _menu_controls_in_window(host: Viewport, main: Main) -> Array[Rect2]:
	var rects : Array[Rect2] = []
	for node : Node in main.menu_scene.get_node(^"Content").find_children("*", "Control", true, false):
		var control := node as Control
		if (control is Button or control is Label) and control.is_visible_in_tree():
			rects.append(_menu_control_in_window(host, main._pictures[&"start_menu"], control))
	return rects

## How many lines `row`'s buttons are drawn on in `host`'s window.
func _menu_row_lines(host: Viewport, main: Main, row: Container) -> int:
	var lines : Dictionary[int, bool] = {}
	for button : Control in row.get_children():
		lines[roundi(_menu_control_in_window(host, main._pictures[&"start_menu"], button).position.y)] = true
	return lines.size()

func _check_the_bottom_rows_lines(host: Window, main: Main, what: String) -> void:
	var row : Container = main.menu_scene.get_node(^"Content/Main")
	var lines := _menu_row_lines(host, main, row)
	check(lines == 1, "the bare menu's unstacked bottom row is one line %s" % what,
			"%d lines of %d buttons" % [lines, row.get_child_count()])

# ONE LINE PER BUTTON IS THE STACK and fewer lines than buttons a row, wrapped or not. Either way
# every control of the scene is shown inside the window and overlaps no other; stacked, each sits
# below the one before it on one centre line, the column's own separation apart.
func _check_the_menus_layout(host: Window, main: Main, stacked: bool, submenu_open: bool, what: String) -> void:
	var window := Rect2(Vector2.ZERO, Vector2(host.size)).grow(1.0)
	var rects := _menu_controls_in_window(host, main)
	var content := main.menu_scene.get_node(^"Content")
	var expected := content.get_children().filter(func(child: Node) -> bool: return not child is Container).size()
	expected += content.get_node(^"Main").get_child_count()
	if submenu_open: expected += main.menu_scene.play_row.get_child_count()
	check(rects.size() == expected, "the menu shows its title and every button %s" % what,
			"%d shown of %d" % [rects.size(), expected])
	var outside := rects.filter(func(rect: Rect2) -> bool: return not window.encloses(rect))
	check(outside.is_empty(), "every menu control lies inside the window %s" % what, "%s in %s" % [outside, window])
	var overlapping : Array[String] = []
	for i : int in rects.size():
		for j : int in i:
			if rects[i].grow(-0.5).intersects(rects[j]): overlapping.append("%d over %d" % [i, j])
	check(overlapping.is_empty(), "no menu control overlaps another %s" % what, str(overlapping))
	for row : Container in [main.menu_scene.play_row, main.menu_scene.get_node(^"Content/Main")] as Array[Container]:
		if not row.is_visible_in_tree(): continue
		var lines := _menu_row_lines(host, main, row)
		check((lines == row.get_child_count()) == stacked,
				"%s's buttons are %s %s" % [row.name, "stacked one a line" if stacked else "laid out as a row", what],
				"%d lines of %d buttons" % [lines, row.get_child_count()])
	if not stacked: return
	var scale := host.get_final_transform().get_scale()
	var separation := (main.menu_scene.get_node(^"Content") as Control).get_theme_constant(&"separation") * scale.y
	var off_the_line : Array[String] = []
	var off_the_gap : Array[String] = []
	for i : int in range(1, rects.size()):
		if absf(rects[i].get_center().x - rects[0].get_center().x) > MENU_CENTRED_TOLERANCE_PX * scale.x:
			off_the_line.append("%d at %.1f" % [i, rects[i].get_center().x])
		var gap := rects[i].position.y - rects[i - 1].end.y
		if absf(gap - separation) > 0.5: off_the_gap.append("%d after %.2f" % [i, gap])
	check(off_the_line.is_empty(), "the stacked menu's controls share one centre line %s" % what,
			"%s against %.1f" % [off_the_line, rects[0].get_center().x])
	check(off_the_gap.is_empty(),
			"each stacked control sits the column's own separation below the one before it %s" % what,
			"%s against %.2f" % [off_the_gap, separation])

## At 600x1000 in the player's window, keys alone and the d-pad alone walk the stacked menu top to bottom and back, Play first, past a disabled Continue, and Left and Right move nothing.
func test_keys_and_the_d_pad_walk_the_stacked_menu_in_order() -> void:
	for device : String in ["keys", "pad"] as Array[String]:
		backup_real_save(suite_tag())
		_prev_run = RunManager.run
		_prev_save_info = Main.save_info
		var booted := await _boot_main_at(INSET_WINDOWS[1], true)
		var host : Window = booted[0]
		var main : Main = booted[1]
		var menu := main.menu_scene
		await _await_the_menu_laid_out(main)
		var bottom : Array[Node] = menu.get_node(^"Content/Main").get_children()
		var play : Button = menu.get_node(^"Content/Play")
		var closed : Array[Node] = [play]
		await _check_the_walk(host, main, device, closed + bottom, "the submenu closed")
		await _press_on(host, device, KEY_ENTER, JOY_BUTTON_A)
		await _await_the_menu_laid_out(main)
		check(menu.play_row.visible and menu.continue_button.disabled,
				"%s: sanity: accept on Play opened the submenu, Continue disabled with no save" % device)
		var live := menu.play_row.get_children().filter(
				func(button: Node) -> bool: return button != menu.continue_button)
		check(live.size() == menu.play_row.get_child_count() - 1, "%s: sanity: only Continue is left out" % device)
		await _check_the_walk(host, main, device, closed + live + bottom, "the submenu open")
		await _end_booted_fixture(host, main)

# Down from the first of `stack` to its last, a Left and a Right tried at every stop, then Up all
# the way back; the focus is read in the menu picture's own viewport, where the presses land.
func _check_the_walk(host: Window, main: Main, device: String, stack: Array[Node], what: String) -> void:
	var viewport : SubViewport = main._pictures[&"start_menu"].viewport
	check(viewport.gui_get_focus_owner() == stack[0], "%s: the walk starts on %s, %s" % [device, stack[0].name, what],
			str(viewport.gui_get_focus_owner()))
	for i : int in stack.size():
		if i > 0:
			await _press_on(host, device, KEY_DOWN, JOY_BUTTON_DPAD_DOWN)
			check(viewport.gui_get_focus_owner() == stack[i], "%s: Down reaches %s, %s" % [device, stack[i].name, what],
					str(viewport.gui_get_focus_owner()))
		await _press_on(host, device, KEY_LEFT, JOY_BUTTON_DPAD_LEFT)
		check(viewport.gui_get_focus_owner() == stack[i],
				"%s: Left on %s moves nothing, %s" % [device, stack[i].name, what],
				str(viewport.gui_get_focus_owner()))
		await _press_on(host, device, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT)
		check(viewport.gui_get_focus_owner() == stack[i],
				"%s: Right on %s moves nothing, %s" % [device, stack[i].name, what],
				str(viewport.gui_get_focus_owner()))
	for i : int in range(stack.size() - 2, -1, -1):
		await _press_on(host, device, KEY_UP, JOY_BUTTON_DPAD_UP)
		check(viewport.gui_get_focus_owner() == stack[i], "%s: Up reaches %s, %s" % [device, stack[i].name, what],
				str(viewport.gui_get_focus_owner()))

## One tap of `key` by keys or of `button` by the pad, pushed into `host` as the engine delivers it.
func _press_on(host: Viewport, device: String, key: Key, button: JoyButton) -> void:
	for pressed : bool in [true, false]:
		if device == "keys":
			_push_key(host, key, pressed)
			continue
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		host.push_input(event)
	await get_tree().process_frame
	await get_tree().process_frame

# ⚠ THE COLUMN IS READ IN THE MENU'S OWN CANVAS, the sidebar in window pixels: the landing's slide
# starts while the camera still settles its zoom (measured ~25 px of drift), which moves the whole
# picture and is not the menu's layout. One sample a frame until the slide rests at `aim`.
func _sample_the_menus_slide(viewport: SubViewport, main: Main, aim: float, start: Callable) -> Array[Dictionary]:
	var container := main.hud_container
	var row : Container = main.menu_scene.get_node(^"Content/Main")
	var picture : WallPicture = main._pictures[&"start_menu"]
	var column : Control = main.menu_scene.get_node(^"Content")
	var samples : Array[Dictionary] = []
	start.call()
	for _frame : int in range(300):
		var buttons : Array[Rect2] = []
		for button : Node in row.get_children():
			buttons.append((button as Control).get_global_rect())
		samples.append({&"slid": container.slid_fraction(),
				&"sidebar": viewport.get_final_transform() * container.position,
				&"drawn": _menu_control_in_window(viewport, picture, column).size.x / column.get_global_rect().size.x,
				&"centre": column.get_global_rect().get_center(), &"buttons": buttons})
		if is_equal_approx(container.slid_fraction(), aim) and not main._move_in_flight: break
		await get_tree().process_frame
	check(is_equal_approx(container.slid_fraction(), aim) and not main._move_in_flight,
			"sanity: the slide toward %.0f settled inside the sampled frames" % aim,
			"slid %.3f, moving %s" % [container.slid_fraction(), main._move_in_flight])
	return samples

# THE SPACE BESIDE THE SIDEBAR MOVES ITS CENTRE AT HALF THE SIDEBAR'S SPEED: from the frame before the
# slide to the one after it, the column's centre and its one-layout row step no further, except the
# row across the one frame it may re-wrap (the opening's first, the closing's last).
func _check_the_column_only_shifts(samples: Array[Dictionary], what: String) -> void:
	var first := samples.find_custom(func(s: Dictionary) -> bool: return s[&"slid"] > 0.001 and s[&"slid"] < 0.999)
	var last := samples.rfind_custom(func(s: Dictionary) -> bool: return s[&"slid"] > 0.001 and s[&"slid"] < 0.999)
	check(first >= 1 and last - first >= 2 and last + 1 < samples.size(),
			"sanity: %s is sampled mid-slide, with a rest frame either side" % what,
			"mid %d..%d of %d" % [first, last, samples.size()])
	if first < 1 or last + 1 >= samples.size(): return
	var opening : bool = samples[-1][&"slid"] > 0.5
	var rewrap_step := first if opening else last + 1
	var layouts : Dictionary[String, bool] = {}
	var centre_worst := -INF
	var button_worst := -INF
	for i : int in range(first - 1, last + 2):
		if i != (first - 1 if opening else last + 1):
			var lines : Array[int] = []
			for rect : Rect2 in samples[i][&"buttons"]:
				if not lines.has(roundi(rect.position.y)): lines.append(roundi(rect.position.y))
			lines.sort()
			layouts[str((samples[i][&"buttons"] as Array).map(
					func(rect: Rect2) -> int: return lines.find(roundi(rect.position.y))))] = true
		if i == first - 1: continue
		var sidebar_step := ((samples[i][&"sidebar"] as Vector2) - (samples[i - 1][&"sidebar"] as Vector2)).length()
		var bound := (sidebar_step / 2.0 + 0.5) / (samples[i][&"drawn"] as float)
		centre_worst = maxf(centre_worst,
				((samples[i][&"centre"] as Vector2) - (samples[i - 1][&"centre"] as Vector2)).length() - bound)
		if i == rewrap_step: continue
		for b : int in (samples[i][&"buttons"] as Array).size():
			var step := ((samples[i][&"buttons"][b] as Rect2).position - (samples[i - 1][&"buttons"][b] as Rect2).position).length()
			button_worst = maxf(button_worst, step - bound)
	check(layouts.size() == 1, "the bottom row keeps one line layout through %s" % what, str(layouts.keys()))
	check(centre_worst <= 0.0, "...the column's centre steps at most half the sidebar's step a frame, through %s" % what,
			"%.2f px over" % centre_worst)
	check(button_worst <= 0.0, "...and its buttons move with it outside the one re-wrap frame, through %s" % what,
			"%.2f px over" % button_worst)

# At rest the bottom row flows across the whole width beside the sidebar as it rests, and every
# button lies in that space.
func _check_the_bottom_row_beside_the_sidebar(viewport: SubViewport, main: Main, what: String) -> void:
	var beside := viewport.get_final_transform() * main.hud_container.rect_beside(null)
	var row : Control = main.menu_scene.get_node(^"Content/Main")
	var spans := _menu_control_in_window(viewport, main._pictures[&"start_menu"], row).size.x
	check(absf(spans - beside.size.x) <= 1.0, "the bottom row spans the whole width beside the sidebar, %s" % what,
			"%.1f of %.1f" % [spans, beside.size.x])
	for button : Node in row.get_children():
		var rect := _menu_control_in_window(viewport, main._pictures[&"start_menu"], button as Control)
		check(beside.grow(1.0).encloses(rect), "%s rests beside the sidebar, inside the window, %s" % [button.name, what],
				"%s in %s" % [rect, beside])

func _check_drawn_at_the_ui_scale(viewport: Viewport, rect: Rect2, control: Control, where: String) -> void:
	var ui := viewport.get_final_transform().get_scale()
	var drawn_scale := rect.size / control.size
	check(absf(drawn_scale.x - ui.x) <= 0.001 * ui.x and absf(drawn_scale.y - ui.y) <= 0.001 * ui.y,
			"%s draws at the UI scale across and down at %s" % [control.name, where],
			"%s px for %s at UI %s" % [rect.size, control.size, ui])

## Where `control`, drawn in the menu picture's own canvas, lands in `viewport`'s window pixels.
func _menu_control_in_window(viewport: Viewport, picture: WallPicture, control: Control) -> Rect2:
	return _picture_rect_in_window(viewport, picture,
			control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size))

## Where `canvas`, a rect in `picture`'s own canvas, lands in `viewport`'s window pixels.
func _picture_rect_in_window(viewport: Viewport, picture: WallPicture, canvas: Rect2) -> Rect2:
	var texels := Vector2(picture.viewport.size) / picture.viewport.get_visible_rect().size
	var start := viewport.get_final_transform() * _picture_point_in_window(picture, canvas.position * texels)
	var end := viewport.get_final_transform() * _picture_point_in_window(picture, canvas.end * texels)
	return Rect2(start, end - start)

## A keyboard alone starts a run from the start menu: Play holds the focus from a fresh boot, the arrows walk the column (Play, the submenu below it, the bottom row), Enter presses, and the menu shown again after the map rests the focus on Play once more.
func test_keys_alone_start_a_run_from_the_start_menu_and_find_it_again() -> void:
	await _start_a_run_from_the_menu_with("keys", _tap_key.bind(KEY_ENTER), _tap_key.bind(KEY_DOWN),
			_tap_key.bind(KEY_UP), _tap_key.bind(KEY_LEFT))
	_main._focus_picture(&"start_menu")
	await _wait_out_the_move()
	check(_main._current_focus == &"start_menu", "keys: sanity: the move back to the menu landed",
			str(_main._current_focus))
	var menu_viewport : SubViewport = _main._pictures[&"start_menu"].viewport
	check(menu_viewport.gui_get_focus_owner() == _main.menu_scene.get_node(^"Content/Play"),
			"keys: the menu shown again rests the key focus on Play",
			str(menu_viewport.gui_get_focus_owner()))
	var continue_button : Button = _main.menu_scene.continue_button
	check(RunManager.has_save() and _main.menu_scene.play_row.visible,
			"keys: sanity: the run started is saved, and the submenu is still open on the return")
	check(not continue_button.disabled and continue_button.focus_mode == Control.FOCUS_ALL,
			"keys: ...where Continue is live on the return itself, the save made since it was held",
			"disabled %s, focus_mode %d" % [continue_button.disabled, continue_button.focus_mode])
	await _tap_key(KEY_DOWN)
	var steps := 0
	while menu_viewport.gui_get_focus_owner() != continue_button and steps < _main.menu_scene.play_row.get_child_count():
		await _tap_key(KEY_RIGHT if menu_viewport.gui_get_focus_owner() == _main.menu_scene.new_run_button else KEY_LEFT)
		steps += 1
	check(menu_viewport.gui_get_focus_owner() == continue_button,
			"keys: ...where a live Continue takes the key focus again", str(menu_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## A pad alone starts a run from the start menu, with the d-pad and the accept button only.
func test_a_pad_alone_starts_a_run_from_the_start_menu() -> void:
	await _start_a_run_from_the_menu_with("pad", _tap_pad.bind(JOY_BUTTON_A),
			_tap_pad.bind(JOY_BUTTON_DPAD_DOWN), _tap_pad.bind(JOY_BUTTON_DPAD_UP),
			_tap_pad.bind(JOY_BUTTON_DPAD_LEFT))
	var menu := _main.menu_scene
	_main._focus_picture(&"start_menu")
	await _wait_out_the_move()
	check(not menu.continue_button.disabled, "pad: sanity: the menu shown during the run offers Continue")
	_main._focus_picture(&"map")
	await _wait_out_the_move()
	await TestMainHost.await_world_settled(self, _main, "the run's loss")
	var baked := RunManager.MAP_BAKE_DIR.path_join("composite.png")
	var bake := FileAccess.get_file_as_bytes(baked)
	_main._on_run_lost()
	_main._focus_picture(&"start_menu")
	await _wait_out_the_move()
	var menu_viewport : SubViewport = _main._pictures[&"start_menu"].viewport
	check(not RunManager.has_save() and menu.play_row.visible and _main._current_focus == &"start_menu",
			"pad: sanity: the run is lost, and the menu shown again keeps the submenu open")
	check(menu.continue_button.disabled and menu.continue_button.focus_mode == Control.FOCUS_NONE,
			"pad: ...where Continue is held on the return itself, no save left to resume",
			"disabled %s, focus_mode %d" % [menu.continue_button.disabled, menu.continue_button.focus_mode])
	var reached : Array[Control] = []
	for press : JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT]:
		await _tap_pad(press)
		reached.append(menu_viewport.gui_get_focus_owner())
	check(not reached.has(menu.continue_button),
			"pad: ...so the d-pad never lands on the held Continue, and accept can never resume the lost run",
			str(reached))
# The loss deletes the bake the teardown reads as "the world finished"; it had, before the loss.
	FileAccess.open(baked, FileAccess.WRITE).store_buffer(bake)
	await _end_main_fixture()

# ONE DEVICE, each press a tap pushed into the window's viewport as the engine delivers it, the
# focus owner checked in the viewport the next press moves in. Sees the new run onto the map.
func _start_a_run_from_the_menu_with(device: String, accept: Callable, down: Callable, up: Callable,
		left: Callable) -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	check(RunManager.run == null, "%s: sanity: a fresh boot, so the game's warm-up runs behind the menu" % device)
	var booted := await _boot_main_at(Vector2i(1280, 720))
	_booted_viewport = booted[0]
	_main = booted[1]
	var menu := _main.menu_scene
	var menu_viewport : SubViewport = _main._pictures[&"start_menu"].viewport
	var play : Button = menu.get_node(^"Content/Play")
	var bottom_row : Container = menu.get_node(^"Content/Main")
	check(menu_viewport.gui_get_focus_owner() == play and _booted_viewport.gui_get_focus_owner() == null,
			"%s: a fresh boot rests the key focus on Play, in the menu's picture" % device,
			"%s / %s" % [menu_viewport.gui_get_focus_owner(), _booted_viewport.gui_get_focus_owner()])
	await down.call()
	check(menu_viewport.gui_get_focus_owner() in bottom_row.get_children(),
			"%s: down from Play reaches the bottom row" % device, str(menu_viewport.gui_get_focus_owner()))
	await up.call()
	check(menu_viewport.gui_get_focus_owner() == play, "%s: ...and up comes back to Play" % device,
			str(menu_viewport.gui_get_focus_owner()))
	await accept.call()
	check(menu.play_row.visible and menu_viewport.gui_get_focus_owner() == play,
			"%s: accept presses Play, the submenu opens and Play keeps the focus" % device,
			str(menu_viewport.gui_get_focus_owner()))
	check(menu.continue_button.disabled, "%s: sanity: with no save on disk Continue is disabled" % device)
	await down.call()
	check(menu_viewport.gui_get_focus_owner() in menu.play_row.get_children(),
			"%s: down from Play reaches the submenu below it" % device, str(menu_viewport.gui_get_focus_owner()))
	check(menu_viewport.gui_get_focus_owner() != menu.continue_button,
			"%s: ...on a live button, never the disabled Continue" % device, str(menu_viewport.gui_get_focus_owner()))
	await down.call()
	check(menu_viewport.gui_get_focus_owner() in bottom_row.get_children(),
			"%s: ...and down again the bottom row, in the column's order" % device,
			str(menu_viewport.gui_get_focus_owner()))
	await up.call()
	check(menu_viewport.gui_get_focus_owner() in menu.play_row.get_children()
			and menu_viewport.gui_get_focus_owner() != menu.continue_button,
			"%s: up from the bottom row comes back into the submenu, on a live button" % device,
			str(menu_viewport.gui_get_focus_owner()))
	await down.call()
	var presses := 0
	while menu_viewport.gui_get_focus_owner() != bottom_row.get_child(0) and presses < bottom_row.get_child_count():
		await left.call()
		presses += 1
	await up.call()
	check(menu_viewport.gui_get_focus_owner() == menu.new_run_button,
			"%s: left along the bottom row to its first button, then up, reaches New Run" % device,
			"%d lefts, on %s" % [presses, menu_viewport.gui_get_focus_owner()])
	await accept.call()
	var picker := _the_deck_picker(_main)
	check(picker != null and _booted_viewport.gui_get_focus_owner() == picker.rows.get_child(0).get_child(2),
			"%s: accept on New Run opens the deck picker, the focus on its first Pick" % device,
			str(_booted_viewport.gui_get_focus_owner()))
	var map_ready : Array[bool] = [false]
	_main.map_scene.controller.map_ready.connect(func() -> void: map_ready[0] = true, CONNECT_ONE_SHOT)
	await accept.call()
	var waited := 0.0
	while (_main._current_focus != &"map" or _main._move_in_flight or not map_ready[0]) 			and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_container = _main.wall.get_node(^"%HudContainer")
	await _wait_out_the_return()
	check(_main._current_focus == &"map" and RunManager.run != null and map_ready[0]
			and is_equal_approx(_container.slid_fraction(), 1.0),
			"%s: accept on the Pick starts the run and lands on the map, its sidebar slid in" % device,
			"%s ready %s slid %.3f" % [_main._current_focus, map_ready[0], _container.slid_fraction()])
	check(menu_viewport.gui_get_focus_owner() == null,
			"%s: ...where the menu, not the screen shown, takes no focus" % device,
			str(menu_viewport.gui_get_focus_owner()))

## A show left for the menu and resumed with keys alone lands with a key focus on its board, though the menu took the focus while it was shown.
func test_a_show_resumed_through_the_menu_rests_a_key_focus_on_its_board() -> void:
	await _start_game_fixture()
	check(_game_viewport.gui_get_focus_owner() != null, "sanity: the dealt board holds the key focus",
			str(_game_viewport.gui_get_focus_owner()))
	await _through_the_menu_and_back_by_keys()
	var owner := _game_viewport.gui_get_focus_owner()
	check(owner != null and _play_area.is_ancestor_of(owner),
			"the resumed show rests a key focus on its board, in the game's own viewport", str(owner))
	await _end_main_fixture()

## A show whose outcome is up, left for the menu and resumed with keys alone, lands with the key focus on the outcome's Continue, its board taking none.
func test_a_resolved_show_resumed_through_the_menu_rests_the_key_focus_on_continue() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _end_the_show_by_its_button(view)
	await get_tree().process_frame
	check(view.game.state.show_ended and _game_viewport.gui_get_focus_owner() == view._continue_button,
			"sanity: the outcome is up, Continue holding the focus", str(_game_viewport.gui_get_focus_owner()))
	await _through_the_menu_and_back_by_keys()
	check(_game_viewport.gui_get_focus_owner() == view._continue_button,
			"the resumed outcome rests the key focus on Continue, in the game's own viewport",
			str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

# wall_back's key until the menu is shown -- a focused board takes the first press to zoom out --
# then wall_forward's twice back to the show, each move seen through before the next press.
func _through_the_menu_and_back_by_keys() -> void:
	for _press : int in range(4):
		if _main._current_focus == &"start_menu": break
		await _tap_key(KEY_BRACKETLEFT)
		await _wait_out_the_move()
		if _main._current_focus != &"start_menu": await _wait_out_the_return()
	var menu_viewport : SubViewport = _main._pictures[&"start_menu"].viewport
	check(_main._current_focus == &"start_menu"
			and menu_viewport.gui_get_focus_owner() == _main.menu_scene.get_node(^"Content/Play"),
			"sanity: wall_back's key reaches the menu, the focus on Play",
			"%s / %s" % [_main._current_focus, menu_viewport.gui_get_focus_owner()])
	for _press : int in range(2):
		await _tap_key(KEY_BRACKETRIGHT)
		await _wait_out_the_return()
	check(_main._current_focus == &"game", "sanity: wall_forward's key twice resumes the show",
			str(_main._current_focus))


# ------------------------------------------------------------------ S5: publish and show

# The deal spawns its card controls a frame behind `enter_game()`, so the board is waited FOR
# rather than slept on. Bounded: a real hang is a bug to surface, not one to spin on.
const CARD_CONTROL_TIMEOUT_SEC := 5.0
## How far past a card's drag threshold a press travels to become a drag: past float noise, and still well inside the card's own rect.
const DRAG_THRESHOLD_MARGIN_PX := 2.0

var _prev_run : RunState = null
var _prev_save_info : RunState = null
## The live fixture the S5 tests share, so four tests do not each re-derive the same five nodes.
var _main : Main = null
var _map : Map = null
var _container : HudContainer = null
var _panel : DescriptionPanel = null
var _play_area : PlayArea = null
var _game_viewport : SubViewport = null
var _map_viewport : SubViewport = null
var _booted_viewport : SubViewport = null

# A real `Main` resting on its generated map screen: the fixture every whole-route test starts
# from, with nothing stubbed. Torn down by `_end_main_fixture()`.
func _start_map_fixture(size := Vector2i(1280, 720), in_players_window := false) -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var booted := await _boot_main_at(size, in_players_window)
	_booted_viewport = booted[0] as SubViewport
	_main = booted[1]
	_map = _main.map_scene
	_map_viewport = _main._pictures[&"map"].viewport
	await _focus_map(_main, run)
	_container = _main.wall.get_node(^"%HudContainer")
	_panel = _container.get_node(^"%DescriptionPanel")
	await _clear_any_auto_pick()

# ⚠ THE GRAPH IS RANDOMISED PER BOOT with no seed hook, so whether the start node's single onward
# node auto-picks is a coin flip -- and a pick hides the resting view every map row asserts. The
# auto-pick is proved where it is DRIVEN: the single-reachable-node row, and TestMapTraversal.
func _clear_any_auto_pick() -> void:
	_map.controller.clear_selection()
	await get_tree().process_frame

# The same fixture carried on into a dealt game screen: the only one that proves the WHOLE board
# route -- the board's focus, `GameView`'s relay, `Main`'s handler and the container's swap.
func _start_game_fixture(size := Vector2i(1280, 720), in_players_window := false) -> void:
	await _start_map_fixture(size, in_players_window)
	await _enter_game_fixture()

# The map fixture carried on into the game screen, split out so a test can do something on the map
# FIRST and still reach the board through the product's own route.
func _enter_game_fixture() -> void:
	await _main.enter_game()
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_play_area = view.play_area
	_game_viewport = _main._pictures[&"game"].viewport
	await _await_the_opening_ease(_play_area)

func _end_main_fixture() -> void:
	await _free_booted_main(_main.get_viewport(), _main)
	_booted_viewport = null
	_main = null
	_map = null
	_map_viewport = null
	_container = null
	_panel = null
	_play_area = null
	_game_viewport = null
	CardEnvironment.CURRENT = null
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

# Card controls the pointer can genuinely land ON, and that publish when it does: on screen, not
# covered by another (board cards overlap), not a HELD card (`grab_cards` makes its control IGNORE
# and the pointer passes through it), not a buried zone control (FOCUS_NONE publishes nothing).
func _hoverable_card_controls() -> Array[Control]:
	var rect := Rect2(Vector2.ZERO, Vector2(_game_viewport.size))
	var waited := 0.0
	var out : Array[Control] = []
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		_play_area.flush_rebuild()
		var every : Array[Control] = []
		for control : Control in _play_area.ui_data:
			if is_instance_valid(control): every.append(control)
		out.clear()
		for control : Control in every:
			if _play_area.is_stock_control(control): continue
			if not control.is_visible_in_tree(): continue
			if control.mouse_filter == Control.MOUSE_FILTER_IGNORE: continue
			if not _is_selectable(control): continue
			if rect.encloses(control.get_global_rect()) and not _is_covered(control, every):
				out.append(control)
		if out.size() >= 2: break
	return out

func _is_covered(control: Control, others: Array[Control]) -> bool:
	var centre := control.get_global_rect().get_center()
	for other : Control in others:
		if other != control and other.get_global_rect().has_point(centre): return true
	return false

# A REAL pointer, pushed into the game picture's own SubViewport where the board's controls live,
# so the route under test is the product's own: mouse_entered grabs focus, and focus publishes.
func _hover(at: Vector2) -> void:
	_hover_in(_game_viewport, at)

# A pointer move pushed into whichever picture hosts the control -- a viewer opened over the start
# menu is not in the game's own viewport, which `_hover()` pushes into.
func _hover_in(viewport: Viewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion)

# The pointer is walked across the candidates until the BOARD ITSELF reports a different card
# under it. Which control a point hits is the engine's answer, not the test's: cards overlap in a
# stack and the strips clip, so a rect's own centre is not always hit-testable.
func _hover_another_card(controls: Array[Control], avoid: Control) -> Control:
	for control : Control in controls:
		if control == avoid: continue
#The walk is after a hover that MOVES the focus, which the card already holding it cannot give.
		if control == _game_viewport.gui_get_focus_owner(): continue
		_hover(control.get_global_rect().get_center())
		await get_tree().process_frame
		var hovered : Control = _play_area.moused_hovered_control
#THE FOCUS IS WHAT PUBLISHES, so a hover the board registered but that moved no focus has not
#reached the description route at all, and the walk carries on to the next card.
		if _game_viewport.gui_get_focus_owner() != hovered: continue
		if hovered != null and hovered != avoid and _play_area.ui_data.has(hovered):
			return hovered
	return null

## Off the picture entirely: no control can be under the pointer there, whatever a re-lay-out moves.
func _off_the_board_point() -> Vector2:
	return Vector2(-100.0, -100.0)

# Bare board: a point belonging to no card control, so the pointer leaving everything is a real
# mouse exit rather than the test merely declining to publish.
func _bare_board_point(controls: Array[Control]) -> Vector2:
	var board := Vector2(_game_viewport.size)
	for step : int in 20:
		var candidate := Vector2(board.x - 4.0, 4.0 + step * board.y / 20.0)
		var covered := false
		for control : Control in controls:
			if control.get_global_rect().has_point(candidate): covered = true
		if not covered: return candidate
	return Vector2(board.x - 4.0, 4.0)

# The text the board publishes for a card, split the way `PlayArea.card_info()` splits it: the
# first line is the card's name, the rest is its description.
func _expected_text(data: CardData) -> PackedStringArray:
	return ControlCard.describe_card(data).split("\n", true, 1)

func _preview_card(node: Node) -> ControlCard:
	var card := node as ControlCard
	if card: return card
	for child : Node in node.get_children():
		var found := _preview_card(child)
		if found: return found
	return null

## The title is the card's own name, "<Rank> of <Suits>", and every effect is a block whose NAME is written larger than the description under it; harness-scale only.
func test_the_description_titles_a_card_and_sizes_its_effect_names() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var knife := PipSuitKnife.new().get_plural_str()
	var numeral := CardData.new().with_suit(PipSuitKnife.new())
	numeral.rank = PipRankNumeral.new().with_value(5)
	check(ControlCard.card_title(numeral) == "5 of %s" % knife,
			"a numeral card is titled by its rank and suit (R10)", ControlCard.card_title(numeral))
	var face := CardData.new().with_suit(PipSuitKnife.new())
	face.rank = PipRankNumeral.new().with_value(13)
	check(ControlCard.card_title(face) == "%s of %s" % [TRANSLATION.find('RANK_KING'), knife],
			"...and a court card by its own name (R10)", ControlCard.card_title(face))
	var skilled := CardData.new().with_suit(PipSuitKnife.new()).with_skill(SkillExtraPoint.new())
	skilled.rank = PipRankNumeral.new().with_value(5)
	_container.show_description(PlayArea.card_info(skilled,
			CardVisual.preview_window_px()))
	await get_tree().process_frame
	check(title.text == ControlCard.card_title(skilled),
			"the panel's title is that name and nothing else (R10)", title.text)
	var named := "[font_size=%d]%s[/font_size]" % [ControlCard.NAME_FONT_SIZE,
			SkillExtraPoint.new().get_str()]
	check(body.text.contains(named),
			"...and the effect's NAME is written in the large font (R10)", body.text)
	check(body.get_parsed_text().contains(SkillExtraPoint.new().get_description()),
			"...with its description under it (R10)", body.get_parsed_text())
	check(body.get_theme_font_size(&"normal_font_size") != ControlCard.NAME_FONT_SIZE,
			"...in a font size of its own, smaller than the name's (R10)",
			"%d vs %d" % [body.get_theme_font_size(&"normal_font_size"), ControlCard.NAME_FONT_SIZE])
	await _end_main_fixture()

## The title names the suit in the plural ("King of Knives") for every suit, while the suit's own block and every other reader keep the singular.
func test_the_title_names_the_suit_in_the_plural() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var suits : Array[GDScript] = [PipSuitHoop, PipSuitKnife, PipSuitBall, PipSuitFire,
			PipSuitFirework]
	var plural_keys : Array[StringName] = [&'SUIT_HOOP_PLURAL', &'SUIT_KNIFE_PLURAL',
			&'SUIT_BALL_PLURAL', &'SUIT_FIRE_PLURAL', &'SUIT_FIREWORK_PLURAL']
	var card_px := CardVisual.preview_window_px()
	for i : int in suits.size():
		var suit_script : GDScript = suits[i]
		var suit : PipSuit = suit_script.new()
		var singular : String = suit.get_str()
		var plural : String = TRANSLATION.find(plural_keys[i])
		var numeral : CardData = CardData.new().with_suit(suit)
		numeral.rank = PipRankNumeral.new().with_value(5)
		_container.show_description(PlayArea.card_info(numeral, card_px))
		await get_tree().process_frame
		check(title.text == "5 of %s" % plural,
				"the published title of a %s numeral card names the suit in the plural"
						% singular, title.text)
		check(not title.text.contains("SUIT_"),
				"...and no %s title falls back to a raw localisation key" % singular,
				title.text)
		check(body.text.contains("[font_size=%d]%s[/font_size]"
						% [ControlCard.NAME_FONT_SIZE, singular]),
				"...while the %s block under it stays singular" % singular, body.text)
		check(str(numeral).begins_with(singular + " "),
				"...and CardData's own string keeps the %s singular" % singular,
				str(numeral))
		var face_suit : PipSuit = suit_script.new()
		var face : CardData = CardData.new().with_suit(face_suit)
		face.rank = PipRankNumeral.new().with_value(13)
		_container.show_description(PlayArea.card_info(face, card_px))
		await get_tree().process_frame
		check(title.text == "%s of %s" % [TRANSLATION.find('RANK_KING'), plural],
				"...and a %s court card's published title too" % singular, title.text)
		var rankless_suit : PipSuit = suit_script.new()
		var rankless : CardData = CardData.new().with_suit(rankless_suit)
		_container.show_description(PlayArea.card_info(rankless, card_px))
		await get_tree().process_frame
		check(title.text == plural,
				"...and a %s card with no rank is titled by the plural alone" % singular,
				title.text)
		check(body.text.contains("[font_size=%d]%s[/font_size]"
						% [ControlCard.NAME_FONT_SIZE, singular]),
				"...while its own %s block stays singular" % singular, body.text)
	await _end_main_fixture()

## 1.2/B1/B2: a highlight -- key/pad focus or a real mouse hover -- swaps the container to that card's description.
func test_a_highlight_opens_the_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var title : Label = _panel.get_node(^"%Title")
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var slot : Control = _panel.get_node(^"%VisualSlot")

	var spelled := InfoEntry.new()
	spelled.title = "A"
	spelled.body = "B"
	_container.show_description(spelled)
	check(_panel.visible and not hud_stack.visible,
			"the description replaces the HUD, never both and never neither (B2)")
	check(title.text == "A", "...and the title reads the entry's name", title.text)
	check(body.text == "B", "...and the body reads its description", body.text)

	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two reachable card controls",
			str(controls.size()))
	if controls.size() >= 2:
		_container.show_hud()
		controls[0].grab_focus()
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible,
				"key/pad selection onto a card opens the description (B1)")
		check(title.text == _expected_text(_play_area.ui_data[controls[0]])[0],
				"...and the title reads that card's own name", title.text)
		check(not body.text.is_empty(), "...and the body carries its description", body.text)
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		check(title.get_global_rect().position.y >= overlay.button_band_bottom(),
				"the name starts below the overlay's own button row, as the HUD does (Q46)",
				"%.1f vs %.1f" % [title.get_global_rect().position.y, overlay.button_band_bottom()])
		var entry : InfoEntry = _panel.current_entry
		check(entry != null and entry.visual != null and entry.visual.get_parent() == slot,
				"the card's own visual is mounted in the panel (Q33=c)")
		if entry != null and entry.visual != null:
			var preview := _preview_card(entry.visual)
			check(preview != null and preview.child != null, "...and it is a real preview card")
			if preview != null and preview.child != null:
				check(not preview.child.floating, "...frozen rather than idling (Q35=b)")
				check(preview.focus_mode == Control.FOCUS_NONE
						and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE,
						"...and inert: it takes no pad focus and swallows no click")
		var hovered := await _hover_another_card(controls, controls[0])
		check(hovered != null, "the pointer can land on a card other than the pad's own")
		check(_panel.visible and not hud_stack.visible,
				"a real mouse hover opens it by the same rule as the pad (B1)")
		if hovered != null:
			check(title.text == _expected_text(_play_area.ui_data[hovered])[0],
					"...and the title follows the card the pointer is on", title.text)
	await _end_main_fixture()

# A state check reads the title's TEXT, which a panel laid out off screen still carries: this one
# asks where the name, the preview and the body are DRAWN, through a shrink and back while it shows.
func test_a_hovered_cards_description_draws_inside_the_container() -> void:
	await _start_game_fixture()
	var data := await _hover_a_card_with_a_visual()
	check(data != null, "the pointer described a board card")
	if data != null:
		var windows : Array[Vector2i] = [Vector2i(1280, 720), Vector2i(600, 1000), Vector2i(1280, 720)]
		for window : Vector2i in windows:
			await _resize_viewport(_booted_viewport, window)
			await get_tree().physics_frame
			_check_description_draws_inside_the_container(window)
	await _end_main_fixture()

# ⚠ THE BODY IS THE ONE PART ALLOWED TO RUN PAST THE BOTTOM: at the one preview size (R9) the top
# row alone can fill a short top band, and what is below the fold is what the scroll is for. It
# still has to START inside the container and stay inside it sideways.
func _check_description_draws_inside_the_container(window: Vector2i) -> void:
	var bounds := _sidebar_screen_rect(_container)
	var parts : Array[Control] = [_panel.get_node(^"%Title") as Control,
			_preview_card(_panel.current_entry.visual), _panel.get_node(^"%Body") as Control]
	for part : Control in parts:
		var rect := _sidebar_screen_rect(part)
		var fits := bounds.encloses(rect) if part.name != &"Body" else (
				bounds.has_point(rect.position)
				and rect.end.x <= bounds.end.x + PREVIEW_WIDTH_TOLERANCE_PX)
		check(part.is_visible_in_tree() and rect.has_area() and fits,
				"the description's %s draws inside the container at %s" % [part.name, window],
				"%s vs container %s" % [rect, bounds])

## The windows the content inset is measured at: the shipped side case and the top case every top-band row uses.
const INSET_WINDOWS : Array[Vector2i] = [Vector2i(1280, 720), Vector2i(600, 1000)]

## A letter drawn at the container's very edge loses its first column, so the description and the HUD both start one overlay inset inside it; harness-scale only.
func test_the_containers_content_starts_one_inset_inside_its_left_edge() -> void:
	await _start_game_fixture()
	var data := await _hover_a_card_with_a_visual()
	check(data != null, "the pointer described a board card")
	if data != null:
		for window : Vector2i in INSET_WINDOWS:
			await _resize_viewport(_booted_viewport, window)
			await get_tree().physics_frame
			var parts : Array[Control] = [_panel.get_node(^"%Title") as Control,
					_preview_card(_panel.current_entry.visual), _panel.get_node(^"%Body") as Control]
			_check_parts_start_one_inset_inside(parts, "the description's", window)
		_container.show_hud()
		await get_tree().process_frame
		var names : Array[StringName] = []
		_collect_unique_names(_container.get_node(^"%GameHud"), _container, names)
		var members : Array[Control] = []
		for member_name : StringName in names:
			var member := _container.get_node(NodePath("%" + member_name)) as Control
			if member.is_visible_in_tree(): members.append(member)
		_check_parts_start_one_inset_inside(members, "the HUD's", INSET_WINDOWS[-1])
	await _end_main_fixture()

func _check_parts_start_one_inset_inside(parts: Array[Control], owner_label: String,
		window: Vector2i) -> void:
	var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
	var edge := _sidebar_screen_rect(_container).position.x + overlay.button_band_inset()
	for part : Control in parts:
		var left := _sidebar_screen_rect(part).position.x
		check(left >= edge - 0.5,
				"close fix E: %s %s starts one overlay inset inside the container at %s"
						% [owner_label, part.name, window],
				"%.1f vs %.1f" % [left, edge])

## The X sits over the description's top-right corner, so the wrapped name must leave that column free or a word draws beneath it; harness-scale only.
func test_the_title_leaves_the_exit_xs_column() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		check(_exit_button().is_visible_in_tree(),
				"a click stuck the description, the one state with an X")
		for window : Vector2i in INSET_WINDOWS:
			await _resize_viewport(_booted_viewport, window)
			await get_tree().physics_frame
			var title := _sidebar_screen_rect(_panel.get_node(^"%Title") as Control)
			var exit := _exit_button()
			check(exit.is_visible_in_tree() and not title.intersects(exit.get_global_rect()),
					"close fix E: the title leaves the exit X's column at %s" % window,
					"title %s vs X %s" % [title, exit.get_global_rect()])
	await _end_main_fixture()

## A 1280x1000 window's logical canvas: the tallest band where the HUD is taller than the room below the buttons.
const SHORT_TOP_BAND_WINDOW := Vector2i(1152, 900)

## The overlay's buttons draw above the container, so a top band's HUD starts below their row at the shipped size, whatever the band's height; harness-scale only.
func test_the_top_bands_hud_starts_below_the_overlay_buttons() -> void:
	for window : Vector2i in [INSET_WINDOWS[-1], SHORT_TOP_BAND_WINDOW] as Array[Vector2i]:
		await _start_game_fixture(window)
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		check(HudContainer.container_is_top(Vector2(window), PlayArea.settings()),
				"sanity: %s puts the container on the top band" % window)
		await get_tree().process_frame
		var band_bottom := overlay.button_band_bottom()
		var names : Array[StringName] = []
		_collect_unique_names(_container.get_node(^"%GameHud"), _container, names)
		for member_name : StringName in names:
			var member := _container.get_node(NodePath("%" + member_name)) as Control
			if not member.is_visible_in_tree(): continue
			var top := _sidebar_screen_rect(member).position.y
			check(top >= band_bottom - 0.5,
					"close fix E: %s starts below the overlay buttons at %s" % [member_name, window],
					"%.1f vs band %.1f, container %s" % [top, band_bottom, _container.container_rect()])
		await _end_main_fixture()

## How near the preview's drawn width must land on the board card's own -- a pixel of layout rounding on each side.
const PREVIEW_WIDTH_TOLERANCE_PX := 2.0

# What a card ACTUALLY DRAWS AT, not the box it was allocated: every scale above it, times its own
# face. The two differ -- `CardVisual._ready()` re-runs `recalculate_size()`, so a card can sit in a
# correctly sized slot drawing at the wrong size, which is exactly the defect this test exists for.
func _card_drawn_width(card: CardVisual) -> float:
	return CardVisual.CARD_SIZE.x * card.get_global_transform_with_canvas().get_scale().x

# A board card's width as the player SEES it: its drawn width inside the game picture's viewport,
# times the scale the wall draws that viewport at, read off the picture's own screen sprite, so the
# live camera zoom is in it, not modelled twice.
func _card_window_width(card: CardVisual) -> float:
	var picture : WallPicture = _main._pictures[&"game"]
	var sprite : Sprite2D = picture.get_node(^"%Screen")
	var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
	var texel := float(picture.viewport.size.x) / design.x
	return _card_drawn_width(card) * texel * sprite.get_global_transform_with_canvas().get_scale().x

# The card the pointer genuinely landed on, and one the board has a CardVisual for -- a drawn
# width can only be compared against a card that is really rendered. Null when the dealt board
# offered none, which is a failed check either way.
func _hover_a_card_with_a_visual() -> CardData:
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	var hovered := await _hover_another_card(controls, null)
	check(hovered != null, "the pointer landed on a board card")
	if hovered == null: return null
	var data : CardData = _play_area.ui_data[hovered]
	return data if _play_area.data_card.has(data) else null

## R9/Q33=c: every description draws its card at the ONE preview size, the deck viewer's, with the name beside it; harness-scale only.
func test_the_preview_is_drawn_at_the_one_preview_size() -> void:
	await _start_game_fixture()
	var data := await _hover_a_card_with_a_visual()
	if data != null:
		await get_tree().process_frame
		var board_px := _card_window_width(_play_area.data_card[data])
		var preview := _preview_card(_panel.current_entry.visual)
		check(preview != null, "the description mounted a preview card")
		if preview != null and preview.child != null:
			var preview_px := _card_drawn_width(preview.child)
			var preview_rect := _sidebar_screen_rect(preview)
			var one_size := CardVisual.preview_window_px().x
			check(absf(one_size - board_px) > PREVIEW_WIDTH_TOLERANCE_PX,
					"sanity: the one preview size and the board's own card width differ enough to tell apart",
					"one size %.1f px vs board %.1f px" % [one_size, board_px])
			check(absf(preview_px - one_size) <= PREVIEW_WIDTH_TOLERANCE_PX,
					"the preview is drawn at the deck viewer's card size, not the board's (R9)",
					"preview %.1f px vs one size %.1f px, board %.1f px at board zoom %.3f"
					% [preview_px, one_size, board_px, _play_area.board_zoom])
			check(absf(preview_rect.size.x - preview_px) <= PREVIEW_WIDTH_TOLERANCE_PX,
					"...and the slot it was given is that same width, so the name clears it",
					"slot %.1f px vs card %.1f px" % [preview_rect.size.x, preview_px])
			var title_rect := _sidebar_screen_rect(_panel.get_node(^"%Title") as Label)
			check(title_rect.position.x >= preview_rect.end.x - PREVIEW_WIDTH_TOLERANCE_PX,
					"the name starts to the RIGHT of the visual (Q33=c)",
					"name at %.1f vs visual ending %.1f"
					% [title_rect.position.x, preview_rect.end.x])
			check(title_rect.position.y < preview_rect.end.y
					and title_rect.end.y > preview_rect.position.y,
					"...and beside it, not under it (Q33=c)",
					"name %s vs visual %s" % [title_rect, preview_rect])
	await _end_main_fixture()

## R9 through a resize: the preview is re-drawn at the one preview size at the NEW window, not the one it was published at; harness-scale only.
func test_the_preview_follows_a_resize_to_the_new_preview_size() -> void:
	await _start_game_fixture()
	var data := await _hover_a_card_with_a_visual()
	if data != null:
		_booted_viewport.size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		_play_area.flush_rebuild()
		await get_tree().process_frame
		var board_px := _card_window_width(_play_area.data_card[data])
		var preview := _preview_card(_panel.current_entry.visual)
		check(preview != null and preview.child != null,
				"the description still holds its preview after the resize")
		if preview != null and preview.child != null:
			var preview_px := _card_drawn_width(preview.child)
			var one_size := CardVisual.preview_window_px().x
			check(absf(one_size - board_px) > PREVIEW_WIDTH_TOLERANCE_PX,
					"sanity: the one preview size and the board's own card width still differ",
					"one size %.1f px vs board %.1f px" % [one_size, board_px])
			check(absf(preview_px - one_size) <= PREVIEW_WIDTH_TOLERANCE_PX,
					"the preview is re-drawn at the one preview size at the new window (R9)",
					"preview %.1f px vs one size %.1f px, board %.1f px at board zoom %.3f"
					% [preview_px, one_size, board_px, _play_area.board_zoom])
	await _end_main_fixture()

## R "merely hovering a card causes it to become sticky": a hover DESCRIBES with no X, and closes again the moment the pointer is on no card.
func test_a_hover_describes_a_board_card_without_sticking_it() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var title : Label = _panel.get_node(^"%Title")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible, "hovering a card opens the description")
		check(title.text == _expected_text(_play_area.ui_data[controls[0]])[0],
				"...reading the card the pointer is on", title.text)
		check(not _container.is_locked(),
				"...and a HOVER STICKS NOTHING: only a click locks the sidebar")
		check(not _exit_button().is_visible_in_tree(),
				"...so it carries NO exit X, which would promise it will stay")
		check(_exit_button().focus_mode == Control.FOCUS_NONE,
				"...and no pad player can navigate onto that X either",
				str(_exit_button().focus_mode))

		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		check(hud_stack.visible and not _panel.visible,
				"the pointer leaving every card CLOSES the description again")
		check(not _exit_button().is_visible_in_tree(), "...with the X gone with it")
	await _end_main_fixture()

# Every entry the board publishes, in order -- a count, so a hover that published twice shows.
func _record_board_publishes() -> Array[InfoEntry]:
	var published : Array[InfoEntry] = []
	_play_area.info_requested.connect(func(entry: InfoEntry) -> void: published.append(entry))
	return published

## The pointer leaving keeps the focus rim, and coming back onto that same card describes it again.
func test_re_hovering_the_focused_card_describes_it_again() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two card controls to hover",
			str(controls.size()))
	if controls.size() >= 2:
		var a : Control = controls[0]
		var a_title : String = _expected_text(_play_area.ui_data[a])[0]
		var published := _record_board_publishes()
		_hover(a.get_global_rect().get_center())
		await get_tree().process_frame
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		check(_game_viewport.gui_get_focus_owner() == a,
				"sanity: the closed hover left the board focus (and its rim) on the card")
		_hover(a.get_global_rect().get_center())
		await get_tree().process_frame
		var a_publishes := published.filter(func(e: InfoEntry) -> bool: return e.title == a_title)
		check(a_publishes.size() == 2,
				"hovering the card, leaving and hovering it again describes it BOTH times",
				str(a_publishes.size()))
		check(_panel.visible and title.text == a_title,
				"...and the sidebar reads it after the second hover", title.text)
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		var b := await _hover_another_card(controls, a)
		check(b != null, "the pointer landed on a second card")
		if b != null:
			check(_panel.visible and title.text == _expected_text(_play_area.ui_data[b])[0],
					"leaving the first card and hovering another describes the other", title.text)
	await _end_main_fixture()

## A hover that moves the focus publishes through focus_entered alone, so the re-hover route adds no second publish.
func test_a_hover_that_moves_the_focus_publishes_once() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two card controls to hover",
			str(controls.size()))
	if controls.size() >= 2:
		var a : Control = controls[0]
		_hover(a.get_global_rect().get_center())
		await get_tree().process_frame
		var published := _record_board_publishes()
		var b := await _hover_another_card(controls, a)
		check(b != null, "the pointer moved the focus onto a second card")
		if b != null:
			var b_title : String = _expected_text(_play_area.ui_data[b])[0]
			var b_publishes := published.filter(func(e: InfoEntry) -> bool: return e.title == b_title)
			check(b_publishes.size() == 1,
					"a hover that moves the focus publishes the new card EXACTLY once",
					str(b_publishes.size()))
	await _end_main_fixture()

# A click on the first Entrance card sticks its description; null when the board dealt none.
func _stick_an_entrance_card() -> CardData:
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if entrance.is_empty(): return null
	var stuck : CardData = _play_area.ui_data[entrance[0]]
	await _lock_without_holding(entrance[0])
	return stuck

## A stuck description through a re-hover: the pointer coming back onto the stuck card neither loses nor unsticks it.
func test_re_hovering_a_stuck_card_keeps_it_stuck() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var stuck := await _stick_an_entrance_card()
	if stuck != null:
		var controls := await _hoverable_card_controls()
		var a : Control = _play_area.data_ui[stuck]
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		_hover(a.get_global_rect().get_center())
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(stuck)[0],
				"re-hovering the stuck card still reads it", title.text)
		check(_container.is_locked() and _play_area.locked_data == stuck,
				"...and it is still stuck")
		check(_exit_button().is_visible_in_tree(), "...with its X up")
	await _end_main_fixture()

## The same rule for the other device: a pad/keyboard focus describes and sticks nothing, and the focus leaving the board closes it.
func test_a_pad_focus_describes_a_board_card_without_sticking_it() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to focus",
			str(controls.size()))
	if not controls.is_empty():
		_hover(_off_the_board_point())
		await get_tree().process_frame
		controls[0].grab_focus()
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible,
				"a pad focus onto a card opens the description")
		check(not _container.is_locked(), "...and sticks nothing (R: only a click does)")
		check(not _exit_button().is_visible_in_tree(), "...so it carries no exit X")

		_container.submit_button.grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		check(_game_viewport.gui_get_focus_owner() == null,
				"the board holds no focused control once the HUD took the focus",
				str(_game_viewport.gui_get_focus_owner()))
		check(hud_stack.visible and not _panel.visible,
				"...so the focus leaving the board closes the description")
	await _end_main_fixture()

## 1.14/B15/B16/Q19=c/Q20=b: each screen remembers its own stuck description and gets it back on return.
func test_leaving_and_returning_restores_the_screens_own_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var controls := await _entrance_card_controls()
	check(not controls.is_empty(), "the dealt board offers a clickable Entrance card",
			str(controls.size()))
	if not controls.is_empty():
		await _lock_without_holding(controls[0])
		var shown : InfoEntry = _panel.current_entry
		check(shown != null, "the game screen has a description to remember")

		await _main._focus_picture(&"map")
		check(hud_stack.visible and not _panel.visible,
				"the map has read nothing of its own, so it shows its own HUD (B15)")

		await _main._focus_picture(&"game")
		check(_panel.visible and not hud_stack.visible,
				"coming back re-shows the game's description immediately (B16, Q20=b)")
		check(shown != null and _panel.current_entry == shown,
				"...and it is the very entry that screen was left on (Q19=c)")
		check(shown != null and shown.visual != null and shown.visual.get_parent() == slot,
				"...with its own visual back in the panel")
	await _end_main_fixture()

# The player's own way off the game and back: the overlay's Back and Forward buttons, each move
# waited out, so the container sees exactly the two screen changes `Main` makes for them.
func _leave_the_game_and_return_by_the_wall() -> void:
	var overlay : Node = _main.wall.get_node(^"%Overlay")
	await _click((overlay.get_node(^"%BackButton") as Control).get_global_rect().get_center(),
			_booted_viewport)
	await _wait_out_the_move()
	check(_main._current_focus == &"map", "sanity: Back left the game for the map",
			str(_main._current_focus))
	await _click((overlay.get_node(^"%ForwardButton") as Control).get_global_rect().get_center(),
			_booted_viewport)
	await _wait_out_the_move()
	check(_main._current_focus == &"game", "sanity: Forward returned to the game",
			str(_main._current_focus))

## Q64=a/B10: a description dismissed with the exit X stays dismissed -- leaving the game and coming back does not re-open it.
func test_a_description_dismissed_with_the_x_stays_dismissed_on_return() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		check(_container.showing_description(), "sanity: a description is up before the X")
		await _click(_exit_button().get_global_rect().get_center(), _booted_viewport)
		check(_hud_is_up(), "sanity: the exit X reverted the container to the HUD")
		await _leave_the_game_and_return_by_the_wall()
		check(_hud_is_up(),
				"Close fix 4: a description dismissed with the X does not come back on return (Q64=a, B10)")
		check(not _container.is_locked(), "...and nothing is locked on return")
	await _end_main_fixture()

## Q64=a/B11: a description a placement took down stays down -- leaving the game and coming back does not re-open it.
func test_a_description_a_placement_took_down_stays_down_on_return() -> void:
	await _start_game_fixture()
	await _await_the_board_idle()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_container.showing_description(), "sanity: a description is up before the placement")
		var placed := await _lift_and_place_a_card()
		check(placed != null, "sanity: a lifted card landed on a cell")
		check(_hud_is_up(), "sanity: the placement reverted the container to the HUD")
		await _leave_the_game_and_return_by_the_wall()
		check(_hud_is_up(),
				"Close fix 4: a description a placement took down does not come back on return (Q64=a, B11)")
	await _end_main_fixture()

## An arrow's description sticks nothing, so Back and Forward find the HUD, not a card nothing is on.
func test_a_focused_card_is_forgotten_across_back_and_forward() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to focus",
			str(controls.size()))
	if not controls.is_empty():
		_hover(_off_the_board_point())
		await get_tree().process_frame
		await _tap_key(KEY_RIGHT)
		check(_container.showing_description() and not _container.is_locked(),
				"sanity: an arrow described a board card and stuck nothing")
		await _leave_the_game_and_return_by_the_wall()
		check(_hud_is_up(), "P57: an unstuck focused card is not re-shown on Forward (nineteenth round a)",
				str(_panel.current_entry.title if _panel.current_entry else null))
	await _end_main_fixture()

## A hover's description sticks nothing, so Back and Forward find the HUD, not the card the pointer left.
func test_a_hovered_card_is_forgotten_across_back_and_forward() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_container.showing_description() and not _container.is_locked(),
				"sanity: a hover described a board card and stuck nothing")
		await _leave_the_game_and_return_by_the_wall()
		check(_hud_is_up(), "P57: an unstuck hovered card is not re-shown on Forward (nineteenth round a)",
				str(_panel.current_entry.title if _panel.current_entry else null))
	await _end_main_fixture()

## The panel OWNS the mounted visual: the next entry frees the last, so reading along a row of cards leaks no preview.
func test_a_new_entry_frees_the_visual_it_replaces() -> void:
	await _start_game_fixture()
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var controls := await _hoverable_card_controls()
	check(controls.size() >= 2, "the dealt board offers two reachable card controls",
			str(controls.size()))
	if controls.size() >= 2:
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		var shown_on : Control = _play_area.moused_hovered_control
		var first : Node = _panel.current_entry.visual if _panel.current_entry else null
		check(first != null, "the first hover mounted a visual")
		var hovered := await _hover_another_card(controls, shown_on)
		await get_tree().process_frame
		check(hovered != null, "the pointer moved onto a different card")
		check(not is_instance_valid(first),
				"the replaced entry's visual is freed, not orphaned",
				"%d visual(s) left in the slot" % slot.get_child_count())
		check(_panel.current_entry != null and _panel.current_entry.visual != first,
				"...and the panel shows the next card's own visual")
	await _end_main_fixture()

# ------------------------------------------------------------------ S6: the lock and the exit X

# A real click, pushed where the hover already is: press and release at the same point, one frame
# apart, so `_on_gui_input` sees the hovered control still focused under the button.
func _click(at: Vector2, viewport: SubViewport, button := MOUSE_BUTTON_LEFT) -> void:
	_push_mouse_button(at, viewport, true, 0, button)
	await get_tree().process_frame
	_push_mouse_button(at, viewport, false, 0, button)
	await get_tree().process_frame

# A real click on a button, in the viewport it is drawn in, answering whether it pressed: a hidden,
# disabled or covered button swallows the click, which a hand-emitted `pressed` never could. A HUD
# just swapped back lays its buttons out a frame later, so the click waits for the rect to land.
func _click_button(button: Button, viewport: SubViewport) -> bool:
	var presses : Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1, CONNECT_ONE_SHOT)
	var at := Vector2.INF
	var waited := 0.0
	while at != button.get_global_rect().get_center() and waited < CARD_CONTROL_TIMEOUT_SEC:
		at = button.get_global_rect().get_center()
		await get_tree().process_frame
		waited += get_process_delta_time()
	_hover_in(viewport, at)
	await get_tree().process_frame
	await _click(at, viewport)
	return presses[0] == 1

# End shows only once the show cannot progress, so every stock goes to the discard pile the show
# sweeps home; the goal is met too, so Continue hands back to the map instead of ending the run.
func _end_the_show_by_its_button(view: GameView) -> void:
	var state := view.game.state
	_drain_the_stocks(state)
	state.goal = 0
	state.revision += 1
	await get_tree().process_frame
	check(await _click_button(view.submit_button, _booted_viewport), "a real click on End pressed it")

# The player's-window fixture boots no harness SubViewport for the click helper to push into, so
# there End is pressed through its own signal: the layout is what is measured.
func _end_the_show_by_pressing_end(view: GameView, in_players_window: bool) -> void:
	if not in_players_window:
		await _end_the_show_by_its_button(view)
		return
	_drain_the_stocks(view.game.state)
	view.game.state.goal = 0
	view.game.state.revision += 1
	await get_tree().process_frame
	view.submit_button.pressed.emit()
	await get_tree().process_frame

## Every stock goes to the discard pile the show sweeps home, which is what an exhausted deck leaves.
func _drain_the_stocks(state: GameData) -> void:
	for stock : ArrayCardData in state.entrance_stocks():
		state.discard_deck.append_array(stock.datas)
		stock.datas.clear()

# The outcome screen builds Continue, so the click waits for it to be laid out, and then for the
# hand-back move it starts to land on the map.
func _continue_to_the_map(view: GameView) -> void:
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC and not (is_instance_valid(view._continue_button)
			and view._continue_button.get_global_rect().has_area()):
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(await _click_button(view._continue_button, _game_viewport),
			"a real click on Continue pressed it")
	while waited < CARD_CONTROL_TIMEOUT_SEC and (_main._current_focus != &"map"
			or _main._move_in_flight):
		await get_tree().process_frame
		waited += get_process_delta_time()

# The cancel button a player presses: a real right press into the game picture's own viewport, so
# the board reads it through the same handler that hears the left one.

# A press aimed at the overlay -- the sidebar or the button band -- goes into the BOOTED viewport
# instead, which is the one the overlay's own layer draws and reads in.
func _second_button_press(at: Vector2, viewport: SubViewport = null) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = at
	event.global_position = at
	(viewport if viewport else _game_viewport).push_input(event)
	await get_tree().process_frame
	await get_tree().process_frame

func _push_mouse_button(at: Vector2, viewport: SubViewport, pressed: bool, device := 0,
		button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.global_position = at
	event.device = device
	viewport.push_input(event)

# Entrance cards are the ones a click can GRAB, so Q56's "the click still performs its game action"
# is only testable on those -- a grid card's click has no pickup to prove.
func _entrance_card_controls() -> Array[Control]:
	var out : Array[Control] = []
	for control : Control in await _hoverable_card_controls():
		if _play_area.upper_zone_right.is_ancestor_of(control) and _is_selectable(control):
			out.append(control)
	return out

# A slot's own zone control sits in `ui_data` but is left FOCUS_NONE and zero-height once a card
# covers it (`_size_stack_slot`), so neither a click nor a key can land on it.
func _is_selectable(control: Control) -> bool:
	return control.focus_mode != Control.FOCUS_NONE

# Clicks a board card the way a player does -- hover first (the board selects what the pointer is
# on), then press and release -- and waits out `try_grab`'s own await.
func _click_card(control: Control) -> void:
	_hover(control.get_global_rect().get_center())
	await get_tree().process_frame
	_hover(control.get_global_rect().get_center())
	await get_tree().process_frame
	await _click(control.get_global_rect().get_center(), _game_viewport)
	await get_tree().process_frame
	await get_tree().process_frame

# WHICH CARD A CLICK LANDED ON IS THE BOARD'S OWN ANSWER: a grab rebuilds the board and the slot
# controls are POOLED, so a mapping read either side of the click can name a different card.
func _watch_clicks() -> Array[CardData]:
	var clicked : Array[CardData] = []
	_play_area.data_selected.connect(func(data: CardData) -> void: clicked.append(data))
	return clicked

# Why an input did not land: every state that decides whether the board acts on one, in the order
# `_on_gui_input` and `grab_focus()` consult them.
func _board_input_state(control: Control) -> String:
	var game := CardEnvironment.get_current_game()
	return ("processing %s, paused %s, held %d, in ui_data %s, visible %s, focus_mode %d, "
			+ "hovered %s, focused %s, owner %s") % [
			game.processing, get_tree().paused, _play_area.selected_cards.size(),
			_play_area.ui_data.has(control), control.is_visible_in_tree(), control.focus_mode,
			_play_area.moused_hovered_control == control, _play_area.focused_control == control,
			control.get_viewport().gui_get_focus_owner()]

func _exit_button() -> Button:
	return _container.get_node(^"%ExitX") as Button

## A hoverable card control whose card is not `avoid`, so the board focus can be moved off it.
func _another_card_control(controls: Array[Control], avoid: CardData) -> Control:
	for control : Control in controls:
		if _play_area.ui_data[control] != avoid and _is_selectable(control): return control
	return null

## Q56=a/Q57=a/B5: one click both grabs the card and locks the sidebar to it -- there is no inspect-only mode.
func test_a_click_grabs_the_card_and_locks_its_description() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var clicked := _watch_clicks()
		await _click_card(entrance[0])
		check(clicked.size() == 1, "the click reached the board's own selection",
				str(clicked.size()))
		check(not _play_area.selected_cards.is_empty(),
				"the click still performs its game action: the card is grabbed (Q57=a)",
				str(_play_area.selected_cards.size()))
		check(_container.is_locked(), "...and the same click locks the description (B5, Q56=a)")
		if clicked.size() == 1:
			check(_play_area.locked_data == clicked[0], "...to the card that was clicked")
			var title : Label = _panel.get_node(^"%Title")
			check(title.text == _expected_text(clicked[0])[0],
					"...and the sidebar shows that card's own name", title.text)
	await _end_main_fixture()

## 1.6/B8/Q61=a: only one lock exists, so locking a second card replaces the first.
func test_locking_a_second_card_replaces_the_first() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(entrance.size() >= 2, "the dealt board offers two clickable Entrance cards",
			str(entrance.size()))
	if entrance.size() >= 2:
		var clicked := _watch_clicks()
		var first : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		check(_play_area.locked_data == first, "the first click locked the first card")
		_play_area.ungrab_cards()
		var next_control := _another_card_control(await _entrance_card_controls(), first)
		check(next_control != null, "a second Entrance card is reachable for the next click")
		if next_control != null:
			await _lock_without_holding(next_control)
			check(clicked.size() == 2, "both clicks reached the board", _board_input_state(next_control))
			check(_container.is_locked(), "the second click leaves the sidebar locked")
			if clicked.size() == 2:
				check(clicked[1] != clicked[0], "the two clicks landed on different cards")
				check(_play_area.locked_data == clicked[1],
						"...to the SECOND card: locking a second replaces the first (B8)")
				_hover(_bare_board_point(entrance))
				await get_tree().process_frame
				check(_container.is_locked() and _play_area.locked_data == clicked[1],
						"...and leaving every card keeps that same lock")
				var title : Label = _panel.get_node(^"%Title")
				check(title.text == _expected_text(clicked[1])[0],
						"...with the second card's own description showing", title.text)
	await _end_main_fixture()

## Q58=c: the locked card keeps the marking a focused card gets, even once the focus has moved on.
func test_the_locked_card_keeps_its_marking_while_focus_moves_on() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the board offers a lockable card", str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		var others := await _hoverable_card_controls()
		_hover(_off_the_board_point())
		await get_tree().process_frame
		var elsewhere := _another_card_control(others, locked)
		check(elsewhere != null, "a second card can take the focus")
		if elsewhere != null:
			elsewhere.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			var moved : CardData = _play_area.ui_data[_play_area.focused_control]
			check(_play_area.focused_control == elsewhere,
					"the key/pad focus landed on that second card",
					_board_input_state(elsewhere))
			var title : Label = _panel.get_node(^"%Title")
			check(title.text == _expected_text(moved)[0],
					"the description follows the new highlight (B1)", title.text)
			check(_play_area.data_card[locked].focused,
					"...and the LOCKED card keeps the focus marking behind it (Q58=c)")
			check(_play_area.data_card[moved].focused,
					"...while the newly focused card is marked as well")
	await _end_main_fixture()

## 1.13/B13/Q65=a: a board rebuild keeps the same CardData's description and its marking, whichever control now represents it.
func test_a_board_rebuild_keeps_the_same_cards_description() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var data : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		_play_area.queue_rebuild()
		await get_tree().process_frame
		_play_area.flush_rebuild()
		await get_tree().process_frame
		check(_container.is_locked() and _play_area.locked_data == data,
				"the lock survives a board rebuild")
		check(title.text == _expected_text(data)[0],
				"...and the sidebar still shows that same card's description", title.text)
		check(_play_area.data_ui.has(data), "...the card has a control again after the rebuild")
		check(_play_area.data_card.has(data) and _play_area.data_card[data].focused,
				"...and the marking is on whichever visual now represents it (B13)")
	await _end_main_fixture()

## 1.7/C16/Q179=a/Q180=a: pressing the exit X reverts the container to the HUD and drops the lock.
func test_the_exit_x_reverts_to_the_hud() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		var hud_stack : Control = _container.get_node(^"%HudStack")
		check(not hud_stack.visible and _container.is_locked(),
				"the description is up and locked before the press")
		await _click(_exit_button().get_global_rect().get_center(), _booted_viewport)
		check(hud_stack.visible and not _panel.visible,
				"the exit X reverts the container to the HUD (B10, Q179=a)")
		check(not _container.is_locked(), "...and the lock is gone (B10)")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		check(_play_area.locked_data == null, "...so the board drops the locked card's marking")
		check(_game_viewport.gui_get_focus_owner() == null,
				"...and a mouse click hands no focus back to the board (only a key/pad accept does)",
				str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## C16/Q47=a: the exit X is a full touch target in the container's top-right, below the overlay's own button band, and only while the description shows.
func test_the_exit_x_is_a_touch_target_below_the_button_band() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var button := _exit_button()
		var target := GestureMetrics.touch_target_px(
				_container.get_viewport().get_visible_rect().size, PlayArea.settings())
		check(button.is_visible_in_tree(), "the exit X shows over a STUCK description")
		check(button.size.x >= target - 0.5 and button.size.y >= target - 0.5,
				"...at the same touch target every overlay control is grown to (Q47=a)",
				"%s vs %.1f" % [button.size, target])
		var rect := button.get_global_rect()
		var bounds := _container.container_rect()
		check(bounds.encloses(rect), "...inside the container's own rect",
				"%s vs %s" % [rect, bounds])
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		check(rect.position.y >= overlay.button_band_bottom(),
				"...below the overlay's button band, never under it (D12)",
				"%.1f vs %.1f" % [rect.position.y, overlay.button_band_bottom()])
		check(absf(rect.end.x - bounds.end.x) <= 1.0,
				"...and in the top-right corner (C16)",
				"%.1f vs %.1f" % [rect.end.x, bounds.end.x])
		_container.show_hud()
		await get_tree().process_frame
		check(not button.is_visible_in_tree(),
				"the HUD hides it again: it belongs to the description")
	await _end_main_fixture()

## The touch target is a share of the window's short side, so a resize that changes that side re-grows every overlay control and the exit X, and the X stays below the re-grown band; harness-scale only.
func test_a_resize_re_applies_every_overlay_touch_target() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		await _resize_viewport(_booted_viewport, Vector2i(1280, 960))
		var window := _container.get_viewport().get_visible_rect().size
		check(window == Vector2(1280, 960), "sanity: the window took the 4:3 resize", str(window))
		var target := GestureMetrics.touch_target_px(window, PlayArea.settings())
		var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
		var row : Array[Button] = [overlay._back_button, overlay._forward_button, overlay._wall_button]
		for button : Button in row:
			check(absf(button.size.y - target) <= 0.5 and button.size.x >= target - 0.5,
					"%s is grown to the resized window's touch target" % button.name,
					"%s vs %.1f" % [button.size, target])
		var exit := _exit_button()
		check(absf(exit.size.x - target) <= 0.5 and absf(exit.size.y - target) <= 0.5,
				"...and so is the exit X", "%s vs %.1f" % [exit.size, target])
		check(absf(overlay.button_band_bottom() - (row[0].position.y + target)) <= 0.5,
				"the band's bottom is the resized row's bottom",
				"%.1f vs %.1f" % [overlay.button_band_bottom(), row[0].position.y + target])
		check(absf(exit.offset_top - overlay.button_band_bottom()) <= 0.5,
				"...and the exit X is parked at that bottom, not the band from before the resize",
				"%.1f vs %.1f" % [exit.offset_top, overlay.button_band_bottom()])
	await _end_main_fixture()

## The overlay row grows from its AUTHORED size, so a visit to a larger touch target and back returns every button, the band and the container's top margin to their fresh values, in the player's window.
func test_a_resize_round_trip_shrinks_the_overlay_row_back() -> void:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var booted := await _boot_main_at(INSET_WINDOWS[0], true)
	var window : Window = booted[0]
	var main : Main = booted[1]
	var overlay : WallOverlay = main.wall.get_node(^"%Overlay")
	var row : Array[Button] = [overlay._back_button, overlay._forward_button, overlay._wall_button]
	var margin : MarginContainer = main.hud_container._game_hud_margin
	var fresh : Array[Rect2] = []
	for button : Button in row:
		fresh.append(button.get_rect())
	var fresh_band := overlay.button_band_bottom()
	var fresh_margin := margin.get_theme_constant(&"margin_top")
	window.size = INSET_WINDOWS[1]
	await get_tree().process_frame
	await get_tree().process_frame
	check(overlay.button_band_bottom() > fresh_band + 0.5,
			"sanity: the tall window grows the band",
			"%.2f vs %.2f, %s" % [overlay.button_band_bottom(), fresh_band, row[0].get_rect()])
	window.size = INSET_WINDOWS[0]
	await get_tree().process_frame
	await get_tree().process_frame
	for i : int in row.size():
		check(row[i].get_rect().is_equal_approx(fresh[i]),
				"%s returns to its fresh rect after the round trip" % row[i].name,
				"%s vs %s" % [row[i].get_rect(), fresh[i]])
	check(absf(overlay.button_band_bottom() - fresh_band) <= 0.5,
			"...so does the band's bottom", "%.2f vs %.2f" % [overlay.button_band_bottom(), fresh_band])
	check(margin.get_theme_constant(&"margin_top") == fresh_margin,
			"...and the container's top margin follows it back",
			"%d vs %d" % [margin.get_theme_constant(&"margin_top"), fresh_margin])
	await _end_booted_fixture(window, main)

## A resize re-lays the description that is already up, so its content follows the container's new width rather than keeping the old one; harness-scale only.
func test_a_resize_relays_the_description_to_the_new_width() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_panel.visible, "the description is up before the resize")
		_booted_viewport.size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		var width := _container._content_size().x
		var content : VBoxContainer = _panel.get_node(^"%Content")
		check(absf(_panel.size.x - width) <= 1.0,
				"the panel follows the container's new width, inside its margins",
				"%.1f vs %.1f" % [_panel.size.x, width])
		check(absf(content.size.x - width) <= 1.0,
				"...and so does the content it lays out",
				"%.1f vs %.1f" % [content.size.x, width])
		var carried := content.custom_minimum_size.y
		_panel.resize_to(Vector2(width, _panel.size.y))
		check(absf(content.custom_minimum_size.y - carried) <= 0.5,
				"...and the height it scrolls to is the new width's, not the old one's",
				"%.1f carried vs %.1f fresh" % [carried, content.custom_minimum_size.y])
	await _end_main_fixture()

# ------------------------------------------------------------------ S6: follow, return, dismiss

## The keyboard Back the wall reads, built the way `test_wall_input` builds it.
func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

# Clicks an Entrance card and leaves NOTHING held: a later cancel cannot then be spent on the
# ungrab instead of on the description, and the pointer can leave the card's cell without the held
# card following it out and closing what was locked.
func _lock_without_holding(control: Control) -> void:
	await _click_card(control)
	_play_area.ungrab_cards()
	await get_tree().process_frame

## 1.4/B7/Q60=c: a locked description FOLLOWS the hover onto another card, and the lock stays where it was.
func test_the_description_follows_the_hover_while_locked() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		check(_container.is_locked() and _play_area.locked_data == locked,
				"the click locked the description to the card it landed on")
		var controls := await _hoverable_card_controls()
		var elsewhere := await _hover_another_card(controls, _play_area.data_ui[locked])
		check(elsewhere != null, "the pointer landed on a second card")
		if elsewhere != null:
			var hovered : CardData = _play_area.ui_data[elsewhere]
			check(hovered != locked, "...a different card from the locked one")
			check(title.text == _expected_text(hovered)[0],
					"the description FOLLOWS the hover while locked (B7, Q60=c)", title.text)
			check(_container.is_locked() and _play_area.locked_data == locked,
					"...and the lock is still on the first card (B8)")
			check(_play_area.data_card[locked].focused,
					"...which keeps its marking behind the hover (Q58=c)")
	await _end_main_fixture()

## 1.5/B7/B4: the pointer leaving everything returns to the LOCKED card, and with no lock keeps the last entry.
func test_leaving_everything_returns_to_the_locked_card() -> void:
	await _start_game_fixture()
	var slot : Control = _panel.get_node(^"%VisualSlot")
	var title : Label = _panel.get_node(^"%Title")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		var locked_visual : Node = _panel.current_entry.visual
		var controls := await _hoverable_card_controls()
		var elsewhere := await _hover_another_card(controls, _play_area.moused_hovered_control)
		check(elsewhere != null, "the pointer landed on a second card")
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(locked)[0],
				"the pointer leaving every card returns to the LOCKED card (B7, Q60=c)", title.text)
		var back : InfoEntry = _panel.current_entry
		check(is_instance_valid(locked_visual) and back != null and back.visual == locked_visual
				and locked_visual.get_parent() == slot,
				"...the very visual the lock was shown with, handed back rather than freed")
		_hover(_off_the_board_point())
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(locked)[0],
				"...and leaving the board entirely keeps it there", title.text)

		_container.show_hud()
		var first := await _hover_another_card(controls, null)
		var second := await _hover_another_card(controls, first)
		check(second != null, "two cards can be read in turn with nothing locked")
		if second != null:
			_hover(_bare_board_point(controls))
			await get_tree().process_frame
			await get_tree().process_frame
			check(not _container.is_locked(), "nothing is locked once the container went back")
			check((_container.get_node(^"%HudStack") as Control).visible and not _panel.visible,
					"...so leaving everything CLOSES an unstuck description (R, overturns B4)")
	await _end_main_fixture()

## Viewer-path answer (2) on the BOARD: a click sticks and shows the X, other cards borrow the sidebar without the X only while hovered, and the stuck one is back once the pointer is on nothing -- or on the sidebar itself.
func test_a_stuck_card_survives_hovers_and_the_pointer_reaching_the_sidebar() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var stuck := await _stick_an_entrance_card()
	if stuck != null:
		check(_container.is_locked(), "a CLICK is what sticks the description")
		check(_exit_button().is_visible_in_tree(),
				"...and only a stuck description carries the exit X")

		var controls := await _hoverable_card_controls()
		var elsewhere := await _hover_another_card(controls, _play_area.data_ui[stuck])
		check(elsewhere != null, "the pointer landed on a second card")
		if elsewhere != null:
			check(title.text == _expected_text(_play_area.ui_data[elsewhere])[0],
					"hovering another card borrows the sidebar while it lasts", title.text)
			check(_container.is_locked() and _play_area.locked_data == stuck,
					"...without unsticking the clicked one")
			check(not _exit_button().is_visible_in_tree(),
					"...with no X: the borrowed description is not the stuck one")
			_hover(_bare_board_point(controls))
			await get_tree().process_frame
			await get_tree().process_frame
			check(title.text == _expected_text(stuck)[0] and _exit_button().is_visible_in_tree(),
					"...and the stuck card is back, with its X, once no card is hovered", title.text)

		var borrowed := await _hover_another_card(controls, _play_area.data_ui[stuck])
		check(borrowed != null, "the pointer can borrow the sidebar a second time")
		_hover(_off_the_board_point())
		_hover_in(_booted_viewport, _container.get_global_rect().get_center())
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == _expected_text(stuck)[0],
				"the pointer REACHING THE SIDEBAR shows the stuck card, so it can be read there",
				title.text)
		check(_container.is_locked() and _play_area.locked_data == stuck,
				"...still stuck to the card that was clicked")
	await _end_main_fixture()

## B7 for the pad: the board focus landing on a HUD control leaves no card highlighted, so the locked card comes back.
func test_focus_leaving_the_board_returns_to_the_locked_card() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		_hover(_off_the_board_point())
		await get_tree().process_frame
		var elsewhere := _another_card_control(await _hoverable_card_controls(), locked)
		check(elsewhere != null, "a second card can take the board focus")
		if elsewhere != null:
			elsewhere.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			var moved : CardData = _play_area.ui_data[elsewhere]
			check(title.text == _expected_text(moved)[0],
					"the pad's own highlight moved the description with it (B1)", title.text)
			_container.submit_button.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			check(_play_area.get_viewport().gui_get_focus_owner() == null,
					"the board has no focused control left once the HUD took the focus",
					str(_play_area.get_viewport().gui_get_focus_owner()))
			check(title.text == _expected_text(locked)[0],
					"...so the description returns to the locked card (B7, Q60=c)", title.text)
	await _end_main_fixture()

## 1.7/B9/B10/Q64=a/Q100=c: cancel with nothing held reverts to the HUD, and the SAME press reaches the wall -- the transition then locks input, so there is no second press to make.
func test_cancel_reverts_to_the_hud_and_still_reaches_the_wall() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		var left_the_screen : Array[bool] = [false]
		_main.wall.wall_view_entered.connect(func() -> void: left_the_screen[0] = true)
		check(_container.showing_description() and _play_area.selected_cards.is_empty(),
				"the description is up and nothing is held before the cancel")

		_booted_viewport.push_input(_cancel_event())
		await get_tree().process_frame
		check(hud_stack.visible and not _panel.visible,
				"cancel with nothing held reverts the container to the HUD (B9, B10)")
		check(not _container.is_locked(), "...and the lock is gone with it")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		check(left_the_screen[0],
				"...and that ONE press also reaches the wall's own zoom out, rather than a second one doing it (Q100=c)")
	await _end_main_fixture()

## S18.1/Q99=b: the second mouse button cancels ONE thing per press -- the held card first, the description on the next press.
func test_the_second_button_releases_the_held_card_then_dismisses() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var at := entrance[0].get_global_rect().get_center()
		await _click_card(entrance[0])
		var held := _held_card()
		check(held != null, "the click left the card held", str(_play_area.selected_cards.size()))
		check(_container.showing_description(), "...with its description up")
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		await _second_button_press(at)
		check(_play_area.selected_cards.is_empty(),
				"the first second-button press released the held card (S18.1, Q99=b)",
				str(_play_area.selected_cards.size()))
		if held != null and held in _play_area.data_card:
			var visual : CardVisual = _play_area.data_card[held]
			check(visual.held == 0 and not visual.following,
					"...back in its slot, neither held nor following (S18.1)",
					"%d / %s" % [visual.held, str(visual.following)])
		check(_container.showing_description() and dismissals.is_empty(),
				"...and the description it was reading is still up (S18.1, E20)",
				str(dismissals.size()))
		await _second_button_press(at)
		check(not _container.showing_description() and dismissals.size() == 1,
				"a second press then dismisses the description (S18.1, E21)",
				str(dismissals.size()))
	await _end_main_fixture()

## 1.7/B9/B10: a real press on bare board reverts the container to the HUD.
func test_a_press_on_bare_board_reverts_to_the_hud() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var controls := await _hoverable_card_controls()
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		check(_container.showing_description(), "the description is up before the press")
		var bare := _bare_board_point(controls)
		_hover(bare)
		await get_tree().process_frame
		await _click(bare, _game_viewport)
		check(hud_stack.visible and not _panel.visible,
				"a press on bare board reverts the container to the HUD (B9, B10)")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
	await _end_main_fixture()

# Whether the board's own drop map takes `held` onto the cell this control belongs to, so no
# placement rule is spelled out here.
func _board_accepts(held: Array[CardData], control: Control) -> bool:
	return _zone_card_of(_play_area.ui_data[control]) in await _drop_map(held)

## The zone cards the board lets `held` land on, asked the way the highlight asks.
func _drop_map(held: Array[CardData]) -> Array[CardData]:
	var game := CardEnvironment.get_current_game()
	return await game.legal_cells_for(held, game.state.grids)

# The map holds ZONE cards, so a control is looked up by the cell it names or sits in; an
# Entrance card sits in no cell (its row is -1, which is no cell index) and is a landing the
# map never holds.
func _zone_card_of(data: CardData) -> CardData:
	var state := CardEnvironment.get_current_game().state
	if not state.cell_type_coord(data).is_nowhere(): return data
	var coord := state.grid_position_of(data)
	if coord.is_nowhere() or coord.is_entrance(): return null
	var grid : GridData = state.grids[coord.grid]
	return grid.cell_types[grid.cell_index(coord.x, coord.y)]

# A landing for `held` the board itself accepts or refuses.
func _placement_target(controls: Array[Control], held: Array[CardData], legal: bool) -> Control:
	var map := await _drop_map(held)
	for control : Control in controls:
		if not _is_selectable(control): continue
		if _play_area.ui_data[control] in held: continue
		if (_zone_card_of(_play_area.ui_data[control]) in map) == legal: return control
	return null

## Clicks an Entrance card and hands back what the board grabbed -- the shared opening of every placement test.
func _grab_a_card_to_place() -> Array[CardData]:
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a grabbable Entrance card",
			str(entrance.size()))
	if entrance.is_empty(): return []
	await _click_card(entrance[0])
	var held : Array[CardData] = _play_area.selected_cards.duplicate()
	check(not held.is_empty(), "the click grabbed a card to place", str(held.size()))
	return held

## B12/Q63=a: placing the held card finishes the interaction, so the description closes -- a refused place leaves it up.
func test_placing_a_card_closes_the_description() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var controls := await _hoverable_card_controls()
		var refused := await _placement_target(controls, held, false)
		check(refused != null, "the board offers a cell this card may NOT land on")
		if refused != null:
			await _click_card(refused)
			check(_panel.visible and not hud_stack.visible,
					"a refused place leaves the description up: the choice is not finished")
			check(not _play_area.selected_cards.is_empty(), "...and the card is still held")
		var carried : Array[CardData] = _play_area.selected_cards.duplicate()
		var legal := await _placement_target(await _hoverable_card_controls(), carried, true)
		check(legal != null, "the board offers a cell this card MAY land on")
		if legal != null:
			await _click_card(legal)
			await get_tree().process_frame
			check(carried[0] not in _play_area.selected_cards, "the card was placed",
					str(_play_area.selected_cards.size()))
			check(hud_stack.visible and not _panel.visible,
					"placing the card closes the description (B12, Q63=a)")
			check(not _container.is_locked(), "...and the lock goes with it")
	await _end_main_fixture()

## A leak is no check failure, so the one path that can orphan a visual -- a lock replaced while a hover holds the panel -- is checked here.
func test_replacing_a_displaced_lock_frees_its_visual() -> void:
	var container := _build_container()
	var locked := InfoEntry.new()
	locked.visual = Control.new()
	container.lock_to(locked)
	container.show_description(InfoEntry.new())
	check(is_instance_valid(locked.visual) and locked.visual.get_parent() == null,
			"a hover takes the locked visual OUT of the panel rather than freeing it")
	container.lock_to(InfoEntry.new())
	await get_tree().process_frame
	check(not is_instance_valid(locked.visual),
			"...and the NEXT lock frees the displaced one, which nothing holds any more")
	container.queue_free()


# ------------------------------------------------------------------ S7: the processing rule

## Exactly one content child ever shows, so "the HUD is what is up" is one question both ways.
func _hud_is_up() -> bool:
	return (_container.get_node(^"%HudStack") as Control).visible and not _panel.visible

## The control the board presents `data` on NOW -- a grab rebuilds the board and its slot controls are POOLED, so one read before a rebuild can name a different card after it.
func _control_for(data: CardData) -> Control:
	for control : Control in _play_area.ui_data:
		if _play_area.ui_data[control] == data: return control
	return null

# A real placement, watched two ways at once: the flip itself (a cascade shorter than a frame is
# still a cascade) and then every frame it runs for. Returns [flips, flips with the HUD up,
# busy frames, busy frames with the HUD up].
func _place_and_watch_the_cascade(target: Control) -> Array[int]:
	var game := CardEnvironment.get_current_game()
	var counts : Array[int] = [0, 0, 0, 0]
	var watcher := func(busy: bool) -> void:
		if not busy: return
		counts[0] += 1
		if _hud_is_up(): counts[1] += 1
	game.processing_changed.connect(watcher)
	var at := target.get_global_rect().get_center()
	_hover(at)
	await get_tree().process_frame
	_push_mouse_button(at, _game_viewport, true)
	_push_mouse_button(at, _game_viewport, false)
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if game.processing:
			counts[2] += 1
			if _hud_is_up(): counts[3] += 1
		elif counts[0] > 0:
			break
	game.processing_changed.disconnect(watcher)
	return counts

## 1.9/B17/B18/C8/Q255=a/Q256=a: `processing` going true reverts to the HUD whatever was showing, and the lock is gone for good.
func test_processing_reverts_to_the_hud_and_drops_the_lock() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var dismissals : Array[bool] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(true))
		await _lock_without_holding(entrance[0])
		check(_container.is_locked() and not _hud_is_up(),
				"a LOCKED description is what shows before the cascade")
		dismissals.clear()
		var game := CardEnvironment.get_current_game()
		game.processing = true
		check(_hud_is_up(), "processing reverts the container to the HUD, lock and all (B17, Q255=a)")
		check(not _container.is_locked(), "...and the lock is gone (B18, Q256=a)")
		check(_play_area.locked_data == null, "...so the board drops that card's marking too")
		check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
		dismissals.clear()
		game.processing = false
		check(_hud_is_up(), "the lock is NOT restored when processing ends (B18)")
		check(dismissals.is_empty(), "...and nothing is announced for a HUD that was already up",
				str(dismissals.size()))
	await _end_main_fixture()

## 1.9/C8/Q259b=b: a REAL placement -- the HUD is what the whole cascade is watched in, from the flip to the last frame.
func test_a_real_cascade_holds_the_hud_for_its_whole_length() -> void:
	await _start_game_fixture()
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var legal := await _placement_target(await _hoverable_card_controls(), held, true)
		check(legal != null, "the board offers a cell this card MAY land on")
		if legal != null:
			var counts := await _place_and_watch_the_cascade(legal)
			check(counts[0] >= 1, "the placement really started a cascade", str(counts[0]))
			check(counts[1] == counts[0],
					"the HUD was up the instant processing began (B17, C8)",
					"%d of %d flips" % [counts[1], counts[0]])
			check(counts[3] == counts[2],
					"...and for every frame the cascade ran (C8, Q259b=b)",
					"%d of %d frames" % [counts[3], counts[2]])
			check(_hud_is_up(), "...and it is still up once the cascade has finished (B20)")
			check(not _container.is_locked(), "...with no lock left behind (B18)")
	await _end_main_fixture()

## 1.10/B19/Q258=a: a hover DURING the cascade is ignored entirely, so a resting pointer cannot swap the HUD straight back out.
func test_a_hover_during_processing_changes_nothing() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var game := CardEnvironment.get_current_game()
		game.processing = true
		check(_hud_is_up(), "the cascade put the HUD up")
		var elsewhere := await _hover_another_card(await _hoverable_card_controls(),
				_play_area.moused_hovered_control)
		check(elsewhere != null, "the pointer landed on another card mid-cascade")
		check(_hud_is_up(), "...and the HUD is still what shows: the hover is ignored (B19, Q258=a)")
		check(not _container.is_locked(), "...with no lock taken from it either")
		game.processing = false
	await _end_main_fixture()

## 1.11/B20/C9/Q257=b: once the cascade ends the HUD holds until ANY focus event -- landing back on the card it was already on counts.
func test_the_hud_holds_after_processing_until_any_focus_event() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var read : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		var game := CardEnvironment.get_current_game()
		game.processing = true
		var elsewhere := await _hover_another_card(await _hoverable_card_controls(),
				_control_for(read))
		check(elsewhere != null and _play_area.ui_data[elsewhere] != read,
				"the pointer landed on a DIFFERENT card mid-cascade")
		game.processing = false
		await get_tree().process_frame
		check(_hud_is_up(), "processing ended and the HUD HOLDS with no focus event (B20, C9)")
		var back := _control_for(read)
		check(back != null, "the card that was being read before the cascade is still on the board")
		if back != null:
			check(_game_viewport.gui_get_focus_owner() != back,
					"...and the board focus is elsewhere, so landing on it again is a real focus event")
			back.grab_focus()
			await get_tree().process_frame
			var title : Label = _panel.get_node(^"%Title")
			check(not _hud_is_up(),
					"one focus event onto the SAME card opens the description again (Q257=b)")
			check(title.text == _expected_text(read)[0], "...that card's own description", title.text)
			var other := await _hover_another_card(await _hoverable_card_controls(), back)
			check(other != null, "a real hover reaches a different card")
			if other != null:
				check(title.text == _expected_text(_play_area.ui_data[other])[0],
						"...and the ordinary hover route is live again", title.text)
	await _end_main_fixture()

## 1.12/C10/Q260b=b: the processing rule is the GAME screen only -- the map has no cascade worth watching, so its container never swaps on one.
func test_the_maps_container_does_not_swap_on_the_games_processing() -> void:
	await _start_game_fixture()
	await _main._focus_picture(&"map")
	check((_container.get_node(^"%MapHud") as Control).visible, "the map is the focused screen")
	var node := _map.controller._sorted_next()[0]
	await _select_map_node_and_settle(node)
	check(_container.showing_description(), "a map pick fills the sidebar")
	var game := CardEnvironment.get_current_game()
	game.processing = true
	check(_container.showing_description(),
			"the game's processing leaves the map's description up (C10, Q260b=b)")
	var described : InfoEntry = _panel.current_entry
	_map.controller.clear_selection()
	await get_tree().process_frame
	await _select_map_node_and_settle(node)
	check(_container.showing_description() and _panel.current_entry != described,
			"...and a real pick's publication still reaches it mid-cascade (1.12)")
	game.processing = false
	await _end_main_fixture()

## B20/C9/Q257=b: nothing is de-duplicated away -- the very entry that was up when the cascade started re-shows when it is published again.
func test_the_same_entry_published_again_after_processing_still_shows() -> void:
	var container := _build_container()
	container.set_active_screen(&"game")
	var entry := InfoEntry.new()
	container.show_description(entry)
	check(container.showing_description(), "the entry is what shows before the cascade")
	container.set_processing(true)
	check(not container.showing_description(), "processing put the HUD up (B17)")
	container.set_processing(false)
	check(not container.showing_description(), "...and the HUD holds once processing ends (B20)")
	container.show_description(entry)
	check(container.showing_description(),
			"the SAME entry published again re-shows it: nothing is swallowed (Q257=b)")
	container.queue_free()

# ------------------------------------------------------------------ S8: scroll and multi-modal reach

## How many lines the scroll fixtures' body carries -- a real card's own text is three lines and fits every window this suite builds, which would leave every scroll assertion trivially true.
const LONG_BODY_LINES := 80

## Frames a pushed stick is held for before the scroll it drives is read -- the stick reports once and the container integrates it per frame.
const STICK_HELD_FRAMES := 10

func _long_entry() -> InfoEntry:
	var entry := InfoEntry.new()
	entry.title = "Scrolling"
	var lines : Array[String] = []
	for line : int in LONG_BODY_LINES:
		lines.append("line %d of a description far longer than the container is tall" % line)
	entry.body = "\n".join(lines)
	return entry

func _short_entry() -> InfoEntry:
	var entry := InfoEntry.new()
	entry.title = "Short"
	entry.body = "One line."
	return entry

func _panel_scroll(panel: DescriptionPanel) -> ScrollContainer:
	return panel.get_node(^"%Scroll") as ScrollContainer

# The axis the InputMap actually binds, never a constant of this suite's own: Q102=a makes every
# action rebindable, and pinning one here would turn a rebind into a failure.
func _scroll_stick_axis() -> int:
	if not InputMap.has_action(&"sidebar_scroll"): return -1
	for event : InputEvent in InputMap.action_get_events(&"sidebar_scroll"):
		var motion := event as InputEventJoypadMotion
		if motion: return motion.axis
	return -1

func _push_scroll_stick(viewport: Viewport, axis_value: float) -> void:
	var axis := _scroll_stick_axis()
	if axis < 0: return
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis as JoyAxis
	motion.axis_value = axis_value
	viewport.push_input(motion)

func _push_key(viewport: Viewport, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	viewport.push_input(event)

## Q42=a: `sidebar_scroll` is a real action, on an axis Godot's own navigation does not already steer with.
func test_the_sidebar_scroll_action_binds_the_non_navigation_stick() -> void:
	check(InputMap.has_action(&"sidebar_scroll"), "the InputMap registers sidebar_scroll")
	if not InputMap.has_action(&"sidebar_scroll"): return
	var events := InputMap.action_get_events(&"sidebar_scroll")
	check(not events.is_empty(), "sidebar_scroll has at least one real binding",
			"events=%d" % events.size())
	var axes : Array[int] = []
	var directions : Array[float] = []
	for event : InputEvent in events:
		var motion := event as InputEventJoypadMotion
		check(motion != null, "every sidebar_scroll binding is a joypad axis (Q42=a)")
		if motion == null: continue
		if not axes.has(motion.axis): axes.append(motion.axis)
		if not directions.has(signf(motion.axis_value)): directions.append(signf(motion.axis_value))
	check(axes.size() == 1, "...all of them the same axis, so one stick scrolls", str(axes))
	check(directions.size() == 2, "...bound both ways, so the stick scrolls up AND down",
			str(directions))
	var navigation_axes : Array[int] = []
	for action : StringName in ([&"ui_up", &"ui_down"] as Array[StringName]):
		for event : InputEvent in InputMap.action_get_events(action):
			var motion := event as InputEventJoypadMotion
			if motion and not navigation_axes.has(motion.axis):
				navigation_axes.append(motion.axis)
	check(not axes.is_empty() and not navigation_axes.has(axes[0]),
			"...and it is NOT the stick ui_up/ui_down already navigate with (Q42=a)",
			"scroll=%s navigation=%s" % [str(axes), str(navigation_axes)])

## Q40=b/Q41=a: an overflowing description shows the scrollbar and opens at the top, however far the last one was scrolled.
func test_a_long_description_shows_a_scrollbar_and_rests_at_the_top() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	check(scroll.get_v_scroll_bar().visible,
			"a description taller than the container shows the scrollbar (Q40=b)")
	check(scroll.scroll_vertical == 0, "...and opens at the top (Q41=a)",
			str(scroll.scroll_vertical))
	_push_key(get_viewport(), KEY_PAGEDOWN, true)
	await get_tree().process_frame
	check(scroll.scroll_vertical > 0, "a page down really moved it", str(scroll.scroll_vertical))
	container.show_description(_long_entry())
	await get_tree().process_frame
	check(scroll.scroll_vertical == 0, "...and the next description rests at the top again (Q41=a)",
			str(scroll.scroll_vertical))
	container.queue_free()

## Q40=b: the other half of the rule -- content that fits carries no scrollbar at all.
func test_a_short_description_hides_the_scrollbar() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_short_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	check(not scroll.get_v_scroll_bar().visible,
			"a description that fits shows no scrollbar (Q40=b)")
	container.queue_free()

## Q43=b: Page Down and Page Up move the description a page, whenever it is what shows.
func test_page_keys_scroll_the_description_by_a_page() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	_push_key(get_viewport(), KEY_PAGEDOWN, true)
	await get_tree().process_frame
	var page := scroll.size.y
	check(absf(float(scroll.scroll_vertical) - page) <= 1.0,
			"Page Down scrolls exactly one page of the description (Q43=b)",
			"%d vs %.1f" % [scroll.scroll_vertical, page])
	_push_key(get_viewport(), KEY_PAGEUP, true)
	await get_tree().process_frame
	check(scroll.scroll_vertical == 0, "...and Page Up brings it back",
			str(scroll.scroll_vertical))
	container.queue_free()

## Q42=a: the stick scrolls whatever description is showing, and does nothing at all behind the HUD.
func test_the_scroll_stick_scrolls_the_description_and_not_the_hud() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	await get_tree().process_frame
	await get_tree().process_frame
	_push_scroll_stick(get_viewport(), 1.0)
	var held := await _hold_stick_until_scrolled(scroll, 0)
	var scrolled := scroll.scroll_vertical
	check(scrolled > 0, "the stick scrolls the description while it shows (Q42=a)",
			"%d px after %.0f ms" % [scrolled, held * 1000.0])
	_push_scroll_stick(get_viewport(), 0.0)
	await get_tree().process_frame
	var rested := scroll.scroll_vertical
	for frame : int in STICK_HELD_FRAMES: await get_tree().process_frame
	check(scroll.scroll_vertical == rested, "...and stops the moment it centres",
			"%d vs %d" % [scroll.scroll_vertical, rested])
	container.show_hud()
	_push_scroll_stick(get_viewport(), 1.0)
	for frame : int in STICK_HELD_FRAMES: await get_tree().process_frame
	check(scroll.scroll_vertical == rested, "...and moves nothing while the HUD shows",
			"%d vs %d" % [scroll.scroll_vertical, rested])
	_push_scroll_stick(get_viewport(), 0.0)
	container.queue_free()

## How tall the scroll is made for the slow-scroll check: a fraction of a pixel a frame at any frame rate this suite runs at, which is where a per-frame rounding loses the scroll entirely.
const SHORT_PANEL_PX := 40.0

## A deflection clear of the stick's own deadzone but nowhere near full.
const LOW_STICK_DEFLECTION := 0.25

## Summed process delta a held stick is given to move the scroll before the check gives up, at any frame rate this suite runs at.
const STICK_HELD_SECONDS := 1.0

# THE STICK IS INTEGRATED PER DELTA, SO A FRAME COUNT PROVES NOTHING: 30 frames measured 45 ms at
# the windowed rate, short of the 50 ms a gentle push needs for its first whole pixel.
func _hold_stick_until_scrolled(scroll: ScrollContainer, from: int) -> float:
	var elapsed := 0.0
	while scroll.scroll_vertical == from and elapsed < STICK_HELD_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return elapsed

## Q42=a: a gentle push on the stick still scrolls a short description, rather than rounding away to nothing every frame.
func test_a_low_stick_deflection_still_scrolls_a_short_description() -> void:
	var container := _build_container()
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var scroll := _panel_scroll(panel)
	container.show_description(_long_entry())
	container.size = Vector2(container.size.x, SHORT_PANEL_PX)
	await get_tree().process_frame
	await get_tree().process_frame
	check(scroll.size.y <= SHORT_PANEL_PX,
			"the description is short enough that one frame of a gentle push is under a pixel",
			str(scroll.size.y))
	_push_scroll_stick(get_viewport(), LOW_STICK_DEFLECTION)
	var held := await _hold_stick_until_scrolled(scroll, 0)
	check(scroll.scroll_vertical > 0,
			"a low stick deflection still scrolls a short description (Q42=a)",
			"%d px after %.0f ms" % [scroll.scroll_vertical, held * 1000.0])
	_push_scroll_stick(get_viewport(), 0.0)
	container.queue_free()

## Q43=b: the arrows are the sidebar's only once it is LOCKED; unlocked they stay the board's own.
func test_the_arrows_scroll_only_once_the_description_is_locked() -> void:
	await _start_game_fixture()
	var scroll := _panel_scroll(_panel)
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to read",
			str(controls.size()))
	if not controls.is_empty():
		controls[0].grab_focus()
		await get_tree().process_frame
		var focused_before := _game_viewport.gui_get_focus_owner()
		check(focused_before == controls[0],
				"a board card holds the key/pad focus before any arrow is pushed")
		_container.show_description(_long_entry())
		await get_tree().process_frame
		await get_tree().process_frame
		_push_key(_booted_viewport, KEY_DOWN, true)
		var handled_unlocked := _booted_viewport.is_input_handled()
		await get_tree().process_frame
		check(scroll.scroll_vertical == 0,
				"an UNLOCKED description does not take the arrow (Q43=b)",
				str(scroll.scroll_vertical))
		check(not handled_unlocked, "...so the board still gets it")
		_container.lock_to(_long_entry())
		await get_tree().process_frame
		await get_tree().process_frame
		_push_key(_booted_viewport, KEY_DOWN, true)
		var handled_locked := _booted_viewport.is_input_handled()
		await get_tree().process_frame
		check(scroll.scroll_vertical > 0, "a LOCKED description scrolls on the arrow (Q43=b)",
				str(scroll.scroll_vertical))
		check(handled_locked, "...spending the event before the board can see it")
		check(_game_viewport.gui_get_focus_owner() == focused_before,
				"...so the board's own selection does not move with it")
	await _end_main_fixture()

## Q68=b/C16: the exit X joins keyboard/pad navigation whenever a description shows -- a pad player can always dismiss what is shown -- and accept on it dismisses.
func test_the_exit_x_joins_navigation_whenever_a_description_shows() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to read",
			str(controls.size()))
	if not controls.is_empty():
		_container.show_hud()
		await get_tree().process_frame
		check(_exit_button().focus_mode == Control.FOCUS_NONE,
				"the HUD keeps the X out of the navigation path entirely (Q68=b)",
				str(_exit_button().focus_mode))
		_container.show_description(_long_entry())
		await get_tree().process_frame
		check(_exit_button().focus_mode == Control.FOCUS_ALL,
				"an unlocked description puts it in: a pad player can always dismiss what is shown",
				str(_exit_button().focus_mode))
		_container.lock_to(_long_entry())
		await get_tree().process_frame
		check(_exit_button().focus_mode == Control.FOCUS_ALL,
				"...and locking keeps it there (Q68=b, C16)", str(_exit_button().focus_mode))
		_push_key(_booted_viewport, KEY_UP, true)
		await get_tree().process_frame
		check(_exit_button().has_focus(),
				"...and navigation off the top of the locked description lands on it (Q68=b)",
				str(_booted_viewport.gui_get_focus_owner()))
		_push_key(_booted_viewport, KEY_ENTER, true)
		_push_key(_booted_viewport, KEY_ENTER, false)
		await get_tree().process_frame
		check(hud_stack.visible and not _panel.visible,
				"...and accept on it dismisses the description (C16)")
		check(not _container.is_locked(), "...taking the lock with it")
	await _end_main_fixture()

func _tap_key(keycode: Key) -> void:
	_push_key(_booted_viewport, keycode, true)
	_push_key(_booted_viewport, keycode, false)
	await get_tree().process_frame
	await get_tree().process_frame

## Multi-modal: a key/pad player who dismisses with the X lands back on the board, and the next accept acts there.
func test_accepting_the_exit_x_hands_the_focus_back_to_the_board() -> void:
	await _start_game_fixture()
	await _hoverable_card_controls()
	var described := _game_viewport.gui_get_focus_owner()
	check(_play_area.ui_data.has(described),
			"sanity: the show rests the focus on a board card", str(described))
	var selected := _watch_clicks()
	await _tap_key(KEY_ENTER)
	check(_container.is_locked() and selected.size() == 1,
			"sanity: accept on that card locked its description", str(selected.size()))
	await _tap_key(KEY_UP)
	check(_exit_button().has_focus(), "sanity: navigation reached the X (Q68=b)",
			str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_ENTER)
	check(_hud_is_up(), "accept on the X dismissed the description")
	var owner := _game_viewport.gui_get_focus_owner()
	if is_instance_valid(described) and _play_area.ui_data.has(described):
		check(owner == described,
				"...and the focus is back on the board card it was opened from (Q68=b, multi-modal)",
				"%s vs %s" % [owner, described])
	else:
		check(owner != null and _play_area.ui_data.has(owner),
				"...and the focus is back on a board control, the one it was opened from having been "
				+ "rebuilt away (Q68=b, multi-modal)", str(owner))
	check(_hud_is_up(), "...without that focus re-opening what was just dismissed")
	await await_the_tap_window()
	await _tap_key(KEY_ENTER)
	check(selected.size() == 2, "...so the next accept acts on the board (multi-modal)",
			str(selected.size()))
	await _end_main_fixture()

# ------------------------------------------------ A SCREEN'S STATE BELONGS TO ITS OWN CONTENT

# A hand-back leaves `Main` mid-move and a move in flight refuses the next one outright, so a test
# that acts on the screen the hand-back lands on waits that move out first.
func _wait_out_the_move() -> void:
	var waited := 0.0
	while _main._move_in_flight and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()

# The product's own way into the NEXT show: `Main` builds a whole new `GameView`, so the fixture's
# cached board nodes are re-read off the one that is live now.
func _restart_the_show() -> void:
	await _wait_out_the_move()
	await _main.enter_game()
	var view := _main._pictures[&"game"].screen_root as GameView
	CardEnvironment.CURRENT = view.game
	_play_area = view.play_area
	_game_viewport = _main._pictures[&"game"].viewport

# The gate reads godot.log after the whole run, so an error raised inside one row's window is
# heard here as the engine raises it, with what it said for the failure detail.
class _Errors extends Logger:
	var said : Array[String] = []

	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING: said.append("%s: %s %s" % [function, code, rationale])

## The outcome screen keeps the show busy, so the sidebar takes no publication there: a click on a listed card sticks it in its viewer and leaves no lock without an entry.
func test_a_listed_card_clicked_on_the_outcome_screen_leaves_no_empty_lock() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _end_the_show_by_its_button(view)
	check(view.game.processing and _hud_is_up(),
			"sanity: the outcome screen is up, the show busy and the sidebar on its HUD")
	check(await _click_button(_container.discard_ui.get_node(^"Button") as Button, _booted_viewport),
			"sanity: a real click on Discard, which holds the swept stocks, pressed it on the outcome screen")
	await get_tree().process_frame
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer) and not viewer.cards().controls.is_empty(),
			"sanity: Discard opened a viewer that lists cards")
	if is_instance_valid(viewer) and not viewer.cards().controls.is_empty():
		await _await_the_list_at_rest(viewer._scroll as SmoothScrollContainer)
		var listed := viewer.cards().controls[0]
		var at := listed.get_global_rect().get_center()
		var errors := _Errors.new()
		OS.add_logger(errors)
		_hover_in(_booted_viewport, at)
		await get_tree().process_frame
		await _click(at, _booted_viewport)
		var stuck := viewer.cards().sticky
		_hover_in(_booted_viewport, viewer.margin_container.get_global_rect().end - Vector2.ONE)
		await get_tree().process_frame
		OS.remove_logger(errors)
		check(stuck != null and stuck == viewer.cards()._data_of[listed] and listed.has_focus(),
				"sanity: the real click landed on the listed card and stuck it in its viewer")
		check(errors.said.is_empty(), "the click and the pointer leaving raise no error",
				"\n".join(errors.said))
		check(not _container.is_locked() or _container._locked_entry_by_screen[&"game"] != null,
				"...and leave no lock without an entry, which every later return to the lock would read")
		await _close_the_open_viewer()
	await _end_main_fixture()

## A show hands back with its cascade flag still up, so the NEXT show must not inherit it: its first hover opens a description.
func test_a_finished_show_leaves_no_cascade_flag_for_the_next_one() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _end_the_show_by_its_button(view)
	check(view.game.processing, "the ended show is still flagged busy as it hands back")
	await _continue_to_the_map(view)
	await _restart_the_show()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the next show dealt a card control to hover",
			str(controls.size()))
	if not controls.is_empty():
		_hover(controls[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_container.showing_description(),
				"the next show's first hover opens a description: B19 died with the last show")
		check(not _container.is_locked(), "...and nothing is locked in it yet")
	await _end_main_fixture()

## A new run replaces the show, so the container must not re-open the last show's locked description over a fresh board.
func test_a_new_run_does_not_inherit_the_last_shows_lock() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		check(_container.is_locked(), "the show is left with a locked description")
		await _main._on_new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
		await _restart_the_show()
		check(_hud_is_up(), "the new show opens on the HUD, not the last show's description")
		check(not _container.is_locked(), "...and with nothing locked (PLAN 5 step 1)")
		check(_play_area.locked_data == null, "...and no card marked on the fresh board")
	await _end_main_fixture()

## A show left with a card in hand hands its hand back too: in the next show's stuck description, Up reaches the X again.
func test_a_new_run_does_not_inherit_the_last_shows_hand() -> void:
	await _start_game_fixture()
	var on_the_entrance := func() -> bool:
		var owner := _game_viewport.gui_get_focus_owner()
		return owner != null and _play_area.upper_zone_right.is_ancestor_of(owner)
	await _tap_until(KEY_DOWN, on_the_entrance, 8)
	await _tap_key(KEY_ENTER)
	check(not _play_area.selected_cards.is_empty(),
			"sanity: the keys lifted an Entrance card, so the show is left with a card in hand")
	await _main._on_new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	await _restart_the_show()
	await _hoverable_card_controls()
	var described := _game_viewport.gui_get_focus_owner()
	check(_play_area.ui_data.has(described),
			"sanity: the new show rests the focus on a board card", str(described))
	await _tap_key(KEY_ENTER)
	check(_container.is_locked() and _play_area.selected_cards.is_empty(),
			"sanity: accept on that card sticks its description with nothing in hand",
			str(_play_area.selected_cards.size()))
	await _tap_key(KEY_UP)
	check(_exit_button().has_focus(),
			"...so Up climbs to the X, the last show's hand not inherited",
			str(_booted_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## The map persists across runs, so its remembered description is the RUN's: a new run's map opens on its own HUD, not the last run's pack.
func test_a_new_run_does_not_inherit_the_maps_last_description() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	await _close_the_open_viewer()
	check(_container.showing_description(), "sanity: the map is left describing a pack node")
	await _start_a_new_run_from_the_wall()
	check(_hud_is_up(),
			"Close fix 2: a new run's map opens on the HUD, not the last run's pack description")
	await _end_main_fixture()

## A possible-cards list left up with a card stuck is the LAST run's: the new run's map opens on its HUD, with no list, no Deck row and no lock.
func test_a_new_run_closes_the_last_runs_possible_cards() -> void:
	var list := await _stick_a_possible_card()
	await _start_a_new_run_from_the_wall()
	check(not is_instance_valid(list) or list.is_queued_for_deletion(),
			"a new run closes the last run's possible-cards list", str(DeckViewer._open))
	check(_hud_is_up() and not _map.selection_buttons.visible and not _container.is_locked(),
			"...its map opening on the HUD with no Deck row and nothing locked",
			"shown=%s row=%s locked=%s" % [_described_title(), _map.selection_buttons.visible,
			_container.is_locked()])
	await _end_main_fixture()

## A pack chooser left up with a card stuck and the run deck over it is the LAST run's pack: the new run's map has no chooser, nothing locked, the sidebar on its HUD, and its keys pick a node to travel to.
func test_a_new_run_throws_away_the_last_runs_chooser() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		check(await _click_button(_map.selection_deck_button, _booted_viewport),
				"sanity: a click stuck a chosen card and a real click pressed its Deck")
		await get_tree().process_frame
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and _chooser_is_up(chooser), "sanity: the run deck is open over the chooser")
		await _start_a_new_run_from_the_wall()
		check(not _map.chooser_is_up() and (not is_instance_valid(chooser) or chooser.is_queued_for_deletion())
				and (not is_instance_valid(deck) or deck.is_queued_for_deletion()),
				"a new run throws away the last run's chooser and the deck over it")
		check(_hud_is_up() and not _map.selection_buttons.visible and not _container.is_locked(),
				"...its map opening on the HUD with no Deck row and nothing locked",
				"shown=%s row=%s locked=%s" % [_described_title(), _map.selection_buttons.visible,
				_container.is_locked()])
		await _tap_key(KEY_RIGHT)
		await _close_the_open_viewer()
		check(_map.controller.selected() != null and _map.travel_button.is_visible_in_tree(),
				"...where a key picks a node and its Travel is offered once a pack's list is closed",
				"picked=%s travel=%s focus=%s moving=%s" % [_map.controller.selected(),
				_map.travel_button.is_visible_in_tree(), _booted_viewport.gui_get_focus_owner(),
				_map.controller._moving])
	await _end_main_fixture()

# THE GATE SCANS godot.log FOR ERRORS ONLY, so the engine's warning that a control off screen was
# asked to take the focus would pass it; a logger hears the warning as the engine raises it.
class _FocusWarnings extends Logger:
	var count : int = 0

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if "can't grab focus" in code: count += 1

## From the map through the wall and the start menu into a new run, waited until that run's own map is ready and at rest.
func _start_a_new_run_from_the_wall() -> void:
	await _click_overlay(&"WallButton")
	await _wait_out_the_move()
	await _main._on_picture_enter_requested(&"start_menu")
	check(_main._current_focus == &"start_menu", "sanity: the start menu is entered from the wall",
			str(_main._current_focus))
	var landed : Array[bool] = [false]
	_map.controller.map_ready.connect(func() -> void: landed[0] = true, CONNECT_ONE_SHOT)
	var warnings := _FocusWarnings.new()
	OS.add_logger(warnings)
	await _main._on_new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	var waited := 0.0
	while not landed[0] and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	OS.remove_logger(warnings)
	check(warnings.count == 0,
			"a new run started from the menu hands no focus to a control off the screen shown",
			"%d \"can't grab focus\" warnings" % warnings.count)
# The new run populates a fresh graph, which may auto-pick its own single onward node -- the NEW
# run's description, never the old one's, and a no-op clear on every other boot.
	await _clear_any_auto_pick()
	check(landed[0] and _main._current_focus == &"map", "sanity: the new run lands on its own ready map",
			"ready=%s focus=%s" % [landed[0], _main._current_focus])

## B15/B16: leaving a screen is not a dismissal -- the lock comes back exactly as it was left, marking and all.
func test_leaving_while_locked_keeps_the_whole_lock_alive() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		var locked : CardData = _play_area.locked_data
		check(locked != null and _container.is_locked(), "the game screen is left locked")
		await _main._focus_picture(&"map")
		await _main._focus_picture(&"game")
		await get_tree().process_frame
		check(_container.is_locked(), "the lock is alive again on return (B15, B16)")
		check(_play_area.locked_data == locked,
				"...and the board wears that card's marking again (Q58=c)",
				str(_play_area.locked_data))
		check(locked != null and _play_area.data_card.has(locked)
				and _play_area.data_card[locked].focused,
				"...on whichever visual represents it now")
		check(_exit_button().focus_mode == Control.FOCUS_ALL,
				"...and the exit X is navigable again (Q68=b)", str(_exit_button().focus_mode))
	await _end_main_fixture()

## Zooming out to wall view with a board card still focused leaves the lock whole: the way back re-opens the locked card's own description.
func test_zooming_out_with_a_focused_card_keeps_the_lock() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var title : Label = _panel.get_node(^"%Title")
		var locked : CardData = _play_area.ui_data[entrance[0]]
		await _lock_without_holding(entrance[0])
		entrance[0].grab_focus()
		await get_tree().process_frame
		check(_game_viewport.gui_get_focus_owner() == entrance[0],
				"an Entrance card holds the board's focus while the description is locked",
				str(_game_viewport.gui_get_focus_owner()))
		await _main._go_to_wall_view()
		await get_tree().process_frame
		await _main._focus_picture(&"game")
		await _wait_out_the_move()
		await get_tree().process_frame
		check(title.text == _expected_text(locked)[0],
				"the way back from wall view re-opens the locked card's description", title.text)
		check(_container.is_locked() and _play_area.locked_data == locked,
				"...with the lock and the board's marking still on that card",
				str(_play_area.locked_data))
		check(_exit_button().focus_mode == Control.FOCUS_ALL,
				"...and the exit X is navigable again", str(_exit_button().focus_mode))
	await _end_main_fixture()

## Every event that ends a lock ends ALL of it: the exit X, a cancel and the show's own end each leave nothing locked and nothing half-remembered.
func test_every_end_of_a_lock_ends_all_of_it() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		check(await _click_button(_exit_button(), _booted_viewport),
				"a real click on the exit X pressed it")
		await get_tree().process_frame
		check(not _container.is_locked(),
				"the exit X ends the lock and leaves nothing behind")

		await _lock_without_holding(entrance[0])
		_booted_viewport.push_input(_cancel_event())
		await get_tree().process_frame
		await _wait_out_the_move()
		check(not _container.is_locked(),
				"a cancel ends the lock and leaves nothing behind")
		await _main._focus_picture(&"game")
		await _wait_out_the_move()

		var back := await _entrance_card_controls()
		check(not back.is_empty(), "the board offers a clickable Entrance card after the cancel",
				str(back.size()))
		if not back.is_empty():
			await _lock_without_holding(back[0])
			await _main._on_new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
			await _restart_the_show()
			check(not _container.is_locked(),
					"a new run ends the last show's lock and leaves nothing behind")
	await _end_main_fixture()

## A right-click cancel then the pointer leaving every card: the lost highlight must find the container in a state it can answer, whether the cancel took one step or both.
func test_a_cancelled_lock_survives_the_pointer_leaving_every_card() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var at := entrance[0].get_global_rect().get_center()
		await _click_card(entrance[0])
		check(_container.is_locked(), "the click-pickup locked the description")
		await _second_button_press(at)
		check(_container.showing_description(),
				"one cancel step let the held card go and left the description up")
		_play_area.open_zoomed_out()
		await get_tree().process_frame
		await _pointer_leaves_every_card(at)
		check(_container.showing_description(),
				"the pointer leaving every card after ONE cancel step returns to the locked card")

		await _second_button_press(at)
		check(not _container.showing_description(),
				"the second cancel step closed the description")
		check(not _container.is_locked(),
				"...and took the whole lock with it")
		_play_area.open_zoomed_out()
		await get_tree().process_frame
		await _pointer_leaves_every_card(at)
		check(_hud_is_up(),
				"the pointer leaving every card after BOTH cancel steps leaves the HUD up")
	await _end_main_fixture()

## A DRAG never locks -- only a click does -- so the release that drops the card, and the exit X after it, leave nothing for a lost highlight to return to.
func test_a_dropped_card_leaves_no_lock_behind() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a draggable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		var at := entrance[0].get_global_rect().get_center()
		await _drag_past_the_threshold(entrance[0])
		check(not _container.is_locked(),
				"a drag's own pickup describes the card without locking it")
		var bare := _bare_board_point(await _hoverable_card_controls())
		_hover(bare)
		await get_tree().process_frame
		await _release_at(bare)
		check(_play_area.selected_cards.is_empty(),
				"the release over bare board dropped the card",
				str(_play_area.selected_cards.size()))
		await _pointer_leaves_every_card(at)
		check(not _container.is_locked(),
				"the pointer leaving every card after the drop finds no lock at all")

		await _lock_without_holding(entrance[0])
		check(await _click_button(_exit_button(), _booted_viewport),
				"a real click on the exit X pressed it")
		await get_tree().process_frame
		await _pointer_leaves_every_card(at)
		check(not _container.is_locked(),
				"the pointer leaving every card after the exit X finds no lock at all")
	await _end_main_fixture()

# The board announces a lost highlight only when the pointer LEFT a card control and landed on no
# other, so the pointer is put back on the card before it is taken off the board.
func _pointer_leaves_every_card(on_a_card: Vector2) -> void:
	_hover(on_a_card)
	await get_tree().process_frame
	_hover(_off_the_board_point())
	await get_tree().process_frame
	await get_tree().process_frame

## At rest the map and its sea buffer fill the space beside the resting sidebar on the binding axis, centred, at any window shape; harness-scale only.
func test_the_map_at_rest_fits_the_space_beside_the_sidebar() -> void:
	for size : Vector2i in ([Vector2i(1280, 720), Vector2i(600, 1000)] as Array[Vector2i]):
		await _start_map_fixture(size)
		_check_map_fits_the_space(_main, "rest %s" % size)
		await _end_main_fixture()

## The fit is the floor of the zoom: wheeling out stops there, and wheeling out after a zoom in comes back to it exactly.
func test_zooming_out_stops_at_the_fit() -> void:
	await _start_map_fixture()
	var camera := _map.controller.camera
	var fit := camera.zoom.x
	await _wheel_the_map_out(5)
	check(is_equal_approx(camera.zoom.x, fit), "wheeling out at the fit zooms out no further",
			"%.4f vs fit %.4f" % [camera.zoom.x, fit])
	_check_map_fits_the_space(_main, "after wheeling out")
	await _zoom_the_map_in(_main, 2)
	await _wheel_the_map_out(4)
	check(is_equal_approx(camera.zoom.x, fit),
			"...and wheeling out after a zoom in comes back to the fit",
			"%.4f vs fit %.4f" % [camera.zoom.x, fit])
	_check_map_fits_the_space(_main, "back at the fit")
	await _end_main_fixture()

func _wheel_the_map_out(notches: int) -> void:
	for _i : int in range(notches):
		_push_wheel_notch(_booted_viewport, MOUSE_BUTTON_WHEEL_DOWN, _ui_space(_main).get_center())
	await _await_map_framing_settled(_main)

## At the fit the whole map is on screen, so there is nothing to pan: a drag moves nothing, and neither does the token walking; harness-scale only.
func test_at_the_fit_nothing_pans() -> void:
	await _start_map_fixture()
	var before := _framed_map_rect(_main)
	_pan_map_by(_map_space(_main).get_center(), MAP_PAN_DRAG)
	await _await_map_framing_settled(_main)
	check(_framed_map_rect(_main).is_equal_approx(before), "at the fit a drag moves the map nowhere",
			"%s vs %s" % [_framed_map_rect(_main), before])
	var frames : Array[Rect2] = []
	_map.controller.move_to(_map.controller._sorted_next()[0])
	while _map.controller._moving:
		frames.append(_framed_map_rect(_main))
		await get_tree().process_frame
	var still := frames.all(func(r: Rect2) -> bool: return r.is_equal_approx(before))
	check(not frames.is_empty() and still, "...and the camera stays put while the token walks",
			"%d frames" % frames.size())
	await _wait_out_the_move()
	await _end_main_fixture()

## Zoomed in, the camera pans, but never so far that anything past the map's sea buffer shows. A Travel is never zoomed in: it starts at the fit.
func test_zoomed_in_the_view_never_passes_the_maps_edge() -> void:
	await _start_map_fixture()
	var camera := _map.controller.camera
	var fit := camera.zoom.x
	await _zoom_the_map_in(_main, 10)
	check(camera.zoom.x > fit, "sanity: the wheel zoomed the map in",
			"%.3f vs %.3f" % [camera.zoom.x, fit])
	var start := camera.position
	_pan_map_by(_map_space(_main).get_center(), _drag_toward_the_map_centre(MAP_PAN_DRAG))
	await _await_map_framing_settled(_main)
	check(not camera.position.is_equal_approx(start), "zoomed in, a drag does pan the map",
			"%s vs %s" % [camera.position, start])
	for by : Vector2 in ([Vector2(4000.0, 0.0), Vector2(-4000.0, 0.0), Vector2(0.0, 4000.0),
			Vector2(0.0, -4000.0)] as Array[Vector2]):
		_pan_map_by(_map_space(_main).get_center(), by)
		await _await_map_framing_settled(_main)
		_check_the_view_stays_on_the_map(_main, "zoomed in, after a pan by %s" % by)
	await _end_main_fixture()

## The return to the fit is a SNAP: from a view zoomed in to the map's edge, no drawn frame of a Travel or a re-entry is blended between that view and the fit.
func test_no_frame_is_blended_across_a_return_to_the_fit() -> void:
	await _start_map_fixture()
	await _zoom_the_map_in_to_its_edge()
	_map.controller.move_to(_map.controller._sorted_next()[0])
	var past := await _frames_past_the_map(8, func() -> bool: return false)
	check(past.is_empty(), "no drawn frame passes the map's sea buffer as a Travel returns it to the fit",
			"; ".join(past))
	await _await_map_arrival()
	await _wait_out_the_move()
	await _end_main_fixture()
	await _start_map_fixture()
	await _zoom_the_map_in_to_its_edge()
	await _main._go_to_wall_view()
	var entered : Array[bool] = [false]
	var enter := func() -> void:
		await _main._focus_picture(&"map")
		entered[0] = true
	enter.call()
	past = await _frames_past_the_map(600, func() -> bool: return entered[0])
	check(past.is_empty(), "no drawn frame passes the map's sea buffer as re-entering returns it to the fit",
			"; ".join(past))
	await _end_main_fixture()

func _zoom_the_map_in_to_its_edge() -> void:
	await _zoom_the_map_in(_main, 10)
	_pan_map_by(_map_space(_main).get_center(), Vector2(4000.0, 4000.0))
	await _await_map_framing_settled(_main)

## Each Travel puts the map back at the fit the moment it starts: the whole map is in view for the walk.
func test_a_travel_returns_the_map_to_the_fit() -> void:
	await _start_map_fixture()
	var camera := _map.controller.camera
	var fit := camera.zoom.x
	await _zoom_the_map_in(_main, 5)
	check(camera.zoom.x > fit, "sanity: the wheel zoomed the map in",
			"%.3f vs %.3f" % [camera.zoom.x, fit])
	_map.controller.move_to(_map.controller._sorted_next()[0])
	check(is_equal_approx(camera.zoom.x, fit), "a Travel puts the map back at the fit",
			"%.4f vs fit %.4f" % [camera.zoom.x, fit])
	await _await_map_arrival()
	await _wait_out_the_move()
	await _end_main_fixture()

## Leaving the map picture and coming back finds the map at the fit again.
func test_leaving_and_reentering_the_map_returns_it_to_the_fit() -> void:
	await _start_map_fixture()
	var camera := _map.controller.camera
	var fit := camera.zoom.x
	await _zoom_the_map_in(_main, 5)
	check(camera.zoom.x > fit, "sanity: the wheel zoomed the map in",
			"%.3f vs %.3f" % [camera.zoom.x, fit])
	await _main._go_to_wall_view()
	await _main._focus_picture(&"map")
	await _await_map_framing_settled(_main)
	check(is_equal_approx(camera.zoom.x, fit), "re-entering the map picture finds it at the fit",
			"%.4f vs fit %.4f" % [camera.zoom.x, fit])
	_check_map_fits_the_space(_main, "after re-entering the map")
	await _end_main_fixture()

## Within one visit and with no Travel, a zoom in stays through a pan and a pick.
func test_a_zoom_stays_through_a_visit_without_a_travel() -> void:
	await _start_map_fixture()
	var camera := _map.controller.camera
	await _zoom_the_map_in(_main, 5)
	var zoomed := camera.zoom.x
	_pan_map_by(_map_space(_main).get_center(), _drag_toward_the_map_centre(MAP_PAN_DRAG))
	await _await_map_framing_settled(_main)
	_map.controller.select_node(_map.controller._sorted_next()[0])
	await get_tree().process_frame
	_map.controller.clear_selection()
	await _await_map_framing_settled(_main)
	check(is_equal_approx(camera.zoom.x, zoomed), "a pan and a pick leave the player's zoom alone",
			"%.4f vs %.4f" % [camera.zoom.x, zoomed])
	await _end_main_fixture()

## The map picture's background is the map's own sea, so the letterbox and the buffer read as open water, and in the window's own pixels the buffer is whole on screen on all four sides at both window shapes.
func test_the_maps_background_is_its_sea() -> void:
	await _start_map_fixture()
	await RenderingServer.frame_post_draw
	var image := _map_viewport.get_texture().get_image()
	var sea := WorldHeightColorizer.new().ocean_color
	var framed := _framed_map_rect(_main)
	var buffer := framed.size.x * SettingsManager.settings.map_edge_buffer_fraction
	var in_the_buffer := Vector2(framed.get_center().x, framed.position.y + buffer / 2.0)
	for at : Vector2 in ([Vector2(2.0, 2.0), in_the_buffer] as Array[Vector2]):
		var seen := image.get_pixelv(Vector2i(at))
		check(Vector3(seen.r - sea.r, seen.g - sea.g, seen.b - sea.b).length() < 0.02,
				"the map picture shows the sea at %s" % at, "%s vs %s" % [seen, sea])
	await _end_main_fixture()
	for size : Vector2i in INSET_WINDOWS:
		var where := "the harness window %s" % size
		await _start_map_fixture(size)
		_booted_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await await_drawn_frames(2)
		var window := _booted_viewport.get_texture().get_image()
		for corner : Vector2 in _check_the_sea_buffer_beside_the_sidebar(_booted_viewport, where):
			var seen := window.get_pixelv(Vector2i(corner))
			check(_colour_distance(seen, sea) < OPAQUE_COLOUR_TOLERANCE,
					"...and the window shows the sea there in %s" % where, "%s at %s vs %s" % [seen, corner, sea])
		await _end_main_fixture()

# Measured, not sampled: an embedded Window's own texture holds its canvas at scale 1, cut to the
# window's pixel size, so the stretched pixels the player sees cannot be read back here.
## The map's sea buffer is whole on screen on all four sides beside the sidebar, at the player's content scale at both window shapes.
func test_the_maps_sea_buffer_is_whole_on_screen_in_the_players_window() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var where := "the player's window %s" % size
		await _start_map_fixture(size, true)
		var window := _main.get_viewport() as Window
		_check_the_players_scale(window, where)
		_check_the_sea_buffer_beside_the_sidebar(window, where)
		await _end_main_fixture()

## How far inside the framed map's edge its outermost buffer pixel is taken, in canvas px: past a whole-pixel rounding, well inside the buffer.
const SEA_EDGE_INSET_PX := 1.5

# At the CORNERS, each on two edges: a map node may sit over the buffer at an edge's middle (the
# buffer exists for exactly that), and a corner is the point furthest from every node.
## The framed map's outermost buffer pixel at each corner, in `viewport`'s canvas px, lies in the space beside the resting sidebar; returns the corners that do.
func _check_the_sea_buffer_beside_the_sidebar(viewport: Viewport, where: String) -> Array[Vector2]:
	check(is_equal_approx(_container.slid_fraction(), 1.0),
			"sanity: the sidebar rests beside the map in %s" % where)
	var framed := viewport.get_final_transform().affine_inverse() * _picture_rect_in_window(viewport,
			_main._pictures[&"map"], _framed_map_rect(_main))
	var space := _ui_space(_main)
	var inside := framed.grow(-SEA_EDGE_INSET_PX)
	var corners : Dictionary[String, Vector2] = {"top left": inside.position,
			"top right": Vector2(inside.end.x, inside.position.y),
			"bottom left": Vector2(inside.position.x, inside.end.y), "bottom right": inside.end}
	var on_screen : Array[Vector2] = []
	for corner : String in corners:
		check(space.has_point(corners[corner]),
				"the map's %s sea buffer is on screen beside the sidebar in %s" % [corner, where],
				"%s at %s, the framed map %s in %s" % [corner, corners[corner], framed, space])
		if space.has_point(corners[corner]): on_screen.append(corners[corner])
	return on_screen

## A show tears down ITS OWN wiring and nobody else's: the map it hands back to keeps its Deck button and its inset.
func test_a_finished_show_leaves_the_maps_own_wiring_alive() -> void:
	await _start_game_fixture()
	var view := _main._pictures[&"game"].screen_root as GameView
	await _end_the_show_by_its_button(view)
	await _continue_to_the_map(view)
	var map : Map = _main.map_scene
	var camera : Camera2D = map.controller.camera
	var before := camera.offset
	await _resize_viewport(_booted_viewport, Vector2i(600, 1000))
	var after_the_resize := camera.offset
	map._publish_map_inset()
	check(camera.offset != before, "sanity: this resize moves the map's own inset",
			"%s vs %s" % [camera.offset, before])
	check(after_the_resize == camera.offset,
			"the resize re-inset the map by itself: the finished show dropped only its own pairs",
			"%s vs %s" % [after_the_resize, camera.offset])
	check(not is_instance_valid(DeckViewer._open), "sanity: no viewer is open yet")
	check(await _click_button(_container.map_deck_button, _booted_viewport),
			"a real click on the map's Deck button pressed it")
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open),
			"...and the map's own Deck button still opens its viewer after a show")
	await _end_main_fixture()

## Leaving a screen mid-cascade frees the description it was left on, a cascade's hold sticking nothing.
func test_a_remembered_entry_dropped_by_a_cascade_is_freed() -> void:
	var container := _build_container()
	container.set_active_screen(&"game")
	var read := InfoEntry.new()
	read.visual = Control.new()
	container.show_description(read)
	container.set_processing(true)
	container.set_active_screen(&"")
	await get_tree().process_frame
	check(not is_instance_valid(read.visual), "leaving after a cascade frees the remembered entry")
	container.set_active_screen(&"game")
	check(not container.showing_description(), "...and the return finds the HUD")
	container.queue_free()

# Split so this suite never itself contains the retired name, which the deletion gate greps for.
const RETIRED_MODE_TOKEN := "wall_" + "info"

## L1-L4: Info mode is deleted, so no script may still name it.
func test_no_script_names_the_retired_mode() -> void:
	var offenders : Array[String] = []
	for path : String in gd_scripts_under("res://"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains(RETIRED_MODE_TOKEN): offenders.append(path)
	check(offenders.is_empty(), "no script outside addons/ names the retired Info mode (8.1)",
			"
".join(offenders))

## L1: the toggle's input action went with the mode.
func test_the_retired_action_is_unbound() -> void:
	check(not InputMap.has_action(StringName(RETIRED_MODE_TOKEN)),
			"the retired mode's input action is gone from the InputMap (8.1)")

# Split so this suite never itself contains the retired names, which the deletion gate greps for.
const RETIRED_POPUP_TOKENS : Array[String] = ["_focus" + "_info", "wall_screen" + "_popups"]

## The in-board popup and the setting that gated it are deleted, so no script may still name either.
func test_no_script_names_the_retired_in_board_popup() -> void:
	var offenders : Array[String] = []
	for path : String in gd_scripts_under("res://"):
		var text := FileAccess.get_file_as_string(path)
		for token : String in RETIRED_POPUP_TOKENS:
			if text.contains(token): offenders.append("%s names %s" % [path, token])
	check(offenders.is_empty(), "no script outside addons/ names the in-board popup (8.2)",
			"\n".join(offenders))

# ------------------------------------------------------------------ the viewers publish too

# Opens a viewer the way a PAD player does: the pile button takes the focus, then accept presses it
# -- press AND release, because a Button fires on the release -- pushed into the viewport the
# overlay's buttons live in.
func _open_viewer_by_accept(button: Button) -> void:
	button.grab_focus()
	await get_tree().process_frame
	_push_key(_booted_viewport, KEY_ENTER, true)
	_push_key(_booted_viewport, KEY_ENTER, false)
	await get_tree().process_frame
	await get_tree().process_frame

## The pad's open is NOT a highlight -- the sidebar stays on the HUD, its arrows walk it, and the arrow off its inner edge is what enters the list and shows its first card.
func test_the_first_arrow_enters_a_viewer_and_shows_its_first_card() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await _open_viewer_by_accept(deck)
	check(is_instance_valid(DeckViewer._open), "accept on the Deck button opened the viewer")
	if is_instance_valid(DeckViewer._open):
		var first := DeckViewer._open.flow_container.get_child(0) as ControlCard
		check(first != null and not first.has_focus(),
				"the opened viewer focuses nothing, so no card holds the sidebar (S12.8)")
		check(_hud_is_up() and deck.is_visible_in_tree(),
				"...the HUD is what shows, with its Deck button still there to press (S12.8)")
		var walked := await _walk_right_off_the_sidebar(_push_arrow.bind(_booted_viewport, KEY_RIGHT))
		check(walked and first != null and first.has_focus(),
				"the arrow off the sidebar's inner edge lands on the viewer's first card (S12.8, B1)",
				str(_booted_viewport.gui_get_focus_owner()))
		check(_container.showing_description(),
				"...and THAT highlight is what opens the description (S12.8, B1)")
		if first != null:
			check(title.text == _expected_text(first.child.data)[0],
					"...reading the first card's own name", title.text)
	await _end_main_fixture()

## Keyboard/controller: closing a viewer hands the focus to something the player can SEE -- with nothing stuck that is the HUD, so the button that opened it takes the focus straight back.
func test_closing_a_viewer_leaves_the_focus_somewhere_visible() -> void:
	await _start_game_fixture()
	var button := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await _open_viewer_by_accept(button)
	check(is_instance_valid(DeckViewer._open), "accept on the Deck button opened the viewer")
	await _close_open_viewer(_booted_viewport)
	check(not is_instance_valid(DeckViewer._open), "cancel closed the viewer")
	check(_hud_is_up(), "closing with nothing stuck takes the sidebar back to the HUD (S12.9)")
	var landed := _booted_viewport.gui_get_focus_owner()
	check(landed != null and landed.is_visible_in_tree(),
			"...and the focus lands on a control the player can see (S12.9)", str(landed))
	check(landed == button,
			"...the button that opened it, which the HUD coming back put on screen again (S12.9)",
			str(landed))
	await _end_main_fixture()

## A pile button pressed over an open viewer: the new viewer highlights nothing, so the sidebar falls back to the board's own lock until the player points at something.
func test_swapping_viewers_falls_back_to_what_the_viewer_covered() -> void:
	await _start_game_fixture()
	var state := (_main._pictures[&"game"].screen_root as GameView).game.state
	var stocked := state.all_stock_cards()
	check(stocked.size() >= 2, "sanity: the slot stocks can seed a discard pile",
			str(stocked.size()))
	state.discard_deck.append(stocked[0])
	state.discard_deck.append(stocked[1])
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a lockable card", str(entrance.size()))
	if not entrance.is_empty():
		var title : Label = _panel.get_node(^"%Title")
		await _click_card(entrance[0])
		check(_container.is_locked(), "sanity: the board click locked the sidebar")
		var locked_title := title.text
		var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		var incoming := _expected_text(state.discard_deck[0])[0]
		var read_here := _viewer_card_named_other_than(cards, incoming)
		check(read_here != null, "the deck lists a card the discard pile's first does not name",
				"%d listed" % cards.size())
		if read_here != null:
			read_here.grab_focus()
			await get_tree().process_frame
			var read_title := _expected_text(read_here.child.data)[0]
			check(title.text == read_title,
					"sanity: the deck viewer owns the sidebar before the swap", title.text)
			check(_container._shown_hosted_viewer().suspended_lock != null,
					"the board's own lock waits under the open viewer rather than showing")
			var discard_button := _container.discard_ui.get_node(^"Button") as Button
			check(not discard_button.is_visible_in_tree(),
					"a published description hides the pile buttons, so only the press itself swaps (S12.10)")
			discard_button.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
			check(title.text == locked_title
					and _container._shown_hosted_viewer().suspended_lock != null,
					"the swap falls back to the board's own card, waiting under the new viewer, which highlights nothing until the player does (S12.10, B7)",
					"%s vs %s" % [title.text, locked_title])
			check(_container._shown_hosted_viewer().suspended_lock != null,
					"...with the board's own lock still waiting under both of them")
	await _end_main_fixture()

# The button's own press, not the pad's accept: these tests open a viewer from states where the
# container is showing a description, which hides the pile buttons and so drops a pad's key focus.
# `DeckViewer._open` is the viewer's own record of which one is up.
func _open_viewer_cards(button: Button) -> Array[ControlCard]:
	button.grab_focus()
	await get_tree().process_frame
	button.pressed.emit()
	await get_tree().process_frame
	return _listed_viewer_cards()

# The cards the one open viewer lists, in the order it lists them.
func _listed_viewer_cards() -> Array[ControlCard]:
	var out : Array[ControlCard] = []
	for child : Node in DeckViewer._open.flow_container.get_children():
		var card := child as ControlCard
		if card: out.append(card)
	return out

# A viewer's own highlight has to reach the sidebar. The container is put back on the HUD FIRST, so
# the swap is a real transition rather than a description some earlier test left up.
func _check_viewer_publishes(button: Button, pile: String) -> void:
	var cards := await _open_viewer_cards(button)
	check(cards.size() >= 2, "the %s viewer lists cards to point at" % pile, str(cards.size()))
	if cards.size() < 2: return
	var title : Label = _panel.get_node(^"%Title")
	_container.show_hud()
	cards[1].grab_focus()
	await get_tree().process_frame
	check(_container.showing_description(),
			"a highlight in the %s viewer opens the description (S12, Q140=a)" % pile)
	check(title.text == _expected_text(cards[1].child.data)[0],
			"...and the title reads that viewer card's own name", title.text)

## The deck viewer publishes the card under the highlight into the wall's one sidebar.
func test_the_deck_viewer_publishes_into_the_sidebar() -> void:
	await _start_game_fixture()
	await _check_viewer_publishes(_container.deck_ui.get_node(^"Button") as Button, "deck")
	await _end_main_fixture()

## The rules and discard viewers publish through their own buttons, by the same rule.
func test_the_rules_and_discard_viewers_publish_into_the_sidebar() -> void:
	await _start_game_fixture()
	await _check_viewer_publishes(_container.rules_ui.get_node(^"Button") as Button, "rules")
	var view := _main._pictures[&"game"].screen_root as GameView
	var state := view.game.state
	var stocked := state.all_stock_cards()
	check(stocked.size() >= 2, "sanity: the slot stocks can seed a discard pile",
			str(stocked.size()))
	state.discard_deck.append(stocked[0])
	state.discard_deck.append(stocked[1])
	await _check_viewer_publishes(_container.discard_ui.get_node(^"Button") as Button, "discard")
	await _end_main_fixture()

## Every card the Rules viewer lists draws a card face, the grid creator's typeless card the blank one.
func test_every_rules_viewer_card_draws_a_card_face() -> void:
	await _start_game_fixture()
	var cards := await _open_viewer_cards(_container.rules_ui.get_node(^"Button") as Button)
	var bodiless := 0
	var typeless_frames : Array[Vector2] = []
	for card : ControlCard in cards:
		if not card.child.type.visible: bodiless += 1
		if card.child.data.type == null: typeless_frames.append(_type_frame_origin(card.child))
	check(not typeless_frames.is_empty(),
			"sanity: the rules row lists the grid creator's typeless card", "%d listed" % cards.size())
	check(bodiless == 0, "every rules viewer card draws its face, none a bare mark",
			"%d of %d bodiless" % [bodiless, cards.size()])
	var blank := _sheet_frame_origin(CardVisual.BLANK_CARD_FRAME)
	check(typeless_frames.all(func(origin: Vector2) -> bool: return origin == blank),
			"...and a card with no type draws the blank card frame",
			"%s vs %s" % [typeless_frames, blank])
	await _end_main_fixture()

# The space a viewer's cards belong in, in the PICTURE's own space: what `local_rect_beside()`
# leaves once the container is reserved, at whatever window is up -- the side case's left inset and
# the top case's band both, so a test states the claim once and the window decides which it is.
func _space_beside_the_container(picture: WallPicture, container: HudContainer) -> Rect2:
	var window : Vector2 = container.get_viewport().get_visible_rect().size
	return picture.local_rect_beside(window, container.container_rect(),
			HudContainer.container_is_top(window, SettingsManager.settings))

# ⚠ A LIST THAT SCROLLS IS CLIPPED BY ITS OWN VIEWPORT, so a deck viewer row below the fold is held
# to the horizontal span and the band's edge and never to the bottom one.
func _unbounded_below(beside: Rect2) -> Rect2:
	return Rect2(beside.position, Vector2(beside.size.x, INF))

# The claim made about the CARDS rather than about the offsets a viewer just wrote to itself: every
# listed card is drawn inside the space left beside the container.
func _check_every_card_inside(cards: Array[ControlCard], bounds: Rect2, label: String) -> void:
	var outside : Array[Rect2] = []
	for card : ControlCard in cards:
		if not bounds.encloses(card.get_global_rect()):
			outside.append(card.get_global_rect())
	check(cards.size() >= 2 and outside.is_empty(), label,
			"%d of %d cards outside %s, e.g. %s"
			% [outside.size(), cards.size(), bounds, outside[0] if outside else Rect2()])

## The viewer sits INSIDE the sidebar's screen: its cards start beside the container, never under it; harness-scale only.
func test_the_deck_viewers_cards_start_beside_the_container() -> void:
	await _start_game_fixture()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	var window : Vector2 = _container.get_viewport().get_visible_rect().size
	var top := HudContainer.container_is_top(window, SettingsManager.settings)
	check(not top, "sanity: 1280x720 is the side case this inset is measured in")
	var remaining := _container.resting_rect_beside(null)
	var grid : Control = DeckViewer._open.flow_container
	check(grid.get_global_rect().position.x >= remaining.position.x,
			"the viewer's card grid starts at or beyond the container's inner edge (S12.4, Q141=b)",
			"%.1f vs %.1f" % [grid.get_global_rect().position.x, remaining.position.x])
	_check_every_card_inside(cards, _unbounded_below(remaining),
			"...and every listed card lies beside the container and inside the visible picture (S12.4)")
	await _end_main_fixture()

# A REAL window change: the private `SubViewport` is resized and the tree given the frames the
# container needs to re-apply its rect and everything that rides on it to follow.
func _resize_viewport(viewport: SubViewport, size: Vector2i) -> void:
	viewport.size = size
	await get_tree().process_frame
	await get_tree().process_frame

## An open viewer follows the container the board does: the window moving under it re-fits it, and re-fitting twice lands it in the same place rather than insetting it twice; harness-scale only.
func test_a_resize_re_fits_the_open_viewer() -> void:
	await _start_game_fixture()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(cards.size() >= 2, "the deck viewer lists cards to point at", str(cards.size()))
	await _resize_viewport(_booted_viewport, Vector2i(600, 1000))
	_check_every_card_inside(cards,
			_unbounded_below(_container.resting_rect_beside(null)),
			"a resize re-fits the open viewer into the space left below the new band (S12.13)")
	await _resize_viewport(_booted_viewport, Vector2i(1280, 720))
	_check_every_card_inside(cards,
			_unbounded_below(_container.resting_rect_beside(null)),
			"...and resizing back fits it from its authored margins, never inset twice (S12.13)")
	await _end_main_fixture()

## A dismissal is the player's own act: the container moving under an open viewer re-fits it without re-opening what the exit X put away.
func test_a_resize_does_not_re_open_a_dismissed_description() -> void:
	await _start_game_fixture()
	var listed := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(listed.size() >= 2, "the deck viewer lists cards to point at", str(listed.size()))
	if listed.size() >= 2:
		listed[1].grab_focus()
		await get_tree().process_frame
		check(_container.showing_description(),
				"sanity: the viewer's own highlight opened the description")
		await _click(listed[1].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked() and _exit_button().visible,
				"sanity: a click sticks the card, which is what puts the exit X there")
		await _click(_exit_button().get_global_rect().get_center(), _booted_viewport)
		check(_hud_is_up(), "sanity: the exit X put that description away (B9)")
		await _resize_viewport(_booted_viewport, Vector2i(600, 1000))
		check(_hud_is_up(),
				"a resize after the exit X leaves the dismissal standing (B9-B11)")
	await _end_main_fixture()

## A rect change re-draws an open viewer's entry, and it comes back at the one preview size the deck viewer already draws at; harness-scale only.
func test_a_resize_keeps_a_viewers_preview_at_the_viewers_own_card_size() -> void:
	await _start_game_fixture()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(cards.size() >= 2, "the deck viewer lists cards to point at", str(cards.size()))
	if cards.size() >= 2:
		cards[1].grab_focus()
		await get_tree().process_frame
		check(_container.showing_description(), "sanity: the viewer's highlight is what shows")
		await _resize_viewport(_booted_viewport, Vector2i(1920, 1080))
		var preview := _preview_card(_panel.current_entry.visual)
		check(preview != null and preview.child != null,
				"the description still holds its preview after the resize")
		if preview != null and preview.child != null:
			var viewer_px := _card_drawn_width(cards[1].child)
			var board_px := _play_area.board_card_window_px().x
			check(absf(viewer_px - board_px) > PREVIEW_WIDTH_TOLERANCE_PX,
					"sanity: the viewer's card width and the board's are far enough apart to tell apart",
					"viewer %.1f vs board %.1f" % [viewer_px, board_px])
			check(absf(_card_drawn_width(preview.child) - viewer_px) <= PREVIEW_WIDTH_TOLERANCE_PX,
					"the resize re-draws the entry at the one preview size (S12.14, R9)",
					"preview %.1f vs viewer %.1f, board %.1f"
					% [_card_drawn_width(preview.child), viewer_px, board_px])
	await _end_main_fixture()

## The same claim at a TOP window: the listed cards clear the band and stay inside the visible picture; harness-scale only.
func test_the_deck_viewers_cards_lie_below_the_band_at_a_top_window() -> void:
	await _start_game_fixture(Vector2i(600, 1000))
	var window : Vector2 = _container.get_viewport().get_visible_rect().size
	check(HudContainer.container_is_top(window, SettingsManager.settings),
			"sanity: 600x1000 puts the container on the top band")
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	_check_every_card_inside(cards,
			_unbounded_below(_container.resting_rect_beside(null)),
			"every deck viewer card is drawn below the band and inside the visible picture (S12.12)")
	await _end_main_fixture()

# A card name is often just a rank, so "the description followed the hover" is only a real claim
# about a viewer card whose name the locked one does not already share -- and about one the
# highlight can genuinely MOVE onto, since the viewer's own opening focus already sits on its first.
func _viewer_card_named_other_than(cards: Array[ControlCard], title: String) -> ControlCard:
	for card : ControlCard in cards:
		if card.has_focus(): continue
		if _expected_text(card.child.data)[0] != title: return card
	return null

# Escape, pushed into the picture the viewer lives in -- the viewer's own `_unhandled_input` close,
# never a test-only call.
func _close_open_viewer(viewport: Viewport) -> void:
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	viewport.push_input(cancel)
	await get_tree().process_frame
	await get_tree().process_frame

## A lock made on the board outlives a viewer: the hover follows inside it, and closing it comes back.
func test_a_board_lock_survives_opening_and_closing_a_viewer() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a lockable card", str(entrance.size()))
	if not entrance.is_empty():
		var clicked := _watch_clicks()
		await _click_card(entrance[0])
		check(clicked.size() == 1 and _container.is_locked(),
				"sanity: the board click locked the sidebar", str(clicked.size()))
		var title : Label = _panel.get_node(^"%Title")
		var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		var locked_title := _expected_text(clicked[0])[0] if clicked.size() == 1 else ""
		var other := _viewer_card_named_other_than(cards, locked_title)
		check(other != null, "the deck lists a card whose own name differs from the locked card's",
				"%d listed" % cards.size())
		if clicked.size() == 1 and other != null:
			other.grab_focus()
			await get_tree().process_frame
			check(title.text == _expected_text(other.child.data)[0]
					and title.text != locked_title,
					"the description follows the hover inside the viewer (B7)", title.text)
			await _close_open_viewer(_booted_viewport)
			check(not is_instance_valid(DeckViewer._open), "escape closed the viewer")
			check(_container.is_locked() and title.text == locked_title,
					"...and the sidebar comes back to the card the board locked (B7)", title.text)
	await _end_main_fixture()

# ------------------------------------------------------------------ a viewer is modal

# An arrow pushed into the viewport the viewer lives in, which is where a key player's presses land.
func _push_arrow(viewport: SubViewport, keycode: Key) -> void:
	_push_key(viewport, keycode, true)
	_push_key(viewport, keycode, false)
	await get_tree().process_frame
	await get_tree().process_frame

## The map's dots answer arrows of their own, and an open viewer must not let one through: the pick cannot move behind a viewer the player is still reading.
func test_an_arrow_in_an_open_viewer_never_moves_the_maps_pick() -> void:
	await _start_map_fixture()
	check(await _click_button(_container.map_deck_button, _booted_viewport),
			"a real click on the map's Deck button opened its viewer")
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open), "sanity: the map's deck viewer is open")
	var before : WorldGraphNode = _map.controller.selected()
	for keycode : Key in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		await _push_arrow(_booted_viewport, keycode)
	check(_map.controller.selected() == before,
			"four arrows inside the open viewer leave the map's pick exactly where it was",
			"%s vs %s" % [_map.controller.selected(), before])
	check(is_instance_valid(DeckViewer._open), "...and the viewer is still the thing on screen")
	var owner : Control = _booted_viewport.gui_get_focus_owner()
	check(owner != null and is_instance_valid(DeckViewer._open)
			and DeckViewer._open.is_ancestor_of(owner),
			"...with the focus still inside the viewer, in the window's own viewport",
			str(owner))
	await _close_the_open_viewer()
	await _end_main_fixture()

## A pointer press over the viewer never reaches the board under it: it closes the viewer instead.
func test_a_click_beneath_an_open_viewer_never_reaches_the_board() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		_container.show_hud()
		await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		check(is_instance_valid(DeckViewer._open), "sanity: the deck viewer is open over the board")
		var clicked := _watch_clicks()
		var at := _a_board_point_on_the_viewer_backdrop(entrance)
		check(at != Vector2.INF, "sanity: an Entrance card lies behind the viewer's backdrop, clear of its cards")
		if at != Vector2.INF: await _click(at, _booted_viewport)
		check(clicked.is_empty(),
				"a click aimed at a board card under the viewer never reaches the board",
				"%d board selections" % clicked.size())
		check(not is_instance_valid(DeckViewer._open)
				or DeckViewer._open.is_queued_for_deletion(),
				"...it closes the viewer instead")
		check(_play_area.selected_cards.is_empty(),
				"...and nothing was picked up", str(_play_area.selected_cards.size()))
	await _end_main_fixture()

## The same rule on the map: a press on bare map closes the viewer and moves no pick.
func test_a_click_outside_a_viewer_on_the_map_closes_it_and_travels_nowhere() -> void:
	await _start_map_fixture()
	check(await _click_button(_container.map_deck_button, _booted_viewport),
			"a real click on the map's Deck button opened its viewer")
	await get_tree().process_frame
	var before : WorldGraphNode = _map.controller.selected()
	await _click_outside_the_map_viewer()
	check(not is_instance_valid(DeckViewer._open)
			or DeckViewer._open.is_queued_for_deletion(),
			"a click outside the viewer closes it")
	check(_map.controller.selected() == before,
			"...and the map's pick did not move behind it",
			"%s vs %s" % [_map.controller.selected(), before])
	await _end_main_fixture()

## Closing takes the viewer's card out of the sidebar: nothing is left describing a card no longer on screen.
func test_closing_a_viewer_takes_its_card_out_of_the_sidebar() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(cards.size() >= 2, "the deck viewer lists cards to point at", str(cards.size()))
	if cards.size() >= 2:
		cards[1].grab_focus()
		await get_tree().process_frame
		check(_container.showing_description(),
				"sanity: a highlight in the viewer describes its card")
		await _close_open_viewer(_booted_viewport)
		check(_hud_is_up(),
				"closing the viewer leaves the HUD, not the description of a card that is gone")
		check(not _container.is_locked(), "...and nothing is left locked to it")
	await _end_main_fixture()

## No X while nothing is stuck -- the X promises the description stays, and a bare highlight will not.
func test_the_exit_x_shows_only_once_a_viewer_card_is_clicked() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(cards.size() >= 2, "the deck viewer lists cards to point at", str(cards.size()))
	if cards.size() >= 2:
		cards[1].grab_focus()
		await get_tree().process_frame
		check(_container.showing_description() and not _exit_button().visible,
				"a viewer highlight describes its card with no exit X",
				str(_exit_button().visible))
		await _click(cards[1].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "a click on that card sticks the sidebar to it")
		check(_exit_button().visible and _exit_button().focus_mode == Control.FOCUS_ALL,
				"...and only then is the exit X there to be clicked",
				str(_exit_button().visible))
		var preview : Node = _panel.current_entry.visual
		check(is_instance_valid(preview) and preview.get_parent() != null,
				"...with the card's own preview still drawn: sticking what is shown never frees it",
				str(preview))
	await _end_main_fixture()

## The board's own lock waits under the viewer's stuck card and is handed straight back on close.
func test_a_board_lock_waits_under_a_stuck_viewer_card_and_comes_back() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a lockable card", str(entrance.size()))
	if not entrance.is_empty():
		var clicked := _watch_clicks()
		await _click_card(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		var locked_title := _expected_text(clicked[0])[0] if clicked.size() == 1 else ""
		check(clicked.size() == 1 and _container.is_locked(),
				"sanity: the board click locked the sidebar", str(clicked.size()))
		var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		check(not _container.is_locked(),
				"the open viewer takes the lock over, so the board's own waits under it")
		var other := _viewer_card_named_other_than(cards, locked_title)
		if other != null:
			await _click(other.get_global_rect().get_center(), _booted_viewport)
			check(_container.is_locked() and title.text == _expected_text(other.child.data)[0],
					"a click in the viewer sticks the sidebar to ITS card", title.text)
			await _close_open_viewer(_booted_viewport)
			check(_container.is_locked() and title.text == locked_title,
					"closing hands the board's own lock straight back", title.text)
	await _end_main_fixture()

## P35: every arrow walks the open viewer's own grid -- across FlowContainer rows too -- and the rim follows the focus, whether or not a card is stuck to the sidebar.
func test_every_arrow_walks_the_viewers_grid_and_the_rim_follows() -> void:
	await _start_game_fixture()
	_container.show_hud()
	await _open_viewer_by_accept(_container.deck_ui.get_node(^"Button") as Button)
	var cards := _listed_viewer_cards()
	var from := _card_with_a_neighbour_every_way(cards)
	check(from != null, "the deck viewer lays out a card with a neighbour in every direction",
			str(cards.size()))
	if from != null:
		for stuck : bool in [false, true]:
			from.grab_focus()
			await get_tree().process_frame
			if stuck:
				await _click(from.get_global_rect().get_center(), _booted_viewport)
				check(_container.is_locked(), "sanity: the click stuck that card to the sidebar")
			for keycode : Key in [KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP]:
				from.grab_focus()
				await get_tree().process_frame
				await _walks_one_neighbour(cards, from, keycode, stuck)
	await _end_main_fixture()

## The first listed card the FlowContainer placed with another card left, right, above and below it.
func _card_with_a_neighbour_every_way(cards: Array[ControlCard]) -> ControlCard:
	for card : ControlCard in cards:
		var at := card.global_position
		var sides := {}
		for other : ControlCard in cards:
			var there := other.global_position
			if there.y == at.y and there.x != at.x: sides[signf(there.x - at.x) * Vector2.RIGHT] = true
			if there.x == at.x and there.y != at.y: sides[signf(there.y - at.y) * Vector2.DOWN] = true
		if sides.size() == 4: return card
	return null

# One arrow from `from`, read back the way a player sees it: which control the window's own
# viewport now focuses, and the rim each card is actually drawn with.
func _walks_one_neighbour(cards: Array[ControlCard], from: ControlCard, keycode: Key,
		stuck: bool) -> void:
	var tag := "%s with a card stuck" % keycode if stuck else "%s with nothing stuck" % keycode
	check(_rim_of(from) == PaletteDB.ROLES.match_rim,
			"sanity: the card the walk starts from wears the focus rim (%s)" % tag,
			str(_rim_of(from)))
	await _push_arrow(_booted_viewport, keycode)
	var landed := _booted_viewport.gui_get_focus_owner() as ControlCard
	check(landed != null and landed != from and cards.has(landed),
			"%s moves the focus to a neighbouring card in the viewer's own grid" % tag,
			str(_booted_viewport.gui_get_focus_owner()))
	check(_game_viewport.gui_get_focus_owner() == null,
			"...with the focus in the window's own viewport, none left on the board behind (%s)" % tag,
			str(_game_viewport.gui_get_focus_owner()))
	check(not from.child.focused and _rim_of(from) != PaletteDB.ROLES.match_rim,
			"...the card it left goes dark (%s)" % tag, str(_rim_of(from)))
	if landed != null:
		check(landed.child.focused and _rim_of(landed) == PaletteDB.ROLES.match_rim,
				"...and the rim follows onto the card it landed on (%s)" % tag,
				str(_rim_of(landed)))

## The palette index a listed card's rim is ACTUALLY drawn in, read off the polygon's own material.
func _rim_of(control: ControlCard) -> int:
	return CardOutline.material_of(control.child.type).get_shader_parameter(&"u_outline_index")

## P35: ONLY an arrow off the list's own edge leaves for the sidebar -- and only while a stuck card has put the X there for it to land on.
func test_an_edge_arrow_leaves_the_stuck_viewer_for_the_exit_x() -> void:
	await _start_game_fixture()
	_container.show_hud()
	await _open_viewer_by_accept(_container.deck_ui.get_node(^"Button") as Button)
	var cards := _listed_viewer_cards()
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		cards[0].grab_focus()
		await get_tree().process_frame
		await _push_arrow(_booted_viewport, KEY_UP)
		check(_booted_viewport.gui_get_focus_owner() == cards[0],
				"up off the top row with nothing stuck stays on the card: an unstuck viewer asks for the sidebar at no edge (P40)",
				str(_booted_viewport.gui_get_focus_owner()))
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "sanity: the click stuck the first card to the sidebar")
		await _push_arrow(_booted_viewport, KEY_UP)
		check(_booted_viewport.gui_get_focus_owner() == _exit_button(),
				"...and with it stuck the same edge press lands on the X, in the sidebar's viewport",
				str(_booted_viewport.gui_get_focus_owner()))
		check(not cards[0].child.focused and _rim_of(cards[0]) != PaletteDB.ROLES.match_rim,
				"...the card it left giving up the rim with the focus", str(_rim_of(cards[0])))
	await _end_main_fixture()

## The X is in the OVERLAY's viewport and focus never crosses one, so the arrow off the list's edge hands it over by itself.
func test_an_edge_key_in_a_viewer_lands_the_focus_on_the_exit_x() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "sanity: the first card is stuck to the sidebar")
		await _push_arrow(_booted_viewport, KEY_UP)
		check(_booted_viewport.gui_get_focus_owner() == _exit_button(),
				"up off the top of the list lands on the exit X, in the OVERLAY's viewport",
				str(_booted_viewport.gui_get_focus_owner()))
		check(_game_viewport.gui_get_focus_owner() == null,
				"...and the game picture's viewport holds no focus of its own any more",
				str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## The Deck button TOGGLES: pressed a second time it closes the viewer it opened.
func test_the_deck_button_pressed_again_closes_the_viewer_it_opened() -> void:
	await _start_game_fixture()
	var button := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await _open_viewer_cards(button)
	check(is_instance_valid(DeckViewer._open), "the first press opened the deck viewer")
# The viewer's own opening highlight hides the HUD, so the button is put back within reach the
# way the player would: the description it published is dismissed first.
	_container.show_hud()
	await get_tree().process_frame
	check(await _click_button(button, _booted_viewport), "a real second click on Deck pressed it")
	await get_tree().process_frame
	check(not is_instance_valid(DeckViewer._open)
			or DeckViewer._open.is_queued_for_deletion(),
			"...and that second press closed the open viewer instead of opening another")
	await _end_main_fixture()

## A CARD description on the map carries none of the node's buttons: Travel and Deck belong to a node, not to a card.
func test_the_map_shows_no_travel_or_deck_while_it_describes_a_card() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	check(pack != null, "the generated map offers a talent-pack node")
	if pack != null:
		await _select_map_node_and_settle(pack)
		check(is_instance_valid(DeckViewer._open),
				"sanity: the first pick of a pack node opens its possible-cards viewer")
		check(not _map.selection_buttons.visible,
				"while the sidebar describes a viewer CARD, no Travel or Deck button shows")
		await _close_the_open_viewer()
		check(_map.selection_buttons.visible and _map.travel_button.is_visible_in_tree(),
				"closing the viewer comes back to the node, and its buttons with it")
		check(_map.selection_deck_button.is_visible_in_tree(),
				"...the node's description carrying its Deck button")
		check(_container.showing_description(),
				"...describing the node the player picked, not the card they were reading")
	await _end_main_fixture()

## The map's row belongs to the map: a node picked there puts no Deck or Travel beside a game-screen card -- a regression net only, green even without that guard now the chooser cannot be left.
func test_a_card_on_the_game_screen_shows_no_map_buttons_while_a_node_is_picked() -> void:
	await _start_game_fixture()
	await _back_to_the_map_with_the_show_frozen()
	var node := _a_map_node_with_role(MapNodeRoles.ROLE_GAME)
	check(node != null, "sanity: the map offers a show node")
	if node != null:
		await _select_map_node_and_settle(node)
		check(_map.selection_deck_button.is_visible_in_tree()
				and _map.travel_button.is_visible_in_tree(),
				"sanity: the pick's description offers its Deck and Travel buttons")
		await _click_overlay(&"ForwardButton")
		await _wait_out_the_move()
		check(_main._current_focus == &"game", "sanity: Forward went back to the live show",
				str(_main._current_focus))
		await _hover_a_card_with_a_visual()
		check(_container.showing_description(), "sanity: the game screen describes a card")
		check(not _map.selection_deck_button.is_visible_in_tree()
				and not _map.travel_button.is_visible_in_tree(),
				"a card described on the game screen carries no Deck or Travel button")
	await _end_main_fixture()

# The overlay's Back is the player's own way out of a show that is still running: the show stays
# frozen behind the map, its board and its hover alive in their own picture.
func _back_to_the_map_with_the_show_frozen() -> void:
	await _click_overlay(&"BackButton")
	await _wait_out_the_move()
	for _i : int in range(180):
		if is_equal_approx(_container.slid_fraction(), 1.0): break
		await get_tree().process_frame
	check(_main._current_focus == &"map" and _main._pictures[&"game"].screen_root is GameView,
			"sanity: Back left a live show frozen behind the map", str(_main._current_focus))

## A reachable node of the kind asked for, picked by a real click on its dot -- the token set down one step short of one when none is reachable yet.
func _click_a_reachable_node(wants_pack: bool) -> WorldGraphNode:
	var node : WorldGraphNode = null
	for next : WorldGraphNode in _map.controller._sorted_next():
		if (_booster_of(next) != null) == wants_pack: node = next
	if node == null:
		node = _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER if wants_pack
				else MapNodeRoles.ROLE_GAME)
		_map.controller._current = _a_neighbour_leading_to(node)
		_map.controller.refresh_visuals()
# The camera eases on beside the sidebar still sliding in, so the dot is clicked where it RESTS.
	var at := Vector2.INF
	for _i : int in range(180):
		var now := WorldMapController.node_screen_rect(node).get_center()
		if now.is_equal_approx(at): break
		at = now
		await get_tree().process_frame
	await _click(at, _map_viewport)
	await get_tree().process_frame
	return node

## A frozen show's board is not on the screen the player is using: a real click on the map's Travel goes where it was aimed.
func test_travel_goes_by_mouse_while_a_show_is_frozen_behind_the_map() -> void:
	await _start_game_fixture()
	await _back_to_the_map_with_the_show_frozen()
	var node := await _click_a_reachable_node(false)
	check(_map.controller.selected() == node and _map.travel_button.is_visible_in_tree(),
			"sanity: a real click picked a node and put Travel beside its description")
	var entered := _count_arrivals()
	check(await _click_button(_map.travel_button, _booted_viewport),
			"a real click on Travel pressed it with a show frozen behind the map")
	await _await_map_arrival()
	check(entered.size() == 1 and entered[0] == node,
			"...and the token travelled there", str(entered.size()))
	await _wait_out_the_move()
	await _end_main_fixture()

## With a show frozen behind the map, closing a pack's possible-cards viewer still comes back to the picked node, Travel within reach.
func test_closing_a_packs_viewer_returns_to_the_node_while_a_show_is_frozen() -> void:
	await _start_game_fixture()
	await _back_to_the_map_with_the_show_frozen()
	var pack := await _click_a_reachable_node(true)
	check(_map.controller.selected() == pack and is_instance_valid(DeckViewer._open),
			"sanity: a real click picked the pack node and opened its possible-cards viewer")
	await _click_outside_the_map_viewer()
	await get_tree().process_frame
	check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
			"sanity: a click outside the viewer closed it")
	check(_container.showing_description() and _map.travel_button.is_visible_in_tree(),
			"closing the viewer comes back to the picked node with Travel in reach")
	check(_container.showing_description() and _panel.current_entry.title == _map._info_for(pack).title,
			"...describing the node", _panel.current_entry.title if _panel.current_entry else "none")
	check(_map.controller.selected() == pack, "...the pick itself untouched")
	await _end_main_fixture()

## The X is the same one cancel as Escape: over a viewer it lets the stuck card go AND closes the viewer, in one press.
func test_the_sidebars_x_over_a_viewer_unsticks_and_closes_together() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked() and _exit_button().visible,
				"sanity: the click stuck the card and put the X there")
		check(await _click_button(_exit_button(), _booted_viewport),
				"a real click on the X pressed it")
		await get_tree().process_frame
		check(not is_instance_valid(DeckViewer._open)
				or DeckViewer._open.is_queued_for_deletion(),
				"one press of the X closed the viewer as well as unsticking the card")
		check(_hud_is_up(), "...and the sidebar is back on the HUD")
	await _end_main_fixture()

## An unstuck description belongs to the pointer: it goes as soon as the pointer is on no listed card.
func test_an_unstuck_viewer_description_goes_when_the_pointer_leaves_the_card() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		_hover_in(_booted_viewport, cards[0].get_global_rect().get_center())
		await get_tree().process_frame
		await get_tree().process_frame
		check(_container.showing_description(),
				"sanity: hovering a listed card describes it")
		_hover_in(_booted_viewport, Vector2(_booted_viewport.size) - Vector2.ONE)
		await get_tree().process_frame
		await get_tree().process_frame
		check(_hud_is_up(),
				"the pointer leaving every listed card takes the unstuck description away with it")
		check(is_instance_valid(DeckViewer._open) and not DeckViewer._open.is_queued_for_deletion(),
				"...and the viewer itself is still open")
	await _end_main_fixture()

## With nothing stuck the sidebar is the HUD, so the Deck button is under the pointer the whole time a viewer is open -- and pressing it again closes what it opened.
func test_the_deck_button_toggles_by_mouse_while_its_viewer_is_open() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await get_tree().process_frame
	check(await _click_button(deck, _booted_viewport), "a real click on Deck opened its viewer")
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open), "sanity: the viewer is open")
	check(_hud_is_up() and not _container.showing_description(),
			"the open viewer describes nothing, so the sidebar is the HUD")
	check(deck.is_visible_in_tree(),
			"...and the Deck button is on screen for the pointer to reach")
	check(await _click_button(deck, _booted_viewport), "a real second click on Deck pressed it")
	await get_tree().process_frame
	check(not is_instance_valid(DeckViewer._open)
			or DeckViewer._open.is_queued_for_deletion(),
			"...and that second press closed the viewer instead of opening another")
	await _end_main_fixture()

## The same route with no pointer at all: the opener keeps the pad focus, so accept on it opens and accept again closes.
func test_the_deck_button_toggles_by_pad_while_its_viewer_is_open() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await _open_viewer_by_accept(deck)
	check(is_instance_valid(DeckViewer._open), "accept on the Deck button opened the viewer")
	check(deck.has_focus(),
			"the open no longer steals the focus, so the pad is still on the Deck button",
			str(_booted_viewport.gui_get_focus_owner()))
	_push_key(_booted_viewport, KEY_ENTER, true)
	_push_key(_booted_viewport, KEY_ENTER, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(DeckViewer._open)
			or DeckViewer._open.is_queued_for_deletion(),
			"...so a second accept closes it, with no pointer anywhere")
	await _end_main_fixture()

## Cancel on a sticky card description leaves the focus in the SIDEBAR with no card description behind it.
func test_a_cancel_from_a_sticky_description_leaves_the_focus_in_the_sidebar() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	var cards := await _open_viewer_cards(deck)
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "sanity: the click stuck the card")
		await _close_open_viewer(_booted_viewport)
		check(not _container.showing_description(),
				"the cancel leaves no card description standing")
		var landed := _booted_viewport.gui_get_focus_owner()
		check(landed != null and _container.is_ancestor_of(landed),
				"...and the focus is in the sidebar, where the player can act", str(landed))
	await _end_main_fixture()

## A right-click over the stuck card is the same cancel as Esc, letting it go and closing the viewer together.
func test_a_right_click_over_a_stuck_deck_viewer_card_cancels_as_esc_does() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(not cards.is_empty(), "the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "sanity: the left click stuck the card")
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport, MOUSE_BUTTON_RIGHT)
		check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
				"a right-click over the stuck card closes the viewer, as Esc does")
		check(not _container.is_locked() and not _container.showing_description(),
				"...letting the card go: no lock and no card description left standing")
		var landed := _booted_viewport.gui_get_focus_owner()
		check(landed != null and _container.is_ancestor_of(landed),
				"...and the focus is in the sidebar, as Esc leaves it", str(landed))
	await _end_main_fixture()

# An open viewer is the focus: the rebuild an Undo ends in must not rest the board's focus on a
# card under it, which the booted viewport's own focus owner cannot see.
func _check_the_board_is_not_the_focus(route: String) -> void:
	var owner := _game_viewport.gui_get_focus_owner()
	check(owner == null or not _play_area.ui_data.has(owner),
			"an Undo under the open viewer rests no board card's focus (%s)" % route, str(owner))
	check(_hud_is_up(), "...so the sidebar is the HUD, describing no board card (%s)" % route)

## The mouse route: an Undo clicked under the open viewer leaves the board unfocused, the viewer's own card describes on hover, and a click outside hands the focus back to the opener.
func test_an_undo_under_an_open_viewer_rests_no_board_card_by_mouse() -> void:
	await _start_game_fixture()
	var placed := await _lift_and_place_a_card()
	check(placed != null, "sanity: a lifted card found a cell to land on")
	var deck := _container.deck_ui.get_node(^"Button") as Button
	check(await _click_button(deck, _booted_viewport), "a real click on Deck opened its viewer")
	check(await _click_button(_container.undo_button, _booted_viewport),
			"a real click on Undo under the viewer pressed it")
	await _await_the_board_idle()
	await _await_the_rest()
	_check_the_board_is_not_the_focus("mouse")
	var cards := _listed_viewer_cards()
	check(not cards.is_empty(), "sanity: the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		var title : Label = _panel.get_node(^"%Title")
		_hover_in(_booted_viewport, cards[0].get_global_rect().get_center())
		await get_tree().process_frame
		check(_container.showing_description()
				and title.text == _expected_text(cards[0].child.data)[0],
				"...and a hover in the viewer describes the viewer's card", title.text)
	await _click(Vector2(_booted_viewport.size) - Vector2(2, 2), _booted_viewport)
	check(not is_instance_valid(DeckViewer._open), "a click outside closed the viewer")
	check(_hud_is_up() and deck.has_focus(),
			"...leaving the HUD, with the focus on the button that opened it",
			str(_booted_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## The keyboard and d-pad route, no pointer anywhere, the placement that gives Undo its rewind included: arrows walk the HUD to Undo under the open viewer, an Undo accepted there leaves the board unfocused, the arrow off the sidebar into the viewer describes its first card, and cancel hands the focus back to the opener.
func test_an_undo_under_an_open_viewer_rests_no_board_card_by_keys() -> void:
	await _start_game_fixture()
	var placed := await _lift_and_place_a_card_by_keys()
	check(placed != null, "sanity: a lifted card found a cell to land on, giving Undo a rewind")
	var deck := _container.deck_ui.get_node(^"Button") as Button
	await _tap_until(KEY_LEFT, func() -> bool: return _booted_viewport.gui_get_focus_owner() != null, 12)
	await _tap_until(KEY_DOWN, deck.has_focus, 8)
	check(deck.has_focus(), "sanity: the keys reached the Deck button",
			str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_ENTER)
	check(is_instance_valid(DeckViewer._open), "accept on Deck opened its viewer")
	var undo := _container.undo_button
	await _walk_by([_tap_key.bind(KEY_DOWN), _tap_pad.bind(JOY_BUTTON_DPAD_UP),
			_tap_pad.bind(JOY_BUTTON_DPAD_DOWN)] as Array[Callable],
			[undo, deck, undo] as Array[Control], "the HUD under the open viewer")
	await _tap_key(KEY_ENTER)
	await _await_the_board_idle()
	await _await_the_rest()
	_check_the_board_is_not_the_focus("keys")
	var cards := _listed_viewer_cards()
	check(not cards.is_empty(), "sanity: the deck viewer lists cards", str(cards.size()))
	if not cards.is_empty():
		var title : Label = _panel.get_node(^"%Title")
		var walked := await _walk_right_off_the_sidebar(_tap_key.bind(KEY_RIGHT))
		check(walked and cards[0].has_focus(), "Right off the sidebar's inner edge enters the viewer's first card",
				str(_booted_viewport.gui_get_focus_owner()))
		check(_container.showing_description()
				and title.text == _expected_text(cards[0].child.data)[0],
				"...and the sidebar describes THAT card, not the HUD a board focus leaving put back",
				title.text if _container.showing_description() else "HUD")
	await _tap_key(KEY_ESCAPE)
	check(not is_instance_valid(DeckViewer._open), "cancel closed the viewer")
	check(_hud_is_up() and deck.has_focus(),
			"...leaving the HUD, with the focus on the button that opened it",
			str(_booted_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## An EMPTY viewer lists nothing for the first arrow to enter, and still it is the focus: Right off the sidebar's last control stays out of the board behind it.
func test_right_off_the_sidebar_never_reaches_the_board_behind_an_empty_viewer() -> void:
	await _start_game_fixture()
	var discard := _container.discard_ui.get_node(^"Button") as Button
	await _tap_until(KEY_LEFT, func() -> bool: return _booted_viewport.gui_get_focus_owner() != null, 12)
	await _tap_until(KEY_RIGHT, discard.has_focus, 8)
	check(discard.has_focus(), "sanity: the keys reached the Discard button",
			str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_ENTER)
	check(is_instance_valid(DeckViewer._open) and _listed_viewer_cards().is_empty(),
			"sanity: accept on Discard opened a viewer of the show's empty discard pile",
			str(_listed_viewer_cards().size()) if is_instance_valid(DeckViewer._open) else "closed")
	for _press : int in 8:
		await _tap_key(KEY_RIGHT)
	var board_owner := _game_viewport.gui_get_focus_owner()
	check(board_owner == null or not _play_area.ui_data.has(board_owner),
			"Right off the sidebar's last control focuses no board card behind the open viewer",
			str(board_owner))
	var owner := _booted_viewport.gui_get_focus_owner()
	check(owner != null and _container.is_ancestor_of(owner),
			"...and the focus stays in the sidebar", str(owner))
	check(is_instance_valid(DeckViewer._open), "...with the viewer still open")
	await _end_main_fixture()

## With nothing stuck an open viewer and the sidebar are one walk, by arrows or by the d-pad alone: Right off the sidebar's inner edge enters the list, Left off the list's left edge comes back to the HUD, and no press reaches the board beneath.
func test_the_sidebar_and_an_open_viewer_are_one_walk_with_nothing_stuck() -> void:
	for device : String in ["arrows", "d-pad"]:
		var left : Callable = _tap_key.bind(KEY_LEFT) if device == "arrows" \
				else _tap_pad.bind(JOY_BUTTON_DPAD_LEFT)
		var right : Callable = _tap_key.bind(KEY_RIGHT) if device == "arrows" \
				else _tap_pad.bind(JOY_BUTTON_DPAD_RIGHT)
		await _start_game_fixture()
		_container.show_hud()
		await _open_viewer_by_accept(_first_hud_control() as Button)
		var cards := _listed_viewer_cards()
		check(cards.size() >= 2, "sanity: the deck viewer lists two cards to walk (%s)" % device,
				str(cards.size()))
		if cards.size() >= 2:
			var walked := await _walk_right_off_the_sidebar(right)
			check(walked and cards[0].has_focus(),
					"Right off the sidebar's inner edge enters the list's first card (%s)" % device,
					_control_label(_booted_viewport.gui_get_focus_owner()))
			await _walk_by([right, left, left] as Array[Callable],
					[cards[1], cards[0], _first_hud_control()] as Array[Control],
					"inside the list, then Left off its left edge back to the HUD (%s)" % device)
			check(_hud_is_up() and not _container.is_locked(),
					"...the sidebar back on its HUD with nothing stuck (%s)" % device)
			var board_owner := _game_viewport.gui_get_focus_owner()
			check(board_owner == null or not _play_area.ui_data.has(board_owner),
					"...and no press of the walk focused a board card beneath the viewer (%s)" % device,
					str(board_owner))
			check(is_instance_valid(DeckViewer._open), "...the viewer still open (%s)" % device)
		await _end_main_fixture()

## The menu shows no HUD, so Left off the Inspect viewer's left edge has nothing in the sidebar to land on: the press stays in the list and the card it was on is still the one described, by keys and by the d-pad.
func test_left_off_the_menus_viewer_stays_in_it_with_nothing_to_land_on() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: the picker's Inspect viewer is open")
	if is_instance_valid(viewer):
		var panel : DescriptionPanel = main.hud_container.get_node(^"%DescriptionPanel")
		await _tap_key_in(viewport, KEY_DOWN)
		var first : ControlCard = viewer.cards().controls[0]
		check(first.has_focus(), "sanity: Down entered the viewer's first card",
				str(viewport.gui_get_focus_owner()))
		for device : String in ["keys", "d-pad"]:
			if device == "keys": await _tap_key_in(viewport, KEY_LEFT)
			else: await _tap_pad_in(viewport, JOY_BUTTON_DPAD_LEFT)
			check(viewport.gui_get_focus_owner() == first,
					"Left off the list's left edge stays on its card, the menu's sidebar having nothing to land on (%s)" % device,
					str(viewport.gui_get_focus_owner()))
			check(main.hud_container.showing_description() and panel.current_entry != null
					and panel.current_entry.title == _expected_text(first.child.data)[0],
					"...and that card is still the one described (%s)" % device,
					panel.current_entry.title if panel.current_entry else "none")
	await _end_booted_fixture(viewport, main)

func _tap_pad_in(viewport: SubViewport, button: JoyButton) -> void:
	for pressed : bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event)
		await get_tree().process_frame

## The run deck opened over a chooser card stuck to the sidebar: Left off the deck's left edge lands on the row that opened it, reading Close deck, with the chooser's stuck card described again -- and Right off that row goes back into the deck, by keys and by the d-pad.
func test_left_off_the_deck_over_a_stuck_chooser_card_lands_on_close_deck() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _tap_key(KEY_RIGHT)
		await _tap_key(KEY_ENTER)
		var stuck := chooser.cards().sticky
		check(stuck != null and _map.selection_deck_button.is_visible_in_tree(),
				"sanity: accept stuck a chooser card, its description offering the deck")
		await _open_viewer_by_accept(_map.selection_deck_button)
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck.cards().controls.size() > 0,
				"sanity: the run deck opened over the chooser")
		if is_instance_valid(deck) and deck.cards().controls.size() > 0:
			var first := deck.cards().controls[0]
			var row := _map.selection_deck_button
			await _walk_by([_tap_key.bind(KEY_DOWN), _tap_key.bind(KEY_LEFT),
					_tap_pad.bind(JOY_BUTTON_DPAD_RIGHT), _tap_pad.bind(JOY_BUTTON_DPAD_LEFT)]
					as Array[Callable], [first, row, first, row] as Array[Control],
					"between the deck over a stuck chooser card and its Close deck row")
			check(row.text == TRANSLATION.find(&"MAP_CLOSE_DECK")
					and _described_title() == _expected_text(stuck)[0],
					"...the row reading Close deck, the chooser's stuck card described again",
					"%s / %s" % [row.text, _described_title()])
			deck._close()
		chooser.queue_free()
		await get_tree().process_frame
	await _end_main_fixture()

## A pack node's possible cards open over its own description, X and all, its row put away while they are listed: with nothing stuck, Left off the list lands on that X, the pick described again, and Left once more -- no row beside the X -- goes back into the list, by keys and by the d-pad.
func test_left_off_the_possible_cards_lands_on_the_picks_x_first() -> void:
	for device : String in ["keys", "d-pad"]:
		var left : Callable = _tap_key.bind(KEY_LEFT) if device == "keys" \
				else _tap_pad.bind(JOY_BUTTON_DPAD_LEFT)
		var right : Callable = _tap_key.bind(KEY_RIGHT) if device == "keys" \
				else _tap_pad.bind(JOY_BUTTON_DPAD_RIGHT)
		await _start_map_fixture()
		await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
		var pack := _map.controller.selected()
		var list := DeckViewer._open
		check(pack != null and is_instance_valid(list) and list.cards().controls.size() > 0,
				"sanity: the pick listed its pack's possible cards (%s)" % device)
		if pack != null and is_instance_valid(list) and list.cards().controls.size() > 0:
			await _walk_by([right, left] as Array[Callable],
					[list.cards().controls[0], _exit_button()] as Array[Control],
					"into the possible cards and Left to the pick's X (%s)" % device)
			check(_described_title() == _map._info_for(pack).title and list.cards().sticky == null
					and not _map.selection_buttons.is_visible_in_tree(),
					"...the pick described again, nothing stuck, its row put away under the list (%s)" % device,
					_described_title())
			await _walk_by([left] as Array[Callable], [list.cards().controls[0]] as Array[Control],
					"Left off the X, with nothing beside it, goes back into the list (%s)" % device)
			await _close_the_open_viewer()
		await _end_main_fixture()

## The wall answers input frames before the sidebar slides in after a landing, but while it is out the wall's focus is still the frozen screen being left: a Left then asks no screen for the sidebar, and no hidden sidebar control takes the key focus -- both ways, into the game and back to the map.
func test_a_left_before_the_sidebar_slides_in_asks_no_screen_for_it() -> void:
	for route : StringName in [&"ForwardButton", &"BackButton"] as Array[StringName]:
		await _start_game_fixture()
		await _back_to_the_map_with_the_show_frozen()
		if route == &"BackButton":
			await _click_overlay(&"ForwardButton")
			await _wait_out_the_return()
		var asked : Array[int] = [0]
		_map.controller.sidebar_requested.connect(func() -> void: asked[0] += 1)
		_play_area.sidebar_requested.connect(func() -> void: asked[0] += 1)
		await _click_overlay(route)
		var waited := 0.0
		while waited < CARD_CONTROL_TIMEOUT_SEC and _main.wall.input_locked:
			await get_tree().process_frame
			waited += get_process_delta_time()
		var in_window := not _main.wall.input_locked and not _container.is_visible_in_tree()
		check(in_window, "sanity: the wall answers input while the sidebar is still out (%s)" % route,
				"locked=%s container shown=%s" % [_main.wall.input_locked, _container.is_visible_in_tree()])
		_push_key(_booted_viewport, KEY_LEFT, true)
		_push_key(_booted_viewport, KEY_LEFT, false)
		var focused := _booted_viewport.gui_get_focus_owner()
		check(asked[0] == 0 and (focused == null or focused.is_visible_in_tree()),
				"a Left then asks no screen for the sidebar and focuses no hidden control (%s)" % route,
				"asked=%d focus=%s" % [asked[0], focused])
		await _wait_out_the_return()
		await _end_main_fixture()

## Every screen a player can stand on, as `_stand_on()` reaches it.
const TAB_SCREENS : Array[String] = ["the start menu", "the bare map", "the map with a node described",
		"the game board", "the game with its deck viewer open", "the pack chooser"]

## Tab is wall_overview's key on every screen and Shift+Tab with it: each does what the pad's View button does there -- opens the wall -- and moves no GUI focus on the way, the arrows alone moving it.
func test_tab_opens_the_wall_on_every_screen_as_the_pad_button_does() -> void:
	check(InputMap.action_get_events(&"ui_focus_next").is_empty()
			and InputMap.action_get_events(&"ui_focus_prev").is_empty(),
			"no key is bound to the GUI's next or previous focus: the arrows alone move it")
	for screen : String in TAB_SCREENS:
		for press : String in ["Tab", "Shift+Tab", "the pad's View button"]:
			var chooser := await _stand_on(screen)
			var before := _focus_owners()
			_push_wall_overview_press(press, true)
			var after := _focus_owners()
			check(after == before or after == [null, null],
					"%s on %s moves the GUI focus to no other control" % [press, screen],
					"%s -> %s" % [before, after])
			_push_wall_overview_press(press, false)
			await get_tree().process_frame
			await _wait_out_the_move()
			check(_main._current_focus == &"", "%s on %s opens the wall" % [press, screen],
					str(_main._current_focus))
			if chooser: chooser.queue_free()
			await get_tree().process_frame
			await _end_main_fixture()

## Boots Main onto `screen` through the product's own routes; the pack chooser it opened, on that one screen.
func _stand_on(screen: String) -> ChoiceViewer:
	match screen:
		"the start menu":
			await _start_map_fixture()
			await _main._focus_picture(&"start_menu")
			await _wait_out_the_move()
		"the bare map":
			await _start_map_fixture()
		"the map with a node described":
			await _start_map_fixture()
			await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
			await _close_the_open_viewer()
		"the game board":
			await _start_game_fixture()
			await _hoverable_card_controls()
		"the game with its deck viewer open":
			await _start_game_fixture()
			await _open_viewer_by_accept(_first_hud_control() as Button)
		"the pack chooser":
			return await _open_the_chooser_with_pictures_behind_and_ahead()
	return null

## The key focus in the window's own viewport and in the focused picture's, which is where a board or menu keeps its own.
func _focus_owners() -> Array:
	var picture : WallPicture = _main._pictures.get(_main._current_focus)
	return [_booted_viewport.gui_get_focus_owner(),
			picture.viewport.gui_get_focus_owner() if picture and picture.viewport else null]

func _push_wall_overview_press(press: String, pressed: bool) -> void:
	if press == "the pad's View button":
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_BACK
		button.pressed = pressed
		_booted_viewport.push_input(button)
		return
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.physical_keycode = KEY_TAB
	key.shift_pressed = press == "Shift+Tab"
	key.pressed = pressed
	_booted_viewport.push_input(key)

# The board rests its focus once its visuals are ready, which can be frames after the rebuild.
func _await_the_rest() -> void:
	if not _play_area.visuals_ready(): await _play_area.board_visuals_ready
	await get_tree().process_frame
	await get_tree().process_frame

## The chooser is a window as tall as what it holds (no longer a square, visual review round 3), centred beside the sidebar with the map showing on every side, and its sidebar offers a look at the deck the cards are joining; harness-scale only.
func test_the_chooser_is_a_fitted_window_with_the_map_around_it() -> void:
	await _start_map_fixture()
	var chooser := await _open_a_pack_chooser()
	if chooser != null:
		await _resize_viewport(_booted_viewport, INSET_WINDOWS[-1])
		_check_the_chooser_holds_its_parts_beside_the_sidebar(chooser, str(INSET_WINDOWS[-1]))
		_check_rerolls_sits_beside_take(chooser, str(INSET_WINDOWS[-1]))
		await _resize_viewport(_booted_viewport, INSET_WINDOWS[0])
		_check_the_chooser_holds_its_parts_beside_the_sidebar(chooser, str(INSET_WINDOWS[0]))
		_check_rerolls_sits_beside_take(chooser, str(INSET_WINDOWS[0]))
		_check_the_offered_cards_lie_in_one_row(chooser, str(INSET_WINDOWS[0]))
		var window := _chooser_window(chooser)
		var space := _ui_space(_main)
		_check_the_chooser_pads_its_rows_as_its_sides(chooser, str(INSET_WINDOWS[0]))
		check(is_equal_approx(window.get_center().x, space.get_center().x)
				and is_equal_approx(window.get_center().y, space.get_center().y),
				"...centred in the space beside the sidebar", "%s in %s" % [window, space])
		await _check_the_map_shows_around_the_chooser(window, space)
		_click_a_listed_card(chooser._cards.controls[0])
		await get_tree().process_frame
		check(_container.showing_description() and _container.is_locked(),
				"a click on a chosen card sticks its description to the sidebar")
		check(_map.selection_deck_button.is_visible_in_tree(),
				"...which carries a Deck button, the chooser having no node of its own")
		check(not _map.travel_button.is_visible_in_tree()
				and not _map.possible_cards_button.is_visible_in_tree(),
				"...and nothing else: there is no node here to travel to or list")
		_map.selection_deck_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		check(is_instance_valid(DeckViewer._open),
				"that Deck button opens the run deck over the chooser")
		check(is_instance_valid(chooser) and not chooser.is_queued_for_deletion(),
				"...and the chooser is still there underneath it")
		if is_instance_valid(DeckViewer._open): DeckViewer._open._close()
		await get_tree().process_frame
		if is_instance_valid(chooser): chooser.queue_free()
		await get_tree().process_frame
	await _end_main_fixture()

## The map around the chooser's window stays in view and answers nothing: a hover names no node, a click picks none, a drag pans nothing and the wheel zooms nothing, and the chooser stays up.
func test_the_map_around_the_chooser_ignores_clicks_drags_and_the_wheel() -> void:
	await _start_map_fixture()
	await _zoom_the_map_in(_main, 3)
	var chooser := await _open_a_pack_chooser()
	if chooser != null:
		await get_tree().process_frame
		var window := _chooser_window(chooser)
		var target := _a_reachable_node_beside(window)
		check(target != null, "sanity: a reachable node lies on the map outside the window")
		if target != null:
			var controller := _map.controller
			var at := _point_in_window(&"map", WorldMapController.node_screen_rect(target).get_center())
			var camera_before := controller.camera.global_transform
			var zoom_before := controller.camera.zoom
			_hover_in(_booted_viewport, at)
			await get_tree().process_frame
			check(controller._hovered != target, "a hover over a node outside the window reaches no node",
					str(controller._hovered))
			await _click(at, _booted_viewport)
			check(controller.selected() == null, "a click on it picks nothing",
					str(controller.selected()))
			_drag_in_the_window(at, _drag_toward_the_map_centre(MAP_PAN_DRAG))
			await _await_map_framing_settled(_main)
			check(controller.camera.global_transform.is_equal_approx(camera_before),
					"a drag starting outside the window pans nothing",
					"%s -> %s" % [camera_before.origin, controller.camera.global_transform.origin])
			_push_wheel_notch(_booted_viewport, MOUSE_BUTTON_WHEEL_DOWN, at)
			await _await_map_framing_settled(_main)
			check(controller.camera.zoom.is_equal_approx(zoom_before),
					"...and the wheel there zooms nothing", "%s -> %s" % [zoom_before, controller.camera.zoom])
			check(_chooser_is_up(chooser), "...and the chooser is still up")
		chooser.queue_free()
		await get_tree().process_frame
	await _end_main_fixture()

## A wheel over a deck viewer moves nothing beneath it -- its list at either limit, its frame, the map around its window, the board under a game viewer -- and still scrolls the list.
func test_a_wheel_over_a_deck_viewer_never_reaches_the_screen_beneath() -> void:
	await _start_map_fixture()
	var fit := _map.controller.camera.zoom.x
	await _zoom_the_map_in(_main, 3)
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	var list := DeckViewer._open
	check(is_instance_valid(list) and _map.controller.camera.zoom.x > fit,
			"sanity: the pack's list is up over a map zoomed in past its fit, so a wheel either way would show",
			"%.4f vs fit %.4f" % [_map.controller.camera.zoom.x, fit])
	if is_instance_valid(list):
		var scroll := list._scroll as SmoothScrollContainer
		await _await_the_list_at_rest(scroll)
		var window := _backdrop_of(list).get_global_rect()
		var inside := scroll.get_global_rect()
		var catcher := list.margin_container.get_global_rect()
		var centre := inside.get_center()
		var frame := Vector2((window.position.x + inside.position.x) * 0.5, centre.y)
		var outside := catcher.end - Vector2.ONE
		var bar := scroll.get_v_scroll_bar()
		var end := bar.max_value - bar.page
		check(end > 0.0 and scroll.scroll_vertical == 0 and inside.has_area(),
				"sanity: the list has a range to scroll and rests at its top",
				"range %.1f, at %d, in %s" % [end, scroll.scroll_vertical, inside])
		check(window.has_point(frame) and not inside.has_point(frame),
				"sanity: the frame point is on the window's frame, outside the list",
				"%s, window %s, list %s" % [frame, window, inside])
		check(catcher.has_point(outside) and not window.has_point(outside),
				"sanity: the outside point is on the map beside the window",
				"%s, catcher %s, window %s" % [outside, catcher, window])
		await _check_a_notch_zooms_no_map(scroll, MOUSE_BUTTON_WHEEL_UP, centre, 0,
				"up at the list's top limit")
		await _check_a_notch_zooms_no_map(scroll, MOUSE_BUTTON_WHEEL_DOWN, frame, 0,
				"over the window's frame")
		await _check_a_notch_zooms_no_map(scroll, MOUSE_BUTTON_WHEEL_DOWN, outside, 0,
				"over the map beside the window")
		await _notch_over_the_viewer(scroll, MOUSE_BUTTON_WHEEL_DOWN, centre)
		var part_way := scroll.scroll_vertical
		check(part_way > 0, "a notch over the list still scrolls it", str(part_way))
		await _notch_over_the_viewer(scroll, MOUSE_BUTTON_WHEEL_UP, bar.get_global_rect().get_center())
		check(scroll.scroll_vertical < part_way, "...and one over its scrollbar scrolls it back",
				"%d -> %d" % [part_way, scroll.scroll_vertical])
		for _notch : int in range(ceili(end)):
			if scroll.scroll_vertical >= floori(end): break
			await _notch_over_the_viewer(scroll, MOUSE_BUTTON_WHEEL_DOWN, centre)
		var at_end := scroll.scroll_vertical
		check(absf(at_end - end) <= 1.0, "sanity: real notches took the list to its end",
				"%d of %.1f" % [at_end, end])
		await _check_a_notch_zooms_no_map(scroll, MOUSE_BUTTON_WHEEL_DOWN, centre, at_end,
				"down at the list's end")
		check(is_instance_valid(list) and not list.is_queued_for_deletion(),
				"...and the list is still up through every notch")
		await _close_the_open_viewer()
	await _end_main_fixture()
	await _start_game_fixture()
	check(await _click_button(_container.deck_ui.get_node(^"Button") as Button, _booted_viewport),
			"sanity: a real click on the board's Deck pressed it")
	await get_tree().process_frame
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: the board's Deck opened its viewer")
	if is_instance_valid(viewer):
		var scroll := viewer._scroll as SmoothScrollContainer
		await _await_the_list_at_rest(scroll)
		var bar := scroll.get_v_scroll_bar()
		check(bar.max_value - bar.page > 0.0 and scroll.scroll_vertical == 0
				and scroll.get_global_rect().has_area(),
				"sanity: the board's deck list has a range to scroll and rests at its top",
				"range %.1f, at %d" % [bar.max_value - bar.page, scroll.scroll_vertical])
		var reached : Array[int] = [0]
		var count_the_notch := func(event: InputEvent) -> void:
			var button := event as InputEventMouseButton
			if button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP: reached[0] += 1
		_play_area.scroll_container.gui_input.connect(count_the_notch)
		await _notch_over_the_viewer(scroll, MOUSE_BUTTON_WHEEL_UP, scroll.get_global_rect().get_center())
		_play_area.scroll_container.gui_input.disconnect(count_the_notch)
		check(reached[0] == 0, "a notch up at the deck list's top limit reaches no board beneath it",
				"%d reached the board's own scroll" % reached[0])
		check(scroll.scroll_vertical == 0, "...and the list rests at its top", str(scroll.scroll_vertical))
		await _close_the_open_viewer()
	await _end_main_fixture()

## One real notch at `at` over a viewer, then the list and the map beneath both left to come to rest.
func _notch_over_the_viewer(scroll: SmoothScrollContainer, button: MouseButton, at: Vector2) -> void:
	_hover_in(_booted_viewport, at)
	await get_tree().process_frame
	_push_wheel_notch(_booted_viewport, button, at)
	await _await_the_list_at_rest(scroll)
	await _await_map_framing_settled(_main)

## Checks one real notch at `at` leaves the map's zoom as it was and the list resting at `rests_at`.
func _check_a_notch_zooms_no_map(scroll: SmoothScrollContainer, button: MouseButton, at: Vector2,
		rests_at: int, where: String) -> void:
	var zoom := _map.controller.camera.zoom
	await _notch_over_the_viewer(scroll, button, at)
	check(_map.controller.camera.zoom.is_equal_approx(zoom),
			"a wheel notch %s zooms no map beneath" % where,
			"%s -> %s" % [zoom, _map.controller.camera.zoom])
	check(scroll.scroll_vertical == rests_at, "...and the list rests where it was (%s)" % where,
			"%d vs %d" % [scroll.scroll_vertical, rests_at])

# THE LIST EASES AFTER A NOTCH, and springs back from past a limit: at rest once a frame has run and
# nothing is left moving it, bounded so a list that never rests surfaces as a failure.
func _await_the_list_at_rest(scroll: SmoothScrollContainer) -> void:
	var waited := 0.0
	await get_tree().process_frame
	while (scroll.is_scrolling or scroll.velocity != Vector2.ZERO) and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()

# A node a click could pick, drawn on the map beside the chooser's window rather than under it. The
# graph is random per boot, so the token is stood where its next step lands outside the window.
func _a_reachable_node_beside(window: Rect2) -> WorldGraphNode:
	var controller := _map.controller
	var space := _ui_space(_main)
	for from : WorldGraphNode in controller.map.overlay().nodes():
		for node : WorldGraphNode in controller.next_nodes_of(from):
			var rect := WorldMapController.node_screen_rect(node)
			var at := Rect2(_point_in_window(&"map", rect.position), Vector2.ZERO) \
					.expand(_point_in_window(&"map", rect.end))
			if space.encloses(at) and not window.grow(8.0).intersects(at):
				controller._current = from
				return node
	return null

## A press, one motion and a release, pushed at the booted window as a player's drag would arrive.
func _drag_in_the_window(from: Vector2, by: Vector2) -> void:
	_push_mouse_button(from, _booted_viewport, true)
	var motion := InputEventMouseMotion.new()
	motion.position = from + by
	motion.global_position = motion.position
	motion.relative = by
	_booted_viewport.push_input(motion)
	_push_mouse_button(from + by, _booted_viewport, false)

## A pack node's chooser opened on the map, or null (each a failed check) when there is none.
func _open_a_pack_chooser() -> ChoiceViewer:
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	check(pack != null, "the generated map offers a talent-pack node")
	if pack == null: return null
	await _map._open_booster(pack)
	await get_tree().process_frame
	var chooser := _map._chooser
	check(chooser != null, "the pack node opened its chooser")
	return chooser

## The chooser's window, in the overlay's own space.
func _chooser_window(chooser: ChoiceViewer) -> Rect2:
	return (chooser.get_node(^"Layout") as Control).get_global_rect()

func _check_the_chooser_holds_its_parts_beside_the_sidebar(chooser: ChoiceViewer,
		where: String) -> void:
	var window := _chooser_window(chooser)
	var parts : Array[Control] = [chooser.confirm_button, chooser.rerolls_label]
	parts.append_array(chooser._reroll_buttons)
	for control : ControlCard in chooser._cards.controls:
		parts.append(control)
	for part : Control in parts:
		check(window.grow(0.5).encloses(part.get_global_rect()),
				"the chooser's window holds its %s at %s" % [part.name, where],
				"%s outside %s" % [part.get_global_rect(), window])
	check(_ui_space(_main).grow(0.5).encloses(window),
			"...and lies inside the space beside the sidebar at %s" % where,
			"%s vs %s" % [window, _ui_space(_main)])

## Half a pixel either side: a container places its children on whole pixels.
const CENTRED_TOLERANCE_PX := 1.0

## How far off the space's centre the menu's content may rest, in UI pixels.
const MENU_CENTRED_TOLERANCE_PX := 2.0

# Rerolls and Take share the window's foot row: the same vertical band, Rerolls to Take's left.
func _check_rerolls_sits_beside_take(chooser: ChoiceViewer, where: String) -> void:
	var rerolls := chooser.rerolls_label.get_global_rect()
	var take := chooser.confirm_button.get_global_rect()
	check(absf(rerolls.get_center().y - take.get_center().y) < 0.5
			and rerolls.end.x <= take.position.x,
			"Rerolls sits beside Take in one row at %s" % where, "%s vs %s" % [rerolls, take])
	var pair := rerolls.merge(take)
	var window := _chooser_window(chooser)
	check(absf(pair.get_center().x - window.get_center().x) <= CENTRED_TOLERANCE_PX,
			"...the pair centred in the window at %s" % where, "%s in %s" % [pair, window])

# The offered cards unwrapped: one shared top edge, each starting past the one before.
func _check_the_offered_cards_lie_in_one_row(chooser: ChoiceViewer, where: String) -> void:
	var rects : Array[Rect2] = []
	for control : ControlCard in chooser._cards.controls:
		rects.append(control.get_global_rect())
	var one_row := rects.size() == 5
	for i : int in range(1, rects.size()):
		one_row = one_row and is_equal_approx(rects[i].position.y, rects[0].position.y) 				and rects[i].position.x >= rects[i - 1].end.x
	check(one_row, "the five offered cards lie in one row at %s" % where, str(rects))
	var row := rects[0]
	for rect : Rect2 in rects: row = row.merge(rect)
	var window := _chooser_window(chooser)
	check(absf(row.get_center().x - window.get_center().x) <= CENTRED_TOLERANCE_PX,
			"...centred in the window at %s" % where, "%s in %s" % [row, window])

# THE MAP IS DRAWN AROUND THE WINDOW, read off the window's own pixels: the window is the HUD
# background, and a point halfway between each of its edges and the space's edge is not.
func _check_the_map_shows_around_the_chooser(window: Rect2, space: Rect2) -> void:
	_booted_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _booted_viewport.get_texture().get_image()
	var hud := PaletteDB.color(PaletteDB.ROLES.viewer_pack)
	var centre := window.get_center()
	var inside := window.position + Vector2.ONE * 4.0
	check(_colour_distance(image.get_pixelv(Vector2i(inside)), hud) < 0.05,
			"the chooser's window is drawn in its own colour", "%s at %s of %s, hud %s, sidebar %s" % [
			image.get_pixelv(Vector2i(inside)), inside, image.get_size(), hud,
			image.get_pixelv(Vector2i(_container.get_global_rect().get_center()))])
	var beside : Dictionary[String, Vector2] = {
		"left": Vector2((space.position.x + window.position.x) / 2.0, centre.y),
		"right": Vector2((window.end.x + space.end.x) / 2.0, centre.y),
		"top": Vector2(centre.x, (space.position.y + window.position.y) / 2.0),
		"bottom": Vector2(centre.x, (window.end.y + space.end.y) / 2.0),
	}
	for side : String in beside:
		var at := beside[side]
		var pixel := image.get_pixelv(Vector2i(at))
		check(not window.has_point(at) and space.has_point(at)
				and _colour_distance(pixel, hud) > 0.05,
				"the map shows on the window's %s" % side, "%s at %s" % [pixel, at])

static func _colour_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## A click outside closes the pack's possible-cards viewer and closes nothing of the chooser; a cancel with nothing stuck leaves it waiting and reaches the wall.
func test_a_click_outside_closes_the_pack_viewer_but_never_the_chooser() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	check(pack != null, "the generated map offers a talent-pack node")
	if pack != null:
		await _select_map_node_and_settle(pack)
		check(is_instance_valid(DeckViewer._open),
				"sanity: picking the pack node opened its possible-cards viewer")
		await _click_outside_the_map_viewer()
		check(not is_instance_valid(DeckViewer._open)
				or DeckViewer._open.is_queued_for_deletion(),
				"a click outside the possible-cards viewer closes it")
		_map.controller.clear_selection()
		await _map._open_booster(pack)
		await get_tree().process_frame
		var chooser := _map._chooser
		check(chooser != null, "the pack node opened its chooser")
		if chooser != null:
			await _click(Vector2(_booted_viewport.size) - Vector2.ONE, _booted_viewport)
			check(not chooser.is_queued_for_deletion(),
					"a click outside the chooser closes nothing")
			var cancel := InputEventAction.new()
			cancel.action = &"ui_cancel"
			cancel.pressed = true
			_booted_viewport.push_input(cancel)
			await get_tree().process_frame
			await _wait_out_the_move()
			check(_main._current_focus == &"" and _chooser_is_up(chooser),
					"...and a cancel with nothing stuck reaches the wall, the chooser left waiting",
					"focus=%s chooser_up=%s" % [_main._current_focus, _chooser_is_up(chooser)])
			chooser.queue_free()
			await get_tree().process_frame
	await _end_main_fixture()

## No route off the map is locked while the chooser is up: each one leaves, and coming back finds the chooser exactly as it was left -- its rolled cards, its rerolls, its stuck card described with its X. Take still finishes it.
func test_every_route_leaves_the_chooser_and_comes_back_to_it_in_progress() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser, a picture behind the map and one ahead")
	if chooser != null:
		for button_name : StringName in [&"BackButton", &"ForwardButton", &"WallButton"]:
			check(not _overlay_button(button_name).disabled,
					"with the chooser up, the overlay's %s is live, not greyed" % button_name)
		check(await _click_button(chooser._reroll_buttons[0], _booted_viewport),
				"sanity: a real click on a Reroll pressed it")
		var waited := 0.0
		while waited < CARD_CONTROL_TIMEOUT_SEC and chooser.data.rerolls == SettingsManager.settings.booster_reroll_pool:
			await get_tree().process_frame
			waited += get_process_delta_time()
		await _click(chooser.cards().controls[1].get_global_rect().get_center(), _booted_viewport)
		var left_as := _the_chooser_in_progress(chooser)
		check(chooser.data.rerolls < SettingsManager.settings.booster_reroll_pool
				and chooser.cards().sticky != null and _container.is_locked() and _exit_button().visible,
				"sanity: a card was rerolled and another stuck, described with its X", str(left_as))
# A pinch over the window lands on its cards, so the pinch route pinches beside it.
		var routes := _routes_off_the_map()
		for index : int in routes.size():
			if routes[index][0] == "a pinch in":
				routes[index] = ["a pinch in beside the window",
						_pinch_in_at.bind(_beside_the_chooser(chooser)), routes[index][2]]
		for route : Array in routes:
			await (route[1] as Callable).call()
			await _wait_out_the_move()
			check(_main._current_focus != &"map" and _chooser_is_up(chooser),
					"with the chooser up, %s leaves the map, the chooser waiting there" % route[0],
					"focus=%s chooser_up=%s" % [_main._current_focus, _chooser_is_up(chooser)])
			if _main._current_focus == &"map": continue
			await (route[2] as Callable).call()
			await _wait_out_the_return()
			check(_main._current_focus == &"map" and _the_chooser_in_progress(chooser) == left_as,
					"...and coming back after %s finds the chooser as it was left" % route[0],
					"focus=%s %s vs %s" % [_main._current_focus, _the_chooser_in_progress(chooser), left_as])
			_check_the_key_focus_is_on(_stuck_control(chooser), "after %s" % route[0])
		await _tap_key(KEY_ESCAPE)
		check(chooser.cards().sticky == null and not chooser.confirm_button.disabled
				and _main._current_focus == &"map",
				"a cancel with a card stuck only lets it go, Take back within reach, the map still the screen",
				str(_main._current_focus))
		var let_go_as := _the_chooser_in_progress(chooser)
		await _tap_key(KEY_ESCAPE)
		await _wait_out_the_move()
		check(_main._current_focus == &"" and _chooser_is_up(chooser),
				"...and the next cancel, nothing stuck, reaches the wall, the chooser waiting on the map",
				"focus=%s chooser_up=%s" % [_main._current_focus, _chooser_is_up(chooser)])
		await _click_overlay(&"BackButton")
		await _wait_out_the_return()
		check(_main._current_focus == &"map" and _the_chooser_in_progress(chooser) == let_go_as,
				"...and Back from the wall finds the chooser in progress",
				"focus=%s %s vs %s" % [_main._current_focus, _the_chooser_in_progress(chooser), let_go_as])
		_check_the_key_focus_is_on(chooser.confirm_button, "after the cancel to the wall")
		check(await _click_button(chooser.confirm_button, _booted_viewport),
				"a real click on Take pressed it")
		await get_tree().process_frame
		check(not is_instance_valid(chooser) or chooser.is_queued_for_deletion(),
				"...and Take finished the chooser")
		await _stand_the_map_between_two_pictures()
		for route : Array in _routes_off_the_map():
			await (route[1] as Callable).call()
			await _wait_out_the_move()
			check(_main._current_focus != &"map",
					"after Take, %s leaves the map" % route[0],
					str(_main._current_focus))
			await (route[2] as Callable).call()
			await _wait_out_the_move()
			check(_main._current_focus == &"map", "sanity: back on the map after %s" % route[0],
					str(_main._current_focus))
			check(_hud_is_up(),
					"...and its sidebar is back on the HUD, not on a card the chooser took with it")
	await _end_main_fixture()

# THE ROUTES ABOVE WALKED THE HISTORY, and a wall_jump visit trims it, so the map is stood again
# with a picture behind it and one ahead: game, map, the start menu, then Back.
func _stand_the_map_between_two_pictures() -> void:
	for id : StringName in [&"game", &"map", &"start_menu"] as Array[StringName]:
		await _main._focus_picture(id)
	await _click_overlay(&"BackButton")
	await _wait_out_the_move()
	check(_main._current_focus == &"map" and _main._focus_stack.can_back()
			and _main._focus_stack.can_forward(),
			"sanity: the map stands between a picture behind it and one ahead", str(_main._current_focus))

# THE CHOOSER COMES BACK WITH THE SIDEBAR, fading in on its slide, which runs on after the move lands.
func _wait_out_the_return() -> void:
	await _wait_out_the_move()
	await _await_the_menus_slide(_container, 1.0)

## A window point halfway between the chooser's window and the space's left edge.
func _beside_the_chooser(chooser: ChoiceViewer) -> Vector2:
	var window := _chooser_window(chooser)
	return Vector2((_ui_space(_main).position.x + window.position.x) / 2.0, window.get_center().y)

## A point in picture `id`'s own viewport in the booted window's pixels: the wall's own routing, run backwards.
func _point_in_window(id: StringName, at: Vector2) -> Vector2:
	return _picture_point_in_window(_main._pictures[id], at)

func _picture_point_in_window(picture: WallPicture, at: Vector2) -> Vector2:
	var sprite : Sprite2D = picture.get_node(^"%Screen")
	return sprite.get_global_transform_with_canvas() * (at - Vector2(picture.viewport.size) * 0.5)

## Everything a return to the chooser must find unchanged, as one comparable value.
func _the_chooser_in_progress(chooser: ChoiceViewer) -> Array:
	if not _chooser_is_up(chooser): return []
	var shown := _panel.current_entry.title if _container.showing_description() and _panel.current_entry 			else "HUD"
	return [chooser.data.current_choices.duplicate(), chooser.data.rerolls, chooser.cards().sticky,
			shown, _container.is_locked(), _exit_button().visible, chooser.is_visible_in_tree()]

## A pack reached while the player is already leaving the map still lets them back to it: the chooser waits there, and Take closes it.
func test_leaving_mid_walk_onto_a_pack_never_strands_the_chooser() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	check(pack != null, "the generated map offers a talent-pack node")
	if pack != null:
		await _select_map_node_and_settle(pack)
		await _close_the_open_viewer()
		check(await _click_button(_map.travel_button, _booted_viewport), "a real click on Travel pressed it")
# ⚠ THE KEY, NOT A CLICK: a push is handled at once, so the leave starts while the token walks; a
# click's hover and release frames let a short edge arrive first.
		check(_map.controller._moving, "sanity: the token is still walking as wall_back is pressed")
		await _tap_key(KEY_BRACKETLEFT)
		var waited := 0.0
		while waited < CARD_CONTROL_TIMEOUT_SEC and (_map._chooser == null
				or _main._move_in_flight):
			await get_tree().process_frame
			waited += get_process_delta_time()
		var chooser := _map._chooser
		check(chooser != null and _main._current_focus == &"start_menu",
				"sanity: the leave landed while the walk arrived on the pack and opened its chooser",
				str(_main._current_focus))
		await _click_overlay(&"ForwardButton")
		await _wait_out_the_move()
		check(_main._current_focus == &"map",
				"from where the leave landed, Forward brings the player back to the chooser",
				str(_main._current_focus))
		if chooser != null and _main._current_focus == &"map":
			check(await _click_button(chooser.confirm_button, _booted_viewport),
					"...where a real click on Take presses it")
	await _end_main_fixture()

## The chooser's own Deck button opens the run deck over it; a Back and Forward come back to both as left, and closing that viewer comes back to the chooser.
func test_the_choosers_deck_button_opens_over_it_and_closing_returns_to_it() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked() and _map.selection_deck_button.is_visible_in_tree(),
				"sanity: a click stuck a chosen card, its description offering the deck")
		check(await _click_button(_map.selection_deck_button, _booted_viewport),
				"a real click on the chooser's Deck button pressed it")
		await get_tree().process_frame
		check(is_instance_valid(DeckViewer._open) and _chooser_is_up(chooser),
				"the run deck opens over the chooser, which stays up underneath")
		var deck := DeckViewer._open
		await _click_overlay(&"BackButton")
		await _wait_out_the_move()
		check(_main._current_focus != &"map" and _chooser_is_up(chooser),
				"...and Back leaves the map with the deck viewer over the chooser",
				str(_main._current_focus))
		await _click_overlay(&"ForwardButton")
		await _wait_out_the_return()
		check(_main._current_focus == &"map" and is_instance_valid(deck)
				and not deck.is_queued_for_deletion() and _chooser_is_up(chooser),
				"...and Forward comes back to the deck still open over the chooser",
				str(_main._current_focus))
		var focused := _booted_viewport.gui_get_focus_owner()
		check(focused == null or not chooser.is_ancestor_of(focused),
				"...the key focus not put back under the deck, on a chooser control", str(focused))
		await _tap_key(KEY_ESCAPE)
		check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
				"a cancel closes the deck viewer")
		check(_main._current_focus == &"map" and _chooser_is_up(chooser),
				"...and the player is back on the chooser, the map still the screen",
				str(_main._current_focus))
	await _end_main_fixture()

## The run deck opened over a stuck chooser card sets that card aside, and closing the deck -- by a cancel or by a click outside -- gives it back, stuck, with its X; Take stays held.
func test_closing_the_deck_viewer_over_the_chooser_gives_back_its_stuck_card() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		var stuck_title := _panel.current_entry.title if _panel.current_entry else ""
		check(_container.is_locked() and _exit_button().visible and chooser.confirm_button.disabled,
				"sanity: a click stuck a chosen card, its X up and Take held")
		var closes : Array[Array] = [
			["a cancel", _tap_key.bind(KEY_ESCAPE)],
			["a click outside it", _click.bind(Vector2(_booted_viewport.size) - Vector2.ONE, _booted_viewport)],
			["its close tab", _click_the_open_viewers_tab.bind(_booted_viewport)],
		]
		for close : Array in closes:
			check(await _click_button(_map.selection_deck_button, _booted_viewport),
					"a real click on the chooser's Deck button pressed it (%s)" % close[0])
			await get_tree().process_frame
			check(is_instance_valid(DeckViewer._open) and not DeckViewer._open.is_queued_for_deletion(),
					"sanity: the run deck opened over the chooser (%s)" % close[0])
			await (close[1] as Callable).call()
			await get_tree().process_frame
			check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
					"sanity: %s closed the deck viewer" % close[0])
			var shown_title := _panel.current_entry.title 					if _container.showing_description() and _panel.current_entry else "HUD"
			check(_container.is_locked() and shown_title == stuck_title and _exit_button().visible,
					"closing the deck by %s gives back the chooser's stuck card with its X" % close[0],
					"locked=%s shown=%s x=%s" % [_container.is_locked(), shown_title,
					_exit_button().visible])
			check(chooser.cards().sticky != null and chooser.confirm_button.disabled,
					"...and the chooser still holds it stuck, Take held as before (%s)" % close[0])
			check(_map.selection_deck_button.is_visible_in_tree(),
					"...its Deck button still beside it (%s)" % close[0])
		chooser.queue_free()
	await _end_main_fixture()

## A right-click over the chooser's stuck card lets it go as Esc does, and one with nothing stuck leaves the pack up: Take alone finishes it.
func test_a_right_click_over_a_stuck_chooser_card_lets_it_go_as_esc_does() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		var card := chooser.cards().controls[0]
		await _click(card.get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked() and chooser.cards().sticky != null
				and chooser.confirm_button.disabled,
				"sanity: the left click stuck a chosen card, Take held")
		await _click(card.get_global_rect().get_center(), _booted_viewport, MOUSE_BUTTON_RIGHT)
		check(chooser.cards().sticky == null and not _container.is_locked(),
				"a right-click over the stuck card lets it go, as Esc does")
		check(_chooser_is_up(chooser) and not chooser.confirm_button.disabled,
				"...and the pack stays up with Take back within reach")
		await _click(card.get_global_rect().get_center(), _booted_viewport, MOUSE_BUTTON_RIGHT)
		check(_chooser_is_up(chooser) and chooser.cards().sticky == null,
				"a right-click with nothing stuck leaves the pack up and sticks nothing")
		chooser.queue_free()
	await _end_main_fixture()

## The chooser keeps its Deck button while the run deck is open over it, and pressing it again -- by a click or a keyboard accept -- closes the deck and gives back the stuck card with its X.
func test_the_choosers_deck_button_stays_up_and_closes_its_open_deck() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		var stuck_title := _panel.current_entry.title if _panel.current_entry else ""
		check(_container.is_locked() and _exit_button().visible and chooser.confirm_button.disabled,
				"sanity: a click stuck a chosen card, its X up and Take held")
		var presses : Array[Array] = [
			["a click", _click_button.bind(_map.selection_deck_button, _booted_viewport)],
			["a keyboard accept", _open_viewer_by_accept.bind(_map.selection_deck_button)],
		]
		for press : Array in presses:
			await _click_button(_map.selection_deck_button, _booted_viewport)
			await get_tree().process_frame
			var viewer := DeckViewer._open
			check(is_instance_valid(viewer) and not viewer.is_queued_for_deletion(),
					"sanity: the run deck opened over the chooser (%s)" % press[0])
			check(_map.selection_deck_button.is_visible_in_tree(),
					"the chooser's Deck button stays visible while its deck is open (%s)" % press[0])
			await (press[1] as Callable).call()
			await get_tree().process_frame
			check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
					"pressing the chooser's Deck again by %s closes the deck" % press[0])
			var shown_title := _panel.current_entry.title \
					if _container.showing_description() and _panel.current_entry else "HUD"
			check(_container.is_locked() and shown_title == stuck_title and _exit_button().visible,
					"...giving back the chooser's stuck card with its X (%s)" % press[0],
					"locked=%s shown=%s x=%s" % [_container.is_locked(), shown_title,
					_exit_button().visible])
			check(chooser.cards().sticky != null and chooser.confirm_button.disabled,
					"...Take held as before (%s)" % press[0])
		chooser.queue_free()
	await _end_main_fixture()

# THE ROW COMES BEFORE ANYTHING DESCRIPTIVE: under the overlay's own band, above the described card
# and its name, wherever it shows -- a picked node, and the chooser's stuck card.
func test_the_description_row_sits_under_the_band_above_the_described_card() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	await _close_the_open_viewer()
	await get_tree().process_frame
	_check_the_row_heads_the_description("a picked pack node")
	await _resize_viewport(_booted_viewport, INSET_WINDOWS[-1])
	_check_the_row_heads_the_description("a picked pack node, top-band window")
	await _end_main_fixture()
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		await get_tree().process_frame
		_check_the_row_heads_the_description("the chooser's stuck card")
		chooser.queue_free()
	await _end_main_fixture()

func _check_the_row_heads_the_description(where: String) -> void:
	var band_bottom := -INF
	for button_name : StringName in [&"BackButton", &"ForwardButton", &"WallButton"] as Array[StringName]:
		band_bottom = maxf(band_bottom, _overlay_button(button_name).get_global_rect().end.y)
	var row := _map.selection_buttons.get_global_rect()
	var described := (_panel.get_node(^"%VisualSlot") as Control).get_global_rect() \
			.merge((_panel.get_node(^"%Title") as Control).get_global_rect())
	check(_map.selection_buttons.is_visible_in_tree() and row.position.y >= band_bottom - 0.5,
			"the row sits below the Back/Forward/Wall band (%s)" % where,
			"row top %s band bottom %s" % [row.position.y, band_bottom])
	check(row.end.y <= described.position.y + 0.5,
			"the row sits above the described card and its name (%s)" % where,
			"row bottom %s described top %s" % [row.end.y, described.position.y])
	var x := _exit_button().get_global_rect()
	for button : Button in _map.selection_buttons.get_children():
		if not button.is_visible_in_tree(): continue
		check(not (_exit_button().visible and button.get_global_rect().intersects(x)),
				"%s is not under the X (%s)" % [button.text, where],
				"%s vs %s" % [button.get_global_rect(), x])

# THE OPENER IS ALSO THE CLOSER while its own viewer is up, and says so; closing it puts the name back.
func test_the_choosers_deck_button_reads_close_deck_while_its_deck_is_open() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		var deck := _map.selection_deck_button
		check(deck.text == TRANSLATION.find(&"MAP_DECK"), "sanity: Deck reads Deck", deck.text)
		check(await _click_button(deck, _booted_viewport), "a real click pressed Deck")
		await get_tree().process_frame
		check(is_instance_valid(DeckViewer._open) and not DeckViewer._open.is_queued_for_deletion(),
				"sanity: the run deck opened over the chooser")
		check(deck.text == TRANSLATION.find(&"MAP_CLOSE_DECK") and deck.text != "MAP_CLOSE_DECK",
				"with its deck open, the chooser's Deck reads Close deck", deck.text)
		var viewer := DeckViewer._open
		check(await _click_button(deck, _booted_viewport), "a real click pressed Close deck")
		await get_tree().process_frame
		check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
				"...and it closed the deck")
		check(deck.text == TRANSLATION.find(&"MAP_DECK"), "...and reads Deck again", deck.text)
		chooser.queue_free()
	await _end_main_fixture()

## The chooser is UI: its cards are drawn at the deck viewer's own size at the window's UI scale, the same on both axes, at both window shapes and whatever the map picture's zoom; harness-scale only.
func test_the_choosers_cards_draw_at_the_ui_size_whatever_the_map_zoom() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		var chooser := await _open_a_pack_chooser()
		if chooser != null:
			var zoom_before := _map.controller.camera.zoom
			_check_cards_at_the_ui_size(_booted_viewport, chooser.cards().controls, "the chooser, %s at the map's fit" % size)
			await _zoom_the_map_under_a_viewer(_main, 3)
			check(not _map.controller.camera.zoom.is_equal_approx(zoom_before),
					"sanity: the map zoomed in at %s" % size,
					"%s -> %s" % [zoom_before, _map.controller.camera.zoom])
			_check_cards_at_the_ui_size(_booted_viewport, chooser.cards().controls, "the chooser, %s with the map zoomed in" % size)
			chooser.queue_free()
			await get_tree().process_frame
		await _end_main_fixture()

func _check_cards_at_the_ui_size(viewport: Viewport, cards: Array, where: String) -> void:
	var content_scale := viewport.get_final_transform().get_scale()
	var visible := viewport.get_visible_rect().size
	check(absf(content_scale.x - content_scale.y) * maxf(visible.x, visible.y) <= 1.0,
			"sanity: the window's UI scale is uniform to a pixel across the window (%s)" % where, str(content_scale))
	var ui := CardVisual.CARD_SIZE * CardVisual.DECK_VIEWER_SCALE * content_scale
	for control : ControlCard in cards:
		var drawn := (viewport.get_final_transform()
				* control.get_global_transform_with_canvas()).basis_xform(control.size)
		check(drawn.is_equal_approx(ui),
				"a listed card is drawn at the UI card size (%s)" % where, "%s vs %s" % [drawn, ui])

## A possible-cards list's icons at the window's UI scale: each its list's one cell, and a part other than a type drawn one art unit per viewer card scale.
func _check_icons_at_the_ui_size(viewport: Viewport, list: DeckViewer, where: String) -> void:
	var content_scale := viewport.get_final_transform().get_scale()
	var cell := list.cards().item_px * content_scale
	var art_unit := CardVisual.DECK_VIEWER_SCALE * content_scale
	check(list.cards().controls.any(func(icon: PartIcon) -> bool: return icon.data.type == null),
			"sanity: the list has a part other than a type to measure in art units (%s)" % where)
	for icon : PartIcon in list.cards().controls:
		var drawn := (viewport.get_final_transform()
				* icon.get_global_transform_with_canvas()).basis_xform(icon.size)
		check(drawn.is_equal_approx(cell),
				"a listed icon is drawn at its list's cell at the UI scale (%s)" % where, "%s vs %s" % [drawn, cell])
		if icon.data.type: continue
		var unit := (viewport.get_final_transform()
				* icon._art.get_global_transform_with_canvas()).get_scale()
		check(unit.is_equal_approx(art_unit),
				"a listed part is drawn one art unit per viewer card scale (%s)" % where, "%s vs %s" % [unit, art_unit])

# ------------------------------------------------------------------ the player's window

# The run's window stays at the project's base size, where the root's content scale is 1 like the
# harness's SubViewport. These rows boot `Main` in a Window stretched as the root is, at the two
# shapes the harness rows use, so each claim is measured at the scale the player actually sees.
func _check_the_players_scale(window: Window, where: String) -> void:
	var scale := window.get_final_transform().get_scale()
	TestLog.line("  %s: content %s drawn at scale %s; the run's own window %s at scale %s" % [where,
			window.get_visible_rect().size, scale, get_tree().root.size,
			get_tree().root.get_final_transform().get_scale()])
	check(not scale.is_equal_approx(Vector2.ONE),
			"sanity: %s draws at a content scale the harness never does" % where, str(scale))

## Every viewer -- possible cards, the run deck, the chooser, the game's Deck, Discard and Rules, the menu picker's Inspect -- draws its cards at the UI size in the player's window's own pixels, at both window shapes.
func test_every_viewer_draws_at_the_ui_size_in_the_players_window() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var where := "the player's window %s" % size
		await _start_map_fixture(size, true)
		var window := _main.get_viewport() as Window
		_check_the_players_scale(window, where)
		await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
		var list := DeckViewer._open
		check(is_instance_valid(list) and list.get_viewport() == window,
				"sanity: the possible-cards list opens in %s" % where)
		if is_instance_valid(list):
			_check_icons_at_the_ui_size(window, list, "possible cards, %s" % where)
			list._close()
			await get_tree().process_frame
		_container.map_deck_button.pressed.emit()
		await get_tree().process_frame
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck.get_viewport() == window,
				"sanity: the map's run deck opens in %s" % where)
		if is_instance_valid(deck):
			_check_cards_at_the_ui_size(window, deck.cards().controls.slice(0, 8), "the run deck, %s" % where)
			deck._close()
			await get_tree().process_frame
		var chooser := await _open_a_pack_chooser()
		if chooser != null:
			_check_cards_at_the_ui_size(window, chooser.cards().controls, "the chooser, %s" % where)
			chooser.queue_free()
			await get_tree().process_frame
		await _end_main_fixture()
		await _start_game_fixture(size, true)
		await _check_the_games_viewers_at_the_ui_size(where)
		await _end_main_fixture()
		var opened := await _open_the_pickers_inspect_viewer(size, true)
		var menu_window := opened[0] as Window
		var viewer := DeckViewer._open
		check(is_instance_valid(viewer) and viewer.get_viewport() == menu_window,
				"sanity: the picker's viewer opens in %s" % where)
		if is_instance_valid(viewer):
			_check_cards_at_the_ui_size(menu_window, viewer.cards().controls.slice(0, 8),
					"the picker's viewer, %s" % where)
		await _end_booted_fixture(menu_window, opened[1] as Main)

## The chooser draws as a window as tall as the parts it holds (no longer a square, visual review round 3), wholly on screen and centred in the space beside the sidebar, in the player's window's own pixels at both window shapes.
func test_the_chooser_fits_its_rows_beside_the_sidebar_in_the_players_window() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var where := "the player's window %s" % size
		await _start_map_fixture(size, true)
		var window := _main.get_viewport() as Window
		_check_the_players_scale(window, where)
		var chooser := await _open_a_pack_chooser()
		if chooser != null:
			_check_the_chooser_holds_its_parts_beside_the_sidebar(chooser, where)
			var drawn := window.get_final_transform() * _chooser_window(chooser)
			var space := window.get_final_transform() * _ui_space(_main)
			var tolerance := CENTRED_TOLERANCE_PX * window.get_final_transform().get_scale().x
			_check_the_chooser_pads_its_rows_as_its_sides(chooser, where)
			check(Rect2(Vector2.ZERO, Vector2(window.size)).grow(tolerance).encloses(drawn),
					"...wholly on screen in %s" % where, "%s in %s" % [drawn, window.size])
			check(drawn.get_center().distance_to(space.get_center()) <= tolerance,
					"...centred in the space beside the sidebar in %s" % where, "%s in %s" % [drawn, space])
			chooser.queue_free()
			await get_tree().process_frame
		await _end_main_fixture()

## The start menu's column draws at exactly the UI scale, centred in the space beside the sidebar the picker slid in to rest, in the player's window's own pixels at both window shapes.
func test_the_menus_column_draws_at_the_ui_scale_beside_the_sidebar_in_the_players_window() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var where := "the player's window %s" % size
		var opened := await _open_the_deck_picker(size, true)
		var window := opened[0] as Window
		var main : Main = opened[1]
		_check_the_players_scale(window, where)
		check(is_equal_approx(main.hud_container.slid_fraction(), 1.0),
				"sanity: the picker's sidebar rests beside the menu in %s" % where)
		var column := Rect2()
		for node : Node in main.menu_scene.get_node(^"Content").find_children("*", "Control", true, false):
			var control := node as Control
			if not (control is Button or control is Label) or not control.is_visible_in_tree():
				continue
			var rect := _menu_control_in_window(window, main._pictures[&"start_menu"], control)
			_check_drawn_at_the_ui_scale(window, rect, control, where)
			column = rect if column.size == Vector2.ZERO else column.merge(rect)
		var space := window.get_final_transform() * _ui_space(main)
		var axis := Vector2.AXIS_Y if HudContainer.container_is_top(window.get_visible_rect().size,
				SettingsManager.settings) else Vector2.AXIS_X
		check(absf(column.get_center()[axis] - space.get_center()[axis])
				<= MENU_CENTRED_TOLERANCE_PX * window.get_final_transform().get_scale()[axis],
				"the menu's column centres in the space beside the resting sidebar in %s" % where,
				"%s in %s" % [column, space])
		await _end_booted_fixture(window, main)

# The space is derived as the harness row derives it: the picture's beside the resting sidebar at the
# COVERING scale, which the picture then overfills. Tolerance: GRID VIEW's `_check_the_set_centred`.
## The board's set of grids is centred across the picture space beside the resting sidebar, as drawn in the player's window's own pixels at both window shapes.
func test_the_board_is_centred_beside_the_resting_sidebar_in_the_players_window() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var where := "the player's window %s" % size
		await _start_game_fixture(size, true)
		var window := _main.get_viewport() as Window
		_check_the_players_scale(window, where)
		_play_area.flush_rebuild()
		await _settle_scroll_x(_play_area)
		check(is_equal_approx(_container.slid_fraction(), 1.0),
				"sanity: the sidebar rests beside the board in %s" % where)
		var game : WallPicture = _main._pictures[&"game"]
		var first := _play_area._cells_root(_play_area.grid_container.get_child(0) as Control)
		var last := _play_area._cells_root(_play_area.grid_container.get_child(-1) as Control)
		var first_drawn := _menu_control_in_window(window, game, first)
		var grids := first_drawn.merge(_menu_control_in_window(window, game, last))
		var authored_px := first_drawn.size.x / first.size.x
		var visible := window.get_visible_rect().size
		var design := Vector2(PlayArea.game_picture_design_size(PlayArea.settings()))
		var picture_scale := maxf(visible.x / design.x, visible.y / design.y)
		var shown := visible / picture_scale
		var left := (design.x - shown.x) / 2.0
		if not HudContainer.container_is_top(visible, PlayArea.settings()):
			left += _container.container_rect().end.x / picture_scale
		var space := _picture_rect_in_window(window, game,
				Rect2(left, 0.0, (design.x + shown.x) / 2.0 - left, design.y))
		check(absf(grids.get_center().x - space.get_center().x) < authored_px,
				"the board's grids centre across the picture space beside the resting sidebar in %s" % where,
				"%s in %s, one authored px %.3f window px; the window's own space beside it %s" % [grids,
				space, authored_px, window.get_final_transform() * _ui_space(_main)])
		await _end_main_fixture()

## The win or lose result centres over the board across the picture, its label and its buttons, and as one block down the space beside the sidebar, and moves with the board as the sidebar slides, centre to centre, in the harness and in the player's window at both window shapes.
func test_the_outcome_centres_over_the_board_resting_and_slid() -> void:
	for in_players_window : bool in [false, true]:
		for size : Vector2i in INSET_WINDOWS:
			var where := "%s %s" % ["the player's window" if in_players_window else "the harness", size]
			await _start_game_fixture(size, in_players_window)
			var view := _main._pictures[&"game"].screen_root as GameView
			await _end_the_show_by_pressing_end(view, in_players_window)
			var screen : Label = view.win_screen if view.win_screen.visible else view.lose_screen
			check(screen.visible and view._outcome_buttons != null, "sanity: the outcome is up in %s" % where)
			var apart : Array[Vector2] = []
			for slide : float in [1.0, 0.0]:
				await _container.slide_to(slide)
				_play_area.flush_rebuild()
				await _settle_scroll_x(_play_area)
				var first := _play_area._cells_root(_play_area.grid_container.get_child(0) as Control)
				var last := _play_area._cells_root(_play_area.grid_container.get_child(-1) as Control)
				var board := first.get_global_rect().merge(last.get_global_rect())
				var authored_px := first.get_global_transform().get_scale().x
				var label := view._outcome_title.get_global_rect()
				var row := view._outcome_buttons.get_global_rect()
				var at := "%s, the sidebar slid to %.0f" % [where, slide]
				check(absf(label.get_center().x - board.get_center().x) < authored_px
						and absf(row.get_center().x - board.get_center().x) < authored_px,
						"the outcome's label and buttons centre across the board in %s" % at,
						"label %s row %s board %s" % [label, row, board])
				apart.append(label.get_center() - board.get_center())
				_check_the_outcome_is_centred_down_its_space(view, at)
			check(apart[0].distance_to(apart[1]) < 1.0,
					"...and the slide moves the outcome as it moves the board, centre to centre, in %s" % where,
					str(apart))
			await _container.slide_to(1.0)
			await _end_main_fixture()

# Measured in the host's own pixels from what is drawn: the label and buttons as one block, against
# the window less the band the sidebar draws over it. The board is reserved at the covering scale
# and drawn overfilled, so under a top band its centre stands half the overfill of the band lower.
func _check_the_outcome_is_centred_down_its_space(view: GameView, at: String) -> void:
	var host := _main.get_viewport()
	var game : WallPicture = _main._pictures[&"game"]
	var block := _menu_control_in_window(host, game, view._outcome_title).merge(
			_menu_control_in_window(host, game, view._outcome_buttons))
	var window := host.get_final_transform() * host.get_visible_rect()
	var sidebar := host.get_final_transform() * _container.get_global_rect()
	var band := 0.0
	if HudContainer.container_is_top(host.get_visible_rect().size, PlayArea.settings()):
		band = maxf(sidebar.end.y - window.position.y, 0.0)
	var centre := window.get_center().y + band / 2.0
	var slack := (PlayArea.settings().wall_overfill_margin - 1.0) * band / 2.0 + 1.0
	check(block.size.y > 0.0 and absf(block.get_center().y - centre) <= slack,
			"the outcome's label and buttons, as one block, centre down the space beside the sidebar in %s" % at,
			"block %s centre y %.1f, the space's %.1f under a band of %.1f in %s, slack %.1f" % [block,
			block.get_center().y, centre, band, window, slack])

## Goal, Total and the board-total-times-combo line are drawn wholly inside the sidebar at a won show's end after a combo pulse, at the show's own values and at long ones, in the harness and in the player's window at both window shapes.
func test_the_score_lines_draw_inside_the_sidebar_at_a_won_show() -> void:
	for in_players_window : bool in [false, true]:
		for size : Vector2i in INSET_WINDOWS:
			var where := "%s %s" % ["the player's window" if in_players_window else "the harness", size]
			await _start_game_fixture(size, in_players_window)
			var view := _main._pictures[&"game"].screen_root as GameView
			await _end_the_show_by_pressing_end(view, in_players_window)
			check(view.win_screen.visible, "sanity: the show is won in %s" % where)
			await get_tree().process_frame
			_check_the_score_lines_through_a_combo_pulse(view, "%s, won" % where)
			_container.goal_label.text = str(LONG_SCORE_TOTAL)
			_container.total_label.text = str(LONG_SCORE_TOTAL)
			await get_tree().process_frame
			_check_the_score_lines_inside_the_sidebar("%s, won at a long Goal and Total" % where)
			view.game.state.goal = LONG_SCORE_TOTAL
			view._refresh_hud()
			_container.combo_label.text = TRANSLATION.find('GAME_SCORE_LINE') % [LONG_SCORE_TOTAL, LONG_SCORE_COMBO]
			await get_tree().process_frame
			_check_the_score_lines_inside_the_sidebar("%s, won at a long score line" % where)
			await _end_main_fixture()

const LONG_SCORE_TOTAL := 9999
const LONG_SCORE_COMBO := 99.99

# A new combo class pulses the score line; the pulse is stepped by hand so its peak is sampled at
# any base_delay, the suite's near-zero one included.
func _check_the_score_lines_through_a_combo_pulse(view: GameView, moment: String) -> void:
	view.game.combo_changed.emit(1)
	var step := view.game.get_delay() / COMBO_PULSE_SAMPLES
	var peak := 1.0
	while view._combo_tween.is_running():
		view._combo_tween.custom_step(step)
		peak = maxf(peak, _container.combo_label.scale.x)
		_check_the_score_lines_inside_the_sidebar("%s, the combo pulse at scale %.3f" % [moment,
				_container.combo_label.scale.x])
	check(peak > 1.0, "sanity: the combo pulse grew the score line in %s" % moment, str(peak))

const COMBO_PULSE_SAMPLES := 20.0

# The drawn text, not the label's box: a Label draws its text from its box's left edge, scaled by
# its own transform, so the box can be wider than the sidebar while its text is not.
func _check_the_score_lines_inside_the_sidebar(moment: String) -> void:
	var sidebar := _container.get_global_rect()
	var inner_left := (_container.goal_label.get_parent().get_node(^"Caption") as Control).get_global_rect().position.x
	var lines : Array[Label] = [_container.goal_label, _container.total_label, _container.combo_label]
	for line : Label in lines:
		var box := line.get_global_rect()
		var text_width := line.get_theme_font(&"font").get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, line.get_theme_font_size(&"font_size")).x * line.get_global_transform().get_scale().x
		var drawn := Rect2(box.position, Vector2(text_width, box.size.y))
		check(drawn.position.x >= inner_left - 0.5 and drawn.end.x <= sidebar.end.x + 0.5,
				"%s: the score line '%s' is drawn inside the sidebar from its inner margin" % [moment, line.text],
				"drawn %s inner left %.1f sidebar %s scale %s pivot %s" % [drawn, inner_left, sidebar,
				line.scale, line.pivot_offset])

## The chooser and the run deck open over it are UI on the sidebar's layer: in wall view neither is drawn nor hears input, and coming back fades both in with the sidebar exactly as they were left.
func test_the_chooser_and_its_deck_are_hidden_in_wall_view_and_back_on_return() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		await _click(chooser.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
		check(await _click_button(_map.selection_deck_button, _booted_viewport),
				"sanity: a real click on the chooser's Deck pressed it")
		await get_tree().process_frame
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck.get_viewport() == _booted_viewport
				and chooser.get_viewport() == _booted_viewport,
				"the chooser and the deck over it are drawn in the window's own viewport, not the map picture",
				"%s / %s" % [chooser.get_viewport(), deck.get_viewport() if is_instance_valid(deck) else null])
		var left_as := _the_chooser_in_progress(chooser)
		var listed := deck.cards().controls.size()
		check(listed > 0, "sanity: the deck over the chooser lists the run deck", str(listed))
		await _click_overlay(&"WallButton")
		await _wait_out_the_move()
		check(_main._current_focus == &"", "sanity: the Wall button reached wall view",
				str(_main._current_focus))
		check(not chooser.is_visible_in_tree() and not deck.margin_container.is_visible_in_tree(),
				"in wall view neither the chooser nor the deck over it is drawn")
		check(not chooser.can_process() and not deck.can_process(),
				"...and neither hears input there")
		await _click_overlay(&"BackButton")
		var mismatch := 0.0
		while _main._move_in_flight or _container.slid_fraction() < 1.0:
			mismatch = maxf(mismatch, absf(chooser.modulate.a - _container.slid_fraction()))
			await get_tree().process_frame
		check(_main._current_focus == &"map" and is_zero_approx(mismatch),
				"coming back, the chooser fades in with the sidebar's slide",
				"focus=%s worst mismatch %s" % [_main._current_focus, mismatch])
		check(chooser.is_visible_in_tree() and is_equal_approx(chooser.modulate.a, 1.0)
				and deck.margin_container.is_visible_in_tree() and not deck.is_queued_for_deletion()
				and chooser.can_process() and deck.can_process(),
				"...and both are back, drawn and answering, the deck still over the chooser")
		check(_the_chooser_in_progress(chooser) == left_as,
				"...the chooser exactly as it was left", "%s vs %s" % [_the_chooser_in_progress(chooser), left_as])
		check(deck.cards().controls.size() == listed
				and deck.flow_container.get_child_count() == listed,
				"...and the deck over it still lists every card it listed before the leave",
				"%d controls, %d children vs %d" % [deck.cards().controls.size(),
				deck.flow_container.get_child_count(), listed])
		deck._close()
		chooser.queue_free()
		await get_tree().process_frame
	await _end_main_fixture()

## Keys and pad stay in the chooser, whose focus lives in the window's own viewport: an arrow walks its cards, the deck opened over it takes the arrows and hands them back on close, and coming back from a leave the first arrow is the chooser's again.
func test_keys_stay_in_the_chooser_on_the_windows_own_viewport() -> void:
	var chooser := await _open_the_chooser_with_pictures_behind_and_ahead()
	check(chooser != null, "sanity: arriving on a pack opened its chooser")
	if chooser != null:
		var cards := chooser.cards().controls
		check(_booted_viewport.gui_get_focus_owner() == chooser.confirm_button,
				"the chooser opens with Take holding the focus in the window's own viewport",
				str(_booted_viewport.gui_get_focus_owner()))
		await _tap_key(KEY_RIGHT)
		check(_booted_viewport.gui_get_focus_owner() == cards[0],
				"the first arrow enters the chooser's first card", str(_booted_viewport.gui_get_focus_owner()))
		await _tap_key(KEY_RIGHT)
		check(_booted_viewport.gui_get_focus_owner() == cards[1] and _map_viewport.gui_get_focus_owner() == null,
				"a second arrow walks to its next card, nothing in the map picture focused",
				"%s / map %s" % [_booted_viewport.gui_get_focus_owner(), _map_viewport.gui_get_focus_owner()])
		await _tap_key(KEY_ENTER)
		check(chooser.cards().sticky == (cards[1] as ControlCard).child.data and _map.selection_deck_button.is_visible_in_tree(),
				"sanity: accept stuck that card, its description offering the deck")
		await _open_viewer_by_accept(_map.selection_deck_button)
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and _booted_viewport.gui_get_focus_owner() == _map.selection_deck_button,
				"the deck opens over the chooser with the focus still on the Deck button that opened it",
				str(_booted_viewport.gui_get_focus_owner()))
		await _tap_key(KEY_DOWN)
		check(is_instance_valid(deck) and deck.cards().focus_is_inside(),
				"...and the next arrow enters the deck on top, not the chooser under it",
				str(_booted_viewport.gui_get_focus_owner()))
		await _tap_key(KEY_ESCAPE)
		check(not is_instance_valid(deck) or deck.is_queued_for_deletion(), "sanity: a cancel closed the deck")
		check(_booted_viewport.gui_get_focus_owner() == _map.selection_deck_button,
				"closing the deck hands the focus back to the Deck button that opened it",
				str(_booted_viewport.gui_get_focus_owner()))
		var walked := await _walk_right_off_the_sidebar(_tap_key.bind(KEY_RIGHT))
		check(walked and chooser.cards().focus_is_inside(),
				"...and Right off the sidebar's inner edge is the chooser's again",
				str(_booted_viewport.gui_get_focus_owner()))
		await _tap_key(KEY_BRACKETLEFT)
		await _wait_out_the_move()
		await _tap_key(KEY_BRACKETRIGHT)
		await _wait_out_the_return()
		check(_main._current_focus == &"map", "sanity: wall_back then wall_forward came back to the map",
				str(_main._current_focus))
		var owner := _booted_viewport.gui_get_focus_owner()
		check(owner == null or chooser.is_ancestor_of(owner),
				"coming back, no control outside the chooser holds the focus", str(owner))
		await _tap_key(KEY_RIGHT)
		check(chooser.cards().focus_is_inside(),
				"...and the first arrow is the chooser's", str(_booted_viewport.gui_get_focus_owner()))
		chooser.queue_free()
		await get_tree().process_frame
	await _end_main_fixture()

## The map's possible-cards list and its run deck are UI: their cards draw at the deck viewer's own size at the window's UI scale, at both window shapes and whatever the map picture's zoom; harness-scale only.
func test_the_maps_viewers_draw_at_the_ui_size_whatever_the_map_zoom() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_map_fixture(size)
		await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
		var list := DeckViewer._open
		check(is_instance_valid(list) and list.get_viewport() == _booted_viewport,
				"the possible-cards list opens in the window's own viewport at %s" % size,
				str(list.get_viewport() if is_instance_valid(list) else null))
		if is_instance_valid(list):
			var zoom_before := _map.controller.camera.zoom
			_check_icons_at_the_ui_size(_booted_viewport, list, "possible cards, %s at the fit" % size)
			await _zoom_the_map_under_a_viewer(_main, 3)
			check(not _map.controller.camera.zoom.is_equal_approx(zoom_before),
					"sanity: the map zoomed in under the list at %s" % size)
			_check_icons_at_the_ui_size(_booted_viewport, list, "possible cards, %s zoomed in" % size)
			list._close()
			await get_tree().process_frame
		_container.map_deck_button.pressed.emit()
		await get_tree().process_frame
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck.get_viewport() == _booted_viewport,
				"the map's run deck opens in the window's own viewport at %s" % size)
		if is_instance_valid(deck):
			_check_cards_at_the_ui_size(_booted_viewport, deck.cards().controls.slice(0, 8), "the run deck, %s" % size)
			deck._close()
			await get_tree().process_frame
		await _end_main_fixture()

## The run deck open over a possible-cards list with a stuck card: in wall view neither is drawn nor hears input, and coming back finds the stack as it was left -- both listing every card, the deck on top, the list's card still stuck -- and it unwinds as before the leave.
func test_the_maps_viewer_stack_is_hidden_in_wall_view_and_back_on_return() -> void:
	var list := await _stick_a_possible_card()
	var stuck := list.cards().sticky
	check(await _click_button(_map.selection_deck_button, _booted_viewport),
			"sanity: a real click pressed the stuck card's Deck")
	await get_tree().process_frame
	var deck := DeckViewer._open
	check(is_instance_valid(deck) and deck != list, "sanity: the run deck opened over the list")
	if is_instance_valid(deck) and deck != list:
		var counts := [list.cards().controls.size(), deck.cards().controls.size()]
		await _click_overlay(&"WallButton")
		await _wait_out_the_move()
		check(_main._current_focus == &"", "sanity: the Wall button reached wall view",
				str(_main._current_focus))
		check(not list.margin_container.is_visible_in_tree() and not deck.margin_container.is_visible_in_tree()
				and not list.can_process() and not deck.can_process(),
				"in wall view neither the list nor the deck over it is drawn or hears input")
		await _click_overlay(&"BackButton")
		await _wait_out_the_return()
		check(_main._current_focus == &"map" and list.margin_container.is_visible_in_tree()
				and deck.margin_container.is_visible_in_tree() and list.can_process() and deck.can_process(),
				"coming back, both are drawn and answering again", str(_main._current_focus))
		check([list.cards().controls.size(), deck.cards().controls.size()] == counts
				and DeckViewer._open == deck and list.cards().sticky == stuck,
				"...the deck still on top, both listing every card, the list's card still stuck",
				"%s vs %s, open %s" % [[list.cards().controls.size(), deck.cards().controls.size()],
				counts, DeckViewer._open])
		check(_previewed_card() == stuck and not _exit_button().visible,
				"...the sidebar back on the list's stuck card, with no X while the deck is over it",
				"shown=%s x=%s" % [_described_title(), _exit_button().visible])
		await _tap_key(KEY_ESCAPE)
		check(DeckViewer._open == list and list.cards().sticky == stuck and _container.is_locked()
				and _previewed_card() == stuck and _exit_button().visible,
				"a cancel closes only the deck: the list's stuck card is back, described, with its X",
				"open=%s sticky=%s locked=%s shown=%s x=%s" % [DeckViewer._open, list.cards().sticky,
				_container.is_locked(), _described_title(), _exit_button().visible])
		var warnings := _FocusWarnings.new()
		OS.add_logger(warnings)
		await _tap_key(KEY_ESCAPE)
		OS.remove_logger(warnings)
		check(not is_instance_valid(list) or list.is_queued_for_deletion(),
				"the next cancel unsticks and closes the list together")
		check(_hud_is_up(), "...leaving the sidebar on the HUD, no pick having survived the leave",
				_described_title())
		check(warnings.count == 0,
				"...its opener gone with the pick and no X up, it hands the focus to no control off screen",
				"%d \"can't grab focus\" warnings" % warnings.count)
	await _end_main_fixture()

# A CARD STUCK IN A PACK'S POSSIBLE CARDS OFFERS THE RUN DECK; one merely hovered offers nothing,
# and closing the list sets the pick's whole row back.
func test_a_card_stuck_in_the_possible_cards_carries_only_the_deck_row() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: the first pick listed the pack")
	var at := viewer.cards().controls[0].get_global_rect().get_center()
	_hover_in(_booted_viewport, at)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_container.showing_description() and not _map.selection_buttons.is_visible_in_tree(),
			"a hovered possible card is described with no row",
			"described=%s row=%s" % [_container.showing_description(),
			_map.selection_buttons.is_visible_in_tree()])
	await _click(at, _booted_viewport)
	await get_tree().process_frame
	check(viewer.cards().sticky != null, "sanity: a click stuck the possible card")
	check(_map.selection_deck_button.is_visible_in_tree()
			and not _map.travel_button.is_visible_in_tree()
			and not _map.possible_cards_button.is_visible_in_tree(),
			"a stuck possible card carries the row with Deck only",
			"deck=%s travel=%s possible=%s" % [_map.selection_deck_button.is_visible_in_tree(),
			_map.travel_button.is_visible_in_tree(), _map.possible_cards_button.is_visible_in_tree()])
	await _close_the_open_viewer()
	check(_map.travel_button.visible and _map.selection_deck_button.visible
			and _map.possible_cards_button.visible,
			"closing the list restores the pick's whole row, not the Deck-only one",
			"travel=%s deck=%s possible=%s" % [_map.travel_button.visible,
			_map.selection_deck_button.visible, _map.possible_cards_button.visible])
	await _end_main_fixture()

# The owner's "Open over the list": the run deck opens OVER the possible cards, the row stays up
# reading Close deck, and closing the deck -- by Close deck, a cancel or a click outside it -- finds
# the list still open with its card still stuck.
func test_deck_from_a_stuck_possible_card_opens_over_the_list() -> void:
	for close : String in ["Close deck", "a cancel", "a click outside the deck", "the deck's tab"] \
			as Array[String]:
		var list := await _stick_a_possible_card()
		var stuck := list.cards().sticky
		check(await _click_button(_map.selection_deck_button, _booted_viewport),
				"a real click pressed the stuck card's Deck (%s)" % close)
		await get_tree().process_frame
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck != list and deck.deck == Main.save_info.card_datas,
				"Deck from a stuck possible card opens the run deck (%s)" % close, str(deck))
		check(is_instance_valid(list) and not list.is_queued_for_deletion()
				and list.cards().sticky == stuck,
				"...OVER the list, which stays open with its card still stuck (%s)" % close)
		check(_map.selection_deck_button.is_visible_in_tree()
				and _map.selection_deck_button.text == TRANSLATION.find(&"MAP_CLOSE_DECK"),
				"...and the row stays up reading Close deck (%s)" % close,
				"visible=%s text=%s" % [_map.selection_deck_button.is_visible_in_tree(),
				_map.selection_deck_button.text])
		match close:
			"Close deck":
				check(await _click_button(_map.selection_deck_button, _booted_viewport),
						"a real click pressed Close deck")
			"a cancel": await _tap_key(KEY_ESCAPE)
			"the deck's tab": await _click_the_open_viewers_tab(_booted_viewport)
			_: await _click_outside_the_map_viewer()
		await get_tree().process_frame
		check(not is_instance_valid(deck) or deck.is_queued_for_deletion(),
				"%s closes the run deck" % close)
		check(is_instance_valid(list) and not list.is_queued_for_deletion()
				and list.cards().sticky == stuck and DeckViewer._open == list,
				"...and only the deck: the list is back on top, its card still stuck (%s)" % close,
				"list=%s open=%s" % [is_instance_valid(list) and not list.is_queued_for_deletion(),
				DeckViewer._open])
		check(is_instance_valid(list) and _close_tab_of(list) != null
				and _close_tab_of(list).is_visible_in_tree(),
				"...still carrying its own close tab (%s)" % close)
		check(_container.is_locked() and _previewed_card() == stuck and _exit_button().visible,
				"...its stuck card described, with its X (%s)" % close,
				"locked=%s shown=%s x=%s" % [_container.is_locked(), _described_title(),
				_exit_button().visible])
		check(_map.selection_deck_button.is_visible_in_tree()
				and not _map.travel_button.is_visible_in_tree()
				and _map.selection_deck_button.text == TRANSLATION.find(&"MAP_DECK"),
				"...and the row back to Deck only, reading Deck (%s)" % close,
				"deck=%s travel=%s text=%s" % [_map.selection_deck_button.is_visible_in_tree(),
				_map.travel_button.is_visible_in_tree(), _map.selection_deck_button.text])
		await _end_main_fixture()

# The owner's "Back to the pick": closing the list with one of its cards stuck -- a click outside,
# a cancel or its X -- comes back to the pack node's description with Travel live.
func test_closing_the_possible_cards_with_a_card_stuck_returns_to_the_pick() -> void:
	for close : String in ["a click outside", "a cancel", "its X", "its tab"] as Array[String]:
		var list := await _stick_a_possible_card()
		var pack := _map.controller.selected()
		match close:
			"a click outside": await _click_outside_the_map_viewer()
			"a cancel": await _tap_key(KEY_ESCAPE)
			"its tab": await _click_the_open_viewers_tab(_booted_viewport)
			_: check(await _click_button(_exit_button(), _booted_viewport), "a real click pressed the X")
		await get_tree().process_frame
		check(not is_instance_valid(list) or list.is_queued_for_deletion(),
				"sanity: %s closed the possible cards" % close)
		var pick_title := _map._info_for(pack).title
		check(_map.controller.selected() == pack and _described_title() == pick_title,
				"closing the list by %s with a card stuck comes back to the pack node" % close,
				"selected=%s shown=%s want=%s" % [_map.controller.selected() == pack,
				_described_title(), pick_title])
		check(not _container.is_locked(), "...its stuck card let go (%s)" % close)
		check(await _click_button(_map.travel_button, _booted_viewport),
				"...with Travel visible and a real click pressing it (%s)" % close)
		await _see_the_travel_through()
		await _end_main_fixture()

# The same by keys alone: Right enters the list, accept sticks, Left off it reaches the X and Left
# again the row's Deck, accept opens the deck over the list, Left off the deck comes back to Close deck, accept again closes
# it, a cancel closes the deck only, and the next cancel closes the list back to the pick.
func test_the_deck_over_the_possible_cards_by_keys_alone() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	var pack := _map.controller.selected()
	var list := DeckViewer._open
	check(is_instance_valid(list), "sanity: the first pick listed the pack")
	await _tap_key(KEY_RIGHT)
	check(list.cards().controls[0].has_focus(), "sanity: Right enters the list's first card",
			str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_ENTER)
	var stuck := list.cards().sticky
	check(stuck != null and _container.is_locked(), "sanity: accept stuck the focused card")
	var deck_row := _map.selection_deck_button
	await _walk_by([_tap_key.bind(KEY_LEFT)] as Array[Callable], [_exit_button()] as Array[Control],
			"Left off the list's edge reaches the stuck card's X")
	for close : Key in [KEY_ENTER, KEY_ESCAPE] as Array[Key]:
		var route := "accept on Close deck" if close == KEY_ENTER else "a cancel"
		var by_keys := close == KEY_ENTER
		var left : Callable = _tap_key.bind(KEY_LEFT) if by_keys else _tap_pad.bind(JOY_BUTTON_DPAD_LEFT)
		var right : Callable = _tap_key.bind(KEY_RIGHT) if by_keys else _tap_pad.bind(JOY_BUTTON_DPAD_RIGHT)
		var down : Callable = _tap_key.bind(KEY_DOWN) if by_keys else _tap_pad.bind(JOY_BUTTON_DPAD_DOWN)
		if by_keys:
			await _walk_by([left] as Array[Callable], [deck_row] as Array[Control],
					"Left from the X reaches the stuck card's Deck row (%s)" % route)
		else:
			await _walk_by([right, left] as Array[Callable], [_exit_button(), deck_row] as Array[Control],
					"from the Deck row to the X and back (%s)" % route)
		await _tap_key(KEY_ENTER)
		var deck := DeckViewer._open
		check(is_instance_valid(deck) and deck != list and is_instance_valid(list)
				and not list.is_queued_for_deletion() and list.cards().sticky == stuck,
				"accept on Deck opens the run deck over the list, its card still stuck (%s)" % route)
		check(deck_row.text == TRANSLATION.find(&"MAP_CLOSE_DECK"),
				"...the row reading Close deck (%s)" % route, deck_row.text)
		if is_instance_valid(deck) and deck != list and deck.cards().controls.size() > 0:
			await _walk_by([down, left] as Array[Callable],
					[deck.cards().controls[0], deck_row] as Array[Control],
					"into the deck over the stuck possible card and Left back to Close deck (%s)" % route)
			check(_previewed_card() == stuck,
					"...the stuck possible card described again (%s)" % route, _described_title())
		await _tap_key(close)
		check(not is_instance_valid(deck) or deck.is_queued_for_deletion(),
				"%s closes the run deck" % route)
		check(is_instance_valid(list) and DeckViewer._open == list and list.cards().sticky == stuck
				and _container.is_locked() and _previewed_card() == stuck and _exit_button().visible,
				"...and only the deck: the list's stuck card is back, described, with its X (%s)" % route,
				"open=%s shown=%s x=%s" % [DeckViewer._open, _described_title(), _exit_button().visible])
	await _tap_key(KEY_ESCAPE)
	check(not is_instance_valid(list) or list.is_queued_for_deletion(),
			"the next cancel closes the list")
	check(_described_title() == _map._info_for(pack).title,
			"...back to the pack node's description", _described_title())
	var travel := _map.travel_button
	var possible := _map.possible_cards_button
	check(possible.has_focus() and possible.get_global_rect().position.y
			> travel.get_global_rect().end.y,
			"sanity: the list's close rests on Possible cards, wrapped under Travel and Deck at %s -- the walk below leans on that wrap" % _booted_viewport.size,
			"%s at %s, Travel at %s" % [_booted_viewport.gui_get_focus_owner(),
			possible.get_global_rect(), travel.get_global_rect()])
	await _walk_by([_tap_key.bind(KEY_RIGHT), _tap_key.bind(KEY_LEFT)] as Array[Callable],
			[deck_row, travel] as Array[Control], "...with Travel in the keys' reach")
	var presses : Array[int] = [0]
	travel.pressed.connect(func() -> void: presses[0] += 1, CONNECT_ONE_SHOT)
	await _tap_key(KEY_ENTER)
	check(presses[0] == 1, "...and accept on it travels")
	await _see_the_travel_through()
	await _end_main_fixture()

## A third window width, its whole-column count differing from both inset windows'.
const OTHER_COLUMNS_WINDOW := Vector2i(1360, 720)

## The run deck opened over a pack's possible cards hides the whole list under it: every viewer lays out the card's one column width, so the deck's opaque window is the list's exactly -- in the harness by real clicks, and in the player's window at both shapes and where wider cells once differed.
func test_the_deck_over_the_possible_cards_hides_the_whole_list() -> void:
	var list := await _stick_a_possible_card()
	check(await _click_button(_map.selection_deck_button, _booted_viewport),
			"sanity: a real click on the stuck part's Deck pressed it")
	await _check_the_deck_covers(list, "the harness")
	for size : Vector2i in INSET_WINDOWS + ([OTHER_COLUMNS_WINDOW] as Array[Vector2i]):
		await _start_map_fixture(size, true)
		await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
		var listed := DeckViewer._open
		listed.cards().stick_to((listed.cards().controls[0] as PartIcon).data)
		_map.selection_deck_button.pressed.emit()
		await _check_the_deck_covers(listed, "the player's window %s" % size)

## Checks the deck just opened over `list` draws the list's own window, then closes both and ends the fixture.
func _check_the_deck_covers(list: DeckViewer, where: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var deck := DeckViewer._open
	check(is_instance_valid(deck) and deck != list, "sanity: the run deck opened over the list (%s)" % where)
	if is_instance_valid(deck) and deck != list:
		var over := _backdrop_of(deck).get_global_rect()
		var under := _backdrop_of(list).get_global_rect()
		check(over.is_equal_approx(under),
				"the run deck's opaque backdrop is the same whole window as the possible-cards list's under it (%s)" % where,
				"%s over %s" % [over, under])
		deck._close()
		await get_tree().process_frame
	if is_instance_valid(list): list._close()
	await get_tree().process_frame
	await _end_main_fixture()

## The chooser's window pads its first row above and its Rerolls-and-Take row below as it pads its sides, so it is exactly as tall as what it holds.
func _check_the_chooser_pads_its_rows_as_its_sides(chooser: ChoiceViewer, where: String) -> void:
	var window := chooser._layout.get_global_rect()
	var first := chooser._cards.controls[0].get_global_rect()
	var foot := chooser._bottom_row.get_global_rect()
	var side := first.position.x - window.position.x
	var above := first.position.y - window.position.y
	var below := window.end.y - foot.end.y
	check(absf(above - side) <= 1.0 and absf(below - side) <= 1.0,
			"the chooser is as tall as what it holds, padded above and below as at its sides, in %s" % where,
			"above %.2f below %.2f side %.2f" % [above, below, side])

## The opaque backdrop `viewer` draws its window in.
func _backdrop_of(viewer: DeckViewer) -> ColorRect:
	return viewer.margin_container.get_node(^"ColorRect") as ColorRect

## A pack node picked and its first possible card clicked stuck, through the product's own routes.
func _stick_a_possible_card() -> DeckViewer:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	var list := DeckViewer._open
	check(is_instance_valid(list), "sanity: the first pick listed the pack")
	await _click(list.cards().controls[0].get_global_rect().get_center(), _booted_viewport)
	await get_tree().process_frame
	check(list.cards().sticky != null and _map.selection_deck_button.is_visible_in_tree(),
			"sanity: a click stuck a possible card, its Deck on the row")
	return list

## A click on the far corner of the map as shown beside the sidebar, outside every card a map viewer lists.
func _click_outside_the_map_viewer() -> void:
	var shown := DeckViewer._open.margin_container.get_global_rect()
	await _click(shown.end - Vector2.ONE, _booted_viewport)

## The title the sidebar shows, or "HUD" while the description is down.
func _described_title() -> String:
	if not _container.showing_description() or _panel.current_entry == null: return "HUD"
	return _panel.current_entry.title

# ------------------------------------------------------------------ the viewer's close tab

## The close tab `viewer` carries on its window's side, or null while it carries none.
func _close_tab_of(viewer: DeckViewer) -> Button:
	return viewer.get_node_or_null(^"%CloseTab") as Button

## A real click on the close tab of the viewer on top, in the picture it is drawn in.
func _click_the_open_viewers_tab(viewport: SubViewport) -> void:
	var tab := _close_tab_of(DeckViewer._open)
	check(tab != null, "the viewer on top carries a close tab to click")
	if tab == null: return
	check(await _click_button(tab, viewport), "a real click on the viewer's close tab pressed it")

## The mouse: a click on the tab closes the viewer, and the focus goes back where every close sends it.
func test_a_click_on_the_viewers_close_tab_closes_it() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	await _open_viewer_by_accept(deck)
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: accept on Deck opened the deck viewer")
	await _click_the_open_viewers_tab(_booted_viewport)
	await get_tree().process_frame
	check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
			"a click on the close tab closes the viewer")
	check(_hud_is_up() and deck.has_focus(),
			"...back to the HUD with the focus on the button that opened it",
			"hud=%s focus=%s" % [_hud_is_up(), _booted_viewport.gui_get_focus_owner()])
	await _end_main_fixture()

# ONE DEVICE REACHES AND PRESSES THE TAB: Right off the sidebar enters the list, Right on along the row
# lands on the tab sticking out of that side, Left goes back into the list, and accept on the tab
# closes the viewer -- the keyboard's arrows and Enter, and the pad's d-pad and A.
func test_the_viewers_close_tab_by_keys_or_pad_alone() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	var devices : Array[Array] = [
		["keys", _tap_key.bind(KEY_RIGHT), _tap_key.bind(KEY_LEFT), _tap_key.bind(KEY_ENTER)],
		["the pad", _tap_pad.bind(JOY_BUTTON_DPAD_RIGHT), _tap_pad.bind(JOY_BUTTON_DPAD_LEFT),
				_tap_pad.bind(JOY_BUTTON_A)],
	]
	for device : Array in devices:
		var by : String = device[0]
		var right : Callable = device[1]
		_container.show_hud()
		await _open_viewer_by_accept(deck)
		var viewer := DeckViewer._open
		var tab := _close_tab_of(viewer) if is_instance_valid(viewer) else null
		check(tab != null, "the deck viewer opened by accept carries a close tab (%s)" % by)
		if tab == null:
			await _close_the_open_viewer()
			continue
		var cards := viewer.cards().controls
		var walked := await _walk_right_off_the_sidebar(right)
		check(walked and cards[0].has_focus(),
				"sanity: Right off the sidebar's inner edge enters the list (%s)" % by,
				str(_booted_viewport.gui_get_focus_owner()))
		for step : int in cards.size():
			if tab.has_focus(): break
			await right.call()
		check(tab.has_focus(), "Right off the list's right edge lands on the close tab (%s)" % by,
				str(_booted_viewport.gui_get_focus_owner()))
		await (device[2] as Callable).call()
		var back := _booted_viewport.gui_get_focus_owner() as ControlCard
		check(back != null and cards.has(back),
				"...Left from the tab goes back into the list (%s)" % by,
				str(_booted_viewport.gui_get_focus_owner()))
		await right.call()
		check(tab.has_focus(), "...and Right comes back to the tab (%s)" % by,
				str(_booted_viewport.gui_get_focus_owner()))
		await (device[3] as Callable).call()
		check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
				"accept on the tab closes the viewer (%s)" % by)
		check(deck.has_focus(), "...handing the focus back to the button that opened it (%s)" % by,
				str(_booted_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

# THE TAB STICKS OUT OF THE WINDOW'S RIGHT SIDE, a touch target across, inside the visible picture
# and clear of the sidebar and of every listed card -- at the side window and the top band alike.
func test_the_viewers_close_tab_sticks_out_clear_of_the_sidebar_and_its_cards() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_game_fixture(size)
		var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		var tab := _close_tab_of(DeckViewer._open)
		check(tab != null and tab.is_visible_in_tree(),
				"the open deck viewer shows a close tab (%s)" % size)
		if tab != null:
			var at := tab.get_global_rect()
			var frame := (DeckViewer._open.margin_container.get_node(^"ColorRect") as Control) \
					.get_global_rect()
			check(absf(at.position.x - frame.end.x) <= 1.0 and at.position.y >= frame.position.y - 1.0
					and at.position.y < frame.end.y,
					"...sticking out of the window's right side, attached to it (%s)" % size,
					"tab %s window %s" % [at, frame])
			var beside := _container.resting_rect_beside(null)
			check(beside.encloses(at),
					"...inside the window and clear of the sidebar (%s)" % size,
					"tab %s beside %s" % [at, beside])
			var scroll := DeckViewer._open.flow_container.get_parent() as Control
			var covered : Array[Rect2] = []
			for card : ControlCard in cards:
				if card.get_global_rect().intersects(at): covered.append(card.get_global_rect())
			check(not scroll.get_global_rect().intersects(at) and covered.is_empty(),
					"...and over none of the viewer's cards (%s)" % size,
					"tab %s list %s covered %s" % [at, scroll.get_global_rect(), covered])
			var window : Vector2 = _container.get_viewport().get_visible_rect().size
			var target := WallInput.touch_target_px(window, SettingsManager.settings)
			var across := minf(at.size.x, at.size.y)
			check(across >= target - 0.5,
					"...at least one touch target across, in window pixels (%s)" % size,
					"%.1f vs %.1f" % [across, target])
		await _end_main_fixture()

## A drawn pixel within this of its role's colour IS that colour: a translucent fill blends with what is under it and lands farther off.
const OPAQUE_COLOUR_TOLERANCE := 0.02

## Read off the booted window's own pixels, each kind opened by its product route: every overlay window kind draws its own opaque colour, told apart from each other and the sidebar, and a viewer's X tab is solid.
func test_every_window_kind_draws_its_own_opaque_colour() -> void:
	var kinds : Array[StringName] = [&"hud_background", &"viewer_deck", &"viewer_discard",
			&"viewer_rules", &"viewer_possible_cards", &"viewer_pack", &"viewer_inspect",
			&"deck_picker", &"close_tab"]
	for i : int in kinds.size():
		for j : int in range(i + 1, kinds.size()):
			var a := PaletteDB.ROLES.color_of(kinds[i])
			var b := PaletteDB.ROLES.color_of(kinds[j])
			check(_colour_distance(a, b) > 0.1, "%s and %s are told apart" % [kinds[i], kinds[j]],
					"%s vs %s" % [a, b])
	await _start_game_fixture()
	var piles : Dictionary[StringName, Button] = {
		&"viewer_deck": _container.deck_ui.get_node(^"Button") as Button,
		&"viewer_discard": _container.discard_ui.get_node(^"Button") as Button,
		&"viewer_rules": _container.rules_ui.get_node(^"Button") as Button,
	}
	for role : StringName in piles:
		_container.show_hud()
		await _open_viewer_by_accept(piles[role])
		await _check_the_open_viewer_draws(role)
		await _close_the_open_viewer()
	var sidebar := _drawn_in_window(_booted_viewport, _container)
	await _check_drawn_in(sidebar.position + Vector2(4.0, sidebar.size.y - 4.0), &"hud_background",
			"the sidebar")
	await _end_main_fixture()
	var list := await _stick_a_possible_card()
	await _check_the_open_viewer_draws(&"viewer_possible_cards")
	check(await _click_button(_map.selection_deck_button, _booted_viewport),
			"sanity: a real click on the stuck part's Deck pressed it")
	await get_tree().process_frame
	await get_tree().process_frame
	check(DeckViewer._open != list, "sanity: the run deck opened over the list")
	await _check_the_open_viewer_draws(&"viewer_deck")
	await _end_main_fixture()

## The viewer on top draws its window in `role` and its X tab solid in the tab's role.
func _check_the_open_viewer_draws(role: StringName) -> void:
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: a viewer is open for %s" % role)
	if not is_instance_valid(viewer): return
	var window := _drawn_in_window(_booted_viewport, _backdrop_of(viewer))
	await _check_drawn_in(window.position + Vector2.ONE * 4.0, role, "the %s window" % role)
	var tab := _drawn_in_window(_booted_viewport, viewer.close_tab)
	await _check_drawn_in(tab.position + Vector2.ONE * 2.0, &"close_tab", "the %s window's X tab" % role)

func _check_drawn_in(at: Vector2, role: StringName, what: String) -> void:
	_booted_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var seen := _booted_viewport.get_texture().get_image().get_pixelv(Vector2i(at))
	var wanted := PaletteDB.ROLES.color_of(role)
	check(_colour_distance(seen, wanted) < OPAQUE_COLOUR_TOLERANCE,
			"%s draws solid %s" % [what, role], "%s at %s vs %s" % [seen, at, wanted])

# EVERY OPENER IS ALSO ITS VIEWER'S CLOSER and says so while it is open, on either screen.
func test_every_pile_opener_reads_close_while_its_viewer_is_open() -> void:
	await _start_map_fixture()
	await _check_the_opener_reads_close(_container.map_deck_button, &"MAP_CLOSE_DECK")
	await _end_main_fixture()
	await _start_game_fixture()
	for pile : Control in [_container.deck_ui, _container.discard_ui, _container.rules_ui] as Array[Control]:
		var close_key : StringName = {_container.deck_ui: &"GAME_CLOSE_DECK",
				_container.discard_ui: &"GAME_CLOSE_DISCARD", _container.rules_ui: &"GAME_CLOSE_RULES"}[pile]
		await _check_the_opener_reads_close(pile.get_node(^"Button") as Button, close_key)
	await _end_main_fixture()

func _check_the_opener_reads_close(opener: Button, close_key: StringName) -> void:
	var open_text := opener.text
	check(await _click_button(opener, _booted_viewport), "a real click pressed %s" % open_text)
	await get_tree().process_frame
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer) and not viewer.is_queued_for_deletion(),
			"sanity: %s opened its viewer" % open_text)
	check(opener.text == TRANSLATION.find(close_key) and opener.text != String(close_key),
			"with its viewer open, %s reads %s" % [open_text, close_key], opener.text)
	check(await _click_button(opener, _booted_viewport), "a real click pressed %s" % opener.text)
	await get_tree().process_frame
	check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
			"...and it closed the viewer %s opened" % open_text)
	check(opener.text == open_text, "...and reads %s again" % open_text, opener.text)

# One device end to end: accept on the map hands the pad the row, Up reaches the X above it, and
# Down from the X comes back into the row, so every row button and the X are one walk.
func test_a_keyboard_reaches_every_row_button_from_the_x() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	await _close_the_open_viewer()
	_push_key(_map_viewport, KEY_ENTER, true)
	_push_key(_map_viewport, KEY_ENTER, false)
	await get_tree().process_frame
	var visited : Array[Control] = [_booted_viewport.gui_get_focus_owner()]
	check(visited[0] == _map.travel_button, "sanity: accept on the map hands the pad Travel",
			str(visited[0]))
	for keycode : Key in [KEY_RIGHT, KEY_DOWN] as Array[Key]:
		await _tap_key(keycode)
		visited.append(_booted_viewport.gui_get_focus_owner())
	var names : Array[String] = []
	for control : Control in visited:
		names.append((control as Button).text if control is Button else str(control))
	for button : Button in _map.selection_buttons.get_children():
		check(button in visited, "Right then Down from Travel reaches %s" % button.text,
				", ".join(names))
	await _tap_key(KEY_UP)
	check(_booted_viewport.gui_get_focus_owner() == _exit_button(),
			"Up from the row reaches the X", str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_DOWN)
	var below := _booted_viewport.gui_get_focus_owner()
	check(below != null and below.get_parent() == _map.selection_buttons,
			"...and Down from the X comes back into the row", str(below))
	await _end_main_fixture()

## A game deck viewer the player left open behind the overlay's Back is the game's alone: on the map the Deck button, a pack's first pick and an arrow each behave exactly as with no viewer anywhere, and Forward finds the game sane.
func test_a_game_viewer_left_open_across_back_changes_nothing_on_the_map() -> void:
	for route : String in ["the map's Deck button", "a pack node's first pick", "an arrow"]:
		await _start_game_fixture()
		_container.show_hud()
		await get_tree().process_frame
		var game_deck := _container.deck_ui.get_node(^"Button") as Button
		check(await _click_button(game_deck, _booted_viewport),
				"sanity: a real click on the game's Deck opened its viewer (%s)" % route)
		await get_tree().process_frame
		var game_viewer := DeckViewer._open
		var listed := _listed_viewer_cards()
		check(not listed.is_empty(), "sanity: the game's deck viewer lists cards (%s)" % route)
		if listed.is_empty():
			await _end_main_fixture()
			continue
		await _click(listed[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked(), "sanity: a click stuck a game deck card (%s)" % route)
		await _back_to_the_map_with_the_show_frozen()
		check(is_instance_valid(game_viewer) and not game_viewer.is_queued_for_deletion(),
				"sanity: Back left the game's viewer open behind the map (%s)" % route)
		await _check_the_map_ignores_the_game_viewer(route)
		if route == "an arrow":
			var pack_picked : bool = _map.controller.selected() != null \
					and _map.controller.selected().meta.get(MapNodeRoles.ROLE_KEY, "") == MapNodeRoles.ROLE_BOOSTER
			var still_open := is_instance_valid(game_viewer) and not game_viewer.is_queued_for_deletion()
			check(still_open != pack_picked,
					"the arrow's pick closes the game's viewer exactly when it is a pack, whose possible cards open in its place",
					"pack picked=%s viewer open=%s" % [pack_picked, still_open])
		await _click_overlay(&"ForwardButton")
		await _wait_out_the_move()
		await get_tree().process_frame
		check(_main._current_focus == &"game", "sanity: Forward went back to the show (%s)" % route,
				str(_main._current_focus))
		if is_instance_valid(game_viewer) and not game_viewer.is_queued_for_deletion():
			check(_container.is_locked() and _exit_button().visible,
					"Forward onto the viewer nothing closed finds its stuck card as it was left (%s)" % route)
			await _tap_key(KEY_RIGHT)
			check(game_viewer.cards().focus_is_inside(),
					"...and an arrow there still walks that viewer (%s)" % route)
		else:
			check(_hud_is_up() and not _container.is_locked(),
					"Forward after the map closed the game's viewer finds the game on its HUD, nothing stuck (%s)" % route,
					"locked=%s hud=%s" % [_container.is_locked(), _hud_is_up()])
			var rested := _game_viewport.gui_get_focus_owner()
			check(_play_area.ui_data.has(rested),
					"...its board focus rested on a board card, as an ordinary Back and Forward leaves it (%s)" % route,
					str(rested))
			var map_viewer := DeckViewer._open
			await _tap_key(KEY_RIGHT)
			check(is_instance_valid(map_viewer) and not map_viewer.cards().focus_is_inside(),
					"...and an arrow there is not taken by the map's viewer left open behind it (%s)" % route)
			var moved := _game_viewport.gui_get_focus_owner()
			check(_play_area.ui_data.has(moved) and moved != rested
					and moved.get_viewport() == _game_viewport,
					"...but moves the board focus, in the game's own viewport (%s)" % route,
					"%s -> %s" % [rested, moved])
		await _end_main_fixture()

## Deck, Discard and Rules are UI: each opens in the window's own viewport and draws its cards at the deck viewer's own size at the window's UI scale, at both window shapes; harness-scale only.
func test_the_games_viewers_draw_at_the_ui_size_at_both_window_shapes() -> void:
	for size : Vector2i in INSET_WINDOWS:
		await _start_game_fixture(size)
		await _check_the_games_viewers_at_the_ui_size(str(size))
		await _end_main_fixture()

# Deck, Discard and Rules opened on the game fixture, each in the fixture's own window.
func _check_the_games_viewers_at_the_ui_size(where: String) -> void:
	var state := _fixture_game().state
	state.discard_deck.append_array(state.all_stock_cards().slice(0, 2))
	for pile : Control in [_container.deck_ui, _container.discard_ui, _container.rules_ui] as Array[Control]:
		var cards := await _open_viewer_cards(pile.get_node(^"Button") as Button)
		var viewer := DeckViewer._open
		check(is_instance_valid(viewer) and viewer.get_viewport() == _main.get_viewport()
				and not cards.is_empty(),
				"the %s viewer opens in the window's own viewport at %s" % [pile.name, where],
				str(viewer.get_viewport() if is_instance_valid(viewer) else null))
		_check_cards_at_the_ui_size(_main.get_viewport(), cards.slice(0, 8), "the %s viewer, %s" % [pile.name, where])
		await _close_the_open_viewer()

## A game viewer with a card stuck is UI on the sidebar's layer: in wall view it is neither drawn nor hears input, and coming back fades it in with the sidebar as it was left -- its card stuck, described, with its X -- and a cancel closes it back to its opener.
func test_a_game_viewer_is_hidden_in_wall_view_and_back_on_return() -> void:
	await _start_game_fixture()
	var deck := _container.deck_ui.get_node(^"Button") as Button
	_container.show_hud()
	var cards := await _open_viewer_cards(deck)
	var viewer := DeckViewer._open
	check(cards.size() >= 2, "sanity: the game's deck viewer lists cards", str(cards.size()))
	if cards.size() >= 2:
		await _click(cards[1].get_global_rect().get_center(), _booted_viewport)
		var stuck := viewer.cards().sticky
		check(stuck == cards[1].child.data and _container.is_locked(),
				"sanity: a real click stuck a card in the game's deck viewer")
		await _click_overlay(&"WallButton")
		await _wait_out_the_move()
		check(_main._current_focus == &"", "sanity: the Wall button reached wall view",
				str(_main._current_focus))
		check(not viewer.margin_container.is_visible_in_tree() and not viewer.can_process(),
				"in wall view the game's viewer is neither drawn nor hears input")
		await _click_overlay(&"BackButton")
		await _wait_out_the_move()
		var landing := Vector2(_container.slid_fraction(), viewer.margin_container.modulate.a)
		if _container.slid_fraction() < 1.0: await _container.slide_settled
		check(_main._current_focus == &"game" and viewer.margin_container.is_visible_in_tree()
				and viewer.can_process() and is_equal_approx(viewer.margin_container.modulate.a, 1.0),
				"coming back, the viewer is drawn and answering again", str(_main._current_focus))
		check(is_equal_approx(landing.y, landing.x),
				"...having faded in with the sidebar's slide", "slide %.2f, alpha %.2f at the landing"
				% [landing.x, landing.y])
		check(viewer.cards().sticky == stuck and _container.is_locked() and _previewed_card() == stuck
				and _exit_button().visible,
				"...its card still stuck, described, with its X",
				"shown=%s x=%s" % [_described_title(), _exit_button().visible])
		await _tap_key(KEY_ESCAPE)
		check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
				"a cancel there closes the viewer")
		check(_hud_is_up() and deck.has_focus(),
				"...back to the HUD with the focus on the button that opened it",
				str(_booted_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## Behind an open game viewer the board answers no pointer: moving over a board card describes nothing of the board's, and a drag begun over it closes the viewer and pans nothing.
func test_the_board_behind_an_open_viewer_answers_no_pointer() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "sanity: the dealt board offers a card to point at",
			str(controls.size()))
	if not controls.is_empty():
		_container.show_hud()
		await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
		var published : Array[String] = []
		_play_area.info_requested.connect(func(entry: InfoEntry) -> void: published.append(entry.title))
		var catcher := DeckViewer._open.margin_container.get_global_rect()
		var behind : Array[Vector2] = []
		for control : Control in controls:
			var point := _point_in_window(&"game", control.get_global_rect().get_center())
			if catcher.has_point(point): behind.append(point)
		check(not behind.is_empty(), "sanity: a board card lies behind the open viewer",
				"catcher %s" % catcher)
		var at : Vector2 = behind[0] if not behind.is_empty() else catcher.get_center()
# ⚠ A PUSHED MOTION IS HIT-TESTED ONLY ONCE THE VIEWPORT KNOWS THE POINTER IS IN IT: a window is
# told by the OS, a booted SubViewport never, and every motion then falls through its controls.
		_booted_viewport.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
		_hover_in(_booted_viewport, at)
		await get_tree().process_frame
		await get_tree().process_frame
		check(published.is_empty(), "a pointer over a board card behind the viewer describes no board card",
				"at %s in catcher %s: %s" % [at, catcher, published])
		var entrance := _a_board_point_on_the_viewer_backdrop(await _entrance_card_controls())
		check(entrance != Vector2.INF,
				"sanity: an Entrance card, which a drag lifts, lies behind the viewer's backdrop, clear of its cards",
				"catcher %s" % catcher)
		if entrance != Vector2.INF: at = entrance
		var dragged : Array[CardData] = []
		_play_area.card_dragged.connect(func(data: CardData) -> void: dragged.append(data))
		var scroll := _play_area.scroll_container as SmoothScrollContainer
		var before := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
		_push_mouse_button(at, _booted_viewport, true)
		for step : int in [1, 2, 3]:
			var motion := InputEventMouseMotion.new()
			motion.position = at + MAP_PAN_DRAG * step / 3.0
			motion.global_position = motion.position
			motion.relative = MAP_PAN_DRAG / 3.0
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			_booted_viewport.push_input(motion)
			await get_tree().process_frame
		check(dragged.is_empty() and _play_area.selected_cards.is_empty(),
				"a drag begun on an Entrance card behind the viewer takes up no card",
				"%d dragged, %d held" % [dragged.size(), _play_area.selected_cards.size()])
		check(not scroll.input_handler.content_dragging,
				"...and starts no pan")
		_push_mouse_button(at + MAP_PAN_DRAG, _booted_viewport, false)
		await get_tree().process_frame
		await get_tree().process_frame
		check(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical) == before,
				"...and moves the board nowhere", "%s -> %s"
				% [before, Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)])
		check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
				"...its press closing the viewer, as a click outside it does")
	await _end_main_fixture()

# A POINT ON ONE OF `controls` WHERE THE OPEN VIEWER SHOWS ONLY ITS BACKDROP, or INF: a press on one of
# its cards sticks that card instead of closing it. A card counts only where its list clips it in.
func _a_board_point_on_the_viewer_backdrop(controls: Array[Control]) -> Vector2:
	var viewer := DeckViewer._open
	var catcher := viewer.margin_container.get_global_rect()
	var list := viewer.flow_container.get_parent_control().get_global_rect()
	var covered : Array[Rect2] = [viewer.close_tab.get_global_rect()]
	for slot : Control in viewer.flow_container.get_children():
		covered.append(slot.get_global_rect().intersection(list))
	for control : Control in controls:
		var rect := control.get_global_rect()
		var corner := _point_in_window(&"game", rect.position)
		var seen := Rect2(corner, _point_in_window(&"game", rect.end) - corner).intersection(catcher)
		for y : int in range(ceili(seen.position.y), floori(seen.end.y)):
			for x : int in range(ceili(seen.position.x), floori(seen.end.x)):
				var point := Vector2(x, y)
				if not covered.any(func(r: Rect2) -> bool: return r.has_point(point)): return point
	return Vector2.INF

# Each route is checked against what the same press does on a map with no viewer anywhere.
func _check_the_map_ignores_the_game_viewer(route: String) -> void:
	match route:
		"the map's Deck button":
			check(await _click_button(_container.map_deck_button, _booted_viewport),
					"a real click on the map's Deck button pressed it")
			await get_tree().process_frame
			check(is_instance_valid(DeckViewer._open)
					and DeckViewer._open.get_parent() == _main.wall.get_node(^"%Overlay"),
					"...and the map's own deck viewer opened")
			check(_hud_is_up() and not _container.is_locked(),
					"...over the map's HUD, no game card on the map's sidebar",
					_panel.current_entry.title if _panel.current_entry else "none")
		"a pack node's first pick":
			var pack := await _click_a_reachable_node(true)
			check(is_instance_valid(DeckViewer._open)
					and DeckViewer._open.get_parent() == _main.wall.get_node(^"%Overlay"),
					"a pack node's first pick opened its possible-cards viewer")
			check(_container.showing_description() and not _container.is_locked()
					and _panel.current_entry.title == _map._info_for(pack).title,
					"...with the picked node described, no game card on the map's sidebar",
					_panel.current_entry.title if _panel.current_entry else "none")
		"an arrow":
			await _tap_key(KEY_DOWN)
			check(_map.controller.selected() != null,
					"the first arrow on the map picks a node")
			check(_container.showing_description() and not _container.is_locked()
					and _panel.current_entry.title == _map._info_for(_map.controller.selected()).title,
					"...and the sidebar describes that node, no game card on the map's sidebar",
					_panel.current_entry.title if _panel.current_entry else "none")

# Reached the way a player reaches it: a live show, Back to the map, then onto a pack node -- so
# the stack holds a picture behind the map AND one ahead, and Back and Forward are both live.
func _open_the_chooser_with_pictures_behind_and_ahead() -> ChoiceViewer:
	await _start_game_fixture()
	await _click_overlay(&"BackButton")
	await _wait_out_the_move()
	if _container.slid_fraction() < 1.0: await _container.slide_settled
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	if _main._current_focus != &"map" or pack == null: return null
	if pack not in _map.controller.next_nodes_of(_map.controller._current):
		_map.controller._current = _a_neighbour_leading_to(pack)
	_map.controller.move_to(pack)
	return await _await_the_chooser()

## The walk onto a pack node ends and its chooser comes up, or null once the wait runs out.
func _await_the_chooser() -> ChoiceViewer:
	await _await_map_arrival()
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC and _map._chooser == null:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().process_frame
	return _map._chooser

# A TRAVEL PRESSED FOR REAL IS SEEN THROUGH before the fixture ends: freeing Main mid-walk lets the
# pack's chooser build after it, on nothing, and its cards leak at exit.
func _see_the_travel_through() -> void:
	var chooser := await _await_the_chooser()
	check(chooser != null, "sanity: the travel onto the pack node opened its chooser")
	if chooser: chooser.queue_free()
	await get_tree().process_frame

func _chooser_is_up(chooser: ChoiceViewer) -> bool:
	return is_instance_valid(chooser) and not chooser.is_queued_for_deletion()

## The chooser's listed control showing its stuck card, or null while none is stuck.
func _stuck_control(chooser: ChoiceViewer) -> Control:
	for control : ControlCard in chooser.cards().controls:
		if control.child.data == chooser.cards().sticky: return control
	return null

## The key and pad focus in the window's own viewport, where the chooser lives, is on `expected`.
func _check_the_key_focus_is_on(expected: Control, when: String) -> void:
	var focused := _booted_viewport.gui_get_focus_owner()
	check(expected != null and focused == expected,
			"the key focus is back on the chooser %s" % when, "on %s, expected %s" % [focused, expected])

## Every way off the map screen a player has, each beside the press that brings them back to it: `[label, leave, return]`.
func _routes_off_the_map() -> Array[Array]:
	var back := _click_overlay.bind(&"BackButton")
	var forward := _click_overlay.bind(&"ForwardButton")
	return [
		["a click on the overlay's Back", back, forward],
		["a click on the overlay's Forward", forward, back],
		["a click on the overlay's Wall", _click_overlay.bind(&"WallButton"), back],
		["wall_back's key", _tap_key.bind(KEY_BRACKETLEFT), forward],
		["wall_forward's key", _tap_key.bind(KEY_BRACKETRIGHT), back],
		["wall_overview's key", _tap_key.bind(KEY_TAB), back],
		["wall_back's pad button", _tap_pad.bind(JOY_BUTTON_LEFT_SHOULDER), forward],
		["wall_forward's pad button", _tap_pad.bind(JOY_BUTTON_RIGHT_SHOULDER), back],
		["wall_overview's pad button", _tap_pad.bind(JOY_BUTTON_BACK), back],
		["a pinch in", _pinch_in_at.bind(Vector2(_booted_viewport.size) / 2.0), back],
		["a wall_jump key to another picture", _tap_key.bind(_jump_key_off_the_map()), back],
	]

func _overlay_button(button_name: StringName) -> Button:
	return _main.wall.get_node(^"%Overlay").get_node(NodePath("%" + button_name)) as Button

func _click_overlay(button_name: StringName) -> void:
	var at := _overlay_button(button_name).get_global_rect().get_center()
	_hover_in(_booted_viewport, at)
	await get_tree().process_frame
	await _click(at, _booted_viewport)

func _tap_pad(button: JoyButton) -> void:
	for pressed : bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		_booted_viewport.push_input(event)
		await get_tree().process_frame

# ⚠ THE FINGERS LIFT ONCE THE LEAVE HAS LANDED: the wall drops input while a move is in flight, so
# a lift during it never reaches the pinch tracker, and it then refuses every later pinch.
## Two fingers closing past the wall's pinch threshold, about `centre` in the window.
func _pinch_in_at(centre: Vector2) -> void:
	var spread := WallPicture.settings().wall_pinch_threshold_px * 3.0
	for index : int in [0, 1]:
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = centre + Vector2(spread * index, 0.0)
		_booted_viewport.push_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = centre + Vector2(spread / 3.0, 0.0)
	_booted_viewport.push_input(drag)
	await get_tree().process_frame
	await _wait_out_the_move()
	for index : int in [0, 1]:
		var lift := InputEventScreenTouch.new()
		lift.index = index
		lift.position = centre
		_booted_viewport.push_input(lift)
	await get_tree().process_frame

## The number key that jumps straight to the first picture on the wall that is not the map.
func _jump_key_off_the_map() -> Key:
	var off_the_map := 1 if _main.wall._packed_ids_in_placement_order()[0] == &"map" else 0
	return (KEY_1 + off_the_map) as Key

## A real left press on a listed control, through the signal Godot's own GUI pass fires.
func _click_a_listed_card(control: Control) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	control.gui_input.emit(press)

## The sidebar settled at `aim`, or the wait ran out: a slide that never starts must fail a check rather than hang the suite.
func _await_the_menus_slide(container: HudContainer, aim: float) -> void:
	var waited := 0.0
	while not is_equal_approx(container.slid_fraction(), aim) and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()

## The sidebar part-way in or out, or the wait ran out: a slide that jumps must fail a check rather than hang the suite.
func _await_the_menus_slide_under_way(container: HudContainer) -> void:
	var waited := 0.0
	while (container.slid_fraction() <= 0.0 or container.slid_fraction() >= 1.0) \
			and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()

# The start menu's own Inspect viewer, reached the way a player reaches it: New Run opens the deck
# picker, the first deck's Inspect button opens a viewer over the menu. Returns
# `[viewport, main, inspect_button]`.
func _open_the_pickers_inspect_viewer(size := Vector2i(1280, 720), in_players_window := false) -> Array:
	var opened := await _open_the_deck_picker(size, in_players_window)
	var main : Main = opened[1]
	var picker : DeckPicker = opened[2]
	var inspect : Button = null
	if picker: inspect = (picker.rows.get_child(0) as HBoxContainer).get_child(1) as Button
	if inspect: inspect.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	await _await_the_menus_slide(container, 1.0)
	return [opened[0], main, inspect]

## The start menu is a screen like the others: the picker's viewer lists its cards beside the container, never under it; harness-scale only.
func test_the_start_menus_inspect_viewer_lists_beside_the_container() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	check(opened[2] != null and is_instance_valid(DeckViewer._open),
			"New Run's picker offers an Inspect button that opens a viewer (S12.16)")
	if is_instance_valid(DeckViewer._open):
		check(container.visible, "sanity: the open viewer brought the container up on the start menu")
		_check_every_card_inside(_listed_viewer_cards(), _unbounded_below(container.resting_rect_beside(null)),
				"every card the picker's viewer lists lies beside the container and inside the window (S12.16)")
	await _end_booted_fixture(viewport, main)

## With the picker's viewer up the menu's sidebar is in, so a click on it is the sidebar's, and a click anywhere else beside the list closes the viewer; the sidebar stays in for the picker, and slides out once the picker closes with nothing described.
func test_a_click_beside_the_menus_viewer_closes_it_and_the_sidebar_slides_out() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	check(is_instance_valid(DeckViewer._open) and container.visible
			and is_equal_approx(container.slid_fraction(), 1.0),
			"sanity: the picker's viewer is open with the menu's sidebar slid in",
			"%.3f" % container.slid_fraction())
	if is_instance_valid(DeckViewer._open):
		await _click(container.container_rect().get_center(), viewport)
		check(is_instance_valid(DeckViewer._open) and not DeckViewer._open.is_queued_for_deletion(),
				"a click on the slid-in sidebar is not a click outside the viewer")
		var outside := Vector2(viewport.size) - Vector2(2, 2)
		await _click(outside, viewport)
		check(not is_instance_valid(DeckViewer._open) or DeckViewer._open.is_queued_for_deletion(),
				"a click beside the list closes the picker's viewer", str(outside))
		check(container.visible and is_equal_approx(container.slid_fraction(), 1.0),
				"...and the menu's sidebar stays in while the picker is up", "%.3f" % container.slid_fraction())
		await _close_open_viewer(viewport)
		await _await_the_menus_slide(container, 0.0)
		check(not container.visible and is_zero_approx(container.slid_fraction()),
				"...and closing the picker with nothing described slides the sidebar back out",
				"%.3f" % container.slid_fraction())
	await _end_booted_fixture(viewport, main)

## The picker's viewer publishes into the menu's own container, and closing it hands the focus back to Inspect.
func test_the_start_menus_inspect_viewer_publishes_into_the_container() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var inspect : Button = opened[2]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var title : Label = panel.get_node(^"%Title")
	var cards : Array[ControlCard] = []
	if is_instance_valid(DeckViewer._open): cards = _listed_viewer_cards()
	check(cards.size() >= 2, "the inspected deck lists cards to point at", str(cards.size()))
	if cards.size() >= 2:
		cards[1].grab_focus()
		await get_tree().process_frame
		check(container.showing_description(),
				"a highlight in the picker's viewer opens the menu's description (S12.17, Q140=a)")
		check(title.text == _expected_text(cards[1].child.data)[0],
				"...and the title reads that card's own name (S12.17)", title.text)
		await _close_open_viewer(viewport)
		check(not is_instance_valid(DeckViewer._open), "escape closed the picker's viewer")
		check(viewport.gui_get_focus_owner() == inspect,
				"...and the focus is back on the Inspect button that opened it (S12.17)",
				str(viewport.gui_get_focus_owner()))
	await _end_booted_fixture(viewport, main)

## The picker's own dimmer must not eat the viewer it opened: a POINTER on a listed card publishes, exactly as the keyboard does.
func test_the_start_menus_inspect_viewer_publishes_on_hover() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var title : Label = panel.get_node(^"%Title")
	var cards : Array[ControlCard] = []
	if is_instance_valid(DeckViewer._open): cards = _listed_viewer_cards()
	check(cards.size() >= 2, "the inspected deck lists cards to point at", str(cards.size()))
	var target := _viewer_card_named_other_than(cards, title.text)
	check(target != null, "the inspected deck lists a card the opening focus did not already read",
			title.text)
	if target != null:
		container.show_hud()
		_hover_in(viewport, target.get_global_rect().get_center())
		await get_tree().process_frame
		check(container.showing_description(),
				"a pointer on the picker's viewer card opens the menu's description")
		check(title.text == _expected_text(target.child.data)[0],
				"...and the title reads that card's own name", title.text)
	await _end_booted_fixture(viewport, main)

## The picker's viewer is UI like every other: it opens in the window's own viewport, beside the sidebar it slid in, its cards at the deck viewer's size at the window's UI scale, at both window shapes; harness-scale only.
func test_the_menus_viewer_draws_at_the_ui_size_at_both_window_shapes() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var opened := await _open_the_pickers_inspect_viewer(size)
		var viewport : SubViewport = opened[0]
		var main : Main = opened[1]
		var container : HudContainer = main.wall.get_node(^"%HudContainer")
		var viewer := DeckViewer._open
		check(is_instance_valid(viewer) and viewer.get_viewport() == viewport,
				"the picker's viewer opens in the window's own viewport at %s" % size,
				str(viewer.get_viewport() if is_instance_valid(viewer) else null))
		check(container.visible and is_equal_approx(container.slid_fraction(), 1.0),
				"...with the menu's sidebar slid in beside it at %s" % size, "%.3f" % container.slid_fraction())
		if is_instance_valid(viewer):
			_check_cards_at_the_ui_size(viewport, viewer.cards().controls.slice(0, 8),
					"the picker's viewer, %s" % size)
		await _end_booted_fixture(viewport, main)

## Leaving the menu takes the picker's viewer out with the sidebar -- not drawn, deaf in wall view -- and coming back fades it in with the sidebar's slide, still listing its deck.
func test_the_menus_viewer_fades_with_the_sidebar_across_a_leave() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var viewer := DeckViewer._open
	check(is_instance_valid(viewer), "sanity: the picker's viewer is open")
	if is_instance_valid(viewer):
		var listed := viewer.cards().controls.size()
		await main._go_to_wall_view()
		check(main._current_focus == &"", "sanity: the menu was left for wall view", str(main._current_focus))
		check(not viewer.margin_container.is_visible_in_tree() and not viewer.can_process(),
				"in wall view the picker's viewer is neither drawn nor hears input")
		main._focus_picture(&"start_menu")
		while main._current_focus != &"start_menu": await get_tree().process_frame
		await _await_the_menus_slide_under_way(container)
		var midway := Vector2(container.slid_fraction(), viewer.margin_container.modulate.a)
		check(midway.x > 0.0 and midway.x < 1.0,
				"sanity: the sample is taken while the sidebar is still sliding in", "slide %.3f" % midway.x)
		check(is_equal_approx(midway.y, midway.x),
				"coming back it fades in with the sidebar's slide", "slide %.3f, alpha %.3f mid-slide"
				% [midway.x, midway.y])
		await _await_the_menus_slide(container, 1.0)
		check(viewer.margin_container.is_visible_in_tree() and viewer.can_process()
				and is_equal_approx(viewer.margin_container.modulate.a, 1.0)
				and viewer.cards().controls.size() == listed and container.visible,
				"...and is drawn and answering again beside the slid-in sidebar, listing its whole deck")
	await _end_booted_fixture(viewport, main)

## The viewer belongs to the picker: a Pick that starts a new run with it open takes it with the picker, and the new run's map hosts nothing of the menu's.
func test_picking_a_deck_with_the_viewer_open_closes_it() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var viewer := DeckViewer._open
	var picker : DeckPicker = _the_deck_picker(main)
	check(is_instance_valid(viewer) and picker != null, "sanity: the picker's viewer is open over the picker")
	if picker != null:
		var landed : Array[bool] = [false]
		main.map_scene.controller.map_ready.connect(func() -> void: landed[0] = true, CONNECT_ONE_SHOT)
		((picker.rows.get_child(0) as HBoxContainer).get_child(2) as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(),
				"a Pick with the viewer open closes it with the picker")
		check(container._hosted_viewers.is_empty(), "...and the sidebar hosts no viewer any more",
				str(container._hosted_viewers.size()))
		var waited := 0.0
		while not landed[0] and waited < CARD_CONTROL_TIMEOUT_SEC:
			await get_tree().process_frame
			waited += get_process_delta_time()
		check(landed[0], "sanity: the new run's map came up")
	await _end_booted_fixture(viewport, main)

## A card read in the picker belongs to the picker: once it closes, leaving the menu and coming back finds the HUD.
func test_closing_the_picker_drops_the_menus_description() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var cards : Array[ControlCard] = []
	if is_instance_valid(DeckViewer._open): cards = _listed_viewer_cards()
	check(not cards.is_empty(), "the inspected deck lists a card to read", str(cards.size()))
	if not cards.is_empty():
		cards[0].grab_focus()
		await get_tree().process_frame
		check(container.showing_description(), "sanity: the menu is describing a picker card")
		await _close_open_viewer(viewport)
		await _close_open_viewer(viewport)
		check(_the_deck_picker(main) == null,
				"sanity: the second escape closed the picker itself")
		await main._go_to_wall_view()
		await main._focus_picture(&"start_menu")
		check(not container.showing_description(),
				"Close fix 2: returning to the menu after the picker closed finds the HUD")
	await _end_booted_fixture(viewport, main)

## The deck picker wherever it is up, or null while none is: where it lives is what the rows check.
func _the_deck_picker(main: Main) -> DeckPicker:
	return main.find_child("DeckPicker", true, false) as DeckPicker

# The player's route to the picker: Play unfolds the run row, New Run opens the picker. The row
# must be showing, since closing the picker hands the focus back to New Run.
func _press_new_run(main: Main) -> void:
	(main.menu_scene.get_node(^"Content/Play") as Button).pressed.emit()
	main.menu_scene.new_run_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

## The deck picker open on a booted menu at `size`. Returns `[viewport, main, picker]`.
func _open_the_deck_picker(size := Vector2i(1280, 720), in_players_window := false) -> Array:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var booted := await _boot_main_at(size, in_players_window)
	var main : Main = booted[1]
	await _press_new_run(main)
	await _await_the_menus_slide(main.hud_container, 1.0)
	return [booted[0], main, _the_deck_picker(main)]

## Where `control` is drawn in `viewport`'s own window pixels.
func _drawn_in_window(viewport: SubViewport, control: Control) -> Rect2:
	return viewport.get_final_transform() * control.get_global_transform_with_canvas() \
			* Rect2(Vector2.ZERO, control.size)

func _tap_key_in(viewport: SubViewport, keycode: Key) -> void:
	_push_key(viewport, keycode, true)
	_push_key(viewport, keycode, false)
	await get_tree().process_frame
	await get_tree().process_frame

## The deck picker is UI like its viewer: in the window's own viewport, drawn at its own size whatever the menu picture's zoom, wholly on screen and centred where the menu centres its own content, at both window shapes; harness-scale only.
func test_the_deck_picker_draws_at_the_ui_size_on_screen_at_both_window_shapes() -> void:
	for size : Vector2i in INSET_WINDOWS:
		var opened := await _open_the_deck_picker(size)
		var viewport : SubViewport = opened[0]
		var main : Main = opened[1]
		var picker : DeckPicker = opened[2]
		check(picker != null and picker.get_viewport() == viewport,
				"the deck picker opens in the window's own viewport at %s" % size,
				str(picker.get_viewport() if picker else null))
		if picker != null:
			var panel : Control = picker.get_node(^"Panel")
			var drawn := _drawn_in_window(viewport, panel)
			var ui := panel.size * viewport.get_final_transform().get_scale()
			check(drawn.size.is_equal_approx(ui),
					"...drawn at its own size at the window's UI scale, never the menu's zoom, at %s" % size,
					"%s vs %s" % [drawn.size, ui])
			check(Rect2(Vector2.ZERO, Vector2(size)).encloses(drawn),
					"...wholly inside the window at %s" % size, str(drawn))
			var scroll : ScrollContainer = picker.get_node(^"Panel/VBox/Scroll")
			var first_pick : Control = picker.rows.get_child(0).get_child(2)
			check(scroll.scroll_vertical == 0 and viewport.gui_get_focus_owner() == first_pick
					and _drawn_in_window(viewport, scroll).encloses(_drawn_in_window(viewport, first_pick)),
					"...its list at the top, the focused first Pick in view, at %s" % size,
					"scroll %d focus %s" % [scroll.scroll_vertical, viewport.gui_get_focus_owner()])
			var beside := viewport.get_final_transform() * main.hud_container.rect_beside(null)
			check(drawn.get_center().distance_to(beside.get_center()) <= 1.0,
					"...centred where the menu centres its own content, beside the sidebar as shown, at %s"
					% size, "%s vs %s" % [drawn.get_center(), beside.get_center()])
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			await await_drawn_frames(2)
			var corner := drawn.position + Vector2.ONE * 6.0
			var seen := viewport.get_texture().get_image().get_pixelv(Vector2i(corner))
			var own := PaletteDB.ROLES.color_of(&"deck_picker")
			check(_colour_distance(seen, own) < OPAQUE_COLOUR_TOLERANCE,
					"...its panel drawn solid in its own colour at %s" % size,
					"%s at %s vs %s" % [seen, corner, own])
		await _end_booted_fixture(viewport, main)

## Inspect opens its viewer OVER the picker, on the layer above it, and opaque: the pointer over the picker's list is the viewer's, and no picker row shows through between the viewer's cards.
func test_the_deck_pickers_viewer_draws_over_the_picker() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var picker := _the_deck_picker(main)
	var viewer := DeckViewer._open
	check(picker != null and is_instance_valid(viewer), "sanity: the picker's viewer is open over the picker")
	if picker != null and is_instance_valid(viewer):
		var panel : Control = picker.get_node(^"Panel")
		check(viewer.layer > panel.get_canvas_layer_node().layer,
				"the picker's viewer is on a layer above the picker",
				"%d vs %d" % [viewer.layer, panel.get_canvas_layer_node().layer])
		_hover_in(viewport, _drawn_in_window(viewport, panel).get_center())
		await get_tree().process_frame
		var hovered := viewport.gui_get_hovered_control()
		check(hovered != null and (hovered == viewer.margin_container
				or viewer.margin_container.is_ancestor_of(hovered)),
				"...and the pointer over the picker's list is the viewer's", str(hovered))
		var label := _a_picker_label_under_the_viewer_between_its_cards(viewport, picker, viewer)
		check(label != Rect2(), "sanity: a picker row's label lies under the viewer, clear of its cards")
		if label != Rect2():
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			await await_drawn_frames(2)
			var image := viewport.get_texture().get_image()
			var hud := PaletteDB.color(PaletteDB.ROLES.viewer_inspect)
			var through := 0
			for y : int in range(int(label.position.y), int(label.end.y)):
				for x : int in range(int(label.position.x), int(label.end.x)):
					if _colour_distance(image.get_pixel(x, y), hud) > 0.05: through += 1
			check(through == 0,
					"...and the picker's row does not show through the viewer: its label's pixels are all the viewer's own colour",
					"%d of %s differ" % [through, label])
	await _end_booted_fixture(viewport, main)

## A picker row's label, in window pixels, that lies wholly inside the viewer's backdrop and inside the picker's own scroll, clear of every listed card; empty if none does.
func _a_picker_label_under_the_viewer_between_its_cards(viewport: SubViewport, picker: DeckPicker,
		viewer: DeckViewer) -> Rect2:
	var backdrop := _drawn_in_window(viewport, viewer.margin_container.get_node(^"ColorRect") as Control)
	var scroll := _drawn_in_window(viewport, picker.get_node(^"Panel/VBox/Scroll") as Control)
	for row : Node in picker.rows.get_children():
		var label := _drawn_in_window(viewport, row.get_child(0) as Control)
		if not (backdrop.encloses(label) and scroll.encloses(label)): continue
		if viewer.cards().controls.any(func(card: ControlCard) -> bool:
				return _drawn_in_window(viewport, card).intersects(label)): continue
		return label
	return Rect2()

## One device reaches every control, in the window's own viewport with the menu's picture holding no focus: Left to Inspect, Enter opens its viewer, Escape closes it back onto Inspect, Down walks every Pick to Close, Close hands the focus back to New Run, and Enter on a Pick starts the run.
func test_keys_reach_every_deck_picker_control_in_the_windows_own_viewport() -> void:
	var opened := await _open_the_deck_picker()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var picker : DeckPicker = opened[2]
	var menu_viewport : SubViewport = main._pictures[&"start_menu"].viewport
	check(picker != null, "sanity: New Run opened the deck picker")
	if picker != null:
		var first_row := picker.rows.get_child(0) as HBoxContainer
		var inspect := first_row.get_child(1) as Button
		check(viewport.gui_get_focus_owner() == first_row.get_child(2)
				and menu_viewport.gui_get_focus_owner() == null,
				"the picker opens on its first Pick in the window's own viewport, the menu holding no focus",
				"%s / %s" % [viewport.gui_get_focus_owner(), menu_viewport.gui_get_focus_owner()])
		await _tap_key_in(viewport, KEY_LEFT)
		check(viewport.gui_get_focus_owner() == inspect, "Left reaches the row's Inspect",
				str(viewport.gui_get_focus_owner()))
		await _tap_key_in(viewport, KEY_ENTER)
		check(is_instance_valid(DeckViewer._open) and DeckViewer._open.get_viewport() == viewport,
				"Enter on Inspect opens its viewer in the window's own viewport")
		await _tap_key_in(viewport, KEY_ESCAPE)
		check(not is_instance_valid(DeckViewer._open) and _the_deck_picker(main) == picker
				and viewport.gui_get_focus_owner() == inspect,
				"Escape closes the viewer alone, the focus back on Inspect", str(viewport.gui_get_focus_owner()))
		await _tap_key_in(viewport, KEY_RIGHT)
		var close : Button = picker.get_node(^"Panel/VBox/Close")
		var reached : Array[Control] = [viewport.gui_get_focus_owner()]
		for _step : int in picker.rows.get_child_count():
			await _tap_key_in(viewport, KEY_DOWN)
			reached.append(viewport.gui_get_focus_owner())
		var picks : Array[Control] = []
		for row : Node in picker.rows.get_children():
			picks.append(row.get_child(2) as Control)
		check(picks.all(func(pick: Control) -> bool: return pick in reached) and close in reached,
				"Down walks every row's Pick and on to Close", str(reached))
		if viewport.gui_get_focus_owner() == close:
			await _tap_key_in(viewport, KEY_ENTER)
			check(_the_deck_picker(main) == null
					and menu_viewport.gui_get_focus_owner() == main.menu_scene.new_run_button,
					"Enter on Close closes the picker, the focus back on New Run in the menu's picture",
					str(menu_viewport.gui_get_focus_owner()))
		main.menu_scene.new_run_button.pressed.emit()
		await _await_the_menus_slide(main.hud_container, 1.0)
		var landed : Array[bool] = [false]
		main.map_scene.controller.map_ready.connect(func() -> void: landed[0] = true, CONNECT_ONE_SHOT)
		await _tap_key_in(viewport, KEY_ENTER)
		var waited := 0.0
		while not landed[0] and waited < CARD_CONTROL_TIMEOUT_SEC:
			await get_tree().process_frame
			waited += get_process_delta_time()
		check(landed[0] and _the_deck_picker(main) == null,
				"Enter on a reopened picker's Pick starts the new run and closes the picker")
	await _end_booted_fixture(viewport, main)

## The menu behind the picker answers no pointer: the picker's dim takes it over the menu's Profile, the overlay's Wall button still takes it above the dim, and with the picker closed the same click presses Profile.
func test_the_menu_behind_the_deck_picker_answers_no_pointer() -> void:
	var opened := await _open_the_deck_picker()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var picker : DeckPicker = opened[2]
	check(picker != null, "sanity: New Run opened the deck picker")
	if picker != null:
		var profile := main.menu_scene.get_node(^"Content/Main/Profile") as Button
		var at := _picture_point_in_window(main._pictures[&"start_menu"],
				profile.get_global_rect().get_center())
		var presses : Array[int] = [0]
		profile.pressed.connect(func() -> void: presses[0] += 1)
		_hover_in(viewport, at)
		await get_tree().process_frame
		check(viewport.gui_get_hovered_control() == picker.get_node(^"Dim"),
				"the pointer over the menu's Profile is the picker's dim's", str(viewport.gui_get_hovered_control()))
		await _click(at, viewport)
		check(presses[0] == 0, "...and its click does not press Profile behind the picker", str(presses[0]))
		var wall_button : Button = main.wall.get_node(^"%Overlay").get_node(^"%WallButton")
		_hover_in(viewport, wall_button.get_global_rect().get_center())
		await get_tree().process_frame
		check(viewport.gui_get_hovered_control() == wall_button,
				"the overlay's Wall button still takes the pointer above the dim", str(viewport.gui_get_hovered_control()))
		await _close_open_viewer(viewport)
		check(_the_deck_picker(main) == null, "sanity: Escape closed the picker")
		await _await_the_menus_slide(main.hud_container, 0.0)
		at = _picture_point_in_window(main._pictures[&"start_menu"], profile.get_global_rect().get_center())
		_hover_in(viewport, at)
		await get_tree().process_frame
		await _click(at, viewport)
		check(presses[0] == 1, "sanity: with the picker closed the same click presses Profile", str(presses[0]))
	await _end_booted_fixture(viewport, main)

## Leaving the menu takes the picker out with the sidebar -- not drawn, deaf in wall view -- and coming back fades it in with the sidebar's slide, focused on its first Pick, and Escape still closes it.
func test_the_deck_picker_is_hidden_in_wall_view_and_back_on_return() -> void:
	var opened := await _open_the_deck_picker()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var picker : DeckPicker = opened[2]
	check(picker != null, "sanity: New Run opened the deck picker")
	if picker != null:
		await main._go_to_wall_view()
		check(main._current_focus == &"", "sanity: the menu was left for wall view", str(main._current_focus))
		var panel : Control = picker.get_node(^"Panel")
		check(not panel.is_visible_in_tree() and not picker.can_process(),
				"in wall view the deck picker is neither drawn nor hears input")
		main._focus_picture(&"start_menu")
		while main._current_focus != &"start_menu": await get_tree().process_frame
		var landing := Vector2(main.hud_container.slid_fraction(), picker.modulate.a)
		await _await_the_menus_slide(main.hud_container, 1.0)
		check(is_equal_approx(landing.y, landing.x),
				"coming back it fades in with the sidebar's slide", "slide %.2f, alpha %.2f at the landing"
				% [landing.x, landing.y])
		check(panel.is_visible_in_tree() and picker.can_process() and is_equal_approx(picker.modulate.a, 1.0)
				and viewport.gui_get_focus_owner() == picker.rows.get_child(0).get_child(2),
				"...and is drawn and answering again, focused on its first Pick", str(viewport.gui_get_focus_owner()))
		await _close_open_viewer(viewport)
		check(_the_deck_picker(main) == null, "...and Escape closes it")
	await _end_booted_fixture(viewport, main)

## The picker's viewer is the focus: left up across a leave, the return hands no focus to a Pick hidden behind it, Enter starts no run, and the first arrow enters the viewer in the window's own viewport -- as a game viewer left up across a leave does.
func test_a_return_to_the_menu_leaves_the_focus_to_the_pickers_viewer() -> void:
	var opened := await _open_the_pickers_inspect_viewer()
	var viewport : SubViewport = opened[0]
	var main : Main = opened[1]
	var picker := _the_deck_picker(main)
	var viewer := DeckViewer._open
	check(picker != null and is_instance_valid(viewer), "sanity: the picker's viewer is open over the picker")
	if picker != null and is_instance_valid(viewer):
		viewer.cards().controls[1].grab_focus()
		await main._go_to_wall_view()
		main._focus_picture(&"start_menu")
		while main._current_focus != &"start_menu": await get_tree().process_frame
		await _await_the_menus_slide(main.hud_container, 1.0)
		var owner := viewport.gui_get_focus_owner()
		check(owner == null or not picker.is_ancestor_of(owner),
				"back on the menu, no Pick behind the open viewer holds the focus", str(owner))
		var menu_owner := main._pictures[&"start_menu"].viewport.gui_get_focus_owner()
		check(menu_owner == null, "...and no menu button behind it holds the menu picture's focus",
				str(menu_owner))
		var runs : Array[int] = [0]
		main.menu_scene.new_run_requested.connect(func(_cards: Array[CardData], _rules: Array[CardData]) -> void:
				runs[0] += 1)
		await _tap_key_in(viewport, KEY_ENTER)
		check(runs[0] == 0 and _the_deck_picker(main) == picker,
				"...Enter starts no run and the picker stays up", str(runs[0]))
		await _tap_key_in(viewport, KEY_DOWN)
		owner = viewport.gui_get_focus_owner()
		check(owner != null and viewer.margin_container.is_ancestor_of(owner)
				and owner.get_viewport() == viewport,
				"...and the first arrow enters the viewer, in the window's own viewport", str(owner))
	await _end_booted_fixture(viewport, main)

# A real booster pack open on a live map at `size`, reached through a map node rather than a button.
# ⚠ The TEMPLATE is handed back too: a real map node holds it for the whole run, and a reroll calls
# its generator. Returns `[viewport, main, viewer, template]`.
func _boot_map_with_a_booster(size: Vector2i) -> Array:
	backup_real_save(suite_tag())
	_prev_run = RunManager.run
	_prev_save_info = Main.save_info
	var run := RunManager.new_run(TestDecks.deck_standard_52(), TestDecks.standard_rules())
	Main.save_info = run
	var booted := await _boot_main_at(size)
	var main : Main = booted[1]
	await _focus_map(main, run)
	var node := WorldGraphNode.new()
	var template := TypeBoosterBasic.new()
	node.meta[MapNodeRoles.ROLE_KEY] = MapNodeRoles.ROLE_BOOSTER
	node.meta[MapNodeRoles.BOOSTER_KEY] = template
	await main.map_scene._open_booster(node)
	node.free()
	await get_tree().process_frame
	return [booted[0], main, _open_choice_viewer(main), template]

# The teardown every fixture that boots a real `Main` shares: free the boot, drop the run this test
# made and put the owner's own save back.
func _end_booted_fixture(viewport: Viewport, main: Main) -> void:
	await _free_booted_main(viewport, main)
	RunManager._shutdown_saver()
	RunManager.clear_save()
	restore_real_save(suite_tag())
	RunManager.run = _prev_run
	Main.save_info = _prev_save_info

# A viewer owning its own layout owns the WHOLE of it: the confirm button and the reroll counter
# are inset with the pack rather than left anchored to the picture they float over.
func _check_chrome_inside(viewer: ChoiceViewer, remaining: Rect2, label: String) -> void:
	var confirm := viewer.confirm_button.get_global_rect()
	var counter := viewer.rerolls_label.get_global_rect()
	check(remaining.encloses(confirm) and remaining.encloses(counter),
			"%s: the confirm button and the reroll counter lie inside it too" % label,
			"confirm %s counter %s in %s" % [confirm, counter, remaining])
	var pair := confirm.merge(counter)
	check(absf(pair.get_center().x - remaining.get_center().x) <= 2.0,
			"%s: Rerolls and Take centre under the pack as a pair, not on the picture" % label,
			"%.1f vs %.1f" % [pair.get_center().x, remaining.get_center().x])

func _choice_viewer_cards(viewer: ChoiceViewer) -> Array[ControlCard]:
	var cards : Array[ControlCard] = []
	for child : Node in viewer.flow_container.get_children():
		var card := child as ControlCard
		if card: cards.append(card)
	return cards

## The booster choice viewer publishes into the sidebar exactly as the deck viewer does.
func test_the_choice_viewer_publishes_into_the_sidebar() -> void:
	var booted := await _boot_map_with_a_booster(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var viewer : ChoiceViewer = booted[2]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var title : Label = panel.get_node(^"%Title")
	check(viewer != null, "the booster node opened a choice viewer on the map")
	if viewer != null:
		var cards := _choice_viewer_cards(viewer)
		check(not cards.is_empty(), "the pack generated cards to point at", str(cards.size()))
		if not cards.is_empty():
			cards[0].grab_focus()
			await get_tree().process_frame
			check(container.showing_description(),
					"a highlight in the choice viewer opens the description (S12.3, Q142=a)")
			check(title.text == _expected_text(cards[0].child.data)[0],
					"...and the title reads that card's own name", title.text)
			_check_every_card_inside(cards,
					_ui_space(main),
					"...and every pack card is drawn beside the container, inside the visible picture")
			_check_chrome_inside(viewer,
					_ui_space(main),
					"the space beside the container holds the whole viewer (S12.11)")
	await _end_booted_fixture(viewport, main)

# The Reroll button one pack slot owns, parented to the card it belongs to -- the control a player
# clicks, not the viewer's own list of them.
func _reroll_button_of(card: ControlCard) -> Button:
	for child : Node in card.get_children():
		var button := child as Button
		if button: return button
	return null

## A rerolled slot is a new card under the same highlight: the sidebar reads the replacement, never the card that was rerolled away.
func test_a_reroll_moves_the_sidebar_onto_the_replacement() -> void:
	var booted := await _boot_map_with_a_booster(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var viewer : ChoiceViewer = booted[2]
	var template : BoosterTemplate = booted[3]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var panel : DescriptionPanel = container.get_node(^"%DescriptionPanel")
	var title : Label = panel.get_node(^"%Title")
	check(viewer != null and template != null,
			"the booster node opened a choice viewer on the map, over a live template")
	if viewer != null:
		var cards := _choice_viewer_cards(viewer)
		var reroll : Button = _reroll_button_of(cards[0]) if not cards.is_empty() else null
		check(reroll != null and not reroll.disabled,
				"the pack's first slot offers a Reroll to spend", str(cards.size()))
		if reroll != null and not reroll.disabled:
			cards[0].grab_focus()
			await get_tree().process_frame
			var rerolled_away : CardData = cards[0].child.data
			check(container.showing_description()
						and title.text == _expected_text(rerolled_away)[0],
					"sanity: the sidebar reads the slot the highlight is on", title.text)
			var published : InfoEntry = panel.current_entry
			reroll.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
			var replacement := _choice_viewer_cards(viewer)[0]
			check(replacement.child.data != rerolled_away,
					"the Reroll replaced the slot's card", str(replacement.child.data))
			check(panel.current_entry != published,
					"...and the sidebar re-publishes for the card that took the slot (B1)")
			check(title.text == _expected_text(replacement.child.data)[0],
					"...reading the replacement's own name, not the rerolled card's", title.text)
	await _end_booted_fixture(viewport, main)

## The same claim at a TOP window: a pack inset only on its left and top edges centres past the visible right edge; harness-scale only.
func test_the_choice_viewers_pack_lies_below_the_band_at_a_top_window() -> void:
	var booted := await _boot_map_with_a_booster(Vector2i(600, 1000))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var viewer : ChoiceViewer = booted[2]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	check(viewer != null, "the booster node opened a choice viewer on the map")
	if viewer != null:
		check(HudContainer.container_is_top(
				container.get_viewport().get_visible_rect().size, SettingsManager.settings),
				"sanity: 600x1000 puts the container on the top band")
		_check_every_card_inside(_choice_viewer_cards(viewer),
				_ui_space(main),
				"every pack card is drawn below the band and inside the visible picture (S12.11)")
		_check_chrome_inside(viewer,
				_ui_space(main),
				"the space below the band holds the whole viewer (S12.11)")
	await _end_booted_fixture(viewport, main)

## The map's own pack follows the container as well: a resize re-fits it into the space beside it; harness-scale only.
func test_a_resize_re_fits_the_open_choice_viewer() -> void:
	var booted := await _boot_map_with_a_booster(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var viewer : ChoiceViewer = booted[2]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	check(viewer != null, "the booster node opened a choice viewer on the map")
	if viewer != null:
		await _resize_viewport(viewport, Vector2i(600, 1000))
		_check_every_card_inside(_choice_viewer_cards(viewer),
				_ui_space(main),
				"a resize re-fits the open pack below the new band (S12.15)")
	await _end_booted_fixture(viewport, main)

func _open_choice_viewer(main: Main) -> ChoiceViewer:
	return main.map_scene._chooser

## The choice viewer's own inspector panel is gone: the sidebar is the one surface.
func test_the_choice_viewer_owns_no_inspector_panel() -> void:
	var scene : PackedScene = load("res://UI/choice_viewer.tscn")
	var viewer : ChoiceViewer = scene.instantiate()
	check(viewer.find_child("CardInfo", true, false) == null,
			"the choice viewer's own card-info panel is gone from its scene (S12.7)")
	viewer.free()

## The Deck Maker tool is REPAIRED, not deleted: its scene loads, stands up clean and its options really edit the card it previews.
func test_the_deck_builder_tool_loads_and_stands_up() -> void:
	var scene : PackedScene = load("res://UI/deck_builder.tscn")
	check(scene != null, "the deck builder scene still loads (S12.6, Q166=c)")
	var tool_root : Control = scene.instantiate()
	add_child(tool_root)
	await get_tree().process_frame
	check(tool_root.is_inside_tree(), "...and instantiates into a live tree")
	check(tool_root.find_child("TypeOption", true, false) == null,
			"...with the unwired type selector gone from its scene (Q166=c)")
	var preview := _preview_card(tool_root.get_node(^"HSplitContainer/Control/Preview"))
	check(preview != null and preview.child != null,
			"...with a real preview card built from the current classes")
	if preview != null and preview.child != null:
		await _check_the_rank_option_redraws_the_preview(tool_root, preview)
	tool_root.queue_free()

# A REPAIRED tool has to do something past `_ready()`: picking a rank writes it to the card the tool
# previews AND re-draws that card, which is the whole loop the Deck Maker is. Two known ranks, since
# the preview starts on a random one that could already be the one picked.
func _check_the_rank_option_redraws_the_preview(tool_root: Control, preview: ControlCard) -> void:
	var values : OptionButton = tool_root.get_node(^"HSplitContainer/Control/RankOptionValue")
	var first := 1
	var last := values.item_count - 1
	values.select(first)
	values.item_selected.emit(first)
	await get_tree().process_frame
	check(preview.child.data.rank.value == float(values.get_item_id(first)),
			"picking a rank writes it to the card the tool previews (S12.6)",
			"%s vs id %d" % [preview.child.data.rank.value, values.get_item_id(first)])
	var drawn := preview.child.rank.uv.duplicate()
	values.select(last)
	values.item_selected.emit(last)
	await get_tree().process_frame
	await get_tree().process_frame
	check(preview.child.data.rank.value == float(values.get_item_id(last)),
			"...and picking another writes that one instead (S12.6)",
			"%s vs id %d" % [preview.child.data.rank.value, values.get_item_id(last)])
	check(preview.child.rank.uv != drawn,
			"...and the preview re-draws the pip the new rank frames (S12.6)")

# ------------------------------------------------------------------ S14: LIFTED, AND CARRIED

## How far a press on this control must travel before its gesture becomes a drag.
func _threshold_px(control: Control) -> float:
	return GestureMetrics.drag_threshold_px(control.get_global_rect().size, PlayArea.settings())

# A card LIFTED the way a player lifts one: a click, which leaves it held and raised in its own
# slot with nothing having told it to follow.
func _lift_by_click(control: Control) -> CardVisual:
	var data : CardData = _play_area.ui_data[control]
	await _click_card(control)
	return _play_area.data_card.get(data)

# A card CARRIED the way a player carries one: a press on it, then travel past its own drag
# threshold with the button still down. A quarter of a card's width is well inside its own rect, so
# the pointer ends in the cell the card came from.
func _drag_past_the_threshold(control: Control) -> CardVisual:
	var data : CardData = _play_area.ui_data[control]
	var from := control.get_global_rect().get_center()
	_hover(from)
	await get_tree().process_frame
	_push_mouse_button(from, _game_viewport, true)
	await get_tree().process_frame
	_hover(from + Vector2(_threshold_px(control) + DRAG_THRESHOLD_MARGIN_PX, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	return _play_area.data_card.get(data)

## The release that closes a live gesture, pushed where the pointer already is.
func _release_at(at: Vector2) -> void:
	_push_mouse_button(at, _game_viewport, false)
	await get_tree().process_frame
	await get_tree().process_frame

# A board card EASES toward its target rather than snapping, so a position read on the next frame
# is mid-flight. Bounded, and it returns the instant the card is actually still.
func _await_card_settled(visual: CardVisual) -> void:
	var last := visual.global_position
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		if visual.global_position.distance_to(last) < 0.05: return
		last = visual.global_position

# How far the card is raised above what it AIMS at, the one quantity the two held states share:
# its own slot until it follows, the cursor once it does.
func _lift_above_aim(visual: CardVisual, aim: Vector2) -> float:
	return aim.y - visual.global_position.y

func _slot_centre_of(visual: CardVisual) -> Vector2:
	return visual.get_card_control_center(visual.control_anchor)

## 6.4/G4/G5: a CLICKED card LIFTS at once and does not follow -- it rests on its own slot, raised.
func test_a_held_card_lifts_and_does_not_follow() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _lift_by_click(entrance[0])
		check(visual.held != 0, "the card is HELD by the click (6.4)", str(visual.held))
		check(not visual.following, "...and is NOT following the cursor (6.4)")
		await _await_card_settled(visual)
		var lift := _lift_above_aim(visual, _slot_centre_of(visual))
		check(absf(lift - visual.held_lift_px()) < 2.0,
				"...and rests at its slot centre raised by the lift (6.4, G4)",
				"%.1f vs %.1f" % [lift, visual.held_lift_px()])
	await _end_main_fixture()

## 6.5: motion with NO button down never carries a lifted card -- it waits in its slot.
func test_mouse_motion_with_no_button_down_never_follows() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _lift_by_click(entrance[0])
		check(not visual.following, "the clicked card starts out not following")
		_hover(_bare_board_point(controls))
		await get_tree().process_frame
		_hover(_off_the_board_point())
		await get_tree().process_frame
		check(not visual.following,
				"mouse motion with the button UP leaves it resting in its slot (6.5)")
		check(visual.held != 0, "...and still held", str(visual.held))
	await _end_main_fixture()

## 6.6/G7/GAP-006: a key or pad focus does NOT start the follow -- the card waits in its slot.
func test_a_key_focus_leaves_the_card_resting_in_its_slot() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(entrance.size() >= 2, "the dealt board offers two Entrance cards", str(entrance.size()))
	if entrance.size() >= 2:
		var visual := await _lift_by_click(entrance[0])
		check(not visual.following, "the clicked card starts out not following")
		entrance[1].grab_focus()
		await get_tree().process_frame
		check(not visual.following,
				"a key/pad focus onto another card leaves it NOT following (6.6, GAP-006)")
		await _await_card_settled(visual)
		var rest := _slot_centre_of(visual) - Vector2(0.0, visual.held_lift_px())
		check(visual.global_position.distance_to(rest) < 2.0,
				"...still resting at its slot centre raised by the lift (6.6, GAP-006)",
				"%s vs %s" % [visual.global_position, rest])
	await _end_main_fixture()

## 6.7/G8: the follow ends with its gesture -- a release over bare board takes no cell, so the card goes back to its slot with nothing holding it.
func test_the_release_ends_the_follow() -> void:
	await _start_game_fixture()
	var controls := await _hoverable_card_controls()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to drag",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _drag_past_the_threshold(entrance[0])
		check(visual != null and visual.following,
				"the press and its travel started the card following (6.7)")
		var at := _bare_board_point(controls)
		_hover(at)
		await get_tree().process_frame
		await _release_at(at)
		check(visual != null and not visual.following, "the release ends the follow (6.7)")
		check(_play_area.selected_cards.is_empty() and visual != null and visual.held == 0,
				"...and the card bare board took nothing from is flat in its slot (6.7)",
				"%d held, lift %d" % [_play_area.selected_cards.size(), visual.held])
		check(TestGridFixtures.lit_cell_count(_play_area) == 0,
				"...with the drop map out on every cell (6.7)",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		_hover(_off_the_board_point())
		await get_tree().process_frame
		check(visual != null and not visual.following,
				"...and later motion does not resume it (6.7, GAP-007)")
	await _end_main_fixture()

## 6.8/G8/Q265=a: the lift is the SAME height in both states, so following only makes the card move.
func test_the_lift_is_the_same_height_in_both_states() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to pick up",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _lift_by_click(entrance[0])
		await _await_card_settled(visual)
		var before := _lift_above_aim(visual, _slot_centre_of(visual))
		check(before > 2.0, "the card at rest is lifted by a REAL height, not zero (6.8)",
				"%.1f" % before)
		var from := entrance[0].get_global_rect().get_center()
		var at := from + Vector2(_threshold_px(entrance[0]) + DRAG_THRESHOLD_MARGIN_PX, 0.0)
		_push_mouse_button(from, _game_viewport, true)
		await get_tree().process_frame
		_hover(at)
		await get_tree().process_frame
		await _await_card_settled(visual)
		var after := _lift_above_aim(visual, at + visual.cursor_ride_offset())
		check(absf(after - before) < 2.0,
				"...and it rides the cursor at exactly that same lift (6.8, Q265=a)",
				"%.1f vs %.1f" % [after, before])
		check(visual.following, "...while following")
		await _release_at(at)
	await _end_main_fixture()

## 6.9/G11: a card a DRAG took up follows the cursor from the moment it is held.
func test_a_dragged_card_follows_the_cursor() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to drag",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _drag_past_the_threshold(entrance[0])
		check(not _play_area.selected_cards.is_empty(), "the drag picked a card up",
				str(_play_area.selected_cards.size()))
		if visual != null:
			check(visual.held != 0 and visual.following,
					"a DRAGGED card is following as soon as it is held (6.9)",
					"held %d following %s" % [visual.held, visual.following])
	await _end_main_fixture()

## 1.7/B9/B11/`GAP-008`=a: the click that locked and grabbed one card keeps its description through the drag, and the PLACEMENT closes it.
func test_a_click_locked_card_keeps_its_description_until_it_is_placed() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		check(_container.showing_description() and not _play_area.selected_cards.is_empty(),
				"the click locked a description and lifted the card it landed on")
		_hover(_off_the_board_point())
		await get_tree().process_frame
		check(_panel.visible and not hud_stack.visible and dismissals.is_empty(),
				"pointer motion does NOT dismiss the card the click locked (1.7, GAP-008=a)",
				str(dismissals.size()))
		var placed := await _place_the_held_card()
		check(placed != null, "the board offers that card a cell it may land on")
		if placed != null:
			check(hud_stack.visible and not _panel.visible,
					"...and the placement is what reverts the container to the HUD (1.7, B11)")
	await _end_main_fixture()

## 1.7/B9/B10/Q268=a: the FOURTH dismissal -- a FOLLOWING card the player never clicked to lock leaves its cell and reverts to the HUD.
func test_a_following_card_leaving_its_cell_reverts_to_the_hud() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	check(not controls.is_empty(), "the dealt board offers a card control to read",
			str(controls.size()))
	if not controls.is_empty():
		await _lock_without_holding(controls[0])
		var carried : Control = null
		for control : Control in await _entrance_card_controls():
			if _play_area.ui_data[control] != _play_area.locked_data:
				carried = control
				break
		check(carried != null, "the board offers an Entrance card OTHER than the locked one to hold")
		if carried != null:
			var visual := await _drag_past_the_threshold(carried)
			var dismissals : Array[int] = []
			_container.description_dismissed.connect(func() -> void: dismissals.append(1))
			check(visual != null and visual.following and _container.showing_description()
					and dismissals.is_empty(),
					"a drag INSIDE the held card's own cell carries it and dismisses nothing",
					str(dismissals.size()))
			_hover(_off_the_board_point())
			await get_tree().process_frame
			check(hud_stack.visible and not _panel.visible,
					"a FOLLOWING card leaving its cell reverts the container to the HUD (1.7, Q268=a)")
			check(dismissals.size() == 1, "...announced exactly once", str(dismissals.size()))
	await _end_main_fixture()

## 1.8/B11/Q268=a: a card that is NOT following dismisses nothing -- a click lifts it and the pointer may leave.
func test_a_lifted_card_that_is_not_following_keeps_the_description() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _lift_by_click(entrance[0])
		var dismissals : Array[int] = []
		_container.description_dismissed.connect(func() -> void: dismissals.append(1))
		check(_container.showing_description() and not visual.following,
				"the click locked a description and the lifted card is not following")
		_hover(_off_the_board_point())
		await get_tree().process_frame
		check(_container.showing_description() and dismissals.is_empty(),
				"a card that was NOT following dismisses nothing when the pointer leaves (1.8)",
				str(dismissals.size()))
		check(not visual.following, "...and that motion started no following either")
	await _end_main_fixture()

## Round 2 review: with a card lifted, the focus moved off it describes its new cell with NO X; the X comes back with the lifted card's own description.
func test_only_the_stuck_entry_carries_the_x_while_a_card_is_lifted() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to lift",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lift_by_click(entrance[0])
		var title : Label = _panel.get_node(^"%Title")
		var lifted_title := title.text
		check(_container.is_locked() and _exit_button().visible,
				"sanity: the click lifted and stuck the card, X shown")
		await _push_arrow(_game_viewport, KEY_UP)
		var elsewhere := _game_viewport.gui_get_focus_owner()
		print("P59 MEASURE after Up: focus=%s title=%s locked=%s x=%s held=%d"
				% [elsewhere, title.text, _container.is_locked(), _exit_button().visible,
						_play_area.selected_cards.size()])
		check(elsewhere != entrance[0] and _container.showing_description()
				and _panel.current_entry != _container._locked_entry_by_screen[&"game"],
				"Up moved the focus off the lifted card and the sidebar describes the new cell",
				title.text)
		check(not _exit_button().visible and _exit_button().focus_mode == Control.FOCUS_NONE,
				"...with no X, and no X in the focus chain: the stuck card is not what is shown",
				str(_exit_button().visible))
		entrance[0].grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		check(title.text == lifted_title and _exit_button().visible,
				"the focus back on the lifted card shows its description and the X again",
				"%s x=%s" % [title.text, _exit_button().visible])
		await _push_arrow(_game_viewport, KEY_UP)
		_play_area.sidebar_requested.emit()
		await get_tree().process_frame
		check(_booted_viewport.gui_get_focus_owner() == _exit_button() and title.text == lifted_title,
				"a key into the sidebar from another cell brings the stuck entry back and lands on its X",
				"%s %s" % [_booted_viewport.gui_get_focus_owner(), title.text])
		_hover(_another_card_control(await _hoverable_card_controls(),
				_play_area.ui_data[entrance[0]]).get_global_rect().get_center())
		await get_tree().process_frame
		print("P59 MEASURE hover while X focused: x=%s overlay_focus=%s title=%s"
				% [_exit_button().visible, _booted_viewport.gui_get_focus_owner(), title.text])
		check(_exit_button().visible or _booted_viewport.gui_get_focus_owner() != _exit_button(),
				"a hover that hides the X leaves no focus stranded on it",
				str(_booted_viewport.gui_get_focus_owner()))
		_hover(_off_the_board_point())
		await get_tree().process_frame
		await _push_arrow(_game_viewport, KEY_UP)
		_push_key(_game_viewport, KEY_ESCAPE, true)
		_push_key(_game_viewport, KEY_ESCAPE, false)
		await get_tree().process_frame
		await get_tree().process_frame
		check(_play_area.selected_cards.is_empty(),
				"with the X hidden a key cancel still puts the lifted card down",
				str(_play_area.selected_cards.size()))
	await _end_main_fixture()

## Round 2 review: a stuck viewer card gives the X up while another viewer card is focused, and takes it back with its own description.
func test_only_the_stuck_viewer_card_carries_the_x() -> void:
	await _start_game_fixture()
	_container.show_hud()
	var cards := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	check(cards.size() >= 2, "the deck viewer lists cards to point at", str(cards.size()))
	if cards.size() >= 2:
		await _click(cards[0].get_global_rect().get_center(), _booted_viewport)
		check(_container.is_locked() and _exit_button().visible,
				"sanity: the click stuck the first card, X shown")
		cards[1].grab_focus()
		await get_tree().process_frame
		check(_container.is_locked() and not _exit_button().visible,
				"another viewer card focused is described with no X", str(_exit_button().visible))
		cards[0].grab_focus()
		await get_tree().process_frame
		check(_exit_button().visible, "back on the stuck card, the X is back",
				str(_exit_button().visible))
	await _end_main_fixture()

# ------------------------------------------------ S15: NOTHING IS HELD UNTIL THE PLAYER ACTS

# How many placements the Entrance is emptied in before a refill is called a no-show: five slots,
# plus room for a placement the committed grid refuses.
const ENTRANCE_REFILL_PLACEMENTS := 8

## The card in the player's hand right now, read from the live selection -- never stored by the test.
func _held_card() -> CardData:
	return _play_area.selected_cards[0] if _play_area.selected_cards else null

## The leftmost Entrance card the STATE holds.
func _leftmost_present_card() -> CardData:
	var slot := TestGridFixtures.leftmost_entrance_slot()
	if slot == -1: return null
	return CardEnvironment.get_current_game().state.upper_zone[slot].datas.back()

# A placement can start a scoring cascade, and nothing the board does afterwards lands until that
# cascade ends. Bounded, and it returns the instant the board is idle.
func _await_the_board_idle() -> void:
	var game := CardEnvironment.get_current_game()
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not game.processing: return

# Places whatever is in hand the way a player does -- one click on a cell that accepts it -- and
# hands back the card that landed, or null when nowhere takes it. A board COMMITTED to one grid
# refuses a legal-looking cell in every other, so cells are tried until the card really moves.
func _place_the_held_card() -> CardData:
	var held := _held_card()
	if held == null: return null
	var candidates := await _hoverable_card_controls()
	while true:
		var target := await _placement_target(candidates, [held] as Array[CardData], true)
		if target == null: return null
		await _click_card(target)
		await _await_the_board_idle()
		if _held_card() != held: return held
		candidates.erase(target)
	return null

# The whole interaction a player makes to move one card: a click on the leftmost Entrance card to
# lift it, then a click on a cell that takes it.
func _lift_and_place_a_card() -> CardData:
	var entrance := await _entrance_card_controls()
	if entrance.is_empty(): return null
	await _click_card(entrance[0])
	return await _place_the_held_card()

# The same placement by keys alone: Down onto an Entrance card, accept to lift it, Up into the grid,
# the arrows to a cell that takes it, accept.
func _lift_and_place_a_card_by_keys() -> CardData:
	var on_the_entrance := func() -> bool:
		var owner := _game_viewport.gui_get_focus_owner()
		return owner != null and _play_area.upper_zone_right.is_ancestor_of(owner)
	await _tap_until(KEY_DOWN, on_the_entrance, 8)
	if not on_the_entrance.call(): return null
	var card : CardData = _play_area.ui_data[_game_viewport.gui_get_focus_owner()]
	for key : Key in [KEY_ENTER, KEY_UP] as Array[Key]:
		await _tap_key(key)
	var keys := await TestGridFixtures.arrow_keys_to_a_legal_cell(
			_play_area._coord_of_control(_game_viewport.gui_get_focus_owner()), card)
	for key : Key in keys:
		await _tap_key(key)
	await _tap_key(KEY_ENTER)
	await _await_the_board_idle()
	var state := CardEnvironment.get_current_game().state
	var landed := (_play_area.selected_cards.is_empty()
			and _play_area._entrance_slot_holding(state, card) == -1)
	return card if landed else null

# Undo is pressed by hand here: a real click in the window's viewport, on Undo or on the exit X,
# empties the game picture's focus owner (measured), which is the one reading this row makes.
## 6.2/B3/Q240=a: a freshly dealt show holds nothing and opens no description -- it is the HUD.
func test_a_fresh_show_holds_nothing_and_shows_the_hud() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	check(TestGridFixtures.leftmost_entrance_slot() != -1, "the deal filled the Entrance",
			str(TestGridFixtures.leftmost_entrance_slot()))
	check(_play_area.selected_cards.is_empty(),
			"...and left nothing in the player's hand", str(_play_area.selected_cards.size()))
	var lifted : Array[CardData] = []
	for data : CardData in _play_area.data_card:
		if _play_area.data_card[data].held != 0: lifted.append(data)
	check(lifted.is_empty(), "...and no card on the board is lifted", str(lifted.size()))
	check(hud_stack.visible and not _panel.visible,
			"a freshly dealt show still shows the HUD (6.2, Q240=a)")
	await _end_main_fixture()

## G10/Q251=b: the show rests the opening focus on a grid cell a pad can move from, ONCE, and silently.
func test_the_show_rests_the_opening_focus_on_a_board_cell() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var owner := _game_viewport.gui_get_focus_owner()
	check(owner != null and _play_area.ui_data.has(owner),
			"the show's opening focus rests on a board control (G10, Q251=b)",
			"picture=%s root=%s" % [owner, _booted_viewport.gui_get_focus_owner()])
	check(owner != null and _play_area.ui_data.has(owner)
			and _zone_card_of(_play_area.ui_data[owner]) != null,
			"...a grid cell's own control, which is what a pad steps from with nothing in hand",
			str(owner))
	check(hud_stack.visible and not _panel.visible,
			"...silently: the container still shows the HUD (Q240=a)")
	await _end_main_fixture()

## Q116/G14: a placement empties the hand and puts nothing back into it.
func test_a_placement_leaves_nothing_held() -> void:
	await _start_game_fixture()
	var placed := await _lift_and_place_a_card()
	check(placed != null, "a lifted card found a cell to land on")
	if placed != null:
		check(_play_area.selected_cards.is_empty(),
				"the placement left nothing in hand (Q116)", str(_play_area.selected_cards.size()))
		check(_leftmost_present_card() != null and _leftmost_present_card() != placed,
				"...with a card still waiting in the Entrance for the player to take (G14)")
	await _end_main_fixture()

# A real deck clears the default goal inside these few placements, ending the show before its next
# refill, so the goal goes out of reach and this stays a test about refills.
## Q118/G14: the Entrance refills left to right, and the refill still leaves the hand empty.
func test_a_refill_fills_the_leftmost_slot_and_holds_nothing() -> void:
	await _start_game_fixture()
	CardEnvironment.get_current_game().state.goal = GOAL_OUT_OF_REACH
	var dealt : Array[CardData] = []
	for column : ArrayCardData in CardEnvironment.get_current_game().state.upper_zone:
		dealt.append_array(column.datas)
	var refilled := false
	for attempt : int in ENTRANCE_REFILL_PLACEMENTS:
		if await _lift_and_place_a_card() == null: break
		var leftmost := _leftmost_present_card()
		if leftmost != null and leftmost not in dealt:
			refilled = true
			break
	check(refilled, "placing the Entrance out refills it", str(dealt.size()))
	if refilled:
		check(TestGridFixtures.leftmost_entrance_slot() == 0,
				"the refill lands in the leftmost slot (Q118)",
				str(TestGridFixtures.leftmost_entrance_slot()))
		check(_play_area.selected_cards.is_empty(),
				"...and nothing picks the refilled card up for the player (Q118, G14)",
				str(_play_area.selected_cards.size()))
	await _end_main_fixture()

## A show resumed mid-cascade must stand where the live show would have: refilled, and holding nothing.
func test_a_resumed_placement_leaves_nothing_held() -> void:
	await _start_game_fixture()
	var game := CardEnvironment.get_current_game()
	game.state.goal = GOAL_OUT_OF_REACH
	var kept : CardData = game.state.upper_zone[0].datas.back()
	for column : ArrayCardData in game.state.upper_zone:
		column.datas.clear()
	game.state.upper_zone[0].datas.append(kept)
	var grid : GridData = game.state.grids[0]
	check(grid.cells[grid.cell_index(0, 0)].datas.is_empty(), "sanity: the target cell is empty")
	var stocked := game.state.entrance_stocks().filter(
			func(stock: ArrayCardData) -> bool: return not stock.datas.is_empty())
	check(not stocked.is_empty(), "sanity: the stocks still hold cards to refill from")
	game.state.revision += 1
	game.save_state()
	RunManager.run.pending_action = &"on_placement"
	RunManager.run.pending_placement_slot = 0
	RunManager.run.pending_placement_coord = Vector4i(0, 0, 0, 0)
	_main._pictures[&"game"].detach_screen()
	await _restart_the_show()
	var resumed := CardEnvironment.get_current_game()
	var waited := 0.0
	while (resumed.processing or RunManager.run.pending_action != &"") \
			and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await _await_the_board_idle()
	var resumed_grid : GridData = resumed.state.grids[0]
	check(not resumed.processing and RunManager.run.pending_action == &""
			and not resumed_grid.cells[resumed_grid.cell_index(0, 0)].datas.is_empty(),
			"sanity: the resume replayed the placement and handed the board back (Q233=b)")
	check(TestGridFixtures.leftmost_entrance_slot() != -1,
			"sanity: the refill drew into the Entrance the placement emptied")
	check(_play_area.selected_cards.is_empty(),
			"the resumed show hands the board back holding nothing (Q116/Q118, Q233=b)",
			str(_play_area.selected_cards.size()))
	var lifted : Array[CardData] = []
	for data : CardData in _play_area.data_card:
		if _play_area.data_card[data].held != 0: lifted.append(data)
	check(lifted.is_empty(), "...and no card of its refill is lifted", str(lifted.size()))
	await _end_main_fixture()

## 6.10/G16/Q117=a: an undo restores the board and leaves the hand empty -- nothing picks a card back up.
func test_an_undo_leaves_nothing_held() -> void:
	await _start_game_fixture()
	var placed := await _lift_and_place_a_card()
	check(placed != null, "a lifted card found a cell to land on")
	if placed != null:
		check(await _click_button(_container.undo_button, _booted_viewport),
				"a real click on Undo pressed it (6.10)")
		await _await_the_board_idle()
		check(_play_area.selected_cards.is_empty(),
				"the undo left nothing in hand (6.10, Q117=a)",
				str(_play_area.selected_cards.size()))
		var restored := _leftmost_present_card()
		check(restored != null
						and _expected_text(restored)[0] == _expected_text(placed)[0],
				"...with the card it put back waiting in the Entrance -- an undo rebuilds the board's own card objects, so it is the same card by name (6.10, G16)")
		var lifted : Array[CardData] = []
		for data : CardData in _play_area.data_card:
			if _play_area.data_card[data].held != 0: lifted.append(data)
		check(lifted.is_empty(), "...and nothing on the restored board is lifted (6.10)",
				str(lifted.size()))
	await _end_main_fixture()

## Q114=a: clicking an Entrance card lifts it AND locks its description; clicking another moves the hold.
func test_clicking_another_entrance_card_moves_the_hold_onto_it() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(entrance.size() >= 2, "the dealt Entrance offers two cards to click",
			str(entrance.size()))
	if entrance.size() >= 2:
		var first : CardData = _play_area.ui_data[entrance[0]]
		await _click_card(entrance[0])
		check(_held_card() == first, "the first click lifted the card it landed on (Q114=a)")
		var other := _another_card_control(await _entrance_card_controls(), first)
		check(other != null, "the dealt Entrance offers a second card to click")
		if other != null:
			var wanted : CardData = _play_area.ui_data[other]
			await _click_card(other)
			check(_held_card() == wanted,
					"a click on another Entrance card moves the hold onto it (Q114=a)")
			check(_play_area.selected_cards.size() == 1,
					"...and lets the first one go", str(_play_area.selected_cards.size()))
			check(_container.is_locked() and _play_area.locked_data == wanted,
					"...and the same click locks that card's description (Q114=a)")
	await _end_main_fixture()

## 1.9: a click while the board resolves an act picks nothing up.
func test_a_click_during_processing_grabs_nothing() -> void:
	await _start_game_fixture()
	var game := CardEnvironment.get_current_game()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if not entrance.is_empty():
		game.processing = true
		await _click_card(entrance[0])
		check(_play_area.selected_cards.is_empty(),
				"the click during a cascade grabbed nothing (1.9)",
				str(_play_area.selected_cards.size()))
		game.processing = false
		await _await_the_board_idle()
		check(_play_area.selected_cards.is_empty(),
				"...and the cascade ending picks nothing up for the player either (1.9)",
				str(_play_area.selected_cards.size()))
	await _end_main_fixture()

## 1.9: a click on a card no rule grabs leaves the hand exactly as empty as it was.
func test_a_click_on_a_card_no_rule_grabs_leaves_the_hand_empty() -> void:
	await _start_game_fixture()
	var hoverable := await _hoverable_card_controls()
	var refused : Control = null
	for control : Control in hoverable:
		if not _play_area.upper_zone_right.is_ancestor_of(control) and _is_selectable(control):
			refused = control
			break
	check(refused != null, "the dealt board offers a grid card no rule grabs")
	if refused != null:
		await _click_card(refused)
		check(_play_area.selected_cards.is_empty(), "the click on that card grabbed nothing (1.9)",
				str(_play_area.selected_cards.size()))
		var lifted : Array[CardData] = []
		for data : CardData in _play_area.data_card:
			if _play_area.data_card[data].held != 0: lifted.append(data)
		check(lifted.is_empty(), "...and lifted nothing anywhere else (1.9)", str(lifted.size()))
	await _end_main_fixture()

## Q115=a: letting the held card go leaves nothing held, "and the next click on a cell does nothing".
func test_the_disarm_leaves_nothing_held() -> void:
	await _start_game_fixture()
	var game := CardEnvironment.get_current_game()
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var cell := await _placement_target(await _hoverable_card_controls(), held, true)
		check(cell != null, "the board offers a cell that card could have landed on")
		_play_area.ungrab_cards()
		await get_tree().process_frame
		await get_tree().process_frame
		check(_play_area.selected_cards.is_empty(),
				"the release left nothing held, and nothing picked one back up (Q115=a)",
				str(_play_area.selected_cards.size()))
		if cell != null:
			var before := game.state.revision
			await _click_card(cell)
			check(game.state.revision == before,
					"...so the next click on a cell does nothing (Q115=a)",
					"%d vs %d" % [game.state.revision, before])
	await _end_main_fixture()

## Q119=a: an empty Entrance has nothing to lift, and a click on a cell then does nothing at all.
func test_an_empty_entrance_lifts_nothing() -> void:
	await _start_game_fixture()
	for column : ArrayCardData in CardEnvironment.get_current_game().state.upper_zone:
		column.datas.clear()
	_play_area.setup_gui()
	await get_tree().process_frame
	check(TestGridFixtures.leftmost_entrance_slot() == -1,
			"an emptied Entrance holds no card to lift")
	check(_play_area.selected_cards.is_empty(), "...and nothing is held (Q119=a)",
			str(_play_area.selected_cards.size()))
	var cells := await _hoverable_card_controls()
	if not cells.is_empty():
		await _click_card(cells[0])
		check(_play_area.selected_cards.is_empty(),
				"...and a click on a cell with nothing held picks nothing up (Q119=a)")
	await _end_main_fixture()

## 6.11/G12/`GAP-005`=a: the highlight IS the drop map -- it lights what the board accepts, nothing it refuses, and it follows the answer when a placement changes it.
func test_the_legal_cell_highlight_follows_what_a_placement_accepts() -> void:
	await _start_game_fixture()
	var filler := await _fill_a_cell_from_the_entrance(0)
	check(filler != null, "the deal offered a second Entrance card to fill a cell with")
	var held := await _grab_a_card_to_place()
	if filler != null and not held.is_empty():
		var controls := await _hoverable_card_controls()
		var cell := _an_empty_cells_control(controls)
		var refused := await _placement_target(_cell_controls(controls), held, false)
		check(cell != null, "the dealt board offers an empty grid cell to aim at")
		check(refused != null, "...and a CELL this card may NOT land on -- never an Entrance card")
		if cell != null and refused != null:
			var zone_card : CardData = _play_area.ui_data[cell]
			var refused_cell := _zone_card_of(_play_area.ui_data[refused])
			var accepted := await _board_accepts(held, cell)
			check(accepted, "the board takes the held card onto that cell (6.11)")
			check(is_equal_approx(_glow_of(zone_card), _highlight_glow()),
					"...and the cell's zone card is DRAWN with the legal-cell brightening (6.11, G12)",
					str(_glow_of(zone_card)))
			check(is_equal_approx(_glow_of(refused_cell), 1.0),
					"a cell the board refuses is drawn unlit (6.11, G12)",
					str(_glow_of(refused_cell)))
			cell.grab_focus()
			await get_tree().process_frame
			check(_play_area.data_card[zone_card].focused
					and is_equal_approx(_glow_of(zone_card), _highlight_glow()),
					"a cell that is legal AND focused is drawn at that ONE glow and never its "
					+ "square: the focus is an outline and brightens nothing (6.11, G12)",
					"focused %s, glow %f" % [str(_play_area.data_card[zone_card].focused),
					_glow_of(zone_card)])
			var marked_before := TestGridFixtures.lit_cell_count(_play_area)
			await _click_card(cell)
			await _hoverable_card_controls()
			check(_play_area.selected_cards.is_empty(),
					"the click placed the held card and emptied the hand (6.11)",
					str(_play_area.selected_cards.size()))
			check(TestGridFixtures.lit_cell_count(_play_area) == 0,
					"...so the placement left no cell lit (6.11, G12)",
					str(TestGridFixtures.lit_cell_count(_play_area)))
			var now_held := await _grab_a_card_to_place()
			var still_accepted := await _board_accepts(now_held, _play_area.data_ui[held[0]])
			check(not still_accepted, "the filled cell takes nothing more (6.11)")
			check(is_equal_approx(_glow_of(zone_card), 1.0),
					"...so the cell that was legal has lost the highlight (6.11, G12)",
					str(_glow_of(zone_card)))
			var marked_after := TestGridFixtures.lit_cell_count(_play_area)
			check(marked_after == marked_before - 1,
					"...and every cell still legal kept the highlight (6.11, G12)",
					"%d marked, was %d" % [marked_after, marked_before])
	await _end_main_fixture()

## 6.11/G12: the DIRECT rebuild (setup_gui, undo) re-sweeps the drop map too -- a cell filled behind the arm has left the map once the board is rebuilt.
func test_a_direct_rebuild_re_sweeps_the_drop_map() -> void:
	await _start_game_fixture()
	var state := CardEnvironment.get_current_game().state
	var held := await _grab_a_card_to_place()
	var zone_card : CardData = state.grids[0].cell_types[0]
	check(zone_card in _play_area._legal_cells, "the empty cell is on the drop map before the fill")
	var filler := await _fill_a_cell_from_the_entrance(0)
	check(filler != null, "...and dealt a second Entrance card to fill a cell with")
	if not held.is_empty() and filler != null:
		var expected := await _drop_map(_play_area.selected_cards)
		check(zone_card not in expected, "the board refuses the filled cell")
		var swept := _play_area._legal_cells.size() == expected.size()
		for legal : CardData in expected:
			swept = swept and legal in _play_area._legal_cells
		check(swept, "a direct rebuild re-swept the drop map to what the board accepts (6.11, G12)",
				"%d mapped, %d legal" % [_play_area._legal_cells.size(), expected.size()])
		check(is_equal_approx(_glow_of(zone_card), 1.0),
				"...so the filled cell is drawn unlit (6.11, G12)", str(_glow_of(zone_card)))
	await _end_main_fixture()

# A fresh deal refuses NO cell -- every cell is empty and an empty cell takes anything -- so the
# fixture fills one behind the player's back, through the state and a direct rebuild: its top then
# refuses every card, because the standard rules carry no stacking placer. The filler, or null.
func _fill_a_cell_from_the_entrance(cell: int) -> CardData:
	var state := CardEnvironment.get_current_game().state
	if state.upper_zone.size() < 2 or state.upper_zone[1].datas.is_empty(): return null
	var filler : CardData = state.upper_zone[1].datas.back()
	state.upper_zone[1].datas.erase(filler)
	state.grids[0].cells[cell].datas.append(filler)
	filler.stage = CardData.Stage.PLAY
	state.invalidate_pos_index()
	_play_area.setup_gui()
	await get_tree().process_frame
	return filler

## The brightening this card's face is DRAWN with -- the uniform the shader gets, never the field.
func _glow_of(data: CardData) -> float:
	return TestGridFixtures.brightness_of(_play_area.data_card[data].type)

func _highlight_glow() -> float:
	return PlayArea.settings().highlight_glow

## An EMPTY cell's own zone control -- what a release onto that cell lands on.
func _an_empty_cells_control(controls: Array[Control]) -> Control:
	var game := CardEnvironment.get_current_game()
	for control : Control in controls:
		if not game.state.cell_type_coord(_play_area.ui_data[control]).is_nowhere(): return control
	return null

## The controls that sit in a CELL -- a zone control or a card stacked in one -- and never an Entrance card.
func _cell_controls(controls: Array[Control]) -> Array[Control]:
	var out : Array[Control] = []
	for control : Control in controls:
		if _zone_card_of(_play_area.ui_data[control]) != null: out.append(control)
	return out

## S18.2/F9: the second button with nothing held closes the description, and closes nothing else.
func test_the_second_button_dismisses_a_description_with_nothing_held() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _lock_without_holding(entrance[0])
		check(_container.showing_description() and _play_area.selected_cards.is_empty(),
				"the description is up and nothing is held before the press")
		await _second_button_press(entrance[0].get_global_rect().get_center())
		check(hud_stack.visible and not _panel.visible,
				"the second button reverts the container to the HUD (S18.2, Q99=b)")
		check(not _container.is_locked(), "...and the lock is gone with it (S18.2)")
	await _end_main_fixture()

## S18.2/Q100=c: the second button is cancel-only -- with nothing to cancel it is not a way out of the screen.
func test_the_second_button_with_nothing_to_cancel_does_nothing() -> void:
	await _start_game_fixture()
	var hud_stack : Control = _container.get_node(^"%HudStack")
	var controls := await _hoverable_card_controls()
	var at := _bare_board_point(controls)
	var went_back : Array[bool] = [false]
	_main.wall.back_requested.connect(func() -> void: went_back[0] = true)
	await _second_button_press(at)
	check(_play_area.selected_cards.is_empty(),
			"the first press released whatever the deal armed",
			str(_play_area.selected_cards.size()))
	await _second_button_press(at)
	check(hud_stack.visible and not _panel.visible,
			"with nothing held and nothing showing the second button leaves the HUD up (S18.2)")
	check(not went_back[0],
			"...and never reaches the wall's own Back (S18.2, F9)")
	await _end_main_fixture()

## S18.2/B15: the second button cancels from ANYWHERE on screen -- the overlay panel covers part of the board and must not swallow it.
func test_the_second_button_over_the_panel_still_cancels() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		check(not _play_area.selected_cards.is_empty() and _panel.visible,
				"the click left a card held with the description panel up",
				"%d held, panel %s" % [_play_area.selected_cards.size(), str(_panel.visible)])
		check(TestGridFixtures.lit_cell_count(_play_area) > 0,
				"precondition: the held card lit a drop map to put out",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		var at := _panel.get_global_rect().get_center()
		check(_container.get_global_rect().has_point(at),
				"the aim point is inside the container's own rect, where a click is eaten (S18.2)",
				"%s in %s" % [str(at), str(_container.get_global_rect())])
		await _second_button_press(at, _booted_viewport)
		await get_tree().process_frame
		check(_play_area.selected_cards.is_empty(),
				"a second-button press over the sidebar still released the held card (S18.2, B15)",
				str(_play_area.selected_cards.size()))
		check(TestGridFixtures.lit_cell_count(_play_area) == 0,
				"...and the drop map it lit went out with it (6.11, G12)",
				str(TestGridFixtures.lit_cell_count(_play_area)))
	await _end_main_fixture()

## Cancel reaches the board from anywhere on screen: the overlay's Back/Forward/Wall buttons sit outside the container and must not swallow it either.
func test_the_second_button_over_the_overlay_band_still_cancels() -> void:
	await _start_game_fixture()
	var overlay : WallOverlay = _main.wall.get_node(^"%Overlay")
	var pressed : Array[bool] = [false]
	var note := func() -> void: pressed[0] = true
	overlay.back_pressed.connect(note)
	overlay.forward_pressed.connect(note)
	overlay.wall_pressed.connect(note)
	for button_name : StringName in [&"%BackButton", &"%ForwardButton", &"%WallButton"]:
		var button : Control = overlay.get_node(NodePath(button_name))
		var entrance := await _entrance_card_controls()
		check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
				str(entrance.size()))
		if entrance.is_empty(): break
		await _click_card(entrance[0])
		check(not _play_area.selected_cards.is_empty(),
				"precondition: the click left a card held before the %s press" % button_name,
				str(_play_area.selected_cards.size()))
		check(TestGridFixtures.lit_cell_count(_play_area) > 0,
				"precondition: the held card lit a drop map to put out",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		var at := button.get_global_rect().get_center()
		check(button.is_visible_in_tree() and button.get_global_rect().has_point(at),
				"the aim point is on %s, where a click is eaten" % button_name,
				"%s in %s" % [str(at), str(button.get_global_rect())])
		await _second_button_press(at, _booted_viewport)
		await get_tree().process_frame
		check(_play_area.selected_cards.is_empty(),
				"a second-button press over %s still released the held card" % button_name,
				str(_play_area.selected_cards.size()))
		check(TestGridFixtures.lit_cell_count(_play_area) == 0,
				"...and the drop map it lit went out with it",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		check(not pressed[0], "...and the button itself was never pressed by it")
	await _end_main_fixture()

## S18.3/Q100=c/E22: ONE Escape releases the held card, dismisses the description and zooms out to the wall.
func test_escape_cancels_everything_and_steps_back_in_one_press() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		check(not _play_area.selected_cards.is_empty() and _container.showing_description(),
				"the click left a card held with its description locked")
		check(TestGridFixtures.lit_cell_count(_play_area) > 0,
				"precondition: the held card lit a drop map to put out",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		var left_the_screen : Array[bool] = [false]
		_main.wall.wall_view_entered.connect(func() -> void: left_the_screen[0] = true)
		_booted_viewport.push_input(_cancel_event())
		await get_tree().process_frame
		await get_tree().process_frame
		check(_play_area.selected_cards.is_empty(),
				"one Escape released the held card (S18.3, E22)",
				str(_play_area.selected_cards.size()))
		check(TestGridFixtures.lit_cell_count(_play_area) == 0,
				"...and the drop map it lit went out with it (6.11, G12)",
				str(TestGridFixtures.lit_cell_count(_play_area)))
		check(not _container.showing_description(),
				"...dismissed the description in the SAME press (S18.3, Q100=c)")
		check(left_the_screen[0],
				"...and still left the screen, for WALL VIEW (S18.3, owner ruling)")
	await _end_main_fixture()

## S18.4/E20: releasing the held card is not a dismissal -- a locked description outlives it.
func test_releasing_the_held_card_leaves_the_locked_description_up() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a clickable Entrance card",
			str(entrance.size()))
	if not entrance.is_empty():
		await _click_card(entrance[0])
		var locked := _play_area.locked_data
		check(_container.is_locked() and locked != null,
				"the click locked the description to the card it held")
		await _second_button_press(entrance[0].get_global_rect().get_center())
		check(_play_area.selected_cards.is_empty(), "the release let the card go (S18.4)")
		check(_container.showing_description() and _container.is_locked(),
				"...and the lock it was read against is untouched (S18.4, E20)")
		check(_play_area.locked_data == locked,
				"...still on the same card (S18.4)")
	await _end_main_fixture()

## S18.5/Q115=a/Q114=a: a cancel empties the hand, the next click on a cell does nothing, and only a click on an Entrance card lifts again.
func test_a_cancel_needs_a_click_on_an_entrance_card_to_lift_again() -> void:
	await _start_game_fixture()
	var game := CardEnvironment.get_current_game()
	var held := await _grab_a_card_to_place()
	if not held.is_empty():
		var controls := await _hoverable_card_controls()
		var cell := await _placement_target(controls, held, true)
		check(cell != null, "the board offers a cell that card could have landed on")
		await _second_button_press(_bare_board_point(controls))
		check(_play_area.selected_cards.is_empty(),
				"the cancel emptied the hand, and nothing picked a card back up (S18.5, Q115=a)",
				str(_play_area.selected_cards.size()))
		if cell != null:
			var before := game.state.revision
			await _click_card(cell)
			check(game.state.revision == before,
					"...so the next click on a cell does nothing (S18.5, Q115=a)",
					"%d vs %d" % [game.state.revision, before])
		var entrance := await _entrance_card_controls()
		if not entrance.is_empty():
			var wanted : CardData = _play_area.ui_data[entrance[0]]
			await _click_card(entrance[0])
			check(_held_card() == wanted,
					"...and a click on an Entrance card lifts it (S18.5, Q114=a)")
	await _end_main_fixture()

# The board's arrows must stay on the board's own cards: focus parked on the scroll container
# leaves accept inert and draws its focus border across the picture.
func test_an_arrow_from_an_entrance_card_leaves_the_focus_on_the_board() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to focus from",
			str(entrance.size()))
	if not entrance.is_empty():
#⚠ LEFT IS NOT ON THIS LIST (P40): off the strip's leftmost stop it is the sidebar's door, and
#where it lands is asserted there. The rule this row pins is about the arrows that STAY.
		for keycode : Key in [KEY_UP, KEY_DOWN, KEY_RIGHT]:
			entrance[0].grab_focus()
			await get_tree().process_frame
			_push_key(_game_viewport, keycode, true)
			await get_tree().process_frame
			var owner := _game_viewport.gui_get_focus_owner()
			check(owner != null and _play_area.ui_data.has(owner),
					"an arrow from an Entrance card leaves a board card focused, not a container",
					"%s -> %s" % [OS.get_keycode_string(keycode), owner])
			_push_key(_game_viewport, keycode, false)
			await get_tree().process_frame
	await _end_main_fixture()

## A following card keeps following wherever the pointer goes, including over the container -- witnessed by the cell-leave ask, which only a card the player did NOT click to lock still makes.
func test_motion_over_the_container_reaches_the_following_card() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers a card to pick up",
			str(entrance.size()))
	if not entrance.is_empty():
		var visual := await _drag_past_the_threshold(entrance[0])
		check(visual != null and visual.following,
				"a drag inside its own cell left the card following the pointer",
				str(_play_area.selected_cards.size()))
		var reached : Array[bool] = [false]
		_play_area.description_dismiss_requested.connect(func() -> void: reached[0] = true)
		check(_container.mouse_filter == Control.MOUSE_FILTER_STOP
				and _container.get_global_rect().has_point(_container.container_rect().get_center()),
				"the container really is a blocking control under that point",
				"filter %d, rect %s" % [_container.mouse_filter, _container.get_global_rect()])
		_hover_in(_booted_viewport, _container.container_rect().get_center())
		await get_tree().process_frame
		await get_tree().process_frame
		check(reached[0], "motion over the container reached the board's pointer reader",
				"dismiss %s" % reached[0])
	await _end_main_fixture()

# ==============================================================================
# S21 -- THE ENTRANCE DRAWS FACE DOWN AND FLIPS IN PLACE
# ==============================================================================

## An Entrance coordinate in the fixture's own board, for the slot geometry these tests measure.
func _entrance_coord(slot: int) -> BoardCoord:
	return BoardCoord.new(0, slot, BoardCoord.ENTRANCE_ROW, 0)

## The live game behind the fixture's board.
func _fixture_game() -> Game:
	return (_main._pictures[&"game"].screen_root as GameView).game

# Every slot is emptied INTO THE DISCARD rather than dropped, so no card stops being reachable
# from the state -- which is what the leak sentinel measures.
func _empty_every_entrance_slot() -> void:
	for slot : int in _fixture_game().state.upper_zone.size():
		await _discard_held_cards_of(slot)

# One slot emptied the same way, leaving its stock alone -- a slot that holds nothing but still
# draws its face-down card.
func _discard_held_cards_of(slot: int) -> void:
	var state := _fixture_game().state
	state.discard_deck.append_array(state.upper_zone[slot].datas)
	state.upper_zone[slot].datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame

## The controls of `slot` that draw its face-down stock.
func _stock_controls(slot: int) -> Array[Control]:
	var out : Array[Control] = []
	for child : Node in _play_area.upper_zone_right.get_child(slot).get_children():
		var control := child as Control
		if _play_area.is_stock_control(control): out.append(control)
	return out

## S21.1: no fly-in -- a card drawn into a slot whose empty stock left it no entity is BORN there. The delay is raised because the suite's own 0.01 s would carry a wrong spawn home before the first frame.
func test_a_refilled_card_appears_in_its_own_slot() -> void:
	await _start_game_fixture()
	var settings := SettingsManager.settings
	var old_delay := settings.base_delay
	settings.base_delay = 1.0
	var state := _fixture_game().state
	await _empty_every_entrance_slot()
	for stock : ArrayCardData in state.entrance_stocks():
		state.discard_deck.append_array(stock.datas)
		stock.datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame
	var returning : CardData = state.discard_deck.pop_back()
	state.entrance_stocks()[0].datas.append(returning)
	await _fixture_game().refill_entrance_if_due()
	_play_area.flush_rebuild()
	await get_tree().process_frame
	var drawn : CardData = state.upper_zone[0].datas.back()
	var visual : CardVisual = _play_area.data_card[drawn]
	var slot_centre := _play_area.slot_center_global(_entrance_coord(0))
	check(drawn == returning and visual.global_position.distance_to(slot_centre) <= 1.0,
			"the refilled card's visual is created at its own slot, not at the Deck button (S21.1)",
			"%s vs slot %s" % [visual.global_position, slot_centre])
	settings.base_delay = old_delay
	await _end_main_fixture()

## S21.2: a slot still holding a card keeps it, face up and in the same visual; only the empty slots draw and flip.
func test_only_the_empty_slots_flip() -> void:
	await _start_game_fixture()
	var settings := SettingsManager.settings
	var old_delay := settings.base_delay
	var old_stagger := settings.entrance_flip_stagger
	settings.base_delay = 1.0
	settings.entrance_flip_stagger = 0.5
	var state := _fixture_game().state
	check(state.upper_zone.size() >= 2, "sanity: the board has more than one Entrance slot",
			str(state.upper_zone.size()))
	for i : int in range(1, state.upper_zone.size()):
		state.discard_deck.append_array(state.upper_zone[i].datas)
		state.upper_zone[i].datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame
	var kept : CardData = state.upper_zone[0].datas.back()
	var kept_visual : CardVisual = _play_area.data_card[kept]
	await _fixture_game().run_all_mods(&"on_refill")
	_play_area.flush_rebuild()
	await get_tree().process_frame
	var still_held : CardData = state.upper_zone[0].datas.back()
	check(still_held == kept
			and _play_area.data_card[kept] == kept_visual
			and not kept_visual.face_down,
			"the slot that already held a card keeps it, face up, in the same visual (S21.2)")
	var flipping := 0
	for i : int in range(1, state.upper_zone.size()):
		var drawn : CardData = state.upper_zone[i].datas.back()
		if _play_area.data_card[drawn].face_down: flipping += 1
	check(flipping == state.upper_zone.size() - 1,
			"...and every slot that was empty drew a card that is still turning over (S21.2)",
			str(flipping))
	settings.base_delay = old_delay
	settings.entrance_flip_stagger = old_stagger
	await _end_main_fixture()

## S21.3: the slots turn over left to right, one `entrance_flip_stagger` of the game's delay apart.
func test_the_flip_waits_one_stagger_per_slot() -> void:
	await _start_game_fixture()
	var settings := SettingsManager.settings
	var old_delay := settings.base_delay
	var old_stagger := settings.entrance_flip_stagger
	settings.base_delay = 1.0
	settings.entrance_flip_stagger = 0.5
	var state := _fixture_game().state
	var last := state.upper_zone.size() - 1
	check(last >= 2, "sanity: three slots or more to stagger", str(state.upper_zone.size()))
	await _empty_every_entrance_slot()
	await _fixture_game().refill_entrance_if_due()
	_play_area.flush_rebuild()
	await get_tree().process_frame
	var step : float = settings.entrance_flip_stagger * _fixture_game().get_delay()
	check(is_zero_approx(_play_area.entrance_flip_delay(0))
			and is_equal_approx(_play_area.entrance_flip_delay(1), step)
			and is_equal_approx(_play_area.entrance_flip_delay(2), 2.0 * step),
			"slot i waits i staggers of the game's own delay, left to right (S21.3)",
			"%f, %f, %f (step %f)" % [_play_area.entrance_flip_delay(0),
					_play_area.entrance_flip_delay(1), _play_area.entrance_flip_delay(2), step])
	settings.entrance_flip_stagger = 0.25
	var narrower : float = settings.entrance_flip_stagger * _fixture_game().get_delay()
	check(is_equal_approx(_play_area.entrance_flip_delay(1), narrower) and narrower < step,
			"...and the spacing is the knob's, not a number of its own (S21.3)",
			"%f vs %f" % [_play_area.entrance_flip_delay(1), narrower])
	settings.entrance_flip_stagger = 0.5
	await get_tree().create_timer(0.25).timeout
	check(not _play_area.data_card[state.upper_zone[0].datas.back()].face_down
			and _play_area.data_card[state.upper_zone[last].datas.back()].face_down,
			"...and on the board the leftmost slot has turned over while the last still has not",
			"last slot %d" % last)
	settings.base_delay = old_delay
	settings.entrance_flip_stagger = old_stagger
	await _end_main_fixture()

## S21.4: a slot shows ONE face-down card however deep its stock is -- the rest are not entities at all.
func test_a_slot_shows_one_face_down_card_whatever_its_depth() -> void:
	await _start_game_fixture()
	var state := _fixture_game().state
	var dealt_visual : CardVisual = _play_area.data_card[state.upper_zone[0].datas.back()]
	var waited := 0.0
	while not dealt_visual.show_front and waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(dealt_visual.show_front,
			"sanity: the dealt card has turned over once the game screen is focused and running",
			"waited %.2fs" % waited)
	check(state.upper_zone.size() >= 4, "sanity: four slots to stock differently",
			str(state.upper_zone.size()))
	var pool := state.all_stock_cards()
	check(pool.size() >= 9, "sanity: the deal leaves enough cards to stock them", str(pool.size()))
	var stocks := state.entrance_stocks()
	stocks[0].datas.assign(pool.slice(0, 8))
	stocks[1].datas.assign(pool.slice(8, 9))
	stocks[2].datas.clear()
	stocks[3].datas.clear()
	state.discard_deck.append_array(pool.slice(9))
	for i : int in range(4, stocks.size()):
		stocks[i].datas.clear()
	state.discard_deck.append_array(state.upper_zone[3].datas)
	state.upper_zone[3].datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame
	check(_card_entities(0) == 2 and _card_entities(1) == 2
			and _card_entities(2) == 1 and _card_entities(3) == 0,
			"a stock of eight is one face-down card, of one the same, an exhausted slot none (S21.4)",
			"%d, %d, %d, %d" % [_card_entities(0), _card_entities(1), _card_entities(2),
					_card_entities(3)])
	check(_stock_controls(0).size() == 1 and _stock_controls(2).is_empty(),
			"...and exactly one of a stocked slot's entities is the face-down card (S21.4)",
			"%d, %d" % [_stock_controls(0).size(), _stock_controls(2).size()])
	var frame : Control = _play_area.upper_zone_right.get_child(3).get_child(-1)
	check(frame.custom_minimum_size.y == CardVisual.card_size_play.y,
			"...and the empty slot with an empty stock is left showing its own frame (S21.4)",
			str(frame.custom_minimum_size))
	var face_down_visual : CardVisual = _play_area.data_card[
			_play_area.ui_data[_stock_controls(0)[0]]]
	var revealed_visual : CardVisual = _play_area.data_card[state.upper_zone[0].datas.back()]
	check(_type_frame_origin(face_down_visual) == _sheet_frame_origin(CardVisual.CARD_BACK_FRAME),
			"...and the face-down card draws the card back off the type sheet (S21.4)",
			str(_type_frame_origin(face_down_visual)))
	check(_type_frame_origin(revealed_visual) != _sheet_frame_origin(CardVisual.CARD_BACK_FRAME),
			"...while the revealed card above it draws its own type, not the back (S21.4)",
			str(_type_frame_origin(revealed_visual)))
	state.discard_deck.append(_fixture_game().draw_card(1))
	state.discard_deck.append_array(state.upper_zone[1].datas)
	state.upper_zone[1].datas.clear()
	_play_area.set_card_zones()
	await get_tree().process_frame
	check(_card_entities(1) == 0,
			"...and a slot whose last stock card has been drawn away is left with nothing (S21.4)",
			str(_card_entities(1)))
	await _end_main_fixture()

## S21.4b: the face-down card IS the next revealed card -- the same entity, turned over, with a fresh one beneath it.
func test_the_face_down_card_becomes_the_revealed_one() -> void:
	await _start_game_fixture()
	var settings := SettingsManager.settings
	var old_delay := settings.base_delay
	settings.base_delay = 1.0
	var state := _fixture_game().state
	await _empty_every_entrance_slot()
	var waiting : CardData = _play_area.ui_data[_stock_controls(0)[0]]
	var waiting_visual : CardVisual = _play_area.data_card[waiting]
	var next_down : CardData = state.entrance_stocks()[0].datas[-2]
	await _fixture_game().refill_entrance_if_due()
	_play_area.flush_rebuild()
	await get_tree().process_frame
	var revealed : CardData = state.upper_zone[0].datas.back()
	check(revealed == waiting and _play_area.data_card[revealed] == waiting_visual,
			"the card that was lying face down IS the revealed one, in the same entity (S21.4b)")
	check(_stock_controls(0).size() == 1
			and _play_area.ui_data[_stock_controls(0)[0]] == next_down,
			"...and one fresh face-down card has taken its place beneath (S21.4b)",
			"%d face down" % _stock_controls(0).size())
	settings.base_delay = old_delay
	await _end_main_fixture()

## Which frame of the type sheet a card DRAWS: a Polygon2D has no `frame`, so its shader clamp says it.
func _type_frame_origin(visual: CardVisual) -> Vector2:
	var uv : Vector4 = CardOutline.material_of(visual.type).get_shader_parameter(&"u_frame_uv")
	return (Vector2(uv.x, uv.y) * CardModifierType.TYPE_TEXTURE.get_size()).round()

## Where one frame of the type sheet starts, from the same source `CardOutline.frame_polygon` uses.
func _sheet_frame_origin(frame_index: int) -> Vector2:
	return CardModifier.frame_rect(CardModifierType.TYPE_TEXTURE, CardModifierType.H_FRAMES,
			CardModifierType.V_FRAMES, frame_index).position.round()

## The card entities a slot draws at all: its revealed cards plus its one face-down card, never its zone frame.
func _card_entities(slot: int) -> int:
	return _play_area.upper_zone_right.get_child(slot).get_child_count() - 1

## S21.8: a face-down stock card sits UNDER the slot's own card and never lifts it -- a lift means the player is holding that card.
func test_a_stocked_slot_draws_its_card_as_flat_as_an_exhausted_one() -> void:
	await _start_game_fixture()
	var state := _fixture_game().state
	check(state.upper_zone.size() >= 3,
			"sanity: three Entrance slots, so two are not the leftmost present one",
			str(state.upper_zone.size()))
	var leftmost := TestGridFixtures.leftmost_entrance_slot()
	check(leftmost != 1 and leftmost != 2,
			"sanity: neither slot under test is the leftmost present one", str(leftmost))
	var stocks := state.entrance_stocks()
	check(not stocks[1].datas.is_empty(), "sanity: slot 1 still has a stock behind its card",
			str(stocks[1].datas.size()))
	state.discard_deck.append_array(stocks[2].datas)
	stocks[2].datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame
	check(state.upper_zone[1].datas.size() == state.upper_zone[2].datas.size(),
			"sanity: the two slots hold the same number of cards",
			"%d vs %d" % [state.upper_zone[1].datas.size(), state.upper_zone[2].datas.size()])
	var stocked : CardVisual = _play_area.data_card[state.upper_zone[1].datas.back()]
	var bare : CardVisual = _play_area.data_card[state.upper_zone[2].datas.back()]
	await _await_card_settled(stocked)
	await _await_card_settled(bare)
	check(absf(stocked.global_position.y - bare.global_position.y) < 1.0,
			"a stocked slot's card sits as flat as an exhausted slot's (S21.8)",
			"%.1f vs %.1f" % [stocked.global_position.y, bare.global_position.y])
	var face_down : CardVisual = _play_area.data_card[_play_area.ui_data[_stock_controls(1)[0]]]
	await _await_card_settled(face_down)
	check(face_down.global_position.distance_to(stocked.global_position) < 1.0,
			"...and its face-down card rests at the same point, drawn under it (S21.8)",
			"%s vs %s" % [face_down.global_position, stocked.global_position])
	await _end_main_fixture()

## S21.5: a face-down card describes the SLOT -- how many it has left -- never the card it hides. The focus LEAVES and comes back for the second read: a control already focused publishes nothing.
func test_hovering_a_stock_says_how_many_it_has_left() -> void:
	await _start_game_fixture()
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var state := _fixture_game().state
	var stock_control := _stock_controls(1)[0]
	stock_control.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	var before : int = state.entrance_stocks()[1].datas.size()
	check(_container.showing_description() and body.text.contains(str(before)),
			"hovering the face-down stock publishes how many cards it has left (S21.5)",
			"%s vs %d" % [body.text, before])
	state.discard_deck.append(_fixture_game().draw_card(1))
	_play_area.set_card_zones()
	await get_tree().process_frame
	_stock_controls(0)[0].grab_focus()
	await get_tree().process_frame
	_stock_controls(1)[0].grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	check(body.text.contains(str(before - 1)),
			"...and drawing one card off it drops the count by one (S21.5)",
			"%s vs %d" % [body.text, before - 1])
	await _end_main_fixture()

## 4.7: one slot running out of stock is not an empty deck, and it drops nothing -- not even the card the player is holding off that very slot.
func test_one_drained_stock_drops_nothing() -> void:
	await _start_game_fixture()
	var state := _fixture_game().state
	state.goal = GOAL_OUT_OF_REACH
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if entrance.is_empty():
		await _end_main_fixture()
		return
	await _click_card(entrance[0])
	var held := _held_card()
	var slot := TestGridFixtures.leftmost_entrance_slot()
	check(held != null, "the click left that slot's card in hand", str(slot))
	state.discard_deck.append_array(state.entrance_stocks()[slot].datas)
	state.entrance_stocks()[slot].datas.clear()
	state.revision += 1
	_play_area.set_card_zones()
	await get_tree().process_frame
	check(not state.stocks_are_empty(), "that slot's drained stock is not an empty deck (4.7)",
			str(_stock_controls(slot).size()))
	check(_held_card() == held and TestGridFixtures.leftmost_entrance_slot() == slot,
			"...and nothing drops it: the same card is still held off its own drained slot (4.7)",
			"%s in %d" % [_held_card(), TestGridFixtures.leftmost_entrance_slot()])
	check(held != null and _play_area.data_card[held].held > 0,
			"...still lifted as a held card (4.7)")
	check(not (_main._pictures[&"game"].screen_root as GameView).submit_button.visible,
			"...and End is not revealed (4.7)")
	var placed := await _place_the_held_card()
	check(placed != null and placed == held, "the card off the drained slot still places (4.7)",
			str(placed))
	check(state.entrance_stocks()[slot].datas.is_empty(),
			"...its slot's refill had nothing to draw (4.7)",
			str(state.entrance_stocks()[slot].datas.size()))
	check(_play_area.selected_cards.is_empty(),
			"...and the placement left nothing in hand (4.7)",
			str(_play_area.selected_cards.size()))
	await _end_main_fixture()

## S21.5b: a CLICK on the face-down card describes the slot too -- it never hands the hidden card to the view, so nothing locks to a card the player cannot see.

# The slot is emptied first: a face-down card under a card the slot holds is covered by it exactly,
# so the only place a POINTER can reach one is a slot showing nothing else.
func test_clicking_a_stock_describes_the_slot_and_locks_nothing() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var state := _fixture_game().state
	await _discard_held_cards_of(1)
	var stock_control := _stock_controls(1)[0]
	var hidden : CardData = _play_area.ui_data[stock_control]
	var clicked := _watch_clicks()
	await _click_card(stock_control)
	check(clicked.is_empty(), "a click on the face-down stock selects no card at all (S21.5b)",
			_board_input_state(stock_control))
	check(not _container.is_locked() and _play_area.locked_data == null,
			"...so the sidebar is not locked to the hidden card (S21.5b)",
			str(_play_area.locked_data))
	check(title.text != hidden.rank.get_str()
			and body.text.contains(str(state.entrance_stocks()[1].datas.size())),
			"...and what it shows is the SLOT's remaining count, not that card (S21.5b)",
			"%s / %s" % [title.text, body.text])
	await _end_main_fixture()

## S21.5c: the keyboard accept on the face-down card reads the same as the click -- the slot, never the hidden card.
func test_accepting_a_stock_describes_the_slot_and_locks_nothing() -> void:
	await _start_game_fixture()
	var title : Label = _panel.get_node(^"%Title")
	var body : RichTextLabel = _panel.get_node(^"%Body")
	var state := _fixture_game().state
	var stock_control := _stock_controls(1)[0]
	var hidden : CardData = _play_area.ui_data[stock_control]
	var clicked := _watch_clicks()
	stock_control.grab_focus()
	await get_tree().process_frame
	_push_key(_game_viewport, KEY_ENTER, true)
	_push_key(_game_viewport, KEY_ENTER, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(clicked.is_empty(), "ui_accept on the face-down stock selects no card at all (S21.5c)",
			_board_input_state(stock_control))
	check(not _container.is_locked() and _play_area.locked_data == null,
			"...so the sidebar is not locked to the hidden card (S21.5c)",
			str(_play_area.locked_data))
	check(title.text != hidden.rank.get_str()
			and body.text.contains(str(state.entrance_stocks()[1].datas.size())),
			"...and what it shows is the SLOT's remaining count, not that card (S21.5c)",
			"%s / %s" % [title.text, body.text])
	await _end_main_fixture()

## The control an arrow can land on in `slot`: the topmost one the neighbour links point at.
func _slot_top_control(slot: int) -> Control:
	return _play_area.upper_zone_right.get_child(slot).get_child(0) as Control

## Presses one arrow on a focused board control and hands back whatever holds the focus after it.
func _focus_after_arrow(from: Control, keycode: Key) -> Control:
	from.grab_focus()
	await get_tree().process_frame
	_push_key(_game_viewport, keycode, true)
	await get_tree().process_frame
	_push_key(_game_viewport, keycode, false)
	await get_tree().process_frame
	return _game_viewport.gui_get_focus_owner()

## S21.7: an arrow never stops on a face-down card -- a slot holding nothing is walked past to the next slot that shows a card the player could play.
func test_an_arrow_never_stops_on_a_face_down_card() -> void:
	await _start_game_fixture()
	var state := _fixture_game().state
	state.goal = GOAL_OUT_OF_REACH
	check(state.upper_zone.size() >= 4, "sanity: four slots to leave gaps between",
			str(state.upper_zone.size()))
	var placed := await _lift_and_place_a_card()
#⚠ THE FIRST PLACEMENT IS WHAT COMMITS THE ENTRANCE, and the commitment slides the row from the
#centre of the window to its grid's columns. An arrow pressed mid-slide searches moving rects.

#⚠ FLUSHED AFTER THE WAIT, NOT BEFORE. Waiting lets a queued rebuild run, and a rebuild re-binds
#the pooled slot controls -- so the control the focus grabbed is no longer the one a later
#`_slot_top_control` read hands back, and the two compare unequal with nothing having moved.
	await _settle_entrance_x(_play_area)
	_play_area.flush_rebuild()
	check(placed != null and state.upper_zone[0].datas.is_empty(),
			"a placement empties the leftmost slot while its neighbours still hold cards (S21.7)",
			str(state.upper_zone[0].datas.size()))
	check(_stock_controls(0).size() == 1,
			"...and that slot still draws its face-down card (S21.7)",
			str(_stock_controls(0).size()))
	var landed := await _focus_after_arrow(_slot_top_control(1), KEY_LEFT)
	check(landed == null or not _play_area.is_stock_control(landed),
			"an arrow into the emptied slot never stops on its face-down card (S21.7)",
			_board_input_state(_slot_top_control(0)))
#⚠ RE-POINTED BY P40: skipping the emptied slot leaves slot 1's top as the strip's LEFTMOST stop,
#and left off that is the sidebar's door -- so the arrow leaves the picture's viewport entirely
#rather than landing on the grid cell the engine's geometric search used to answer with.
	check(_booted_viewport.gui_get_focus_owner() != null
			and _container.is_ancestor_of(_booted_viewport.gui_get_focus_owner()),
			"...and with no card revealed that way the arrow leaves the Entrance row for the "
			+ "sidebar rather than stopping on the emptied slot (S21.7, P40)",
			"picture owner %s, sidebar owner %s"
			% [landed, _booted_viewport.gui_get_focus_owner()])
	_play_area.return_focus_to_board()
	await get_tree().process_frame
	await _discard_held_cards_of(2)
	landed = await _focus_after_arrow(_slot_top_control(1), KEY_RIGHT)
	check(landed != null and not _play_area.is_stock_control(landed),
			"...nor when the emptied slot lies between two that hold cards (S21.7)",
			_board_input_state(_slot_top_control(2)))
	check(landed == _slot_top_control(3),
			"...the arrow reaches the next slot that shows a revealed card (S21.7)",
			str(landed))
	await _end_main_fixture()

## S21.6: the Deck viewer is every stock as ONE pile, sorted by suit then rank, so no slot order leaks.
func test_the_deck_viewer_lists_every_stock_as_one_sorted_pile() -> void:
	await _start_game_fixture()
	var state := _fixture_game().state
	var pool := state.all_stock_cards()
	var stocks := state.entrance_stocks()
	for stock : ArrayCardData in stocks:
		stock.datas.clear()
	var late := _card_of_the_latest_suit(pool)
	stocks[0].datas.assign([late] as Array[CardData])
	var rest : Array[CardData] = []
	for card : CardData in pool:
		if card != late: rest.append(card)
	stocks[1].datas.assign(rest.slice(0, 3))
	state.discard_deck.append_array(rest.slice(3))
	state.revision += 1
	var listed := await _open_viewer_cards(_container.deck_ui.get_node(^"Button") as Button)
	var order : Array[CardData] = DeckViewer._open.deck
	check(listed.size() == 4 and order.size() == 4,
			"the viewer lists the union of both stocks as one pile (S21.6)",
			"%d listed, %d cards" % [listed.size(), order.size()])
	check(_is_sorted_by_suit_then_rank(order),
			"...in suit-then-rank order", _suit_rank_log(order))
	var last_listed : CardData = order.back()
	check(last_listed == late,
			"...which is NOT the slot order the stocks hold them in (S21.6)",
			_suit_rank_log(order))
	await _close_open_viewer(_booted_viewport)
	state.discard_deck.clear()
	state.discard_deck.append_array([rest[1], rest[0]] as Array[CardData])
	await _open_viewer_cards(_container.discard_ui.get_node(^"Button") as Button)
	check(DeckViewer._open.deck == state.discard_deck,
			"...while the Discard viewer still lists its pile exactly as the pile holds it (S21.6)",
			_suit_rank_log(DeckViewer._open.deck))
	await _close_open_viewer(_booted_viewport)
	await _end_main_fixture()

## The card the sort must put LAST, so "sorted" and "in slot order" cannot accidentally agree.
func _card_of_the_latest_suit(cards: Array[CardData]) -> CardData:
	var latest : CardData = cards[0]
	for card : CardData in cards:
		if card.suit.get_suit_index() > latest.suit.get_suit_index() \
				or (card.suit.get_suit_index() == latest.suit.get_suit_index()
					and card.rank.value > latest.rank.value):
			latest = card
	return latest

func _is_sorted_by_suit_then_rank(cards: Array[CardData]) -> bool:
	for i : int in range(1, cards.size()):
		var before : CardData = cards[i - 1]
		var after : CardData = cards[i]
		if before.suit.get_suit_index() > after.suit.get_suit_index(): return false
		if before.suit.get_suit_index() == after.suit.get_suit_index() \
				and before.rank.value > after.rank.value: return false
	return true

func _suit_rank_log(cards: Array[CardData]) -> String:
	var parts : PackedStringArray = []
	for card : CardData in cards:
		parts.append("%d/%d" % [card.suit.get_suit_index(), int(card.rank.value)])
	return ", ".join(parts)

# ------------------------------------------ S23: THE MAP'S NAME POPUP AND ITS SIDEBAR

## A hovered map node is a bare dot, so a hover NAMES it at the dot -- and names it only: the sidebar describes what the player PICKED, so passing the cursor over a neighbour cannot displace it.
func test_hovering_a_map_node_names_the_dot_and_leaves_the_sidebar_alone() -> void:
	await _start_map_fixture()
	var node := await _hover_a_map_node()
	var popup := _map.name_popup
	check(not _container.showing_description(),
			"S23.1: hovering a map node does not fill the sidebar")
	check(popup.visible, "S23.1: the name popup shows above the node")
	check(_popup_text(popup) == _map._info_for(node).title,
			"S23.1: the popup says the node's name and nothing else",
			"%s vs %s" % [_popup_text(popup), _map._info_for(node).title])
	var dot := WorldMapController.node_screen_rect(node)
	check(absf(popup.get_rect().get_center().x - dot.get_center().x) <= 1.0,
			"S23.1: the popup centres on the node",
			"%s vs %s" % [popup.get_rect().get_center().x, dot.get_center().x])
	check(popup.position.y + popup.size.y <= dot.position.y,
			"S23.1: the popup sits entirely above the node",
			"%s vs %s" % [popup.position.y + popup.size.y, dot.position.y])
	await _end_main_fixture()

## The name is a label on a dot, not a tooltip trailing the pointer: placed once, then left alone.
func test_the_name_stays_put_while_the_pointer_moves_inside_the_node() -> void:
	await _start_map_fixture()
	var node := await _hover_a_map_node()
	var placed : Vector2 = _map.name_popup.position
	var dot := WorldMapController.node_screen_rect(node)
	_hover_in(_map_viewport, dot.get_center() + Vector2(dot.size.x * 0.25, 0.0))
	await get_tree().process_frame
	check(_map.name_popup.position == placed,
			"S23.2: moving inside the node leaves the name where it was",
			"%s vs %s" % [_map.name_popup.position, placed])
	await _end_main_fixture()

## A CLICK PICKS AND TRAVELS NOWHERE, so the player can look before they go; the pick's description stays up once the dot is left, and the Travel button is the only way there.
func test_one_click_picks_the_node_and_only_travel_goes_there() -> void:
	await _start_map_fixture()
	var node := _map.controller._sorted_next()[0]
	var entered := _count_arrivals()
	var at := WorldMapController.node_screen_rect(node).get_center()
	_push_mouse_button(at, _map_viewport, true)
	_push_mouse_button(at, _map_viewport, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(entered.is_empty(), "S23.3: one click on a reachable node enters nothing",
			str(entered.size()))
	check(_map.controller.selected() == node, "S23.3: ...it picks that node instead")
	var described : InfoEntry = _panel.current_entry
	check(_container.showing_description(), "S23.3: ...and the sidebar describes it")
	_hover_in(_map_viewport, Vector2(_map_viewport.size) * 0.5 - Vector2(4000.0, 4000.0))
	await get_tree().process_frame
	check(_container.showing_description() and _panel.current_entry == described,
			"S23.3: the pointer leaving the dot keeps the PICK's description up")
# A pack node's pick opens its possible-cards viewer over the map, and a viewer's card description
# carries none of the node's buttons -- so the viewer is closed before Travel is looked for.
	await _close_the_open_viewer()
	check(await _click_button(_map.travel_button, _booted_viewport),
			"S23.3: the Travel button is a real button a real click can press")
	await _await_map_arrival()
	check(entered.size() == 1 and entered[0] == node,
			"S23.3: ...and pressing it is what enters the node", str(entered.size()))
	await _end_main_fixture()

## A finger has no hover, so a tap has to be able to ask what a dot is without going there -- and now no tap count takes it there either, the Travel button being the one way.
func test_a_tap_picks_the_node_and_no_second_tap_enters_it() -> void:
	await _start_map_fixture()
	var node := _map.controller._sorted_next()[0]
	var at := WorldMapController.node_screen_rect(node).get_center()
	var entered := _count_arrivals()
	_push_finger(at)
	await get_tree().process_frame
	check(_container.showing_description() and _map.name_popup.visible,
			"S23.4: a tap names the node and describes it")
	check(_map.controller.selected() == node, "S23.4: ...and picks it")
	check(entered.is_empty(), "S23.4: a tap does not enter the node", str(entered.size()))
	_push_synthesised_mouse_press(at)
	await get_tree().process_frame
	check(entered.is_empty(),
			"S23.4: the mouse press the engine synthesises from that finger enters nothing")
	_push_finger(at)
	await get_tree().process_frame
	await get_tree().process_frame
	check(entered.is_empty(),
			"S23.4: a second tap on the same node still enters nothing", str(entered.size()))
	check(_map.controller.selected() == node, "S23.4: ...the pick simply stands")
	await _end_main_fixture()

## A zoomed-in map is panned with one finger, so the rule that lets a tap NAME a dot must not eat the drag.
func test_a_finger_drag_pans_the_map() -> void:
	await _start_map_fixture()
	var controller := _map.controller
	await _zoom_the_map_in(_main, 5)
	var entered := _count_arrivals()
	var before := controller.camera.position
	var drag := _drag_toward_the_map_centre(MAP_PAN_DRAG)
	_drag_finger_by(WorldMapController.node_screen_rect(controller._sorted_next()[0]).get_center(),
			drag)
	await get_tree().process_frame
	var moved := before - controller.camera.position
	var expected := drag / controller.camera.zoom.x
	check(moved.is_equal_approx(expected),
			"Fix 14.1: one finger pans the camera by the distance it dragged",
			"%s vs %s" % [moved, expected])
	check(entered.is_empty(), "Fix 14.1: a finger dragged across a node enters nothing",
			str(entered.size()))
	check(not _map.name_popup.visible,
			"Fix 14.1: a finger dragged across a node names nothing")
	await _end_main_fixture()

# THE MAP NEVER LOCKS, so up at the top of any description it shows is the press that enters the
# panel: onto the X. The X's accept is the way out -- the description gone, the pick dropped, no
# focus owner, and the next arrow picks a node again.
func test_a_pad_enters_the_panel_by_up_on_the_map_and_leaves_it_by_the_x() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	var pack : InfoEntry = _panel.current_entry
	var picked_before := _map.controller.selected()
	check(not _container.is_locked(), "sanity: the map's description is shown, not locked")
	await _tap_key(KEY_UP)
	var owner := _booted_viewport.gui_get_focus_owner()
	check(owner == _exit_button(), "1.20: up at the top of the map's description focuses the X",
			str(owner))
	check(_map.controller.selected() == picked_before and _panel.current_entry == pack,
			"1.20: ...and the map's own pick did not move",
			"%s vs %s" % [_map.controller.selected(), picked_before])
	await _tap_key(KEY_ENTER)
	check(not _container.showing_description() and _hud_is_up(),
			"1.20: accept on the X takes the description down and puts the HUD up")
	check(_map.controller.selected() == null,
			"1.20: ...dropping the pick with it, so the map is back to its basic view")
	check(_booted_viewport.gui_get_focus_owner() == null,
			"1.20: ...leaving no root control focused", str(_booted_viewport.gui_get_focus_owner()))
	await _tap_key(KEY_RIGHT)
	check(_map.controller.selected() != null,
			"1.20: ...and the next right picks a map node again",
			str(_map.controller.selected()))
	await _end_main_fixture()

# A node with exactly one onward node needs no click. Measured: dismissal routes through the same
# `show_hud()` a cancel does, so re-applying the pick there would re-select through a cancel too --
# a dismissal drops the pick like any other clear; the next arrival/population/lap flip re-picks it.
func test_a_single_reachable_node_selects_itself_and_a_dismissal_drops_it_like_any_other_clear() -> void:
	await _start_map_fixture()
	var controller := _map.controller
	var lone : WorldGraphNode = null
	for n : WorldGraphNode in controller.map.overlay().nodes():
		if controller.next_nodes_of(n).size() == 1:
			lone = n
			break
	check(lone != null, "sanity: the generated map has a node with a single onward node")
	if lone == null:
		await _end_main_fixture()
		return
	var only := controller.next_nodes_of(lone)[0]
	controller._current = lone
	controller.refresh_visuals()
	controller._auto_select_if_single()
	await get_tree().process_frame
	await get_tree().process_frame
	check(controller.selected() == only,
			"the single reachable node auto-selects, no click")
	check(_map.travel_button.is_visible_in_tree(),
			"...and Travel is live without a click")
	check(_container.showing_description(), "...with its description on the sidebar")
	check(_container._shown_hosted_viewer() == null,
			"...and NO viewer over the map: an auto-pick is not a request to read a pack",
			"pack=%s" % str(_map._booster_of(only) != null))
	await _tap_key(KEY_UP)
	await _tap_key(KEY_ENTER)
	check(controller.selected() == null,
			"dismissing the description drops the pick, same as any other clear")
	check(not _map.travel_button.is_visible_in_tree(),
			"...so Travel goes with it")
	check(_hud_is_up(), "...back to the basic HUD view")
	await _end_main_fixture()

# A HOSTED VIEWER HAS A FOCUS CHAIN OF ITS OWN -- the pack's cards, their Rerolls, Take all -- so an
# up pressed inside it walks that chain, never the panel: the X taking the press would clear the
# viewer's focus, and the accept after it would find no owner in either viewport.
func test_up_inside_a_hosted_viewer_walks_the_viewer_not_the_x() -> void:
	var booted := await _boot_map_with_a_booster(Vector2i(1280, 720))
	var viewport : SubViewport = booted[0]
	var main : Main = booted[1]
	var viewer : ChoiceViewer = booted[2]
	var container : HudContainer = main.wall.get_node(^"%HudContainer")
	var exit_x : Button = container.get_node(^"%ExitX")
	var cards := _choice_viewer_cards(viewer)
	check(viewer != null and not cards.is_empty(), "sanity: a pack is open on the map")
	if viewer != null and not cards.is_empty():
		cards[0].grab_focus()
		await get_tree().process_frame
		viewer.confirm_button.grab_focus()
		await get_tree().process_frame
		check(container.showing_description() and not container.is_locked(),
				"sanity: the highlighted card's description is shown, unlocked, with Take all focused")
		_push_key(viewport, KEY_UP, true)
		_push_key(viewport, KEY_UP, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var owner := viewer.get_viewport().gui_get_focus_owner()
		check(owner != null and viewer.is_ancestor_of(owner),
				"1.20a: up inside a hosted viewer keeps the focus in the viewer's own chain",
				str(owner))
		check(viewport.gui_get_focus_owner() != exit_x,
				"1.20a: ...and the X did not take it", str(viewport.gui_get_focus_owner()))
	await _end_booted_fixture(viewport, main)

# Real key presses one at a time, each read back through the focus owner, so the walk proves the
# neighbour chain and not a `grab_focus()`. Stops at `arrived` or after `steps` presses.
## Each press through the window in turn, the key focus asserted to land on the matching control after every one.
func _walk_by(presses: Array[Callable], landings: Array[Control], route: String) -> void:
	for index : int in presses.size():
		await presses[index].call()
		var landed := _booted_viewport.gui_get_focus_owner()
		check(landed == landings[index], "%s: press %d lands on %s" % [route, index + 1,
				_control_label(landings[index])], "on %s" % _control_label(landed))

func _control_label(control: Control) -> String:
	return "%s '%s'" % [control, (control as Button).text] if control is Button else str(control)

## Presses `press` until the key focus leaves the sidebar, each press inside it walking on to another of its controls; whether the focus left for the open viewer.
func _walk_right_off_the_sidebar(press: Callable) -> bool:
	for step : int in SIDEBAR_WALK_STEPS:
		var from := _booted_viewport.gui_get_focus_owner()
		await press.call()
		var landed := _booted_viewport.gui_get_focus_owner()
		if landed != null and not _container.is_ancestor_of(landed): return true
		check(landed != null and landed != from, "a Right inside the sidebar walks on to its next control",
				"%s -> %s" % [_control_label(from), _control_label(landed)])
	return false

## More presses than the sidebar has controls in a row, so a walk that never leaves it fails instead of hanging.
const SIDEBAR_WALK_STEPS := 8

func _tap_until(keycode: Key, arrived: Callable, steps: int) -> Control:
	for step : int in steps:
		if arrived.call(): break
		await _tap_key(keycode)
	return _booted_viewport.gui_get_focus_owner()

## The `CardData` the description is PREVIEWING beside its name, or null while it shows no card of its own.
func _previewed_card() -> CardData:
	for card : ControlCard in (_panel.get_node(^"%VisualSlot") as Control).find_children(
			"*", "ControlCard", true, false):
		return card.child.data
	return null

## Whatever is selected is described, by pad and keyboard as well as by pointer.
func test_selecting_a_node_by_key_describes_it() -> void:
	await _start_map_fixture()
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	_map_viewport.push_input(key)
	await get_tree().process_frame
	var selected := _map.controller.selected()
	check(selected != null, "S23.6: an arrow selects a reachable node")
	check(_container.showing_description(),
			"S23.6: the selected node is described in the sidebar")
	check(_popup_text(_map.name_popup) == _map._info_for(selected).title,
			"S23.6: the selected node is named at the dot too",
			"%s vs %s" % [_popup_text(_map.name_popup), _map._info_for(selected).title])
	var dot := WorldMapController.node_screen_rect(selected)
	check(absf(_map.name_popup.get_rect().get_center().x - dot.get_center().x) <= 1.0,
			"S23.6: the name is placed at the node the arrow selected",
			"%s vs %s" % [_map.name_popup.get_rect().get_center().x, dot.get_center().x])
	await _end_main_fixture()

## With nothing picked the map rests on its HUD: Fame, Lap, Luck and the Deck button, and not one control that belongs to a pick.
func test_the_map_rests_with_nothing_picked_and_no_pick_buttons() -> void:
	await _start_map_fixture()
	check(_map.controller.selected() == null, "the map rests with nothing picked")
	check(_hud_is_up(), "...so the sidebar rests on its basic HUD view")
	check(_container.map_deck_button.is_visible_in_tree(),
			"...whose Deck button is there to be pressed")
	for button : Button in [_map.travel_button, _map.possible_cards_button] as Array[Button]:
		check(not button.is_visible_in_tree(),
				"...and %s is not on screen at all with nothing picked" % button.text)
	await _end_main_fixture()

# THE SIDEBAR CARRIES THE HUD OR THE DESCRIPTION AND NEVER BOTH, so a pick's Deck button is a second
# button of its own on the description side -- the owner's "just 1 button", not the HUD's kept alive.
func test_a_pick_brings_up_travel_and_a_deck_button_of_its_own() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	check(_container.showing_description(), "a pick puts its description on the sidebar")
	check(not _container.map_deck_button.is_visible_in_tree(),
			"the HUD's own Deck button is gone with the HUD, not special-cased to stay")
	for button : Button in [_map.travel_button, _map.selection_deck_button] as Array[Button]:
		check(button.is_visible_in_tree(), "a pick shows its own %s button" % button.text)
	check(not _map.possible_cards_button.is_visible_in_tree(),
			"a show node has no possible cards to list, so no button for them")
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	await _close_the_open_viewer()
	check(_map.possible_cards_button.is_visible_in_tree(),
			"a talent pack picks up the third button, for its possible cards")
	await _end_main_fixture()

## Comparing the pack against what you already hold must not cost the pick: the deck viewer opens over it and closes back onto it.
func test_the_decks_viewer_comes_back_to_the_same_pick() -> void:
	await _start_map_fixture()
	var node := _a_map_node_with_role(MapNodeRoles.ROLE_GAME)
	await _select_map_node_and_settle(node)
	var described := _panel.current_entry.title
	check(await _click_button(_map.selection_deck_button, _booted_viewport),
			"the pick's Deck button is a real button a real click can press")
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open), "...and it opens the run deck over the pick")
	check(_map.controller.selected() == node, "...without cancelling the pick")
	await _close_the_open_viewer()
	check(_map.controller.selected() == node, "closing it leaves the same node picked")
	check(_container.showing_description() and _panel.current_entry.title == described,
			"...with the sidebar describing that node again",
			"%s vs %s" % [_panel.current_entry.title, described])
	await _end_main_fixture()

## The buttons belong to a picked MAP node, so no other screen's description may carry them.
func test_the_picks_buttons_never_show_on_another_screen() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	check(_map.selection_buttons.is_visible_in_tree(), "sanity: the pick's row is up on the map")
	await _main.enter_game()
	await get_tree().process_frame
	check(not _map.selection_buttons.is_visible_in_tree(),
			"the pick's row is gone the moment another screen is shown")
	check(_map.controller.selected() == null, "...and the pick went with it")
	await _end_main_fixture()

## R2's order: cancel spends itself on the pick before it spends itself on leaving the picture.
func test_cancel_drops_the_pick_before_it_leaves_the_picture() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	_map_viewport.push_input(_cancel_event())
	await get_tree().process_frame
	await get_tree().process_frame
	check(_map.controller.selected() == null, "cancel drops the pick")
	check(_hud_is_up(), "...back to the basic view")
	check(_main._current_focus == &"map", "...and stays inside the map picture",
			str(_main._current_focus))
	await _end_main_fixture()

## A viewer open over the pick does not make the pick stuck: leaving the map drops both, and the return finds no description of it.
func test_a_pick_under_an_open_viewer_is_not_re_shown_on_return() -> void:
	await _start_map_fixture()
	var node := _a_map_node_with_role(MapNodeRoles.ROLE_GAME)
	await _select_map_node_and_settle(node)
	var described := _panel.current_entry.title
	check(await _click_button(_map.selection_deck_button, _booted_viewport),
			"sanity: the pick's Deck button opened the run deck over the pick")
	await get_tree().process_frame
	await _main._go_to_wall_view()
	await _wait_out_the_move()
	await _main._focus_picture(&"map")
	await _wait_out_the_move()
	await get_tree().process_frame
	check(_map.controller.selected() == null, "sanity: leaving the map dropped the pick")
	check(not (_container.showing_description() and _panel.current_entry
			and _panel.current_entry.title == described),
			"P57: the dropped pick is not re-shown on return, a viewer having covered it",
			str(_panel.current_entry.title if _panel.current_entry else null))
	await _end_main_fixture()

## A pick dropped on the map, or dropped by leaving it, is not what the map comes back to: the HUD is, with its own Deck button.
func test_a_dropped_pick_leaves_the_map_nothing_to_come_back_to() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	_map.controller.clear_selection()
	await _main.enter_game()
	await _main._focus_picture(&"map")
	check(_hud_is_up() and _container.map_deck_button.is_visible_in_tree(),
			"a pick dropped on the map is not re-shown on returning to it")
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	await _main.enter_game()
	await _main._focus_picture(&"map")
	check(_hud_is_up() and _container.map_deck_button.is_visible_in_tree(),
			"a pick dropped by leaving the map is not re-shown on returning to it")
	await _end_main_fixture()

# A KEY THAT IS NOT IN THE CSV COMES BACK AS ITSELF, so a button showing its own key looks like a
# label until someone reads it. Every button this screen and the pack chooser added is checked
# against the locale, and against the key it was asked for.
func test_every_new_button_is_written_in_the_locale() -> void:
	await _start_map_fixture()
	var by_key : Dictionary[StringName, Button] = {
		&"MAP_TRAVEL": _map.travel_button,
		&"MAP_DECK": _map.selection_deck_button,
		&"MAP_POSSIBLE_CARDS": _map.possible_cards_button,
	}
	for key : StringName in by_key:
		var button : Button = by_key[key]
		check(button.text == TRANSLATION.find(key) and button.text != String(key),
				"%s is written through its locale key, not as a literal" % key, button.text)
	var viewer : ChoiceViewer = await ChoiceViewer.add_to_scene(_map, _card_for_a_pack, 2, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(viewer.confirm_button.text == TRANSLATION.find(&"CHOICE_TAKE") \
			and viewer.confirm_button.text != "CHOICE_TAKE",
			"Take is written through its locale key, not as a literal", viewer.confirm_button.text)
	viewer.queue_free()
	await get_tree().process_frame
	await _end_main_fixture()

## One card for a pack the locale row opens -- what it holds does not matter, only that the chooser draws its own button.
func _card_for_a_pack() -> CardData:
	return CardData.new().with_rank(PipRankNumeral.new().with_value(5)).with_suit(PipSuitKnife.new())

## A pack's possible cards list each part it could roll as a labelled icon, every icon in one shared cell a card's width, each name on one line in one shared font, a type's face shrunk into it -- and no card body is drawn anywhere in the list.
func test_the_possible_cards_list_every_part_as_an_icon_and_no_card() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	await _select_map_node_and_settle(pack)
	var list := DeckViewer._open
	check(is_instance_valid(list), "sanity: the first pick of a pack listed its possible cards")
	if is_instance_valid(list):
		var parts := await _booster_of(pack).get_possible_preview_cards()
		var icons : Array[PartIcon] = []
		for control : Control in list.cards().controls:
			if control is PartIcon: icons.append(control)
		check(icons.size() == parts.size() and icons.size() == list.cards().controls.size(),
				"every possible part is listed as one icon, and nothing else is listed",
				"%d icons, %d listed, %d parts" % [icons.size(), list.cards().controls.size(), parts.size()])
		var bodies := list.flow_container.find_children("*", "", true, false).filter(
				func(node: Node) -> bool: return node is CardVisual)
		check(bodies.is_empty(), "no card body is drawn in the possible-cards list", str(bodies.size()))
		var cell := icons[0].size
		check(icons.all(func(icon: PartIcon) -> bool: return icon.size == cell),
				"every icon shares its list's one cell", str(cell))
		check(is_equal_approx(cell.x, CardVisual.preview_window_px().x),
				"...as wide as a listed card's, so a column is one width in every viewer",
				"%s vs %s" % [cell, CardVisual.preview_window_px()])
		var font := icons[0]._label.get_theme_font_size(&"font_size")
		for icon : PartIcon in icons:
			var label := icon._label
			var line := label.get_theme_font(&"font").get_string_size(label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font).x
			check(label.get_theme_font_size(&"font_size") == font and line <= cell.x,
					"...its name on one line inside that width, in the one font every label shares",
					"%s: %.1f wide at %d, list font %d" % [label.text, line,
					label.get_theme_font_size(&"font_size"), font])
		for icon : PartIcon in icons:
			var named : String = PartIcon.part_of(icon.data).call(&"get_str")
			check(icon._label.text == named,
					"an icon is labelled with its part's own name", icon._label.text)
			if icon.data.type == null: continue
			var drawn := icon._window * icon._art.scale
			check(drawn.x <= icon._art_box.size.x and drawn.y <= icon._art_box.size.y
					and icon._art.scale.x < CardVisual.DECK_VIEWER_SCALE,
					"a type's face is shrunk into the cell, not drawn as a card",
					"%s in %s" % [drawn, icon._art_box.size])
		await _close_the_open_viewer()
	await _end_main_fixture()

## A pack's possible cards group each kind in the kinds' fixed order under its own left-aligned header one row wide, a card gap under it and under the group before; the list is sized by the height it lays out to, and the keys and d-pad walk down through every group, never onto a header.
func test_the_possible_cards_group_each_kind_under_its_own_header() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	await _select_map_node_and_settle(pack)
	var list := DeckViewer._open
	check(is_instance_valid(list), "sanity: the first pick of a pack listed its possible cards")
	if is_instance_valid(list):
		var parts := await _booster_of(pack).get_possible_preview_cards()
		var kinds : Array[StringName] = []
		for kind : StringName in PartIcon.KINDS:
			if parts.any(func(data: CardData) -> bool: return PartIcon.kind_of(data) == kind):
				kinds.append(kind)
		check(kinds == PartIcon.KINDS.keys(), "sanity: the pack offers every kind of part", str(kinds))
		_check_the_groups(list, parts, kinds)
		for press : Callable in [_tap_key.bind(KEY_DOWN), _tap_pad.bind(JOY_BUTTON_DPAD_DOWN)]:
			await _check_down_walks_every_group(list, kinds, press)
		await _close_the_open_viewer()
	await _end_main_fixture()

## Checks the list's children against `kinds`, one header and its group each, and the height the list is sized by.
func _check_the_groups(list: DeckViewer, parts: Array[CardData], kinds: Array[StringName]) -> void:
	var headers : Array[Label] = []
	var groups : Array[Array] = []
	for child : Node in list.flow_container.get_children():
		if child is Label:
			headers.append(child as Label)
			groups.append([])
		elif not groups.is_empty():
			(groups.back() as Array).append(child)
	check(headers.size() == kinds.size() and list.flow_container.get_child(0) is Label,
			"the list opens with a header, and there is one header for each kind the pack offers",
			"%d headers, %d kinds" % [headers.size(), kinds.size()])
	var gap := float(PlayArea.viewer_separation_px())
	var cell := (list.cards().controls[0] as Control).size
	var grid_right := 0.0
	var bottom := 0.0
	for icon : Control in list.cards().controls:
		grid_right = maxf(grid_right, icon.get_rect().end.x)
	for child : Control in list.flow_container.get_children():
		bottom = maxf(bottom, child.get_rect().end.y)
	var columns := roundi((grid_right + gap) / (cell.x + gap))
	check(is_equal_approx(list.cards().fit_rows(columns), bottom),
			"the list is sized by the height it lays out to at %d columns" % columns,
			"%.1f vs %.1f" % [list.cards().fit_rows(columns), bottom])
	if headers.size() != kinds.size(): return
	var above := -INF
	for index : int in kinds.size():
		var header := headers[index]
		var group : Array = groups[index]
		var key := PartIcon.KINDS[kinds[index]]
		check(header.text == TRANSLATION.find(key) and header.text != String(key),
				"group %d is headed by its kind's locale key, in the kinds' fixed order" % index,
				"'%s' for %s" % [header.text, kinds[index]])
		check(group.size() == parts.filter(func(data: CardData) -> bool:
				return PartIcon.kind_of(data) == kinds[index]).size() and group.all(
				func(icon: Control) -> bool: return PartIcon.kind_of((icon as PartIcon).data) == kinds[index]),
				"...and holds every %s part and nothing else" % kinds[index], "%d listed" % group.size())
		var first : Control = group[0]
		check(header.focus_mode == Control.FOCUS_NONE
				and header.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT
				and header.position.x == 0.0 and first.position.x == 0.0,
				"...its header unfocusable and left-aligned at the grid's left edge, its group opening a row",
				"header x %.1f, first cell x %.1f" % [header.position.x, first.position.x])
		check(is_equal_approx(header.size.x, grid_right),
				"...its header one row of the grid wide, so no cell shares its line",
				"%.1f vs %.1f" % [header.size.x, grid_right])
		var group_top := first.position.y
		var group_bottom := 0.0
		for icon : Control in group:
			group_top = minf(group_top, icon.position.y)
			group_bottom = maxf(group_bottom, icon.get_rect().end.y)
		check(is_equal_approx(group_top, header.get_rect().end.y + gap)
				and (index == 0 or is_equal_approx(header.position.y, above + gap)),
				"...one card gap under its header, its header one card gap under the group before",
				"header %.1f-%.1f, group from %.1f, the group before ends %.1f, gap %.1f" % [
				header.position.y, header.get_rect().end.y, group_top, above, gap])
		above = group_bottom

## Walks down from the list's first cell by `press` until the focus stops, checking every landing is a cell and every group is reached in order.
func _check_down_walks_every_group(list: DeckViewer, kinds: Array[StringName], press: Callable) -> void:
	var controls := list.cards().controls
	controls[0].grab_focus()
	await get_tree().process_frame
	var reached : Array[StringName] = [PartIcon.kind_of((controls[0] as PartIcon).data)]
	for step : int in controls.size():
		var from := _booted_viewport.gui_get_focus_owner()
		await press.call()
		var landed := _booted_viewport.gui_get_focus_owner()
		if landed == from: break
		check(landed is PartIcon and controls.has(landed), "a press down lands on a listed cell, never a header",
				str(landed))
		if not landed is PartIcon: return
		var kind := PartIcon.kind_of((landed as PartIcon).data)
		if reached.back() != kind: reached.append(kind)
	check(reached == kinds, "...and walks down through every group in order", str(reached))

## A possible rank's numeral is drawn in the cream role it is filled with, not the ink its outline shares, read off the window's pixels on every texel of its silhouette.
func test_a_possible_rank_is_filled_in_its_own_role_not_the_outlines_ink() -> void:
	await _start_map_fixture()
	await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
	var list := DeckViewer._open
	check(is_instance_valid(list), "sanity: the first pick of a pack listed its possible cards")
	if is_instance_valid(list):
		var ranks := list.cards().controls.filter(
				func(icon: PartIcon) -> bool: return icon.data.rank != null)
		var icon : PartIcon = ranks[0]
		icon.grab_focus()
		_booted_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
# A SubViewport carries its own filter, defaulting to linear, which blends each texel a quarter into
# its neighbour at the list's two pixels a texel; the player's window draws nearest (test_pixels.gd).
		_booted_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		await await_drawn_frames(RANK_SCROLL_FRAMES)
		var window := _booted_viewport.get_texture().get_image()
		var scroll_rect := _drawn_in_window(_booted_viewport, list._scroll)
		check(scroll_rect.encloses(_drawn_in_window(_booted_viewport, icon)),
				"sanity: the rank icon is scrolled wholly into view", str(scroll_rect))
		var sheet := PipRankNumeral.RANK_TEXTURE.get_image()
		var frame := CardModifier.frame_rect(PipRankNumeral.RANK_TEXTURE, PipRankNumeral.H_FRAMES,
				PipRankNumeral.V_FRAMES, int(icon.data.rank.value) - 1)
		var to_window := _booted_viewport.get_final_transform() * icon._art.get_global_transform_with_canvas()
		var wanted := PaletteDB.ROLES.color_of(&"part_rank_fill")
		var body := 0
		var off : Array[String] = []
		for y : int in int(frame.size.y):
			for x : int in int(frame.size.x):
				if sheet.get_pixelv(Vector2i(frame.position) + Vector2i(x, y)).a < 0.5: continue
				body += 1
				var at := to_window * (Vector2(x, y) + Vector2.ONE * (CardOutline.WIDTH + 0.5))
				var seen := window.get_pixelv(Vector2i(at))
				if _colour_distance(seen, wanted) >= OPAQUE_COLOUR_TOLERANCE:
					off.append("%s at %s" % [seen, at])
		check(body > 0 and off.is_empty(),
				"every texel of the rank numeral is drawn in part_rank_fill, not the outline's ink",
				"%d of %d off %s: %s" % [off.size(), body, wanted, off.slice(0, 3)])
		await _close_the_open_viewer()
	await _end_main_fixture()

## Frames a focus-followed scroll takes to bring the last group into view and draw it.
const RANK_SCROLL_FRAMES := 30

## Hovered, focused by keys or by the d-pad, or stuck by a click or an accept, a listed part is described in the sidebar by its own name and a description that is never empty, previewed on a card with a body -- and so is every other part in the list.
func test_a_possible_part_is_described_by_its_name_on_a_card_preview() -> void:
	for route : String in ["mouse", "keys", "d-pad"]:
		await _start_map_fixture()
		await _select_map_node_and_settle(_a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER))
		var list := DeckViewer._open
		check(is_instance_valid(list) and list.cards().controls.size() > 1,
				"sanity: the first pick of a pack listed its possible cards (%s)" % route)
		if is_instance_valid(list) and list.cards().controls.size() > 1:
			var icons := list.cards().controls
			var target : PartIcon = icons[1]
			if route == "mouse":
				target = icons[icons.find_custom(func(icon: PartIcon) -> bool: return icon.data.stamp != null)]
				_hover_in(_booted_viewport, target.get_global_rect().get_center())
				await get_tree().process_frame
				await get_tree().process_frame
			else:
				var right : Callable = _tap_key.bind(KEY_RIGHT) if route == "keys" \
						else _tap_pad.bind(JOY_BUTTON_DPAD_RIGHT)
				await _walk_by([right, right] as Array[Callable], [icons[0], target] as Array[Control],
						"into the possible cards and on to the next part (%s)" % route)
			_check_the_part_described(target, "highlighted by %s" % route)
			if route == "mouse": await _click(target.get_global_rect().get_center(), _booted_viewport)
			elif route == "keys": await _tap_key(KEY_ENTER)
			else: await _tap_pad(JOY_BUTTON_A)
			check(list.cards().sticky == target.data,
					"the part's click or accept sticks it (%s)" % route, str(list.cards().sticky))
			_check_the_part_described(target, "stuck by %s" % route)
			if route == "keys":
				for icon : PartIcon in icons:
					icon.grab_focus()
					await get_tree().process_frame
					_check_the_part_described(icon, "every part, focused")
			await _close_the_open_viewer()
		await _end_main_fixture()

## The sidebar describes `icon`'s part: its name as the title, its own non-empty description, and a card preview carrying that part on a body.
func _check_the_part_described(icon: PartIcon, how: String) -> void:
	var part := PartIcon.part_of(icon.data)
	var entry := _panel.current_entry
	var described : String = part.call(&"get_description")
	var named : String = part.call(&"get_str")
	check(_container.showing_description() and entry != null
			and entry.title == named and entry.body == described
			and not described.is_empty(),
			"a listed part is described by its own name and a description that is never empty (%s)" % how,
			"%s: '%s' / '%s'" % [(part.get_script() as Script).get_global_name(),
			entry.title if entry else "none", entry.body if entry else "none"])
	var previews : Array = []
	if entry and entry.visual:
		previews = entry.visual.find_children("*", "", true, false).filter(
				func(node: Node) -> bool: return node is CardVisual)
	var preview : CardData = (previews[0] as CardVisual).data if previews.size() == 1 else null
	check(preview != null and preview.type != null and _carries(preview, part),
			"...previewed on one card with a body, the part in its own place (%s)" % how,
			"%d previews" % previews.size())

## Whether `card` carries a part of the same kind and value as `part`.
func _carries(card: CardData, part: Resource) -> bool:
	for own : Resource in [card.type, card.stamp, card.skill, card.suit, card.rank]:
		if own and own.get_script() == part.get_script() \
				and (not part is PipRank or (own as PipRank).value == (part as PipRank).value):
			return true
	return false

# THE SIDEBAR IS TOO NARROW TO READ A PACK IN, so the pack lists itself in a viewer on the first
# pick -- and only the first: a later pick of the same node leaves the player where they are, and
# the button is how they ask again.
func test_a_pack_lists_its_possible_cards_on_the_first_pick_only() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	var other := _a_map_node_with_role(MapNodeRoles.ROLE_GAME)
	await _select_map_node_and_settle(pack)
	check(is_instance_valid(DeckViewer._open),
			"the first pick of a talent pack lists its possible cards")
	var listed : int = DeckViewer._open.deck.size()
	var icons : int = DeckViewer._open.cards().controls.filter(
			func(control: Control) -> bool: return control is PartIcon).size()
	check(listed == (await _booster_of(pack).get_possible_preview_cards()).size() and listed > 0
			and icons == listed,
			"...every part the pack could roll as one icon each, and nothing else",
			"%d parts, %d icons" % [listed, icons])
	await _close_the_open_viewer()
	await _select_map_node_and_settle(other)
	await _select_map_node_and_settle(pack)
	check(not is_instance_valid(DeckViewer._open),
			"picking the same pack again before travelling opens nothing")
	check(await _click_button(_map.possible_cards_button, _booted_viewport),
			"its button in the sidebar is how it is asked for again")
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open), "...and that opens it")
	await _close_the_open_viewer()
	await _end_main_fixture()

## "Before travelling" is what the once is keyed on, so arriving anywhere lets every pack list itself afresh.
func test_travelling_lets_a_pack_list_itself_again() -> void:
	await _start_map_fixture()
	var pack := _a_map_node_with_role(MapNodeRoles.ROLE_BOOSTER)
	await _select_map_node_and_settle(pack)
	await _close_the_open_viewer()
	check(_map._packs_shown.has(pack.id), "sanity: that pack is marked as listed")
	await _map._on_node_entered(_a_map_node_with_role(MapNodeRoles.ROLE_GAME))
	check(_map._packs_shown.is_empty(), "arriving anywhere forgets every pack that was listed")
	_map.start_run(RunManager.run)
	check(_map._packs_shown.is_empty(), "...and so does starting a run over")
	await _end_main_fixture()

## The pack a node opens, for a test that needs the list it would show.
func _booster_of(node: WorldGraphNode) -> BoosterTemplate:
	return node.meta.get(MapNodeRoles.BOOSTER_KEY)

## The popup is a MAP affordance for nodes that are just dots; a board card is already drawn.
func test_no_name_popup_shows_on_the_board() -> void:
	await _start_map_fixture()
	await _hover_a_map_node()
	check(_map.name_popup.visible, "S23.7: the map node was named before the show was entered")
	await _enter_game_fixture()
	var controls := await _hoverable_card_controls()
	_hover(controls[0].get_global_rect().get_center())
	await get_tree().process_frame
	check(_container.showing_description(), "S23.7: the board card is described")
	check(_visible_name_popups().is_empty(),
			"S23.7: no name popup is visible anywhere on the board",
			str(_visible_name_popups().size()))
	await _end_main_fixture()

## A name is pinned to a dot, so the dot moving under the camera has to carry the name with it.
func test_the_name_follows_its_node_when_the_camera_pans() -> void:
	await _start_map_fixture()
	await _zoom_the_map_in(_main, 5)
	var node := await _hover_a_map_node()
	var before := WorldMapController.node_screen_rect(node)
	_pan_map_by(before.get_center(), _drag_toward_the_map_centre(MAP_PAN_DRAG))
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().physics_frame
		await get_tree().process_frame
		waited += get_process_delta_time()
		if WorldMapController.node_screen_rect(node).get_center().distance_to(
				before.get_center()) > 1.0: break
	await get_tree().process_frame
	var dot := WorldMapController.node_screen_rect(node)
	check(dot.get_center().distance_to(before.get_center()) > 1.0,
			"Fix 13.1: the pan moved the node on screen",
			"%s vs %s" % [dot.get_center(), before.get_center()])
	check(absf(_map.name_popup.get_rect().get_center().x - dot.get_center().x) <= 1.0,
			"Fix 13.1: the name is still centred on the node it names",
			"%s vs %s" % [_map.name_popup.get_rect().get_center().x, dot.get_center().x])
	check(_map.name_popup.position.y + _map.name_popup.size.y <= dot.position.y,
			"Fix 13.1: the name is still above the node it names",
			"%s vs %s" % [_map.name_popup.position.y + _map.name_popup.size.y, dot.position.y])
	await _end_main_fixture()

## A run starting over rebuilds the dots, so a name left from the last one labels nothing.
func test_starting_a_run_takes_the_name_off_the_map() -> void:
	await _start_map_fixture()
	await _hover_a_map_node()
	check(_map.name_popup.visible, "Fix 13.2: a node was named before the run restarted")
	_map.start_run(RunManager.run)
	await get_tree().process_frame
	check(not _map.name_popup.visible,
			"Fix 13.2: starting a run leaves no name on the map")
	await _end_main_fixture()

# A pan runs the camera AGAINST the drag and stops at the map's edge, so a drag meant to move it by
# its full length is aimed to send the camera toward the map's centre, where there is room.
func _drag_toward_the_map_centre(by: Vector2) -> Vector2:
	var at := _map.controller.camera.position
	return Vector2(signf(at.x) * absf(by.x), signf(at.y) * absf(by.y))

# The map pans on a mouse DRAG, so the motion has to carry its own `relative`: the controller moves
# the camera by exactly that, and an event without it pans nothing.
func _pan_map_by(from: Vector2, by: Vector2) -> void:
	_push_mouse_button(from, _map_viewport, true)
	var motion := InputEventMouseMotion.new()
	motion.position = from + by
	motion.global_position = motion.position
	motion.relative = by
	_map_viewport.push_input(motion)
	_push_mouse_button(from + by, _map_viewport, false)

## Every name popup the player can actually see, so a check can say the board carries none.
func _visible_name_popups() -> Array[Node]:
	var shown : Array[Node] = []
	for popup : Node in get_tree().root.find_children("*", "MapNamePopup", true, false):
		if (popup as Control).is_visible_in_tree(): shown.append(popup)
	return shown

# The pointer pushed onto a reachable node in the MAP picture's own SubViewport -- the viewport the
# wall pushes into, so the route under test is the product's own hover.
func _hover_a_map_node() -> WorldGraphNode:
	var node := _map.controller._sorted_next()[0]
	_hover_in(_map_viewport, WorldMapController.node_screen_rect(node).get_center())
	await get_tree().process_frame
	return node

# A REAL finger: `device` stays at 0, which is what tells it from the mouse form the engine
# synthesises from it.
func _push_touch(at: Vector2, pressed: bool) -> void:
	_push_touch_in(_map_viewport, at, pressed)

# A finger pushed into whichever picture hosts what it lands on -- the sidebar's own controls are
# not in the map's viewport, which `_push_touch()` pushes into.
func _push_touch_in(viewport: Viewport, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = at
	touch.pressed = pressed
	viewport.push_input(touch)

# One finger tapping, in the engine's own dispatch order: it emits the mouse form it emulates from
# a touch BEFORE the touch itself, at the press and again at the release.
func _push_finger(at: Vector2) -> void:
	_push_finger_in(_map_viewport, at)

## The same tap, aimed at the viewport that hosts what the finger lands on.
func _push_finger_in(viewport: SubViewport, at: Vector2) -> void:
	_push_mouse_button(at, viewport, true, -1)
	_push_touch_in(viewport, at, true)
	_push_mouse_button(at, viewport, false, -1)
	_push_touch_in(viewport, at, false)

# One finger dragging, in the same order: a finger that travels arrives as an emulated motion
# carrying `relative` (what the camera moves by) as well as its own screen drag.
func _drag_finger_by(from: Vector2, by: Vector2) -> void:
	_push_mouse_button(from, _map_viewport, true, -1)
	_push_touch(from, true)
	var motion := InputEventMouseMotion.new()
	motion.position = from + by
	motion.global_position = motion.position
	motion.relative = by
	motion.device = -1
	_map_viewport.push_input(motion)
	var drag := InputEventScreenDrag.new()
	drag.position = from + by
	drag.relative = by
	_map_viewport.push_input(drag)
	_push_mouse_button(from + by, _map_viewport, false, -1)
	_push_touch(from + by, false)

# The mouse press the engine emulates from a finger, marked `device` -1 -- it arrives BEFORE the
# touch event, so a map that travelled on it would go there on the tap that only meant to ask.
func _push_synthesised_mouse_press(at: Vector2) -> void:
	_push_mouse_button(at, _map_viewport, true, -1)

## Every node the map is entered from here on, so a test can say how many clicks it took.
func _count_arrivals() -> Array[WorldGraphNode]:
	var entered : Array[WorldGraphNode] = []
	_map.controller.node_entered.connect(func(node: WorldGraphNode) -> void: entered.append(node))
	return entered

# The token walks the edge curve over several frames, so the arrival is waited FOR. Bounded: a
# travel that never ends is a bug to surface, not one to spin on.
func _await_map_arrival() -> void:
	var waited := 0.0
	while waited < CARD_CONTROL_TIMEOUT_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not _map.controller._moving: return

## The whole of the popup's text, so a check can say it holds the name and nothing besides.
func _popup_text(popup: MapNamePopup) -> String:
	var parts : Array[String] = []
	for label : Label in popup.find_children("*", "Label", true, false):
		parts.append(label.text)
	return "".join(parts)

# A node of one kind, wherever it fell on the generated graph -- a pack's entry brings a grid of
# preview cards and a show's brings none, which is the difference every height check here turns on.
func _a_map_node_with_role(role: String) -> WorldGraphNode:
	for node : WorldGraphNode in _map.controller.map.overlay().nodes():
		if node.meta.get(MapNodeRoles.ROLE_KEY, "") == role:
			return node
	return null

# The description settled on what picking `node` publishes, through the product's own route, so what
# is read straight after is what the player would be looking at.
func _select_map_node_and_settle(node: WorldGraphNode) -> void:
	var controller := _map.controller
	if node not in controller.next_nodes_of(controller._current):
		controller._current = _a_neighbour_leading_to(node)
		controller.refresh_visuals()
	controller.select_node(node)
	await get_tree().process_frame
	await get_tree().process_frame

## A node the map's own reachability puts `node` one step beyond, so a pick of `node` goes through the product's own refusal rather than around it.
func _a_neighbour_leading_to(node: WorldGraphNode) -> WorldGraphNode:
	for n : WorldGraphNode in _map.controller.map.overlay().nodes():
		if node in _map.controller.next_nodes_of(n): return n
	return null

## Closes whatever viewer is open, if one still is -- a viewer freed by the act before is not one.
func _close_the_open_viewer() -> void:
	if is_instance_valid(DeckViewer._open) and not DeckViewer._open.is_queued_for_deletion():
		DeckViewer._open._close()
	await get_tree().process_frame
	await get_tree().process_frame

## The height the description lays its content out to, which is the floor the scroll can never fall below.
func _content_height() -> float:
	return (_panel.get_node(^"%Content") as VBoxContainer).custom_minimum_size.y

## How far the description can actually be scrolled, which is what a player meets rather than any one control's height.
func _scroll_overflow() -> float:
	var bar := _panel_scroll(_panel).get_v_scroll_bar()
	return maxf(bar.max_value - bar.page, 0.0)

# ------------------------------------------------------------- P40: the board's door to the sidebar

# The sidebar and the picture are two focus worlds, so every row here says WHICH viewport owns the
# focus after the press: a row that asserts only the control is green while the pad is stranded.
func _p40_press(viewport: Viewport, keycode: Key) -> void:
	_push_key(viewport, keycode, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_push_key(viewport, keycode, false)
	await get_tree().process_frame

## The game HUD's first control -- where a press off the board's left edge lands.
func _first_hud_control() -> Control:
	return _container.deck_ui.get_node(^"Button") as Button

# The one route three rows below share: a dealt board, the focus on the strip's leftmost stop, one
# left press. Returns the card the press left, or null when the deal offered none to press from.
func _left_off_the_leftmost_entrance_card() -> Control:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to press from",
			str(entrance.size()))
	if entrance.is_empty(): return null
	entrance[0].grab_focus()
	await get_tree().process_frame
	await _p40_press(_game_viewport, KEY_LEFT)
	return entrance[0]

## P40: left off the leftmost Entrance card is the keyboard's only way into the sidebar, and it lands on a HUD button in the OVERLAY's viewport.
func test_left_from_the_leftmost_entrance_card_enters_the_sidebar() -> void:
	var left_from : Control = await _left_off_the_leftmost_entrance_card()
	check(left_from != null and left_from.focus_neighbor_left.is_empty(),
			"sanity: the card pressed from is the strip's leftmost stop, with no left neighbour",
			str(left_from.focus_neighbor_left) if left_from else "-")
	check(_booted_viewport.gui_get_focus_owner() == _first_hud_control(),
			"P40: left off the leftmost Entrance card lands on the HUD's Deck button",
			str(_booted_viewport.gui_get_focus_owner()))
	check(_game_viewport.gui_get_focus_owner() == null,
			"P40: ...and the picture's own viewport owns nothing any more",
			str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## P40: the same door from a grid cell -- the lattice step lands on no cell, which is the board's left edge.
func test_left_from_the_leftmost_grid_cell_enters_the_sidebar() -> void:
	await _start_game_fixture()
	var cell := _play_area._cell_focus_control(BoardCoord.new(0, 0, 0, 0))
	check(cell != null, "the dealt board offers the leftmost grid cell to press from", str(cell))
	if cell == null:
		await _end_main_fixture()
		return
	cell.grab_focus()
	await get_tree().process_frame
	await _p40_press(_game_viewport, KEY_LEFT)
	check(_booted_viewport.gui_get_focus_owner() == _first_hud_control(),
			"P40: left off the leftmost column of the leftmost grid lands on the HUD's Deck button",
			str(_booted_viewport.gui_get_focus_owner()))
	check(_game_viewport.gui_get_focus_owner() == null,
			"P40: ...leaving the picture's viewport with no focus owner",
			str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## P40: and back again -- rights walk the HUD's own row and the one off its right edge returns to the very card the press left.
func test_right_from_the_sidebars_last_control_returns_to_the_card_it_left() -> void:
	var left_from : Control = await _left_off_the_leftmost_entrance_card()
	var steps := 0
	while steps < 6:
		var owner := _booted_viewport.gui_get_focus_owner()
		if owner == null or not _container.is_ancestor_of(owner): break
		await _p40_press(_booted_viewport, KEY_RIGHT)
		steps += 1
	check(steps > 0 and _booted_viewport.gui_get_focus_owner() == null,
			"P40: rights walk the HUD's controls and the last one gives the sidebar's focus up",
			"%d presses, owner %s" % [steps, _booted_viewport.gui_get_focus_owner()])
	check(_game_viewport.gui_get_focus_owner() == left_from,
			"P40: ...handing the picture back the card the press left, in the picture's viewport",
			str(_game_viewport.gui_get_focus_owner()))
	await _end_main_fixture()

## P40: a stuck description holds the panel, so the edge press lands on its X rather than on a HUD button that is not on screen.
func test_left_with_a_stuck_description_lands_on_the_x() -> void:
	await _start_game_fixture()
	var entrance := await _entrance_card_controls()
	check(not entrance.is_empty(), "the dealt board offers an Entrance card to click",
			str(entrance.size()))
	if entrance.is_empty():
		await _end_main_fixture()
		return
	await _click_card(entrance[0])
	check(_container.is_locked(), "sanity: the click stuck the card's description to the sidebar")
	var cell := _play_area._cell_focus_control(BoardCoord.new(0, 0, 0, 0))
	check(cell != null, "the dealt board offers the leftmost grid cell to press from", str(cell))
	if cell:
		cell.grab_focus()
		await get_tree().process_frame
		await _p40_press(_game_viewport, KEY_LEFT)
		check(_booted_viewport.gui_get_focus_owner() == _exit_button(),
				"P40: with a stuck description the edge press lands on the X, in the sidebar's viewport",
				str(_booted_viewport.gui_get_focus_owner()))
		check(_container.is_locked(),
				"P40: ...and the description it is the way out of is still stuck")
	await _end_main_fixture()

## P40: the landing is a real button -- a pad accept on it presses it, so a pad player opens the deck with no mouse.
func test_a_pad_accept_on_the_landed_hud_button_presses_it() -> void:
	await _left_off_the_leftmost_entrance_card()
	check(_booted_viewport.gui_get_focus_owner() == _first_hud_control(),
			"sanity: the edge press landed on the Deck button",
			str(_booted_viewport.gui_get_focus_owner()))
	for pressed : bool in [true, false]:
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_A
		pad.pressed = pressed
		_booted_viewport.push_input(pad)
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_instance_valid(DeckViewer._open),
			"P40: a pad accept on the button the edge press landed on opens the deck viewer",
			str(DeckViewer._open))
	await _close_the_open_viewer()
	await _end_main_fixture()

## P40: the map's own edge -- its dots are no Controls, so left with nothing picked is the one key route to the Deck button its basic view offers.
func test_left_on_the_map_with_nothing_picked_reaches_its_deck_button() -> void:
	await _start_map_fixture()
	check(_map.controller._selected == null, "sanity: the map rests with nothing picked",
			str(_map.controller._selected))
	check(_container.map_deck_button.is_visible_in_tree(),
			"sanity: the basic view's Deck button is the only control the map's sidebar offers")
	await _p40_press(_map_viewport, KEY_LEFT)
	var entered := _booted_viewport.gui_get_focus_owner() == _container.map_deck_button
	check(entered,
			"P40: left with nothing picked lands on the map's Deck button, in the sidebar's viewport",
			str(_booted_viewport.gui_get_focus_owner()))
	check(_map.controller._selected == null,
			"P40: ...and picks no node on the way out", str(_map.controller._selected))
	await _p40_press(_booted_viewport, KEY_RIGHT)
	check(entered and _booted_viewport.gui_get_focus_owner() == null,
			"P40: right off that one control gives the sidebar's focus back up",
			str(_booted_viewport.gui_get_focus_owner()))
	await _p40_press(_map_viewport, KEY_DOWN)
	check(entered and _map.controller._selected != null,
			"P40: ...so the map's own arrows answer again and pick a node",
			str(_map.controller._selected))
	await _end_main_fixture()
