class_name PauseMenu
extends CanvasLayer
## 暂停菜单（齿轮 / Esc）：**三个模式（竞猜 / 沙盒 / 肉鸽）共用这一份**。
##
## 依据：`05_ui_hud.md#10`（暂停菜单）、`07_file_layout.md#5`（依赖方向）。
## 为什么单独成层：三套 HUD（`hud.gd` 竞猜 / `sandbox_hud.gd` 沙盒 / `roguelike_hud.gd` 肉鸽）都要这个菜单，
## 而它们是 `scripts/ui/` 下的**兄弟** —— 兄弟互相引用违反依赖方向（`07_file_layout.md#5` 只允许自上而下），
## 所以抽成同级的独立一层：由各自的 HUD 实例化（挂在 HUD 之下 ⇒ 随 HUD 一起释放）。
## ⚠️ 与 `ui_style.gd` 是同一类做法（把兄弟之间的公共物抽到同级）：那边抽的是**外观**，这边抽的是**整块菜单**。
##
## ⚠️ 整层 `PROCESS_MODE_ALWAYS`：菜单必须在"整棵树被暂停"时照样跑、照样能被点（用户口径：战斗中按 ESC）。
## 这只影响"处理与否"，不改任何玩法数据（R-07）。
##
## `configure(mode_host, ui_host)` 的两半契约（鸭子类型，靠 `has_method()` 兜底）：
##   · `mode_host`（玩法侧：`Game` / `Sandbox` / `Roguelike`）—— 只出**暂停与恢复**两件事：
##       `pause_match()`   整棵树暂停（`MatchPause.pause_tree()`）
##       `resume_match()`  解除暂停，并把暂停期间流逝的时间**从所有绝对时刻里扣掉**
##                         （树暂停**不会停表**，见不变量 I-13 —— 这一步少不得）
##   · `ui_host`（界面侧：`Hud` / `SandboxHud` / `RoguelikeHud`）—— **选项文案与"哪个相位能唤出"是界面的知识**
##     （界面本来就知道当前相位）：
##       `pause_allowed() -> bool`   当前相位是否允许唤出菜单（ESC 与齿轮都看它）
##       `pause_actions() -> Array`  追加在「继续」与「主菜单」之间的选项：`[{"text", "action"}]`
##                                   经典 = 「重新开始」；沙盒**布兵阶段为空**（用户口径：
##                                   布兵阶段不许出现「重新开始」）、战斗中 = 「结束战斗」；
##                                   肉鸽**准备 / 结算阶段为空**（同一条理由：玩家正在花钱）、战斗中 = 「结束回合」
##       `pause_action(action)`      某个中间项被选中（**黑透那一刻**才调；实现方自己负责解除暂停）
##
## 「继续」是所有模式共有的。离开这一局的那一颗：沙盒仍写「主菜单」，按下直接离开。
## 竞猜和生存写「保存并退出」，先 `write_resume()` 再走同一条离开。
## 离开本身走总线 `Events.main_menu_requested` —— 界面不认识 `main`（`07_file_layout.md#5`）。

# ---------------------------------------------------------------- 表现参数
## 本层的 `CanvasLayer.layer`：⚠️ 必须**高于 `Hud`**（Hud 没设 layer ⇒ 默认 1），否则菜单会画在
## 顶栏 / 下注面板**下面**；又必须**低于 `StartScreen`**（`SCREEN_LAYER = 10`），
## 否则退回主菜单时那块黑幕盖不住菜单。
const MENU_LAYER := 5
## 过渡（渐暗 / 渐亮）与开始界面同源的两个时长。计时一律按**绝对时刻**（不变量 I-13）。
const FADE_OUT_MS := 620
const FADE_IN_MS := 760
const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.62)
const OPTION_SEPARATION := 18

const FADE_IDLE := 0
const FADE_OUT := 1
const FADE_IN := 2

var _mode_host: Object = null
var _ui_host: Object = null

var _root: Control = null
var _options: VBoxContainer = null
var _fade: ColorRect = null
## 设置界面（2026-09-25 新增）：**懒建**（第一次点「设置」才 `new()`），挂在本层下面 ——
## 它是 `CanvasLayer` 且层号更高（`SettingsScreen.SETTINGS_LAYER = 20` > 本层 5），
## 所以盖在本层之上，而"返回"就是把它收起来（本层一直原样在底下，见那边文件头）。
var _settings: SettingsScreen = null
var _codex: CodexScreen = null
var _fade_mode: int = FADE_IDLE
var _fade_from_ms: int = 0
var _action: String = ""
var _black_done: bool = false

## 接上两个宿主并建好控件。**建好之后本层一直存在**（只是 `_root.visible = false`），
## 每次打开只重建"中间那几项"（选项随相位而变）。
func configure(mode_host: Object, ui_host: Object) -> void:
	_mode_host = mode_host
	_ui_host = ui_host
	layer = MENU_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func is_open() -> bool:
	return _root != null and _root.visible

## 当前相位是否允许唤出菜单（经典 = 押注 / 战斗 / 结算；沙盒 = 布兵 / 战斗 / 结果）。
func allowed() -> bool:
	if _ui_host == null or _root == null:
		return false
	if _ui_host.has_method("pause_allowed"):
		return bool(_ui_host.pause_allowed())
	return false

# ---------------------------------------------------------------- 打开 / 关闭
## 打开：**整棵树暂停**（用户口径），但本层是 ALWAYS ⇒ 菜单照常响应。
## ⚠️ 暂停时长由玩法侧（`Game` / `Sandbox`）记账并在恢复时平移所有绝对时刻。
func open() -> void:
	if _root == null or _root.visible or _fade_mode != FADE_IDLE:
		return
	if _mode_host == null or not allowed():
		return
	if _mode_host.has_method("pause_match"):
		_mode_host.pause_match()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE      ## 战斗中光标本来是锁住的，菜单要能点
	_rebuild_options()
	_root.visible = true

## 关闭 = 继续（**瞬间**，用户口径：不过渡）。
## ⚠️ 顺带把设置界面收掉：它挂在本层下面、却是**另一个 `CanvasLayer`**（层号更高），
## 本层 `_root.visible = false` **管不到它** —— 不收的话"点继续"以后设置界面还浮在场上。
## ⚠️ 鼠标模式不在这里恢复：`CameraRig._process` 每帧自己核对一次（战斗阶段会立刻重新锁住光标）。
func close() -> void:
	_close_settings()
	_close_codex()
	if _root == null or not _root.visible:
		return
	_root.visible = false
	if _mode_host != null and _mode_host.has_method("resume_match"):
		_mode_host.resume_match()

# ---------------------------------------------------------------- 构建
func _build() -> void:
	_root = Control.new()
	_root.name = "PauseMenu"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS   ## ⚠️ 暂停时还得能点
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  ## 吃掉背后的点击
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	_options = VBoxContainer.new()
	_options.name = "PauseOptions"
	_options.set_anchors_preset(Control.PRESET_CENTER)
	_options.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_options.grow_vertical = Control.GROW_DIRECTION_BOTH
	_options.add_theme_constant_override("separation", OPTION_SEPARATION)
	_root.add_child(_options)

	## ⚠️ 过渡黑幕**加在按钮之后** ⇒ 同层时画在菜单上面 ⇒ 变暗时这个界面自己也跟着变暗（用户口径）。
	_fade = ColorRect.new()
	_fade.name = "PauseFade"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

## 重建选项：继续 / **中间几项（由界面侧按相位给）** / 设置 / 主菜单。
## ⚠️ 用 `remove_child()` + `queue_free()` 而不是只 `queue_free()`：名字是按 `get_child_count()`
## 编序号的（§3.1），不先摘掉的话新按钮会跟旧按钮**重名**，而且旧按钮这一帧还留在布局里
##（`queue_free()` 要到帧尾才真的删）。
func _rebuild_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	_add_option("继续", _on_resume)
	if _ui_host != null and _ui_host.has_method("pause_actions"):
		for entry in _ui_host.pause_actions():
			var item: Dictionary = entry
			_add_option(String(item.get("text", "")), _on_action.bind(String(item.get("action", ""))))
	## 「图鉴」和「设置」都不随相位变，写在离开这一局的那一颗上方。
	_add_option("图鉴", _on_codex)
	_add_option("设置", _on_settings)
	if _mode_host != null and _mode_host.has_method("write_resume"):
		_add_option("保存并退出", _save_match_and_leave)
	else:
		_add_option("主菜单", _on_main_menu)

## 与开始界面的「开始游戏」同一种按钮（同字号 / 同悬停：**原地放大** + 白→金），**但不打飞**（用户口径）。
## 外观统一由 `UiStyle` 装扮 —— 不再各持一份常量（2026-09-25 抽共享）。
func _add_option(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = "PauseOption_%d" % _options.get_child_count()   ## 纯英文 + 序号（§3.1）
	button.text = text
	UiStyle.decorate_option(button)
	button.mouse_entered.connect(UiStyle.apply_option_hover.bind(button, true))
	button.mouse_exited.connect(UiStyle.apply_option_hover.bind(button, false))
	button.pressed.connect(handler)
	_options.add_child(button)
	return button

# ---------------------------------------------------------------- 选项
func _on_resume() -> void:
	if _fade_mode != FADE_IDLE:
		return                       ## 正在跑"换场"的过渡：别理
	close()

## 「设置」：懒建 + 打开。⚠️ 打开设置**不动暂停状态**（整棵树本来就停着）—— 玩家在设置里改音量时，
## 底下的战斗仍然静静地停着，收起来还是原来那个暂停菜单。
func _on_settings() -> void:
	if _settings == null:
		_settings = SettingsScreen.new()
		_settings.name = "SettingsScreen"
		add_child(_settings)
	_settings.open()

func _close_settings() -> void:
	if _settings != null and _settings.is_open():
		_settings.close()

func _on_codex() -> void:
	if _codex == null:
		_codex = CodexScreen.new()
		_codex.name = "CodexScreen"
		add_child(_codex)
	_codex.open()

func _close_codex() -> void:
	if _codex != null and _codex.is_open():
		_codex.close()

func _save_match_and_leave() -> void:
	if _mode_host != null and _mode_host.has_method("write_resume"):
		_mode_host.write_resume()
	_on_main_menu()

func _on_main_menu() -> void:
	_begin_transition("main_menu")

func _on_action(action: String) -> void:
	_begin_transition(action)

func _begin_transition(action: String) -> void:
	if _fade_mode != FADE_IDLE:
		return
	_action = action
	_black_done = false
	_fade_from_ms = Time.get_ticks_msec()
	_fade_mode = FADE_OUT

## 过渡推进（在 `_process` 里跑；本层是 ALWAYS ⇒ 暂停中照样推进）。计时按绝对时刻（不变量 I-13）。
func _process(_delta: float) -> void:
	if _fade_mode == FADE_IDLE or _fade == null:
		return
	var total := FADE_OUT_MS if _fade_mode == FADE_OUT else FADE_IN_MS
	var t := clampf(float(Time.get_ticks_msec() - _fade_from_ms) / float(total), 0.0, 1.0)
	if _fade_mode == FADE_OUT:
		_fade.color.a = smoothstep(0.0, 1.0, t)      ## 渐暗（菜单自己也跟着暗）
		if t >= 1.0 and not _black_done:
			_black_done = true
			_apply_action()                          ## 黑透那一刻才换场（玩家看不见）
		return
	_fade.color.a = 1.0 - smoothstep(0.0, 1.0, t)    ## 渐亮
	if t >= 1.0:
		_fade_mode = FADE_IDLE

## 黑透那一刻要做的事。
func _apply_action() -> void:
	_close_settings()                ## 换场（主菜单 / 重新开始 / 结束战斗）时设置界面不能留在场上
	_close_codex()
	var action := _action
	_action = ""
	if action == "main_menu":
		## ⚠️ **不自己收黑幕**：`main.gd` 收到信号后会拆掉整场比赛（连同本层与这层黑幕），
		## 而开始界面自带一层 α=1 的黑幕接手 ⇒ 交接处不会闪一下。
		Events.main_menu_requested.emit()
		return
	## 中间那一项（经典 = 重新开始 / 沙盒 = 结束战斗）：交给界面侧转给玩法侧。
	## ⚠️ 实现方**必须自己解除暂停**（经典走 `Game.restart_game()`、沙盒走 `Sandbox.end_battle()`）——
	## 这里绝不补一次 `resume_match()`：那会把暂停时长重复扣一遍（`shift_deadlines` 会被调两次）。
	if _ui_host != null and _ui_host.has_method("pause_action"):
		_ui_host.pause_action(action)
	_root.visible = false            ## 菜单收掉（此刻屏幕全黑，看不见切换）
	_fade_mode = FADE_IN
	_fade_from_ms = Time.get_ticks_msec()

# ---------------------------------------------------------------- 输入
## ESC = 菜单开关（用户口径："快捷键 esc"）。齿轮按钮由各 HUD 自己建、自己接 `open()`。
## ⚠️ 直接读 `KEY_ESCAPE`，**不动 `project.godot` 的输入映射** —— 与 `camera_rig._alt_hold()` 读 `KEY_ALT`
## 是同一种做法；动映射表会让 `05_ui_hud.md#5` 的输入映射表立刻过期。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if _root == null:
		return
	## ⚠️ **设置界面开着时，ESC 归它**（它那边是"退出 = 修改无效"）。
	## 这里必须**直接让路**，不能靠"谁先收到事件"（两个节点都认 ESC，先后顺序是引擎的遍历顺序，
	## 不是我们能依赖的东西）—— 不让路的话按一下 ESC 会**同时**关掉设置和暂停菜单。
	if _settings != null and _settings.is_open():
		return
	if _codex != null and _codex.is_open():
		return
	if _root.visible:
		if _fade_mode == FADE_IDLE:
			close()                  ## 再按一次 ESC = 继续
		return
	if allowed():
		open()
	## ⚠️ 吃掉这一下：本作没有别的 ESC 用途，但留着不标记的话，将来任何"也认 ESC"的节点
	## 都会跟着响应（`_unhandled_input` 是**逐个节点**发的，不标记就不会停）。
	get_viewport().set_input_as_handled()
