extends MeshInstance3D

@export var height : int
@export var total_slices : int
@export var heightmap_texture : Image:
	set(value):
		heightmap_texture = value
		update()
@export var color_texture : Image:
	set(value):
		color_texture = value
		update()

func update():
	pass
	# check height, use this as paremeter to cut off parts of color texture lower than the height of heightmap texture
	# cut off 1 pixel on edge of remaining color texture.
	# apply height filtered color texture to the extrude shader on the mesh
	# pass in size of color texture to shader, it will use this to widen bottom of the mesh by 1 pixel using vertex shader
