class_name Menu
extends Control
## Title screen, pause menu, settings and the how-to-play panel.

var main
var mode := "title"
var _settings_back := "title"
var _content: Control
var _bg: TextureRect
var _particles: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build("title")

func build(new_mode: String) -> void:
	mode = new_mode
	for c in get_children():
		c.queue_free()
	_particles.clear()
	var show_bg: bool = mode == "title" or (mode != "pause" and _settings_back == "title")
	if show_bg:
		_bg = TextureRect.new()
		_bg.texture = Assets.world("title_bg")
		_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
	var tint := TextureRect.new()
	tint.texture = Assets.ui("black")
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.modulate = Color(1, 1, 1, 0.35 if mode == "title" else 0.72)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	var vig := TextureRect.new()
	vig.texture = Assets.ui("vignette")
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	match mode:
		"title":
			_build_title()
		"pause":
			_build_pause()
		"settings":
			_build_settings()
		"howto":
			_build_howto()

func _label(text: String, size: int, color: Color, outline: int = 0) -> Label:
	return Assets.label(text, size, color, outline)

func _button(text: String, x: float, y: float, w: float, h: float, cb: Callable) -> Button:
	var b := Assets.button(text, 20)
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(cb)
	_content.add_child(b)
	return b

func _button_centered(text: String, y: float, w: float, h: float, cb: Callable) -> Button:
	# Anchored to the true screen centre, not to 1280 px. With the "expand"
	# stretch mode a 20:9 phone exposes a wider logical canvas, which used to
	# leave the title buttons visibly left of centre.
	var b := Assets.button(text, 20)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 0.5
	b.anchor_bottom = 0.5
	b.offset_left = -w * 0.5
	b.offset_right = w * 0.5
	b.offset_top = y - EG.SCREEN.y * 0.5
	b.offset_bottom = y - EG.SCREEN.y * 0.5 + h
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(cb)
	_content.add_child(b)
	return b

func _center_title(text: String, y: float, size: int, color: Color) -> Label:
	var l := _label(text, size, color, 4)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = y
	l.offset_bottom = y + size + 20
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(l)
	return l

func _build_title() -> void:
	var logo := TextureRect.new()
	logo.texture = Assets.ui("title_logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.offset_left = -560
	logo.offset_right = 560
	logo.offset_top = 54
	logo.offset_bottom = 374
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(logo)
	var sub := _center_title("无枪可开 · 只有引力 · 让导弹替你击穿炮塔", 384, 18, EG.C_DIM)
	sub.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	var start := _button_centered("开始游戏", 430, 300, 58, func(): if main != null: main.start_run())
	start.add_theme_color_override("font_color", EG.C_CYAN)
	_button_centered("设置", 500, 300, 50, func(): _open_settings("title"))
	_button_centered("玩法说明", 560, 300, 50, func(): _open_howto("title"))
	_button_centered("退出游戏", 620, 300, 50, func(): if main != null: main.quit_game())
	var best := _label("最深深度  %d      累计击杀  %d      生存时长  %s" % [
		Store.best_depth, Store.total_kills, _fmt_time(Store.playtime)], 14, EG.C_DIM)
	best.position = Vector2(30, 660)
	best.size = Vector2(700, 30)
	_content.add_child(best)
	var ver := _label("v1.0.4", 13, EG.C_DIM)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -140
	ver.offset_top = -44
	ver.offset_right = -24
	ver.offset_bottom = -22
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_content.add_child(ver)
	var hint := _label("Enter / 空格 开始", 13, Color(0.55, 0.7, 0.85, 0.7))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -200
	hint.offset_right = 200
	hint.offset_top = -34
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.visible = not Store.touch_mode
	_content.add_child(hint)

func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

func _build_pause() -> void:
	var panel := _center_panel(500, 380)
	_panel_title(panel, "引 力 暂 停", 26, 30, EG.C_CYAN)
	var y := 100.0
	for spec in [["继续游戏", "resume"], ["设置", "settings"], ["返回主菜单", "menu"]]:
		var b := Assets.button(spec[0], 20)
		b.position = Vector2(130, y)
		b.size = Vector2(240, 52)
		b.custom_minimum_size = Vector2(240, 52)
		var act: String = spec[1]
		b.pressed.connect(func(): _pause_action(act))
		panel.add_child(b)
		y += 64
	var tip := _label("Esc 继续", 13, EG.C_DIM)
	tip.position = Vector2(130, 322)
	tip.size = Vector2(240, 20)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(tip)

func _pause_action(act: String) -> void:
	if act == "resume":
		if main != null:
			main.resume_run()
	elif act == "settings":
		_open_settings("pause")
	else:
		if main != null:
			main.show_menu()

func _panel_title(parent: Control, text: String, y: float, size: int, color: Color) -> Label:
	var l := _label(text, size, color, 4)
	l.position = Vector2(0, y)
	l.size = Vector2(parent.size.x, size + 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _panel_rect(w: float, h: float, x: float, y: float) -> Control:
	var p := Control.new()
	p.position = Vector2(x, y)
	p.size = Vector2(w, h)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(p)
	var bg := Assets.panel("panel_9p")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(bg)
	return p

func _center_panel(w: float, h: float) -> Control:
	var p := Control.new()
	p.size = Vector2(w, h)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -w * 0.5
	p.offset_top = -h * 0.5
	p.offset_right = w * 0.5
	p.offset_bottom = h * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(p)
	var bg := Assets.panel("panel_9p")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(bg)
	return p

func _build_settings() -> void:
	var p := _center_panel(760, 600)
	_panel_title(p, "设置", 22, 34, EG.C_CYAN)
	var row_y := 96.0
	_volume_row(p, "主音量", "master", row_y)
	_volume_row(p, "音乐", "music", row_y + 78)
	_volume_row(p, "音效", "sfx", row_y + 156)
	_toggle_row(p, "屏幕震动", "screenshake", row_y + 236)
	if not OS.has_feature("mobile"):
		_toggle_row(p, "全屏", "fullscreen", row_y + 300)
	_toggle_row(p, "触屏操作界面", "touch", (row_y + 364) if not OS.has_feature("mobile") else (row_y + 300))
	var back := Assets.button("返回", 18)
	back.position = Vector2(280, 520)
	back.size = Vector2(200, 48)
	back.custom_minimum_size = Vector2(200, 48)
	var prev := _settings_back
	back.pressed.connect(func(): build(prev))
	p.add_child(back)

func _volume_row(parent: Control, title: String, key: String, y: float) -> void:
	var l := _label(title, 18, EG.C_TEXT)
	l.position = Vector2(48, y + 6)
	l.size = Vector2(180, 30)
	parent.add_child(l)
	var val_label := _label("", 15, EG.C_DIM)
	val_label.position = Vector2(560, y + 8)
	val_label.size = Vector2(100, 24)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(val_label)
	var bar := Assets.progress_bar("bar_fill_exp", "bar_bg_9p")
	bar.nine_patch_stretch = true
	bar.texture_progress = Assets.ui("bar_fill_shield")
	bar.position = Vector2(210, y + 8)
	bar.size = Vector2(320, 18)
	bar.max_value = 100
	parent.add_child(bar)
	var minus := Assets.button("-", 20)
	minus.position = Vector2(160, y)
	minus.size = Vector2(44, 36)
	minus.custom_minimum_size = Vector2(44, 36)
	parent.add_child(minus)
	var plus := Assets.button("+", 20)
	plus.position = Vector2(534, y)
	plus.size = Vector2(44, 36)
	plus.custom_minimum_size = Vector2(44, 36)
	parent.add_child(plus)
	var upd := func():
		var v: float = float(Store.get_opt(key))
		bar.value = v * 100.0
		val_label.text = "%d%%" % roundi(v * 100.0)
	upd.call()
	minus.pressed.connect(func():
		Store.set_opt(key, clampf(float(Store.get_opt(key)) - 0.1, 0.0, 1.0))
		Store.save_data()
		Store.apply()
		upd.call())
	plus.pressed.connect(func():
		Store.set_opt(key, clampf(float(Store.get_opt(key)) + 0.1, 0.0, 1.0))
		Store.save_data()
		Store.apply()
		upd.call())

func _toggle_row(parent: Control, title: String, key: String, y: float) -> void:
	var l := _label(title, 18, EG.C_TEXT)
	l.position = Vector2(48, y + 6)
	l.size = Vector2(300, 30)
	parent.add_child(l)
	var b := Assets.button("", 16)
	b.position = Vector2(360, y)
	b.size = Vector2(130, 40)
	b.custom_minimum_size = Vector2(130, 40)
	parent.add_child(b)
	var upd := func():
		var on := bool(Store.get_opt(key))
		b.text = "开启" if on else "关闭"
		b.add_theme_color_override("font_color", EG.C_MINT if on else EG.C_DIM)
	upd.call()
	b.pressed.connect(func():
		Store.set_opt(key, not bool(Store.get_opt(key)))
		Store.save_data()
		Store.apply()
		upd.call()
		if key == "touch":
			if main != null:
				main.rebuild_hud_touch()
	)

func _build_howto() -> void:
	var p := _center_panel(1080, 620)
	_panel_title(p, "玩法说明", 20, 34, EG.C_CYAN)
	var left_x := 48.0
	var top := 82.0
	var sections := [
		["没有武器", "你不能开火。唯一能伤害攻击者的东西，\n是它自己发射的追踪导弹。让导弹撞上它的外壳。", EG.C_AMBER],
		["导弹的规律", "导弹速度与你的基础速度相同（150），\n转向半径约 286 px。锁定你 5 秒后脱锁，\n之后只会直线飞行，但仍会被天体引力弯折。", EG.C_TEXT],
		["怎么诱导", "贴着攻击者绕圈，让它的转弯弧线切进外壳；\n或者在最后一刻用脉冲把导弹沿切线甩进外壳。\n被击中的攻击者会过载停火 2.5 秒。", EG.C_CYAN],
	]
	var y := top
	for sec in sections:
		var h := _label(sec[0], 20, sec[2])
		h.position = Vector2(left_x, y)
		h.size = Vector2(560, 26)
		p.add_child(h)
		var b := _label(sec[1], 14, EG.C_DIM)
		b.position = Vector2(left_x, y + 30)
		b.size = Vector2(560, 70)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_child(b)
		y += 118
	var controls := _label("操作\nWASD / 方向键 / 左摇杆：推进（有惯性）\nShift / LS：加力（3 倍推力，1.2× 燃料）\nJ / K（Y / B）：技能 1 / 2\nQ / E：切换物品　F / X：使用物品\n1-3：升级 / 商店选择　Esc：暂停", 14, EG.C_TEXT)
	controls.position = Vector2(640, top)
	controls.size = Vector2(390, 190)
	controls.add_theme_constant_override("line_spacing", 4)
	p.add_child(controls)
	var rules := _label("生存规则\n护盾 20，敌方导弹伤害 25：挨一发就结束。\n陨石只磨损 0.5，但被你撞飞的陨石能对攻击者造成 5 伤害。\n燃料 500；耗尽后只能靠惯性漂移。\n安全区：补满燃料、清除导弹、隐藏威胁信息。\n商店：用代币购买道具。\n辅助操作装置自动平衡天体引力；导弹没有它，始终被引力弯折。", 14, EG.C_DIM)
	rules.position = Vector2(640, top + 205)
	rules.size = Vector2(390, 190)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(rules)
	var ship_icon := TextureRect.new()
	ship_icon.texture = Assets.world("ship")
	ship_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship_icon.position = Vector2(90, 462)
	ship_icon.size = Vector2(100, 100)
	p.add_child(ship_icon)
	var mis := TextureRect.new()
	mis.texture = Assets.world("missile")
	mis.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mis.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mis.position = Vector2(245, 480)
	mis.size = Vector2(120, 62)
	p.add_child(mis)
	var tur := TextureRect.new()
	tur.texture = Assets.world("turret")
	tur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tur.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tur.position = Vector2(430, 452)
	tur.size = Vector2(130, 130)
	tur.modulate = Color(1, 1, 1, 0.85)
	p.add_child(tur)
	var back := Assets.button("返回", 18)
	back.position = Vector2(840, 548)
	back.size = Vector2(200, 46)
	back.custom_minimum_size = Vector2(200, 46)
	var prev := _settings_back
	back.pressed.connect(func(): build(prev))
	p.add_child(back)

func _open_settings(back_mode: String) -> void:
	_settings_back = back_mode
	build("settings")

func _open_howto(back_mode: String) -> void:
	_settings_back = back_mode
	build("howto")
