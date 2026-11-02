class_name MapEditor
extends Node3D
## Trình tạo map. Camera: giữ chuột phải + WASD, Q/E xuống/lên, Shift nhanh, lăn chuột tiến/lùi.
## Đặt: chuột trái. Xoay: Z/X. Công cụ: 1-5. Lưu: Ctrl+S. F10: về menu.

enum Tool { TREE, HOUSE, VICTIM, GATE, ERASE }

const TOOL_KEYS := ["tree", "house", "victim", "gate"]
const TOOL_TITLES := ["1  Cây (giữ Shift: cả cụm)", "2  Nhà", "3  Nạn nhân", "4  Vòng đua (đặt theo thứ tự)", "5  Xóa"]
const TOOL_COLORS := [Color(0.2, 0.9, 0.3, 0.6), Color(0.9, 0.7, 0.3, 0.6), Color(1.0, 0.5, 0.1, 0.6),
		Color(1.0, 0.3, 0.7, 0.6), Color(1.0, 0.2, 0.2, 0.6)]
const NEED_TITLES := ["Phao cứu sinh (dưới nước)", "Túi y tế (bị thương)", "Đèn tín hiệu (định vị)"]
const NEED_LABELS_3D := ["PHAO", "TUI Y TE", "DEN TIN HIEU"]

@export_file("*.tscn") var menu_scene := "res://res/scenes/main_menu.tscn"
@export_file("*.tscn") var rescue_scene := "res://res/scenes/test_flight.tscn"
@export_file("*.tscn") var race_scene := "res://res/scenes/race_track.tscn"

var data := {}
var _terrain: TerrainGenerator
var _base: HomeBase
var _cam: Camera3D
var _yaw_cam := 0.0
var _pitch := -0.6
var _items: Array = []                 # song song với data["objects"]: {"d": dict, "n": node}
var _gate_nodes: Array[RaceGate] = []
var _tool := Tool.TREE
var _yaw := 0.0
var _hit := Vector3.INF
var _busy := false

var _ghost: Node3D
var _ghost_mat := StandardMaterial3D.new()
var _path_mesh: MeshInstance3D
var _path_mat := StandardMaterial3D.new()

var _tool_btns: Array[Button] = []
var _name_edit: LineEdit
var _seed_box: SpinBox
var _hill_s: HSlider
var _mount_s: HSlider
var _trees_s: HSlider
var _need_opt: OptionButton
var _gate_h: HSlider
var _gate_r: HSlider
var _map_opt: OptionButton
var _status: Label
var _count: Label


func _ready() -> void:
	get_tree().paused = false
	Session.from_editor = true
	if not Session.last_edit.is_empty():
		data = Session.last_edit.duplicate(true)
	_normalize()
	_build_world()
	_build_ui()
	_sync_ui()
	_regenerate.call_deferred()


func _normalize() -> void:
	var defaults := {"name": "map_moi", "seed": 2026, "hill_height": 10.0,
			"mountain_height": 90.0, "tree_count": 1200, "house_count": 0}
	for k in defaults:
		if not data.has(k):
			data[k] = defaults[k]
	if not (data.get("objects") is Array):
		data["objects"] = []


# =====================================================================
#  THẾ GIỚI
# =====================================================================
func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(sun)
	var w := WorldSetup.new()
	w.sun = sun
	add_child(w)

	_cam = Camera3D.new()
	_cam.far = 1500.0
	_cam.position = Vector3(0.0, 70.0, 90.0)
	_cam.rotation = Vector3(_pitch, _yaw_cam, 0.0)
	add_child(_cam)
	_cam.make_current()

	# Dấu đặt (ghost): cầu + mũi tên chỉ hướng xoay
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost = Node3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.4
	sm.material = _ghost_mat
	var s := MeshInstance3D.new()
	s.mesh = sm
	_ghost.add_child(s)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.5
	cm.height = 1.4
	cm.material = _ghost_mat
	var a := MeshInstance3D.new()
	a.mesh = cm
	a.rotation.x = -PI / 2.0              # đầu nhọn chỉ về -Z
	a.position = Vector3(0.0, 0.0, -1.8)
	_ghost.add_child(a)
	_ghost.visible = false
	add_child(_ghost)

	# Đường nối các vòng đua
	_path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_mat.albedo_color = Color(1.0, 0.9, 0.3)
	_path_mesh = MeshInstance3D.new()
	_path_mesh.mesh = ImmediateMesh.new()
	_path_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_mesh)


func _regenerate() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Đang tạo địa hình..."
	await get_tree().process_frame
	await get_tree().process_frame
	for it in _items:
		if is_instance_valid(it["n"]):
			it["n"].queue_free()
	_items.clear()
	if _terrain:
		_terrain.queue_free()
	if _base:
		_base.queue_free()

	_terrain = TerrainGenerator.new()
	_terrain.use_session = false
	_terrain.seed_value = int(data["seed"])
	_terrain.hill_height = float(data["hill_height"])
	_terrain.mountain_height = float(data["mountain_height"])
	_terrain.tree_count = int(data["tree_count"])
	_terrain.house_count = 0
	_terrain.tree_collision = false
	_terrain.cell = 4.0
	add_child(_terrain)

	_base = HomeBase.new()
	_base.terrain = _terrain
	add_child(_base)

	for d in data["objects"]:
		_items.append({"d": d, "n": _spawn(d)})
	_rebuild_gates()
	_busy = false
	_status.text = "Sẵn sàng. Bấm 1-5 chọn công cụ, chuột trái để đặt."
	_update_count()


# =====================================================================
#  ĐỐI TƯỢNG
# =====================================================================
func _spawn(d: Dictionary) -> Node3D:
	var x := float(d["x"])
	var z := float(d["z"])
	var y := _terrain.height_at(x, z)
	match str(d["t"]):
		"tree":
			var n := _make_tree()
			n.position = Vector3(x, y, z)
			add_child(n)
			return n
		"house":
			return _terrain._add_house(Vector3(x, y, z), float(d.get("rot", 0.0)))
		"victim":
			var wet := y < _terrain.water_level + 0.3
			var root := Node3D.new()
			root.position = Vector3(x, _terrain.water_level if wet else y, z)
			var h := HumanFigure.new()
			h.setup(int(d.get("seed", 1)))
			h.waving = true
			h.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			h.position = Vector3(0.0, 0.11, 0.0)
			root.add_child(h)
			var lbl := Label3D.new()
			lbl.text = NEED_LABELS_3D[clampi(int(d.get("need", 1)), 0, 2)]
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.pixel_size = 0.01
			lbl.font_size = 56
			lbl.outline_size = 12
			lbl.modulate = Color(1.0, 0.85, 0.3)
			lbl.position = Vector3(0.0, 2.3, 0.0)
			root.add_child(lbl)
			add_child(root)
			return root
	return null          # vòng đua do _rebuild_gates quản lý


func _make_tree() -> Node3D:
	var root := Node3D.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 2.4
	trunk.radial_segments = 6
	_mi(root, trunk, Vector3(0, 1.2, 0), Color(0.32, 0.21, 0.12), 1.0)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.4
	cone.height = 5.0
	cone.radial_segments = 8
	_mi(root, cone, Vector3(0, 4.1, 0), Color(0.10, 0.33, 0.12), 1.0)
	_mi(root, cone, Vector3(0, 5.95, 0), Color(0.12, 0.36, 0.14), 0.7)
	return root


func _mi(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, color: Color, scl: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = Vector3(scl, scl, scl)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_object(d: Dictionary) -> void:
	data["objects"].append(d)
	_items.append({"d": d, "n": _spawn(d)})
	if d["t"] == "gate":
		_rebuild_gates()
	_update_count()


func _rebuild_gates() -> void:
	for g in _gate_nodes:
		g.queue_free()
	_gate_nodes.clear()
	var list := []
	for d in data["objects"]:
		if d["t"] == "gate":
			list.append(d)
	for i in list.size():
		var d: Dictionary = list[i]
		var x := float(d["x"])
		var z := float(d["z"])
		var ground := maxf(_terrain.height_at(x, z), _terrain.water_level)
		var r := float(d.get("r", 3.0))
		var g := RaceGate.new()
		add_child(g)
		g.global_transform = Transform3D(Basis(Vector3.UP, float(d.get("rot", 0.0))),
				Vector3(x, ground + float(d.get("h", 8.0)), z))
		g.build(r, i, i == list.size() - 1, ground, false)
		g.set_state(RaceGate.GateState.NEXT if i == 0 else RaceGate.GateState.UPCOMING)
		# Mũi tên chỉ hướng bay xuyên qua vòng
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.5
		cm.height = 1.6
		var am := StandardMaterial3D.new()
		am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		am.albedo_color = Color(0.3, 1.0, 0.4)
		cm.material = am
		var arrow := MeshInstance3D.new()
		arrow.mesh = cm
		arrow.rotation.x = -PI / 2.0
		arrow.position = Vector3(0.0, 0.0, -(r + 1.8))
		g.add_child(arrow)
		_gate_nodes.append(g)

	var im := _path_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if not _gate_nodes.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _path_mat)
		im.surface_add_vertex(Vector3(0.0, 3.0, 0.0))        # điểm xuất phát (căn cứ)
		for g in _gate_nodes:
			im.surface_add_vertex(g.global_position)
		im.surface_end()


# =====================================================================
#  ĐẶT / XÓA
# =====================================================================
func _place() -> void:
	if _hit == Vector3.INF or _busy:
		return
	if _tool == Tool.ERASE:
		_erase()
		return
	if _tool == Tool.TREE and Input.is_key_pressed(KEY_SHIFT):
		for i in 8:
			var a := randf() * TAU
			var r := sqrt(randf()) * 9.0
			var x := _hit.x + cos(a) * r
			var z := _hit.z + sin(a) * r
			if _terrain.height_at(x, z) > _terrain.water_level + 0.5:
				_add_object({"t": "tree", "x": snappedf(x, 0.1), "z": snappedf(z, 0.1)})
		return
	var d := {"t": TOOL_KEYS[_tool], "x": snappedf(_hit.x, 0.1), "z": snappedf(_hit.z, 0.1)}
	match _tool:
		Tool.HOUSE:
			d["rot"] = _yaw
		Tool.VICTIM:
			d["need"] = _need_opt.selected
			d["seed"] = randi() % 1000000
		Tool.GATE:
			d["rot"] = _yaw
			d["h"] = _gate_h.value
			d["r"] = _gate_r.value
	_add_object(d)


func _erase() -> void:
	var best := -1
	var best_d := 6.0
	for i in _items.size():
		var d: Dictionary = _items[i]["d"]
		var dist := Vector2(float(d["x"]) - _hit.x, float(d["z"]) - _hit.z).length()
		if dist < best_d:
			best_d = dist
			best = i
	if best < 0:
		return
	var was_gate: bool = str(_items[best]["d"]["t"]) == "gate"
	if is_instance_valid(_items[best]["n"]):
		_items[best]["n"].queue_free()
	data["objects"].remove_at(best)
	_items.remove_at(best)
	if was_gate:
		_rebuild_gates()
	_update_count()


# =====================================================================
#  ĐIỀU KHIỂN
# =====================================================================
func _process(delta: float) -> void:
	_move_camera(delta)
	_update_hit()
	_update_ghost()


func _move_camera(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return                                   # đang gõ tên map
	var b := _cam.global_basis
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_D): dir += b.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	var speed := 45.0 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var p := _cam.global_position + dir.normalized() * speed * delta
	p.x = clampf(p.x, -330.0, 330.0)
	p.z = clampf(p.z, -330.0, 330.0)
	p.y = clampf(p.y, 3.0, 400.0)
	_cam.global_position = p


func _update_hit() -> void:
	_hit = Vector3.INF
	if _busy or _terrain == null or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + _cam.project_ray_normal(mp) * 1500.0, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		_hit = r["position"]


func _update_ghost() -> void:
	_ghost.visible = _hit != Vector3.INF
	if not _ghost.visible:
		return
	var p := _hit
	if _tool == Tool.GATE:
		p.y += _gate_h.value
	_ghost.global_position = p
	_ghost.rotation.y = _yaw
	_ghost_mat.albedo_color = TOOL_COLORS[_tool]
	_ghost.get_child(1).visible = _tool == Tool.HOUSE or _tool == Tool.GATE


func _input(event: InputEvent) -> void:
	# Nhả chuột phải luôn phải trả con trỏ (kể cả khi đang ở trên UI)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_LEFT:
				_place()
			MOUSE_BUTTON_WHEEL_UP:
				_cam.global_position += -_cam.global_basis.z * 10.0
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam.global_position += _cam.global_basis.z * 10.0
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw_cam -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.5, 1.5)
		_cam.rotation = Vector3(_pitch, _yaw_cam, 0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_5:
		_set_tool(k - KEY_1)
	elif k == KEY_Z:
		_yaw -= deg_to_rad(15.0)
	elif k == KEY_X:
		_yaw += deg_to_rad(15.0)
	elif k == KEY_S and event.ctrl_pressed:
		_save()
	elif k == KEY_F10:
		_back()


func _set_tool(i: int) -> void:
	_tool = i as Tool
	_tool_btns[i].button_pressed = true


# =====================================================================
#  GIAO DIỆN
# =====================================================================
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	root.theme = Theme.new()
	root.theme.default_font = sf
	root.theme.default_font_size = 15
	layer.add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 310.0
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(290, 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_label(vb, "TẠO MAP", 24)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Tên map"
	_name_edit.text_changed.connect(func(t: String) -> void: data["name"] = t)
	vb.add_child(_name_edit)

	_label(vb, "Công cụ")
	var grp := ButtonGroup.new()
	for i in TOOL_TITLES.size():
		var b := Button.new()
		b.text = TOOL_TITLES[i]
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tool.bind(i))
		vb.add_child(b)
		_tool_btns.append(b)
	_tool_btns[0].button_pressed = true

	_need_opt = OptionButton.new()
	for t in NEED_TITLES:
		_need_opt.add_item(t)
	_need_opt.selected = 1
	_label(vb, "Nạn nhân cần:")
	vb.add_child(_need_opt)
	_gate_h = _slider(vb, "Vòng: độ cao so với đất (m)", 3.0, 25.0, 0.5, 8.0, func(_v): pass)
	_gate_r = _slider(vb, "Vòng: nửa cạnh (m)", 1.5, 5.0, 0.1, 3.0, func(_v): pass)

	_label(vb, "Địa hình")
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 999999
	_seed_box.prefix = "Seed "
	_seed_box.value_changed.connect(func(v: float) -> void: data["seed"] = int(v))
	vb.add_child(_seed_box)
	_hill_s = _slider(vb, "Đồi (0 = phẳng)", 0.0, 25.0, 0.5, 10.0,
			func(v: float) -> void: data["hill_height"] = v)
	_mount_s = _slider(vb, "Núi (0 = không núi)", 0.0, 120.0, 1.0, 90.0,
			func(v: float) -> void: data["mountain_height"] = v)
	_trees_s = _slider(vb, "Rừng tự mọc (số cây)", 0.0, 2500.0, 50.0, 1200.0,
			func(v: float) -> void: data["tree_count"] = int(v))
	_btn(vb, "Tạo lại địa hình", _regenerate)
	_btn(vb, "Seed ngẫu nhiên", func() -> void:
		data["seed"] = randi() % 999999
		_seed_box.value = data["seed"]
		_regenerate())

	_label(vb, "Tệp")
	_btn(vb, "Lưu map (Ctrl+S)", _save)
	_map_opt = OptionButton.new()
	vb.add_child(_map_opt)
	_btn(vb, "Mở map đã chọn", _load_selected)
	_btn(vb, "Xóa file map đã chọn", _delete_selected)
	_btn(vb, "Map mới (xóa hết)", func() -> void:
		data = {}
		_normalize()
		_sync_ui()
		_regenerate())

	_label(vb, "Chơi thử")
	_btn(vb, "Chơi thử: Cứu hộ", _play.bind(rescue_scene))
	_btn(vb, "Chơi thử: Đua FPV", _play.bind(race_scene))
	_btn(vb, "Về menu (F10)", _back)

	var help := Label.new()
	help.text = "Giữ chuột phải + WASD: bay camera\nQ/E: xuống/lên  |  Shift: nhanh\nLăn chuột: tiến/lùi\nZ/X: xoay vật sắp đặt\nCăn cứ ở gốc tọa độ (cột sáng xanh)."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(280, 0)
	help.modulate = Color(0.75, 0.8, 0.85)
	vb.add_child(help)

	_count = Label.new()
	vb.add_child(_count)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(280, 0)
	_status.modulate = Color(1.0, 0.85, 0.3)
	vb.add_child(_status)


func _label(parent: Control, text: String, fsize := 16) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	parent.add_child(l)


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(parent: Control, title: String, lo: float, hi: float, step: float,
		val: float, on_change: Callable) -> HSlider:
	var l := Label.new()
	l.text = "%s: %s" % [title, str(val)]
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 20)
	s.value_changed.connect(func(v: float) -> void:
		l.text = "%s: %s" % [title, str(snappedf(v, 0.01))]
		on_change.call(v))
	parent.add_child(s)
	return s


func _sync_ui() -> void:
	_name_edit.text = str(data["name"])
	_seed_box.value = float(data["seed"])
	_hill_s.value = float(data["hill_height"])
	_mount_s.value = float(data["mountain_height"])
	_trees_s.value = float(data["tree_count"])
	_refresh_maps()


func _refresh_maps() -> void:
	_map_opt.clear()
	for n in Session.list_maps():
		_map_opt.add_item(n)


func _update_count() -> void:
	var c := {"tree": 0, "house": 0, "victim": 0, "gate": 0}
	for d in data["objects"]:
		var k := str(d["t"])
		c[k] = int(c.get(k, 0)) + 1
	_count.text = "Cây %d | Nhà %d | Nạn nhân %d | Vòng %d" % [c["tree"], c["house"], c["victim"], c["gate"]]


# =====================================================================
#  TỆP + CHƠI THỬ
# =====================================================================
func _commit_name() -> void:
	if str(data["name"]).strip_edges().is_empty():
		data["name"] = "map_moi"
	Session.last_edit = data.duplicate(true)


func _save() -> void:
	_commit_name()
	if Session.save_map(data):
		_status.text = "Đã lưu: " + str(data["name"])
		_refresh_maps()
	else:
		_status.text = "Lưu thất bại!"


func _load_selected() -> void:
	if _map_opt.item_count == 0 or _map_opt.selected < 0:
		return
	var m := Session.load_map(_map_opt.get_item_text(_map_opt.selected))
	if m.is_empty():
		_status.text = "Không đọc được map."
		return
	data = m
	_normalize()
	_sync_ui()
	_regenerate()


func _delete_selected() -> void:
	if _map_opt.item_count == 0 or _map_opt.selected < 0:
		return
	Session.delete_map(_map_opt.get_item_text(_map_opt.selected))
	_refresh_maps()
	_status.text = "Đã xóa file map."


func _play(scene: String) -> void:
	_commit_name()
	Session.map = data.duplicate(true)
	Session.from_editor = true
	get_tree().change_scene_to_file(scene)


func _back() -> void:
	_commit_name()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(menu_scene)