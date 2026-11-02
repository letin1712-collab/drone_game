class_name WorldSetup
extends WorldEnvironment
## Bầu trời, sương mù, ánh sáng. set_daylight(0..1): 1 = ban ngày, 0 = đêm
## (đêm dùng để thử Night Vision).

@export var sun: DirectionalLight3D
@export_range(0.0, 1.0) var daylight := 1.0: set = set_daylight
@export var fog_enabled := true
@export var fog_density := 0.0012

var _sky_mat := ProceduralSkyMaterial.new()
var _env := Environment.new()


func _ready() -> void:
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = fog_enabled
	_env.fog_density = fog_density
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_hdr_threshold = 1.0      # chỉ vật có emission mạnh (vòng đua) mới tỏa sáng
	environment = _env
	_apply()


func set_daylight(v: float) -> void:
	daylight = v
	_apply()


func _apply() -> void:
	var d := daylight
	# Màu trời giữ độ sáng dưới ngưỡng "nóng" của shader Thermal (lum < 0.8)
	_sky_mat.sky_top_color = Color(0.01, 0.015, 0.04).lerp(Color(0.25, 0.45, 0.80), d)
	_sky_mat.sky_horizon_color = Color(0.03, 0.04, 0.08).lerp(Color(0.62, 0.72, 0.82), d)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color(0.03, 0.04, 0.08).lerp(Color(0.30, 0.33, 0.30), d)
	_env.ambient_light_energy = lerpf(0.25, 1.0, d)
	_env.fog_light_color = Color(0.03, 0.04, 0.08).lerp(Color(0.65, 0.73, 0.82), d)
	if sun:
		sun.light_energy = lerpf(0.05, 1.1, d)
		sun.shadow_enabled = Session.quality > 0
		sun.directional_shadow_max_distance = Session.shadow_dist[Session.quality]

func set_fog(d: float) -> void:
	fog_density = d
	_env.fog_density = d