class_name WindSystem
extends Node
## Gió nền + gió giật (dùng noise để giật ngẫu nhiên, mượt theo thời gian).

@export var enabled := true
@export var base_speed := 3.0            # m/s
## Hướng gió THỔI TỚI. 0° = hướng -Z, 90° = hướng +X.
@export_range(0.0, 360.0) var direction_deg := 45.0
@export var gust_strength := 4.0         # m/s cộng thêm tối đa
@export var gust_frequency := 0.2        # càng lớn gió giật càng dồn dập

var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.0


func _process(delta: float) -> void:
	_time += delta


func get_base_direction() -> Vector3:
	var a := deg_to_rad(direction_deg)
	return Vector3(sin(a), 0.0, -cos(a))


## Vận tốc gió (m/s) tại một vị trí trong thế giới.
func get_wind(pos: Vector3) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var dir := get_base_direction()
	var side := dir.cross(Vector3.UP)
	var t := _time * gust_frequency
	var p := pos * 0.05  # gió thay đổi nhẹ theo vị trí

	# Chỉ lấy phần dương để có cảm giác "giật" từng đợt, không đổi chiều
	var gust := maxf(_noise.get_noise_3d(p.x, p.z, t), 0.0) * gust_strength
	var lateral := _noise.get_noise_3d(p.x + 100.0, p.z, t) * gust_strength * 0.5
	var vertical := _noise.get_noise_3d(p.x, p.z + 100.0, t) * gust_strength * 0.25

	return dir * (base_speed + gust) + side * lateral + Vector3.UP * vertical