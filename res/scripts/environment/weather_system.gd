class_name WeatherSystem
extends Node
## 5 kiểu thời tiết, chuyển đổi mượt. Ảnh hưởng: sương mù, gió, ánh sáng, mưa, độ rung drone.
## F2: đổi thời tiết (để thử).

enum Type { CLEAR, CLOUDY, RAIN, STORM, FOG }
signal changed(weather_name: String)

const PRESETS := {
	Type.CLEAR:  {"name": "Trời quang",     "fog": 0.0010, "wind": 2.0, "gust": 3.0, "rain": 0.0, "light": 1.00, "turb": 0.3},
	Type.CLOUDY: {"name": "Nhiều mây",      "fog": 0.0018, "wind": 3.0, "gust": 4.0, "rain": 0.0, "light": 0.75, "turb": 0.6},
	Type.RAIN:   {"name": "Mưa",            "fog": 0.0045, "wind": 5.0, "gust": 5.0, "rain": 0.6, "light": 0.55, "turb": 1.0},
	Type.STORM:  {"name": "Bão",            "fog": 0.0070, "wind": 7.0, "gust": 7.0, "rain": 1.0, "light": 0.35, "turb": 2.0},
	Type.FOG:    {"name": "Sương mù dày",   "fog": 0.0150, "wind": 1.5, "gust": 1.5, "rain": 0.0, "light": 0.70, "turb": 0.3},
}
const WEIGHTS := [25, 25, 20, 10, 20]   # xác suất random (%)
const KEYS := ["fog", "wind", "gust", "rain", "light", "turb"]

@export var world: WorldSetup
@export var wind: WindSystem
@export var drone: DroneController
@export var start_type: Type = Type.CLEAR
## Độ sáng gốc (1 = ngày). Muốn thử Night Vision, đặt giá trị này nhỏ (vd 0.15).
@export_range(0.0, 1.0) var base_daylight := 1.0
@export var transition_time := 4.0

var current_type: Type = Type.CLEAR
var rain_level := 0.0

var _cur := {}
var _target := {}
var _rain: GPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_rain()
	set_weather(start_type, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F2:
		set_weather(((current_type + 1) % Type.size()) as Type)


func set_random() -> void:
	var roll := _rng.randi() % 100
	var acc := 0
	for i in WEIGHTS.size():
		acc += WEIGHTS[i]
		if roll < acc:
			set_weather(i as Type)
			return


func set_weather(t: Type, instant := false) -> void:
	current_type = t
	var p: Dictionary = PRESETS[t]
	for k in KEYS:
		_target[k] = p[k]
		if instant or not _cur.has(k):
			_cur[k] = p[k]
	if instant:
		_apply(0.0)
	changed.emit(p["name"])


func get_weather_name() -> String:
	return PRESETS[current_type]["name"]


func _process(delta: float) -> void:
	# Làm mượt hàm mũ: sau transition_time giây đạt ~95% giá trị đích
	var k := 1.0 - exp(-delta * 3.0 / maxf(transition_time, 0.1))
	for key in KEYS:
		_cur[key] = lerpf(_cur[key], _target[key], k)
	_apply(delta)


func _apply(_delta: float) -> void:
	if world:
		world.set_fog(_cur["fog"])
		world.set_daylight(base_daylight * _cur["light"])
	if wind:
		wind.base_speed = _cur["wind"]
		wind.gust_strength = _cur["gust"]
	if drone:
		drone.turbulence = _cur["turb"]
		_rain.global_position = drone.global_position + Vector3(0.0, 14.0, 0.0)
	rain_level = _cur["rain"]
	_rain.amount_ratio = clampf(rain_level * Session.rain_mult[Session.quality], 0.01, 1.0)
	_rain.emitting = rain_level > 0.02


## Hạt mưa: hộp 44x44 m bám theo drone, mỗi hạt là một vệt mảnh rơi xuống.
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 5000
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 0.5, 22.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	_rain.process_material = pm

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.5, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_rain.draw_pass_1 = mesh
	add_child(_rain)