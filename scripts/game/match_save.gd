class_name MatchSave
extends RefCounted
## 竞猜、生存各一份存档，写在本机用户目录。沙盒不存。
## 不进 Autoload（不变量 I-06）。

const QUIZ_PATH := "user://save_quiz.json"
const ROGUELIKE_PATH := "user://save_roguelike.json"


static func has_quiz() -> bool:
	return FileAccess.file_exists(QUIZ_PATH)

static func has_roguelike() -> bool:
	return FileAccess.file_exists(ROGUELIKE_PATH)

static func any_exists() -> bool:
	return has_quiz() or has_roguelike()

static func has_mode(mode: String) -> bool:
	if mode == "quiz":
		return has_quiz()
	if mode == "roguelike":
		return has_roguelike()
	return false


static func read_quiz() -> Dictionary:
	return _read(QUIZ_PATH)

static func read_roguelike() -> Dictionary:
	return _read(ROGUELIKE_PATH)

static func write_quiz(data: Dictionary) -> void:
	_write(QUIZ_PATH, data)

static func write_roguelike(data: Dictionary) -> void:
	_write(ROGUELIKE_PATH, data)

static func erase_quiz() -> void:
	_erase(QUIZ_PATH)

static func erase_roguelike() -> void:
	_erase(ROGUELIKE_PATH)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return _unpack(parsed) as Dictionary
	return {}

static func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_pack(data)))

static func _erase(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _pack(value: Variant) -> Variant:
	if value is Vector3:
		var point := value as Vector3
		return {"_v3": [point.x, point.y, point.z]}
	if value is Vector2:
		var flat := value as Vector2
		return {"_v2": [flat.x, flat.y]}
	if value is Dictionary:
		var packed := {}
		for key in (value as Dictionary).keys():
			packed[key] = _pack((value as Dictionary)[key])
		return packed
	if value is Array:
		var packed_list: Array = []
		for item in value as Array:
			packed_list.append(_pack(item))
		return packed_list
	return value

static func _unpack(value: Variant) -> Variant:
	if value is Dictionary:
		var row := value as Dictionary
		if row.has("_v3") and row["_v3"] is Array:
			var coords: Array = row["_v3"]
			return Vector3(float(coords[0]), float(coords[1]), float(coords[2]))
		if row.has("_v2") and row["_v2"] is Array:
			var flat: Array = row["_v2"]
			return Vector2(float(flat[0]), float(flat[1]))
		var unpacked := {}
		for key in row.keys():
			unpacked[key] = _unpack(row[key])
		return unpacked
	if value is Array:
		var unpacked_list: Array = []
		for item in value as Array:
			unpacked_list.append(_unpack(item))
		return unpacked_list
	return value
