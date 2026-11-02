class_name HumanFigure
extends Node3D
## Người cho nạn nhân. Chân ở y=0, mặt hướng -Z, cao TARGET_HEIGHT mét.
## Victim xoay 90° quanh X để nằm ngửa.
## - Có res://res/models/person.glb: dùng model đó (tự đo chiều cao theo xương,
##   tự xoay mặt về -Z, chạy hoạt ảnh idle).
## - Không có: dựng người bằng code như trước.
## Camera nhiệt: thân trắng (nóng), lưới tóc alpha được ẩn để không thành tấm đặc.

const MODEL_PATH := "res://res/models/person.glb"
const TARGET_HEIGHT := 1.75
const MODE_THERMAL := 1      # trùng VisionPostProcess.Vision.THERMAL
const SKINS := [Color(0.96, 0.80, 0.69), Color(0.87, 0.69, 0.52), Color(0.70, 0.50, 0.35), Color(0.45, 0.31, 0.22)]
const SHIRTS := [Color(0.95, 0.45, 0.10), Color(0.90, 0.80, 0.15), Color(0.85, 0.15, 0.15), Color(0.20, 0.50, 0.90), Color(0.20, 0.70, 0.40)]
const PANTS := [Color(0.15, 0.20, 0.40), Color(0.35, 0.30, 0.22), Color(0.12, 0.12, 0.14)]
const HAIRS := [Color(0.08, 0.06, 0.05), Color(0.30, 0.20, 0.10), Color(0.60, 0.60, 0.62), Color(0.55, 0.35, 0.15)]

var waving := false          # dùng cho người dựng bằng code
## Hoạt ảnh của model này lệch đơn vị với xương (gây méo, kéo dãn tay chân) nên mặc định TẮT.
var use_idle_animation := false
var debug_print := true

var _seed := 0
var _core: Array[MeshInstance3D] = []
var _limbs: Array[MeshInstance3D] = []
var _alpha: Array[MeshInstance3D] = []    # lưới tóc/alpha: ẩn trong Thermal
var _anim: AnimationPlayer
var _arm_r: Node3D
var _hot_core := StandardMaterial3D.new()
var _hot_limb := StandardMaterial3D.new()
var _t := randf() * 10.0
var _wave_amount := 0.0
var _alive := true


## Gọi trước hoặc sau add_child đều được; việc dựng thực hiện trong _ready().
func setup(p_seed: int) -> void:
	_seed = p_seed


func _ready() -> void:
	add_to_group("heat_sources")
	for m in [_hot_core, _hot_limb]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.render_priority = 10
	_hot_core.albedo_color = Color.WHITE
	_hot_limb.albedo_color = Color(0.9, 0.9, 0.9)

	if not _try_load_model():
		_build_procedural(_seed)

	var vp = get_tree().get_first_node_in_group("vision_post")
	if vp:
		vp.vision_changed.connect(_on_vision_changed)
		_on_vision_changed(vp.current)


func _process(delta: float) -> void:
	if _arm_r == null:
		return
	_t += delta
	_wave_amount = move_toward(_wave_amount, 1.0 if waving else 0.0, delta * 2.0)
	var wave := deg_to_rad(115.0 + sin(_t * 5.0) * 28.0)
	_arm_r.rotation.x = lerpf(0.05, wave, _wave_amount)


# =====================================================================
#  MODEL THẬT (GLB)
# =====================================================================
func _try_load_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var scn := load(MODEL_PATH) as PackedScene
	if scn == null:
		return false
	var inst := scn.instantiate()

	# Pivot: xoay 180° quanh Y (model quay mặt về +Z, game dùng -Z), chỉnh tỉ lệ + vị trí chân
	var pivot := Node3D.new()
	pivot.rotation.y = PI
	add_child(pivot)
	pivot.add_child(inst)

	var skel := _find_skeleton(inst)
	if skel != null and skel.get_bone_count() > 0:
		# Đo chiều cao theo xương (cùng đơn vị với mesh vì mesh bị xương kéo)
		var to_inst := _xform_to(inst, skel)
		var min_y := INF
		var max_y := -INF
		for i in skel.get_bone_count():
			var p := to_inst * skel.get_bone_global_rest(i).origin
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
		var h := max_y - min_y
		if h > 0.001:
			# +8% vì xương đầu/gót nằm trong thân, không phải đỉnh đầu/đế giày
			var s := TARGET_HEIGHT / (h * 1.08)
			pivot.scale = Vector3(s, s, s)
			pivot.position.y = -min_y * s + 0.03    # gót hơi nhô xuống dưới xương chân

	_collect(inst)
	for m in _core:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim and not use_idle_animation:
		_anim.stop()
		_anim.active = false
		if skel:
			skel.reset_bone_poses()          # về tư thế gốc (rest pose)
	elif _anim:
		for a in _anim.get_animation_list():
			if String(a).to_lower().contains("idle"):
				var anim := _anim.get_animation(a)
				anim.loop_mode = Animation.LOOP_LINEAR
				_anim.speed_scale = 0.6
				_anim.play(a)
				_anim.seek(randf() * anim.length)
				break
	if debug_print:
		print("[HumanFigure] pivot scale=%s, bones=%d, meshes=%d, alpha=%d" % [
				pivot.scale, skel.get_bone_count() if skel else 0, _core.size(), _alpha.size()])
	return true


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


## Biến đổi của `node` tính trong hệ tọa độ của `root` (không cần node nằm trong cây).
func _xform_to(root: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if _is_alpha(mi):
			_alpha.append(mi)
		else:
			_core.append(mi)
	for c in n.get_children():
		_collect(c)


func _is_alpha(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


# =====================================================================
#  NHIỆT
# =====================================================================
func _on_vision_changed(mode: int) -> void:
	var thermal := mode == MODE_THERMAL
	for m in _core:
		m.material_override = _hot_core if thermal else null
	for m in _limbs:
		m.material_override = _hot_limb if thermal else null
	for m in _alpha:
		m.visible = not thermal


## hot = false: đã tử vong, nguội dần (xám tối trong Thermal), dừng hoạt ảnh.
func set_hot(hot: bool) -> void:
	_alive = hot
	_hot_core.albedo_color = Color.WHITE if hot else Color(0.18, 0.18, 0.2)
	_hot_limb.albedo_color = Color(0.9, 0.9, 0.9) if hot else Color(0.16, 0.16, 0.18)
	if _anim and not hot:
		_anim.pause()


## Vẽ đè lên vật che (nhiệt xuyên tán cây).
func set_xray(on: bool) -> void:
	_hot_core.no_depth_test = on
	_hot_limb.no_depth_test = on


# =====================================================================
#  NGƯỜI DỰNG BẰNG CODE (dự phòng khi không có model)
# =====================================================================
func _build_procedural(p_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var pants: Color = PANTS[rng.randi() % PANTS.size()]
	var hair: Color = HAIRS[rng.randi() % HAIRS.size()]
	var shoe := Color(0.1, 0.1, 0.12)

	_part(self, _cap(0.15, 0.62), Vector3(0, 1.18, 0), shirt, true, Vector3(1, 1, 0.65))
	_part(self, _cyl(0.05, 0.10), Vector3(0, 1.50, 0), skin, true)
	_part(self, _sph(0.115), Vector3(0, 1.62, 0), skin, true, Vector3(0.9, 1.1, 1.0))
	_part(self, _sph(0.12), Vector3(0, 1.69, 0.01), hair, true, Vector3(1, 0.6, 1.05))
	_part(self, _sph(0.013), Vector3(-0.04, 1.64, -0.10), Color.BLACK, true)
	_part(self, _sph(0.013), Vector3(0.04, 1.64, -0.10), Color.BLACK, true)
	_part(self, _sph(0.02), Vector3(0, 1.605, -0.112), skin.darkened(0.12), true)

	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.2, 1.42, 0.0)
		arm.rotation.z = side * 0.12
		add_child(arm)
		_part(arm, _cap(0.048, 0.32), Vector3(0, -0.14, 0), shirt, false)
		_part(arm, _cap(0.04, 0.32), Vector3(0, -0.40, 0), skin, false)
		_part(arm, _sph(0.045), Vector3(0, -0.58, 0), skin, false)
		if side > 0.0:
			_arm_r = arm

		var leg := Node3D.new()
		leg.position = Vector3(side * 0.09, 0.9, 0.0)
		leg.rotation.z = -side * 0.04
		add_child(leg)
		_part(leg, _cap(0.07, 0.86), Vector3(0, -0.43, 0), pants, false)
		_part(leg, _boxm(Vector3(0.10, 0.07, 0.27)), Vector3(0, -0.89, -0.05), shoe, false)


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, color: Color,
		core: bool, scl := Vector3.ONE) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if core:
		_core.append(mi)
	else:
		_limbs.append(mi)


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 3
	return c


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


func _boxm(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b