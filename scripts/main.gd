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
const START_PLATFORM_Y := 910.0
const GROUP_GAP := 195.0
const SHORT_PLATFORM_GAP := 160.0
const MAX_HP := 4
const ROUND_TIME := 180.0
const SAVE_PATH := "user://progress.cfg"
const ICE_SPEED := 210.0
const LINE21_MAX_UPWARD_SPEED := 820.0

enum GameState { HOME, PLAYING, GAME_OVER }

var db = ContentDatabaseClass.new()
var atlas = EgretAtlasClass.new()
var rng := RandomNumberGenerator.new()
var state := GameState.HOME

var world := Node2D.new()
var background_layer := Node2D.new()
var content_layer := Node2D.new()
var player := AnimatedSprite2D.new()
var shield_effect := AnimatedSprite2D.new()
var aim_layer = AimOverlayClass.new()
var hud := CanvasLayer.new()
var home := CanvasLayer.new()
var game_over_panel := CanvasLayer.new()
var music_player := AudioStreamPlayer.new()

var background_sprites: Array[Sprite2D] = []
var content_groups: Array[Dictionary] = []
var velocity := Vector2.ZERO
var grounded := true
var grounded_platform: Dictionary = {}
var aiming := false
var drag_origin := Vector2.ZERO
var drag_position := Vector2.ZERO
var hp := MAX_HP
var score := 0
var energy := 0
var time_left := ROUND_TIME
var hurt_cooldown := 0.0
var rocket_time := 0.0
var shield_time := 0.0
var highest_group_y := 900.0
var tier_slot := 0
var current_tier_score := -1
var safe_position := Vector2(320.0, 876.0)
var previous_group_was_double := false
var high_score := 0
var sound_enabled := true
var paused_by_player := false
var smoke_test_mode := false
var tier_notice_time := 0.0

var score_label: Label
var timer_label: Label
var hp_label: Label
var energy_label: Label
var result_label: Label
var hint_label: Label
var high_score_label: Label
var pause_overlay: CanvasLayer
var pause_button: Button
var sound_buttons: Array[Button] = []
var tier_notice_label: Label
var buff_label: Label


func _ready() -> void:
	smoke_test_mode = "--capture-smoke" in OS.get_cmdline_user_args()
	rng.randomize()
	_load_progress()
	db.load_all()
	_build_world()
	_build_home()
	_build_hud()
	_build_game_over()
	_build_pause_overlay()
	_build_audio()
	show_home()
	if smoke_test_mode:
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
	shield_effect.sprite_frames = atlas.movie_frames(
		"res://assets/animations/effects/hudun.png",
		"res://assets/animations/effects/hudun.json",
		"walk"
	)
	shield_effect.animation = "hudun"
	shield_effect.z_index = -1
	shield_effect.visible = false
	player.add_child(shield_effect)


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

	var title := _make_label("弹弹鸟 · Godot 重制", 34, Color("fff1a8"), true)
	title.position = Vector2(70, 650)
	title.size = Vector2(500, 100)
	title.add_theme_color_override("font_shadow_color", Color("6c2917"))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 7)
	home.add_child(title)

	var start_button := _make_button("开始挑战", Color("65c92f"))
	start_button.position = Vector2(130, 760)
	start_button.size = Vector2(380, 92)
	start_button.pressed.connect(start_game)
	home.add_child(start_button)

	var rules := _make_label("向下拖动 · 松手弹射 · 不断向上", 22, Color("fff8df"), true)
	rules.position = Vector2(80, 890)
	rules.size = Vector2(480, 48)
	home.add_child(rules)
	high_score_label = _make_label("最高分 %d" % high_score, 22, Color("fff1a8"), false)
	high_score_label.position = Vector2(24, 24)
	high_score_label.size = Vector2(260, 48)
	home.add_child(high_score_label)
	var home_sound := _make_icon_button("♪", "切换音效")
	home_sound.position = Vector2(556, 24)
	home_sound.pressed.connect(_toggle_sound)
	home.add_child(home_sound)
	sound_buttons.append(home_sound)


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
	tier_notice_label = _make_label("", 28, Color("ffe36d"), true)
	tier_notice_label.position = Vector2(120, 225)
	tier_notice_label.size = Vector2(400, 56)
	tier_notice_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	tier_notice_label.add_theme_constant_override("shadow_offset_x", 2)
	tier_notice_label.add_theme_constant_override("shadow_offset_y", 2)
	tier_notice_label.visible = false
	hud.add_child(tier_notice_label)
	buff_label = _make_label("", 20, Color("80efff"), true)
	buff_label.position = Vector2(200, 126)
	buff_label.size = Vector2(240, 38)
	buff_label.visible = false
	hud.add_child(buff_label)
	var hud_sound := _make_icon_button("♪", "切换音效")
	hud_sound.position = Vector2(278, 35)
	hud_sound.pressed.connect(_toggle_sound)
	hud.add_child(hud_sound)
	sound_buttons.append(hud_sound)
	pause_button = _make_icon_button("Ⅱ", "暂停")
	pause_button.position = Vector2(330, 35)
	pause_button.pressed.connect(_toggle_pause)
	hud.add_child(pause_button)
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
	result_label.position = Vector2(120, 430)
	result_label.size = Vector2(400, 110)
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
	_apply_sound_state()


func _build_pause_overlay() -> void:
	pause_overlay = CanvasLayer.new()
	pause_overlay.layer = 40
	add_child(pause_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.68)
	shade.position = Vector2.ZERO
	shade.size = VIEW_SIZE
	pause_overlay.add_child(shade)
	var label := _make_label("已暂停", 48, Color.WHITE, true)
	label.position = Vector2(120, 420)
	label.size = Vector2(400, 80)
	pause_overlay.add_child(label)
	var resume := _make_button("继续", Color("65c92f"))
	resume.position = Vector2(190, 530)
	resume.size = Vector2(260, 76)
	resume.pressed.connect(_toggle_pause)
	pause_overlay.add_child(resume)
	pause_overlay.visible = false


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
	shield_time = 0.0
	tier_notice_time = 0.0
	tier_slot = 0
	current_tier_score = 0
	previous_group_was_double = false
	velocity = Vector2.ZERO
	grounded = true
	grounded_platform = {}
	aiming = false
	paused_by_player = false
	pause_overlay.visible = false
	tier_notice_label.visible = false
	safe_position = Vector2(320.0, START_PLATFORM_Y - PLAYER_RADIUS)
	player.position = safe_position
	player.scale = Vector2.ONE
	shield_effect.visible = false
	shield_effect.stop()
	player.modulate = Color.WHITE
	player.play("walk1")
	hint_label.visible = true
	_create_backgrounds()
	_spawn_initial_content()
	_update_hud()


func _process(delta: float) -> void:
	if state != GameState.PLAYING or paused_by_player:
		return
	time_left = maxf(0.0, time_left - delta)
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	rocket_time = maxf(0.0, rocket_time - delta)
	shield_time = maxf(0.0, shield_time - delta)
	if shield_time <= 0.0 and shield_effect.visible:
		shield_effect.visible = false
		shield_effect.stop()
	tier_notice_time = maxf(0.0, tier_notice_time - delta)
	tier_notice_label.visible = tier_notice_time > 0.0
	if rocket_time > 0.0:
		player.modulate = Color("ffd95b")
	elif hurt_cooldown > 0.0 and int(hurt_cooldown * 12.0) % 2 == 0:
		player.modulate = Color(1.0, 1.0, 1.0, 0.35)
	else:
		player.modulate = Color.WHITE
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
	if grounded and not grounded_platform.is_empty() and int(grounded_platform.get("id", 0)) == 24:
		var ice_direction := float(grounded_platform.get("slide_direction", 1.0))
		velocity.x = move_toward(velocity.x, ice_direction * ICE_SPEED, 520.0 * delta)
		player.position.x += velocity.x * delta
	elif not grounded:
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
			var collision_bottom := top + float(platform["height"])
			if old_bottom <= collision_bottom and new_bottom >= top and player.position.x + 22.0 >= left and player.position.x - 22.0 <= right:
				if top < best_top:
					best_top = top
					best_platform = platform
					safe_position = Vector2(clampf(player.position.x, left + 32.0, right - 32.0), top - PLAYER_RADIUS)
	if best_top < INF:
		player.position.y = best_top - PLAYER_RADIUS
		velocity = Vector2.ZERO
		grounded = true
		grounded_platform = best_platform
		player.play("walk1")
		_play_landing_feedback()
		if float(best_platform.get("fall_delay", 0.0)) > 0.0 and float(best_platform.get("fall_timer", -1.0)) < 0.0:
			best_platform["fall_timer"] = float(best_platform["fall_delay"])


func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.PLAYING or paused_by_player:
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
	velocity = get_launch_velocity(drag)
	grounded = false
	grounded_platform = {}
	player.play("walk4" if power > 0.82 else "walk3")
	_play_sound(6)


func get_launch_velocity(drag: Vector2) -> Vector2:
	if drag.length() < 0.001:
		return Vector2.ZERO
	var limited_drag := drag.limit_length(MAX_DRAG)
	var power := clampf(limited_drag.length() / MAX_DRAG, 0.0, 1.0)
	var launch_velocity := -limited_drag.normalized() * lerpf(260.0, MAX_LAUNCH_SPEED, power)
	if int(grounded_platform.get("id", 0)) == 21:
		launch_velocity.y = maxf(launch_velocity.y, -LINE21_MAX_UPWARD_SPEED)
	return launch_velocity


func get_trajectory_points(drag: Vector2) -> Array[Vector2]:
	return get_trajectory_prediction(drag)["points"]


func get_trajectory_prediction(drag: Vector2) -> Dictionary:
	var points: Array[Vector2] = []
	var landing: Dictionary = {}
	var launch_velocity := get_launch_velocity(drag)
	if launch_velocity.length() < 1.0:
		return {"points": points, "landing": landing}
	var previous_point := player.position
	for index in range(1, 33):
		var time := float(index) * 0.055
		var point := player.position + launch_velocity * time + Vector2(0.0, GRAVITY * time * time * 0.5)
		points.append(point)
		if launch_velocity.y + GRAVITY * time > 0.0:
			landing = _predicted_landing(previous_point, point)
			if not landing.is_empty():
				points[points.size() - 1] = landing["position"]
				break
		if point.y > VIEW_SIZE.y or point.x < 0.0 or point.x > VIEW_SIZE.x:
			break
		previous_point = point
	return {"points": points, "landing": landing}


func _predicted_landing(previous_point: Vector2, point: Vector2) -> Dictionary:
	var best_ratio := INF
	var result: Dictionary = {}
	var old_bottom := previous_point.y + PLAYER_RADIUS
	var new_bottom := point.y + PLAYER_RADIUS
	if new_bottom <= old_bottom:
		return result
	for group in content_groups:
		var root: Node2D = group["root"]
		for platform in group["platforms"]:
			if platform.get("falling", false):
				continue
			var top := root.position.y + float(platform["local_y"])
			if old_bottom > top or new_bottom < top:
				continue
			var ratio := (top - old_bottom) / (new_bottom - old_bottom)
			var landing_x := lerpf(previous_point.x, point.x, ratio)
			var left := float(platform["x"])
			var right := left + float(platform["width"])
			if landing_x + 22.0 < left or landing_x - 22.0 > right:
				continue
			if ratio < best_ratio:
				best_ratio = ratio
				result = {"position": Vector2(landing_x, top - PLAYER_RADIUS), "platform": platform}
	return result


func _play_landing_feedback() -> void:
	player.scale = Vector2(1.12, 0.86)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(player, "scale", Vector2.ONE, 0.16)


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
	safe_position.y += amount
	_cleanup_and_spawn()


func _spawn_initial_content() -> void:
	var safe_platform := _spawn_safe_group(START_PLATFORM_Y)
	grounded_platform = safe_platform
	safe_position = Vector2(320.0, START_PLATFORM_Y - PLAYER_RADIUS)
	player.position = safe_position
	highest_group_y = START_PLATFORM_Y
	for index in range(8):
		highest_group_y = _spawn_config_group(highest_group_y)


func _spawn_safe_group(y: float) -> Dictionary:
	var root := Node2D.new()
	root.position.y = y
	content_layer.add_child(root)
	var platform := _create_platform(root, db.platforms[10], 0.0, 0.0, false)
	content_groups.append({"root": root, "platforms": [platform], "monsters": [], "pickups": [], "scored": true})
	return platform


func _spawn_config_group(lower_group_y: float) -> float:
	var tier: Dictionary = db.get_tier(score)
	var tier_score := int(tier["score"])
	if tier_score != current_tier_score:
		current_tier_score = tier_score
		tier_slot = 0
	var group_id: int = db.pick_group_id(score, tier_slot, rng)
	for retry in range(6):
		if not previous_group_was_double or not _group_has_two_platforms(group_id):
			break
		group_id = db.pick_group_id(score, tier_slot, rng)
	if previous_group_was_double and _group_has_two_platforms(group_id):
		var single_platform_groups: Array[int] = []
		for slot in tier["group_slots"]:
			for candidate in slot:
				if not _group_has_two_platforms(int(candidate)):
					single_platform_groups.append(int(candidate))
		if not single_platform_groups.is_empty():
			group_id = single_platform_groups[rng.randi_range(0, single_platform_groups.size() - 1)]
	var tool_id: int = db.pick_tool_id(score, tier_slot, rng)
	tier_slot += 1
	var cfg: Dictionary = db.groups[group_id]
	previous_group_was_double = int(cfg["shuzhi2"]) > 0
	var target_width := float(db.platforms[int(cfg["shuzhi1"])]["lang"])
	if int(cfg["shuzhi2"]) > 0:
		target_width += float(db.platforms[int(cfg["shuzhi2"])]["lang"])
	var group_gap := SHORT_PLATFORM_GAP if target_width < VIEW_SIZE.x else GROUP_GAP
	var root := Node2D.new()
	root.position.y = lower_group_y - group_gap
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
			monsters.append(_create_monster(root, db.monsters[monster_id], float(cfg[x_field]), platforms))
	if tool_id > 0 and db.tools.has(tool_id):
		pickups.append(_create_pickup(root, db.tools[tool_id], float([200, 260, 320, 380, 440][rng.randi_range(0, 4)]), platforms))
	content_groups.append({"root": root, "platforms": platforms, "monsters": monsters, "pickups": pickups, "scored": false, "id": group_id, "gap": group_gap})
	return root.position.y


func _create_platform(root: Node2D, cfg: Dictionary, start_x: float, local_y: float, mirrored: bool) -> Dictionary:
	var profile: Dictionary = db.get_platform_profile(int(cfg["id"]))
	var inset := float(profile.get("edge_inset", 0.0))
	var visual_width := float(cfg["lang"])
	var x := start_x
	if mirrored:
		x = VIEW_SIZE.x - start_x - visual_width
	var sprite := Sprite2D.new()
	sprite.texture = atlas.frame("res://assets/ui/game1.png", "res://assets/ui/game1.json", str(cfg["img"]))
	sprite.centered = false
	sprite.position = Vector2(x, local_y - float(profile["surface_y"]))
	sprite.flip_h = mirrored
	root.add_child(sprite)
	return {
		"id": int(cfg["id"]),
		"sprite": sprite,
		"x": x + inset,
		"width": maxf(1.0, visual_width - inset * 2.0),
		"visual_x": x,
		"local_y": local_y,
		"surface_y": float(profile["surface_y"]),
		"height": float(profile["collision_height"]),
		"slide_direction": -1.0 if mirrored else 1.0,
		"fall_delay": float(cfg["time"]),
		"fall_timer": -1.0,
		"fall_speed": 0.0,
		"falling": false
	}


func _group_has_two_platforms(group_id: int) -> bool:
	return db.groups.has(group_id) and int(db.groups[group_id]["shuzhi2"]) > 0


func _update_platforms(delta: float) -> void:
	for group in content_groups:
		for platform in group["platforms"]:
			var timer := float(platform.get("fall_timer", -1.0))
			if timer >= 0.0 and not platform.get("falling", false):
				timer -= delta
				platform["fall_timer"] = timer
				if timer <= 0.0:
					platform["falling"] = true
					if not grounded_platform.is_empty() and grounded_platform.get("sprite") == platform["sprite"]:
						grounded = false
						grounded_platform = {}
						velocity = Vector2(0.0, maxf(90.0, float(platform["fall_speed"])))
						player.play("walk3")
			if platform.get("falling", false):
				platform["fall_speed"] = float(platform["fall_speed"]) + GRAVITY * delta * 0.65
				platform["local_y"] = float(platform["local_y"]) + float(platform["fall_speed"]) * delta
				var sprite: Sprite2D = platform["sprite"]
				sprite.position.y = float(platform["local_y"]) - float(platform["surface_y"])


func _create_monster(root: Node2D, cfg: Dictionary, x: float, platforms: Array) -> Dictionary:
	var name := str(cfg["img"])
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = atlas.movie_frames(
		"res://assets/animations/enemies/%s.png" % name,
		"res://assets/animations/enemies/%s.json" % name,
		"walk"
	)
	var anchor_platform := _platform_nearest_x(platforms, x)
	var frame_texture := sprite.sprite_frames.get_frame_texture("walk", 0)
	var sprite_height: float = float(frame_texture.get_height()) if frame_texture != null else 80.0
	var surface_y := float(anchor_platform.get("local_y", 0.0))
	var patrol_left := float(anchor_platform.get("x", 40.0))
	var patrol_right := patrol_left + float(anchor_platform.get("width", VIEW_SIZE.x - 80.0))
	x = clampf(x, patrol_left + 20.0, patrol_right - 20.0)
	sprite.play("walk")
	sprite.position = Vector2(x, surface_y - float(cfg["sky"]) - sprite_height * 0.5)
	sprite.z_index = 8
	root.add_child(sprite)
	var direction := 1.0 if x <= 320.0 else -1.0
	sprite.flip_h = direction > 0.0
	return {"sprite": sprite, "cfg": cfg, "direction": direction, "active": int(cfg["movetype"]) == 1, "dead": false, "patrol_left": patrol_left, "patrol_right": patrol_right, "surface_y": surface_y, "sprite_height": sprite_height, "anchor_platform": anchor_platform}


func _create_pickup(root: Node2D, cfg: Dictionary, x: float, platforms: Array) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = atlas.frame("res://assets/ui/game1.png", "res://assets/ui/game1.json", str(cfg["img"]))
	var anchor_platform := _platform_nearest_x(platforms, x)
	var left := float(anchor_platform.get("x", 0.0))
	var right := left + float(anchor_platform.get("width", VIEW_SIZE.x))
	x = clampf(x, left + 20.0, right - 20.0)
	var surface_y := float(anchor_platform.get("local_y", 0.0))
	var sprite_height: float = float(sprite.texture.get_height()) if sprite.texture != null else 40.0
	var base_y: float = surface_y - 30.0 - sprite_height * 0.5
	sprite.position = Vector2(x, base_y)
	sprite.z_index = 10
	root.add_child(sprite)
	return {"sprite": sprite, "cfg": cfg, "taken": false, "phase": rng.randf_range(0.0, TAU), "base_y": base_y, "surface_y": surface_y, "sprite_height": sprite_height, "surface_offset": -30.0 - sprite_height * 0.5, "anchor_platform": anchor_platform}


func _platform_nearest_x(platforms: Array, x: float) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for platform in platforms:
		var left := float(platform["x"])
		var right := left + float(platform["width"])
		if x >= left and x <= right:
			return platform
		var distance := absf(x - (left + right) * 0.5)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = platform
	return nearest


func _update_monsters(delta: float) -> void:
	for group in content_groups:
		var root: Node2D = group["root"]
		for monster in group["monsters"]:
			var sprite: AnimatedSprite2D = monster["sprite"]
			if monster["dead"]:
				sprite.position.y += 520.0 * delta
				continue
			var anchor_platform: Dictionary = monster["anchor_platform"]
			monster["surface_y"] = float(anchor_platform["local_y"])
			sprite.position.y = float(monster["surface_y"]) - float(monster["cfg"]["sky"]) - float(monster["sprite_height"]) * 0.5
			if not monster["active"] and absf((root.position.y + sprite.position.y) - player.position.y) < 120.0 and grounded:
				monster["active"] = true
				monster["direction"] = 1.0 if sprite.global_position.x < player.position.x else -1.0
			if monster["active"]:
				sprite.position.x += float(monster["direction"]) * float(monster["cfg"]["speed"]) * 34.0 * delta
				if sprite.position.x < float(monster["patrol_left"]) + 20.0:
					monster["direction"] = 1.0
				elif sprite.position.x > float(monster["patrol_right"]) - 20.0:
					monster["direction"] = -1.0
				sprite.flip_h = float(monster["direction"]) > 0.0
			var monster_rect := _sprite_world_rect(sprite, root.position)
			if _circle_intersects_rect(player.position, PLAYER_RADIUS * 0.72, monster_rect):
				if rocket_time > 0.0 or (velocity.y > 120.0 and player.position.y + PLAYER_RADIUS * 0.5 < monster_rect.position.y + 8.0):
					monster["dead"] = true
					velocity.y = -420.0
					grounded = false
					grounded_platform = {}
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
			var anchor_platform: Dictionary = pickup["anchor_platform"]
			pickup["surface_y"] = float(anchor_platform["local_y"])
			pickup["base_y"] = float(pickup["surface_y"]) + float(pickup["surface_offset"])
			sprite.position.y = float(pickup["base_y"]) + sin(elapsed * 3.0 + float(pickup["phase"])) * 7.0
			if _circle_intersects_rect(player.position, PLAYER_RADIUS * 0.72, _sprite_world_rect(sprite, root.position)):
				pickup["taken"] = true
				sprite.visible = false
				_apply_pickup(pickup["cfg"])


func _apply_pickup(cfg: Dictionary) -> void:
	match int(cfg["type"]):
		1:
			_activate_shield(float(cfg["value"]) / 1000.0)
		2:
			rocket_time = maxf(rocket_time, float(cfg["value"]) / 1000.0)
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
	if hurt_cooldown > 0.0 or state != GameState.PLAYING:
		return
	if not fell and (rocket_time > 0.0 or shield_time > 0.0):
		return
	hp -= 1
	hurt_cooldown = 1.2
	_play_sound(4)
	if hp <= 0:
		_finish_game()
		return
	if fell:
		var respawn := _find_respawn_target()
		player.position = respawn["position"]
		velocity = Vector2.ZERO
		grounded = true
		grounded_platform = respawn["platform"]
		player.play("walk1")
	else:
		player.position += Vector2(0, -50)
		velocity = Vector2(rng.randf_range(-280.0, 280.0), -480.0)
		grounded = false
		grounded_platform = {}


func _find_respawn_target() -> Dictionary:
	var best_platform: Dictionary = {}
	var best_position := safe_position
	var best_distance := INF
	for group in content_groups:
		var root: Node2D = group["root"]
		for platform in group["platforms"]:
			if platform.get("falling", false):
				continue
			var top := root.position.y + float(platform["local_y"])
			if top < CAMERA_LINE + 70.0 or top > VIEW_SIZE.y - 80.0:
				continue
			var distance := absf(top - 790.0)
			if distance < best_distance:
				best_distance = distance
				best_platform = platform
				var left := float(platform["x"])
				var right := left + float(platform["width"])
				best_position = Vector2(clampf(player.position.x, left + 32.0, right - 32.0), top - PLAYER_RADIUS)
	return {"position": best_position, "platform": best_platform}


func _sprite_world_rect(sprite: Node2D, root_position: Vector2) -> Rect2:
	var texture: Texture2D
	if sprite is AnimatedSprite2D:
		var animated := sprite as AnimatedSprite2D
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
	elif sprite is Sprite2D:
		texture = (sprite as Sprite2D).texture
	if texture == null:
		return Rect2(root_position + sprite.position - Vector2(20, 20), Vector2(40, 40))
	var texture_size := texture.get_size() * sprite.scale.abs()
	return Rect2(root_position + sprite.position - texture_size * 0.5, texture_size)


func _circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(
		clampf(center.x, rect.position.x, rect.end.x),
		clampf(center.y, rect.position.y, rect.end.y)
	)
	return center.distance_squared_to(nearest) <= radius * radius


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
		highest_group_y = _spawn_config_group(highest_group_y)


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
	for side in range(2):
		var wall := Sprite2D.new()
		wall.texture = load("res://assets/backgrounds/bgl%d.png" % (side + 1))
		wall.centered = false
		wall.position = Vector2(0.0 if side == 0 else VIEW_SIZE.x - wall.texture.get_width(), 0.0)
		wall.z_index = 4
		background_layer.add_child(wall)


func _clear_content() -> void:
	for child in content_layer.get_children():
		child.queue_free()
	content_groups.clear()


func _add_score(value: int) -> void:
	var previous_tier := int(db.get_tier(score)["score"])
	score += value
	var next_tier := int(db.get_tier(score)["score"])
	if next_tier > previous_tier:
		tier_notice_label.text = "难度提升 · %d 分段" % next_tier
		tier_notice_time = 1.8
		tier_notice_label.visible = true


func _finish_game() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.GAME_OVER
	velocity = Vector2.ZERO
	aiming = false
	if score > high_score:
		high_score = score
		high_score_label.text = "最高分 %d" % high_score
		_save_progress()
	result_label.text = "得分 %d\n最高分 %d" % [score, high_score]
	game_over_panel.visible = true
	_play_sound(5)


func _update_hud() -> void:
	score_label.text = "得分 %d" % score
	timer_label.text = "时间 %d" % ceili(time_left)
	hp_label.text = "生命 " + "♥ ".repeat(hp).strip_edges()
	energy_label.text = "能量 " + "■ ".repeat(energy) + "□ ".repeat(5 - energy)
	if shield_time > 0.0:
		buff_label.text = "护盾 %.1f 秒" % shield_time
		buff_label.visible = true
	elif rocket_time > 0.0:
		buff_label.text = "火箭 %.1f 秒" % rocket_time
		buff_label.visible = true
	else:
		buff_label.visible = false


func _activate_shield(duration: float) -> void:
	shield_time = maxf(shield_time, duration)
	shield_effect.visible = true
	shield_effect.play("hudun")


func _update_aim_layer_draw() -> void:
	pass


func _play_sound(id: int) -> void:
	if not sound_enabled:
		return
	var player_node := AudioStreamPlayer.new()
	player_node.stream = load("res://assets/audio/%d.mp3" % id)
	player_node.finished.connect(player_node.queue_free)
	add_child(player_node)
	player_node.play()


func _make_icon_button(text_value: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 24)
	return button


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	_apply_sound_state()
	_save_progress()


func _apply_sound_state() -> void:
	for button in sound_buttons:
		button.modulate = Color.WHITE if sound_enabled else Color(1.0, 1.0, 1.0, 0.4)
	if sound_enabled:
		if not music_player.playing and music_player.stream != null:
			music_player.play()
	else:
		music_player.stop()


func _toggle_pause() -> void:
	if state != GameState.PLAYING:
		return
	paused_by_player = not paused_by_player
	pause_overlay.visible = paused_by_player
	if pause_button != null:
		pause_button.text = "▶" if paused_by_player else "Ⅱ"


func _notification(what: int) -> void:
	if not smoke_test_mode and what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == GameState.PLAYING and not paused_by_player:
		_toggle_pause()


func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		high_score = int(config.get_value("progress", "high_score", 0))
		sound_enabled = bool(config.get_value("settings", "sound_enabled", true))


func _save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "high_score", high_score)
	config.set_value("settings", "sound_enabled", sound_enabled)
	config.save(SAVE_PATH)


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
	assert(db.platform_profiles.size() == db.platforms.size(), "Every platform needs a tuning profile")
	await get_tree().process_frame
	await get_tree().process_frame
	var home_image := get_viewport().get_texture().get_image()
	if home_image != null:
		home_image.save_png("res://artifacts/home.png")
	start_game()
	assert(content_groups.size() >= 9, "Expected initial content groups")
	assert(shield_effect.sprite_frames.has_animation("hudun") and shield_effect.sprite_frames.get_frame_count("hudun") == 5, "Shield effect must load all five animation frames")
	var shield_available := false
	for slot in db.get_tier(300)["tool_slots"]:
		if 1 in slot:
			shield_available = true
	assert(shield_available, "Shield must enter the drop pool from the 300 score tier")
	var trajectory := get_trajectory_points(Vector2(80.0, 130.0))
	assert(trajectory.size() >= 3, "Aiming must provide a usable trajectory preview")
	assert((trajectory[2].y - trajectory[1].y) > (trajectory[1].y - trajectory[0].y), "Trajectory preview must include gravity")
	var landing_prediction := get_trajectory_prediction(Vector2(30.0, 135.0))
	assert(not landing_prediction["landing"].is_empty(), "Reachable launch arcs must identify their landing platform")
	var original_grounded_platform := grounded_platform
	grounded_platform = {"id": 21}
	var line21_launch := get_launch_velocity(Vector2(0.0, MAX_DRAG))
	var line21_apex := line21_launch.y * line21_launch.y / (2.0 * GRAVITY)
	assert(is_equal_approx(line21_launch.y, -LINE21_MAX_UPWARD_SPEED), "Line21 must cap its upward launch speed")
	assert(line21_apex > GROUP_GAP and line21_apex < SHORT_PLATFORM_GAP * 2.0, "Line21 must reach one tier without skipping two")
	grounded_platform = original_grounded_platform
	var last_was_double := false
	for group in content_groups:
		var is_double: bool = group["platforms"].size() > 1
		assert(not (last_was_double and is_double), "Generated content cannot contain consecutive double platforms")
		last_was_double = is_double
		if group.has("gap"):
			var visual_width := 0.0
			for platform in group["platforms"]:
				visual_width += float(db.platforms[int(platform["id"])]["lang"])
			if visual_width < VIEW_SIZE.x:
				assert(float(group["gap"]) == SHORT_PLATFORM_GAP, "Short target platforms need the assisted vertical gap")
		for monster in group["monsters"]:
			var monster_sprite: AnimatedSprite2D = monster["sprite"]
			var monster_feet := monster_sprite.position.y + float(monster["sprite_height"]) * 0.5 + float(monster["cfg"]["sky"])
			assert(is_equal_approx(monster_feet, float(monster["surface_y"])), "Monster feet must follow the platform surface")
		for pickup in group["pickups"]:
			var pickup_bottom := float(pickup["base_y"]) + float(pickup["sprite_height"]) * 0.5
			assert(is_equal_approx(pickup_bottom, float(pickup["surface_y"]) - 30.0), "Pickup hover height must follow the platform surface")
	var anchor_tested := false
	for group in content_groups:
		if not group["monsters"].is_empty():
			var test_monster: Dictionary = group["monsters"][0]
			var test_anchor: Dictionary = test_monster["anchor_platform"]
			var original_surface := float(test_anchor["local_y"])
			var original_monster_y: float = test_monster["sprite"].position.y
			test_anchor["local_y"] = original_surface + 12.0
			_update_monsters(0.0)
			assert(is_equal_approx(test_monster["sprite"].position.y, original_monster_y + 12.0), "Monsters must follow moving platforms")
			test_anchor["local_y"] = original_surface
			_update_monsters(0.0)
			anchor_tested = true
			break
	assert(anchor_tested, "Smoke content must include an anchored monster")
	var pickup_anchor_tested := false
	for group in content_groups:
		if not group["pickups"].is_empty():
			var test_pickup: Dictionary = group["pickups"][0]
			var pickup_anchor: Dictionary = test_pickup["anchor_platform"]
			var pickup_surface := float(pickup_anchor["local_y"])
			var original_base := float(test_pickup["base_y"])
			pickup_anchor["local_y"] = pickup_surface + 12.0
			_update_pickups()
			assert(is_equal_approx(float(test_pickup["base_y"]), original_base + 12.0), "Pickups must follow moving platforms")
			pickup_anchor["local_y"] = pickup_surface
			_update_pickups()
			pickup_anchor_tested = true
			break
	assert(pickup_anchor_tested, "Smoke content must include an anchored pickup")
	await get_tree().process_frame
	await get_tree().process_frame
	var gameplay_image := get_viewport().get_texture().get_image()
	if gameplay_image != null:
		gameplay_image.save_png("res://artifacts/gameplay.png")
	_begin_aim(Vector2(320.0, 450.0))
	drag_position = Vector2(350.0, 585.0)
	_update_launch_preview()
	aim_layer.queue_redraw()
	await get_tree().process_frame
	var aim_image := get_viewport().get_texture().get_image()
	if aim_image != null:
		aim_image.save_png("res://artifacts/aim_preview.png")
	_release_aim()
	assert(not grounded and velocity.y < 0.0, "Drag release must launch the player upward")
	for frame in range(20):
		_process(1.0 / 60.0)
		await get_tree().process_frame
	var action_image := get_viewport().get_texture().get_image()
	if action_image != null:
		action_image.save_png("res://artifacts/gameplay_action.png")
	time_left = 0.0
	_process(1.0 / 60.0)
	assert(state == GameState.GAME_OVER, "Timer expiry must end the round")
	await get_tree().process_frame
	var game_over_image := get_viewport().get_texture().get_image()
	if game_over_image != null:
		game_over_image.save_png("res://artifacts/game_over.png")
	start_game()
	assert(state == GameState.PLAYING and hp == MAX_HP and score == 0, "Restart must reset the round")
	assert(bool(content_groups[0]["scored"]), "The starting safety platform must not award progress score")
	_scroll_world(240.0)
	assert(safe_position.y > START_PLATFORM_Y - PLAYER_RADIUS, "World scrolling must move the active safe position")
	start_game()
	assert(is_equal_approx(player.position.y, START_PLATFORM_Y - PLAYER_RADIUS), "Restart must restore the initial spawn height")
	assert(not grounded_platform.is_empty() and int(grounded_platform["id"]) == 10, "Restart must bind the player to the safety platform")
	score = 90
	_add_score(10)
	assert(tier_notice_time > 0.0 and tier_notice_label.visible, "Crossing a score tier must show progression feedback")
	start_game()
	var pause_time := time_left
	_toggle_pause()
	_process(1.0)
	assert(time_left == pause_time, "Pausing must freeze the round timer")
	_toggle_pause()
	var hp_before_shield := hp
	_activate_shield(5.0)
	_take_damage(false)
	assert(hp == hp_before_shield and shield_effect.visible, "An active shield must block monster damage and show its effect")
	await get_tree().process_frame
	await get_tree().process_frame
	var shield_image := get_viewport().get_texture().get_image()
	if shield_image != null:
		shield_image.save_png("res://artifacts/shield.png")
	shield_time = 0.0
	shield_effect.visible = false
	shield_effect.stop()
	var ice_start_x := player.position.x
	grounded_platform = {"id": 24, "slide_direction": 1.0}
	_update_player(0.2)
	assert(player.position.x > ice_start_x, "Ice platforms must slide the grounded player")
	player.position.y = VIEW_SIZE.y + 100.0
	_update_player(1.0 / 60.0)
	assert(hp == MAX_HP - 1 and grounded, "Falling must cost one life and respawn on a safe platform")
	assert(not grounded_platform.is_empty(), "Respawn must select a live platform")
	print("SMOKE PASS: restart stability, scoring tiers, landing prediction, moving anchors and core game flow")
	get_tree().quit()
