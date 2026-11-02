class_name SceneNav
extends Node
## F4: bảng FPS | F10: về menu (hoặc về editor nếu đang chơi thử) | F11: toàn màn hình

@export_file("*.tscn") var menu_scene := "res://res/scenes/main_menu.tscn"

var _label: Label
var _acc := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.offset_left = 8.0
	_label.offset_top = -26.0
	_label.add_theme_font_size_override("font_size", 13)
	_label.visible = false
	layer.add_child(_label)


func _process(delta: float) -> void:
	if not _label.visible:
		return
	_acc += delta
	if _acc < 0.5:
		return
	_acc = 0.0
	_label.text = "FPS %d | Draw %d | Tri %dk | Phys %d obj | %.1f ms" % [
		int(Engine.get_frames_per_second()),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F4:
			_label.visible = not _label.visible
		KEY_F10:
			get_tree().paused = false
			var target := Session.editor_scene if Session.from_editor else menu_scene
			get_tree().change_scene_to_file(target)
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN