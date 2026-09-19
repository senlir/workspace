class_name ContentDatabase
extends RefCounted

var tools: Dictionary = {}
var monsters: Dictionary = {}
var platforms: Dictionary = {}
var platform_profiles: Dictionary = {}
var groups: Dictionary = {}
var score_tiers: Array[Dictionary] = []


func load_all() -> void:
	tools = _index_by_id(_load_json("res://data/config/cfg_daoju.json"))
	monsters = _index_by_id(_load_json("res://data/config/cfg_guaiwu.json"))
	platforms = _index_by_id(_load_json("res://data/config/cfg_shuzhi.json"))
	platform_profiles = _index_by_id(_load_json("res://data/config/cfg_platform_profiles.json"))
	groups = _index_by_id(_load_json("res://data/config/cfg_zuhe.json"))
	for row in _load_json("res://data/config/cfg_score_zuhe.json"):
		var tier: Dictionary = row.duplicate(true)
		tier["group_slots"] = _parse_slots(str(row["ids"]))
		tier["tool_slots"] = _parse_slots(str(row["daojuid"]))
		score_tiers.append(tier)
	score_tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) < int(b["score"]))


func get_tier(score: int) -> Dictionary:
	var selected: Dictionary = score_tiers[0]
	for tier in score_tiers:
		if int(tier["score"]) == 99999:
			break
		if score >= int(tier["score"]):
			selected = tier
		else:
			break
	return selected


func get_platform_profile(id: int) -> Dictionary:
	if platform_profiles.has(id):
		return platform_profiles[id]
	var cfg: Dictionary = platforms.get(id, {})
	var height := float(cfg.get("houdu", 32.0))
	return {"id": id, "surface_y": height * 0.5, "collision_height": height, "edge_inset": 0.0}


func pick_group_id(score: int, slot_index: int, rng: RandomNumberGenerator) -> int:
	var tier := get_tier(score)
	var slots: Array = tier["group_slots"]
	var candidates: Array = slots[slot_index % slots.size()]
	return int(candidates[rng.randi_range(0, candidates.size() - 1)])


func pick_tool_id(score: int, slot_index: int, rng: RandomNumberGenerator) -> int:
	var tier := get_tier(score)
	var slots: Array = tier["tool_slots"]
	var candidates: Array = slots[slot_index % slots.size()]
	return int(candidates[rng.randi_range(0, candidates.size() - 1)])


func _load_json(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open config: %s" % path)
		return []
	var value = JSON.parse_string(file.get_as_text())
	if not value is Array:
		push_error("Config root must be an array: %s" % path)
		return []
	return value


func _index_by_id(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		result[int(row["id"])] = row
	return result


func _parse_slots(value: String) -> Array:
	var result: Array = []
	for slot in value.split("#"):
		var candidates: Array[int] = []
		for item in slot.split("&"):
			candidates.append(int(item))
		result.append(candidates)
	return result
