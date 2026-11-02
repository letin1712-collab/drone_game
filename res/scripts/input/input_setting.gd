class_name InputSettings
extends Resource

@export var throttle := AxisSettings.new(0.10, 0.0) # Throttle không nên có expo
@export var yaw := AxisSettings.new(0.10, 0.3)
@export var pitch := AxisSettings.new(0.08, 0.4)
@export var roll := AxisSettings.new(0.08, 0.4)

@export_group("Bàn phím")
## Thời gian (giây) để phím đạt giá trị tối đa. Phím chỉ có 0/1 nên cần làm mượt.
@export_range(0.01, 1.0) var kb_ramp_up := 0.15
@export_range(0.01, 1.0) var kb_ramp_down := 0.10