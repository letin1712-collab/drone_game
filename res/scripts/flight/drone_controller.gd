class_name DroneController
extends RigidBody3D
## Điều khiển vật lý drone. Chỉ đọc DroneInput.current, không biết thiết bị nào.
## Quy ước Godot: trước = -Z, lên = +Y, phải = +X.

signal battery_depleted

@export_group("Khối lượng")
@export var base_mass := 1.2          # kg, drone rỗng
@export var payload_mass := 0.0:      # kg, hàng cứu hộ đang mang
	set(value):
		payload_mass = maxf(value, 0.0)
		mass = base_mass + payload_mass
## Mô-men quán tính theo 3 trục cục bộ (kg·m²)
@export var inertia_tensor := Vector3(0.012, 0.020, 0.012)

@export_group("Động cơ")
## Lực đẩy tối đa / trọng lượng drone rỗng. FPV đua thật có thể 5-8, đây để dễ chơi.
@export var thrust_to_weight := 3.0
@export var motor_time_constant := 0.05      # giây, độ trễ động cơ
@export var max_angular_accel := 200.0       # rad/s², giới hạn mô-men

@export_group("Angle mode")
@export var max_tilt_deg := 35.0
@export var max_climb_speed := 5.0           # m/s
@export var angle_yaw_rate_deg := 120.0
@export var tilt_kp := 60.0                  # độ cứng giữ góc
@export var tilt_kd := 14.0                  # giảm chấn (≈ 2·√kp là tắt dần tới hạn)
@export var yaw_kp := 10.0
@export var climb_kp := 4.0
@export var hold_position := true
## Độ nghiêng (rad) bù cho mỗi 1 m/s vận tốc ngang. Lớn hơn = hãm mạnh hơn.
@export var hold_kp := 0.15
@export var hold_max_tilt_deg := 25.0

@export_group("Acro mode")
@export var acro_roll_rate_deg := 360.0
@export var acro_pitch_rate_deg := 360.0
@export var acro_yaw_rate_deg := 240.0
@export var acro_rate_kp := 30.0

@export_group("Khí động học")
@export var air_density := 1.225
## CdA (hệ số cản × diện tích, m²) theo trục cục bộ X (ngang), Y (dọc), Z (trước/sau)
@export var drag_cda := Vector3(0.05, 0.10, 0.03)
@export var wind_system: WindSystem

@export_group("Pin")
@export var capacity_wh := 30.0
@export var hover_power_w := 150.0           # công suất khi lơ lửng (drone rỗng)
@export var idle_power_w := 8.0              # điện trở bo mạch, camera...

var battery_wh := 0.0
var _thrust := 0.0
var _gravity := 9.8
var _wind := Vector3.ZERO
var turbulence := 0.0      # WeatherSystem cập nhật: độ rung do thời tiết xấu
var input_locked := false            # true: bỏ qua input (đang đếm ngược)
var _teleport_pending := false
var _teleport_xform := Transform3D.IDENTITY
var _spawn_transform := Transform3D.IDENTITY
var _reset_pending := false
var _was_depleted := false


func _ready() -> void:
	add_to_group("drone")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	mass = base_mass + payload_mass
	inertia = inertia_tensor
	# Tự tính drag nên tắt damping mặc định của engine
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true            # cần để biết drone đang chạm đất
	max_contacts_reported = 4
	battery_wh = capacity_wh
	_spawn_transform = global_transform


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		_reset_pending = true


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_pending:
		_reset_pending = false
		state.transform = _spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		battery_wh = capacity_wh
		_thrust = 0.0
		_was_depleted = false
		return
	if _teleport_pending:
		_teleport_pending = false
		state.transform = _teleport_xform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_thrust = base_mass * _gravity      # giữ lực nâng để không rơi ngay
		return
	var dt := state.step
	var cmd: DroneInputData = DroneInput.current
	if input_locked:
		cmd = DroneInputData.new()
		cmd.mode = DroneInput.current.mode
	var b := state.transform.basis.orthonormalized()
	var up := b.y
	var v := state.linear_velocity
	var w := state.angular_velocity
	var is_angle := cmd.mode == DroneInputData.FlightMode.ANGLE

	_wind = wind_system.get_wind(state.transform.origin) if wind_system else Vector3.ZERO

	# ---------- 1) THRUST ----------
	var weight_empty := base_mass * _gravity
	var max_thrust := weight_empty * thrust_to_weight
	# Pin yếu → điện áp sụt → lực đẩy tối đa giảm (dưới 15% pin)
	var sag := clampf(get_battery_percent() / 15.0, 0.4, 1.0)
	max_thrust *= sag

	var thrust_cmd := 0.0
	if is_angle:
		# Throttle → tốc độ leo mục tiêu. Điều khiển P trên vận tốc đứng:
		# T = m·(g + kp·(vz_target − vz)) / cos(tilt)   (bù khi thân nghiêng)
		var vz_target := cmd.throttle * max_climb_speed
		var tilt_comp := maxf(up.y, 0.5)
		thrust_cmd = mass * (_gravity + climb_kp * (vz_target - v.y)) / tilt_comp
	else:
		# Throttle thô: 0 = lực nâng hover (khi drone rỗng), +1 = tối đa, -1 = tắt hẳn
		var hover := 1.0 / thrust_to_weight
		var collective := hover + (1.0 - hover) * cmd.throttle if cmd.throttle >= 0.0 \
			else hover * (1.0 + cmd.throttle)
		thrust_cmd = collective * max_thrust
	thrust_cmd = clampf(thrust_cmd, 0.0, max_thrust)

	# Nằm trên mặt đất và không đẩy ga → tắt động cơ để drone đỗ yên
	if _is_grounded(state) and cmd.throttle <= 0.05:
		thrust_cmd = 0.0
	if battery_wh <= 0.0:
		thrust_cmd = 0.0
		if not _was_depleted:
			_was_depleted = true
			battery_depleted.emit()

	# Độ trễ động cơ: T ← lerp(T, T_cmd, 1 − e^(−dt/τ))
	_thrust = lerpf(_thrust, thrust_cmd, 1.0 - exp(-dt / motor_time_constant))
	state.apply_central_force(up * _thrust)

	# ---------- 2) DRAG (so với không khí, có gió) ----------
	var v_local := b.transposed() * (v - _wind)
	var drag_local := -0.5 * air_density * drag_cda * v_local * v_local.length()
	state.apply_central_force(b * drag_local)

	# ---------- 3) TORQUE ----------
	var alpha_world := _angle_angular_accel(cmd, b, w, v) if is_angle \
		else _acro_angular_accel(cmd, b, w)
	alpha_world = alpha_world.limit_length(max_angular_accel)
	# τ = I·α, tính trong hệ cục bộ vì I là đường chéo theo trục thân
	var alpha_local := b.transposed() * alpha_world
	state.apply_torque(b * (inertia_tensor * alpha_local))
	if turbulence > 0.0:
		var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * 0.3, randf_range(-1.0, 1.0))
		state.apply_torque(b * (jitter * turbulence * 0.03))

	# ---------- 4) PIN ----------
	var ratio := _thrust / weight_empty
	var power_w := idle_power_w + hover_power_w * pow(ratio, 1.5)
	battery_wh = maxf(battery_wh - power_w * dt / 3600.0, 0.0)


## Angle mode: PD controller trên vector "lên" + điều khiển tốc độ xoay yaw.
## Angle mode: PD controller trên vector "lên" + điều khiển tốc độ xoay yaw.
## Có thêm vòng ngoài "giữ vị trí": khi thả stick, tự nghiêng ngược hướng trôi.
func _angle_angular_accel(cmd: DroneInputData, b: Basis, w: Vector3, v: Vector3) -> Vector3:
	var up := b.y
	var fwd := -b.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var yaw_basis := Basis(Vector3.UP, yaw)

	var max_tilt := deg_to_rad(max_tilt_deg)
	var pitch_t := cmd.pitch * max_tilt
	var roll_t := cmd.roll * max_tilt

	if hold_position:
		# Vận tốc ngang (so với mặt đất) quy về hệ theo hướng mũi: x = phải, z = sau
		var v_local := yaw_basis.inverse() * Vector3(v.x, 0.0, v.z)
		# Bù nghiêng tỉ lệ vận tốc: tilt_corr = -kp · v
		# (trôi tới trước → pitch âm để phanh; trôi sang phải → roll âm)
		var pitch_corr := hold_kp * v_local.z
		var roll_corr := -hold_kp * v_local.x
		# Stick càng đẩy thì hãm càng yếu, để người chơi vẫn bay được
		var stick := clampf(maxf(absf(cmd.pitch), absf(cmd.roll)) * 3.0, 0.0, 1.0)
		var auto := 1.0 - stick
		var hold_max := deg_to_rad(hold_max_tilt_deg)
		pitch_t += clampf(pitch_corr, -hold_max, hold_max) * auto
		roll_t += clampf(roll_corr, -hold_max, hold_max) * auto
		pitch_t = clampf(pitch_t, -max_tilt, max_tilt)
		roll_t = clampf(roll_t, -max_tilt, max_tilt)

	var tilt := Basis(Vector3.RIGHT, -pitch_t) * Basis(Vector3.BACK, -roll_t)
	var desired_up := yaw_basis * (tilt * Vector3.UP)

	var err := up.cross(desired_up)
	var w_yaw := up * w.dot(up)
	var w_tilt := w - w_yaw

	# α = kp·e − kd·ω  (PD)
	var alpha := tilt_kp * err - tilt_kd * w_tilt

	var yaw_rate_target := -cmd.yaw * deg_to_rad(angle_yaw_rate_deg)
	alpha += up * (yaw_kp * (yaw_rate_target - w.dot(up)))
	return alpha


## Acro mode: stick = tốc độ góc mục tiêu (hệ cục bộ), α = kp·(ω_target − ω).
func _acro_angular_accel(cmd: DroneInputData, b: Basis, w: Vector3) -> Vector3:
	var w_local := b.transposed() * w
	var target := Vector3(
		-cmd.pitch * deg_to_rad(acro_pitch_rate_deg),   # quanh X
		-cmd.yaw * deg_to_rad(acro_yaw_rate_deg),       # quanh Y
		-cmd.roll * deg_to_rad(acro_roll_rate_deg))     # quanh Z
	return b * (acro_rate_kp * (target - w_local))


func _is_grounded(state: PhysicsDirectBodyState3D) -> bool:
	for i in state.get_contact_count():
		if absf(state.get_contact_local_normal(i).y) > 0.7:
			return true
	return false


# ---------- Dữ liệu cho HUD (Module 3) ----------
func set_payload(kg: float) -> void:
	payload_mass = kg

func get_battery_percent() -> float:
	return battery_wh / capacity_wh * 100.0

func get_altitude() -> float:
	return global_position.y

func get_speed() -> float:
	return linear_velocity.length()

func get_wind() -> Vector3:
	return _wind

func get_thrust_ratio() -> float:
	return clampf(_thrust / (base_mass * _gravity * thrust_to_weight), 0.0, 1.0)

func recharge(wh: float) -> void:
	battery_wh = minf(battery_wh + wh, capacity_wh)
	if battery_wh > 0.0:
		_was_depleted = false

## Đặt drone tại một vị trí/hướng (dùng khi hồi sinh ở vòng đua).
func teleport(xf: Transform3D) -> void:
	_teleport_xform = xf
	_teleport_pending = true