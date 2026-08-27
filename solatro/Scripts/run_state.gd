class_name RunState
extends Resource

## The single persisted run document (replaces PlayerSave): world seed, token position,
## lap/fame/luck progression, the run deck, and the traveled-edge history. Saved to
## user://run_save/run.tres by RunManager; only @export vars persist.

## Reproducibility handle for the world map; pinned non-zero at run start so Continue
## regenerates identical terrain + node roles.
@export var world_seed : int = 0
## Graph node id the player token sits on (-1 = fresh run, start at the lap origin).
@export var current_node_id : int = -1
## Completed-tour counter; direction reverses each lap (see is_reversed).
@export var lap : int = 0
## Accumulated fame: the FULL total_score of every won game.
@export var fame : int = 0
## The run deck (name matches old PlayerSave so Game.add_deck keeps working).
@export var card_datas : Array[CardData]
@export var rule_datas : Array[CardData]
## Traveled edge history: (edge_src_id, edge_dst_id, lap), always stored in the graph's
## forward-edge orientation regardless of travel direction. Accumulates across laps.
@export var traveled : Array[Vector3i]
## Goal injected into the next Game (set when a game node is entered, before enter_game).
@export var pending_goal : int = 0
## Node being resolved when a game starts (quit mid-show resumes the exact board below).
@export var pending_node_id : int = -1

## The in-progress show's FULL undo stack (empty when not in a show): one serialization-
## ready GameData snapshot per committed action, oldest first, current = last. Persisting
## the whole history means the undo system survives a quit AND closing the game can't
## rewind a mistake (anti-cheat). Snapshots are "saveable" form — modifier self-cycles
## unlinked, scores packed to primitives — rebuilt to runtime by Game when pulled.
@export var game_history : Array[GameData] = []
## Snapshots the undo cap dropped from the front of game_history this show (E5-lite).
## game_history_trimmed + game_history.size() = total actions committed — Game hashes that
## sum for replay-stable prop sides (entity_side_for_row).
@export var game_history_trimmed : int = 0
## A board-mutating button (Submit/Next) was pressed but its async resolution (scoring /
## draw animations) had not committed when the run was last saved. Persisted so a quit
## mid-resolution REPLAYS the action from the committed pre-action board on resume — the
## player can't dodge a Submit by killing the app (anti-cheat). Empty = no action pending.
## Values are the mod event name the action runs: &"on_run_scorer" (Submit) / &"on_next"
## (Next). Cleared the instant an action fully commits (see Game.save_state).
@export var pending_action : StringName = &""

## Which Entrance slot the pending placement took its card from, and where it was aimed
## (grid, x, y, h). Only meaningful while `pending_action` is the placement marker: a
## placement is identified by its SLOT rather than by the card, because the pre-placement
## board a replay starts from carries its own copies of every card and no reference to the
## original survives the save. `-1` = no placement pending.
@export var pending_placement_slot : int = -1
@export var pending_placement_coord : Vector4i = Vector4i.ZERO

## Odd laps traverse the graph backwards (end -> start).
func is_reversed() -> bool:
	return lap % 2 == 1
