extends Node2D

const ContentDatabaseClass = preload("res://scripts/content_database.gd")
const EgretAtlasClass = preload("res://scripts/egret_atlas.gd")
const AimOverlayClass = preload("res://scripts/aim_overlay.gd")

const VIEW_SIZE := Vector2(640.0, 1091.0)
const PLAYER_RADIUS := 34.0
const GRAVITY := 1450.0
const MAX_LAUNCH_SPEED := 980.0
const MAX_DRAG := 150.0
const CAMERA_LINE := 500.0
const GROUP_GAP := 195.0
const MAX_HP := 4
const ROUND_TIME := 180.0

enum GameState { HOME, PLAYING, GAME_OVER }

var db = ContentDatabaseClass.new()
var atlas = EgretAtlasClass.new()
var rng := RandomNumberGenerator.new()
var state := GameState.HOME

var world := Node2D.new()
var background_layer := Node2D.new()
var content_layer := Node2D.new()
var player := AnimatedSprite2D.new()
var aim_layer = AimOverlayClass.new()
var hud := CanvasLayer.new()
var home := CanvasLayer.new()
var game_over_panel := CanvasLayer.new()
var music_player := AudioStreamPlayer.new()

var background_sprites: Array[Sprite2D] = []
var content_groups: Array[Dictionary] = []
var velocity := Vector2.ZERO
var grounded := true
var aiming := false
var drag_origin := Vector2.ZERO
var drag_position := Vector2.ZERO
var hp := MAX_HP
var score := 0
var energy := 0
var time_left := ROUND_TIME
var hurt_cooldown := 0.0
var rocket_time := 0.0
var highest_group_y := 900.0
var tier_slot := 0
var current_tier_score := -1
var safe_position := Vector2(320.0, 840.0)

var score_label: Label
var timer_label: Label
var hp_label: Label
var energy_label: Label
var result_label: Label
var hint_label: Label


func _ready() -> void:
	rng.randomize()
	db.load_all()
	_build_world()
	_build_home()
	_build_hud()
	_build_game_over()
	_build_audio()
	show_home()
	if "--capture-smoke" in OS.get_cmdline_user_args():
		call_deferred("_capture_smoke")


func _build_world() -> void:
	add_child(world)
	world.add_child(background_layer)
	world.add_child(content_layer)
	world.add_child(player)
	world.add_child(aim_layer)
	aim_layer.owner_game = self
	player.sprite_frames = atlas.movie_frames(
		"res://assets/animations/player/playmc3.png",
		"res://assets/animations/player/playmc3.json",
		"playmc3"
	)
	player.animation = "walk1"
	player.position = safe_position
	player.z_index = 20


func _build_home() -> void:
	add_child(home)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/backgrounds/bg3.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	home.add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.035, 0.08, 0.18)
	shade.position = Vector2(0, 0)
	shade.size = VIEW_SIZE
	home.add_child(shade)

	var title := _make_label("弹 弹 鸟", 72, Color("fff1a8"), true)
	title.position = Vector2(70, 120)
	title.size = Vector2(500, 100)
	title.add_theme_color_override("font_shadow_color", Color("6c2917"))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 7)
	home.add_child(title)

	var subtitle := _make_label("困难不可想象", 28, Color.WHITE, true)
	subtitle.position = Vector2(150, 220)
	subtitle.size = Vector2(340, 50)
	home.add_child(subtitle)

	var start_button := _make_button("开始挑战", Color("65c92f"))
	start_button.position = Vector2(130, 760)
	start_button.size = Vector2(380, 92)
	start_button.pressed.connect(start_game)
	home.add_child(start_button)

	var rules := _make_label("向下拖动 · 松手弹射 · 不断向上", 22, Color("fff8df"), true)
	rules.position = Vector2(80, 890)
	rules.size = Vector2(480, 48)
	home.add_child(rules)


func _build_hud() -> void:
	add_child(hud)
	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.08, 0.12, 0.78)
	bar.position = Vector2(18, 18)
	bar.size = Vector2(604, 106)
	hud.add_child(bar)

	score_label = _make_label("得分 0", 28, Color("ffe17a"), false)
	score_label.position = Vector2(38, 32)
	score_label.size = Vector2(230, 40)
	hud.add_child(score_label)
	timer_label = _make_label("时间 180", 28, Color.WHITE, false)
	timer_label.position = Vector2(385, 32)
	timer_label.size = Vector2(210, 40)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(timer_label)
	hp_label = _make_label("生命 ♥ ♥ ♥ ♥", 23, Color("ff6d79"), false)
	hp_label.position = Vector2(38, 76)
	hp_label.size = Vector2(300, 34)
	hud.add_child(hp_label)
	energy_label = _make_label("能量 □ □ □ □ □", 22, Color("dff44d"), false)
	energy_label.position = Vector2(330, 76)
	energy_label.size = Vector2(265, 34)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(energy_label)

	hint_label = _make_label("手指向下滑，笨鸟向上跳", 24, Color.WHITE, true)
	hint_label.position = Vector2(100, 170)
	hint_label.size = Vector2(440, 56)
	hint_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint_label.add_theme_constant_override("shadow_offset_x", 2)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(hint_label)
	hud.visible = false


func _build_game_over() -> void:
	add_child(game_over_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.72)
	shade.position = Vector2.ZERO
	shade.size = VIEW_SIZE
	game_over_panel.add_child(shade)
	var panel := ColorRect.new()
	panel.color = Color("f7bd42")
	panel.position = Vector2(90, 310)
	panel.size = Vector2(460, 390)
	game_over_panel.add_child(panel)
	var title := _make_label("本局结束", 48, Color("54240d"), true)
	title.position = Vector2(120, 350)
	title.size = Vector2(400, 70)
	game_over_panel.add_child(title)
	result_label = _make_label("得分 0", 38, Color("54240d"), true)
	result_label.position = Vector2(120, 450)
	result_label.size = Vector2(400, 60)
	game_over_panel.add_child(result_label)
	var restart := _make_button("再来一次", Color("68c934"))
	restart.position = Vector2(155, 570)
	restart.size = Vector2(330, 80)
	restart.pressed.connect(start_game)
	game_over_panel.add_child(restart)
	game_over_panel.visible = false


func _build_audio() -> void:
	var music = load("res://assets/audio/1.mp3")
	if music is AudioStreamMP3:
		music.loop = true
	music_player.stream = music
	music_player.volume_db = -8.0
	add_child(music_player)
	music_player.play()


func show_home() -> void:
	state = GameState.HOME
	home.visible = true
	hud.visible = false
	game_over_panel.visible = false
	world.visible = false


func start_game() -> void:
	_clear_content()
	state = GameState.PLAYING
	home.visible = false
	hud.visible = true
	game_over_panel.visible = false
	world.visible = true
	hp = MAX_HP
	score = 0
	energy = 0
	time_left = ROUND_TIME
	hurt_cooldown = 0.0
	rocket_time = 0.0
	tier_slot = 0
	current_tier_score = 0
	velocity = Vector2.ZERO
	grounded = true
	aiming = false
	player.position = safe_position
	player.modulate = Color.WHITE
	player.play("walk1")
	hint_label.visible = true
	_create_backgrounds()
	_spawn_initial_content()
	_update_hud()


func _process(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	time_left = maxf(0.0, time_left - delta)
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	rocket_time = maxf(0.0, rocket_time - delta)
	player.modulate = Color("ffd95b") if rocket_time > 0.0 else Color.WHITE
	if time_left <= 0.0:
		_finish_game()
		return
	_update_player(delta)
	_update_platforms(delta)
	_update_monsters(delta)
	_update_pickups()
	_update_aim_visual()
	_update_hud()


func _update_player(delta: float) -> void:
	var previous_position := player.position
	if not grounded:
		velocity.y += GRAVITY * delta
		player.position += velocity * delta
		_check_platform_landing(previous_position)
	if player.position.x < PLAYER_RADIUS:
		player.position.x = PLAYER_RADIUS
		velocity.x = absf(velocity.x) * 0.72
	elif player.position.x > VIEW_SIZE.x - PLAYER_RADIUS:
		player.position.x = VIEW_SIZE.x - PLAYER_RADIUS
		velocity.x = -absf(velocity.x) * 0.72
	if player.position.y < CAMERA_LINE:
		_scroll_world(CAMERA_LINE - player.position.y)
		player.position.y = CAMERA_LINE
	if player.position.y > VIEW_SIZE.y + 80.0:
		_take_damage(true)
	if not grounded:
		player.flip_h = velocity.x < 0.0


func _check_platform_landing(previous_position: Vector2) -> void:
	if velocity.y <= 0.0:
		return
	var old_bottom := previous_position.y + PLAYER_RADIUS
	var new_bottom := player.position.y + PLAYER_RADIUS
	var best_top := INF
	var best_platform: Dictionary = {}
	for group in content_groups:
		var root: Node2D = group["root"]
		for platform in group["platforms"]:
			if platform.get("falling", false):
				continue
			var top := root.position.y + float(platform["local_y"])
			var left := float(platform["x"])
			var right := left + float(platform["width"])
			if old_bottom <= top + 2.0 and new_bottom >= top and player.position.x + 24.0 >= left and player.position.x - 24.0 <= right:
				if top < best_top:
					best_top = top
					best_platform = platform
					safe_position = Vector2(clampf(player.position.x, left + 32.0, right - 32.0), top - PLAYER_RADIUS)
	if best_top < INF:
		player.position.y = best_top - PLAYER_RADIUS
		velocity = Vector2.ZERO
		grounded = true
		player.play("walk1")
		if float(best_platform.get("fall_delay", 0.0)) > 0.0 and float(best_platform.get("fall_timer", -1.0)) < 0.0:
			best_platform["fall_timer"] = float(best_platform["fall_delay"])


func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.PLAYING:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and grounded:
			_begin_aim(event.position)
		elif not event.pressed and aiming:
			_release_aim()
	elif event is InputEventMouseMotion and aiming:
		drag_position = event.position
		_update_launch_preview()
	elif event is InputEventScreenTouch:
		if event.pressed and grounded:
			_begin_aim(event.position)
		elif not event.pressed and aiming:
			_release_aim()
	elif event is InputEventScreenDrag and aiming:
		drag_position = event.position
		_update_launch_preview()


func _begin_aim(position: Vector2) -> void:
	aiming = true
	drag_origin = position
	drag_position = position
	hint_label.visible = false
	player.play("walk2")


func _update_launch_preview() -> void:
	var drag := drag_position - drag_origin
	if drag.length() > MAX_DRAG:
		drag_position = drag_origin + drag.normalized() * MAX_DRAG


func _release_aim() -> void:
	var drag := drag_position - drag_origin
	aiming = false
	if drag.length() < 12.0:
		player.play("walk1")
		return
	var power := clampf(drag.length() / MAX_DRAG, 0.0, 1.0)
	velocity = -drag.normalized() * lerpf(260.0, MAX_LAUNCH_SPEED, power)
	grounded = false
	player.play("walk4" if power > 0.82 else "walk3")
	_play_sound(6)


func _update_aim_visual() -> void:
	aim_layer.queue_redraw()


func _draw() -> void:
	pass


func _scroll_world(amount: float) -> void:
	for group in content_groups:
		var root: Node2D = group["root"]
		root.position.y += amount
	for bg in background_sprites:
		bg.position.y += amount * 0.22
		if bg.position.y - bg.texture.get_height() * 0.5 > VIEW_SIZE.y:
			var highest := background_sprites[0].position.y
			for other in background_sprites:
				highest = minf(highest, other.position.y)
			bg.position.y = highest - bg.texture.get_height()
	highest_group_y += amount
	_cleanup_and_spawn()


func _spawn_initial_content() -> void:
	_spawn_safe_group(910.0)
	highest_group_y = 715.0
	for index in range(8):
		_spawn_config_group(highest_group_y)
		highest_group_y -= GROUP_GAP


func _spawn_safe_group(y: float) -> void:
	var root := Node2D.new()
	root.position.y = y
	content_layer.add_child(root)
	var platform := _create_platform(root, db.platforms[10], 0.0, 0.0, false)
	content_groups.append({"root": root, "platforms": [platform], "monsters": [], "pickups": [], "scored": false})


func _spawn_config_group(y: float) -> void:
	var tier: Dictionary = db.get_tier(score)
	var tier_score := int(tier["score"])
	if tier_score != current_tier_score:
		current_tier_score = tier_score
		tier_slot = 0
	var group_id: int = db.pick_group_id(score, tier_slot, rng)
	var tool_id: int = db.pick_tool_id(score, tier_slot, rng)
	tier_slot += 1
	var cfg: Dictionary = db.groups[group_id]
	var root := Node2D.new()
	root.position.y = y
	content_layer.add_child(root)
	var platforms: Array = []
	var monsters: Array = []
	var pickups: Array = []
	var first_width := 0.0
	if int(cfg["shuzhi1"]) > 0:
		var pcfg: Dictionary = db.platforms[int(cfg["shuzhi1"])]
		first_width = float(pcfg["lang"])
		platforms.append(_create_platform(root, pcfg, 0.0, 0.0, int(cfg["shuzhi1dir"]) == 1))
	if int(cfg["shuzhi2"]) > 0:
		var pcfg2: Dictionary = db.platforms[int(cfg["shuzhi2"])]
		platforms.append(_create_platform(root, pcfg2, first_width, 0.0, int(cfg["shuzhi2dir"]) == 1))
	for monster_field in ["guaiwu1", "guaiwu2"]:
		var monster_id := int(cfg[monster_field])
		if monster_id > 0:
			var x_field := "guaiwu1x" if monster_field == "guaiwu1" else "guaiwu2x"
			monsters.append(_create_monster(root, db.monsters[monster_id], float(cfg[x_field])))
	if tool_id > 0 and db.tools.has(tool_id):
		pickups.append(_create_pickup(root, db.tools[tool_id], float([200, 260, 320, 380, 440][rng.randi_range(0, 4)])))
	content_groups.append({"root": root, "platforms": platforms, "monsters": monsters, "pickups": pickups, "scored": false, "id": group_id})


func _create_platform(root: Node2D, cfg: Dictionary, start_x: float, local_y: float, mirrored: bool) -> Dictionary:
	var width := float(cfg["lang"])
	var x := start_x
	if mirrored:
		x = VIEW_SIZE.x - start_x - width
	var sprite := Sprite2D.new()
	sprite.texture = atlas.frame("res://assets/ui/game1.png", "res://assets/ui/game1.json", str(cfg["img"]))
	sprite.centered = false
	sprite.position = Vector2(x, local_y - float(cfg["houdu"]) * 0.5)
	sprite.flip_h = mirrored
	root.add_child(sprite)
	return {"sprite": sprite, "x": x, "width": width, "local_y": local_y, "height": float(cfg["houdu"]), "fall_delay": float(cfg["time"]), "fall_timer": -1.0, "fall_speed": 0.0, "falling": false}


func _update_platforms(delta: float) -> void:
	for group in content_groups:
		for platform in group["platforms"]:
			var timer := float(platform.get("fall_timer", -1.0))
			if timer >= 0.0 and not platform.get("falling", false):
				timer -= delta
				platform["fall_timer"] = timer
				if timer <= 0.0:
					platform["falling"] = true
			if platform.get("falling", false):
				platform["fall_speed"] = float(platform["fall_speed"]) + GRAVITY * delta * 0.65
				platform["local_y"] = float(platform["local_y"]) + float(platform["fall_speed"]) * delta
				var sprite: Sprite2D = platform["sprite"]
				sprite.position.y = float(platform["local_y"]) - float(platform["height"]) * 0.5


func _create_monster(root: Node2D, cfg: Dictionary, x: float) -> Dictionary:
	var name := str(cfg["img"])
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = atlas.movie_frames(
		"res://assets/animations/enemies/%s.png" % name,
		"res://assets/animations/enemies/%s.json" % name,
		"walk"
	)
	sprite.play("walk")
	sprite.position = Vector2(x, -50.0 - float(cfg["sky"]))
	sprite.z_index = 8
	root.add_child(sprite)
	var direction := 1.0 if x <= 320.0 else -1.0
	sprite.flip_h = direction > 0.0
	return {"sprite": sprite, "cfg": cfg, "direction": direction, "active": int(cfg["movetype"]) == 1, "dead": false}


func _create_pickup(root: Node2D, cfg: Dictionary, x: float) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = atlas.frame("res://assets/ui/game1.png", "res://assets/ui/game1.json", str(cfg["img"]))
	sprite.position = Vector2(x, -80.0)
	sprite.z_index = 10
	root.add_child(sprite)
	return {"sprite": sprite, "cfg": cfg, "taken": false, "phase": rng.randf_range(0.0, TAU)}


func _update_monsters(delta: float) -> void:
	for group in content_groups:
		var root: Node2D = group["root"]
		for monster in group["monsters"]:
			var sprite: AnimatedSprite2D = monster["sprite"]
			if monster["dead"]:
				sprite.position.y += 520.0 * delta
				continue
			if not monster["active"] and absf((root.position.y + sprite.position.y) - player.position.y) < 120.0 and grounded:
				monster["active"] = true
				monster["direction"] = 1.0 if sprite.global_position.x < player.position.x else -1.0
			if monster["active"]:
				sprite.position.x += float(monster["direction"]) * float(monster["cfg"]["speed"]) * 34.0 * delta
				if sprite.position.x < 45.0:
					monster["direction"] = 1.0
				elif sprite.position.x > VIEW_SIZE.x - 45.0:
					monster["direction"] = -1.0
				sprite.flip_h = float(monster["direction"]) > 0.0
			var global_pos := root.position + sprite.position
			if global_pos.distance_to(player.position) < 58.0:
				if rocket_time > 0.0 or (velocity.y > 120.0 and player.position.y < global_pos.y - 10.0):
					monster["dead"] = true
					velocity.y = -420.0
					grounded = false
					_add_score(10)
				else:
					_take_damage(false)


func _update_pickups() -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0
	for group in content_groups:
		var root: Node2D = group["root"]
		for pickup in group["pickups"]:
			if pickup["taken"]:
				continue
			var sprite: Sprite2D = pickup["sprite"]
			sprite.position.y = -80.0 + sin(elapsed * 3.0 + float(pickup["phase"])) * 7.0
			if (root.position + sprite.position).distance_to(player.position) < 52.0:
				pickup["taken"] = true
				sprite.visible = false
				_apply_pickup(pickup["cfg"])


func _apply_pickup(cfg: Dictionary) -> void:
	match int(cfg["type"]):
		3:
			time_left = minf(ROUND_TIME, time_left + float(cfg["value"]))
		4:
			if hp >= MAX_HP:
				_add_score(10)
			else:
				hp += int(cfg["value"])
		5:
			energy = mini(5, energy + int(cfg["value"]))
			if energy >= 5:
				energy = 0
				rocket_time = 5.0
	_add_score(10)
	_play_sound(2)


func _take_damage(fell: bool) -> void:
	if hurt_cooldown > 0.0 or rocket_time > 0.0 or state != GameState.PLAYING:
		return
	hp -= 1
	hurt_cooldown = 1.2
	_play_sound(4)
	if hp <= 0:
		_finish_game()
		return
	player.position = Vector2(320.0, 760.0) if fell else player.position + Vector2(0, -50)
	velocity = Vector2(rng.randf_range(-280.0, 280.0), -480.0)
	grounded = false


func _cleanup_and_spawn() -> void:
	for index in range(content_groups.size() - 1, -1, -1):
		var group: Dictionary = content_groups[index]
		var root: Node2D = group["root"]
		if root.position.y > VIEW_SIZE.y + 160.0:
			if not group.get("scored", false):
				_add_score(10)
			root.queue_free()
			content_groups.remove_at(index)
	while highest_group_y > -GROUP_GAP:
		highest_group_y -= GROUP_GAP
		_spawn_config_group(highest_group_y)


func _create_backgrounds() -> void:
	for child in background_layer.get_children():
		child.queue_free()
	background_sprites.clear()
	for index in range(3):
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/backgrounds/bg1.jpg" if index == 2 else "res://assets/backgrounds/bg2.jpg")
		sprite.centered = true
		sprite.position = Vector2(VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.5 - index * 1091.0)
		background_layer.add_child(sprite)
		background_sprites.append(sprite)


func _clear_content() -> void:
	for child in content_layer.get_children():
		child.queue_free()
	content_groups.clear()


func _add_score(value: int) -> void:
	score += value


func _finish_game() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.GAME_OVER
	velocity = Vector2.ZERO
	aiming = false
	result_label.text = "得分 %d" % score
	game_over_panel.visible = true
	_play_sound(5)


func _update_hud() -> void:
	score_label.text = "得分 %d" % score
	timer_label.text = "时间 %d" % ceili(time_left)
	hp_label.text = "生命 " + "♥ ".repeat(hp).strip_edges()
	energy_label.text = "能量 " + "■ ".repeat(energy) + "□ ".repeat(5 - energy)


func _update_aim_layer_draw() -> void:
	pass


func _play_sound(id: int) -> void:
	var player_node := AudioStreamPlayer.new()
	player_node.stream = load("res://assets/audio/%d.mp3" % id)
	player_node.finished.connect(player_node.queue_free)
	add_child(player_node)
	player_node.play()


func _make_label(text_value: String, font_size: int, color: Color, centered: bool) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 38)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = Color.WHITE
	normal.set_border_width_all(5)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _capture_smoke() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	await get_tree().process_frame
	await get_tree().process_frame
	var home_image := get_viewport().get_texture().get_image()
	if home_image != null:
		home_image.save_png("res://artifacts/home.png")
	start_game()
	await get_tree().process_frame
	await get_tree().process_frame
	var gameplay_image := get_viewport().get_texture().get_image()
	if gameplay_image != null:
		gameplay_image.save_png("res://artifacts/gameplay.png")
	get_tree().quit()
