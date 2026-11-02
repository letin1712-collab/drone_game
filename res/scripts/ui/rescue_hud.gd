class_name RescueHUD
extends Control
## HUD vẽ bằng code: la bàn, độ cao, tốc độ, pin, GPS (thanh + dạng sóng), hướng gió.

@export var drone: DroneController
@export var color := Color(0.6, 1.0, 0.7)

var _font: Font
var _noise := FastNoiseLite.new()
var _wave := PackedFloat32Array()
var _t := 0.0
var _gps_quality := 1.0
var _vision: VisionPostProcess
var _cam: ChaseCamera
var _redraw_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_noise.seed = randi()
	_noise.frequency = 0.6
	_wave.resize(60)
	_vision = get_tree().get_first_node_in_group("vision_post") as VisionPostProcess
	_cam = get_tree().get_first_node_in_group("drone_camera") as ChaseCamera


func _process(delta: float) -> void:
	_t += delta
	if drone:
		# GPS yếu khi bay sát đất (che chắn), dao động nhẹ theo thời gian
		var low := 1.0 - clampf(drone.get_altitude() / 5.0, 0.0, 1.0)
		_gps_quality = clampf(0.92 - low * 0.35 + _noise.get_noise_1d(_t * 20.0) * 0.1, 0.05, 1.0)
	_wave.remove_at(0)
	_wave.append(_noise.get_noise_1d(_t * 300.0) * _gps_quality)
	queue_redraw()


func _draw() -> void:
	if drone == null:
		return
	var s := size
	var heading := _heading_deg()

	_draw_compass(Vector2(s.x * 0.5, 36.0), heading)
	_draw_crosshair(s * 0.5)

	# Độ cao (trái) và tốc độ (phải)
	_text(Vector2(40, s.y * 0.5 - 10), "ALT", 14)
	_text(Vector2(40, s.y * 0.5 + 20), "%.1f m" % drone.get_altitude(), 26)
	_text(Vector2(s.x - 40, s.y * 0.5 - 10), "SPD", 14, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(s.x - 40, s.y * 0.5 + 20), "%.1f m/s" % drone.get_speed(), 26, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(s.x - 40, s.y * 0.5 + 44), "V/S %+.1f" % drone.linear_velocity.y, 14, HORIZONTAL_ALIGNMENT_RIGHT)

	# Trạng thái chế độ (trên cùng bên trái / phải)
	var mode_name: String = DroneInputData.FlightMode.keys()[DroneInput.current.mode]
	_text(Vector2(24, 30), "MODE  " + mode_name, 18)
	_text(Vector2(24, 54), "PAYLOAD  %.2f kg" % drone.payload_mass, 14)
	var vis_name := "NORMAL"
	if _vision:
		vis_name = VisionPostProcess.Vision.keys()[_vision.current]
	var cam_name := "FPV" if (_cam and _cam.is_fpv) else "TPV"
	_text(Vector2(s.x - 24, 30), "%s  |  %s" % [cam_name, vis_name], 18, HORIZONTAL_ALIGNMENT_RIGHT)

	_draw_battery(Vector2(40, s.y - 60))
	_draw_gps(Vector2(s.x * 0.5 - 90, s.y - 80))
	_draw_wind(Vector2(s.x - 100, s.y - 100), heading)


func _heading_deg() -> float:
	var fwd := -drone.global_basis.z
	# 0° = hướng -Z (Bắc), 90° = +X (Đông), cùng quy ước với WindSystem
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _text(pos: Vector2, txt: String, fsize := 18,
		align := HORIZONTAL_ALIGNMENT_LEFT, col := Color.TRANSPARENT) -> void:
	var c := color if col.a == 0.0 else col
	var w := 300.0
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	# Bóng đen phía sau để dễ đọc trên mọi nền
	draw_string(_font, p + Vector2(1, 1), txt, align, w, fsize, Color(0, 0, 0, 0.7))
	draw_string(_font, p, txt, align, w, fsize, c)


func _draw_compass(center: Vector2, heading: float) -> void:
	var half_span := 60.0
	var ppd := 3.4  # pixel mỗi độ
	var a := int(floor((heading - half_span) / 5.0)) * 5
	while a <= heading + half_span:
		var x := center.x + (a - heading) * ppd
		var major := a % 30 == 0
		draw_line(Vector2(x, center.y), Vector2(x, center.y + (14 if major else 7)), color, 2.0 if major else 1.0)
		if major:
			var d := int(fposmod(a, 360))
			var label := str(d)
			match d:
				0: label = "N"
				90: label = "E"
				180: label = "S"
				270: label = "W"
			_text(Vector2(x, center.y + 34), label, 14, HORIZONTAL_ALIGNMENT_CENTER)
		a += 5
	# Mũi tên giữa + số hướng
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -4), center + Vector2(-6, -14), center + Vector2(6, -14)]), color)
	_text(center + Vector2(0, -20), "%03d°" % int(heading), 16, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_crosshair(c: Vector2) -> void:
	draw_arc(c, 18.0, 0, TAU, 32, color, 1.5)
	draw_line(c + Vector2(-34, 0), c + Vector2(-18, 0), color, 1.5)
	draw_line(c + Vector2(18, 0), c + Vector2(34, 0), color, 1.5)
	draw_line(c + Vector2(0, 18), c + Vector2(0, 28), color, 1.5)


func _draw_battery(pos: Vector2) -> void:
	var pct := drone.get_battery_percent()
	var col := Color(0.3, 1.0, 0.4)
	if pct < 30.0:
		col = Color(1.0, 0.85, 0.2)
	if pct < 15.0:
		# Nhấp nháy cảnh báo pin yếu
		col = Color(1.0, 0.2, 0.2) if int(_t * 3.0) % 2 == 0 else Color(0.5, 0.1, 0.1)
	_text(pos + Vector2(0, -6), "BAT  %d%%" % int(pct), 18, HORIZONTAL_ALIGNMENT_LEFT, col)
	draw_rect(Rect2(pos, Vector2(160, 14)), color, false, 2.0)
	draw_rect(Rect2(pos + Vector2(2, 2), Vector2(156.0 * pct / 100.0, 10)), col)


func _draw_gps(pos: Vector2) -> void:
	var bars := ceili(_gps_quality * 5.0)
	var sats := int(4.0 + _gps_quality * 10.0)
	_text(pos + Vector2(0, -6), "GPS  %d SAT" % sats, 16)
	for i in 5:
		var h := 6.0 + i * 5.0
		var col := color if i < bars else Color(color, 0.25)
		draw_rect(Rect2(pos + Vector2(i * 9.0, 28.0 - h), Vector2(6, h)), col)
	# Dạng sóng tín hiệu (biên độ tỉ lệ chất lượng)
	var base := pos + Vector2(60, 14)
	for i in range(1, _wave.size()):
		var p1 := base + Vector2((i - 1) * 2.0, _wave[i - 1] * 14.0)
		var p2 := base + Vector2(i * 2.0, _wave[i] * 14.0)
		draw_line(p1, p2, color, 1.5)


func _draw_wind(c: Vector2, heading: float) -> void:
	var r := 42.0
	draw_arc(c, r, 0, TAU, 48, color, 2.0)
	# Điểm "mũi drone" ở phía trên vòng tròn
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r - 2), c + Vector2(-5, -r - 10), c + Vector2(5, -r - 10)]), color)
	var w := drone.get_wind()
	var speed := Vector2(w.x, w.z).length()
	# Góc gió THỔI TỚI, tính tương đối so với mũi drone
	var ang := atan2(w.x, -w.z) - deg_to_rad(heading)
	var dir := Vector2(sin(ang), -cos(ang))
	var tail := c - dir * r * 0.6
	var tip := c + dir * r * 0.6
	draw_line(tail, tip, color, 3.0)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip + dir * 10.0, tip + side * 7.0, tip - side * 7.0]), color)
	_text(c + Vector2(0, r + 28), "WIND %.1f m/s" % speed, 16, HORIZONTAL_ALIGNMENT_CENTER)