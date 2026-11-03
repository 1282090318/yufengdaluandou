extends Node
## 全局数值表与队伍生成（Autoload 名：GameConfig）
##
## 本文件是 docs/bible 里所有数值的**唯一代码落点**：其他地方只允许引用这里的名字，
## 不允许出现字面量。
##
## 数值现状（2026-09-17 按用户指令重新标定，已同步进 bible）：
##   1. 三种兵种权重统一为 1，各自数值重新平衡；短弓手（旧名"弓兵"）射程 11 → 16 m
##   2. 新增第六属性 **move_speed（移速）**，全体比之前更慢
##   3. 每队总权重从固定 14 改为 **按轮次递增**（10 起，每轮 **+5**）
##      ⚠️ 2026-09-19 由 +3 改为 +5（用户："初始权重为 10，每回合权重增加 5"）⇒ 十轮预算 10~55；见 `TEAM_WEIGHT_STEP`
##   4. 场地 36×18 → 52×24；双方在**己方后半段**成簇刷新（不再排成一排）
##   5. 长矛兵击退增强到"能把剑盾兵推出其射程"
##
## 本轮（2026-09-18：场地放大 + 场外风景）：
##   6. 场地 52×24 → **100×50**；随后按新场地重标两个被牵动的模块：
##      `RING_START_RADIUS` 16 → 32（几何约束，理由见该常量注释）、
##      相机全景 / 开战机位 `CAM_OVERVIEW_DISTANCE` 38 → 73、`CAM_FIGHT_HEIGHT/BACK` 22/26 → 28/32
##   7. 新增"场地风景"段：边界墙之外的**纯装饰**（一件都不带碰撞体），落在 `arena.gd#_build_scenery`
##   ✅ 上面 6 / 7 已同步进 bible（`04_physics.md#2` / `#2.4`、`05_ui_hud.md#7.3`、`00_world.md#4.3`、`_index.md#4`）——
##      原"⚠️ 待办"已于 2026-09-25 结清。⚠️ 但 6 / 7 **不是**最后一次改动：
##      2026-09-19 起又落地了兵种扩到 12 种、权重 +5、判定体改盒体、沙虫 boss、攻击节奏重做等，
##      **本注释只登记到 2026-09-18，不是 changelog** —— 以各常量自身的注释为准。
##
## 参数存放约定：**所有可调参数都住在本文件**（按功能分段，注释里标了对应 bible 章节）。
## `Arena` / `CameraRig` / `Unit3D` 这些节点只读取，不保存副本 ——
## 它们全部由 `main.gd` 在代码里 `new()` 出来，没有任何 .tscn 实例，因此
## `@export` 既不会出现在编辑器面板里、也无法被保存，留着只会造成两处数值漂移。

const VERSION := "0.2.0"

# ---------------------------------------------------------------- 比赛节奏
const ROUND_COUNT := 10                ## 一局最多播送的轮次
## 押注阶段**没有倒计时**（优化 2）：玩家不选就一直等，因此不再需要
## 决策时限 / 自动观望 / 隐藏推荐倾向这三个时间常量。
const MATCH_LIMIT_MS := 90000          ## 单场比赛总时长（超时按剩余血量判定）
const BATTLE_HOLD_DELAY_MS := 200       ## 战斗分出胜负后再演算这么久，然后定格
const STALEMATE_MS := 20000            ## 双方都打不到对方持续这么久 -> 判平局
## 兴奋圈已废止（2026-10-23，I-14）。下面这组常量还在，玩法不再读取它们来画圈或改攻速。
const RING_GRACE_MS := 3000            ## 兴奋圈出现后的免伤宽限（给圈外单位回防时间）
const RING_START_MS := 60000           ## 兴奋圈开始收缩的时刻（= 原作的 1 分钟）
const RING_SHRINK_MS := 20000          ## 每多少毫秒向内收缩一格
const RING_SHRINK_STEP := 1.0          ## 每格收缩多少米
const RING_MIN_RADIUS := 3.0           ## 收缩下限
const CIRCLE_ATK_MULT := 2.0           ## 圈外：攻击力倍率
const CIRCLE_HIT_MULT := 2.0           ## 圈外：攻击速度倍率
const CIRCLE_DOT_RATIO := 0.005        ## 圈外：每层内伤每秒造成的最大生命占比
## 圈外：每隔多久叠 1 层内伤。= `01_core_loop.md#3` 的"每秒叠 1 层内伤（每层 0.5% 最大生命的真伤）"。
## ⚠️ 它必须与伤害结算共用同一个节拍：入口 `Arena._update_excited` 是**每物理帧**调用一次，
## 少了这个节流，层数会以 60 层/秒累积（2026-09-18 实测：圈外 2.2 s 掉 91% 最大生命）。
const CIRCLE_DOT_INTERVAL_MS := 1000
## 全场倍率（不变量 I-23 / I-24）：**2026-09-18 由 ×1.5 / ×0.5 改为 ×1.0，即取消全场缩放。**
## 这样"bible 上的表值 = 场上的实际值"，不用再心算一遍；`max_hp()` / `hit_damage()` 的乘法结构保留，
## 只是系数为 1，将来若要重新引入全场缩放不用改代码结构。
## ⚠️ 改这两个值会改变击杀刀数（例：剑盾兵 270 HP 挨 34 伤害 = 8 刀，而旧倍率下是 3 刀），
## 因而显著改变比赛时长——动它必须重跑 `debug_balance_stats`（见 `04_physics.md#10`）。
const HIT_ATK_MULT := 1.0              ## 全场：攻击力倍率（不变量 I-23 = ×1.0）
const HIT_HP_MULT := 1.0               ## 全场：最大生命倍率（不变量 I-24 = ×1.0）

# ---------------------------------------------------------------- 押注规则
const START_POINTS := 10000            ## 开局白送的礼物点数
const WAGER_TABLE := [2000, 2400, 3000, 4000, 5500, 8000, 12000, 18000, 30000, 50000]
const ALL_IN_FROM_ROUND := 3           ## 从第几轮起开放"全力支持"（2026-09-18 由 6 提前到 3）
const ALL_IN_BONUS := 2.0              ## 全力支持押中时，额外奖励 = 投入 × 该值
const NORMAL_BONUS := 1.0              ## 普通投入押中时，额外奖励 = 投入 × 该值
const CHANCES_MAX := 3                 ## 玩家的**观望机会**（= 可主动观望的次数；押错不消耗，见不变量 I-21）
const FULL_SUPPORT_THRESHOLD := 150000 ## 结算称号用：点数达到此值即算"点生点成功"

# ---------------------------------------------------------------- 场地与物理
## ⚠️ 本段所有值都是**唯一来源**：场景节点（Arena / CameraRig / Unit3D）只读取，不保存副本。
## 改数值只改这里（并同步 docs/bible 的对应表格）。
var ARENA_HALF_X := 50.0               ## 场地半宽（东西，两队对阵方向）→ 净空 100 m
var ARENA_HALF_Z := 25.0               ## 场地半深（南北）→ 净空 50 m
var WALL_HEIGHT := 3.0                 ## 隐形边界墙的高度（只拦人，不渲染）
var WALL_THICK := 0.5
var FLOOR_MARGIN := 72.0               ## 地板在场地外的富余 m。被击退出界仍有地面；多出来的一圈给场地外的景物
var FLOOR_THICK := 40.0                ## 地板厚度：必须远大于"单帧下落距离"，否则会穿地
var TERMINAL_VELOCITY := 25.0          ## 下落终端速度 m/s，防止穿地并让贴地稳定
## 兴奋圈初始半径（= 60s 出现时的半径）。
## ⚠️ 它**不是自由参数**：圈内外判定是 XZ 平面上的一个圆（`arena.gd#_update_excited`），
## 因此半径必须 ≥ `ARENA_HALF_Z`，否则**站在场地南北边缘正常交战**的单位会被判成"圈外"、
## 持续叠内伤（这个圆在 Z 方向必须罩满整个场地）。
## 52×24 时代 `16 > 12` 成立；场地放大到 100×50 后必须同步放大到 `32 > 25`。
## 它在 X 方向留下的"走廊"半宽 = 半径，这是逼两队互相靠近的唯一机制。
var RING_START_RADIUS := 32.0
var RING_HEIGHT := 4.0
const RING_SEGMENTS := 96

# ---------------------------------------------------------------- 场地风景（纯装饰）
## 依据 `00_world.md#4`：低饱和环境衬托高饱和阵营；风景只负责"场地之外还有一个世界"的
## 氛围与尺度参照，不参与任何玩法。
##
## ⚠️ 两条硬约束（改这段代码之前先读）：
##  1. **一件都不许带碰撞体**。风景一旦挂进 world 层（collision_layer = 1），
##     选手的贴地射线（`unit3d.gd#_grounded`，mask = 1）会把风景误判成地面（表现为悬空 / 下坠），
##     箭矢也会插在风景上（`04_physics.md#8.1`）。所以 `arena.gd#_build_scenery`
##     里只用 MeshInstance3D 拼，绝不 new StaticBody3D / CollisionShape3D。
##  2. **一件都不许压进场地**。道具内边缘距边界墙至少 `ARENA_SCENERY_CLEARANCE`，
##     保证 100 × 50 的净空不被侵占（`04_physics.md#2.2`：边界只用地线表达）。
##     另外南侧（+Z）只放低矮岩石：观赛相机默认就在 +Z 后方（全景与开战机位都在 +Z），
##     南侧放高道具会直接挡住比赛。
var ARENA_SCENERY_CLEARANCE := 2.5       ## 道具内边缘距边界墙的最小外扩 m
var ARENA_SCENERY_MIN_GAP := 3.6         ## 相邻道具之间的最小间距 m（防止互相穿插）
var ARENA_SCENERY_SEED := 20260918       ## 固定随机种子：布局每次运行一致，便于截图比对
var ARENA_SCENERY_ROCK_COUNT := 30       ## 岩石总数（环绕全场，低矮，南侧也放）
var ARENA_SCENERY_TREE_COUNT := 20       ## 树丛总数（只放北侧，形成远景树线）
var ARENA_SCENERY_PILLAR_SPACING := 7.0  ## 立柱等距间隔 m（东 / 西 / 北三边，南侧不放）
var ARENA_SCENERY_PILLAR_HEIGHT := 5.0   ## 立柱高 m
var ARENA_SCENERY_PILLAR_RADIUS := 0.42  ## 立柱半径 m
var ARENA_SCENERY_TREE_HEIGHT := 6.4     ## 树丛总高 m（树干 + 树冠）
var ARENA_SCENERY_STAND_GAP := 7.0       ## 看台内边缘距边界墙的距离 m（东西两端各一座）
var ARENA_SCENERY_STAND_STEPS := 3       ## 看台台阶数
var ARENA_SCENERY_STAND_DEPTH := 3.0     ## 每级台阶进深 m（向外递升）
var ARENA_SCENERY_STAND_RISE := 1.7      ## 每级台阶高度 m
var ARENA_SCENERY_BANNER_HEIGHT := 7.2   ## 队旗杆高 m（东西两端各一面，用队伍色）

## 战场外观。玩家在设置里勾选下面这五种；进入时从勾上的里面抽一个。
## 一个都没勾，用 `BATTLE_SCENE_PLAIN`（现在这套灰场地）。
const BATTLE_SCENE_PLAIN := "plain"
const BATTLE_SCENE_IDS := ["forest", "mountain", "desert", "snow", "city"]
var _battle_scene_enabled := {
	"forest": true,
	"mountain": true,
	"desert": true,
	"snow": true,
	"city": true,
}

func battle_scene_ids() -> Array:
	return BATTLE_SCENE_IDS.duplicate()

func battle_scene_name(scene_id: String) -> String:
	match scene_id:
		"forest":
			return "森林"
		"mountain":
			return "山脉"
		"desert":
			return "沙漠"
		"snow":
			return "雪地"
		"city":
			return "城市"
		_:
			return "灰场地"

func is_battle_scene_enabled(scene_id: String) -> bool:
	return bool(_battle_scene_enabled.get(scene_id, false))

func set_battle_scene_enabled(scene_id: String, enabled: bool) -> void:
	if not _battle_scene_enabled.has(scene_id):
		return
	_battle_scene_enabled[scene_id] = enabled

func battle_scene_snapshot() -> Dictionary:
	return _battle_scene_enabled.duplicate()

## 勾上的场景里随机一个。池子是空的就返回灰场地。
func pick_battle_scene(rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for scene_id in BATTLE_SCENE_IDS:
		if is_battle_scene_enabled(String(scene_id)):
			pool.append(String(scene_id))
	if pool.is_empty():
		return BATTLE_SCENE_PLAIN
	return String(pool[rng.randi_range(0, pool.size() - 1)])

# ------------------------------------------------------- 出生点（后半段成簇刷新）
var SPAWN_RANGE_NEAR := 0.30           ## 出生区距中心线的最近比例（1.0 = 贴边）
var SPAWN_RANGE_FAR := 0.95            ## 出生区距中心线的最远比例
var SPAWN_CLUSTER_RADIUS := 3.4        ## 同兵种聚簇半径 m（纵向 = 沿朝向、正面对进 = 世界 X）
var SPAWN_CLUSTER_ASPECT := 2.5        ## 聚簇在**横向**（垂直于朝向 = 世界 Z）的拉伸倍率
## ⚠️ 「横 / 纵」以**双方朝向**为准，**不看屏幕**（不变量 I-36，见 `04_physics.md#6`）：
## 两队沿 X 对阵 → 横向 = 世界 Z、纵向 = 世界 X。所以"横排"是把簇沿 Z 铺开，不是沿 X。
## 别拿屏幕当参考系：相机默认沿 −Z 看场地，一条横排在屏上会呈现为"自远而近"的纵深——
## 那是刻意的观感，不代表队形叫"纵队"。1.0 = 圆形簇。
var SPAWN_MIN_SEPARATION := 4.0        ## 不同兵种簇心之间的最小间距 m
var SPAWN_MIN_GAP := 1.0               ## 同队选手之间的最小间距 m（防止互相挡射界）
var SPAWN_CLUSTER_TRIES := 40          ## 簇心采样尝试次数
var SPAWN_HEIGHT := 0.40               ## 出生高度 m（略高于地面，避免贴地判定抖动）

# ---------------------------------------------------------------- 出生演出 + 单位拾取
## **买兵时的"从天上掉下来"**（2026-09-27 用户："新增动画购买兵种时令这一队兵种从天上掉下来
## （匀速，只是动画，0.5s内播放完）"）。
## ⚠️ **纯视觉**：偏移只加在模型（`Unit3D._visual`）上，**角色的碰撞体 / 出生高度 / 判定一律不动** ⇒
##    它一落地就能打、也能被打（不变量 I-31~I-34 与"出生点"那套口径都不受影响）。
## ⚠️ **匀速**（线性，不是自由落体）：0.5 s 内从 `UNIT_DROP_HEIGHT` 平滑降到 0；单位是 m / ms。
const UNIT_DROP_HEIGHT := 14.0         ## 掉落动画的起始高度 m（"从天上掉下来"，比人身高高一截）
const UNIT_DROP_MS := 500              ## 掉落动画时长 ms（用户口径"0.5s 内播放完"）
## **拾取单位的那条射线**（点选 / 拖动 / 查看敌方都用它）：只打"两队单位层"⇒ 命中不了地面，不用比距离。
## ⚠️ 2026-09-27 去重：原先 `Roguelike.POST_PICK_*` 与 `Sandbox.PICK_*` **各持一份同值常量**（旧账），
##    现在只有这一处出处（I-15：可调参数全在 `GameConfig`）。
const UNIT_PICK_MASK := (1 << 1) | (1 << 2)
const UNIT_PICK_RANGE := 500.0         ## 射线长度 m（观赛机位在 40~75 m 高，够长即可）

const PROJECTILE_SPEED := 22.0         ## 箭矢飞行速度 m/s
const ARROW_LIFETIME_MS := 4000        ## 飞行超时自毁

# ---------------------------------------------------------------- 沙盒布兵（手动摆放）
## 沙盒模式"左键点地面 / **按住左键拖动连摆**"的两条闸门（2026-09-25 用户裁决：从 `sandbox.gd` **搬进这里** ——
## 不变量 I-15 说"可调参数全部在 `GameConfig`"，它们虽然偏"输入交互"，但既然可调就该住这一处）。
## ⚠️ 它们**不参与战斗模拟**（单位 / 伤害 / AI 一概不读），只管"一笔怎么落点"，口径见 `03_rules.md#10.2`。
const DRAG_MIN_SPACING := 2.5          ## 拖动时离上一笔的最小中心距 m。身体比这更大的，另按脚印分开
const DRAG_STROKE_LIMIT := 60          ## 一笔最多摆几个（**帧率安全阀**，不是玩法限制）

# ---------------------------------------------------------------- 肉鸽模式（2026-09-26 新增，**分步落地**）
## 用户口径（原文）："肉鸽模式的主要玩法：一共10个回合，每个回合开始时会获得一定的补给，通过补给购买兵种或
## 增益来抵挡敌方的进攻…补给：第一回合开始时获得20的补给，此后每回合多5的补给收入（即第二回合开始时获得25补给，
## 第三回合30，以此类推）。血量：基础血量为200，若未击败敌方，则扣除敌方存活兵种总权重的血量。血量降到0及以下则失败"。
##
## ⚠️ **本模式刻意不受 I-20 / I-28 约束**（用户 2026-09-26 裁决：**与沙盒同一条豁免** ——
## 那两条的适用范围再收窄一次，只描述竞猜模式）。理由：肉鸽是"用补给自由买兵"的单人防守玩法，
## 既没有"两队配平"这回事，也没有"每队 ≤3 种"的限制。
## ⚠️ **分步落地**：第一块 = 骨架 + 经济记账；**第二块（商店 / 解锁 / 初始四选一 / 场地格子 / 队形表）
## 已于 2026-09-26 落地** —— 下面两段常量合起来就是它的全部数值。
## ⚠️ **敌人仍未做**（用户："先不做，后面再说"）⇒ `Roguelike.enemy_weight()` 目前恒为 0。
const ROGUELIKE_ROUND_COUNT := 10      ## 一局最多这么多个回合。
										## ⚠️ 与不变量 I-22（竞猜模式的"最多 10 轮"）**只是数字相同**，
										## 两者互不引用、也不共用常量（那条描述的是押注轮次）。
const ROGUELIKE_SUPPLY_START := 25     ## 第 1 回合开始时的补给（2026-10-16：20 → 25。递增不变）
## 此后每回合**多**这么多收入 ⇒ 第 N 回合的收入 = `START + STEP × (N − 1)`
##（2026-10-01：递增由 5 改为 10。2026-10-16：第 1 回合改为 25）
## ⇒ 十回合的收入序列 = 25 / 35 / 45 / 55 / 65 / 75 / 85 / 95 / 105 / 115（本局累计 700）。
const ROGUELIKE_SUPPLY_STEP := 10
const ROGUELIKE_AID_FROM_ROUND := 2
const ROGUELIKE_AID_OFFER_COUNT := 4
const ROGUELIKE_AID_SKIP_SUPPLY := 5
const ROGUELIKE_POST_KILL_SUPPLY := 10
const ROGUELIKE_AID_POST_CLEAR_M := 20.0
const ROGUELIKE_AID_OIL_SPEED_MULT := 0.4
const ROGUELIKE_AID_SMOKE_RANGE_CUT := 10.0
const ROGUELIKE_AID_BURN_TICK := 100.0
const ROGUELIKE_AID_BURN_MS := 15000
const ROGUELIKE_AID_GROUND_TICK_MS := 1000
const ROGUELIKE_AID_ACID_RATIO := 0.03
const ROGUELIKE_AID_SQUAD_CLEAR_M := 3
const ROGUELIKE_AID_MODULE_WEIGHT := 10
const ROGUELIKE_AID_COST_CONTROL_MULT := 0.9   ## 成本控制：此后购买的小队，生命和伤害再 × 本值
const ROGUELIKE_AID_SHIELD_DROP_SCALE := 2.0   ## 空投魔法盾的血量倍数（再乘护盾专家）
const ROGUELIKE_AID_WARD_HP := 1000.0          ## 便携魔法盾基数。实际血量 =（本值 + 庇护的盾血）× 等级 × 护盾专家
const ROGUELIKE_AID_WARD_RADIUS := 15.0        ## 便携魔法盾半径（米）
## 基础血量（用户："基础血量为200"）。⚠️ 它是**玩家**的血，不是单位的血 ——
## 别与 `PROFILES[*]["hp"]`（选手属性表的"血量"）混起来（同"权重 vs 重量"那次一样的坑）。
const ROGUELIKE_HP_MAX := 200

## ---- 肉鸽第二块：商店 / 解锁 / 初始四选一（2026-09-26）----
## 用户口径（2026-09-26 第二轮问答，逐条对应）：
##   · **"点一次买一整队"** ⇒ 一次交易 = 一整"队"，价格 = **一队人数 × 该兵种权重**（补给 : 权重 = 1 : 1）；
##   · **"每回合不设可购买的总权重上限，而是限定最多购买两队兵"** ⇒ `ROGUELIKE_SQUADS_PER_ROUND`
##     ⚠️ **这条改写了第一块里的旧口径**（"每回合可购买的总权重上限 = 2 × 当前补给"**已作废**）；
##   · **解锁价 = ⌊全队总权重 ÷ 2⌋、每回合最多解锁一个** ⇒ `ROGUELIKE_UNLOCK_DIVISOR` / `_PER_ROUND`；
##   · **"初始部队四选一"**：从权重 1 / 2 的兵种里随机挑两个组成一个选择（四个选择两两不同），
##     **选定后每个兵种白送 `ROGUELIKE_STARTER_SQUADS` 队**（2026-10-01：由各一队改为各两队；仍不花钱、不占本回合购买额度）。
const ROGUELIKE_SQUADS_PER_ROUND := 2   ## 每回合最多买几"队"（用户："限定最多购买两队兵"）
const ROGUELIKE_STARTER_SQUADS := 2     ## 四选一选定后，每个起手兵种白送几队
const ROGUELIKE_UNLOCK_PER_ROUND := 1   ## 每回合最多解锁几个兵种
const ROGUELIKE_UNLOCK_DIVISOR := 2     ## 解锁价 = ⌊全队总权重 ÷ 本值⌋（用户："解锁口径要改" ⇒ 按"队"算）
const ROGUELIKE_CELL_SIZE := 2.0        ## 场地格子边长（米）—— 用户："2.0 m 一格"
const ROGUELIKE_START_CHOICE_COUNT := 4 ## 初始四选一的选项个数
const ROGUELIKE_START_WEIGHTS := [1, 2] ## 四选一的抽签池 = 权重落在这一族里的兵种

## ---- 肉鸽第三块：指挥所与增益（2026-09-26）----
## 用户口径（原文，逐条对应）：
##   · "在场地上左半部分的中间和右半部分的中间分别放上两个指挥所（占据3*3）（敌我两边都有），
##      血量均为500，重量9999，无攻击能力，不移动"；
##   · "任意一个指挥所被敌方摧毁都会使我方全体成员移速下降90%，伤害下降90%，持续5s
##     （两个指挥所均被摧毁时，减益的效果和持续时间不叠加，只会刷新持续时间）"；
##   · 点**右方**指挥所买**持续**增益：进攻指令 / 防御指令（各三级，价 10/20/30）、指挥部升级（三级，价 10/15/20）；
##   · 点**左方**指挥所买**单回合**增益：紧急补给（+20 现在 / −30 下回合）、射程 +4 m（价 5）、移速 +1 m/s（价 5）。
## ⚠️ 用户 2026-09-26 的六条补充裁决：每方半场 **2 个**（共 4 个）；**增益买了就永久生效、与指挥所是否被摧毁无关**；
## 买增益**不占**"每回合最多 2 队"的额度、同一回合**可连升多级**；**紧急补给每回合限一次**；
## 防御指令**加上限并补等量当前血**、射程 / 速度对当回合**新买的兵也生效**；判定体 6×6×3 m + weight 999 + 锚定。
const ROGUELIKE_POST_TYPE := "commandpost"
const ROGUELIKE_POST_PER_TEAM := 2                 ## 每方半场两个（用户裁决）
## ---- 肉鸽的场地尺寸（2026-09-26 第六块：用户"增大肉鸽模式的场地（宽变为原来的 1.75 倍）"）----
## ⚠️ **只有肉鸽变大**（用户裁决："只放大肉鸽的场地（竞猜 / 沙盒不变）"）⇒ 这两个常量**只给肉鸽用**，
## 全局的 `ARENA_HALF_X` / `ARENA_HALF_Z` **一个字不动** —— 竞猜的配平面（I-20）、`04_physics.md#2.1`
## 那五条几何约束、出生布局（`make_spawn_layout()`）全都建立在 100×50 上面。
## 落地方式：`Arena` 多两个**实例字段** `half_x` / `half_z`（默认取全局值），`main.gd` 按模式传一套。
## ⚠️ **变的是「宽」= 南北 = 世界 Z**（用户 2026-09-26 更正："你刚刚加长的是场地的长，要加长的是宽"）：
## 对阵方向（X）**保持 50**，南北（Z）**25 → 43.75（×1.75）** ⇒ 场地 100 × 87.5。
## ⚠️ 这条口径与不变量 I-36 一致：「横 = 垂直于朝向 = **世界 Z**」—— 场地表里把 X 叫"半宽"是历史叫法，
## 用户说的"宽"指的是**横排方向**（别被那个名字带偏；本批已经因此返工过一次）。
## ⚠️ **2026-09-27 第七块（用户："场地的长变为原来的 1.5 倍"）**：「长」= **X**（对阵方向，不变量 I-36）
## ⇒ 半宽 **50 → 75**（净空 100 → **150**）；南北那条"宽"仍是 87.5。
## 两端再各长出一条"前进布阵区"（见下面 `ROGUELIKE_ZONE_*`）⇒ X 总跨度 **75 + 37.5 + 75 + 37.5 = 225 m**。
const ROGUELIKE_ARENA_HALF_X := 75.0       ## 肉鸽的场地半宽（对阵方向）⇒ 净空 150 m
const ROGUELIKE_ARENA_HALF_Z := 43.75      ## 肉鸽的场地半深（横排方向 = 用户说的"宽" ⇒ 25 × 1.75）

## 指挥所的摆位：**己方半场的中心**（X）+ **左右两个子半场的中心**（Z）。
## 用户 2026-09-26 第六块："指挥所的位置**依旧保持为己方左半场和右半场的中心**" ⇒ 从场地尺寸**推**出来，
## 不写死 25 / 9 —— 场地一变，它们自动落在新的半场中心（旧值 25 / 9 已删除，见 `99_decisions.md`）。
## ⚠️ "左右"以**该队朝向**为准（不变量 I-36）：0 队朝 +X ⇒ 左 = −Z、右 = +Z。
func roguelike_post_x() -> float:
	return ROGUELIKE_ARENA_HALF_X * 0.5    ## 半场的中心 ⇒ 75 ÷ 2 = 37.5

func roguelike_post_z() -> float:
	return ROGUELIKE_ARENA_HALF_Z * 0.5    ## 每个子半场的中心 ⇒ 43.75 ÷ 2 = 21.875

## ---- 肉鸽第七块：贴在**两条长边外侧**的特殊场地（前进布阵区）----
## 用户原文："在敌我场地的两边再延伸出一个特殊的场地，长度为从己方场地最后方到己方场地四分之三处，
## 宽度为6格（敌我双方都有）在部署阶段'我方'可以在'敌方'的这个场地布置兵种，但我方单位每当部署到这个
## 场地时需要5s准备时间（5s后才能行动，期间会被敌方攻击）。己方的这个特殊区域只有敌方能部署（敌方同理）。
## 在这个区域部署后的下一个回合开始则不需要启动时间。（同理边界向外扩）"
## ⚠️ **2026-09-27 用户红笔标注（扫件）订正了位置**：第一版做成了"东西两端外侧的两条窄走廊" ✗ ——
## 正确的是**贴着南北两条长边、在场地外侧**各一条带子（用户："那个特殊区域加的是这种位置（另一边也要）"）。
## ⇒ 竞技场不再是一个 150 × 87.5 的矩形 + 两端凸出，而是**直接向外扩成 150 × 111.5 的大矩形**
##（南北各加 12 m；"边界向外扩"这句就是这个意思），带子是**矩形内部的南北两条边带**。
## 用户 2026-09-27 四条裁决：① 两条长边各一条、各 **12 m 宽（6 格）**；② 长度 = 从**各自的后方底线**
## 起算到"场地四分之三处" ⇒ **112.5 m**（= 半宽 × 1.5）；③ 归属：**己方那两条只有敌方能布阵、
## 敌方那两条只有我方**（原文："己方的这两条带子归属敌方，敌方的那两条带子归属我方"——后半句
## 用户笔误写成"归属敌方"，按"两边对称"与最初那句"我方可以在敌方的这个场地布置兵种"理解）；
## ④ **不绕角**（只是贴长边）。
## ⚠️ 两条带子各自从**自己的后方底线**起算 56.25 m ⇒ **不再重叠**；中间那一段（当前 19 格）两边都不能布阵。
## ⚠️ 准备期口径不变（2026-09-26 第三条）：**从开战那一刻起算**，这 5 s 里不能移动 / 攻击 / 放技能，
## 但**会被攻击、也会被击退**（与「定身」的区别就在这里）。
const ROGUELIKE_ZONE_DEPTH := 12.0         ## 每条带子沿 Z 的深度（= 6 格 × 2.0 m）
const ROGUELIKE_ZONE_PREP_MS := 5000       ## 落在**敌方**带子里的单位：开战后这么长的准备期

## ⚠️ **2026-09-27 第二次订正（用户原话）**："我方可部署兵种的特殊区域**从敌方场地底线延伸到敌方场地
## 四分之三处**，敌方的可部署场地从我方底线延伸到我方四分之三处"。
## ⇒ 每条带子沿 X 的长度 = **本方半场的 3/4**（从**自己的底线**往内量到 3/4 处），不是"全长的 3/4"：
## 当前 = 75 × 0.75 = **56.25 m** ⇒ 我方占 x ∈ [+18.75, +75]（列 47~74）、敌方占 x ∈ [−75, −18.75]（列 0~27）。
## ⚠️ 两条带子**不再重叠**；中间 19 格（x ∈ [−18.75, +18.75]）带子还在、但**两边都不能布阵**。
## 用户 2026-09-27 前三条裁决不变：① 两条长边各一条、各 12 m 深（6 格）；② 归属 = 己方那条只有敌方能布阵、
## 敌方那条只有我方；③ 不绕角。准备期口径也不变（开战那一刻起算 5 s、可被打可被击退）。
func roguelike_zone_span_x() -> float:
	return ROGUELIKE_ARENA_HALF_X * 0.75

## **竞技场**（含两条带子）的半深 = 主场地半深 + 带子深度（当前 43.75 + 12 = **55.75** ⇒ 总深 111.5）
## ⚠️ `ROGUELIKE_ARENA_HALF_Z` 仍是**主场地**的半深（指挥所 / 子半场 / 出生线都按它算，不受带子影响），
## 只有竞技场的边界与地板用这个"含带子"的值 ⇒ `main.gd` 写 `Arena.half_z` 时用它。
func roguelike_arena_half_z() -> float:
	return ROGUELIKE_ARENA_HALF_Z + ROGUELIKE_ZONE_DEPTH

## 带子沿 X 有几格（`ceil(56.25 / 2.0)` = **29**；最外那一格有 1.75 m 落在带子外、格心仍在带内）
func roguelike_zone_cells() -> int:
	return int(ceil(roguelike_zone_span_x() / ROGUELIKE_CELL_SIZE))

## ---- 带子占哪些行（闭区间；行号 = 现在这套 56 行的全场网格）----
## 格心 = −竞技场半深 + (row + 0.5) × 格边长；当前尺寸下：**北带 = 0~5、南带 = 50~55**（各正好 6 行），
## 中间 6~49 就是原来的主场地（44 行，与第六块那版逐位一致）。
func roguelike_zone_row_south_min() -> int:
	return int(ceil((roguelike_arena_half_z() + ROGUELIKE_ARENA_HALF_Z) / ROGUELIKE_CELL_SIZE - 0.5))

func roguelike_zone_row_south_max() -> int:
	return int(floor(roguelike_arena_half_z() * 2.0 / ROGUELIKE_CELL_SIZE - 0.5))

func roguelike_zone_row_north_min() -> int:
	return 0

func roguelike_zone_row_north_max() -> int:
	return int(floor((roguelike_arena_half_z() - ROGUELIKE_ARENA_HALF_Z) / ROGUELIKE_CELL_SIZE - 0.5))

## ---- 主场地（不含两条带子）占哪些行（闭区间）----
## 当前 = **6 ~ 49**（44 行，与第六块那版逐位一致）—— 里外差的就是南北各 6 行带子。
## ⚠️ 自动落位 / 己方半场的边距判定都要用它，**不能**用整个竞技场的行数（那会把兵摆进带子里）。
func roguelike_field_row_min() -> int:
	return int(ceil((roguelike_arena_half_z() - ROGUELIKE_ARENA_HALF_Z) / ROGUELIKE_CELL_SIZE - 0.5))

func roguelike_field_row_max() -> int:
	return int(floor((roguelike_arena_half_z() + ROGUELIKE_ARENA_HALF_Z) / ROGUELIKE_CELL_SIZE - 0.5))

## ---- 带子占哪些列（闭区间）----
## **己方那一条**（0 队 = 西，只有敌方能布阵）：从己方底线（x = −half_x）往东铺 56.25 m；
## **敌方那一条**（我方布阵用）：从敌方底线（x = +half_x）往西铺同样长度（镜像）。
## 当前尺寸：己方 = 列 **0~27**、敌方 = 列 **47~74**；两段之间 **28~46 那 19 格谁也不能布阵**。
func roguelike_zone_col_own_min() -> int:
	return int(ceil(0.0 - 0.5))                       ## 从西墙那一格起 ⇒ 0

func roguelike_zone_col_own_max() -> int:
	return int(floor(roguelike_zone_span_x() / ROGUELIKE_CELL_SIZE - 0.5))

func roguelike_zone_col_foe_min(cols: int) -> int:
	return int(ceil((cols * ROGUELIKE_CELL_SIZE - roguelike_zone_span_x()) / ROGUELIKE_CELL_SIZE - 0.5))

func roguelike_zone_col_foe_max(cols: int) -> int:
	return cols - 1

## 这一列在不在"两条带子"里（**不分归属** —— 只是几何上属于带子）：
## 判"这一格是不是带子里的死区（两边都不能布阵）"用它。
func roguelike_col_in_zone(col: int, cols: int) -> bool:
	if col >= roguelike_zone_col_own_min() and col <= roguelike_zone_col_own_max():
		return true
	return col >= roguelike_zone_col_foe_min(cols) and col <= roguelike_zone_col_foe_max(cols)
## 被摧毁 ⇒ **该指挥所所属那一方**全体：移速与伤害都降到 `POST_DEBUFF_MULT`（用户："下降90%"），
## 持续 `POST_DEBUFF_MS`（5 s）。⚠️ 两个都被摧毁时**只刷新持续时间、不叠加**（用户口径）。
const ROGUELIKE_POST_DEBUFF_MULT := 0.10
const ROGUELIKE_POST_DEBUFF_MS := 5000
const ROGUELIKE_POST_DEBUFF_CUT_MS := 1000         ## 指挥部每升一级，这个减益 −1 s（用户）
## 持续增益（**右方**指挥所）：三级 + 价格表。`STEP` = 每级的加成（12%）。
const ROGUELIKE_BUFF_ATTACK := "attack"            ## 进攻指令：全体伤害 +12%/24%/36%
const ROGUELIKE_BUFF_DEFENSE := "defense"          ## 防御指令：全体生命上限 +12%/24%/36%（并补等量当前血）
const ROGUELIKE_BUFF_UPGRADE := "upgrade"          ## 指挥部升级：指挥所 +300 血 / 摧毁减益 −1 s
const ROGUELIKE_BUFF_STEP := 0.12
const ROGUELIKE_BUFF_MAX_LEVEL := 3
const ROGUELIKE_BUFF_HP_PER_LEVEL := 1000.0        ## 指挥部每升一级，指挥所加这么多血
const ROGUELIKE_BUFF_PRICES := {
	"attack": [10, 20, 30],
	"defense": [10, 20, 30],
	"upgrade": [10, 15, 20],
}
## 单回合增益（**左方**指挥所）：只在当回合有效，回合开始时清掉。
const ROGUELIKE_ROUND_BUFF_SUPPLY := "supply"      ## 紧急补给：立刻 +20，**下回合开始 −30**（可为负；每回合限一次）
const ROGUELIKE_ROUND_BUFF_RANGE := "range"        ## 射程 +4 m（**只对远程单位**；价 5）
const ROGUELIKE_ROUND_BUFF_SPEED := "speed"        ## 移速 +1 m/s（价 5）
const ROGUELIKE_LOAN_GAIN := 20                    ## 紧急补给：现在拿到多少
const ROGUELIKE_LOAN_DEBT := 30                    ## 紧急补给：下回合开始扣多少（用户："失去30"）
const ROGUELIKE_ROUND_RANGE_BONUS := 4.0           ## 米
const ROGUELIKE_ROUND_SPEED_BONUS := 1.0           ## m/s
const ROGUELIKE_ROUND_BUFF_PRICE := 5              ## 射程 / 速度各 5（紧急补给是"借"，价 0）
## ---- 单位等级（2026-09-27 第三轮：用户"在肉鸽模式新增单位的等级"）----
## 口径四条（用户原文 + 同轮澄清）：
##   ① **一队同级**、**最高 9 级**；② **倍率 = L**（2 级 2 倍、9 级 9 倍）——⚠️ **倍率是独立乘区**：
##      百分比加成彼此相加（同一乘区），倍率与它们**逐个相乘**（用户："三个增益：血量+20%、变为2倍、变为3倍
##      ⇒ 最终 1.2 × 2 × 3 = 7.2 倍"）；③ 升级经验：**L→L+1 要 L × 该队总权重**（基础 = 总权重，每级多一倍）；
##      ④ 击杀得经验 = **被杀单位的权重 × 它的等级**（1 级矛兵 1 点、5 级长矛兵 5 点）。
const ROGUELIKE_LEVEL_MAX := 9                     ## 等级上限（用户："最高9级"）
## "精英招募"（左方指挥所的第 5 条单回合增益）：**本回合买下的兵 +1 级**（用户："本回合招募的兵种等级增加1级"）。
## ⚠️ 价 **10**（用户同日给定）、**封顶 9 级**、**只对"买"生效**（起手白送的两队不算 —— 用户："只给买的"）。
const ROGUELIKE_ROUND_BUFF_ELITE := "elite"
const ROGUELIKE_ELITE_PRICE := 10
## "左 / 右"这两套增益各挂在哪个指挥所上（按**该队朝向**分左右，见上面 `POST_Z` 的注）。
const ROGUELIKE_POST_SIDE_ROUND := "left"          ## 左方 = 单回合增益
const ROGUELIKE_POST_SIDE_STEADY := "right"        ## 右方 = 持续增益

## ---- 肉鸽第四块：布阵交互（2026-09-26）----
## 用户口径（原文）："点击我方单位可以选中这一队单位，查看其最终数值…"、"靠拖动单位可以移动其位置（单位必须限定在
## 格子内，格子被其他单位占据则无法放置），但**只有当回合购买的兵能够移动位置**"、"选中单位或拖动单位时按 R 可以使
## 单位的布阵旋转 90°（如横着变成竖着），但**单位的方向依旧是面向敌方**"。
## ⚠️ 随后用户改了两条：① 旋转**只在拖动移动单位时**可用；② 触发键由 **R 改成鼠标右键**。
## ⚠️ 这个阈值是"输入手感参数" ⇒ 按 `DRAG_MIN_SPACING` 的先例也住 `GameConfig`（I-15）。
const ROGUELIKE_DRAG_SLOP := 6.0       ## 按下后移动超过这么多**像素**才算"拖动"（否则算一次点选）

## ---- 肉鸽第五块：场地道具（陷阱 / 魔法盾，2026-09-26）----
## 用户口径（原文）：陷阱"当自身 8m 范围内出现敌军时，延迟 1s，然后以那名敌军为中心触发半径 10m 的爆炸，
## 造成 200 点伤害并使移动速度降低 80%，持续 3s，价格 5。陷阱只要未触发就会一直存在，直至触发后在下回合开始时移除"；
## 魔法盾"与陷阱相同的放置方式，不占用格子。血量 100，不移动，不攻击。大小为 14m 半径的圆，可以抵挡所有敌方的
## 远程攻击（不会被主动锁定，火枪无法穿透），没有碰撞体积……若敌方远程在圆圈内发动攻击，攻击也无法穿过魔法盾的边……
## 价格 10……回合开始时回满血。放置时不能放置到会把敌方领地包括住的位置"。
## ⚠️ 两件都是**肉鸽自己的场地道具**（用户 2026-09-26 裁决）⇒ **不进 `PROFILES`、不算兵种**，
## 所以 I-26 的"七项属性"与 I-27 的权重都不涉及它们；数值全部住这里（不变量 I-15）。
## ⚠️ 用户 2026-09-26 同一批还有两条补充口径：**放置 = 从商店按钮拖到场上**（松手时位置不可部署
## 就什么都不做、**也不扣补给**）；**不占**"每回合最多 2 队"的额度（与增益同例）。
const ROGUELIKE_PROP_TRAP := "trap"                    ## 陷阱的 kind 键
const ROGUELIKE_PROP_SHIELD := "magic_shield"          ## 魔法盾的 kind 键
const ROGUELIKE_TRAP_PRICE := 5                        ## 陷阱价格
const ROGUELIKE_TRAP_TRIGGER_RADIUS := 8.0             ## 敌军进到这个半径（米、中心距）就上弦
const ROGUELIKE_TRAP_DELAY_MS := 1000                  ## 上弦后延迟这么久才炸（绝对毫秒，I-13）
const ROGUELIKE_TRAP_BLAST_RADIUS := 10.0              ## 爆炸半径（米、中心距，同"落点溅射"那条口径）
const ROGUELIKE_TRAP_DAMAGE := 500.0                   ## 爆炸伤害
const ROGUELIKE_TRAP_SLOW_MULT := 0.20                 ## 移速降低 80% ⇒ 剩 20%
const ROGUELIKE_TRAP_SLOW_MS := 3000                   ## 减速持续 3 s
const ROGUELIKE_SHIELD_PRICE := 10                     ## 魔法盾价格
const ROGUELIKE_SHIELD_RADIUS := 14.0                  ## 魔法盾的圆半径（米）
const ROGUELIKE_SHIELD_HP := 1000.0                    ## 魔法盾血量（回合开始时回满）
## ⚠️ **2026-09-26 由 100 改 1000**（用户口径："能量盾的血为1000" —— ⚠️ 用户确认"能量盾"是**笔误**，
## 名字仍叫**魔法盾**、kind 串仍是 `magic_shield`）。改这一条的连带事实：被挡下的弹**会打掉盾的血**
##（本实现的取舍，见 `Roguelike._poll_arrow_blocks()`）⇒ 100 血只扛得住 2 发长弓（90/发），
## 1000 血 ≈ 11 发 —— 这才配得上"抵挡所有敌方的远程攻击"这条口径。
const ROGUELIKE_PROP_MIN_SPACING := 2.0                ## 两件道具的中心最近距离（= 一格，免得叠在一起）

## 道具的价格（界面与玩法侧**共用这一个口**，别各写一份）
func roguelike_prop_price(kind: String) -> int:
	if kind == ROGUELIKE_PROP_TRAP:
		return ROGUELIKE_TRAP_PRICE
	if kind == ROGUELIKE_PROP_SHIELD:
		return ROGUELIKE_SHIELD_PRICE
	if kind == ROGUELIKE_PROP_BEACON:
		return ROGUELIKE_BEACON_PRICE
	return 0

## 道具的显示名（顶栏 / 卡片 / 反馈行共用）
func roguelike_prop_name(kind: String) -> String:
	if kind == ROGUELIKE_PROP_TRAP:
		return "陷阱"
	if kind == ROGUELIKE_PROP_SHIELD:
		return "魔法盾"
	if kind == ROGUELIKE_PROP_BEACON:
		return "移动信标"
	return kind

## 两件道具的 kind 清单（顺序 = 商店里摆的顺序）
func roguelike_prop_kinds() -> Array:
	return [ROGUELIKE_PROP_TRAP, ROGUELIKE_PROP_SHIELD, ROGUELIKE_PROP_BEACON]

## ---- 肉鸽第六块：紧急招募（**左方**指挥所的第 4 条单回合增益，2026-09-26）----
## 用户："紧急招募：本回合可额外招募一队兵种" ⇒ 效果 = 本回合的"最多买 2 队"临时 +1。
## ⚠️ 价 5（用户裁决："两个都 5" —— 与射程增加 / 速度增加同档，`ROGUELIKE_ROUND_BUFF_PRICE` 就是它）。
## ⚠️ 它**只是额度 +1**：不改 `ROGUELIKE_SQUADS_PER_ROUND` 本身（那是每回合的基准），
## 单回合的额度由 `Roguelike.squad_limit_this_round()` 现算（买过就 +1，回合开始清）。
const ROGUELIKE_ROUND_BUFF_RECRUIT := "recruit"
const ROGUELIKE_RECRUIT_BONUS_SQUADS := 1      ## 本回合的额外组队名额（用户："额外招募一队"）

## ---- 肉鸽第三轮：测试敌人的**等级**（2026-09-27）----
## 用户给的经验口径里出现了"5 级长矛兵"⇒ 敌方也得有等级。当前唯一来源仍是测试敌人，
## 所以先给它一个旋钮（默认 1 = 与之前逐位相同）：把它调高就能验证"击杀高等级给更多经验"。
## ⚠️ 以后真敌人按波次带等级时，把等级写进 `_spawn_foe_squad()` 的账本条目即可（界面不用改）。
const ROGUELIKE_TEST_ENEMY_LEVEL := 1

## ---- 肉鸽第六块：移动信标（**右方**指挥所卖的场地道具，2026-09-26）----
## 用户口径（原文）："移动信标：获得一个道具"移动信标"……在部署阶段可以放置，拖动到场上放置后半径 10m 内的
## 所有兵种（同一队兵只有被包括的那一部分兵被影响）在战斗开始后会**优先跟着移动信标标定的路线移动**
## （攻击时也会移动），移动到终点时开始自由移动。如何放置：拖动放置到场上后还能够点击两次来决定单位往
## 那个方向移动，第一次点击确定从信标方位移动至第一次点击的位置（最远 30m），第二次点击决定从第一次点击的
## 位置移动到第二次点击的位置（最远 30m），信标可以放置在任意位置（包括敌方）。
## 注意：信标的移动只是一个区域，并不代表所有单位要移动到那个点，而是代表所有被影响单位按信标划出的两条线移动。"
## ⚠️ 用户 2026-09-26 三条补充裁决：① 移动方式 = **保持队形沿路线平移**（各自到路线的垂直偏移不变）；
## ② 购买流程 = 右方指挥所面板买下 ⇒ **道具行多一张卡**，再从卡片拖到场上；
## ③ 某一段点到 30 m 之外 ⇒ **自动夹到 30 m**（方向取点击方向）。
const ROGUELIKE_PROP_BEACON := "beacon"
const ROGUELIKE_BEACON_PRICE := 5              ## 信标价格（用户裁决："两个都 5"）
const ROGUELIKE_BEACON_RADIUS := 10.0          ## 影响半径（米、三维中心距）：战斗开始时半径内的我方单位受它指挥
const ROGUELIKE_BEACON_SEGMENT_MAX := 30.0     ## 路线每一段的最远距离（米）—— 超了自动夹取
const ROGUELIKE_BEACON_POINT_COUNT := 2        ## 放置之后还要点几下（用户："点击两次"）

## 遣返（右方指挥所，与移动信标同一类道具，2026-10-01）。
## 买一次永久拥有；每回合从道具卡拖到一队兵上，把这一队永久撤走，退回已花补给的一半（不含科技、不含解锁）。
const ROGUELIKE_RECALL_PRICE := 5

## ---- 肉鸽第六块：临时测试敌人（用户："先在敌方场地中心放置一个敌人以便测试"）----
## 用户选定：**1 个剑盾兵**（近战、能自己走进我方半场 ⇒ 顺带把陷阱 / 魔法盾 / 指挥所减益都变成可测）。
## ⚠️ 关掉它 = 回到"场上没有敌人"的老状态（`ROGUELIKE_TEST_ENEMY_ENABLED := false` 一行）。
## ⚠️ 位置 = **敌方半场的中心**（从场地尺寸推 ⇒ 见 `Roguelike._test_enemy_pos()`）。
const ROGUELIKE_TEST_ENEMY_ENABLED := true
const ROGUELIKE_TEST_ENEMY := "sword"
## 这一支测试敌人**几个兵**（2026-09-27 加：敌方现在按"队"记账，队得有个编制数）。
## ⚠️ 用户原话是"先在敌方场地中心放置**一个**敌人以便测试" ⇒ 默认 **1**；改成 N 就是"一队 N 个剑盾兵"
##（`_spawn_foe_squad()` 会沿横排铺开，界面按队显示"在场 N / 共 M"）。
const ROGUELIKE_TEST_ENEMY_COUNT := 1

## 十回合敌方波次。每一项是 `{squad_weight, squads}`：
## `squad_weight` = 这一队的总权重（只有 10 / 15 / 25），`squads` = 几队。
## 具体兵种不写在这里：生成时从「一队总权重正好是这个数」的可买兵种里各抽一次。
## 一队总权重 = 人数 × 兵种权重，所以 10 覆盖权重 1 / 2 / 10，15 覆盖 3 / 5，25 覆盖 25。
## 表内权重合计 = `roguelike_enemy_weight_target()`。侧翼抽走的队也算在这张名单里，不另加权重。
## 等级不写在这张表里：见 `roguelike_enemy_squad_level()`。先写 10、再写 15、最后写 25，队尾抬级落在更重的档。
## 总权重是一次函数：`60 + 30×(回合−1)` ⇒ 60 / 90 / 120 / 150 / 180 / 210 / 240 / 270 / 300 / 330。
## 第 1 回合 60，第 9 回合 300。人数随抽到的兵种变；按「10 档最多 10 人、15 档最多 5 人、25 档 1 人」估，每回合最多 60 人。
const ROGUELIKE_ENEMY_WEIGHT_BASE := 60
const ROGUELIKE_ENEMY_WEIGHT_PER_ROUND := 30
## 生存难度。后一档在前一档上叠加；没写到的项目保持前一档。
## 「不可能的奇迹」的总权重回到上面这组 60 / 30，波次表也仍用 `ROGUELIKE_ENEMY_WAVES`。
const ROGUELIKE_DIFFICULTY_VERY_EASY := "very_easy"
const ROGUELIKE_DIFFICULTY_EASY := "easy"
const ROGUELIKE_DIFFICULTY_NORMAL := "normal"
const ROGUELIKE_DIFFICULTY_HARD := "hard"
const ROGUELIKE_DIFFICULTY_VERY_HARD := "very_hard"
const ROGUELIKE_DIFFICULTY_TRANSCEND := "transcend"
const ROGUELIKE_DIFFICULTY_MIRACLE := "miracle"
const ROGUELIKE_DIFFICULTY_ORDER: Array = [
	ROGUELIKE_DIFFICULTY_VERY_EASY,
	ROGUELIKE_DIFFICULTY_EASY,
	ROGUELIKE_DIFFICULTY_NORMAL,
	ROGUELIKE_DIFFICULTY_HARD,
	ROGUELIKE_DIFFICULTY_VERY_HARD,
	ROGUELIKE_DIFFICULTY_TRANSCEND,
	ROGUELIKE_DIFFICULTY_MIRACLE,
]
const ROGUELIKE_DIFFICULTY_DEFAULT := ROGUELIKE_DIFFICULTY_VERY_EASY
const ROGUELIKE_DIFFICULTY_WEIGHT_BASE := 50
const ROGUELIKE_DIFFICULTY_WEIGHT_STEP := 20
const ROGUELIKE_DIFFICULTY_STEP_BONUS := 5
const ROGUELIKE_DIFFICULTY_BASE_BONUS := 5
const ROGUELIKE_DIFFICULTY_LEVEL_FROM_ROUND := 3
const ROGUELIKE_DIFFICULTY_EASY_LEVEL_DENOM := 8
const ROGUELIKE_DIFFICULTY_HARD_LEVEL_DENOM := 4
const ROGUELIKE_DIFFICULTY_LEVEL3_FROM_ROUND := 7
const ROGUELIKE_DIFFICULTY_TECH_FROM_ROUND := 3
const ROGUELIKE_DIFFICULTY_TECH_ALL_ROUND := 7
const ROGUELIKE_DIFFICULTY_TECH_HALF_DENOM := 2
## 拆队时的目标比例：第 1 回合偏 10，第 10 回合偏 25，15 留在中间。
const ROGUELIKE_DIFFICULTY_PACK_EARLY_10 := 0.70
const ROGUELIKE_DIFFICULTY_PACK_LATE_10 := 0.15
const ROGUELIKE_DIFFICULTY_PACK_EARLY_25 := 0.10
const ROGUELIKE_DIFFICULTY_PACK_LATE_25 := 0.70
## 远程（含持续照射）与火焰拳：敌方半场内缩。边缘这几格，加上面向我方的那几格，都不落子。
const ROGUELIKE_ENEMY_EDGE_CELLS := 3
const ROGUELIKE_ENEMY_FRONT_CELLS := 8
## 投石车、弩车、火枪手面向我方的内缩比其他远程更深。
const ROGUELIKE_ENEMY_SIEGE_FRONT_CELLS := 15
const ROGUELIKE_ENEMY_SIEGE_TYPES: Array = ["catapult", "ballista", "musket"]
## 近战里唯一按远程站位的兵种。
const ROGUELIKE_ENEMY_BACKLINE_MELEE: Array = ["flamefist"]
## 近战抽到「已经落在某支远程正前方」的格子时，额外加上的抽取权重。
const ROGUELIKE_ENEMY_MELEE_FRONT_WEIGHT := 1000
## 侧翼：第 3～5 回合 50% 随机一侧；第 6～8 回合每一侧各自 50%；第 9 回合两侧都有；第 10 回合没有。
const ROGUELIKE_ENEMY_FLANK_FROM_ROUND := 3
const ROGUELIKE_ENEMY_FLANK_SPLIT_FROM_ROUND := 6
const ROGUELIKE_ENEMY_FLANK_BOTH_ROUND := 9
const ROGUELIKE_ENEMY_FLANK_LAST_ROUND := 9
const ROGUELIKE_ENEMY_FLANK_CHANCE := 0.5
const ROGUELIKE_ENEMY_WAVES: Array = [
	## 1：60 = 6×10
	[{"squad_weight": 10, "squads": 6}],
	## 2：90 = 3×10 + 4×15
	[{"squad_weight": 10, "squads": 3}, {"squad_weight": 15, "squads": 4}],
	## 3：120 = 3×10 + 6×15
	[{"squad_weight": 10, "squads": 3}, {"squad_weight": 15, "squads": 6}],
	## 4：150 = 1×10 + 6×15 + 2×25
	[{"squad_weight": 10, "squads": 1}, {"squad_weight": 15, "squads": 6},
		{"squad_weight": 25, "squads": 2}],
	## 5：180 = 2×10 + 4×15 + 4×25
	[{"squad_weight": 10, "squads": 2}, {"squad_weight": 15, "squads": 4},
		{"squad_weight": 25, "squads": 4}],
	## 6：210 = 2×10 + 6×15 + 4×25
	[{"squad_weight": 10, "squads": 2}, {"squad_weight": 15, "squads": 6},
		{"squad_weight": 25, "squads": 4}],
	## 7：240 = 2×10 + 3×15 + 7×25
	[{"squad_weight": 10, "squads": 2}, {"squad_weight": 15, "squads": 3},
		{"squad_weight": 25, "squads": 7}],
	## 8：270 = 2×10 + 5×15 + 7×25
	[{"squad_weight": 10, "squads": 2}, {"squad_weight": 15, "squads": 5},
		{"squad_weight": 25, "squads": 7}],
	## 9：300 = 1×10 + 6×15 + 8×25
	[{"squad_weight": 10, "squads": 1}, {"squad_weight": 15, "squads": 6},
		{"squad_weight": 25, "squads": 8}],
	## 10：330 = 2×10 + 4×15 + 10×25
	[{"squad_weight": 10, "squads": 2}, {"squad_weight": 15, "squads": 4},
		{"squad_weight": 25, "squads": 10}],
]
## 波次在敌方半场的排距（米）。前排从 14 m 起，每排 +8 m；34～50 m 是指挥所那一截，跳过去。
const ROGUELIKE_ENEMY_WAVE_RANK_M := 8.0
const ROGUELIKE_ENEMY_WAVE_FRONT_X := 14.0
const ROGUELIKE_ENEMY_WAVE_SKIP_X := 34.0
const ROGUELIKE_ENEMY_WAVE_REAR_X := 50.0
## 敌方科技从第几回合开始。此前为 0。同一兵种这一回合共用抽到的那一批。
const ROGUELIKE_ENEMY_TECH_FROM_ROUND := 3
## 敌方等级从第几回合开始抬。此前整波 1 级。最后一回合整波都是 `ROGUELIKE_ENEMY_LEVEL_LAST`。
const ROGUELIKE_ENEMY_LEVEL_FROM_ROUND := 3
const ROGUELIKE_ENEMY_LEVEL_LAST := 4
## 从起始回合起，每过这么多回合，每个兵种再多 1 条（第 3～4 回合 1 条，第 5～6 回合 2 条，依此）。
const ROGUELIKE_ENEMY_TECH_STEP_ROUNDS := 2

## 六档"队"表（用户给定的队形表）：权重 → **这一队排成几列几行（按"兵"数）+ 每个兵占几格**。
## ⚠️ 轴的叫法照 `04_physics.md#6` 与不变量 I-36：**横 / 纵以双方朝向为准** ——
##   `across` / `unit_width` 是**横**（垂直于朝向 = 世界 Z）、`deep` / `unit_depth` 是**纵**（沿朝向 = 世界 X）。
## 从它推出来的三个数（`roguelike_squad_size/width/depth/cost()`，**不要在这里另写一份**）：
##   一队人数 = `across × deep`；外框（格）= （`across × unit_width`）横 ×（`deep × unit_depth`）纵；
##   一队价格 = 人数 × 权重 ⇒ 六档依次 **10 / 10 / 15 / 15 / 10 / 25** 补给
##（⇒ 第 1 回合的 20 补给正好买 2 队便宜的，与"每回合最多 2 队"同拍）。
const ROGUELIKE_SQUAD_TABLE := {
	1: {"across": 5, "deep": 2, "unit_width": 1, "unit_depth": 1},    ## 10 人排成 5 横 × 2 纵、每人 1 格
	## ⚠️ **2026-09-27 第九轮（用户："肉鸽中权重2的兵种占据前后2格，自己站在中间"）**：
	## 权重 2 的每个兵改成占 **1 横 × 2 纵**（`unit_depth` 1 → 2）⇒ 前后两格都算它的，
	## 而站位取那块 2 格的正中（`Roguelike._squad_centers()` 里 `at.x += (ext.y − 1) × 格 ÷ 2`）
	## ⇒ 观感 = "骑着/摆着的大件压在前后两格上、人站在缝上"。全队外框因此 5 横 × 2 纵 = 10 格。
	2: {"across": 5, "deep": 1, "unit_width": 1, "unit_depth": 2},    ## 5 人排成 5 × 1、每人占 1 × 2 格（前后 2 格）
	3: {"across": 5, "deep": 1, "unit_width": 1, "unit_depth": 1},    ## 5 人排成 5 × 1
	5: {"across": 3, "deep": 1, "unit_width": 2, "unit_depth": 2},    ## 3 人排成 3 × 1、每人占 2 × 2 格
	10: {"across": 1, "deep": 1, "unit_width": 3, "unit_depth": 3},   ## 1 人占 3 × 3 格
	25: {"across": 1, "deep": 1, "unit_width": 4, "unit_depth": 4},   ## 1 人占 4 × 4 格
}

# ---------------------------------------------------------------- 击退
## 2026-09-18 改口径（不变量 I-26 新增第七项「重量」）：它现在是**每单位击退数值的初速**。
## 冲量 = 本值 × 攻击者的 `"knockback"`（长矛兵 2.0），实际位移再除以**被击退者的重量**（`"mass"`）。
## 长矛兵打重量 1 的单位 ⇒ 7.5 × 2 ÷ 1 = 15.0 m/s —— 与改口径之前逐位相同（单次推开 ≈ 1.15 m）。
var KNOCKBACK_SPEED := 7.5
var KNOCKBACK_DECAY := 13.0            ## 击退速度每秒衰减
var KNOCKBACK_CD_MS := 1000            ## 同一选手被击退的最短间隔（≈ 长矛兵攻击间隔）
## 击退动量转移（2026-09-18）：被击退的单位撞到别的单位时，把自己**当前速度的这个比例**传过去。
## 用 `tap_knockback()` 做闸门——每个单位 `KNOCKBACK_CD_MS` 内只能被击退一次，
## 所以"多米诺"链条天然会在 1 s 内衰减完，不会无限传递。
var KNOCKBACK_TRANSFER := 0.6          ## 撞人时转移的动量比例（0 = 不传递，1 = 全额传递）

# ---------------------------------------------------------------- 选手动作手感
## 这些是"表现层"参数，不影响胜负判定，但会影响观感与命中宽容。
const UNIT_ROTATION_SPEED := 9.0       ## 转向角速度 rad/s
const UNIT_HIT_FLASH_MS := 140         ## 受击闪白时长 ms
const UNIT_WINDUP_RATIO := 0.30        ## 攻击前摇占攻击间隔的比例（默认值，可被 PROFILE 的 windup_ratio 覆盖）
const UNIT_THRUST_DISTANCE := 0.55     ## 突刺型武器（长矛）出手时沿武器轴向前推出的距离 m
## 手臂姿态（2026-11-02 新增，用户："给所有士兵做上符合建模的战斗动画，比如射箭时手要拉弓"）。
## 全部只喂 `Unit3D._update_arm_pose()`：它每帧把**前臂**重新摆到「肘 → 当前手」之间，
## 于是武器挥到哪、手就在哪，手臂不再和武器脱节（判据：不改任何出手节奏，纯表现）。
const UNIT_ARM_FOLLOW := 0.55          ## 手跟随武器的程度（1 = 完全跟随；留一点余量，动作不至于发僵）
const UNIT_ARM_REACH_MAX := 0.62       ## 肩到手的最大伸直距离 m（超过就夹住，免得前臂被拉成面条）
const UNIT_BOW_DRAW_DISTANCE := 0.26   ## 弓手拉弦：拉弦手沿本体 **+Z**（身后）后撤的距离 m
## 拉弓时的整弓姿态（2026-11-02 新增，用户："把弓抬到水平，做得真实一点"）。
## 真实的拉弓 = **持弓臂前伸、弓身竖直**；原先弓手走 `is_ranged()` 那条通用支
## （`rotation.x = −0.35 × swing`，绕脚下原点转 ⇒ 弓梢在命中帧往前栽 0.4 rad），读起来像"弓倒了"。
## 现在拉弓期间**不转、只平移**：整把弓抬到肩高、往前送一截，命中帧正好抬满。
## ⚠️ 纯表现：不动 `_next_hit_ms` / `_swing_from_ms`，出手节奏一格不动（I-13）。
const UNIT_BOW_RAISE_HEIGHT := 0.22    ## 拉弓时整把弓抬高的距离 m（弓从胸口抬到肩高）
const UNIT_BOW_EXTEND_DISTANCE := 0.12 ## 拉弓时整把弓沿本体 **−Z**（身前）送出去的距离 m
const UNIT_MUSKET_RECOIL_DISTANCE := 0.10  ## 火枪后坐：枪身沿本体 **+Z** 后退的距离 m
const UNIT_MUSKET_RECOIL_TILT := 0.14      ## 火枪后坐：枪口上跳角 rad
const UNIT_CONTACT_RATIO := 1.18       ## 近战命中宽容系数（击退会把目标推出射程）
const UNIT_CORPSE_FADE_MS := 700       ## 阵亡倒地演出时长 ms
const UNIT_STOP_DECELERATION := 30.0   ## 停下时的减速度 m/s²
const UNIT_BOB_AMPLITUDE := 0.03       ## 待机浮动幅度 m
## 剑盾兵的盾牌让位（纯表现；格挡判定只看 `Unit3D._striking`，见 `04_physics.md#7.1.1`）：
## 平时盾面朝前、挡在身前；出手窗口内转到身侧——玩家要能一眼看出"这会儿挡不住箭"。
const UNIT_SHIELD_SWING := Vector3(0.0, 1.45, 0.0)       ## 让位时的额外旋转 rad（盾面转向身侧）
const UNIT_SHIELD_OFFSET := Vector3(-0.22, -0.10, 0.26)  ## 让位时的额外位移 m（离开身前、贴到身侧）
## 剑盾兵的过顶劈砍（2026-11-03 新增，用户："建模和动画像已发售的游戏，更自然、更美观"）。
## 旧版 `_animate_attack()` 的挥砍支**只转 `Sword`、握点(手)一动不动** ⇒ 手臂像焊在腰上、剑在原地绕圈。
## 现在把手也一起抬放（前臂由 `_update_arm_pose()` 自动接回「肘 → 手」），并拆成三段：
##   ① 蓄力 → ② 下劈（**命中帧正好劈到位**）→ ③ 跟随过冲后回位。
## ⚠️ 纯表现：`_next_hit_ms` / `_swing_from_ms` 一格不动，命中帧仍是动画顶点（`04_physics.md#3.5` 的硬性质）。
const UNIT_SWORD_COCK_TILT := 0.26     ## 蓄力：剑越过竖直再往后仰的角度 rad（扛到肩后）
const UNIT_SWORD_COCK_LIFT := 0.20     ## 蓄力：握点抬高的距离 m（手举到肩上）
## ⚠️ **2026-11-03：0.10 → 0**（用户："剑穿了肩甲的膜"）。护肩是个**球壳**
##（球心 (±0.30, 1.35, 0)、半径 0.2185 / 0.1045 / 0.19，见 `unit_factory.gd#_refine_sword_armor()`），
## 而握点在正下方 0.30 m 处 ⇒ **剑身只要在护肩那个高度上落进 z ∈ ±0.19 就会从壳里穿出来**。
## 原来的"往后收 0.10 m"正好把剑身拖回壳里。现在蓄力**只抬不后收**（手抬到肩高、剑越过竖直后仰 15°），
## 观感仍是"蓄势待发"，但剑身整段留在护肩前面。
const UNIT_SWORD_COCK_BACK := 0.0      ## 蓄力：握点往身后（+Z）收的距离 m
const UNIT_SWORD_CHOP_TILT := 1.62     ## 下劈：从竖直往前压的角度 rad（≈93° ⇒ 命中帧剑尖在身前略朝下，带跟随感）
## ⚠️ **2026-11-03：0.30 → 0**（用户："砍下去也要刀刃朝前"）。剑身的菱形截面已经把**刃口转到朝前**
##（见 `unit_factory.gd#_sword_blade_mesh()`）⇒ 这一格是绕**剑身长轴**的滚转，非零值会把刃口拧出下劈平面，
## 命中帧变成"斜着削"。取 0 ⇒ 刃口全程留在这个平面里、正对劈下去的方向。
const UNIT_SWORD_CHOP_SIDE := 0.0      ## 下劈：绕 Z 的横扫分量 rad（0 = 纯上下劈；非零 = 刃口拧出劈砍平面）
const UNIT_SWORD_CHOP_REACH := 0.14    ## 下劈：握点往前（−Z）送的距离 m
const UNIT_SWORD_CHOP_DROP := 0.05     ## 下劈：握点往下压的距离 m
const UNIT_SWORD_COCK_END := 0.34      ## 前摇里"蓄力"占的比例，之后才开始下劈
const UNIT_SWORD_RECOVER := 0.55       ## 收招里"剑落回静止"占的比例（剩下的时间保持静止等下一起手）
## 骑士的大剑过顶劈砍（2026-11-03，用户："模仿剑盾兵把剩下的角色的建模和战斗动画都更新一下"）。
## 与 `UNIT_SWORD_*` **同构**（同样拆成 蓄力 → 下劈 → 跟随 三段、命中帧仍是动画顶点），
## 只把幅度按"更重的兵种"放大：手抬得更高、剑后仰更多、砸下去的角度更陡、送出去更远。
## ⚠️ `UNIT_KNIGHT_COCK_BACK` 仍必须是 **0**：骑士的护肩同样是球壳（球心 (±0.35, 1.37, 0)、
## 半径 0.2415 / 0.1218 / 0.21），而剑身宽轴半宽 = 0.045 × 1.30 = **0.0585**
## ⇒ 剑身在护肩那一层要让开 |z| ≥ 0.21 + 0.0585 = **0.2685**；握点已经写在 z = −0.32，
## 蓄力时再往后收就把剑身拖回壳里（剑盾兵 2026-11-03 踩过同一个坑，用户："剑穿了肩甲的膜"）。
## ⚠️ 纯表现：`_next_hit_ms` / `_swing_from_ms` 一格不动，出手节奏与判定完全不受影响。
const UNIT_KNIGHT_COCK_TILT := 0.34    ## 蓄力：剑越过竖直再往后仰的角度 rad（扛到肩后，比剑盾兵多 0.08）
const UNIT_KNIGHT_COCK_LIFT := 0.26    ## 蓄力：握点抬高的距离 m（手举到肩高，比剑盾兵多 0.06）
const UNIT_KNIGHT_COCK_BACK := 0.0     ## 蓄力：握点往身后（+Z）收的距离 m（必须 0，理由见上）
const UNIT_KNIGHT_CHOP_TILT := 1.80    ## 下劈：从竖直往前压的角度 rad（≈103° ⇒ 命中帧剑尖略朝下，比剑盾兵更陡）
const UNIT_KNIGHT_CHOP_SIDE := 0.0     ## 下劈：绕 Z 的横扫分量 rad（0 = 刃口留在劈砍平面里，同剑盾兵）
const UNIT_KNIGHT_CHOP_REACH := 0.18   ## 下劈：握点往前（−Z）送的距离 m（大剑吃进得更深）
const UNIT_KNIGHT_CHOP_DROP := 0.06    ## 下劈：握点往下压的距离 m
const UNIT_KNIGHT_COCK_END := 0.38     ## 前摇里"蓄力"占的比例（比剑盾兵晚 0.04 ⇒ 蓄势更久）
const UNIT_KNIGHT_RECOVER := 0.55      ## 收招里"剑落回静止"占的比例（与大剑重量相称，不再拖长）
## 狂战士的双斧过顶劈砍（2026-11-03，用户："把剩下的角色都按照剑盾兵这样来更新…战斗动画"）。
## 与 `UNIT_SWORD_*` / `UNIT_KNIGHT_*` **同一套三段式**（蓄力 → 下劈 → 跟随，命中帧仍是动画顶点），
## 区别只在"人设"：两把斧同握在一个 `Axes` 节点上 ⇒ 抡起来更野、收得更急。
## ⚠️ `UNIT_BERSERKER_CHOP_SIDE` 是三个劈砍里**唯一非 0**的：双斧是左右对称的两把，
##    绕 Z 给一点点横扫分量（0.10 rad）才读得出"两把一起抡"，单轴下劈会像一把斧头劈两遍。
## ⚠️ 纯表现：`_next_hit_ms` / `_swing_from_ms` 一格不动。
const UNIT_BERSERKER_COCK_TILT := 0.40   ## 蓄力：斧柄越过竖直再往后仰 rad（比骑士更夸张）
const UNIT_BERSERKER_COCK_LIFT := 0.20   ## 蓄力：握点抬高的距离 m
const UNIT_BERSERKER_COCK_BACK := 0.06   ## 蓄力：握点往身后（+Z）收的距离 m（斧头在 z −0.27，收 6 cm 仍在前方）
const UNIT_BERSERKER_CHOP_TILT := 1.90   ## 下劈：从竖直往前压的角度 rad（≈109°，比骑士更狠）
const UNIT_BERSERKER_CHOP_SIDE := 0.10   ## 下劈：绕 Z 的横扫分量 rad（双斧的"剪刀感"，见上）
const UNIT_BERSERKER_CHOP_REACH := 0.22  ## 下劈：握点往前（−Z）送的距离 m
const UNIT_BERSERKER_CHOP_DROP := 0.10   ## 下劈：握点往下压的距离 m
const UNIT_BERSERKER_COCK_END := 0.30    ## 前摇里"蓄力"占的比例（比剑盾兵还早 ⇒ 抡得快）
const UNIT_BERSERKER_RECOVER := 0.50     ## 收招里"斧落回静止"占的比例
## ---- 卡住自救 / 横向绕行（2026-09-26 用户："兵种会在投石车 / 弩车和召唤石柱后面左右摇摆"）----
## ⚠️ 这四支本来以**字面量**散在 `unit3d.gd#_start_sidestep()` 里（0.26 s / 每米半径 420 ms / 阈值 0.5 m）；
## 按不变量 I-15"可调参数全部住 `GameConfig`"搬进来，顺手把"时长按半径拍"换成"按自己的移速算"。
const UNIT_SIDESTEP_BIG_RADIUS := 0.5    ## 判定半径超过它的障碍算**巨物**（绕行时平时不左右交替）
const UNIT_SIDESTEP_CLEARANCE := 0.10    ## 绕过障碍时多留的余量 m（贴着表面走会一路刮蹭）
const UNIT_SIDESTEP_MIN_MS := 260        ## 一次侧滑的时长下限 ms（= 人形绕人形的历史值 0.26 s）
const UNIT_SIDESTEP_MAX_MS := 1800       ## 一次侧滑的时长上限 ms（防慢单位绕巨物时侧滑太久）
const UNIT_SIDESTEP_BIG_STROKES := 3     ## 巨物连续绕这么多**次**都没进展，才换一次边（~3 s 一次）

# ---------------------------------------------------------------- 技能（2026-09-18 新增机制）
## 技能写在 `PROFILES[*]["skill"]` 里，由 AI 在满足条件时自动释放、释放后进入冷却（`02_entities.md#2.3`）。
## 数值域前缀沿用 `UNIT_*`（选手动作与手感），不新开域（`08_naming.md#3.3`）。
const UNIT_FAN_ARC_DEG := 120.0        ## 扇子兵扇形攻击的张角（±60°；2026-09-19 由 90 加宽）
## 骑士技能·冲撞：目标进入 `UNIT_CHARGE_RANGE` 且自身不在出手时发动；
## 冲锋期间以 `UNIT_CHARGE_SPEED` 直线冲向目标，撞到即结算伤害与击退数值 4。
const UNIT_CHARGE_RANGE := 6.0         ## 触发距离 m
const UNIT_CHARGE_SPEED := 14.0        ## 冲锋速度 m/s
const UNIT_CHARGE_DAMAGE_MULT := 1.5   ## 撞击伤害 = 自身伤害 × 本值
const UNIT_CHARGE_KNOCKBACK := 4.0     ## 撞击的**击退数值**（不是冲量；冲量 = KNOCKBACK_SPEED × 本值）
const UNIT_CHARGE_CD_MS := 8000        ## 冷却 8 s
const UNIT_CHARGE_MAX_MS := 900        ## 冲锋最长持续时间（防打空后一直冲）

# ---------------------------------------------------------------- 盾牌猛击（骑士第二技能，2026-09-19）
## 用户要求：骑士**保留冲撞**，另加「盾牌猛击」——进入射程后按自己的冷却放一次强化出手：
## 伤害 ×1（= 自身 `damage`，44）、**击退数值 2**、冷却 **3 s**；
## ⚠️ 与普通出手的关键差别：**猛击期间盾牌照常生效**（普通出手会让盾牌失效，见 `04_physics.md#7.1.1`），
## 实现上就是**不去动 `_striking`**——盾牌失效只看那一个标志。
const UNIT_BASH_CD_MS := 3000          ## 盾牌猛击冷却 3 s
const UNIT_BASH_DAMAGE_MULT := 1.0     ## 伤害倍率（= 自身伤害 ×1）
const UNIT_BASH_KNOCKBACK := 2.0       ## 击退数值（不是冲量；冲量 = KNOCKBACK_SPEED × 本值）

# ---------------------------------------------------------------- 投射物（2026-09-18 R2）
## 三种投射物共用一个实体（`arrow.gd`，ID 沿用历史名 `arrow`）：箭矢 / 石弹 / 弩箭。
const UNIT_STONE_SPEED := 36.0         ## 石弹初速 m/s。最大水平射程 = v²/g：36²/16 = 81 m。
									   ## 点满射程 = 面板 35 +「射程增加」10 +「攻城模式」18，再加指挥所本回合 +4 = 67 m。
									   ## 初速只够 42 m 时，弹道解会把瞄点夹在半路，石头落在目标前面。
									   ## 历史：14 → 22 → 26（只覆盖面板 35 m）→ **36**。
const UNIT_STONE_GRAVITY := 16.0       ## 石弹下坠 m/s²（抛物线；箭矢为 0）
const UNIT_STONE_AOE_RADIUS := 4.0     ## 石弹落地范围伤害半径 m
## 石弹的**溅射伤害**：直接命中的那个单位吃 `damage`（= 140），
## 落点半径内**其他**敌人吃本值（70）；石弹打在空地上（没有直击目标）时，半径内所有人吃本值。
## 沿革：140 / 70 →（2026-09-19 第二条）**160 / 80** →（**2026-09-25 第五条**）**140 / 70**，
## 用户："投石车伤害变回 140，但是会对所有击中的敌人附加眩晕 1"。
## ⚠️ 本值**恒等于直击的一半** —— 下次再调直击时**两处一起改**（HUD 词条会把两个数都写出来）。
const UNIT_STONE_SPLASH_DAMAGE := 70.0
## 石弹落点的**眩晕时长** ms（2026-09-25 第五条，用户："会对所有击中的敌人附加眩晕 1"）。
## ⚠️ "所有击中的敌人" = **直击那一个 + 落点半径内被溅射到的其他敌人**（用户裁定），
## 也就是 `Arrow._explode()` 那个循环里的**每一个**敌人，**不分档**。
## ⚠️ 与另外两处眩晕同单位、同口径（`UNIT_FLAME_HIT_STUN_MS` / `UNIT_SANDWORM_SURFACE_STUN_MS` 都是 1000），
## 但它是**第一个挂在投射物上的眩晕源** —— 前两处都是技能，这一条走 `Arrow._explode()` 的命中结算。
## ⚠️ 走的是同一个 `Unit3D.apply_stun()` ⇒ **boss（沙虫）照旧免疫**，潜地中的单位照旧跳过（不可锁定 + 无敌）。
const UNIT_STONE_STUN_MS := 1000
## 火球地面烧多久，以及火 / 酸液对同一个单位的结算间隔。
## 多摊叠在一起时，这个间隔内只掉一次血。酸液本身留到回合结束。
const UNIT_FIRE_DURATION_MS := 5000
const UNIT_GROUND_TICK_MS := 1000
const UNIT_BOLT_SPEED := 180.0         ## 弩箭速度 m/s（2026-09-19 由 60 提到 3 倍；直线、不可被盾挡）
## 火枪子弹速度（2026-09-25 火枪兵）：用户口径"**速度是弩车子弹的两倍**" ⇒ 写成**表达式**而不是 360.0
## —— 以后弩箭调速时这层关系自动跟着走（同 `UNIT_SHORTBOW_ARROW_SPEED` 的写法）。
## ⚠️ **360 m/s 在 60 Hz 下每帧 6 m**：必须走线段查询（箭矢本来就是"上一帧位置 → 这一帧位置"的线段，
## 见 `arrow.gd#_resolve_segment()`），否则会直接穿过目标。
const UNIT_MUSKET_BULLET_SPEED := UNIT_BOLT_SPEED * 2.0
## 长弓手的箭矢（2026-09-25 新增）：**快箭 + 抛物线 + 落点预判**，用户口径"箭矢速度快，能预判，抛物线"。
## ⚠️ 与短弓手那条直线箭（`PROJECTILE_SPEED` 22 m/s、`gravity` 0）走**两条不同的弹道**：
##   短弓手 = 直线匀速、瞄当前位置（近战距离 16 m 内飞行时间短，预判的收益还不够抵消复杂度）；
##   长弓手 = 抛物线 + 按"解出的滞空时间 × 目标速度"提前量瞄准（30 m 射程下必须预判，否则永远落在身后）。
## 数值推导（不是拍的）：
##   · **最大的水平射程 = v²/g**（与石弹同一条式子）⇒ 52²/16 = **169 m**，对 30 m 的射程余量极大
##     ⇒ 弹道解永远不会退化成"只能打近处"（旧石弹的"朝正上方投"就是撞在这一条上）；
##   · **滞空时间** ≈ 水平距离 ÷ 水平分量：30 m 上约 **0.6 s**、最高点离发射线约 **0.6 m**
##     —— 够看出"是一条弧"，又不会高到打不中（抛物线是**表现**要求，不是弹道谜题）；
##   · 52 m/s 是短弓手 22 m/s 的 **2.4 倍** ⇒ 用户要的"箭矢速度快"由它承担，
##     弓弦感由 `"longbow_arrow"` 的细长箭网格承担（见 `arrow.gd#_build_longbow_arrow()`）。
const UNIT_LONGBOW_ARROW_SPEED := 52.0   ## 长弓箭矢初速 m/s
const UNIT_LONGBOW_ARROW_GRAVITY := 16.0  ## 长弓箭矢下坠 m/s²（与石弹同值；短弓手为 0 = 直线）
## 短弓手的箭矢（**2026-09-25 大改**：从"直线 22 m/s、不预判"改成**抛物线 + 落点预判 + 重建模**）。
## 用户口径两句话："短弓手箭矢速度变为长弓手的四分之三"、"短弓手箭矢应有抛物线"。
##   · 速度：`UNIT_LONGBOW_ARROW_SPEED × 0.75` = **39 m/s**。⚠️ 用**表达式**而不是写 39.0 ——
##     用户给的是"长弓手的四分之三"这条**关系**，写死数字的话以后改长弓速度会静默失配；
##   · 下坠：**低于长弓的 16**。39 m/s 配 16 时最大平射程只有 `39²/16 = 95 m`、滞空偏短，
##     16 m 射程上几乎看不出弧线（"有抛物线"就名存实亡）；取 **13** 后
##     `39²/13 = 117 m`、16 m 处抬角约 **4.7°**：既看得见弧线，又近到能打中（与长弓 3.6°/30 m 同量级）。
const UNIT_SHORTBOW_ARROW_SPEED := UNIT_LONGBOW_ARROW_SPEED * 0.75
const UNIT_SHORTBOW_ARROW_GRAVITY := 13.0
## 弩车击退的动量传递到"被击退者的同队单位"时的伤害（`04_physics.md#5.1` 的唯一特例）。
const UNIT_BALLISTA_TRANSFER_DAMAGE := 60.0
## 尸体滑行（2026-09-19 用户要求）：**被击退致死**的单位，尸体先是实体——保留碰撞与击退速度，
## 继续 `move_and_slide()` 并被推着走，然后才消失。这是弩车"传递伤害"能落地的前提：
## 一发 400 秒杀时，被秒的人以前会立刻失去碰撞，根本飞不到同队单位身上。
const CORPSE_SLIDE_MAX_MS := 800       ## 滑行最长时长 ms（超过就结束、交回普通阵亡演出）
const CORPSE_SLIDE_MIN_SPEED := 1.0    ## 击退速度衰减到本值以下即结束滑行 m/s
## 动量传递的"撞上"判定半径（2026-09-19）：单位胶囊半径 0.38 ⇒ 两个身体贴上约 0.76 m，
## 留一点余量取 0.9。⚠️ 这里**不能**再用 `attack_reach()`——对远程兵种那是射程（弩车 44 m），
## 会让一次击退把半个场地的同队单位全推一遍（用户报告的"弩车打人堆炸开来"）。
const KNOCKBACK_CONTACT_RADIUS := 0.9

## "穿队友"掩码的**延时还原**（2026-09-19 用户第六条）：冲撞 / 跳跃常常正好**停在队友身上**，
## 若那一刻立刻把己方层加回掩码，引擎的穿透修正会把这名队友顶开（实测：骑士停在队友身上 ⇒
## 队友被推开 1.4 m；狂战士高速落地时更夸张）。所以技能结束时**不立刻还原**：先看一圈，
## 身边还有队友就"再戴一会儿"，最多 `UNIT_ALLY_GHOST_MAX_HOLD_MS`。
## ⚠️ 超时**无条件**还原：宁可挨一次穿透修正，也不能让"穿队友"变成永久状态。
const UNIT_ALLY_GHOST_CLEAR_RADIUS := 1.0   ## 解除前要求"这个半径内没有队友" m
const UNIT_ALLY_GHOST_MAX_HOLD_MS := 600    ## 最多多戴多久 ms

# ---------------------------------------------------------------- 火箭跳跃（狂战士技能，2026-09-18 R3）
## 2026-09-19 用户第四条：**取消"第二次起距离减半"**，改成**按被锁定对象的距离自适应**——
## 每次跳跃的水平距离 = 与目标的当前距离 − `UNIT_JUMP_LAND_GAP`（留一个贴身间隙，免得正好落进对方身体里），
## 上下限由 `UNIT_JUMP_MIN_DISTANCE` 与 `UNIT_JUMP_RANGE` 夹住（太近就不跳了：直接走上去 / 平 A）。
## ⚠️ 旧常量 `UNIT_JUMP_DISTANCE`（固定 14 m）随本轮删除：跳跃距离不再有"固定值"。
## ⚠️ 它的触发条件因此变成"目标距离 ∈ [`UNIT_JUMP_MIN_DISTANCE` + `UNIT_JUMP_LAND_GAP`, `UNIT_JUMP_RANGE`]"。
const UNIT_JUMP_RANGE := 14.0          ## 触发距离 m（"较大"，明显大于冲撞的 6 m）＝自适应跳跃的**距离上限**
const UNIT_JUMP_MIN_DISTANCE := 3.0    ## 跳跃水平距离的**下限** m（触发下限 = 本值 + `UNIT_JUMP_LAND_GAP`）
const UNIT_JUMP_LAND_GAP := 1.0        ## 落点比目标**近**这么多 m（贴身但不重叠）
const UNIT_JUMP_AIR_MS := 600          ## 滞空时长 ms（抛物线由重力画，见 `04_physics.md#5.2`）
const UNIT_JUMP_INVULN_MS := 500       ## 落地后额外的免疫时长 ms（滞空期间也免疫）
const UNIT_JUMP_CD_MS := 2000          ## 冷却 2 s

# ---------------------------------------------------------------- 炎爆（火焰拳技能，2026-09-19 新增）
## 数值全部来自用户口径：触发距离 5~13 m、蓄力 1 s、极速冲刺、击退 4、眩晕 1、0.5 s 后 6 m 爆炸
## （3× 攻击伤害 + 眩晕 1）、自身眩晕 1、**无冷却**。机制见 `02_entities.md#2.3`。
const UNIT_FLAME_RANGE_MIN := 5.0       ## 触发距离下限 m（太近不发动：冲刺需要助跑段）
const UNIT_FLAME_RANGE_MAX := 13.0      ## 触发距离上限 m
const UNIT_FLAME_CHARGE_MS := 1000      ## 蓄力时长 ms（"蓄力 1s"；原地不动，可被打断）
## 冲刺速度：用户要求"极快速"。60 m/s 下 5~13 m 只要 0.08~0.22 s，观感是一道直线；
## ⚠️ 一帧 ≈1 m，比单位胶囊（半径 0.38）还长 ⇒ **命中判定必须用距离**，不能靠碰撞体（会穿过去）。
const UNIT_FLAME_DASH_SPEED := 60.0
const UNIT_FLAME_DASH_MAX_MS := 400     ## 冲刺最长时长 ms（目标瞬移 / 被挡住时的兜底）
## 命中判定距离：比近战出手宽容（`attack_reach()` = 1.8×1.18 ≈ 2.12）略大一点，保证高速冲刺不漏判。
const UNIT_FLAME_HIT_DISTANCE := 2.2
const UNIT_FLAME_HIT_KNOCKBACK := 4.0   ## 撞上被锁定单位：**击退数值**（不是冲量；不造成伤害）
const UNIT_FLAME_HIT_STUN_MS := 1000    ## 撞上被锁定单位：眩晕 1
const UNIT_FLAME_BLAST_DELAY_MS := 500  ## 撞上之后到爆炸的间隔 ms（"0.5 秒后"）
const UNIT_FLAME_BLAST_RADIUS := 6.0    ## 爆炸半径 m（**以被撞对象为中心**；对象中途消失则回落自身，见 `_flame_explode`）
const UNIT_FLAME_BLAST_DAMAGE_MULT := 3.0  ## 爆炸伤害 = 自身伤害 × 本值（用户："3 倍攻击伤害"）
const UNIT_FLAME_BLAST_STUN_MS := 1000  ## 爆炸给范围内所有敌方的眩晕（1）
const UNIT_FLAME_SELF_STUN_MS := 1000   ## 爆炸后**自身的**眩晕（1）

# ---------------------------------------------------------------- 潜地 / 沙虫（boss 单位，2026-09-19 新增）
## 沙虫是第一个 **boss 单位**（`PROFILES["sandworm"]["boss"] = true`，判据 `GameConfig.is_boss()`）：
## **免疫眩晕**、**每队最多一个**（配平在 `_random_composition()` 里把关）、权重 **25**（新档位）。
## 攻击复用扇子兵那条 `attack_arc_deg` 通路 ⇒ **前方扇形、命中范围内所有敌人**（用户口径："只打敌方"）。
## 技能「潜地」（`burrow`）：攻击范围内没有敌人 ⇒ 钻入地下（**不可锁定 + 无敌 + 免疫一切状态**），
## 只有攻击时才钻出；**要移动必须钻至地下**、**无冷却**。⚠️ 押注阶段（`active == false`）不钻地。
## 机制见 `04_physics.md#5.2`。
const UNIT_SANDWORM_FAN_RADIUS := 5.0   ## 扇形攻击半径 m（= 面板射程）
const UNIT_SANDWORM_ARC_DEG := 120.0    ## 扇形张角（±60°，与扇子兵同宽）
const UNIT_SANDWORM_SINK_MS := 300      ## 钻入 / 钻出的过渡时长 ms（过渡期间锁住移动与出手）
const UNIT_SANDWORM_BITE_DISTANCE := 0.8  ## 出手动作：下颚沿本体 −Z 前咬的距离 m（纯表现，同 `UNIT_THRUST_DISTANCE`）
## 2026-09-19 用户："沙虫钻到地里 0.3 秒后才能移动，钻出地后 0.3 秒后才能攻击" ⇒ 两个**时序**闸门。
## ⚠️ 它们是玩法数值（决定什么时候能动手）⇒ 按 I-15 住在这里，不写成脚本常量。
const UNIT_SANDWORM_UNDER_DELAY_MS := 300   ## 完全钻入地下后，还要再等这么久才允许移动
const UNIT_SANDWORM_SURFACE_DELAY_MS := 300  ## 钻出地面后，还要再等这么久才允许出手
## 2026-09-19 用户："沙虫更改：**钻回地需要在范围内没有敌人并持续 0.6 秒才行**，
## **钻到地里需过 0.6 秒才能钻出来**" ⇒ 潜地两端各加一道**时间**闸门（与既有两个 0.3 s 闸门各自独立）：
##   · `SINK_DELAY_MS`：射程内**连续**没有敌人满这么久才真正下潜（中途有敌人回到射程 ⇒ 计时作废重来）；
##     这 0.6 s 里它仍是 `SURFACED`，照常站着（只是没敌人可打）；
##   · `UNDER_MIN_MS`：到达 `UNDER` 后**至少**待这么久才允许浮出（即使敌人已经进射程也按着不出来）；
##     与 `UNDER_DELAY_MS` 分属两件事——那条管"能不能移动"，这条管"能不能浮出"。
const UNIT_SANDWORM_SINK_DELAY_MS := 600  ## 射程内连续没有敌人满这么久，才允许钻回地
const UNIT_SANDWORM_UNDER_MIN_MS := 600  ## 到达 UNDER 后至少待这么久，才允许浮出
## 2026-09-19 用户："钻出地时立即对以自身为中心、半径 4 m 的所有单位（包括友方）造成眩晕 1，
## 且钻出地后的第一下攻击造成双倍伤害" ⇒ 浮出瞬间的**范围眩晕** + 第一口**双倍伤害**。
## ⚠️ 那个 4 m **已于 2026-09-25 改为 6 m**（用户："沙虫钻出地面的眩晕范围变成 6m"），见下面的常量。
## 口径（本轮确认）：眩晕 = **1 s**；半径按**三维距离**（与炎爆 6 m 爆炸同一条写法）；
## **不区分敌我**——友方也吃（用户明说"包括友方"）；潜地单位跳过（沿用扇形 / 爆炸那条既有口径）。
## ⚠️ 沙虫自己是 boss ⇒ `apply_stun()` 自带免疫（"任何来源"），不会被自己这一下晕到。
## ⚠️ 2026-09-25 用户："沙虫钻出地面的眩晕范围变成 6m"：半径 **4.0 → 6.0**（眩晕时长仍是 1 s）。
## 连带事实：浮出"震地"特效（`unit3d.gd#_update_burst_fx()` 的沙浪 / 沙环）**直接读本值** ⇒ 观感自动跟着放大到 6 m，
## 与判定边界继续重合（与炎爆火池取 `UNIT_FLAME_BLAST_RADIUS` 同一条规矩），不需要另改特效代码。
const UNIT_SANDWORM_SURFACE_STUN_RADIUS := 6.0  ## 浮出瞬间的范围眩晕半径 m（以自身为中心）
const UNIT_SANDWORM_SURFACE_STUN_MS := 1000  ## 浮出瞬间的眩晕时长 ms（= 用户口径的"眩晕 1"）
## 第一口双倍伤害的口径（本轮确认）：**这一口命中的全部目标**都 ×2（沙虫平 A 走扇形通路，
## 见 `unit3d.gd#_resolve_cone_attack()`）；一口**咬空**（扇形里没人 / 目标已出射程）**不算用掉**
## ⇒ buff 保留到下一次真正命中；`SURFACED → SINKING` 重新钻地时清除。
const UNIT_SANDWORM_FIRST_BITE_MULT := 2.0  ## 浮出后第一口命中的伤害倍率（0 目标不消耗）

# ---------------------------------------------------------------- 冲锋（轻骑兵（矛）技能，2026-09-25 新增）
## 用户口径（原文）："技能：冲锋：距离锁定对象 7m 时发动，持续时间 3 秒，基础伤害 40，
## 持续时间内对锁定对象发动冲锋（移速变为 10m/s，不能更改方向），持续 1.5s，期间对所有进入前方矩形
## （宽 1m，长 3.4m）的兵种造成『基础伤害 + 附加伤害（被攻击者与轻骑兵矛相对速度差越大，数值越大）』的伤害，
## 附加击退 3（每个进入矩形的兵种只会受到一次伤害，离开矩形后重置），期间能够推开其他与之碰撞模型相碰的兵种，
## 冷却 5s（技能持续时间结束后开始计算）。技能冷却期间不会主动接近敌方进行战斗，而是在附近游走，持续移动，
## 保持距离（要能够发动技能）"。
##
## ⚠️ **这段"总分总"读法 2026-09-25 已三度作废，只留作沿革**：
## 用户最初给的三个数（总 3 s / 追踪 1.5 s / 锁方向 1.5 s）先后被几次改动推翻 ——
##   ① 同日：方向锁死被"转弯限速 180°/s"取代（见 `UNIT_LANCE_LOCK_MS`）；
##   ② 同日第四条：**总时长 3 s → 10 s**（用户："持续时间 10 秒"）；
##   ③ **同日其后：10 s → 8 s**（用户："技能持续时间变为 8"）。
## ⇒ 现在只有**一条**时长口径：`UNIT_LANCE_CHARGE_MS` = **8 s**，期间全程限速转向、**不分段**。
const UNIT_LANCE_CHARGE_RANGE := 7.0      ## 触发距离 m（对**锁定对象**的距离）
## ⚠️ **2026-09-25：3 s → 10 s（第四条，用户："修改轻骑兵冲锋技能，持续时间 10 秒，且只能使用一次"）
## → 8 s（用户："技能持续时间变为 8"）。**
## 连带事实（**都必须在文档里写明，不是可选项**）：
##   · 8 s × 14 m/s ⇒ 单次冲刺**理论位移可达 112 m**，而场地只有 100 × 50 m ⇒ 它仍可能**贴到边界墙**，
##     由 `move_and_slide()` 沿墙滑行。⚠️ 这**不是漏洞**：墙在世界层、而"穿过所有单位"的掩码
##     **保留世界层**（`_set_pass_all()`），所以它冲得再久也出不去；
##   · 转弯限速 180°/s 在 8 s 里至多能转 **1440°（4 整圈）** ⇒ "绕回来再压上去"的余地仍远大于 3 s 时代。
const UNIT_LANCE_CHARGE_MS := 8000         ## 冲刺总时长 ms（2026-09-25：3 s → 10 s → **8 s**）
const UNIT_LANCE_LOCK_MS := 1500           ## ⚠️ **2026-09-25 起不再使用**：原"方向锁死"的时刻。
## 用户本轮把口径改成"**轻骑兵在转弯时每秒最多旋转 180°**" ⇒ 由 `UNIT_LANCE_TURN_DEG_PER_SEC`
## 的**转向限速**取代"锁死方向"。常量保留只为说明沿革，新代码不要引用它。
const UNIT_LANCE_TURN_DEG_PER_SEC := 180.0  ## 转弯限速**基档**：每秒最多转这么多度（用户 2026-09-25 指定）
## 冲刺的**快档转弯限速**（度/秒，2026-09-25 第十条，用户："轻骑兵转弯速度可以在每秒 180 度和 270 度间切换，
## 防止一直转圈撞不到人"）。判据在 `Unit3D._lance_turn_deg_per_sec()`：
## **目标超出命中矩形可及范围（> `UNIT_LANCE_BOX_LENGTH`）时用快档收紧圈子，够得到就落回基档 180**。
## ⚠️ 为什么"够不到"要用快档 —— 转弯半径 = 冲刺速度 ÷ 角速度：
##   180°/s（π rad/s）⇒ 14 ÷ π ≈ **4.46 m**；270°/s（4.712 rad/s）⇒ ≈ **2.97 m**；
##   而命中矩形只有 **3.4 m** 长 ⇒ 4.46 m 处的目标**永远在矩形之外**，2.97 m 才收得进来。
const UNIT_LANCE_TURN_FAST_DEG_PER_SEC := 270.0
const UNIT_LANCE_CHARGE_SPEED := 14.0      ## 冲锋期移速 m/s（**2026-09-25 由 10 改**，用户："修改轻骑兵冲刺时移速：14m/s"）
## **单场冲刺次数上限**（2026-09-25 用户："冲刺次数限制：2 次"，并明确"额度用完就只剩平 A，且不再游走"）。
## ⚠️ 它是**每场**（每个单位一生）的额度，不是"每次冷却后又给 N 次"；与冷却是**两个独立闸门** ——
## 额度用完就不再冲刺**也不再游走**，退化为普通近战（走常规走位 + 平 A）。
## ⚠️ **2026-09-25 第四条（用户："且**只能使用一次**"）：2 → 1。**
## ⚠️ **同日第五条推翻了第四条那条"被打断就退还额度"的连带口径**：眩晕对冲刺是**暂停**、不是打断
##（用户："被眩晕打断后能在眩晕结束时继续冲锋（**眩晕持续期间不进行技能持续时间计时**），直到 10s 为止"）
## ⇒ **扣点只有 `_start_lance()` 一处、没有任何退还路径**：`_interrupt_skill()` 里**故意没有**
## `charge_lance` 分支，`apply_stun()` 只把 `_lance_until_ms` 的截止时刻往后推"被晕掉的那一段"、**不碰额度**。
## 沿革：第四条曾短暂实现"被打断就退还额度"，**第五条已推翻**，别照第四条那段旧口径写代码。
const UNIT_LANCE_CHARGES_MAX := 1
const UNIT_LANCE_CD_MS := 5000             ## 冷却 5 s，**从技能结束那一刻起算**（用户明说）
## 前方矩形：**宽 1.5 m × 长 3.4 m**（用户给定）。⚠️ 3.4 与它的面板射程 `range` 是同一个数、但不是同一个含义：
## 这里是**冲锋期专用的命中矩形长度**，面板射程管的是平 A。两者取同一个数字是用户的口径。
## ⚠️ **2026-09-25（用户："冲刺时的攻击范围的宽度变为原来的 1.5 倍"）：宽 1.0 → 1.5 m**（左右各 0.75 m）；
## 长度 3.4 m **一个字都没动** —— 用户只说"宽度"。
const UNIT_LANCE_BOX_WIDTH := 1.5          ## 矩形宽 m（垂直于冲锋方向，左右各半）
const UNIT_LANCE_BOX_LENGTH := 3.4         ## 矩形长 m（沿冲锋方向，从自身出发向前）
const UNIT_LANCE_HIT_KNOCKBACK := 3.0      ## 矩形伤害附带的**击退数值**（不是冲量）
## 矩形伤害的**结算节拍** ms（2026-09-25：用户先定"轻骑兵修改：冲刺时**每 0.4 秒最多造成一次伤害**"，
## 同日随后改口 —— "轻骑兵冲刺期间攻击间隔变为 0.3" ⇒ **400 → 300 ms**）。
## ⚠️ 它是**整条技能**的节拍，**不是**每个目标各自的冷却 —— 一次结算里，所有"新进入矩形"的人都吃伤害
## （"每个进入者只吃一次、离开矩形后重置"那条规则照旧）。
## ⚠️ 连带后果（用户已确认，是**刻意的削弱**）：0.3 s 内**穿过**矩形、没赶上结算帧的单位**一次都不吃** ——
## 3.4 m 的框在 14 m/s 下 0.243 s 就穿完，所以"能不能吃上"完全看**它是不是正好卡在结算帧上**。
## ⚠️ 第一跳在**发动那一帧**就发生（`_start_lance()` 把计时清 0）⇒ 起步就撞上的目标不会被延迟 0.3 s。
const UNIT_LANCE_BOX_TICK_MS := 300
## 索敌格子与远处隐藏（2026-10-02）。玩法仍是只打最近的敌人；这两项只决定查多远、藏多远。
const UNIT_QUERY_CELL := 4.0               ## 索敌格子边长 m。⚠️ **性能 A/B 旋钮**（2026-10-28）：
										   ## 调大 ⇒ 非空格子数变少（每帧扫的格子少），但每格人多（比距离的次数多）。
										   ## 它**不改结果**，只改快慢 ⇒ 想调必须配实测（默认 4.0 未动）
const UNIT_QUERY_SLACK_M := 2.0            ## 索敌提前停下的余量 m。一帧走不出这么远
## 索敌节流（2026-10-28 性能优化 A 组）。⚠️ **默认 0 = 关**：
## 关着时 `Arena.solve_nearest()` 每人每帧都重算最近敌人，与优化前**逐帧同口径**。
## 改成 > 0（建议先试 **200~300 ms**）时，同一单位在这段时间内复用上一次的结果 ⇒
## **会动 bible 那条"随时 `target` == 最近敌人"的不变式**（最近者最多滞后这么久）。
## ⚠️ 打开它必须同时做两件事：① 先在 `debug_autoplay` 里 A/B 实测（"锁定最近者 N/N"别掉）；
## ② 在 `04_physics.md#3` 登记"这条不变式放宽到了什么程度"。别默默打开。
## ⚠️ 重算时刻按实例 id 错开（`arena._match_nearest()`）⇒ 实际间隔是这里的 **1~2 倍**。
const UNIT_RELOCK_MS := 0                  ## 索敌复用上一次结果的时长 ms（0 = 关）
const UNIT_STAND_SLIDE_SPEED := 0.02       ## 水平速度低于此（m/s）且贴地、没被击退时，不再跑滑动求解
const UNIT_MARCH_SLIDE_M := 1.6            ## 离最近敌人近过这么远，行进才改回滑动求解 m
const UNIT_MARCH_BODY_M := 0.5             ## 行进探路时，朝速度方向多探出的身位 m
const UNIT_LOD_HIDE_M := 48.0              ## 镜头离单位超过这么远就藏起马的零件和血条 m
## 冲刺**停步的贴近阈值**（m）。⚠️ **2026-09-25 第二条起不再被引用**：
## 用户两次报"轻骑兵冲到对面面前就停下了"，两次都出在这个"停步"上 ——
## 只要冲刺的语义是"**穿过**所有单位"，**任何**停步条件都会表现成"停在对手面前"。
## 现在冲刺**全程不停**（目标跑到身后由转弯限速把它绕回来），本常量**只留作沿革说明**。
## ⚠️ 不要再拿它去加停步判据；真要恢复停步，先想清楚"穿过"这条还成不成立。
const UNIT_LANCE_STOP_DISTANCE := KNOCKBACK_CONTACT_RADIUS + 0.3
## 附加伤害的斜率：**每 1 点相对速度差 = 这么多点伤害**。
## ⚠️ 常量名里的 `MS` 是"米/秒"（相对速度的单位），**不是毫秒** —— 别被名字骗了。
## 附加伤害 = 本值 × 被撞者与自己在**冲刺轴上的相对速度**
##（= 两者速度在冲刺轴上的投影之差；**取绝对值** ⇒ 迎面冲来与同向逃跑都算"速度差"）。
## ⚠️ **2026-09-25 第八条（用户："轻骑兵额外伤害 10 变为 8"）：10.0 → 8.0**（仍**不设上限**）。
## 实测四档（14 m/s 冲刺、基础伤害 40）：
##   · 静止目标 `|14 − 0| = 14` ⇒ 附加 **112** ⇒ 合计 **152**（3.0 时代 82、10.0 时代 180）；
##   · 同向逃跑 3.4 m/s `|14 − 3.4| = 10.6` ⇒ 附加 85 ⇒ 合计 **≈125**；
##   · 迎面 3 m/s `|14 + 3| = 17` ⇒ 附加 136 ⇒ 合计 **176**；
##   · 迎面 7 m/s（轻骑兵对冲）`|14 + 7| = 21` ⇒ 附加 168 ⇒ 合计 **208**。
##   ⇒ 仍能一撞秒掉 120 / 140 那一档（短弓手 / 长弓手）；长矛兵 195 需要迎面接近速度 ≥ 5.4 m/s 才秒。
## ⚠️ 改这个值只影响"附加伤害"这一项，基础伤害永远是 40（= `PROFILES["lightcav"]["damage"]`）。
const UNIT_LANCE_SPEED_BONUS_PER_MS := 8.0
## 冷却期间的游走（**2026-09-25 整条重做**）：用户："轻骑兵游走逻辑修改：**至少 10m 且尽量远离**"。
## ⚠️ 这条推翻了原来"窄环带 [5.0, 8.6] m、贴边待命"的设计（那个设计是为了"冷却一结束就够得着"，
## 但用户本轮明确要求"至少 10 m 且尽量远离"）。
## ⚠️ **连带事实（必须知道）**：技能触发距离是 **7 m**，而游走下限是 **10 m** ⇒
## **在冷却期内它永远进不了触发距离**。因此"能发动技能"只可能发生在**冷却刚结束**那一小段
## （那时 `_lance_patrol()` 交回常规走位、它才会主动压进 7 m；冲完又回到 ≥10 m 的游走）。
## 也就是说它的节奏变成：**退到远处待机 → 冷却一结束立刻压进 7 m 冲一次 → 再退开**。
## ⚠️ 若以后把触发距离提到 ≥10 m，这条就会变成"永远发不出技能"的死局 —— 两者必须一起看。
const UNIT_LANCE_PATROL_INNER := 10.0      ## 游走**下限** m：比这更近就往远退（用户："至少 10m"）
const UNIT_LANCE_PATROL_OUTER := 16.0      ## "尽量远离"的**上限** m：退到这里就不再退（防无界后退拖成僵持）
## 环带内改走"横向来回"的方向翻转周期 ms：每隔这么久把绕行方向左右对调一次 ⇒ 读起来是"来回游走"，
## 而不是绕着目标转圈或原地抖动。
const UNIT_LANCE_PATROL_TURN_MS := 1100

# ---------------------------------------------------------------- 武士大师的四技能（boss，2026-09-25 新增）
## 用户口径（原文）："拥有技能：高级偏折：冷却4s，能够格挡箭矢、子弹等小型投射物并反弹（箭矢以大小相同、
## 方向相反的速度继续飞行，并将其视为我方投射物），能够格挡15次。挡完5次后才进入冷却
## 拥有技能：冲刺：类似冲撞但不造成伤害和击退，只会冲到锁定目标进入攻击范围，冷却1s
## 拥有技能：后撤步：一旦有敌方近战单位要对自己发起攻击时（如果为轻骑兵且正在冲锋则靠近他就后撤），
## 立刻后撤至自身后方7m、张角共60°的圆弧上，冷却1s
## 拥有技能：拔刀斩：冷却12s。冷却完成时即可发动，发动前先向正后方后撤10m，蓄力1s后向锁定方向
## 快速移动35m（能够穿过所有单位），立即使所有被穿过的敌方单位（宽度为2m）定身1s（包括boss单位，
## 且移动完后自身也被定身1.5s）。在敌方单位的定身结束后，立即对其造成300+x（"x"的值为被定身单位
## 血上限的四分之一）的伤害，技能持续时间内无敌（在自身定身结束后解除无敌）"。
##
## ⚠️ 四处**用户没给数、由我定的**（都只在这一组里，改起来一处改完）：
##   · `UNIT_MASTER_IAI_DASH_SPEED`（拔刀斩位移速度：35 m / 70 m/s = **0.5 s** 走完）；
##   · `UNIT_MASTER_DASH_MAX_MS`（冲刺②的兜底时限：目标一直够不着时的保险）；
##   · `UNIT_MASTER_BACKSTEP_CHARGE_RANGE`（"轻骑兵正在冲锋就靠近即后撤"的那条距离）。
## ⚠️ 定身**无视 boss / 载具的免疫**（用户同日裁决）⇒ 拔刀斩能定住沙虫与另一只武士大师，见 `apply_root()`。
const UNIT_MASTER_DEFLECT_CHARGES := 15       ## 高级偏折总次数（用户："能够格挡15次"）
const UNIT_MASTER_DEFLECT_PER_COOLDOWN := 5   ## 一个冷却周期内能挡几次（用户："挡完5次后才进入冷却"）
const UNIT_MASTER_DEFLECT_CD_MS := 2000       ## 触发后的冷却（⚠️ **2026-09-25 用户："高级偏折冷却：变为2s"，4 s → 2 s**）——冷却期间**不格挡、不反弹**
## 反弹后的**飞行上限**（2026-09-25 用户："高级偏折反弹的投射物最多飞行6m"）。
## ⚠️ 从**偏折点**起算（不是从它自己的发射点）；与"投射物总寿命" `ARROW_LIFETIME_MS` 是**两条独立的闸门**
## —— 这一条只管"被弹回来之后还能飞多远"，实现见 `arrow.gd#_physics_process()`。
const UNIT_MASTER_DEFLECT_RANGE := 6.0
const UNIT_MASTER_DASH_CD_MS := 1000          ## 冲刺②冷却（用户："冷却1s"）
## 冲刺②的**触发上限**（2026-09-25 用户："冲刺新增触发条件：锁定单位在8m内"）：
## 与射程 2.2 m 一起构成窗口 **2.2 m < d ≤ 8 m** —— 更远就先走过去，不再从半场外飞扑。
const UNIT_MASTER_DASH_RANGE := 8.0
const UNIT_MASTER_DASH_SPEED := 18.0          ## 冲刺②的位移速度 m/s（"类似冲撞"⇒ 一瞬间贴上去）
const UNIT_MASTER_DASH_MAX_MS := 2000         ## 冲刺②的兜底时限 ms（目标一直跑、够不着时的保险）
const UNIT_MASTER_BACKSTEP_CD_MS := 1000      ## 后撤步③冷却（用户："冷却1s"）
const UNIT_MASTER_BACKSTEP_DISTANCE := 7.0    ## 后撤距离 m（用户："后撤至自身后方7m"）
const UNIT_MASTER_BACKSTEP_ARC_DEG := 60.0    ## 落点圆弧总张角（用户："张角共60°"）——落点在其中**随机**取一点
## 后撤步的**时长**（2026-09-25 用户："后撤步应有动画"）：位移从"瞬移"改成 ~0.2 s 的平滑滑出。
## ⚠️ 本项目**没有骨骼动画**，所以"动画"的实现就是"看得见的位移"（同拔刀斩后撤段的手法）。
const UNIT_MASTER_BACKSTEP_MS := 200
## 后撤步结束后的**禁冲刺**时长（2026-09-25 用户："后撤步未完成时即后撤步完成后 0.3 s 内不得冲刺"）。
## ⚠️ 它是**额外**加的锁：滑行期间由 `_backstep_until_ms` 本身挡着，这一条管"滑完之后"。
const UNIT_MASTER_DASH_LOCK_MS := 300
## 「后撤步」的**触发窗口**（2026-09-25 第四轮，用户裁决"选 A"）：
## 触发判据原本是"**敌方近战的整个出手窗口**"（`is_winding_up_at()`：从起手到命中帧之间任何时候都算），
## 于是沙虫那种 600 ms 长前摇会让大师**一进 5.9 m 就被赶走**、永远贴不上去（实测 30 s 双方 0 伤害）。
## ⇒ 用户选了方案 A：**只在"命中帧前 `本值` 以内"才闪**（把窗口从"整个前摇"收成"最后这一段"）。
## 取 **150 ms**：沙虫前摇 600 ms ⇒ 大师能安心打前面那 450 ms，只在真要挨咬时闪开；
## 而 150 ms 也够后撤步的 200 ms 滑行走完一半以上（不是"刚起步就被打中"）。
const UNIT_MASTER_BACKSTEP_LEAD_MS := 150
## "敌方近战要出手"的判据用**它自己的攻击范围 + 前摇**（见 `_enemy_winding_up()`）；
## 这一条**只**管"轻骑兵正冲过来"那种"还没进攻击范围、但已经贴上了"的情况。
const UNIT_MASTER_BACKSTEP_CHARGE_RANGE := 6.0
const UNIT_MASTER_IAI_CD_MS := 12000          ## 拔刀斩④冷却（用户："冷却12s"）
## 拔刀斩的**触发距离**（2026-09-25 用户："发动条件变为锁定单位在5m以内且冷却完成"）：
## 与冷却一起构成触发条件 ⇒ 它从"半场外随时起手"变成**贴身技**（配合冲刺②的 8 m 触发，
## 武士大师的整体节奏是"走近 → 贴上去 → 拔刀"）。
const UNIT_MASTER_IAI_RANGE := 5.0
const UNIT_MASTER_IAI_RETREAT := 10.0         ## 发动前向正后方后撤的距离 m（用户："先向正后方后撤10m"）
const UNIT_MASTER_IAI_RETREAT_MS := 220       ## 后撤那一段的时长 ms（表现：快速倒飞，不是瞬移）
const UNIT_MASTER_IAI_CHARGE_MS := 1000       ## 蓄力时长 ms（用户："蓄力1s"；⚠️ 可被打断，打断即作废进冷却）
const UNIT_MASTER_IAI_DASH := 35.0            ## 位移距离 m（用户："快速移动35m"）
## 位移速度 m/s。⚠️ **2026-09-25 用户："移动速度变为原来的 1.5 倍"** ⇒ **70 → 105**
##（35 m 从 0.5 s 缩到 **≈0.33 s**；`_iai_dash_ms()` 与"全程无敌"的截止时刻都由它推导，自动跟着变）。
const UNIT_MASTER_IAI_DASH_SPEED := 105.0
const UNIT_MASTER_IAI_WIDTH := 2.0            ## 沿途判定宽度 m（用户："宽度为2m" ⇒ 以自身为轴 ±1 m）
const UNIT_MASTER_IAI_ROOT_ENEMY_MS := 1000   ## 沿途敌人定身时长 ms（用户："定身1s（包括boss单位）"）
const UNIT_MASTER_IAI_SELF_ROOT_MS := 1500    ## 自己落地后的定身时长 ms（用户："自身也被定身1.5s"）
const UNIT_MASTER_IAI_DAMAGE := 300.0         ## 定身结束时的基础伤害（用户："300+x"）
const UNIT_MASTER_IAI_DAMAGE_HP_RATIO := 0.25 ## "x" = 被定身单位**血上限**的这个比例（用户："血上限的四分之一"）

# ---------------------------------------------------------------- 心灵腐化师 / 玉面手雷王（2026-09-25 第二轮新增）
## 心灵腐化师（`corruptor`）：攻击是**激光式持续照射** —— 锁定一个目标、蓄力后持续照它，
## 期间不掉血、只往它身上叠「心灵腐化值」（用户口径见 `02_entities.md#2.3`）。
const UNIT_CORRUPT_CHARGE_MS := 500       ## 锁定后的**蓄力**时长 ms（用户："经过 0.5s 蓄力后持续攻击这个目标"）
## ---- 湮灭之瞳的「能量汇集」（2026-09-27 第十轮）----
## 用户口径："持续攻击同一个单位时间越长，造成的伤害越高（**攻击四下后激光变粗，伤害由30变为90，
## 再攻击四下后激光达到最粗，伤害变为300**）"。
## ⚠️ 判据是"**对同一个目标的连续命中数**"（`Unit3D._focus_hits`），换目标 / 丢锁 ⇒ 清零。
## ⚠️ 档位 = `命中数 ÷ UNIT_DOOM_HITS_PER_STAGE`（截断、封顶 3）⇒ **第 1~4 下是基础 30**、
##    **第 5~8 下是 90**、**第 9~12 下是 300**、**第 13 下起是 1000**
##    （"攻击四下后"= 已经打满 4 下 ⇒ 从下一档的第一下开始变强；第三档也只打 4 下）。
const UNIT_DOOM_HITS_PER_STAGE := 4
const UNIT_DOOM_STAGE_DAMAGE := [30.0, 90.0, 300.0, 1000.0]   ## 四档伤害（第 0 档 = PROFILE 里的基础伤害）
## 四档的**光束半径**（m）。前三档是原有的细 / 粗 / 最粗，第四档再加粗一档。
## ⚠️ 它是**表现参数**，但住在 `GameConfig` 是因为"档位"是玩法概念、必须和伤害同步（`unit3d.gd` 只是读它）。
const UNIT_DOOM_BEAM_RADIUS := [0.055, 0.14, 0.28, 0.50]
## "停照即清"的宽限 ms。用户裁决（2026-09-25）："**停止被照射就立即清零**（只要存在至少一个心灵腐化师
## 在攻击他就不会清零）" ⇒ 判据落地为"最近一次被照射距今是否超过这个宽限"。
## ⚠️ 它**必须大于一个照射间隔**（攻速 8/s ⇒ 125 ms），否则连续照射期间会被自己的间隙清掉；
## 取 **200 ms**（≈1.6 个间隔）：既留了帧抖动余量、又满足"立即"（肉眼就是一断就清）。
const UNIT_CORRUPT_HOLD_MS := 200
## 玉面手雷王（`grenadier`）：**死亡时自爆**。用户："当自身死亡时，对自身范围 4m 以内的敌人造成 150 点伤害"。
const UNIT_GRENADE_BLAST_RADIUS := 4.0    ## 自爆半径 m（用户："自身范围4m以内"）
const UNIT_GRENADE_BLASTS_PER_FRAME := 6  ## 同一物理帧最多结算几发手雷自爆，多出来的留到后面的帧
const UNIT_GRENADE_BLAST_DAMAGE := 120.0  ## 自爆伤害。⚠️ **2026-09-25 第四轮：150 → 120**（用户："玉面手雷王爆炸伤害从150变为120"）

# ---------------------------------------------------------------- 影魔（2026-09-25 第三轮新增）
## 「影袭」（技能①）：**受到任意伤害时免疫那一下**，化成影子扑到"伤害来源那一类单位"身边，
## 变回原身并**眩晕**它 2 s。用户口径见 `02_entities.md#2.3`。
const UNIT_SHADOW_STRIKE_CD_MS := 4000    ## 冷却 ms（用户："冷却4s"）
const UNIT_SHADOW_STUN_MS := 2000         ## 落地后对锁定单位的眩晕时长（用户："使锁定单位眩晕2s"）
## 影子形态的位移速度 m/s。用户只说"**极快**"、没给数 ⇒ **这是我定的**：
## 取 **120**（比拔刀斩的 105 再快一档 ⇒ 60 Hz 下一帧 2 m）——目的是"扑过去"在一两帧内完成，
## 观感上就是瞬移；放慢会变成"看得见它从 A 滑到 B"，那就不像影子了。
const UNIT_SHADOW_DASH_SPEED := 120.0
## 落地时与目标的距离 = `attack_reach() × 本值`。⚠️ 用户只说"移动到伤害来源处"，
## 但**落在它身上**会让两个胶囊互相顶开（引擎的穿透修正）⇒ 落在"够得着但没重合"的位置。
const UNIT_SHADOW_LAND_RATIO := 0.9
## 「时候已到」（技能②，被动）：**距上次出手每满 1 秒伤害 +80，但那是"总伤害"的爬升**——
## ⚠️ **2026-09-25 第四轮（用户："影魔的伤害封顶320是总伤害不是额外伤害"）**：320 是**这一刀打出去的总量**，
## 不是"面板 80 **再加** 320"。⇒ 读数只可能是 **80 / 160 / 240 / 320** 四档（面板 80 + 整秒×80，到顶封住）。
## 用户原话："每过一秒造成的伤害增加80，伤害上限为320，攻击后重置（即持续攻击时不会叠层）"、
## "从影子状态变回原身时自动到达伤害上限"。
## ⚠️ 沿革：第三轮按"额外伤害封顶 320"实现过一版（总伤害 400）—— 第四轮按用户口径改成"总量封顶"。
const UNIT_SHADOW_HOUR_STEP := 80.0       ## 每秒的伤害增量（面板 80，所以第 0 秒就是 80）
const UNIT_SHADOW_HOUR_MAX := 320.0       ## **总伤害**上限（不是额外伤害的上限）
## "变回原身时自动到达上限"的落地：把计时锚点**回拨**满额所需的毫秒数。
## 满额需要 (上限 − 面板) ÷ 每秒增量 = (320 − 80) ÷ 80 = **3 秒**。
## ⚠️ 写成一个显式的 3000 而不是再推一个式子：那个式子里含"面板伤害"（在 PROFILE 里），
## `const` 表达式取不到它；把算式写在注释里、数字留在这里更好核对（这 3 秒与面板 80 是一对，改一个要连另一个）。
const UNIT_SHADOW_HOUR_FULL_MS := 3000

# ---------------------------------------------------------------- 召唤石柱（2026-09-25 第七轮，**仅沙盒模式**）
## 用户口径（原文）："新增单位召唤石柱（仅限沙盒模式）：血量2000，权重999，不移动，伤害200，
## 攻击距离10，攻击速度0.2/s。模型大。拥有技能：单位召唤：在战斗开始前60s，每5s会召唤随机一个
## 召唤石柱以外的单位（要保证以后新增单位时会自动加入召唤石柱的召唤名单），每过60s则多召唤一个，
## 最多4个。"
##
## ⚠️ **它为什么不违反 I-20 / I-27**：那两条的适用范围被用户在 2026-09-25 明确收窄为**竞猜模式**
##（见 `_index.md#2.3` 开头的适用范围说明）—— 沙盒模式刻意不受"两队总权重一致"与"兵种权重档位"约束，
## 所以权重 999 在沙盒里只是一个显示数字。**代价是它必须永不进竞猜池**：
## `PROFILES["pillar"]["sandbox_only"] = true` + `_random_composition()` 显式跳过（见那里的注释）。
##
## ⚠️ 三处"用户没给数、由我定的"（都只在这一个兵种上，改起来一处改完）：
##   · `mass` = **9999**（重量）：用户只说"不移动"，没说被击退怎么办。石柱是死物 ⇒ 取"击退免疫"
##     （与沙虫同一个手法：位移 = 击退数值 ÷ 重量）；⚠️ 它**不动 ≠ 免疫眩晕**，眩晕照吃（用户没要求免疫）。
##   · `UNIT_SUMMON_RING_RADIUS`（召唤落点半径）：必须在判定体之外，否则召唤物一出生就卡在柱子里。
##   · "最多4个"的口径：**每一拍最多召唤几个**（不是"一辈子最多 4 个"）—— 用户下一句是
##     "每过60s则多召唤一个"，若 4 是总量上限，那第二句在第一分钟内就已经撞顶、等于没有意义。
const SUMMONER_TYPE := "pillar"                 ## 召唤者自己的兵种 ID（`summon_pool()` 靠它把自己排除）
const UNIT_SUMMON_INTERVAL_MS := 5000           ## 每多少毫秒召唤一**拍**（用户："每5s"）
const UNIT_SUMMON_WINDOW_MS := 60000            ## 每过这么久，**每一拍**多召唤一个（用户："每过60s"）
const UNIT_SUMMON_MAX_BATCH := 4                ## 每一拍最多召唤几个（用户："最多4个"）
## 召唤落点：以石柱为心的一个随机方位的圆环上（判定体半径约 1.1 m ⇒ 3.2 m 一定在体外来）。
const UNIT_SUMMON_RING_RADIUS := 3.2
## **「权重递增模式」**（用户："战斗开始前10s只能召唤权重为1的单位，之后每过10s召唤单位权重上限
##（不是召唤单位的总权重，是每个单位的权重）增加2"）—— 只在沙盒里**由玩家开局选择是否开启**。
## 触顶读数（下限 1、每 10 s +2）：0~10 s ⇒ 1、10~20 s ⇒ 3、20~30 s ⇒ 5、30~40 s ⇒ 7、50 s ⇒ 11…
## ⇒ 权重 4（火枪兵）在 10 s 后进场、权重 10（两台载具 / 腐化师）在 50 s 后、boss（25）要 120 s 后。
const UNIT_ESCALATION_START_MS := 10000         ## 第一档持续多久（用户："战斗开始前10s"）
const UNIT_ESCALATION_WEIGHT_START := 1         ## 第一档允许的**单兵权重上限**（用户："只能召唤权重为1的单位"）
const UNIT_ESCALATION_WEIGHT_STEP := 2          ## 每过一档，上限 +2（用户："增加2"）

# ---------------------------------------------------------------- 判定体（碰撞体）对齐视觉（2026-09-19 用户要求）
## 用户口径："判定体应和视觉模型相符，所以改变投石车、弩车和沙虫的判定体使其与视觉模型相符
##（不要改变弩车和投石车的视觉建模）"。
##   · 其余 7 种（人形）继续用**胶囊**：半径 `UNIT_BODY_CAPSULE_RADIUS`、总高 `UNIT_BODY_CAPSULE_HEIGHT`
##     —— 与历史值逐位相同（0.38 / 1.80），手感一个字节都没动；
##   · 三个**巨物**改成**盒体**（下表）：`size` = (横 X, 高 Y, 纵深 Z)、`lift` = 盒心离地高度；
##     数值是**引擎内实测的视觉包围盒**（`Unit3D._visual` 子树 AABB，已含载具的 ×2 缩放），
##     标定方法：先按 `UNIT_BODY_BOX` 的占位值跑一次，用 `godot_exec` 读 `visual` 的 AABB，
##     再把 `size` 取整到 0.05 m、`lift` 取 `AABB 中心 y`。
## ⚠️ 这是**玩法数值**（决定命中与碰撞），按不变量 I-15 住进 `GameConfig`，不再硬编码在 `unit3d.gd`。
const UNIT_BODY_CAPSULE_RADIUS := 0.38
const UNIT_BODY_CAPSULE_HEIGHT := 1.80
## 引擎内实测（2026-09-19，`godot_exec` 递归合并 `visual` 子树的 AABB，参考系 = 单位原点）：
##   | 兵种 | 实测包围盒 (X×Y×Z) | 实测底 / 顶 | 本表 size | 本表 lift |
##   | 投石车 | 2.60 × 4.24 × 4.81 | −0.36 / 3.88 | 2.60 × 3.88 × 4.81 | 1.94 |
##   | 弩车   | 5.76 × 1.85 × 4.59 | −0.22 / 1.63 | 5.76 × 1.63 × 4.59 | 0.82 |
##   | 沙虫   | 2.99 × 2.81 × 4.76 | −0.35 / 2.45 | 2.99 × 2.45 × 4.76 | 1.23 |
## ⚠️ **盒底夹到地面**（`lift = top / 2`）：实测底在 −0.2 ~ −0.4（模型有零件低于原点），
## 盒子若照抄就会插进地板、`move_and_slide` 每帧把机体往上顶 ⇒ 只取"地面以上"那一段。
## ⚠️ 这三个盒子**包含抛臂 / 弓臂 / 触须**的扫掠范围（"与视觉相符"的字面口径）⇒ 机器比机体本身更高更宽；
## 若嫌它们太"胖"，下一轮可以只取机体（排除 `Arm*` / `Bow*` / 触须）——那时改这张表即可。
const UNIT_BODY_BOX := {
	"catapult": {"size": Vector3(2.60, 3.88, 4.81), "lift": 1.94},
	"ballista": {"size": Vector3(5.76, 1.63, 4.59), "lift": 0.82},
	## ⚠️ 指挥所（2026-09-26 第三块）：用户口径"占据 3*3"（= 3 格 × 3 格 × 2.0 m/格 = **6 × 6 m**），
	## 高度 3 m 由我定（用户没给）。⚠️ **这两行不是实测值、是按口径算的**（模型与判定体同一批落地）；
	## 将来改指挥所的模型，要照上面那三个巨物的办法**重测**这张表。
	"commandpost": {"size": Vector3(6.0, 3.0, 6.0), "lift": 1.5},
	## ⚠️ 沙虫 2026-09-19 第三轮**去掉触须 + 嘴巴立起来**之后重测（之前 2.88 × 5.12 × 3.10 / 2.56）：
	## 现在是 2.29 × 4.64 × 2.82、盒心 2.32（底正好落在地面 0.00 ⇒ 不需要夹取）。
	## ⚠️ 这份尺寸还派生了**潜地的下沉深度**（`unit3d.gd#_resolve_sink_depth()` = 本值 + 0.6 m）
	## ⇒ 改模型必须重测这张表，否则又会"钻地太浅、模型露头"。
	"sandworm": {"size": Vector3(2.29, 4.64, 2.82), "lift": 2.32},
	## 召唤石柱（2026-09-25 第七轮）：引擎内实测 `visual` 子树 AABB = **2.20 × 5.20 × 2.20**、底正好在 y = 0
	##（`godot_exec` 递归合并各件包围盒，方法与 2026-09-19 那三台同一套；取整到 0.05 m ⇒ 与实测同值）。
	## ⚠️ **刻意排除贴地的队伍色光环**（`TeamAccent_Ring`）：它是一片半径 1.65、厚 0.04 m 的**地面标记**，
	## 算进去的话盒体会变成 3.30 m 宽、把半个场地堵住 —— 与沙虫那条"只取地面以上那一段"是同一类取舍
	##（口径见 `04_physics.md#4`：盒体描述的是**身体**，装饰件不算）。
	## ⚠️ 连带事实（都是这张表的派生量，一处改完全跟着走）：`body_radius("pillar")` = 1.10 m ⇒
	## 近战打它按**表面**算（`surface_distance_to()`）、动量传递的"撞上"半径取 max(0.9, 1.10 + 对方半径)、
	## 血条挂点 = 2.60 + 2.60 + 0.35 = **5.55 m**（正好在 5.20 m 高的晶体之上）。
	"pillar": {"size": Vector3(2.20, 5.20, 2.20), "lift": 2.60},
	## 湮灭之瞳（2026-09-27 第十轮新增 / **第十一轮重做成"一只眼"**）：引擎内实测 `visual` 子树 AABB =
	## **3.19 × 3.05 × 3.34**、盒心 **1.10 + 3.05 / 2 = 2.63**（方法同石柱那次：递归合并各件的 AABB，
	## **必须用 global 变换** —— 瞳孔三件挂在带旋转的 `GazePivot` 下，只乘自己的 `transform` 会算歪）。
	## ⚠️ **刻意排除贴地的队伍色光环**（`TeamAccent_Ring`，半径 3.10）：算进去会变成 6.20 × 4.27 × 6.20
	## —— 那是**地面标记**不是身体，与石柱那条同一个取舍（口径见 `04_physics.md#4`）。
	## ⚠️ 沿革：第十轮那版"能量核心"是 (6.20, 3.90, 6.20)/1.95；第十一轮改成"一只眼"时**当场重测过两次**
	##（先按手算 (3.60, 3.17, 3.12) 落地 → 实测 (3.60, 3.22, 3.31)/2.66 → 眼皮从半球壳改成环面后
	## 再实测到下面这组）。⇒ **改这个模型就必须重测这一行**。
	"doom_eye": {"size": Vector3(3.19, 3.05, 3.34), "lift": 2.63},
}
## 轻骑兵的马比判定胶囊长。沙盒摆放按这组视觉尺寸留空，判定体仍是胶囊，不进 `body_radius()`。
const UNIT_LIGHTCAV_VISUAL_X := 0.910
const UNIT_LIGHTCAV_VISUAL_Y := 3.090
const UNIT_LIGHTCAV_VISUAL_Z := 4.325

## 该兵种的**判定体**是不是盒体（三个巨物）。返回空字典 = 用默认胶囊。
func body_box(type_id: String) -> Dictionary:
	return UNIT_BODY_BOX.get(type_id, {})

## 该兵种的**水平等效半径**（m）：胶囊取半径，盒体取长宽中较大的一半。
## ⚠️ 它是"身体多大"的派生量，不是另开的一组数值；两处耦合都用它：
##   ① 出生间距（`SPAWN_MIN_GAP`）改成 `max(1.0, 两者半径之和)` —— 否则大单位一出生就互相穿插
##      （几何约束 G-02 只管"至少 1.0 m"，放大是允许的）；
##   ② 动量传递的"撞上"判定（`KNOCKBACK_CONTACT_RADIUS`）改成 `max(0.9, 两者半径之和)` ——
##      那个 0.9 原本就是"胶囊半径 0.38 × 2 + 余量"推出来的，巨物贴着时不能算没撞上。
func body_radius(type_id: String) -> float:
	var box: Dictionary = body_box(type_id)
	if box.is_empty():
		return UNIT_BODY_CAPSULE_RADIUS
	var size: Vector3 = box["size"]
	return maxf(size.x, size.z) * 0.5

## 沙盒摆放用的身体尺寸（本地 X 横、Y 高、Z 纵深）。有判定盒的读那张表，其余按胶囊直径。
## 轻骑兵读视觉尺寸，避免马身叠在一起，同时不把判定体改大。
func place_footprint_size(type_id: String) -> Vector3:
	var box: Dictionary = body_box(type_id)
	if not box.is_empty():
		return box["size"]
	if type_id == "lightcav":
		return Vector3(UNIT_LIGHTCAV_VISUAL_X, UNIT_LIGHTCAV_VISUAL_Y, UNIT_LIGHTCAV_VISUAL_Z)
	return Vector3(UNIT_BODY_CAPSULE_RADIUS * 2.0, UNIT_BODY_CAPSULE_HEIGHT, UNIT_BODY_CAPSULE_RADIUS * 2.0)

## 身体最高点（含悬浮）。操控镜头放在这之上，才不会钻进沙虫、湮灭之瞳这类大模型。
func pilot_body_top(type_id: String) -> float:
	var box: Dictionary = body_box(type_id)
	if box.is_empty():
		return place_footprint_size(type_id).y
	var size: Vector3 = box["size"]
	return float(box["lift"]) + size.y * 0.5

## 身体水平方向伸出中心多远。镜头再往外一截，才不会被正面挡住。
func pilot_body_front(type_id: String) -> float:
	var box: Dictionary = body_box(type_id)
	var size: Vector3 = place_footprint_size(type_id) if box.is_empty() else box["size"]
	return maxf(size.x, size.z) * 0.5

# ---------------------------------------------------------------- 相机手感
const CAM_FOV := 70.0                          ## 视野角
const CAM_MOUSE_SENSITIVITY := 0.0022          ## 鼠标灵敏度 rad/px
const CAM_PITCH_MIN := -1.45                   ## 俯仰下限 rad
const CAM_PITCH_MAX := 1.45                    ## 俯仰上限 rad
const CAM_FLY_SPEED := 14.0                    ## 自由飞行速度 m/s
const CAM_FLY_SPEED_ROGUELIKE_MULT := 2.0      ## ⚠️ **仅肉鸽**的飞行速度倍率（2026-09-27 用户："（仅限肉鸽模式）镜头的移动速度变为原来的2倍"）—— 肉鸽场地 150 × 111.5，用竞猜那档速度挪起来太慢；三个模式各自取自己的档，沙盒 / 竞猜保持 1.0
const CAM_FLY_BOOST_MULT := 2.8                ## 按住 Shift 的飞行倍率（与上面那条**相乘**）
const CAM_FLY_SMOOTH := 18.0                   ## 飞行速度平滑（越大越跟手）
## ---- 滚轮推拉（2026-09-25 用户："在竞猜模式的押注阶段和沙盒模式的布兵阶段可以通过滚轮来拉近拉远镜头"）----
## ⚠️ **与 W 的分工**（用户原话："w 只能沿镜头方向**水平**移动，而滚轮能够**同时在水平和竖直方向上**移动"）：
## WASD 用的 `forward` 是**水平**的（y 恒为 0，见 `camera_rig.gd#_physics_process`），
## 滚轮走的是**完整视线方向**（含俯仰分量）⇒ 俯视时滚轮会一边靠近、一边降低高度。
## ⚠️ 每格步长按"当前到 `CAM_OVERVIEW_FOCUS` 的距离"取比例：拉近时越来越细、不会一步冲过焦点，
## 飞远之后又有上限兜着；夹在 `[CAM_ZOOM_STEP_MIN, CAM_ZOOM_STEP_MAX]` 之间。
const CAM_ZOOM_STEP_RATIO := 0.10              ## 滚轮每格 = 到焦点距离 × 这个比例（无量纲）
const CAM_ZOOM_STEP_MIN := 2.0                 ## 每格步长下限 m（贴近时仍有手感）
const CAM_ZOOM_STEP_MAX := 12.0                ## 每格步长上限 m（飞远后不至于一格跳一座场）
const CAM_ZOOM_MIN_HEIGHT := 2.0               ## 推拉时的离地高度下限 m（俯视拉近到底也不钻到地板下面）
## ⚠️ **最近距离**：不许推到焦点（0, 0.4, 0）跟前去。
## 少了这一道：俯视方向一路推到底会先被高度下限压平、再**贴着地面从场地中间穿出去**，
## 观感是"镜头飞到场外了"（探针实测：不设界时可以径直穿过焦点继续前进）。
## 12 m ≈ 停在场地中圈外侧，下压到 7 m 高 —— 这时整块 100 × 50 的场地仍在画面里。
const CAM_ZOOM_MIN_DISTANCE := 12.0             ## 镜头到 `CAM_OVERVIEW_FOCUS` 的最近距离 m
## ⚠️ **平滑**（2026-09-25 用户："滚轮移动镜头时应该顺滑点，过渡应光滑"）：
## 滚轮只改**目标机位**（`camera_rig.gd#_zoom_target`），`_pos` 每帧按指数缓动追过去 ——
## 与帧率无关（`1 − e^(−k·dt)`，同 `CAM_FLY_SMOOTH` 的手法）。取 12 ⇒ 约 63% 在 0.08 s、
## 95% 在 0.25 s 走完一格；调大更跟手、调小更飘，**0 = 退回"一格一跳"**（改前的手感）。
const CAM_ZOOM_SMOOTH := 12.0                  ## 推拉缓动速率 1/s
## 全景距离：38 → **73**。
## 历史：原为 60（罩住整个 52×24 场地），但那样选手小到看不清 → 降到 38 只罩"中央条带"（优化 4）。
## 本轮场地放大到 100×50（半宽 26 → 50，×1.92），全景按同一比例放大回 73，
## 否则押注阶段只能看到场地正中一小块、东西两端全被切掉。
## 代价：全景里单个选手更小 —— 想看清单个选手请用开战机位 / 跟随 / 自己飞过去。
const CAM_OVERVIEW_DISTANCE := 73.0
const CAM_OVERVIEW_PITCH := -0.58              ## 全景俯角（负值 = 俯视）
## 竞猜押注和沙盒布兵共用这一档。自由视角飞去的落点仍是上面的 `CAM_OVERVIEW_PITCH`。
## −0.46 → −0.38：高度 73 × sin(0.38) ≈ 27 m。距离不动，场地宽度不变。
const CAM_QUIZ_PITCH := -0.38
											   ## 2026-09-19 用户要求"押注阶段默认镜头高度太高，稍微降低"：
											   ## 73 × sin(0.80) ≈ 52 m → 73 × sin(0.72) ≈ 48 m。
											   ## ⚠️ **2026-09-25 用户又提了一次同样的话（"默认的镜头高度太高了，调低一点"）**：
											   ## −0.72 → **−0.58** ⇒ 高度 73 × sin(0.58) ≈ **40 m**（比上一版再低 8 m）。
											   ## ⚠️ **仍然只压俯角、不动 `CAM_OVERVIEW_DISTANCE`** —— 距离一缩，
											   ## 100 × 50 m 的场地就会被切掉东西两端（见上方注释）；73 m 不变 ⇒ 视场宽度不变。
const CAM_OVERVIEW_FOCUS := Vector3(0.0, 0.4, 0.0)  ## 全景焦点
const CAM_OVERVIEW_SWAY := 0.22                ## 全景左右摆动幅度 rad
const CAM_OVERVIEW_SWAY_SPEED := 0.16          ## 全景摆动速度
## ---- 肉鸽的**部署机位**（2026-09-26 第四块：用户"修改肉鸽模式默认视角，方便操作与分清敌我关系"）----
## 与全景机位同一套状态（FLY + 准滚轮推拉 + 显形光标），只换三个姿态量；焦点沿用 `CAM_OVERVIEW_FOCUS`
##（场地中心 —— ⚠️ 刻意**不另开一个同值常量**：同一件事只允许一个名字，见 `08_naming.md#1.4`）。
## ⚠️ **yaw 是这一条口径的关键**：镜头退到**己方（0 队 = 西）后方偏南**，于是屏幕**左下 = 我方、右上 = 敌方**
##（用户要的"分清敌我关系"）；全景那条 `yaw = 0` 是从正南看，两队变成左右并排 ⇒ 分不清谁是谁。
## ⚠️ **焦点不在场地中心、而在己方半场里（x = −52）**：焦点永远落在屏幕正中（`_apply_pose()` 的定义），
## 而**底部面板盖住了屏幕最下面 37%**（`ACTION_PANEL_HEIGHT`，实测面板顶边 y = 553 / 900）——
## 焦点放场地中心会让整个下半场（正是玩家要布阵的那一半）沉到面板底下。
## ⚠️ 这五个数是**按"关键点投影"选的**（引擎内 `unproject_position` 扫描，不是凭感觉调）：
## 判据 = 我方布阵区最靠下的那一点 ≤ 520 px，同时敌方底线仍在画面里。1600×900 实测（50 m 半宽那版）：
## 我方布阵区 y 295~463、两座我方指挥所 y 298、敌方指挥所 y 161、敌方底线 y 47。
## ⚠️ **焦点与距离按"场地半宽"的比例**（肉鸽的场地比全局大 ⇒ 写死的绝对值会把新场地切掉）。
## ⚠️ **2026-09-26 更正后重扫过**（变的是**横排方向 Z** ⇒ 场地 100 × 87.5，接近方形）：原来那套"从南看"
## 的方位角会让近处那半沉到面板底下（实测无解）；改成**镜头退到西偏南（yaw ≈ −63°）** ⇒
## 87.5 m 的"宽"**横铺在画面里**、纵深被压缩 ⇒ 一组就过。判据同上一版（我方落位区 / 两座我方指挥所 /
## 敌指挥所 / 敌方底线 / 场地中心共 8 个关键点全在 y ≤ 520 且 x ∈ [40, 1560] 内）。
## 本组实测（1600×900）：关键点 y[85..510]、x[441..1261] ⇒ 全部在底部面板（顶边 553）之上 ✓。
## ⚠️ **2026-09-27 第四次重扫（按用户给的参考图取景）+ 同日微调**：
## 构图从"正南俯视、整场一屏"改成**从西南方往东北方俯看、场地铺满画面** ——
## 世界 +X（东）落在画面的**右上**、−Z（北）落在**左上**（所以树在左上、两队出生带一条在左下一条在右上）。
## ⚠️ **用户 2026-09-27 又提了两句**："再往右下旋转一点，高度变高" ⇒
##   ① **画面顺时针转一点**：方位角 −0.52 → **−0.35**（世界 +X 轴摊得更平、更贴屏幕横轴）；
##   ② **镜头抬高**：俯角 −0.78 → **−0.90**（相机高度 = 距离 × sin|俯角|，从 ≈ 40 m 抬到 ≈ 50 m），
##      距离同时 0.75 → **0.85**（半宽 × 0.85 ≈ 64 m）⇒ 抬高的同时把构图撑住，不再切掉更多场地。
## ⚠️ **取景取舍（实测过三版）**：按参考图贴到最近（52 m、焦点在正中）时**两块可布阵地几乎全在画外**
##    （我方半场中心 y = 496 已被面板挡住、自动落位格 x = −281）；退到 70 m 又明显比参考图远。
##    本版＝**参考图的近 + 焦点往我方偏 25 m**：我方半场中心 / 自动落位格 / 我方可用带西端都进画面。
## 参数：焦点 X = −0.33 × 半宽（≈ −25 m）、焦点 Z = 0.32 × 半深（≈ 18 m）、距离 **0.85 × 半宽 ≈ 64 m**、
## 方位角 **−20°**、俯角 **−52°**。
## ⚠️ 更早三版参数（第四块的"西偏南斜看"、第七块的"焦点 Z 0.95 / 距离 1.55 正南俯视"）**都已作废**。
## 2026-10-23：视线再低一点、再偏东一点；机位再低、再靠西。
## 俯角 −0.90 → −1.02，方位角 −0.35 → −0.50，焦点 X −0.33 → −0.42，距离 0.85 → 0.70。
## 只加俯角会把镜头抬高，所以距离一起缩短。半宽 75 m 时高度约 45 m（上一档约 50 m）。
const CAM_ROGUELIKE_FOCUS_RATIO := -0.42       ## 焦点 X = 场地半宽 × 本值（负 = 往我方半场偏）
const CAM_ROGUELIKE_FOCUS_Z_RATIO := 0.32      ## 焦点 Z = 场地半深 × 本值（≈ 18 m，略偏南）
const CAM_ROGUELIKE_DISTANCE_RATIO := 0.70     ## 机位到焦点的距离 = 半宽 × 本值
const CAM_ROGUELIKE_YAW := -0.50               ## 水平方位角 rad（镜头更靠西，视线更偏东）
const CAM_ROGUELIKE_PITCH := -0.92             ## 俯角 rad（2026-10-23：视线再抬一点，−1.02 → −0.92）
## ---- 拖动"幽灵"的两个颜色（2026-09-26 第六块）----
## 绿 = 放得下 / 红 = 放不下。⚠️ **两个模式共用这两个值**（沙盒的"摆兵笔"幽灵与肉鸽的"换位拖动"幽灵），
## 所以住 `GameConfig` 而不是各写一份 —— 同一件事只允许一个名字、一份值（`08_naming.md#1.4`）。
## ⚠️ 它们**不是**玩法数值，只是跨模式共用的表现色；肉鸽格子那一层填充色（`CELL_*`，含透明度）
## 仍是它自己的表现参数，不住这里。
const GHOST_OK_COLOR := Color(0.35, 0.95, 0.55, 1.0)
const GHOST_BAD_COLOR := Color(0.95, 0.30, 0.30, 1.0)
## 开战机位：直接摆到"两队质心上方偏后"的指挥视角，而不是沿用全景远景（优化 4）
## ⚠️ 高度 / 后退从 22 / 26 调到 28 / 32：水平视场角 102.4°（FOV 70 + 16:9），
## 焦点深度上的可见半宽 ≈ 镜头到焦点的距离 × 1.245；而场地半宽已经是 50 m、
## 两队最远会在 ±47.5 m 处出生，所以镜头到焦点至少要 40 m —— 28 / 32 → 42.5 m。
const CAM_FIGHT_HEIGHT := 28.0                 ## 开战时镜头高度 m
const CAM_FIGHT_BACK := 32.0                   ## 开战时镜头相对质心的后退距离 m
const CAM_FIGHT_PITCH := -0.66                 ## 开战时俯角 rad
## 开赛镜头的过渡时长（2026-09-18）：下注阶段停在**全景远景**，开赛要落到"质心上方偏后"的指挥视角。
## 优化 4 时代这里是**硬切**（直接赋值），虽然解决了"看不清"，但观感像跳了一下；
## 现在保留同一个落点，只把过程改成 `CAM_FIGHT_BLEND_MS` 内的 smoothstep 过渡——
## 两端速度为零，所以既是"无缝衔接"，也不会在结尾顿一下。
## 玩家一动鼠标 / 按 WASD 就立刻中断过渡，把镜头交还给玩家（过渡不抢操作）。
const CAM_FIGHT_BLEND_MS := 900
const CAM_FOLLOW_DISTANCE := 9.0               ## 跟随时的后退距离 m
const CAM_FOLLOW_HEIGHT := 4.5                 ## 跟随时的抬高 m
const CAM_FOLLOW_LAG := 3.5                    ## 跟随延迟
## 第一人称操作（沙盒 / 生存的战斗）。默认第一人称；X 切到右肩后方。
## 高度从身体最高点往上加，前后从身体外缘再加，大模型不会挡在镜头里。
const CAM_PILOT_ABOVE := 0.55                  ## 第一人称：高出身体顶部 m
const CAM_PILOT_AHEAD := 0.45                  ## 第一人称：伸出身体正面 m
const CAM_PILOT_SHOULDER_LIFT := 1.0           ## 越肩：高出身体顶部 m
const CAM_PILOT_SHOULDER_BACK := 2.5           ## 越肩：留在身体后面 m
const CAM_PILOT_SHOULDER_RIGHT := 0.55         ## 越肩：偏到右肩 m
const CAM_PILOT_PICK_RADIUS_PX := 80.0         ## 按住 Alt 点选时，射线打不中（潜地）就用这个屏幕半径补选
const CAM_PILOT_AIM_CONE_DEG := 35.0           ## 近战沿准星挥时，面前多大的夹角算打中
const CAM_PILOT_BEAM_TOLERANCE := 0.9          ## 持续照射：准星射线侧面多近才照到人 m
const CAM_SHAKE_DECAY := 3.2                   ## 镜头震动衰减

# ---------------------------------------------------------------- 选手属性表（六项）
## 属性：血量 / 伤害 / 攻速 / 射程 / 权重 / **移速**
## 攻速 = 每秒攻击次数；射程与移速单位米；权重 = 占位成本（三种兵现在都是 1）。
## 数值用 debug_balance_stats 回归标定：三种兵 1v1 应互有胜负，不应该有"必赢"组合。
## ⚠️ `"weight"` 与 `"mass"` 是**两件事**（不变量 I-26，两者目前数值都是 1，但不要互相替代）：
##   `"weight"` = **配平**用的占位成本（决定每队人数与阵容评分，见 `02_entities.md#4`、I-27）
##   `"mass"`   = **击退**用的物理质量（位移 = 击退数值 ÷ mass，见 `04_physics.md#5`）
var PROFILES := {
	"sword": {
		"id": "sword", "name": "剑盾兵", "name_en": "Sword & Shield",
		"hp": 300.0, "damage": 34.0, "attack_speed": 0.90, "range": 1.8,
		"weight": 1, "mass": 1, "move_speed": 2.9,
		"is_ranged": false, "has_shield": true, "shield_arc_dot": -0.34,
	},
	"spear": {
		"id": "spear", "name": "长矛兵", "name_en": "Spearman",
		## 伤害 2026-09-18 由 34 → **51**（×1.5，用户指定）：取消全场倍率后长矛→剑盾跌出了
		## `04_physics.md#5` 的 55~90% 判据带（实测 43~50%），按该节既有结论"改伤害或血量"上调。
		"hp": 195.0, "damage": 45.0, "attack_speed": 1.00, "range": 3.2,
		"weight": 1, "mass": 1, "move_speed": 3.1,
		## `"knockback"` = **击退数值**（2026-09-18 由 1.0 → 2.0，用户指定）：
		## 冲量 = `KNOCKBACK_SPEED × 本值`，位移再 ÷ 目标重量。对重量 1 的目标等效初速仍 15.0。
		"is_ranged": false, "has_shield": false, "knockback": 2.0,
		## 攻击动作是**向前突刺**（矛杆前后移动），不是挥砍；见 `unit3d.gd#_animate_attack`
		"thrust": true,
		## 前摇比全局 `UNIT_WINDUP_RATIO`(0.30) 短一半：长矛是"捅"，抬矛的预备动作本来就该快
		"windup_ratio": 0.15,
	},
	## 短弓手（2026-09-25 由「弓兵」**改名**，不是新兵种）：显示名与实体 ID 一起改，`archer` → `shortbow`。
	## 七项数值一个字节都没动（血量 120 / 伤害 42 / 攻速 0.75 / 射程 16 m / 权重 1 / 重量 1 / 移速 3.4）。
	## ⚠️ **2026-09-25 第二条（用户："短弓手箭矢速度变为长弓手的四分之三""短弓手箭矢应有抛物线"
	## "短弓手箭矢重建模"）**：`"projectile"` 由 `"arrow"` 改成 **`"shortbow_arrow"`** ——
	## 它现在也走**抛物线 + 落点预判**（与长弓手共用同一条弹道解），只是速度与下坠更小；
	## 投射物网格也重做（与长弓的细长箭刻意区分，见 `arrow.gd#_build_shortbow_arrow()`）。
	"shortbow": {
		"id": "shortbow", "name": "短弓手", "name_en": "Shortbowman",
		## ⚠️ 2026-09-25 用户："**短弓手伤害变为 35**"：伤害 **42 → 35**（配合长弓手 100 → 90 的同步下调）。
		## 其余六项未动（血量 120 / 攻速 0.75 / 射程 16 m / 权重 1 / 重量 1 / 移速 3.4）。
		"hp": 120.0, "damage": 35.0, "attack_speed": 0.75, "range": 16.0,
		"weight": 1, "mass": 1, "move_speed": 3.4,
		"is_ranged": true, "has_shield": false,
		"projectile": "shortbow_arrow",
	},
	## 长弓手（2026-09-25 新增，用户口径）："血量140，伤害100，射程30m，攻速0.4/s，重量1，权重2，
	## 移速与短弓手相同（箭矢速度快，能预判，抛物线）"。
	##   · 移速 = 短弓手同款 **3.4 m/s**（用户明说"与短弓手相同" ⇒ 引用同一个值，不是另写一个数）；
	##   · 权重 **2** ⇒ 与扇子兵 / 骑士同档（第 1 轮预算 10 够 5 个，或 2 个 + 若干 1 权重兵）；
	##   · 弹道：`"longbow_arrow"` —— **抛物线 + 落点预判**，与短弓手那条直线箭**分道**
	##     （口径见 `arena.gd#spawn_arrow` 的 `"longbow_arrow"` 支与 `UNIT_LONGBOW_*` 常量组）。
	## ⚠️ 射程 30 m 是**用户明确给的**：全场第二远（仅次于弩车 44 m、超过投石车 35 m 之外的所有人）。
	##     它必须与"抛物线弹道 + 0.4 攻速"一起看 —— 单发 100 但 2.5 s 才一箭（理论 DPS 40），
	##     且远距离飞行时间长 ⇒ 预判才是它的核心，不是射程本身。
	"longbow": {
		"id": "longbow", "name": "长弓手", "name_en": "Longbowman",
		## ⚠️ 2026-09-25 用户："**长弓手伤害变为 90，射程变为 28**"：
		## 伤害 **100 → 90**、射程 **30.0 → 28.0 m**（同时短弓手伤害 42 → 35）。
		## ⚠️ 射程下调**不影响弹道解**：28 m 远在 `52²/16 = 169 m` 的最大平射程之内，
		## 所以 `UNIT_LONGBOW_ARROW_*` 两个常量**都不用动**（这与投石车"射程与初速必须成对改"不同 ——
		## 那是因为它的射程 35 m 已经逼近 `26²/16 = 42.25 m` 的上限）。
		## 其余四项未动（血量 140 / 攻速 0.40 / 权重 2 / 重量 1 / 移速 3.4）。
		"hp": 140.0, "damage": 90.0, "attack_speed": 0.4, "range": 28.0,
		"weight": 2, "mass": 1, "move_speed": 3.4,
		"is_ranged": true, "has_shield": false,
		"projectile": "longbow_arrow",
	},
	## 轻骑兵（矛）（2026-09-25 新增，用户口径）："血量400，伤害40，射程3.4m，攻速0.6/s，重量3，权重4，
	## 移速7m/s，拥有技能：冲锋"。
	## ⚠️ 那句里的"**权重4**"是**新增当时的原话**，保留作沿革 —— **同日已改成 5**（用户："将轻骑兵的权重变为 5"），
	## 以本字典里的 `"weight": 5` 为准。
	##   · 权重 **5**：由 4 改（2026-09-25 用户："将轻骑兵的权重变为 5"）⇒ 档位 `4` 从此**没有兵种占用**
	##     （同 `8` 的先例：投石车改回 10 之后 8 就空着），I-27 照旧是"**只改例子、规则未动**"；
	##     连带事实：它与弩车 / 投石车（10）**不同档**、比狂战士（3）贵；第 1 轮预算 10 ⇒ 一队**最多 2 个**轻骑兵。
	##   · 移速 **7.0 m/s** 是**全场最快**（原纪录是狂战士 3.8 m/s，几乎翻倍）——它靠走位进场，
	##     而不是靠射手那样的射程；
	##   · 重量 **3** ⇒ 长矛兵的击退数值 2 推得动它（与骑士的重量 2 是同一条"禁移"判据的两侧）；
	##   · 技能·**冲刺**（`"skill": "charge_lance"`，与骑士的 `"charge"` 是**两个不同的技能**）：
	##     7 m 触发 → **8 s** 冲刺（**全程 14 m/s**；方向每帧朝目标更新，**够得着 180°/s、够不着 270°/s**）→
	##     对前方矩形（**宽 1.5 m × 长 3.4 m**、**每 0.3 s 结算一跳**；⚠️ 矩形**逐帧扫描、跳拍结算** ——
	##     进过框的人**一定会**在下一跳吃到，见 `_lance_scan_box()` / `_lance_settle_box()`）
	##     造成「40 + 附加伤害」并击退 3；
	##     冷却 5 s、**每场限 1 次**（⚠️ **被眩晕只是「暂停」，不作废也不退还**，见 `UNIT_LANCE_CHARGES_MAX`），
	##     **冷却期间不接敌，在 10~16 m 处游走**。
	##     数值全在 `UNIT_LANCE_*` 常量组，机制见 `02_entities.md#2.3`。
	## ⚠️ 上面两行 2026-09-25 第三条已更正：原文写"前 1.5 s 追踪 / 后 1.5 s **锁定方向**、10 m/s、
	##     7 m 外游走"——那是**同日第一次大改之前**的旧口径，`UNIT_LANCE_*` 常量本身早就是
	##     14 m/s / 180° / 10~16 m，只有这段注释没跟着改。典型的"注释漂移"：**注释不参与行为**，
	##     以常量为准。记在这里是因为它是本项目踩过多次的同一个坑（见 `99_decisions.md`）。
	"lightcav": {
		"id": "lightcav", "name": "轻骑兵（矛）", "name_en": "Light Cavalry (Lance)",
		## 血量 400 → **350**（2026-09-25 用户："轻骑兵血量变成350"）。
		"hp": 350.0, "damage": 40.0, "attack_speed": 0.6, "range": 3.4,
		"weight": 5, "mass": 3, "move_speed": 7.0,
		"is_ranged": false, "has_shield": false,
		"knockback": UNIT_LANCE_HIT_KNOCKBACK,
		## 出手动作 = **向前突刺**（2026-09-25 用户："轻骑兵攻击时长矛不应上下舞动，应该前后戳刺"）。
		## 走 `PROFILES[*].thrust` 这一支（与长矛兵同一条）⇒ `unit3d.gd#_animate_attack()` 只推**位置**
		## （沿本体 −Z、距离 `UNIT_THRUST_DISTANCE`）、**`rotation` 全程不变** ⇒ 上下舞动消失。
		## ⚠️ **出手节奏一字未动**：`thrust` 只换动画通道，命中帧仍是那条 `0 → 1.15 → 0` 曲线的**顶点**
		## （= `windup`），所以 `windup_ratio` 保持默认 0.30 ⇒ 攻速 0.60 与面板 DPS 都不变。
		"thrust": true,
		"skill": "charge_lance",
	},
	## 扇子兵（2026-09-18 新增）：攻击力极低，但**一次挥扇命中面前一片扇形**里的所有敌人并施加击退数值 2。
	## 权重 2（占两个名额）、重量 1（被推得动）。扇形判定见 `unit3d.gd#_resolve_attack`。
	"fan": {
		"id": "fan", "name": "扇子兵", "name_en": "Fan Dancer",
		"hp": 300.0, "damage": 12.0, "attack_speed": 1.20, "range": 3.4,
		"weight": 2, "mass": 1, "move_speed": 2.9,
		"is_ranged": false, "has_shield": false,
		"attack_arc_deg": UNIT_FAN_ARC_DEG,
		"knockback": 3.0,
		## 2026-09-19 用户要求：击退数值 2.0 → **3.0**（扇子兵的扇形攻击也推开人）。
	},
	## 骑士（2026-09-18 新增）：数值更高的剑盾兵，带技能·冲撞（冷却 8 s）。
	## 重量 2 ⇒ 长矛兵的击退数值 2 **推不动它**（`04_physics.md#5` 的禁移条件），这是刻意的定位差。
	"knight": {
		"id": "knight", "name": "骑士", "name_en": "Knight",
		"hp": 380.0, "damage": 44.0, "attack_speed": 0.85, "range": 1.9,
		"weight": 2, "mass": 2, "move_speed": 2.8,
		"is_ranged": false, "has_shield": true, "shield_arc_dot": -0.34,
		"skill": "charge",
		## 2026-09-19：第二个技能「盾牌猛击」（用户要求保留冲撞 ⇒ 这里是**新增**而不是替换）。
		## 只开一个开关，数值全在 `UNIT_BASH_*` 三个常量里。
		"bash": true,
	},
	## 投石车（2026-09-18 R2）：抛射石弹，落地范围伤害 + 击退数值 3。攻速极慢、走得最慢。
	## 重量 5 ⇒ 只有弩车自己的击退推得动它。
	## ⚠️ **权重 10**（2026-09-25 第五条由 8 改回，用户："权重变回 10"）⇒ 第 1 轮（总权重 10）
	## **正好一队一辆**；且它与弩车**重新同档** —— 2026-09-19 那句"两台载具从此不同档"**作废**。
	## 2026-09-19：射程 26 → 35 m（用户要求）。⚠️ 与 `UNIT_STONE_SPEED` **耦合**：石弹最大水平射程
	## = v²/g，所以射程一改就必须同步改初速，否则远目标打不到（弹道解会把瞄点夹到最大射程）。
	## 2026-09-19 第二条（用户："投石车攻速：0.25 变成 0.3"）：面板间隔 4.00 → **3.33 s**、前摇 1.20 → **1.00 s**，
	## 理论 DPS 35 → 42；⚠️ 射程与石弹初速**都没动**，所以弹道不受影响。
	## 2026-09-19 第三条（用户："投石车直击伤害变为 160，溅射伤害为它的一半"）：直击 140 → **160**、
	## 溅射 70 → **80**（见 `UNIT_STONE_SPLASH_DAMAGE`）；理论 DPS 42 → **48**（160 ÷ 3.33 s）。
	## ⚠️ 只动伤害：射程 35 / 初速 26 / 攻速 0.3 全部不变 ⇒ 弹道与出手节奏一个字节都没变。
	## ⚠️ **2026-09-25 第五条（用户："伤害变回 140，但是会对所有击中的敌人附加眩晕 1"）**：
	## **直击 160 → 140、溅射 80 → 70**（两处一起改，维持"溅射 = 直击的一半"）⇒ 理论 DPS 48 → **42**；
	## **新增**：落点范围内**每一个被击中的敌人**都吃 `UNIT_STONE_STUN_MS`（**眩晕 1**），
	## 实现在 `Arrow._explode()`（直击与溅射**不分档**，与用户裁定的"所有击中的"一致）。
	## ⚠️ 射程 / 初速 / 攻速 / 击退数值**都没动** ⇒ 弹道与出手节奏仍是一个字节都没变。
	"catapult": {
		"id": "catapult", "name": "投石车", "name_en": "Catapult",
		"hp": 260.0, "damage": 140.0, "attack_speed": 0.3, "range": 35.0,
		## ⚠️ **2026-09-25 第五条（用户："权重变回 10"）：8 → 10** —— 与弩车**重新同档**，
		## 2026-09-19 那句"两台载具从此不同档"**作废**。连带事实：第 1 轮预算 10 ⇒
		## 一队**只装得下一辆**投石车（正好占满整队预算，与最早的 10 时代一致）。
		"weight": 10, "mass": 5, "move_speed": 2.4,
		"is_ranged": true, "has_shield": false,
		## 大型弹射物：**无法被盾牌阻挡**（2026-09-19 用户要求，与弩车同为 `04_physics.md#7` 的例外）。
		## 对它尤其重要：被判定"挡住"的石弹只会钉在盾上、**不会落地炸开**，等于整发消失。
		"projectile": "stone", "aoe_radius": UNIT_STONE_AOE_RADIUS, "ignores_shield": true,
		"knockback": 3.0,
		## **直击 140 / 溅射 70**（= 直击的一半，见 `UNIT_STONE_SPLASH_DAMAGE`；2026-09-25 第五条改回）。
		"splash_damage": UNIT_STONE_SPLASH_DAMAGE,
		## **免疫眩晕**（2026-09-25 第六条，用户："投石车和弩车不会被眩晕"）：
		## 判据 `GameConfig.is_stun_immune()`（= 本字段 ∪ `is_boss()`）。
		## ⚠️ 刻意**不复用** `boss` 字段：那个还带"每队最多一个"的配平含义。
		"stun_immune": true,
	},
	## 弩车（2026-09-18 R2 / 2026-09-19 调整）：射程最远、单发最高、弩箭极快、
	## **大型弹射物，无法被盾牌阻挡**（`ignores_shield`）；单体命中后击退 20；
	## 它造成的击退在传递时会**附带伤害**（`04_physics.md#5.1` 的唯一特例）。
	## 2026-09-19：攻速 0.15 → 0.2（用户要求）⇒ 面板间隔 6.67 s → **5.0 s**，理论 DPS 60 → 80。
	"ballista": {
		"id": "ballista", "name": "弩车", "name_en": "Ballista",
		"hp": 240.0, "damage": 400.0, "attack_speed": 0.2, "range": 44.0,
		"weight": 10, "mass": 5, "move_speed": 2.2,
		"is_ranged": true, "has_shield": false,
		"projectile": "bolt", "ignores_shield": true,
		"knockback": 60.0, "knockback_damage": UNIT_BALLISTA_TRANSFER_DAMAGE,
		## **免疫眩晕**（2026-09-25 第六条，用户："投石车和弩车不会被眩晕"）—— 与投石车同一条规则，
		## 判据 `GameConfig.is_stun_immune()`。⚠️ 它**照旧会被击退**（重量 5），免疫的只是眩晕。
		"stun_immune": true,
	},
	## 狂战士（2026-09-18 R3）：全场最快、双持斧（一次出手两把各结算一次）、
	## 技能·火箭跳跃（跳过去 + 滞空与落地 0.5 s 免疫一切伤害，冷却 2 s，第二次起距离减半）。
	## 2026-09-19：**权重 2 → 3**（用户要求），血量与伤害**按用户指定 ×2**（200→400、16→32），
	## 出手速度与双斧两段不变 ⇒ 有效 DPS 44.8 → 89.6。注意这不是"按权重涨幅折算"：
	## 权重只涨了 50%（2→3），数值涨 100% ⇒ 单位权重战力比原先更高，属刻意的加强。
	## 权重 3 的意义：此前权重只有 1/2/10，某队若 3 个兵种全是偶数权重（扇子兵/骑士/投石车/弩车），
	## 奇数预算（如第 4 轮 19）就永远凑不出来 ⇒ 总权重恒等被破坏。3 是新的奇数权重，和 2 一起
	## 可以拼出任何 ≥2 的整数，配平的奇偶能力因此不再只依赖权重 1 的三个兵种。
	## 重量仍是 1（最轻）：长矛兵的击退数值 2 照样推得动它，与骑士（重量 2，推不动）的定位差保留。
	"berserker": {
		"id": "berserker", "name": "狂战士", "name_en": "Berserker",
		"hp": 400.0, "damage": 32.0, "attack_speed": 1.40, "range": 1.6,
		"weight": 3, "mass": 1, "move_speed": 3.8,
		"is_ranged": false, "has_shield": false,
		## 双持斧：`_resolve_attack` 会按这个次数**连续结算**（伤害 × 本值 = 面板 16×2）
		"attacks_per_swing": 2,
		"skill": "rocket_jump",
	},
	## 火焰拳（2026-09-19 新增，用户口径）：**权重 5** 的近战爆发兵种。
	## 平 A 是普通单体近战（走 `_resolve_attack` 的默认分支），输出主要靠技能「炎爆」——
	## 锁定目标落在 5~13 m 时自动发动（**无冷却**）：蓄力 1 s → 极速冲刺（**可穿队友**）→
	## 对被锁定单位只给**击退 4 + 眩晕 1（不造成伤害）**→ 0.5 s 后**以被撞对象为中心** 6 m 爆炸
	##（范围内**所有敌方**吃 3× 攻击伤害 + 眩晕 1）→ **自己再眩晕 1**。
	## ⚠️ 蓄力**不是死承诺**（2026-09-19 用户第二条）：锁定目标离开 5~13 m 或**换目标** ⇒ 蓄力中断
	##（不爆炸、不自晕，这一帧交回常规走位）；起手之后的冲刺 / 待爆 / 爆炸仍照旧走完。
	## 数值（2026-09-19 用户第三次给定）：血量 **300**、伤害 **70**、攻速 0.8、射程 1.8、移速 3.1、重量 2。
	## ⇒ 平 A 的 DPS 56，爆炸 = 3 × 70 = **210**；技能里那些数在下面的 `UNIT_FLAME_*` 常量组。
	"flamefist": {
		"id": "flamefist", "name": "火焰拳", "name_en": "Flamefist",
		"hp": 300.0, "damage": 70.0, "attack_speed": 0.8, "range": 1.8,
		## ⚠️ 2026-09-19 用户："火焰拳权重变为 6"：**5 → 6**（仍是偶数档；第 1 轮预算 10 ⇒ 1 个火焰拳 + 4 个 1 权重）。
		## ⚠️ **2026-09-26 用户（"火拳权重6变成5"）：6 → 5**（回落到"1 个火焰拳 + 5 个 1 权重"那一档）。
		## 连带事实：**档位 `6` 从此没有任何兵种**（与 `8` 同例），而档位 `5` 现在有**四个**兵种
		##（轻骑兵（矛）/ 影魔 / 火焰拳 / 火枪兵）—— I-27 照旧"只改例子、规则未动"。
		## ⚠️ 这条改动同时是**肉鸽模式**的前置：那边"队"的尺寸表只按 **1 / 2 / 3 / 5 / 10 / 25** 六档定义，
		## 改完之后**现行权重档位正好就是这六档**（见 `ROGUELIKE_SQUAD_*` 那一族）。
		"weight": 5, "mass": 2, "move_speed": 3.1,
		"is_ranged": false, "has_shield": false,
		"skill": "flame_burst",
	},
	## 沙虫（2026-09-19 新增，**第一个 boss 单位**）：潜地 + 前方扇形群伤。
	## 权重 **25** 是新档位 ⇒ 第 4 轮（预算 25）才刚好够一个；又因为 I-28 要求"两队兵种不重叠"，
	## 一场比赛里**最多只会出现一只**（用户口径："免疫眩晕且最多在一队中出现一个"）。
	## 数值（2026-09-19 用户确认）：血量 1200 / 伤害 90 / 攻速 0.5（2 s 一次）/ 射程 = 扇形半径 5 m /
	## 移速 2.0 / 重量 10；扇形 ±60°（`UNIT_SANDWORM_ARC_DEG`），命中范围内**所有敌方**。
	## 数值（2026-09-19 用户第三条调整）：血量 **1500** / 伤害 **150** / 攻速 0.5（2 s 一次）/ 射程 = 扇形半径 5 m /
	## 移速 **3.0** / 重量 10；扇形 ±60°（`UNIT_SANDWORM_ARC_DEG`），命中范围内**所有敌方**。
	## 沿革：1200/90/2.0 →（用户："血量变为 1500，伤害变为 150，速度变为 3"）1500/150/3.0。
	"sandworm": {
		"id": "sandworm", "name": "沙虫", "name_en": "Sandworm",
		## ⚠️ 2026-09-25 用户："沙虫血量变为 2000"：**1800 → 2000**（当时伤害 150 / 攻速 0.5 / 移速 3.0 / 权重 25 都没动）。
		## 沿革：1200 / 90 / 2.0 → 1500 / 150 / 3.0 → 1800 → **2000**（只动血量）。
		## ⚠️ 2026-10-04 用户："提升沙虫的攻速，变成 0.75"：**0.5 → 0.75**（2 s 一次 → 1.33 s 一次）。
		"hp": 2000.0, "damage": 150.0, "attack_speed": 0.75, "range": UNIT_SANDWORM_FAN_RADIUS,
		## ⚠️ 2026-09-19 用户："沙虫重量变为无穷大（9999）"：`mass` 10 → **9999**。
		## 实际效果 = **击退免疫**：位移 = 击退数值 ÷ 重量（`04_physics.md#5`）⇒ 9999 之下任何来路的击退
		## 位移都 ≈ 0；且 `is_knockback_immobile()`（重量 < 本次击退数值）恒为假 ⇒ 它永远在"可移动档"，
		## 被推时照常自主走位（推不动，但也不会被推得动不了）。
		## ⚠️ 只动**重量**；**权重 25 是另一件事**（I-26：权重 = 配平占位成本，重量 = 击退用物理质量）。
		"weight": 25, "mass": 9999, "move_speed": 3.0,
		"is_ranged": false, "has_shield": false,
		## boss 标记：免疫眩晕（`apply_stun()` 直接返回）+ 每队最多一个（配平约束）
		"boss": true,
		"skill": "burrow",
		## 扇形群伤：与扇子兵共用 `_resolve_attack()` 里的 `attack_arc_deg` 通路
		"attack_arc_deg": UNIT_SANDWORM_ARC_DEG,
	},
	## 火枪兵（2026-09-25 新增，用户口径）："权重5，血量150，伤害200，攻速0.2/s，移速3m/s，射程38m，
	## 重量1。可穿透一个敌方单位（包括盾牌），能预判。子弹为小型投射物，速度是弩车子弹的两倍，
	## 附加击退3。"
	##   · 权重 **5** ⇒ 与轻骑兵（矛）**同档**（I-27 是"只补例子、规则未动"，同档不冲突）；
	##   · 射程 **38 m** 是**全场第二远**（仅次于弩车 44 m，超过长弓手 28 / 投石车 35）；
	##   · 攻速 **0.2/s** ⇒ 5 s 一发、单发 **200** ⇒ 面板 DPS **40**（与长弓手同档，但一发顶两发）；
	##   · 重量 **1** ⇒ 长矛兵的击退（数值 2）推得动它；
	##   · **穿透**：`"pierce": 1` ⇒ 最多命中 **2 个**敌人（打到第一个不停、继续飞，见 `arrow.gd`）；
	##     两档伤害**不分档**（都吃满 200）—— 这是我的口径，用户只说了"可穿透一个敌方单位"；
	##   · **无视盾牌**：`"ignores_shield": true`（与弩箭同一条，用户："包括盾牌"）；
	##   · **预判**：走 `arena.gd#_aim_straight()`（直线弹的预判），并吃既有的"预判总闸门"
	##     （目标正在被击退 / 冲撞中就不预判，见 `04_physics.md#5.3`）；
	##   · 子弹速度 = **`UNIT_BOLT_SPEED × 2` = 360 m/s**（用户："速度是弩车子弹的两倍"）——
	##     60 Hz 下每帧位移 **6 m** ⇒ 必须走既有的**线段查询**（`arrow.gd#_resolve_segment()`，
	##     箭矢从来都是线段而不是点），否则会直接穿过目标。
	"musket": {
		"id": "musket", "name": "火枪兵", "name_en": "Musketeer",
		"hp": 150.0, "damage": 200.0, "attack_speed": 0.22, "range": 38.0,
		## ⚠️ **2026-09-25 用户："火枪手权重：4"**：**5 → 4**（`4` 这个档位在轻骑兵改成 5 之后空置过一阵，
		## 现在由火枪兵占用 —— I-27 照旧"只改例子、规则未动"；连带事实：它与轻骑兵（矛）**不再同档**）。
		## ⚠️ **2026-09-26 用户（"火枪手权重变成5，伤害变回200，攻速从0.2变0.22"）**：
		## **权重 4 → 5**（回到与轻骑兵（矛）/ 影魔 / 火焰拳同档；**档位 `4` 从此又空置了**，与 `6` / `8` 同例）、
		## **攻速 0.2 → 0.22**（面板间隔 5.0 → **≈4.545 s**，理论 DPS 40 → **44**）。
		## ⚠️ **"伤害变回200" 无需改动**：它本来就是 **200**（本轮只核对了这一项，数值一字未动）。
		## ⚠️ 与火焰拳那条同理：改完之后**现行权重档位正好只剩 1 / 2 / 3 / 5 / 10 / 25**，
		## 也就是**肉鸽模式"队"尺寸表的六档**。
		"weight": 5, "mass": 1, "move_speed": 3.0,
		"is_ranged": true, "has_shield": false,
		"projectile": "musket_bullet", "ignores_shield": true, "pierce": 1,
		"knockback": 3.0,
		## 出手动作：**向前一顶**（枪托后坐的表现），与轻骑兵 / 长矛兵共用 `thrust` 通道 ——
		## 它只推位置、不改 `rotation`，正合"枪口始终朝前"。
		"thrust": true,
	},
	## 武士大师（2026-09-25 新增，用户口径）：**第二个 boss 单位**（权重 25，与沙虫同档）。
	## 数值：血量 800 / 伤害 250 / 攻速 1.5（每 0.667 s 一刀）/ 射程 2.2 m / 移速 3 / 重量 2。
	## ⚠️ 前摇：用户说"攻击前摇极短（敌方进入攻击范围后 **0.1 s** 就能击中敌方）"——
	## 本项目的前摇是**占攻击间隔的比例**（`windup_ratio`，默认 0.30），所以这里换算成
	## **0.1 ÷ 0.667 = 0.15**（第二个覆盖默认值的兵种，第一个是长矛兵）。
	## 四个技能（全部走 `"skill": "master"` 一条技能循环，数值在 `UNIT_MASTER_*` 常量组）：
	##   ① **高级偏折**：格挡**小型投射物**并**反弹**（同速反向、归我方），额度 15 次，挡满 5 次进 4 s 冷却；
	##   ② **冲刺**：像骑士冲撞但**不造成伤害与击退**，只冲到锁定目标进射程，冷却 1 s；
	##   ③ **后撤步**：敌方近战要出手（或冲锋中的轻骑兵靠近）⇒ 立刻后撤到自身后方 7 m、张角 60° 的弧上，
	##      冷却 1 s；
	##   ④ **拔刀斩**：冷却 12 s，后撤 10 m → 蓄力 1 s → 向锁定方向**穿过所有单位**冲 35 m，
	##      沿途（宽 2 m）的敌人**定身 1 s（含 boss）**，自己落地后再定身 1.5 s；
	##      被定身者在**定身结束时**吃 `300 + 其血上限 × 0.25`；技能全程无敌（自己定身结束才解除）。
	## boss 的既有两条特权它自动继承：**免疫眩晕**（`is_boss()`）+ 每队最多一个。
	## ⚠️ **它免疫眩晕、但吃定身**（用户 2026-09-25 裁决：定身无视 boss / 载具的免疫）——
	## 所以两只武士大师 / 沙虫互放定身是**生效**的（`apply_root()` 不走 `is_stun_immune()`）。
	"master": {
		"id": "master", "name": "武士大师", "name_en": "Swordmaster",
		## ⚠️ **2026-09-25 用户："武士大师血量：变为1000"**：**800 → 1000**（其余六项一字未动）。
		"hp": 1000.0, "damage": 250.0, "attack_speed": 1.5, "range": 2.2,
		"weight": 25, "mass": 2, "move_speed": 3.0,
		"is_ranged": false, "has_shield": false,
		"boss": true,
		## ⚠️ **2026-09-25 第三轮（用户："武士大师攻击前摇变为0.05s"）**：用户这次给的是**绝对时长**，
		## 所以按"前摇 = 间隔 × 比例"的口径换算：**0.05 ÷ 0.667 = 0.075**（实测 `windup_ms = 50`）。
		## ⚠️ 沿革：上一轮按"缩短到能在后撤前击中沙虫"取的 0.03（20 ms）**已被本条取代** ——
		## 用户改成给定值；⚠️ 但上一轮实测的那条结论**仍然有效**（前摇大小不是"打不到沙虫"的原因，
		## 真因在后撤步的触发规则，见 `99_decisions.md` 同日条目与那三条待裁决修法）。
		"windup_ratio": 0.075,
		"skill": "master",
	},
	## 心灵腐化师（2026-09-25 第二轮新增，用户口径）：血量 400 / 伤害 10 / 攻速 8（每 0.125 s 一跳）/
	## 射程 20 m / 权重 **10** / 重量 1 / 移速 **2.5**（比所有人都慢 —— 它是"站桩照射"型）。
	## ⚠️ **它的"伤害"不掉血**：`"corrupt": true` ⇒ `Unit3D.apply_hit()` 把它转成**心灵腐化值**，
	## 于是 10 × 8/s = **80 腐化值/s** —— 这就是那道激光的读数（对 400 血的单位约 5 s 转化）。
	## ⚠️ **`is_ranged` 刻意是 false**：本作的 `is_ranged` 语义是"**走 `arena.spawn_arrow()` 打投射物**"，
	## 而激光**没有弹体** ⇒ 它走"单体直接结算"那一支（`_resolve_attack()` 里 `arc_deg == 0` 的路径），
	## 射程仍由 `range` 决定（近战那一档要乘接触宽容 `UNIT_CONTACT_RATIO` ⇒ 实际够得着 20 × 1.18 = 23.6 m）。
	## ⚠️ 权重 **10** ⇒ 与投石车 / 弩车同档（I-27 照旧"只补例子、规则未动"，**没有开新档位**）。
	## ⚠️ **2026-09-26 用户（"心灵腐化师攻击力：40变成35"）：按 ×0.875 的比例削腐化速度 ⇒
	## 攻速 8 → 7**（= 用户选定的实现口径"每跳仍 10、动攻速"）⇒ **腐化值/s 80 → 70**、
	## 面板间隔 0.125 → **≈0.143 s**。⚠️ **伤害 10 没动**（用户口径里的"40 → 35"在代码里没有对应数，
	## 那是"腐化速度"的读数；按 ×0.875 落到 80/s 上就是 70/s，见 `99_decisions.md` 待补条目）。
	## ⚠️ 连带核对：`UNIT_CORRUPT_HOLD_MS`（200 ms）仍大于新间隔（143 ms）⇒"连续照射期间不会被
	## 自己的间隙清掉"这条**照旧成立**（那条注释里写的"必须大于一个照射间隔"就是这道闸门）。
	"corruptor": {
		"id": "corruptor", "name": "心灵腐化师", "name_en": "Mind Corruptor",
		## ⚠️ **2026-09-27 第十轮（用户："心灵孵化师：攻速7变成8"）**：`attack_speed` **7.0 → 8.0**
		##（沿革：新增时 8 → 2026-09-26 按"攻击力 40→35"改 7 → **本轮改回 8**）⇒ 腐蚀速度
		## 每跳 10 × 8 = **80/s**（2026-09-26 那次削到 70/s 的口径**作废**）。⚠️ 连带核对：
		## `UNIT_CORRUPT_HOLD_MS`（200 ms）仍**大于**新间隔 125 ms ⇒"连续照射期间不会被自己的间隙清掉"照旧成立。
		"hp": 400.0, "damage": 10.0, "attack_speed": 8.0, "range": 20.0,
		"weight": 10, "mass": 1, "move_speed": 2.5,
		"is_ranged": false, "has_shield": false,
		"corrupt": true,
		## 前摇取极小值：激光是**持续照射**，不该有看得见的挥击前摇（那段 0.5 s 蓄力由
		## `UNIT_CORRUPT_CHARGE_MS` 单独表达，见 `Unit3D._tick_attack()`）。
		"windup_ratio": 0.02,
		## 出手动作走 `thrust`（举杖向前一顶）：模型没有 `Weapon` 节点时该分支自动不生效，不会报错。
		"thrust": true,
		## 它属于"锁定后持续照射"那一族（`is_sustained_beam()`）：蓄力 / 断锁口径与湮灭之瞳共用一套。
		"sustained_beam": true,
	},
	## 湮灭之瞳（2026-09-27 第十轮新增，用户口径）：
	## 血量 **1800** / 基础伤害 **30** / 攻速 **2.5** / 射程 **22 m** / 权重 **25** / 重量 **9999** / 移速 **2.5**。
	## 攻击方式与心灵腐化师**同一套激光**（锁定后 0.5 s 蓄力 → 持续照射；目标死亡 / 出射程 ⇒ 丢锁），
	## 但它**造成伤害**（腐化师是叠腐化值）—— 而伤害会**越照越高**：
	## 被动技能「能量汇集」（`UNIT_DOOM_HITS_PER_STAGE` = 4）：对**同一个**目标每命中 4 下升一档 ——
	##   0~3 下 = 基础 **30**（细激光）→ 4~7 下 = **90**（变粗）→ 8~11 下 = **300** → **12 下起 = 1000**（最粗）。
	## ⚠️ 换目标 / 丢锁 ⇒ 档位**清零重来**（`Unit3D._focus_hits`）。
	## ⚠️ 它是 **boss**（`boss: true`）：免疫眩晕 + 配平里每队最多一个（与沙虫 / 武士大师同待遇）。
	## ⚠️ 权重 **25** ⇒ 肉鸽"队"表里正好落在"1 人 / 4 × 4 格"那一档（用户："权重是25，进沙盒肉鸽竞猜"）。
	## ⚠️ **2026-09-27 第十一轮（用户："1.湮灭之瞳射程变为25m 2.湮灭之瞳攻速变为3"）**：
	## 射程 **22.0 → 25.0 m**（`attack_reach()` = 25 × 1.18 = **29.5 m**）、攻速 **2.5 → 3.0**
	##（面板间隔 0.4 s → **0.333 s**）。⚠️ 连带：`windup_ratio` 0.02 ⇒ 前摇 8 ms → **6.7 ms**；
	## 「能量汇集」的到档时间也随攻速提前 ⇒ 4 下 = **1.33 s**（原 1.6 s）、8 下 = **2.67 s**（原 3.2 s）。
	"doom_eye": {
		"id": "doom_eye", "name": "湮灭之瞳", "name_en": "Doom Eye",
		"hp": 1800.0, "damage": 30.0, "attack_speed": 3.0, "range": 25.0,
		"weight": 25, "mass": 9999, "move_speed": 2.5,
		"is_ranged": false, "has_shield": false,
		"boss": true,
		"sustained_beam": true,
		## 与腐化师同理：持续照射不该有看得见的挥击前摇；出手只推位置（`_weapon` = 瞳孔）
		"windup_ratio": 0.02,
		"thrust": true,
	},
	## 玉面手雷王（2026-09-25 第二轮新增，用户口径）：血量 **80**（2026-10-02 由 100 改）/ 伤害 10 / 攻速 1 / 射程 1.5 m /
	## 权重 **1** / 重量 **1** / 移速 **5**。
	## ⚠️ 用户原话在"重量"处断了（"权重1，重量"），**重量 1 是用户当场补定的**（2026-09-25 问答）。
	## ⚠️ 它是**自杀式杂兵**：平 A 只有 10，价值全在"死亡时自爆 150"（`UNIT_GRENADE_BLAST_*`）。
	## ⚠️ 移速 5 ⇒ 比全部人形都快（剑盾 2.9 / 长矛 3.1 / 短弓 3.4），仅次轻骑兵 7.0 —— 它得冲得上去才炸得到人。
	"grenadier": {
		"id": "grenadier", "name": "玉面手雷王", "name_en": "Grenade King",
		"hp": 80.0, "damage": 10.0, "attack_speed": 1.0, "range": 1.5,
		"weight": 1, "mass": 1, "move_speed": 5.0,
		"is_ranged": false, "has_shield": false,
		"self_destruct": true,
	},
	## 影魔（2026-09-25 第三轮新增，用户口径）：权重 **5** / 血量 300 / 伤害 80 / 攻速 0.8 /
	## 射程 **1.8 m**（⚠️ 用户没给射程 —— I-26 七项里缺的那一项，2026-09-25 当场问答定为 1.8 m）/
	## 移速 4 / 重量 2。
	## 两个技能（`"skill": "shadow"`）：
	##   ① **影袭**（冷却 4 s）：受到**任意伤害**时免疫那一下、化成影子扑到"伤害来源那一类单位"身边，
	##      变回原身并**眩晕**它 2 s；**被眩晕（或定身）则无法发动**；无来源的伤害不发动。
	##   ② **时候已到**（被动）：**距上次出手每满 1 秒伤害 +80、封顶 320**，出手即清零；
	##      **从影子变回原身时直接封顶**。
	## ⚠️ 权重 **5** ⇒ 与轻骑兵（矛）**同档**（I-27"只补例子、规则未动"，**没有开新档位**）。
	"shadow": {
		"id": "shadow", "name": "影魔", "name_en": "Shadow Fiend",
		"hp": 300.0, "damage": 80.0, "attack_speed": 0.8, "range": 1.8,
		"weight": 5, "mass": 2, "move_speed": 4.0,
		"is_ranged": false, "has_shield": false,
		"skill": "shadow",
	},
	## 召唤石柱（2026-09-25 第七轮新增，**仅沙盒模式**）：用户口径与三条自定口径见 `UNIT_SUMMON_*` 段。
	## 七项属性：血量 **2000** / 伤害 **200** / 攻速 **0.2**（5 s 一发）/ 射程 **10 m** /
	## 权重 **999** / 重量 **9999**（击退免疫，自定）/ 移速 **0**（"不移动"）。
	## ⚠️ `is_ranged` 是 **false**：本作的 `is_ranged` 语义是"走 `arena.spawn_arrow()` 打投射物"，
	## 而石柱的出手是**无弹体的直击**（与心灵腐化师的激光同一支：`_resolve_attack()` 的单体直接结算），
	## 射程仍由 `range` 决定 —— 近战那一档要乘接触宽容 `UNIT_CONTACT_RATIO`（10 × 1.18 = 11.8 m）。
	## ⚠️ `"beam": true` 只加**观感**：没有它，"10 m 外莫名掉血"读不出来（腐化师的激光同理），
	## 见 `unit3d.gd#_update_laser_beam()`；它**不产生任何判定**（伤害那一刀仍走 `_resolve_attack()`）。
	## ⚠️ `"thrust": true`：出手动作走"沿 −Z 前顶"那一支（动位置、不动旋转）—— 石柱顶上那颗晶体的
	## 前顶就是它的"出手"，比整根柱子旋转合理得多。
	"pillar": {
		"id": "pillar", "name": "召唤石柱", "name_en": "Summon Pillar",
		"hp": 2000.0, "damage": 200.0, "attack_speed": 0.2, "range": 10.0,
		"weight": 999, "mass": 9999, "move_speed": 0.0,
		"is_ranged": false, "has_shield": false,
		## 沙盒专属（用户："仅限沙盒模式"）：竞猜模式的配平池**永不生成它**，见 `is_sandbox_only()`。
		"sandbox_only": true,
		## **锚定**（2026-09-26 用户："有些兵种不知道为什么能够推动 9999 重量的石柱（特别是位移类技能）"）：
		## 水平位置每物理帧复位到出生点 ⇒ **任何外力都推不动它**（真因与实现见 `Unit3D._hold_anchor()`：
		## 不是击退 —— 击退早被重量 9999 除没了 —— 而是**引擎的穿透修正**，技能位移是直接写
		## `global_position` 的，冲进判定盒里之后石柱自己那一帧的 `move_and_slide()` 会把它推出去）。
		"anchored": true,
		"skill": "summon",
		"beam": true,
		"thrust": true,
	},
	## 指挥所（2026-09-26 第三块新增，**肉鸽专属**的建筑）：每方半场两个，点它可以买增益。
	## 用户口径（原文）："在场地上左半部分的中间和右半部分的中间分别放上两个指挥所（占据3*3）（敌我两边都有），
	## 血量均为500，重量9999，无攻击能力，不移动"。
	## 七项属性：血量 **500**（用户）/ 伤害 **0** / 攻速 **0** / 射程 **0** / 权重 **999**（自定，见下）/
	## 重量 **9999**（用户："重量9999"）/ 移速 **0**（用户："不移动"）。
	## ⚠️ **权重 999 只为记号**：它与石柱同理 —— **永不进任何池子**（`"roguelike_only": true`，见
	## `is_roguelike_only()`）⇒ 不进竞猜配平池（否则当场破坏 I-20 / I-27）、不进沙盒兵种栏、
	## 不进石柱的召唤名单、也不进肉鸽商店。
	## ⚠️ `"no_attack": true`：**连平 A 都没有** ⇒ `_think()` 直接跳过索敌与出手（判据 `is_no_attack()`）；
	## 这也是它 `damage` / `attack_speed` 敢写 0 的原因 —— `attack_interval()` 是 `1.0 / attack_speed`，
	## 0 会除出 INF，而"无攻击"这条闸门保证那条路根本不会被走到。
	## ⚠️ `"anchored": true`：与石柱同例（位移类技能是**直接写 `global_position`** 的，不锚定就会被引擎的
	## 穿透修正顶走）—— 用户 2026-09-26 裁决："6×6×3 m + weight 999 + 锚定"。
	"commandpost": {
		"id": "commandpost", "name": "指挥所", "name_en": "Command Post",
		"hp": 500.0, "damage": 0.0, "attack_speed": 0.0, "range": 0.0,
		"weight": 999, "mass": 9999, "move_speed": 0.0,
		"is_ranged": false, "has_shield": false,
		"roguelike_only": true,
		"anchored": true,
		"no_attack": true,
		"skill": "",
	},
}
## ⚠️ 2026-09-25：`archer` → **`shortbow`**（弓兵改名短弓手，ID 跟着改），并新增长弓手 `longbow`
## 与轻骑兵（矛）`lightcav`。三种远程/高速单位的相对位置：短弓手 16 m 直线箭、长弓手 30 m 抛物线箭、
## 轻骑兵 7 m 起冲锋（`7.0 m/s` 走位）。
const TYPE_ORDER := ["sword", "spear", "shortbow", "longbow", "fan", "knight", "catapult", "ballista",
		"berserker", "flamefist", "lightcav", "sandworm", "musket", "master",
		"corruptor", "grenadier", "shadow",
		## 2026-09-27 第十轮：**湮灭之瞳**（boss，三模式通用）。⚠️ 排在这里而不是最后：
		## 它**参与竞猜配平**（权重 25，与沙虫 / 大师同档）⇒ 抽签遍历序要把它算进来；
		## 而沙盒兵种栏 / 肉鸽商店都按**权重**排序 ⇒ 显示位置自然落在 25 那一档。
		"doom_eye",
		## 2026-09-25 第七轮：**召唤石柱**（`SUMMONER_TYPE`，仅沙盒模式）。
		## ⚠️ 它排在**最后**：`TYPE_ORDER` 的另一个身份是"配平抽签的遍历序"，而它永不参与配平；
		## 沙盒兵种栏按**权重**排序（`sandbox_hud.gd#_types_by_weight()`）⇒ 它自然排在 999 那一档的最后。
		"pillar",
		## 2026-09-26 第三块：**指挥所**（肉鸽专属建筑，每方半场两个）。与石柱同理排在最后、
		## **永不参与配平**；它靠 `"roguelike_only"` 被各处池子排除（见 `is_roguelike_only()`）。
		"commandpost"]

# ---------------------------------------------------------------- 每队总权重（按轮递增）
const TEAM_WEIGHT_START := 10          ## 第 1 轮每队总权重
## 每轮递增。2026-09-19 用户第四条："初始权重为 10，每回合权重增加 5"——由 **3 改为 5**。
## ⇒ 十轮预算 = 10 / 15 / 20 / 25 / 30 / 35 / 40 / 45 / 50 / 55。
## ⚠️ 这条数值写在不变量 **I-20** 的正文里（`_index.md#2`），改它必须同步那一条 + 记 `99_decisions.md`。
const TEAM_WEIGHT_STEP := 5
## 上限，防止轮次越界后爆炸。⚠️ 步长改 5 之后第 10 轮只有 55 ⇒ 上限已经够不着，保留作兜底。
const TEAM_WEIGHT_MAX := 60
const PAIR_SAMPLE_COUNT := 240         ## 保留给 `debug_balance_stats` 的采样口径（配平已改为全随机，不再用它挑对手）
## B 队为满足"权重相同 + 种数相同 + 兵种不重叠"的重抽上限（2026-09-19）
const PAIR_RETRY_LIMIT := 200
## 双方总权重的允许偏差（2026-09-19 用户要求"允许双方权重有 1 的偏差"⇒ 不变量 I-20 由"恒等"放宽）。
## 存在的理由：权重只有 1 / 2 / 3 / 10，若某队 3 个兵种全落在偶数权重（扇子兵 2、骑士 2、
## 投石车 10、弩车 10），奇数预算（第 4 轮 19、第 10 轮 37）就永远凑不出来——实测旧口径下
## 160 次配平有 18.75% 差 1（狂战士改权重 3 后仍有 13.1%）。放宽 1 点即把这类"奇偶凑不出来"合法化。
const PAIR_WEIGHT_TOLERANCE := 1
## 每队**去重后**最多出现的兵种数（2026-09-19 用户新规则）；双方种数必须相同，见 `make_match()`。
const MAX_KINDS_PER_TEAM := 3
## **前几轮各队"正好"几种兵**（2026-09-25 第七轮用户口径："第一二轮双方只有各一个兵种，第三四轮双方只有各两个兵种"）。
## 下标 = 轮次 − 1 ⇒ 第 1 / 2 轮 **1 种**、第 3 / 4 轮 **2 种**；**第 5 轮起回到既有口径**（`MAX_KINDS_PER_TEAM`，
## 即"去重后 ≤ 3 种"，一个字都没改）。
## ⚠️ 它**收窄**而不违反不变量 I-28（那条写的是"≤ 3 种、双方种数相等"）：1 ≤ 3、2 ≤ 3 都成立，
##    所以 I-28 的正文不需要改，这里只是"某几轮抽得更窄"。
## ⚠️ **连带事实（必须知道，不是 bug）**：权重档位里 `4`（火枪兵）与 `6`（火焰拳）在**第 1 轮**、
##    以及 `6` / `10` 在**第 2 轮**都**填不满**那一轮预算（容差只有 ±1，见 `PAIR_WEIGHT_TOLERANCE`）⇒
##    这几轮的重抽循环会把它们自然排除（实测：第 1 轮 15 个可抽兵种里 13 个能配上、第 2 轮 10 个）——
##    **配平规则一个字没动**，只是"单一兵种 + 该权重"凑不出预算的那些组合会被重抽掉。
## ⚠️ 另一条连带事实：**第 4 轮（预算 25）要求"正好 2 种"** ⇒ boss（权重 25）**不可能出现**在那两轮里
##    （它一个人就占满整队预算，凑不出第二种兵）⇒ boss 自本轮起**只可能在第 5 轮及以后**登场
##    （最小阵容 = 25 + 权重 1 的一个兵 = 26，仍在 ±1 内）。"每队最多一个 boss"那条**没有动**。
const EXACT_KINDS_BY_ROUND := [1, 1, 2, 2]

## 该队出生在半场的哪一侧（+1 = +X = 东，−1 = −X = 西），不变量 I-35 的**唯一出处**：
## 出生区染色、看台队伍色前缘、队旗、出生朝向全部由它推导，改这一处就能整队换边。
const TEAM_META := [
	{"name": "赤羽卫", "short": "A", "color": Color(0.85, 0.24, 0.22), "spawn_sign": -1.0},
	{"name": "青锋卫", "short": "B", "color": Color(0.20, 0.52, 0.90), "spawn_sign": 1.0},
]

# ---------------------------------------------------------------- 属性读取
func profile(type_id: String) -> Dictionary:
	return PROFILES[type_id]

func profile_name(type_id: String) -> String:
	return PROFILES[type_id]["name"] if PROFILES.has(type_id) else type_id

## 是不是 **boss 单位**（2026-09-19 新增，第一个是沙虫）。boss 的两条特权：
##   ① **免疫眩晕**（`Unit3D.apply_stun()` 直接返回，任何来源的眩晕都吃不上）；
##   ② **每队最多一个**（`_random_composition()` 里把关）。
## ⚠️ 2026-09-25 起"免疫眩晕"**不再是 boss 独有**（载具也免疫）⇒ 判那个问题请用 `is_stun_immune()`。
func is_boss(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("boss", false))

## 是不是**免疫眩晕**的单位（2026-09-25 新增，用户："投石车和弩车不会被眩晕"）。
## 判据是**两个来源的并集**，两者刻意分开写：
##   · ① **boss**（沙虫）—— `PROFILES[*]["boss"]`，2026-09-19 的既有特权；
##   · ② **载具**（投石车 / 弩车）—— `PROFILES[*]["stun_immune"]`，本条新增。
## ⚠️ **不要合并成一个字段**：`boss` 还背着"每队最多一个"的配平含义（`_random_composition()` 在用），
##    而载具没有那条限制；合并会让"给载具加免疫"顺手把配平也改了。
## ⚠️ 物理上说得通：两台载具是**无人机械**，而眩晕在表现上是"模型原地摇晃"——
##    给一台投石车加摇晃既没有受力主体、也读不出来。
func is_stun_immune(type_id: String) -> bool:
	if is_boss(type_id):
		return true
	return bool(PROFILES.get(type_id, {}).get("stun_immune", false))

## 是不是**只在沙盒模式里存在**的兵种（2026-09-25 第七轮，目前只有召唤石柱）。
## 判据是 PROFILE 的 `"sandbox_only"` 标记 —— 与 `is_boss()` / `is_corruptor()` 同一种做法：
## "我是什么"只有一处出处，不在调用点上猜兵种名。
## ⚠️ 它管的是**配平**：竞猜模式的抽签（`_random_composition()`）会跳过这些兵种，
## 因为它们的权重（石柱 999）一进竞猜池就会破坏不变量 I-20。
func is_sandbox_only(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("sandbox_only", false))

## 是不是"**锁定后持续照射**"的激光兵种（2026-09-27 第十轮抽出）。
## 这一族现在的口径：0.5 s 蓄力（`UNIT_CORRUPT_CHARGE_MS`）→ 持续照射；目标死亡 / 出射程 / 变成友方 ⇒ 丢锁；
## **换锁定对象要重新蓄力**。成员：心灵腐化师（叠腐化值）与湮灭之瞳（造成伤害、且伤害逐档升高）。
## ⚠️ 与 `"beam": true`（召唤石柱那种"出手那一刻的可见弹道"，见 `Unit3D._beam_active()`）**不是一回事**：
##    那一族没有蓄力、也没有持续照射。两条判据并存，各自服务一种激光。
## ⚠️ 与 `is_boss()` / `is_sandbox_only()` 同一种做法："我是什么"只有**本文件的 PROFILE**一处出处，
## 不在调用点上猜兵种名。⚠️ 注意：`Unit3D` 上那个同名方法（`is_corruptor()`）是**另一个东西**
##（它是单位实例上的查询），本函数必须直接读 PROFILE 的 `"corrupt"` 标记。
func is_sustained_beam(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("corrupt", false)) \
			or bool(PROFILES.get(type_id, {}).get("sustained_beam", false))

## 湮灭之瞳的「能量汇集」档位（0 / 1 / 2 / 3）→ 该档的伤害。`hits` = 对**同一个目标**的连续命中数。
## ⚠️ 档位口径见 `UNIT_DOOM_HITS_PER_STAGE` 的注（第 5 下起 90、第 9 下起 300、第 13 下起 1000）。
func doom_stage(hits: int) -> int:
	return clampi(hits / UNIT_DOOM_HITS_PER_STAGE, 0, UNIT_DOOM_STAGE_DAMAGE.size() - 1)

## 某一档的伤害（`GameConfig.hit_damage()` 是第 0 档；这里取的是**乘过 HIT_ATK_MULT 的口径**）
func doom_damage(stage: int) -> float:
	var s := clampi(stage, 0, UNIT_DOOM_STAGE_DAMAGE.size() - 1)
	return float(UNIT_DOOM_STAGE_DAMAGE[s])

## 某一档的光束半径（表现，见 `UNIT_DOOM_BEAM_RADIUS`）
func doom_beam_radius(stage: int) -> float:
	var s := clampi(stage, 0, UNIT_DOOM_BEAM_RADIUS.size() - 1)
	return float(UNIT_DOOM_BEAM_RADIUS[s])

## 是不是**只在肉鸽模式里存在**的东西（2026-09-26 第三块，目前只有指挥所）。
## 与 `is_sandbox_only()` 同一个套路、同一条理由：**权重 999 的建筑一旦混进任何"可抽/可买/可招"的池子，
## 就会当场破坏竞猜的 I-20 / I-27**（或让沙盒的兵种栏多出一张不该有的卡）⇒ 靠这一个标记在四处排除：
##   ① 竞猜配平池（`_random_composition()`）、② 沙盒兵种栏（`sandbox_hud.gd#_types_by_weight()`）、
##   ③ 石柱的召唤名单（`summon_pool()`）、④ 肉鸽商店（`roguelike_buyable_types()`）。
## ⚠️ **新增这类"不属于任何池子"的实体时，四处都要看一遍** —— 名单不写死，全靠这个判据。
func is_roguelike_only(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("roguelike_only", false))

## 有没有**攻击能力**（2026-09-26 第三块新增，目前只有指挥所）。
## 判据落在 `PROFILE["no_attack"]`：`Unit3D._think()` 见到它就**直接返回** —— 既不索敌、也不出手、也不走位。
## ⚠️ 与"射程 0 / 伤害 0"是两件事：那两个数只是"打不到"，而这个标记是"根本不尝试打"（省掉整条 AI 分支）。
func is_no_attack(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("no_attack", false))

## 是不是**锚定**单位（2026-09-26 新增，目前只有召唤石柱）：水平位置每物理帧回到出生点，
## 外力（击退 / 动量传递 / **引擎的穿透修正**）一概推不动它。判据落在 `PROFILE["anchored"]`，
## 与 `is_boss()` / `is_corruptor()` 同一种做法（"我是什么"只有一处出处）。
## ⚠️ 它**只管水平位移**：重力与贴地照旧（y 不受影响），伤害 / 眩晕 / 策反也一概照吃。
func is_anchored(type_id: String) -> bool:
	return bool(PROFILES.get(type_id, {}).get("anchored", false))

## **召唤名单**（召唤石柱的技能用）：注册表全体 − 召唤石柱自己。
## 用户口径："随机一个召唤石柱以外的单位（**要保证以后新增单位时会自动加入召唤石柱的召唤名单**）"
## ⇒ 这里**绝不写死名单**，一律从 `TYPE_ORDER` 现推 —— 以后往 `TYPE_ORDER` 里加兵种，
## 它自动进名单，不需要回来改这一处。
func summon_pool() -> Array:
	var out: Array = []
	for type_id in TYPE_ORDER:
		## ⚠️ 排除两样：召唤者自己（`SUMMONER_TYPE`）与**一切"不属于任何池子"的实体**
		##（指挥所靠 `roguelike_only` 在这里被挡下 —— 否则沙盒的石柱会开始召唤指挥所）。
		if String(type_id) != SUMMONER_TYPE and not is_roguelike_only(String(type_id)):
			out.append(String(type_id))
	return out

## 「权重递增模式」下，**战斗开始后 `elapsed_ms`** 时允许召唤的**单兵权重上限**。
## 用户口径："战斗开始前10s只能召唤权重为1的单位，之后每过10s召唤单位权重上限…增加2"
## ⇒ `1 + 2 × ⌊elapsed / 10 s⌋`（0~10 s ⇒ 1、10~20 s ⇒ 3、20~30 s ⇒ 5 …）。
## ⚠️ 注意它限的是**每一个单位的权重**，不是"这一拍召唤出来的总权重"（用户特意点了这一句）。
func summon_weight_cap(elapsed_ms: int) -> int:
	var steps := maxi(elapsed_ms, 0) / UNIT_ESCALATION_START_MS
	return UNIT_ESCALATION_WEIGHT_START + UNIT_ESCALATION_WEIGHT_STEP * steps

## 这一拍**能被召唤的兵种名单**：`summon_pool()`（或"权重上限"过滤后的那一份）。
## `escalation == false`（玩家没开权重递增）⇒ 不过滤，全体都在名单里。
## ⚠️ 过滤后为空是**不可能**的（权重 1 有四个兵种，而第一档要的就是它们），但仍返回空数组让调用方
## 自己判空 —— 不去猜"总有一个"。
func summon_candidates(elapsed_ms: int, escalation: bool) -> Array:
	var cap := summon_weight_cap(elapsed_ms) if escalation else -1
	var out: Array = []
	for type_id in summon_pool():
		if cap > 0 and int(PROFILES[type_id]["weight"]) > cap:
			continue
		out.append(type_id)
	return out

func move_speed(type_id: String) -> float:
	return float(PROFILES[type_id].get("move_speed", 3.0))

## 击退用的物理质量（2026-09-18 新增，不变量 I-26 的第七项「重量」）：
## 被击退的位移 = 击退数值 ÷ 本值。与配平用的 `weight` 是两件事，见 `PROFILES` 顶部的说明。
func mass(type_id: String) -> float:
	return maxf(float(PROFILES[type_id].get("mass", 1.0)), 0.01)

## 攻击前摇占攻击间隔的比例：默认取全局 `UNIT_WINDUP_RATIO`，
## 兵种可以在自己的 PROFILE 里用 `windup_ratio` 覆盖（当前只有长矛兵，理由见其注释）。
func windup_ratio(type_id: String) -> float:
	return float(PROFILES[type_id].get("windup_ratio", UNIT_WINDUP_RATIO))

## 实际最大生命 = 表值 × 全场减半系数
func max_hp(type_id: String) -> float:
	return float(PROFILES[type_id]["hp"]) * HIT_HP_MULT

## 每次命中的实际伤害 = 表值 × 全场攻击力倍率
func hit_damage(type_id: String) -> float:
	return float(PROFILES[type_id]["damage"]) * HIT_ATK_MULT

func max_attack_speed(type_id: String) -> float:
	## 兴奋圈已废止，不再乘圈外攻速。
	return float(PROFILES[type_id]["attack_speed"])

func attack_interval(type_id: String) -> float:
	return 1.0 / float(PROFILES[type_id]["attack_speed"])

func team_color(team: int) -> Color:
	return TEAM_META[clampi(team, 0, TEAM_META.size() - 1)]["color"]

func team_name(team: int) -> String:
	return TEAM_META[clampi(team, 0, TEAM_META.size() - 1)]["name"]

## 出生侧符号：+1 = 出生在 +X（东），−1 = 出生在 −X（西）。见不变量 I-35。
func team_spawn_sign(team: int) -> float:
	return float(TEAM_META[clampi(team, 0, TEAM_META.size() - 1)]["spawn_sign"])

func wager_of(round_index: int) -> int:
	## round_index 从 1 开始
	return int(WAGER_TABLE[clampi(round_index - 1, 0, WAGER_TABLE.size() - 1)])

func all_in_unlocked(round_index: int) -> bool:
	return round_index >= ALL_IN_FROM_ROUND

## 第 N 轮的每队总权重：10 起，每轮 +3（两队始终相同）
func total_weight_for_round(round_index: int) -> int:
	var value := TEAM_WEIGHT_START + TEAM_WEIGHT_STEP * maxi(round_index - 1, 0)
	return mini(value, TEAM_WEIGHT_MAX)

## 肉鸽模式**第 N 回合开始时**的补给收入（`ROGUELIKE_SUPPLY_START` 起、每回合 +`ROGUELIKE_SUPPLY_STEP`）。
## ⚠️ 它**与竞猜模式的 `total_weight_for_round()` 是两条独立的曲线**（那条是"两队总权重预算"）——
## 两者数字巧合（都是"起手 + 每回合递增"）但用途、单位、归属全不同，**不要合并**。
## `round_index` 从 1 起；越界（≤0）按第 1 回合算，免得负数回合算出负收入。
func roguelike_supply_income(round_index: int) -> int:
	return ROGUELIKE_SUPPLY_START + ROGUELIKE_SUPPLY_STEP * maxi(round_index - 1, 0)


## 这一回合开始时，指挥所自己带的等级。1～3 回合是 0 级；4、5 是 1 级；6、7 是 2 级；8、9、10 是 3 级。
func roguelike_post_round_level(round_index: int) -> int:
	if round_index >= 8:
		return 3
	if round_index >= 6:
		return 2
	if round_index >= 4:
		return 1
	return 0

var _aid_rows: Array = []

func roguelike_aid_catalog() -> Array:
	if _aid_rows.is_empty():
		_aid_rows = _build_aid_rows()
	return _aid_rows

func roguelike_aid_def(id: String) -> Dictionary:
	for row in roguelike_aid_catalog():
		if String(row["id"]) == id:
			return row
	return {}

func _aid(id: String, group: String, aid_name: String, blurb: String, cost: int, extra: Dictionary) -> Dictionary:
	var row := {
		"id": id, "group": group, "name": aid_name, "blurb": blurb, "cost": cost,
	}
	row.merge(extra, true)
	return row

func _build_aid_rows() -> Array:
	var rows: Array = []
	rows.append_array(_aid_variants())
	rows.append_array(_aid_experts())
	rows.append_array(_aid_props())
	rows.append_array(_aid_modules())
	return rows

func _aid_variants() -> Array:
	return [
		_aid("sword_bulk", "variant", "批量剑盾兵", "血量 −20%，伤害 −20%，招募价 −5", 0,
			{"type_id": "sword", "gate": "bulk", "hp_mult": 0.8, "damage_mult": 0.8, "recruit_delta": -5}),
		_aid("sword_heavy", "variant", "重装剑盾兵", "血量 +100%，伤害 −50%，移速 −1", 0,
			{"type_id": "sword", "gate": "open", "hp_mult": 2.0, "damage_mult": 0.5, "speed_add": -1.0}),
		_aid("spear_bulk", "variant", "批量长矛兵", "血量 −20%，伤害 −20%，招募价 −5", 0,
			{"type_id": "spear", "gate": "bulk", "hp_mult": 0.8, "damage_mult": 0.8, "recruit_delta": -5}),
		_aid("spear_assault", "variant", "突击长矛兵", "血量 −30%，移速 +2，伤害 +30%", 0,
			{"type_id": "spear", "gate": "open", "hp_mult": 0.7, "speed_add": 2.0, "damage_mult": 1.3}),
		_aid("shortbow_bulk", "variant", "批量短弓手", "血量 −40%，招募价 −5", 0,
			{"type_id": "shortbow", "gate": "bulk", "hp_mult": 0.6, "recruit_delta": -5}),
		_aid("shortbow_improve", "variant", "改进型短弓手", "血量 +50%，伤害 +50%，射程 +4，招募价 +10", 0,
			{"type_id": "shortbow", "gate": "improve", "hp_mult": 1.5, "damage_mult": 1.5, "range_add": 4.0, "recruit_delta": 10}),
		_aid("grenadier_grow", "variant", "成长型玉面", "升级价格 −5", 0,
			{"type_id": "grenadier", "gate": "open", "upgrade_delta": -5}),
		_aid("grenadier_bulk", "variant", "批量玉面", "生命 −50%，招募价 −5", 0,
			{"type_id": "grenadier", "gate": "bulk", "hp_mult": 0.5, "recruit_delta": -5}),
		_aid("longbow_improve", "variant", "改进型长弓手", "血量 +40%，伤害 +40%，射程 +5，招募价 +10", 0,
			{"type_id": "longbow", "gate": "improve", "hp_mult": 1.4, "damage_mult": 1.4, "range_add": 5.0, "recruit_delta": 10}),
		_aid("longbow_heavy", "variant", "重装长弓手", "血量 +200%，射程 −5", 0,
			{"type_id": "longbow", "gate": "open", "hp_mult": 3.0, "range_add": -5.0}),
		_aid("fan_bulk", "variant", "批量扇子兵", "血量 −40%，招募价 −5", 0,
			{"type_id": "fan", "gate": "bulk", "hp_mult": 0.6, "recruit_delta": -5}),
		_aid("fan_support", "variant", "辅助型扇子兵", "不能造成伤害，生命 −20%。每 3 次攻击获得 1 点经验。升级和科技价 −5", 0,
			{"type_id": "fan", "gate": "open", "hp_mult": 0.8, "damage_mult": 0.0, "xp_every": 3, "upgrade_delta": -5, "tech_delta": -5}),
		_aid("knight_bulk", "variant", "批量骑士", "血量 −20%，伤害 −20%，招募价 −5", 0,
			{"type_id": "knight", "gate": "bulk", "hp_mult": 0.8, "damage_mult": 0.8, "recruit_delta": -5}),
		_aid("knight_improve", "variant", "改进型骑士", "伤害 +150%，招募价 +10", 0,
			{"type_id": "knight", "gate": "improve", "damage_mult": 2.5, "recruit_delta": 10}),
		_aid("berserker_assault", "variant", "突击狂战士", "血量 −20%，伤害 +30%", 0,
			{"type_id": "berserker", "gate": "open", "hp_mult": 0.8, "damage_mult": 1.3}),
		_aid("berserker_heavy", "variant", "重装狂战士", "血量 +40%，重量 +2，移速 −1", 0,
			{"type_id": "berserker", "gate": "open", "hp_mult": 1.4, "mass_add": 2.0, "speed_add": -1.0}),
		_aid("flamefist_bulk", "variant", "批量火拳", "血量 −30%，伤害 −10%，招募价 −8", 0,
			{"type_id": "flamefist", "gate": "bulk", "hp_mult": 0.7, "damage_mult": 0.9, "recruit_delta": -8}),
		_aid("flamefist_over", "variant", "过载型火拳", "炎爆伤害翻倍，每回合只能炎爆一次", 0,
			{"type_id": "flamefist", "gate": "open", "blast_mult": 2.0, "blast_once": true}),
		_aid("lightcav_assault", "variant", "突击型轻骑兵", "移速 +3，生命 −20%", 0,
			{"type_id": "lightcav", "gate": "open", "speed_add": 3.0, "hp_mult": 0.8}),
		_aid("lightcav_improve", "variant", "改进型轻骑兵", "生命 +40%，所有伤害 +20%，招募价 +10", 0,
			{"type_id": "lightcav", "gate": "improve", "hp_mult": 1.4, "damage_mult": 1.2, "recruit_delta": 10}),
		_aid("musket_wise", "variant", "智慧火枪手", "获得的经验翻倍", 0,
			{"type_id": "musket", "gate": "open", "xp_mult": 2.0}),
		_aid("musket_pierce", "variant", "穿甲火枪手", "伤害 +30%，穿透 +1，攻击间隔 +1 秒", 0,
			{"type_id": "musket", "gate": "open", "damage_mult": 1.3, "pierce_add": 1, "interval_add": 1.0}),
		_aid("shadow_bulk", "variant", "批量影魔", "血量 −20%，伤害 −20%，招募价 −8", 0,
			{"type_id": "shadow", "gate": "bulk", "hp_mult": 0.8, "damage_mult": 0.8, "recruit_delta": -8}),
		_aid("shadow_master", "variant", "大师级影魔", "血量 +40%，伤害 +60%，击杀不再获得经验", 0,
			{"type_id": "shadow", "gate": "open", "hp_mult": 1.4, "damage_mult": 1.6, "no_kill_xp": true}),
		_aid("catapult_bulk", "variant", "批量投石车", "血量 −20%，伤害 −20%，招募价 −5", 0,
			{"type_id": "catapult", "gate": "bulk", "hp_mult": 0.8, "damage_mult": 0.8, "recruit_delta": -5}),
		_aid("catapult_range", "variant", "增程投石车", "射程 +10，伤害 −30%", 0,
			{"type_id": "catapult", "gate": "open", "range_add": 10.0, "damage_mult": 0.7}),
		_aid("ballista_improve", "variant", "改进型弩车", "血量 +30%，伤害 +30%，射程 +5，招募价 +10", 0,
			{"type_id": "ballista", "gate": "improve", "hp_mult": 1.3, "damage_mult": 1.3, "range_add": 5.0, "recruit_delta": 10}),
		_aid("ballista_range", "variant", "增程弩车", "射程 +10，伤害 −30%", 0,
			{"type_id": "ballista", "gate": "open", "range_add": 10.0, "damage_mult": 0.7}),
		_aid("corruptor_heavy", "variant", "重装心灵腐化师", "生命 +400%，射程 −10", 0,
			{"type_id": "corruptor", "gate": "open", "hp_mult": 5.0, "range_add": -10.0}),
		_aid("corruptor_improve", "variant", "改进型心灵腐化师", "生命 +20%，伤害 +50%，射程 +4，招募价 +10", 0,
			{"type_id": "corruptor", "gate": "improve", "hp_mult": 1.2, "damage_mult": 1.5, "range_add": 4.0, "recruit_delta": 10}),
		_aid("sandworm_improve", "variant", "改进型沙虫", "生命 +30%，伤害 +30%，招募价 +10", 0,
			{"type_id": "sandworm", "gate": "improve", "hp_mult": 1.3, "damage_mult": 1.3, "recruit_delta": 10}),
		_aid("sandworm_assault", "variant", "突击型沙虫", "生命 −20%，移速 +2，伤害 +30%", 0,
			{"type_id": "sandworm", "gate": "open", "hp_mult": 0.8, "speed_add": 2.0, "damage_mult": 1.3}),
		_aid("master_heavy", "variant", "重装武士大师", "生命 +50%，冲刺和后撤冷却 +1 秒", 0,
			{"type_id": "master", "gate": "open", "hp_mult": 1.5, "cd_add_ms": 1000}),
		_aid("master_bulk", "variant", "批量武士大师", "生命 −40%，伤害 −30%，招募价 −13", 0,
			{"type_id": "master", "gate": "bulk", "hp_mult": 0.6, "damage_mult": 0.7, "recruit_delta": -13}),
		_aid("doom_bulk", "variant", "批量湮灭之瞳", "生命 −30%，伤害 −30%，射程 −2，招募价 −13", 0,
			{"type_id": "doom_eye", "gate": "bulk", "hp_mult": 0.7, "damage_mult": 0.7, "range_add": -2.0, "recruit_delta": -13}),
		_aid("doom_over", "variant", "过载湮灭之瞳", "攻击速度翻倍，射程 −10", 0,
			{"type_id": "doom_eye", "gate": "open", "interval_mult": 0.5, "range_add": -10.0}),
	]

func _aid_experts() -> Array:
	return [
		_aid("expert_speed", "expert", "速度专家", "所有单位移速 +1", 5, {"effect": "speed", "amount": 1.0}),
		_aid("expert_flank", "expert", "突击专家", "部署在敌方侧翼的准备时间减半", 0, {"effect": "flank"}),
		_aid("expert_income", "expert", "补给专家", "此后每回合额外 +5 补给", 5, {"effect": "income", "amount": 5}),
		_aid("expert_income_super", "expert", "超级补给专家", "此后每回合额外 +15 补给", 20, {"effect": "income", "amount": 15}),
		_aid("expert_tech", "expert", "科技专家", "所有科技价格 −5", 5, {"effect": "tech", "amount": 5}),
		_aid("expert_heavy", "expert", "重装专家", "所有单位生命 +20%", 20, {"effect": "hp", "amount": 1.2}),
		_aid("expert_tactic", "expert", "战术专家", "战场道具冷却 −1 回合", 5, {"effect": "prop_cd", "amount": 1}),
		_aid("expert_cost", "expert", "成本控制专家", "此后招募的队伍生命和伤害 −10%，每回合额外 +10 补给", 5, {"effect": "cost", "amount": 10}),
		_aid("expert_deploy", "expert", "部署专家", "每回合可以额外招募一队", 5, {"effect": "squad"}),
		_aid("expert_elite", "expert", "精英专家", "可以直接招募 2 级兵种", 10, {"effect": "elite"}),
		_aid("expert_shield", "expert", "护盾专家", "所有魔法盾血量 +40%", 0, {"effect": "shield", "amount": 1.4}),
		_aid("expert_range", "expert", "射程专家", "所有远程单位射程 +4", 20, {"effect": "range", "amount": 4.0}),
		_aid("expert_attack", "expert", "进攻专家", "所有单位伤害 +20%", 20, {"effect": "damage", "amount": 1.2}),
	]

func _aid_props() -> Array:
	return [
		_aid("prop_grenadier", "prop", "玉面手雷王生成", "开战时在落点生成一队 1 级玉面手雷王。须离敌方指挥所 20 米以外。冷却 0 回合", 10,
			{"use": "point", "delay_ms": 0, "cooldown": 0, "spawn_type": "grenadier", "post_clear": true}),
		_aid("prop_doom", "prop", "空投湮灭之瞳", "开战时生成一队 1 级湮灭之瞳。须离敌方指挥所 20 米以外。冷却 1 回合", 10,
			{"use": "point", "delay_ms": 0, "cooldown": 1, "spawn_type": "doom_eye", "post_clear": true}),
		_aid("prop_master", "prop", "空投武士大师", "开战时生成一队 1 级武士大师。须离敌方指挥所 20 米以外。冷却 1 回合", 10,
			{"use": "point", "delay_ms": 0, "cooldown": 1, "spawn_type": "master", "post_clear": true}),
		_aid("prop_train", "prop", "训练", "拖到一队单位上，立刻补满这队经验。冷却 1 回合", 5,
			{"use": "squad", "cooldown": 1, "train": true}),
		_aid("prop_fire", "prop", "燃烧弹", "开战 2 秒后，40×20 米矩形燃烧 15 秒。冷却 1 回合", 10,
			{"use": "rect", "delay_ms": 2000, "cooldown": 1, "zone": "fire", "length": 40.0, "width": 20.0, "shieldable": true}),
		_aid("prop_oil", "prop", "油桶", "开战 2 秒后洒油，持续两回合。与燃烧重合就烧起来。油上移速 −60%。冷却 1 回合", 10,
			{"use": "rect", "delay_ms": 2000, "cooldown": 1, "zone": "oil", "zone_rounds": 2, "length": 40.0, "width": 20.0, "shieldable": true}),
		_aid("prop_acid", "prop", "酸液弹", "开战 2 秒后洒酸，持续两回合。冷却 2 回合", 10,
			{"use": "rect", "delay_ms": 2000, "cooldown": 2, "zone": "acid", "zone_rounds": 2, "length": 40.0, "width": 20.0, "shieldable": true}),
		_aid("prop_silence", "prop", "沉默弹", "开战 2 秒后，半径 9 米的敌军受到 300 伤害并沉默 10 秒。冷却 1 回合", 5,
			{"use": "point", "delay_ms": 2000, "cooldown": 1, "radius": 9.0, "damage": 300.0, "silence_ms": 10000, "shieldable": true}),
		_aid("prop_silence_big", "prop", "大型沉默弹", "开战 2 秒后，半径 30 米的敌军沉默 10 秒。冷却 3 回合", 20,
			{"use": "point", "delay_ms": 2000, "cooldown": 3, "radius": 30.0, "silence_ms": 10000, "shieldable": true}),
		_aid("prop_storm", "prop", "闪电风暴", "开战 1 秒后，每 0.5 秒在半径 30 米内随机打一处半径 5 米、500 伤害，持续 10 秒。范围内敌军移速 −40%。冷却 3 回合", 20,
			{"use": "point", "delay_ms": 1000, "cooldown": 3, "radius": 30.0, "pulse_ms": 500, "duration_ms": 10000, "pulse_radius": 5.0, "damage": 500.0, "slow_mult": 0.6, "slow_ms": 10000, "shieldable": true}),
		_aid("prop_nuke", "prop", "核弹", "开战 10 秒后，半径 30 米内所有单位受到 7000 伤害。冷却 4 回合", 25,
			{"use": "point", "delay_ms": 10000, "cooldown": 4, "radius": 30.0, "damage": 7000.0, "hits_friendly": true, "shieldable": true}),
		_aid("prop_missile", "prop", "小型导弹", "开战 2 秒后，半径 9 米的敌军受到 500 伤害。无冷却", 0,
			{"use": "point", "delay_ms": 2000, "cooldown": 0, "radius": 9.0, "damage": 500.0, "shieldable": true}),
		_aid("prop_spear", "prop", "神圣长矛", "开战 2 秒后，半径 1 米的敌军受到 7000 伤害，无视魔法盾。冷却 2 回合", 10,
			{"use": "point", "delay_ms": 2000, "cooldown": 2, "radius": 1.0, "damage": 7000.0, "ignore_shield": true}),
		_aid("prop_shield", "prop", "空投魔法盾", "开战 1 秒后空投一面双倍血量的魔法盾。冷却 1 回合", 5,
			{"use": "point", "delay_ms": 1000, "cooldown": 1, "shield_drop": true}),
		_aid("prop_barrier", "prop", "空投火焰屏障", "开战 1 秒后，半径 18 米的友方获得 10 秒火焰屏障。冷却 2 回合", 10,
			{"use": "point", "delay_ms": 1000, "cooldown": 2, "barrier": true, "radius": 18.0}),
		_aid("prop_beacon", "prop", "移动信标", "额外获得一个移动信标", 5, {"use": "squad", "cooldown": 0, "beacon": true}),
		_aid("prop_recall", "prop", "高效遣返", "遣返一队并返还除科技外的全部花费。冷却 1 回合", 5,
			{"use": "squad", "cooldown": 1, "full_recall": true}),
		_aid("prop_redeploy", "prop", "再部署", "使一队在本回合可以重新移动。无冷却", 5,
			{"use": "squad", "cooldown": 0, "redeploy": true}),
		_aid("prop_orbital", "prop", "轨道轰炸", "开战 1 秒后，每 0.5 秒在半径 30 米内随机打一处半径 5 米、1500 伤害，持续 10 秒。冷却 3 回合", 20,
			{"use": "point", "delay_ms": 1000, "cooldown": 3, "radius": 30.0, "pulse_ms": 500, "duration_ms": 10000, "pulse_radius": 5.0, "damage": 1500.0, "shieldable": true}),
		_aid("prop_smoke", "prop", "烟雾弹", "开战 2 秒后烟雾持续两回合。烟雾内远程射程 −10。冷却 2 回合", 10,
			{"use": "rect", "delay_ms": 2000, "cooldown": 2, "zone": "smoke", "zone_rounds": 2, "length": 40.0, "width": 20.0, "shieldable": true}),
	]

func _aid_modules() -> Array:
	return [
		_aid("mod_quiet", "module", "抗干扰模块", "不会被心灵腐化师锁定，免疫沉默和指挥所被摧毁的负面", 0,
			{"block_corrupt": true, "block_silence": true, "block_post": true}),
		_aid("mod_ward", "module", "便携魔法盾", "仅权重 ≥ 10。每回合自带半径 15 米、1000×等级的跟随魔法盾。已有庇护则血量叠加", 5,
			{"min_weight": 10, "ward": true}),
		_aid("mod_raid", "module", "游击模块", "每回合部署阶段都能移动", 0, {"move_always": true}),
		_aid("mod_speed", "module", "速度模块", "移速 +2", 0, {"speed_add": 2.0}),
		_aid("mod_amp_small", "module", "小型增幅模块", "攻击和生命 +30%", 5, {"hp_mult": 1.3, "damage_mult": 1.3}),
		_aid("mod_range", "module", "射程模块", "仅远程。射程 +8", 5, {"ranged_only": true, "range_add": 8.0}),
		_aid("mod_heavy", "module", "重装模块", "生命 +100%", 10, {"hp_mult": 2.0}),
		_aid("mod_mend", "module", "自我恢复模块", "每回合回复最大生命的 9%", 10, {"heal_ratio": 0.09}),
		_aid("mod_amp_large", "module", "大型增幅模块", "攻击和生命 +60%", 15, {"hp_mult": 1.6, "damage_mult": 1.6}),
		_aid("mod_ultimate", "module", "究极模块", "攻击和生命 +100%，升级不消耗补给", 30,
			{"hp_mult": 2.0, "damage_mult": 2.0, "free_upgrade": true}),
		_aid("mod_rush", "module", "速攻模块", "移速 +1，伤害 +40%", 5, {"speed_add": 1.0, "damage_mult": 1.4}),
		_aid("mod_ultra", "module", "超重装模块", "生命 +150%", 15, {"hp_mult": 2.5}),
		_aid("mod_summon_grenadier", "module", "玉面手雷王生产模块", "仅权重 ≥ 10。每 10 秒召唤 4 个同等级玉面手雷王", 10,
			{"min_weight": 10, "summon_type": "grenadier", "summon_count": 4, "summon_interval_ms": 10000}),
		_aid("mod_summon_sword", "module", "剑盾兵模块", "仅权重 ≥ 10。每 10 秒召唤 4 个同等级剑盾兵", 10,
			{"min_weight": 10, "summon_type": "sword", "summon_count": 4, "summon_interval_ms": 10000}),
		_aid("mod_summon_shortbow", "module", "短弓手生产模块", "仅权重 ≥ 10。每 10 秒召唤 4 个同等级短弓手", 10,
			{"min_weight": 10, "summon_type": "shortbow", "summon_count": 4, "summon_interval_ms": 10000}),
		_aid("mod_summon_spear", "module", "长矛兵生产模块", "仅权重 ≥ 10。每 10 秒召唤 4 个同等级长矛兵", 10,
			{"min_weight": 10, "summon_type": "spear", "summon_count": 4, "summon_interval_ms": 10000}),
		_aid("mod_core", "module", "统御核心", "攻击 +50%，生命 +100%。每回合开始 +5 补给。这队被消灭时我方单位全部死亡", 0,
			{"hp_mult": 2.0, "damage_mult": 1.5, "income": 5, "doom": true}),
	]

# ---------------------------------------------------------------- 肉鸽：格子与"队"（第二块）
## 场地格数：沿 X（东西，两队对阵方向）= 2 × 半宽 ÷ 格边长、沿 Z（南北）= 2 × 半深 ÷ 格边长。
## ⚠️ 格数**从场地尺寸推**，不写死格数 —— 改场地或改格子边长，这里自动跟上。
## ⚠️ `half_x` / `half_z` 是**肉鸽自己的**场地半宽 / 半深（第六块起肉鸽的场地与全局不同）：
## 不传（或传负）时回落到**全局**值（100×50 ⇒ 50 × 25 格）；肉鸽传 `arena.half_x` / `arena.half_z`
##（2026-09-27 第七块：150×111.5 ⇒ **75 × 56 格**）。⚠️ 参数默认值不能用 `ARENA_HALF_X` —— 那个是 `var` 不是 `const`，
## GDScript 的默认值必须是常量表达式 ⇒ 用 −1 当"没传"的哨兵。
func roguelike_grid_cols(half_x: float = -1.0) -> int:
	var half: float = ARENA_HALF_X if half_x < 0.0 else half_x
	return int(round(half * 2.0 / ROGUELIKE_CELL_SIZE))

func roguelike_grid_rows(half_z: float = -1.0) -> int:
	var half: float = ARENA_HALF_Z if half_z < 0.0 else half_z
	return int(round(half * 2.0 / ROGUELIKE_CELL_SIZE))

## 第 (col, row) 格**中心**的世界坐标：`col` 沿 X（0 = 西墙那一侧）、`row` 沿 Z（0 = −Z 边起）。
## ⚠️ 同样按肉鸽自己的场地尺寸算（见上面两个函数）；不传时回落全局值。
func roguelike_cell_center(col: int, row: int, half_x: float = -1.0, half_z: float = -1.0) -> Vector3:
	var hx: float = ARENA_HALF_X if half_x < 0.0 else half_x
	var hz: float = ARENA_HALF_Z if half_z < 0.0 else half_z
	return Vector3(
			-hx + (float(col) + 0.5) * ROGUELIKE_CELL_SIZE,
			0.0,
			-hz + (float(row) + 0.5) * ROGUELIKE_CELL_SIZE)

## 该权重档的"队"定义。⚠️ 表里**没有**这个档位时返回空字典 ⇒ 调用方自己判 `is_empty()`。
func roguelike_squad_def(weight: int) -> Dictionary:
	return ROGUELIKE_SQUAD_TABLE.get(weight, {})

## 一队几个兵（= `across × deep`；表里没有的档位 ⇒ 0）
func roguelike_squad_size(weight: int) -> int:
	var def: Dictionary = roguelike_squad_def(weight)
	return int(def.get("across", 0)) * int(def.get("deep", 0))

## 一队的**外框**：横（沿 Z 的格数）× 纵（沿 X 的格数）
func roguelike_squad_width(weight: int) -> int:
	var def: Dictionary = roguelike_squad_def(weight)
	return int(def.get("across", 0)) * int(def.get("unit_width", 0))

func roguelike_squad_depth(weight: int) -> int:
	var def: Dictionary = roguelike_squad_def(weight)
	return int(def.get("deep", 0)) * int(def.get("unit_depth", 0))

## 买一整队要花多少补给 = **人数 × 权重**（补给 : 权重 = 1 : 1）
func roguelike_squad_cost(weight: int) -> int:
	return roguelike_squad_size(weight) * weight

## 升到下一级要的经验。1 级升 2 级 = 一队总权重；每再高一级，在这个基数上加 50%。
## 总权重 10 ⇒ 10、15、20、25（不是 10、15、22 这种复利）。出现半数时向上取整。
func roguelike_squad_xp_cost(level: int, unit_weight: int) -> int:
	if level < 1 or level >= ROGUELIKE_LEVEL_MAX:
		return 0
	var base := roguelike_squad_cost(unit_weight)
	return ceili(float(base) * (1.0 + 0.5 * float(level - 1)))

## 这一回合每个敌方兵种抽几条科技。第 3 回合起才有，之后由少到多，封顶由兵种自己的表决定。
func roguelike_enemy_tech_count(round_index: int) -> int:
	if round_index < ROGUELIKE_ENEMY_TECH_FROM_ROUND:
		return 0
	return 1 + (round_index - ROGUELIKE_ENEMY_TECH_FROM_ROUND) / ROGUELIKE_ENEMY_TECH_STEP_ROUNDS

## 这一回合里第 `squad_index` 队（0 起，按波次名单的出生顺序）是几级。
## 第 1～2 回合全是 1 级。第 3 回合起从**队尾**开始抬：每一档每回合只多盖住一段，不是整波一起跳。
## 最后一回合全部 `ROGUELIKE_ENEMY_LEVEL_LAST`。同一队仍然同级。
func roguelike_enemy_squad_level(round_index: int, squad_index: int, squad_count: int) -> int:
	if round_index < ROGUELIKE_ENEMY_LEVEL_FROM_ROUND:
		return 1
	if round_index >= ROGUELIKE_ROUND_COUNT:
		return ROGUELIKE_ENEMY_LEVEL_LAST
	var n := maxi(squad_count, 1)
	var from_tail := n - 1 - clampi(squad_index, 0, n - 1)
	var at_least_2 := 0
	var at_least_3 := 0
	var at_least_4 := 0
	match round_index:
		3:
			at_least_2 = _enemy_level_slice(n, 1, 5)
		4:
			at_least_2 = _enemy_level_slice(n, 2, 5)
			at_least_3 = _enemy_level_slice(n, 1, 8)
		5:
			at_least_2 = _enemy_level_slice(n, 3, 5)
			at_least_3 = _enemy_level_slice(n, 1, 4)
		6:
			at_least_2 = _enemy_level_slice(n, 4, 5)
			at_least_3 = _enemy_level_slice(n, 2, 5)
			at_least_4 = _enemy_level_slice(n, 1, 8)
		7:
			at_least_2 = _enemy_level_slice(n, 4, 5)
			at_least_3 = _enemy_level_slice(n, 1, 2)
			at_least_4 = _enemy_level_slice(n, 1, 5)
		8:
			at_least_2 = n
			at_least_3 = _enemy_level_slice(n, 3, 4)
			at_least_4 = _enemy_level_slice(n, 2, 5)
		9:
			at_least_2 = n
			at_least_3 = n
			at_least_4 = _enemy_level_slice(n, 3, 5)
		_:
			return ROGUELIKE_ENEMY_LEVEL_LAST
	at_least_3 = mini(maxi(at_least_3, at_least_4), n)
	at_least_2 = mini(maxi(at_least_2, at_least_3), n)
	if from_tail < at_least_4:
		return 4
	if from_tail < at_least_3:
		return 3
	if from_tail < at_least_2:
		return 2
	return 1

## 这一档盖住队尾的多少队。分子为 0 时一队都不抬；否则至少 1 队，不超过整波。
func _enemy_level_slice(squad_count: int, numer: int, denom: int) -> int:
	if numer <= 0 or denom <= 0 or squad_count <= 0:
		return 0
	return mini(squad_count, maxi(1, int(squad_count * numer / denom)))

## 第 `round_index` 回合（从 1 起）的敌方波次。超出 1～10 时夹到最后一回合。
func roguelike_enemy_wave(round_index: int) -> Array:
	if ROGUELIKE_ENEMY_WAVES.is_empty():
		return []
	var index := clampi(round_index, 1, ROGUELIKE_ENEMY_WAVES.size()) - 1
	return ROGUELIKE_ENEMY_WAVES[index]

## 这一回合敌方作战单位的总权重。第 1 回合 `BASE`，之后每回合加 `PER_ROUND`。
func roguelike_enemy_weight_target(round_index: int) -> int:
	var k := clampi(round_index, 1, ROGUELIKE_ROUND_COUNT) - 1
	return ROGUELIKE_ENEMY_WEIGHT_BASE + ROGUELIKE_ENEMY_WEIGHT_PER_ROUND * k


func roguelike_difficulty_id(raw: String) -> String:
	if ROGUELIKE_DIFFICULTY_ORDER.has(raw):
		return raw
	return ROGUELIKE_DIFFICULTY_DEFAULT


func roguelike_difficulty_name(difficulty: String) -> String:
	match roguelike_difficulty_id(difficulty):
		ROGUELIKE_DIFFICULTY_EASY:
			return "简单"
		ROGUELIKE_DIFFICULTY_NORMAL:
			return "普通"
		ROGUELIKE_DIFFICULTY_HARD:
			return "困难"
		ROGUELIKE_DIFFICULTY_VERY_HARD:
			return "非常困难"
		ROGUELIKE_DIFFICULTY_TRANSCEND:
			return "超越"
		ROGUELIKE_DIFFICULTY_MIRACLE:
			return "不可能的奇迹"
		_:
			return "非常简单"


func _roguelike_difficulty_rank(difficulty: String) -> int:
	var index := ROGUELIKE_DIFFICULTY_ORDER.find(roguelike_difficulty_id(difficulty))
	return index if index >= 0 else 0


func roguelike_enemy_weight_target_for(difficulty: String, round_index: int) -> int:
	var rank := _roguelike_difficulty_rank(difficulty)
	var base := ROGUELIKE_DIFFICULTY_WEIGHT_BASE
	var step := ROGUELIKE_DIFFICULTY_WEIGHT_STEP
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_EASY):
		step += ROGUELIKE_DIFFICULTY_STEP_BONUS
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_NORMAL):
		base += ROGUELIKE_DIFFICULTY_BASE_BONUS
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_VERY_HARD):
		step += ROGUELIKE_DIFFICULTY_STEP_BONUS
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_MIRACLE):
		base += ROGUELIKE_DIFFICULTY_BASE_BONUS
	var k := clampi(round_index, 1, ROGUELIKE_ROUND_COUNT) - 1
	return base + step * k


func roguelike_enemy_uses_flank(difficulty: String) -> bool:
	return _roguelike_difficulty_rank(difficulty) >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_HARD)


func roguelike_enemy_wave_for(difficulty: String, round_index: int) -> Array:
	if roguelike_difficulty_id(difficulty) == ROGUELIKE_DIFFICULTY_MIRACLE:
		return roguelike_enemy_wave(round_index)
	return _roguelike_enemy_pack(roguelike_enemy_weight_target_for(difficulty, round_index), round_index)


func roguelike_enemy_squad_level_for(difficulty: String, round_index: int, squad_index: int,
		squad_count: int) -> int:
	var rank := _roguelike_difficulty_rank(difficulty)
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_TRANSCEND):
		return roguelike_enemy_squad_level(round_index, squad_index, squad_count)
	if rank < _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_EASY):
		return 1
	var n := maxi(squad_count, 1)
	var from_tail := n - 1 - clampi(squad_index, 0, n - 1)
	if round_index < ROGUELIKE_DIFFICULTY_LEVEL_FROM_ROUND:
		return 1
	if rank >= _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_HARD):
		if round_index < ROGUELIKE_DIFFICULTY_LEVEL3_FROM_ROUND:
			var raised_2 := int(n * (round_index - 2) / ROGUELIKE_DIFFICULTY_HARD_LEVEL_DENOM)
			return 2 if from_tail < raised_2 else 1
		var raised_3 := int(n * (round_index - 6) / ROGUELIKE_DIFFICULTY_HARD_LEVEL_DENOM)
		return 3 if from_tail < raised_3 else 2
	var steps := mini(round_index - 2, ROGUELIKE_DIFFICULTY_EASY_LEVEL_DENOM)
	var raised := int(n * steps / ROGUELIKE_DIFFICULTY_EASY_LEVEL_DENOM)
	return 2 if from_tail < raised else 1


func roguelike_enemy_squad_tech_count(difficulty: String, round_index: int, squad_index: int,
		squad_count: int) -> int:
	var rank := _roguelike_difficulty_rank(difficulty)
	if rank < _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_NORMAL):
		return 0
	if round_index < ROGUELIKE_DIFFICULTY_TECH_FROM_ROUND:
		return 0
	var n := maxi(squad_count, 1)
	var from_tail := n - 1 - clampi(squad_index, 0, n - 1)
	var half := int(n / ROGUELIKE_DIFFICULTY_TECH_HALF_DENOM)
	if rank < _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_VERY_HARD):
		if round_index < ROGUELIKE_DIFFICULTY_TECH_ALL_ROUND:
			return 1 if from_tail < half else 0
		return 1
	if rank < _roguelike_difficulty_rank(ROGUELIKE_DIFFICULTY_MIRACLE):
		if round_index < ROGUELIKE_DIFFICULTY_TECH_ALL_ROUND:
			return 1
		return 2
	var elapsed := round_index - ROGUELIKE_DIFFICULTY_TECH_FROM_ROUND
	var pair := int(elapsed / 2)
	var target := pair + 1
	var half_round := elapsed % 2 == 0
	if half_round:
		return target if from_tail < half else maxi(target - 1, 0)
	return target


func _roguelike_enemy_pack(weight: int, round_index: int) -> Array:
	var span := float(maxi(ROGUELIKE_ROUND_COUNT - 1, 1))
	var along := clampf(float(clampi(round_index, 1, ROGUELIKE_ROUND_COUNT) - 1) / span, 0.0, 1.0)
	var want_10 := lerpf(ROGUELIKE_DIFFICULTY_PACK_EARLY_10, ROGUELIKE_DIFFICULTY_PACK_LATE_10, along)
	var want_25 := lerpf(ROGUELIKE_DIFFICULTY_PACK_EARLY_25, ROGUELIKE_DIFFICULTY_PACK_LATE_25, along)
	var want_15 := 1.0 - want_10 - want_25
	var best_left := weight + 1
	var best_mix := 0.0
	var best_10 := 0
	var best_15 := 0
	var best_25 := 0
	var found := false
	for count_25 in range(int(weight / 25) + 1):
		var after_25 := weight - count_25 * 25
		for count_15 in range(int(after_25 / 15) + 1):
			var after_15 := after_25 - count_15 * 15
			var count_10 := int(after_15 / 10)
			var left := after_15 - count_10 * 10
			var total := count_10 + count_15 + count_25
			if total <= 0:
				continue
			var err_10 := absf(float(count_10) - want_10 * float(total))
			var err_15 := absf(float(count_15) - want_15 * float(total))
			var err_25 := absf(float(count_25) - want_25 * float(total))
			var mix := err_10 * (1.0 + 2.0 * (1.0 - along)) + err_15 + err_25 * (1.0 + 2.0 * along)
			if not found or left < best_left or (left == best_left and mix < best_mix):
				found = true
				best_left = left
				best_mix = mix
				best_10 = count_10
				best_15 = count_15
				best_25 = count_25
	var out: Array = []
	if best_10 > 0:
		out.append({"squad_weight": 10, "squads": best_10})
	if best_15 > 0:
		out.append({"squad_weight": 15, "squads": best_15})
	if best_25 > 0:
		out.append({"squad_weight": 25, "squads": best_25})
	return out

## 一队总权重正好是 `squad_weight` 的可买兵种。指挥所和沙盒专属不在里面。
func roguelike_enemy_types_for_squad_weight(squad_weight: int) -> Array:
	var out: Array = []
	for type_id in roguelike_buyable_types():
		var unit_weight := int(profile(String(type_id)).get("weight", 0))
		if roguelike_squad_size(unit_weight) <= 0:
			continue
		if roguelike_squad_cost(unit_weight) == squad_weight:
			out.append(String(type_id))
	return out

## 这一兵种在敌方半场里按后排走：投射物、持续照射，以及名单里的近战火焰拳。
func roguelike_enemy_stands_back(type_id: String) -> bool:
	if ROGUELIKE_ENEMY_BACKLINE_MELEE.has(type_id):
		return true
	if not PROFILES.has(type_id):
		return false
	var row: Dictionary = PROFILES[type_id]
	if bool(row.get("is_ranged", false)):
		return true
	return bool(row.get("sustained_beam", false))

## 面向我方要空出的格数。近战（火焰拳除外）是 0。
func roguelike_enemy_front_cells(type_id: String) -> int:
	if not roguelike_enemy_stands_back(type_id):
		return 0
	if ROGUELIKE_ENEMY_SIEGE_TYPES.has(type_id):
		return ROGUELIKE_ENEMY_SIEGE_FRONT_CELLS
	return ROGUELIKE_ENEMY_FRONT_CELLS

## 敌方半场其余三边要空出的格数。近战（火焰拳除外）是 0。
func roguelike_enemy_edge_cells(type_id: String) -> int:
	if roguelike_enemy_stands_back(type_id):
		return ROGUELIKE_ENEMY_EDGE_CELLS
	return 0

## 解锁一个兵种的花费 = ⌊**招募一队这个兵种**的总权重 ÷ `ROGUELIKE_UNLOCK_DIVISOR`⌋。
## 用户口径（2026-09-26 第三块修正）："解锁的价格不是场上兵种总权重的一半，而是**招募一队这个兵种**总权重的一半
##（如召一队剑盾手要 5 补给）" —— ⚠️ **第二块那版按"全队总权重"算是错的**（那是我的误读，已改回来）：
## 剑盾手一队 10 人 × 权重 1 = 10 ⇒ 解锁 **5** ✓ 与用户举的例子一致。
## 六档依次 = **5 / 5 / 7 / 7 / 5 / 12**（= `squad_cost ÷ 2` 向下取整）。
func roguelike_unlock_cost(type_id: String) -> int:
	var weight := int(PROFILES.get(type_id, {}).get("weight", 0))
	return roguelike_squad_cost(weight) / ROGUELIKE_UNLOCK_DIVISOR

# ---------------------------------------------------------------- 肉鸽兵种科技（2026-09-27 第十二轮）
## 用户口径（原话在项目根的 `肉鸽兵种科技.txt`）："科技需要**选中相应兵种**后**花费补给激活**，
## 激活后**所有同类型兵种都能吃到科技加成**（如点了剑盾兵的某个科技，则所有剑盾兵都会吃到该科技加成）"。
## ⚠️ **分两批落地**（2026-09-27 当场问答，用户选了"① 分两批，先数值类"）：
##   第一批（"改一个数"就能生效的 7 条）：护甲升级（剑/矛）、防御模式、狂暴、魔法护盾、射程增加、精英猎手；
##   第二批（要新机制的 5 条）：高级格挡 / 火焰附加 / 剑圣 / Spartan 投矛 / 火矢 —— **2026-09-27 同日已全部落地**，
##   所以现在**表里没有任何 `"pending"` 标记**（`roguelike_tech_ready()` 与界面上那两种灰态因此暂时用不到，
##   留着是为了"下次再分批加科技"时不用改界面）。
## ⚠️ 点燃的两个共享口径（2026-09-27 当场问答）：
##   ① **只刷新、取最高**：同一目标身上只有一个点燃状态，再点火就刷新持续时间、百分比取较高的那条；
##   ② **点燃不吃护甲**（否则 15 × 等级的护甲会把 6~8%/s 的小额跳伤直接减到 0 ⇒ 点燃对高护甲单位等于无效）。
const ROGUELIKE_BURN_TICK_MS := 1000     ## 点燃的跳伤节拍 ms（每秒一跳 ⇒ 5 s 共 5 跳；绝对时刻，I-13）
## ⚠️ 效果参数一律住这张表（I-15：可调参数的唯一住处）—— `unit3d.gd` 只读、不存副本。
## 字段：`id`（稳定标识，写进存档/调试）、`name`（界面用）、`cost`（补给）、`effect`（效果种类，
## 与 `Unit3D` 里那一支 switch 对应）、其余为该效果自己的参数。
const ROGUELIKE_TECH_TABLE := {
	"sword": [
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "block_ranged", "name": "高级格挡", "cost": 10, "effect": "block_ranged"},
		{"id": "fire_blade", "name": "火焰附加", "cost": 25, "effect": "ignite",
			"burn_ratio_per_sec": 0.08, "burn_ms": 5000},
		{"id": "sword_saint", "name": "剑圣", "cost": 30, "effect": "sword_saint",
			"hp_mult": 3.0, "damage_mult": 2.5, "range_mult": 2.0},
	],
	"spear": [
		{"id": "defense_mode", "name": "防御模式", "cost": 20, "effect": "defense",
			"hp_mult": 1.80, "kb_bonus": 2.0, "move_speed_delta": -2.0},
		{"id": "spartan", "name": "This is SPARTA！", "cost": 20, "effect": "spartan",
			"throw_range": 16.0, "throw_damage_mult": 1.5},
		{"id": "armor_up", "name": "护甲升级", "cost": 15, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "rage", "name": "狂暴", "cost": 35, "effect": "rage",
			"move_speed_delta": 2.0, "interval_mult": 0.5},
	],
	"shortbow": [
		{"id": "magic_shield", "name": "魔法护盾", "cost": 30, "effect": "magic_shield",
			"shield_hp_mult": 1.0},
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "fire_arrow", "name": "火矢", "cost": 25, "effect": "ignite",
			"burn_ratio_per_sec": 0.06, "burn_ms": 5000},
		{"id": "elite_hunter", "name": "精英猎手", "cost": 30, "effect": "elite",
			"damage_per_level": 0.07, "hp_per_level": 0.07, "range_per_level": 1.5},
	],
	"fan": [
		{"id": "gale", "name": "八级大狂风", "cost": 15, "effect": "gale",
			"kb_bonus": 2.0},
		{"id": "intercept", "name": "拦截", "cost": 25, "effect": "intercept",
			"range": 16.0},
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "scavenger", "name": "清道夫", "cost": 15, "effect": "scavenger",
			"radius": 5.0},
	],
	"knight": [
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "mend", "name": "自我修复", "cost": 25, "effect": "mend",
			"hp_mult": 1.60, "heal_ratio": 0.045},
		{"id": "bulwark", "name": "壁垒", "cost": 30, "effect": "bulwark",
			"hp_mult": 2.20, "link_radius": 5.0},
		{"id": "holy_strike", "name": "神圣打击", "cost": 20, "effect": "holy_strike",
			"radius": 4.0, "cooldown_ms": 8000},
	],
	"berserker": [
		{"id": "rage", "name": "狂暴", "cost": 30, "effect": "rage",
			"move_speed_delta": 2.0, "interval_mult": 0.5, "hp_mult": 0.60, "jump_mult": 2.0},
		{"id": "ember", "name": "余烬", "cost": 15, "effect": "ember",
			"endure_ms": 2000},
		{"id": "armor_up", "name": "护甲升级", "cost": 10, "effect": "armor",
			"armor_per_level": 15.0},
		{"id": "destroyer", "name": "毁灭者", "cost": 30, "effect": "destroyer",
			"damage_mult": 2.0, "self_ratio": 0.08},
	],
	"grenadier": [
		{"id": "acid_bomb", "name": "酸液炸弹", "cost": 30, "effect": "acid",
			"radius": 2.0, "tick_ratio": 0.03, "vuln_mult": 2.0},
		{"id": "rage", "name": "狂暴", "cost": 25, "effect": "rage",
			"move_speed_delta": 2.0, "interval_mult": 0.5, "damage_mult": 3.0},
		{"id": "damage_amp", "name": "伤害增幅", "cost": 20, "effect": "damage_amp",
			"damage_pct": 0.30},
		{"id": "replicate", "name": "自我复制", "cost": 30, "effect": "replicate"},
	],
	"longbow": [
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "elite_hunter", "name": "精英猎手", "cost": 30, "effect": "elite",
			"damage_per_level": 0.07, "hp_per_level": 0.07, "range_per_level": 1.5},
		{"id": "explosive_arrow", "name": "爆炸箭", "cost": 20, "effect": "explosive",
			"damage_mult": 0.7, "radius": 3.0, "splash_ratio": 0.5},
	],
	"catapult": [
		{"id": "scatter_shot", "name": "散射", "cost": 15, "effect": "scatter",
			"count": 3, "damage_mult": 0.7, "spread_deg": 7.0},
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "rapid_throw", "name": "快速投掷", "cost": 25, "effect": "rapid",
			"interval_mult": 0.5, "range_bonus": -8.0},
		{"id": "siege_mode", "name": "攻城模式", "cost": 30, "effect": "siege",
			"range_bonus": 18.0, "min_range": 18.0},
		{"id": "fireball", "name": "火球", "cost": 20, "effect": "fireball",
			"tick_damage": 100.0},
		{"id": "silence_shot", "name": "沉默弹", "cost": 30, "effect": "silence",
			"duration_ms": 5000, "move_mult": 0.7},
	],
	"ballista": [
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "rapid_shot", "name": "快速射击", "cost": 10, "effect": "rapid",
			"interval_mult": 0.5, "damage_reduction": 0.5, "kb_mult": 0.5},
		{"id": "assault", "name": "突击模式", "cost": 20, "effect": "assault",
			"hp_mult": 4.0, "move_speed_delta": 3.0, "aoe_radius": 4.0, "range_bonus": -20.0},
		{"id": "elite_hunter", "name": "精英猎手", "cost": 30, "effect": "elite",
			"damage_per_level": 0.07, "hp_per_level": 0.07, "range_per_level": 2.0},
		{"id": "silence_shot", "name": "沉默弹", "cost": 25, "effect": "silence",
			"duration_ms": 5000, "move_mult": 0.7},
	],
	"flamefist": [
		{"id": "energy_leech", "name": "能量汲取", "cost": 15, "effect": "energy_leech",
			"hp_ratio": 0.5},
		{"id": "energy_burst", "name": "能量爆发", "cost": 20, "effect": "energy_burst",
			"radius": 6.0},
		{"id": "mend", "name": "自我修复", "cost": 25, "effect": "mend",
			"hp_mult": 1.60, "heal_ratio": 0.045},
		{"id": "flame_barrier", "name": "火焰屏障", "cost": 30, "effect": "flame_barrier",
			"delay_ms": 1000, "duration_ms": 10000, "radius": 18.0, "damage_taken_mult": 0.6},
	],
	"musket": [
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "elite_hunter", "name": "精英猎手", "cost": 30, "effect": "elite",
			"damage_per_level": 0.07, "hp_per_level": 0.07, "range_per_level": 1.5},
		{"id": "rapid_shot", "name": "快速射击", "cost": 10, "effect": "rapid",
			"interval_mult": 0.5, "damage_reduction": 0.5, "kb_mult": 0.5},
		{"id": "silence_shot", "name": "沉默弹", "cost": 30, "effect": "silence",
			"duration_ms": 5000, "move_mult": 0.7},
	],
	"shadow": [
		{"id": "shadow_guard", "name": "暗影守护", "cost": 20, "effect": "shadow_guard",
			"duration_ms": 2000, "damage_taken_mult": 0.5},
		{"id": "replicate", "name": "自我复制", "cost": 30, "effect": "replicate"},
		{"id": "revenge", "name": "复仇", "cost": 25, "effect": "revenge",
			"damage_mult": 1.5, "radius": 4.0},
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
	],
	"lightcav": [
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "wild_horse", "name": "野马", "cost": 25, "effect": "wild_horse",
			"damage_mult": 2.0, "duration_mult": 0.5},
		{"id": "horse_speed", "name": "马作的卢", "cost": 20, "effect": "horse_speed",
			"move_speed_delta": 3.0},
		{"id": "dismount", "name": "弃马人", "cost": 15, "effect": "dismount"},
	],
	"corruptor": [
		{"id": "control_heal", "name": "强化控制", "cost": 15, "effect": "control_heal"},
		{"id": "multi_beam", "name": "多重控制", "cost": 20, "effect": "multi_beam",
			"beam_count": 5, "corrupt_ratio": 0.4, "range_bonus": -4.0},
		{"id": "shelter", "name": "庇护", "cost": 30, "effect": "shelter",
			"radius": 15.0, "shield_hp": 700.0},
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
	],
	"sandworm": [
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "sandstorm", "name": "沙暴", "cost": 30, "effect": "sandstorm",
			"radius": 10.0, "duration_ms": 6000, "move_pct": -0.40, "damage_taken_mult": 0.6},
		{"id": "burrow_mend", "name": "潜地修复", "cost": 15, "effect": "burrow_mend",
			"heal_ratio": 0.15},
		{"id": "broodmother", "name": "母虫", "cost": 25, "effect": "broodmother",
			"hp_scale": 0.5, "damage_scale": 0.5},
		{"id": "ambush", "name": "偷袭", "cost": 20, "effect": "ambush",
			"damage_mult": 4.0, "range_bonus": 1.0},
	],
	"master": [
		{"id": "deflect_up", "name": "偏折升级", "cost": 20, "effect": "deflect_up",
			"flight_range": 20.0, "per_cooldown": 20, "charges": 20},
		{"id": "afterimage", "name": "影分身", "cost": 25, "effect": "afterimage",
			"hp_scale": 0.333333, "duration_ms": 1000},
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
		{"id": "sidestep", "name": "侧闪", "cost": 10, "effect": "sidestep",
			"cooldown_ms": 5000},
		{"id": "riposte", "name": "攻守相济", "cost": 15, "effect": "riposte",
			"damage_mult": 1.0, "cooldown_ms": 2000},
		{"id": "thunder_breath", "name": "雷之呼吸", "cost": 30, "effect": "thunder_breath",
			"width_mult": 2.0, "damage_mult": 2.0},
	],
	"doom_eye": [
		{"id": "range_up", "name": "射程增加", "cost": 20, "effect": "range",
			"range_bonus": 10.0},
		{"id": "leech", "name": "榨取", "cost": 20, "effect": "leech",
			"heal_ratio": 0.5},
		{"id": "energy_scatter", "name": "能量散射", "cost": 25, "effect": "energy_scatter",
			"beam_count": 5, "damage_ratio": 0.2, "range_bonus": -8.0},
		{"id": "shelter", "name": "庇护", "cost": 30, "effect": "shelter",
			"radius": 15.0, "shield_hp": 1500.0},
		{"id": "summon_grenadier", "name": "召唤手雷王", "cost": 15, "effect": "summon_grenadier",
			"interval_ms": 15000, "count": 4},
		{"id": "armor_up", "name": "护甲升级", "cost": 20, "effect": "armor",
			"armor_per_level": 15.0, "hp_mult": 1.30},
	],
}

## 同兵种每已经买下一条，该兵种还没买的每条标价再加这么多补给（2026-10-01）。
## 买第 1 条按表内 `cost`；买第 2 条时其余各 +15；买第 3 条时剩下的各 +30。别的兵种不加。
const ROGUELIKE_TECH_COST_STEP := 15
## 「自我复制」一次最多生出几个（2026-10-01：按被杀单位权重生，超过本值的部分截掉）。
## 影魔不走这条：它要累计击杀权重到 `ROGUELIKE_SHADOW_REPLICATE_WEIGHT` 才生 1 个，场上同时最多 `ROGUELIKE_SHADOW_REPLICATE_CAP` 个。
const ROGUELIKE_REPLICATE_CAP := 4
const ROGUELIKE_SHADOW_REPLICATE_WEIGHT := 5
const ROGUELIKE_SHADOW_REPLICATE_CAP := 1
## 「自我复制」新生单位围着死者散开的半径 m（防叠在同一点）。
const ROGUELIKE_REPLICATE_SPREAD := 1.6
## 「This is SPARTA！」投出标枪后，这一小段不能自己走路（仍可以挨打）。
const ROGUELIKE_SPARTAN_ROOT_MS := 500
## 扇子兵「拦截」：开战这么久之内精准度是满的；再往后线性下降，到截止时刻起不再拦截。
const FAN_INTERCEPT_FULL_MS := 10000
const FAN_INTERCEPT_STOP_MS := 20000

## 有科技可点的兵种（**顺序 = 界面上兵种卡的顺序**，也是 `TYPE_ORDER` 里的顺序）。
const ROGUELIKE_TECH_TYPES := ["sword", "spear", "shortbow", "longbow", "fan", "knight", "catapult", "ballista", "berserker", "flamefist", "lightcav", "sandworm", "musket", "master", "corruptor", "grenadier", "shadow", "doom_eye"]

## 该兵种的科技清单（没有科技的兵种返回空数组）。
func roguelike_tech_list(type_id: String) -> Array:
	return ROGUELIKE_TECH_TABLE.get(type_id, [])

## 取一条科技的定义（找不到返回空字典）。
func roguelike_tech_def(type_id: String, tech_id: String) -> Dictionary:
	for row in roguelike_tech_list(type_id):
		if String(row.get("id", "")) == tech_id:
			return row
	return {}

## 这条科技**本批是否已实现**（未实现的在界面上灰掉，见 `ROGUELIKE_TECH_TABLE` 的说明）。
func roguelike_tech_ready(type_id: String, tech_id: String) -> bool:
	var def := roguelike_tech_def(type_id, tech_id)
	return not def.is_empty() and not bool(def.get("pending", false))

## 科技效果的一句话说明（界面提示用：`tooltip_text` 与面板底部那行提示都读它）。
func roguelike_tech_desc(type_id: String, tech_id: String) -> String:
	var def := roguelike_tech_def(type_id, tech_id)
	if def.is_empty():
		return ""
	var pending := bool(def.get("pending", false))
	var head := "" if not pending else "（第二批实现，暂不可用）"
	match String(def.get("effect", "")):
		"armor":
			var armor_text := "%s每次受伤减少 %d × 兵种等级 点伤害" % [head, int(def["armor_per_level"])]
			if def.has("hp_mult"):
				armor_text += "；生命 +%d%%" % int(round((float(def["hp_mult"]) - 1.0) * 100.0))
			return armor_text
		"defense":
			return "%s生命 +%d%%；攻击额外击退 %d；移速 %+.0f m/s" % [head,
					int(round((float(def["hp_mult"]) - 1.0) * 100.0)), int(def["kb_bonus"]),
					float(def["move_speed_delta"])]
		"rage":
			var rage_text := "%s移速 %+.0f m/s；攻击间隔 ×%.2f" % [head,
					float(def["move_speed_delta"]), float(def["interval_mult"])]
			if def.has("hp_mult"):
				rage_text += "；生命 %+d%%" % int(round((float(def["hp_mult"]) - 1.0) * 100.0))
			if def.has("jump_mult"):
				rage_text += "；最远跳跃 ×%.0f" % float(def["jump_mult"])
			if def.has("damage_mult"):
				rage_text += "；普通攻击 ×%.0f" % float(def["damage_mult"])
			return rage_text
		"mend":
			return "%s每秒恢复最大生命 %0.1f%%；生命 ×%.2f" % [head,
					float(def["heal_ratio"]) * 100.0, float(def["hp_mult"])]
		"bulwark":
			return "%s%.0f m 内连在一起的骑士分摊伤害（先扣护甲，再平分，分出去的那份不再扣护甲）；生命 +%d%%" % [head,
					float(def["link_radius"]), int(round((float(def["hp_mult"]) - 1.0) * 100.0))]
		"holy_strike":
			return "%s普通攻击额外造成半径 %.0f m 的范围伤害，冷却 %d s" % [head,
					float(def["radius"]), int(round(float(def["cooldown_ms"]) / 1000.0))]
		"ember":
			return "%s受到致命伤害后继续战斗 %d s，然后死去；这段时间不会被锁定" % [head,
					int(round(float(def["endure_ms"]) / 1000.0))]
		"destroyer":
			return "%s伤害 ×%.0f；每秒损失最大生命 %d%%" % [head,
					float(def["damage_mult"]), int(round(float(def["self_ratio"]) * 100.0))]
		"acid":
			return "%s死亡后在半径 %.0f m 留下酸液，留到本回合结束：上面的单位（含友方）每秒损失最大生命 %d%%（无来源），受到的伤害 ×%.0f。同一单位不叠加" % [head,
					float(def["radius"]), int(round(float(def["tick_ratio"]) * 100.0)), float(def["vuln_mult"])]
		"damage_amp":
			return "%s普通攻击与自爆伤害 +%d%%" % [head, int(round(float(def["damage_pct"]) * 100.0))]
		"replicate":
			return "%s每杀死一个敌人，按它的权重生出同等级的%s，一次最多 %d 个" % [head,
					profile_name(type_id), ROGUELIKE_REPLICATE_CAP]
		"energy_leech":
			return "%s击杀后回复目标最大生命的 %d%%；超出当前上限的部分加进最大生命" % [head,
					int(round(float(def["hp_ratio"]) * 100.0))]
		"energy_burst":
			return "%s死亡时以自身为中心再炸一次（半径 %.0f m，含友方），伤害等于本场达到过的最大生命" % [head,
					float(def["radius"])]
		"flame_barrier":
			return "%s开战 %d s 后，给 %.0f m 内的友方（含潜地）一层屏障：受到的攻击伤害 ×%.2f，免疫沉默、燃烧和酸液，持续 %d s" % [head,
					int(round(float(def["delay_ms"]) / 1000.0)), float(def["radius"]),
					float(def["damage_taken_mult"]), int(round(float(def["duration_ms"]) / 1000.0))]
		"shadow_guard":
			return "%s触发影袭后 %d s 内，受到的伤害 ×%.1f" % [head,
					int(round(float(def["duration_ms"]) / 1000.0)), float(def["damage_taken_mult"])]
		"revenge":
			return "%s生命降到 50%% 和 0%% 时各袭击一次最近的敌人：伤害为面板基础伤害的 %d%%，半径 %.0f m，不限距离" % [head,
					int(round(float(def["damage_mult"]) * 100.0)), float(def["radius"])]
		"wild_horse":
			return "%s冲锋伤害 ×%.0f，持续时间 ×%.2f" % [head, float(def["damage_mult"]), float(def["duration_mult"])]
		"horse_speed":
			return "%s移速 %+.0f m/s" % [head, float(def["move_speed_delta"])]
		"dismount":
			return "%s死亡时骑手下马，变成同等级的长矛兵，并带上这名轻骑兵的科技和本局已激活的长矛科技" % head
		"control_heal":
			return "%s被这名腐化师策反的单位回满生命" % head
		"multi_beam":
			return "%s同时射出 %d 根射线，优先锁不同的人；每根每跳只叠原腐化的 %d%%，射程 %+.0f m。人不够时多出来的射线也打已经锁定的人" % [head,
					int(def["beam_count"]), int(round(float(def["corrupt_ratio"]) * 100.0)), float(def["range_bonus"])]
		"shelter":
			return "%s以自身为中心带一面半径 %.0f m 的魔法盾，%d × 等级 的血，跟着自己走；每回合开始回满。挡弹规则与道具魔法盾相同" % [head,
					float(def["radius"]), int(def["shield_hp"])]
		"sandstorm":
			return "%s钻出地面时生成半径 %.0f m、持续 %d s 的沙暴：里面所有单位移速 %+d%%；沙虫在里面受到的攻击伤害 ×%.1f" % [head,
					float(def["radius"]), int(round(float(def["duration_ms"]) / 1000.0)),
					int(round(float(def["move_pct"]) * 100.0)), float(def["damage_taken_mult"])]
		"burrow_mend":
			return "%s在地下时每秒恢复最大生命的 %.0f%%" % [head, float(def["heal_ratio"]) * 100.0]
		"broodmother":
			return "%s钻出地面时，在身前生出一只同等级的小沙虫：生命与攻击都是一半，带着同一套科技，吃沙暴减伤，自己不放沙暴" % head
		"ambush":
			return "%s钻出地面后的第一下攻击 ×%.0f，攻击范围 +%.0f m" % [head,
					float(def["damage_mult"]), float(def["range_bonus"])]
		"deflect_up":
			return "%s反弹出去的投射物最远再飞 %.0f m，一个冷却周期里最多弹 %d 发" % [head,
					float(def["flight_range"]), int(def["per_cooldown"])]
		"afterimage":
			return "%s后撤时在原处留下一个三分之一血量的影分身，不能后撤、冲刺、居合，最多 %d s" % [head,
					int(round(float(def["duration_ms"]) / 1000.0))]
		"sidestep":
			return "%s高级偏折正在冷却时，可以闪过一发远程投射物，冷却 %d s" % [head,
					int(round(float(def["cooldown_ms"]) / 1000.0))]
		"riposte":
			return "%s格挡一次近战攻击，并立刻对攻击者造成 %d 倍伤害，冷却 %d s" % [head,
					int(def["damage_mult"]), int(round(float(def["cooldown_ms"]) / 1000.0))]
		"thunder_breath":
			return "%s居合斩的判定宽度 ×%.0f，伤害 ×%.0f" % [head,
					float(def["width_mult"]), float(def["damage_mult"])]
		"leech":
			return "%s造成的伤害有 %.0f%% 回复自己" % [head, float(def["heal_ratio"]) * 100.0]
		"energy_scatter":
			return "%s同时射出 %d 根射线，优先锁不同的人；每根造成 %.0f%% 的伤害，射程 %+.0f m" % [head,
					int(def["beam_count"]), float(def["damage_ratio"]) * 100.0, float(def["range_bonus"])]
		"summon_grenadier":
			return "%s开战就召唤 %d 个与自己同等级的玉面手雷王，之后每 %d s 再召一次" % [head,
					int(def["count"]), int(round(float(def["interval_ms"]) / 1000.0))]
		"range":
			return "%s射程 +%.0f m" % [head, float(def["range_bonus"])]
		"elite":
			var per_level := float(def["range_per_level"])
			var per_text := "%d" % int(per_level) if is_equal_approx(per_level, floor(per_level)) else "%.1f" % per_level
			return "%s每 1 级：伤害 +%d%%、生命 +%d%%、射程 +%s m（向下取整）" % [head,
					int(round(float(def["damage_per_level"]) * 100.0)),
					int(round(float(def["hp_per_level"]) * 100.0)),
					per_text]
		"magic_shield":
			return "%s获得一层等于最大生命的护盾（受伤先扣盾，且**打不穿**：单次伤害不会溢出到生命）" % head
		"ignite":
			return "%s攻击点燃目标：每秒损失最大生命 %d%%，持续 %d s（只刷新、取最高）" % [head,
					int(round(float(def["burn_ratio_per_sec"]) * 100.0)),
					int(round(float(def["burn_ms"]) / 1000.0))]
		"block_ranged":
			return "%s攻击时也能格挡小型投射物，并能格挡火枪子弹" % head
		"sword_saint":
			return "%s每个剑盾兵小队里有一位剑圣：生命 ×%.1f、攻击 ×%.1f、射程 ×%.1f；旋风斩打范围内所有敌人；免疫击退" % [
					head, float(def["hp_mult"]), float(def["damage_mult"]), float(def["range_mult"])]
		"spartan":
			return "%s所有矛兵手持月牙盾，能挡小型投射物（挡不了子弹，攻击时不能格挡）；每个矛兵**每回合一发**投矛：射程 %.0f m、伤害 ×%.1f。普通盾挡不住，点了「高级格挡」的剑盾兵能挡，武士大师能弹反" % [
					head, float(def["throw_range"]), float(def["throw_damage_mult"])]
		"gale":
			return "%s击退数值 +%d" % [head, int(def["kb_bonus"])]
		"intercept":
			return "%s敌方投射物一进入 %.0f m 就用普通攻击打下来：弓箭 1 下、子弹和投矛 2 下、弩箭和石弹 5 下。开战 %d s 内打得中，之后越来越容易打空，%d s 起不再拦截。同一发只派刚够打下来的人" % [
					head, float(def["range"]),
					int(FAN_INTERCEPT_FULL_MS / 1000), int(FAN_INTERCEPT_STOP_MS / 1000)]
		"explosive":
			return "%s伤害 −%d%%；无论打中、打空还是被盾牌挡住，都会对落点周围 %.0f m 内的敌人造成这一发伤害的一半（溅射无视盾牌；主箭被挡住的人不吃直击，但吃这一圈；弹反当时不炸，弹回去射中了人才炸）" % [head,
					int(round((1.0 - float(def["damage_mult"])) * 100.0)), float(def["radius"])]
		"scatter":
			return "%s一次扔出 %d 颗较小的石头，弹道略有偏差；每颗伤害 ×%.1f，不眩晕、不击退" % [head,
					int(def["count"]), float(def["damage_mult"])]
		"rapid":
			var rapid_text := "%s攻击间隔 ×%.2f" % [head, float(def["interval_mult"])]
			if def.has("range_bonus"):
				rapid_text += "；射程 %+.0f m" % float(def["range_bonus"])
			if def.has("damage_reduction"):
				rapid_text += "；攻击伤害减少 %d%%" % int(round(float(def["damage_reduction"]) * 100.0))
			elif def.has("damage_mult"):
				rapid_text += "；伤害 ×%.2f" % float(def["damage_mult"])
			if def.has("kb_mult"):
				rapid_text += "；击退 ×%.2f" % float(def["kb_mult"])
			return rapid_text
		"siege":
			return "%s射程 +%.0f m，但打不到自身 %.0f m 以内的单位" % [head,
					float(def["range_bonus"]), float(def["min_range"])]
		"fireball":
			return "%s石弹变成火球，溅射范围内的地面燃烧 %d 秒：上面的单位（含友方）每秒受到 %d 点固定伤害，同一单位不叠加" % [head,
					int(UNIT_FIRE_DURATION_MS / 1000), int(def["tick_damage"])]
		"silence":
			return "%s命中的单位沉默 %d s（含 boss）：身上的科技暂时失效，移速 −%d%%" % [head,
					int(round(float(def["duration_ms"]) / 1000.0)),
					int(round((1.0 - float(def["move_mult"])) * 100.0))]
		"assault":
			return "%s生命 ×%.0f，移速 +%.0f m/s；攻击变为半径 %.0f m 的群伤（击退只打直击），射程 %+.0f m" % [head,
					float(def["hp_mult"]), float(def["move_speed_delta"]),
					float(def["aoe_radius"]), float(def["range_bonus"])]
		"scavenger":
			return "%s清掉自身 %.0f m 内的地面效果（酸液，以及以后的燃烧地面、减速油）" % [head, float(def["radius"])]
	return head


## 肉鸽能买的全部兵种 = 竞猜配平池（**排除沙盒专属**的召唤石柱 —— 它权重 999、是沙盒的"建筑"）。
## **配平池**：竞猜模式允许抽到的兵种（= `TYPE_ORDER` − 沙盒专属 − 肉鸽专属）。
## ⚠️ 这是"哪些兵种允许进竞猜"的**唯一出处**：`_random_composition()` 与调试工具都读它 ——
## 以后再加"不属于任何池子"的实体（`is_sandbox_only()` / `is_roguelike_only()`），只要改这一处。
## ⚠️ **2026-09-26 经用户裁决改名**：`balance_types()` → **`balance_pool()`** ——
## 本项目"一池子候选"这一族统一以 `_pool` 结尾（`summon_pool()` / `roguelike_starter_pool()`），
## 旧名与它们不同族（见本批 `08_naming.md` 审计）。
func balance_pool() -> Array:
	var out: Array = []
	for type_id in TYPE_ORDER:
		if not is_sandbox_only(String(type_id)) and not is_roguelike_only(String(type_id)):
			out.append(String(type_id))
	return out

## 肉鸽能买的全部兵种 —— **与配平池是同一份名单**（两份都排除"沙盒专属"与"肉鸽专属"），
## 所以直接转调 `balance_pool()`：口径只有一处，不会有哪一天两边走偏。
func roguelike_buyable_types() -> Array:
	return balance_pool()

## 初始四选一的抽签池 = 权重落在 `ROGUELIKE_START_WEIGHTS` 里的兵种。
## 扇子兵「拦截」打掉这一发要几下普通攻击。0 = 这种投射物不拦截。
func fan_intercept_hits(kind: String) -> int:
	match kind:
		"arrow", "shortbow_arrow", "longbow_arrow":
			return 1
		"musket_bullet", "spear":
			return 2
		"bolt", "stone":
			return 5
		_:
			return 0

func roguelike_starter_pool() -> Array:
	var out: Array = []
	for type_id in roguelike_buyable_types():
		if ROGUELIKE_START_WEIGHTS.has(int(PROFILES[type_id]["weight"])):
			out.append(type_id)
	return out

## 摇出 `ROGUELIKE_START_CHOICE_COUNT` 个**两两不同**的初始选择（每个选择 = 抽签池里两个不同的兵种）。
## ⚠️ 用**调用方传进来的 rng**（同一局可复现），不碰全局随机源；⚠️ `["a","b"]` 与 `["b","a"]` 算同一个选择。
func roguelike_make_starter_choices(rng: RandomNumberGenerator) -> Array:
	var pool := roguelike_starter_pool()
	var seen := {}
	var choices: Array = []
	var guard := 0
	while choices.size() < ROGUELIKE_START_CHOICE_COUNT and guard < 200 and pool.size() >= 2:
		guard += 1
		var a: String = String(pool[rng.randi_range(0, pool.size() - 1)])
		var b: String = String(pool[rng.randi_range(0, pool.size() - 1)])
		if a == b:
			continue
		var key := "%s|%s" % ([a, b] if a < b else [b, a])
		if seen.has(key):
			continue
		seen[key] = true
		choices.append([a, b])
	return choices

# ---------------------------------------------------------------- 队伍生成
## 生成两支"总权重相同（允许 `PAIR_WEIGHT_TOLERANCE` = 1 的偏差）"的队伍。
## 配平（2026-09-19 用户要求**全随机**）：不用评分挑对手，只保证四条硬规则——
##   ① 双方总权重之差 ≤ 1（I-20，2026-09-19 由"恒等"放宽）；② 每队总权重与本轮预算的偏差也 ≤ 1；
##   ③ 双方兵种种数相同（I-28）；④ **双方兵种不重叠**（同一兵种只能出现在一方，2026-09-19 新增）。
## A、B 两队**都在重抽循环里重抽**：原先 A 只抽一次且在循环外，A 一旦偏差过大，
## B 无论抽多少次都无法让整对成立 ⇒ `PAIR_RETRY_LIMIT` 次必然全败，最后落到"允许重叠"的兜底上。
## 上限 `PAIR_RETRY_LIMIT` 次；实在抽不到（理论上极罕见）退化为权重放宽并打印警告。
## ⚠️ `_score()` / `_fingerprint()` 保留：前者现在只服务于 `debug_balance_stats` 的 ① 配平质量
##（报告"随机配平实际差多少"，不再是优化目标）。
func make_match(round_index: int = 1, rng: RandomNumberGenerator = null) -> Array:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var total := total_weight_for_round(round_index)
	## 本轮的**种数口径**（2026-09-25 第七轮）：`exact > 0` = "正好这么多"（第 1~4 轮），
	## 否则沿用既有口径"≤ `MAX_KINDS_PER_TEAM`"（第 5 轮起）。抽签上限一律取 `kind_cap`。
	var exact := exact_kinds_for_round(round_index)
	var kind_cap := kind_cap_for_round(round_index)
	var relaxed: Array = []
	for _i in PAIR_RETRY_LIMIT:
		var base := _random_composition(total, r, [], kind_cap)
		var base_weight := roster_weight(_units_of(base))
		if absi(base_weight - total) > PAIR_WEIGHT_TOLERANCE:
			continue
		var base_kinds := _kind_count(base)
		if exact > 0 and base_kinds != exact:
			continue
		var banned := _types_of(base)
		var other := _random_composition(total, r, banned, kind_cap)
		if _kind_count(other) != base_kinds:
			continue
		if not _is_disjoint(other, banned):
			continue
		var other_weight := roster_weight(_units_of(other))
		if absi(other_weight - total) > PAIR_WEIGHT_TOLERANCE:
			continue
		if absi(other_weight - base_weight) > PAIR_WEIGHT_TOLERANCE:
			if relaxed.is_empty():
				relaxed = [_units_of(base), _units_of(other)]
			continue
		return [_units_of(base), _units_of(other)]
	push_warning("[配平] 第 %d 轮在 %d 次重抽内没找到总权重偏差 ≤ %d 的阵容，已放宽权重"
		% [round_index, PAIR_RETRY_LIMIT, PAIR_WEIGHT_TOLERANCE])
	if relaxed.is_empty():
		relaxed = [_units_of(_random_composition(total, r, [], kind_cap)),
				_units_of(_random_composition(total, r, [], kind_cap))]
		push_warning("[配平] 第 %d 轮连'种数相同且不重叠'的候选都没抽到，已退化为允许重叠" % round_index)
	return relaxed

## 该轮每队**正好**几种兵；返回 **0 = 不设死**（第 5 轮起沿用"≤ `MAX_KINDS_PER_TEAM`"）。
## 出处只有 `EXACT_KINDS_BY_ROUND` 一张表，`make_match()` 与 `kind_cap_for_round()` 都读它。
func exact_kinds_for_round(round_index: int) -> int:
	if round_index >= 1 and round_index <= EXACT_KINDS_BY_ROUND.size():
		return int(EXACT_KINDS_BY_ROUND[round_index - 1])
	return 0

## 该轮抽签的**种数上限**（`_random_composition()` 的 `kind_cap` 实参）。
func kind_cap_for_round(round_index: int) -> int:
	var exact := exact_kinds_for_round(round_index)
	return exact if exact > 0 else MAX_KINDS_PER_TEAM

## 去重后的兵种数（2026-09-19 新规则用：每队 ≤ `MAX_KINDS_PER_TEAM` 种，且双方种数相等）
func _kind_count(counts: Dictionary) -> int:
	var n := 0
	for type_id in counts:
		if int(counts[type_id]) > 0:
			n += 1
	return n

## 该阵容用到的兵种列表（"双方不重叠"判定与抽签排除都用它）
func _types_of(counts: Dictionary) -> Array:
	var out: Array = []
	for type_id in counts:
		if int(counts[type_id]) > 0:
			out.append(type_id)
	return out

## 阵容是否完全不含 `banned` 里的兵种
func _is_disjoint(counts: Dictionary, banned: Array) -> bool:
	for type_id in banned:
		if int(counts.get(type_id, 0)) > 0:
			return false
	return true

## 随机生成一个"权重和 = total、兵种数 ≤ `kind_cap`、且不含 `banned` 里兵种"的阵容。
## 抽签单位是"权重点"（I-27 放开权重后不再等于人数）；一旦已经用满 `kind_cap` 种，
## 后续只允许从这几种里继续抽（2026-09-19 用户新规则；2026-09-25 第七轮起 `kind_cap` 按轮次给：
## 第 1~2 轮 = 1、第 3~4 轮 = 2、第 5 轮起 = `MAX_KINDS_PER_TEAM`，见 `kind_cap_for_round()`）。
## ⚠️ **沙盒专属兵种永不进竞猜池**（`is_sandbox_only()`）：召唤石柱的权重 999 若混进来，
## 会当场破坏不变量 I-20（两队总权重一致）—— 它只在沙盒模式里由玩家摆放（用户口径"仅限沙盒模式"）。
func _random_composition(total: int, r: RandomNumberGenerator, banned: Array = [],
		kind_cap: int = MAX_KINDS_PER_TEAM) -> Dictionary:
	var counts := {}
	for type_id in TYPE_ORDER:
		counts[type_id] = 0
	var budget := total
	while true:
		var pickable: Array = []
		var kinds := _kind_count(counts)
		for type_id in TYPE_ORDER:
			if banned.has(type_id) or is_sandbox_only(String(type_id)) or is_roguelike_only(String(type_id)):
				continue
			if int(PROFILES[type_id]["weight"]) > budget:
				continue
			## 已经满 `kind_cap` 种时，只从"本轮已经抽过的兵种"里继续抽
			if kinds >= kind_cap and int(counts[type_id]) == 0:
				continue
			## boss 每队**最多一个**（2026-09-19 用户："免疫眩晕且最多在一队中出现一个"）。
			## ⚠️ 权重 25 本身就把它挡在前三轮之外（预算 10 / 15 / 20 < 25），这里只负责"不重复"。
			if is_boss(type_id) and int(counts[type_id]) >= 1:
				continue
			pickable.append(type_id)
		if pickable.is_empty():
			break
		var pick: String = pickable[r.randi_range(0, pickable.size() - 1)]
		counts[pick] = int(counts[pick]) + 1
		budget -= int(PROFILES[pick]["weight"])
	return counts

func _fingerprint(counts: Dictionary) -> String:
	var parts: Array = []
	for type_id in TYPE_ORDER:
		parts.append("%s=%d" % [type_id, int(counts[type_id])])
	return ",".join(parts)

## 阵容战力评分：血量 + 远程 DPS×2 + 近战 DPS×1.4（仅用于配平，不展示给玩家）
func _score(counts: Dictionary) -> float:
	var total := 0.0
	for type_id in TYPE_ORDER:
		var n: int = int(counts[type_id])
		if n <= 0:
			continue
		var p: Dictionary = PROFILES[type_id]
		var hp: float = float(p["hp"]) * HIT_HP_MULT * float(n)
		var dps: float = float(p["damage"]) * float(p["attack_speed"]) * float(n)
		total += hp + (dps * 2.0 if bool(p["is_ranged"]) else dps * 1.4)
	return total

func _units_of(comp: Dictionary) -> Array:
	var units: Array = []
	for type_id in TYPE_ORDER:
		for _i in range(0, int(comp[type_id])):
			units.append(type_id)
	units.shuffle()
	return units

func roster_weight(units: Array) -> int:
	var total := 0
	for type_id in units:
		total += int(PROFILES[type_id]["weight"])
	return total

func roster_text(units: Array) -> String:
	var counts := {}
	for type_id in units:
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var parts: Array = []
	for type_id in TYPE_ORDER:
		if counts.has(type_id):
			parts.append("%s×%d" % [profile_name(type_id), counts[type_id]])
	return " · ".join(parts) if not parts.is_empty() else "（空）"

func roster_cost_breakdown(units: Array) -> String:
	var counts := {}
	for type_id in units:
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var parts: Array = []
	for type_id in TYPE_ORDER:
		if counts.has(type_id):
			parts.append("%s×%d(%d)" % [profile_name(type_id), counts[type_id], int(PROFILES[type_id]["weight"])])
	return " + ".join(parts)

# ---------------------------------------------------------------- 出生点布局
## 在**己方后半段**成簇刷新：同兵种聚在一个簇里，不同兵种之间保持最小间距，
## 但簇半径足够大，允许其他兵种穿插进来（用户要求，见 99_decisions 后续同步）。
## 返回与 units 一一对应的局部坐标数组（x 为对阵轴，z 为横轴）。
func make_spawn_layout(units: Array, team: int, rng: RandomNumberGenerator = null) -> Array:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	## 出生侧来自 `TEAM_META`（不变量 I-35）；这里不再自己判 team == 0。
	var sign_x := team_spawn_sign(team)
	var near := ARENA_HALF_X * SPAWN_RANGE_NEAR * sign_x
	var far := ARENA_HALF_X * SPAWN_RANGE_FAR * sign_x
	var x_min := minf(near, far)
	var x_max := maxf(near, far)

	# 每种兵一个簇心；同兵种允许两个簇心（人数多时自动多开一簇）
	var centers: Array = []
	for type_id in TYPE_ORDER:
		var wanted := 2 if _count_of(units, type_id) >= 10 else 1
		for _i in wanted:
			var point := _sample_center(r, x_min, x_max, centers, type_id)
			centers.append({"type_id": type_id, "pos": point})

	var out: Array = []
	var placed: Array = []
	for type_id in units:
		var spot := _sample_offset(r, String(type_id), centers, placed)
		placed.append({"type_id": String(type_id), "pos": spot})
		out.append(spot)
	return out

## 两个兵种之间的**出生最小间距**（2026-09-19）：人形仍是 `SPAWN_MIN_GAP`（1.0 m，几何约束 G-02），
## 巨物按"两者判定半径之和"自动拉开 ⇒ 出生时不会互相穿插（否则引擎会在开局把它们弹开）。
func spawn_gap_between(a: String, b: String) -> float:
	return maxf(SPAWN_MIN_GAP, body_radius(a) + body_radius(b))

func _count_of(units: Array, type_id: String) -> int:
	var n := 0
	for item in units:
		if String(item) == type_id:
			n += 1
	return n

## 簇心采样。⚠️ 2026-09-19 用户报告"有时候会在一瞬间有很多兵都往同一个方向去"：
## 根因就是这里——簇心间距一直是**固定** `SPAWN_MIN_SEPARATION`（4.0 m），而判定体放大之后
## "投石车（2.40）+ 弩车（2.88）= 5.28 m"这类组合**光半径和就超过 4.0** ⇒ 两个兵种的人一出生
## 就大面积互相穿插，引擎的穿透修正 + 动量传递会把一群人朝同一个方向弹开（也可能触发集体"卡住自救"）。
## 现在按**双方判定半径之和 + 1 m 余量**取大值：人形之间仍是 4.0（半径 0.38×2 + 1 = 1.76 < 4）⇒ 行为不变。
func _center_gap_between(a: String, b: String) -> float:
	return maxf(SPAWN_MIN_SEPARATION, body_radius(a) + body_radius(b) + 1.0)

func _sample_center(r: RandomNumberGenerator, x_min: float, x_max: float, taken: Array,
		type_id: String) -> Vector3:
	var fallback := Vector3(r.randf_range(x_min, x_max), 0.0, r.randf_range(-ARENA_HALF_Z * 0.85, ARENA_HALF_Z * 0.85))
	for _try in SPAWN_CLUSTER_TRIES:
		var candidate := Vector3(r.randf_range(x_min, x_max), 0.0, r.randf_range(-ARENA_HALF_Z * 0.85, ARENA_HALF_Z * 0.85))
		var ok := true
		for entry in taken:
			if candidate.distance_to(entry["pos"]) < _center_gap_between(type_id, String(entry["type_id"])):
				ok = false
				break
		if ok:
			return candidate
	return fallback

func _sample_offset(r: RandomNumberGenerator, type_id: String, centers: Array, placed: Array) -> Vector3:
	var anchor := Vector3.ZERO
	var found := false
	for entry in centers:
		if String(entry["type_id"]) == type_id:
			anchor = entry["pos"]
			found = true
			break
	if not found:
		anchor = Vector3(r.randf_range(-ARENA_HALF_X * 0.8, ARENA_HALF_X * 0.8), 0.0, 0.0)
	var fallback := anchor
	## 簇内散布半径：人形仍是 `SPAWN_CLUSTER_RADIUS`（3.4 m）；**巨物按判定半径放大**
	##（2026-09-19 随"判定体对齐视觉"一起做）——弩车的判定半径就有 2.88 m，5 台挤在 3.4 m 的簇里
	## 根本放不下，采样会失败并退回"全部叠在簇心"。
	var spread := maxf(SPAWN_CLUSTER_RADIUS, body_radius(type_id) * 2.5)
	for _try in SPAWN_CLUSTER_TRIES:
		var angle := r.randf_range(0.0, TAU)
		var radius := sqrt(r.randf()) * spread
		# 沿 Z 拉伸成椭圆簇：屏幕横向 = 世界 Z 轴，所以这样看起来是"一横排"
		var candidate := anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * SPAWN_CLUSTER_ASPECT)
		candidate.x = clampf(candidate.x, -ARENA_HALF_X * 0.96, ARENA_HALF_X * 0.96)
		candidate.z = clampf(candidate.z, -ARENA_HALF_Z * 0.92, ARENA_HALF_Z * 0.92)
		var ok := true
		## ⚠️ 2026-09-19：`placed` 从"纯坐标"改成"带兵种的字典"，因为间距要按**双方判定体大小**算
		##（人形仍是 1.0 m；巨物自动拉开，见 `spawn_gap_between()`）。
		for other in placed:
			if candidate.distance_to(other["pos"]) < spawn_gap_between(type_id, String(other["type_id"])):
				ok = false
				break
		if ok:
			return candidate
	return fallback
