class_name PayloadSystem
extends Node
## Kho hàng. Tab: chọn vật phẩm, Space/A: thả. Hạ cánh ở căn cứ: tự nạp lại đầy.
## Khối lượng hàng được cộng vào drone → lực nâng cần nhiều hơn → pin tụt nhanh hơn.

signal inventory_changed
signal message(text: String, color: Color)

const ITEM_MASSES := [0.3, 0.2, 0.08]    # kg: phao, túi y tế, đèn tín hiệu

@export var drone: DroneController
@export var start_stock := Vector3i(2, 2, 2)   # (phao, túi y tế, đèn)

var stock: Array[int] = [0, 0, 0]
var selected := 0


func _ready() -> void:
	add_to_group("payload_system")
	DroneInput.release_payload.connect(release_selected)
	DroneInput.cycle_payload.connect(cycle_selected)
	restock()


## Đặt lại hoàn toàn (đầu nhiệm vụ).
func restock() -> void:
	stock[0] = start_stock.x
	stock[1] = start_stock.y
	stock[2] = start_stock.z
	selected = 0
	_update_mass()
	inventory_changed.emit()


func needs_refill() -> bool:
	return stock[0] < start_stock.x or stock[1] < start_stock.y or stock[2] < start_stock.z


## Nạp lại ở căn cứ, giữ nguyên vật phẩm đang chọn.
func refill() -> void:
	stock[0] = start_stock.x
	stock[1] = start_stock.y
	stock[2] = start_stock.z
	_update_mass()
	inventory_changed.emit()
	message.emit("Đã nạp đầy vật phẩm và sạc pin tại căn cứ", Color(0.4, 1.0, 0.5))


func cycle_selected() -> void:
	if get_tree().paused:
		return
	selected = (selected + 1) % 3
	inventory_changed.emit()
	message.emit("Đã chọn: %s (còn %d)" % [Victim.NEED_NAMES_VI[selected], stock[selected]],
			Color(1.0, 0.9, 0.3))


func release_selected() -> void:
	if drone == null or get_tree().paused:
		return
	if stock[selected] <= 0:
		message.emit("Hết %s! Hạ cánh ở căn cứ để nạp thêm." % Victim.NEED_NAMES_VI[selected],
				Color(1.0, 0.4, 0.3))
		return
	stock[selected] -= 1

	var item := PayloadItem.new()
	item.need = selected
	item.item_mass = ITEM_MASSES[selected]
	drone.get_parent().add_child(item)
	item.global_position = drone.global_position - drone.global_basis.y * 0.25
	item.linear_velocity = drone.linear_velocity          # giữ quán tính của drone
	item.add_collision_exception_with(drone)

	_update_mass()
	inventory_changed.emit()
	message.emit("Đã thả: %s" % Victim.NEED_NAMES_VI[selected], Color(0.6, 1.0, 0.7))


func _update_mass() -> void:
	if drone == null:
		return
	var total := 0.0
	for i in 3:
		total += stock[i] * float(ITEM_MASSES[i])
	drone.set_payload(total)