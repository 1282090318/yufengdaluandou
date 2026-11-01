class_name InputBindings
extends RefCounted
## 玩家可以改的按键。默认写在 `project.godot` 的 InputMap 里。
## 启用过的改动由 `UserPrefs` 写进本机文件，启动时盖回去。
## 不进 Autoload（不变量 I-06）。Esc 和鼠标键不在这份名单里。

const ACTIONS: Array[String] = [
	"cam_forward",
	"cam_back",
	"cam_left",
	"cam_right",
	"cam_overview",
	"pilot_skill",
	"pilot_shoulder",
	"pilot_release",
]

const _LABELS := {
	"cam_forward": "前进",
	"cam_back": "后退",
	"cam_left": "左移",
	"cam_right": "右移",
	"cam_overview": "自由视角",
	"pilot_skill": "技能",
	"pilot_shoulder": "肩位",
	"pilot_release": "交还",
}

const _DEFAULT_CODE := {
	"pilot_skill": KEY_1,
	"pilot_shoulder": KEY_X,
	"pilot_release": KEY_Q,
}


static func action_label(action: String) -> String:
	return String(_LABELS.get(action, action))


static func ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		var code := int(_DEFAULT_CODE.get(action, 0))
		if code != 0:
			_set_key(action, code)


static func read(cfg: ConfigFile) -> void:
	ensure_actions()
	for action in ACTIONS:
		if cfg.has_section_key("input", action):
			_set_key(action, int(cfg.get_value("input", action)))


static func write(cfg: ConfigFile) -> void:
	ensure_actions()
	for action in ACTIONS:
		cfg.set_value("input", action, physical_code(action))


static func snapshot() -> Dictionary:
	ensure_actions()
	var data := {}
	for action in ACTIONS:
		data[action] = physical_code(action)
	return data


static func restore(data: Dictionary) -> void:
	ensure_actions()
	for action in ACTIONS:
		_set_key(action, int(data.get(action, 0)))


static func physical_code(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.physical_keycode != 0:
				return key.physical_keycode
			return key.keycode
	return 0


## 主键盘数字改过之后，小键盘上的同一颗数字仍然算这一项。
static func pad_matches(key: InputEventKey, action: String) -> bool:
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	var twin := _pad_twin(physical_code(action))
	return twin != 0 and code == twin


static func key_label(action: String) -> String:
	var code := physical_code(action)
	if code == 0:
		return "未设置"
	return OS.get_keycode_string(code)


## 同一颗键只留给这次设的那一项。名单以外的动作（跟随、重置、升降）不动。
static func set_physical(action: String, code: int) -> void:
	ensure_actions()
	if code != 0:
		for other in ACTIONS:
			if other != action and physical_code(other) == code:
				_set_key(other, 0)
	_set_key(action, code)


static func _set_key(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_erase_events(action)
	if code == 0:
		return
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	InputMap.action_add_event(action, event)


static func _pad_twin(code: int) -> int:
	match code:
		KEY_0:
			return KEY_KP_0
		KEY_1:
			return KEY_KP_1
		KEY_2:
			return KEY_KP_2
		KEY_3:
			return KEY_KP_3
		KEY_4:
			return KEY_KP_4
		KEY_5:
			return KEY_KP_5
		KEY_6:
			return KEY_KP_6
		KEY_7:
			return KEY_KP_7
		KEY_8:
			return KEY_KP_8
		KEY_9:
			return KEY_KP_9
		_:
			return 0
