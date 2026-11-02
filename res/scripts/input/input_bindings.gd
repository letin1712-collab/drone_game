class_name InputBindings
extends RefCounted
## Đăng ký Input Map mặc định bằng code.
## Deadzone của action đặt = 0 vì ta tự xử lý deadzone trong AxisSettings.

const ACTIONS: Array[StringName] = [
	&"throttle_up", &"throttle_down", &"yaw_left", &"yaw_right",
	&"pitch_forward", &"pitch_back", &"roll_left", &"roll_right",
	&"toggle_flight_mode", &"toggle_camera", &"cycle_vision",
	&"release_payload", &"return_home", &"cycle_payload",
]

static func register_defaults() -> void:
	# --- Trục bay ---
	_add(&"throttle_up",   [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add(&"throttle_down", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add(&"yaw_left",      [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add(&"yaw_right",     [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add(&"pitch_forward", [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add(&"pitch_back",    [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add(&"roll_left",     [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add(&"roll_right",    [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1.0)])
	# --- Nút bấm ---
	_add(&"toggle_flight_mode", [_key(KEY_M), _btn(JOY_BUTTON_DPAD_UP)])
	_add(&"toggle_camera",      [_key(KEY_C), _btn(JOY_BUTTON_DPAD_RIGHT)])
	_add(&"cycle_vision",       [_key(KEY_V), _btn(JOY_BUTTON_DPAD_LEFT)])
	_add(&"release_payload",    [_key(KEY_SPACE), _btn(JOY_BUTTON_A)])
	_add(&"return_home",        [_key(KEY_H), _btn(JOY_BUTTON_Y)])
	_add(&"cycle_payload",      [_key(KEY_TAB), _btn(JOY_BUTTON_RIGHT_SHOULDER)])

static func _add(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.0)
	for e in events:
		InputMap.action_add_event(action, e)

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

static func _btn(index: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	return e