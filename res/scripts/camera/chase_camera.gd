class_name ChaseCamera
extends Camera3D
## C: đổi FPV <-> TPV. FPV gắn lên mũi drone, có góc ngẩng như drone đua thật.

@export var target: Node3D
@export_group("TPV")
@export var distance := 3.0
@export var height := 1.0
@export var follow_speed := 6.0
@export var tpv_fov := 70.0
@export_group("FPV")
@export var fpv_uptilt_deg := 20.0           # camera ngẩng lên để bay nhanh vẫn nhìn phía trước
@export var fpv_offset := Vector3(0, 0.04, -0.15)
@export var fpv_fov := 70.0

var is_fpv := false


func _enter_tree() -> void:
	add_to_group("drone_camera")


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.05
	fov = tpv_fov
	DroneInput.toggle_camera.connect(toggle_view)
	_update_visual()
	_snap_tpv()


func toggle_view() -> void:
	is_fpv = not is_fpv
	fov = fpv_fov if is_fpv else tpv_fov
	_update_visual()
	if not is_fpv:
		_snap_tpv()


func _process(delta: float) -> void:
	if target == null:
		return
	if is_fpv:
		var b := target.global_basis.orthonormalized()
		# Xoay quanh X dương → camera ngẩng lên
		global_transform = Transform3D(
			b * Basis(Vector3.RIGHT, deg_to_rad(fpv_uptilt_deg)),
			target.global_transform * fpv_offset)
	else:
		var desired := _tpv_position()
		if desired == Vector3.INF:
			return
		global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
		look_at(target.global_position + Vector3.UP * 0.2)


func _tpv_position() -> Vector3:
	# Bám theo hướng mũi, bỏ qua độ nghiêng để camera không lắc theo drone
	var fwd := -target.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return Vector3.INF
	fwd = fwd.normalized()
	return target.global_position - fwd * distance + Vector3.UP * height


func _snap_tpv() -> void:
	if target == null:
		return
	var p := _tpv_position()
	if p != Vector3.INF:
		global_position = p


func _update_visual() -> void:
	# FPV: ẩn mô hình để cánh quạt không che tầm nhìn
	if target == null:
		return
	var vis := target.get_node_or_null("Visual")
	if vis:
		vis.visible = not is_fpv

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var step := 0.0
	if event.physical_keycode == KEY_BRACKETLEFT:
		step = -3.0
	elif event.physical_keycode == KEY_BRACKETRIGHT:
		step = 3.0
	if step != 0.0:
		if is_fpv:
			fpv_fov = clampf(fpv_fov + step, 50.0, 100.0)
			fov = fpv_fov
		else:
			tpv_fov = clampf(tpv_fov + step, 50.0, 100.0)
			fov = tpv_fov