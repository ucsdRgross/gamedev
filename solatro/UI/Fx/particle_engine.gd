class_name ParticleEngine
extends Node2D
## THE particle path for the whole game. Every particle, from any source and of any kind, is
## spawned here and simulated in one pass under ONE global cap — so total cost is bounded by
## construction and no single effect can starve the frame.
##
## WORLD-SPACE BY DESIGN: a particle's position is its own, so an emitter moving, despawning or
## being freed never moves or removes the particles it already emitted. That is what makes
## "embers shouldn't follow fire if the flaming object leaves the area" true by construction
## rather than by teardown discipline — emitters own no particles and have nothing to release.
##
## This is SHARED INFRASTRUCTURE, not part of any one effect. Future systems (score bursts, card
## dust, prop impacts) call emit() instead of adding a CPUParticles2D/GPUParticles2D anywhere.

## The ONE cap. When full, the OLDEST particle is recycled: a burst always shows, and old debris
## is what gives way. Fixed size means the cap is structural rather than a policy someone can
## forget to apply.
const MAX_PARTICLES := 1024

## Floats per MultiMesh instance: an 8-float 2D transform followed by an RGBA colour.
const STRIDE := 12

## The engine on the current screen, or null. Effects live in views that have no play area
## (a card in the deck viewer still shows its statuses), so emit() must be a NO-OP when there is
## no engine rather than an assumption that one exists.
static var CURRENT : ParticleEngine = null

var _pos_x := PackedFloat32Array()
var _pos_y := PackedFloat32Array()
var _vel_x := PackedFloat32Array()
var _vel_y := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
## Which kind each slot is running. Parallel to the packed arrays rather than inside them, since
## it is a reference, not a number.
var _spec : Array[ParticleSpec] = []
## Next slot to hand out — the ring's write head, which gives oldest-first eviction for free.
var _next : int = 0
var _buffer := PackedFloat32Array()

@onready var _mesh : MultiMeshInstance2D = _build_mesh()

func _ready() -> void:
	CURRENT = self
	_pos_x.resize(MAX_PARTICLES)
	_pos_y.resize(MAX_PARTICLES)
	_vel_x.resize(MAX_PARTICLES)
	_vel_y.resize(MAX_PARTICLES)
	_age.resize(MAX_PARTICLES)
	_life.resize(MAX_PARTICLES)
	_spec.resize(MAX_PARTICLES)
	_buffer.resize(MAX_PARTICLES * STRIDE)
	# Every slot starts dead: age past its lifetime, drawn at zero scale.
	for i : int in MAX_PARTICLES:
		_age[i] = 1.0
		_life[i] = 0.0

func _exit_tree() -> void:
	if CURRENT == self: CURRENT = null

## One MultiMeshInstance2D for EVERY particle in the game — a single draw call, written per frame
## as one buffer assignment rather than through per-instance setters. This is what makes "lots of
## particles" a non-issue.
func _build_mesh() -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_PARTICLES
	var node := MultiMeshInstance2D.new()
	node.name = "Particles"
	node.multimesh = mm
	add_child(node)
	return node

## Spawn `count` particles of `spec` at a GLOBAL position, travelling roughly along `dir`. Any
## system may call this; nothing else in the game creates particles. Over-cap requests recycle
## the oldest slots rather than being dropped.
func emit(spec: ParticleSpec, at: Vector2, count: int, dir := Vector2.UP) -> void:
	if not spec or count <= 0: return
	var local := to_local(at)
	var base := dir.angle() if dir.length_squared() > 0.0 else -PI * 0.5
	for _i : int in count:
		var slot := _next
		_next = (_next + 1) % MAX_PARTICLES
		var angle := base + randf_range(-spec.spread, spec.spread)
		var speed := spec.speed * (1.0 - randf() * spec.speed_var)
		_pos_x[slot] = local.x
		_pos_y[slot] = local.y
		_vel_x[slot] = cos(angle) * speed
		_vel_y[slot] = sin(angle) * speed
		_age[slot] = 0.0
		_life[slot] = maxf(spec.lifetime * (1.0 - randf() * spec.lifetime_var), 0.01)
		_spec[slot] = spec

## Convenience for callers that may run where there is no engine — a card in a viewer, or a test.
## Silently does nothing rather than crashing: "no engine" is a supported state.
static func spawn(spec: ParticleSpec, at: Vector2, count: int, dir := Vector2.UP) -> void:
	if CURRENT: CURRENT.emit(spec, at, count, dir)

## One O(n) pass over every slot, allocating nothing. Stepped by delta * pacing like every other
## animation here, so particles slow and quicken with act compression.
func _process(delta: float) -> void:
	var step := delta * FxAttachment.pacing()
	for i : int in MAX_PARTICLES:
		var out := i * STRIDE
		var spec : ParticleSpec = _spec[i]
		if not spec or _age[i] >= _life[i]:
			# Dead: a zero-scale, fully transparent instance. Still written, because the buffer is
			# assigned whole — branching to skip it would cost more than the twelve floats.
			for j : int in STRIDE:
				_buffer[out + j] = 0.0
			continue
		_age[i] += step
		var decay := maxf(1.0 - spec.drag * step, 0.0)
		_vel_x[i] = _vel_x[i] * decay + spec.gravity.x * step
		_vel_y[i] = _vel_y[i] * decay + spec.gravity.y * step
		_pos_x[i] += _vel_x[i] * step
		_pos_y[i] += _vel_y[i] * step
		var t := clampf(_age[i] / maxf(_life[i], 1e-4), 0.0, 1.0)
		var size := lerpf(spec.size_start, spec.size_end, t)
		# Position and UNIFORM SCALE only — never rotation. A rotating sprite is a rotating pixel
		# grid, which the universal VFX rule forbids; embers are blobs, so orientation carries
		# nothing anyway.
		_buffer[out + 0] = size
		_buffer[out + 1] = 0.0
		_buffer[out + 2] = 0.0
		_buffer[out + 3] = _pos_x[i]
		_buffer[out + 4] = 0.0
		_buffer[out + 5] = size
		_buffer[out + 6] = 0.0
		_buffer[out + 7] = _pos_y[i]
		var col := spec.ramp.sample(t) if spec.ramp else Color.WHITE
		_buffer[out + 8] = col.r
		_buffer[out + 9] = col.g
		_buffer[out + 10] = col.b
		_buffer[out + 11] = col.a
	_mesh.multimesh.buffer = _buffer

## How many particles are currently alive. For tests and for tuning the cap.
func live_count() -> int:
	var n := 0
	for i : int in MAX_PARTICLES:
		if _spec[i] and _age[i] < _life[i]: n += 1
	return n
