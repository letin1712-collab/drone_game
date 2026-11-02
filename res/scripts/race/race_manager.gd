class_name RaceManager
extends Node
## Điều phối cuộc đua: đếm ngược → bấm giờ → bay qua lần lượt các vòng → về đích.
## Phát hiện qua vòng bằng toán học (không dùng vật lý nên tốc độ cao cũng không sót):
## đổi vị trí drone sang hệ tọa độ vòng; qua vòng khi z đổi dấu từ + sang - và
## điểm cắt mặt phẳng nằm trong bán kính lỗ.
##   t = z_trước / (z_trước - z_sau);  hit = lerp(p_trước, p_sau, t)
## R: chạy lại | F3: đường đua mới | T: về vòng trước (+phạt)

signal message(text: String, color: Color)
signal state_changed(new_state: int)

enum State { COUNTDOWN, RACING, FINISHED }

const RECORD_PATH := "user://race_records.cfg"

@export var terrain: TerrainGenerator
@export var drone: DroneController
@export var course: RaceCourse
@export var countdown_seconds := 3.0
@export var respawn_penalty := 5.0
@export_enum("Angle (dễ)", "Acro (FPV thật)") var start_mode := 0
## 0 = ngẫu nhiên mỗi lần vào; khác 0 = lần đầu dùng đúng seed này
@export var fixed_seed := 0
@export_group("Mục tiêu thời gian")
@export var par_speed_angle := 9.0       # m/s chuẩn ở Angle
@export var par_speed_acro := 12.0       # m/s chuẩn ở Acro

const MEDAL_NAMES := ["KHÔNG CÓ", "ĐỒNG", "BẠC", "VÀNG"]

var difficulty := 0.0
var stars := 1
var par_time := 0.0          # mốc vàng
var silver_time := 0.0
var bronze_time := 0.0
var medal := 0               # 0 không, 1 đồng, 2 bạc, 3 vàng
var score := 0
var best_score := 0
var state := State.COUNTDOWN
var countdown := 0.0
var elapsed := 0.0
var penalties := 0.0
var next_index := 0
var splits: Array[float] = []
var best_time := 0.0
var finish_time := 0.0
var new_record := false

var seed_value: int:
	get:
		return course.seed_value if course else 0

var _start_xform := Transform3D.IDENTITY
var _prev_local := Vector3.ZERO
var _has_prev := false
var _miss_cooldown := 0.0
var _first_course := true


static func format_time(t: float) -> String:
	return "%02d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


func _ready() -> void:
	await get_tree().process_frame            # chờ Terrain dựng xong
	if drone == null or course == null:
		push_error("RaceManager: thiếu Drone hoặc Course")
		return
	_start_xform = drone.global_transform
	DroneInput.set_flight_mode(start_mode as DroneInputData.FlightMode)
	var cam := get_tree().get_first_node_in_group("drone_camera") as ChaseCamera
	if cam and not cam.is_fpv:
		cam.toggle_view()                     # đua FPV thì bắt đầu bằng góc nhìn FPV
	new_course()


func total_time() -> float:
	return elapsed + penalties


func gate_count() -> int:
	return course.gates.size() if course else 0


func next_gate() -> RaceGate:
	if course and next_index < course.gates.size():
		return course.gates[next_index]
	return null


func new_course() -> void:
	var custom: Array = Session.objects_of("gate")
	if custom.size() >= 2:
		var key := absi(str(Session.map.get("name", "map")).hash()) % 99999
		course.generate_custom(custom, _start_xform.origin, key)
	else:
		var s := randi_range(1000, 99999)
		if _first_course and fixed_seed != 0:
			s = fixed_seed
		_first_course = false
		course.generate(s, _start_xform.origin, -_start_xform.basis.z)
	drone.teleport(_start_xform)
	_begin()


func restart() -> void:
	_begin()                                  # drone tự reset bằng phím R của DroneController


func _begin() -> void:
	state = State.COUNTDOWN
	countdown = countdown_seconds
	elapsed = 0.0
	penalties = 0.0
	next_index = 0
	splits.clear()
	new_record = false
	finish_time = 0.0
	_has_prev = false
	best_time = _load_best()
	course.set_progress(0)
	_compute_targets()
	drone.recharge(drone.capacity_wh)
	drone.input_locked = true
	state_changed.emit(state)
	message.emit("Đường đua #%d: %d vòng, %d m, độ khó %d/5. Mốc vàng %s" % [
		seed_value, gate_count(), int(course.total_length), stars, format_time(par_time)],
		Color(0.6, 1.0, 0.7))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			restart()
		KEY_F3:
			new_course()
		KEY_T:
			respawn()


func _physics_process(delta: float) -> void:
	if drone == null or course == null or course.gates.is_empty():
		return
	_miss_cooldown = maxf(_miss_cooldown - delta, 0.0)
	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				state = State.RACING
				drone.input_locked = false
				state_changed.emit(state)
		State.RACING:
			elapsed += delta
			_check_gate()
			_check_bounds()


func _check_gate() -> void:
	var gate := course.gates[next_index]
	var cur: Vector3 = gate.global_transform.affine_inverse() * drone.global_position
	if _has_prev:
		if _prev_local.z > 0.0 and cur.z <= 0.0:          # cắt mặt phẳng vòng đúng chiều
			var t := _prev_local.z / (_prev_local.z - cur.z)
			var hit := _prev_local.lerp(cur, t)
			var off := maxf(absf(hit.x), absf(hit.y))
			if off <= gate.radius - 0.25:
				_on_gate_passed()
				return
			if off < gate.radius + 6.0 and _miss_cooldown <= 0.0:
				_miss_cooldown = 1.5
				message.emit("Trượt vòng %d! Quay lại bay qua vòng." % (next_index + 1),
						Color(1.0, 0.6, 0.2))
		elif _prev_local.z < 0.0 and cur.z >= 0.0 and _miss_cooldown <= 0.0 \
					and maxf(absf(cur.x), absf(cur.y)) < gate.radius:
			_miss_cooldown = 1.5
			message.emit("Sai chiều! Bay xuyên vòng theo hướng mũi tên.", Color(1.0, 0.6, 0.2))
	_prev_local = cur
	_has_prev = true


func _on_gate_passed() -> void:
	var t := total_time()
	splits.append(t)
	next_index += 1
	course.set_progress(next_index)
	_has_prev = false
	if next_index >= gate_count():
		_finish()
	else:
		message.emit("Vòng %d/%d   %s" % [next_index, gate_count(), format_time(t)],
				Color(0.6, 1.0, 0.3))


func _finish() -> void:
	state = State.FINISHED
	finish_time = total_time()
	medal = 0
	if finish_time <= par_time:
		medal = 3
	elif finish_time <= silver_time:
		medal = 2
	elif finish_time <= bronze_time:
		medal = 1
	score = int(clampf(par_time / maxf(finish_time, 0.1), 0.0, 1.5) * 1000.0 * (1.0 + 0.5 * difficulty))
	var cfg := ConfigFile.new()
	cfg.load(RECORD_PATH)
	var key := "score_" + _record_key()
	best_score = maxi(score, int(cfg.get_value("records", key, 0)))
	cfg.set_value("records", key, best_score)
	cfg.save(RECORD_PATH)
	var old := _load_best()
	new_record = old <= 0.0 or finish_time < old
	if new_record:
		_save_best(finish_time)
		best_time = finish_time
	else:
		best_time = old
	state_changed.emit(state)


func respawn() -> void:
	if state != State.RACING:
		return
	penalties += respawn_penalty
	var xf := _start_xform
	if next_index > 0:
		var g := course.gates[next_index - 1]
		var fwd := -g.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		xf = Transform3D(Basis.looking_at(fwd, Vector3.UP), g.global_position + fwd * 4.0)
	drone.teleport(xf)
	_has_prev = false
	message.emit("Về lại sau vòng %d   +%d giây" % [next_index, int(respawn_penalty)],
			Color(1.0, 0.6, 0.2))


func _check_bounds() -> void:
	var half := (terrain.size * 0.5 - 5.0) if terrain else 250.0
	var p := drone.global_position
	if absf(p.x) > half or absf(p.z) > half or p.y < -15.0:
		message.emit("Ra ngoài khu vực đua!", Color(1.0, 0.3, 0.3))
		respawn()


# ---------------- Kỷ lục (theo đường đua + chế độ lái) ----------------
func _record_key() -> String:
	return "%d_%d" % [seed_value, DroneInput.current.mode]


func _load_best() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_PATH) != OK:
		return 0.0
	return float(cfg.get_value("records", _record_key(), 0.0))


func _save_best(t: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORD_PATH)                      # không có file cũng không sao
	cfg.set_value("records", _record_key(), t)
	cfg.save(RECORD_PATH)

func _compute_targets() -> void:
	difficulty = course.compute_difficulty()
	stars = 1 + roundi(difficulty * 4.0)
	var base := par_speed_acro if DroneInput.current.mode == DroneInputData.FlightMode.ACRO \
			else par_speed_angle
	var v := base * (1.0 - 0.3 * difficulty)
	par_time = course.total_length / v + gate_count() * 0.8 + 2.0
	silver_time = par_time * 1.25
	bronze_time = par_time * 1.6
	medal = 0
	score = 0


## Màu theo huy chương còn đạt được ở thời điểm hiện tại.
func pace_color() -> Color:
	var t := total_time()
	if t <= par_time:
		return Color(0.4, 1.0, 0.5)
	if t <= silver_time:
		return Color(1.0, 0.9, 0.3)
	if t <= bronze_time:
		return Color(1.0, 0.6, 0.2)
	return Color(1.0, 0.35, 0.3)