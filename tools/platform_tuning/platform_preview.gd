class_name PlatformTuningPreview
extends Control

var platform_texture: Texture2D
var surface_y := 0.0
var collision_height := 32.0
var edge_inset := 0.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("18212d"), true)
	if platform_texture == null:
		return
	var image_size := platform_texture.get_size()
	var scale_factor := minf((size.x - 40.0) / image_size.x, 1.0)
	var draw_size := image_size * scale_factor
	var origin := Vector2((size.x - draw_size.x) * 0.5, 36.0)
	draw_texture_rect(platform_texture, Rect2(origin, draw_size), false)
	var surface_screen_y := origin.y + surface_y * scale_factor
	var inset := edge_inset * scale_factor
	var collision_rect := Rect2(
		Vector2(origin.x + inset, surface_screen_y),
		Vector2(maxf(1.0, draw_size.x - inset * 2.0), collision_height * scale_factor)
	)
	draw_rect(collision_rect, Color(0.25, 0.9, 0.45, 0.24), true)
	draw_rect(collision_rect, Color("63e581"), false, 2.0)
	draw_line(
		Vector2(origin.x + inset, surface_screen_y),
		Vector2(origin.x + draw_size.x - inset, surface_screen_y),
		Color("ff5555"),
		4.0
	)


func set_profile(texture: Texture2D, profile: Dictionary) -> void:
	platform_texture = texture
	surface_y = float(profile.get("surface_y", 0.0))
	collision_height = float(profile.get("collision_height", 32.0))
	edge_inset = float(profile.get("edge_inset", 0.0))
	queue_redraw()
