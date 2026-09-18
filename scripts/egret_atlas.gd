class_name EgretAtlas
extends RefCounted

var _json_cache: Dictionary = {}


func frame(texture_path: String, json_path: String, frame_name: String) -> AtlasTexture:
	var data := _read_json(json_path)
	var frames: Dictionary = data.get("frames", {})
	if not frames.has(frame_name):
		push_error("Missing atlas frame %s in %s" % [frame_name, json_path])
		return null
	return _atlas_texture(texture_path, frames[frame_name])


func movie_frames(texture_path: String, json_path: String, clip_name: String = "") -> SpriteFrames:
	var data := _read_json(json_path)
	var clips: Dictionary = data.get("mc", {})
	if clips.is_empty():
		return SpriteFrames.new()
	if clip_name.is_empty() or not clips.has(clip_name):
		clip_name = str(clips.keys()[0])
	var clip: Dictionary = clips[clip_name]
	var resources: Dictionary = data.get("res", {})
	var result := SpriteFrames.new()
	result.remove_animation("default")
	var labels: Array = clip.get("labels", [])
	if labels.is_empty():
		labels = [{"name": "walk", "frame": 1, "end": clip.get("frames", []).size()}]
	for label in labels:
		var animation_name := str(label.get("name", "walk"))
		result.add_animation(animation_name)
		result.set_animation_speed(animation_name, float(clip.get("frameRate", 12)))
		result.set_animation_loop(animation_name, animation_name != "walk1")
		var first := maxi(0, int(label.get("frame", 1)) - 1)
		var last := mini(clip.get("frames", []).size() - 1, int(label.get("end", first + 1)) - 1)
		for index in range(first, last + 1):
			var movie_frame: Dictionary = clip["frames"][index]
			var resource_name := str(movie_frame["res"])
			if resources.has(resource_name):
				result.add_frame(animation_name, _atlas_texture(texture_path, resources[resource_name]))
	return result


func _atlas_texture(texture_path: String, region_data: Dictionary) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = load(texture_path)
	result.region = Rect2(
		float(region_data.get("x", 0)),
		float(region_data.get("y", 0)),
		float(region_data.get("w", 1)),
		float(region_data.get("h", 1))
	)
	return result


func _read_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open atlas: %s" % path)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("Invalid atlas JSON: %s" % path)
		return {}
	_json_cache[path] = data
	return data
