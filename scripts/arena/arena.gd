class_name Arena
extends Node3D
## 竞技场：场地 / 兴奋圈 / 刷兵 / 箭矢 / 胜负检测
##
## 依据：docs/bible/02_entities.md#2-实体总表、03_rules.md#1-胜负判定、04_physics.md#7-场景尺寸

signal match_ended(result: Dictionary)
signal ring_shrunk(radius: float)

const FALLOUT_Y := -3.0

## 风景配色（依据 `00_world.md#4.2`：环境一律低饱和冷灰，不许抢红 / 蓝两队的注意力，
## 也不许引入第三种高饱和色）。它们只做表现、不属于"可调数值"，因此按既有惯例留在本文件
## （`00_world.md#4.2` 的"代码落点"列本来就指向 `arena.gd#_build_environment`）。
## ⚠️ 命名沿用 `GameConfig` 里 `ARENA_SCENERY_*` 的**同一个域**，不另开 `SCENERY_*` 前缀——
## `08_naming.md#3.3` 要求"前缀取自既有域"，`ARENA_*` 是本项目一直在用的域。
const ARENA_SCENERY_COLOR_PILLAR := Color(0.44, 0.47, 0.52)   ## 冷灰，沿用文档里记的围栏色
const ARENA_SCENERY_COLOR_STAND := Color(0.34, 0.37, 0.43)    ## 看台：更深的冷灰
const ARENA_SCENERY_COLOR_ROCK := Color(0.38, 0.40, 0.44)
const ARENA_SCENERY_COLOR_TRUNK := Color(0.30, 0.28, 0.26)    ## 树干：低饱和褐灰
const ARENA_SCENERY_COLOR_LEAF := Color(0.29, 0.36, 0.33)     ## 树冠：低饱和灰绿，呼应地面色

## 说明：本节点**不保存任何可调数值**。
## 场地尺寸、出生布局、击退、三种兵的六项属性全部定义在 `GameConfig`（见 `config.gd`
## 里按功能分段的注释），这里只读取。这样只存在一处数值来源，不会出现"节点上的副本与
## GameConfig 漂移"的问题（本轮曾漂移过一次：剑盾兵/长矛兵伤害在两边不一致）。

var units: Array[Unit3D] = []
var arrows: Array[Arrow] = []
## ---- 场地尺寸（**实例字段**，2026-09-26 第六块）----
## 默认 = 全局的 `ARENA_HALF_X` / `ARENA_HALF_Z`（100 × 50 ⇒ 竞猜与沙盒**逐位不变**）；
## ⚠️ **肉鸽用自己的一套**（2026-09-26 第六块引入"按模式给"、2026-09-27 第七块把长 ×1.5 并加进南北两条布阵带：
## 150 × 111.5 ⇒ 半宽 75 / 半深 55.75）⇒ `main.gd#_build_stage()`
## 在 `add_child()` **之前**按模式写入（几何全在 `_ready()` 里建，晚一步就来不及了）。
## ⚠️ 场地内所有几何 / 边界墙 / 风景 / 出生点都读这两个字段，**不再读全局常量** ——
## 这样"一个进程里两套尺寸"才是安全的（全局常量一个字没动 ⇒ 竞猜的配平面与 §2.1 五条几何约束不受影响）。
## ⚠️ 默认值取全局值，但**不能写在字段初始值里**（那会变成 `var half_x = half_x` 自引用 ⇒
## 报 "Could not resolve member: Cyclic reference"；本批就是先踩了这一下）⇒ 放 `_init()`，
## 时机一样（都在 `main` 覆写之前），也不会把 50 / 25 这两个数抄第二遍。
var half_x: float = 50.0
var half_z: float = 25.0
var _relief_noise: FastNoiseLite
var _relief_amplitude := 0.0
var _relief_blend := 18.0
var _relief_apron := 12.0

func _init() -> void:
	half_x = GameConfig.ARENA_HALF_X
	half_z = GameConfig.ARENA_HALF_Z
## 场地上的**圆形挡弹物**（2026-09-26 肉鸽第五块：魔法盾是唯一来源；其它模式恒为空数组）。
## ⚠️ 由**玩法侧**（`Roguelike`）整体重写，场地只读不改 —— 与 `team_damage_buff` / `team_range_bonus`
## 那几个"场地字段由肉鸽写、单位每帧读"的字段同一条分工。
## ⚠️ 里面存的是**值**（`{id, center, radius, team}`），**不是活对象**：`arrow.gd` 只拿它做几何判定。
## `id` 是玩法侧单调发的编号（不随数组下标漂移），用来把"挡下的这一发"回认到具体哪一件盾。
var arrow_blockers: Array = []
## 本帧**被魔法盾挡下**的投射物：`{id, point, damage}`。
## ⚠️ `arrow.gd` 只负责**追加**、玩法侧每帧读走并清空 ⇒ 投射物**从不直接改玩法数据**
##（血量的主人始终是玩法侧；这也避免了 `arrow.gd` 反向依赖 `roguelike.gd`）。
var arrow_blocks: Array = []

## 把带「庇护」的单位写成挡弹圆。道具盾的条目留下，这一类带 `ward` 标记，每帧重写。
## 圆心在箭飞行时再读单位的当前位置，这里的 `center` 只是给没有活引用时的兜底。
func sync_unit_wards() -> void:
	var kept: Array = []
	for raw in arrow_blockers:
		var blocker: Dictionary = raw
		if not bool(blocker.get("ward", false)):
			kept.append(blocker)
	arrow_blockers = kept
	for node in units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive or not unit.has_ward():
			continue
		arrow_blockers.append({
			"id": unit.get_instance_id(),
			"center": unit.global_position,
			"radius": unit.ward_radius(),
			"team": unit.team,
			"ward": true,
			"unit": unit,
		})

## 把打在「庇护」上的记录从 `arrow_blocks` 里拿走并扣盾。道具盾的记录留着给肉鸽去扣。
func drain_ward_blocks() -> void:
	if arrow_blocks.is_empty():
		return
	var rest: Array = []
	for raw in arrow_blocks:
		var record: Dictionary = raw
		var node := instance_from_id(int(record.get("id", -1)))
		var unit := node as Unit3D
		if unit != null and is_instance_valid(unit) and unit.take_ward_damage(float(record.get("damage", 0.0))):
			continue
		rest.append(record)
	arrow_blocks = rest

## 线段有没有穿过某一面敌方盾（道具魔法盾或「庇护」）。穿过就返回最近的那个交点。
## 两端都在圆里不算穿过，跟箭的口径一样。
func shield_crossing(from_pos: Vector3, to_pos: Vector3, from_team: int) -> Dictionary:
	var best := {}
	var best_t := INF
	for raw in arrow_blockers:
		var blocker: Dictionary = raw
		var center: Vector3 = blocker["center"]
		var radius := float(blocker["radius"])
		var owner_team := int(blocker.get("team", -1))
		var owner: Variant = blocker.get("unit", null)
		if owner != null:
			if not is_instance_valid(owner):
				continue
			var ward_unit := owner as Unit3D
			if ward_unit == null or not ward_unit.has_ward():
				continue
			center = ward_unit.global_position
			radius = ward_unit.ward_radius()
			owner_team = ward_unit.team
		if owner_team == from_team:
			continue
		var hit := _segment_sphere_hit(from_pos, to_pos, center, radius)
		if hit.is_empty():
			continue
		var along := float(hit["t"])
		if along < best_t:
			best_t = along
			best = {"point": hit["point"], "id": int(blocker.get("id", -1))}
	return best

func note_shield_block(info: Dictionary, amount: float) -> void:
	arrow_blocks.append({
		"id": int(info.get("id", -1)),
		"point": info.get("point", Vector3.ZERO),
		"damage": amount,
	})

func _segment_sphere_hit(from_pos: Vector3, to_pos: Vector3, center: Vector3, radius: float) -> Dictionary:
	var step := to_pos - from_pos
	var offset := from_pos - center
	var a := step.dot(step)
	if a < 0.000001:
		return {}
	var b := 2.0 * offset.dot(step)
	var c := offset.dot(offset) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return {}
	var root := sqrt(disc)
	var t_near := (-b - root) / (2.0 * a)
	if t_near >= 0.0 and t_near <= 1.0:
		return {"point": from_pos + step * t_near, "t": t_near}
	var t_far := (-b + root) / (2.0 * a)
	if t_far >= 0.0 and t_far <= 1.0:
		return {"point": from_pos + step * t_far, "t": t_far}
	return {}

## 持续照射用：敌方魔法盾 / 「庇护」里，离 `from_pos` 最近的那一圈边缘。
## 盾不是兵，不进 `units`。边缘点在水平圆上，朝向攻击者的那一侧。
func nearest_shield_rim(from_pos: Vector3, from_team: int) -> Dictionary:
	var best := {}
	var best_gap := INF
	for raw in arrow_blockers:
		var info := _shield_rim_of(raw, from_pos, from_team)
		if info.is_empty():
			continue
		var gap := float(info["gap"])
		if gap < best_gap:
			best_gap = gap
			best = info
	return best

## 按编号取同一面盾的当前边缘。盾没了、或已经是己方的，返回空。
func shield_rim(shield_id: int, from_pos: Vector3, from_team: int) -> Dictionary:
	for raw in arrow_blockers:
		var blocker: Dictionary = raw
		if int(blocker.get("id", -1)) != shield_id:
			continue
		return _shield_rim_of(blocker, from_pos, from_team)
	return {}

func _shield_rim_of(blocker: Dictionary, from_pos: Vector3, from_team: int) -> Dictionary:
	var center: Vector3 = blocker["center"]
	var radius := float(blocker["radius"])
	var owner_team := int(blocker.get("team", -1))
	var owner: Variant = blocker.get("unit", null)
	if owner != null:
		if not is_instance_valid(owner):
			return {}
		var ward_unit := owner as Unit3D
		if ward_unit == null or not ward_unit.has_ward():
			return {}
		center = ward_unit.global_position
		radius = ward_unit.ward_radius()
		owner_team = ward_unit.team
	if owner_team == from_team or radius <= 0.0:
		return {}
	var point := _rim_toward(center, radius, from_pos)
	var flat := point - from_pos
	flat.y = 0.0
	return {"id": int(blocker.get("id", -1)), "point": point, "gap": flat.length()}

## 水平圆上离攻击者最近的点。人在圆心里时方向取世界 +X，避免零向量。
func _rim_toward(center: Vector3, radius: float, from_pos: Vector3) -> Vector3:
	var flat := Vector3(from_pos.x - center.x, 0.0, from_pos.z - center.z)
	var outward := Vector3.RIGHT
	if flat.length_squared() > 0.0001:
		outward = flat.normalized()
	return center + outward * radius

var ring: MeshInstance3D = null
var ring_radius: float = 0.0
var ring_visual_radius: float = 0.0
var match_active: bool = false
var match_start_ms: int = 0
## **沙盒战斗时钟**（2026-09-25 第七轮）：`start_skirmish()` 记下的开战时刻，0 = 没在战斗。
## ⚠️ 它与 `match_start_ms` **刻意分开**：沙盒从不启赛程（`match_active` 恒为 false），
## 而召唤石柱的技能要的是"**战斗开始后**过了多久"（用户口径"战斗开始前60s，每5s…"）。
## 借 `match_start_ms` 的话，沙盒里它永远是 0 ⇒ 石柱一辈子召唤不出东西。
var skirmish_start_ms: int = 0
## **「权重递增模式」开关**（沙盒专属，用户口径：点「召唤石柱」卡片时选是否开启）。
## ⚠️ 它由 `Sandbox.set_weight_escalation()` 写、由 `Unit3D`（石柱）只读 ——
## 单位不认识 `Sandbox`，场地是两者之间唯一的中转（同 `show_impact_dust()` 那条路）。
var summon_escalation: bool = false

# ---------------------------------------------------------------- 队伍级修正（肉鸽第三块）
## ⚠️ 这是本项目**第一处"全队状态"**：它不挂在任何单位身上，而是"单位每帧向场地问一次：我这队现在是多少倍"。
## 三个来源互相独立，取值时才合成（见下面那三个 `*_for()`）：
##   · `team_damage_buff` —— 肉鸽**右方**指挥所买的持续增益（买了就永久，**与指挥所是否被摧毁无关**）；
##   · `team_speed_bonus` / `team_range_bonus` —— **左方**指挥所的单回合增益（每回合开始清 0）；
##   · `_team_debuff_until_ms` —— 指挥所**被摧毁**后的全体减益（×0.10、5 s、**不叠加只刷新**）。
## ⚠️ 别的模式里这些数恒为"1.0 / 0.0 / 0" ⇒ 单位读到的结果与改动前**逐位相同**。
var team_damage_buff: Array = [1.0, 1.0]     ## 伤害倍率（1.0 = 无加成）
var team_speed_bonus: Array = [0.0, 0.0]     ## 移速加成 m/s（单回合）
var team_range_bonus: Array = [0.0, 0.0]     ## 射程加成 m（单回合，只作用于远程）
var _team_debuff_until_ms: Array = [0, 0]    ## 被摧毁减益的截止时刻（0 = 没有）
var _ring_step: int = 0
var _settled: bool = true
var _last_hit_ms: int = 0
var _spawn_points: Dictionary = {}      ## 选手 -> 出生点，用于掉出世界后的安全网复位
var _spawn_layout_rng := RandomNumberGenerator.new()   ## 出生点布局用的随机源
## 落点扬尘的**预建实例池**（`_build_impact_dust_pool()` 填）与"池满时覆盖哪个"的轮转指针。
## ⚠️ 它们是**常驻**的：播完只 `stop()`（隐藏 + 停 `_process`），**不销毁**。
var _impact_dusts: Array[Arrow.ImpactDust] = []
const ACID_POOL_SIZE := 8
var _acid_visuals: Array[MeshInstance3D] = []
var _acid_pools: Array = []
const FIRE_POOL_SIZE := 8
var _fire_visuals: Array[MeshInstance3D] = []
var _fire_pools: Array = []
## 同一个单位下一次还能吃火 / 酸液跳伤的时刻。多摊叠在一起时不重复结算。
var _fire_tick_ms: Dictionary = {}
var _acid_tick_ms: Dictionary = {}
const HOLY_BURST_POOL := 6
const HOLY_BURST_MS := 480
var _holy_bursts: Array[MeshInstance3D] = []
var _holy_meta: Array = []
const FLAME_BARRIER_POOL := 4
const FLAME_BARRIER_MS := 700
var _flame_barrier_pulses: Array[MeshInstance3D] = []
var _flame_barrier_meta: Array = []
const REVENGE_BURST_POOL := 4
const REVENGE_BURST_MS := 420
var _revenge_bursts: Array[MeshInstance3D] = []
var _revenge_meta: Array = []
const BULWARK_LINK_POOL := 24
var _bulwark_links: Array[MeshInstance3D] = []
const INTERCEPT_FLASH_POOL := 8
const INTERCEPT_FLASH_MS := 280
var _intercept_flashes: Array[MeshInstance3D] = []
var _intercept_until: Array[int] = []
var _impact_dust_next: int = 0
var _battle_look: Dictionary = {}
## 战斗分出胜负后的定格。到点之前继续演算；到点后本节点停掉，子节点（单位、投射物）一起停。
var presentation_frozen: bool = false
var _presentation_at_ms: int = 0
var _presentation_result: Dictionary = {}

func _ready() -> void:
	add_to_group("arena")
	ring_radius = GameConfig.RING_START_RADIUS
	ring_visual_radius = GameConfig.RING_START_RADIUS
	_spawn_layout_rng.randomize()
	_battle_look = _look_for(GameConfig.BATTLE_SCENE_PLAIN)
	_build_environment()
	_build_scenery()
	_build_ring()
	_build_impact_dust_pool()
	_build_acid_pool()
	_build_fire_pool()
	_build_holy_bursts()
	_build_flame_barrier_pulses()
	_build_revenge_bursts()
	_build_bulwark_links()
	_build_intercept_flashes()
	Events.unit_was_hit.connect(_on_any_hit)
	Events.unit_was_blocked.connect(_on_any_hit)

# ---------------------------------------------------------------- 落点扬尘的**预建池**（2026-09-25 修卡顿）
## 用户："投石车特效出现时会有卡顿" —— 根因是**每次落地都现造** 6 个 `MeshInstance3D`
## + 6 个 `TRANSPARENCY_ALPHA` 材质：比赛中途第一次渲染"网格 + 透明材质"这个组合时，
## 渲染管线要现编译着色器并初始化材质 RID ⇒ 那一帧就是肉眼可见的卡顿。
## 修法：开赛前就把一小池扬尘**建好、播完不销毁只隐藏**，运行期只改 `visible` / `scale` / `position`。
## ⚠️ 池容量 `DUST_POOL_SIZE` 取得比"同屏可能同时播的扬尘数"大：
## 投石车最快 0.30 次/秒（面板间隔 3.33 s），而一段扬尘只放 620 ms
## ⇒ 同屏同时播放的通常 ≤ 2；取 4 是给"两台投石车 + 手动调试"留余量。
## ⚠️ 池**满了直接复用最老的那个**（不新建、不排队）：宁可截断一段旧特效，也不能在战斗中分配。
const DUST_POOL_SIZE := 4

func _build_impact_dust_pool() -> void:
	for i in DUST_POOL_SIZE:
		var dust := Arrow.ImpactDust.new()
		dust.name = "ImpactDust_%d" % i
		add_child(dust)
		## ⚠️ `_ready()` 里已把 `visible` 置 false、并 `set_process` 关掉 ⇒ 空转零开销。
		## 位置在 `show_impact_dust()` 里按落点写；这里只负责把实例挂进池。
		_impact_dusts.append(dust)
	_impact_dust_next = 0

## 播一次落点扬尘：优先找**空闲的**那个，都忙就**复用轮转指针处的那个**（覆盖最旧的一段）。
## ⚠️ 全程不 `new()`、不 `add_child()`、不建材质 —— 这是"不卡顿"的前提。
## `variant` 只改 `play()` 内部的标量（整体朝向 + 各尘团起始大小），同样不新建资源。
func show_impact_dust(at: Vector3, radius: float) -> void:
	if _impact_dusts.is_empty():
		return
	var picked: Arrow.ImpactDust = null
	for dust in _impact_dusts:
		if not dust.is_playing():
			picked = dust
			break
	if picked == null:
		picked = _impact_dusts[_impact_dust_next % _impact_dusts.size()]
	_impact_dust_next += 1
	picked.play(at, radius, _impact_dust_next % 3)

func _build_acid_pool() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.32, 0.06, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.16, 0.28, 0.05)
	mat.emission_energy_multiplier = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in ACID_POOL_SIZE:
		var node := MeshInstance3D.new()
		node.name = "AcidPool_%d" % i
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		add_child(node)
		_acid_visuals.append(node)

func place_acid(at: Vector3, radius: float, ratio: float, vuln: float) -> void:
	var visual_index := _claim_ground_visual(_acid_visuals, _acid_pools, "AcidPool")
	var pos := Vector3(at.x, 0.16, at.z)
	if visual_index >= 0 and visual_index < _acid_visuals.size():
		var node := _acid_visuals[visual_index]
		node.visible = true
		node.position = pos
		node.scale = Vector3(radius, 1.0, radius)
	_acid_pools.append({
		"pos": pos,
		"radius": radius,
		"ratio": ratio,
		"vuln": vuln,
		"next_ms": Time.get_ticks_msec() + GameConfig.UNIT_GROUND_TICK_MS,
		"visual": visual_index,
	})

func _build_fire_pool() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.10, 0.03, 0.26)
	mat.emission_enabled = true
	mat.emission = Color(0.42, 0.10, 0.02)
	mat.emission_energy_multiplier = 0.40
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in FIRE_POOL_SIZE:
		var node := MeshInstance3D.new()
		node.name = "FirePool_%d" % i
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		add_child(node)
		_fire_visuals.append(node)

func place_fire(at: Vector3, radius: float, tick_damage: float, source: Unit3D) -> void:
	var visual_index := _claim_ground_visual(_fire_visuals, _fire_pools, "FirePool")
	var pos := Vector3(at.x, 0.18, at.z)
	if visual_index >= 0 and visual_index < _fire_visuals.size():
		var node := _fire_visuals[visual_index]
		node.visible = true
		node.position = pos
		node.scale = Vector3(radius, 1.0, radius)
	_fire_pools.append({
		"pos": pos,
		"radius": radius,
		"damage": tick_damage,
		"source": source,
		"next_ms": Time.get_ticks_msec() + GameConfig.UNIT_GROUND_TICK_MS,
		"until_ms": Time.get_ticks_msec() + GameConfig.UNIT_FIRE_DURATION_MS,
		"visual": visual_index,
	})

## 地面效果要留到收兵。预建的 8 块用完之后再补一块，共用已有网格，不把最早的那摊抹掉。
func _claim_ground_visual(visuals: Array[MeshInstance3D], pools: Array, pool_name: String) -> int:
	for i in visuals.size():
		var used := false
		for pool in pools:
			if int(pool.get("visual", -1)) == i:
				used = true
				break
		if not used:
			return i
	var index := visuals.size()
	var node := MeshInstance3D.new()
	node.name = "%s_%d" % [pool_name, index]
	if not visuals.is_empty():
		node.mesh = visuals[0].mesh
		node.material_override = visuals[0].material_override
	node.visible = false
	add_child(node)
	visuals.append(node)
	return index

func tick_fire() -> void:
	var now := Time.get_ticks_msec()
	var kept: Array = []
	for pool in _fire_pools:
		var until := int(pool.get("until_ms", 0))
		var due := now >= int(pool["next_ms"]) and int(pool["next_ms"]) <= until
		if due:
			pool["next_ms"] = int(pool["next_ms"]) + GameConfig.UNIT_GROUND_TICK_MS
			var pos: Vector3 = pool["pos"]
			var radius := float(pool["radius"])
			var amount := float(pool["damage"])
			var raw_source: Variant = pool.get("source")
			var source := _living_unit(raw_source)
			if source == null:
				pool["source"] = null
			for unit in units:
				var other := _living_unit(unit)
				if other == null or not other.alive or other.is_burrowed():
					continue
				var flat := other.global_position - pos
				flat.y = 0.0
				if flat.length() > radius:
					continue
				if other.has_flame_barrier():
					continue
				if not _ground_tick_ready(_fire_tick_ms, other, now):
					continue
				other.apply_hit(amount, source, Vector3.ZERO, 0.0, true)
		if now >= until:
			_hide_ground_visual(_fire_visuals, int(pool.get("visual", -1)))
			continue
		kept.append(pool)
	_fire_pools = kept

func _resolve_fan_intercepts(delta: float) -> void:
	for node in arrows.duplicate():
		if not is_instance_valid(node):
			arrows.erase(node)
			continue
		var arrow := node as Arrow
		if arrow == null or not arrow.active:
			continue
		if arrow.intercept_left <= 0:
			continue
		var from := arrow.global_position
		var vel := arrow.flight_velocity()
		if arrow.gravity > 0.0:
			vel.y -= arrow.gravity * delta
		arrow.try_instant_intercept(from, from + vel * delta)

func acid_vuln_at(at: Vector3) -> float:
	var best := 1.0
	for pool in _acid_pools:
		var pos: Vector3 = pool["pos"]
		var flat := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
		if flat.length() <= float(pool["radius"]):
			best = maxf(best, float(pool["vuln"]))
	return best

func tick_acid() -> void:
	var now := Time.get_ticks_msec()
	for pool in _acid_pools:
		if now < int(pool["next_ms"]):
			continue
		pool["next_ms"] = int(pool["next_ms"]) + GameConfig.UNIT_GROUND_TICK_MS
		var pos: Vector3 = pool["pos"]
		var radius := float(pool["radius"])
		var ratio := float(pool["ratio"])
		for unit in units:
			var other := _living_unit(unit)
			if other == null or not other.alive or other.is_burrowed():
				continue
			var flat := other.global_position - pos
			flat.y = 0.0
			if flat.length() > radius:
				continue
			if other.has_flame_barrier():
				continue
			if not _ground_tick_ready(_acid_tick_ms, other, now):
				continue
			other.apply_hit(other.max_hp * ratio, null, Vector3.ZERO, 0.0, true, false, true)

func _ground_tick_ready(book: Dictionary, unit: Unit3D, now: int) -> bool:
	var key := unit.get_instance_id()
	if now < int(book.get(key, 0)):
		return false
	book[key] = now + GameConfig.UNIT_GROUND_TICK_MS
	return true

func _hide_ground_visual(visuals: Array[MeshInstance3D], visual_index: int) -> void:
	if visual_index < 0 or visual_index >= visuals.size():
		return
	visuals[visual_index].visible = false

func _shift_tick_book(book: Dictionary, delta_ms: int) -> void:
	for key in book.keys():
		var stamp := int(book[key])
		if stamp > 0:
			book[key] = stamp + delta_ms

func _build_holy_bursts() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	mesh.rings = 28
	mesh.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.45, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in HOLY_BURST_POOL:
		var node := MeshInstance3D.new()
		node.name = "HolyBurst_%d" % i
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		add_child(node)
		_holy_bursts.append(node)
		_holy_meta.append({"until_ms": 0, "radius": 1.0})

func show_holy_burst(at: Vector3, radius: float) -> void:
	var slot := 0
	var oldest := 0
	for i in _holy_bursts.size():
		if not _holy_bursts[i].visible:
			slot = i
			break
		if int(_holy_meta[i].get("until_ms", 0)) < int(_holy_meta[oldest].get("until_ms", 0)):
			oldest = i
		slot = oldest
	var node := _holy_bursts[slot]
	node.visible = true
	node.position = Vector3(at.x, 0.14, at.z)
	node.scale = Vector3(0.4, 1.0, 0.4)
	_holy_meta[slot] = {
		"until_ms": Time.get_ticks_msec() + HOLY_BURST_MS,
		"radius": radius,
		"born_ms": Time.get_ticks_msec(),
	}

func tick_holy() -> void:
	var now := Time.get_ticks_msec()
	for i in _holy_bursts.size():
		var node := _holy_bursts[i]
		if not node.visible:
			continue
		var until := int(_holy_meta[i].get("until_ms", 0))
		if now >= until:
			node.visible = false
			continue
		var born := int(_holy_meta[i].get("born_ms", now))
		var t := clampf(float(now - born) / float(HOLY_BURST_MS), 0.0, 1.0)
		var radius := float(_holy_meta[i].get("radius", 4.0))
		var grown := lerpf(0.35, radius, t)
		node.scale = Vector3(grown, 1.0, grown)

func _build_ring_pool(store: Array[MeshInstance3D], meta: Array, count: int, node_name: String, color: Color, emission: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	mesh.rings = 28
	mesh.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 1.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in count:
		var node := MeshInstance3D.new()
		node.name = "%s_%d" % [node_name, i]
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		store.append(node)
		meta.append({"until_ms": 0, "radius": 1.0})

func _build_flame_barrier_pulses() -> void:
	_build_ring_pool(_flame_barrier_pulses, _flame_barrier_meta, FLAME_BARRIER_POOL, "FlameBarrierPulse",
			Color(1.0, 0.42, 0.08, 0.62), Color(1.0, 0.28, 0.04))

func _build_revenge_bursts() -> void:
	_build_ring_pool(_revenge_bursts, _revenge_meta, REVENGE_BURST_POOL, "RevengeBurst",
			Color(0.32, 0.05, 0.48, 0.7), Color(0.45, 0.08, 0.7))

func _show_ring(nodes: Array[MeshInstance3D], meta: Array, at: Vector3, radius: float, duration_ms: int) -> void:
	var slot := 0
	var oldest := 0
	for i in nodes.size():
		if not nodes[i].visible:
			slot = i
			break
		if int(meta[i].get("until_ms", 0)) < int(meta[oldest].get("until_ms", 0)):
			oldest = i
		slot = oldest
	var node := nodes[slot]
	node.visible = true
	node.position = Vector3(at.x, 0.14, at.z)
	node.scale = Vector3(0.4, 1.0, 0.4)
	var now := Time.get_ticks_msec()
	meta[slot] = {"until_ms": now + duration_ms, "radius": radius, "born_ms": now}

func _tick_ring(nodes: Array[MeshInstance3D], meta: Array, duration_ms: int) -> void:
	var now := Time.get_ticks_msec()
	for i in nodes.size():
		var node := nodes[i]
		if not node.visible:
			continue
		var until := int(meta[i].get("until_ms", 0))
		if now >= until:
			node.visible = false
			continue
		var born := int(meta[i].get("born_ms", now))
		var t := clampf(float(now - born) / float(maxi(duration_ms, 1)), 0.0, 1.0)
		var radius := float(meta[i].get("radius", 4.0))
		var grown := lerpf(0.35, radius, t)
		node.scale = Vector3(grown, 1.0, grown)

func _hide_ring_bursts() -> void:
	for node in _holy_bursts:
		node.visible = false
	for node in _flame_barrier_pulses:
		node.visible = false
	for node in _revenge_bursts:
		node.visible = false

func show_flame_barrier(at: Vector3, radius: float) -> void:
	_show_ring(_flame_barrier_pulses, _flame_barrier_meta, at, radius, FLAME_BARRIER_MS)

func tick_flame_barrier() -> void:
	_tick_ring(_flame_barrier_pulses, _flame_barrier_meta, FLAME_BARRIER_MS)

func show_revenge_burst(at: Vector3, radius: float) -> void:
	_show_ring(_revenge_bursts, _revenge_meta, at, radius, REVENGE_BURST_MS)

func tick_revenge() -> void:
	_tick_ring(_revenge_bursts, _revenge_meta, REVENGE_BURST_MS)

func _build_bulwark_links() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.06, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.9, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in BULWARK_LINK_POOL:
		var node := MeshInstance3D.new()
		node.name = "BulwarkLink_%d" % i
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		add_child(node)
		_bulwark_links.append(node)

func show_bulwark_links(segments: Array) -> void:
	for i in _bulwark_links.size():
		var node := _bulwark_links[i]
		if i >= segments.size():
			node.visible = false
			continue
		var seg: Dictionary = segments[i]
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var flat := b - a
		flat.y = 0.0
		var dist := flat.length()
		if dist < 0.2:
			node.visible = false
			continue
		node.visible = true
		node.global_position = Vector3((a.x + b.x) * 0.5, 0.12, (a.z + b.z) * 0.5)
		node.look_at(node.global_position + flat, Vector3.UP)
		node.scale = Vector3(1.0, 1.0, dist)

func _build_intercept_flashes() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.95, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.9, 1.0)
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in INTERCEPT_FLASH_POOL:
		var node := MeshInstance3D.new()
		node.name = "InterceptFlash_%d" % i
		node.mesh = mesh
		node.material_override = mat
		node.visible = false
		add_child(node)
		_intercept_flashes.append(node)
		_intercept_until.append(0)

func show_intercept_flash(at: Vector3) -> void:
	var slot := 0
	for i in _intercept_flashes.size():
		if not _intercept_flashes[i].visible:
			slot = i
			break
		if _intercept_until[i] < _intercept_until[slot]:
			slot = i
	var node := _intercept_flashes[slot]
	node.visible = true
	node.global_position = at
	_intercept_until[slot] = Time.get_ticks_msec() + INTERCEPT_FLASH_MS

func tick_intercept_fx() -> void:
	var now := Time.get_ticks_msec()
	for i in _intercept_flashes.size():
		if _intercept_flashes[i].visible and now >= _intercept_until[i]:
			_intercept_flashes[i].visible = false

func hide_intercept_flashes() -> void:
	for node in _intercept_flashes:
		node.visible = false

## 清道夫：抹掉这个点附近的地面效果。现在只有酸液；燃烧地面和减速油以后加在这里。
func clear_ground_near(at: Vector3, radius: float) -> void:
	var kept: Array = []
	for pool in _acid_pools:
		var pos: Vector3 = pool["pos"]
		var flat := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
		if flat.length() <= radius:
			var visual := int(pool.get("visual", -1))
			if visual >= 0 and visual < _acid_visuals.size():
				_acid_visuals[visual].visible = false
			continue
		kept.append(pool)
	_acid_pools = kept
	var fire_kept: Array = []
	for pool in _fire_pools:
		var pos: Vector3 = pool["pos"]
		var flat := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
		if flat.length() <= radius:
			var visual := int(pool.get("visual", -1))
			if visual >= 0 and visual < _fire_visuals.size():
				_fire_visuals[visual].visible = false
			continue
		fire_kept.append(pool)
	_fire_pools = fire_kept

func clear_acid() -> void:
	_acid_pools.clear()
	for node in _acid_visuals:
		if is_instance_valid(node):
			node.visible = false
	_fire_pools.clear()
	for node in _fire_visuals:
		if is_instance_valid(node):
			node.visible = false
	_fire_tick_ms.clear()
	_acid_tick_ms.clear()

func _on_any_hit(_unit: Node3D) -> void:
	_last_hit_ms = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	## 兴奋圈已废止（2026-10-23，I-14）。网格还在，但永不显示。
	if ring != null:
		ring.visible = false

var _unit_cells: Dictionary = {}
var _empty_cell: Array = []   ## 空格子的共用返回值，不许往里面加人
var _open_cells: Array = [{}, {}]   ## 每队一份：格子 → 能被锁定的人（已去掉潜地 / 影子 / 余烬）
var _open_keys: Array = [[], []]    ## 每队有人的那些格子，索敌时不再翻空格
var _blast_queue: Array = []
var _storms: Array = []
var _nearest_of: Dictionary = {}
var _nearest_solved: bool = false

func _physics_process(delta: float) -> void:
	_tick_presentation_hold()
	if presentation_frozen:
		return
	# 押注阶段也要兜底：防止有人在开赛前就掉出世界
	_catch_fallen_units()
	## 布兵 / 押注还没点火：不算最近的人，也不重填格子。开战（赛程或沙盒互殴）才查。
	if match_active or skirmish_start_ms > 0:
		rebuild_unit_grid()
		rebuild_storms()
		solve_nearest()
		tick_blasts()
		## 父节点先于单位和箭。快弹在自己那一帧的位移里跨进 16 m 时，扇子兵这一下已经落下。
		_resolve_fan_intercepts(delta)
	if not match_active:
		return
	var elapsed := Time.get_ticks_msec() - match_start_ms
	_clear_excited()
	if elapsed >= GameConfig.MATCH_LIMIT_MS:
		_finish(_judge())
		return
	# 僵持检测：双方都打不到对方（例如最后两个远程互相追不上）时判平局
	if elapsed > GameConfig.STALEMATE_MS and Time.get_ticks_msec() - _last_hit_ms > GameConfig.STALEMATE_MS:
		_finish({
			"winner": -1, "reason": "stalemate",
			"alive": [alive_count(0), alive_count(1)],
			"hp": [int(round(team_hp(0))), int(round(team_hp(1)))],
			"duration_ms": elapsed,
		})
		return
	var alive_a := alive_count(0)
	var alive_b := alive_count(1)
	if alive_a == 0 or alive_b == 0:
		_finish(_judge())

# ---------------------------------------------------------------- 场地
func _build_environment() -> void:
	# 地板铺得远大于场地：被击退或被挤到边界外时也不会"脚下没有地面"。
	# 已修 bug：2a（见 99_decisions.md#修-选手穿地掉落）
	var floor_node := StaticBody3D.new()
	floor_node.name = "Floor"
	floor_node.collision_layer = 1
	floor_node.collision_mask = 0
	floor_node.physics_material_override = _phys(1.0, 0.0)
	var floor_size := Vector3(
		(half_x + GameConfig.FLOOR_MARGIN) * 2.0,
		GameConfig.FLOOR_THICK,
		(half_z + GameConfig.FLOOR_MARGIN) * 2.0)
	var floor_top := -GameConfig.FLOOR_THICK * 0.5
	floor_node.add_child(_box_shape(Vector3(0.0, floor_top, 0.0), floor_size))
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Surface"
	var floor_mesh_res := BoxMesh.new()
	floor_mesh_res.size = floor_size
	floor_mesh.mesh = floor_mesh_res
	floor_mesh.position = Vector3(0.0, floor_top, 0.0)
	floor_mesh.material_override = _mat(_battle_look["floor"], 1.0)
	floor_node.add_child(floor_mesh)
	add_child(floor_node)

	# 场地边界轮廓（替代原来的高墙外观：只画一圈地面上的细线）
	# ⚠️ 肉鸽第七块起肉鸽的 `half_z` 把南北两条"前进布阵带"也算进来了（= 55.75）⇒ 这一圈画在**最外沿**；
	#    主场地与带子之间那条分界线由 `Roguelike` 自己画（它才知道带子在哪，见 `_build_grid()`）。
	var edge_color := Color(0.80, 0.82, 0.86)
	_add_edge("Edge_north", Vector3(0.0, 0.02, -half_z), Vector3(half_x * 2.0, 0.03, 0.14), edge_color)
	_add_edge("Edge_south", Vector3(0.0, 0.02, half_z), Vector3(half_x * 2.0, 0.03, 0.14), edge_color)
	_add_edge("Edge_west", Vector3(-half_x, 0.02, 0.0), Vector3(0.14, 0.03, half_z * 2.0), edge_color)
	_add_edge("Edge_east", Vector3(half_x, 0.02, 0.0), Vector3(0.14, 0.03, half_z * 2.0), edge_color)

	# 中线
	var mid := MeshInstance3D.new()
	mid.name = "CenterLine"
	var mid_mesh := BoxMesh.new()
	mid_mesh.size = Vector3(0.12, 0.03, half_z * 2.0)
	mid.mesh = mid_mesh
	mid.position = Vector3(0.0, 0.02, 0.0)
	mid.material_override = _mat(Color(0.85, 0.85, 0.80), 0.6, true)
	add_child(mid)

	# 两队出发区染色
	for team in [0, 1]:
		var zone := MeshInstance3D.new()
		zone.name = "Zone_%s" % ("a" if team == 0 else "b")
		var zone_mesh := BoxMesh.new()
		zone_mesh.size = Vector3(3.4, 0.03, half_z * 2.0)
		zone.mesh = zone_mesh
		var sign_x := GameConfig.team_spawn_sign(team)
		zone.position = Vector3(sign_x * (half_x - 1.9), 0.02, 0.0)
		zone.material_override = _mat(GameConfig.team_color(team), 0.75, true)
		add_child(zone)

	# 边界：只保留碰撞，不再渲染高墙（观感上"没有围墙"，但选手与箭矢不会跑出场地）
	# 已改：任务 3-(2) 去掉高墙，见 99_decisions.md#去掉视觉高墙
	# ⚠️ 肉鸽第七块起 `half_z` 含南北两条布阵带 ⇒ 这两道墙自然落在带子的外沿（带子在场地内，不另加墙）。
	_add_wall("Bounds_north", Vector3(0.0, 0.0, -(half_z + GameConfig.WALL_THICK * 0.5)),
			Vector3(half_x * 2.0 + GameConfig.WALL_THICK * 2.0, GameConfig.WALL_HEIGHT, GameConfig.WALL_THICK))
	_add_wall("Bounds_south", Vector3(0.0, 0.0, half_z + GameConfig.WALL_THICK * 0.5),
			Vector3(half_x * 2.0 + GameConfig.WALL_THICK * 2.0, GameConfig.WALL_HEIGHT, GameConfig.WALL_THICK))
	_add_wall("Bounds_west", Vector3(-(half_x + GameConfig.WALL_THICK * 0.5), 0.0, 0.0),
			Vector3(GameConfig.WALL_THICK, GameConfig.WALL_HEIGHT, half_z * 2.0 + GameConfig.WALL_THICK * 2.0))
	_add_wall("Bounds_east", Vector3(half_x + GameConfig.WALL_THICK * 0.5, 0.0, 0.0),
			Vector3(GameConfig.WALL_THICK, GameConfig.WALL_HEIGHT, half_z * 2.0 + GameConfig.WALL_THICK * 2.0))

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	light.light_energy = 1.6
	light.light_color = _battle_look["sun"]
	light.shadow_enabled = true
	add_child(light)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _battle_look["ambient"]
	e.ambient_light_energy = 1.8
	e.fog_enabled = bool(_battle_look.get("fog_enabled", true))
	e.fog_light_color = _battle_look["fog"]
	e.fog_density = float(_battle_look["fog_density"])
	e.fog_sky_affect = 0.2
	env.environment = e
	add_child(env)
	_paint_sky(e)

	var cam := Camera3D.new()
	cam.name = "SpectatorCamera"
	cam.current = true
	cam.position = Vector3(0.0, 26.0, 24.0)
	cam.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
	add_child(cam)

# ---------------------------------------------------------------- 风景（纯装饰，全在场地外）
## 依据 `00_world.md#4`：低饱和环境衬托高饱和阵营；风景只负责"场地之外还有一个世界"的
## 氛围与尺度参照，**不参与任何玩法**。
##
## ⚠️ 两条硬约束（改这段之前先读 `GameConfig` 的"场地风景"段）：
##  1. **一件都不带碰撞体** —— 这里只用 MeshInstance3D 拼，绝不 new StaticBody3D。
##     带上碰撞就会挂进 world 层（collision_layer = 1），而选手的贴地射线是 mask = 1
##     （`unit3d.gd#_grounded`）→ 风景会被当成地面；箭矢也会插在风景上（`04_physics.md#8.1`）。
##  2. **一件都不压进场地** —— 最近边距边界墙 ≥ `ARENA_SCENERY_CLEARANCE`。
##     南侧和另外三边用同一套景物。场地外的起伏只是地面外观，不另加碰撞体。
##
## 节点名沿用 `08_naming.md#3.1`：`Scenery_<种类>_<方位|序号>`，后缀一律用下划线。
## 从设置里勾上的场景抽一个，换地面色、天空和场地外的风景。
## 竞猜在每一局开始时调；沙盒和生存在进入模式时调一次。
## 灰场地（一个都没勾）走现在这套柱子、看台、树和石头。
func roll_battle_scene() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	use_battle_scene(GameConfig.pick_battle_scene(rng))

func battle_scene_id() -> String:
	return String(_battle_look.get("scene_id", GameConfig.BATTLE_SCENE_PLAIN))

func use_battle_scene(scene_id: String) -> void:
	if scene_id == "":
		scene_id = GameConfig.BATTLE_SCENE_PLAIN
	_battle_look = _look_for(scene_id)
	_paint_battle_scene()
	_clear_scenery()
	_build_scenery()

func capture_match_clock(frozen_ms: int) -> Dictionary:
	var elapsed := 0
	var since_hit := 0
	if match_active:
		elapsed = frozen_ms - match_start_ms
		since_hit = frozen_ms - _last_hit_ms
	return {
		"match_active": match_active,
		"elapsed_ms": elapsed,
		"since_hit_ms": since_hit,
		"ring_step": _ring_step,
		"ring_radius": ring_radius,
	}

func restore_match_clock(data: Dictionary, now_ms: int) -> void:
	match_active = bool(data.get("match_active", false))
	_settled = not match_active
	_ring_step = int(data.get("ring_step", 0))
	ring_radius = float(data.get("ring_radius", GameConfig.RING_START_RADIUS))
	ring_visual_radius = ring_radius
	if match_active:
		match_start_ms = now_ms - int(data.get("elapsed_ms", 0))
		_last_hit_ms = now_ms - int(data.get("since_hit_ms", 0))

func capture_units(frozen_ms: int) -> Array:
	var kept: Array[Unit3D] = []
	for unit in units:
		if unit != null and is_instance_valid(unit):
			kept.append(unit)
	var index_of := {}
	for i in kept.size():
		index_of[kept[i]] = i
	var rows: Array = []
	for unit in kept:
		var row := unit.capture_for_save(frozen_ms)
		var target_i := -1
		if unit.target != null and index_of.has(unit.target):
			target_i = int(index_of[unit.target])
		row["target"] = target_i
		rows.append(row)
	return rows

func restore_units(rows: Array, now_ms: int) -> void:
	settle()
	var spawned: Array[Unit3D] = []
	for raw in rows:
		var row: Dictionary = raw
		var unit := spawn_unit(int(row.get("team", 0)), String(row.get("type_id", "sword")),
				Vector3(float(row.get("x", 0.0)), 0.0, float(row.get("z", 0.0))),
				float(row.get("yaw", 0.0)))
		if unit == null:
			continue
		unit.apply_for_save(row, now_ms)
		spawned.append(unit)
	for i in spawned.size():
		if spawned[i] == null:
			continue
		var row: Dictionary = rows[i]
		var target_i := int(row.get("target", -1))
		if target_i < 0 or target_i >= spawned.size() or spawned[target_i] == null:
			continue
		spawned[i].target = spawned[target_i]

func _paint_battle_scene() -> void:
	var surface := get_node_or_null("Floor/Surface") as MeshInstance3D
	if surface != null and surface.material_override is StandardMaterial3D:
		(surface.material_override as StandardMaterial3D).albedo_color = _battle_look["floor"]
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.ambient_light_color = _battle_look["ambient"]
		env_node.environment.fog_enabled = bool(_battle_look.get("fog_enabled", true))
		env_node.environment.fog_light_color = _battle_look["fog"]
		env_node.environment.fog_density = float(_battle_look["fog_density"])
		_paint_sky(env_node.environment)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = _battle_look["sun"]

func _clear_scenery() -> void:
	var old: Array = []
	for child in get_children():
		if String(child.name).begins_with("Scenery_"):
			old.append(child)
	for child in old:
		child.free()

func _look_for(scene_id: String) -> Dictionary:
	var plain := {
		"floor": Color(0.46, 0.50, 0.47),
		"sky": Color(0.10, 0.12, 0.16),
		"ambient": Color(0.70, 0.76, 0.88),
		"fog": Color(0.12, 0.14, 0.18),
		"fog_density": 0.004,
		"sun": Color(1.0, 0.97, 0.92),
		"pillar": ARENA_SCENERY_COLOR_PILLAR,
		"stand": ARENA_SCENERY_COLOR_STAND,
		"rock": ARENA_SCENERY_COLOR_ROCK,
		"trunk": ARENA_SCENERY_COLOR_TRUNK,
		"leaf": ARENA_SCENERY_COLOR_LEAF,
		"tree_count": -1,
		"rock_count": -1,
		"fog_enabled": true,
		"tree_ring": false,
		"tree_variety": false,
		"cactus_count": 0,
		"peak_count": 0,
		"glacier_count": 0,
		"snowman_count": 0,
		"building_count": 0,
		"clouds": false,
		"scene_id": "plain",
	}
	var look := plain.duplicate()
	look["scene_id"] = scene_id
	match scene_id:
		"forest":
			look["floor"] = Color(0.30, 0.46, 0.24)
			look["sky"] = Color(0.36, 0.62, 0.94)
			look["ambient"] = Color(0.78, 0.86, 0.72)
			look["fog_enabled"] = false
			look["sun"] = Color(1.0, 0.98, 0.90)
			look["pillar"] = Color(0.36, 0.26, 0.16)
			look["stand"] = Color(0.30, 0.34, 0.22)
			look["rock"] = Color(0.40, 0.42, 0.36)
			look["trunk"] = Color(0.32, 0.20, 0.12)
			look["leaf"] = Color(0.18, 0.50, 0.16)
			look["tree_count"] = 160
			look["tree_ring"] = true
			look["tree_variety"] = true
			look["tree_clusters"] = true
			look["bush_count"] = 24
			look["clouds"] = true
			look["rock_count"] = 8
		"mountain":
			look["floor"] = Color(0.42, 0.40, 0.38)
			look["sky"] = Color(0.42, 0.66, 0.95)
			look["ambient"] = Color(0.78, 0.82, 0.88)
			look["fog_enabled"] = false
			look["sun"] = Color(0.96, 0.97, 1.0)
			look["pillar"] = Color(0.50, 0.50, 0.52)
			look["stand"] = Color(0.38, 0.38, 0.40)
			look["rock"] = Color(0.45, 0.44, 0.42)
			look["trunk"] = Color(0.30, 0.28, 0.26)
			look["leaf"] = Color(0.34, 0.40, 0.32)
			look["tree_count"] = 4
			look["tree_variety"] = false
			look["clouds"] = true
			look["peak_count"] = 8
			look["rock_count"] = 36
		"desert":
			look["floor"] = Color(0.72, 0.58, 0.34)
			look["sky"] = Color(0.78, 0.62, 0.40)
			look["ambient"] = Color(0.95, 0.82, 0.62)
			look["fog"] = Color(0.86, 0.70, 0.46)
			look["fog_density"] = 0.005
			look["sun"] = Color(1.0, 0.90, 0.72)
			look["rock"] = Color(0.62, 0.46, 0.28)
			look["trunk"] = Color(0.42, 0.30, 0.16)
			look["leaf"] = Color(0.48, 0.36, 0.18)
			look["tree_count"] = 0
			look["rock_count"] = 6
			look["cactus_count"] = 32
		"snow":
			look["floor"] = Color(0.50, 0.55, 0.61)
			look["sky"] = Color(0.62, 0.74, 0.86)
			look["ambient"] = Color(0.66, 0.72, 0.79)
			look["fog"] = Color(0.60, 0.67, 0.74)
			look["fog_density"] = 0.007
			look["sun"] = Color(0.90, 0.94, 1.0)
			look["rock"] = Color(0.70, 0.76, 0.82)
			look["trunk"] = Color(0.28, 0.24, 0.22)
			look["leaf"] = Color(0.70, 0.82, 0.78)
			look["tree_count"] = 22
			look["north_tree_count"] = 18
			look["rock_count"] = 16
			look["glacier_count"] = 8
			look["north_glacier_count"] = 6
			look["snowman_count"] = 0
		"city":
			look["floor"] = Color(0.32, 0.33, 0.36)
			look["sky"] = Color(0.38, 0.64, 0.94)
			look["ambient"] = Color(0.78, 0.84, 0.92)
			look["fog_enabled"] = false
			look["sun"] = Color(1.0, 0.98, 0.94)
			look["pillar"] = Color(0.45, 0.46, 0.50)
			look["stand"] = Color(0.28, 0.30, 0.34)
			look["rock"] = Color(0.40, 0.36, 0.30)
			look["trunk"] = Color(0.24, 0.28, 0.22)
			look["leaf"] = Color(0.20, 0.38, 0.24)
			look["tree_count"] = 48
			look["tree_variety"] = true
			look["tree_rows"] = true
			look["clouds"] = true
			look["building_count"] = 20
			look["rock_count"] = 10
	return look

func _scenery_tree_count() -> int:
	var count := int(_battle_look.get("tree_count", -1))
	if count < 0:
		return int(GameConfig.ARENA_SCENERY_TREE_COUNT)
	return count

func _scenery_rock_count() -> int:
	var count := int(_battle_look.get("rock_count", -1))
	if count < 0:
		return int(GameConfig.ARENA_SCENERY_ROCK_COUNT)
	return count

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.ARENA_SCENERY_SEED        ## 固定种子：同一种场景的布局每次一样
	var taken: Array = []                            ## 已落地的道具位置，用于维持最小间距
	_prepare_relief()
	_build_relief_mesh()
	_build_banners(taken)
	_build_peaks(rng, taken)
	_build_buildings(rng, taken)
	_build_glaciers(rng, taken)
	_build_trees(rng, taken)
	_build_rocks(rng, taken)
	_build_cacti(rng, taken)
	_build_bushes(rng, taken)
	_build_clouds(rng)

## 队旗：东西两端各一面，用队伍色（不变量 I-35 的视觉锚点）
func _build_banners(taken: Array) -> void:
	var height: float = GameConfig.ARENA_SCENERY_BANNER_HEIGHT
	var x: float = half_x + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + 1.0
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.13
	pole_mesh.bottom_radius = 0.17
	pole_mesh.height = height
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 0
	var pole_mat := _mat(_battle_look["pillar"], 0.90)
	for team in [0, 1]:
		var sign_x := GameConfig.team_spawn_sign(team)
		var flag := Node3D.new()
		flag.name = "Scenery_banner_%s" % ("east" if sign_x > 0.0 else "west")
		add_child(flag)
		var pole := MeshInstance3D.new()
		pole.name = "Pole"
		pole.mesh = pole_mesh
		pole.material_override = pole_mat
		pole.position = Vector3(sign_x * x, height * 0.5, 0.0)
		flag.add_child(pole)
		var cloth := MeshInstance3D.new()
		cloth.name = "Cloth"
		var cloth_mesh := BoxMesh.new()
		cloth_mesh.size = Vector3(0.10, 2.6, 1.9)
		cloth.mesh = cloth_mesh
		cloth.material_override = _mat(GameConfig.team_color(team), 0.85)
		cloth.position = Vector3(sign_x * x, height - 1.7, -1.05)   ## 旗面沿 z 侧挂，不探进场地
		flag.add_child(cloth)
		taken.append(Vector3(sign_x * x, 0.0, 0.0))

## 树：森林按种类分成几片，城市沿边排齐，其余场景四面都放，南侧不另做一套。
func _build_trees(rng: RandomNumberGenerator, taken: Array) -> void:
	var total: float = GameConfig.ARENA_SCENERY_TREE_HEIGHT
	var trunk_height: float = total * 0.40
	var crown_height: float = total - trunk_height
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.20
	trunk_mesh.bottom_radius = 0.30
	trunk_mesh.height = trunk_height
	trunk_mesh.radial_segments = 8
	trunk_mesh.rings = 0
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.35
	crown_mesh.bottom_radius = 1.90
	crown_mesh.height = crown_height
	crown_mesh.radial_segments = 12
	crown_mesh.rings = 0
	var trunk_mat := _mat(_battle_look["trunk"], 0.95)
	var leaf_mat := _mat(_battle_look["leaf"], 0.95)
	var tree_count := _scenery_tree_count()
	if tree_count <= 0:
		return
	if bool(_battle_look.get("tree_rows", false)):
		_place_tree_rows(rng, taken, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
		return
	if bool(_battle_look.get("tree_clusters", false)):
		_place_tree_clusters(rng, taken, tree_count, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
		return
	var placed := 0
	placed += _place_north_pines(rng, taken, placed, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
	var scattered := 0
	for _try in tree_count * 16:
		if scattered >= tree_count:
			break
		var pos := _sample_outfield(rng, true, 1.6)
		if not _spot_is_free(pos, taken):
			continue
		var kind := "pine"
		if bool(_battle_look.get("tree_variety", false)):
			kind = _tree_kind(rng)
		var tree := _add_tree(pos, kind, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat, placed)
		if String(_battle_look.get("scene_id", "")) == "snow":
			_jostle_tree(tree, Vector3(pos.x, _ground_y(pos.x, pos.z), pos.z), rng)
		taken.append(pos)
		placed += 1
		scattered += 1

func _place_tree_rows(rng: RandomNumberGenerator, taken: Array,
		trunk_height: float, crown_height: float, trunk_mesh: Mesh, crown_mesh: Mesh,
		trunk_mat: Material, leaf_mat: Material) -> void:
	var placed := 0
	var end_outs: Array[float] = [8.0, 27.0, 45.0]
	for out in end_outs:
		placed += _place_tree_line(rng, taken, -1.0, true, out, placed, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
		placed += _place_tree_line(rng, taken, 1.0, true, out, placed, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
	var side_outs: Array[float] = [8.0, 30.0]
	for out in side_outs:
		placed += _place_tree_line(rng, taken, -1.0, false, out, placed, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)
		placed += _place_tree_line(rng, taken, 1.0, false, out, placed, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat)

## 一整排只用一种树。南北各三排，东西各两排。
func _place_tree_line(rng: RandomNumberGenerator, taken: Array, side: float, along_x: bool, out: float, index_from: int,
		trunk_height: float, crown_height: float, trunk_mesh: Mesh, crown_mesh: Mesh,
		trunk_mat: Material, leaf_mat: Material) -> int:
	var kind := "pine"
	if bool(_battle_look.get("tree_variety", false)):
		kind = _tree_kind(rng)
	var stride := 12.0
	var limit := half_z * 0.7
	if along_x:
		limit = half_x - 4.0
	var use := int(floor(limit * 2.0 / stride)) + 1
	use = maxi(use, 2)
	var base := GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + out
	var placed := 0
	for i in use:
		var along := -limit + (limit * 2.0) * float(i) / float(use - 1)
		var pos := Vector3(along, 0.0, side * (half_z + base))
		if not along_x:
			pos = Vector3(side * (half_x + base), 0.0, along)
		if not _point_is_outfield(pos, 1.2) or not _spot_is_clear(pos, taken, 6.5):
			continue
		_add_tree(pos, kind, trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat, index_from + placed)
		taken.append(pos)
		placed += 1
	return placed

## 四种树各占场地外的一个象限，树与树至少隔 6.5 m。外缘留一圈空地。
func _place_tree_clusters(rng: RandomNumberGenerator, taken: Array, tree_count: int,
		trunk_height: float, crown_height: float, trunk_mesh: Mesh, crown_mesh: Mesh,
		trunk_mat: Material, leaf_mat: Material) -> void:
	var kinds: Array[String] = ["pine", "maple", "ginkgo", "cherry"]
	var gap := 6.5
	var base_n := int(tree_count / kinds.size())
	var leftover := tree_count - base_n * kinds.size()
	var placed := 0
	for sector in kinds.size():
		var want := base_n
		if sector < leftover:
			want += 1
		var got := 0
		for _try in want * 80:
			if got >= want:
				break
			var pos := _sample_outfield(rng, true, 1.6)
			if _ring_sector(pos) != sector or not _forest_band(pos) or not _spot_is_clear(pos, taken, gap):
				continue
			_add_tree(pos, kinds[sector], trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat, placed)
			taken.append(pos)
			got += 1
			placed += 1

func _ring_sector(pos: Vector3) -> int:
	var ang := atan2(pos.x, -pos.z)
	if ang < 0.0:
		ang += TAU
	return int(floor(ang / (PI * 0.5))) % 4

## 外缘留一圈空地，树不铺到地板尽头。
func _forest_band(pos: Vector3) -> bool:
	var reach_x := half_x + GameConfig.FLOOR_MARGIN - 16.0
	var reach_z := half_z + GameConfig.FLOOR_MARGIN - 16.0
	return absf(pos.x) <= reach_x and absf(pos.z) <= reach_z

## 雪地北侧补松树，位置散开，不排成直线。北是 −Z。
func _place_north_pines(rng: RandomNumberGenerator, taken: Array, index_from: int,
		trunk_height: float, crown_height: float, trunk_mesh: Mesh, crown_mesh: Mesh,
		trunk_mat: Material, leaf_mat: Material) -> int:
	var count := int(_battle_look.get("north_tree_count", 0))
	if count <= 0:
		return 0
	var inner := half_z + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + 8.0
	var outer := half_z + GameConfig.FLOOR_MARGIN * 0.75
	var limit_x := half_x + GameConfig.FLOOR_MARGIN * 0.42
	var placed := 0
	for _try in count * 40:
		if placed >= count:
			break
		var pos := Vector3(rng.randf_range(-limit_x, limit_x), 0.0, -rng.randf_range(inner, outer))
		if not _point_is_outfield(pos, 1.4) or not _spot_is_clear(pos, taken, 6.5):
			continue
		var tree := _add_tree(pos, "pine", trunk_height, crown_height, trunk_mesh, crown_mesh, trunk_mat, leaf_mat, index_from + placed)
		_jostle_tree(tree, Vector3(pos.x, _ground_y(pos.x, pos.z), pos.z), rng)
		taken.append(pos)
		placed += 1
	return placed

func _point_is_outfield(pos: Vector3, pad: float) -> bool:
	var inner_x: float = half_x + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + pad
	var inner_z: float = half_z + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + pad
	var outer_x: float = half_x + GameConfig.FLOOR_MARGIN - 2.0
	var outer_z: float = half_z + GameConfig.FLOOR_MARGIN - 2.0
	if absf(pos.x) > outer_x or absf(pos.z) > outer_z:
		return false
	return absf(pos.x) >= inner_x or absf(pos.z) >= inner_z

## 岩石：方块，四面都有。沙漠只放少量，山脉大小差得更开。
func _build_rocks(rng: RandomNumberGenerator, taken: Array) -> void:
	var scene_id := String(_battle_look.get("scene_id", "plain"))
	var base := Vector3(2.6, 1.4, 2.2)
	var scale_min := 0.75
	var scale_max := 1.35
	if scene_id == "desert":
		base = Vector3(1.5, 1.35, 1.45)
	elif scene_id == "mountain":
		scale_min = 0.45
		scale_max = 1.75
	var rock_mat := _mat(_battle_look["rock"], 0.95)
	var rock_count := _scenery_rock_count()
	var inner_x: float = half_x + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE
	var inner_z: float = half_z + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE
	var outer_x: float = half_x + GameConfig.FLOOR_MARGIN - 2.0
	var outer_z: float = half_z + GameConfig.FLOOR_MARGIN - 2.0
	var placed := 0
	for _try in maxi(rock_count, 1) * 12:
		if placed >= rock_count:
			break
		var pos := _ring_point(rng, inner_x, outer_x, inner_z, outer_z)
		if not _spot_is_free(pos, taken):
			continue
		var scale := rng.randf_range(scale_min, scale_max)
		var rock := MeshInstance3D.new()
		rock.name = "Scenery_rock_%d" % placed
		var mesh := BoxMesh.new()
		mesh.size = base * scale
		rock.mesh = mesh
		rock.material_override = rock_mat
		var ground_y := _ground_y(pos.x, pos.z)
		rock.position = pos + Vector3(0.0, ground_y + base.y * scale * 0.42, 0.0)
		rock.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
		add_child(rock)
		taken.append(pos)
		placed += 1

func _tree_kind(rng: RandomNumberGenerator) -> String:
	var kinds := ["pine", "maple", "ginkgo", "cherry"]
	return String(kinds[rng.randi_range(0, kinds.size() - 1)])

func _crown_color(kind: String) -> Color:
	match kind:
		"willow":
			return Color(0.28, 0.55, 0.28)
		"maple":
			return Color(0.86, 0.40, 0.10)
		"ginkgo":
			return Color(0.93, 0.78, 0.16)
		"cherry":
			return Color(0.94, 0.55, 0.68)
		_:
			return _battle_look["leaf"]

func _add_tree(pos: Vector3, kind: String, trunk_height: float, crown_height: float,
		trunk_mesh: Mesh, crown_mesh: Mesh, trunk_mat: Material, leaf_mat: Material, index: int) -> Node3D:
	pos.y = _ground_y(pos.x, pos.z)
	var tree := Node3D.new()
	tree.name = "Scenery_tree_%d" % index
	add_child(tree)
	var stem := trunk_height
	if kind == "maple" or kind == "cherry":
		stem = 2.55
		_add_stem(tree, pos, stem, 0.2, 0.36, trunk_mat)
	elif kind == "ginkgo":
		stem = 2.3
		_add_stem(tree, pos, stem, 0.2, 0.36, trunk_mat)
	else:
		var trunk := MeshInstance3D.new()
		trunk.name = "Trunk"
		trunk.mesh = trunk_mesh
		trunk.material_override = trunk_mat
		trunk.position = Vector3(pos.x, pos.y + stem * 0.5, pos.z)
		tree.add_child(trunk)
	var leaf := _crown_color(kind)
	var crown_mat := _mat(leaf, 0.9)
	match kind:
		"maple":
			_add_lobed_crown(tree, pos, stem, crown_mat, false)
		"cherry":
			_add_lobed_crown(tree, pos, stem, crown_mat, true)
		"ginkgo":
			_add_ginkgo_crown(tree, pos, stem, crown_mat)
		_:
			_add_pine_cones(tree, pos, stem, crown_height, leaf_mat)
	return tree

## 雪地松树绕着树根转一下、歪一点、高矮差一点，避免同一棵树复制一排。
func _jostle_tree(tree: Node3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var scale := rng.randf_range(0.78, 1.24)
	var lean := rng.randf_range(-0.16, 0.16)
	var axis := Vector3(cos(yaw), 0.0, -sin(yaw))
	var basis := Basis(axis, lean) * Basis(Vector3.UP, yaw)
	for child in tree.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var rel := (node.position - base) * scale
		node.basis = basis
		node.scale = Vector3(scale, scale, scale)
		node.position = base + basis * rel

func _add_stem(tree: Node3D, pos: Vector3, height: float, top_radius: float, bottom_radius: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = mesh
	trunk.material_override = mat
	trunk.position = Vector3(pos.x, pos.y + height * 0.5, pos.z)
	tree.add_child(trunk)

func _add_pine_cones(tree: Node3D, pos: Vector3, stem: float, crown_height: float, leaf_mat: Material) -> void:
	var layers := 4
	var base_y := stem * 0.7
	var step := crown_height * 0.30
	for cone_i in layers:
		var extra := MeshInstance3D.new()
		extra.name = "Cone_%d" % cone_i
		var cone := CylinderMesh.new()
		var t := float(cone_i) / float(layers - 1)
		cone.top_radius = 0.06
		cone.bottom_radius = lerpf(2.2, 0.55, t)
		cone.height = lerpf(crown_height * 0.58, crown_height * 0.40, t)
		cone.radial_segments = 6
		extra.mesh = cone
		extra.material_override = leaf_mat
		extra.position = Vector3(pos.x, pos.y + base_y + float(cone_i) * step, pos.z)
		tree.add_child(extra)

func _add_lobed_crown(tree: Node3D, pos: Vector3, stem: float, mat: Material, compact: bool) -> void:
	var offsets: Array[Vector3] = [
		Vector3(0.0, 1.55, 0.0),
		Vector3(1.45, 0.2, 0.25),
		Vector3(-1.3, 0.95, -0.4),
		Vector3(0.3, 0.35, 1.4),
		Vector3(-0.2, 1.25, -1.2),
	]
	var spread := 1.16 if compact else 1.0
	var lift := 0.9 if compact else 1.0
	for lobe_i in offsets.size():
		var lobe := MeshInstance3D.new()
		lobe.name = "Lobe_%d" % lobe_i
		var mesh := SphereMesh.new()
		var radius := 1.25
		if lobe_i == 0:
			radius = 1.15
		elif lobe_i == 2:
			radius = 1.55
		mesh.radius = radius
		mesh.height = radius * 2.05
		lobe.mesh = mesh
		lobe.material_override = mat
		var off := offsets[lobe_i]
		lobe.position = Vector3(pos.x + off.x * spread, pos.y + stem + off.y * lift, pos.z + off.z * spread)
		tree.add_child(lobe)

func _add_ginkgo_crown(tree: Node3D, pos: Vector3, stem: float, mat: Material) -> void:
	var blade_i := 0
	var layers: Array[Dictionary] = [
		{"y": 0.2, "reach": 0.55, "length": 1.45, "pitch": 0.65, "count": 5, "rise": 0.28},
		{"y": 0.75, "reach": 1.05, "length": 1.9, "pitch": 0.22, "count": 6, "rise": 0.22},
		{"y": 1.3, "reach": 0.75, "length": 1.55, "pitch": -0.18, "count": 5, "rise": 0.2},
		{"y": 1.8, "reach": 0.35, "length": 1.15, "pitch": -0.55, "count": 4, "rise": 0.18},
	]
	for layer in layers:
		var count := int(layer["count"])
		var reach := float(layer["reach"])
		var length := float(layer["length"])
		var pitch := float(layer["pitch"])
		var y := float(layer["y"])
		var rise := float(layer["rise"])
		for i in count:
			var blade := MeshInstance3D.new()
			blade.name = "Blade_%d" % blade_i
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.48, rise, length)
			blade.mesh = mesh
			blade.material_override = mat
			var yaw := float(i) / float(count) * TAU + y
			var outward := Vector3(sin(yaw), 0.0, cos(yaw))
			var lift := y + float(i % 2) * 0.24
			blade.position = Vector3(pos.x, pos.y + stem + lift, pos.z) + outward * reach
			blade.rotation = Vector3(pitch, yaw, 0.0)
			tree.add_child(blade)
			blade_i += 1

## 场地外取样。四面都放，靠近默认机位的一侧和其余几边用同一套景物。
func _sample_outfield(rng: RandomNumberGenerator, allow_south: bool, pad: float) -> Vector3:
	var inner_x: float = half_x + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + pad
	var inner_z: float = half_z + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + pad
	var outer_x: float = half_x + GameConfig.FLOOR_MARGIN - pad - 2.0
	var outer_z: float = half_z + GameConfig.FLOOR_MARGIN - pad - 2.0
	outer_x = maxf(outer_x, inner_x + 4.0)
	outer_z = maxf(outer_z, inner_z + 4.0)
	for _try in 16:
		var pos := _ring_point(rng, inner_x, outer_x, inner_z, outer_z)
		if allow_south or pos.z <= half_z:
			return pos
	return Vector3(rng.randf_range(-outer_x, outer_x), 0.0, -(inner_z + outer_z) * 0.5)

func _build_peaks(rng: RandomNumberGenerator, taken: Array) -> void:
	var count := int(_battle_look.get("peak_count", 0))
	if count <= 0:
		return
	var mat := _mat(_battle_look["rock"], 0.95)
	var placed := 0
	for _try in count * 12:
		if placed >= count:
			break
		var pos := _seat(_sample_outfield(rng, true, 10.0))
		if not _spot_is_clear(pos, taken, 16.0):
			continue
		var height := rng.randf_range(16.0, 28.0)
		var foot := rng.randf_range(7.0, 11.0)
		var peak := Node3D.new()
		peak.name = "Scenery_peak_%d" % placed
		add_child(peak)
		var yaw := rng.randf_range(0.0, TAU)
		_add_slope(peak, "Mass", pos, height, foot, mat, Vector3(0.08, yaw, -0.12))
		_add_slope(peak, "Spur_0", pos + Vector3(cos(yaw) * foot * 0.34, 0.0, sin(yaw) * foot * 0.34),
			height * 0.62, foot * 0.58, mat, Vector3(-0.22, yaw + 0.6, 0.18))
		_add_slope(peak, "Spur_1", pos + Vector3(cos(yaw + 2.2) * foot * 0.3, 0.0, sin(yaw + 2.2) * foot * 0.3),
			height * 0.46, foot * 0.42, mat, Vector3(0.16, yaw + 1.4, -0.2))
		for facet_i in 3:
			var facet := MeshInstance3D.new()
			facet.name = "Facet_%d" % facet_i
			var box := BoxMesh.new()
			box.size = Vector3(foot * rng.randf_range(0.32, 0.55), height * rng.randf_range(0.34, 0.58), foot * 0.26)
			facet.mesh = box
			facet.material_override = mat
			var fang := yaw + float(facet_i) * 2.15
			facet.position = pos + Vector3(cos(fang) * foot * 0.2, height * 0.3, sin(fang) * foot * 0.2)
			facet.rotation = Vector3(rng.randf_range(-0.45, 0.35), fang, rng.randf_range(-0.5, 0.5))
			peak.add_child(facet)
		taken.append(pos)
		placed += 1

func _add_slope(peak: Node3D, node_name: String, pos: Vector3, height: float, foot: float, mat: Material, tilt: Vector3) -> void:
	var lowest := _lowest_ground(pos.x, pos.z, foot)
	var lean := sqrt(tilt.x * tilt.x + tilt.z * tilt.z)
	var bottom := pos.y - height * 0.08
	var extra := maxf(0.0, bottom - (lowest - foot * sin(lean) - 0.6))
	var slope := MeshInstance3D.new()
	slope.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = foot * 0.04
	mesh.bottom_radius = foot
	mesh.height = height + extra
	mesh.radial_segments = 4
	slope.mesh = mesh
	slope.material_override = mat
	slope.position = pos + Vector3(0.0, height * 0.42 - extra * 0.5, 0.0)
	slope.rotation = tilt
	peak.add_child(slope)

## 山脚范围内地面的最低点。只用来把山体接到地上，不改起伏。
func _lowest_ground(x: float, z: float, radius: float) -> float:
	var lowest := _ground_y(x, z)
	for ring in 2:
		var reach := radius if ring == 1 else radius * 0.55
		for i in 8:
			var ang := TAU * float(i) / 8.0
			lowest = minf(lowest, _ground_y(x + cos(ang) * reach, z + sin(ang) * reach))
	return lowest

func _build_buildings(rng: RandomNumberGenerator, taken: Array) -> void:
	if int(_battle_look.get("building_count", 0)) <= 0:
		return
	var placed := 0
	var end_outs: Array[float] = [18.0, 36.0, 54.0]
	for out in end_outs:
		placed += _place_building_row(rng, taken, -1.0, true, placed, out)
		placed += _place_building_row(rng, taken, 1.0, true, placed, out)
	var side_outs: Array[float] = [18.0, 40.0]
	for out in side_outs:
		placed += _place_building_row(rng, taken, -1.0, false, placed, out)
		placed += _place_building_row(rng, taken, 1.0, false, placed, out)

func _place_building_row(rng: RandomNumberGenerator, taken: Array, side: float, along_x: bool, index_from: int, out: float) -> int:
	var stride := 15.0
	var limit := half_z * 0.62
	if along_x:
		limit = half_x - 8.0
	var use := int(floor(maxf(limit, stride) * 2.0 / stride)) + 1
	use = maxi(use, 2)
	var base := GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + out
	var placed := 0
	for i in use:
		var along := -limit + (limit * 2.0) * float(i) / float(maxi(use - 1, 1))
		var pos := Vector3(along, 0.0, side * (half_z + base))
		if not along_x:
			pos = Vector3(side * (half_x + base), 0.0, along)
		if not _point_is_outfield(pos, 4.0) or not _spot_is_clear(pos, taken, stride - 0.4):
			continue
		var height := rng.randf_range(9.0, 18.0)
		## 默认机位在南边。这一侧的楼太高会挡住场地近端。
		if along_x and side > 0.0:
			height = rng.randf_range(3.2, 6.0)
		_add_building(pos, 7.2, 6.4, height, rng, index_from + placed)
		taken.append(pos)
		placed += 1
	return placed

func _add_building(pos: Vector3, width: float, depth: float, height: float, rng: RandomNumberGenerator, index: int) -> void:
	pos = _seat(pos)
	var block := Node3D.new()
	block.name = "Scenery_building_%d" % index
	add_child(block)
	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(width, height, depth)
	wall.mesh = wall_mesh
	var wall_color: Color = _battle_look["pillar"]
	if rng.randf() < 0.5:
		wall_color = wall_color.lightened(rng.randf_range(0.0, 0.08))
	else:
		wall_color = wall_color.darkened(rng.randf_range(0.0, 0.08))
	wall.material_override = _mat(wall_color, 0.9)
	wall.position = pos + Vector3(0.0, height * 0.5, 0.0)
	block.add_child(wall)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(width * 1.06, 0.6, depth * 1.06)
	roof.mesh = roof_mesh
	roof.material_override = _mat(_battle_look["stand"], 0.85)
	roof.position = pos + Vector3(0.0, height + 0.3, 0.0)
	block.add_child(roof)

func _build_glaciers(rng: RandomNumberGenerator, taken: Array) -> void:
	var count := int(_battle_look.get("glacier_count", 0))
	var north_count := int(_battle_look.get("north_glacier_count", 0))
	if count <= 0 and north_count <= 0:
		return
	var mat := _mat(Color(0.72, 0.88, 0.96), 0.25)
	var placed := _place_north_glaciers(rng, taken, mat, north_count)
	var scattered := 0
	for _try in maxi(count, 1) * 12:
		if scattered >= count:
			break
		var pos := _seat(_sample_outfield(rng, true, 6.0))
		if not _spot_is_clear(pos, taken, 12.0):
			continue
		_add_glacier(pos, rng, mat, placed)
		taken.append(pos)
		placed += 1
		scattered += 1

## 雪地北侧一排冰川，排在北侧松树后面。
func _place_north_glaciers(rng: RandomNumberGenerator, taken: Array, mat: Material, count: int) -> int:
	if count <= 0:
		return 0
	var placed := 0
	var out := 48.0
	var z := -(half_z + GameConfig.WALL_THICK + GameConfig.ARENA_SCENERY_CLEARANCE + out)
	var limit := half_x * 0.9
	for i in count:
		var x := -limit + (limit * 2.0) * float(i) / float(maxi(count - 1, 1))
		x += rng.randf_range(-2.0, 2.0)
		var pos := _seat(Vector3(x, 0.0, z + rng.randf_range(-3.0, 3.0)))
		if not _point_is_outfield(pos, 6.0) or not _spot_is_clear(pos, taken, 16.0):
			continue
		_add_glacier(pos, rng, mat, placed)
		taken.append(pos)
		placed += 1
	return placed

func _add_glacier(pos: Vector3, rng: RandomNumberGenerator, mat: Material, index: int) -> void:
	var height := rng.randf_range(11.0, 18.0)
	var foot := rng.randf_range(5.5, 9.0)
	var ice := Node3D.new()
	ice.name = "Scenery_glacier_%d" % index
	add_child(ice)
	_add_ice_prism(ice, "Base", pos, height * 0.58, foot, mat, rng.randf_range(0.0, TAU))
	_add_ice_prism(ice, "Mid", pos + Vector3(0.3, height * 0.26, -0.2), height * 0.36, foot * 0.58, mat, rng.randf_range(0.0, TAU))
	_add_ice_prism(ice, "Tip", pos + Vector3(-0.2, height * 0.46, 0.25), height * 0.24, foot * 0.32, mat, rng.randf_range(0.0, TAU))
	var shard := MeshInstance3D.new()
	shard.name = "Shard"
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(foot * 0.42, height * 0.32, foot * 0.7)
	shard.mesh = shard_mesh
	shard.material_override = mat
	shard.position = pos + Vector3(foot * 0.22, height * 0.14, 0.0)
	shard.rotation = Vector3(0.18, rng.randf_range(0.0, TAU), -0.22)
	ice.add_child(shard)

func _add_ice_prism(ice: Node3D, node_name: String, pos: Vector3, height: float, foot: float, mat: Material, yaw: float) -> void:
	var part := MeshInstance3D.new()
	part.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = foot * 0.18
	mesh.bottom_radius = foot
	mesh.height = height
	mesh.radial_segments = 5
	part.mesh = mesh
	part.material_override = mat
	part.position = pos + Vector3(0.0, height * 0.42, 0.0)
	part.rotation.y = yaw
	ice.add_child(part)

func _build_cacti(rng: RandomNumberGenerator, taken: Array) -> void:
	var count := int(_battle_look.get("cactus_count", 0))
	if count <= 0:
		return
	var mat := _mat(Color(0.22, 0.48, 0.24), 0.85)
	var placed := 0
	for _try in count * 12:
		if placed >= count:
			break
		var pos := _seat(_sample_outfield(rng, true, 0.8))
		if not _spot_is_free(pos, taken):
			continue
		var south := pos.z > half_z
		var height := 2.2 if south else rng.randf_range(3.0, 5.2)
		var cactus := Node3D.new()
		cactus.name = "Scenery_cactus_%d" % placed
		add_child(cactus)
		var trunk := MeshInstance3D.new()
		trunk.name = "Trunk"
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.58
		trunk_mesh.bottom_radius = 0.72
		trunk_mesh.height = height
		trunk_mesh.radial_segments = 8
		trunk.mesh = trunk_mesh
		trunk.material_override = mat
		trunk.position = pos + Vector3(0.0, height * 0.5, 0.0)
		cactus.add_child(trunk)
		for arm_i in 2:
			var arm := MeshInstance3D.new()
			arm.name = "Arm_%d" % arm_i
			var arm_mesh := CylinderMesh.new()
			var arm_len := 1.05 if south else rng.randf_range(1.25, 1.7)
			arm_mesh.top_radius = 0.26
			arm_mesh.bottom_radius = 0.32
			arm_mesh.height = arm_len
			arm_mesh.radial_segments = 6
			arm.mesh = arm_mesh
			arm.material_override = mat
			var side := -1.0 if arm_i == 0 else 1.0
			var arm_y := height * (0.5 if arm_i == 0 else 0.68)
			arm.position = pos + Vector3(side * 0.42, arm_y, 0.0)
			arm.rotation_degrees = Vector3(0.0, rng.randf_range(-25.0, 25.0), side * 58.0)
			cactus.add_child(arm)
		taken.append(pos)
		placed += 1

## 太阳画在天空贴图上，跟着方向光的来向。方向光本身仍叫 `Sun`。
func _paint_sky(env: Environment) -> void:
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = _make_sun_panorama()
	var sky := Sky.new()
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

func _sun_sky_direction() -> Vector3:
	var toward := Vector3(-0.48, 0.76, -0.44)
	var light := get_node_or_null("Sun") as DirectionalLight3D
	if light != null:
		toward = light.global_transform.basis.z
		if toward.y < 0.2:
			toward = -toward
	if toward.y < 0.2:
		toward = Vector3(-0.48, 0.76, -0.44)
	return toward.normalized()

func _make_sun_panorama() -> Texture2D:
	var width := 768
	var height := 384
	var sky_color: Color = _battle_look["sky"]
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(sky_color)
	var dir := _sun_sky_direction()
	var phi := atan2(dir.x, dir.z)
	if phi < 0.0:
		phi += TAU
	var cu := int(phi / TAU * float(width))
	var cv := int(acos(clampf(dir.y, -1.0, 1.0)) / PI * float(height))
	var disc := 0.055
	var halo := 0.26
	var reach := int(halo / TAU * float(width)) + 4
	var core := Color(1.0, 0.98, 0.86)
	var mid := Color(1.0, 0.84, 0.42)
	for y in range(maxi(cv - reach, 0), mini(cv + reach, height)):
		for x in range(cu - reach, cu + reach):
			var xx := x % width
			if xx < 0:
				xx += width
			var u := (float(xx) + 0.5) / float(width)
			var v := (float(y) + 0.5) / float(height)
			var ang := acos(clampf(_panorama_direction(u, v).dot(dir), -1.0, 1.0))
			if ang >= halo:
				continue
			var color := sky_color.lerp(mid, pow(1.0 - ang / halo, 1.7))
			if ang < disc:
				color = core
			elif ang < disc * 2.4:
				color = core.lerp(mid, (ang - disc) / (disc * 1.4))
			img.set_pixel(xx, y, color)
	return ImageTexture.create_from_image(img)

func _panorama_direction(u: float, v: float) -> Vector3:
	var phi := u * TAU
	var theta := v * PI
	var horiz := sin(theta)
	return Vector3(sin(phi) * horiz, cos(theta), cos(phi) * horiz)

## 城市以外，场地外的地面平滑起伏。碰撞地板仍是平的，这层只是外观。
func _prepare_relief() -> void:
	var scene_id := String(_battle_look.get("scene_id", "plain"))
	if scene_id == "city":
		_relief_amplitude = 0.0
		_relief_blend = 18.0
		_relief_apron = 12.0
		_relief_noise = null
		return
	_relief_amplitude = 5.2
	_relief_blend = 18.0
	_relief_apron = 12.0
	if scene_id == "mountain":
		_relief_amplitude = 16.0
		_relief_blend = 32.0
	var noise := FastNoiseLite.new()
	noise.seed = int(GameConfig.ARENA_SCENERY_SEED)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.35
	_relief_noise = noise

func _ground_y(x: float, z: float) -> float:
	if _relief_amplitude <= 0.0 or _relief_noise == null:
		return 0.0
	var dx := maxf(absf(x) - half_x, 0.0)
	var dz := maxf(absf(z) - half_z, 0.0)
	if dx <= 0.0 and dz <= 0.0:
		return 0.0
	var dist := Vector2(dx, dz).length()
	if dist <= _relief_apron:
		return 0.0
	var blend := smoothstep(0.0, _relief_blend, dist - _relief_apron)
	return _relief_noise.get_noise_2d(x, z) * _relief_amplitude * blend

func _seat(pos: Vector3) -> Vector3:
	return Vector3(pos.x, _ground_y(pos.x, pos.z), pos.z)

func _build_relief_mesh() -> void:
	var surface := get_node_or_null("Floor/Surface") as MeshInstance3D
	if _relief_amplitude <= 0.0:
		if surface != null:
			surface.visible = true
		return
	if surface != null:
		surface.visible = false
	var margin := GameConfig.FLOOR_MARGIN
	var x0 := -(half_x + margin)
	var x1 := half_x + margin
	var z0 := -(half_z + margin)
	var z1 := half_z + margin
	var step := 4.0
	var nx := int(ceil((x1 - x0) / step))
	var nz := int(ceil((z1 - z0) / step))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var ax := x0 + step * float(ix)
			var az := z0 + step * float(iz)
			var bx := minf(ax + step, x1)
			var bz := minf(az + step, z1)
			_add_relief_quad(tool, ax, az, bx, bz)
	tool.generate_normals()
	var ground := MeshInstance3D.new()
	ground.name = "Scenery_ground"
	ground.mesh = tool.commit()
	ground.material_override = _mat(_battle_look["floor"], 1.0)
	add_child(ground)

func _add_relief_quad(tool: SurfaceTool, x0: float, z0: float, x1: float, z1: float) -> void:
	var y00 := _ground_y(x0, z0)
	var y10 := _ground_y(x1, z0)
	var y11 := _ground_y(x1, z1)
	var y01 := _ground_y(x0, z1)
	tool.add_vertex(Vector3(x0, y00, z0))
	tool.add_vertex(Vector3(x1, y10, z0))
	tool.add_vertex(Vector3(x1, y11, z1))
	tool.add_vertex(Vector3(x0, y00, z0))
	tool.add_vertex(Vector3(x1, y11, z1))
	tool.add_vertex(Vector3(x0, y01, z1))

func _build_bushes(rng: RandomNumberGenerator, taken: Array) -> void:
	var count := int(_battle_look.get("bush_count", 0))
	if count <= 0:
		return
	var mat := _mat((_battle_look["leaf"] as Color).darkened(0.12), 0.9)
	var placed := 0
	for _try in count * 14:
		if placed >= count:
			break
		var pos := _seat(_sample_outfield(rng, true, 0.6))
		if not _spot_is_free(pos, taken):
			continue
		var bush := Node3D.new()
		bush.name = "Scenery_bush_%d" % placed
		add_child(bush)
		for sprig_i in 5:
			var sprig := MeshInstance3D.new()
			sprig.name = "Sprig_%d" % sprig_i
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = rng.randf_range(0.2, 0.38)
			cone.height = rng.randf_range(0.55, 1.05)
			cone.radial_segments = 5
			sprig.mesh = cone
			sprig.material_override = mat
			var ang := float(sprig_i) / 5.0 * TAU
			sprig.position = pos + Vector3(cos(ang) * 0.26, cone.height * 0.42, sin(ang) * 0.26)
			sprig.rotation = Vector3(0.4, ang, 0.0)
			bush.add_child(sprig)
		taken.append(pos)
		placed += 1

func _build_clouds(rng: RandomNumberGenerator) -> void:
	if not bool(_battle_look.get("clouds", false)):
		return
	var mat := _mat(Color(0.96, 0.97, 0.98), 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var span_x: float = half_x + GameConfig.FLOOR_MARGIN * 0.65
	var span_z: float = half_z + GameConfig.FLOOR_MARGIN * 0.45
	for index in 12:
		var cloud := Node3D.new()
		cloud.name = "Scenery_cloud_%d" % index
		cloud.position = Vector3(
			rng.randf_range(-span_x, span_x),
			rng.randf_range(34.0, 62.0),
			rng.randf_range(-span_z, span_z * 0.35))
		add_child(cloud)
		for puff_i in 3:
			var puff := MeshInstance3D.new()
			puff.name = "Puff_%d" % puff_i
			var mesh := SphereMesh.new()
			var radius := rng.randf_range(3.5, 7.0)
			mesh.radius = radius
			mesh.height = radius * 1.15
			puff.mesh = mesh
			puff.material_override = mat
			puff.position = Vector3(float(puff_i - 1) * radius * 0.8, rng.randf_range(-0.6, 0.6), 0.0)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(puff)

## 候选点是否离所有已放置道具都足够远（不够远就宁可不放，避免两件叠在一起）
func _spot_is_free(pos: Vector3, taken: Array) -> bool:
	return _spot_is_clear(pos, taken, GameConfig.ARENA_SCENERY_MIN_GAP)

func _spot_is_clear(pos: Vector3, taken: Array, gap: float) -> bool:
	var flat := Vector3(pos.x, 0.0, pos.z)
	for other in taken:
		var there := other as Vector3
		if flat.distance_to(Vector3(there.x, 0.0, there.z)) < gap:
			return false
	return true

## 在"内矩形之外、外矩形之内"的环形带里随机取一点（= 风景可用区）
func _ring_point(rng: RandomNumberGenerator, inner_x: float, outer_x: float, inner_z: float, outer_z: float) -> Vector3:
	var x := rng.randf_range(-outer_x, outer_x)
	var z := rng.randf_range(-outer_z, outer_z)
	if absf(x) < inner_x and absf(z) < inner_z:
		## 落进场地了：沿随机一个方向推到该侧环带的中线上
		if rng.randf() < 0.5:
			x = (inner_x + outer_x) * 0.5 * signf(x if x != 0.0 else 1.0)
		else:
			z = (inner_z + outer_z) * 0.5 * signf(z if z != 0.0 else 1.0)
	return Vector3(x, 0.0, z)

## 兴奋圈：可视化 + 边界计算（收圈节奏见 docs/bible/01_core_loop.md）
func _build_ring() -> void:
	ring = MeshInstance3D.new()
	ring.name = "ExciteRing"
	var mesh := CylinderMesh.new()
	mesh.top_radius = GameConfig.RING_START_RADIUS
	mesh.bottom_radius = GameConfig.RING_START_RADIUS
	mesh.height = GameConfig.RING_HEIGHT
	mesh.radial_segments = GameConfig.RING_SEGMENTS
	mesh.cap_top = false
	mesh.cap_bottom = false
	ring.mesh = mesh
	ring.position = Vector3(0.0, GameConfig.RING_HEIGHT * 0.5, 0.0)
	ring.visible = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.35, 0.25, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.40, 0.25)
	mat.emission_energy_multiplier = 1.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	add_child(ring)

func _shrink_ring() -> void:
	_ring_step += 1
	ring_radius = maxf(GameConfig.RING_MIN_RADIUS, GameConfig.RING_START_RADIUS - float(_ring_step) * GameConfig.RING_SHRINK_STEP)
	ring.visible = true
	ring_shrunk.emit(ring_radius)

# ---------------------------------------------------------------- 刷兵 / 箭矢
## 在**己方后半段**成簇刷新（同兵种扎堆、允许其他兵种穿插），不再排成一排。
## 布局算法在 GameConfig.make_spawn_layout（数值只出现在那一处）。
func spawn_roster(team: int, roster: Array) -> void:
	var layout: Array = GameConfig.make_spawn_layout(roster, team, _spawn_layout_rng)
	var side := "A" if team == 0 else "B"
	# 出生朝向：让每队都面朝对面。约定见不变量 I-30（正面 = 自身 -Z）与 I-35（0 队出生在 −X = 西）。
	#   yaw = -π/2 → -Z 转向 +X（0 队在西侧，朝对面即 +X）
	#   yaw = +π/2 → -Z 转向 -X（1 队在东侧，朝对面即 -X）
	# ⚠️ 修 bug：早期版本两个符号都写反了，导致两队出生时背对背。
	# 2026-09-18：改为**从出生侧推导**（`sign * π/2`），换边时朝向自动跟着走，不再各写一个常数。
	var facing := GameConfig.team_spawn_sign(team) * PI * 0.5
	for i in roster.size():
		var type_id := String(roster[i])
		var unit := Unit3D.new()
		unit.name = "Unit%s_%s_%d" % [side, type_id, i]
		unit.setup(team, type_id)
		unit.tree_exiting.connect(_on_unit_exiting.bind(unit))
		add_child(unit)
		var spot: Vector3 = layout[i]
		unit.global_position = Vector3(spot.x, GameConfig.SPAWN_HEIGHT, spot.z)
		unit.rotation.y = facing
		units.append(unit)
		_spawn_points[unit] = unit.global_position
		Events.unit_spawned.emit(unit)

func _on_unit_exiting(unit: Unit3D) -> void:
	## 尸体淡出后会自动 queue_free，这里同步把引用摘掉，避免留下失效对象
	units.erase(unit)
	_spawn_points.erase(unit)
	var key := unit.get_instance_id()
	_fire_tick_ms.erase(key)
	_acid_tick_ms.erase(key)

## 安全网：万一还有选手掉到地板以下（穿模 / 被挤出世界），把它放回出生点。
## 修 bug 2a 的第二道保险，见 99_decisions.md#修-选手穿地掉落
func _catch_fallen_units() -> void:
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if unit.global_position.y >= FALLOUT_Y:
			continue
		var back: Vector3 = _spawn_points.get(unit, Vector3(0.0, 0.5, 0.0))
		unit.global_position = back + Vector3(0.0, 0.30, 0.0)
		unit.velocity = Vector3.ZERO

func spawn_arrow(shooter: Unit3D, target: Unit3D) -> void:
	if shooter == null or target == null:
		return
	_launch_aimed_shot(shooter, target, target.shot_aim_point())

## 沿准星射，不锁人。`target` 传空 ⇒ 弹道不预判，飞向 `aim_point`。
func spawn_arrow_along(shooter: Unit3D, aim_point: Vector3) -> void:
	if shooter == null:
		return
	_launch_aimed_shot(shooter, null, aim_point)

func _launch_aimed_shot(shooter: Unit3D, target: Unit3D, to: Vector3) -> void:
	var from := shooter.global_position + Vector3(0.0, 1.25, 0.0) - shooter.global_transform.basis.z * 0.5
	## 投射物参数全部来自 shooter 的 PROFILE（2026-09-18 R2：箭矢 / 石弹 / 弩箭共用这一个实体）
	var p: Dictionary = GameConfig.profile(shooter.type_id)
	var arrow := Arrow.new()
	arrow.shooter = shooter
	arrow.team = shooter.team
	var aid_damage := float(shooter.aid_mods.get("damage_mult", 1.0))
	arrow.damage = GameConfig.hit_damage(shooter.type_id) * shooter.tech_damage_mult() * aid_damage
	## ⚠️ 尾乘 `tech_damage_mult()`（2026-09-27 第十二轮「精英猎手」）：**远程的伤害加成必须在这里乘**
	## ——近战走 `Unit3D._outgoing_damage()`、远程走这一行，两处各乘一次、不会重复。
	## 没有科技时它恒为 1.0 ⇒ 别的模式与改动前逐位相同。
	## 溅射伤害（2026-09-19）：只有投石车写了这个字段，其余兵种取 0 ⇒ 走"全体吃 damage"的老路。
	arrow.splash_damage = float(p.get("splash_damage", 0.0)) * GameConfig.HIT_ATK_MULT * aid_damage
	arrow.dir = (to - from).normalized()
	arrow.kind = String(p.get("projectile", "arrow"))
	arrow.aoe_radius = float(p.get("aoe_radius", 0.0))
	arrow.knockback = float(p.get("knockback", 0.0))
	arrow.knockback_damage = float(p.get("knockback_damage", 0.0))
	arrow.ignores_shield = bool(p.get("ignores_shield", false))
	## 穿透额度（2026-09-25 火枪兵）：只有它的 PROFILE 写了 `pierce`，其余兵种取 0 ⇒ 老行为逐位不变。
	arrow.pierce = int(p.get("pierce", 0)) + int(shooter.aid_mods.get("pierce_add", 0))
	match arrow.kind:
		"stone":
			arrow.speed = GameConfig.UNIT_STONE_SPEED
			arrow.gravity = GameConfig.UNIT_STONE_GRAVITY
			arrow.dir = _aim_ballistic(from, to, target, arrow.speed, arrow.gravity)
		"longbow_arrow":
			## 长弓手（2026-09-25 新增）：**同一条抛物线弹道解**，只是速度更快、不落地炸开。
			## ⚠️ 与石弹共用 `_solve_ballistic()`（同一条式子、同一套夹取与迭代），
			## 区别只在"打中一个就停"（`aoe_radius` = 0）与箭矢网格 —— 命中模型与石弹**分道**，
			## 但弹道数学不重复实现（重复实现必然漂移）。
			arrow.speed = GameConfig.UNIT_LONGBOW_ARROW_SPEED
			arrow.gravity = GameConfig.UNIT_LONGBOW_ARROW_GRAVITY
			arrow.dir = _aim_ballistic(from, to, target, arrow.speed, arrow.gravity)
		"shortbow_arrow":
			## 短弓手（**2026-09-25 大改**，用户："短弓手箭矢速度变为长弓手的四分之三""短弓手箭矢应有抛物线"）：
			## 从"直线 22 m/s、不预判"改成**抛物线 + 落点预判**，与长弓共用同一个 `_aim_ballistic()`。
			## ⇒ 两种弓手的弹道**从此同源**，只差速度（39 对 52）与下坠（13 对 16）。
			arrow.speed = GameConfig.UNIT_SHORTBOW_ARROW_SPEED
			arrow.gravity = GameConfig.UNIT_SHORTBOW_ARROW_GRAVITY
			arrow.dir = _aim_ballistic(from, to, target, arrow.speed, arrow.gravity)
		"bolt":
			## 弩车（**2026-09-25** 用户："弩车、短弓手新增预判"）：弩箭本身是 180 m/s 的**直线**弹，
			## 不适用抛物线解；但**落点预判**同样成立 —— 用"射程 ÷ 速度"估滞空、按目标速度提前量瞄准。
			## ⚠️ 180 m/s 下 44 m 只需 0.24 s，提前量很小，但**不是零**（对 7 m/s 的轻骑兵约 1.7 m）。
			arrow.speed = GameConfig.UNIT_BOLT_SPEED
			arrow.gravity = 0.0
			arrow.dir = (to - from).normalized() if _skip_prediction(target) \
				else _aim_straight(from, to, target, arrow.speed)
		"musket_bullet":
			## 火枪兵（2026-09-25 新增）：与弩箭**同一条直线预判**（`_aim_straight()`、同样吃
			## `_skip_prediction()` 那道总闸门），只是速度是它的**两倍**（360 m/s）。
			## ⚠️ 60 Hz 下每帧 **6 m** —— 靠的是 `arrow.gd#_resolve_segment()` 的**线段查询**
			##（箭矢从来都是"上一帧位置 → 这一帧位置"的线段，不是点），所以不会穿模。
			## ⚠️ 它 `ignores_shield = true`（穿盾）**但仍是"小型投射物"** ⇒ 会被武士大师的高级偏折反弹；
			## 那两条是独立的通路（盾牌看 `ignores_shield`，偏折看 `Arrow.is_small_projectile()`）。
			arrow.speed = GameConfig.UNIT_MUSKET_BULLET_SPEED
			arrow.gravity = 0.0
			arrow.dir = (to - from).normalized() if _skip_prediction(target) \
				else _aim_straight(from, to, target, arrow.speed)
		_:
			arrow.speed = GameConfig.PROJECTILE_SPEED
			arrow.gravity = 0.0
	arrow.ignited = shooter.has_tech("fire_arrow")
	arrow.knockback *= shooter.tech_kb_mult()
	if arrow.kind == "stone":
		arrow.apply_stun = true
	_apply_shot_techs(arrow, shooter)
	var yaws: Array[float] = [0.0]
	if arrow.kind == "stone" and shooter.has_tech("scatter_shot"):
		var scatter := shooter.tech_def("scatter_shot")
		var count := maxi(int(scatter.get("count", 3)), 1)
		var spread := deg_to_rad(float(scatter.get("spread_deg", 7.0)))
		var mult := float(scatter.get("damage_mult", 0.7))
		arrow.damage *= mult
		arrow.splash_damage *= mult
		arrow.knockback = 0.0
		arrow.knockback_damage = 0.0
		arrow.apply_stun = false
		arrow.stone_scale = 0.72
		yaws.clear()
		for i in count:
			yaws.append(spread * (float(i) - float(count - 1) * 0.5))
	var base_dir := arrow.dir
	for i in yaws.size():
		var shot := arrow if i == 0 else _copy_shot(arrow)
		shot.dir = base_dir.rotated(Vector3.UP, yaws[i])
		_launch_shot(shot, from)
	## 发射音（2026-09-25）：**走既有的 `fx_request` 总线，不新增信号** —— `06_audio.md#3` 的口径是
	## "表现层专用信号统一走 `fx_request`，事件名只是音频层内部的映射键"。
	## ⚠️ 这里必须把**兵种 ID 编进事件名**（`shot_catapult` / `shot_ballista` / `shot_shortbow` / `shot_longbow`）：
	## `fx_request` 只带 `(event, world_pos)` 两个参数，不编进去音频层就分不出是哪个兵种在射。
	Events.fx_request.emit("shot_%s" % shooter.type_id, from)

func _apply_shot_techs(arrow: Arrow, shooter: Unit3D) -> void:
	if arrow.kind == "longbow_arrow" and shooter.has_tech("explosive_arrow"):
		var spec := shooter.tech_def("explosive_arrow")
		arrow.explosive_radius = float(spec.get("radius", 3.0))
		arrow.explosive_ratio = float(spec.get("splash_ratio", 0.5))
	if arrow.kind == "stone" and shooter.has_tech("fireball"):
		var spec := shooter.tech_def("fireball")
		arrow.fireball = true
		arrow.fire_damage = float(spec.get("tick_damage", 100.0))
	if shooter.has_tech("silence_shot") and (arrow.kind == "stone" or arrow.kind == "bolt" or arrow.kind == "musket_bullet"):
		var spec := shooter.tech_def("silence_shot")
		arrow.silence_ms = int(spec.get("duration_ms", 5000))
		arrow.silence_move_mult = float(spec.get("move_mult", 0.7))
	if arrow.kind == "bolt" and shooter.has_tech("assault"):
		var spec := shooter.tech_def("assault")
		arrow.aoe_radius = float(spec.get("aoe_radius", 4.0))
		arrow.splash_damage = arrow.damage
		arrow.splash_knockback = false

func _copy_shot(src: Arrow) -> Arrow:
	var arrow := Arrow.new()
	arrow.shooter = src.shooter
	arrow.team = src.team
	arrow.damage = src.damage
	arrow.splash_damage = src.splash_damage
	arrow.kind = src.kind
	arrow.aoe_radius = src.aoe_radius
	arrow.knockback = src.knockback
	arrow.knockback_damage = src.knockback_damage
	arrow.ignores_shield = src.ignores_shield
	arrow.pierce = src.pierce
	arrow.speed = src.speed
	arrow.gravity = src.gravity
	arrow.ignited = src.ignited
	arrow.apply_stun = src.apply_stun
	arrow.splash_knockback = src.splash_knockback
	arrow.explosive_radius = src.explosive_radius
	arrow.explosive_ratio = src.explosive_ratio
	arrow.fireball = src.fireball
	arrow.fire_damage = src.fire_damage
	arrow.silence_ms = src.silence_ms
	arrow.silence_move_mult = src.silence_move_mult
	arrow.stone_scale = src.stone_scale
	return arrow

func _launch_shot(arrow: Arrow, from: Vector3) -> void:
	add_child(arrow)
	arrow.global_position = from
	if arrow.dir.length_squared() > 0.0001:
		var up := Vector3.FORWARD if absf(arrow.dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		arrow.look_at(arrow.global_position + arrow.dir, up)
	_keep_arrow(arrow)

## Spartan 投矛（2026-09-27 第十二轮·第二批「this is Spartan！」）：**每个矛兵一生一次**的投射物。
## 用户口径："第一下攻击变为射程为 16 m 的投矛，造成 1.5 倍伤害"；当场补充："**造弹体**"。
## ⚠️ 为什么另起一个函数而不是复用 `spawn_arrow()`：那个函数的**一切参数都从 shooter 的 PROFILE 来**
##（弹道种类 / 速度 / 溅射 / 穿透…），而投矛是"长矛兵临时打出一发不属于它 PROFILE 的弹" ——
## 硬塞进去要在 `spawn_arrow()` 里加一堆"如果是 Spartan 就改成…"的分支，那是漂移的温床。
## ⇒ 这里显式给全套参数，**走同一条直线预判**（`_aim_straight()` + `_skip_prediction()` 闸门，与弩箭 / 子弹同源）。
## ⚠️ 标枪 `kind = "spear"`：普通盾与月牙盾挡不住；剑盾兵点了「高级格挡」能挡；武士大师能弹反。
## `ignores_shield` 仍为真，免得没点高级格挡的普通盾把它当成箭挡下来。
func spawn_spear_throw(shooter: Unit3D, target: Unit3D, throw_range: float, damage_mult: float) -> void:
	if shooter == null or target == null:
		return
	_launch_spear(shooter, target, target.shot_aim_point(), throw_range, damage_mult)

## 投矛沿准星飞，不锁人。
func spawn_spear_along(shooter: Unit3D, aim_point: Vector3, throw_range: float, damage_mult: float) -> void:
	if shooter == null:
		return
	_launch_spear(shooter, null, aim_point, throw_range, damage_mult)

func _launch_spear(shooter: Unit3D, target: Unit3D, to: Vector3, throw_range: float, damage_mult: float) -> void:
	var from := shooter.global_position + Vector3(0.0, 1.25, 0.0) - shooter.global_transform.basis.z * 0.5
	var arrow := Arrow.new()
	arrow.shooter = shooter
	arrow.team = shooter.team
	arrow.damage = GameConfig.hit_damage(shooter.type_id) * damage_mult * shooter.tech_damage_mult()
	arrow.splash_damage = 0.0
	arrow.kind = "spear"
	arrow.aoe_radius = 0.0
	arrow.knockback = 0.0
	arrow.knockback_damage = 0.0
	arrow.ignores_shield = true
	arrow.pierce = 0
	arrow.speed = GameConfig.PROJECTILE_SPEED
	arrow.gravity = 0.0
	arrow.dir = (to - from).normalized()
	if not _skip_prediction(target):
		arrow.dir = _aim_straight(from, to, target, arrow.speed)
	## 射程上限：投矛不能飞过 `throw_range`（16 m）—— 用箭自己的"最大飞行距离"闸门
	##（`Arrow.max_flight`，本轮为它新增；0 = 不限，其余投射物照旧）。
	arrow.max_flight = throw_range + GameConfig.UNIT_BODY_CAPSULE_RADIUS * 4.0
	add_child(arrow)
	arrow.global_position = from
	arrow.mark_flight_origin()
	if arrow.dir.length_squared() > 0.0001:
		var up := Vector3.FORWARD if absf(arrow.dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
		arrow.look_at(arrow.global_position + arrow.dir, up)
	_keep_arrow(arrow)
	## 发射音：编进兵种 ID（与 `spawn_arrow()` 同一套；矛兵没有专属素材 ⇒ 音频层会落到缺省那一档）。
	Events.fx_request.emit("shot_%s" % shooter.type_id, from)

## **预判总闸门**（2026-09-25 用户："修改预判逻辑：**如果被锁定单位正在被击退或正在冲撞
##（目前只有骑士，火焰拳），则不预判**"）。
## 判据落在 `Unit3D.is_mid_dash()` 里（击退中 / 骑士冲撞 / 火焰拳炎爆 / **轻骑兵冲刺**）。
## ⚠️ 为什么"被击退或冲撞时不预判"是对的：这两类位移的速度方向由**外力**决定、随时会变
##（击退会衰减、冲撞会撞停），拿它外推提前量只会把箭瞄到一个它不会去的位置 ——
## 此时"打在它当前所在处"反而是更准的近似。
func _skip_prediction(target: Unit3D) -> bool:
	return target == null or not is_instance_valid(target) or target.is_mid_dash()

## 抛物线投射物的瞄准入口：闸门打开时退回"瞄当前位置"（= 不预判）。
func _aim_ballistic(from: Vector3, to: Vector3, target: Unit3D, speed: float, gravity: float) -> Vector3:
	var target_velocity := target.aim_velocity() if not _skip_prediction(target) else Vector3.ZERO
	return _solve_ballistic(from, to, target_velocity, speed, gravity)

## 直线投射物（弩车）的落点预判：解一元一次 —— 提前量 = 目标速度 × (水平距离 ÷ 速度)。
## ⚠️ 与抛物线解**不是**同一套数学（直线没有重力项），所以单独一个函数；
## 闸门（`_skip_prediction`）两条路共用。
func _aim_straight(from: Vector3, to: Vector3, target: Unit3D, speed: float) -> Vector3:
	var flat := to - from
	flat.y = 0.0
	var flight := maxf(flat.length() / maxf(speed, 0.01), 0.0)
	var lead := target.aim_velocity()
	var aim := to + Vector3(lead.x, 0.0, lead.z) * flight
	return (aim - from).normalized()

## 定速弹道解（速度固定，解出水平 / 竖直分量）+ **落点预判**，返回发射方向（单位向量）。
## 2026-09-25：从"投石车"那一支里提出来 —— 长弓手要的是**同一条数学**、不同的速度与命中模型。
##
## ⚠️ 三个坑（前两个 2026-09-19 处理，第三个 2026-09-25 实测补上）：
##   ① 用"按平地飞行时间抬高 0.5·g·t"的近似会**过射**（抬角本身让滞空变长）；
##   ② 目标超出弹丸能飞到的距离（`v²/g`）时，`vx²` 会变成负数——旧代码用 `maxf(..., 1.0)`
##      一夹，发射方向就退化成**几乎正上方**，这就是"有时朝正上方投石"的 bug。
##      现在把瞄准点**夹到最大射程内**，远了就打不到那么远，但姿势正常。
##   ③ **飞行时间必须与"竖直分量也花掉的那部分速度"自洽**。`t` 用 `水平距离 ÷ 速度` 估时，
##      等于假装竖直分量不占速度预算 ⇒ `vy` 偏大、弹道整体抬高、末端高于瞄准点。
##      实测（长弓手 30 m 射程）：箭的最高点比目标高 1.0 m，从**目标头顶掠过**，
##      40 发一发不中（单位胶囊半径 0.38、直径 0.76 m，1 m 的误差足以让箭从旁边飞过）。
##      石弹看不出来是因为它有 4 m 溅射半径兜底；长弓是单体直击，必须打准。
##      现在用 `t = 水平距离 / 水平分量` 反复回代（4 轮足够收敛到毫米级）。
## ⚠️ 预判也是**迭代收敛**的：提前量取决于滞空时间，滞空时间又取决于提前量，
##    单次近似在 30 m 上会差出几米（长弓手射程远，这一条比投石车更吃紧）。
func _solve_ballistic(from: Vector3, to: Vector3, target_velocity: Vector3,
		speed: float, gravity: float) -> Vector3:
	var flat := to - from
	flat.y = 0.0
	var d := flat.length()
	var max_flat := speed * speed / gravity
	if d > max_flat:
		flat = flat.normalized() * max_flat
		d = max_flat
	## 朝射手走的那一截提前量丢掉。投石车进射程会站住，按"还会往前走"去瞄，
	## 石头会落在两人中间；人被队友堵住时速度也还指着敌人，落点同样偏近。
	## 横着走、往远处走的提前量留着。
	var shot_dir := Vector3.ZERO
	if flat.length_squared() > 0.0001:
		shot_dir = flat.normalized()
	var lead := Vector3(target_velocity.x, 0.0, target_velocity.z)
	if shot_dir != Vector3.ZERO:
		var along := lead.dot(shot_dir)
		if along < 0.0:
			lead -= shot_dir * along
	## 初值：平价滞空时间（下面 4 轮回代把它修对）
	var t := maxf(d / speed, 0.05)
	var aim_point := to
	var aim_flat := flat
	var vy := 0.0
	var vx := speed
	for _i in 4:
		## 预判瞄准点：提前量 = 留下的那部分速度 × 滞空时间
		aim_point = to + lead * t
		aim_flat = aim_point - from
		aim_flat.y = 0.0
		if aim_flat.length() > max_flat:
			aim_flat = aim_flat.normalized() * max_flat
		var aim_d := aim_flat.length()
		## 竖直分量由"在 t 内到达瞄准高度"定出
		vy = (aim_point.y - from.y) / t + 0.5 * gravity * t
		vy = clampf(vy, -speed * 0.99, speed * 0.99)
		## 水平分量 = 速度预算里剩下的那一部分 ⇒ 真正的滞空时间由它决定（这是本轮修的那一步）
		vx = sqrt(maxf(speed * speed - vy * vy, 0.01))
		t = maxf(aim_d / vx, 0.05)
	return (aim_flat.normalized() * vx + Vector3.UP * vy).normalized()

func _keep_arrow(arrow: Arrow) -> void:
	arrow.tree_exiting.connect(_on_arrow_exiting.bind(arrow))
	arrows.append(arrow)

func _on_arrow_exiting(arrow: Arrow) -> void:
	arrows.erase(arrow)

func remove_arrow(arrow: Arrow) -> void:
	arrows.erase(arrow)

# ---------------------------------------------------------------- 比赛流程
func start_match() -> void:
	match_start_ms = Time.get_ticks_msec()
	_last_hit_ms = match_start_ms
	match_active = true
	_settled = false
	ring.visible = false
	for unit in units:
		if unit.alive:
			unit.active = true

## **沙盒模式**：开战 —— 只"点火"（让摆好的单位能动），**不启动赛程**（`match_active` 保持 false）。
## 依据（用户口径）：兴奋圈、90 s 限时、僵持判平、平局判定**都属于竞猜模式**，沙盒一概不要；
## 这四样全挂在 `_physics_process` 的 `match_active` 闸门之后（连 `_update_excited()` 也在里面）
## ⇒ 不启赛程就自然全都不生效（单位永远不会进入"兴奋"）。
## ⚠️ 与 `start_match()` 的差别**只有"不启赛程"**这一条：两边都得让单位活跃，否则摆好的兵不动。
func start_skirmish() -> void:
	ring.visible = false
	## 沙盒战斗时钟从这一帧起算（**只有它**给"召唤那几拍"当锚点，见 `skirmish_elapsed_ms()`）
	skirmish_start_ms = Time.get_ticks_msec()
	for unit in units:
		if unit.alive:
			unit.active = true

## 沙盒战斗已经打了多久（ms）；**返回 −1 = 现在没在战斗**（布兵阶段 / 已收兵 / 已拆场）。
## 调用方（召唤石柱的技能）靠它判"该不该召唤"，判据里那一句 `elapsed < 0` 就是"没开战"。
func skirmish_elapsed_ms() -> int:
	if skirmish_start_ms <= 0:
		return -1
	return Time.get_ticks_msec() - skirmish_start_ms

## **沙盒模式**：收兵 —— 结果展示期间让所有单位停手（与 `_finish()` 里那两行同义）。
## ⚠️ 不复用 `_finish()`：它带"只结一次账"的闸门（`_settled`）与 `match_ended` 信号，
## 而沙盒的胜负由 `Sandbox` 自己按"剩余总血量"判（用户口径：不判平局），既不走 `Arena` 的赛程结算，
## 也不该让 `Game` 那套下注结算被牵连触发。
func stop_skirmish() -> void:
	park_combat()
	clear_arrows()
	clear_acid()
	show_bulwark_links([])
	_hide_ring_bursts()


## 让单位和投射物停手，但把它们留在画面上。定格用这一支，清场用 `clear_arrows()` / `settle()`。
func park_combat() -> void:
	skirmish_start_ms = 0
	match_active = false
	for unit in units:
		if is_instance_valid(unit):
			unit.active = false
	for arrow in arrows:
		if is_instance_valid(arrow):
			arrow.active = false


func clear_arrows() -> void:
	for arrow in arrows.duplicate():
		if is_instance_valid(arrow):
			arrow.queue_free()
	arrows.clear()


## 胜负已经判定。`delay_ms` 内继续演算，到点定格。`result` 非空时，定格那一帧发出 `match_ended`。
func begin_presentation_hold(result: Dictionary = {}, delay_ms: int = -1) -> void:
	var delay := GameConfig.BATTLE_HOLD_DELAY_MS if delay_ms < 0 else delay_ms
	presentation_frozen = false
	process_mode = Node.PROCESS_MODE_INHERIT
	_presentation_at_ms = Time.get_ticks_msec() + delay
	_presentation_result = result


func end_presentation_hold() -> void:
	presentation_frozen = false
	_presentation_at_ms = 0
	_presentation_result = {}
	process_mode = Node.PROCESS_MODE_INHERIT


func _tick_presentation_hold() -> void:
	if presentation_frozen or _presentation_at_ms <= 0:
		return
	if Time.get_ticks_msec() < _presentation_at_ms:
		return
	presentation_frozen = true
	var result := _presentation_result
	_presentation_result = {}
	_presentation_at_ms = 0
	process_mode = Node.PROCESS_MODE_DISABLED
	if not result.is_empty():
		match_ended.emit(result)

func settle() -> void:
	## 清场，为下一轮做准备
	for arrow in arrows.duplicate():
		if is_instance_valid(arrow):
			arrow.queue_free()
	arrows.clear()
	clear_acid()
	show_bulwark_links([])
	_hide_ring_bursts()
	for unit in units.duplicate():
		if is_instance_valid(unit):
			unit.queue_free()
	units.clear()
	## 挡弹物与"本帧挡下的登记"一起清掉：它们都是"这一场的东西"
	##（肉鸽的魔法盾由玩法侧在下一回合重新同步，见 `Roguelike._sync_arrow_blockers()`）
	arrow_blockers.clear()
	arrow_blocks.clear()
	_spawn_points.clear()
	match_active = false
	_settled = true
	## 沙盒战斗时钟一并归零：下一场由 `start_skirmish()` 重新起算，
	## 否则"重新布兵"后石柱会以为自己已经打了很久（第一拍就直接刷出一批兵）。
	skirmish_start_ms = 0
	ring.visible = false
	ring_radius = GameConfig.RING_START_RADIUS
	ring_visual_radius = GameConfig.RING_START_RADIUS
	_ring_step = 0

## **手动放一个单位**（沙盒模式用；真比赛走 `spawn_roster()` 的配平布局）。
## ⚠️ 除了"位置 / 朝向由调用方给"，其余（命名 / 分组 / 登记 / 生死钩子）与 `spawn_roster()` **逐行一致** ——
## 两个入口必须保持同步，否则会出现"手动放的单位不参与索敌 / 掉出世界不复位"这类分叉。
func spawn_unit(team: int, type_id: String, at: Vector3, facing: float) -> Unit3D:
	var side := "A" if team == 0 else "B"
	var unit := Unit3D.new()
	unit.name = "Unit%s_%s_%d" % [side, type_id, units.size()]
	unit.setup(team, type_id)
	unit.tree_exiting.connect(_on_unit_exiting.bind(unit))
	add_child(unit)
	## 高度一律取 `SPAWN_HEIGHT`（略高于地面）：y 由重力落定，别让调用方传高度
	unit.global_position = Vector3(at.x, GameConfig.SPAWN_HEIGHT, at.z)
	unit.rotation.y = facing
	units.append(unit)
	_spawn_points[unit] = unit.global_position
	Events.unit_spawned.emit(unit)
	return unit

## 暂停恢复：把本场地自己的**绝对毫秒时刻**整体后移（见 `match_pause.gd#shift_deadlines()` 的说明）。
## ⚠️ 树暂停**不会停表**（计时一律是绝对毫秒，不变量 I-13）⇒ 暂停期间流逝的时间必须在这里补回来，
## 否则赛程倒计时（`match_start_ms`）与"僵持判平"的静默计时（`_last_hit_ms`）都会白白走掉。
func shift_deadlines(delta_ms: int) -> void:
	if delta_ms <= 0:
		return
	if match_start_ms > 0:
		match_start_ms += delta_ms
	if _last_hit_ms > 0:
		_last_hit_ms += delta_ms
	## 沙盒战斗时钟同样要平移：它是**绝对时刻**，而树暂停不会停表（不变量 I-13）。
	## 不平移的话，"暂停 20 s 回来"会让石柱当场补刷 4 拍召唤。
	if skirmish_start_ms > 0:
		skirmish_start_ms += delta_ms
	if _presentation_at_ms > 0 and not presentation_frozen:
		_presentation_at_ms += delta_ms
	## 队伍级减益的截止时刻同样是**绝对毫秒**（不变量 I-13）⇒ 也要平移，否则"暂停 6 s 回来"会发现
	## 指挥所那 5 s 减益早就走完了。
	for i in range(_team_debuff_until_ms.size()):
		if int(_team_debuff_until_ms[i]) > 0:
			_team_debuff_until_ms[i] = int(_team_debuff_until_ms[i]) + delta_ms
	for pool in _acid_pools:
		if int(pool.get("next_ms", 0)) > 0:
			pool["next_ms"] = int(pool["next_ms"]) + delta_ms
	for pool in _fire_pools:
		if int(pool.get("next_ms", 0)) > 0:
			pool["next_ms"] = int(pool["next_ms"]) + delta_ms
		if int(pool.get("until_ms", 0)) > 0:
			pool["until_ms"] = int(pool["until_ms"]) + delta_ms
	_shift_tick_book(_fire_tick_ms, delta_ms)
	_shift_tick_book(_acid_tick_ms, delta_ms)
	for meta in _holy_meta:
		if int(meta.get("until_ms", 0)) > 0:
			meta["until_ms"] = int(meta["until_ms"]) + delta_ms
			meta["born_ms"] = int(meta.get("born_ms", 0)) + delta_ms
	for i in range(_intercept_until.size()):
		if _intercept_until[i] > 0:
			_intercept_until[i] += delta_ms

## 供相机按 1/2/3 选人时定位（docs/bible/05_ui_hud.md#6-输入映射）
func units_of_team(team: int) -> Array:
	var out: Array = []
	for unit in units:
		if is_instance_valid(unit) and unit.alive and unit.team == team:
			out.append(unit)
	return out

func _cell_key(at: Vector3) -> Vector2i:
	return Vector2i(int(floor(at.x / GameConfig.UNIT_QUERY_CELL)), int(floor(at.z / GameConfig.UNIT_QUERY_CELL)))

## 本帧开头按活着的人重填格子。每一格里两队各放一列。
## 能被锁定的人另外按格收成名单，索敌只翻有人的格子。
func rebuild_unit_grid() -> void:
	_unit_cells.clear()
	(_open_cells[0] as Dictionary).clear()
	(_open_cells[1] as Dictionary).clear()
	(_open_keys[0] as Array).clear()
	(_open_keys[1] as Array).clear()
	for unit in units:
		if not is_instance_valid(unit) or not unit.alive:
			continue
		if unit.team != 0 and unit.team != 1:
			continue
		var key := _cell_key(unit.global_position)
		if not _unit_cells.has(key):
			_unit_cells[key] = [[], []]
		var buckets: Array = _unit_cells[key]
		(buckets[unit.team] as Array).append(unit)
		if unit.is_burrowed() or unit.is_in_shadow_form() or unit.is_ember():
			continue
		var open_map: Dictionary = _open_cells[unit.team]
		if not open_map.has(key):
			open_map[key] = []
			(_open_keys[unit.team] as Array).append(key)
		(open_map[key] as Array).append(unit)

func _cell_units(key: Vector2i, team: int) -> Array:
	if not _unit_cells.has(key):
		return _empty_cell
	var buckets: Array = _unit_cells[key]
	if team < 0 or team >= buckets.size():
		return _empty_cell
	return buckets[team]

func units_near(at: Vector3, radius: float) -> Array:
	var pad := int(ceil((radius + GameConfig.UNIT_QUERY_SLACK_M) / GameConfig.UNIT_QUERY_CELL))
	var home := _cell_key(at)
	var out: Array = []
	for x in range(home.x - pad, home.x + pad + 1):
		for z in range(home.y - pad, home.y + pad + 1):
			var key := Vector2i(x, z)
			for unit in _cell_units(key, 0):
				out.append(unit)
			for unit in _cell_units(key, 1):
				out.append(unit)
	return out

## 已经释放的对象不能送进带类型的参数，否则调用本身就会报错，进不了函数体。
func _living_unit(node: Variant) -> Unit3D:
	if not is_instance_valid(node):
		return null
	return node as Unit3D

func _enemy_candidate(from: Unit3D, other: Unit3D, min_reach: float) -> bool:
	if other == null or not is_instance_valid(other) or other == from or not other.alive:
		return false
	if other.team == from.team:
		return false
	if other.is_burrowed() or other.is_in_shadow_form() or other.is_ember():
		return false
	if from.is_corruptor() and bool(other.aid_mods.get("block_corrupt", false)):
		return false
	if min_reach > 0.0 and from.surface_distance_to(other) < min_reach:
		return false
	return true

## 最近的敌人。上一帧的目标先占着“目前最近”，格子只往外扩到不可能有人更近为止。
func nearest_enemy(from: Unit3D, min_reach: float, prior_target: Variant = null) -> Unit3D:
	if from == null:
		return null
	var origin := from.global_position
	var home := _cell_key(origin)
	var foe := 1 - from.team
	var best: Unit3D = null
	var best_d := INF
	var prior := _living_unit(prior_target)
	if _enemy_candidate(from, prior, min_reach):
		best = prior
		best_d = origin.distance_squared_to(prior.global_position)
	var cell := GameConfig.UNIT_QUERY_CELL
	var slack := GameConfig.UNIT_QUERY_SLACK_M
	for ring in range(0, 48):
		var x0 := home.x - ring
		var x1 := home.x + ring
		var z0 := home.y - ring
		var z1 := home.y + ring
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				if ring > 0 and x != x0 and x != x1 and z != z0 and z != z1:
					continue
				for node in _cell_units(Vector2i(x, z), foe):
					var other := _living_unit(node)
					if not _enemy_candidate(from, other, min_reach):
						continue
					var d := origin.distance_squared_to(other.global_position)
					if d < best_d:
						best_d = d
						best = other
		var min_x := float(home.x - ring) * cell
		var max_x := float(home.x + ring + 1) * cell
		var min_z := float(home.y - ring) * cell
		var max_z := float(home.y + ring + 1) * cell
		var edge := minf(origin.x - min_x, max_x - origin.x)
		edge = minf(edge, minf(origin.z - min_z, max_z - origin.z))
		if best != null and sqrt(best_d) + slack <= edge:
			break
	return best

## 本帧开头收一次还在生效的沙暴。没有沙暴时，后面的移速查询直接返回。
func rebuild_storms() -> void:
	_storms.clear()
	for unit in units:
		if not is_instance_valid(unit) or not unit.alive:
			continue
		var row := unit.sandstorm_fields()
		if row.is_empty():
			continue
		_storms.append(row)

func storm_move_pct_at(at: Vector3) -> float:
	if _storms.is_empty():
		return 0.0
	var pct := 0.0
	for storm in _storms:
		var center: Vector3 = storm["at"]
		var flat := at - center
		flat.y = 0.0
		if flat.length() > float(storm["radius"]):
			continue
		pct += float(storm["move_pct"])
	return pct

func storm_taken_mult_at(at: Vector3) -> float:
	if _storms.is_empty():
		return 1.0
	var mult := 1.0
	for storm in _storms:
		var center: Vector3 = storm["at"]
		var flat := at - center
		flat.y = 0.0
		if flat.length() > float(storm["radius"]):
			continue
		mult *= float(storm["taken_mult"])
	return mult

## 一帧算完所有人的最近敌人。每人只跟身边格子里的敌方名单比，身边没有更近的才往外扩。
func solve_nearest() -> void:
	_nearest_of.clear()
	_nearest_solved = true
	var sides: Array = [[], []]
	for unit in units:
		if not is_instance_valid(unit) or not unit.alive:
			continue
		if unit.team != 0 and unit.team != 1:
			continue
		(sides[unit.team] as Array).append(unit)
	_match_nearest(sides[0], 1)
	_match_nearest(sides[1], 0)

func _match_nearest(seekers: Array, foe_team: int) -> void:
	if foe_team != 0 and foe_team != 1:
		return
	var keys: Array = _open_keys[foe_team]
	var cells: Dictionary = _open_cells[foe_team]
	for node in seekers:
		var seeker := node as Unit3D
		if seeker == null:
			continue
		_nearest_of[seeker.get_instance_id()] = _nearest_on_grid(seeker, keys, cells)

## 从有人的最近一圈往外看。上一帧的目标先占着“目前最近”，圈外不可能更近就停。
func _nearest_on_grid(from: Unit3D, keys: Array, cells: Dictionary) -> Unit3D:
	var origin := from.global_position
	var min_reach := from.attack_min_reach()
	var best: Unit3D = null
	var best_d := INF
	var prior := _living_unit(from.target)
	if _enemy_candidate(from, prior, min_reach):
		best = prior
		best_d = origin.distance_squared_to(prior.global_position)
	if keys.is_empty():
		return best
	var home := _cell_key(origin)
	var min_ring := 48
	for key in keys:
		var cell: Vector2i = key
		var ring := maxi(absi(cell.x - home.x), absi(cell.y - home.y))
		if ring < min_ring:
			min_ring = ring
	var cell_size := GameConfig.UNIT_QUERY_CELL
	var slack := GameConfig.UNIT_QUERY_SLACK_M
	for ring in range(min_ring, 48):
		for key in keys:
			var cell: Vector2i = key
			if maxi(absi(cell.x - home.x), absi(cell.y - home.y)) != ring:
				continue
			var bucket: Array = cells[cell]
			for node in bucket:
				var other := _living_unit(node)
				if other == null:
					continue
				if other.is_burrowed() or other.is_in_shadow_form() or other.is_ember():
					continue
				if min_reach > 0.0 and from.surface_distance_to(other) < min_reach:
					continue
				var gap := origin.distance_squared_to(other.global_position)
				if gap < best_d:
					best_d = gap
					best = other
		var min_x := float(home.x - ring) * cell_size
		var max_x := float(home.x + ring + 1) * cell_size
		var min_z := float(home.y - ring) * cell_size
		var max_z := float(home.y + ring + 1) * cell_size
		var edge := minf(origin.x - min_x, max_x - origin.x)
		edge = minf(edge, minf(origin.z - min_z, max_z - origin.z))
		if best != null and sqrt(best_d) + slack <= edge:
			break
	return best

func cached_nearest(unit: Unit3D) -> Unit3D:
	if unit == null:
		return null
	if not _nearest_solved or not _nearest_of.has(unit.get_instance_id()):
		return nearest_enemy(unit, unit.attack_min_reach(), unit.target)
	var raw = _nearest_of[unit.get_instance_id()]
	if raw == null:
		return null
	var found := raw as Unit3D
	if found == null or not is_instance_valid(found):
		return null
	return found

func queue_blast(at: Vector3, radius: float, damage: float, from: Unit3D, from_team: int, enemies_only: bool) -> void:
	_blast_queue.append({
		"at": at,
		"radius": radius,
		"damage": damage,
		"from": from,
		"team": from_team,
		"enemies_only": enemies_only,
	})

## 同一帧最多结算几发爆炸，其余留到后面的帧。新炸出来的也要再等一帧。
func tick_blasts() -> void:
	if _blast_queue.is_empty():
		return
	var count := mini(GameConfig.UNIT_GRENADE_BLASTS_PER_FRAME, _blast_queue.size())
	var wave: Array = []
	for _i in count:
		wave.append(_blast_queue.pop_front())
	for blast in wave:
		var at: Vector3 = blast["at"]
		var radius := float(blast["radius"])
		var damage := float(blast["damage"])
		var from := _living_unit(blast["from"])
		var from_team := int(blast["team"])
		var enemies_only := bool(blast["enemies_only"])
		for node in units_near(at, radius):
			var other := _living_unit(node)
			if other == null or other == from or not other.alive:
				continue
			if enemies_only and other.team == from_team:
				continue
			if other.is_burrowed():
				continue
			if at.distance_to(other.global_position) > radius:
				continue
			other.apply_hit(damage, from)

func alive_count(team: int) -> int:
	var total := 0
	for unit in units:
		if is_instance_valid(unit) and unit.alive and unit.team == team:
			total += 1
	return total

## ---- 队伍级修正的取值口（肉鸽第三块）----
## ⚠️ 这三个 `*_for()` 是**单位唯一该调的口**：合成规则只写在这里，单位侧不许自己再乘一遍。
## 被摧毁减益在移速与伤害两个口里各乘一次（用户："移速下降90%、伤害下降90%"）。

## 这一队现在的**伤害倍率** = 持续增益 × 被摧毁减益
func damage_mult_for(team: int) -> float:
	var scale := GameConfig.ROGUELIKE_POST_DEBUFF_MULT if debuff_active(team) else 1.0
	return float(team_damage_buff[team]) * scale

## 这一队现在的**实际移速** = (单位基础移速 + 单回合加成) × 被摧毁减益
## ⚠️ 顺序是"先加后乘"：+1 m/s 之后整体再砍 90%（口径里这两件事本就是分开的）
func speed_for(team: int, base_speed: float) -> float:
	var scale := GameConfig.ROGUELIKE_POST_DEBUFF_MULT if debuff_active(team) else 1.0
	return (base_speed + float(team_speed_bonus[team])) * scale

## 这一队现在的**射程加成**（米）—— ⚠️ 只对**远程**生效，判不判由调用方（`Unit3D.attack_reach()`）
func range_bonus_for(team: int) -> float:
	return float(team_range_bonus[team])

## 这一队现在有没有"指挥所被打掉"的减益（界面读它显示一行警告）
func debuff_active(team: int) -> bool:
	return int(_team_debuff_until_ms[team]) > Time.get_ticks_msec()

## 给某一队挂上被摧毁减益：**刷新**截止时刻（用户："两个指挥所均被摧毁时…不叠加，只会刷新持续时间"）
func apply_team_debuff(team: int, duration_ms: int) -> void:
	if team < 0 or team >= _team_debuff_until_ms.size():
		return
	_team_debuff_until_ms[team] = Time.get_ticks_msec() + maxi(duration_ms, 0)

## 清掉**单回合**加成（肉鸽每回合开始时调；持续增益 `team_damage_buff` 不动）
func clear_round_buffs() -> void:
	team_speed_bonus = [0.0, 0.0]
	team_range_bonus = [0.0, 0.0]

func team_hp(team: int) -> float:
	var total := 0.0
	for unit in units:
		if is_instance_valid(unit) and unit.alive and unit.team == team:
			total += unit.hp
	return total

func team_max_hp(team: int) -> float:
	var total := 0.0
	for unit in units:
		if is_instance_valid(unit) and unit.alive and unit.team == team:
			total += unit.max_hp
	return total

## 兴奋圈已废止。读档若还带着旧的圈外状态，这里清掉，不再叠内伤、不再加攻速。
func _clear_excited() -> void:
	for unit in units:
		if is_instance_valid(unit) and unit.excited:
			unit.set_excited(false)

func _judge() -> Dictionary:
	var alive_a := alive_count(0)
	var alive_b := alive_count(1)
	var hp_a := team_hp(0)
	var hp_b := team_hp(1)
	var max_a := team_max_hp(0)
	var max_b := team_max_hp(1)
	var winner := -1
	var reason := "timeout"
	# 1) 双方同时全灭 -> 平局（观众两边都算押中，见 docs/bible/03_rules.md#1-胜负判定）
	if alive_a == 0 and alive_b == 0:
		winner = -1
		reason = "draw"
	elif alive_a == 0:
		winner = 1
		reason = "wipe"
	elif alive_b == 0:
		winner = 0
		reason = "wipe"
	else:
		# 2) 时间到 -> 比剩余血量，再比血量比例，仍相同则判平局
		reason = "timeout"
		if not is_equal_approx(hp_a, hp_b):
			winner = 0 if hp_a > hp_b else 1
		else:
			var ratio_a := hp_a / maxf(max_a, 1.0)
			var ratio_b := hp_b / maxf(max_b, 1.0)
			if absf(ratio_a - ratio_b) > 0.001:
				winner = 0 if ratio_a > ratio_b else 1
			else:
				winner = -1
				reason = "draw"
	return {
		"winner": winner,
		"reason": reason,
		"alive": [alive_a, alive_b],
		"hp": [int(round(hp_a)), int(round(hp_b))],
		"duration_ms": Time.get_ticks_msec() - match_start_ms,
	}

func _finish(result: Dictionary) -> void:
	if _settled:
		return
	_settled = true
	match_active = false
	begin_presentation_hold(result)

# ---------------------------------------------------------------- 工具
## 地面轮廓线的一段（纯表现：贴地的一根细条，零碰撞）
func _add_edge(edge_name: String, at: Vector3, size: Vector3, tint: Color) -> void:
	var edge := MeshInstance3D.new()
	edge.name = edge_name
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = size
	edge.mesh = edge_mesh
	edge.position = at
	edge.material_override = _mat(tint, 0.6, true)
	add_child(edge)

## 一段边界墙（隐形：只有碰撞体、不渲染）。`at` = 墙脚中心 ⇒ y 自动抬到半高。
func _add_wall(wall_name: String, at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.name = wall_name
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.physics_material_override = _phys(0.6, 0.0)
	wall.add_child(_box_shape(Vector3.ZERO, size))
	wall.position = at + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(wall)

func _box_shape(pos: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	return shape

func _mat(color: Color, roughness: float = 0.9, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _phys(friction: float, bounce: float) -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = bounce
	return pm

func ring_ratio() -> float:
	return ring_radius / GameConfig.RING_START_RADIUS

## 全场存活单位的质心（开战机位用它瞄准）
func battle_center() -> Vector3:
	var center := Vector3.ZERO
	var count := 0
	for unit in units:
		if is_instance_valid(unit) and unit.alive:
			center += unit.global_position
			count += 1
	if count == 0:
		return Vector3.ZERO
	center /= float(count)
	center.y = 0.9
	return center

## 观赛相机默认焦点：向质心缓慢靠拢
func camera_focus_point(delta: float, current: Vector3) -> Vector3:
	var center := battle_center()
	return current.lerp(center, clampf(delta * 1.6, 0.0, 1.0))

func _mcp_state() -> Dictionary:
	return {
		"match_active": match_active,
		## 沙盒战斗时钟（−1 = 没在战斗）与权重递增开关：探针靠这两个读数验"召唤那几拍"
		##（`04_physics.md#5.2` 那一族探针一律走 `_mcp_state()`，不去猜内部字段）。
		"skirmish_elapsed_ms": skirmish_elapsed_ms(),
		"summon_escalation": summon_escalation,
		"ring_radius": snappedf(ring_radius, 0.01),
		"alive": [alive_count(0), alive_count(1)],
		"hp": [int(round(team_hp(0))), int(round(team_hp(1)))],
		"units": units.size(),
		"arrows": arrows.size(),
	}
