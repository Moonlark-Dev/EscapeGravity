extends Node

const SelftestScript = preload("res://src/selftest.gd")
## Application shell: title screen, run lifecycle, pause, transitions.

var menu: Menu
var menu_layer: CanvasLayer
var hud: Hud
var run: Run
var fade_layer: CanvasLayer
var fade_rect: TextureRect
var paused := false
var _switching := false
var _needs_fade_in := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.has("--touch"):
		Store.touch_mode = true
		Store.touch_override = -1
	if args.has("--selftest"):
		var st = SelftestScript.new()
		add_child(st)
		st.run_tests()
		return
	for a in args:
		if a.begins_with("--shots="):
			_setup_menu()
			_run_shots(a.substr(8))
			return
	_setup_fade()
	_setup_menu()
	Audio.music("bgm_menu")
	show_menu(false)

func _setup_fade() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 80
	add_child(fade_layer)
	fade_rect = TextureRect.new()
	fade_rect.texture = Assets.ui("black")
	fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate = Color(1, 1, 1, 1)
	fade_layer.add_child(fade_rect)
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", 0.0, 0.5)
	_needs_fade_in = false

func _setup_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 40
	add_child(menu_layer)
	menu = Menu.new()
	menu.main = self
	menu_layer.add_child(menu)
	menu.visible = false

func _fade(to_alpha: float, time: float) -> void:
	var t := create_tween()
	t.tween_property(fade_rect, "modulate:a", to_alpha, time)
	await t.finished

func show_menu(with_fade: bool = true) -> void:
	if _switching:
		return
	_switching = true
	if with_fade:
		await _fade(1.0, 0.22)
	paused = false
	if run != null:
		run.queue_free()
		run = null
	if hud != null:
		hud.queue_free()
		hud = null
	menu.visible = true
	menu.build("title")
	Audio.music("bgm_menu")
	Audio.fade_music(-3.0, 0.2)
	await _fade(0.0, 0.3)
	_switching = false

func start_run() -> void:
	if _switching:
		return
	_switching = true
	await _fade(1.0, 0.22)
	paused = false
	if run != null:
		run.queue_free()
		run = null
	if hud != null:
		hud.queue_free()
		hud = null
	menu.visible = false
	_create_hud()
	run = Run.new()
	run.main = self
	run.hud = hud
	run.seed_value = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	hud.main = self
	add_child(run)
	move_child(run, 0)
	Audio.music("bgm_run")
	Audio.fade_music(-3.0, 0.4)
	await _fade(0.0, 0.35)
	_switching = false

func _create_hud() -> void:
	hud = Hud.new()
	hud.layer = 10
	hud.main = self
	add_child(hud)

func retry() -> void:
	start_run()

func quit_game() -> void:
	Store.save_data()
	get_tree().quit()

func toggle_pause() -> void:
	if run == null or run.state != Run.State.PLAYING:
		return
	if paused:
		resume_run()
		return
	paused = true
	run.paused = true
	Audio.loop_sfx("sfx_thrust", false)
	if hud != null:
		hud.visible = false
	menu.build("pause")
	menu.visible = true
	Audio.fade_music(-14.0, 0.15)

func resume_run() -> void:
	if run == null:
		return
	paused = false
	run.paused = false
	menu.visible = false
	if hud != null:
		hud.visible = true
	Audio.fade_music(-3.0, 0.2)

func rebuild_hud_touch() -> void:
	if run == null:
		return
	var old := hud
	_create_hud()
	run.hud = hud
	hud.main = self
	hud.bind(run)
	hud.set_info_hidden(run.player_hidden)
	hud.set_safe_mode(run.player_hidden)
	hud.visible = not paused
	hud.refresh()
	if old != null:
		old.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if run != null and run.state == Run.State.PLAYING:
			toggle_pause()
			get_viewport().set_input_as_handled()
		elif menu.visible:
			if menu.mode == "settings" or menu.mode == "howto":
				menu.build("title")
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart") and run != null and run.state == Run.State.DEAD:
		retry()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and menu.visible and not paused and menu.mode == "title":
		start_run()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		Store.fullscreen = not Store.fullscreen
		Store.apply()
		Store.save_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if OS.has_feature("mobile") and run != null and run.state == Run.State.PLAYING and not paused and run.run_time > 0.5:
			toggle_pause()
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if run != null and run.state == Run.State.PLAYING:
			toggle_pause()
		elif menu.visible and (menu.mode == "settings" or menu.mode == "howto"):
			menu.build("title")
		else:
			Store.save_data()


# ---------------------------------------------------------------- screenshots

func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _snap(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)

func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	menu.visible = true
	menu.build("title")
	await _wait_frames(8)
	await _snap(dir, "01_title")
	menu.build("howto")
	await _wait_frames(4)
	await _snap(dir, "02_howto")
	menu.build("settings")
	await _wait_frames(4)
	await _snap(dir, "03_settings")

	menu.visible = false
	_create_hud()
	run = Run.new()
	run.main = self
	run.hud = hud
	run.seed_value = 20261101
	hud.main = self
	add_child(run)
	await _wait_frames(6)

	run.ship.position = Vector2.ZERO
	run.ship.vel = Vector2.ZERO
	run.camera.position = Vector2.ZERO
	var e = run.current_enemy
	if e != null:
		e.position = Vector2(0, -580)
		e.fire_timer = 99.0
		e.in_view = true
		e.overheated = false
		e.reveal()
	# fly a few missiles around the player
	for i in range(3):
		var ang: float = -0.6 + i * 1.1
		var pos: Vector2 = Vector2.RIGHT.rotated(ang) * (260.0 + i * 45.0)
		var m = run.spawn_enemy_missile(e, pos, ang + PI)
		m.source = null
		m.seen = true
		m.locked = true
		m.lock_timer = 1.2
		m._age = 2.0
	# two suicide drones closing in, so the combat shot documents the new threat
	for i in range(2):
		var dp: Vector2 = run.ship.position + Vector2(-470.0 + 900.0 * float(i), -210.0 + 420.0 * float(i))
		run.spawn_drone(dp, (run.ship.position - dp).angle())
	if run.safe_zone != null:
		run.safe_zone.position = Vector2(-1250, 620)
	if run.shop_zone != null:
		run.shop_zone.position = Vector2(2100, -900)
	for i in range(18):
		run.scatter_matter_at(Vector2(randf_range(-500, 500), randf_range(-300, 400)), 1, 40.0)
	run.paused = true
	await _wait_frames(4)
	await _snap(dir, "04_battle")

	# pause menu
	paused = true
	if hud != null:
		hud.visible = false
	menu.build("pause")
	menu.visible = true
	await _wait_frames(4)
	await _snap(dir, "04b_pause")
	menu.visible = false
	paused = false
	if hud != null:
		hud.visible = true

	# threat arc + explosion
	if e != null:
		e.position = run.ship.position + Vector2(-3000, -260)
		e.in_view = false
	for m in run.missiles:
		m.position = run.ship.position + Vector2(340, 120) if m.locked else m.position
	Fx.explosion(run.fx_layer, run.ship.position + Vector2(240, -150), 0.9, false)
	await _wait_frames(2)
	await _snap(dir, "04c_threat")
	Fx.explosion(run.fx_layer, run.ship.position + Vector2(-260, 120), 1.4, true)
	await _wait_frames(2)
	await _snap(dir, "04d_explosion")

	# safe zone
	run.paused = false
	var z = run.make_zone("safe", run.ship.position)
	run.safe_zone = z
	for m in run.missiles.duplicate():
		m.remove()
	run.missiles.clear()
	run._zone_checks()
	# Let the expansion animation finish so the documentation shot shows the
	# full ring (the trigger radius is already at maximum on the first frame).
	await _wait_frames(50)
	await _snap(dir, "05_safezone")

	# shop
	run.player_hidden = false
	hud.set_info_hidden(false)
	if run.safe_zone != null:
		run.safe_zone.remove()
		run.safe_zone = null
	run.ship.position = Vector2(3000, 3000)
	run.camera.position = run.ship.position
	var sz = run.make_zone("shop", run.ship.position)
	run.shop_zone = sz
	run._zone_checks()
	run.state = Run.State.SHOP
	run.shop_open = true
	run.shop_inside = true
	run.shop_stock = run._roll_shop()
	run.tokens = 7
	hud.show_shop(run.shop_stock, run.tokens)
	await _wait_frames(6)
	await _snap(dir, "06_shop")

	# level up
	hud.hide_shop()
	run.state = Run.State.PLAYING
	run.begin_levelup()
	await _wait_frames(6)
	await _snap(dir, "07_levelup")

	# game over
	hud.hide_levelup()
	run.state = Run.State.PLAYING
	run.die("护盾击穿")
	await _wait_frames(8)
	await _snap(dir, "08_gameover")

	await _wait_frames(2)
	get_tree().quit()
