class_name DroneInputService
extends Node
## Đọc đồng thời bàn phím và tay cầm; thiết bị có tín hiệu gần nhất là "active_device".
## Không cần menu chuyển thiết bị.

enum ActiveDevice { KEYBOARD_MOUSE, GAMEPAD }
signal cycle_payload
signal toggle_camera
signal cycle_vision
signal release_payload
signal return_home
signal flight_mode_changed(mode: DroneInputData.FlightMode)
signal active_device_changed(device: ActiveDevice)
signal rebind_finished(action: StringName)

const SAVE_PATH := "user://input_bindings.cfg"
const PAD_AXIS_THRESHOLD := 0.25

@export var settings: InputSettings
@export var starting_mode := DroneInputData.FlightMode.ANGLE

var current := DroneInputData.new()
var active_device := ActiveDevice.KEYBOARD_MOUSE

# Giá trị phím đã làm mượt (ramp)
var _kb_throttle := 0.0
var _kb_yaw := 0.0
var _kb_pitch := 0.0
var _kb_roll := 0.0

var _rebind_action: StringName = &""


func _ready() -> void:
	process_priority = -100                   # Chạy trước controller vật lý
	process_mode = Node.PROCESS_MODE_ALWAYS   # Vẫn đọc input khi pause
	if settings == null:
		settings = InputSettings.new()
	current.mode = starting_mode
	InputBindings.register_defaults()
	_load_bindings()


func _process(delta: float) -> void:
	# Bù Engine.time_scale để input không bị ảnh hưởng khi làm slow-motion
	var dt := delta / maxf(Engine.time_scale, 0.001)

	var raw_throttle := Input.get_axis(&"throttle_down", &"throttle_up")
	var raw_yaw := Input.get_axis(&"yaw_left", &"yaw_right")
	var raw_pitch := Input.get_axis(&"pitch_back", &"pitch_forward")
	var raw_roll := Input.get_axis(&"roll_left", &"roll_right")

	if active_device == ActiveDevice.KEYBOARD_MOUSE:
		# Phím chỉ có 0/±1 nên làm mượt bằng ramp để tránh điều khiển giật cục
		_kb_throttle = _ramp(_kb_throttle, raw_throttle, dt)
		_kb_yaw = _ramp(_kb_yaw, raw_yaw, dt)
		_kb_pitch = _ramp(_kb_pitch, raw_pitch, dt)
		_kb_roll = _ramp(_kb_roll, raw_roll, dt)
		raw_throttle = _kb_throttle
		raw_yaw = _kb_yaw
		raw_pitch = _kb_pitch
		raw_roll = _kb_roll
	else:
		# Reset ramp để khi quay lại bàn phím không bị "nhảy"
		_kb_throttle = 0.0
		_kb_yaw = 0.0
		_kb_pitch = 0.0
		_kb_roll = 0.0

	current.throttle = settings.throttle.apply(raw_throttle)
	current.yaw = settings.yaw.apply(raw_yaw)
	current.pitch = settings.pitch.apply(raw_pitch)
	current.roll = settings.roll.apply(raw_roll)


## Tiến giá trị về mục tiêu với tốc độ = 1 / thời gian ramp (trục/giây).
func _ramp(value: float, target: float, dt: float) -> float:
	var speeding_up := absf(target) > absf(value) \
		or (target != 0.0 and signf(target) != signf(value))
	var t := settings.kb_ramp_up if speeding_up else settings.kb_ramp_down
	return move_toward(value, target, dt / t)


func _input(event: InputEvent) -> void:
	if _rebind_action != &"":
		_try_rebind(event)
		get_viewport().set_input_as_handled()
		return

	_detect_device(event)

	if event.is_echo():
		return
	if event.is_action_pressed(&"toggle_camera"):
		toggle_camera.emit()
	elif event.is_action_pressed(&"cycle_vision"):
		cycle_vision.emit()
	elif event.is_action_pressed(&"release_payload"):
		release_payload.emit()
	elif event.is_action_pressed(&"return_home"):
		return_home.emit()
	elif event.is_action_pressed(&"cycle_payload"):
		cycle_payload.emit()
	elif event.is_action_pressed(&"toggle_flight_mode"):
		var next := DroneInputData.FlightMode.ACRO \
			if current.mode == DroneInputData.FlightMode.ANGLE \
			else DroneInputData.FlightMode.ANGLE
		set_flight_mode(next)


func set_flight_mode(mode: DroneInputData.FlightMode) -> void:
	if current.mode == mode:
		return
	current.mode = mode
	flight_mode_changed.emit(mode)


# ---------------- Phát hiện thiết bị ----------------
func _detect_device(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_set_device(ActiveDevice.KEYBOARD_MOUSE)
	elif event is InputEventJoypadButton:
		_set_device(ActiveDevice.GAMEPAD)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > PAD_AXIS_THRESHOLD:
		# Chỉ tính khi stick đẩy đủ mạnh để tránh nhiễu/trôi stick làm đổi thiết bị
		_set_device(ActiveDevice.GAMEPAD)


func _set_device(device: ActiveDevice) -> void:
	if device == active_device:
		return
	active_device = device
	active_device_changed.emit(device)
	print("[Input] Chuyển thiết bị: ", ActiveDevice.keys()[device])


# ---------------- Gán lại phím ----------------
## Gọi từ nút UI. Sự kiện kế tiếp (phím / nút / trục tay cầm) sẽ thay thế
## binding cùng loại thiết bị của action. Nhấn ESC để hủy.
func begin_rebind(action: StringName) -> void:
	_rebind_action = action


func _try_rebind(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_rebind_action = &""
			return
		_replace_binding(event, InputEventKey)
	elif event is InputEventJoypadButton and event.pressed:
		_replace_binding(event, InputEventJoypadButton)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		event.axis_value = signf(event.axis_value)
		_replace_binding(event, InputEventJoypadMotion)


func _replace_binding(new_event: InputEvent, type: Variant) -> void:
	for old in InputMap.action_get_events(_rebind_action):
		if is_instance_of(old, type):
			InputMap.action_erase_event(_rebind_action, old)
	InputMap.action_add_event(_rebind_action, new_event)
	_save_bindings()
	var done := _rebind_action
	_rebind_action = &""
	rebind_finished.emit(done)


func reset_bindings() -> void:
	for a in InputBindings.ACTIONS:
		InputMap.erase_action(a)
	InputBindings.register_defaults()
	DirAccess.remove_absolute(SAVE_PATH)


func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	for a in InputBindings.ACTIONS:
		cfg.set_value("bindings", String(a), InputMap.action_get_events(a))
	cfg.save(SAVE_PATH)


func _load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for a in InputBindings.ACTIONS:
		if cfg.has_section_key("bindings", String(a)):
			InputMap.action_erase_events(a)
			for e in cfg.get_value("bindings", String(a)):
				InputMap.action_add_event(a, e)