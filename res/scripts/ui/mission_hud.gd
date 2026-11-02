class_name MissionHUD
extends Control
## HUD nhiệm vụ: đồng hồ, danh sách nạn nhân, thẻ vật phẩm, mũi tên về căn cứ,
## marker trên màn hình, thông báo và màn hình kết quả.

@export var drone: DroneController
@export var mission: MissionManager
@export var payload: PayloadSystem
@export var color := Color(0.6, 1.0, 0.7)

const CARD_W := 250.0
const CARD_H := 58.0
const CARD_STEP := 66.0

var _font: Font
var _cam: Camera3D
var _toasts: Array = []
var _redraw_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Font hệ thống (Segoe UI/Arial...) để hiển thị đúng dấu tiếng Việt
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	_font = sf
	_cam = get_tree().get_first_node_in_group("drone_camera") as Camera3D
	if mission:
		mission.message.connect(_push_toast)
	if payload:
		payload.message.connect(_push_toast)


func _push_toast(text: String, col: Color) -> void:
	_toasts.append({"text": text, "color": col, "t": 5.0})
	if _toasts.size() > 4:
		_toasts.pop_front()


func _process(delta: float) -> void:
	for t in _toasts:
		t["t"] -= delta
	_toasts = _toasts.filter(func(t): return t["t"] > 0.0)
	_redraw_t += delta
	if _redraw_t >= 1.0 / 30.0:
		_redraw_t = 0.0
		queue_redraw()


func _draw() -> void:
	if drone == null or mission == null or payload == null:
		return
	var s := size
	_draw_markers()
	_draw_mission_panel()
	_draw_payload_cards(s)
	_draw_home_arrow(s)
	_draw_empty_warning(s)
	_draw_toasts(s)
	if mission.state != MissionManager.State.ACTIVE:
		_draw_result(s)


func _text(pos: Vector2, txt: String, fsize := 16, align := HORIZONTAL_ALIGNMENT_LEFT,
		col := Color.TRANSPARENT, w := 300.0) -> void:
	var c := color if col.a == 0.0 else col
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	draw_string(_font, p + Vector2(1, 1), txt, align, w, fsize, Color(0, 0, 0, 0.7))
	draw_string(_font, p, txt, align, w, fsize, c)


# ---------------- Marker trên màn hình ----------------
func _draw_markers() -> void:
	if _cam == null:
		return
	for v in mission.victims:
		if v.state == Victim.State.DEAD:
			continue
		var p := v.global_position + Vector3(0.0, 1.2, 0.0)
		if _cam.is_position_behind(p):
			continue
		var sp := _cam.unproject_position(p)
		var dist := _cam.global_position.distance_to(p)

		if v.state == Victim.State.UNKNOWN:
			if v.scan_progress > 0.0:      # vòng khóa mục tiêu
				draw_arc(sp, 22.0, -PI * 0.5, -PI * 0.5 + TAU * v.scan_progress, 32,
						Color(1.0, 0.85, 0.3), 3.0)
			continue

		var col := Color(1.0, 0.85, 0.3) if v.state == Victim.State.DETECTED else Color(0.4, 1.0, 0.5)
		draw_polyline(PackedVector2Array([
			sp + Vector2(0, -14), sp + Vector2(14, 0), sp + Vector2(0, 14),
			sp + Vector2(-14, 0), sp + Vector2(0, -14)]), col, 2.0)
		_text(sp + Vector2(0, -24), "%s  %dm" % [v.victim_name, int(dist)], 14,
				HORIZONTAL_ALIGNMENT_CENTER, col, 400.0)
		if v.state == Victim.State.DETECTED:
			_text(sp + Vector2(0, 34), "Tình trạng %d%%" % int(v.condition), 14,
					HORIZONTAL_ALIGNMENT_CENTER, col)


# ---------------- Bảng nhiệm vụ (trái) ----------------
func _draw_mission_panel() -> void:
	var tl := int(ceilf(mission.time_left))
	var tcol := color
	if mission.time_left < 60.0:
		tcol = Color(1.0, 0.85, 0.2)
	if mission.time_left < 30.0:
		tcol = Color(1.0, 0.3, 0.25) if int(Time.get_ticks_msec() / 250.0) % 2 == 0 else Color(0.6, 0.15, 0.1)
	_text(Vector2(24, 84), "CÒN LẠI %02d:%02d" % [floori(tl / 60.0), tl % 60], 22,
			HORIZONTAL_ALIGNMENT_LEFT, tcol)
	_text(Vector2(24, 108), "ĐIỂM %d     ĐÃ CỨU %d/%d" % [int(mission.rescue_points),
			mission.rescued_count, mission.victims.size()], 14)

	var y := 140.0
	for v in mission.victims:
		var line := ""
		var col := color
		match v.state:
			Victim.State.UNKNOWN:
				line = "TÍN HIỆU ???"
				col = Color(0.7, 0.7, 0.7)
				if v.scan_progress > 0.0:
					line = "ĐANG QUÉT %d%%" % int(v.scan_progress * 100.0)
			Victim.State.DETECTED:
				line = "%s - cần %s" % [v.victim_name, Victim.NEED_NAMES_VI[v.need]]
				col = Color(1.0, 0.85, 0.3)
			Victim.State.RESCUED:
				line = "%s - đã an toàn" % v.victim_name
				col = Color(0.4, 1.0, 0.5)
			Victim.State.DEAD:
				line = "%s - đã mất" % v.victim_name
				col = Color(1.0, 0.3, 0.3)
		_text(Vector2(24, y), line, 14, HORIZONTAL_ALIGNMENT_LEFT, col, 340.0)

		if v.state == Victim.State.DETECTED:
			var c := v.condition / 100.0
			var bc := Color(0.3, 1.0, 0.4)
			if c < 0.5:
				bc = Color(1.0, 0.85, 0.2)
			if c < 0.25:
				bc = Color(1.0, 0.25, 0.2)
			draw_rect(Rect2(24, y + 6, 150, 8), color, false, 1.5)
			draw_rect(Rect2(25, y + 7, 148.0 * c, 6), bc)
		y += 40.0


# ---------------- Thẻ vật phẩm (phải) ----------------
func _draw_payload_cards(s: Vector2) -> void:
	_text(Vector2(s.x - 24.0, 80.0), "KHO HÀNG   [Tab] đổi   [Space] thả", 14,
			HORIZONTAL_ALIGNMENT_RIGHT, Color.TRANSPARENT, 400.0)
	var x := s.x - 24.0 - CARD_W
	for i in 3:
		var y := 92.0 + i * CARD_STEP
		var sel := i == payload.selected
		var empty := payload.stock[i] <= 0
		var rect := Rect2(x, y, CARD_W, CARD_H)
		draw_rect(rect, Color(0, 0, 0, 0.55))
		draw_rect(rect, Color(1.0, 0.9, 0.3) if sel else Color(color, 0.45), false,
				3.0 if sel else 1.5)
		if sel:   # mũi tên chỉ thẻ đang chọn
			var m := Vector2(x - 8.0, y + CARD_H * 0.5)
			draw_colored_polygon(PackedVector2Array([
				m, m + Vector2(-12, -8), m + Vector2(-12, 8)]), Color(1.0, 0.9, 0.3))

		_draw_item_icon(i, Vector2(x + 26.0, y + CARD_H * 0.5))

		var name_col := Color(1.0, 0.9, 0.3) if sel else color
		if empty:
			name_col = Color(0.8, 0.4, 0.4)
		_text(Vector2(x + 52.0, y + 24.0), Victim.NEED_NAMES_VI[i], 17,
				HORIZONTAL_ALIGNMENT_LEFT, name_col, 170.0)
		_text(Vector2(x + CARD_W - 12.0, y + 26.0), "x%d" % payload.stock[i], 20,
				HORIZONTAL_ALIGNMENT_RIGHT, name_col, 60.0)
		var hint: String = "HẾT - về căn cứ để nạp" if empty else Victim.NEED_HINTS_VI[i]
		_text(Vector2(x + 52.0, y + 46.0), hint, 12, HORIZONTAL_ALIGNMENT_LEFT,
				Color(0.85, 0.85, 0.85), 190.0)


func _draw_item_icon(i: int, c: Vector2) -> void:
	match i:
		0:   # phao: vòng cam
			draw_arc(c, 11.0, 0.0, TAU, 24, Color(0.95, 0.4, 0.1), 5.0)
		1:   # túi y tế: hộp trắng, chữ thập đỏ
			draw_rect(Rect2(c - Vector2(12, 9), Vector2(24, 18)), Color(0.95, 0.95, 0.95))
			draw_rect(Rect2(c - Vector2(2, 7), Vector2(4, 14)), Color(0.85, 0.1, 0.1))
			draw_rect(Rect2(c - Vector2(7, 2), Vector2(14, 4)), Color(0.85, 0.1, 0.1))
		_:   # đèn tín hiệu: ống đỏ, đầu sáng
			draw_line(c + Vector2(0, 11), c + Vector2(0, -8), Color(1.0, 0.2, 0.15), 5.0)
			draw_circle(c + Vector2(0, -12), 3.5, Color(1.0, 0.85, 0.3))


func _draw_empty_warning(s: Vector2) -> void:
	if mission.state != MissionManager.State.ACTIVE:
		return
	if payload.stock[0] + payload.stock[1] + payload.stock[2] > 0:
		return
	var a := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
	_text(Vector2(s.x * 0.5, s.y - 130.0),
			"HẾT VẬT PHẨM - hạ cánh ở căn cứ (bãi H) để nạp lại và sạc pin", 18,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.3, a), 900.0)


# ---------------- Mũi tên về căn cứ (bên phải la bàn) ----------------
func _draw_home_arrow(s: Vector2) -> void:
	if mission.home == null:
		return
	var to := mission.home.global_position - drone.global_position
	var fwd := -drone.global_basis.z
	var rel := atan2(to.x, -to.z) - atan2(fwd.x, -fwd.z)
	var c := Vector2(s.x * 0.5 + 260.0, 40.0)
	var dir := Vector2(sin(rel), -cos(rel))
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		c + dir * 14.0, c - dir * 8.0 + side * 8.0, c - dir * 8.0 - side * 8.0]), color)
	_text(c + Vector2(0, 34), "CĂN CỨ %dm" % int(Vector2(to.x, to.z).length()), 14,
			HORIZONTAL_ALIGNMENT_CENTER)


# ---------------- Thông báo (giữa, dưới tâm ngắm) + kết quả ----------------
func _draw_toasts(s: Vector2) -> void:
	var y := s.y * 0.5 + 80.0
	for t in _toasts:
		var a := clampf(t["t"], 0.05, 1.0)
		_text(Vector2(s.x * 0.5, y), t["text"], 18, HORIZONTAL_ALIGNMENT_CENTER,
				Color(t["color"], a), 700.0)
		y += 26.0


func _draw_result(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var title := "NHIỆM VỤ THẤT BẠI"
	var col := Color(1.0, 0.35, 0.3)
	match mission.state:
		MissionManager.State.SUCCESS:
			title = "NHIỆM VỤ HOÀN THÀNH"
			col = Color(0.4, 1.0, 0.5)
		MissionManager.State.PARTIAL:
			title = "NHIỆM VỤ KẾT THÚC"
			col = Color(1.0, 0.75, 0.25)
	var cx := s.x * 0.5
	var y := s.y * 0.5 - 150.0
	_text(Vector2(cx, y), title, 44, HORIZONTAL_ALIGNMENT_CENTER, col, 900.0)
	_text(Vector2(cx, y + 36.0), mission.result_text, 20, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1), 900.0)
	y += 76.0
	for line in mission.breakdown:
		_text(Vector2(cx, y), line, 16, HORIZONTAL_ALIGNMENT_CENTER, Color(0.9, 0.9, 0.9), 900.0)
		y += 24.0
	y += 14.0
	_text(Vector2(cx, y + 20.0), "TỔNG ĐIỂM  %d" % mission.score, 34, HORIZONTAL_ALIGNMENT_CENTER,
			Color(1.0, 0.9, 0.3), 900.0)
	_text(Vector2(cx, y + 62.0), "XẾP HẠNG  %s" % mission.rank, 30, HORIZONTAL_ALIGNMENT_CENTER, col, 900.0)
	var best := "KỶ LỤC MỚI!" if mission.new_best else "Điểm cao nhất: %d" % mission.best_score
	_text(Vector2(cx, y + 96.0), best, 18, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.3), 900.0)
	_text(Vector2(cx, y + 130.0), "Nhấn R để chơi lại   |   F10: menu", 16,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1), 900.0)