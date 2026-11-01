class_name CameraRig
extends Node3D
## 观赛相机
##
## 三种模式：
##   OVERVIEW —— **自由视角**（2026-09-18 改造）：与 FLY 同一套移动（WASD + 鼠标转向），
##                区别只在"看比赛"的状态——隐藏 HUD 与光标，**点鼠标左/右键**退出
##   FLY      —— **第一人称式自由飞行**：WASD 控制镜头的空间位置，移动鼠标控制镜头朝向
##   FOLLOW   —— 锁定某位选手，镜头跟着它走，鼠标仍可自由转头
##
## 依据：docs/bible/05_ui_hud.md（输入映射）、08_naming.md（命名约定）
## 说明：相机手感参数（灵敏度 / 飞行速度 / 全景 / 跟随）定义在 `GameConfig`
## 的"相机手感"段，本节点只读取、不保存副本。

enum Mode { OVERVIEW, FLY, FOLLOW }
## 战斗中接管一个单位。CLOSED = 这个模式不许操作；ANY = 沙盒两队；OWN = 生存只限我方。
enum PilotGate { CLOSED, ANY, OWN }

var arena: Node3D = null
var mode: int = Mode.OVERVIEW

var _pivot: Node3D = null
var _cam: Camera3D = null
var _pos: Vector3 = Vector3.ZERO          ## 平滑后的相机世界位置
var _yaw: float = 0.0
var _pitch: float = -0.6
var _velocity: Vector3 = Vector3.ZERO
var _shake: float = 0.0
## bug 1（2026-09-18）：全景"点击退出"的上膛标志。进入全景时归零，
## 等鼠标左右键**全部松开**之后才上膛——否则"点「全景」按钮"那一下会立刻把全景点掉。
var _overview_click_armed: bool = false
## bug 2 / bug 3（2026-09-18）：进入全景时记下当时的机位；退出全景时**平滑回到这里**。
## 之所以要记：进入全景会把镜头送到"战场上方 73 m 的全景机位"，退出必须回到玩家原来看的地方。
var _overview_return_pos: Vector3 = Vector3.ZERO
var _overview_return_yaw: float = 0.0
var _overview_return_pitch: float = 0.0
## 战斗定格期间的自由视角只藏界面：进出都不改机位，也不飞回进入时的姿态。
var _overview_keeps_pose: bool = false
## 开赛过渡（下注全景 → 开战指挥视角）。用绝对时刻计时，遵守不变量 I-13（不用累加 delta）
var _blend_until_ms: int = 0
var _blend_total_ms: int = 1
var _blend_from_pos: Vector3 = Vector3.ZERO
var _blend_to_pos: Vector3 = Vector3.ZERO
var _blend_from_yaw: float = 0.0
var _blend_to_yaw: float = 0.0
var _blend_from_pitch: float = 0.0
var _blend_to_pitch: float = 0.0
## 正在跑的那段过渡是不是**退出自由视角的回程**（2026-09-19 修 bug）。
## 回程被 WASD / 鼠标打断时，必须先把镜头**落到回程终点**再取消 —— 否则玩家一边按着 WASD
## 一边退出时，回程在第一帧就被中断，镜头永远停在 73 m 的俯瞰位上
##（用户报告："无法回到正常机位"）。
var _blend_returning_overview: bool = false
var _follow_team: int = -1
var _follow_index: int = -1
## 正在打（任务 8）：开赛之后鼠标隐藏；押注阶段与结算浮层（界面可见）要显形，否则点不了按钮
var _fight_started: bool = false
## 滚轮推拉的准用相位（2026-09-25 用户：只给**竞猜模式的押注阶段**与**沙盒模式的布兵阶段**）：
## 由 `on_betting_phase()` 打开、`on_fight_phase()` / `on_round_result()` 关掉 ——
## 恰好是"这两种模式里界面可见、镜头还没进入指挥视角"的那一段（见 05_ui_hud.md#5.2）。
var _zoom_allowed: bool = false
## 自由飞行的**模式倍率**（2026-09-27 用户："（仅限肉鸽模式）镜头的移动速度变为原来的2倍"）。
## ⚠️ 由两个"部署相位"的入口各自设定：`on_betting_phase()`（竞猜押注 / 沙盒布兵）置 1.0、
## `on_roguelike_phase()` 置 `CAM_FLY_SPEED_ROGUELIKE_MULT` —— 肉鸽场地是 150 × 111.5，
## 用竞猜那档速度挪起来太慢。⚠️ 与 Shift 的加速**相乘**，两条互不覆盖。
var _fly_mult: float = 1.0
## 滚轮推拉的**目标机位**：滚轮每一格只改它，`_pos` 每帧平滑追过去（见 `CAM_ZOOM_SMOOTH`）。
## ⚠️ 必须多这一格：直接往 `_pos` 上一格一跳正是用户 2026-09-25 报的"不够顺滑、过渡不光滑"。
var _zoom_target: Vector3 = Vector3.ZERO
## bug 3（2026-09-18）：Alt 的事件兜底状态（轮询见 `_alt_hold()`）
var _alt_down: bool = false
var _pilot_gate: int = PilotGate.CLOSED
var _pilot_unit: Unit3D = null
var _hover_unit: Unit3D = null
var _pilot_shoulder: bool = false
var _pilot_has_return: bool = false
var _pilot_return_pos: Vector3 = Vector3.ZERO
var _pilot_return_yaw: float = 0.0
var _pilot_return_pitch: float = 0.0
var _pilot_layer: CanvasLayer = null
var _pilot_hp_label: Label = null
var _pilot_skill_label: Label = null

func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.current = true
	_cam.fov = GameConfig.CAM_FOV
	_cam.near = 0.08
	_cam.far = 800.0
	_pivot.add_child(_cam)
	## 先于单位写入瞄准方向，单位同一物理帧就能沿准星走。
	process_physics_priority = 20
	_build_pilot_overlay()

## 暂停恢复：把转场截止时刻后移（见 `match_pause.gd#shift_deadlines()`）—— 否则"暂停期间本该跑完"的
## 开赛 / 全景过渡会在恢复那一帧**瞬间到位**（观感像跳帧）。
func shift_deadlines(delta_ms: int) -> void:
	if delta_ms <= 0:
		return
	if _blend_until_ms > 0:
		_blend_until_ms += delta_ms


func setup(p_arena: Node3D) -> void:
	arena = p_arena
	if arena != null and arena.has_signal("match_ended"):
		arena.match_ended.connect(_on_match_ended)
	_apply_overview_pose()

## 屏幕射线要用**当前那台相机**（沙盒模式的"点地面摆兵 / 点兵收兵"）。
## ⚠️ 别让调用方自己去 `get_viewport().get_camera_3d()` 猜：场地里另有一台兜底的
## `SpectatorCamera`（`arena.gd#_build_environment()`），"哪台是 current"的唯一出处是本节点。
func camera() -> Camera3D:
	return _cam

# ---------------------------------------------------------------- 模式切换
func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	var previous := mode
	mode = new_mode
	## 退出全景（bug 3，2026-09-18）：**平滑回到进入全景时记下的机位**，不瞬移。
	## 这条路不走下面的通用分支——位置交给过渡负责，`FLY` 的"原地接管"在这儿不适用。
	if previous == Mode.OVERVIEW:
		if _overview_keeps_pose:
			_apply_mouse_mode()
			return
		_start_camera_blend(_overview_return_pos, _overview_return_yaw, _overview_return_pitch,
			GameConfig.CAM_FIGHT_BLEND_MS)
		## 2026-09-19 修 bug：这段是**回程**——中途被打断时不许"停在半路"，见 `_cancel_camera_blend()`。
		_blend_returning_overview = true
		_apply_mouse_mode()
		return
	_cancel_camera_blend()
	match mode:
		Mode.OVERVIEW:
			_follow_team = -1
			_follow_index = -1
			_overview_click_armed = false
			## 战斗定格：自由视角只藏界面，镜头停在玩家刚才飞到的地方。
			if not _overview_keeps_pose:
				## bug 2（2026-09-18）：先把**当前机位**记成"回来的落点"，再**平滑飞**到全景机位。
				## 以前这里直接 `_apply_overview_pose()`（硬摆位），观感就是"一按全景，镜头瞬间
				## 跳到战场上方几十米外"——现在是 `CAM_FIGHT_BLEND_MS` 内从当前位置飞过去。
				_overview_return_pos = _pos
				_overview_return_yaw = _yaw
				_overview_return_pitch = _pitch
				var overview_pitch: float = GameConfig.CAM_OVERVIEW_PITCH
				_start_camera_blend(GameConfig.CAM_OVERVIEW_FOCUS + _offset_for(0.0, overview_pitch,
						GameConfig.CAM_OVERVIEW_DISTANCE), 0.0, overview_pitch, GameConfig.CAM_FIGHT_BLEND_MS)
		Mode.FLY:
			if previous == Mode.FOLLOW:
				# 从跟随切到飞行：原地接管（不跳视角），只把朝向留给玩家继续调
				_pos = _cam.global_position
		Mode.FOLLOW:
			pass
	_apply_mouse_mode()

## 任务 8（2026-09-18）：**正在看比赛时隐藏鼠标**（全景 / 开赛之后，锁在窗口内），
## 避免光标飘到屏幕外；只要玩家需要点界面（押注、结算、结束浮层）就必须显形。
##
## bug 3（2026-09-18）：**按住 Alt 临时唤出光标**，此时鼠标也不改朝向。
## 本函数每帧被 `_process` 调一次，所以 Alt 的按下与松开都会立刻反映。
func _apply_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_CAPTURED if _want_mouse_hidden() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

## 想不想藏光标：看比赛时藏（全景 / 开赛之后）；按着 Alt 时一律放出来。
func _want_mouse_hidden() -> bool:
	if _alt_hold():
		return false
	return mode == Mode.OVERVIEW or _fight_started

## bug 1（2026-09-18）：鼠标**只在光标被锁住时**驱动镜头——也就是"正在看比赛"的战斗阶段与全景。
## 押注阶段光标必须可见，那时鼠标不动镜头；按住 Alt 唤出光标时同样不动。
func _mouse_look_active() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _alt_hold()

## bug 3（2026-09-18）：按住 Alt = 临时唤出光标。
## 以"轮询 + 事件兜底"两条路判断：Alt 在部分平台只以修饰键形式出现，单靠事件会漏。
func _alt_hold() -> bool:
	return Input.is_key_pressed(KEY_ALT) or _alt_down

func on_betting_phase() -> void:
	## 任务 4（2026-09-18）：押注阶段**不再自动摇摆**，而是停在一个固定观赛机位，
	## 玩家可以用 WASD 自由飞去看局势；鼠标**不再改变朝向**（见 `_unhandled_input`）。
	## 全景模式（`Mode.OVERVIEW`）现在是单独的"看全景"状态，由按钮 / Tab 进入。
	##
	## 每轮开局是**硬切**到这个固定机位（`_apply_overview_pose()` 会顺带取消任何在跑的过渡）——
	## 换轮本来就是一次场景重置，这里不需要平滑（进出全景才需要，见 `set_mode`）。
	_enter_deploy_state()
	_fly_mult = 1.0                 ## 竞猜押注 / 沙盒布兵：用全局那档飞行速度（肉鸽另有一档，见字段处说明）
	_apply_deploy_pose()


## 竞猜押注和沙盒布兵同一套默认机位。自由视角飞去的落点仍是全景俯角。
func on_quiz_phase() -> void:
	_enter_deploy_state()
	_fly_mult = 1.0
	_apply_deploy_pose()


func _apply_deploy_pose() -> void:
	_apply_pose(GameConfig.CAM_OVERVIEW_FOCUS, 0.0, GameConfig.CAM_QUIZ_PITCH,
			GameConfig.CAM_OVERVIEW_DISTANCE)

## **肉鸽的部署机位**（2026-09-26 第四块，用户："修改肉鸽模式默认视角，方便操作与分清敌我关系"）。
## ⚠️ 与下注阶段**共用全部状态**（FLY 自由飞 + 准滚轮推拉 + 显示光标），**只换姿态**：
## 镜头退到己方（西）后方偏南 ⇒ 屏幕左下 = 我方、右上 = 敌方（三个数见 `CAM_ROGUELIKE_*`）。
## ⚠️ 沙盒的布兵阶段**仍走 `on_betting_phase()`**（用户只点了肉鸽）—— 两个模式的默认视角自此**不同**，
## 这是刻意的，不是漏改。
func on_roguelike_phase() -> void:
	_enter_deploy_state()
	_fly_mult = GameConfig.CAM_FLY_SPEED_ROGUELIKE_MULT   ## 仅肉鸽：镜头移动速度 ×2（用户 2026-09-27）
	## ⚠️ 焦点 / 距离 / 姿态全部走 `GameConfig.CAM_ROGUELIKE_*` 的比例（写死的绝对值会把场地切掉一半；
	## 比例值 = 当年在 50 m 半宽下扫出来的最优解除以 50 ⇒ 大小场地构图等比）。
	## ⚠️ **第七块第三次重扫**（场地 150 × 111.5，含南北两条布阵带）：构图按用户给的参考图 ——
	## **镜头退到西南方往东北俯看**（世界 +X = 画面右上、−Z 北 = 画面左上）、场地铺满画面。
	## ⚠️ 沿革：第四块首次给出肉鸽自己的部署机位（西偏南斜看）；第六块按"场地放大"重扫过一次；
	## 第七块场地位置与尺寸都改了 ⇒ 第三次重扫（前两版的参数都已作废）。
	var half: float = arena.half_x if arena != null else GameConfig.ARENA_HALF_X
	var half_z: float = arena.half_z if arena != null else GameConfig.ARENA_HALF_Z
	_apply_pose(Vector3(GameConfig.CAM_ROGUELIKE_FOCUS_RATIO * half, 0.4,
			GameConfig.CAM_ROGUELIKE_FOCUS_Z_RATIO * half_z),
			GameConfig.CAM_ROGUELIKE_YAW, GameConfig.CAM_ROGUELIKE_PITCH,
			GameConfig.CAM_ROGUELIKE_DISTANCE_RATIO * half)

## 下注 / 布兵 / 肉鸽准备这三个"玩家要操作"的相位共用的状态位（硬切机位之前先摆好它）。
## ⚠️ 抽出来是因为 `on_betting_phase()` 与 `on_roguelike_phase()` **只差姿态**，
## 各写一份必然会漂移（滚轮准用 / 光标显形两件事最容易被漏掉一处）。
func _enter_deploy_state() -> void:
	close_pilot_gate()
	_fight_started = false
	_zoom_allowed = true            ## 押注 / 布兵 / 肉鸽准备阶段才准滚轮推拉（见字段处的说明）
	set_mode(Mode.FLY)
	_overview_keeps_pose = false
	_apply_mouse_mode()

func on_fight_phase() -> void:
	_overview_keeps_pose = false
	close_pilot_gate()
	## 开赛：从**下注阶段全景机位所在的位置**平滑飞到"两队质心上方偏后"的指挥视角。
	##
	## 历史：优化 4 曾把这里改成硬切（直接摆位），解决了"刚开赛什么都看不清"，
	## 但观感像跳帧。现在**落点不变**，只把过程改成 `CAM_FIGHT_BLEND_MS` 的 smoothstep 过渡——
	## 两端速度为零，所以起手不"窜"、收尾不"顿"，与下注阶段无缝衔接。
	_follow_team = -1
	_follow_index = -1
	_fight_started = true           ## 任务 8：开赛之后鼠标一直隐藏
	_zoom_allowed = false           ## 开赛即收回滚轮推拉（用户口径：只给押注 / 布兵阶段）
	set_mode(Mode.FLY)
	## ⚠️ 必须显式补一次：任务 4 之后押注阶段本身就是 FLY，`set_mode(FLY)` 会因"模式没变"
	## 提前返回，末尾的 `_apply_mouse_mode()` 不会执行，鼠标就不会隐藏（同 `on_betting_phase`）。
	_apply_mouse_mode()
	## 任务 4 之后押注阶段的机位本身就是 FLY，所以这里**一律走过渡**（不再区分是否来自全景），
	## "开赛瞬间无缝衔接"对下注机位同样成立。
	## 起点由 `_start_camera_blend()` 现取 `_pos`——若此刻正在全景（或正在退出全景的过渡里），
	## 起点就是镜头**当前所在**的位置，于是"从全景直接开赛"也不会跳。
	_start_camera_blend(_fight_pose_origin() + Vector3(0.0, GameConfig.CAM_FIGHT_HEIGHT, GameConfig.CAM_FIGHT_BACK),
		0.0, GameConfig.CAM_FIGHT_PITCH, GameConfig.CAM_FIGHT_BLEND_MS)

## bug 2（2026-09-18）：**一轮打完就放出光标**——结算浮层的「下一轮」得能点。
## 只放开光标、不动机位：结果浮层期间玩家仍能自由看战场。
## （若此刻正在全景模式，光标仍隐藏——因为整个 HUD 也隐藏着；点一下鼠标左/右键出来即可。）
func on_round_result() -> void:
	close_pilot_gate()
	_fight_started = false
	_zoom_allowed = false           ## 结算浮层也不再推拉（只有"等玩家决策"的那两段才给）
	_apply_mouse_mode()


## 战斗定格之后：镜头继续能移动、转向，Tab 仍进自由视角。不改当前机位。
func hold_battle_view() -> void:
	close_pilot_gate()
	_overview_keeps_pose = true
	_fight_started = true
	_zoom_allowed = false
	if mode == Mode.FOLLOW:
		set_mode(Mode.FLY)
	_apply_mouse_mode()


## 放开鼠标转向，但不挪机位。选择界面从隐藏恢复时用，滚轮推拉一并交还准备阶段。
func release_look() -> void:
	_fight_started = false
	_zoom_allowed = true
	_apply_mouse_mode()

## 相机过渡：smoothstep 插值位置与朝向，两端速度为零。
## 2026-09-18 起**三条路共用**这一套字段：开赛落位、进入全景、退出全景——
## 后一次 `_start_camera_blend()` 会直接接管前一次（起点现取当前 `_pos`），所以过渡不会打架。
func _update_camera_blend() -> void:
	var now := Time.get_ticks_msec()
	if now >= _blend_until_ms:
		_blend_until_ms = 0
		_blend_returning_overview = false
		_pos = _blend_to_pos
		_yaw = _blend_to_yaw
		_pitch = _blend_to_pitch
		return
	var t := 1.0 - float(_blend_until_ms - now) / float(_blend_total_ms)
	var ease := t * t * (3.0 - 2.0 * t)
	_pos = _blend_from_pos.lerp(_blend_to_pos, ease)
	_yaw = lerp_angle(_blend_from_yaw, _blend_to_yaw, ease)
	_pitch = lerpf(_blend_from_pitch, _blend_to_pitch, ease)

## 起一段"平滑送到目标机位"的过渡。**起点是调用瞬间的 `_pos` / `_yaw` / `_pitch`**，
## 所以调用前不要先改这三样（例如 `set_mode` 里的分支就刻意不动它们）。
func _start_camera_blend(to_pos: Vector3, to_yaw: float, to_pitch: float, duration_ms: int) -> void:
	_blend_from_pos = _pos
	_blend_from_yaw = _yaw
	_blend_from_pitch = _pitch
	_blend_to_pos = to_pos
	_blend_to_yaw = to_yaw
	_blend_to_pitch = to_pitch
	_blend_total_ms = maxi(duration_ms, 1)
	_blend_until_ms = Time.get_ticks_msec() + _blend_total_ms
	## 新过渡默认"打断就作废"（开赛落位 / 进自由视角都是这个语义）；
	## 只有"退出自由视角的回程"会在调用之后把它置回 true（见 `set_mode`）。
	_blend_returning_overview = false
	_velocity = Vector3.ZERO

## 玩家一接管就中断过渡：过渡只负责"把镜头送过去"，绝不抢操作。
## ⚠️ 2026-09-19 修 bug：被中断的若是**退出自由视角的回程**，先把镜头**落到回程终点**再取消 ——
## 否则"按住 WASD 的同时退出"会让回程在第一帧就被打断，镜头停在全景俯瞰位上回不来
##（用户报告的原话："无法回到正常机位"）。落点之后 `FLY` 原地接管，玩家的 WASD 照常生效。
func _cancel_camera_blend() -> void:
	if _blend_returning_overview:
		_pos = _blend_to_pos
		_yaw = _blend_to_yaw
		_pitch = _blend_to_pitch
		_blend_returning_overview = false
	_blend_until_ms = 0

## 开战机位的瞄准点：优先取两队存活单位的质心，拿不到就用场地中心
func _fight_pose_origin() -> Vector3:
	if arena != null and arena.has_method("battle_center"):
		return arena.battle_center()
	return Vector3.ZERO

func toggle_overview() -> void:
	set_mode(Mode.FLY if mode == Mode.OVERVIEW else Mode.OVERVIEW)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

## 机位偏移向量：从焦点出发，按 yaw / pitch 转到 `distance` 之外。
## ⚠️ 2026-09-26 起**距离也走参数**（原来是写死 `CAM_OVERVIEW_DISTANCE`）——
## 肉鸽的部署机位与全景机位用的是**同一个式子、不同的三个数**（见 `_apply_pose()`）。
func _offset_for(yaw: float, pitch: float, distance: float) -> Vector3:
	return Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * distance

## 直接摆到一个"固定部署机位"。**硬切**，只用于每轮开局的复位与 `setup()`；
## 进出全景模式走 `_start_camera_blend()`。
## 顺带取消任何在跑的过渡 —— 这是一次"立刻到位"的摆位，不该再被旧过渡拉走。
func _apply_pose(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	_cancel_camera_blend()
	_yaw = yaw
	_pitch = pitch
	_pos = focus + _offset_for(yaw, pitch, distance)
	_velocity = Vector3.ZERO
	_zoom_target = _pos            ## 硬摆位：推拉目标一并对齐（否则会被缓动拽回上一个目标）

## 下注 / 沙盒布兵阶段的机位 = 全景机位（`CAM_OVERVIEW_*`）
func _apply_overview_pose() -> void:
	_apply_pose(GameConfig.CAM_OVERVIEW_FOCUS, 0.0, GameConfig.CAM_OVERVIEW_PITCH,
			GameConfig.CAM_OVERVIEW_DISTANCE)

# ---------------------------------------------------------------- 每帧更新
func _process(delta: float) -> void:
	if _cam == null:
		return
	## bug 1（2026-09-18）：全景下**左键或右键**退出，回到正常下注界面（无需按住 Alt）。
	## 用轮询而不是鼠标事件：① 全景期间整个 HUD 是隐藏的，不存在"和界面抢点击"的问题；
	## ② 进入全景那一下（点「全景」按钮 / 按 `Tab`）手上可能还按着键钮，所以要等按键全部松开
	## 才"上膛"，避免刚进全景就被自己那一下点出去。
	if mode == Mode.OVERVIEW:
		var button_down := (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		if not _overview_click_armed:
			if not button_down:
				_overview_click_armed = true
		elif button_down:
			set_mode(Mode.FLY)
	if _pilot_unit != null and _pilot_current() == null:
		exit_pilot()
	_refresh_pilot_halo()
	if _pilot_current() != null:
		_place_pilot_camera()
	elif _blend_until_ms > 0:
		_update_camera_blend()
	_refresh_pilot_ui()
	## 2026-09-18「自由视角」改造：全景**不再自动环绕**——它现在与战斗镜头是**同一种**镜头
	##（自由飞行 + 鼠标转向），所以这里不再每帧重算 `_yaw` / `_pos` 去追焦点，
	## 镜头怎么动完全交给 `_physics_process`（WASD）与鼠标。
	## 进出全景的平滑过渡、以及 FOLLOW 的跟随逻辑都不受影响。
	if _pilot_current() == null and mode == Mode.FOLLOW:
		var unit := _follow_unit()
		if unit == null:
			set_mode(Mode.FLY)
		else:
			var back := Vector3(sin(_yaw), 0.0, cos(_yaw)) * GameConfig.CAM_FOLLOW_DISTANCE
			var want: Vector3 = unit.global_position + Vector3(0.0, GameConfig.CAM_FOLLOW_HEIGHT, 0.0) + back
			_pos = _pos.lerp(want, clampf(delta * GameConfig.CAM_FOLLOW_LAG, 0.0, 1.0))
			_zoom_target = _pos          ## 跟随时以跟随为准，别让没走完的推拉把镜头往回拽

	## 滚轮推拉：**只有这里**把 `_pos` 朝 `_zoom_target` 缓动过去（滚轮本身不动 `_pos`）。
	## ⚠️ 正在跑过渡时以过渡为准（把目标摁回当前机位）：否则两边同时写 `_pos`，镜头会互相拽。
	if _blend_until_ms > 0:
		_zoom_target = _pos
	else:
		_tick_zoom(delta)

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - GameConfig.CAM_SHAKE_DECAY * delta)

	var jitter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	_pivot.global_position = _pos + jitter
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	## bug 3：每帧核对一次光标显隐，Alt 的按下/松开才会立刻生效（写入前会先比对，不会白写）
	_apply_mouse_mode()

func _physics_process(delta: float) -> void:
	var pilot := _pilot_current()
	if pilot != null:
		pilot.pilot_aim = _pilot_aim_direction(pilot)
		return
	## 2026-09-18「自由视角」：全景与自由飞行**共用同一套移动**（WASD / QE / Shift），
	## 所以这条闸门放行两种模式；FOLLOW 仍由 `_process` 的跟随逻辑接管。
	if mode != Mode.FLY and mode != Mode.OVERVIEW:
		return
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("cam_forward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("cam_back"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("cam_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("cam_right"):
		input_dir.x += 1.0
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
	var vertical := 0.0
	if Input.is_action_pressed("cam_up"):
		vertical += 1.0
	if Input.is_action_pressed("cam_down"):
		vertical -= 1.0

	# WASD 控制镜头的**空间位置**，参考系是**镜头朝向**（优化 1）：
	#   W → 朝镜头看的方向前进、S → 后退、A → 镜头左方、D → 镜头右方。
	# 符号推导（yaw=0 时 pivot 朝向 -Z）：
	#   视线方向（水平）= -Z   → forward = -(sin(yaw), 0, cos(yaw))
	#   镜头右方        = +X   → right   =  (cos(yaw), 0, -sin(yaw))
	# ⚠️ 修 bug：早期版本这两个向量都取错了符号（写成了"镜头背后 / 镜头左方"），
	#    导致 W/S/A/D 四向全反（实测 dot(forward, 视线) = −1.000）。
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var speed := GameConfig.CAM_FLY_SPEED * _fly_mult * (GameConfig.CAM_FLY_BOOST_MULT if Input.is_action_pressed("cam_boost") else 1.0)
	# 玩家一动方向键就中断过渡（过渡不抢操作）
	if input_dir.length_squared() > 0.0 or not is_zero_approx(vertical):
		_cancel_camera_blend()
	var want := (right * input_dir.x + forward * input_dir.y + Vector3.UP * vertical) * speed
	_velocity = _velocity.lerp(want, clampf(delta * GameConfig.CAM_FLY_SMOOTH, 0.0, 1.0))
	_pos += _velocity * delta
	## ⚠️ 滚轮的目标机位**跟着一起平移**：否则"先滚一格、立刻按 W"时，那一格没走完的推拉
	## 会把镜头往回拽（两者都在写同一个目标，必须同进同退）。
	_zoom_target += _velocity * delta

# ---------------------------------------------------------------- 滚轮推拉
## 滚轮沿**完整视线方向**推拉机位（2026-09-25 用户："在竞猜模式的押注阶段和沙盒模式的布兵阶段可以通过滚轮
## 来拉近拉远镜头"，并明确了它与 W 的分工："w 只能沿镜头方向**水平**移动，而滚轮能够**同时在水平和竖直
## 方向上**移动"）。
##
## ⚠️ **为什么走 `_input()` 而不是 `_unhandled_input()`**：押注 / 布兵阶段屏幕底部有面板（下注面板 /
## 兵种栏），光标压在上面时那一手滚轮会被 Control（默认 `MOUSE_FILTER_STOP`）**吃掉**、根本到不了
## `_unhandled_input`。`_input()` 比界面处理更早 ⇒ **光标在哪都能推拉**。本项目没有任何要用滚轮的界面
##（没有 `ScrollContainer` 之类），所以不存在"抢滚轮"的一方。
## ⚠️ **暂停时不会误触发**：本节点是默认可暂停的（`PROCESS_MODE_INHERIT`），树一暂停就收不到 `_input`
##（与调试探针在冻结模式下收不到事件是同一个机制）⇒ 暂停菜单开着时滚轮不动镜头。
func _input(event: InputEvent) -> void:
	if not _zoom_allowed:
		return
	## 沙盒兵种栏自己要用滚轮翻卡。这一手比界面更早，不在这里让开的话，
	## 光标压在栏上也会推镜头（栏里的 `set_input_as_handled()` 拦不住 `_input`）。
	if _mouse_over_palette():
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(1.0)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(-1.0)

## 光标是否压在沙盒兵种栏上。栏把自己放进 `palette_wheel`，矩形盖住卡片和空白。
func _mouse_over_palette() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var mouse := vp.get_mouse_position()
	for node in get_tree().get_nodes_in_group("palette_wheel"):
		var control := node as Control
		if control != null and control.visible and control.get_global_rect().has_point(mouse):
			return true
	return false

## 推拉一格：`notches` > 0 = 朝视线方向前进 = **拉近**。
## ⚠️ 它只改 **`_zoom_target`**（目标机位），**不直接动 `_pos`** —— 真正的位移由 `_tick_zoom()`
## 每帧缓动完成（用户 2026-09-25："滚轮移动镜头时应该顺滑点，过渡应光滑"）。
## ⚠️ 连续滚动的多格**叠在目标上**（不是在"还没走完的当前位置"上）：滚快一点就该推得远一点，
## 而指数缓动永远不会"冲过头"，所以两者不冲突。
func _apply_zoom(notches: float) -> void:
	if _cam == null:
		return
	var focus: Vector3 = GameConfig.CAM_OVERVIEW_FOCUS
	var dist := _zoom_target.distance_to(focus)
	var step := clampf(dist * GameConfig.CAM_ZOOM_STEP_RATIO,
		GameConfig.CAM_ZOOM_STEP_MIN, GameConfig.CAM_ZOOM_STEP_MAX)
	var candidate := _zoom_target + _look_direction() * (step * notches)
	## 俯视拉近到底会一路扎向地面（视线含俯仰分量）⇒ 高度夹一道下限，别钻到地板下面。
	## 夹住之后仍会**贴着地面继续靠近**（这正是"掠地靠过去看"的手感），
	## 所以还需要下面那道"最近距离"界来收尾。
	candidate.y = maxf(candidate.y, GameConfig.CAM_ZOOM_MIN_HEIGHT)
	## 最近距离：推到焦点跟前就停（不然会穿过场地飞到对面去，见 `GameConfig.CAM_ZOOM_MIN_DISTANCE`）。
	## ⚠️ 只在"这一步把镜头推得**更近**"时才丢：玩家若先用 WASD 飞进了内圈，滚轮仍要能把他推出来。
	var new_dist := candidate.distance_to(focus)
	if new_dist < dist and new_dist < GameConfig.CAM_ZOOM_MIN_DISTANCE:
		return
	_cancel_camera_blend()          ## 与 WASD / 鼠标同级：玩家一接管就中断正在跑的过渡
	_zoom_target = candidate

## 每帧把 `_pos` 朝 `_zoom_target` 缓动一格（指数缓动，与帧率无关）。
## 差得足够小就**直接对齐**（不再无限逼近）——`is_equal_approx` 的阈值远小于一个像素。
func _tick_zoom(delta: float) -> void:
	if _pos.is_equal_approx(_zoom_target):
		_pos = _zoom_target
		return
	_pos = _pos.lerp(_zoom_target, 1.0 - exp(-GameConfig.CAM_ZOOM_SMOOTH * delta))

## **完整**视线方向（含俯仰分量，单位向量）。
## ⚠️ 与 `_physics_process()` 里那个 `forward` **不是同一支**：那一支的 y 恒为 0（WASD 只走水平面），
## 这一支才带俯仰 —— 这个分工是用户明确定下的（见 `GameConfig.CAM_ZOOM_*` 处的注释）。
## 符号与 `_physics_process` 的 `forward` / `right` 同一套约定（`_pivot.rotation = (pitch, yaw, 0)`）：
## 俯角为负（俯视）时 y 分量为负 ⇒ 越推越低，正是"俯冲过去看"。
func _look_direction() -> Vector3:
	var horizontal := cos(_pitch)
	return Vector3(-sin(_yaw) * horizontal, sin(_pitch), -cos(_yaw) * horizontal)

## 越肩时镜头在身体右后方，视线和兵的朝向是两条平行线，准星会偏到兵的一侧。
## 改成瞄准「镜头正中这条射线打到的点」，兵的出手就穿过准星。
func _pilot_aim_direction(unit: Unit3D) -> Vector3:
	var look := _look_direction()
	if look.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	look = look.normalized()
	if not _pilot_shoulder:
		return look
	_place_pilot_camera()
	var aim_point := _pos + look * 400.0
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(_pos, aim_point)
		query.collision_mask = 0b111
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [unit.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			aim_point = hit.position
	var from := unit.global_position + Vector3(0.0, 1.25, 0.0)
	var dir := aim_point - from
	if dir.length_squared() < 0.0001:
		return look
	return dir.normalized()

# ---------------------------------------------------------------- 输入
## 任务 4（2026-09-18）：**押注阶段鼠标不改朝向**——那一阶段光标必须可见（要能点按钮），
## 可见光标 + 转向 = 点按钮时视角乱转。左键点选选手也一并取消（那时光标正好是隐藏的，无从点选）。
## bug 1（2026-09-18）：**战斗阶段与全景模式下鼠标重新可以转向**——这两种状态下光标是隐藏的，
## 隐藏的代价正是"可以随便动鼠标而不会飘出屏幕"（见 `_mouse_look_active()`）。
## 任务 6.5 / bug 1：全景模式下 HUD 整个是隐藏的，进出靠**鼠标左键 / 右键**
## （2026-09-18 起**不再**"按任意键退出"：退出判定只留鼠标左右键，见 `_process` 的轮询）。
## bug 1（本轮）：退出全景改由**左键 / 右键**触发（不需要 Alt）；全景里的转向现在与战斗阶段
## 完全同一条路径（2026-09-18「自由视角」改造后不再有"偏置叠加在摆动上"的特例）。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _mouse_look_active():
			return
		var motion := event as InputEventMouseMotion
		## 2026-09-18「自由视角」：全景与战斗阶段现在是**同一种**镜头，转向路径合一
		##（全景不再需要"偏置叠加在自动摆动上"那套特例）。与 WASD 一样，一动就中断过渡。
		_yaw -= motion.relative.x * GameConfig.CAM_MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * GameConfig.CAM_MOUSE_SENSITIVITY,
			GameConfig.CAM_PITCH_MIN, GameConfig.CAM_PITCH_MAX)
		_cancel_camera_blend()
		return
	if event is InputEventMouseButton:
		_try_pilot_click(event)
		## bug 1：全景的"点击退出"走 `_process` 里的轮询（见那里的注释），这里不重复处理。
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ALT:
		_alt_down = (event as InputEventKey).pressed
		return
	if _pilot_current() != null:
		if _pilot_key(event):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("cam_overview") or event.is_action_pressed("cam_reset") \
				or event.is_action_pressed("cam_follow_1") or event.is_action_pressed("cam_follow_2") \
				or event.is_action_pressed("cam_follow_3"):
			get_viewport().set_input_as_handled()
			return
	if mode == Mode.OVERVIEW:
		## 再按一次 Tab 退出自由视角。鼠标左右键的退出仍在 `_process` 里轮询。
		if event.is_action_pressed("cam_overview"):
			toggle_overview()
		return
	if event.is_action_pressed("cam_overview"):
		toggle_overview()
		return
	if event.is_action_pressed("cam_reset"):
		set_mode(Mode.FLY)
		return
	for i in range(1, 4):
		if event.is_action_pressed("cam_follow_%d" % i):
			_follow_slot(i - 1)
			return

func _follow_slot(index: int) -> void:
	if arena == null:
		return
	var list: Array = []
	for team in [0, 1]:
		list.append_array(arena.units_of_team(team))
	if index < 0 or index >= list.size():
		return
	var team_a: int = arena.units_of_team(0).size()
	_follow_team = 0 if index < team_a else 1
	_follow_index = index if _follow_team == 0 else index - team_a
	set_mode(Mode.FOLLOW)

func _follow_unit() -> Unit3D:
	if arena == null or not arena.has_method("units_of_team"):
		return null
	var list: Array = arena.units_of_team(_follow_team)
	if _follow_index < 0 or _follow_index >= list.size():
		return null
	var unit := list[_follow_index] as Unit3D
	if unit == null or not is_instance_valid(unit) or not unit.alive:
		return null
	return unit

## 沙盒传 false（两队都能操作）。生存传 true（只限我方，team 0）。
func open_pilot_gate(own_team_only: bool) -> void:
	_pilot_gate = PilotGate.OWN if own_team_only else PilotGate.ANY

func close_pilot_gate() -> void:
	exit_pilot()
	_pilot_gate = PilotGate.CLOSED

func exit_pilot() -> void:
	var unit := _pilot_unit
	_pilot_unit = null
	_set_hover(null)
	if unit != null and is_instance_valid(unit):
		unit.set_piloted(false)
	if not _pilot_has_return:
		return
	_pilot_has_return = false
	_start_camera_blend(_pilot_return_pos, _pilot_return_yaw, _pilot_return_pitch,
			GameConfig.CAM_FIGHT_BLEND_MS)

func begin_pilot(unit: Unit3D) -> void:
	if not _is_pilotable(unit) or unit == _pilot_unit:
		return
	var switching := _pilot_unit != null
	if switching and is_instance_valid(_pilot_unit):
		_pilot_unit.set_piloted(false)
	else:
		_pilot_return_pos = _pos
		_pilot_return_yaw = _yaw
		_pilot_return_pitch = _pitch
		_pilot_has_return = true
		_pilot_shoulder = false
	_pilot_unit = unit
	unit.set_piloted(true)
	_set_hover(null)
	_cancel_camera_blend()
	if mode != Mode.FLY:
		mode = Mode.FLY
		_follow_team = -1
		_follow_index = -1

func _pilot_current() -> Unit3D:
	var unit := _pilot_unit
	if unit == null or not is_instance_valid(unit) or not unit.alive or unit.is_ember():
		return null
	if _pilot_gate == PilotGate.CLOSED:
		return null
	if _pilot_gate == PilotGate.OWN and unit.team != 0:
		return null
	return unit

func _is_pilotable(unit: Unit3D) -> bool:
	if _pilot_gate == PilotGate.CLOSED or unit == null or not is_instance_valid(unit) or not unit.alive:
		return false
	if unit.is_command_post() or GameConfig.is_no_attack(unit.type_id):
		return false
	## 潜地的沙虫仍可选。影袭、余烬、以及别的钻地状态不能选。
	if unit.is_in_shadow_form() or unit.is_ember():
		return false
	if unit.is_burrowed() and not unit.is_burrower():
		return false
	if _pilot_gate == PilotGate.OWN and unit.team != 0:
		return false
	return true

func _place_pilot_camera() -> void:
	var unit := _pilot_current()
	if unit == null:
		return
	var top := GameConfig.pilot_body_top(unit.type_id)
	var front := GameConfig.pilot_body_front(unit.type_id)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var feet := unit.global_position
	if _pilot_shoulder:
		var cam_y := feet.y + top + GameConfig.CAM_PILOT_SHOULDER_LIFT
		var back := front + GameConfig.CAM_PILOT_SHOULDER_BACK
		_pos = Vector3(feet.x, cam_y, feet.z) - forward * back + right * GameConfig.CAM_PILOT_SHOULDER_RIGHT
	else:
		_pos = feet + Vector3(0.0, top + GameConfig.CAM_PILOT_ABOVE, 0.0) \
				+ forward * (front + GameConfig.CAM_PILOT_AHEAD)
	_zoom_target = _pos
	_velocity = Vector3.ZERO

func _refresh_pilot_halo() -> void:
	var hovered: Unit3D = null
	if _pilot_gate != PilotGate.CLOSED and _fight_started and mode != Mode.OVERVIEW and _alt_hold():
		hovered = _unit_under_cursor()
		if not _is_pilotable(hovered):
			hovered = null
	_set_hover(hovered)

func _set_hover(unit: Unit3D) -> void:
	if _hover_unit == unit:
		return
	if _hover_unit != null and is_instance_valid(_hover_unit):
		_hover_unit.show_pilot_halo(false)
	_hover_unit = unit
	if unit != null:
		unit.show_pilot_halo(true)

func _try_pilot_click(event: InputEvent) -> void:
	if _pilot_gate == PilotGate.CLOSED or not _fight_started or mode == Mode.OVERVIEW:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if _alt_hold():
		var picked := _unit_under_cursor()
		if _is_pilotable(picked):
			begin_pilot(picked)
			get_viewport().set_input_as_handled()
		return
	if _pilot_current() != null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var nearest := _unit_nearest_center()
	if nearest != null:
		begin_pilot(nearest)
		get_viewport().set_input_as_handled()

func _pilot_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	InputBindings.ensure_actions()
	if event.is_action_pressed("pilot_release") or InputBindings.pad_matches(key, "pilot_release"):
		exit_pilot()
		return true
	if event.is_action_pressed("pilot_shoulder") or InputBindings.pad_matches(key, "pilot_shoulder"):
		_pilot_shoulder = not _pilot_shoulder
		return true
	if event.is_action_pressed("pilot_skill") or InputBindings.pad_matches(key, "pilot_skill"):
		var unit := _pilot_current()
		if unit != null:
			unit.pilot_cast_skill(1)
		return true
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_2 or code == KEY_KP_2:
		var second := _pilot_current()
		if second != null:
			second.pilot_cast_skill(2)
		return true
	return false

func _unit_under_cursor() -> Unit3D:
	if _cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 400.0)
	query.collision_mask = 0b111
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	var struck: Unit3D = null if hit.is_empty() else hit.collider as Unit3D
	if _is_pilotable(struck):
		return struck
	## 潜地沙虫关掉了碰撞，射线打在地面上。改用光标附近的屏幕距离补选。
	return _unit_nearest_screen(mouse, GameConfig.CAM_PILOT_PICK_RADIUS_PX)

func _unit_nearest_center() -> Unit3D:
	if _cam == null:
		return null
	return _unit_nearest_screen(get_viewport().get_visible_rect().size * 0.5, -1.0)

func _unit_nearest_screen(screen_pos: Vector2, max_px: float) -> Unit3D:
	if arena == null or _cam == null:
		return null
	var best: Unit3D = null
	var best_distance := INF
	for node in arena.units:
		if not is_instance_valid(node):
			continue
		var unit := node as Unit3D
		if not _is_pilotable(unit):
			continue
		var lift := 0.4 if unit.is_burrowed() else GameConfig.pilot_body_top(unit.type_id) * 0.45
		var point := unit.global_position + Vector3(0.0, lift, 0.0)
		if _cam.is_position_behind(point):
			continue
		var screen := _cam.unproject_position(point)
		var distance := screen.distance_to(screen_pos)
		if max_px >= 0.0 and distance > max_px:
			continue
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best

func _build_pilot_overlay() -> void:
	_pilot_layer = CanvasLayer.new()
	_pilot_layer.name = "PilotLayer"
	_pilot_layer.layer = 4
	_pilot_layer.visible = false
	add_child(_pilot_layer)
	var full := Control.new()
	full.name = "PilotOverlay"
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pilot_layer.add_child(full)
	var cross := Control.new()
	cross.name = "PilotCrosshair"
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -11.0
	cross.offset_top = -11.0
	cross.offset_right = 11.0
	cross.offset_bottom = 11.0
	full.add_child(cross)
	_add_cross_bar(cross, Vector2(0.0, 10.0), Vector2(7.0, 2.0))
	_add_cross_bar(cross, Vector2(15.0, 10.0), Vector2(7.0, 2.0))
	_add_cross_bar(cross, Vector2(10.0, 0.0), Vector2(2.0, 7.0))
	_add_cross_bar(cross, Vector2(10.0, 15.0), Vector2(2.0, 7.0))
	var status := VBoxContainer.new()
	status.name = "PilotStatus"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	status.offset_left = -220.0
	status.offset_right = 220.0
	status.offset_top = 18.0
	status.offset_bottom = 168.0
	full.add_child(status)
	_pilot_hp_label = _pilot_label("PilotHpLabel", 22)
	_pilot_skill_label = _pilot_label("PilotSkillLabel", 20)
	status.add_child(_pilot_hp_label)
	status.add_child(_pilot_skill_label)

func _add_cross_bar(parent: Control, at: Vector2, bar_size: Vector2) -> void:
	var bar := ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color(1.0, 1.0, 1.0, 0.92)
	bar.position = at
	bar.size = bar_size
	parent.add_child(bar)

func _pilot_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	return label

func _refresh_pilot_ui() -> void:
	if _pilot_layer == null:
		return
	var unit := _pilot_current()
	_pilot_layer.visible = unit != null
	if unit == null:
		return
	_pilot_hp_label.text = "血量  %d / %d" % [int(round(unit.hp)), int(round(unit.max_hp))]
	var skill_line := unit.pilot_skill_line()
	_pilot_skill_label.text = skill_line
	_pilot_skill_label.visible = skill_line != ""

func _on_match_ended(_result: Dictionary) -> void:
	shake(0.25)

func _mcp_state() -> Dictionary:
	return {
		"mode": ["overview", "fly", "follow"][mode],
		"pos": {"x": snappedf(_pos.x, 0.01), "y": snappedf(_pos.y, 0.01), "z": snappedf(_pos.z, 0.01)},
		"yaw": snappedf(_yaw, 0.001),
		"pitch": snappedf(_pitch, 0.001),
		"blending": _blend_until_ms > 0,
		"mouse_hidden": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"mouse_look": _mouse_look_active(),
		"alt_hold": _alt_hold(),
		"piloting": _pilot_current() != null,
		"pilot_shoulder": _pilot_shoulder,
	}
