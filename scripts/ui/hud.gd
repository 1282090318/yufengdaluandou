class_name Hud
extends CanvasLayer
## 界面层：顶栏 / 下注面板 / 结算浮层 / 操作提示
##
## 依据：docs/bible/05_ui_hud.md（布局、状态矩阵、输入映射）
## 边界：HUD 只读 Game 的公开状态、只调用 Game 的公开方法，不直接改动玩法数据。

## 字号档位与调色板：**唯一一份在 `UiStyle`**（2026-09-25 搬过去，经典与沙盒两套 HUD 共用）——
## 这里只是本地别名，别再往这里写值。
const FONT_LARGE := UiStyle.FONT_LARGE
const FONT_MID := UiStyle.FONT_MID
const FONT_SMALL := UiStyle.FONT_SMALL
const FONT_TINY := UiStyle.FONT_TINY

const COLOR_TEAM := UiStyle.COLOR_TEAM
const COLOR_TEXT := UiStyle.COLOR_TEXT
const COLOR_DIM := UiStyle.COLOR_DIM
const COLOR_WARN := UiStyle.COLOR_WARN
const COLOR_OK := UiStyle.COLOR_OK

## 「全力支持 ALL」的彩光（2026-09-19 用户："按下全力支持按钮后，选择押注的两个按钮
##（即选择支持哪一方的两个按钮）会冒彩光特效"）。纯表现参数，功能域前缀见 `08_naming.md#3.3`；
## 色相取**绝对时刻**（不变量 I-13），不累加 delta。
const ALL_GLOW_HUE_SPEED := 0.45          ## 色相循环速度（圈/秒）
const ALL_GLOW_BORDER_WIDTH := 3          ## 彩光时的边框粗细（常态 2）
const ALL_GLOW_SHADOW_SIZE := 7           ## 外发光半径（px）
const ALL_GLOW_SATURATION := 0.85         ## 彩光饱和度（明度固定取 1.0）
const ALL_GLOW_TEAM_HUE_OFFSET := 0.5     ## 两张队卡的色相错开半圈，读起来是"两边一起在闪"
## 彩光必须同时盖住三档按钮状态，否则**鼠标一悬停就会切回主题样式、彩光消失**
##（玩家正要把光标移到要押的那一方）。三档只差底色深浅 ⇒ 悬停 / 按下的反馈仍在。
const ALL_GLOW_SLOTS := ["normal", "hover", "pressed"]
const ALL_GLOW_BG := [Color(0.10, 0.11, 0.14, 0.95), Color(0.17, 0.19, 0.23, 0.97), Color(0.06, 0.07, 0.09, 0.98)]

var game: Game = null
var camera_rig: CameraRig = null

var _top_bar: PanelContainer = null
var _round_label: Label = null
var _points_label: Label = null
var _chance_label: Label = null
var _timer_label: Label = null
var _ring_label: Label = null
var _alive_a: Label = null
var _hp_a: Label = null
var _alive_b: Label = null
var _hp_b: Label = null

var _bet_panel: PanelContainer = null
var _bet_col: VBoxContainer = null
var _wager_normal: Label = null
var _wager_allin: Label = null
var _rows_box: HBoxContainer = null
var _team_rows: Array = []          ## 两张队伍卡片的控件引用（只构建一次，见 _refresh_bet_panel）
var _hint_label: Label = null
## 屏幕正中那一行的三个全局按钮（2026-09-18 任务 6：从队伍卡上搬到这里）
var _skip_button: Button = null
var _all_in_button: Button = null
var _overview_button: Button = null
## "全力支持"改成**开关**（任务 6.6）：按下后押注即 ALL，再按取消
var _all_in_selected: bool = false
## 2026-09-19：「全力支持」改成**每一轮都要重新选择** —— 押注阶段一开始就把开关清掉
##（见 `_on_phase_changed`）。这里记上一次收到的相位名，用来识别"相位跳变"：
## `Game` 每 100 ms 会重发同一条相位，只有跳变才算"新一轮开始"。
var _last_phase: String = ""
## ALL 彩光用的样式（2 队 × 3 档 = 6 份：懒建一次，之后逐帧只改颜色）；
## 空数组 = 当前没开彩光（`_update_all_in_glow` / `_clear_all_in_glow`）。
var _glow_styles: Array[StyleBoxFlat] = []

var _overlay: Control = null
var _overlay_title: Label = null
var _overlay_body: Label = null
var _overlay_button: Button = null
var _overlay_mode: String = "round"

var _ctrl_label: Label = null

func build(p_game: Game, p_camera: CameraRig) -> void:
	game = p_game
	camera_rig = p_camera
	## ⚠️ HUD 整层设为 `ALWAYS`：暂停菜单（以及它的渐暗 / 渐亮过渡）必须在"整棵树暂停"时照样跑、
	## 照样能被点（用户口径：战斗中按 ESC 暂停）。这只影响"处理与否"，不改任何玩法数据（R-07）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	## 暂停菜单（2026-09-25 抽成独立一层，经典 / 沙盒共用）：**先建**，因为顶栏的齿轮要接它的 `open()`。
	## ⚠️ 它有自己的 `layer`（`PauseMenu.MENU_LAYER` = 5 > 本层的 1）⇒ **不再依赖"最后 add_child"**
	## 来盖住下注面板 / 结算浮层（旧版按添加顺序压层，注释里还专门叮嘱过"必须最后建"）。
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	_pause.configure(game, self)
	_build_top_bar()
	_build_bet_panel()
	_build_overlay()
	_build_bottom()
	Events.phase_changed.connect(_on_phase_changed)
	_refresh()

# ---------------------------------------------------------------- 顶栏
func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 64.0
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.34, 0.40, 1.0)
	style.set_content_margin_all(10)
	_top_bar.add_theme_stylebox_override("panel", style)
	add_child(_top_bar)

	var row := HBoxContainer.new()
	row.name = "TopBarRow"          ## §3.1：动态生成的节点也必须命名（齿轮就挂在这一行里）
	row.add_theme_constant_override("separation", 18)
	_top_bar.add_child(row)

	_round_label = _make_label("第 1 / 10 轮", FONT_MID, COLOR_TEXT, "RoundLabel")
	row.add_child(_round_label)
	_points_label = _make_label("礼物点数 10,000", FONT_MID, COLOR_TEXT, "PointsLabel")
	row.add_child(_points_label)
	_chance_label = _make_label("观望机会 ●●●", FONT_MID, COLOR_TEXT, "ChanceLabel")
	row.add_child(_chance_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_alive_a = _make_label("赤羽卫 —", FONT_SMALL, COLOR_TEAM[0], "Alive_a")
	row.add_child(_alive_a)
	_hp_a = _make_label("HP —", FONT_TINY, COLOR_DIM, "Hp_a")
	row.add_child(_hp_a)
	_alive_b = _make_label("青锋卫 —", FONT_SMALL, COLOR_TEAM[1], "Alive_b")
	row.add_child(_alive_b)
	_hp_b = _make_label("HP —", FONT_TINY, COLOR_DIM, "Hp_b")
	row.add_child(_hp_b)

	_timer_label = _make_label("60.0s", FONT_MID, COLOR_WARN, "TimerLabel")
	row.add_child(_timer_label)

	## 兴奋圈已废止（2026-10-23）。标签留着占位但永不显示，免得旧存档刷新时找不到节点。
	_ring_label = _make_label("", FONT_TINY, COLOR_DIM, "RingLabel")
	_ring_label.visible = false
	row.add_child(_ring_label)

	## 齿轮（暂停菜单入口）：**顶栏栏内最右一格**（用户口径）。ESC 是同一个功能的快捷键。
	## 外观（尺寸 / 图标 / 提示 / 光标）统一由 `UiStyle` 装扮 —— 沙盒 HUD 用的是**同一个**齿轮
	##（2026-09-25 抽共享，原先这里另有一份 `_gear_texture()`）。
	## 倍速（2026-11-01，用户："加个加速，放右上角…点击 x2、再点 x1"）：
	## **插在齿轮左边** —— 齿轮是"顶栏栏内最右一格"（用户口径，见下面那段），新按钮只能往左排。
	## ⚠️ 倍速**常显**（2026-11-01 修 bug：用户"战斗开始后无法点加速"）：
	## 战斗中正要用它，而那时光标被 `CameraRig` 锁住 ⇒ 靠快捷键 `F` 切（见 `UiStyle`），
	## 按钮本身必须一直亮着（`Button.shortcut` 只在可见时才派发），顺便让人看见当前是几倍。
	_speed_button = UiStyle.make_speed_button("SpeedButton")
	row.add_child(_speed_button)

	_gear = Button.new()
	_gear.name = "GearButton"
	UiStyle.decorate_gear(_gear)
	_gear.visible = false                           ## 只在"光标可见"的相位显示（见 _refresh_top）
	_gear.pressed.connect(_pause.open)
	row.add_child(_gear)

# ---------------------------------------------------------------- 下注面板
## 优化 3：从"左侧竖排卡片"改为**屏幕底部横向平铺**，把画面中央让给战场。
## 结构：一行 = 标题 + 本轮投入 | 第二行 = 两张队伍卡片并排 | 第三行 = 操作提示
func _build_bet_panel() -> void:
	_bet_panel = PanelContainer.new()
	_bet_panel.name = "BetPanel"
	_bet_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bet_panel.offset_left = 16.0
	_bet_panel.offset_right = -16.0
	## ⚠️ 2026-09-25：三个全局按钮改成"沙盒那一档"外观之后，**面板高度必须一点不差地保持原样**
	## （用户："下注面板保持原来的大小不要变"）—— 做法是让按钮行**仍然是 36 高**（见 `_decorate_action_button()`），
	## 所以下面这两个偏移量**一个字都不用改**。
	## ⚠️ 但要记住一件**既有**事实：这个面板的高度一直是**内容撑出来的**（实测 ≈299），
	## 声明值 230 早就被内容顶开了（`PanelContainer` 按内容最小尺寸长大，`grow_vertical = BEGIN` 向上长）。
	_bet_panel.offset_top = -286.0
	_bet_panel.offset_bottom = -56.0
	_bet_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bet_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.93)
	style.border_color = Color(0.32, 0.36, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_bet_panel.add_theme_stylebox_override("panel", style)
	add_child(_bet_panel)

	_bet_col = VBoxContainer.new()
	_bet_col.add_theme_constant_override("separation", 6)
	_bet_panel.add_child(_bet_col)

	# 第一行：标题 + 本轮投入（横排，省掉两行高度）
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 18)
	_bet_col.add_child(title_row)
	title_row.add_child(_make_label("押注：选一支队伍", FONT_MID, COLOR_TEXT, "BetTitleLabel"))
	_wager_normal = _make_label("本轮固定投入 —", FONT_SMALL, COLOR_TEXT, "WagerNormalLabel")
	title_row.add_child(_wager_normal)
	_wager_allin = _make_label("", FONT_TINY, COLOR_DIM, "WagerAllinLabel")
	title_row.add_child(_wager_allin)

	# 第二行：两张队伍卡片并排
	_rows_box = HBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 12)
	_bet_col.add_child(_rows_box)

	# 第三行（任务 6.4/6.5/6.6，2026-09-18）：三个**全局**按钮居中排一行 —— 观望 / 全力支持 / 自由视角。
	# 队伍卡上只留"支持"；ALL 在这里当开关用。
	## ⚠️ 2026-09-25 用户："**将竞猜模式的全力支持、观望和自由视角的按钮变成沙盒模式的同款**" ⇒
	## 三个按钮统一走沙盒「自由视角」那一档的**外观**（`UiStyle.decorate_chip` + `apply_chip_hover` +
	## 三者等宽 280）；⚠️ **但高度与字号按"面板不许变大"定**（36 / 16），细则见 `_decorate_action_button()`。
	## ⚠️ 队卡上的两个「支持（投入 N）」**没在这一批里**（用户只点了这三个），仍是主题默认外观。
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	_bet_col.add_child(actions)

	_all_in_button = Button.new()
	_all_in_button.text = "全力支持 ALL"
	_all_in_button.toggle_mode = false
	_all_in_button.pressed.connect(_on_toggle_all_in)
	_decorate_action_button(_all_in_button)
	actions.add_child(_all_in_button)

	_skip_button = Button.new()
	_skip_button.text = "观望"
	_skip_button.tooltip_text = "不投入、不输不赢，但仍要看一场比赛"
	_skip_button.pressed.connect(_on_skip)
	_decorate_action_button(_skip_button)
	actions.add_child(_skip_button)

	_overview_button = Button.new()
	## 2026-09-19 用户："将『全景』按钮改为『自由视角』"——玩家可见处一律用新叫法；
	## 内部状态名（`CameraRig.Mode.OVERVIEW` / `toggle_overview()` / `_overview_button`）保持不动。
	_overview_button.text = "自由视角"
	_overview_button.tooltip_text = "进入自由视角（隐藏界面、隐藏光标；鼠标转向，点左键或右键退出）"
	_overview_button.pressed.connect(_on_overview)
	_decorate_action_button(_overview_button)
	actions.add_child(_overview_button)

	## 第四行：底部那行提示（⚠️ 2026-09-25 从 `_decorate_action_button()` 里**搬回来** ——
	## 上一批插入那个函数时把它吞了进去，结果"每装扮一个按钮就多造一个空提示标签"，
	## 面板列里凭空多出两个空标签 + 两条间隔（52 px），下注面板白白长高）。
	_hint_label = _make_label("", FONT_TINY, COLOR_DIM, "HintLabel")
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bet_col.add_child(_hint_label)

## 把这三个全局按钮装扮成**沙盒那一档**（沙盒的「自由视角」是同一种做法）。
## ⚠️ 2026-09-25 用户补充："**竞猜模式的下注面板保持原来的大小不要变，将面板大小改回去**" ⇒
## 外观（配色 / 边框 / 悬停原地放大 / 三者等宽 280）全按沙盒那一档，**但高度必须是原来的 36**。
## ⚠️ 这个面板的高度是**内容撑**出来的（声明值 230 早就被内容顶开）：列内四行 + 三条间隔 + 内边距，
## 面板高 = 列最小高 + 24。实测这一行每高 1 px、面板就高 1 px（行 44 ⇒ 255；行 36 ⇒ **247 = 原来的高度**）。
## ⚠️ 字号也必须一起回落到本 HUD 的 16 档：小卡那档是 18，而中日韩字形的行高 ≈ 1.4×字号，
## 18 号 + 小卡内边距（上 6 下 6）⇒ 内容高 38，**会把 36 顶成 38**（实测过：`custom_minimum_size`
## 给 36 也只能排到 38）⇒ 面板照样高 2 px。
func _decorate_action_button(button: Button) -> void:
	UiStyle.decorate_chip(button)
	button.custom_minimum_size = Vector2(UiStyle.MIN_SIZE.x, 36.0)
	button.add_theme_font_size_override("font_size", FONT_SMALL)
	button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(button, true))
	button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(button, false))

# ---------------------------------------------------------------- 结算浮层
func _build_overlay() -> void:
	var banner := UiStyle.make_battle_banner()
	_overlay = banner["root"]
	_overlay_title = banner["title"]
	_overlay_body = banner["body"]
	add_child(_overlay)

# ---------------------------------------------------------------- 底部：操作提示
func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.name = "BottomInfo"
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	## ⚠️ 槽位宽 = 820 − 18 = **802**，必须 ≥ 这行提示的自然宽度（`UiStyle.CAMERA_HINT`，
	## `FONT_TINY` = 14 号时量出来 780 px）。原先写 −640（槽位只有 622）⇒ 容器被最小宽度撑到
	## 780 宽、右边界落到 x = 1740（窗口才 1600），**尾部约 140 px 画在窗口外看不见**；
	## 2026-09-25 改键位让这行字又长了 45 px，才被发现。改文案（尤其变长）时回来核这个数。
	box.offset_left = -820.0
	box.offset_right = -18.0
	box.offset_top = -58.0
	box.offset_bottom = -10.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)

	## ⚠️ 2026-09-19 用户："**移除屏幕右下角的字**" ⇒ **整条属性条拿掉**。
	## 原先这里铺一排 `Label`（由 `_refresh_stats()` 填成 `剑盾兵 W1 | HP 300 | 伤害 34 | …` 那种），
	## 固定占右下角、常驻显示本局阵容里出现过的兵种。删掉后：
	##   · `05_ui_hud.md` 里记的那条"已知瑕疵：属性条与下注面板底部提示轻微重叠"**随之消失**；
	##   · 战斗信息并没有丢：两队血量在顶栏（`HP`）、本队阵容与权重在下注面板、兵种数值以 bible 为准。
	## ⚠️ 下面这行**视角操作提示**保留（它与属性条同处右下角，但属于另一件事）。
	_ctrl_label = _make_label("", FONT_TINY, COLOR_DIM, "CameraHintLabel")
	_ctrl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_ctrl_label)

# ---------------------------------------------------------------- 每帧（ALL 彩光）
func _process(_delta: float) -> void:
	_update_all_in_glow()
	_refresh_ctrl_hint()

## 按下「全力支持 ALL」后，两张队卡的「支持」按钮冒彩光：边框颜色沿色相环循环 + 同色外发光。
## 未按下 / 押注面板不可见时直接早退（并撤掉样式）⇒ 常态零开销。
func _update_all_in_glow() -> void:
	var armed := _all_in_selected and _bet_panel != null and _bet_panel.visible and _team_rows.size() >= 2
	if not armed:
		_clear_all_in_glow()
		return
	if _glow_styles.is_empty():
		for team in [0, 1]:
			var button := _team_rows[team]["normal"] as Button
			for slot_i in ALL_GLOW_SLOTS.size():
				var style := StyleBoxFlat.new()
				style.bg_color = ALL_GLOW_BG[slot_i]      ## 与队伍卡同色系，只换边框与光晕
				style.set_corner_radius_all(6)
				style.set_border_width_all(ALL_GLOW_BORDER_WIDTH)
				_glow_styles.append(style)
				button.add_theme_stylebox_override(ALL_GLOW_SLOTS[slot_i], style)
	## 色相按**绝对时刻**推进（不变量 I-13：不累加 delta）；两张队卡错开半圈
	var hue := fmod(Time.get_ticks_msec() / 1000.0 * ALL_GLOW_HUE_SPEED, 1.0)
	for i in _glow_styles.size():
		var team := i / ALL_GLOW_SLOTS.size()
		var color := Color.from_hsv(fmod(hue + ALL_GLOW_TEAM_HUE_OFFSET * float(team), 1.0),
				ALL_GLOW_SATURATION, 1.0)
		_glow_styles[i].border_color = color
		_glow_styles[i].shadow_color = Color(color.r, color.g, color.b, 0.55)
		_glow_styles[i].shadow_size = ALL_GLOW_SHADOW_SIZE

## 撤掉彩光：按钮回到主题默认样式（`remove_theme_stylebox_override` ⇒ 不留痕迹）
func _clear_all_in_glow() -> void:
	if _glow_styles.is_empty():
		return
	for team in [0, 1]:
		var button := _team_rows[team]["normal"] as Button
		for slot in ALL_GLOW_SLOTS:
			button.remove_theme_stylebox_override(slot)
	_glow_styles.clear()

# ---------------------------------------------------------------- 刷新
func _refresh() -> void:
	if game == null:
		return
	## 任务 6.5（2026-09-18）：**自由视角下隐藏整个界面**——那时只能靠鼠标左右键出来
	##（`CameraRig` 在 OVERVIEW 下只认鼠标左/右键退出，见 bug 1）。
	visible = camera_rig == null or camera_rig.mode != CameraRig.Mode.OVERVIEW
	if not visible:
		return
	_refresh_top()
	_refresh_bet_panel()
	_refresh_ctrl_hint()
	_refresh_overlay()
	_refresh_combat()

func _refresh_top() -> void:
	_round_label.text = "第 %d / %d 轮" % [maxi(game.round_index, 1), GameConfig.ROUND_COUNT]
	_points_label.text = "礼物点数 %s" % _fmt(game.points)
	var dots := ""
	for i in GameConfig.CHANCES_MAX:
		dots += (("●" if i < game.chances else "○") + " ")
	_chance_label.text = "观望机会 %s" % dots.strip_edges()
	_chance_label.add_theme_color_override("font_color", COLOR_WARN if game.chances <= 1 else COLOR_TEXT)
	## 齿轮只在"玩家能用鼠标点"的相位出现：战斗阶段光标被锁在窗口里（`FIGHTING`）⇒ 那时只认 ESC。
	if _gear != null:
		_gear.visible = game.phase == Game.Phase.BETTING or game.phase == Game.Phase.ROUND_RESULT
	## 倍速按钮**不跟着齿轮藏**：它常显（见建它时那条注释），这里就不再动它的可见性。

func _refresh_bet_panel() -> void:
	var betting := game.phase == Game.Phase.BETTING
	_bet_panel.visible = betting
	if not betting:
		return

	# ⚠️ 关键：卡片与按钮**只在第一次构建**，之后每帧只更新文本与可用状态。
	# 历史 bug 2c：早期版本每次刷新都 queue_free() 重建卡片，导致点击时按钮在
	# 按下与抬起之间被销毁，pressed 永远不触发（下注/观望按钮"没反应"）。
	# 见 99_decisions.md#修-下注按钮点击失效
	if _team_rows.is_empty():
		for team in [0, 1]:
			_team_rows.append(_build_team_row(team))

	var wager := GameConfig.wager_of(game.round_index)
	var unlocked := GameConfig.all_in_unlocked(game.round_index)

	for team in [0, 1]:
		var row: Dictionary = _team_rows[team]
		var roster: Array = game.roster_a if team == 0 else game.roster_b
		## 任务 6.2 / 6.3：卡片上只留"队名 + 名单 + 支持"，
		## 总权重、本轮预算、系统倾向、权重分解全部移除。
		(row["roster"] as Label).text = GameConfig.roster_text(roster)
		var normal := row["normal"] as Button
		normal.text = "全力支持（投入 %s）" % _fmt(game.points) if _all_in_selected else "支持（投入 %s）" % _fmt(wager)
		normal.disabled = game.points <= 0

	## 正中的三个全局按钮
	_all_in_button.disabled = not unlocked or game.points <= 0
	_all_in_button.text = ("全力支持 ALL：开（%s）" % _fmt(game.points)) if _all_in_selected else "全力支持 ALL"
	_all_in_button.tooltip_text = ("押中额外奖励 ×%.0f；再按一次取消" % GameConfig.ALL_IN_BONUS) if unlocked else ("第 %d 轮起开放" % GameConfig.ALL_IN_FROM_ROUND)
	## 任务 9：观望机会是**消耗品**，用完就只剩押注一条路（按钮灰掉，`skip_round()` 也会拒收）
	_skip_button.disabled = game.chances <= 0

	_wager_normal.text = ("本轮固定投入 %s" % _fmt(wager)) if wager > 0 else "本轮固定投入 —"
	_wager_allin.text = ("全力支持已开放：ALL = %s（押中额外奖励 ×%.0f）" % [
		_fmt(game.points), GameConfig.ALL_IN_BONUS]) if unlocked else (
		"第 %d 轮起开放全力支持（ALL）" % GameConfig.ALL_IN_FROM_ROUND)
	_wager_allin.add_theme_color_override("font_color", COLOR_WARN if unlocked else COLOR_DIM)
	_hint_label.text = "单机观赛：观望 1 次消耗 1 次观望机会（共 %d 次）；押错只赔点数、不掉机会，点数归零即结束。" % GameConfig.CHANCES_MAX

## 任务 6.6：全力支持改成**开关**——按下后押注即 ALL，再按取消
func _on_toggle_all_in() -> void:
	_all_in_selected = not _all_in_selected
	_refresh_bet_panel()

func _build_team_row(team: int) -> Dictionary:
	var card := PanelContainer.new()
	card.name = "TeamRow%d" % team
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.95)
	style.border_color = COLOR_TEAM[team]
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)

	# 第一行：队名（任务 6.2：**移除"总权重 N / 本轮预算 N"与"系统倾向"**）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(_make_label(GameConfig.team_name(team), FONT_MID, COLOR_TEAM[team], "TeamNameLabel"))

	# 第二行：**只列名单**（任务 6.3：移除权重分解）
	var roster_label := _make_label("", FONT_SMALL, COLOR_TEXT, "RosterLabel")
	col.add_child(roster_label)

	# 第三行：**只留"支持"**——观望 / 全力支持 / 自由视角都搬到面板正中的那一行（任务 6.4~6.6）
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	col.add_child(buttons)

	var normal := Button.new()
	normal.text = "支持"
	normal.custom_minimum_size = Vector2(150.0, 34.0)
	normal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## 押注时带上"全力支持"开关的状态（任务 6.6）
	normal.pressed.connect(func() -> void: _on_bet(team, _all_in_selected))
	buttons.add_child(normal)

	return {"roster": roster_label, "normal": normal}

## 底部那行**视角操作提示**。⚠️ 它原先叫 `_refresh_stats()` 并**同时**负责属性条：
## 属性条已于 2026-09-19 按用户要求整条移除（见 `_build_bottom()` 的说明），所以这里只剩提示文案。
func _refresh_ctrl_hint() -> void:
	if _ctrl_label == null:
		return
	_ctrl_label.text = UiStyle.camera_hint()

func _refresh_combat() -> void:
	var arena := game.arena
	if arena == null:
		return
	var in_fight := game.phase == Game.Phase.FIGHTING
	if in_fight:
		var elapsed := Time.get_ticks_msec() - arena.match_start_ms
		_timer_label.text = "%.1fs" % (float(maxi(0, GameConfig.MATCH_LIMIT_MS - elapsed)) / 1000.0)
		_alive_a.text = "赤羽卫 %d" % arena.alive_count(0)
		_alive_b.text = "青锋卫 %d" % arena.alive_count(1)
		_hp_a.text = "HP %d" % int(round(arena.team_hp(0)))
		_hp_b.text = "HP %d" % int(round(arena.team_hp(1)))
	else:
		_timer_label.text = "%.1fs" % (float(GameConfig.MATCH_LIMIT_MS) / 1000.0)
		_alive_a.text = "赤羽卫 —"
		_alive_b.text = "青锋卫 —"
		_hp_a.text = "HP —"
		_hp_b.text = "HP —"

func _reason_text(reason: String) -> String:
	match reason:
		"wipe":
			return "一方全灭"
		"timeout":
			return "时间到·比剩余血量"
		"stalemate":
			return "僵持不下·判平局"
		"draw":
			return "同时倒下·平局"
	return "已结束"

func _refresh_overlay() -> void:
	var show := game.phase == Game.Phase.ROUND_RESULT or game.phase == Game.Phase.GAME_OVER
	_overlay.visible = show
	if _top_bar != null:
		_top_bar.visible = not show
	if _ctrl_label != null:
		_ctrl_label.visible = not show
	if not show:
		return
	var winner := int(game.last_result.get("winner", -1))
	var lines := _victory_lines(winner)
	if game.phase == Game.Phase.ROUND_RESULT:
		_overlay_mode = "round"
		var entry: Dictionary = game.log_entries[-1] if not game.log_entries.is_empty() else {}
		var hit := bool(entry.get("hit", false))
		var draw := bool(entry.get("draw", false))
		var gain := int(entry.get("gain", 0))
		var bet := int(entry.get("bet", -1))
		var wager := int(entry.get("wager", 0))
		var flow := "未投入" if wager == 0 else ("全额返还" if draw else ("获得 +%s" % _fmt(gain) if gain >= 0 else "损失 %s" % _fmt(abs(gain))))
		var bet_line := "本轮观望" if bet < 0 else ("押中" if hit else ("平局" if draw else "押错"))
		_overlay_title.text = String(lines[0])
		_overlay_title.add_theme_color_override("font_color", lines[2])
		_overlay_body.text = "%s\n%s · 投入 %s · %s · 点数 %s · 观望 %d" % [
			String(lines[1]), bet_line, _fmt(wager), flow, _fmt(game.points), game.chances]
	else:
		_overlay_mode = "over"
		var s := game.summary
		var full_support := bool(s.get("full_support", false))
		var bankrupt := not bool(s.get("reached_end", false))
		var ending := "达成「点生点」" if full_support else ("破产出局" if bankrupt else "观赛结束")
		_overlay_title.text = String(lines[0]) if winner >= 0 else ending
		_overlay_title.add_theme_color_override("font_color", lines[2] if winner >= 0 else (COLOR_OK if full_support else COLOR_WARN))
		_overlay_body.text = "%s\n%s · 最终点数 %s · 最高 %s · 押中 %d / %d" % [
			String(lines[1]) if winner >= 0 else ending,
			ending,
			_fmt(int(s.get("points", 0))), _fmt(int(s.get("peak_points", 0))),
			int(s.get("successes", 0)), int(s.get("rounds_played", 0))]

# ---------------------------------------------------------------- 交互
func _on_bet(team: int, all_in: bool) -> void:
	if game != null:
		game.place_bet(team, all_in)

func _on_skip() -> void:
	if game != null:
		game.skip_round()

func _on_overview() -> void:
	if camera_rig != null:
		camera_rig.toggle_overview()

func _victory_lines(winner: int) -> Array:
	if winner < 0:
		return ["平局", "双方同时倒下", COLOR_DIM]
	return ["%s胜利！" % GameConfig.team_name(winner),
			"打败%s" % GameConfig.team_name(1 - winner), COLOR_TEAM[winner]]


func _on_overlay_button() -> void:
	if game == null:
		return
	if _overlay_mode == "over":
		game.acknowledge_game_over()
		return
	## 任务 9：结算浮层的按钮只看轮次（机会用尽不再等于"本局结束"）
	if game.round_index < GameConfig.ROUND_COUNT:
		game.next_round()
	else:
		game.acknowledge_game_over()

func _on_phase_changed(phase: String) -> void:
	## 2026-09-19 修 bug（用户："以全力支持完成一轮后新开一局（重新开始）会被锁定成全力支持
	## 且无法取消"）：「全力支持」是**每一轮重新选择**的开关 —— 押注阶段一开始就清掉它。
	## 根因：`_all_in_selected` 以前从不重置，而第 1~2 轮 ALL 按钮是禁用的 ⇒ 想关也关不掉。
	## ⚠️ 只认**相位跳变**：`Game` 每 100 ms 会重发一次同一条 `phase_changed`（`05_ui_hud.md#7.1`），
	## 逐次重置会让开关刚按下就被清掉。
	if phase != _last_phase and phase == "betting":
		_all_in_selected = false
	_last_phase = phase
	_refresh()

# ---------------------------------------------------------------- 暂停菜单（齿轮 / Esc）
## 整块菜单已经抽到 `scripts/ui/pause_menu.gd`（`PauseMenu`）—— 沙盒模式的 HUD 也要用**同一份**，
## 而两套 HUD 是 `scripts/ui/` 下的**兄弟**、互相引用违反依赖方向（`07_file_layout.md#5`）。
## 本文件只留两样东西：**那只齿轮**（挂在本 HUD 的顶栏里）与**界面侧契约**（见文件末尾
## `pause_allowed()` / `pause_actions()` / `pause_action()`）。
var _gear: Button = null
## 倍速按钮（2026-11-01）：**顶栏右端、齿轮左边**。外观与接线都在 `UiStyle.make_speed_button()`
##（三套 HUD 共用同一份），这里只负责挂上去、以及"跟着齿轮一起显隐"。
var _speed_button: Button = null
var _pause: PauseMenu = null

# ---------------------------------------------------------------- 暂停菜单的**界面侧契约**
## `PauseMenu` 会调这三个方法（见 `scripts/ui/pause_menu.gd` 的文件头）：
## 「暂停 / 恢复」是**玩法侧**的事（`Game.pause_match()` / `resume_match()`，`PauseMenu` 直接调它），
## 而"哪个相位能唤出菜单""中间那一项叫什么、点了算什么"是**界面的知识** —— 界面本来就知道当前相位。
##
## 允许唤出的相位：押注 / 战斗 / 结算（用户点名了前两个；结算时也能退回主菜单更好用）。
func pause_allowed() -> bool:
	return game != null and (game.phase == Game.Phase.BETTING or game.phase == Game.Phase.FIGHTING
		or game.phase == Game.Phase.ROUND_RESULT)

## 竞猜模式的中间项只有「重新开始」（任何相位都能重开一局）。
## 沙盒模式的这一项随相位而变（布兵阶段**没有**、战斗中变成「结束战斗」），见 `sandbox_hud.gd`。
func pause_actions() -> Array:
	return [{"text": "重新开始", "action": "restart"}]

func pause_action(action: String) -> void:
	if action == "restart" and game != null:
		game.restart_game()          ## 整局重置（点数 / 机会 / 轮次）⇒ 回押注阶段并顺带解除暂停

# ---------------------------------------------------------------- 小工具
## 造一个**带名字**的文字标签。⚠️ `node_name` **必填**（`08_naming.md#3.1`）—— 去掉默认值就是为了让
## "忘了命名"变成**编译错误**。⚠️ 2026-09-26 第六块：三个模式 HUD 的每一行文字都在各自这个口子上统一命名，
## 名字取"这个标签在界面里的角色"的 PascalCase；**同一概念跨 HUD 同名**（例：三处视角提示都叫
## `CameraHintLabel`，见 `08_naming.md#1.4`）。
func _make_label(text: String, size: int, color: Color, node_name: String) -> Label:
	var label := UiStyle.make_label(text, size, color)
	label.name = node_name
	return label

func _fmt(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
