extends Label

func _ready() -> void:
	DroneInput.active_device_changed.connect(func(d): print("Thiết bị: ", d))
	DroneInput.flight_mode_changed.connect(func(m): print("Chế độ bay: ", m))
	DroneInput.release_payload.connect(func(): print("Thả hàng!"))
	DroneInput.toggle_camera.connect(func(): print("Đổi camera"))
	DroneInput.cycle_vision.connect(func(): print("Đổi chế độ nhìn"))

func _process(_delta: float) -> void:
	var d := DroneInput.current
	text = "Device:   %s\nMode:     %s\nThrottle: %.2f\nYaw:      %.2f\nPitch:    %.2f\nRoll:     %.2f" % [
		DroneInputService.ActiveDevice.keys()[DroneInput.active_device],
		DroneInputData.FlightMode.keys()[d.mode],
		d.throttle, d.yaw, d.pitch, d.roll,
	]