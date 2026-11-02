extends Node
## Builds the input map at runtime (works headless too) and exposes helpers.

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
}

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
	_add_action("restart", [KEY_R])
	_add_action("toggle_hud", [KEY_TAB])

	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_joy_btn("boost", JOY_BUTTON_LEFT_STICK)
	_joy_btn("boost", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_btn("skill_1", JOY_BUTTON_Y)
	_joy_btn("skill_2", JOY_BUTTON_B)
	_joy_btn("use_item", JOY_BUTTON_X)
	_joy_btn("item_next", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_btn("item_prev", JOY_BUTTON_LEFT_SHOULDER)
	_joy_btn("pause", JOY_BUTTON_START)
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		InputMap.action_set_deadzone(a, 0.18)

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

func any_device_label(action: String) -> String:
	var labels := {
		"boost": "Shift / LS",
		"skill_1": "J / Y",
		"skill_2": "K / B",
		"use_item": "F / X",
		"pause": "Esc",
	}
	return labels.get(action, action)
