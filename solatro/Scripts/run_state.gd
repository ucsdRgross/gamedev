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
## Accumulated fame: the FULL total_score of every won game, overscore included.
@export var fame : int = 0
## Σ overscore_i / goal_i across wins — nonlinearly inflates future fame requirements
## (see RunManager.goal_for).
@export var overscore_ratio_sum : float = 0.0
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

## Exact snapshot of an in-progress show (null when not in one) so a mid-game quit resumes
## the precise board, decks, scores and act count. Managed by Game + RunManager.
@export var game_state : GameData = null
@export var game_submits : int = 0
## The snapshot's BigNumber score arrays flattened to [[mantissa, exponent], ...] lists —
## RefCounted BigNumber can't be written by ResourceSaver, so RunManager stashes them here
## around the write and rebuilds the arrays on load.
@export var game_scores : Dictionary = {}

## Odd laps traverse the graph backwards (end -> start).
func is_reversed() -> bool:
	return lap % 2 == 1
