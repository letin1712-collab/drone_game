class_name HeatSource
extends MeshInstance3D
## Bình thường là mesh thường. Ở chế độ Thermal chuyển thành trắng sáng (unshaded)
## để shader hiểu là "nóng". set_xray(true): vẽ đè lên vật che (nhiệt xuyên tán cây).

const MODE_THERMAL := 1  # trùng VisionPostProcess.Vision.THERMAL

var _hot_mat := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("heat_sources")
	_hot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hot_mat.albedo_color = Color.WHITE
	_hot_mat.render_priority = 10
	var vp = get_tree().get_first_node_in_group("vision_post")
	if vp:
		vp.vision_changed.connect(_on_vision_changed)
		_on_vision_changed(vp.current)


func _on_vision_changed(mode: int) -> void:
	material_override = _hot_mat if mode == MODE_THERMAL else null


## hot = false: vật nguội (nạn nhân đã chết) hiện xám tối trong Thermal.
func set_hot(hot: bool) -> void:
	_hot_mat.albedo_color = Color.WHITE if hot else Color(0.18, 0.18, 0.2)


func set_xray(on: bool) -> void:
	_hot_mat.no_depth_test = on