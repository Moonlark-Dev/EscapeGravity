class_name Hud
extends CanvasLayer
## In-run HUD and overlays. Everything is built from pre-rendered textures,
## nine-patches and labels — no runtime shape drawing.

var run
var main
var root: Control
var info_root: Control
var overlay: Control
var overlay_body: Control
var toast_root: Control
var flash_rect: TextureRect
var touch_dir := Vector2.ZERO
var touch_boost := false

var _shield_bar: TextureProgressBar
var _shield_label: Label
var _exp_bar: TextureProgressBar
var _level_label: Label
var _fuel_bar: TextureProgressBar
var _fuel_label: Label
var _boost_bar: TextureProgressBar
var _speed_label: Label
var _depth_label: Label
var _enemy_holder: Control
var _enemy_bar: TextureProgressBar
var _enemy_bar2: TextureProgressBar
var _enemy_name: Label
var _enemy_info: Label
var _mods_row: Control
var _mod_chips: Array = []
var _mods_sig := ""
var _safe_label: Label
var _token_label: Label
var _hint_label: Label

var _radar_holder: Control
var _radar_plate: TextureRect
var _radar_sweep: TextureRect
var _radar_player: TextureRect
var _radar_cells: Array = []
var _radar_blips: Array = []
var _radar_marker: Sprite2D
var _radar_t := 0.0

var _threat_arc: Sprite2D
var _bearings: Array = []
var _markers: Array = []

var _inv_holder: Control
var _inv_slots: Array = []
var _inv_sig := ""
var _item_hint: Label
var _skills_holder: Control
var _skill_slots: Array = []
var _pause_btn: Button

var _touch_root: Control
var _joy_base: TextureRect
var _joy_knob: TextureRect
var _joy_touch := -1
var _joy_center := Vector2.ZERO
var _boost_btn: TextureButton
var _touch_skill_btns: Array = []
var _touch_item_btns: Array = []

var _flash_color := Color(1, 1, 1, 0)
var _flash_t := 0.0
var _toasts: Array = []
var _cards_root: VBoxContainer
var _radar_emph := 0.0
var _safe_tint: TextureRect
var _info_hidden := false

func bind(r) -> void:
	run = r
	_build()

# ---------------------------------------------------------------- build

func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	info_root = Control.new()
	info_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info_root)

	_build_bars()
	_build_pause_button()
	_build_enemy_bar()
	_build_radar()
	_build_safe_tint()
	_build_threat_arc()
	_build_inventory()
	_build_skills()
	_build_touch()
	_build_markers()
	_build_toasts()
	_build_overlay()

	_hint_label = Assets.label("", 13, EG.C_DIM)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left = 24
	_hint_label.offset_top = -126
	_hint_label.offset_right = 520
	_hint_label.offset_bottom = -108
	info_root.add_child(_hint_label)
	_hint_label.visible = not Store.touch_mode


func _build_bars() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	holder.offset_left = 22
	holder.offset_top = 18
	holder.offset_right = 340
	holder.offset_bottom = 126
	info_root.add_child(holder)

	var ic1 := Assets.icon("icon_shield")
	ic1.position = Vector2(0, 2)
	ic1.size = Vector2(22, 22)
	holder.add_child(ic1)
	_shield_bar = Assets.progress_bar("bar_fill_shield")
	_shield_bar.position = Vector2(28, 0)
	_shield_bar.size = Vector2(290, 24)
	_shield_bar.max_value = EG.SHIP_SHIELD_MAX
	_shield_bar.value = EG.SHIP_SHIELD_MAX
	holder.add_child(_shield_bar)
	_shield_label = Assets.label("20 / 20", 13, Color(0.02, 0.06, 0.12), 0)
	_shield_label.position = Vector2(28, 3)
	_shield_label.size = Vector2(290, 20)
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(_shield_label)

	var ic2 := Assets.icon("icon_exp")
	ic2.position = Vector2(2, 30)
	ic2.size = Vector2(18, 18)
	holder.add_child(ic2)
	_exp_bar = Assets.progress_bar("bar_fill_exp")
	_exp_bar.position = Vector2(28, 32)
	_exp_bar.size = Vector2(250, 14)
	_exp_bar.max_value = EG.XP_PER_LEVEL
	holder.add_child(_exp_bar)
	_level_label = Assets.label("Lv 1", 18, EG.C_VIOLET)
	_level_label.position = Vector2(284, 26)
	_level_label.size = Vector2(60, 24)
	holder.add_child(_level_label)

	var ic3 := Assets.icon("icon_fuel")
	ic3.position = Vector2(2, 50)
	ic3.size = Vector2(18, 18)
	holder.add_child(ic3)
	_fuel_bar = Assets.progress_bar("bar_fill_fuel")
	_fuel_bar.position = Vector2(28, 52)
	_fuel_bar.size = Vector2(290, 16)
	_fuel_bar.max_value = EG.SHIP_FUEL_MAX
	_fuel_bar.value = EG.SHIP_FUEL_MAX
	holder.add_child(_fuel_bar)
	_fuel_label = Assets.label("240", 12, Color(0.03, 0.09, 0.06), 0)
	_fuel_label.position = Vector2(28, 52)
	_fuel_label.size = Vector2(290, 16)
	_fuel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(_fuel_label)

	var ic4 := Assets.icon("icon_boost")
	ic4.position = Vector2(2, 74)
	ic4.size = Vector2(16, 16)
	holder.add_child(ic4)
	_boost_bar = Assets.progress_bar("bar_fill_boost")
	_boost_bar.position = Vector2(28, 76)
	_boost_bar.size = Vector2(190, 10)
	_boost_bar.max_value = EG.SHIP_BOOST_MAX
	_boost_bar.value = EG.SHIP_BOOST_MAX
	holder.add_child(_boost_bar)

	# Speed readout: turns cyan past the engine limit and amber past 400, so a
	# gravity-assisted launch is readable even when the camera lags behind.
	_speed_label = Assets.label("速度 0", 12, EG.C_DIM)
	_speed_label.position = Vector2(222, 72)
	_speed_label.size = Vector2(118, 16)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(_speed_label)

	_depth_label = Assets.label("深度 1 · 击杀 0", 13, EG.C_DIM)
	_depth_label.position = Vector2(28, 94)
	_depth_label.size = Vector2(240, 20)
	holder.add_child(_depth_label)

	# 核心改装芯片：按流派图标 + 层数排成一行，叠满一层就多一个 ×N。
	_mods_row = Control.new()
	_mods_row.position = Vector2(0, 118)
	_mods_row.size = Vector2(320, 22)
	holder.add_child(_mods_row)

func _build_pause_button() -> void:
	_pause_btn = Assets.button("Ⅱ", 20)
	_pause_btn.custom_minimum_size = Vector2(52, 46)
	_pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -52 - 22
	_pause_btn.offset_top = 248
	_pause_btn.offset_right = -22
	_pause_btn.offset_bottom = 294
	_pause_btn.pressed.connect(_on_pause_pressed)
	root.add_child(_pause_btn)

func _build_enemy_bar() -> void:
	_enemy_holder = Control.new()
	_enemy_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_enemy_holder.anchor_left = 0.5
	_enemy_holder.anchor_right = 0.5
	_enemy_holder.offset_left = -215
	_enemy_holder.offset_right = 215
	_enemy_holder.offset_top = 62
	_enemy_holder.offset_bottom = 116
	_enemy_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_root.add_child(_enemy_holder)

	_enemy_name = Assets.label("", 15, EG.C_TEXT)
	_enemy_name.position = Vector2(0, 0)
	_enemy_name.size = Vector2(430, 20)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_holder.add_child(_enemy_name)
	_enemy_bar = Assets.progress_bar("bar_fill_hp")
	_enemy_bar.position = Vector2(0, 22)
	_enemy_bar.size = Vector2(430, 20)
	_enemy_bar.max_value = 50
	_enemy_bar.value = 50
	_enemy_holder.add_child(_enemy_bar)
	# 双子中继站的主/副双段血条：主条上方是当前目标，副条是其联动站。
	_enemy_bar2 = Assets.progress_bar("bar_fill_hp")
	_enemy_bar2.position = Vector2(70, 45)
	_enemy_bar2.size = Vector2(290, 9)
	_enemy_bar2.max_value = 42
	_enemy_bar2.value = 42
	_enemy_bar2.modulate = Color(1.0, 0.72, 0.45)
	_enemy_bar2.visible = false
	_enemy_holder.add_child(_enemy_bar2)
	_enemy_info = Assets.label("", 12, EG.C_DIM)
	_enemy_info.position = Vector2(0, 0)
	_enemy_info.size = Vector2(430, 20)
	_enemy_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_holder.add_child(_enemy_info)
	_safe_label = Assets.label("", 20, EG.C_MINT, 4)
	_safe_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_safe_label.anchor_left = 0.5
	_safe_label.anchor_right = 0.5
	_safe_label.offset_left = -260
	_safe_label.offset_right = 260
	_safe_label.offset_top = 120
	_safe_label.offset_bottom = 150
	_safe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_root.add_child(_safe_label)

func _build_radar() -> void:
	_radar_holder = Control.new()
	_radar_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_radar_holder.offset_left = -22 - 214
	_radar_holder.offset_top = 18
	_radar_holder.offset_right = -22
	_radar_holder.offset_bottom = 232
	_radar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_root.add_child(_radar_holder)

	_radar_plate = TextureRect.new()
	_radar_plate.texture = Assets.ui("radar_plate")
	_radar_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radar_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_radar_plate.position = Vector2.ZERO
	_radar_plate.size = Vector2(214, 214)
	_radar_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_holder.add_child(_radar_plate)

	var center := Vector2(107, 107)
	for y in range(-6, 7):
		for x in range(-6, 7):
			if Vector2(x, y).length() > 6.4:
				continue
			var c := TextureRect.new()
			c.texture = Assets.world("spark")
			c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			c.size = Vector2(9, 9)
			c.position = center + Vector2(x, y) * 14.0 - Vector2(4.5, 4.5)
			c.modulate = Color(0.1, 0.16, 0.3, 0.45)
			c.z_index = 0
			_radar_holder.add_child(c)
			_radar_cells.append(c)

	_radar_sweep = TextureRect.new()
	_radar_sweep.texture = Assets.ui("radar_sweep")
	_radar_sweep.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radar_sweep.position = Vector2(0, 0)
	_radar_sweep.size = Vector2(214, 214)
	_radar_sweep.pivot_offset = Vector2(107, 107)
	_radar_sweep.modulate = Color(1, 1, 1, 0.55)
	_radar_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_holder.add_child(_radar_sweep)

	_radar_player = TextureRect.new()
	_radar_player.texture = Assets.ui("radar_player")
	_radar_player.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radar_player.size = Vector2(20, 20)
	_radar_player.position = center - Vector2(10, 10)
	_radar_player.pivot_offset = Vector2(10, 10)
	_radar_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_holder.add_child(_radar_player)

	for i in range(16):
		var s := TextureRect.new()
		s.texture = Assets.ui("radar_threat")
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.size = Vector2(10, 10)
		s.visible = false
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_radar_holder.add_child(s)
		_radar_blips.append(s)

	_radar_marker = Assets.ui_sprite("radar_zone")
	_radar_marker.visible = false
	_radar_holder.add_child(_radar_marker)

	_token_label = Assets.label("0", 18, EG.C_MAGENTA)
	_token_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tok := Assets.icon("icon_token")
	if Store.touch_mode:
		# Right side is the touch control column; keep the token readout under
		# the radar so it never sits under the boost/skill buttons.
		_token_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_token_label.offset_left = -236
		_token_label.offset_top = 242
		_token_label.offset_right = -132
		_token_label.offset_bottom = 268
		tok.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tok.offset_left = -128
		tok.offset_top = 240
		tok.offset_right = -104
		tok.offset_bottom = 264
	else:
		_token_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_token_label.offset_left = -150
		_token_label.offset_top = -120
		_token_label.offset_right = -104
		_token_label.offset_bottom = -94
		tok.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		tok.offset_left = -100
		tok.offset_top = -122
		tok.offset_right = -76
		tok.offset_bottom = -98
	info_root.add_child(_token_label)
	info_root.add_child(tok)

func _build_safe_tint() -> void:
	_safe_tint = TextureRect.new()
	_safe_tint.texture = Assets.ui("white")
	_safe_tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_safe_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_tint.modulate = Color(0.35, 1.0, 0.78, 0.0)
	_safe_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_safe_tint)

func _build_threat_arc() -> void:
	_threat_arc = Assets.ui_sprite("threat_arc", true)
	_threat_arc.centered = true
	_threat_arc.z_index = -1
	_threat_arc.visible = false
	info_root.add_child(_threat_arc)

func _build_inventory() -> void:
	_inv_holder = Control.new()
	_inv_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_inv_holder.offset_left = -22 - 352
	_inv_holder.offset_top = -22 - 64
	_inv_holder.offset_right = -22
	_inv_holder.offset_bottom = -22
	_inv_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_root.add_child(_inv_holder)

	for i in range(EG.ITEM_SLOTS_MAX):
		var slot := Control.new()
		slot.position = Vector2(i * 72, 0)
		slot.size = Vector2(64, 64)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		_inv_holder.add_child(slot)
		var bg := TextureRect.new()
		bg.texture = Assets.ui("btn_item")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.size = Vector2(64, 64)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(9, 9)
		ic.size = Vector2(46, 46)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		var num := Assets.label(str(i + 1), 12, EG.C_DIM)
		num.position = Vector2(44, 42)
		num.size = Vector2(18, 18)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot.add_child(num)
		var sel := TextureRect.new()
		sel.texture = Assets.ui("btn_item")
		sel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sel.size = Vector2(64, 64)
		sel.modulate = Color(0.5, 1.0, 1.0, 0.55)
		sel.visible = false
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(sel)
		var idx := i
		slot.gui_input.connect(func(e): _on_inv_slot_input(e, idx))
		_inv_slots.append({"root": slot, "icon": ic, "num": num, "sel": sel})

	_item_hint = Assets.label("", 12, EG.C_DIM)
	_item_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_item_hint.offset_left = -380
	_item_hint.offset_top = -106
	_item_hint.offset_right = -22
	_item_hint.offset_bottom = -88
	_item_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_root.add_child(_item_hint)

func _build_skills() -> void:
	_skills_holder = Control.new()
	_skills_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_skills_holder.offset_left = 22
	_skills_holder.offset_top = -22 - 76
	_skills_holder.offset_right = 22 + 172
	_skills_holder.offset_bottom = -22
	_skills_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_root.add_child(_skills_holder)
	for i in range(2):
		var slot := Control.new()
		slot.position = Vector2(i * 86, 0)
		slot.size = Vector2(76, 76)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		_skills_holder.add_child(slot)
		var bg := TextureRect.new()
		bg.texture = Assets.ui("btn_skill")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.size = Vector2(76, 76)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(bg)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(10, 10)
		ic.size = Vector2(56, 56)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		var key := Assets.label("J" if i == 0 else "K", 13, EG.C_CYAN)
		key.position = Vector2(4, 56)
		key.size = Vector2(24, 20)
		slot.add_child(key)
		var cd := TextureRect.new()
		cd.texture = Assets.ui("cd_dark")
		cd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cd.size = Vector2(76, 76)
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cd)
		var cd_label := Assets.label("", 18, Color.WHITE, 3)
		cd_label.position = Vector2(0, 24)
		cd_label.size = Vector2(76, 28)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(cd_label)
		var idx := i
		slot.gui_input.connect(func(e): _on_skill_slot_input(e, idx))
		_skill_slots.append({"root": slot, "icon": ic, "key": key, "cd": cd, "cd_label": cd_label})

func _build_touch() -> void:
	_touch_root = Control.new()
	_touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_root.visible = Store.touch_mode
	root.add_child(_touch_root)

	var joy := Control.new()
	joy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joy.offset_left = 12
	joy.offset_top = -300
	joy.offset_right = 312
	joy.offset_bottom = 0
	joy.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_root.add_child(joy)
	_joy_base = TextureRect.new()
	_joy_base.texture = Assets.ui("joystick_base")
	_joy_base.modulate = Color(1.9, 2.15, 2.4, 0.95)
	_joy_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_joy_base.position = Vector2(38, 56)
	_joy_base.size = Vector2(224, 224)
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy.add_child(_joy_base)
	var joy_ring := Assets.world_sprite("shockwave", true)
	joy_ring.position = Vector2(112, 112)
	joy_ring.scale = Vector2.ONE * 0.5
	joy_ring.modulate = Color(0.4, 0.95, 1.0, 0.42)
	joy.add_child(joy_ring)
	for i in range(4):
		var tick := Assets.world_sprite("arrow", true)
		tick.position = Vector2(112, 112) + Vector2.RIGHT.rotated(float(i) * PI * 0.5) * 96.0
		tick.rotation = float(i) * PI * 0.5
		tick.scale = Vector2.ONE * 0.42
		tick.modulate = Color(0.45, 0.95, 1.0, 0.55)
		joy.add_child(tick)
	_joy_knob = TextureRect.new()
	_joy_knob.texture = Assets.ui("joystick_knob")
	_joy_knob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_joy_knob.size = Vector2(120, 120)
	_joy_knob.position = _joy_base.position + Vector2(52, 52)
	_joy_knob.modulate = Color(1.8, 2.0, 2.2, 1.0)
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy.add_child(_joy_knob)
	_joy_center = _joy_base.position + Vector2(112, 112)
	joy.gui_input.connect(_on_joy_input)

	_boost_btn = TextureButton.new()
	_boost_btn.texture_normal = Assets.ui("btn_boost")
	_boost_btn.texture_pressed = Assets.ui("btn_boost_down")
	_boost_btn.ignore_texture_size = true
	_boost_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var edge := 22.0
	var boost_size := 150.0
	var skill_size := 92.0
	var gap := 10.0
	_boost_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_btn.offset_left = -edge - boost_size
	_boost_btn.offset_top = -edge - boost_size
	_boost_btn.offset_right = -edge
	_boost_btn.offset_bottom = -edge
	_boost_btn.button_down.connect(func(): touch_boost = true)
	_boost_btn.button_up.connect(func(): touch_boost = false)
	_touch_root.add_child(_boost_btn)

	var skill_top := -edge - boost_size - gap - skill_size
	var skill_bottom := skill_top + skill_size
	for i in range(2):
		var b := TextureButton.new()
		b.texture_normal = Assets.ui("btn_skill")
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var ic := TextureRect.new()
		ic.texture = Assets.ui("icon_skill_pulse")
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.size = Vector2(64, 64)
		ic.position = Vector2(14, 14)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		b.offset_left = -edge - skill_size * float(2 - i) - gap * float(1 - i)
		b.offset_right = b.offset_left + skill_size
		b.offset_top = skill_top
		b.offset_bottom = skill_bottom
		var idx := i
		b.pressed.connect(func(): if run != null: run.cast_skill(idx))
		_touch_root.add_child(b)
		var cd_label := Assets.label("", 17, Color.WHITE, 3)
		cd_label.position = Vector2(24, 32)
		cd_label.size = Vector2(44, 28)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(cd_label)
		_touch_skill_btns.append({"btn": b, "icon": ic, "cd": cd_label})

	# Mobile: keep the desktop skill icons hidden, touch buttons take over.
	# The right column is (bottom -> top): boost, skills, inventory, item hint.
	_skills_holder.visible = not Store.touch_mode
	if Store.touch_mode:
		var inv_bottom := skill_top - gap
		var inv_top := inv_bottom - 64.0
		_inv_holder.offset_top = inv_top
		_inv_holder.offset_bottom = inv_bottom
		_item_hint.offset_top = inv_top - 22.0
		_item_hint.offset_bottom = inv_top - 4.0
	else:
		_inv_holder.offset_top = -22 - 64
		_inv_holder.offset_bottom = -22

func _build_toasts() -> void:
	toast_root = Control.new()
	toast_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_root)

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	root.add_child(overlay)

	flash_rect = TextureRect.new()
	flash_rect.texture = Assets.ui("white")
	flash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.modulate = Color(1, 1, 1, 0)
	root.add_child(flash_rect)

	overlay_body = Control.new()
	overlay_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(overlay_body)

	_cards_root = VBoxContainer.new()
	_cards_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_body.add_child(_cards_root)

# ---------------------------------------------------------------- refresh

func refresh() -> void:
	if run == null or run.ship == null:
		return
	var ship = run.ship
	_shield_bar.max_value = ship.shield_max
	_shield_bar.value = ship.shield
	_shield_label.text = "%d / %d" % [roundi(ship.shield), roundi(ship.shield_max)]
	_exp_bar.max_value = EG.XP_PER_LEVEL
	_exp_bar.value = run.xp
	_level_label.text = "Lv %d" % run.level
	_fuel_bar.max_value = ship.fuel_max
	_fuel_bar.value = ship.fuel
	_fuel_label.text = "%d" % roundi(ship.fuel)
	_boost_bar.max_value = ship.boost_cap
	_boost_bar.value = ship.boost_meter
	var speed: float = ship.vel.length()
	_speed_label.text = ("引力加速 %d" % roundi(speed)) if run.orbit_assist else ("速度 %d" % roundi(speed))
	var speed_col := EG.C_DIM
	if speed > 400.0:
		speed_col = EG.C_AMBER
	elif speed > EG.SHIP_MAX_SPEED * EG.SHIP_BOOST_SPEED_MULT:
		speed_col = EG.C_CYAN
	elif run.orbit_assist:
		speed_col = EG.C_MINT
	_speed_label.add_theme_color_override("font_color", speed_col)
	_depth_label.text = "深度 %d · 击杀 %d" % [run.depth, run.kills]
	_token_label.text = str(run.tokens)
	_refresh_mods()
	_refresh_enemy()
	_refresh_inventory()
	_refresh_skills()
	_radar_t += get_process_delta_time()

	if _radar_t > 0.12:
		_radar_t = 0.0
		_refresh_radar()
	_refresh_markers()
	_refresh_threats()
	_refresh_hint()
	_safe_label.text = ""
	_safe_label.add_theme_color_override("font_color", EG.C_MINT)
	if run.safe_timer > 0.0 and run.current_enemy == null:
		_safe_label.text = "威胁解除 · %.1fs" % run.safe_timer
	elif run.fuel_dead_timer > 0.0:
		_safe_label.text = "燃料耗尽 · %.0fs 后失联" % (12.0 - run.fuel_dead_timer)
		_safe_label.add_theme_color_override("font_color", EG.C_MAGENTA)
	elif run.pending_levels > 0:
		# 升级被攒到安全区：游玩中只提示次数，不弹面板。
		_safe_label.text = "待升级 ×%d · 进入安全区强化" % run.pending_levels
		_safe_label.add_theme_color_override("font_color", EG.C_VIOLET)

func _refresh_enemy() -> void:
	var e = run.current_enemy
	# An attacker stays off the HUD (name, HP, distance) until it has entered
	# the player's screen once.
	if e == null or e.dead or not e.discovered:
		_enemy_holder.visible = false
		return
	_enemy_holder.visible = true
	_enemy_bar.max_value = e.max_hp
	_enemy_bar.value = maxf(0.0, e.hp)
	_enemy_name.text = e.display_name()
	_enemy_name.add_theme_color_override("font_color", EG.C_MAGENTA if e.elite else EG.C_TEXT)
	var partner = e.twin
	if partner != null and is_instance_valid(partner) and not partner.dead and partner.discovered:
		_enemy_bar2.visible = true
		_enemy_bar2.max_value = partner.max_hp
		_enemy_bar2.value = maxf(0.0, partner.hp)
	else:
		_enemy_bar2.visible = false
	var dist: float = e.position.distance_to(run.ship.position)
	if not e.in_view:
		_enemy_info.text = "%d m" % roundi(dist / 10.0)
	else:
		_enemy_info.text = "过载" if e.overheated else "开火"
		if e.overheated:
			_enemy_info.add_theme_color_override("font_color", EG.C_CYAN)
		else:
			_enemy_info.add_theme_color_override("font_color", EG.C_AMBER)

func _refresh_mods() -> void:
	if _mods_row == null:
		return
	var sig := str(run.mods)
	if sig == _mods_sig:
		return
	_mods_sig = sig
	for c in _mod_chips:
		if is_instance_valid(c):
			c.queue_free()
	_mod_chips.clear()
	var x := 0.0
	for id in Defs.MOD_ORDER:
		var n: int = int(run.mods.get(id, 0))
		if n <= 0:
			continue
		var chip := Control.new()
		chip.position = Vector2(x, 0)
		chip.size = Vector2(22, 22)
		_mods_row.add_child(chip)
		var school: Dictionary = Defs.MOD_SCHOOLS[Defs.MODS[id]["school"]]
		var ic := Assets.icon(str(school["icon"]))
		ic.position = Vector2(0, 0)
		ic.size = Vector2(20, 20)
		ic.modulate = school["color"]
		chip.add_child(ic)
		if n > 1:
			var l := Assets.label("×%d" % n, 10, EG.C_TEXT, 2)
			l.position = Vector2(10, 8)
			l.size = Vector2(18, 14)
			chip.add_child(l)
		_mod_chips.append(chip)
		x += 24.0

func _refresh_inventory() -> void:
	var sig := str(run.inventory) + "|" + str(run.item_slots) + "|" + str(run.selected_item)
	if sig == _inv_sig:
		return
	_inv_sig = sig
	for i in range(_inv_slots.size()):
		var slot: Dictionary = _inv_slots[i]
		var active: bool = i < run.item_slots
		slot["root"].visible = active
		var has: bool = i < run.inventory.size()
		var id: String = run.inventory[i] if has else ""
		slot["icon"].texture = Assets.ui("icon_item_" + id) if has else null
		slot["icon"].visible = has
		slot["sel"].visible = active and i == run.selected_item
		slot["num"].text = str(i + 1) if i < 4 else ""
		slot["root"].modulate = Color(1, 1, 1, 1.0 if active else 0.35)
	if run.inventory.size() > 0 and run.selected_item < run.inventory.size():
		var id2: String = run.inventory[run.selected_item]
		_item_hint.text = "%s  [%s]" % [Defs.ITEMS[id2]["name"], "使用" if Store.touch_mode else "F"]
	else:
		_item_hint.text = ""

func _refresh_skills() -> void:
	for i in range(_skill_slots.size()):
		var slot: Dictionary = _skill_slots[i]
		var has: bool = i < run.skills.size()
		var s = run.skills[i] if has else null
		slot["icon"].visible = has
		slot["cd"].visible = has and float(s["cd"]) > 0.0
		slot["cd_label"].text = ("%.1f" % float(s["cd"])) if has and float(s["cd"]) > 0.0 else ""
		if has:
			slot["icon"].texture = Assets.ui("icon_skill_" + str(Defs.SKILLS[s["id"]]["icon"]).replace("skill_", ""))
			slot["icon"].modulate = Color(1, 1, 1, 1.0 if float(s["cd"]) <= 0.0 else 0.55)
			slot["key"].visible = not Store.touch_mode
		else:
			slot["key"].visible = false
		if i < _touch_skill_btns.size():
			_touch_skill_btns[i]["icon"].visible = has
			_touch_skill_btns[i]["btn"].modulate.a = 1.0 if has else 0.55
			if has:
				_touch_skill_btns[i]["icon"].texture = Assets.ui("icon_skill_" + str(Defs.SKILLS[s["id"]]["icon"]).replace("skill_", ""))
				var cdv: float = float(s["cd"])
				_touch_skill_btns[i]["icon"].modulate = Color(1, 1, 1, 1.0 if cdv <= 0.0 else 0.45)
				_touch_skill_btns[i]["cd"].text = ("%.1f" % cdv) if cdv > 0.0 else ""

func _refresh_radar() -> void:
	if _info_hidden:
		return
	var center := Vector2(107, 107)
	var spacing := 12.5
	var cc: Vector2i = run.galaxy.explore_cell_of(run.ship.position)
	for c in _radar_cells:
		c.visible = false
	var used := 0
	for y in range(-6, 7):
		for x in range(-6, 7):
			if Vector2(x, y).length() > 6.4:
				continue
			var cell := Vector2i(cc.x + x, cc.y + y)
			if used >= _radar_cells.size():
				break
			var spr: TextureRect = _radar_cells[used]
			spr.position = center + Vector2(x, y) * spacing - Vector2(4.5, 4.5)
			var explored: bool = run.galaxy.explored_cell(cell)
			spr.modulate = Color(0.22, 0.78, 1.0, 0.24) if explored else Color(0.12, 0.16, 0.32, 0.30)
			spr.visible = true
			used += 1
	for i in range(used, _radar_cells.size()):
		_radar_cells[i].visible = false
	_radar_sweep.rotation += 0.06
	_radar_player.rotation = run.ship.facing + PI * 0.5
	# blips
	var bi := 0
	var targets: Array = []
	if run.safe_zone != null and run.safe_zone.active:
		targets.append({"pos": run.safe_zone.position, "tex": "radar_zone"})
	if run.shop_zone != null and run.shop_zone.active:
		targets.append({"pos": run.shop_zone.position, "tex": "radar_shop"})
	for m in run.missiles:
		if not m.dead:
			targets.append({"pos": m.position, "tex": "radar_threat"})
	for d in run.drones:
		if is_instance_valid(d) and not d.dead:
			targets.append({"pos": d.position, "tex": "radar_threat"})
	if run.current_enemy != null and not run.current_enemy.dead and run.current_enemy.discovered:
		targets.append({"pos": run.current_enemy.position, "tex": "radar_enemy"})
	for t in targets:
		if bi >= _radar_blips.size():
			break
		var spr2: TextureRect = _radar_blips[bi]
		var rel: Vector2 = (t["pos"] - run.ship.position) / EG.RADAR_RANGE * 90.0
		if rel.length() > 90.0:
			rel = rel.normalized() * 90.0
		spr2.texture = Assets.ui(t["tex"])
		spr2.size = Vector2(10, 10)
		spr2.position = center + rel - Vector2(5, 5)
		spr2.visible = true
		spr2.modulate = Color.WHITE
		bi += 1
	for i in range(bi, _radar_blips.size()):
		_radar_blips[i].visible = false

func _build_markers() -> void:
	for spec in [["safe", "marker_zone", EG.C_MINT], ["shop", "marker_shop", EG.C_AMBER], ["enemy", "marker_enemy", Color(1.0, 0.4, 0.45)]]:
		var g := Control.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.visible = false
		info_root.add_child(g)
		var arrow := TextureRect.new()
		arrow.texture = Assets.world("arrow")
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.size = Vector2(34, 34)
		arrow.pivot_offset = Vector2(17, 17)
		arrow.modulate = spec[2]
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(arrow)
		var ic := TextureRect.new()
		ic.texture = Assets.world(spec[1])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.size = Vector2(36, 36)
		ic.pivot_offset = Vector2(18, 18)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(ic)
		var l := Assets.label("", 12, spec[2], 3)
		l.size = Vector2(90, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_child(l)
		_markers.append({"kind": spec[0], "root": g, "arrow": arrow, "icon": ic, "label": l})

func _refresh_markers() -> void:
	for m in _markers:
		m["root"].visible = false
	if run.player_hidden or overlay.visible or _info_hidden:
		return
	var size := root.size
	var center := size * 0.5
	var inset := EG.HUD_BEARING_INSET + 10.0
	var placed: Array = []
	for m in _markers:
		var target = null
		match m["kind"]:
			"safe":
				target = run.safe_zone
			"shop":
				target = run.shop_zone
			"enemy":
				target = run.current_enemy
		if target == null or not is_instance_valid(target):
			continue
		if target is Enemy and not target.discovered:
			continue
		var sp := _world_to_screen(target.position)
		var margin: float = 40.0
		if target is Enemy:
			margin = target.radius * 0.2
		var on_screen: bool = sp.x > -margin and sp.x < size.x + margin and sp.y > -margin and sp.y < size.y + margin
		if on_screen:
			continue
		var dir := (sp - center)
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var half := size * 0.5 - Vector2(inset, inset)
		var t: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var pos := center + dir * t
		# Keep bearing markers out of the HUD clusters in the four corners.
		if absf(dir.x) >= absf(dir.y):
			pos.x = size.x - inset if dir.x > 0.0 else inset
			pos.y = clampf(pos.y, 320.0, 560.0)
		else:
			pos.y = inset if dir.y < 0.0 else size.y - inset
			pos.x = clampf(pos.x, 250.0, 860.0)
		# The enemy now spawns on the safe-zone bearing, so those two edge
		# markers can land on top of each other. Stack them along the edge.
		for _k in range(3):
			var moved := false
			for prev in placed:
				if pos.distance_to(prev) < 58.0:
					pos += dir.orthogonal() * 54.0
					pos.x = clampf(pos.x, inset, size.x - inset)
					pos.y = clampf(pos.y, inset, size.y - inset)
					moved = true
					break
			if not moved:
				break
		placed.append(pos)
		var g: Control = m["root"]
		g.visible = true
		g.position = pos - Vector2(18, 18)
		m["arrow"].rotation = dir.angle()
		m["arrow"].visible = m["kind"] == "enemy"
		m["icon"].visible = m["kind"] != "enemy"
		var dist: float = run.ship.position.distance_to(target.position)
		var label: String = "%d m" % roundi(dist / 10.0)
		if m["kind"] == "safe":
			label = "安全区 " + label
		elif m["kind"] == "shop":
			label = "商店 " + label
		m["label"].text = label
		var lx: float = g.position.x - 27.0
		lx = clampf(lx, 8.0, size.x - 98.0)
		var ly: float = 34.0
		if pos.y > size.y - 80.0:
			ly = -24.0
		m["label"].position = Vector2(lx - g.position.x, ly)

func _refresh_threats() -> void:
	var show: bool = run.current_enemy == null or not run.current_enemy.in_view
	show = show and not run.player_hidden and run.state == Run.State.PLAYING
	var nearest = null
	var nd := 1e20
	if show:
		for m in run.missiles:
			if m.dead:
				continue
			var d: float = m.position.distance_to(run.ship.position)
			if d < 1100.0 and d < nd:
				nd = d
				nearest = m
		if nearest == null:
			for met in run.meteors:
				if met.dead:
					continue
				var d2: float = met.position.distance_to(run.ship.position)
				if d2 < 900.0 and d2 < nd:
					nd = d2
					nearest = met
	if nearest == null:
		_threat_arc.visible = false
		return
	var sp: Vector2 = _world_to_screen(nearest.position)
	var center: Vector2 = _world_to_screen(run.ship.position)
	var dist: float = sp.distance_to(center)
	var t: float = clampf(dist / 700.0, 0.0, 1.0)
	_threat_arc.visible = dist > 160.0 and not _info_hidden
	_threat_arc.position = center
	_threat_arc.rotation = (sp - center).angle() + PI * 0.5
	_threat_arc.scale = Vector2.ONE * clampf(0.55 + t * 0.45, 0.55, 1.0)
	_threat_arc.modulate = Color(1.0, 0.35, 0.3, 0.55).lerp(Color(0.4, 1.0, 0.95, 0.45), t)

func _refresh_hint() -> void:
	if Store.touch_mode:
		_hint_label.visible = false
		return
	_hint_label.visible = not run.player_hidden
	if run.player_hidden:
		return
	_hint_label.text = "WASD 推进 · Shift 加力 · J/K 技能 · F 使用物品"

func _world_to_screen(p: Vector2) -> Vector2:
	var cam: Camera2D = run.camera
	var size := root.size
	return p - cam.get_screen_center_position() + size * 0.5

# ---------------------------------------------------------------- toasts / flash

func toast(text: String, color: Color = EG.C_TEXT, duration: float = 2.4) -> void:
	if toast_root == null:
		return
	var t := Assets.label(text, 18, color, 4)
	t.size = Vector2(900, 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	t.anchor_left = 0.5
	t.anchor_right = 0.5
	t.offset_left = -450
	t.offset_right = 450
	t.offset_top = -210 - _toasts.size() * 30
	t.offset_bottom = -182 - _toasts.size() * 30
	toast_root.add_child(t)
	var entry := {"node": t, "life": duration, "color": color}
	_toasts.append(entry)
	var tw := t.create_tween()
	tw.tween_property(t, "modulate:a", 0.0, 0.6).set_delay(duration)
	tw.tween_callback(func(): _remove_toast(entry))

func _remove_toast(entry: Dictionary) -> void:
	_toasts.erase(entry)
	if is_instance_valid(entry["node"]):
		entry["node"].queue_free()
	for i in range(_toasts.size()):
		var t: Label = _toasts[i]["node"]
		if is_instance_valid(t):
			t.offset_top = -210 - i * 30
			t.offset_bottom = -182 - i * 30

func flash(color: Color, alpha: float) -> void:
	_flash_color = Color(color.r, color.g, color.b, alpha)
	_flash_t = 0.30
	flash_rect.modulate = _flash_color

func flash_update(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		flash_rect.modulate.a = _flash_color.a * (_flash_t / 0.30)

func emphasize_radar() -> void:
	_radar_emph = 1.0
	var tw := create_tween()
	tw.tween_property(_radar_plate, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.18)
	tw.tween_property(_radar_plate, "modulate", Color.WHITE, 0.6)

func set_paused_overlay(on: bool) -> void:
	_set_overlay_mode(on)

func set_safe_mode(on: bool) -> void:
	if _safe_tint == null:
		return
	var tw := create_tween()
	tw.tween_property(_safe_tint, "modulate:a", 0.10 if on else 0.0, 0.45)

func set_info_hidden(hidden: bool) -> void:
	_info_hidden = hidden
	_radar_holder.visible = not hidden
	_threat_arc.visible = false
	for m in _markers:
		m["root"].visible = false
	_hint_label.visible = false if hidden else not Store.touch_mode
	_touch_root.visible = Store.touch_mode

func set_safe_countdown(_t: float) -> void:
	pass

# ---------------------------------------------------------------- input

func _process(_delta: float) -> void:
	if run == null:
		return
	if run.state == Run.State.LEVELUP:
		for i in range(3):
			if Input.is_action_just_pressed("card_%d" % (i + 1)):
				run.choose_upgrade(i)
		return
	if run.state == Run.State.SHOP:
		for i in range(3):
			if Input.is_action_just_pressed("card_%d" % (i + 1)):
				run.buy_offer(i)
		if Input.is_action_just_pressed("use_item") or Input.is_action_just_pressed("pause"):
			run.close_shop()
		return
	if run.state == Run.State.REPLACE_SKILL:
		for i in range(EG.SKILL_SLOTS):
			if Input.is_action_just_pressed("card_%d" % (i + 1)):
				run.choose_skill_replace(i)
		if Input.is_action_just_pressed("pause"):
			run.cancel_skill_replace()
		return
	if run.state == Run.State.DESTROY:
		for i in range(EG.ITEM_SLOTS_MAX):
			if Input.is_action_just_pressed("card_%d" % (i + 1)):
				run.destroy_and_take(i)
		return

	if Store.touch_mode and _touch_root != null and _touch_root.visible:
		_touch_root.visible = not overlay.visible

func _on_pause_pressed() -> void:
	if main != null:
		main.toggle_pause()

func _on_inv_slot_input(e: InputEvent, idx: int) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_inv_click(idx)
	elif e is InputEventScreenTouch and e.pressed:
		_inv_click(idx)

func _inv_click(idx: int) -> void:
	if run == null or idx >= run.item_slots:
		return
	if idx < run.inventory.size():
		if run.selected_item == idx:
			run.use_item_slot(idx)
		else:
			run.select_item_slot(idx)

func _on_skill_slot_input(e: InputEvent, idx: int) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		run.cast_skill(idx)
	elif e is InputEventScreenTouch and e.pressed:
		run.cast_skill(idx)

func _on_joy_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _joy_touch < 0:
			_joy_touch = e.index
			_update_joy(e.position)
		elif not e.pressed and e.index == _joy_touch:
			_joy_touch = -1
			touch_dir = Vector2.ZERO
			_joy_knob.position = _joy_center - Vector2(60, 60)
	elif e is InputEventScreenDrag and e.index == _joy_touch:
		_update_joy(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_update_joy(e.position)
		else:
			touch_dir = Vector2.ZERO
			_joy_knob.position = _joy_center - Vector2(60, 60)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_joy(e.position)

func _update_joy(local: Vector2) -> void:
	var d := local - _joy_center
	var r := 74.0
	if d.length() > r:
		d = d.normalized() * r
	_joy_knob.position = _joy_center + d - Vector2(60, 60)
	touch_dir = d / r

# ---------------------------------------------------------------- overlays

func _clear_overlay() -> void:
	for c in overlay_body.get_children():
		c.queue_free()

func _dim_background() -> void:
	var dim := TextureRect.new()
	dim.texture = Assets.ui("black")
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.modulate = Color(1, 1, 1, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_body.add_child(dim)

func _center_panel(w: float, h: float, texture: String = "panel_9p") -> Control:
	var p := Control.new()
	p.size = Vector2(w, h)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -w * 0.5
	p.offset_top = -h * 0.5
	p.offset_right = w * 0.5
	p.offset_bottom = h * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_body.add_child(p)
	var bg := Assets.panel(texture)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(bg)
	return p

func _title(parent: Control, text: String, y: float, size: int = 34, color: Color = EG.C_TEXT) -> Label:
	var l := Assets.label(text, size, color, 4)
	l.position = Vector2(0, y)
	l.size = Vector2(parent.size.x, 48)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _set_overlay_mode(on: bool) -> void:
	_pause_btn.visible = not on
	_touch_root.visible = Store.touch_mode and not on

func show_levelup(cards: Array) -> void:
	overlay.visible = true
	_set_overlay_mode(true)
	_clear_overlay()
	_dim_background()
	var panel := _center_panel(1040.0, 560.0)
	_title(panel, "升级 · 选择一项强化", 26, 34, EG.C_CYAN)
	var sub := Assets.label("1 / 2 / 3  或点击卡片", 14, EG.C_DIM)
	sub.position = Vector2(0, 72)
	sub.size = Vector2(panel.size.x, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
	var hb := HBoxContainer.new()
	hb.position = Vector2(40, 108)
	hb.size = Vector2(960, 400)
	hb.add_theme_constant_override("separation", 20)
	panel.add_child(hb)
	for i in range(cards.size()):
		hb.add_child(_make_card(cards[i], i))

func _make_card(card: Dictionary, idx: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(306, 396)
	c.size = Vector2(306, 396)
	var bg := Assets.panel("card_9p")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var rarity: String = card.get("rarity", "common")
	var rc := Defs.rarity_color(rarity)
	var top := TextureRect.new()
	top.texture = Assets.ui("divider")
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.position = Vector2(24, 30)
	top.size = Vector2(258, 4)
	top.modulate = rc
	c.add_child(top)
	var ic := TextureRect.new()
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(93, 62)
	ic.size = Vector2(120, 120)
	ic.texture = Assets.ui(card.get("icon", "icon_skill"))
	c.add_child(ic)
	var title := Assets.label(card.get("title", ""), 22, rc, 3)
	title.position = Vector2(16, 196)
	title.size = Vector2(274, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(title)
	var desc := Assets.label(card.get("desc", ""), 15, EG.C_DIM)
	desc.position = Vector2(28, 236)
	desc.size = Vector2(250, 100)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(desc)
	var rl := Assets.label(Defs.RARITY.get(rarity, {"name": "普通"})["name"], 13, rc)
	rl.position = Vector2(16, 360)
	rl.size = Vector2(274, 20)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(rl)
	var key := Assets.label(str(idx + 1), 20, EG.C_CYAN, 3)
	key.position = Vector2(20, 14)
	key.size = Vector2(30, 26)
	c.add_child(key)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func(): run.choose_upgrade(idx))
	c.add_child(btn)
	return c

func hide_levelup() -> void:
	overlay.visible = false
	_set_overlay_mode(false)
	_clear_overlay()

func show_shop(stock: Array, tokens_now: int) -> void:
	overlay.visible = true
	_set_overlay_mode(true)
	_clear_overlay()
	_dim_background()
	var panel := _center_panel(980.0, 520.0, "panel_alt_9p")
	_title(panel, "星港交易", 24, 34, EG.C_AMBER)
	var sub := Assets.label("“拿代币换点能让你多活一会儿的东西。”", 15, EG.C_DIM)
	sub.position = Vector2(0, 66)
	sub.size = Vector2(panel.size.x, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
	var tok_icon := Assets.icon("icon_token")
	tok_icon.position = Vector2(panel.size.x - 200, 22)
	tok_icon.size = Vector2(28, 28)
	panel.add_child(tok_icon)
	var tok_label := Assets.label(str(tokens_now), 22, EG.C_MAGENTA)
	tok_label.position = Vector2(panel.size.x - 166, 20)
	tok_label.size = Vector2(120, 32)
	panel.add_child(tok_label)
	for i in range(stock.size()):
		panel.add_child(_make_shop_row(stock[i], i, panel.size.x))
	var close := Assets.button("离开商店  [F]", 18)
	close.position = Vector2(panel.size.x * 0.5 - 120, panel.size.y - 74)
	close.size = Vector2(240, 50)
	close.pressed.connect(func(): run.close_shop())
	panel.add_child(close)

func _make_shop_row(offer: Dictionary, idx: int, panel_w: float) -> Control:
	var row := Control.new()
	row.position = Vector2(34, 108 + idx * 108)
	row.size = Vector2(panel_w - 68, 96)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Assets.panel("panel_9p")
	bg.modulate = Color(1, 1, 1, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(bg)
	var title: String = str(offer.get("title", ""))
	var desc_text: String = str(offer.get("desc", ""))
	var rarity: String = str(offer.get("rarity", "common"))
	var icon: String = str(offer.get("icon", "icon_inventory"))
	var rc := Defs.rarity_color(rarity)
	var ic := TextureRect.new()
	ic.texture = Assets.ui(icon)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(14, 14)
	ic.size = Vector2(68, 68)
	row.add_child(ic)
	var shelf := str(offer.get("shelf", ""))
	var name_l := Assets.label(("%s · %s" % [shelf, title]) if shelf != "" else title, 20, rc)
	name_l.position = Vector2(98, 10)
	name_l.size = Vector2(520, 26)
	row.add_child(name_l)
	var desc := Assets.label(desc_text, 13, EG.C_DIM)
	desc.position = Vector2(98, 40)
	desc.size = Vector2(560, 50)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	var price_l := Assets.label("", 18, EG.C_AMBER)
	price_l.position = Vector2(panel_w - 430, 30)
	price_l.size = Vector2(120, 30)
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_l.text = ("%d 代币" % int(offer["price"])) if not bool(offer["sold"]) else "已售出"
	row.add_child(price_l)
	var buy := Assets.button("购买", 16)
	buy.position = Vector2(panel_w - 230, 24)
	buy.size = Vector2(150, 46)
	buy.custom_minimum_size = Vector2(150, 46)
	buy.disabled = bool(offer["sold"]) or run.tokens < int(offer["price"])
	buy.pressed.connect(func(): run.buy_offer(idx))
	row.add_child(buy)
	return row

func refresh_shop(stock: Array, tokens_now: int) -> void:
	show_shop(stock, tokens_now)

func show_skill_replace(skills_now: Array, new_id: String) -> void:
	overlay.visible = true
	_set_overlay_mode(true)
	_clear_overlay()
	_dim_background()
	var panel := _center_panel(920.0, 460.0)
	_title(panel, "技能槽已满 · 选择要替换的技能", 24, 30, EG.C_AMBER)
	var new_data: Dictionary = Defs.SKILLS[new_id]
	var sub := Assets.label("新技能：%s · %s" % [new_data["name"], new_data["desc"]], 15, EG.C_DIM)
	sub.position = Vector2(30, 68)
	sub.size = Vector2(panel.size.x - 60, 44)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
	for i in range(skills_now.size()):
		var data: Dictionary = Defs.SKILLS[skills_now[i]["id"]]
		var lv := int(skills_now[i]["level"])
		var card := Control.new()
		card.position = Vector2(56 + i * 300, 138)
		card.size = Vector2(264, 210)
		var bg := Assets.panel("card_9p")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(bg)
		var ic := TextureRect.new()
		ic.texture = Assets.ui("icon_skill_" + str(data["icon"]).replace("skill_", ""))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(92, 20)
		ic.size = Vector2(80, 80)
		card.add_child(ic)
		var nm := Assets.label(str(data["name"]), 22, data["color"], 3)
		nm.position = Vector2(0, 108)
		nm.size = Vector2(264, 28)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var lv_l := Assets.label("当前 Lv%d · 替换后继承 Lv%d" % [lv, maxi(1, int(floor(float(lv) * 0.5)))], 13, EG.C_DIM)
		lv_l.position = Vector2(0, 138)
		lv_l.size = Vector2(264, 20)
		lv_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(lv_l)
		var b := Assets.button("替换 [%d]" % (i + 1), 16)
		b.position = Vector2(52, 164)
		b.size = Vector2(160, 38)
		b.custom_minimum_size = Vector2(160, 38)
		b.pressed.connect(func(): run.choose_skill_replace(i))
		card.add_child(b)
		panel.add_child(card)
	var cancel := Assets.button("保留原技能", 18)
	cancel.position = Vector2(panel.size.x * 0.5 - 120, panel.size.y - 78)
	cancel.size = Vector2(240, 50)
	cancel.pressed.connect(func(): run.cancel_skill_replace())
	panel.add_child(cancel)

func hide_skill_replace() -> void:
	overlay.visible = false
	_set_overlay_mode(false)
	_clear_overlay()

func hide_shop() -> void:
	overlay.visible = false
	_set_overlay_mode(false)
	_clear_overlay()

func show_destroy(inventory: Array, pending_id: String) -> void:
	overlay.visible = true
	_set_overlay_mode(true)
	_clear_overlay()
	_dim_background()
	var panel := _center_panel(880.0, 300.0)
	_title(panel, "物品栏已满", 22, 30, EG.C_AMBER)
	var sub := Assets.label("获得 " + Defs.ITEMS[pending_id]["name"] + " 需要丢弃一件道具", 15, EG.C_DIM)
	sub.position = Vector2(0, 66)
	sub.size = Vector2(panel.size.x, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
	var hb := HBoxContainer.new()
	hb.position = Vector2(30, 110)
	hb.size = Vector2(820, 140)
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hb)
	for i in range(inventory.size()):
		var id: String = inventory[i]
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(120, 140)
		hb.add_child(col)
		var ic := TextureRect.new()
		ic.texture = Assets.ui("icon_item_" + id)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.custom_minimum_size = Vector2(96, 72)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(ic)
		var b := Assets.button("丢弃 %d" % (i + 1), 14)
		b.custom_minimum_size = Vector2(120, 40)
		b.size = Vector2(120, 40)
		b.pressed.connect(func(): run.destroy_and_take(i))
		col.add_child(b)

func hide_destroy() -> void:
	overlay.visible = false
	_set_overlay_mode(false)
	_clear_overlay()

func show_gameover(summary: Dictionary) -> void:
	overlay.visible = true
	_set_overlay_mode(true)
	info_root.visible = false
	_touch_root.visible = false
	_clear_overlay()
	_dim_background()
	var panel := _center_panel(820.0, 540.0)
	_title(panel, "引力逃逸失败", 26, 38, EG.C_MAGENTA)
	var reason := Assets.label(summary.get("reason", ""), 16, EG.C_AMBER)
	reason.position = Vector2(0, 80)
	reason.size = Vector2(panel.size.x, 24)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(reason)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(180, 128)
	grid.size = Vector2(460, 220)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 12)
	panel.add_child(grid)
	var rows := [
		["抵达深度", "%d" % int(summary.get("depth", 1))],
		["摧毁攻击者", "%d" % int(summary.get("kills", 0))],
		["最终等级", "Lv %d" % int(summary.get("level", 1))],
		["存活时间", "%02d:%02d" % [int(float(summary.get("time", 0.0))) / 60, int(float(summary.get("time", 0.0))) % 60]],
		["收集物质", "%d" % int(summary.get("matter", 0))],
		["导弹命中攻击者", "%d" % int(summary.get("hits", 0))],
	]
	for r in rows:
		var k := Assets.label(str(r[0]), 16, EG.C_DIM)
		k.size = Vector2(200, 26)
		grid.add_child(k)
		var v := Assets.label(str(r[1]), 20, EG.C_TEXT)
		v.size = Vector2(160, 26)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	var best := Assets.label("历史最佳深度 %d · 本局代币 %d" % [int(summary.get("best_depth", 0)), int(summary.get("tokens", 0))], 14, EG.C_DIM)
	best.position = Vector2(0, 358)
	best.size = Vector2(panel.size.x, 22)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(best)
	var again := Assets.button("再来一局  [R]", 20)
	again.position = Vector2(panel.size.x * 0.5 - 260, 404)
	again.size = Vector2(240, 56)
	again.custom_minimum_size = Vector2(240, 56)
	again.pressed.connect(func(): if main != null: main.retry())
	panel.add_child(again)
	var menu := Assets.button("返回主菜单", 20)
	menu.position = Vector2(panel.size.x * 0.5 + 20, 404)
	menu.size = Vector2(240, 56)
	menu.custom_minimum_size = Vector2(240, 56)
	menu.pressed.connect(func(): if main != null: main.show_menu())
	panel.add_child(menu)

func clear_overlay() -> void:
	overlay.visible = false
	_clear_overlay()
