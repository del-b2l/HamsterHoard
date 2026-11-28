extends Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var route_points: Array[Vector2] = []
var current_target := 0
var move_speed := 100.0

func set_route(points: Array[Vector2]) -> void:
	route_points = points
	current_target = 0

	if route_points.size() > 0:
		global_position = route_points[0]

func _process(delta: float) -> void:
	if route_points.size() < 2:
		return

	var target := route_points[current_target]
	var direction := global_position.direction_to(target)

	global_position = global_position.move_toward(
		target,
		move_speed * delta
	)

	if global_position.distance_to(target) < 2.0:
		current_target = (current_target + 1) % route_points.size()

	# Flip the sprite when moving left.
	if direction.x < -0.1:
		sprite.flip_h = true
	elif direction.x > 0.1:
		sprite.flip_h = false
