extends Label

@export var drone: DroneController


func _process(_delta: float) -> void:
	if drone == null:
		return
	text = "Mode:    %s\nAlt:     %.1f m\nSpeed:   %.1f m/s\nBattery: %.0f %%\nMass:    %.2f kg\nWind:    %.1f m/s\n[R] reset" % [
		DroneInputData.FlightMode.keys()[DroneInput.current.mode],
		drone.get_altitude(), drone.get_speed(), drone.get_battery_percent(),
		drone.mass, drone.get_wind().length(),
	]
