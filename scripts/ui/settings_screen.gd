class_name SettingsScreen
extends CanvasLayer
## 设置界面：**音乐 / 音效两条滑条 + 「退出」「启用」两个按钮**。
##
## 依据：`05_ui_hud.md#1`（界面是补充、不是主体）、`#6`（字号档位）、`07_file_layout.md#5`（依赖方向）、
## `06_audio.md#1`（总线树：改的是 `Music` 与 `SFX` 两条总线的音量）。与 `pause_menu.gd` 同一层、同一种做法：
## **全部控件由代码构建**，没有 .tscn；**由打开它的界面自己 `new()` 并挂在自己下面**（选项文案 / 挂点归界面管）。
##
## ⚠️ 用户口径（2026-09-25）：
##   · 「设置」按钮的位置 —— **开始界面在「开始游戏」下方**、**两个暂停界面分别在「主菜单」上方**；
##   · 界面里能改**音效 / 音乐的大小**，"类似于滑动变阻器的修改方法"（= 连续滑条，不是档位按钮）；
##   · "**而且要能让玩家预览修改后的效果**"；
##   · 下方两个按钮「退出」「启用」，"**只有按了启用按钮修改才有效，按退出则修改无效，
##     变回原来的样子**"；"这两个按钮都会回到**暂停界面**"（= 回到**打开设置前的那个界面**：
##     从开始界面进来的就回开始界面，从暂停菜单进来的就回暂停菜单 —— 本层是**盖在上面的一层**，
##     从来不隐藏底下的界面，所以"返回"就是把自己收起来）。
##
## 三段行为（本层的全部逻辑）：
##   ① **打开**：记下两条总线的**当前音量当快照**（= 上一次"启用"过的值），滑条按它摆好；
##   ② **拖动**：滑条**实时**写总线（这就是"预览"—— BGM 正在放，音乐滑条一拖就听得出大小；
##      音效滑条则**松手时补放一声试听**，见 `PREVIEW_MIN_INTERVAL_MS`）；
##   ③ **退出 / 启用**：退出 = 把快照写回总线（**修改无效**）；启用 = 把当前值确认为新快照
##      （滑条早就实时写进总线了，所以"启用"只是"确认"）。两者都只是把自己收起来。
##
## ⚠️ 本层 `PROCESS_MODE_ALWAYS`：从**暂停菜单**进来时整棵树是暂停的，本层照样要能点能拖。
## ⚠️ `mouse_filter = STOP` + 全屏 Scrim：把背后的界面（开始界面 / 暂停菜单）的点击整个吃掉，
## 否则拖滑条会顺手点到背后的按钮。
## ⚠️ 音量住在**总线**上（`AudioServer`），本层不自己存值 —— 所以开始界面、两个暂停菜单打开的是
## **同一份音量**，不存在"三个界面各存一份、改一处忘另一处"。

# ---------------------------------------------------------------- 表现参数
## 本层的 `CanvasLayer.layer`：⚠️ 必须**高于**暂停菜单（`PauseMenu.MENU_LAYER = 5`）与
## 开始界面（`StartScreen.SCREEN_LAYER = 10`）—— 那两个界面都可能打开本层，而本层要盖在它们上面。
## ⚠️ 这里写的是**数字**而不是去引用那两个常量：`scripts/ui/` 下的几个界面是**兄弟**，
## 互相引用违反依赖方向（`07_file_layout.md#5` 只允许自上而下）。层号的大小关系写在注释里。
const SETTINGS_LAYER := 20
const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.78)
const ROW_SEPARATION := 22
const LABEL_MIN_WIDTH := 76.0        ## 两行滑条的**名字列**等宽 ⇒ 两个滑条左边对齐
const SLIDER_MIN_SIZE := Vector2(320.0, 28.0)
const PERCENT_MIN_WIDTH := 64.0      ## 百分比列等宽 ⇒ 数字变化时滑条不会左右抖
const BUTTON_SEPARATION := 24

## 试听的**最小间隔** ms：拖动音效滑条时松手会补放一声，连点凹槽也可能触发 ——
## 不加闸门会变成"哒哒哒"一串（计时按绝对时刻，不变量 I-13）。
const PREVIEW_MIN_INTERVAL_MS := 250

var _root: Control = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _music_value: Label = null
var _sfx_value: Label = null
## 打开时的音量快照（「退出」要还原到它）。
var _snapshot_music_db: float = 0.0
var _snapshot_sfx_db: float = 0.0
## 程序性写滑条值（`open()` 摆位）时**不要**触发"实时写总线"那条副作用。
var _applying: bool = false
var _dragging_sfx: bool = false
var _last_preview_ms: int = 0
var _scene_checks: Dictionary = {}
var _built: bool = false
var _fullscreen_check: CheckBox = null
var _snapshot_window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var _snapshot_bindings: Dictionary = {}
var _key_buttons: Dictionary = {}
var _listening_action: String = ""
var _section_pages: Array = []
var _section_tabs: Array = []
var _section_index: int = 0

# ---------------------------------------------------------------- 打开 / 关闭
## 打开：记快照 → 滑条摆到快照值 → 显示。⚠️ **不隐藏底下的界面**（本层只是盖上去的一层）。
func open() -> void:
	_ensure_built()
	_listening_action = ""
	var audio := _audio()
	if audio != null:
		_snapshot_music_db = audio.music_db()
		_snapshot_sfx_db = audio.sfx_db()
	## ⚠️ **2026-11-03**：窗口模式 / 按键的**快照与音频层无关**，原来一并塞在上面那个 `if audio != null` 里 ——
	## 音频层一旦找不到，`_snapshot_window_mode` 就停在默认的「窗口化」，
	## 于是点「退出」时 `cancel()` 会把**正在全屏**的窗口按回窗口化（用户："游戏界面还是没有全屏"）。
	_snapshot_window_mode = DisplayServer.window_get_mode()
	_snapshot_bindings = InputBindings.snapshot()
	_applying = true
	_music_slider.value = _db_to_slider(_snapshot_music_db)
	_sfx_slider.value = _db_to_slider(_snapshot_sfx_db)
	if _fullscreen_check != null:
		_fullscreen_check.button_pressed = _window_is_fullscreen(_snapshot_window_mode)
	_applying = false
	_refresh_value_labels()
	_show_scene_checks()
	_refresh_key_buttons()
	_show_section(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   ## 滑块要光标（`05_ui_hud.md#4`）
	_root.visible = true

func is_open() -> bool:
	return _root != null and _root.visible

## 收起来（"回到打开设置前的那个界面"就是这一步 —— 底下的界面一直还在）。
func close() -> void:
	if _root != null:
		_root.visible = false

# ---------------------------------------------------------------- 两个按钮
## 「退出」= **修改无效**：把打开时的快照写回总线，再收起来。
func cancel() -> void:
	_listening_action = ""
	_write_buses(_snapshot_music_db, _snapshot_sfx_db)
	_apply_window_mode(_snapshot_window_mode)
	InputBindings.restore(_snapshot_bindings)
	close()

## 「启用」= **修改生效**：滑条早就实时写进总线了，这里只是把当前值确认为新基线（下次打开看到的是它）。
func apply() -> void:
	_listening_action = ""
	var audio := _audio()
	if audio != null:
		_snapshot_music_db = audio.music_db()
		_snapshot_sfx_db = audio.sfx_db()
	for scene_id in _scene_checks.keys():
		var box := _scene_checks[scene_id] as CheckBox
		if box != null:
			GameConfig.set_battle_scene_enabled(String(scene_id), box.button_pressed)
	UserPrefs.save_current(_audio())
	close()

func _on_cancel_pressed() -> void:
	cancel()

func _on_apply_pressed() -> void:
	apply()

# ---------------------------------------------------------------- 构建
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	layer = SETTINGS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = "SettingsRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS   ## 暂停中照样能点（与暂停菜单同理）
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  ## 吃掉背后界面的点击
	_root.visible = false
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	## 面板外观复用 `UiStyle`（与选项按钮同一份深底 + 边框），不在这里另造一套颜色。
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UiStyle.option_style(UiStyle.PANEL, 2))
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "SettingsBox"
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	panel.add_child(box)

	box.add_child(UiStyle.make_label("设置", UiStyle.FONT_LARGE))

	var tabs := HBoxContainer.new()
	tabs.name = "SectionTabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	var titles: PackedStringArray = ["视频", "音频", "地图", "按键"]
	for index in titles.size():
		var tab := Button.new()
		tab.name = "SectionTab_%d" % index
		tab.text = titles[index]
		UiStyle.decorate_chip(tab)
		tab.custom_minimum_size = Vector2(108.0, 40.0)
		tab.pressed.connect(_show_section.bind(index))
		tab.mouse_entered.connect(_on_section_tab_hover.bind(index, true))
		tab.mouse_exited.connect(_on_section_tab_hover.bind(index, false))
		tabs.add_child(tab)
		_section_tabs.append(tab)

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.custom_minimum_size = Vector2(520.0, 440.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "SettingsList"
	list.add_theme_constant_override("separation", ROW_SEPARATION)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var video := _add_page(list, 0)
	_add_section(video, "视频", "SectionVideo")
	_fullscreen_check = CheckBox.new()
	_fullscreen_check.name = "VideoFullscreen"
	_fullscreen_check.text = "全屏"
	_style_check(_fullscreen_check)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_fullscreen_check.custom_minimum_size = Vector2(220.0, 36.0)
	video.add_child(_fullscreen_check)

	var audio := _add_page(list, 1)
	_add_section(audio, "音频", "SectionAudio")
	_music_slider = _add_slider_row(audio, "音乐", "MusicRow", true)
	_sfx_slider = _add_slider_row(audio, "音效", "SfxRow", false)

	var maps := _add_page(list, 2)
	_add_section(maps, "地图", "SectionMap")
	var scene_hint := UiStyle.make_label("勾上的才会被抽到。一个都不勾，用现在的灰场地。", UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
	scene_hint.name = "SceneHint"
	scene_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scene_hint.custom_minimum_size = Vector2(460.0, 0.0)
	maps.add_child(scene_hint)
	_add_scene_checks(maps)

	var keys := _add_page(list, 3)
	_add_section(keys, "按键", "SectionKeys")
	var key_hint := UiStyle.make_label("点右边的键，再按一颗新的。Esc 取消这一次。鼠标和 Esc 不能设成按键。同一颗键只留给最后设的那一项。", UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
	key_hint.name = "KeyHint"
	key_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_hint.custom_minimum_size = Vector2(460.0, 0.0)
	keys.add_child(key_hint)
	_add_key_rows(keys)
	_show_section(0)

	var buttons := HBoxContainer.new()
	buttons.name = "ButtonRow"
	buttons.add_theme_constant_override("separation", BUTTON_SEPARATION)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_add_button(buttons, "退出", _on_cancel_pressed)
	_add_button(buttons, "启用", _on_apply_pressed)

	_refresh_value_labels()
	_show_scene_checks()

func _add_page(parent: VBoxContainer, index: int) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "SectionPage_%d" % index
	page.add_theme_constant_override("separation", ROW_SEPARATION)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(page)
	_section_pages.append(page)
	return page


func _show_section(index: int) -> void:
	if _listening_action != "":
		_listening_action = ""
		_refresh_key_buttons()
	_section_index = index
	for page_index in _section_pages.size():
		var page := _section_pages[page_index] as Control
		if page != null:
			page.visible = page_index == index
	for tab_index in _section_tabs.size():
		var tab := _section_tabs[tab_index] as Button
		if tab == null:
			continue
		UiStyle.apply_chip_selected(tab, tab_index == index)
		UiStyle.apply_chip_hover(tab, tab_index == index)


func _on_section_tab_hover(index: int, hovered: bool) -> void:
	var tab := _section_tabs[index] as Button
	if tab == null:
		return
	UiStyle.apply_chip_hover(tab, hovered or index == _section_index)


func _add_section(box: VBoxContainer, title: String, node_name: String) -> void:
	var label := UiStyle.make_label(title, UiStyle.FONT_MID, UiStyle.COLOR_WARN)
	label.name = node_name
	box.add_child(label)


func _style_check(check: CheckBox) -> void:
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", UiStyle.FONT_MID)
	check.add_theme_color_override("font_color", UiStyle.COLOR_TEXT)
	check.add_theme_color_override("font_hover_color", UiStyle.COLOR_TEXT)
	check.add_theme_color_override("font_pressed_color", UiStyle.COLOR_WARN)


func _add_scene_checks(box: VBoxContainer) -> void:
	var names := {
		"forest": "SceneForest",
		"mountain": "SceneMountain",
		"desert": "SceneDesert",
		"snow": "SceneSnow",
		"city": "SceneCity",
	}
	for scene_id in GameConfig.battle_scene_ids():
		var id := String(scene_id)
		var check := CheckBox.new()
		check.name = String(names.get(id, "SceneCheck"))
		check.text = GameConfig.battle_scene_name(id)
		_style_check(check)
		box.add_child(check)
		_scene_checks[id] = check

func _show_scene_checks() -> void:
	for scene_id in _scene_checks.keys():
		var box := _scene_checks[scene_id] as CheckBox
		if box != null:
			box.button_pressed = GameConfig.is_battle_scene_enabled(String(scene_id))

## 加一行"名字 + 滑条 + 百分比"。滑条 = **滑动变阻器**（连续值，不是档位按钮）：
## 0 ~ 100% 线性映射到总线音量（`_slider_to_db()`）。
## ⚠️ 名字列与百分比列都写死最小宽度：不写的话，百分比从 "100%" 变 "9%" 会让滑条跟着重排、滑条自己左右抖。
## ⚠️ **音乐那一行不接试听**（BGM 本身正在响，拖滑条当场就听得出大小）；只有音效行接
## "松手补一声"（见 `_on_sfx_drag_ended()`）—— 接线在这里一次定好，不留空转的回调。
func _add_slider_row(box: VBoxContainer, title: String, row_name: String, is_music: bool) -> HSlider:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var caption := UiStyle.make_label(title, UiStyle.FONT_MID)
	caption.custom_minimum_size = Vector2(LABEL_MIN_WIDTH, 0.0)
	row.add_child(caption)

	var slider := HSlider.new()
	slider.name = row_name + "Slider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = SLIDER_MIN_SIZE
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE      ## Space 是 cam_up / ui_accept，别误触发
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if is_music:
		slider.value_changed.connect(_on_music_changed)
	else:
		slider.value_changed.connect(_on_sfx_changed)
		slider.drag_started.connect(_on_sfx_drag_started)
		slider.drag_ended.connect(_on_sfx_drag_ended)
	row.add_child(slider)

	var percent := UiStyle.make_label("100%", UiStyle.FONT_MID, UiStyle.COLOR_DIM)
	percent.name = row_name + "Value"
	percent.custom_minimum_size = Vector2(PERCENT_MIN_WIDTH, 0.0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(percent)
	if is_music:
		_music_value = percent
	else:
		_sfx_value = percent
	return slider

func _add_button(box: HBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	## §3.1：动态节点必须命名，且**不拿显示文字当标识符**（序号写在 `_` 之后）
	button.name = "SettingButton_%d" % box.get_child_count()
	button.text = text
	UiStyle.decorate_option(button)
	button.mouse_entered.connect(UiStyle.apply_option_hover.bind(button, true))
	button.mouse_exited.connect(UiStyle.apply_option_hover.bind(button, false))
	button.pressed.connect(handler)
	box.add_child(button)
	return button

# ---------------------------------------------------------------- 滑条 → 音量
## "滑动变阻器"的映射：滑条 0~1 线性值 → 总线 dB。
## ⚠️ 拉到 0 时**不能**写 `linear_to_db(0)`（= −inf ⇒ 总线变 NaN），夹到 `MIN_VOLUME_DB`。
static func _slider_to_db(value: float) -> float:
	if value <= 0.001:
		return AudioManager.MIN_VOLUME_DB
	return maxf(linear_to_db(value), AudioManager.MIN_VOLUME_DB)

static func _db_to_slider(db: float) -> float:
	return clampf(db_to_linear(db), 0.0, 1.0)

func _on_music_changed(value: float) -> void:
	if _applying:
		return
	var audio := _audio()
	if audio != null:
		audio.set_music_db(_slider_to_db(value))   ## 实时生效 = 音乐大小当场可听（BGM 正在放）
	_refresh_value_labels()

func _on_sfx_changed(value: float) -> void:
	if _applying:
		return
	var audio := _audio()
	if audio != null:
		audio.set_sfx_db(_slider_to_db(value))
	_refresh_value_labels()
	if not _dragging_sfx:
		_preview_sfx()          ## 直接点凹槽跳值（没在拖）时立刻试听一声

func _on_sfx_drag_started() -> void:
	_dragging_sfx = true

## 松手时补放一声（用户口径里的"预览修改后的效果"）—— 拖动过程中不出声，免得拖一次响一片。
func _on_sfx_drag_ended(value_changed: bool) -> void:
	_dragging_sfx = false
	if value_changed:
		_preview_sfx()

func _preview_sfx() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_preview_ms < PREVIEW_MIN_INTERVAL_MS:
		return
	_last_preview_ms = now
	var audio := _audio()
	if audio != null:
		audio.preview_sfx()

func _refresh_value_labels() -> void:
	if _music_value != null and _music_slider != null:
		_music_value.text = "%d%%" % int(round(_music_slider.value * 100.0))
	if _sfx_value != null and _sfx_slider != null:
		_sfx_value.text = "%d%%" % int(round(_sfx_slider.value * 100.0))

func _write_buses(music_db: float, sfx_db: float) -> void:
	var audio := _audio()
	if audio == null:
		return
	audio.set_music_db(music_db)
	audio.set_sfx_db(sfx_db)

## 音频层：用组查找（`AudioManager.find()`），**不让界面知道 `main`** —— 见 `AudioManager.GROUP` 的说明。
## 取不到时返回 null（合法状态：本层还没建起来），调用方一律自己兜住。
func _audio() -> AudioManager:
	return AudioManager.find(get_tree())

# ---------------------------------------------------------------- 输入
## ESC = 「退出」（与那个按钮同义：修改无效）。⚠️ **必须吃掉这一下**：暂停菜单也认 ESC，
## 不吃的话按一下会"关掉设置 + 顺手把暂停菜单也关了"（两个都收到同一个事件）。
func _add_key_rows(box: VBoxContainer) -> void:
	var index := 0
	for action in InputBindings.ACTIONS:
		var row := HBoxContainer.new()
		row.name = "KeyRow_%d" % index
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var caption := UiStyle.make_label(InputBindings.action_label(action), UiStyle.FONT_MID)
		caption.custom_minimum_size = Vector2(120.0, 0.0)
		row.add_child(caption)
		var button := Button.new()
		button.name = "KeyButton_%d" % index
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(160.0, 36.0)
		button.add_theme_font_size_override("font_size", UiStyle.FONT_MID)
		button.pressed.connect(_on_key_button_pressed.bind(action))
		row.add_child(button)
		_key_buttons[action] = button
		index += 1
	_refresh_key_buttons()


func _refresh_key_buttons() -> void:
	for action in _key_buttons.keys():
		var button := _key_buttons[action] as Button
		if button == null:
			continue
		if action == _listening_action:
			button.text = "请按键"
		else:
			button.text = InputBindings.key_label(String(action))


func _on_key_button_pressed(action: String) -> void:
	_listening_action = "" if _listening_action == action else action
	_refresh_key_buttons()


func _on_fullscreen_toggled(on: bool) -> void:
	if _applying:
		return
	_apply_window_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _window_is_fullscreen(mode: int) -> bool:
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _apply_window_mode(mode: int) -> void:
	UserPrefs.set_fullscreen(_window_is_fullscreen(mode))


func _input(event: InputEvent) -> void:
	if not is_open() or _listening_action == "":
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code != KEY_ESCAPE:
		InputBindings.set_physical(_listening_action, code)
	_listening_action = ""
	_refresh_key_buttons()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or _listening_action != "":
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	cancel()
	get_viewport().set_input_as_handled()
