extends MeshInstance3D

## One thin extruded layer of the 3D map. The viewer builds the shared HeightMap +
## colormap textures once and hands the same two Texture2Ds to every slice; each
## slice differs only by its height index (its cull floor) and the bottom flag.
##
## The scene ships a single shared ShaderMaterial; since instanced sub-resources
## are shared across instances, each slice duplicates it on first use so its
## slice_lo / back_scale are its own.

@export var height: int = 0            # this slice's index, 0 = bottom layer
@export var total_slices: int = 1
@export var edge_flare: float = 1.0    # multiplies the 1px base flare (back_scale)
@export var heightmap_tex: Texture2D:
	set(value):
		heightmap_tex = value
		update()
@export var color_tex: Texture2D:
	set(value):
		color_tex = value
		update()

var _mat: ShaderMaterial

func _ready() -> void:
	update()

# Per-instance material, duplicated once from the scene's shared template.
func _ensure_material() -> ShaderMaterial:
	if _mat == null:
		var src := material_override as ShaderMaterial
		_mat = src.duplicate() if src else ShaderMaterial.new()
		material_override = _mat
	return _mat

func update() -> void:
	if not is_inside_tree() or color_tex == null:
		return
	var mat := _ensure_material()
	mat.set_shader_parameter("Texture", color_tex)
	if heightmap_tex:
		mat.set_shader_parameter("HeightMap", heightmap_tex)
	mat.set_shader_parameter("slice_lo", float(height) / float(maxi(1, total_slices)))
	var w := float(color_tex.get_width())
	var h := float(color_tex.get_height())
	mat.set_shader_parameter("tex_texel", Vector2(1.0 / w, 1.0 / h))
	mat.set_shader_parameter("is_bottom_slice", height == 0)
	# Flare the base out ~1px of the colormap so the slice above (which eroded 1px)
	# is refilled. back_scale scales about center, so +2 texels = +1px per side.
	# The bottom layer stays a plain cube (no trim, no flare).
	var flare := 1.0 if height == 0 else 1.0 + (2.0 / w) * edge_flare
	mat.set_shader_parameter("back_scale", flare)
