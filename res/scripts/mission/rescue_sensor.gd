class_name RescueSensor
extends Node
## Quét nạn nhân bằng chính camera đang dùng: nạn nhân phải nằm trong khung hình,
## trong tầm, và đường nhìn không bị chặn. Giữ trong khung hình `lock_time` giây thì khóa.
##  - Normal / Night: bị chặn bởi địa hình, nhà VÀ cây (layer 1 + 2)
##  - Thermal: chỉ bị chặn bởi địa hình, nhà (layer 1) → nhiệt xuyên tán cây

@export var drone: DroneController
@export var range_normal := 35.0
@export var range_night := 60.0
@export var range_thermal := 100.0
@export var lock_time := 1.2

var _cam: Camera3D
var _vision: VisionPostProcess
var _acc := 0.0


func _ready() -> void:
	_cam = get_tree().get_first_node_in_group("drone_camera") as Camera3D
	_vision = get_tree().get_first_node_in_group("vision_post") as VisionPostProcess


func _physics_process(delta: float) -> void:
	# Quét 20 lần/giây là đủ (thay vì 120)
	_acc += delta
	if _acc < 0.05:
		return
	var dt := _acc
	_acc = 0.0
	if drone == null or _cam == null:
		return

	var mode := VisionPostProcess.Vision.NORMAL
	if _vision:
		mode = _vision.current
	var thermal := mode == VisionPostProcess.Vision.THERMAL
	var max_range := range_normal
	if thermal:
		max_range = range_thermal
	elif mode == VisionPostProcess.Vision.NIGHT:
		max_range = range_night

	var space := drone.get_world_3d().direct_space_state
	var origin := drone.global_position
	var mask := 1 if thermal else 3

	for n in get_tree().get_nodes_in_group("victims"):
		var v := n as Victim
		if v == null or v.state == Victim.State.DEAD:
			continue
		var target := v.global_position + Vector3(0.0, 0.4, 0.0)
		var los := false
		if origin.distance_to(target) <= max_range:
			var q := PhysicsRayQueryParameters3D.create(origin, target, mask)
			q.exclude = [drone.get_rid()]
			los = space.intersect_ray(q).is_empty()

		v.set_thermal_visible(thermal and los)

		if v.state == Victim.State.UNKNOWN:
			var seen := los and _cam.is_position_in_frustum(target)
			if seen:
				v.scan_progress = minf(v.scan_progress + dt / lock_time, 1.0)
			else:
				v.scan_progress = maxf(v.scan_progress - dt * 0.6, 0.0)
			if v.scan_progress >= 1.0:
				v.mark_detected()
