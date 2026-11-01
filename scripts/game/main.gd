extends Node3D
## 入口：组装场景并接线
##
## 依据：docs/bible/07_file_layout.md#5-依赖方向（main 只做装配，不含玩法逻辑）
## 场景内所有内容（场地 / 选手 / 相机 / HUD）都由代码构建，.tscn 只保留这一个根节点。
##
## 2026-09-25（用户："新增一个『开始界面』，点击『开始游戏』才会进入游戏游玩的界面"）：
## 装配分成**两段**，中间夹一次"渐黑 → 渐亮"：
##   ① `_ready()` 只建**开始界面 + 背景演示**（灰色场地 + 固定阵容那场静止的战斗 + 环绕镜头）；
##   ② 玩家在开始界面上选完模式、黑幕黑透那一刻（`StartScreen.screen_blacked_out`）才装配真比赛。
## ⚠️ 顺序上必须**先释放背景演示、再建真单位**：背景演示里的兵也在 `units` 组里，
## 而真单位的索敌是"全场最近者"，留着它就会把背景那 8 个兵当成敌人打。
##
## 2026-09-25 同日第二改（用户："点击『开始游戏』之后再多出两个按钮：竞猜模式 / 沙盒模式"）：
## 模式选择是**开始界面自己的事**（`StartScreen` 里两档按钮），这里只接结果：
##   · `mode_selected(mode)` —— 按下模式那一刻（用于让背景演示向中心推近）；
##   · `screen_blacked_out`   —— 黑透那一刻按 `_mode` 分岔装配（经典 / 沙盒）。

var _showcase: StartShowcase = null
var _start_screen: StartScreen = null
var _match_started: bool = false
## 玩家选的模式（`StartScreen.MODE_QUIZ` / `StartScreen.MODE_SANDBOX`）。
## ⚠️ **模式的 ID 只有 `StartScreen` 一处出处**（它是选择发生的地方），这里只记不改。
var _mode: String = StartScreen.MODE_QUIZ
## 装配出来的场地与相机（两种模式的共用件，见 `_build_stage()`）。
var _arena: Arena = null
var _rig: CameraRig = null
## 兵种模型预热是否已经做过（进程级一次就够，见 `_prewarm_unit_models()`）。
var _prewarmed: bool = false
## 音频层（2026-09-25 起**全程常驻**，见 `_ready()` 与 `_setup_audio()`）。
var _audio: AudioManager = null
## 这一场是从存档接着打，而不是新开一局。
var _loading_save: bool = false

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	_save_match_on_quit()

## 关掉窗口时，竞猜和生存先写下「保存并退出」用的那份存档。沙盒没有这份存档。
func _save_match_on_quit() -> void:
	if not _match_started:
		return
	var quiz := get_node_or_null("Game")
	if quiz != null and quiz.has_method("write_resume"):
		quiz.write_resume()
		return
	var run := get_node_or_null("Roguelike")
	if run != null and run.has_method("write_resume"):
		run.write_resume()

func _ready() -> void:
	## 暂停菜单点「主菜单」时由暂停菜单发出来（界面层不认识 `main`，只能走总线，见 `07_file_layout.md#5`）。
	Events.main_menu_requested.connect(_on_main_menu_requested)
	## ⚠️ 音频层**先建**：开始界面那一屏也要有 BGM（用户："将其加入每一个界面"）。
	UserPrefs.load_battle_scenes()
	UserPrefs.load_video()
	UserPrefs.load_input()
	_setup_audio()
	UserPrefs.load_audio(_audio)
	_open_start_screen()
	_prewarm_unit_models()

## 建音频层并起 BGM。**只在 `_ready()` 里建一次、之后永不释放**（`_on_main_menu_requested()` 会跳过它）。
##
## ⚠️ **2026-09-25 之前它是随比赛建的**（在 `_build_stage()` 里）⇒ 开始界面那一屏**没有音频层**。
## 用户的第二条要求（"已引入 BGM，将其加入每一个界面"）与这条直接冲突：要覆盖开始界面，
## 音频层就得活得比"一场比赛"长。两条路里选了**"提前建、全程不释放"**，
## 因为另一条（把 `AudioManager` 改成 Autoload）会改掉**不变量 I-06** 的 Autoload 顺序表。
## ⇒ 现在的口径：**音频层是 `main` 的子节点，生命周期 = 进程**；I-06 一个字没动。
func _setup_audio() -> void:
	_audio = AudioManager.new()
	_audio.name = "AudioManager"
	add_child(_audio)
	_apply_screen_bgm()

## 每个界面该放哪条 BGM。⚠️ **现在所有界面共用 `BGM_MAIN`**（用户口径："之后不同界面会用不同的 bgm，
## 但现在先共用一个"）—— 将来分界面时**只改这一个函数**（按 `_screen` 之类的状态返回不同 id）。
## ⚠️ `play_bgm()` 是**按 id 幂等**的（同一条正在放就什么都不做）⇒ 每次换屏都调一遍是安全的，
## 不会把音乐重头开始。
func _apply_screen_bgm() -> void:
	if _audio != null:
		_audio.play_bgm(AudioManager.BGM_MAIN)

## **兵种模型预热**（2026-09-25 修 bug）：把 `GameConfig.TYPE_ORDER` 里的**每一个兵种**各**画一帧**，
## 让渲染管线在这一屏就把模型与特效的着色器 / 管线编译完。
## ⚠️ 名单**不写死**（2026-09-25 第七轮起兵种 17 → **18**：新增召唤石柱）：一律遍历 `TYPE_ORDER` ——
## 以后再加兵种，这一处自动跟上（新兵种第一次被摆出来时就不会现编译着色器了）。
##
## ⚠️ 用户报的 bug："沙盒模式偶尔会出现点击下兵后**过一会儿兵种才会在场上出现**（拖动也是）"——
## 根因**不是玩法逻辑**（兵是**当帧**就摆下的，探针实测过），而是**某个兵种的模型第一次被渲染时
## 现编译着色器**：整整卡住一帧（实测 **594 ms**），玩家看到的就是"点了没反应、过一会儿才出现"。
##
## ⚠️ 为什么"**偶尔**"：开始界面的背景演示只用到 5 个兵种（剑盾 / 长矛 / 短弓 / 长弓 / 扇子），
## 剩下 7 个（骑士 / 投石车 / 弩车 / 狂战士 / 火焰拳 / 轻骑兵 / 沙虫）**从没被画过** ⇒
## 玩家在沙盒里第一次摆到哪一个，就在那一刻卡一下（实测：热兵种 18 ms，寒兵种 594 ms）。
##
## ⚠️ 为什么放在**这一屏**：开始界面**整屏是黑的**（`StartScreen._fade.color.a = 1.0`，直到背景预演
## 冻住才渐亮）⇒ 这笔一次性卡顿、以及这几个临时单位，**都不会被看见**。而着色器是**进程级**的，
## 预热一次之后**两种模式**都不再付这笔钱 —— 竞猜模式原先是在黑幕里刷阵容，所以从没暴露过这个问题。
##
## ⚠️ 与 `arena.gd#_build_impact_dust_pool()` 是**同一类修法**：那次治的是落点扬尘"每次现造
## 网格 + 透明材质 ⇒ 现编译着色器"的卡顿，这次治的是单位模型。
## ⚠️ 只在"打开游戏"那一次做（`_prewarmed` 把关）：退回主菜单时会重开开始界面，但没必要重来一遍。
func _prewarm_unit_models() -> void:
	if _prewarmed:
		return
	_prewarmed = true
	var stage := Node3D.new()
	stage.name = "WarmupStage"
	add_child(stage)
	var index := 0
	for type_id in GameConfig.TYPE_ORDER:
		var unit := Unit3D.new()
		unit.name = "Warmup_%d" % index          ## §3.1：动态生成的节点也要命名（序号写在 `_` 之后）
		unit.setup(0, String(type_id))           ## 只用 0 队：两队差别只是材质底色，着色器变体相同
		stage.add_child(unit)
		## ⚠️ 冻结这两条 process：它们只用来"被画一帧"，不该跑 AI / 物理 / 特效更新
		##（`_process` 里的 `_update_flame_fx()` 会把刚显示出来的特效件又藏回去）。
		unit.set_process(false)
		unit.set_physics_process(false)
		## ⚠️ 碰撞层清零：免得这几个临时单位在背景演示里挡住 / 推开演示兵（只画一帧，不需要碰撞）。
		unit.collision_layer = 0
		unit.collision_mask = 0
		## 摆在演示群中心附近（背景演示的环绕镜头半径 9.5 m，±6 m 之内一定在画面里）。
		unit.global_position = Vector3(-6.0 + float(index % 6) * 2.4, 0.6, -2.0 + float(index / 6) * 2.4)
		unit.warmup_show_all_fx()                ## 连"透明 / 自发光"那几套也一起画一帧
		index += 1
	## 画够 3 帧（≥1 帧就够，多留两帧防抖），然后连台子一起扔掉。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	stage.queue_free()

## 装配"开始界面 + 背景演示"这一屏。**启动时**与**从比赛退回主菜单时**共用同一段代码。
func _open_start_screen() -> void:
	_showcase = StartShowcase.new()
	_showcase.name = "StartShowcase"
	add_child(_showcase)

	_start_screen = StartScreen.new()
	_start_screen.name = "StartScreen"
	add_child(_start_screen)
	_start_screen.build()
	_start_screen.screen_blacked_out.connect(_on_screen_blacked_out)
	## 按下模式那一刻（还没黑）：背景演示场景**向中心推近**；"按钮被打飞"由开始界面自己驱动
	##（`StartScreen._tick_fly_out`）。
	_start_screen.mode_selected.connect(_on_mode_selected)
	_start_screen.resume_selected.connect(_on_resume_selected)
	## 背景那场架"打起来并冻住"之后才开始渐亮 ⇒ 玩家看到的第一帧就是那张静止的战斗画面
	##（在那之前整屏全黑，正好盖住单位出生与走动）。
	_showcase.roll_finished.connect(_start_screen.play_fade_in)

## 暂停菜单点了「主菜单」：拆掉整场比赛、回到开始界面（用户口径：**退到主菜单不保存战斗**）。
## ⚠️ 先解除暂停：开始界面的背景演示要靠 `_process` 跑预演，树停着它永远冻不上、也就渐亮不了。
## ⚠️ 这里用 `queue_free()` 而不是 `free()`：本函数是**在暂停菜单的 `_process` 里**（信号是同步发的）
## 被调用的，立即释放"正在执行自己的节点"不安全；延迟到帧尾释放，而这一帧里新开始界面的黑幕
## 已经盖上了 ⇒ 交接不会闪。
func _on_main_menu_requested() -> void:
	get_tree().paused = false
	## ⚠️ **释放所有子节点**，不再按名字列举：三种模式的节点树不一样（竞猜有 `Game`/`Hud`，
	## 沙盒有 `Sandbox`/`SandboxHud`，肉鸽有 `Roguelike`/`RoguelikeHud`），
	## 按名字列举的话，将来加一种模式就会漏掉一个 ——
	## 而漏掉的那个会**跨模式留在场上**（沙盒摆的兵与场地会跟着下一场经典比赛一起跑）。
	## 比赛期间的子节点本来就只有这些，所以"全放"是安全的。
	## ⚠️ **唯一例外是音频层**（`_audio`）：它 2026-09-25 起全程常驻（BGM 要跟着人回开始界面，
	## 见 `_setup_audio()`）⇒ 把这一条**显式写出来**，而不是靠"它还没建"这种巧合。
	## 背景演示必须先**立即**释放（它的兵也在 `units` 组里），见 `_release_showcase()`。
	_release_showcase()
	for child in get_children():
		if child == _audio:
			continue
		child.queue_free()
	_start_screen = null
	_arena = null
	_rig = null
	_match_started = false
	_open_start_screen()
	_apply_screen_bgm()

## 按下某个模式：背景演示场景开始向中心推近（渐黑期间完成），并记住装配哪一套。
## ⚠️ 这里**不换场** —— 换场在黑透那一刻（`_on_screen_blacked_out`），玩家看不见。
func _on_mode_selected(mode: String) -> void:
	_loading_save = false
	_mode = mode
	if is_instance_valid(_showcase):
		_showcase.begin_zoom()

func _on_resume_selected(mode: String) -> void:
	_loading_save = true
	_mode = mode
	if is_instance_valid(_showcase):
		_showcase.begin_zoom()

## 黑幕全黑的那一刻：换场。玩家看不见这一段，所以可以放心地"拆掉一个世界、建起另一个"。
func _on_screen_blacked_out() -> void:
	if _match_started:
		return
	_match_started = true
	_start_match()
	_start_screen.play_fade_in()

## 真比赛：先建两种模式**共有**的舞台，再按 `_mode` 分岔挂上各自的玩法与界面。
func _start_match() -> void:
	_build_stage()
	## 换屏时再看一眼该放哪条 BGM（幂等 ⇒ 与开始界面同一条时它不会被打断，见 `_apply_screen_bgm()`）。
	_apply_screen_bgm()
	if _mode == StartScreen.MODE_SANDBOX:
		_start_sandbox()
		return
	if _mode == StartScreen.MODE_ROGUELIKE:
		_start_roguelike()
		return
	_start_quiz()

## 立即释放背景演示（**不是** `queue_free()`）：它的兵也在 `units` 组里，而紧接着就要建真单位 ——
## 延迟到帧尾释放会留下"同一帧里两批单位共存"的窗口，这个窗口里真单位的索敌 / 质心计算都可能
## 把背景兵算进去。两个调用点（换场、退回主菜单）都在黑屏期间，硬释放没有观感代价。
func _release_showcase() -> void:
	if not is_instance_valid(_showcase):
		return
	_showcase.free()
	_showcase = null

## 舞台 = 场地 + 相机（两种模式逐字相同的那一段）。
## ⚠️ **音频层不再在这里建**（2026-09-25 起全程常驻，见 `_setup_audio()`）—— 它比"一场比赛"活得长，
## 所以"建在第一批单位出生之前"这条约束由 `_ready()` 直接满足（那时连开始界面都还没建）。
func _build_stage() -> void:
	_release_showcase()

	_arena = Arena.new()
	_arena.name = "Arena"
	## ⚠️ **场地尺寸按模式给**（2026-09-26 第六块起；2026-09-27 第七块：用户"场地的长变为原来的 1.5 倍"
	## + 南北两条 12 m 布阵带）：
	## 肉鸽用 `ROGUELIKE_ARENA_HALF_X`（**150**）+ `roguelike_arena_half_z()`（**111.5** —— 已含南北两条
	## 12 m 宽的"前进布阵带"，2026-09-27 按用户红笔标注订正：带子贴**两条长边**、边界整体向外扩）；
	## 其余两个模式用全局值（100 × 50，**逐位不变**）。
	## ⚠️ 必须在 `add_child()` **之前**写：场地几何（地板 / 边界墙 / 风景 / 出生点）全在 `_ready()` 里建。
	if _mode == StartScreen.MODE_ROGUELIKE:
		_arena.half_x = GameConfig.ROGUELIKE_ARENA_HALF_X
		_arena.half_z = GameConfig.roguelike_arena_half_z()
	add_child(_arena)
	## 沙盒和生存进模式时抽一次场景，这一次进入里不再换。
	## 竞猜不在这里抽：第 1 轮在 `setup_first_round()`，之后每一轮在 `next_round()`。
	if _mode != StartScreen.MODE_QUIZ and not _loading_save:
		_arena.roll_battle_scene()

	_rig = CameraRig.new()
	_rig.name = "CameraRig"
	add_child(_rig)
	_rig.setup(_arena)

## 竞猜模式：与"没有开始界面"那些版本的 `_ready()` 逐行相同（对局 + HUD + 首轮）。
func _start_quiz() -> void:
	var game := Game.new()
	game.name = "Game"
	add_child(game)
	game.bind(_arena, _rig)

	var hud := Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.build(game, _rig)

	if _loading_save:
		game.restore_from_save(MatchSave.read_quiz())
	else:
		game.setup_first_round()
		_rig.on_quiz_phase()

## 沙盒模式：玩家自己摆兵（`Sandbox`）+ 自己的界面（`SandboxHud`）。
## ⚠️ **没有** `setup_first_round()` 这一说 —— 沙盒不掷阵容、不押注、不启赛程（见 `sandbox.gd` 文件头）。
func _start_sandbox() -> void:
	var sandbox := Sandbox.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	sandbox.bind(_arena, _rig)

	var sb_hud := SandboxHud.new()
	sb_hud.name = "SandboxHud"
	add_child(sb_hud)
	sb_hud.build(sandbox, _rig)

	## 进布兵阶段：选好默认兵种，并把相机摆到"经典下注阶段"那一套（全景机位 + 光标可见 ——
	## 布兵全靠点地面，光标锁住就没法摆）。
	sandbox.begin()

## 肉鸽模式（2026-09-26 新增）：`Roguelike`（回合 / 补给 / 血量）+ `RoguelikeHud`。
## ⚠️ **分步落地**：当前只有骨架 + 经济记账（购买 / 解锁 / 网格 / 敌人还没做，见 `roguelike.gd` 的文件头）。
## ⚠️ 与沙盒同一条理由：它**不启赛程**（`match_active` 恒为假）—— 兴奋圈 / 90 s 时限 / 僵持判平
## 都不是这个模式的规则。
func _start_roguelike() -> void:
	var roguelike := Roguelike.new()
	roguelike.name = "Roguelike"
	add_child(roguelike)
	roguelike.bind(_arena, _rig)

	var rg_hud := RoguelikeHud.new()
	rg_hud.name = "RoguelikeHud"
	add_child(rg_hud)
	rg_hud.build(roguelike, _rig)

	## 进第 1 回合的准备阶段：领 20 补给、相机摆到全景机位（`Roguelike.begin()` 里调 `on_betting_phase()`）。
	if _loading_save:
		var saved := MatchSave.read_roguelike()
		if saved.is_empty():
			_arena.roll_battle_scene()
			roguelike.begin()
		else:
			roguelike.restore_opening(saved)
	else:
		roguelike.begin()
