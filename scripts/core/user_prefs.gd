class_name UserPrefs
extends RefCounted
## 音量和战场勾选写在本机用户目录里。编辑器运行和导出后的程序读的是同一份。
## 不进 Autoload（不变量 I-06）。

const PATH := "user://user_prefs.cfg"


static func load_battle_scenes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for scene_id in GameConfig.battle_scene_ids():
		if cfg.has_section_key("battle", String(scene_id)):
			GameConfig.set_battle_scene_enabled(String(scene_id), bool(cfg.get_value("battle", String(scene_id))))


static func load_video() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section_key("video", "fullscreen"):
		return
	_apply_fullscreen(bool(cfg.get_value("video", "fullscreen")))


static func load_input() -> void:
	InputBindings.ensure_actions()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	InputBindings.read(cfg)


static func load_audio(audio: AudioManager) -> void:
	if audio == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if cfg.has_section_key("audio", "music_db"):
		audio.set_music_db(float(cfg.get_value("audio", "music_db")))
	if cfg.has_section_key("audio", "sfx_db"):
		audio.set_sfx_db(float(cfg.get_value("audio", "sfx_db")))


static func save_current(audio: AudioManager) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if audio != null:
		cfg.set_value("audio", "music_db", audio.music_db())
		cfg.set_value("audio", "sfx_db", audio.sfx_db())
	for scene_id in GameConfig.battle_scene_ids():
		cfg.set_value("battle", String(scene_id), GameConfig.is_battle_scene_enabled(String(scene_id)))
	cfg.set_value("video", "fullscreen", _fullscreen_now())
	InputBindings.write(cfg)
	cfg.save(PATH)


static func _fullscreen_now() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static var _windowed_size := Vector2i(1600, 900)
static var _windowed_pos := Vector2i(0, 0)
static var _have_windowed := false


static func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	if on:
		if not _fullscreen_now():
			_windowed_size = DisplayServer.window_get_size()
			_windowed_pos = DisplayServer.window_get_position()
			_have_windowed = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var size := _windowed_size if _have_windowed else Vector2i(1600, 900)
	if size.x < 640 or size.y < 360:
		size = Vector2i(1600, 900)
	DisplayServer.window_set_size(size)
	if _have_windowed:
		DisplayServer.window_set_position(_windowed_pos)
		return
	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)


static func _apply_fullscreen(on: bool) -> void:
	set_fullscreen(on)
