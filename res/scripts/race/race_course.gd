class_name RaceCourse
extends Node3D
## Sinh đường đua bằng "đi bộ ngẫu nhiên": mỗi vòng cách vòng trước 45-85 m,
## lệch hướng tối đa max_turn_deg. Kiểm tra: trong bản đồ, không quá cao (núi),
## không đè lên cây/nhà, đường bay giữa hai vòng không cắt xuyên đất.

signal generated

@export var terrain: TerrainGenerator
@export var gate_count_range := Vector2i(8, 12)
@export var spacing_range := Vector2(45.0, 85.0)
@export var max_turn_deg := 65.0
@export var altitude_range := Vector2(6.0, 14.0)    # độ cao tâm vòng so với mặt đất
@export var radius_range := Vector2(2.3, 3.3)       # nhỏ hơn = khó hơn
@export var finish_radius := 4.2
@export var solid_gates := true                     # khung vòng có va chạm thật

var gates: Array[RaceGate] = []
var seed_value := 0
var total_length := 0.0
var difficulty := 0.0

func clear() -> void:
	for g in gates:
		g.queue_free()
	gates.clear()
	total_length = 0.0


## Cùng seed ra cùng đường đua (để so kỷ lục).
func generate(p_seed: int, start_pos: Vector3, start_fwd: Vector3, p_retry := 0) -> void:
	clear()
	seed_value = p_seed
	if terrain == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var count := rng.randi_range(gate_count_range.x, gate_count_range.y)
	var half := terrain.size * 0.5 - 40.0
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var prev := Vector3(start_pos.x, start_pos.y + 6.0, start_pos.z)
	var heading := atan2(start_fwd.x, -start_fwd.z)    # 0 = hướng -Z (cùng quy ước gió)

	for i in count:
		var placed := false
		for attempt in 80:
			# Thử mãi không được thì nới dần góc rẽ
			var turn := deg_to_rad(max_turn_deg + attempt * 1.2)
			var h := heading + rng.randf_range(-turn, turn)
			var dist := rng.randf_range(spacing_range.x, spacing_range.y)
			var x := prev.x + sin(h) * dist
			var z := prev.z - cos(h) * dist
			if absf(x) > half or absf(z) > half:
				continue
			var ground := maxf(terrain.height_at(x, z), terrain.water_level)
			if ground > 26.0:
				continue                                  # tránh sườn núi cao
			# Giới hạn chênh độ cao 8 m giữa hai vòng liên tiếp
			var y := clampf(ground + rng.randf_range(altitude_range.x, altitude_range.y),
					prev.y - 8.0, prev.y + 8.0)
			var cand := Vector3(x, y, z)
			var r := finish_radius if i == count - 1 else rng.randf_range(radius_range.x, radius_range.y)
			if not _gate_ok(cand, r, pts) or not _segment_ok(prev, cand):
				continue
			pts.append(cand)
			radii.append(r)
			heading = h
			prev = cand
			placed = true
			break
		if not placed:
			break                                          # hết chỗ → rút ngắn đường đua

	if pts.size() < 3:
		if p_retry < 5:
			generate(p_seed + 1, start_pos, start_fwd, p_retry + 1)
		return

	_build_gates(pts, radii, start_pos)
	generated.emit()


func set_progress(next_index: int) -> void:
	for j in gates.size():
		if j < next_index:
			gates[j].set_state(RaceGate.GateState.PASSED)
		elif j == next_index:
			gates[j].set_state(RaceGate.GateState.NEXT)
		else:
			gates[j].set_state(RaceGate.GateState.UPCOMING)


func _build_gates(pts: Array[Vector3], radii: Array[float], start_pos: Vector3) -> void:
	var last := pts.size() - 1
	var prev_pt := start_pos
	for i in pts.size():
		var p := pts[i]
		var next_pt := pts[i + 1] if i < last else p + (p - prev_pt)   # vòng cuối: nhìn thẳng tiếp
		# Hướng vòng = trung bình hướng đi vào và đi ra → bay vào mượt
		var d_in := _flat(p - prev_pt)
		var d_out := _flat(next_pt - p)
		var fwd := d_in + d_out
		fwd = d_in if fwd.length() < 0.1 else fwd.normalized()

		var g := RaceGate.new()
		add_child(g)
		g.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
		var ground := maxf(terrain.height_at(p.x, p.z), terrain.water_level)
		g.build(radii[i], i, i == last, ground, solid_gates)
		gates.append(g)

		total_length += prev_pt.distance_to(p)
		prev_pt = p


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## Mặt đất đủ thấp, không đè lên mái nhà trong làng.
func _clear(x: float, z: float, y: float, margin: float) -> bool:
	var ground := maxf(terrain.height_at(x, z), terrain.water_level)
	if y - margin < ground:
		return false
	var vd := Vector2(x - terrain.village_center.x, z - terrain.village_center.y).length()
	if vd < 52.0 and y - margin < ground + 8.0:
		return false
	return true


func _gate_ok(c: Vector3, r: float, pts: Array[Vector3]) -> bool:
	if not _clear(c.x, c.z, c.y, r + 2.0):
		return false
	var ground := maxf(terrain.height_at(c.x, c.z), terrain.water_level)
	if c.y - r - ground < 9.0 and _tree_near(c.x, c.z, 6.0):
		return false
	for q in pts:
		if q.distance_to(c) < 30.0:
			return false                                   # không chồng lên vòng cũ
	return true


## Lấy mẫu dọc đường bay: không cắt đất, không đâm vào cây thấp.
func _segment_ok(a: Vector3, b: Vector3) -> bool:
	for i in range(1, 9):
		var p := a.lerp(b, float(i) / 9.0)
		if not _clear(p.x, p.z, p.y, 2.5):
			return false
		var ground := maxf(terrain.height_at(p.x, p.z), terrain.water_level)
		if p.y - ground < 9.0 and _tree_near(p.x, p.z, 2.5):
			return false
	return true


func _tree_near(x: float, z: float, r: float) -> bool:
	return not terrain.trees_near(x, z, r).is_empty()


## Đường đua do người chơi đặt trong editor (theo đúng thứ tự đặt).
func generate_custom(list: Array, start_pos: Vector3, p_seed: int) -> void:
	clear()
	seed_value = p_seed
	var prev := start_pos
	var last := list.size() - 1
	for i in list.size():
		var d: Dictionary = list[i]
		var x := float(d["x"])
		var z := float(d["z"])
		var ground := maxf(terrain.height_at(x, z), terrain.water_level)
		var g := RaceGate.new()
		add_child(g)
		g.global_transform = Transform3D(Basis(Vector3.UP, float(d.get("rot", 0.0))),
				Vector3(x, ground + float(d.get("h", 8.0)), z))
		g.build(float(d.get("r", 3.0)), i, i == last, ground, solid_gates)
		gates.append(g)
		total_length += prev.distance_to(g.global_position)
		prev = g.global_position
	generated.emit()

## 0 = dễ, 1 = khó: góc cua trung bình, độ nhỏ của khung, số khung.
func compute_difficulty() -> float:
	if gates.size() < 2:
		difficulty = 0.0
		return 0.0
	var turn_sum := 0.0
	var turns := 0
	var r_sum := 0.0
	var prev := Vector2.ZERO                        # căn cứ ở gốc tọa độ
	var prev_dir := Vector2.ZERO
	for g in gates:
		var p := Vector2(g.global_position.x, g.global_position.z)
		var d := p - prev
		if d.length() > 0.1:
			if prev_dir != Vector2.ZERO:
				turn_sum += absf(prev_dir.angle_to(d))
				turns += 1
			prev_dir = d.normalized()
		prev = p
		r_sum += g.radius
	var mean_turn := rad_to_deg(turn_sum / maxf(turns, 1.0))
	var turn_f := clampf(mean_turn / 70.0, 0.0, 1.0)
	var size_f := clampf((3.4 - r_sum / gates.size()) / 1.9, 0.0, 1.0)
	var count_f := clampf((gates.size() - 5.0) / 8.0, 0.0, 1.0)
	difficulty = 0.5 * turn_f + 0.3 * size_f + 0.2 * count_f
	return difficulty