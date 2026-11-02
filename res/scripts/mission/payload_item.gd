class_name PayloadItem
extends RigidBody3D
## Vật phẩm rơi tự do. Chạm đất lần đầu thì giao cho nạn nhân gần nhất (trong bán kính).

@export var need := 0                 # 0 phao, 1 túi y tế, 2 đèn tín hiệu
@export var item_mass := 0.2
@export var delivery_radius := 7.0

var _landed := false
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("payload_items")
	mass = item_mass
	linear_damp = 0.25                # lực cản không khí nhẹ
	collision_layer = 4               # layer riêng để không va drone
	collision_mask = 1                # chỉ chạm địa hình / nhà
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_build_visual()
	get_tree().create_timer(90.0).timeout.connect(queue_free)


func _process(_delta: float) -> void:
	if _light and _landed:
		_light.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.012) * 2.0   # đèn nhấp nháy


func _on_body_entered(body: Node) -> void:
	if _landed or body is DroneController:
		return
	_landed = true
	_deliver()


func _deliver() -> void:
	var best: Victim = null
	var best_d := delivery_radius
	for n in get_tree().get_nodes_in_group("victims"):
		var v := n as Victim
		if v == null or v.state == Victim.State.DEAD or v.state == Victim.State.RESCUED:
			continue
		var d := Vector2(v.global_position.x - global_position.x,
				v.global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = v
	if best:
		best.receive_item(need)


func _build_visual() -> void:
	var shape: Shape3D
	var mesh: Mesh
	var color := Color.WHITE
	match need:
		0:   # Phao cứu sinh: vòng xuyến cam
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.32
			cyl.height = 0.1
			shape = cyl
			var tm := TorusMesh.new()
			tm.inner_radius = 0.18
			tm.outer_radius = 0.32
			mesh = tm
			color = Color(0.95, 0.35, 0.1)
		1:   # Túi y tế: hộp trắng + chữ thập đỏ
			var box := BoxShape3D.new()
			box.size = Vector3(0.3, 0.2, 0.2)
			shape = box
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.2, 0.2)
			mesh = bm
			color = Color(0.95, 0.95, 0.95)
		_:   # Đèn tín hiệu: ống đỏ phát sáng
			var cyl2 := CylinderShape3D.new()
			cyl2.radius = 0.04
			cyl2.height = 0.25
			shape = cyl2
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cm.height = 0.25
			mesh = cm
			color = Color(1.0, 0.15, 0.1)

	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if need == 2:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.1)
	mi.material_override = mat
	add_child(mi)

	if need == 1:
		for sz in [Vector3(0.22, 0.215, 0.05), Vector3(0.05, 0.215, 0.14)]:
			var cross := MeshInstance3D.new()
			var xm := BoxMesh.new()
			xm.size = sz
			cross.mesh = xm
			var xmat := StandardMaterial3D.new()
			xmat.albedo_color = Color(0.85, 0.1, 0.1)
			cross.material_override = xmat
			add_child(cross)

	if need == 2:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.25, 0.1)
		_light.omni_range = 30.0
		_light.light_energy = 0.0
		_light.position = Vector3(0.0, 0.3, 0.0)
		add_child(_light)