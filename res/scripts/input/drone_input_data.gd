class_name DroneInputData
extends RefCounted
## Dữ liệu input đã chuẩn hóa, mọi trục nằm trong [-1, 1].
## Module vật lý chỉ phụ thuộc vào lớp này, không biết input đến từ thiết bị nào.

enum FlightMode { ANGLE, ACRO } # ANGLE: tự cân bằng | ACRO: điều khiển tốc độ góc

var throttle := 0.0 # -1 (giảm) .. +1 (tăng)
var yaw := 0.0      # -1 (xoay trái) .. +1 (xoay phải)
var pitch := 0.0    # -1 (ngả sau) .. +1 (chúi trước)
var roll := 0.0     # -1 (nghiêng trái) .. +1 (nghiêng phải)
var mode: FlightMode = FlightMode.ANGLE