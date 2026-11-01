class_name SandboxHud
extends CanvasLayer
## 沙盒模式的界面层：**顶栏（双方总权重）** + **底部兵种栏** + 开战按钮 + 战果浮层 + 暂停菜单。
##
## 依据（用户 2026-09-25 口径）：底部是兵种栏（选要摆什么）、顶部显示双方总权重、
## 相机操作提示与竞猜模式一字不差；布兵阶段**不许**出现「重新开始」，战斗阶段它变成「结束战斗」。
##
## ⚠️ 为什么**另起一个文件**而不是往 `hud.gd` 里塞分支：经典 HUD 读的是 `Game`（轮次 / 点数 /
## 观望机会 / 下注面板 / 兴奋圈倒计时），而沙盒里这一整套**都不存在**（没有押注、没有圈、没有时限）——
## 合在一起会长出一堆"沙盒时跳过这段"的分支，而两处真正共用的东西已经抽走了：
##   · 外观与调色板 → `scripts/ui/ui_style.gd`（`UiStyle`）
##   · 暂停菜单     → `scripts/ui/pause_menu.gd`（`PauseMenu`，本层持有并 `configure()`）
##
## 边界同 `hud.gd`：只读 `Sandbox` 的公开状态、只调它的公开方法，不直接改玩法数据（R-07）。

## 底部兵种栏：**一排（单行）横向滚动**。
## ⚠️ **2026-09-27 第十一轮（用户："不要把能放置的兵种全都列出来，而是排成一排，显示一部分，
## 通过鼠标移至兵种选择的地方后滑动滚轮来移动兵种排列的地方"）**：原来是 `GridContainer` 6 列全列出来
##（兵种 17 时 3 行、18 时 3 行、**19 时 4 行** ⇒ 面板要被顶高）⇒ 现在改成
## **`ScrollContainer` + `HBoxContainer`**：一排装得下就装、装不下就靠滚轮（或两侧箭头）横着推。
##   ① 可见张数由**面板宽度**决定（原先那 6 列的宽度预算没变 ⇒ 大约可见 6 张）；
##   ② **滚轮一次走一张卡**（`ensure_control_visible(下一张)` ⇒ 恰好"推一格"，两端自动夹住）；
##   ③ 两端各有一颗箭头按钮（还有内容时才显示），给没有滚轮的玩家留一条路；
##   ④ ⚠️ 滚轮事件在**卡上也要接**（鼠标停在兵种卡上滚轮照样生效 —— 用户口径是"鼠标移至兵种选择的
##      地方"，那一带全是卡）⇒ 每张卡也连 `gui_input`，并且 `accept_event()` 把事件吃掉，
##      免得同一次滚轮又被 3D 相机当成缩放（沙盒的相机操作与竞猜一致）。
## 面板高度不写死。首帧用这个数占位，之后 `_fit_palette()` 按内容把底边以上的空档收掉。
const PALETTE_HEIGHT := 240.0
const REFRESH_MS := 100                  ## 顶栏刷新节流（与经典 HUD 的 10 Hz 同频）
## 单排里**两张卡之间**的间距（px）：与原网格的 `h_separation` 同值 —— 给"悬停原地放大"留白
## （小卡放大 `UiStyle.CHIP_GROW` 倍后每侧约长 11 px，间距不够就会盖住邻居）。
const CHIP_ROW_SEPARATION := 14
## 单排容器的**垂直余量**（px，加在卡高之上）：同样是为了让"悬停放大"不被 `ScrollContainer` 裁掉。
const CHIP_ROW_GROW_PAD := 16.0
## 两端箭头按钮的宽度（px）—— 窄条，不抢卡的宽度预算。
const PALETTE_ARROW_W := 24.0
## 单排里**同时看得见几张卡**（用户 2026-09-27 第十一轮选定："**6 张可见 / 滚轮 1 张**"）。
## ⚠️ 它是"滚动区的最小宽度"的口径来源（见 `_build_palette()`），**不是**一个硬性裁剪：
## 窗口更宽时可见的会更多（面板宽了就多露几张，这是好事）。
const CHIP_VISIBLE_TARGET := 6

## 字号档位与调色板：**唯一一份在 `UiStyle`**（与经典 HUD 共用），这里只是本地别名。
const FONT_LARGE := UiStyle.FONT_LARGE
const FONT_MID := UiStyle.FONT_MID
const FONT_SMALL := UiStyle.FONT_SMALL
const FONT_TINY := UiStyle.FONT_TINY
const COLOR_TEAM := UiStyle.COLOR_TEAM
const COLOR_TEXT := UiStyle.COLOR_TEXT
const COLOR_DIM := UiStyle.COLOR_DIM
const COLOR_WARN := UiStyle.COLOR_WARN

var sandbox: Sandbox = null
var camera_rig: CameraRig = null

var _mode_label: Label = null
var _weight_a: Label = null
var _weight_b: Label = null
var _clear_a: Button = null              ## 顶部「清空」：赤羽卫（偏左）
var _clear_b: Button = null              ## 顶部「清空」：青锋卫（与它对称）
var _alive_a: Label = null
var _hp_a: Label = null
var _alive_b: Label = null
var _hp_b: Label = null
var _gear: Button = null
## 倍速按钮（2026-11-01）：顶栏右端、齿轮左边。外观与接线在 `UiStyle.make_speed_button()`（三套 HUD 共用）。
var _speed_button: Button = null

var _palette_panel: PanelContainer = null
var _chips: Dictionary = {}              ## 兵种 ID → 小卡按钮（只建一次，之后只改"选中"外观）
## 单排滚动（2026-09-27 第十一轮）：滚动区 + 两端箭头 + 显示顺序。
## ⚠️ `_palette_order` 必须与 `_chips` 的建卡顺序逐位一致（`_scroll_palette()` 用它取"第一张卡"量步长）。
var _palette_scroll: ScrollContainer = null
var _palette_left_button: Button = null
var _palette_right_button: Button = null
var _palette_order: Array = []
var _start_button: Button = null
var _overview_button: Button = null
var _view_button: Button = null
var _palette_hint: Label = null
var _camera_hint: Label = null
var _place_tech_row: HBoxContainer = null
var _place_tech_buttons: Array = []
var _place_tech_effect: Label = null
var _chip_style_key: String = ""
var _tech_style_key: String = ""
var _inspect_panel: PanelContainer = null
var _inspect_title: Label = null
var _inspect_body: Label = null
var _inspect_note: Label = null

var _overlay: Control = null
var _top_bar: PanelContainer = null
var _overlay_title: Label = null
var _overlay_body: Label = null
var _overlay_button: Button = null

## 点「召唤石柱」卡片时弹的那一问（2026-09-25 第七轮，用户口径："在沙盒中点击『召唤石柱按钮』后
## 能够选择『是否开启权重递增模式』"）。
## ⚠️ 它是**一层挡住全屏的幕**（`SummonScrim`，`MOUSE_FILTER_STOP`）：否则玩家点面板之外的地方时，
## 那一下会落进 `Sandbox._unhandled_input()`，在场上凭空摆出一个兵。
var _summon_scrim: ColorRect = null
var _summon_panel: PanelContainer = null
var _summon_body: Label = null

var _pause: PauseMenu = null
var _refresh_ms: int = 0

func build(p_sandbox: Sandbox, p_camera: CameraRig) -> void:
	sandbox = p_sandbox
	camera_rig = p_camera
	## ⚠️ 与经典 HUD 同一个理由：暂停菜单（含它的渐暗 / 渐亮）必须在"整棵树暂停"时照样跑。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	_pause.configure(sandbox, self)      ## `Sandbox` 管暂停 / 恢复，本层管"哪一项能出现"
	_build_top_bar()
	_build_palette()
	_build_inspect_panel()
	_build_summon_panel()
	_build_overlay()
	sandbox.phase_changed.connect(_on_phase_changed)
	_refresh()

# ---------------------------------------------------------------- 顶栏（双方总权重）
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	_top_bar = bar
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 64.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.34, 0.40, 1.0)
	style.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	var row := HBoxContainer.new()
	row.name = "TopBarRow"               ## §3.1：动态生成的节点也必须命名（齿轮挂在这一行里）
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	## ⚠️ 2026-09-25 用户："**沙盒模式新增『清空』按钮，赤羽卫的清空在顶部偏左边，青锋卫与之对称**" ⇒
	## 顶栏排成**镜像**的两半：左 = 模式名 · 赤羽卫总权重 · **[清空赤羽卫]**；右 = **[清空青锋卫]** · 青锋卫总权重 · 战况 · 齿轮。
	## 两个「清空」因此关于中线一左一右，各自紧挨着自己那一队的权重；只在布兵阶段出现（见 `_refresh_top()`）。
	_mode_label = _make_label("沙盒模式", FONT_MID, COLOR_DIM, "ModeLabel")
	row.add_child(_mode_label)
	## 用户口径：**顶部显示双方总权重**。它显示的是"这一场带了多少兵"（已摆下的清单），
	## 战斗中单位阵亡也不会变 —— 那是"阵容"，与"当前还剩多少血"是两件事（后者在右边）。
	_weight_a = _make_label("", FONT_MID, COLOR_TEAM[0], "Weight_a")
	row.add_child(_weight_a)
	_clear_a = _make_clear_button(0)
	row.add_child(_clear_a)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_clear_b = _make_clear_button(1)
	row.add_child(_clear_b)
	_weight_b = _make_label("", FONT_MID, COLOR_TEAM[1], "Weight_b")
	row.add_child(_weight_b)

	_alive_a = _make_label("", FONT_SMALL, COLOR_TEAM[0], "Alive_a")
	row.add_child(_alive_a)
	_hp_a = _make_label("", FONT_TINY, COLOR_DIM, "Hp_a")
	row.add_child(_hp_a)
	_alive_b = _make_label("", FONT_SMALL, COLOR_TEAM[1], "Alive_b")
	row.add_child(_alive_b)
	_hp_b = _make_label("", FONT_TINY, COLOR_DIM, "Hp_b")
	row.add_child(_hp_b)

	## 倍速（2026-11-01）：插在齿轮左边（齿轮是顶栏最右一格，见竞猜 HUD 同一条口径）。
	## ⚠️ 倍速**常显**（2026-11-01 修 bug：用户"战斗开始后无法点加速"）：
	## 战斗中正要用它，而那时光标被 `CameraRig` 锁住 ⇒ 靠快捷键 `F` 切（见 `UiStyle`），
	## 按钮本身必须一直亮着（`Button.shortcut` 只在可见时才派发），顺便让人看见当前是几倍。
	_speed_button = UiStyle.make_speed_button("SpeedButton")
	row.add_child(_speed_button)

	_gear = Button.new()
	_gear.name = "GearButton"
	UiStyle.decorate_gear(_gear)         ## 与竞猜 HUD 是**同一个**齿轮（`UiStyle` 里只有一份）
	_gear.visible = false                ## 只在"光标可见"的相位显示（见 _refresh_top）
	_gear.pressed.connect(_pause.open)
	row.add_child(_gear)

## 顶栏上的一个「清空」按钮（一队一个）。
## 外观走沙盒那一档（`UiStyle.decorate_chip`），但**尺寸压到 88×36** —— 顶栏只有 64 px 高，
## 兵种小卡那档的 118×62 塞不进去；36 高放大 `CHIP_GROW` 后 ≈ 42，正好落在顶栏内边距里。
func _make_clear_button(team: int) -> Button:
	var button := Button.new()
	button.name = "ClearTeam_%d" % team
	button.text = "清空"
	button.tooltip_text = "把%s已摆下的兵全部收掉（只在布兵阶段可用）" % GameConfig.team_name(team)
	UiStyle.decorate_chip(button)
	button.custom_minimum_size = Vector2(88.0, 36.0)
	button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(button, true))
	button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(button, false))
	button.pressed.connect(_on_clear_pressed.bind(team))
	return button

# ---------------------------------------------------------------- 底部兵种栏
## 结构：一行 = 左边【说明 + 兵种网格】，右边【开战 / 自由视角 / 视角提示】。
## ⚠️ 面板默认 `MOUSE_FILTER_STOP` ⇒ 点在界面上的**不会被 `Sandbox._unhandled_input()` 收走**，
## 所以"点兵种卡"绝不会顺手在场上放一个兵（这正是布兵要的）。
func _build_palette() -> void:
	_palette_panel = PanelContainer.new()
	_palette_panel.name = "PalettePanel"
	_palette_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_palette_panel.offset_left = 16.0
	_palette_panel.offset_right = -16.0
	_palette_panel.offset_top = -PALETTE_HEIGHT
	_palette_panel.offset_bottom = -16.0
	_palette_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_palette_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.93)
	style.border_color = Color(0.32, 0.36, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_palette_panel.add_theme_stylebox_override("panel", style)
	add_child(_palette_panel)

	var row := HBoxContainer.new()
	row.name = "PaletteRow"
	row.add_theme_constant_override("separation", 24)
	_palette_panel.add_child(row)

	var left := VBoxContainer.new()
	left.name = "PaletteBox"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_palette_hint = _make_label("", FONT_SMALL, COLOR_TEXT, "PaletteHintLabel")
	_palette_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_palette_hint.custom_minimum_size = Vector2(0.0, 40.0)
	left.add_child(_palette_hint)

	## 单排：`[◀][滚动区][▶]`。⚠️ 箭头是三件里唯一"可以没有"的（滚轮是主路）⇒ 两端到顶时它会淡出
	## （**保留占位**，见 `_refresh_palette_arrows()` 的理由）。
	var strip := HBoxContainer.new()
	strip.name = "ChipStrip"
	strip.add_theme_constant_override("separation", 8)
	left.add_child(strip)

	_palette_left_button = Button.new()
	_palette_left_button.name = "ChipScrollLeft"
	_palette_left_button.text = "◀"
	_palette_left_button.flat = true
	_palette_left_button.focus_mode = Control.FOCUS_NONE
	_palette_left_button.tooltip_text = "往前翻一个兵种（也可以用滚轮）"
	_palette_left_button.custom_minimum_size = Vector2(PALETTE_ARROW_W, 0.0)
	_palette_left_button.pressed.connect(_scroll_palette.bind(-1))
	strip.add_child(_palette_left_button)

	## 滚动区：横向可滚、**滚动条不画出来**（`SCROLL_MODE_SHOW_NEVER` = 能滚但不显示条），
	## 纵向关掉（单排不需要）—— 高度由 `_refresh_palette()` 按实测卡高 + 悬停余量设。
	_palette_scroll = ScrollContainer.new()
	_palette_scroll.name = "ChipScroll"
	_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## ⚠️ **必须给滚动区一个最小宽度**：`ScrollContainer` 自身的最小宽是 **0**（它可以无限缩），
	## 不给的话这一栏的宽度会由"说明文字有多长"决定 ⇒ "可见几张卡"变成碰运气。
	## 这里按用户选的口径钉死 **6 张**（拿 `UiStyle.CHIP_MIN_SIZE.x` 算，不写死像素）。
	_palette_scroll.custom_minimum_size = Vector2(
			UiStyle.CHIP_MIN_SIZE.x * float(CHIP_VISIBLE_TARGET)
					+ float(CHIP_ROW_SEPARATION * (CHIP_VISIBLE_TARGET - 1)),
			UiStyle.CHIP_MIN_SIZE.y + CHIP_ROW_GROW_PAD)
	_palette_scroll.gui_input.connect(_on_palette_gui_input)
	_palette_scroll.add_to_group("palette_wheel")
	strip.add_child(_palette_scroll)

	var row_box := HBoxContainer.new()
	row_box.name = "ChipRow"
	row_box.add_theme_constant_override("separation", CHIP_ROW_SEPARATION)
	_palette_scroll.add_child(row_box)

	_palette_right_button = Button.new()
	_palette_right_button.name = "ChipScrollRight"
	_palette_right_button.text = "▶"
	_palette_right_button.flat = true
	_palette_right_button.focus_mode = Control.FOCUS_NONE
	_palette_right_button.tooltip_text = "往后翻一个兵种（也可以用滚轮）"
	_palette_right_button.custom_minimum_size = Vector2(PALETTE_ARROW_W, 0.0)
	_palette_right_button.pressed.connect(_scroll_palette.bind(1))
	strip.add_child(_palette_right_button)

	## ⚠️ 顺序是**按权重从小到大**（用户 2026-09-25："兵种按权重大小排列"），见 `_types_by_weight()`。
	_palette_order.clear()
	for type_id in _types_by_weight():
		var tid := String(type_id)
		_palette_order.append(tid)
		_add_chip(row_box, tid)
	## 建完就把箭头状态摆对（否则要等 100 ms 的定时刷新才正确：实机首帧会看到两颗都亮）
	_refresh_palette_arrows()
	_build_place_techs(left)

	var right := VBoxContainer.new()
	right.name = "ActionBox"
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)

	## 「开战」：与开始界面的「开始游戏」同一种外观（同一份 `UiStyle.decorate_option`）。
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = "开战"
	_start_button.tooltip_text = "让场上的两军开打（开战后光标会锁进窗口，按 Esc 可以「结束战斗」）"
	UiStyle.decorate_option(_start_button)
	_start_button.mouse_entered.connect(UiStyle.apply_option_hover.bind(_start_button, true))
	_start_button.mouse_exited.connect(UiStyle.apply_option_hover.bind(_start_button, false))
	_start_button.pressed.connect(_on_start_pressed)
	right.add_child(_start_button)

	## 「自由视角」：与经典下注面板上那颗**同名同义**（内部仍走 `CameraRig.toggle_overview()`）。
	_overview_button = Button.new()
	_overview_button.name = "OverviewButton"
	_overview_button.text = "自由视角"
	_overview_button.tooltip_text = "进入自由视角（隐藏界面、隐藏光标；鼠标转向，点左键或右键退出）"
	UiStyle.decorate_chip(_overview_button)
	_overview_button.custom_minimum_size = Vector2(0.0, 44.0)
	_overview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(_overview_button, true))
	_overview_button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(_overview_button, false))
	_overview_button.pressed.connect(_on_overview_pressed)

	_view_button = Button.new()
	_view_button.name = "ViewModeButton"
	_view_button.text = "查看模式"
	_view_button.tooltip_text = "打开后，左键和右键都只用来点选场上的兵，查看数值和科技"
	UiStyle.decorate_chip(_view_button)
	_view_button.custom_minimum_size = Vector2(0.0, 44.0)
	_view_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(_view_button, true))
	_view_button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(_view_button, false))
	_view_button.pressed.connect(_on_view_mode_pressed)

	var actions := HBoxContainer.new()
	actions.name = "ActionRow"
	actions.add_theme_constant_override("separation", 8)
	actions.add_child(_overview_button)
	actions.add_child(_view_button)
	right.add_child(actions)

	_camera_hint = _make_label(UiStyle.camera_hint(), FONT_TINY, COLOR_DIM, "CameraHintLabel")
	var hint := _camera_hint
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0.0, 22.0)
	left.add_child(hint)
	_fit_palette()

	## ⚠️ 右侧留白 52 px：给「开战」按钮的**悬停放大**留地方 —— 按钮宽 280、放大 `UiStyle.HOVER_GROW`
	## 倍 ⇒ 每侧要长 56 px，而面板右内边距只有 12 px ⇒ 不留白的话按钮会顶出屏幕右边被切掉一截。
	var pad := Control.new()
	pad.name = "RightPad"
	pad.custom_minimum_size = Vector2(52.0, 0.0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

## 一张兵种小卡：名字 + 权重（权重是玩家唯一需要参考的数 —— 顶部那两行总权重就是它累加出来的）。
## ⚠️ 参数类型是 `HBoxContainer`（单排）—— 2026-09-27 第十一轮由 `GridContainer` 改来；
## 本函数体只用到 `add_child()`，所以两种容器都成立，改类型只是为了"读起来就是单排"。
func _add_chip(row: HBoxContainer, type_id: String) -> void:
	var button := Button.new()
	button.name = "Chip_%s" % type_id    ## 纯英文 + 兵种 ID（§3.1）
	button.text = "%s\n权重 %d" % [GameConfig.profile_name(type_id), _type_weight(type_id)]
	UiStyle.decorate_chip(button)
	button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(button, true))
	button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(button, false))
	button.pressed.connect(_on_chip_pressed.bind(type_id))
	## ⚠️ **滚轮要在卡上也接**：用户口径是"鼠标移至兵种选择的地方后滑动滚轮"，而那一带全是卡 ——
	## 只在滚动区的空白处接的话，玩家把鼠标放在卡上滚轮就**没反应**。见 `_on_palette_gui_input()`。
	button.gui_input.connect(_on_palette_gui_input)
	row.add_child(button)
	_chips[type_id] = button

## 选中兵种之后，在兵种卡下面排出这个兵种的科技。再点一次取消。没有科技的兵种这一行藏起来。
func _build_place_techs(parent: VBoxContainer) -> void:
	_place_tech_row = HBoxContainer.new()
	_place_tech_row.name = "PlaceTechRow"
	_place_tech_row.add_theme_constant_override("separation", CHIP_ROW_SEPARATION)
	_place_tech_row.add_to_group("palette_wheel")
	_place_tech_row.visible = false
	parent.add_child(_place_tech_row)
	for type_id in GameConfig.ROGUELIKE_TECH_TYPES:
		for spec in GameConfig.roguelike_tech_list(String(type_id)):
			var tech_id := String(spec.get("id", ""))
			var button := Button.new()
			button.name = "PlaceTech_%s_%s" % [type_id, tech_id]
			button.text = String(spec.get("name", tech_id))
			button.tooltip_text = GameConfig.roguelike_tech_desc(String(type_id), tech_id)
			UiStyle.decorate_chip(button)
			button.mouse_entered.connect(_on_place_tech_hover.bind(button, String(type_id), tech_id, true))
			button.mouse_exited.connect(_on_place_tech_hover.bind(button, String(type_id), tech_id, false))
			button.pressed.connect(_on_place_tech_pressed.bind(String(type_id), tech_id))
			_place_tech_row.add_child(button)
			_place_tech_buttons.append({"type_id": String(type_id), "tech_id": tech_id, "button": button})
	_place_tech_effect = _make_label("", FONT_TINY, COLOR_DIM, "PlaceTechEffectLabel")
	## 三行高度一直占着。悬停只换字，不再把底栏撑高。
	_place_tech_effect.custom_minimum_size = Vector2(0.0, 62.0)
	_place_tech_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_tech_effect.max_lines_visible = 3
	_place_tech_effect.clip_text = true
	_place_tech_effect.visible = false
	parent.add_child(_place_tech_effect)

func _on_place_tech_hover(button: Button, type_id: String, tech_id: String, entered: bool) -> void:
	UiStyle.apply_chip_hover(button, entered)
	if _place_tech_effect == null:
		return
	if entered:
		_place_tech_effect.text = "%s：%s" % [
			String(GameConfig.roguelike_tech_def(type_id, tech_id).get("name", tech_id)),
			GameConfig.roguelike_tech_desc(type_id, tech_id)]
	else:
		_place_tech_effect.text = ""

func _on_place_tech_pressed(type_id: String, tech_id: String) -> void:
	if sandbox == null:
		return
	sandbox.toggle_place_tech(type_id, tech_id)
	_refresh_place_techs()

## 查看面板：版式跟肉鸽「选中单位」一样（标题 / 最终数值 / 科技说明），数字由 `Sandbox.viewed_stats()` 给。
func _build_inspect_panel() -> void:
	_inspect_panel = PanelContainer.new()
	_inspect_panel.name = "InspectPanel"
	_inspect_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_inspect_panel.offset_left = 16.0
	_inspect_panel.offset_bottom = -(PALETTE_HEIGHT + 8.0)
	_inspect_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_inspect_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	style.border_color = Color(0.32, 0.36, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_inspect_panel.add_theme_stylebox_override("panel", style)
	_inspect_panel.visible = false
	add_child(_inspect_panel)
	var col := VBoxContainer.new()
	col.name = "InspectBox"
	col.add_theme_constant_override("separation", 8)
	_inspect_panel.add_child(col)
	_inspect_title = _make_label("", FONT_MID, COLOR_TEXT, "InspectTitleLabel")
	col.add_child(_inspect_title)
	_inspect_body = _make_label("", FONT_SMALL, COLOR_TEXT, "InspectBodyLabel")
	_inspect_body.custom_minimum_size = Vector2(360.0, 0.0)
	_inspect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_inspect_body)
	_inspect_note = _make_label("", FONT_TINY, COLOR_DIM, "InspectNoteLabel")
	_inspect_note.custom_minimum_size = Vector2(360.0, 0.0)
	_inspect_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_inspect_note)
	var close := Button.new()
	close.name = "InspectCloseButton"
	close.text = "关闭"
	UiStyle.decorate_chip(close)
	close.custom_minimum_size = Vector2(120.0, 34.0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_on_inspect_close_pressed)
	col.add_child(close)

func _on_inspect_close_pressed() -> void:
	if sandbox != null:
		sandbox.clear_view()
	_refresh_inspect()

## 兵种栏的滚轮（2026-09-27 第十一轮）：一次走**一张卡**。
## ⚠️ 接在**滚动区**与**每一张卡**两处（卡上那一路见 `_add_chip()`）；两条路都走这里。
## ⚠️ 处理完必须**把事件吃掉**：沙盒的相机操作与竞猜一致（滚轮是缩放），不吃掉的话
## 同一次滚轮会**既翻卡又缩放视角**。
## ⚠️ **不能用 `accept_event()`**：那是 `Control` 的方法，而本类 `extends CanvasLayer`
## ⇒ 会**编译不过**（这个坑是第十一轮用引擎实跑抓到的 —— 静态审查只核到"`Control.accept_event()` 在 Godot 4 里存在"，
## 没核它在错的基类上）。等价写法是直接找视口标脏：`get_viewport().set_input_as_handled()`。
func _on_palette_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_palette(-1)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_palette(1)
	else:
		return
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

## 把单排横向推 `step` 张卡（−1 = 往前、+1 = 往后）。
## ⚠️ **按"一张卡的宽度"推进，不要用 `ensure_control_visible()`**：后者只在"那张卡看不见"时才滚
## ⇒ 一排能露 8 张时，前 8 下滚轮**画面纹丝不动**（第十一轮实机抓到的：`scroll_x` 连按 5 下仍是 0）。
## 用户口径是"滚轮一次移一张卡" ⇒ 这里直接加一格宽度、并夹在 [0, 最大可滚量] 之间（两端自然停住）。
## ⚠️ 卡宽取**第一张卡的实际宽度**（118 px，`UiStyle.CHIP_MIN_SIZE` 也是这个数）：各兵种名字长短不同、
## 宽度略有差异，但逐格推进只需要一个稳定的步长。
func _scroll_palette(step: int) -> void:
	if _palette_scroll == null or _palette_order.is_empty():
		return
	var bar := _palette_scroll.get_h_scroll_bar()
	var max_scroll := maxi(int(bar.max_value - bar.page), 0)
	var step_px := UiStyle.CHIP_MIN_SIZE.x + float(CHIP_ROW_SEPARATION)
	var first: Control = _chips.get(String(_palette_order[0])) as Control
	if first != null and first.size.x > 0.0:
		step_px = first.size.x + float(CHIP_ROW_SEPARATION)
	_palette_scroll.scroll_horizontal = clampi(
			_palette_scroll.scroll_horizontal + int(round(step_px * float(step))), 0, max_scroll)
	_refresh_palette_arrows()

## 两端箭头：**还有内容可翻才亮起来**（判据取自滚动条自身的"当前位置 vs 最大可滚量"，
## 不靠"第几张"猜 —— 可见张数随窗口宽度变，猜不准）。
## ⚠️ 用 `modulate.a = 0`（**保留占位**）而不是 `visible = false`：箭头一隐一现会改变滚动区的宽度，
## 宽度一变又可能翻转"还有没有溢出"的结论 ⇒ 窄窗口下两颗箭头会**来回闪**。占位固定就没有这条回路。
func _refresh_palette_arrows() -> void:
	if _palette_scroll == null:
		return
	var bar := _palette_scroll.get_h_scroll_bar()
	var max_scroll := maxi(int(bar.max_value - bar.page), 0)
	_apply_palette_arrow(_palette_left_button, _palette_scroll.scroll_horizontal > 0)
	_apply_palette_arrow(_palette_right_button, _palette_scroll.scroll_horizontal < max_scroll)

func _apply_palette_arrow(button: Button, usable: bool) -> void:
	if button == null:
		return
	button.modulate.a = 1.0 if usable else 0.0
	button.disabled = not usable
	button.mouse_filter = Control.MOUSE_FILTER_STOP if usable else Control.MOUSE_FILTER_IGNORE

## 兵种栏的**显示顺序**：按权重**从小到大**（用户 2026-09-25："兵种按权重大小排列"）。
## ⚠️ 只影响这一栏 —— `GameConfig.TYPE_ORDER` 与经典下注面板的名单文案**一个字都不动**
##（前者的顺序另有含义：配平抽签的遍历序）；同权重的几个保持 `TYPE_ORDER` 里的相对次序。
## ⚠️ 不用 `sort_custom()`：Godot 的排序**不保证稳定**，同权重的卡片次序会随实现变化。
## 这里改成"先收集出现过的权重并升序，再按权重分桶遍历原表"—— 天然稳定、结果可复现。
func _types_by_weight() -> Array:
	var weights: Array = []
	## ⚠️ 名单走 `GameConfig.TYPE_ORDER`，但**跳过"不属于任何池子"的实体**（召唤石柱由它自己那套处理，
	## 指挥所是肉鸽专属的建筑）—— 否则这一栏会多出不该有的卡。
	for type_id in GameConfig.TYPE_ORDER:
		if GameConfig.is_roguelike_only(String(type_id)):
			continue
		var w := _type_weight(String(type_id))
		if not weights.has(w):
			weights.append(w)
	weights.sort()
	var out: Array = []
	for w in weights:
		for type_id in GameConfig.TYPE_ORDER:
			## ⚠️ 这里也要挡一次：指挥所的权重（999）与石柱**同档**，只按权重取会把那张卡又捞回来。
			if GameConfig.is_roguelike_only(String(type_id)):
				continue
			if _type_weight(String(type_id)) == w:
				out.append(String(type_id))
	return out

func _type_weight(type_id: String) -> int:
	return int(GameConfig.profile(type_id)["weight"])

# ---------------------------------------------------------------- 「召唤石柱」的问询层
## 用户口径（2026-09-25 第七轮）："在沙盒中点击『召唤石柱按钮』后能够选择『是否开启权重递增模式』"。
## 结构 = **一块挡全屏的幕 + 一块居中面板**，与战果浮层同一套做法（`_build_overlay()`），
## 区别是它一次只问一件事、两个按钮都能关掉它。
## ⚠️ 幕必须 `MOUSE_FILTER_STOP`：否则面板之外的那一下点击会穿透到 `Sandbox._unhandled_input()`，
## 顺手在场上摆出一个兵（玩家以为自己在"关掉对话框"）。
func _build_summon_panel() -> void:
	_summon_scrim = ColorRect.new()
	_summon_scrim.name = "SummonScrim"
	_summon_scrim.color = Color(0.02, 0.02, 0.03, 0.62)
	_summon_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summon_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_summon_scrim.visible = false
	add_child(_summon_scrim)

	var center := CenterContainer.new()
	center.name = "SummonCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summon_scrim.add_child(center)

	_summon_panel = PanelContainer.new()
	_summon_panel.name = "SummonPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = Color(0.38, 0.42, 0.50, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	_summon_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_summon_panel)

	var col := VBoxContainer.new()
	col.name = "SummonBox"
	col.add_theme_constant_override("separation", 12)
	_summon_panel.add_child(col)

	var title := _make_label("召唤石柱 · 权重递增模式", FONT_MID, COLOR_TEXT, "SummonTitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_summon_body = _make_label("", FONT_SMALL, COLOR_DIM, "SummonBodyLabel")
	_summon_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summon_body.custom_minimum_size = Vector2(560.0, 0.0)
	_summon_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summon_body)

	var row := HBoxContainer.new()
	row.name = "SummonRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	for spec in [["开启权重递增", true], ["不开启", false]]:
		var button := Button.new()
		button.name = "EscalateOnButton" if bool(spec[1]) else "EscalateOffButton"
		button.text = String(spec[0])
		button.custom_minimum_size = Vector2(190.0, 40.0)
		UiStyle.decorate_chip(button)
		button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(button, true))
		button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(button, false))
		button.pressed.connect(_on_escalation_pressed.bind(bool(spec[1])))
		row.add_child(button)

## 打开问询层（点兵种小卡时、且那张卡是召唤石柱）。
func _open_summon_panel() -> void:
	if _summon_scrim == null:
		return
	_summon_body.text = ("开启后：战斗开始 10 s 内只召唤权重 1 的单位，之后每过 10 s 允许的**单个单位权重上限** +2。\n"
		+ "关闭后：不限权重，从全部兵种里随机召唤。\n\n"
		+ "当前状态：%s　（选完即选中「召唤石柱」，再点地面摆放）"
		% ("开启" if sandbox.weight_escalation() else "不开启"))
	_summon_scrim.visible = true
	_refresh_palette()                  ## 兵种栏此刻在幕下面，顺手刷一次"选中的是哪张卡"

func _close_summon_panel() -> void:
	if _summon_scrim != null:
		_summon_scrim.visible = false

## 玩家选完了：写开关 → 选中石柱 → 收掉这一层（两个按钮都走这里，只是传值不同）。
func _on_escalation_pressed(on: bool) -> void:
	sandbox.set_weight_escalation(on)
	sandbox.select_type(GameConfig.SUMMONER_TYPE)
	_close_summon_panel()
	_sync_chips()

# ---------------------------------------------------------------- 战果浮层
func _build_overlay() -> void:
	var banner := UiStyle.make_battle_banner()
	_overlay = banner["root"]
	_overlay_title = banner["title"]
	_overlay_body = banner["body"]
	add_child(_overlay)

# ---------------------------------------------------------------- 刷新
## 相位跳变（`Sandbox` 自己的信号）即刻刷新；另外每 `REFRESH_MS` 轮询一次 ——
## 战斗中"存活 / 血量"是连续变化的，靠相位信号刷不出来。
func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _refresh_ms < REFRESH_MS:
		return
	_refresh_ms = Time.get_ticks_msec()
	_refresh()

func _on_phase_changed(_phase: String) -> void:
	_refresh()

func _refresh() -> void:
	if sandbox == null:
		return
	## 自由视角下隐藏整个界面（与经典 HUD 同一条口径：那时只能靠鼠标左右键出来）
	visible = camera_rig == null or camera_rig.mode != CameraRig.Mode.OVERVIEW
	if not visible:
		return
	_refresh_top()
	if _camera_hint != null:
		_camera_hint.text = UiStyle.camera_hint()
	_refresh_palette()
	_refresh_overlay()
	_sync_chips()
	_refresh_place_techs()
	_fit_palette()
	_refresh_inspect()

func _refresh_top() -> void:
	_weight_a.text = "%s 总权重 %d" % [GameConfig.team_name(0), sandbox.total_weight(0)]
	_weight_b.text = "%s 总权重 %d" % [GameConfig.team_name(1), sandbox.total_weight(1)]
	var in_battle := sandbox.phase != Sandbox.Phase.PLACING
	## 两个「清空」只在布兵阶段出现（战斗 / 结果阶段没什么可清的；对齐底部兵种栏的显隐口径）
	if _clear_a != null:
		_clear_a.visible = not in_battle
		_clear_a.disabled = sandbox.roster_of(0).is_empty()
	if _clear_b != null:
		_clear_b.visible = not in_battle
		_clear_b.disabled = sandbox.roster_of(1).is_empty()
	if in_battle and sandbox.arena != null:
		_alive_a.text = "%s %d" % [GameConfig.team_name(0), sandbox.arena.alive_count(0)]
		_hp_a.text = "HP %d" % int(round(sandbox.arena.team_hp(0)))
		_alive_b.text = "%s %d" % [GameConfig.team_name(1), sandbox.arena.alive_count(1)]
		_hp_b.text = "HP %d" % int(round(sandbox.arena.team_hp(1)))
	else:
		_alive_a.text = "%s —" % GameConfig.team_name(0)
		_hp_a.text = "HP —"
		_alive_b.text = "%s —" % GameConfig.team_name(1)
		_hp_b.text = "HP —"
	## 齿轮只在"玩家能用鼠标点"的相位出现：开战后光标被锁进窗口（`CameraRig` 的 `_fight_started`）
	## ⇒ 那时只认 Esc（与经典 HUD 同一条口径）。
	if _gear != null:
		_gear.visible = sandbox.phase == Sandbox.Phase.PLACING or sandbox.phase == Sandbox.Phase.RESULT
	## 倍速按钮**不跟着齿轮藏**：它常显（见建它时那条注释），战斗中也亮着。

func _refresh_palette() -> void:
	var placing := sandbox.phase == Sandbox.Phase.PLACING
	_palette_panel.visible = placing
	if _view_button != null:
		_view_button.visible = placing
		UiStyle.apply_chip_selected(_view_button, sandbox.view_mode())
	if _palette_hint != null:
		if sandbox.view_mode():
			_palette_hint.text = "查看模式：左键或右键点一个兵，查看它的数值和科技。这一模式下不能摆兵，也不能收兵。"
		else:
			_palette_hint.text = "兵种：左键点地面放置（按住左键拖动可连摆一串）· 右键点兵收掉（按住右键拖动可沿途批量扫掉）· 滚轮或两侧箭头可翻看更多兵种（左半场赤羽卫 · 右半场青锋卫）"
	if not placing:
		## 离开布兵阶段时把那一问一起收掉（开战 / 结束战斗后才不会留一块挡屏的幕）
		_close_summon_panel()
		return
	## 单排滚动区的**高度**按实测卡高设（2026-09-27 第十一轮）：卡的宽高都由文字决定
	##（两行："名字" + "权重 N"）⇒ 写死一个数迟早裁字；这里每 100 ms 顺手对齐一次，幂等。
	## ⚠️ 加 `CHIP_ROW_GROW_PAD`：`ScrollContainer` 会 `clip_contents`，不留余量的话
	## 「悬停原地放大」的上下两边会被裁掉。
	if _palette_scroll != null:
		var chip_h := 0.0
		for type_id in _chips:
			var card: Control = _chips[type_id] as Control
			if card != null:
				chip_h = maxf(chip_h, card.get_combined_minimum_size().y)
		if chip_h > 0.0:
			_palette_scroll.custom_minimum_size.y = chip_h + CHIP_ROW_GROW_PAD
	## 两端箭头（还有没有东西可翻）
	_refresh_palette_arrows()
	## 两边各至少一个才开得了战（用户口径：不限数量，但空场开战没有意义）
	var ready := sandbox.roster_of(0).size() > 0 and sandbox.roster_of(1).size() > 0
	_start_button.disabled = not ready
	_start_button.tooltip_text = "让场上的两军开打（按 Esc 可以「结束战斗」）" if ready \
		else "两边各至少放 1 个兵才能开战"
	_fit_palette()

## 底栏高度跟内容走：说明、兵种卡、科技、右侧按钮，谁高用谁，下面不留空面板。
func _fit_palette() -> void:
	if _palette_panel == null:
		return
	var h := _palette_panel.get_combined_minimum_size().y
	if h < 1.0:
		return
	_palette_panel.offset_top = _palette_panel.offset_bottom - h
	if _inspect_panel != null:
		_inspect_panel.offset_bottom = _palette_panel.offset_top - 8.0

## 兵种卡的"选中"外观：**只有一张**是选中的（金色边框 + 暖底，见 `UiStyle.apply_chip_selected`）。
## 选中没变就不再给每张卡新建样式。
func _sync_chips() -> void:
	if sandbox == null:
		return
	var selected := sandbox.selected_type()
	if selected == _chip_style_key:
		return
	_chip_style_key = selected
	for type_id in _chips:
		UiStyle.apply_chip_selected(_chips[type_id] as Button, String(type_id) == selected)

func _refresh_overlay() -> void:
	var show := sandbox.phase == Sandbox.Phase.RESULT
	_overlay.visible = show
	if _top_bar != null:
		_top_bar.visible = not show
	if not show:
		return
	var winner := int(sandbox.result.get("winner", -1))
	var hp: Array = sandbox.result.get("hp", [0, 0])
	if winner < 0:
		_overlay_title.text = "同时全灭"
		_overlay_title.add_theme_color_override("font_color", COLOR_DIM)
		_overlay_body.text = "剩余总血量  %d : %d" % [int(hp[0]), int(hp[1])]
	else:
		_overlay_title.text = "%s胜利！" % GameConfig.team_name(winner)
		_overlay_title.add_theme_color_override("font_color", COLOR_TEAM[winner])
		_overlay_body.text = "打败%s\n剩余总血量  %d : %d" % [
			GameConfig.team_name(1 - winner), int(hp[0]), int(hp[1])]

# ---------------------------------------------------------------- 交互
## 兵种小卡：**召唤石柱**那张先问一句"要不要开权重递增模式"（用户口径），其余直接选中。
func _on_chip_pressed(type_id: String) -> void:
	if type_id == GameConfig.SUMMONER_TYPE:
		_open_summon_panel()
		return
	sandbox.select_type(type_id)
	_sync_chips()

## 顶部「清空」：把这一队已摆下的兵全部收掉（玩法侧记账由 `Sandbox.clear_team()` 负责，界面只转发）。
func _on_clear_pressed(team: int) -> void:
	sandbox.clear_team(team)
	_refresh()

func _on_start_pressed() -> void:
	sandbox.start_battle()

func _on_overview_pressed() -> void:
	if camera_rig != null:
		camera_rig.toggle_overview()

func _on_view_mode_pressed() -> void:
	if sandbox == null:
		return
	sandbox.set_view_mode(not sandbox.view_mode())
	_refresh()

func _place_tech_style_key() -> String:
	var type_id := sandbox.selected_type()
	var parts: PackedStringArray = PackedStringArray()
	parts.append(sandbox.phase_name())
	parts.append(type_id)
	for row in _place_tech_buttons:
		if String(row["type_id"]) != type_id:
			continue
		var tech_id := String(row["tech_id"])
		parts.append(tech_id if sandbox.place_tech_on(type_id, tech_id) else "-")
	return "|".join(parts)

func _refresh_place_techs() -> void:
	if _place_tech_row == null or sandbox == null:
		return
	var key := _place_tech_style_key()
	if key == _tech_style_key:
		return
	_tech_style_key = key
	var type_id := sandbox.selected_type()
	var show := sandbox.phase == Sandbox.Phase.PLACING and not GameConfig.roguelike_tech_list(type_id).is_empty()
	_place_tech_row.visible = show
	if _place_tech_effect != null:
		_place_tech_effect.visible = show
		if not show:
			_place_tech_effect.text = ""
	for row in _place_tech_buttons:
		var button: Button = row["button"]
		var mine := String(row["type_id"]) == type_id
		button.visible = show and mine
		if not mine:
			continue
		var tech_id := String(row["tech_id"])
		UiStyle.apply_chip_selected(button, sandbox.place_tech_on(type_id, tech_id))

func _refresh_inspect() -> void:
	if _inspect_panel == null or sandbox == null:
		return
	var stats := sandbox.viewed_stats()
	var show := sandbox.view_mode() and sandbox.phase == Sandbox.Phase.PLACING and not stats.is_empty()
	_inspect_panel.visible = show
	if not show:
		return
	_inspect_title.text = "查看：%s · %s" % [stats["name"], GameConfig.team_name(int(stats["team"]))]
	var dps := float(stats["attack_speed"])
	var lines: Array = []
	lines.append("生命 %d / %d" % [int(stats["hp_now"]), int(stats["hp_max"])])
	var tech_mult := float(stats["tech_mult"])
	if is_equal_approx(tech_mult, 1.0):
		lines.append("伤害 %d" % int(stats["damage_final"]))
	else:
		lines.append("伤害 %d × 科技 %0.2f = %d" % [int(stats["damage"]), tech_mult, int(stats["damage_final"])])
	lines.append("攻击速度 %0.2f 次/秒（每 %0.2f s 一次）" % [dps, 1.0 / maxf(dps, 0.01)])
	lines.append("%s %0.1f m" % ["射程" if bool(stats["is_ranged"]) else "接触距离", float(stats["reach"])])
	lines.append("移速 %0.2f m/s" % float(stats["speed"]))
	lines.append("权重 %d · 质量 %0.1f" % [int(stats["weight"]), float(stats["mass"])])
	_inspect_body.text = "\n".join(lines)
	var notes: Array = []
	var type_id := String(stats["type_id"])
	for raw_id in stats["tech_ids"]:
		var tech_id := String(raw_id)
		var def := GameConfig.roguelike_tech_def(type_id, tech_id)
		notes.append("%s：%s" % [String(def.get("name", tech_id)), GameConfig.roguelike_tech_desc(type_id, tech_id)])
	if notes.is_empty():
		notes.append("没有科技")
	_inspect_note.text = "\n".join(notes)

func _on_roll_again_pressed() -> void:
	sandbox.roll_again()

# ---------------------------------------------------------------- 暂停菜单的**界面侧契约**
## 与 `hud.gd` 的三个同名方法对称（见 `pause_menu.gd` 的文件头）。
## 沙盒里"任何相位都能唤出菜单"：布兵 / 战斗 / 结果都允许（用户口径点名了前两个）。
func pause_allowed() -> bool:
	return sandbox != null

## ⚠️ 用户口径：**布兵阶段不许出现「重新开始」**；战斗阶段它变成「结束战斗」；
## 结果阶段战斗已经结束，于是又什么都不显示（只剩「继续 / 主菜单」）。
func pause_actions() -> Array:
	if sandbox == null:
		return []
	if sandbox.phase == Sandbox.Phase.FIGHTING:
		return [{"text": "结束战斗", "action": "end_battle"}]
	return []

func pause_action(action: String) -> void:
	if action == "end_battle" and sandbox != null:
		sandbox.end_battle()         ## 它自己会解除暂停（见 `Sandbox.end_battle()`）

# ---------------------------------------------------------------- 小工具
## 造一个**带名字**的文字标签。⚠️ `node_name` **必填**（`08_naming.md#3.1`）—— 去掉默认值就是为了让
## "忘了命名"变成**编译错误**。⚠️ 2026-09-26 第六块：三个模式 HUD 的每一行文字都在各自这个口子上统一命名，
## 名字取"这个标签在界面里的角色"的 PascalCase；**同一概念跨 HUD 同名**（例：三处视角提示都叫
## `CameraHintLabel`，见 `08_naming.md#1.4`）。
func _make_label(text: String, size: int, color: Color, node_name: String) -> Label:
	var label := UiStyle.make_label(text, size, color)
	label.name = node_name
	return label
