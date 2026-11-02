class_name Victim
extends Node3D
## Nạn nhân: thân nhiệt (HeatSource) + tình trạng giảm dần theo thời gian.
## Công thức: condition -= (100 / survival_time) · dt  → về 0 là tử vong.

signal detected(victim)
signal rescued(victim)
signal died(victim)
signal wrong_item(victim)

enum Need { LIFEBUOY, MEDKIT, FLARE }
enum State { UNKNOWN, DETECTED, RESCUED, DEAD }

## Dùng chung cho HUD, kho hàng và nhiệm vụ (không dấu để font mặc định hiển thị đúng).
const NEED_NAMES := ["LIFEBUOY", "MEDKIT", "FLARE"]
const NEED_NAMES_VI := ["Phao cứu sinh", "Túi y tế", "Đèn tín hiệu"]
const NEED_HINTS_VI := ["Cho nạn nhân dưới nước", "Cho nạn nhân bị thương", "Giúp đội cứu hộ định vị"]

@export var victim_name := "Victim"
@export_enum("Lifebuoy", "Medkit", "Flare") var need := 1
@export var survival_time := 480.0     # giây
@export var in_water := false

var condition := 100.0                 # 0..100
var state := State.UNKNOWN
var scan_progress := 0.0               # 0..1, do RescueSensor cập nhật
var _yaw := randf() * TAU
var _body: HumanFigure
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("victims")

	_body = HumanFigure.new()
	_body.setup(randi())
	_body.rotation_degrees = Vector3(90.0, randf() * 360.0, 0.0)   # nằm ngửa, hướng ngẫu nhiên
	_body.position = Vector3(0.0, 0.14, 0.0)
	add_child(_body)

	_light = OmniLight3D.new()
	_light.visible = false
	_light.light_color = Color(0.3, 1.0, 0.4)
	_light.omni_range = 10.0
	_light.light_energy = 0.0
	_light.position = Vector3(0.0, 1.5, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	_body.waving = state == State.UNKNOWN or state == State.DETECTED
	_t += delta
	if in_water and state != State.DEAD:
		_body.position.y = 0.12 + sin(_t * 1.6) * 0.05      # nhấp nhô theo sóng

	if state == State.UNKNOWN or state == State.DETECTED:
		condition = maxf(condition - 100.0 / survival_time * delta, 0.0)
		if condition <= 0.0:
			_die()
	elif state == State.RESCUED:
		_light.visible = true
		_light.light_energy = 1.5 + sin(_t * 4.0) * 0.5      # đèn xanh nhấp nháy: đã an toàn
		


func mark_detected() -> void:
	if state != State.UNKNOWN:
		return
	state = State.DETECTED
	scan_progress = 1.0
	detected.emit(self)


## Được PayloadItem gọi khi vật phẩm chạm đất gần nạn nhân.
func receive_item(item_need: int) -> void:
	if state == State.DEAD or state == State.RESCUED:
		return
	if item_need != need:
		wrong_item.emit(self)
		return
	state = State.RESCUED
	scan_progress = 1.0
	rescued.emit(self)


func set_thermal_visible(on: bool) -> void:
	if state != State.DEAD:
		_body.set_xray(on)


func _die() -> void:
	state = State.DEAD
	_body.set_hot(false)
	_body.set_xray(false)
	died.emit(self)
	
## Nằm ngửa, áp sát mặt đất theo pháp tuyến n (sườn dốc thì nghiêng theo).
func align_to_ground(n: Vector3) -> void:
	if in_water:
		n = Vector3.UP
	n = n.normalized()
	var lie := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, PI / 2.0)   # nằm ngửa, hướng _yaw
	_body.basis = Basis(Quaternion(Vector3.UP, n)) * lie                   # nghiêng theo dốc
	_body.position = n * 0.14                                              # nâng khỏi mặt đất theo pháp tuyến