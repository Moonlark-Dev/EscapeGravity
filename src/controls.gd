extends Node
## Builds the input map at runtime (works headless too) and exposes helpers.
##
## PC 端同时支持键鼠与手柄：界面提示必须跟着“最近一次真正操作的设备”切换，
## 用手柄时只显示手柄键位（A/B/X/Y、LB/RB、Start、方向键），用键鼠时只显示
## 键盘键位，避免一张提示里同时塞两套按键。

signal device_changed(pad: bool)

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
}

## 每个动作在两种设备下的键位标签：`[键盘, 手柄]`。
## 覆盖层共用 card_1~5，所以升级/商店/丢弃都能用手柄方向键选择。
const HINTS := {
	"move": ["WASD", "左摇杆"],
	"boost": ["Shift", "RB"],
	"skill_1": ["J", "Y"],
	"skill_2": ["K", "B"],
	"use_item": ["F", "X"],
	"item_next": ["E", "→"],
	"item_prev": ["Q", "←"],
	"pause": ["Esc", "Start"],
	"restart": ["R", "A"],
	"card_1": ["1", "←"],
	"card_2": ["2", "↑"],
	"card_3": ["3", "→"],
	"card_4": ["4", "↓"],
	"card_5": ["5", "A"],
}

var pad_active := false

func _ready() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("boost", [KEY_SHIFT])
	_add_action("skill_1", [KEY_J])
	_add_action("skill_2", [KEY_K])
	_add_action("use_item", [KEY_F])
	_add_action("item_next", [KEY_E])
	_add_action("item_prev", [KEY_Q])
	_add_action("pause", [KEY_ESCAPE, KEY_P])
	_add_action("card_1", [KEY_1, KEY_KP_1])
	_add_action("card_2", [KEY_2, KEY_KP_2])
	_add_action("card_3", [KEY_3, KEY_KP_3])
	_add_action("card_4", [KEY_4, KEY_KP_4])
	_add_action("card_5", [KEY_5, KEY_KP_5])
	_add_action("restart", [KEY_R])
	_add_action("toggle_hud", [KEY_TAB])

	# 移动：左摇杆
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	# 动作键：RB 只负责加力（以前和切换物品共用 RB，会一次触发两件事）。
	_joy_btn("boost", JOY_BUTTON_LEFT_STICK)
	_joy_btn("boost", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_btn("skill_1", JOY_BUTTON_Y)
	_joy_btn("skill_2", JOY_BUTTON_B)
	_joy_btn("use_item", JOY_BUTTON_X)
	_joy_btn("item_next", JOY_BUTTON_DPAD_RIGHT)
	_joy_btn("item_prev", JOY_BUTTON_DPAD_LEFT)
	_joy_btn("pause", JOY_BUTTON_START)
	_joy_btn("restart", JOY_BUTTON_A)
	# 面板选择：方向键 1~4，第 5 格用 A（丢弃面板最多 5 格）。
	_joy_btn("card_1", JOY_BUTTON_DPAD_LEFT)
	_joy_btn("card_2", JOY_BUTTON_DPAD_UP)
	_joy_btn("card_3", JOY_BUTTON_DPAD_RIGHT)
	_joy_btn("card_4", JOY_BUTTON_DPAD_DOWN)
	_joy_btn("card_5", JOY_BUTTON_A)
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		InputMap.action_set_deadzone(a, 0.18)

## 只在“设备真的换了”时发信号：手柄摇杆的噪声不会反复刷新界面。
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if event.pressed:
			set_pad_mode(true)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			set_pad_mode(true)
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			set_pad_mode(false)
	elif event is InputEventMouseButton:
		if event.pressed:
			set_pad_mode(false)
	elif event is InputEventMouseMotion:
		if event.relative.length() > 1.0:
			set_pad_mode(false)

func set_pad_mode(on: bool) -> void:
	if on == pad_active:
		return
	pad_active = on
	device_changed.emit(on)

func using_pad() -> bool:
	return pad_active

## 当前设备下某个动作的键位标签（手柄操作时绝不返回键盘键位）。
func hint(action: String) -> String:
	var pair: Array = HINTS.get(action, [])
	if pair.size() < 2:
		return action
	return str(pair[1]) if pad_active else str(pair[0])

func _add_action(name: String, keys: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)

func _joy_axis(name: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(name, ev)

func _joy_btn(name: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(name, ev)

func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func touch() -> bool:
	return Store.touch_mode

func is_pressed(action: String) -> bool:
	return Input.is_action_pressed(action)

func just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)
