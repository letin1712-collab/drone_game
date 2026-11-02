class_name TerrainGenerator
extends Node3D
## Sinh địa hình bằng code: đồi, núi (vòng biên + 2 đỉnh), sông uốn lượn, rừng, làng.
## Đặt node này tại (0,0,0). Sông chảy dọc theo trục Z.

signal generated

@export_group("Bản đồ")
@export var size := 600.0               # mét, hình vuông
@export var cell := 3.0                 # kích thước ô lưới (nhỏ = chi tiết hơn, nặng hơn)
@export var seed_value := 2026
@export var randomize_seed := false

@export_group("Địa hình")
@export var hill_height := 10.0
@export var mountain_height := 90.0
@export_range(0.3, 0.9) var mountain_start := 0.55   # núi bắt đầu từ 55% bán kính
@export var water_level := 0.0
@export var base_height := 2.0                       # độ cao khu căn cứ
@export var village_center := Vector2(-120.0, 80.0)  # (x, z)
@export var village_height := 3.0

@export_group("Rừng")
@export var tree_count := 2500
@export var tree_collision := true
@export var tree_shadows := false

@export_group("Làng")
@export var house_count := 9

@export var use_session := true               # true: đọc map từ Session (chế độ chơi)
var custom_trees := PackedVector2Array()      # cây người chơi đặt (x, z)
var custom_houses: Array[Vector3] = []        # nhà người chơi đặt (x, yaw, z)

const GRID := 20.0
const POOL := 48                              # số collider cây hoạt động cùng lúc
var _grid := {}
var _pool: Array[StaticBody3D] = []
var _pool_timer := 0.0
var _target: Node3D

var tree_positions := PackedVector3Array()   # Mission dùng để giấu nạn nhân dưới tán cây

var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if use_session:
		_apply_session()
	if randomize_seed:
		seed_value = randi()
	_hills.seed = seed_value
	_hills.frequency = 0.006
	_ridges.seed = seed_value + 1
	_ridges.frequency = 0.004
	_forest.seed = seed_value + 2
	_forest.frequency = 0.012
	_rng.seed = seed_value

	_build_terrain()
	_build_water()
	_scatter_trees()
	_build_tree_grid()
	_build_village()
	_build_custom_houses()
	generated.emit()


func _apply_session() -> void:
	var s := get_node_or_null("/root/Session")
	if s == null:
		return
	cell = s.cell_size[s.quality]
	var mult: float = s.tree_mult[s.quality]
	var m: Dictionary = s.map
	if m.is_empty():
		tree_count = int(tree_count * mult)
		return
	seed_value = int(m.get("seed", seed_value))
	hill_height = float(m.get("hill_height", hill_height))
	mountain_height = float(m.get("mountain_height", mountain_height))
	tree_count = int(float(m.get("tree_count", 1200)) * mult)
	house_count = int(m.get("house_count", 0))
	for o in m.get("objects", []):
		match str(o.get("t", "")):
			"tree":
				custom_trees.append(Vector2(float(o["x"]), float(o["z"])))
			"house":
				custom_houses.append(Vector3(float(o["x"]), float(o.get("rot", 0.0)), float(o["z"])))


func _build_custom_houses() -> void:
	for h in custom_houses:
		_add_house(Vector3(h.x, height_at(h.x, h.z), h.z), h.y)


# =====================================================================
#  HÀM ĐỘ CAO (dùng chung cho mesh, đặt cây, đặt nhà, đặt nạn nhân)
# =====================================================================
## Đường tâm của sông theo z: tổng hai sóng sin để sông uốn lượn.
func river_x(z: float) -> float:
	return 110.0 + sin(z * 0.012) * 50.0 + sin(z * 0.031 + 1.3) * 12.0


func height_at(x: float, z: float) -> float:
	var half := size * 0.5

	# 1) Đồi: nền 4 m + nhiễu fBm, không cho thấp hơn 0.8 để tránh ao ngoài ý muốn
	var h := maxf(4.0 + _hills.get_noise_2d(x, z) * hill_height, 0.8)

	# 2) Núi: vòng quanh biên bản đồ, độ cao nhân với nhiễu "ridge" (1 - |n|) cho sống núi
	var ridge := 1.0 - absf(_ridges.get_noise_2d(x, z))
	var edge := maxf(absf(x), absf(z)) / half                  # 0 ở giữa, 1 ở biên
	h += smoothstep(mountain_start, 1.0, edge) * mountain_height * (0.4 + 0.6 * ridge)

	# 3) Hai đỉnh núi riêng: Gaussian  H·exp(-d²/2σ²), tỉ lệ theo thanh "Núi" của editor
	var peak_k := mountain_height / 90.0
	h += _peak(x, z, Vector2(-150.0, -120.0), 75.0, 55.0) * (0.75 + 0.5 * ridge) * peak_k
	h += _peak(x, z, Vector2(-40.0, 190.0), 60.0, 45.0) * (0.75 + 0.5 * ridge) * peak_k

	# 4) Làm phẳng khu căn cứ và khu làng (nội suy về độ cao mục tiêu)
	h = _flatten(h, x, z, Vector2.ZERO, 28.0, 75.0, base_height)
	h = _flatten(h, x, z, village_center, 45.0, 95.0, village_height)

	# 5) Đào lòng sông: càng gần tâm sông càng bị kéo xuống đáy (thấp hơn mực nước 2.2 m)
	var dx := absf(x - river_x(z))
	var channel := 1.0 - smoothstep(7.0, 30.0, dx)
	var bed := water_level - 2.2 + dx * 0.12
	return lerpf(h, minf(h, bed), channel)
	


func _peak(x: float, z: float, c: Vector2, height: float, sigma: float) -> float:
	var d2 := (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y)
	return height * exp(-d2 / (2.0 * sigma * sigma))


func _flatten(h: float, x: float, z: float, c: Vector2, r_in: float, r_out: float, target: float) -> float:
	var t := 1.0 - smoothstep(r_in, r_out, Vector2(x - c.x, z - c.y).length())
	return lerpf(h, target, t)


# =====================================================================
#  MESH ĐỊA HÌNH + VA CHẠM
# =====================================================================
func _build_terrain() -> void:
	var n := int(size / cell)
	var stride := n + 1
	var half := size * 0.5

	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	for iz in stride:
		for ix in stride:
			heights[iz * stride + ix] = height_at(-half + ix * cell, -half + iz * cell)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in stride:
		for ix in stride:
			var x := -half + ix * cell
			var z := -half + iz * cell
			var h := heights[iz * stride + ix]
			# Pháp tuyến từ gradient: n ∝ (-dh/dx, 1, -dh/dz), sai phân trung tâm
			var hl := heights[iz * stride + maxi(ix - 1, 0)]
			var hr := heights[iz * stride + mini(ix + 1, n)]
			var hu := heights[maxi(iz - 1, 0) * stride + ix]
			var hd := heights[mini(iz + 1, n) * stride + ix]
			var normal := Vector3(hl - hr, 2.0 * cell, hu - hd).normalized()
			st.set_normal(normal)
			st.set_color(_terrain_color(x, z, h, normal.y))
			st.add_vertex(Vector3(x, h, z))

	# Thứ tự đỉnh theo chiều kim đồng hồ khi nhìn từ trên xuống (mặt trước của Godot)
	for iz in n:
		for ix in n:
			var a := iz * stride + ix
			var b := a + 1
			var c := a + stride
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)

	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true   # an toàn: drone không bao giờ lọt xuống dưới đất
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Màu theo độ cao và độ dốc: cát ven nước, cỏ, cỏ khô, đá (dốc đứng), tuyết (rất cao).
func _terrain_color(x: float, z: float, h: float, ny: float) -> Color:
	var v := _hills.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5
	var c := Color(0.25, 0.43, 0.17).lerp(Color(0.38, 0.54, 0.22), v)
	c = c.lerp(Color(0.45, 0.40, 0.27), smoothstep(18.0, 40.0, h))
	c = c.lerp(Color(0.70, 0.62, 0.42), 1.0 - smoothstep(water_level + 0.2, water_level + 1.6, h))
	var rock := smoothstep(0.22, 0.42, 1.0 - ny)
	c = c.lerp(Color(0.43, 0.41, 0.39), rock)
	var snow := smoothstep(62.0, 82.0, h) * (1.0 - rock * 0.5)
	return c.lerp(Color(0.95, 0.96, 1.0), snow)


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.position = Vector3(0.0, water_level, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.35, 0.55, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic = 0.3
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# =====================================================================
#  RỪNG (MultiMesh: hàng nghìn cây chỉ tốn vài draw call)
# =====================================================================
func _scatter_trees() -> void:
	var half := size * 0.5 - 10.0
	var pos := PackedVector3Array()
	var scl := PackedFloat32Array()

	for c in custom_trees:                       # cây do người chơi đặt
		pos.append(Vector3(c.x, height_at(c.x, c.y), c.y))
		scl.append(_rng.randf_range(0.9, 1.3))

	var target := pos.size() + tree_count
	var attempts := 0
	while pos.size() < target and attempts < tree_count * 15:
		attempts += 1
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		if Vector2(x, z).length() < 45.0:
			continue
		if Vector2(x - village_center.x, z - village_center.y).length() < 60.0:
			continue
		if absf(x - river_x(z)) < 22.0:
			continue
		var h := height_at(x, z)
		if h < 1.5 or h > 42.0:
			continue
		var slope := absf(height_at(x + 2.0, z) - h) + absf(height_at(x, z + 2.0) - h)
		if slope > 2.4:
			continue
		var f := _forest.get_noise_2d(x, z) * 0.5 + 0.5
		if _rng.randf() > smoothstep(0.45, 0.7, f):
			continue
		pos.append(Vector3(x, h, z))
		scl.append(_rng.randf_range(0.8, 1.4))

	tree_positions = pos
	if pos.is_empty():
		return

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 2.4
	cone_mesh.height = 5.0
	cone_mesh.radial_segments = 8
	cone_mesh.rings = 1

	var trunks := _make_multimesh(trunk_mesh, pos.size())
	var crowns := _make_multimesh(cone_mesh, pos.size() * 2)

	for i in pos.size():
		var p := pos[i]
		var s := scl[i]
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		trunks.multimesh.set_instance_transform(i, Transform3D(b, p + Vector3(0, 1.2 * s, 0)))
		trunks.multimesh.set_instance_color(i, Color(0.32, 0.21, 0.12))
		var tint := _rng.randf_range(-0.05, 0.05)
		var green := Color(0.10 + tint, 0.33 + tint, 0.12 + tint)
		crowns.multimesh.set_instance_transform(i * 2, Transform3D(b, p + Vector3(0, 4.1 * s, 0)))
		crowns.multimesh.set_instance_color(i * 2, green)
		var b2 := b.scaled(Vector3(0.7, 0.7, 0.7))
		crowns.multimesh.set_instance_transform(i * 2 + 1, Transform3D(b2, p + Vector3(0, 5.95 * s, 0)))
		crowns.multimesh.set_instance_color(i * 2 + 1, green.lightened(0.08))

	if tree_collision:
		_make_tree_pool()


# ---------- Lưới không gian: tìm cây gần một điểm rất nhanh ----------
func _build_tree_grid() -> void:
	_grid.clear()
	for p in tree_positions:
		var k := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(p)


func trees_near(x: float, z: float, r: float) -> Array:
	var out := []
	var r2 := r * r
	for gx in range(floori((x - r) / GRID), floori((x + r) / GRID) + 1):
		for gz in range(floori((z - r) / GRID), floori((z + r) / GRID) + 1):
			var bucket = _grid.get(Vector2i(gx, gz))
			if bucket == null:
				continue
			for p: Vector3 in bucket:
				var dx := p.x - x
				var dz := p.z - z
				if dx * dx + dz * dz <= r2:
					out.append(p)
	return out


# ---------- Va chạm cây theo vùng quanh drone ----------
# Thay vì 2500 collider cố định (gây cảnh báo Jolt và tốn CPU), chỉ giữ POOL collider
# và dời chúng tới các cây gần drone nhất, cập nhật mỗi 0,2 giây.
func _make_tree_pool() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 8.0
	for i in POOL:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.position = Vector3(0, -1000, 0)
		add_child(body)
		_pool.append(body)


func _physics_process(delta: float) -> void:
	if _pool.is_empty():
		return
	_pool_timer -= delta
	if _pool_timer > 0.0:
		return
	_pool_timer = 0.2
	if _target == null:
		_target = get_tree().get_first_node_in_group("drone") as Node3D
		if _target == null:
			return
	var c := _target.global_position
	var near := trees_near(c.x, c.z, 25.0)
	for i in POOL:
		var p := Vector3(0, -1000, 0)
		if i < near.size():
			var t: Vector3 = near[i]
			p = Vector3(t.x, t.y + 4.0, t.z)
		if _pool[i].position != p:
			_pool[i].position = p


func _make_multimesh(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true            # phải bật TRƯỚC khi đặt instance_count
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	inst.material_override = mat
	if not tree_shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


# =====================================================================
#  LÀNG: nhà dựng bằng hộp + lăng trụ (mái)
# =====================================================================
func _build_village() -> void:
	for i in house_count:
		# Hai vòng: vòng trong (i chẵn) và vòng ngoài (i lẻ) để nhà không chồng nhau
		var ang := TAU * float(i) / float(house_count) + _rng.randf_range(-0.2, 0.2)
		var r := _rng.randf_range(18.0, 24.0) if i % 2 == 0 else _rng.randf_range(36.0, 44.0)
		var x := village_center.x + cos(ang) * r
		var z := village_center.y + sin(ang) * r
		_add_house(Vector3(x, height_at(x, z), z), _rng.randf() * TAU)


func _add_house(p: Vector3, yaw: float) -> StaticBody3D:
	var w := _rng.randf_range(6.0, 9.0)
	var d := _rng.randf_range(5.0, 7.0)
	var wh := _rng.randf_range(2.8, 3.4)

	var wall_colors := [Color(0.85, 0.8, 0.7), Color(0.8, 0.72, 0.6), Color(0.7, 0.75, 0.8), Color(0.88, 0.85, 0.78)]
	var roof_colors := [Color(0.6, 0.2, 0.15), Color(0.35, 0.25, 0.2), Color(0.3, 0.32, 0.35)]
	var wall_col: Color = wall_colors[_rng.randi() % wall_colors.size()]
	var roof_col: Color = roof_colors[_rng.randi() % roof_colors.size()]

	var root := StaticBody3D.new()
	root.position = p
	root.rotation.y = yaw
	add_child(root)

	_box(root, Vector3(w + 0.2, 1.5, d + 0.2), Vector3(0, -0.65, 0), Color(0.4, 0.4, 0.4))   # móng nhà
	_box(root, Vector3(w, wh, d), Vector3(0, wh * 0.5, 0), wall_col)                          # tường

	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.8, 2.0, d + 0.8)
	roof.mesh = pm
	roof.position = Vector3(0, wh + 1.0, 0)
	roof.material_override = _flat_mat(roof_col)
	root.add_child(roof)

	_box(root, Vector3(1.1, 2.0, 0.1), Vector3(0, 1.0, d * 0.5 + 0.02), Color(0.35, 0.22, 0.12))          # cửa
	_box(root, Vector3(1.0, 0.9, 0.1), Vector3(-w * 0.28, 1.7, d * 0.5 + 0.02), Color(0.55, 0.75, 0.9))   # cửa sổ
	_box(root, Vector3(1.0, 0.9, 0.1), Vector3(w * 0.28, 1.7, d * 0.5 + 0.02), Color(0.55, 0.75, 0.9))
	_box(root, Vector3(0.5, 1.9, 0.5), Vector3(w * 0.25, wh + 1.5, -d * 0.15), Color(0.45, 0.42, 0.4))    # ống khói

	# Va chạm: khối tường + khối mái (xấp xỉ)
	var c1 := CollisionShape3D.new()
	var s1 := BoxShape3D.new()
	s1.size = Vector3(w, wh, d)
	c1.shape = s1
	c1.position = Vector3(0, wh * 0.5, 0)
	root.add_child(c1)
	var c2 := CollisionShape3D.new()
	var s2 := BoxShape3D.new()
	s2.size = Vector3(w * 0.55, 1.6, d + 0.8)
	c2.shape = s2
	c2.position = Vector3(0, wh + 0.8, 0)
	root.add_child(c2)
	return root


func _box(parent: Node3D, sz: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	mi.material_override = _flat_mat(color)
	parent.add_child(mi)


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m