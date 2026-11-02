class_name DroneVisual
extends Node3D
## Dựng mô hình quadcopter bằng code. Đặt làm CON của node Drone, tên "Visual".
## Hướng mũi = -Z. Cánh quạt quay theo lực đẩy, 2 cặp quay ngược chiều nhau.

var _props: Array[Node3D] = []
var _prop_dir: Array[float] = []
var _discs: Array[MeshInstance3D] = []
var _spin := 0.0
var _drone: DroneController


func _ready() -> void:
	_drone = get_parent() as DroneController
	_build()


func _process(delta: float) -> void:
	var ratio := _drone.get_thrust_ratio() if _drone else 0.0
	# Tốc độ quay mục tiêu (rad/s). Thrust = 0 thì dừng hẳn.
	var target := 0.0 if ratio < 0.01 else lerpf(30.0, 90.0, ratio)
	_spin = move_toward(_spin, target, 250.0 * delta)
	for i in _props.size():
		_props[i].rotate_y(_prop_dir[i] * _spin * delta)
		# Quay nhanh thì hiện "đĩa mờ" thay cho cánh (giống mắt người thấy)
		_discs[i].visible = _spin > 45.0


func _build() -> void:
	var dark := Color(0.12, 0.12, 0.14)
	var red := Color(0.9, 0.15, 0.1)
	var gray := Color(0.25, 0.26, 0.3)

	# Thân + tấm trên + pin
	_box(Vector3(0.14, 0.05, 0.16), Vector3(0, 0, 0), dark)
	_box(Vector3(0.12, 0.012, 0.14), Vector3(0, 0.03, 0), gray)
	_box(Vector3(0.07, 0.03, 0.11), Vector3(0, 0.05, 0.01), Color(0.95, 0.75, 0.1))

	# Camera FPV phía trước (-Z)
	_box(Vector3(0.06, 0.05, 0.04), Vector3(0, 0.0, -0.095), dark)
	var lens := _cyl(0.016, 0.02, Vector3(0, 0.0, -0.12), Color(0.05, 0.1, 0.25))
	lens.rotation.x = PI / 2.0

	# Ăng-ten phía sau
	_cyl(0.004, 0.09, Vector3(0.03, 0.07, 0.09), dark)

	# Chân đáp
	_box(Vector3(0.012, 0.03, 0.2), Vector3(-0.07, -0.04, 0), dark)
	_box(Vector3(0.012, 0.03, 0.2), Vector3(0.07, -0.04, 0), dark)

	# 4 càng + động cơ + cánh quạt
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var m_pos := Vector3(sx * 0.14, 0.02, sz * 0.14)
			var is_front: bool = sz < 0.0

			# Càng: hộp dài 0.2 m nối tâm tới động cơ
			var arm := _box(Vector3(0.2, 0.012, 0.022), Vector3(m_pos.x * 0.5, 0.015, m_pos.z * 0.5),
				red if is_front else dark)
			arm.rotation.y = atan2(-sz, sx)  # trục X của hộp hướng theo (sx, sz)

			_cyl(0.022, 0.03, m_pos, gray)

			var pivot := Node3D.new()
			pivot.position = m_pos + Vector3(0, 0.025, 0)
			add_child(pivot)
			_box(Vector3(0.2, 0.004, 0.018), Vector3.ZERO, Color(0.08, 0.08, 0.08), pivot)
			var disc := _cyl(0.1, 0.002, Vector3.ZERO, Color(0.8, 0.8, 0.8, 0.15), pivot, true)
			disc.visible = false
			_props.append(pivot)
			_prop_dir.append(sx * sz)  # đường chéo quay ngược chiều nhau
			_discs.append(disc)


func _mat(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.2
	m.roughness = 0.6
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, color: Color,
		parent: Node3D = null, transparent := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, transparent)
	if transparent:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi