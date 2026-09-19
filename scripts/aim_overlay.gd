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
	var prediction: Dictionary = owner_game.get_trajectory_prediction(finish - start)
	var points: Array[Vector2] = prediction["points"]
	for index in range(points.size()):
		var alpha := lerpf(0.9, 0.25, float(index) / maxf(1.0, points.size() - 1.0))
		draw_circle(points[index], 5.0 if index % 2 == 0 else 3.0, Color(1.0, 1.0, 1.0, alpha))
	var landing: Dictionary = prediction["landing"]
	if not landing.is_empty():
		var point: Vector2 = landing["position"]
		draw_circle(point + Vector2(0.0, owner_game.PLAYER_RADIUS), 15.0, Color(0.35, 1.0, 0.45, 0.22))
		draw_arc(point + Vector2(0.0, owner_game.PLAYER_RADIUS), 15.0, 0.0, TAU, 24, Color("65ff78"), 3.0)
		draw_line(point + Vector2(-12.0, owner_game.PLAYER_RADIUS - 5.0), point + Vector2(-3.0, owner_game.PLAYER_RADIUS + 4.0), Color("65ff78"), 3.0, true)
		draw_line(point + Vector2(-3.0, owner_game.PLAYER_RADIUS + 4.0), point + Vector2(13.0, owner_game.PLAYER_RADIUS - 10.0), Color("65ff78"), 3.0, true)
