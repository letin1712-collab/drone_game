class_name AxisSettings
extends Resource

@export_range(0.0, 0.5) var deadzone := 0.1
@export_range(0.1, 3.0) var sensitivity := 1.0
## Expo: 0 = tuyến tính, 1 = rất mềm quanh tâm (giống Expo trên tay FPV thật).
@export_range(0.0, 1.0) var expo := 0.3
@export var invert := false

func _init(p_deadzone := 0.1, p_expo := 0.3) -> void:
	deadzone = p_deadzone
	expo = p_expo

## Pipeline: Deadzone -> Rescale -> Expo -> Sensitivity -> Invert
func apply(raw: float) -> float:
	var a := absf(raw)
	if a < deadzone:
		return 0.0

	# 1) Rescale để giá trị vẫn chạy mượt từ 0 -> 1 sau deadzone:
	#    r = (|x| - dz) / (1 - dz)
	var r := (a - deadzone) / (1.0 - deadzone)

	# 2) Expo: trộn đường tuyến tính và đường bậc 3:
	#    out = (1 - e) * r + e * r^3
	#    e càng lớn thì vùng gần tâm càng "mềm", nhưng vùng cuối vẫn đạt 1.
	var curved := (1.0 - expo) * r + expo * r * r * r

	# 3) Độ nhạy, giới hạn lại [0, 1], rồi khôi phục dấu
	var out := clampf(curved * sensitivity, 0.0, 1.0) * signf(raw)
	return -out if invert else out