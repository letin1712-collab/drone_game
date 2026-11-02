class_name MainMenu
extends Control
## Menu chính: chế độ chơi, chọn map, tạo map, chất lượng đồ họa.

@export_file("*.tscn") var rescue_scene := "res://res/scenes/test_flight.tscn"
@export_file("*.tscn") var race_scene := "res://res/scenes/race_track.tscn"
@export_file("*.tscn") var editor_scene := "res://res/scenes/map_editor.tscn"

var _status: Label
var _map_opt: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	DroneInput.set_flight_mode(DroneInputData.FlightMode.ANGLE)
	Session.editor_scene = editor_scene

	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	theme = Theme.new()
	theme.default_font = sf
	theme.default_font_size = 18

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(580, 0)
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)

	var title := Label.new()
	title.text = "DRONE SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vb.add_child(title)

	# Chọn map
	var row := HBoxContainer.new()
	vb.add_child(row)
	var ml := Label.new()
	ml.text = "Map:"
	row.add_child(ml)
	_map_opt = OptionButton.new()
	_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_opt.add_item("Ngẫu nhiên (mặc định)")
	for n in Session.list_maps():
		_map_opt.add_item(n)
	row.add_child(_map_opt)

	var b1 := _mode_button(vb, "CỨU HỘ CỨU NẠN",
			"Tìm nạn nhân bằng camera nhiệt, thả vật phẩm, bay về căn cứ", rescue_scene)
	_mode_button(vb, "ĐUA FPV", "Bay qua các vòng phát sáng, về đích nhanh nhất", race_scene)
	_mode_button(vb, "TẠO MAP", "Tự đặt cây, nhà, nạn nhân, vòng đua rồi chơi thử", editor_scene, true)

	# Chất lượng đồ họa
	var qrow := HBoxContainer.new()
	vb.add_child(qrow)
	var ql := Label.new()
	ql.text = "Đồ họa:"
	qrow.add_child(ql)
	var qo := OptionButton.new()
	qo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qo.add_item("Thấp (máy yếu)")
	qo.add_item("Vừa")
	qo.add_item("Cao")
	qo.selected = Session.quality
	qo.item_selected.connect(func(i: int) -> void: Session.set_quality(i))
	qrow.add_child(qo)

	var quit := Button.new()
	quit.text = "Thoát"
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1.0, 0.6, 0.4)
	vb.add_child(_status)

	var hint := Label.new()
	hint.text = "↑↓ + Enter, chuột, hoặc tay cầm  |  F11: toàn màn hình"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.55, 0.6, 0.65)
	vb.add_child(hint)

	b1.grab_focus.call_deferred()


func _mode_button(parent: Control, title: String, desc: String, path: String, is_editor := false) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [title, desc]
	b.custom_minimum_size = Vector2(0, 80)
	b.pressed.connect(_go.bind(path, is_editor))
	parent.add_child(b)
	return b


func _go(path: String, is_editor := false) -> void:
	if not ResourceLoader.exists(path):
		_status.text = "Không tìm thấy scene: " + path
		return
	Session.from_editor = false
	if not is_editor:
		if _map_opt.selected <= 0:
			Session.map = {}
		else:
			Session.map = Session.load_map(_map_opt.get_item_text(_map_opt.selected))
	get_tree().change_scene_to_file(path)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN