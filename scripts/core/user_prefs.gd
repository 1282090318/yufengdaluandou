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


## 全屏偏好的**口径版本**。改默认值 / 改写法时 +1。
## ⚠️ **v2（2026-11-03）**：全屏改成**默认开**（用户："游戏界面还是没有全屏"）。
## 老文件里那一格 `fullscreen`（几乎一定是"当初没切成功"时顺手存下的 false）**不再采信**，
## 一律按"没配置过"处理 = 全屏；等玩家下次按「启用」再以当场的真实状态写回 v2。
const VIDEO_MODE_VERSION := 2


## 读回全屏偏好。**没配置过（含老版本的 false，见 `VIDEO_MODE_VERSION`）= 全屏**。
## 原来"没有这一格 = 不碰窗口"⇒ 新装 / 没进过设置面板的机器永远是窗口化，看起来就像全屏功能不存在。
static func load_video() -> void:
	var cfg := ConfigFile.new()
	var want := true                     ## 默认 = **全屏**（正式发行的游戏一启动就铺满）
	if cfg.load(PATH) == OK and cfg.has_section_key("video", "fullscreen") \
			and int(cfg.get_value("video", "mode_version", 1)) >= VIDEO_MODE_VERSION:
		want = bool(cfg.get_value("video", "fullscreen"))
	_apply_fullscreen(want)


## 按**上一次要求的那个状态**再应用一次（幂等）。
## ⚠️ 给 `main.gd` 在启动的**帧尾**补一发：`_ready()` 里那一下有可能赶在窗口真正映射出来之前，
## 有的驱动会把那时候的 `window_set_mode()` 吞掉 ⇒ 表现就是"设了全屏、启动还是窗口"。
static func reapply_video() -> void:
	_apply_fullscreen(_want_fullscreen)


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
	## ⚠️ `mode_version` 与 `fullscreen` 必须**一起**写（见 `VIDEO_MODE_VERSION`）：
	## 只写版本号不写状态、或反过来，下次启动就会把握手当成"没配置过"。
	cfg.set_value("video", "mode_version", VIDEO_MODE_VERSION)
	cfg.set_value("video", "fullscreen", _fullscreen_now())
	InputBindings.write(cfg)
	cfg.save(PATH)


static func _fullscreen_now() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 最后一次要求的状态（`reapply_video()` 补发用）。
static var _want_fullscreen := true


## 进 / 出全屏。**进全屏只切模式**：
## ⚠️ **2026-11-03 删掉了紧跟其后的 `window_set_size(screen_size)` / `window_set_position(screen_pos)`**
##（用户："游戏界面还是没有全屏"）。`WINDOW_MODE_FULLSCREEN` 本来就铺满当前显示器，而那两行是**按普通窗口**
## 再摆一次尺寸与位置 —— 在已经是全屏的窗口上等于把窗口当窗口重新摆放，有的驱动会就此把全屏顶回窗口化。
static func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_want_fullscreen = on
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		## ⚠️ **兜底（2026-11-03 第二次改）**：在编辑器的「游戏视图」里嵌入式跑时，游戏窗口是被编辑器收养的
		## 子窗口，`WINDOW_MODE_FULLSCREEN` 在那边是**空操作**（模式根本没变过去）⇒ 画面永远钉在那块 1600×900 里。
		## 所以模式没真的切过去就退到"最大化 + 撑满可用区域"（用户："这次必须随着窗口能放大"）。
		if not _fullscreen_now():
			_grow_to_usable_area()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	_grow_to_usable_area()


## **"窗口化" = 尽量大**，不再回到 1600×900 的小窗（用户三番两次要的是"画面随窗口变大"）。
## · 独立窗口：`WINDOW_MODE_MAXIMIZED` —— 撑到可用区域，标题栏 / 任务栏交给系统算。
## · 嵌入式窗口：它不一定认 `MAXIMIZED`（被编辑器收养的子窗口）⇒ 尺寸还停在项目默认值
##   （< 可用区的 90%）时**显式给一次可用区域的尺寸**；有的嵌法会把它钳到游戏视图面板大小，正好铺满。
static func _grow_to_usable_area() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	if DisplayServer.window_get_size().x < int(float(usable.size.x) * 0.9):
		DisplayServer.window_set_size(usable.size)
		DisplayServer.window_set_position(usable.position)


static func _apply_fullscreen(on: bool) -> void:
	set_fullscreen(on)
