class_name Sandbox
extends Node
## 沙盒模式：玩家**自己摆兵、自己开战、自己收兵**（不做押注）。
##
## 依据（用户 2026-09-25 口径，逐条对应）：
##   · 兵**由玩家自由摆放**，不随机生成；底部是兵种栏（想放哪种就选哪种）；
##   · 落点**左半边（−X）= 赤羽卫**、其余 = 青锋卫 —— 与不变量 I-35 的出生侧完全一致
##     （`GameConfig.team_spawn_sign(0) == −1`），所以这里**不写死方向**，一律从 `team_spawn_sign()` 推；
##   · **没有押注、没有兴奋圈、不判平局**（连"90 s 限时 + 比血量"那套结算也没有）；
##   · 顶部显示**双方总权重**（就是本文件这两个清单的重量，见 `total_weight()`）。
##   · 相机与自由视角的操作与竞猜模式**完全同源**：本文件只调用 `CameraRig` 现成的那几支
##     （`on_betting_phase()` / `on_fight_phase()` / `on_round_result()`），不自己摆机位。
##
## ⚠️ 与竞猜模式的**唯一分界**：本节点**从不调用 `Arena.start_match()`**。
##   那一支的语义是"**启动赛程**"（`match_active = true`）—— 兴奋圈收缩、90 s 限时、僵持判平、
##   平局判定全挂在它下面（`arena.gd#_physics_process`）。按用户口径，这几条**只属于竞猜模式**，
##   沙盒刻意不受它们约束 ⇒ 这里改用 `Arena.start_skirmish()`（只点火、不启赛程），
##   结束条件由本文件自己判（一方全灭 / 玩家点「结束战斗」）。
##   ⇒ 摆完不打也不会超时、圈不会出现、双方同归于尽也不会有"平局"这一说。
##
## ⚠️ 暂停 / 恢复沿用经典那一套（`MatchPause`）：树暂停**不会停表**，而出手冷却 / 技能冷却 /
##   冲刺时长全是绝对毫秒（不变量 I-13）⇒ 恢复时必须把暂停时长整体从这些时刻里扣掉。
##   （本文件与 `game.gd` 的这两段是**刻意各自实现**的：它们属于各自的玩法，只有算法在 `MatchPause`。）

signal phase_changed(phase: String)      ## 相位跳变（本模式**自己的**信号，不上 `Events` 总线）

enum Phase { PLACING, FIGHTING, RESULT }

## 拾取用的碰撞层：`Unit3D.setup()` 把两队放在 layer 2 / 3（`1 << (team + 1)`），
## 掩码取这两位 ⇒ **只可能命中单位**，不会命中地面与场景（于是"点到兵 = 收掉它"不会被地板抢走）。
## ⚠️ 2026-09-27 去重：本文件原先自持一份同值常量（肉鸽那边另有一份，旧账）⇒ 现在只有
## `GameConfig.UNIT_PICK_*` 一处出处（I-15），两个模式共用。
const PICK_MASK := GameConfig.UNIT_PICK_MASK
const PICK_RANGE := GameConfig.UNIT_PICK_RANGE
## ⚠️ 拖动放置的两条闸门（最小间距 / 一笔上限）**不在这里** —— 2026-09-25 用户裁决搬进
## `GameConfig.DRAG_MIN_SPACING` / `GameConfig.DRAG_STROKE_LIMIT`（不变量 I-15：可调参数住 `GameConfig`）。
## 本文件只**读**它们，不保存副本。

var phase: int = Phase.PLACING
var _hold_waiting: bool = false
var _hold_manual: bool = false
var _range_hint: RangeHint = null
var arena: Arena = null
var camera_rig: CameraRig = null
var result: Dictionary = {}              ## 上一场的战果（`_settle_battle()` 填，HUD 读它显示胜负）

var _selected_type: String = ""          ## 兵种栏当前选中的兵种（底部界面点一下换一个）
## 每个兵种栏上勾着的科技（`兵种 ID → {科技 ID: true}`）。只影响**之后放下去**的兵，不改已经在场上的。
## 效果参数仍只读 `GameConfig.ROGUELIKE_TECH_TABLE`（I-15）。沙盒不扣补给。
var _picked_techs: Dictionary = {}
## 查看模式：左右键都只点选场上的兵，不摆、不收。
var _view_mode: bool = false
var _viewed: Unit3D = null               ## 查看模式里点中的那一个（空 = 还没点）
## **「权重递增模式」开关**（2026-09-25 第七轮用户口径：点沙盒里的「召唤石柱」卡片时选是否开启）。
## ⚠️ 它只是一个**运行时开关**：那几档数值（每 10 s +2、第一档只允许权重 1…）全在
## `GameConfig.UNIT_ESCALATION_*`，住 `GameConfig`（不变量 I-15）。
## ⚠️ 开关**跟着这一局沙盒走**（布兵 → 开战 → 重新布兵都保留），写穿到 `Arena` 供石柱读取。
var _weight_escalation: bool = false
## **布兵的唯一记账**：一条 = `{"team": int, "type": String, "at": Vector3, "unit": Unit3D}`。
## ⚠️ 2026-09-25 起它是"名单 + 布局"的**同一份事实**（原先只有两份兵种清单 `_types_a/b`，没有落点）——
## 用户要求"**战斗完毕后应保留之前的布兵布局**"，所以落点必须记下来（见 `roll_again()` / `_respawn_layout()`）。
## ⚠️ `unit` 是"当面那个节点"的引用，只用来把"右键点到的那一个"对回布局条目；重新 spawn 时会刷新。
var _layout: Array[Dictionary] = []
var _pause_from_ms: int = 0              ## 暂停开始时刻（0 = 没在暂停），见 `pause_match()`
## 拖动放置（用户 2026-09-25："沙盒模式可以进行拖动放置"）：按住左键在场上拖，沿途连续摆兵。
## 这四个字段就是"当前这一笔"的全部记账（起笔清零、收笔清空，见 `_begin_paint()` / `_finish_paint()`）。
var _painting: bool = false              ## 左键还按着（这一笔画到一半）
var _paint_has_last: bool = false        ## 本笔已经落下过至少一个点（间距判据的前提）
var _paint_last_pos := Vector3.ZERO      ## 本笔最后一个落点（坐标 ⇒ 名字带 `pos`，§3.3）
var _paint_count: int = 0                ## 本笔已经摆了几个（上限判据）
## 右键"**扫除**"（2026-09-25 用户："沙盒模式按住右键拖动也能批量移除兵种"）：按住右键在场上扫，
## 光标扫过谁就收掉谁。
## ⚠️ 这里**只需要一个状态位**（不像左键那边还要间距 / 上限记账）：被收掉的兵当帧就摘出名单，
## 下一帧的光标只可能命中"还没被收掉的那个" ⇒ 最坏也就是"每物理帧收掉一个"，收完为止。
var _erasing: bool = false
## 拖动"幽灵"（2026-09-26 第六块，用户："拖动时兵种的'幽灵'跟着鼠标"）：一个跟着光标的半透明盒子，
## 绿 = 这一笔落得下 / 红 = 落不下（判据就是 `_can_paint_at()`）。⚠️ 纯表现：不进 `units` / `_layout`。
var _ghost_root: MeshInstance3D = null   ## 幽灵本体（懒建，**一个节点反复复用**，不每次现造）
var _ghost_type: String = ""             ## 当前盒子按哪个兵种的体型盒建的（换兵种时只改 `mesh.size`）

func bind(p_arena: Arena, p_camera: CameraRig) -> void:
	arena = p_arena
	camera_rig = p_camera

# ---------------------------------------------------------------- 相位
## 进入沙盒：默认选好第一个兵种，并把相机摆到"经典下注阶段"那一套（全景机位 + 光标可见）。
## ⚠️ 光标必须可见 —— 布兵全靠点地面（`_unhandled_input()`），光标锁住就没法摆。
func begin() -> void:
	if _selected_type == "":
		_selected_type = String(GameConfig.TYPE_ORDER[0])
	phase = Phase.PLACING
	## 把「权重递增模式」开关推到场地（`arena` 在 `main.gd` 里先于本函数 bind）——
	## 石柱（`Unit3D`）只从场地读它，单位不认识 `Sandbox`。
	_push_escalation()
	if not Events.unit_died.is_connected(_on_unit_died):
		Events.unit_died.connect(_on_unit_died)
	if camera_rig != null:
		camera_rig.on_betting_phase()
	phase_changed.emit(phase_name())

## 「权重递增模式」的**唯一写入口**（界面侧：点石柱卡片时选开启 / 不开启）。
## 读侧是 `weight_escalation()`；石柱那一侧只看 `Arena.summon_escalation`（由本函数写穿）。
func set_weight_escalation(on: bool) -> void:
	_weight_escalation = on
	_push_escalation()

func weight_escalation() -> bool:
	return _weight_escalation

func _push_escalation() -> void:
	if arena != null:
		arena.summon_escalation = _weight_escalation

## 开战（底部「开战」按钮）：点火 + 相机切到指挥视角。**不启赛程**（见文件头）。
func start_battle() -> void:
	if phase != Phase.PLACING:
		return
	if roster_of(0).is_empty() or roster_of(1).is_empty():
		return                           ## 空场开战没有意义（两边各至少一个；按钮由 HUD 灰掉）
	_finish_paint()                      ## 万一开战那一刻还按着左键：这一笔就此收掉
	_finish_erase()                      ## 右键扫除同理
	_viewed = null
	_wake_placed_units()
	arena.start_skirmish()
	for node in arena.units:
		var fighter := node as Unit3D
		if fighter != null and is_instance_valid(fighter):
			fighter.refresh_ward()
	phase = Phase.FIGHTING
	if camera_rig != null:
		## 与竞猜模式开赛同一支：光标锁进窗口 + 平滑飞到"两队质心上方偏后"的指挥视角。
		camera_rig.on_fight_phase()
		camera_rig.open_pilot_gate(false)
	phase_changed.emit(phase_name())

## 结束战斗（暂停菜单里那一项，用户口径：战斗阶段的「重新开始」改为「结束战斗」）。
## ⚠️ 本函数**自己解除暂停**：`PauseMenu` 在黑透那一刻调它，之后只负责渐亮，不会再补
## `resume_match()`（补了会把暂停时长重复扣一遍）。与 `Game.restart_game()` 的分工完全一致。
func end_battle() -> void:
	_pause_from_ms = 0
	get_tree().paused = false
	if phase != Phase.FIGHTING:
		return
	_hold_waiting = false
	if camera_rig != null:
		camera_rig.close_pilot_gate()
		camera_rig.release_look()
	if arena != null:
		arena.settle()
		arena.end_presentation_hold()
	_respawn_layout()
	result = {}
	phase = Phase.PLACING
	if camera_rig != null:
		camera_rig.on_betting_phase()
	phase_changed.emit(phase_name())

## 重新布兵（结果浮层的按钮）：**把之前那套布兵原样摆回去**，再回到布兵阶段。
## ⚠️ 2026-09-25 用户口径改过：原来是"清场 + 清空名单"（布局全丢），现在改成
## "**战斗完毕后应保留之前的布兵布局**" ⇒ 这里不再清空 `_layout`，而是照着它重新 spawn 一遍：
## 兵种 / 落点 / 朝向都照旧，血量回满、一律是"未点火"状态（可以改几个再开战）。
## ⚠️ 必须**重新 spawn**而不是"留着打完的残兵"：战斗会把它们推散、打死、烧掉 —— 只有重摆才是"原来的布局"。
func roll_again() -> void:
	if phase != Phase.RESULT:
		return
	arena.settle()                       ## 清掉单位与箭矢、复位兴奋圈（本模式不显示圈，复位是无害的）
	arena.end_presentation_hold()
	_respawn_layout()
	result = {}
	phase = Phase.PLACING
	if camera_rig != null:
		camera_rig.on_betting_phase()
	phase_changed.emit(phase_name())

## 照着 `_layout` 把兵重新摆一遍（`roll_again()` 用；也顺手刷新每条里的 `unit` 引用）。
## ⚠️ 朝向**重新按半场算**（与 `_place()` 同一条式子），不存进布局 —— 存了就有"两份事实"。
func _respawn_layout() -> void:
	_viewed = null
	for entry in _layout:
		var team := int(entry["team"])
		var type_id := String(entry["type"])
		var at: Vector3 = entry["at"]
		var facing := GameConfig.team_spawn_sign(team) * PI * 0.5
		var unit := arena.spawn_unit(team, type_id, at, facing)
		entry["unit"] = unit
		if unit != null:
			_apply_place_techs(unit, type_id, entry.get("techs", []))
			_park_placed_unit(unit)

func phase_name() -> String:
	match phase:
		Phase.PLACING:
			return "placing"
		Phase.FIGHTING:
			return "fighting"
		Phase.RESULT:
			return "result"
	return "unknown"

# ---------------------------------------------------------------- 兵种栏（底部界面调它）
func select_type(type_id: String) -> void:
	_selected_type = type_id

func selected_type() -> String:
	return _selected_type

## 点一下科技按钮：已勾上就取消，没勾上就勾上。只记在当前兵种名下。
func toggle_place_tech(type_id: String, tech_id: String) -> void:
	if GameConfig.roguelike_tech_def(type_id, tech_id).is_empty():
		return
	if not _picked_techs.has(type_id):
		_picked_techs[type_id] = {}
	var owned: Dictionary = _picked_techs[type_id]
	if owned.has(tech_id):
		owned.erase(tech_id)
	else:
		owned[tech_id] = true

func place_tech_on(type_id: String, tech_id: String) -> bool:
	var owned: Dictionary = _picked_techs.get(type_id, {})
	return owned.has(tech_id)

func view_mode() -> bool:
	return _view_mode

## 打开时收掉正在画的笔和正在扫的右键，免得同一次点击又摆又看。
func set_view_mode(on: bool) -> void:
	if _view_mode == on:
		return
	_view_mode = on
	_finish_paint()
	_finish_erase()
	if not on:
		_viewed = null
	phase_changed.emit(phase_name())

func clear_view() -> void:
	_viewed = null
	phase_changed.emit(phase_name())

## 查看面板要的那本数字。空字典 = 没有可看的兵。最终值直接问单位（科技已经算进去了）。
func viewed_stats() -> Dictionary:
	if _viewed == null or not is_instance_valid(_viewed) or not _viewed.alive:
		return {}
	var type_id := _viewed.type_id
	var profile: Dictionary = GameConfig.profile(type_id)
	var tech_mult := _viewed.tech_damage_mult()
	var interval_mult := _viewed.tech_interval_mult()
	var damage := GameConfig.hit_damage(type_id)
	var attack_speed := float(profile["attack_speed"]) / maxf(interval_mult, 0.001)
	return {
		"name": GameConfig.profile_name(type_id),
		"type_id": type_id,
		"team": _viewed.team,
		"hp_now": _viewed.hp,
		"hp_max": _viewed.max_hp,
		"damage": damage,
		"tech_mult": tech_mult,
		"damage_final": damage * tech_mult,
		"attack_speed": attack_speed,
		"reach": _viewed.attack_reach(),
		"is_ranged": _viewed.is_ranged(),
		"speed": _viewed.current_speed(),
		"weight": int(profile["weight"]),
		"mass": _viewed.mass(),
		"armor": _viewed.tech_armor(),
		"kb_bonus": _viewed.tech_kb_bonus(),
		"shield_max": _viewed.tech_shield_max(),
		"saint": _viewed.is_saint(),
		"tech_ids": _viewed.tech_ids(),
	}

## 某一方**已摆下**的兵种清单（与 `Game.roster_a/roster_b` 同义：这一场带了多少兵）。
## ⚠️ 由 `_layout` **推导**（不再另存一份数组）：两份事实必然漂移，而这里一秒钟能算几十次。
func roster_of(team: int) -> Array:
	var out: Array = []
	for entry in _layout:
		if int(entry["team"]) == team:
			out.append(String(entry["type"]))
	return out

func total_weight(team: int) -> int:
	return GameConfig.roster_weight(roster_of(team))

# ---------------------------------------------------------------- 布兵（左键点/拖放置，右键点/拖收兵）
## 鼠标交互（2026-09-25 按用户口径定）：
##   · **左键**：按下即在光标落点放一个兵；**按住不放并拖动** ⇒ 沿途按 `GameConfig.DRAG_MIN_SPACING`
##     连续摆一串，并且脚印不能压到已经摆下的单位；松手（或光标离开场地）这一笔就结束。
##   · **右键**：点在自己摆的兵身上 = **收掉它**；**按住不放并拖动** ⇒ **沿途扫掉**（批量移除 ——
##     用户 2026-09-25："沙盒模式按住右键拖动也能批量移除兵种"）。
## ⚠️ 用户口径："**左键不再移除兵种**" ⇒ 左键点到一个已经摆好的兵身上时**不收它**，而是在那里放一个新的。
## ⚠️ 两个按钮**互斥**：起手时先把正在进行的那一种收掉（同时按住左右键是手滑，不该一边摆一边收）。
func _unhandled_input(event: InputEvent) -> void:
	if _take_result_continue(event):
		return
	if phase != Phase.PLACING:
		return
	## ⚠️ **2026-09-25 修 bug（用户："沙盒模式中，退出自由视角的鼠标左键和右键也会在场上放置和移除兵种"）**：
	## 退出自由视角的那一下点击是 `CameraRig._process()` **轮询**鼠标键做出来的（不是从事件里读的），
	## 所以**同一个事件也会走到这里** ⇒ 点一下既退出自由视角、又顺手摆/收了一个兵。
	## ⚠️ 输入事件比 `_process` 早：这一下进来时 `mode` **还是** `OVERVIEW` ⇒ 用模式判断就能拦住它。
	##（自由视角下整个 HUD 本来就是隐藏的，玩家在那里点鼠标的语义只有"退出"。）
	if _overview_active():
		return
	## 查看模式：左右键都只点选，不摆、不收。松手也不收笔（这一模式本来就没有笔）。
	if _view_mode:
		if event is InputEventMouseButton:
			var look := event as InputEventMouseButton
			if look.pressed and (look.button_index == MOUSE_BUTTON_LEFT or look.button_index == MOUSE_BUTTON_RIGHT):
				_select_view_at(look.position)
		return
	if event is InputEventMouseMotion:
		## ⚠️ 拖动中**在输入事件上也试一次**（不是只靠 60 Hz 的物理帧轮询）：鼠标移动事件比物理帧密，
		## 笔画 / 扫除都更跟手（摆的那一侧还有 `_can_paint_at()` 的间距闸门兜着，不会因此刷出一堆）。
		var motion := event as InputEventMouseMotion
		if _painting:
			_try_paint_at_screen(motion.position)
		elif _erasing:
			_try_erase_at_screen(motion.position)
		return
	if not (event is InputEventMouseButton):
		return
	## ⚠️ 只认 `_unhandled_input`：底部兵种栏的那些按钮会把点在自己身上的事件吃掉
	##（Control 默认 `MOUSE_FILTER_STOP`）⇒ 点界面绝不会顺手在场上放一个兵。
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_finish_paint()              ## 松手 = 这一笔到此为止
		else:
			_finish_erase()              ## 松手 = 这次扫除到此为止
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_begin_erase_at_screen(button.position)
		return
	## 左键：起笔（落点不在场地上就不起笔 —— 点天上、点看台都不算）
	_begin_paint_at_screen(button.position)

## ⚠️ 2026-09-25 修 bug（用户："选完兵种后刚开始拖动放置时会放不出来，**而且要拖一段才出第一个**"）：
## **按下那一下必须用事件自带的位置**（`event.position`），**不能**用 `get_viewport().get_mouse_position()`
## —— 后者是"视口缓存的上一帧鼠标位置"，在"移过去马上按住"这种快动作下还没跟上：
## 界面命中用的是事件位置（所以面板没吃掉这一下），而摆兵用的是缓存位置（可能落在**底部面板背后**的地面）
## ⇒ 第一个兵被摆在面板后面（玩家看不见），直到拖动几帧后缓存位置跟上，才"突然冒出第一个"。
## 现在按下走事件位置、拖动走视口位置（那时没有事件可用），两条路都从 `_ground_at()` 走。
func _begin_paint_at_screen(screen_pos: Vector2) -> void:
	_finish_erase()                      ## 互斥：先收掉可能正在进行的右键扫除
	var at: Variant = _ground_at(screen_pos)
	if at == null:
		return
	_begin_paint(at)

## 拖动中按"屏幕位置"试落一笔（输入事件与物理帧轮询共用这一条路）。
## ⚠️ 幽灵也在这里更新（不只是物理帧那条轮询）：鼠标移动事件比物理帧密，观感上"幽灵贴着光标走"
## 靠的就是这一路；`_tick_paint()` 那一路是"没有新事件时也每帧对齐一次"的兜底。
func _try_paint_at_screen(screen_pos: Vector2) -> void:
	var at: Variant = _ground_at(screen_pos)
	if at == null:
		return
	if _painting:
		_update_ghost(at)
	_try_paint(at)

## 起笔：落第一个兵，并把这一笔的记账清零。
func _begin_paint(at: Vector3) -> void:
	_painting = true
	_paint_has_last = false
	_paint_count = 0
	_try_paint(at)

## 收笔：清掉"正在拖"的状态（松手、开战、以及任何离开布兵阶段的地方都要走它）。
func _finish_paint() -> void:
	_painting = false
	_paint_has_last = false
	_paint_count = 0
	_hide_ghost()                        ## 幽灵跟着笔画一起收（见 `_update_ghost()`）

# ---------------------------------------------------------------- 拖动"幽灵"（跟着光标的预演）
## 用户 2026-09-26 第六块："拖动时兵种的'幽灵'跟着鼠标" ⇒ 按住左键拖动时，在光标落点摆一个**半透明盒子**
## （尺寸取该兵种的体型盒），绿 = 这一笔落得下、红 = 落不下（超了本笔上限或离上一笔太近，判据就是
## `_can_paint_at()`，与真正落笔**同一个口**）。
## ⚠️ 盒子**不是**单位：没有碰撞体、不进 `units` / `_layout`（纯表现）。
## ⚠️ 只在"正在拖"时出现（松手 / 进自由视角 / 开战都会 `_finish_paint()` ⇒ 一起收掉）。
func _update_ghost(at: Vector3) -> void:
	if _selected_type == "":
		_hide_ghost()
		return
	if _ghost_root == null or not is_instance_valid(_ghost_root):
		_ghost_root = MeshInstance3D.new()
		_ghost_root.name = "PlaceGhost"
		var mesh := BoxMesh.new()
		_ghost_root.mesh = mesh
		_ghost_root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ghost_root)
	## 体型盒跟真正落下的脚印同一套尺寸，再转到这一落点该有的朝向。
	var size := GameConfig.place_footprint_size(_selected_type)
	var box: Dictionary = GameConfig.body_box(_selected_type)
	var lift: float = float(box.get("lift", size.y * 0.5))
	if _ghost_type != _selected_type:
		_ghost_type = _selected_type
		var mesh := BoxMesh.new()        ## 换兵种 ⇒ 换盒子大小（同一个节点，不重建）
		mesh.size = size
		_ghost_root.mesh = mesh
	_ghost_root.global_position = Vector3(at.x, lift, at.z)
	_ghost_root.rotation.y = _place_facing(at)
	var tint: Color = GameConfig.GHOST_OK_COLOR if _can_paint_at(at) else GameConfig.GHOST_BAD_COLOR
	_ghost_root.material_override = _ghost_material(tint)
	_ghost_root.visible = true

func _hide_ghost() -> void:
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.visible = false

## 幽灵的材质：与轮廓同一套语言（绿 = 落得下 / 红 = 落不下），比格子预览更透明（别挡住兵）
func _ghost_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## 拖动中的每一物理帧：光标还在动就按最小间距继续摆；左键一松就收笔。
## ⚠️ 用**轮询**兜底而不是只认鼠标移动事件：拖动时光标可能划过底部兵种栏，那些事件会被界面吃掉 ——
## 轮询每帧独立判断，不受"谁吃掉了事件"影响（松手那一下被吃掉时也靠它收笔）。
func _tick_paint() -> void:
	if not _painting:
		return
	if phase != Phase.PLACING or _view_mode:   ## 开战或查看模式：收笔，别继续摆
		_finish_paint()
		return
	## ⚠️ 进自由视角就收笔（2026-09-25）：那里的鼠标键只用来"退出"，
	## 不拦的话"一边按着左键拖、一边按 Tab 进自由视角"会在自由视角里继续摆兵。
	if _overview_active():
		_finish_paint()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_paint()
		return
	## ⚠️ 光标**藏在自由视角里**时视口位置是旧值，摆出来的兵会落在一个玩家看不见的地方 ⇒ 上面已拦住。
	var at: Variant = _ground_at(get_viewport().get_mouse_position())
	if at == null:
		return
	_update_ghost(at)                    ## 先把幽灵摆到光标下（纯表现），再试落笔
	_try_paint(at)

## 自由视角（`OVERVIEW`）下**一切布兵输入都停摆**：那里的左右键只负责"退出自由视角"。
## ⚠️ 这条闸门是 2026-09-25 修 bug 加的，三处都要用它（`_unhandled_input()` / `_tick_paint()` / `_tick_erase()`）。
func _overview_active() -> bool:
	return camera_rig != null and camera_rig.mode == CameraRig.Mode.OVERVIEW

## 起手扫除：先收掉光标下面那一个，然后进入"扫"的状态（拖动中沿途继续收）。
func _begin_erase_at_screen(screen_pos: Vector2) -> void:
	_finish_paint()                      ## 互斥：先收掉可能正在进行的左键笔画
	_erasing = true
	_try_erase_at_screen(screen_pos)

## 收手：清掉"正在扫"的状态（松手 / 开战 / 离开布兵阶段都要走它）。
func _finish_erase() -> void:
	_erasing = false

## 扫除中的每一物理帧：光标扫到谁就收谁；右键一松就收手。
## ⚠️ 与左键那一侧**共用同一套兜底理由**：拖动时光标会划过底部兵种栏、那些移动事件会被界面吃掉 ——
## 轮询每帧独立判断，不受"谁吃掉了事件"影响（松手那一下被吃掉时也靠它收手）。
func _tick_erase() -> void:
	if not _erasing:
		return
	if phase != Phase.PLACING or _view_mode:   ## 开战或查看模式：收手，别继续收兵
		_finish_erase()
		return
	if _overview_active():               ## 同上：自由视角里右键是"退出"，不是"扫兵"
		_finish_erase()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_finish_erase()
		return
	_try_erase_at_screen(get_viewport().get_mouse_position())

## 光标下面有兵就收掉它（没有就什么也不做）。
func _try_erase_at_screen(screen_pos: Vector2) -> void:
	var picked := _unit_under_cursor(screen_pos)
	if picked != null:
		_remove_unit(picked)

## 这一笔能不能落在 `at`？本笔没超上限，脚印不压到已摆下的单位，
## 并且离上一个落点至少 `GameConfig.DRAG_MIN_SPACING`。
## ⚠️ 单独抽出来是为了**可测**：无头探针可以直接喂坐标验间距与上限，不需要真的按住鼠标。
func _can_paint_at(at: Vector3) -> bool:
	if _paint_count >= GameConfig.DRAG_STROKE_LIMIT:
		return false
	if _selected_type != "" and _place_overlaps(at, _selected_type):
		return false
	if not _paint_has_last:
		return true
	return _paint_last_pos.distance_to(at) >= GameConfig.DRAG_MIN_SPACING

## 落点在哪一侧，朝向就跟 `_place()` 用同一条式子。
func _place_facing(at: Vector3) -> float:
	var team := 0 if at.x < 0.0 else 1
	return GameConfig.team_spawn_sign(team) * PI * 0.5

## 水平面上的半长。单位面朝 ±X 时，本地纵深落到世界 X，本地横宽落到世界 Z。
func _place_world_half(type_id: String, facing: float) -> Vector2:
	var size := GameConfig.place_footprint_size(type_id)
	var along_x := absf(cos(facing))
	var along_z := absf(sin(facing))
	return Vector2(size.x * 0.5 * along_x + size.z * 0.5 * along_z, size.x * 0.5 * along_z + size.z * 0.5 * along_x)

## 这个脚印是否压进了已经摆下的某个单位。贴边不算重叠。
func _place_overlaps(at: Vector3, type_id: String) -> bool:
	var half := _place_world_half(type_id, _place_facing(at))
	for entry in _layout:
		var other_at: Vector3 = entry["at"]
		var other_id := String(entry["type"])
		var other_half := _place_world_half(other_id, _place_facing(other_at))
		var dx := absf(at.x - other_at.x)
		var dz := absf(at.z - other_at.z)
		if dx < half.x + other_half.x and dz < half.y + other_half.y:
			return true
	return false

func _try_paint(at: Vector3) -> void:
	if not _can_paint_at(at):
		return
	_place(at)
	_paint_last_pos = at
	_paint_has_last = true
	_paint_count += 1

## 放一个兵：阵营由**落点所在的半场**决定（用户口径：左半边赤羽卫、其余青锋卫）。
func _place(at: Vector3) -> void:
	if _selected_type == "" or arena == null:
		return
	var team := 0 if at.x < 0.0 else 1
	## 朝向一律"面朝对面"：与 `Arena.spawn_roster()` 用的是**同一条式子**（不变量 I-30 / I-35）
	var facing := _place_facing(at)
	var unit := arena.spawn_unit(team, _selected_type, at, facing)
	if unit == null:
		return
	var tech_ids := _picked_ids(_selected_type)
	_apply_place_techs(unit, _selected_type, tech_ids)
	_park_placed_unit(unit)
	_layout.append({
		"team": team, "type": _selected_type, "at": at, "unit": unit, "techs": tech_ids,
	})
	phase_changed.emit(phase_name())     ## 权重变了 ⇒ 让 HUD 立刻刷新（不必等下一次轮询）

## 当前兵种栏上勾着的科技 id（放兵、以及重新布兵时都读这一份）。
func _picked_ids(type_id: String) -> Array:
	var owned: Dictionary = _picked_techs.get(type_id, {})
	var ids: Array = []
	for tech_id in owned.keys():
		ids.append(String(tech_id))
	return ids

## 布兵阶段先别跑物理。表现留着，买了的科技外观在开战前就能看见。
func _park_placed_unit(unit: Unit3D) -> void:
	unit.set_process(true)
	unit.set_physics_process(false)

func _wake_placed_units() -> void:
	if arena == null:
		return
	for node in arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit):
			continue
		unit.set_process(true)
		unit.set_physics_process(true)

## 把一份科技 id 推到这个兵身上。剑圣在沙盒里是「勾了就这个人自己是」，不是肉鸽那种每队一位。
func _apply_place_techs(unit: Unit3D, type_id: String, tech_ids: Array) -> void:
	var active: Dictionary = {}
	for raw in tech_ids:
		var tech_id := String(raw)
		var def := GameConfig.roguelike_tech_def(type_id, tech_id)
		if def.is_empty():
			continue
		active[tech_id] = def
	unit.set_techs(active)
	unit.set_saint(active.has("sword_saint"))

## 扇子兵「清道夫」：战斗中抹掉身边的酸液。半径读科技表。
func _tick_scavengers() -> void:
	if arena == null:
		return
	var row := GameConfig.roguelike_tech_def("fan", "scavenger")
	var radius := float(row.get("radius", 5.0)) if not row.is_empty() else 5.0
	for raw in arena.units:
		var unit := raw as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive or not unit.has_tech("scavenger"):
			continue
		arena.clear_ground_near(unit.global_position, radius)

## 骑士「壁垒」的圈和连线。分伤本身在单位身上，这里只负责让它看得见。
func _sync_bulwark_fx() -> void:
	if arena == null:
		return
	var knights: Array[Unit3D] = []
	for node in arena.units:
		var unit := node as Unit3D
		if unit != null and unit.alive and unit.has_tech("bulwark"):
			knights.append(unit)
	var linked := {}
	var segments: Array = []
	var link_def := GameConfig.roguelike_tech_def("knight", "bulwark")
	var radius := float(link_def.get("link_radius", 5.0))
	var radius_sq := radius * radius
	for i in knights.size():
		for j in range(i + 1, knights.size()):
			var flat := knights[j].global_position - knights[i].global_position
			flat.y = 0.0
			if flat.length_squared() > radius_sq:
				continue
			linked[knights[i]] = true
			linked[knights[j]] = true
			segments.append({"a": knights[i].global_position, "b": knights[j].global_position})
	for node in arena.units:
		var marked := node as Unit3D
		if marked != null:
			marked.set_bulwark_mark(linked.has(marked))
	arena.show_bulwark_links(segments)

func _clear_bulwark_marks() -> void:
	if arena == null:
		return
	for node in arena.units:
		var unit := node as Unit3D
		if unit != null:
			unit.set_bulwark_mark(false)

## 「自我复制」。生出来的是击杀者自己的兵种，等级与击杀者相同。不进布兵名单，重新布兵时跟着清场一起走。
## 影魔要累计 5 权重才生 1 个；复制体不再复制，打死复制体也不算。
## 同一条死亡也处理「弃马人」。
func _on_unit_died(unit: Node3D) -> void:
	if phase != Phase.FIGHTING:
		return
	var dead := unit as Unit3D
	if dead == null:
		return
	_dismount_on_death(dead)
	var killer := dead.killer()
	if killer == null or not is_instance_valid(killer) or not killer.has_tech("replicate"):
		return
	if arena == null:
		return
	var count := killer.replicate_spawn_count(dead)
	if count <= 0:
		return
	var tech_ids := killer.tech_ids()
	var spawn_type := killer.type_id
	for i in count:
		var angle := TAU * float(i) / float(count)
		var at := dead.global_position + Vector3(cos(angle), 0.0, sin(angle)) * GameConfig.ROGUELIKE_REPLICATE_SPREAD
		var spawned := arena.spawn_unit(killer.team, spawn_type, at, killer.rotation.y)
		if spawned == null:
			continue
		spawned.set_meta("replicated", true)
		spawned.set_meta("replicate_owner", killer.get_instance_id())
		_apply_place_techs(spawned, spawn_type, tech_ids)
		spawned.set_level(killer.level)
		spawned.active = true

## 「弃马人」：勾着这条的轻骑兵死后，留下一名长矛兵。
## 长矛科技取兵种栏上当前勾着的那些（沙盒没有“本局买下”的另一份账）。
func _dismount_on_death(dead: Unit3D) -> void:
	if dead.type_id != "lightcav" or not dead.keeps_tech("dismount"):
		return
	if arena == null:
		return
	var spear_rows := {}
	for raw in _picked_ids("spear"):
		var tech_id := String(raw)
		var def := GameConfig.roguelike_tech_def("spear", tech_id)
		if not def.is_empty():
			spear_rows[tech_id] = def
	var facing := -dead.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.RIGHT
	var at := dead.global_position + facing.normalized() * 1.2
	var spawned := arena.spawn_unit(dead.team, "spear", at, dead.rotation.y)
	if spawned == null:
		return
	spawned.set_meta("dismounted", true)
	spawned.set_techs(dead.dismount_loadout(spear_rows))
	spawned.set_level(dead.level)
	spawned.active = true

## 查看模式：点到兵就选中，点空地就取消。
func _select_view_at(screen_pos: Vector2) -> void:
	_viewed = _unit_under_cursor(screen_pos)
	phase_changed.emit(phase_name())

## 收掉一个兵：布局里同步摘掉那一条（权重显示跟着降），节点交给 `Arena` 自己摘引用
##（`arena.gd#_on_unit_exiting` 挂在 `tree_exiting` 上）。
## ⚠️ 按 **`unit` 引用**把条目对回去（不按"兵种 + 坐标"猜：同兵种同位置的兵完全可能有两个）。
## ⚠️ 只有布兵阶段会走到这里 —— 战斗里死掉的兵由战斗自己处理，不经过本函数。
func _remove_unit(unit: Unit3D) -> void:
	var kept: Array[Dictionary] = []
	if _viewed == unit:
		_viewed = null
	for entry in _layout:
		if entry.get("unit") == unit:
			unit.queue_free()
			continue
		kept.append(entry)
	if kept.size() == _layout.size():
		return                           ## 没找到（理论上不会发生）：别白刷一次 HUD
	_layout = kept
	phase_changed.emit(phase_name())

## 「清空」某一方已摆下的兵（顶部那两个按钮，2026-09-25 用户要求："赤羽卫的清空在顶部偏左边，
## 青锋卫与之对称"）。⚠️ 只在布兵阶段有意义 —— 战斗 / 结果阶段界面上根本没有这两个按钮。
func clear_team(team: int) -> void:
	if phase != Phase.PLACING:
		return
	var kept: Array[Dictionary] = []
	for entry in _layout:
		if int(entry["team"]) != team:
			kept.append(entry)
			continue
		var unit: Unit3D = entry.get("unit")
		if unit != null and is_instance_valid(unit):
			unit.queue_free()
	if kept.size() == _layout.size():
		return                           ## 这一方本来就是空的：不白刷
	_layout = kept
	phase_changed.emit(phase_name())

## 屏幕坐标 → 地面（y = 0）的交点；打不到（射线朝上 / 与地面平行）时返回 null。
## 场地之外一律返回 null ⇒ 不会把兵摆到墙上、看台上或场地外。
## ⚠️ **位置必须由调用方给**：按下用 `event.position`（准），拖动用 `get_viewport().get_mouse_position()`。
func _ground_at(screen_pos: Vector2) -> Variant:
	var cam := _camera()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return null
	var point: Vector3 = hit
	if absf(point.x) > GameConfig.ARENA_HALF_X or absf(point.z) > GameConfig.ARENA_HALF_Z:
		return null
	return point

## 屏幕坐标下面有没有兵。⚠️ 掩码只留两队单位层（`PICK_MASK`）⇒ 命中不了地面，不用比距离。
func _unit_under_cursor(screen_pos: Vector2) -> Unit3D:
	var cam := _camera()
	if cam == null or arena == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * PICK_RANGE, PICK_MASK)
	query.collide_with_areas = false
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var unit := hit["collider"] as Unit3D
	if unit == null or not is_instance_valid(unit) or not unit.alive:
		return null
	return unit

## 屏幕射线要用的相机：**由 `CameraRig` 给**（它才是"当前是哪台相机"的唯一出处，
## 场景里另有一台 `Arena/SpectatorCamera` 兜底，别去猜哪台是 current）。
func _camera() -> Camera3D:
	if camera_rig == null:
		return null
	return camera_rig.camera()

# ---------------------------------------------------------------- 战斗结束
func _physics_process(_delta: float) -> void:
	_tick_paint()                        ## 拖动放置：只在"有笔在画"时才做事，其余帧零开销
	_tick_erase()                        ## 右键扫除：同上（只在"正在扫"时才做事）
	if arena != null:
		arena.sync_unit_wards()
		arena.drain_ward_blocks()
	_tick_range_hint()
	if phase == Phase.FIGHTING and arena != null:
		arena.tick_acid()
		arena.tick_fire()
		arena.tick_holy()
		arena.tick_flame_barrier()
		arena.tick_revenge()
		arena.tick_intercept_fx()
		_tick_scavengers()
		_sync_bulwark_fx()
	elif arena != null:
		arena.show_bulwark_links([])
		arena.hide_intercept_flashes()
		_clear_bulwark_marks()
	if _hold_waiting:
		if arena != null and arena.presentation_frozen:
			_settle_battle(_hold_manual)
		return
	if phase != Phase.FIGHTING:
		return
	## 结束条件：**一方全灭**。⚠️ 不走 `Arena` 的赛程结算（那是竞猜模式的：90 s / 兴奋圈 / 平局），
	## 见文件头 —— 这里只做"数人头"这一件事。
	if arena.alive_count(0) == 0 or arena.alive_count(1) == 0:
		_arm_battle(false)

## 判胜 + 收兵 + 切相位。
## 用户口径：**没有平局**，胜负只看"**剩余总血量**"（全灭与手动「结束战斗」同一个判据）。
## 唯一的退化情形是两边同时归零（同一帧同归于尽）——那时 `winner = -1`，界面显示「同时全灭」。
func _arm_battle(manual: bool) -> void:
	_hold_waiting = true
	_hold_manual = manual
	if camera_rig != null:
		camera_rig.close_pilot_gate()
	arena.begin_presentation_hold()


func _settle_battle(manual: bool) -> void:
	_hold_waiting = false
	arena.park_combat()
	var hp_a := arena.team_hp(0)
	var hp_b := arena.team_hp(1)
	var winner := -1
	if not is_equal_approx(hp_a, hp_b):
		winner = 0 if hp_a > hp_b else 1
	result = {
		"winner": winner,
		"hp": [int(round(hp_a)), int(round(hp_b))],
		"alive": [arena.alive_count(0), arena.alive_count(1)],
		"weight": [total_weight(0), total_weight(1)],
		"manual": manual,
	}
	phase = Phase.RESULT
	if camera_rig != null:
		camera_rig.hold_battle_view()
	phase_changed.emit(phase_name())


func _take_result_continue(event: InputEvent) -> bool:
	if phase != Phase.RESULT or get_tree().paused or not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return false
	get_viewport().set_input_as_handled()
	ScreenFade.attach(self).play(Callable(self, "roll_again"))
	return true


func _range_hint_node() -> RangeHint:
	if _range_hint == null or not is_instance_valid(_range_hint):
		_range_hint = RangeHint.new()
		_range_hint.name = "RangeHint"
		add_child(_range_hint)
	return _range_hint


func _tick_range_hint() -> void:
	var hint := _range_hint_node()
	if camera_rig != null and camera_rig.mode == CameraRig.Mode.OVERVIEW:
		hint.hide_hint()
		return
	if phase != Phase.PLACING or arena == null:
		hint.hide_hint()
		return
	if _view_mode:
		if _viewed != null and is_instance_valid(_viewed) and _viewed.alive:
			var looked := _nearest_enemy_unit(_viewed.global_position, _viewed.team)
			hint.show_hint(_viewed.global_position, _viewed.attack_reach(),
					looked.global_position if looked != null else Vector3.ZERO, looked != null)
		else:
			hint.hide_hint()
		return
	if _selected_type == "":
		hint.hide_hint()
		return
	var ground = _ground_at(get_viewport().get_mouse_position())
	if ground == null:
		hint.hide_hint()
		return
	var at: Vector3 = ground
	var team := 0 if at.x < 0.0 else 1
	var locked := _nearest_enemy_unit(at, team)
	hint.show_hint(at, _preview_reach(_selected_type),
			locked.global_position if locked != null else Vector3.ZERO, locked != null, team)


func _preview_reach(type_id: String) -> float:
	var profile := GameConfig.profile(type_id)
	var reach := float(profile.get("range", 0.0))
	var owned: Dictionary = _picked_techs.get(type_id, {})
	for tech_id in owned.keys():
		var row := GameConfig.roguelike_tech_def(type_id, String(tech_id))
		if row.has("range_bonus"):
			reach += float(row["range_bonus"])
	var beam := bool(profile.get("is_ranged", false)) or bool(profile.get("sustained_beam", false))
	if not beam:
		reach *= GameConfig.UNIT_CONTACT_RATIO
	return reach


func _nearest_enemy_unit(at: Vector3, team: int) -> Unit3D:
	var best: Unit3D = null
	var best_d := INF
	for node in arena.units:
		var other := node as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive or other.team == team:
			continue
		if other.is_burrowed() or other.is_in_shadow_form() or other.is_ember():
			continue
		var dist := at.distance_squared_to(other.global_position)
		if dist < best_d:
			best_d = dist
			best = other
	return best

# ---------------------------------------------------------------- 暂停 / 恢复（暂停菜单用）
## 与 `Game.pause_match()` 同一套语义与同一条实现路径（`MatchPause`）。
func pause_match() -> void:
	if _pause_from_ms > 0:
		return
	_pause_from_ms = Time.get_ticks_msec()
	MatchPause.pause_tree(get_tree())

func resume_match() -> void:
	var delta_ms := 0
	if _pause_from_ms > 0:
		delta_ms = Time.get_ticks_msec() - _pause_from_ms
	_pause_from_ms = 0
	MatchPause.resume_tree(get_tree())
	if delta_ms > 0:
		MatchPause.shift_deadlines(get_tree(), arena, camera_rig, delta_ms)

# ---------------------------------------------------------------- 探针（MCP 运行时观察）
func _mcp_state() -> Dictionary:
	return {
		"phase": phase_name(),
		"selected": _selected_type,
		## 「权重递增模式」开关（2026-09-25 第七轮）：探针靠它验"点了石柱卡片之后确实写穿了场地"。
		"weight_escalation": _weight_escalation,
		"weight": [total_weight(0), total_weight(1)],
		"count": [roster_of(0).size(), roster_of(1).size()],
		"alive": [arena.alive_count(0), arena.alive_count(1)] if arena != null else [0, 0],
		"hp": [int(round(arena.team_hp(0))), int(round(arena.team_hp(1)))] if arena != null else [0, 0],
		"result": result,
	}
