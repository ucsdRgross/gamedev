class_name attackDefault
extends Node2D

onready var _astar: Resource = preload("res://resources/PathFinder.tres")

export var speed = 0.0
export var liftime = 3.0
var parent_cell
var target_cell
var direction

onready var timer := $Timer
onready var hitbox := $Hitbox

func setup(allegiance, parent_cell, target_cell):
	pass
	
func normalized_speed():
	pass	
	
func _physics_process(delta):
	pass

func _on_impact():
	pass

#entered enemy hurtbox
func _on_Hitbox_area_entered(area):
	pass
