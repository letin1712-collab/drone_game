class_name GuidePanel
extends Control
## Nút "? Hướng dẫn" + bảng hướng dẫn. F1 / Esc / nút Back (tay cầm) để bật/tắt.

@export var show_on_start := true
@export var pause_while_open := true

const GUIDE_TEXT := """[color=#ffd84d]MỤC TIÊU[/color]
Tìm các nạn nhân trong vùng tìm kiếm, thả đúng vật phẩm cứu hộ xuống gần họ (trong khoảng 7 m), rồi bay về căn cứ (bãi H có cột sáng xanh) và hạ cánh. Mỗi nạn nhân có thanh tình trạng giảm dần theo thời gian, về 0 là không thể cứu.

[color=#ffd84d]ĐIỀU KHIỂN BAY[/color]
Bàn phím:  W/S ga lên/xuống  |  A/D xoay mũi  |  ↑/↓ chúi/ngả  |  ←/→ nghiêng trái/phải
Tay cầm:  cần trái = ga + xoay mũi  |  cần phải = chúi/nghiêng
M hoặc D-Pad ↑:  đổi chế độ Angle (tự cân bằng) và Acro (thủ công như FPV thật)
R:  chơi lại, nạn nhân được tạo ngẫu nhiên ở vị trí mới

[color=#ffd84d]CAMERA & CẢM BIẾN[/color]
C hoặc D-Pad →:  đổi góc nhìn FPV và TPV
V hoặc D-Pad ←:  đổi Thường, Nhiệt (Thermal), Nhìn đêm
Giữ nạn nhân trong khung hình (không bị che) khoảng 1 giây để khóa mục tiêu. Camera nhiệt nhìn xa nhất và xuyên được tán cây, nên nạn nhân trong rừng chỉ phát hiện được bằng chế độ này.

[color=#ffd84d]VẬT PHẨM CỨU HỘ[/color]
Tab hoặc RB:  chọn vật phẩm   |   Space hoặc A:  thả
Phao cứu sinh:  cho nạn nhân dưới nước
Túi y tế:  cho nạn nhân bị thương
Đèn tín hiệu:  giúp đội cứu hộ định vị nạn nhân
Mỗi nạn nhân chỉ cần một loại, xem bảng nhiệm vụ bên trái sau khi phát hiện. Thả sai loại sẽ không cứu được. Hết vật phẩm hoặc yếu pin: hạ cánh vào bãi H để nạp lại đầy đủ và sạc pin.

[color=#ffd84d]MẸO[/color]
Mang nhiều hàng thì pin hao nhanh hơn. Gió giật đẩy drone trôi nên thả hàng khi bay thấp và chậm. Dưới 15% pin lực đẩy giảm, hãy về căn cứ sớm.
Thời tiết thay đổi mỗi lượt chơi: mưa, bão và sương mù làm giảm tầm nhìn, gió mạnh và drone rung hơn. Nên dùng camera nhiệt khi tầm nhìn kém. F2: đổi thời tiết để thử.
F10: về menu chính."""

var _dim: ColorRect
var _button: Button
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # vẫn nhận input khi game tạm dừng
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	theme = Theme.new()
	theme.default_font = sf
	theme.default_font_size = 16

	# Nút luôn hiển thị, bên trái la bàn (neo giữa-trên)
	_button = Button.new()
	_button.text = "?  Hướng dẫn [F1]"
	_button.focus_mode = Control.FOCUS_NONE          # tránh Space kích hoạt nút
	_button.anchor_left = 0.5
	_button.anchor_right = 0.5
	_button.offset_left = -390.0
	_button.offset_right = -240.0
	_button.offset_top = 10.0
	_button.offset_bottom = 40.0
	_button.pressed.connect(open_guide)
	add_child(_button)

	# Nền mờ + bảng
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.65)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var title := Label.new()
	title.text = _guide_title()
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.custom_minimum_size = Vector2(0, 340)
	rt.text = _guide_text()
	vb.add_child(rt)

	var close := Button.new()
	close.text = "Đóng  [F1 / Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_guide)
	vb.add_child(close)

	if show_on_start:
		open_guide.call_deferred()


func open_guide() -> void:
	_open = true
	_dim.visible = true
	_button.visible = false
	if pause_while_open:
		get_tree().paused = true


func close_guide() -> void:
	_open = false
	_dim.visible = false
	_button.visible = true
	get_tree().paused = false


func toggle() -> void:
	if _open:
		close_guide()
	else:
		open_guide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE and _open:
			close_guide()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_BACK:
		toggle()

func _guide_title() -> String:
	return "HƯỚNG DẪN - DRONE CỨU HỘ"


func _guide_text() -> String:
	return GUIDE_TEXT