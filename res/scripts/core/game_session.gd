extends Node
## Autoload "Session": map đang chọn, chất lượng đồ họa, lưu/đọc map JSON.

const MAP_DIR := "user://maps"
const SETTINGS_PATH := "user://settings.cfg"

var map: Dictionary = {}          # rỗng = map ngẫu nhiên mặc định
var last_edit: Dictionary = {}    # map đang sửa dở trong editor
var from_editor := false          # đang chơi thử từ editor? (F10 quay về editor)
var editor_scene := "res://res/scenes/map_editor.tscn"

# Hệ số theo chất lượng [thấp, vừa, cao]
var tree_mult := [0.35, 0.7, 1.0]
var cell_size := [5.0, 4.0, 3.0]
var shadow_dist := [80.0, 150.0, 250.0]
var rain_mult := [0.4, 0.7, 1.0]
var quality := 1


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		quality = clampi(int(cfg.get_value("graphics", "quality", 1)), 0, 2)
	apply_quality()


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	apply_quality()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", quality)
	cfg.save(SETTINGS_PATH)


func apply_quality() -> void:
	var vp := get_viewport()
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.75      # render 3D ở 75% độ phân giải
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.scaling_3d_scale = 1.0


# ---------------- Map ----------------
func objects_of(type: String) -> Array:
	var out := []
	for o in map.get("objects", []):
		if str(o.get("t", "")) == type:
			out.append(o)
	return out


func list_maps() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(MAP_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


func _path(map_name: String) -> String:
	var n := map_name.strip_edges().validate_filename()
	if n.is_empty():
		n = "map"
	return "%s/%s.json" % [MAP_DIR, n]


func save_map(data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(MAP_DIR)
	var f := FileAccess.open(_path(str(data.get("name", "map"))), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


func load_map(map_name: String) -> Dictionary:
	var p := _path(map_name)
	if not FileAccess.file_exists(p):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary else {}


func delete_map(map_name: String) -> void:
	DirAccess.remove_absolute(_path(map_name))