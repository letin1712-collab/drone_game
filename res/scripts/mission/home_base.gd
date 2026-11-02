class_name HomeBase
extends Node3D
## Bãi đáp: bệ tròn, vòng vàng, chữ H và cột sáng xanh để nhìn thấy từ xa.

@export var terrain: TerrainGenerator
@export var landing_radius := 4.0


func _ready() -> void:
	if terrain:
		global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.01
	_build()


## Coi là "đã hạ cánh" khi ở trong bãi, sát mặt đất và gần như đứng yên.
func is_landed(d: DroneController) -> bool:
	return horizontal_distance(d) < landing_radius \
		and d.global_position.y - global_position.y < 0.6 \
		and d.linear_velocity.length() < 0.6


func horizontal_distance(d: Node3D) -> float:
	var v := d.global_position - global_position
	return Vector2(v.x, v.z).length()


func _build() -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 0.02
	pad.mesh = cm
	pad.material_override = _mat(Color(0.25, 0.26, 0.28))
	add_child(pad)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.55
	tm.outer_radius = 2.85
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.02
	ring.material_override = _mat(Color(0.95, 0.8, 0.1))
	add_child(ring)

	# Chữ H
	for x in [-0.6, 0.6]:
		_slab(Vector3(0.25, 0.02, 1.6), Vector3(x, 0.02, 0.0))
	_slab(Vector3(1.2, 0.02, 0.25), Vector3(0.0, 0.02, 0.0))

	# Cột sáng nhận biết từ xa
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.12
	bm.height = 40.0
	beam.mesh = bm
	beam.position.y = 20.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.2, 0.8, 1.0, 0.22)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _slab(sz: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(Color.WHITE)
	add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m

@export var charge_rate_wh := 2.5     # Wh nạp mỗi giây khi đang đỗ trên bãi

var _drone: DroneController
var _payload: PayloadSystem


func _process(delta: float) -> void:
	if _drone == null:
		_drone = get_tree().get_first_node_in_group("drone") as DroneController
	if _payload == null:
		_payload = get_tree().get_first_node_in_group("payload_system") as PayloadSystem
	if _drone == null or not is_landed(_drone):
		return
	_drone.recharge(charge_rate_wh * delta)
	if _payload and _payload.needs_refill():
		_payload.refill()