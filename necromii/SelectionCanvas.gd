extends MeshInstance3D

@onready var viewport = $SubViewport

func _ready():
	material_override.albedo_texture = viewport.get_texture()
