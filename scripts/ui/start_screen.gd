class_name StartScreen
extends CanvasLayer
## 开始界面：**左侧竖排选项** + 全屏**渐黑 → 渐亮**过渡。
##
## 依据：`05_ui_hud.md#1`（界面是补充、不是主体）、`#6`（字号档位与对比度口径）、
## `07_file_layout.md#5`（表现层只管"看见什么"，不碰玩法数据 —— R-07）。与 `hud.gd` 同一层、同一种做法：
## **全部控件由代码构建**，没有 .tscn。
##
## 四段时序（计时全部按**绝对时刻**，遵守不变量 I-13）：
##   ① **开场渐亮**：开局整屏是黑的（正好盖住背景那场"预演"），`play_fade_in()` 之后黑幕淡出；
##   ② 玩家点「开始游戏」⇒ **选项列原地换档**（第一档「开始游戏 + 设置」⇄ 第二档
##      「竞猜模式 + 沙盒模式 + 肉鸽模式 + 返回」，同一套样式；「返回」把第二档换回第一档）。
##      ⚠️ 2026-09-25 新增这一档（用户口径："点击『开始游戏』之后再多出两个按钮，不要直接进下注界面"）：
##      这一步**不打飞、不渐黑** —— 它只是一次选择，玩家随时还能改主意；
##      ⚠️ 同日其后又加了「设置」（第一档、「开始游戏」下方）与「返回」（第二档、**这一档最后**）；
##      ⚠️ **2026-09-26 再加「肉鸽模式」**（插在「沙盒模式」与「返回」之间）。
##   ③ 玩家点某个模式 ⇒ **渐黑**（`FADE_OUT_MS`）；黑透那一刻 emit `screen_blacked_out`
##      —— `main.gd` 就在这一刻按 `mode_selected` 传来的模式装配真比赛、释放背景演示（玩家看不见换场）；
##   ④ 接着**渐亮**（`FADE_IN_MS`），亮完自己收掉黑幕并 `queue_free()`（此后界面交给 HUD）。
##
## ⚠️ 黑幕（`FadeOverlay`）铺满全屏，`mouse_filter` **必须是 IGNORE**：一旦它吃掉鼠标事件，
## 左侧的按钮就永远点不到（这是本项目 2026-09-19 那个"按钮点了没反应"bug 的同类坑，
## 见 `05_ui_hud.md#7.1`）。
## ⚠️ 选项按钮一律 `focus_mode = NONE`：`Space` 在本作里是 `cam_up`（2026-09-25 第十一条），
## 而 `Space` 同时是引擎内置 `ui_accept` 的默认键 ⇒ 按钮一旦持有焦点，按空格升镜头会顺带按下它。
## 本作没有键盘 UI 导航需求（`05_ui_hud.md#8`），所以直接不给焦点。

## 模式 ID（**唯一出处**在此，`main.gd` 拿它决定装配哪一套）：
##   · `MODE_QUIZ` —— **竞猜模式**（2026-09-25 用户改名：原先叫"经典模式"；**ID 也一起从
##     `MODE_CLASSIC` / `"classic"` 改成 `MODE_QUIZ` / `"quiz"`**，免得界面名与代码名两张皮）：
##     押注 + 十轮 + 兴奋圈（既有玩法，一字未动）；
##   · `MODE_SANDBOX` —— 沙盒模式：自由布兵、自己开战（没有押注 / 没有圈 / 不判平局）。
##   · `MODE_ROGUELIKE` —— **肉鸽模式**（2026-09-26 新增）：10 个回合、回合开始领补给、用补给买兵抵挡进攻
##     （**分步落地**：当前只有骨架 + 经济记账，见 `scripts/game/roguelike.gd` 的文件头）。
const MODE_QUIZ := "quiz"
const MODE_SANDBOX := "sandbox"
const MODE_ROGUELIKE := "roguelike"

signal mode_selected(mode: String)     ## 玩家选了模式（按下那一刻就发：背景推近 / 记住装配哪一套）
signal resume_selected(mode: String)   ## 玩家选了要继续的那一局
signal screen_blacked_out              ## 黑幕已全黑：过渡中点，换场就发生在这一刻

# ---------------------------------------------------------------- 表现参数
# 与 `hud.gd` 同口径的四档字号 / 同一套颜色；悬停色取 HUD 的"警告橙"同一个值（全项目唯一一份调色板）。
## 选项按钮的**外观**统一走 `scripts/ui/ui_style.gd`（`UiStyle`）—— 与暂停菜单共用同一份：
## 字号（30 → 悬停 42）、字色（白 → 金）、面板与边框都在那里，免得两处各持一份、改一处忘另一处
##（2026-09-25 用户要求抽共享，见 `99_decisions.md` 同日条目）。**这里只留布局参数。**
const OPTION_LEFT_MARGIN := 72.0   ## 用户："选项都在左边" ⇒ 竖排列表贴左边、垂直居中
const OPTION_SEPARATION := 18

const FADE_OUT_MS := 620
const FADE_IN_MS := 760

## 本层的 `CanvasLayer.layer`。⚠️ **必须高于 `Hud`**（Hud 没设 layer ⇒ 默认 1，而且它是在"黑透那一刻"
## 才被装配、**排在开始界面之后** ⇒ 同层时它会盖在黑幕上面）：否则渐亮时"顶栏 + 下注面板"**不跟着渐亮**、
## 直接浮在还是黑的画面上 —— 用户报的正是这个（"从『开始游戏』界面到押注界面的过渡，除了屏幕放大
## 还有屏幕渐黑，然后渐亮"）。调到 10 之后：**整幅画面（3D + 界面）一起渐黑、一起渐亮**。
const SCREEN_LAYER := 10

## 选项列表被打飞的运动参数。用户口径："按下开始按钮后，按钮有一个**向右的初速度**和一个**向左的加速度**，
## 最后**离开屏幕后消失**"，并补充"**v0 取小、a 取大，按钮最终只能向右移动一小会儿**"。
## ⇒ 参数就按这两句取：先向右挪十几像素（像被推了一下），随即被反向加速度扫回，**从左边出画**。
## ⚠️ 位移公式是 `x = v0·t − ½·a·t²`（纯运动学，不用缓动曲线）：峰值位移 = v0²/(2a) ≈ **16 px**（在 t ≈ 0.09 s），
## 回到原位在 t ≈ 0.19 s，**整块面板出画在 t ≈ 0.55 s** —— 刚好赶在渐黑结束（620 ms）之前。
const FLY_OUT_V0 := 340.0          ## 向右的初速度 px/s
const FLY_OUT_A := 3600.0          ## 向左的加速度 px/s²

const FADE_IDLE := 0
const FADE_OUT := 1
const FADE_IN := 2

# ---------------------------------------------------------------- 成员
var _fade: ColorRect = null
var _option_list: VBoxContainer = null
var _start_button: Button = null
var _continue_button: Button = null
## 「设置」（2026-09-25 新增）：**在「开始游戏」下方**（用户口径）。与「开始游戏」同进退 ——
## 模式选择那一档（见 `_on_start_pressed()`）里它跟着一起收起，`_on_back_pressed()` 再一起亮回来。
var _settings_button: Button = null
## 设置界面（懒建，挂在**本层**下面）。它是 `CanvasLayer` 且层号更高（`SettingsScreen.SETTINGS_LAYER = 20`
## > 本层的 10）⇒ 盖在选项之上；"返回"就是把它收起来，本层一直原样在底下。
var _settings: SettingsScreen = null
## 「图鉴」与「设置」同属第一档。图鉴层号比本层高，关掉就回到这一列。
var _codex_button: Button = null
var _codex: CodexScreen = null
## 「玩法说明」（2026-11-01 新增；用户："开始可以做个介绍，功能和玩法，新手教程"）：
## 与「图鉴」「设置」同属第一档。玩法说明层号 **22** 高于本层 ⇒ 盖在选项之上，关掉就回到这一列。
var _tutorial_button: Button = null
var _tutorial: TutorialScreen = null
## 「返回」（2026-09-25 新增）：**在「沙盒模式」下方**（用户口径），只在模式选择那一档出现 ——
## 点它**退回到只有「开始游戏」的第一档**（不是退出游戏，也不换场）。
var _back_button: Button = null
## 三个模式按钮（竞猜 / 沙盒 / 肉鸽；**开局就建好、先藏着**：`_on_start_pressed()` 里与「开始游戏」互换可见性）。
## ⚠️ 开局就建而不是"按下时才建"：① 选项列的高度随之确定，换档时不会有一帧布局抖动；
## ② 不在点击回调里创建/挂载节点（`name` 的序号也因此是固定的 `Option_0` … `Option_5`，见 `_add_option`）。
var _mode_buttons: Array[Button] = []
var _resume_buttons: Array[Button] = []
var _resume_back: Button = null
var _confirm: Control = null
var _pending_mode: String = ""
## 过渡状态机的当前档（与"游戏模式"是两件事：模式由 `mode_selected` 带走，这里只看渐黑 / 渐亮走到哪一步）。
var _fade_mode: int = FADE_IDLE
var _from_ms: int = 0
var _black_emitted: bool = false
## 选项列是否正在"被打飞"（见 `FLY_OUT_V0` / `FLY_OUT_A`）。
var _flying: bool = false
var _fly_from_ms: int = 0
## 玩家是否已经可以点选项。⚠️ 开场那段（整屏全黑 + 渐亮中）**必须为 false**：
## 黑幕是 IGNORE 鼠标的，按钮本身却一直可点 ⇒ 不拦的话"对着黑屏乱点一下"就能把开始界面跳过，
## 而且会在背景预演还没冻住时就换场。
var _input_ready: bool = false
## 已经点了「开始游戏」（本次渐亮结束后本层就自我释放，把界面交给 `Hud`）。
var _closing: bool = false

func build() -> void:
	## 见 `SCREEN_LAYER`：黑幕必须盖在 `Hud` 上面，否则渐亮时界面会"提前亮着"。
	layer = SCREEN_LAYER
	## 光标必须可见，否则按钮点不动（`05_ui_hud.md#4` 的"要能点界面就放出光标"）。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_options()
	_build_confirm()
	_build_fade()
	## 开局整屏全黑：背景那场预演（`StartShowcase`）正好在黑幕后面跑完并冻住。
	_fade.color.a = 1.0

# ---------------------------------------------------------------- 左侧选项列
func _build_options() -> void:
	_option_list = VBoxContainer.new()
	_option_list.name = "OptionList"
	_option_list.add_theme_constant_override("separation", OPTION_SEPARATION)
	## 贴左边、垂直居中：左对齐 + 垂直方向随内容居中（`PRESET_CENTER_LEFT` 就是这对锚点）。
	_option_list.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_option_list.offset_left = OPTION_LEFT_MARGIN
	_option_list.grow_horizontal = Control.GROW_DIRECTION_END
	_option_list.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_option_list)
	## ⚠️ **创建顺序 = 从上到下的显示顺序**（`VBoxContainer` 按子节点顺序排），
	## 所以这里刻意排成"两档各自连续"：
	##   第一档：开始游戏 → 继续游戏 → 设置 → 图鉴；
	##   新开一局：竞猜 → 沙盒 → 生存 → 返回；
	##   继续游戏：竞猜 → 生存 → 返回。没有存档的那一格是灰的。
	_start_button = _add_option("开始游戏", _on_start_pressed)
	_continue_button = _add_option("继续游戏", _on_continue_pressed)
	_settings_button = _add_option("设置", _on_settings_pressed)
	_codex_button = _add_option("图鉴", _on_codex_pressed)
	_mode_buttons.append(_add_option("竞猜模式", _on_mode_pressed.bind(MODE_QUIZ)))
	_mode_buttons.append(_add_option("沙盒模式", _on_mode_pressed.bind(MODE_SANDBOX)))
	_mode_buttons.append(_add_option("生存模式", _on_mode_pressed.bind(MODE_ROGUELIKE)))
	_back_button = _add_option("返回", _on_back_pressed)
	_resume_buttons.append(_add_option("竞猜模式", _on_resume_pressed.bind(MODE_QUIZ)))
	_resume_buttons.append(_add_option("生存模式", _on_resume_pressed.bind(MODE_ROGUELIKE)))
	_resume_back = _add_option("返回", _on_back_pressed)
	## 「玩法说明」**追加在最后**：创建顺序 = 显示顺序，而它只在第一档（首页）显示 ⇒ 玩家看到的顺序是
	## 开始游戏 → 继续游戏 → 设置 → 图鉴 → 玩法说明。⚠️ 不插在「图鉴」后面，是为了**不动前面那些
	## `Option_%d` 的序号**（文件头记着"序号是固定的 Option_0 … Option_5"，文档也按序号记位）。
	_tutorial_button = _add_option("玩法说明", _on_tutorial_pressed)
	_show_tier(0)
	_paint_continue()

## 往左侧列表里加一个选项（现在有「开始游戏 / 设置 / 图鉴 / 竞猜模式 / 沙盒模式 / 生存模式 / 返回」七个）。
func _add_option(text: String, handler: Callable) -> Button:
	var button := Button.new()
	## 节点名**不带显示文字**：`08_naming.md#3.1` 要求"动态生成的节点也必须命名"、且**序号写在 `_` 之后**
	##（例：`UnitA_sword_0`）；中文只允许出现在 `@export_group` 的显示文字里（§3.1.1 的明确例外）
	## ⇒ 不要拿 `text` 当标识符（同理见 `hud.gd` 的 `"TeamRow%d" % team`）。
	button.name = "Option_%d" % _option_list.get_child_count()
	button.text = text
	## 外观（尺寸 / 字号 / 白→金悬停 / 四档样式盒）统一由 `UiStyle` 装扮，见文件头。
	UiStyle.decorate_option(button)
	button.mouse_entered.connect(_on_option_hover.bind(button))
	button.mouse_exited.connect(_on_option_unhover.bind(button))
	button.pressed.connect(handler)
	_option_list.add_child(button)
	return button

func _on_option_hover(button: Button) -> void:
	UiStyle.apply_option_hover(button, true)

func _on_option_unhover(button: Button) -> void:
	UiStyle.apply_option_hover(button, false)

# ---------------------------------------------------------------- 过渡（渐黑 → 渐亮）
func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "ConfirmOverlay"
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", UiStyle.option_style(UiStyle.PANEL, 2))
	_confirm.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "ConfirmBox"
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var label := UiStyle.make_label("这会删除原来的存档并新开一局。", UiStyle.FONT_MID)
	label.name = "ConfirmLabel"
	box.add_child(label)
	var row := HBoxContainer.new()
	row.name = "ConfirmButtons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var yes := Button.new()
	yes.name = "ConfirmYes"
	yes.text = "确定"
	UiStyle.decorate_option(yes)
	yes.focus_mode = Control.FOCUS_NONE
	yes.pressed.connect(_on_confirm_yes)
	row.add_child(yes)
	var no := Button.new()
	no.name = "ConfirmNo"
	no.text = "取消"
	UiStyle.decorate_option(no)
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(_on_confirm_no)
	row.add_child(no)

func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.name = "FadeOverlay"
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE     ## ⚠️ 见文件头：绝不吃鼠标事件
	add_child(_fade)

func play_fade_in() -> void:
	## 黑幕淡出，露出已经冻住的背景（开场用，也用于"换场之后"）。
	_fade_mode = FADE_IN
	_from_ms = Time.get_ticks_msec()

## 按下「开始游戏」**不换场**（用户口径："点击开始游戏后再多出两个按钮"）：
## 原地把「开始游戏」（**连「设置」一起**）换成两个模式按钮 + 「返回」，**不打飞、不渐黑**
## —— 这只是选择，玩家还能改主意。
## ⚠️ 换档做成"收起一组、亮出另一组"而不是"再追加几个"：留着「开始游戏」会变成一个**按了没反应**
## 的按钮（它已经没有任何去处了）。两档占的仍是同一个左侧列表，样式一字不差。
## ⚠️ 「设置」跟着「开始游戏」一起收起（它俩同属第一档）：模式那一档有自己的「返回」，
## 点一下就能回到这一档 —— 免得在"选模式"的档里再挤两个不相关的入口。
func _on_start_pressed() -> void:
	if _closing or not _input_ready:
		return
	if _start_button == null or not _start_button.visible:
		return
	_show_tier(1)

func _on_continue_pressed() -> void:
	if _closing or not _input_ready:
		return
	if not MatchSave.any_exists():
		return
	_show_tier(2)

## 按下「返回」：就地退回第一档。
func _on_back_pressed() -> void:
	if _closing or not _input_ready:
		return
	_show_tier(0)

## 0 首页，1 新开一局，2 继续游戏。
func _show_tier(tier: int) -> void:
	var home := tier == 0
	var fresh := tier == 1
	var resume := tier == 2
	_start_button.visible = home
	_continue_button.visible = home
	_settings_button.visible = home
	_codex_button.visible = home
	_tutorial_button.visible = home
	for button in _mode_buttons:
		button.visible = fresh
	_back_button.visible = fresh
	for button in _resume_buttons:
		button.visible = resume
	_resume_back.visible = resume
	if _confirm != null:
		_confirm.visible = false
	if home:
		_paint_continue()
	if resume:
		_paint_enabled(_resume_buttons[0], MatchSave.has_quiz())
		_paint_enabled(_resume_buttons[1], MatchSave.has_roguelike())

func _paint_continue() -> void:
	_paint_enabled(_continue_button, MatchSave.any_exists())

func _paint_enabled(button: Button, enabled: bool) -> void:
	if button == null:
		return
	button.disabled = not enabled
	button.modulate = Color.WHITE if enabled else Color(0.45, 0.45, 0.45, 1.0)

## 按下「设置」：懒建设置界面并打开。⚠️ 它只是**盖在上面的一层**，本层（选项列）不动 ——
## 玩家点「退出」或「启用」就是回到这一档（见 `settings_screen.gd` 文件头）。
func _on_settings_pressed() -> void:
	if _closing or not _input_ready:
		return
	if _settings == null:
		_settings = SettingsScreen.new()
		_settings.name = "SettingsScreen"
		add_child(_settings)
	_settings.open()

func _on_codex_pressed() -> void:
	if _closing or not _input_ready:
		return
	if _codex == null:
		_codex = CodexScreen.new()
		_codex.name = "CodexScreen"
		add_child(_codex)
	_codex.open()

func _on_tutorial_pressed() -> void:
	if _closing or not _input_ready:
		return
	if _tutorial == null:
		_tutorial = TutorialScreen.new()
		_tutorial.name = "TutorialScreen"
		add_child(_tutorial)
	_tutorial.open()

## 选中某个模式：从这里开始才是**旧版「开始游戏」**的那段流程 ——
## 先让背景演示向中心推近，再渐黑；黑透那一刻 `main.gd` 按 `mode_selected` 传来的模式装配。
func _on_mode_pressed(mode: String) -> void:
	if _fade_mode != FADE_IDLE or _closing or not _input_ready:
		return
	if MatchSave.has_mode(mode):
		_pending_mode = mode
		if _confirm != null:
			_confirm.visible = true
		return
	_begin_fresh(mode)

func _on_resume_pressed(mode: String) -> void:
	if _fade_mode != FADE_IDLE or _closing or not _input_ready:
		return
	if not MatchSave.has_mode(mode):
		return
	_closing = true
	resume_selected.emit(mode)
	_start_fade_out()

func _on_confirm_yes() -> void:
	if _closing or _pending_mode == "":
		return
	var mode := _pending_mode
	_pending_mode = ""
	if _confirm != null:
		_confirm.visible = false
	_begin_fresh(mode)

func _on_confirm_no() -> void:
	_pending_mode = ""
	if _confirm != null:
		_confirm.visible = false

func _begin_fresh(mode: String) -> void:
	if _fade_mode != FADE_IDLE or _closing or not _input_ready:
		return
	_closing = true
	mode_selected.emit(mode)
	_start_fade_out()

func _start_fade_out() -> void:
	_fade_mode = FADE_OUT
	_from_ms = Time.get_ticks_msec()
	## ⚠️ **必须显式把黑幕重新打开**：开场那次渐亮结束时它被 `_fade.visible = false` 藏起来了
	##（当时是为了"别再画一块全屏透明四边"），而这里不打开的话，**整段"渐黑 → 渐亮"其实一点黑幕都没有** ——
	## 剩下能看见的只有按钮被打飞和背景推近。用户报的就是这个（"除了屏幕放大还有屏幕渐黑，然后渐亮"）。
	## ⚠️ 教训：探针只读 `_fade.color.a` 会漏掉"alpha 在动但节点不可见" —— 这次就是这么漏掉的，
	## 现在改成**可见性恒定**（`_build_fade()` 建好就不再隐藏）+ 这里再显式打开一次兜底。
	_fade.visible = true
	## 同一刻起把选项列"打飞"：向右一小段 → 被反向加速度扫回 → 从左边出画（见 `FLY_OUT_*`）。
	_flying = true
	_fly_from_ms = _from_ms

## 选项列被打飞：`x = v0·t − ½·a·t²`（纯运动学；计时按**绝对时刻**，不变量 I-13）。
## 完全出画（左边）之后就隐藏 —— 这样渐亮时绝不会再看到这个按钮。
func _tick_fly_out() -> void:
	if not _flying:
		return
	var t := float(Time.get_ticks_msec() - _fly_from_ms) / 1000.0
	_option_list.position.x = OPTION_LEFT_MARGIN + FLY_OUT_V0 * t - 0.5 * FLY_OUT_A * t * t
	## 宽度兜底用 `UiStyle.MIN_SIZE.x`：万一还没布局完（`size.x == 0`），也不至于在面板只挪了 16 px 时就把它藏了。
	var width := maxf(_option_list.size.x, UiStyle.MIN_SIZE.x)
	if _option_list.position.x + width < 0.0:
		_flying = false
		_option_list.visible = false

func _process(_delta: float) -> void:
	_tick_fly_out()
	if _fade_mode == FADE_IDLE:
		return
	var t := clampf(float(Time.get_ticks_msec() - _from_ms) / float(FADE_OUT_MS if _fade_mode == FADE_OUT else FADE_IN_MS), 0.0, 1.0)
	if _fade_mode == FADE_OUT:
		_fade.color.a = smoothstep(0.0, 1.0, t)
		if t >= 1.0 and not _black_emitted:
			## 黑透 ⇒ 通知 `main.gd` 换场。⚠️ 这一刻选项列**早就飞出屏幕并被隐藏**（见 `_tick_fly_out`），
			## 所以渐亮时不会再看到那个按钮 —— 这正是用户报的 bug
			##（"进入游戏界面了但开始游戏的按钮仍会停留一小段时间"）。这里再补一刀，双保险。
			_option_list.visible = false
			_black_emitted = true
			screen_blacked_out.emit()
		return
	_fade.color.a = 1.0 - smoothstep(0.0, 1.0, t)
	if t >= 1.0:
		_fade_mode = FADE_IDLE
		## ⚠️ **这里不再 `_fade.visible = false`**：可见性改成恒定（alpha = 0 本来就看不见），
		## 否则"下一次过渡"必须先记得把它打开 —— 2026-09-25 就是因为漏了这一步，按下「开始游戏」后
		## 整段过渡没有黑幕（见 `_on_mode_pressed()` 里的说明）。
		if _closing:
			queue_free()             ## 换场之后的渐亮：亮完本层就没用了（界面交给 Hud）
		else:
			_input_ready = true      ## 开场渐亮：亮完才允许点选项
