class_name RaceHUD
extends Control
## HUD đua: đồng hồ, tiến độ vòng, kỷ lục, thời gian từng chặng, marker/mũi tên chỉ
## vòng kế tiếp (kẹp vào viền màn hình khi ở ngoài tầm nhìn), đếm ngược, kết quả.

@export var race: RaceManager
@export var drone: DroneController
@export var color := Color(0.6, 1.0, 0.7)

var _font: Font
var _cam: Camera3D
var _toasts: Array = []
var _redraw_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	_font = sf
	_cam = get_tree().get_first_node_in_group("drone_camera") as Camera3D
	if race:
		race.message.connect(_push_toast)


func _push_toast(text: String, col: Color) -> void:
	_toasts.append({"text": text, "color": col, "t": 4.0})
	if _toasts.size() > 3:
		_toasts.pop_front()


func _process(delta: float) -> void:
	for t in _toasts:
		t["t"] -= delta
	_toasts = _toasts.filter(func(t): return t["t"] > 0.0)
	_redraw_t += delta
	if _redraw_t >= 1.0 / 30.0:
		_redraw_t = 0.0
		queue_redraw()


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


func _draw() -> void:
	if race == null or drone == null or race.gate_count() == 0:
		return
	var s := size
	if _cam == null:
		_cam = get_tree().get_first_node_in_group("drone_camera") as Camera3D
	if race.state != RaceManager.State.FINISHED:
		_draw_gate_marker(s)
	_draw_left_panel()
	_draw_splits(s)
	_text(Vector2(s.x * 0.5, s.y - 14.0),
			"[T] về vòng trước (+%ds)   [R] chạy lại   [F3] đường đua mới   [F10] menu" % int(race.respawn_penalty),
			13, HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.85, 0.85), 900.0)
	_draw_toasts(s)
	match race.state:
		RaceManager.State.COUNTDOWN:
			_draw_countdown(s)
		RaceManager.State.RACING:
			if race.elapsed < 1.0:
				_text(Vector2(s.x * 0.5, s.y * 0.35), "GO!", 90, HORIZONTAL_ALIGNMENT_CENTER,
						Color(0.4, 1.0, 0.5, 1.0 - race.elapsed), 400.0)
		RaceManager.State.FINISHED:
			_draw_result(s)


func _draw_left_panel() -> void:
	_text(Vector2(24, 84), "ĐƯỜNG ĐUA #%d   ĐỘ KHÓ %d/5" % [race.seed_value, race.stars], 14)
	_text(Vector2(24, 124), RaceManager.format_time(race.total_time()), 38,
			HORIZONTAL_ALIGNMENT_LEFT, race.pace_color())
	_text(Vector2(24, 150), "VÒNG %d/%d" % [mini(race.next_index + 1, race.gate_count()),
			race.gate_count()], 18)
	var best := "KỶ LỤC  --" if race.best_time <= 0.0 else "KỶ LỤC  " + RaceManager.format_time(race.best_time)
	_text(Vector2(24, 174), best, 14, HORIZONTAL_ALIGNMENT_LEFT, Color(1.0, 0.85, 0.3))
	var y := 198.0
	if race.penalties > 0.0:
		_text(Vector2(24, y), "PHẠT +%ds" % int(race.penalties), 14,
				HORIZONTAL_ALIGNMENT_LEFT, Color(1.0, 0.5, 0.3))
		y += 22.0
	var t := race.total_time()
	var tiers := [["VÀNG", race.par_time, Color(1.0, 0.85, 0.3)],
			["BẠC", race.silver_time, Color(0.8, 0.85, 0.9)],
			["ĐỒNG", race.bronze_time, Color(0.85, 0.55, 0.3)]]
	for tier in tiers:
		var c: Color = tier[2]
		if t > float(tier[1]):
			c = Color(c, 0.35)                 # mốc đã trượt thì mờ đi
		_text(Vector2(24, y), "%s  %s" % [tier[0], RaceManager.format_time(tier[1])], 14,
				HORIZONTAL_ALIGNMENT_LEFT, c)
		y += 20.0


func _draw_splits(s: Vector2) -> void:
	if race.splits.is_empty():
		return
	_text(Vector2(s.x - 24, 84), "CÁC CHẶNG", 14, HORIZONTAL_ALIGNMENT_RIGHT)
	var first := maxi(0, race.splits.size() - 6)
	var y := 108.0
	for i in range(first, race.splits.size()):
		var prev_t: float = race.splits[i - 1] if i > 0 else 0.0
		var lap: float = race.splits[i] - prev_t
		_text(Vector2(s.x - 24, y), "Vòng %d   %s   (%.1fs)" % [
				i + 1, RaceManager.format_time(race.splits[i]), lap], 14,
				HORIZONTAL_ALIGNMENT_RIGHT)
		y += 20.0


func _draw_gate_marker(s: Vector2) -> void:
	var g := race.next_gate()
	if g == null or _cam == null:
		return
	var p := g.global_position
	var dist := _cam.global_position.distance_to(p)
	var behind := _cam.is_position_behind(p)
	var sp := _cam.unproject_position(p)
	var col := Color(0.45, 1.0, 0.25)
	var margin := 60.0
	var inside := not behind and sp.x > margin and sp.x < s.x - margin \
			and sp.y > margin + 40.0 and sp.y < s.y - margin

	if inside:
		draw_polyline(PackedVector2Array([
			sp + Vector2(0, -16), sp + Vector2(16, 0), sp + Vector2(0, 16),
			sp + Vector2(-16, 0), sp + Vector2(0, -16)]), col, 2.0)
		_text(sp + Vector2(0, 38), "%d m" % int(dist), 16, HORIZONTAL_ALIGNMENT_CENTER, col, 200.0)
	else:
		# Ngoài tầm nhìn: mũi tên kẹp vào viền chỉ hướng cần quay
		var c := s * 0.5
		var dir := sp - c
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var half := s * 0.5 - Vector2(margin, margin + 20.0)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var pos := c + dir * k
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			pos + dir * 16.0, pos - dir * 9.0 + side * 10.0, pos - dir * 9.0 - side * 10.0]), col)
		_text(pos - dir * 30.0 + Vector2(0, 5), "%d m" % int(dist), 14,
				HORIZONTAL_ALIGNMENT_CENTER, col, 200.0)


func _draw_countdown(s: Vector2) -> void:
	_text(Vector2(s.x * 0.5, s.y * 0.30), "SẴN SÀNG", 28, HORIZONTAL_ALIGNMENT_CENTER,
			Color(1, 1, 1), 400.0)
	_text(Vector2(s.x * 0.5, s.y * 0.30 + 110.0), str(maxi(ceili(race.countdown), 1)), 120,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.9, 0.3), 300.0)


func _draw_toasts(s: Vector2) -> void:
	var y := s.y * 0.5 + 80.0
	for t in _toasts:
		var a := clampf(t["t"], 0.05, 1.0)
		_text(Vector2(s.x * 0.5, y), t["text"], 18, HORIZONTAL_ALIGNMENT_CENTER,
				Color(t["color"], a), 700.0)
		y += 26.0


func _draw_result(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
	var cx := s.x * 0.5
	var y := s.y * 0.5 - 150.0
	var medal_cols := [Color(0.7, 0.7, 0.7), Color(0.85, 0.55, 0.3), Color(0.8, 0.85, 0.9), Color(1.0, 0.85, 0.3)]
	var mc: Color = medal_cols[race.medal]
	_text(Vector2(cx, y), "VỀ ĐÍCH!", 52, HORIZONTAL_ALIGNMENT_CENTER, Color(0.4, 1.0, 0.5), 900.0)
	_text(Vector2(cx, y + 56.0), RaceManager.format_time(race.finish_time), 44,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1), 900.0)
	_text(Vector2(cx, y + 96.0), "HUY CHƯƠNG: %s" % RaceManager.MEDAL_NAMES[race.medal], 28,
			HORIZONTAL_ALIGNMENT_CENTER, mc, 900.0)
	_text(Vector2(cx, y + 130.0), "Mốc vàng %s   |   bạc %s   |   đồng %s" % [
			RaceManager.format_time(race.par_time), RaceManager.format_time(race.silver_time),
			RaceManager.format_time(race.bronze_time)], 15,
			HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.85, 0.85), 900.0)
	_text(Vector2(cx, y + 170.0), "ĐIỂM  %d     (độ khó %d/5)" % [race.score, race.stars], 30,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.9, 0.3), 900.0)
	if race.new_record:
		_text(Vector2(cx, y + 206.0), "KỶ LỤC THỜI GIAN MỚI!", 22, HORIZONTAL_ALIGNMENT_CENTER,
				Color(1.0, 0.85, 0.3), 900.0)
	else:
		_text(Vector2(cx, y + 206.0), "Kỷ lục: %s   |   Điểm cao nhất: %d" % [
				RaceManager.format_time(race.best_time), race.best_score], 18,
				HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.85, 0.3), 900.0)
	_text(Vector2(cx, y + 250.0), "R: chạy lại   |   F3: đường đua mới   |   F10: menu", 18,
			HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1), 900.0)