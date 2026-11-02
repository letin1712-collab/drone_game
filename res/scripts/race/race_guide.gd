class_name RaceGuide
extends GuidePanel
## Giống GuidePanel nhưng nội dung dành cho chế độ Đua FPV.

const RACE_TEXT := """[color=#ffd84d]MỤC TIÊU[/color]
Bay qua lần lượt tất cả các vòng phát sáng theo đúng thứ tự và đúng chiều, về đích (vòng FINISH màu đỏ) nhanh nhất có thể. Vòng xanh lá nhấp nháy là vòng kế tiếp; mũi tên ở viền màn hình chỉ hướng cần quay khi vòng nằm ngoài tầm nhìn.

[color=#ffd84d]ĐIỀU KHIỂN[/color]
W/S ga lên/xuống  |  A/D xoay mũi  |  ↑/↓ chúi/ngả  |  ←/→ nghiêng
M hoặc D-Pad ↑:  đổi Angle (dễ, tự cân bằng) và Acro (FPV thật, tự kiểm soát hoàn toàn)
C: đổi FPV/TPV   |   V: đổi chế độ nhìn

[color=#ffd84d]LUẬT ĐUA[/color]
Chạm khung vòng sẽ bị va chạm thật. Bay trượt hoặc sai chiều thì quay lại bay qua vòng đó.
T:  về lại ngay sau vòng đã qua gần nhất (phạt +5 giây). Ra khỏi khu vực đua cũng bị đưa về và phạt.
R:  chạy lại đúng đường đua này   |   F3:  đường đua mới   |   F10:  về menu chính
Kỷ lục được lưu riêng cho từng đường đua (#số) và từng chế độ lái.

[color=#ffd84d]MẸO[/color]
Nhìn trước vòng kế tiếp và vào vòng chính giữa lỗ. Giảm tốc trước khúc cua gắt. Ở Acro, thả cần thì drone giữ nguyên độ nghiêng, nên cần chủ động cân bằng. F2: đổi thời tiết (mưa, bão làm bay khó hơn)."""


func _guide_title() -> String:
	return "HƯỚNG DẪN - ĐUA FPV"


func _guide_text() -> String:
	return RACE_TEXT