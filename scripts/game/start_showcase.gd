class_name StartShowcase
extends Node3D
## 开始界面的**背景演示**：一场"打到一半被冻住"的固定阵容战斗，镜头绕着它慢慢转。
##
## 依据：`05_ui_hud.md#1`（界面是补充不是主体）+ `07_file_layout.md#5`（依赖方向：game 层可以往下用
## unit / unit_factory，反过来不行）。本文件属**表现层**，只读 `GameConfig` 与 `Unit3D` 的公开成员，
## 不写任何玩法数据（R-07）。
##
## 与真场地**完全隔离**：自己的地板 / 天空 / 灯光 / 相机 / 站位，**一个 `Arena` 都不建**。
## 唯一连带效果：远程单位因此拿不到 `_arena()`（`unit3d.gd#_arena()` 按 `has_method("spawn_arrow")` 找场地），
## 它们只会做拉弓动作、**不发射箭矢** —— 对一张静止的背景图来说正合适（见 `02_entities.md#2.2`）。
##
## 开场流程（三段）：
##   ① 建好灰色世界与固定阵容，让这场架**真打起来**（预演，此时屏幕上还盖着开场渐亮的黑幕）；
##   ② 等到"真的有人挨了一下"（hp 掉过）就**整棵战斗子树冻住**（`process_mode = DISABLED`）
##      ⇒ 之后画面完全静止、不再推进任何玩法状态，只有相机继续转；
##   ③ emit `roll_finished`，开始界面据此起"渐亮"。
## ⚠️ 冻住的是 `Battle` 子树（单位 / 地板 / 灯光在内都无所谓），**相机不在里面**，所以它照样转。
## ⚠️ 整棵节点在进入下注阶段时由 `main.gd` 释放；在那之前它是场上唯一有 `units` 组成员的东西 ——
## 所以**必须先释放它、再建真比赛**，否则真单位的索敌会把这张背景图里的兵当成敌人。

signal roll_finished      ## 预演跑完、战斗子树已冻住（开始界面据此起渐亮）

# ---------------------------------------------------------------- 表现参数
# 全部是**纯表现**、不参与任何玩法判定，按 `08_naming.md#3.3` 的既有惯例住在脚本里（同 `arrow.gd`
# 的 `SHIELD_STICK_INSET`、`unit3d.gd` 的 `FLAME_FX_*`）：它们不属于 `GameConfig` 的"可调玩法数值"。
const FLOOR_COLOR := Color(0.52, 0.53, 0.55)     ## 灰地板（用户："灰色地板"）
const SKY_COLOR := Color(0.24, 0.25, 0.28)       ## 灰天空（用户："天空比地板暗" ⇒ 明度必须低于地板）
const FLOOR_SIZE := Vector3(64.0, 1.0, 44.0)     ## 地板盒体尺寸 m（够大 ⇒ 谁都掉不下去）
const SUN_COLOR := Color(0.92, 0.93, 0.96)       ## 冷白日光（灰色调下不要暖黄）
const SUN_ENERGY := 1.45
const SUN_ANGLE_DEG := Vector3(-48.0, -32.0, 0.0)
const AMBIENT_COLOR := Color(0.62, 0.65, 0.70)
const AMBIENT_ENERGY := 1.35

## 预演时长（ms）：至少要让它走到"接敌 + 挥出第一刀"（`PREROLL_MIN_MS`），
## 但最多等 `PREROLL_MAX_MS` —— 到点就算还没人挨打也照冻（免得后台一直跑着两个 AI 队）。
const PREROLL_MIN_MS := 900
const PREROLL_MAX_MS := 2200
## 战斗子树的冻结时刻按"第一次挨打"对齐：命中那一帧正好是**挥砍动画的顶点** ⇒ 冻住的姿势最好看。
## 判据只用公开成员 `hp` / `max_hp`（不碰 `Unit3D` 的私有状态机）。

## 环绕镜头（用户："镜头绕着正在战斗的兵种转"）：绕原点、半径/高度固定、匀速。
const ORBIT_RADIUS := 9.5
const ORBIT_HEIGHT := 3.4
const ORBIT_DEG_PER_SEC := 9.0        ## 一圈 40 s：慢到看不出"在转"，又一直在动
const ORBIT_START_DEG := 24.0
const LOOK_HEIGHT := 1.1              ## 视线焦点高度 m（大概在单位胸口）
## 按下「开始游戏」之后**背景向中心放大**（用户："同时背景会向着中心放大"）。做法是演示相机在渐黑期间
## **向中心推近**（dolly-in）：画面里的兵越来越大、像被吸进中心。冻结只停战斗子树，推镜头是另一回事，互不影响。
## ⚠️ 时长与开始界面的 `FADE_OUT_MS`（620 ms）对齐 ⇒ **黑透那一刻刚好推到位**，渐亮时已经是新比赛。
const ZOOM_MS := 620
const ZOOM_RADIUS_END := 5.2          ## 推近终点半径 m（起点 = `ORBIT_RADIUS`）
const ZOOM_HEIGHT_END := 2.1          ## 推近终点高度 m（起点 = `ORBIT_HEIGHT`）

## 固定代表性阵容（用户："兵种们正在打架（静止）"）。
## ⚠️ 刻意**只挑没有技能的兵种**（剑盾 / 长矛 / 短弓 / 长弓 / 扇子）：有技能的那几个会在预演里
## 立刻放技能 —— 骑士冲撞 / 狂战士跳跃 / 火焰拳炎爆会把人打散、轻骑兵冲刺会以 14 m/s 冲出画面，
## 冻结时就不是"两队在打架"而是一地散兵了。
const LINEUP_A := ["sword", "spear", "shortbow", "fan"]        ## 0 队（西侧，面朝 +X）
const LINEUP_B := ["sword", "spear", "longbow", "fan"]         ## 1 队（东侧，面朝 -X）
const RANK_X := 2.6                   ## 每队离中线的横向距离 m（两队相距 2 × 2.6 = 5.2 m）
const RANK_GAP_Z := 2.2               ## 同队相邻两人的横向间距 m

# ---------------------------------------------------------------- 成员
var _battle: Node3D = null
var _pivot: Node3D = null
var _cam: Camera3D = null
var _units: Array[Unit3D] = []
var _spawn_ms: int = 0
var _frozen: bool = false
var _zooming: bool = false
var _zoom_from_ms: int = 0

func _ready() -> void:
	_build_floor()
	_build_sky()
	_build_sun()
	_battle = Node3D.new()
	_battle.name = "Battle"
	add_child(_battle)
	_spawn_lineup(LINEUP_A, 0)
	_spawn_lineup(LINEUP_B, 1)
	_build_camera()
	_spawn_ms = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	## 轨道角按**绝对时刻**算（不变量 I-13：不累加 delta），所以掉帧也不会改变转速。
	var elapsed_ms := Time.get_ticks_msec() - _spawn_ms
	_pivot.rotation_degrees = Vector3(0.0, ORBIT_START_DEG + ORBIT_DEG_PER_SEC * float(elapsed_ms) / 1000.0, 0.0)
	if _zooming:
		_tick_zoom()
	if _frozen:
		return
	if _roll_ready(elapsed_ms):
		_freeze()

## 按下「开始游戏」那一刻由 `main.gd` 调用：相机开始向中心推近（在渐黑期间完成）。
func begin_zoom() -> void:
	if _zooming:
		return
	_zooming = true
	_zoom_from_ms = Time.get_ticks_msec()

## 推近：半径与高度一起按 smoothstep 收到终点值（两端速度为零 ⇒ 起手不窜、收尾不顿）。
## 相机始终挂在 pivot 下 ⇒ **推近的同时照旧绕圈**，观感是"一边被吸向中心、一边还在转"。
func _tick_zoom() -> void:
	var t := clampf(float(Time.get_ticks_msec() - _zoom_from_ms) / float(ZOOM_MS), 0.0, 1.0)
	var k := smoothstep(0.0, 1.0, t)
	var radius := lerpf(ORBIT_RADIUS, ZOOM_RADIUS_END, k)
	var height := lerpf(ORBIT_HEIGHT, ZOOM_HEIGHT_END, k)
	_cam.position = Vector3(0.0, height - LOOK_HEIGHT, radius)
	_cam.rotation = Vector3(-atan2(height - LOOK_HEIGHT, radius), 0.0, 0.0)
	if t >= 1.0:
		_zooming = false

## 冻结判据：过了下限、且**已经有人挨过打**（= 真的挥出刀并命中了），或到了上限。
func _roll_ready(elapsed_ms: int) -> bool:
	if elapsed_ms >= PREROLL_MAX_MS:
		return true
	if elapsed_ms < PREROLL_MIN_MS:
		return false
	for unit in _units:
		if not is_instance_valid(unit):
			continue
		if unit.hp < unit.max_hp:
			return true
	return false

func _freeze() -> void:
	_frozen = true
	## ⚠️ **先回满血再冻**（2026-09-25 用户："开始界面不知道为什么有兵种扣血了（如图）"）：
	## 预演本来就是**故意**让它们真打到有人挨第一下（这样冻结姿势正好落在挥砍动画的顶点），
	## 代价是背景里会挂着"已经在掉血"的血条 ⇒ 冻住之前统一 `heal_to_full()`（血条随之消失），
	## 玩家看到的永远是"刚打到一半、双方都还完好"的那一帧。
	for unit in _units:
		if is_instance_valid(unit):
			unit.heal_to_full()
	## 整棵战斗子树停摆：单位不再思考 / 移动 / 挥砍，动画停在当前这一帧。
	## ⚠️ 相机不在 `_battle` 里，所以它继续转（这正是用户要的"静止的战斗 + 绕圈的镜头"）。
	_battle.process_mode = Node.PROCESS_MODE_DISABLED
	roll_finished.emit()

func has_frozen() -> bool:
	return _frozen

# ---------------------------------------------------------------- 世界（灰地板 / 灰天空）
func _build_floor() -> void:
	## 地板既要有碰撞（单位要站得住、要被重力压在上面），也要能看见 ⇒ StaticBody3D + MeshInstance3D，
	## 与 `arena.gd#_build_environment()` 同一套做法，只是颜色换成灰的、尺寸收小到"看得见的一片"。
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1          ## 世界层：与真场地同一个层，单位掩码认它
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = FLOOR_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, -FLOOR_SIZE.y * 0.5, 0.0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Surface"
	var box_mesh := BoxMesh.new()
	box_mesh.size = FLOOR_SIZE
	mesh.mesh = box_mesh
	mesh.position = Vector3(0.0, -FLOOR_SIZE.y * 0.5, 0.0)
	mesh.material_override = _mat(FLOOR_COLOR)
	body.add_child(mesh)
	add_child(body)

func _build_sky() -> void:
	## 背景色 = 天空。用纯色（`BG_COLOR`）而不是程序化天空：用户要的就是"一片灰"。
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = SKY_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT_COLOR
	e.ambient_light_energy = AMBIENT_ENERGY
	e.fog_enabled = false             ## 灰色调下起雾只会把地板也洗白，这里刻意不开
	env.environment = e
	add_child(env)

func _build_sun() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = SUN_ANGLE_DEG
	light.light_energy = SUN_ENERGY
	light.light_color = SUN_COLOR
	light.shadow_enabled = true
	add_child(light)

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.metallic = 0.0
	return m

# ---------------------------------------------------------------- 阵容与镜头
func _spawn_lineup(lineup: Array, team: int) -> void:
	## ⚠️ 顺序照抄 `arena.gd#spawn_roster()`：先 `setup()` 再 `add_child()`（`_ready()` 里要用 team/type）。
	var facing := GameConfig.team_spawn_sign(team) * PI * 0.5
	var sign_x := GameConfig.team_spawn_sign(team)
	var count := lineup.size()
	for i in count:
		var type_id := String(lineup[i])
		var unit := Unit3D.new()
		unit.name = "Showcase_%s_%d" % [type_id, i]
		unit.setup(team, type_id)
		_battle.add_child(unit)
		var z := (float(i) - float(count - 1) * 0.5) * RANK_GAP_Z
		unit.global_position = Vector3(sign_x * RANK_X, GameConfig.SPAWN_HEIGHT, z)
		unit.rotation.y = facing
		## ⚠️ 必须打开这个开关，否则背景里是"两排兵站着不动"：`Unit3D.active` 默认 false
		##（`unit3d.gd` 里的原话是"比赛开始后才行动"），真比赛里由 `Arena.start_match()` 逐个置真
		##（`arena.gd#start_match()`）。这里没有 Arena，所以由本函数代劳。
		## ⚠️ 它**只影响这一批演示单位**：本文件不建 Arena、不发 `Events.unit_spawned`、
		## 不进任何名单，也不碰 `GameConfig` 的任何一个值。
		unit.active = true
		_units.append(unit)

func _build_camera() -> void:
	## 相机挂在 pivot 上：pivot 只转 yaw ⇒ 相机沿圆周转，同时始终看向圆心。
	_pivot = Node3D.new()
	_pivot.name = "OrbitPivot"
	_pivot.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.name = "ShowcaseCamera"
	_cam.current = true               ## 真比赛的 Arena / CameraRig 各有自己的相机，后建的会接管
	_cam.position = Vector3(0.0, ORBIT_HEIGHT - LOOK_HEIGHT, ORBIT_RADIUS)
	_cam.rotation = Vector3(-atan2(ORBIT_HEIGHT - LOOK_HEIGHT, ORBIT_RADIUS), 0.0, 0.0)
	_pivot.add_child(_cam)
