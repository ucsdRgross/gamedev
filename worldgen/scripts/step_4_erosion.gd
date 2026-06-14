class_name Step4ErosionAndRivers
extends GenerationStep

## GPU hydraulic erosion / flow simulation (Step 4 of the design).
##
## The previous CPU bucket-flow placeholder has been removed (it was never the
## simulation the spec asks for). This is now a pass-through stub: the real
## humidity-seeded ping-pong droplet simulation will be built here per the
## approved plan. Until then, no carving and no rivers are produced, so the
## erosion/river slots simply show the un-eroded terrain.
func execute(gen: WorldGenerator, settings: WorldSettings) -> void:
	gen.river_nodes.clear()
	gen._save_snapshot_bridge("Erosion")
	gen.snapshots["Rivers_Only"] = gen.snapshots["Erosion"].duplicate()
	gen.generation_step_finished.emit("Rivers_Only")
