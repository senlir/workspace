@tool
extends Control

const CONFIG_PATH := "res://data/config/cfg_platform_profiles.json"
const PLATFORM_PATH := "res://data/config/cfg_shuzhi.json"
const ATLAS_TEXTURE := "res://assets/ui/game1.png"
const ATLAS_JSON := "res://assets/ui/game1.json"
const AtlasClass = preload("res://scripts/egret_atlas.gd")
const PreviewClass = preload("res://tools/platform_tuning/platform_preview.gd")

var atlas = AtlasClass.new()
var platform_rows: Array = []
var profiles: Array = []
var selected_index := 0

var selector: OptionButton
var preview: Control
var surface_spin: SpinBox
var height_spin: SpinBox
var inset_spin: SpinBox
var status_label: Label


func _ready() -> void:
	_build_ui()
	_load_data()
	_show_selected()
	if "--capture-platform-tool" in OS.get_cmdline_user_args():
		call_deferred("_capture_tool")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101720")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "平台站位与碰撞调校"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	var help := Label.new()
	help.text = "红线是角色脚底站位面，绿色区域是碰撞厚度。修改数值后保存，重新开始游戏即可生效。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	selector = OptionButton.new()
	selector.item_selected.connect(_on_platform_selected)
	column.add_child(selector)
	preview = PreviewClass.new()
	preview.custom_minimum_size = Vector2(600, 190)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	surface_spin = _add_spin(grid, "站位线 surface_y", 0.0, 160.0, 0.5)
	height_spin = _add_spin(grid, "碰撞厚度 collision_height", 1.0, 160.0, 0.5)
	inset_spin = _add_spin(grid, "左右不可站边距 edge_inset", 0.0, 100.0, 0.5)
	for spin in [surface_spin, height_spin, inset_spin]:
		spin.value_changed.connect(_on_value_changed)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var save := Button.new()
	save.text = "保存配置"
	save.pressed.connect(_save_data)
	actions.add_child(save)
	var reload := Button.new()
	reload.text = "重新载入"
	reload.pressed.connect(_reload_data)
	actions.add_child(reload)
	status_label = Label.new()
	status_label.text = ""
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(status_label)


func _add_spin(parent: GridContainer, title: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _load_data() -> void:
	platform_rows = _load_json(PLATFORM_PATH)
	profiles = _load_json(CONFIG_PATH)
	selector.clear()
	for row in platform_rows:
		selector.add_item("ID %s · %s" % [row["id"], row["img"]])
	selected_index = mini(selected_index, maxi(0, platform_rows.size() - 1))


func _load_json(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取 %s" % path)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _show_selected() -> void:
	if platform_rows.is_empty() or profiles.is_empty():
		return
	selector.select(selected_index)
	var row: Dictionary = platform_rows[selected_index]
	var profile := _profile_for_id(int(row["id"]))
	var texture := atlas.frame(ATLAS_TEXTURE, ATLAS_JSON, str(row["img"]))
	preview.set_profile(texture, profile)
	surface_spin.set_value_no_signal(float(profile["surface_y"]))
	height_spin.set_value_no_signal(float(profile["collision_height"]))
	inset_spin.set_value_no_signal(float(profile["edge_inset"]))
	status_label.text = "资源尺寸 %d × %d" % [texture.get_width(), texture.get_height()]


func _profile_for_id(id: int) -> Dictionary:
	for profile in profiles:
		if int(profile["id"]) == id:
			return profile
	var created := {"id": id, "surface_y": 16.0, "collision_height": 32.0, "edge_inset": 0.0}
	profiles.append(created)
	return created


func _on_platform_selected(index: int) -> void:
	selected_index = index
	_show_selected()


func _on_value_changed(_value: float) -> void:
	if platform_rows.is_empty():
		return
	var row: Dictionary = platform_rows[selected_index]
	var profile := _profile_for_id(int(row["id"]))
	profile["surface_y"] = surface_spin.value
	profile["collision_height"] = height_spin.value
	profile["edge_inset"] = inset_spin.value
	preview.set_profile(preview.platform_texture, profile)
	status_label.text = "有未保存修改"


func _save_data() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "保存失败"
		return
	file.store_string(JSON.stringify(profiles, "  "))
	status_label.text = "已保存到 cfg_platform_profiles.json"


func _reload_data() -> void:
	_load_data()
	_show_selected()
	status_label.text = "已重新载入"


func _capture_tool() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Platform tuning preview must render")
	image.save_png("res://artifacts/platform_tuning.png")
	print("PLATFORM TOOL PASS: rendered platform profile editor")
	get_tree().quit()
