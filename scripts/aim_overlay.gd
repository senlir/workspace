class_name AimOverlay
extends Node2D

var owner_game: Node


func _draw() -> void:
	if owner_game == null or not owner_game.aiming:
		return
	var start: Vector2 = owner_game.drag_origin
	var finish: Vector2 = owner_game.drag_position
	draw_circle(start, 58.0, Color(1, 1, 1, 0.13))
	draw_arc(start, 58.0, 0.0, TAU, 48, Color(1, 1, 1, 0.65), 3.0)
	draw_line(start, finish, Color("ffe36d"), 7.0, true)
	draw_circle(finish, 18.0, Color("ff9e2c"))
	var launch := -(finish - start)
	if launch.length() > 1.0:
		var direction := launch.normalized()
		for index in range(1, 7):
			var point: Vector2 = owner_game.player.position + direction * float(index * 42)
			draw_circle(point, maxf(2.0, 8.0 - index), Color(1, 1, 1, 0.9 - index * 0.1))
