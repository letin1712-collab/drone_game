class_name MissionManager
extends Node
## Điều phối nhiệm vụ: sinh nạn nhân, đồng hồ đếm ngược, chấm điểm. Phím R để chơi lại.
## Hoàn thành: cứu hết + hạ cánh ở căn cứ. Kết thúc một phần: cứu được một số + hạ cánh
## (hoặc hết giờ). Thất bại: không cứu được ai, hết pin, hoặc rời vùng tìm kiếm.
## Điểm: 1000 x (0,5 + 0,5 x tình trạng) cho mỗi người + thưởng thời gian + thưởng pin
## (chỉ khi hạ cánh an toàn), nhân hệ số thời tiết.

signal message(text: String, color: Color)
signal state_changed(new_state: int)

enum State { ACTIVE, SUCCESS, FAILED, PARTIAL }

const SCORE_PATH := "user://scores.cfg"
const POINTS_PER_VICTIM := 1000.0
const TIME_BONUS_PER_SEC := 2.0
const TIME_BONUS_MAX := 600.0
const BATTERY_BONUS_PER_PCT := 3.0

@export var terrain: TerrainGenerator
@export var drone: DroneController
@export var payload: PayloadSystem
@export var home: HomeBase
@export var survival_time_range := Vector2(420.0, 540.0)   # giây
@export var weather: WeatherSystem
@export var random_weather := true
@export_group("Thời gian nhiệm vụ")
@export var time_base := 150.0            # giây
@export var time_per_victim := 120.0      # giây cho mỗi nạn nhân

var state := State.ACTIVE
var victims: Array[Victim] = []
var elapsed := 0.0
var rescued_count := 0
var result_text := ""

# --- Đồng hồ + điểm ---
var time_limit := 0.0
var time_left := 0.0
var rescue_points := 0.0
var score := 0
var rank := "D"
var breakdown: Array[String] = []
var best_score := 0
var new_best := false

var _rng := RandomNumberGenerator.new()
var _landed_time := 0.0
var _oob_time := 0.0
var _all_done_notified := false
var _warned: Array[bool] = [false, false, false]


func _ready() -> void:
	_rng.randomize()
	if weather:
		weather.changed.connect(func(n): message.emit("Thời tiết: " + n, Color(0.6, 0.85, 1.0)))
	await get_tree().process_frame          # chờ Terrain / Home dựng xong
	if drone:
		drone.battery_depleted.connect(_on_battery_depleted)
	restart()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		restart()


func restart() -> void:
	for v in victims:
		v.remove_from_group("victims")
		v.queue_free()
	victims.clear()
	for item in get_tree().get_nodes_in_group("payload_items"):
		item.queue_free()

	state = State.ACTIVE
	elapsed = 0.0
	rescued_count = 0
	result_text = ""
	rescue_points = 0.0
	score = 0
	rank = "D"
	breakdown.clear()
	new_best = false
	_landed_time = 0.0
	_oob_time = 0.0
	_all_done_notified = false
	_warned = [false, false, false]
	if weather and random_weather:
		weather.set_random()
	if payload:
		payload.restock()
	_spawn_victims()

	time_limit = time_base + time_per_victim * victims.size()
	time_left = time_limit
	best_score = _load_best()

	state_changed.emit(state)
	message.emit("NHIỆM VỤ: tìm %d nạn nhân, thả vật phẩm, về căn cứ trong %s." % [
			victims.size(), _fmt(time_limit)], Color(0.6, 1.0, 0.7))
	message.emit("MẸO: camera nhiệt [V] nhìn xuyên được tán cây.", Color(1.0, 0.85, 0.3))


func _process(delta: float) -> void:
	if state != State.ACTIVE or victims.is_empty() or drone == null:
		return
	elapsed += delta
	time_left = maxf(time_limit - elapsed, 0.0)
	_time_warnings()
	if time_left <= 0.0:
		_on_time_up()
		return
	_check_bounds(delta)
	if state != State.ACTIVE:
		return

	var unresolved := 0
	for v in victims:
		if v.state == Victim.State.UNKNOWN or v.state == Victim.State.DETECTED:
			unresolved += 1
	if unresolved > 0:
		return

	if rescued_count == 0:
		_finish(State.FAILED, "Không cứu được ai.")
		return
	if not _all_done_notified:
		_all_done_notified = true
		message.emit("Đã xử lý hết nạn nhân. HÃY VỀ CĂN CỨ và hạ cánh!", Color(0.6, 1.0, 0.7))
	if home and home.is_landed(drone):
		_landed_time += delta
		if _landed_time >= 1.5:
			var total := victims.size()
			var lost := total - rescued_count
			if lost == 0:
				_finish(State.SUCCESS, "Đã cứu cả %d nạn nhân." % total, true)
			else:
				_finish(State.PARTIAL, "Cứu được %d/%d nạn nhân, %d người đã mất." % [
						rescued_count, total, lost], true)
	else:
		_landed_time = 0.0


func _time_warnings() -> void:
	var marks := [60.0, 30.0, 10.0]
	for i in marks.size():
		if not _warned[i] and time_left <= marks[i]:
			_warned[i] = true
			message.emit("CÒN %d GIÂY!" % int(marks[i]), Color(1.0, 0.4, 0.3))


func _on_time_up() -> void:
	var text := "Hết giờ! Cứu được %d/%d nạn nhân." % [rescued_count, victims.size()]
	_finish(State.PARTIAL if rescued_count > 0 else State.FAILED, text)


# ---------------- Sinh nạn nhân ngẫu nhiên ----------------
enum Place { FOREST, RIVER, MOUNTAIN, VILLAGE, FIELD }
const PLACE_NAMES := ["forest", "river", "mountain", "village", "field"]

@export var victim_count_range := Vector2i(3, 5)
@export var min_victim_spacing := 70.0


func _spawn_victims() -> void:
	if terrain == null:
		return

	# Map do người chơi tạo: dùng đúng vị trí nạn nhân đã đặt
	var custom: Array = Session.objects_of("victim")
	if not custom.is_empty():
		for i in custom.size():
			var d: Dictionary = custom[i]
			var x := float(d["x"])
			var z := float(d["z"])
			var h := terrain.height_at(x, z)
			var wet := h < terrain.water_level + 0.3
			var p := Vector3(x, terrain.water_level if wet else h, z)
			_add_victim("Victim %s" % char(65 + i), int(d.get("need", 1)), p, wet)
		return

	# Map ngẫu nhiên
	var places: Array = [Place.FOREST, Place.RIVER, Place.MOUNTAIN, Place.VILLAGE, Place.FIELD]
	places.shuffle()
	var count := clampi(_rng.randi_range(victim_count_range.x, victim_count_range.y), 1, places.size())
	var used: Array[Vector3] = []
	for i in count:
		var place: int = places[i]
		var pos := _pick_spot(place, used)
		used.append(pos)
		var vname := "Victim %s (%s)" % [char(65 + i), PLACE_NAMES[place]]
		_add_victim(vname, _need_for(place), pos, place == Place.RIVER)


func _add_victim(vname: String, need: int, pos: Vector3, in_water: bool) -> void:
	var v := Victim.new()
	v.victim_name = vname
	v.need = need
	v.in_water = in_water
	v.survival_time = _rng.randf_range(survival_time_range.x, survival_time_range.y)
	add_child(v)
	v.global_position = pos
	var n := Vector3(
			terrain.height_at(pos.x - 1.0, pos.z) - terrain.height_at(pos.x + 1.0, pos.z), 2.0,
			terrain.height_at(pos.x, pos.z - 1.0) - terrain.height_at(pos.x, pos.z + 1.0)).normalized()
	v.align_to_ground(n)
	v.detected.connect(_on_detected)
	v.rescued.connect(_on_rescued)
	v.died.connect(_on_died)
	v.wrong_item.connect(_on_wrong_item)
	victims.append(v)


func _slope(x: float, z: float) -> float:
	var dx := absf(terrain.height_at(x + 2.0, z) - terrain.height_at(x - 2.0, z)) / 4.0
	var dz := absf(terrain.height_at(x, z + 2.0) - terrain.height_at(x, z - 2.0)) / 4.0
	return maxf(dx, dz)


func _need_for(place: int) -> int:
	match place:
		Place.RIVER:
			return Victim.Need.LIFEBUOY
		Place.MOUNTAIN:
			return Victim.Need.FLARE
		Place.VILLAGE:
			return Victim.Need.MEDKIT
		_:
			return Victim.Need.MEDKIT if _rng.randf() < 0.5 else Victim.Need.FLARE


## Thử nhiều lần để tìm vị trí hợp lệ, xa căn cứ và xa các nạn nhân khác.
func _pick_spot(place: int, used: Array[Vector3]) -> Vector3:
	var fallback := Vector3.INF
	for i in 150:
		var p := _candidate(place)
		if p == Vector3.INF:
			continue
		fallback = p
		if place != Place.RIVER and _slope(p.x, p.z) > 0.3:
			continue
		if Vector2(p.x, p.z).length() < 80.0:
			continue
		var ok := true
		for u in used:
			if Vector2(p.x - u.x, p.z - u.z).length() < min_victim_spacing:
				ok = false
				break
		if ok:
			return p
	if fallback != Vector3.INF:
		return fallback
	return Vector3(60.0, terrain.height_at(60.0, 60.0), 60.0)


func _candidate(place: int) -> Vector3:
	match place:
		Place.FOREST:
			return _forest_spot()
		Place.RIVER:
			return _river_spot()
		Place.MOUNTAIN:
			return _mountain_spot()
		Place.VILLAGE:
			return _village_spot()
		_:
			return _field_spot()


func _dist_village(x: float, z: float) -> float:
	return Vector2(x - terrain.village_center.x, z - terrain.village_center.y).length()


## Ngay dưới tán một cây → chỉ camera nhiệt thấy được.
func _forest_spot() -> Vector3:
	var trees := terrain.tree_positions
	if trees.is_empty():
		return Vector3.INF
	var p := trees[_rng.randi() % trees.size()]
	var d := Vector2(p.x, p.z).length()
	if d < 80.0 or d > 230.0:
		return Vector3.INF
	var x := p.x + 0.7
	var z := p.z + 0.4
	return Vector3(x, terrain.height_at(x, z), z)


func _river_spot() -> Vector3:
	var z := _rng.randf_range(-150.0, 150.0)
	return Vector3(terrain.river_x(z), terrain.water_level, z)


func _mountain_spot() -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(110.0, 230.0)
	var x := cos(a) * r
	var z := sin(a) * r
	var h := terrain.height_at(x, z)
	if h > 10.0 and h < 32.0 and absf(x - terrain.river_x(z)) > 40.0 \
			and _dist_village(x, z) > 70.0 and _slope(x, z) < 0.3:
		return Vector3(x, h, z)
	return Vector3.INF


## Quảng trường làng (khoảng trống giữa các nhà).
func _village_spot() -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(3.0, 10.0)
	var x := terrain.village_center.x + cos(a) * r
	var z := terrain.village_center.y + sin(a) * r
	return Vector3(x, terrain.height_at(x, z), z)


## Bãi trống: không có cây trong bán kính 6 m, cách sông và làng.
func _field_spot() -> Vector3:
	var x := _rng.randf_range(-220.0, 220.0)
	var z := _rng.randf_range(-220.0, 220.0)
	var h := terrain.height_at(x, z)
	if h < 1.5 or h > 14.0 or absf(x - terrain.river_x(z)) < 40.0 or _dist_village(x, z) < 70.0:
		return Vector3.INF
	if not terrain.trees_near(x, z, 6.0).is_empty():
		return Vector3.INF
	return Vector3(x, h, z)


# ---------------- Sự kiện ----------------
func _on_detected(v) -> void:
	message.emit("Đã phát hiện %s - cần %s" % [v.victim_name, Victim.NEED_NAMES_VI[v.need]], Color(1.0, 0.85, 0.3))


func _on_rescued(v) -> void:
	rescued_count += 1
	# Cứu càng sớm (tình trạng càng cao) càng nhiều điểm: 50% - 100%
	var pts := POINTS_PER_VICTIM * (0.5 + 0.5 * clampf(v.condition / 100.0, 0.0, 1.0))
	rescue_points += pts
	message.emit("Đã cứu xong %s  +%d điểm" % [v.victim_name, int(pts)], Color(0.4, 1.0, 0.5))


func _on_died(v) -> void:
	message.emit("%s đã mất" % v.victim_name, Color(1.0, 0.3, 0.3))


func _on_wrong_item(v) -> void:
	message.emit("Sai vật phẩm cho %s - cần %s" % [v.victim_name, Victim.NEED_NAMES_VI[v.need]], Color(1.0, 0.6, 0.2))


func _on_battery_depleted() -> void:
	if state == State.ACTIVE:
		_finish(State.FAILED, "Hết pin trước khi về căn cứ.")


func _check_bounds(delta: float) -> void:
	if terrain == null:
		return
	var half := terrain.size * 0.5
	var p := drone.global_position
	if absf(p.x) > half or absf(p.z) > half or p.y < -20.0:
		if _oob_time == 0.0:
			message.emit("RA NGOÀI VÙNG TÌM KIẾM - hãy quay lại!", Color(1.0, 0.3, 0.3))
		_oob_time += delta
		if _oob_time > 8.0:
			_finish(State.FAILED, "Đã rời khỏi vùng tìm kiếm.")
	else:
		_oob_time = 0.0


# ---------------- Kết thúc + chấm điểm ----------------
func _finish(new_state: State, text: String, landed := false) -> void:
	state = new_state
	result_text = text
	_compute_score(landed)
	state_changed.emit(state)


func _compute_score(landed: bool) -> void:
	breakdown.clear()
	var total := rescue_points
	breakdown.append("Cứu nạn nhân (%d/%d): %d điểm" % [rescued_count, victims.size(), int(rescue_points)])

	if landed and rescued_count > 0:
		var tb := minf(time_left * TIME_BONUS_PER_SEC, TIME_BONUS_MAX)
		var bb := 0.0
		if drone:
			bb = drone.get_battery_percent() * BATTERY_BONUS_PER_PCT
		total += tb + bb
		breakdown.append("Thưởng thời gian (còn %s): +%d" % [_fmt(time_left), int(tb)])
		breakdown.append("Thưởng pin (%d%%): +%d" % [int(drone.get_battery_percent()) if drone else 0, int(bb)])
	else:
		breakdown.append("Không có thưởng thời gian/pin (chưa hạ cánh an toàn)")

	var mult := _weather_mult()
	if mult > 1.0:
		breakdown.append("Hệ số thời tiết ×%.2f" % mult)
	score = int(total * mult)

	var max_points := victims.size() * POINTS_PER_VICTIM + TIME_BONUS_MAX * 0.5 + 300.0
	var ratio := float(score) / maxf(max_points, 1.0)
	if ratio >= 0.8:
		rank = "S"
	elif ratio >= 0.65:
		rank = "A"
	elif ratio >= 0.45:
		rank = "B"
	elif ratio >= 0.25:
		rank = "C"
	else:
		rank = "D"

	var old := _load_best()
	new_best = score > old
	best_score = maxi(score, old)
	if new_best:
		_save_best(score)


func _weather_mult() -> float:
	if weather == null:
		return 1.0
	match weather.current_type:
		WeatherSystem.Type.RAIN:
			return 1.15
		WeatherSystem.Type.STORM:
			return 1.3
		WeatherSystem.Type.FOG:
			return 1.1
	return 1.0


func _score_key() -> String:
	return "rescue_" + str(Session.map.get("name", "random"))


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SCORE_PATH) != OK:
		return 0
	return int(cfg.get_value("scores", _score_key(), 0))


func _save_best(v: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SCORE_PATH)
	cfg.set_value("scores", _score_key(), v)
	cfg.save(SCORE_PATH)


func _fmt(t: float) -> String:
	var s := int(ceilf(t))
	return "%02d:%02d" % [floori(s / 60.0), s % 60]
