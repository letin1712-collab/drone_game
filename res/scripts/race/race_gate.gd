class_name RaceGate
extends Node3D
## Khung đua hình vuông, hướng bay xuyên qua là -Z cục bộ.
## `radius` = nửa cạnh của lỗ vuông (lỗ rộng 2·radius).
## Trạng thái: UPCOMING (hồng), NEXT (xanh lá nhấp nháy), PASSED (xanh mờ).

enum GateState { UPCOMING, NEXT, PASSED }

const BAR := 0.4            # độ dày thanh khung

var radius := 3.0
var index := 0
var is_finish := false

var _mat := StandardMaterial3D.new()
var _state := GateState.UPCOMING
var _t := 0.0


## Gọi SAU khi đã add_child và đặt global_transform.
func build(p_radius: float, p_index: int, p_finish: bool, ground_y: float, solid: bool) -> void:
	radius = p_radius
	index = p_index
	is_finish = p_finish

	_mat.emission_enabled = true
	_mat.roughness = 0.4

	# 4 thanh tạo thành khung vuông trong mặt phẳng XY
	var r := radius
	var t := BAR
	_bar(Vector3(2.0 * r + 2.0 * t, t, t), Vector3(0.0, r + t * 0.5, 0.0), solid)    # trên
	_bar(Vector3(2.0 * r + 2.0 * t, t, t), Vector3(0.0, -r - t * 0.5, 0.0), solid)   # dưới
	_bar(Vector3(t, 2.0 * r, t), Vector3(-r - t * 0.5, 0.0, 0.0), solid)             # trái
	_bar(Vector3(t, 2.0 * r, t), Vector3(r + t * 0.5, 0.0, 0.0), solid)              # phải

	# Cột đỡ từ mặt đất lên đáy khung
	var length := (global_position.y - r - t) - (ground_y - 0.5)
	if length > 0.5:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = length
		cm.radial_segments = 6
		pole.mesh = cm
		pole.position = Vector3(0.0, -r - t - length * 0.5, 0.0)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.35, 0.36, 0.4)
		pole.material_override = pm
		add_child(pole)

	# Số thứ tự luôn quay về phía camera
	var lbl := Label3D.new()
	lbl.text = "FINISH" if is_finish else str(index + 1)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.012
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.no_depth_test = true
	lbl.position = Vector3(0.0, r + t + 0.9, 0.0)
	add_child(lbl)

	set_state(GateState.UPCOMING)


func _bar(size: Vector3, pos: Vector3, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		add_child(body)


func set_state(s: GateState) -> void:
	_state = s
	var col: Color
	var energy: float
	match s:
		GateState.PASSED:
			col = Color(0.15, 0.45, 0.25)
			energy = 0.3
		GateState.NEXT:
			col = Color(0.2, 1.0, 0.3)          # xanh lá: khung cần bay qua
			energy = 4.0
		_:
			col = Color(1.0, 0.3, 0.7)          # hồng: chưa tới lượt
			energy = 1.8
	_mat.albedo_color = col
	_mat.emission = col
	_mat.emission_energy_multiplier = energy


func _process(delta: float) -> void:
	_t += delta
	if _state == GateState.NEXT:
		_mat.emission_energy_multiplier = 3.5 + sin(_t * 6.0) * 1.5   # nhấp nháy