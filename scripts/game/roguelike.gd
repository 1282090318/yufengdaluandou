class_name Roguelike
extends Node
## 肉鸽模式（2026-09-26 新增）：**10 个回合，每回合先领补给、再用补给买兵 / 买增益抵挡敌方进攻**。
##
## 依据（用户 2026-09-26 口径，逐条对应）：
##   · "一共10个回合，每个回合开始时会获得一定的补给" ⇒ `ROGUELIKE_ROUND_COUNT` + 回合开始的收入；
##   · "补给：第一回合开始时获得补给，此后每回合多 10" ⇒ 现行 `ROGUELIKE_SUPPLY_START`（25）/ `_STEP`；
##   · "基础血量为200，若未击败敌方，则扣除敌方存活兵种总权重的血量。血量降到0及以下则失败" ⇒ `hp` / `_settle_round()`。
##
## ⚠️ **本文件按"一步一步来"分步落地：第一块（骨架 + 经济记账）与
## 第二块（商店 / 解锁 / 初始四选一 / 2.0 m 场地格子 / 六档"队"形）都已落地**，
## **只剩敌人**（用户 2026-09-26："先不做，后面再说"）。
## 已经有的：进入模式 / 10 回合状态机 / 补给收入与余额 / 血量记账 / 结果与失败判定 / 暂停恢复 /
##   初始四选一（选定后每个兵种白送两队）/ 买"队"与解锁 / 场地格子与自动落位 / 探针。
## **还没有的**：敌人 ⇒ `enemy_weight()` 恒为 0、扣血也恒为 0（路径本身已验，见文件尾探针）。
##
## ⚠️ **第二块的口径**（用户 2026-09-26 第二轮问答，逐条落在 `GameConfig` 里）：
##   · 买一次 = **一整队**，价格 = 人数 × 权重（补给 : 权重 = 1 : 1）；
##   · **每回合最多买 2 队**（用户改口径：不是"总权重 ≤ 2 × 补给"）；
##   · 解锁价 = ⌊**全队总权重** ÷ 2⌋、每回合最多解锁 1 个；
##   · **买下的队自动落位**（用户选定）—— 从己方（西）半场的底线往前码，玩家只决定"买哪队"。
##
## ⚠️ 与另外两个模式的分界（三条，写代码时别串）：
##   ① **不押注、不判平局、没有兴奋圈与 90 s 时限** —— 与沙盒同一处理：**从不调用 `Arena.start_match()`**，
##      改用 `Arena.start_skirmish()`（只点火、不启赛程）；
##   ② **不受 I-20 / I-28 约束**（用户 2026-09-26 裁决：与沙盒同一条豁免 —— 那两条只描述竞猜模式）；
##   ③ **回合不是"轮次"**：本文件的 `round_index` 是肉鸽的回合，与 `Game.round_index`（押注轮次）只是同名同义、
##      各自独立（不变量 I-22 那条"最多 10 轮"描述的是竞猜模式）。
##
## ⚠️ 暂停 / 恢复沿用另外两个模式那一套（`MatchPause`）：树暂停**不会停表**，而本模式的计时（回合收入、
## 死亡演出、单位冷却）全是绝对毫秒（不变量 I-13）⇒ 恢复时必须把暂停时长整体从这些时刻里扣掉。

signal phase_changed(phase: String)      ## 相位跳变（本模式**自己的**信号，不上 `Events` 总线）

enum Phase { PREPARE, FIGHTING, ROUND_RESULT, GAME_OVER }
## ⚠️ **2026-09-26 经用户裁决改名**：战斗那一档 `BATTLE` → **`FIGHTING`**（`phase_name()` 同步
## `"battle"` → `"fighting"`）—— 另外两个模式的同名成员逐字都是 `FIGHTING`，
## §1.4「同一概念全局同名」不允许这里独用一个词（见 `08_naming.md` 本批审计与 `99_decisions.md` 同日条目）。
## 四个相位的语义（用户口径的"每个回合：领补给 → 买兵 → 抵挡进攻 → 结算"）：
##   `PREPARE`      回合开始：**先把本回合的收入打进补给**，然后等玩家花钱 / 布阵（购买与解锁是下一步的事）
##   `FIGHTING`     敌我交战。⚠️ **本步是空相位**：敌人还没做 ⇒ 进入的下一物理帧就判定"敌方全灭"、直接结算
##   `ROUND_RESULT` 本回合结果（扣了多少血 / 还剩多少）—— 等玩家点「下一回合」
##   `GAME_OVER`    打满 10 回合（胜）或血量 ≤ 0（败）

var phase: int = Phase.PREPARE
var round_index: int = 1                 ## 当前回合（1 起）
var supply: int = 0                      ## **当前剩余**补给（回合收入会加进来；购买 / 解锁还没做 ⇒ 只增不减）
var income_total: int = 0                ## 本局累计获得的补给（探针与结算用；收入序列 25 / 35 / … / 115 ⇒ 700）
var hp: int = GameConfig.ROGUELIKE_HP_MAX
var hp_max: int = GameConfig.ROGUELIKE_HP_MAX
var log_entries: Array = []              ## 每回合一条结算记录（与 `Game.log_entries` 同义：本模式的流水）
var result: Dictionary = {}              ## 上一回合 / 整局的结算（HUD 读它显示）
var summary: Dictionary = {}             ## 整局结算（`GAME_OVER` 时填）
## 这一回合刚进入准备时的局面。保存时写这一份，不写后来买下的兵和打过的仗。
var _round_opening: Dictionary = {}

var arena: Arena = null
var camera_rig: CameraRig = null

## 暂停开始时刻（0 = 没在暂停），与 `Game` / `Sandbox` 同义（见文件头最后一条 ⚠️）。
var _pause_from_ms: int = 0

# ---------------------------------------------------------------- 第二块的状态（2026-09-26）
var starter_choices: Array = []          ## 初始四选一的四个选项（每个 = 两个兵种 ID）
var starter_chosen: bool = false         ## 选过起手部队没有（没选之前界面只显示四选一浮层）
var difficulty: String = GameConfig.ROGUELIKE_DIFFICULTY_DEFAULT
var difficulty_chosen: bool = false      ## 进生存后先选难度，选完才刷第 1 回合的敌人、再给起手四选一
var pool: Array = []                     ## **已解锁**的兵种（起手那两个 + 之后花钱解锁的）
var squads: Array = []                   ## 已拥有的"队"：{type_id, weight, units, anchor_col, anchor_row, rotated, bought_round}
var bought_this_round: int = 0           ## 本回合已买几队（上限 `ROGUELIKE_SQUADS_PER_ROUND`）
var unlocked_this_round: int = 0         ## 本回合已解锁几个（上限 `ROGUELIKE_UNLOCK_PER_ROUND`）
var last_message: String = ""            ## 最近一次买卖的结果 / 被拒绝的原因（界面读它显示一行反馈）

## 场地格子的几个表现参数（**纯表现** ⇒ 住本脚本，不进 `GameConfig`，同 `08_naming.md#3.3` 的惯例）。
const GRID_COLOR := Color(0.36, 0.56, 0.78, 0.30)   ## 线色（半透明冷色，压在场地底色上看得清）
const GRID_LIFT := 0.030                             ## 线离地高度 m（**比填充层高**：线永远压在色块上面）
## 格子**填充色**（"被单位占据的格子颜色比可部署的格子深"是用户口径）。
## ⚠️ 颜色一律走**材质**（一层一个色），**不走顶点色**：2026-09-26 实测"三角形 + `ARRAY_COLOR` +
## `vertex_color_use_as_albedo`"这一层在本场景里根本不出画（同一套材质的 `GridLines` 线条层却正常），
## 而"一个材质一个 `albedo_color`"这条老路与线条层逐字同源 ⇒ 照它写。三层 = 三个 draw call，代价可忽略。
const CELL_FREE := Color(0.34, 0.52, 0.74, 0.07)    ## 可部署（很淡，只作提示）
const CELL_TAKEN := Color(0.06, 0.09, 0.16, 0.55)   ## **被占据**（明显更深）
## **2026-09-27 用户口径**："如果兵种能移动位置，则兵种所占格子用更加艳丽的绿色表示，不能移动则用现在
## 兵种所占格子的深绿色表示" ⇒ 被占的格子**分两层**：`_TAKEN`（现在的深色，不能移动的那些）与
## `_TAKEN_MOVABLE`（**能移动的那几队** = 本回合拿到手的，见 `squad_movable()`）—— 一眼看出"哪些还能拖"。
const CELL_TAKEN_MOVABLE := Color(0.22, 0.86, 0.36, 0.55)
const CELL_OK := Color(0.35, 0.85, 0.45, 0.42)      ## 拖动预览：放得下
const CELL_BAD := Color(0.92, 0.26, 0.26, 0.52)     ## 拖动预览：放不下（用户要的"标红"）
const CELL_INSET := 0.06                            ## 每格填充往里缩这么多 m ⇒ 格子线还露得出来
const CELL_LIFT := 0.015                            ## 填充层离地高度 m
## 第七块：两条**布阵带**那几层的色（用户口径里两段权利相反 ⇒ 必须一眼分得开）——
## `_OURS` = 我们能布阵的那段（琥珀）、`_THEIRS` = 只有敌方能用那段（暗红）、
## `_DEAD` = **带子里两边都不能布阵的那段**（中性灰；2026-09-27 订正后两条带子各 56.25 m，中间留 19 格死区）。
const CELL_ZONE_OURS := Color(0.95, 0.72, 0.25, 0.13)
const CELL_ZONE_THEIRS := Color(0.86, 0.28, 0.28, 0.12)
const CELL_ZONE_DEAD := Color(0.60, 0.64, 0.70, 0.08)
const PREVIEW_LIFT := 0.022                         ## 预览层再高一点 ⇒ 压在占据色上面（红 / 绿看得清）
## 道具拖放预览（**一圈线**，半径 = 这件道具自己的圆）的纯表现参数 —— 颜色同样走材质，不用顶点色：
const PROP_PREVIEW_OK := Color(0.35, 0.95, 0.55, 0.85)    ## 这个落点放得下
const PROP_PREVIEW_BAD := Color(0.95, 0.30, 0.30, 0.95)   ## 放不下（与格子预览的"标红"同一条语言）
const PROP_PREVIEW_LIFT := 0.06                           ## 圈线离地高度 m（压在地面标记之上）
## 移动信标那条路线的纯表现参数（颜色同样走材质）：
const ROUTE_COLOR := Color(0.45, 0.95, 0.85, 0.85)        ## 已就位的路线
const ROUTE_EDIT_COLOR := Color(0.95, 0.85, 0.35, 0.95)   ## 正在画的那条（黄，和成品区分开）
const ROUTE_LIFT := 0.05                                  ## 路线线离地高度 m
## 陷阱那圈警示环的两档颜色（**纯表现**）：没炸过 = 红橙（`_build_prop_node()` 里写死的那一档）、
## 炸过 = 绿（2026-09-27 用户："陷阱触发后边框由红色变为绿色"）。
const TRAP_RING_DONE := Color(0.30, 0.88, 0.42, 0.95)

var _rng := RandomNumberGenerator.new()
var _occupied := {}                      ## 已占的格子：`"col,row" -> 队序号`（`-1` = 建筑占着，如指挥所）
var _grid: Node3D = null                 ## 场地格子（**本模式自建**、零碰撞；只在 `PREPARE` 可见）
var _cells: MeshInstance3D = null        ## 格子的**填充层**（可部署的格子，很淡）
var _cells_taken: MeshInstance3D = null  ## 格子的**另一层填充**（被单位 / 建筑占据的格子，明显更深）
var _cells_taken_movable: MeshInstance3D = null  ## 2026-09-27：**能移动的那几队**占的格子（艳丽绿，见 `CELL_TAKEN_MOVABLE`）
var _preview: MeshInstance3D = null      ## 拖动时的**预览层**（候选那几格：绿 = 放得下、红 = 放不下）
var _cells_zone_ours: MeshInstance3D = null    ## 第七块：**我们能布阵**的那段带子（琥珀）
var _cells_zone_theirs: MeshInstance3D = null  ## 第七块：只有敌方能用那段带子（暗红）
var _cells_zone_dead: MeshInstance3D = null    ## 第七块：带子里**两边都不能布阵**那段（中性灰）

# ---------------------------------------------------------------- 第四块的状态（2026-09-26）
var selected_squad: int = -1             ## 界面选中的是第几队（`-1` = 没选；与 `selected_post` **互斥**）
var _hold_waiting: bool = false
var choice_hidden: bool = false
var choice_notice: String = ""
var _choice_notice_ms: int = 0
var _range_hint: RangeHint = null
var _drag_squad: int = -1                ## 正在拖动的是第几队（`-1` = 没在拖）
var _drag_press := Vector2.ZERO          ## 按下时的屏幕坐标（用来判"点选"还是"拖动"）
var _dragging: bool = false              ## 是否已经越过拖动阈值
var _drag_anchor := Vector2i(-1, -1)     ## 光标下的**候选锚点**（越界/放不下时为 `(-1,-1)`）
var _drag_valid: bool = false            ## 候选位置能不能放
var _drag_rotated: bool = false          ## 拖动中待定的旋转（**松手放得下才写回队信息** —— 见 `_rotate_dragging()`）
var _press_squad: int = -1               ## 这一次按下落在哪一队上（**含拖不动的队** ⇒ 拖它时能给出原因）

# ---------------------------------------------------------------- 第五块的道具状态（2026-09-26）
## 陷阱 / 魔法盾（用户："完成陷阱和魔法盾"）—— ⚠️ 两件都是**肉鸽自己的场地道具**：
## 不进 `PROFILES`、不算兵种、**不占格子**（魔法盾用户明说"不占用格子"，陷阱同处理），
## 所以它们既不在 `arena.units` 里、也不可能被索敌锁定（用户："不会被主动锁定"是**结构上**成立的）。
var props: Array = []                    ## 每件道具：`{id, kind, pos, hp, hp_max, armed_ms, target, triggered, node}`
var _next_prop_id: int = 1               ## 道具编号（单调递增）：挡弹登记靠它回认，**不靠数组下标**（下标会随移除漂移）
var _prop_root: Node3D = null            ## 所有道具外观的父节点（一局一清，`_clear_props()` 靠它一把收干净）
var _placing: String = ""                ## 正在拖放的道具 kind（`""` = 没在放）
var _place_pos := Vector3.ZERO           ## 光标下的候选落点（世界坐标）
var _place_on_field: bool = false        ## 光标现在**落在场地平面**上吗（`false` = 移到界面/天上了）
var _place_valid: bool = false           ## 这个落点能不能放
var _place_press_seen: bool = false      ## 拖放期间**见过左键按着**吗（见 `_tick_placing()`：没见过就不把"没按"当松手）
var _prop_preview: MeshInstance3D = null ## 拖放预览（一圈线：绿 = 能放 / 红 = 不能；半径 = 该道具自己的圆）
## 拖动'幽灵'（2026-09-26 **第六块**补：用户"拖动时兵种的'幽灵'跟着鼠标"）：
## 拖动时每个槽位一个**半透明盒子**（尺寸取该兵种的体型盒），跟着光标摆在候选格块中心，绿 = 放得下 / 红 = 放不下。
## ⚠️ 盒子只是**表现**：真正的单位在松手前一动不动（见 `_end_press()` 的说明），
## 幽灵给出的是"松手会摆成什么样"的预览。盒子个数跟着被拖那一队的槽位数走（换队时按需增删）。
var _ghost_root: Node3D = null           ## 幽灵的父节点（懒建，局内复用）
var _ghost_boxes: Array = []             ## 每个槽位一个 `MeshInstance3D`
var _ghost_type: String = ""             ## 幽灵当前按哪个兵种的体型盒建的（换队时重建尺寸）
## 移动信标（第六块起；**第七块把"库存"改成"拥有权"**）：拥有权 + 路线编辑状态。
## ⚠️ **库存**是"右方指挥所买来、还没放到场上"的个数（买一个 +1、**放置完成**才 −1）；
## ⚠️ **路线**要两次点击才成立（用户口径），所以在"放下去"和"路线画完"之间必须有一个中间态
## —— `_route_editing` 就是它：指向那个道具在 `props` 里的下标，−1 = 没在定路线。
## 移动信标**拥有权**（2026-09-27 第七块用户裁决："信标不会被锁定，只需要在回合开始时重新部署
##（只要买了信标就能一直免费部署，点击信标的卡片以重新部署）"）⇒ 买一次即**永久拥有**，
## 之后每回合点道具卡**免费**重新部署。⚠️ 旧字段 `_beacon_stock`（"库存次数"口径）**已作废**。
var _beacon_owned: bool = false
## 遣返：买一次永久拥有，每回合用一次。
var _recall_owned: bool = false
var _recall_used: bool = false
var _route_editing: int = -1             ## 正在定路线的信标在 `props` 里的下标（`-1` = 没在定）
var _route_points: Array = []            ## 正在定的路线点（世界坐标；第 0 个 = 信标自己）
var _routes_root: Node3D = null          ## 所有路线折线的父节点（`_rebuild_routes()` 一次全量重建）

## ---- 撤销（2026-09-27 第三轮，用户："新增'撤销'按钮，能够撤销本回合的上一次操作（只能是本回合）……
## 快捷键 ctrl+z，撤销时在屏幕中央显示一行字显示撤销了什么操作"）----
## 实现 = **快照式整体回滚**：在"会改本回合部署状态"的每一次操作**之前**存一份快照，
## Ctrl+Z（或点界面那颗按钮）把整局拉回那一份 —— 覆盖用户列的全部操作（买兵 / 升级 / 移动 /
## 买增益 / 买道具 / 放信标 / 画路线），**不必为每种操作各写一个反向操作**。
## ⚠️ 栈**后进先出**（可连按往回撤），**回合开始时清空**（用户："只能是本回合"）。
## ⚠️ 快照只装**部署阶段能改的东西**；战斗（伤害 / 走位 / 阵亡）不进快照 —— 撤销也只在准备阶段可用。
var _undo_stack: Array = []              ## 快照栈：每项 `{"label": 操作名, "data": 状态字典}`
var _undo_note: String = ""              ## 最近一次撤销的说明（界面拿它在屏幕中央显示一行字）
var _undo_note_ms: int = 0               ## 那一行字的到期时刻（绝对毫秒，I-13）
const UNDO_NOTE_MS := 2600               ## 那一行字显示多久（表现参数 ⇒ 住脚本，不进 `GameConfig`）
const UNDO_STACK_MAX := 40               ## 栈上限（一回合的操作数远小于它；纯防内存）

# ---------------------------------------------------------------- 撤销（2026-09-27 第三轮）
## 在**一次会改本回合部署状态的操作之前**存一份快照。`label` = 那个操作的名字（撤销时显示"撤销：<label>"）。
## ⚠️ 调用点就是"用户能撤销的那些操作"：买兵 / 解锁 / 升级 / 换位 / 买（持续 / 单回合）增益 / 买信标 /
## 放道具 / 画路线 —— 见各处的 `_push_undo()`。
func _push_undo(label: String) -> void:
	if _undo_stack.size() >= UNDO_STACK_MAX:
		_undo_stack.pop_front()
	_undo_stack.append({"label": label, "data": _snapshot_state()})

func _aid_cards_snapshot() -> Array:
	var copy: Array = []
	for card in aid_cards:
		copy.append({
			"uid": int(card.get("uid", 0)),
			"aid_id": String(card.get("aid_id", "")),
			"placed": bool(card.get("placed", false)),
			"pos": Vector3(card.get("pos", Vector3.ZERO)),
			"aim": Vector3(card.get("aim", Vector3.ZERO)),
			"ready_round": int(card.get("ready_round", 1)),
		})
	return copy


func _restore_aid(data: Dictionary) -> void:
	for card in aid_cards:
		var node = card.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	aid_offer = (data.get("aid_offer", []) as Array).duplicate()
	aid_pending = bool(data.get("aid_pending", false))
	aid_income_bonus = int(data.get("aid_income_bonus", 0))
	aid_tech_cut = int(data.get("aid_tech_cut", 0))
	aid_extra_squads = int(data.get("aid_extra_squads", 0))
	aid_shield_mult = float(data.get("aid_shield_mult", 1.0))
	aid_prop_cd_cut = int(data.get("aid_prop_cd_cut", 0))
	aid_flank_half = bool(data.get("aid_flank_half", false))
	aid_elite_level = bool(data.get("aid_elite_level", false))
	aid_cost_control = bool(data.get("aid_cost_control", false))
	aid_speed_add = float(data.get("aid_speed_add", 0.0))
	aid_hp_mult = float(data.get("aid_hp_mult", 1.0))
	aid_damage_mult = float(data.get("aid_damage_mult", 1.0))
	aid_range_add = float(data.get("aid_range_add", 0.0))
	aid_variant = (data.get("aid_variant", {}) as Dictionary).duplicate(true)
	aid_taken = (data.get("aid_taken", {}) as Dictionary).duplicate(true)
	_aid_seq = int(data.get("aid_seq", 1))
	aid_cards.clear()
	for item in data.get("aid_cards", []):
		var snap: Dictionary = item
		aid_cards.append({
			"uid": int(snap.get("uid", 0)),
			"aid_id": String(snap.get("aid_id", "")),
			"placed": bool(snap.get("placed", false)),
			"pos": Vector3(snap.get("pos", Vector3.ZERO)),
			"aim": Vector3(snap.get("aim", Vector3.ZERO)),
			"ready_round": int(snap.get("ready_round", 1)),
			"ran_round": -1,
			"cooled_round": -1,
			"next_ms": 0,
			"node": null,
		})


## 一份**部署状态**的快照（深拷贝到"数字 / 字符串 / 数组 / 字典"这一层，**不含任何活对象引用**）。
## 装的是：补给与欠账 / 队伍列表（含**等级与经验**、锚点、旋转、可动回合、编制数）/ 已解锁池 /
## 两类增益 / 本回合的两个计数 / 信标拥有权 / 全部道具（陷阱 / 魔法盾 / 信标的**路线点**）。
## ⚠️ **不装**场上的单位与指挥所：它们由"队伍列表 + 道具表"完全决定（恢复时按同一套生成函数重建）。
func _snapshot_state() -> Dictionary:
	var squads_copy: Array = []
	for info in squads:
		squads_copy.append((info as Dictionary).duplicate(true))
	var props_copy: Array = []
	for prop in props:
		if String(prop["kind"]) == "aid_ward":
			continue
		props_copy.append({
			"id": int(prop["id"]),
			"kind": String(prop["kind"]),
			"pos": Vector3(prop["pos"]),
			"hp": float(prop.get("hp", 0.0)),
			"hp_max": float(prop.get("hp_max", 0.0)),
			"armed_ms": int(prop.get("armed_ms", 0)),
			"triggered": bool(prop.get("triggered", false)),
			"points": (prop.get("points", []) as Array).duplicate(true),
		})
	return {
		"supply": supply,
		"loan_debt": _loan_debt,
		"squads": squads_copy,
		"pool": pool.duplicate(),
		"buff_levels": buff_levels.duplicate(true),
		"round_buffs": round_buffs.duplicate(true),
		"bought_this_round": bought_this_round,
		"unlocked_this_round": unlocked_this_round,
		"beacon_owned": _beacon_owned,
		"recall_owned": _recall_owned,
		"recall_used": _recall_used,
		"props": props_copy,
		## 兵种科技（2026-09-27 第十二轮）：与"已解锁池"同类 —— 都是玩家花补给买下的**永久状态**
		## ⇒ 必须进快照，否则撤销一步之后科技会留在身上（补给却退回去了）。
		"techs": techs.duplicate(true),
		"aid_offer": aid_offer.duplicate(),
		"aid_pending": aid_pending,
		"aid_income_bonus": aid_income_bonus,
		"aid_tech_cut": aid_tech_cut,
		"aid_extra_squads": aid_extra_squads,
		"aid_shield_mult": aid_shield_mult,
		"aid_prop_cd_cut": aid_prop_cd_cut,
		"aid_flank_half": aid_flank_half,
		"aid_elite_level": aid_elite_level,
		"aid_cost_control": aid_cost_control,
		"aid_speed_add": aid_speed_add,
		"aid_hp_mult": aid_hp_mult,
		"aid_damage_mult": aid_damage_mult,
		"aid_range_add": aid_range_add,
		"aid_variant": aid_variant.duplicate(true),
		"aid_taken": aid_taken.duplicate(true),
		"aid_cards": _aid_cards_snapshot(),
		"aid_seq": _aid_seq,
	}

## 回到某份快照。⚠️ 做法是**重建**而不是"原地改回"：先撤掉场上属于我方队伍的单位与所有道具，
## 再把数值写回、按快照**重新生成**（生成路径与买兵 / 放道具**同一条**）⇒ 等级、加成、落位、拥有权都不会漏。
## ⚠️ **指挥所与敌人不动**（它们不在快照里：指挥所只在回合开始重建，敌人不由玩家操作）。
func _restore_state(data: Dictionary) -> void:
	## ① 清场（我方队伍单位 + 全部道具）
	for unit in arena.units.duplicate():
		var u: Unit3D = null
		if unit != null and is_instance_valid(unit):
			u = unit as Unit3D
		if u == null or u.team != 0 or not u.has_meta("squad_index"):
			continue
		arena.units.erase(u)
		u.queue_free()
	_clear_props()
	_cancel_place()
	_reset_drag()
	## ② 数值回滚
	supply = int(data["supply"])
	_loan_debt = int(data["loan_debt"])
	squads.clear()
	for info in data["squads"]:
		squads.append((info as Dictionary).duplicate(true))
	pool.clear()
	pool.assign(data["pool"])
	buff_levels = (data["buff_levels"] as Dictionary).duplicate(true)
	round_buffs = (data["round_buffs"] as Dictionary).duplicate(true)
	bought_this_round = int(data["bought_this_round"])
	unlocked_this_round = int(data["unlocked_this_round"])
	_beacon_owned = bool(data["beacon_owned"])
	_recall_owned = bool(data.get("recall_owned", false))
	_recall_used = bool(data.get("recall_used", false))
	## 兵种科技：先写回"买没买过"，再靠下面的**重建**让新生成的兵自动带上（出生那一支会推科技）；
	## ⚠️ `data.get("techs", {})` 兜底：快照字段是第十二轮才加的，老快照不会带它。
	techs = (data.get("techs", {}) as Dictionary).duplicate(true)
	## ③ 场上重建：占格账**整体重算**（指挥所先占，再逐队占 + 生成）
	_occupied.clear()
	for team in [0, 1]:
		for post in posts_of_team[team]:
			if post != null and is_instance_valid(post) and (post as Unit3D).alive:
				_reserve_post_cells(post as Unit3D)
	for i in range(squads.size()):
		var info: Dictionary = squads[i]
		_occupy_squad(info, i)
		_spawn_squad(info, i)
	for item in data["props"]:
		var snap: Dictionary = item
		var idx := _spawn_prop(String(snap["kind"]), Vector3(snap["pos"]))
		if idx < 0:
			continue
		var fresh: Dictionary = props[idx]
		fresh["hp"] = float(snap["hp"])
		fresh["hp_max"] = float(snap["hp_max"])
		fresh["armed_ms"] = int(snap["armed_ms"])
		fresh["triggered"] = bool(snap["triggered"])
		fresh["points"] = (snap["points"] as Array).duplicate(true)
	_rebuild_cells()
	_rebuild_routes()
	_sync_arrow_blockers()
	## 兵种科技：重建出来的兵在出生那一支已经带上科技了（`_spawn_one_squad_unit()`），这一行是兜底
	##（例如"我方单位不全来自小队"的将来改动）—— 幂等，代价可忽略。
	apply_all_techs()
	if data.has("aid_cards"):
		_restore_aid(data)
		RoguelikeAid.rehydrate(self)


func _remember_round_opening() -> void:
	if arena == null:
		_round_opening = {}
		return
	var foes: Array = []
	for node in arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive:
			continue
		if unit.team != 1 or String(unit.type_id) == GameConfig.ROGUELIKE_POST_TYPE:
			continue
		if not unit.has_meta("foe_squad_index"):
			continue
		foes.append({
			"type_id": String(unit.type_id),
			"x": unit.global_position.x,
			"z": unit.global_position.z,
			"yaw": unit.rotation.y,
			"level": unit.level,
			"tech_ids": unit.tech_ids(),
			"zone_entered_round": unit.zone_entered_round,
			"squad_index": int(unit.get_meta("foe_squad_index")),
			"slot": int(unit.get_meta("foe_slot")),
		})
	var book: Array = []
	for raw in foe_squads:
		book.append((raw as Dictionary).duplicate(true))
	_round_opening = {
		"round_index": round_index,
		"hp": hp,
		"hp_max": hp_max,
		"income_total": income_total,
		"starter_chosen": starter_chosen,
		"difficulty": difficulty,
		"difficulty_chosen": difficulty_chosen,
		"starter_choices": starter_choices.duplicate(true),
		"log_entries": log_entries.duplicate(true),
		"last_message": last_message,
		"scene_id": arena.battle_scene_id(),
		"state": _snapshot_state(),
		"foes": foes,
		"foe_squads": book,
	}


## 暂停菜单里的「保存并退出」。已经结束的一局只删档。写的是这一回合开始时的局面。
func write_resume() -> void:
	if phase == Phase.GAME_OVER or _round_opening.is_empty():
		MatchSave.erase_roguelike()
		return
	MatchSave.write_roguelike(_round_opening)


## 回到这一回合刚开始、选援助的那一刻。敌人按记下的位置重生，不重新抽。
func restore_opening(data: Dictionary) -> void:
	var state: Dictionary = data.get("state", {})
	if data.is_empty() or arena == null or not state.has("supply"):
		begin()
		return
	arena.settle()
	round_index = int(data.get("round_index", 1))
	hp = int(data.get("hp", GameConfig.ROGUELIKE_HP_MAX))
	hp_max = int(data.get("hp_max", GameConfig.ROGUELIKE_HP_MAX))
	income_total = int(data.get("income_total", 0))
	starter_chosen = bool(data.get("starter_chosen", false))
	if data.has("difficulty"):
		difficulty = GameConfig.roguelike_difficulty_id(String(data.get("difficulty", "")))
	else:
		difficulty = GameConfig.ROGUELIKE_DIFFICULTY_MIRACLE
	difficulty_chosen = bool(data.get("difficulty_chosen", true))
	starter_choices = data.get("starter_choices", [])
	log_entries = data.get("log_entries", [])
	last_message = String(data.get("last_message", ""))
	result = {}
	summary = {}
	selected_post = ""
	selected_squad = -1
	selected_foe_squad = -1
	_undo_stack.clear()
	_undo_note = ""
	_undo_note_ms = 0
	arena.use_battle_scene(String(data.get("scene_id", "")))
	arena.clear_round_buffs()
	if state.has("buff_levels"):
		buff_levels = (state["buff_levels"] as Dictionary).duplicate(true)
	_apply_steady_buff(GameConfig.ROGUELIKE_BUFF_ATTACK)
	_spawn_posts()
	_restore_state(state)
	_spawn_saved_foes(data.get("foes", []), data.get("foe_squads", []))
	phase = Phase.PREPARE
	_build_grid()
	_set_grid_visible(true)
	if camera_rig != null:
		camera_rig.on_roguelike_phase()
	_remember_round_opening()
	_change_state()


func _spawn_saved_foes(rows: Array, book: Array) -> void:
	_clear_enemy_combatants()
	for raw in book:
		if raw is Dictionary:
			foe_squads.append((raw as Dictionary).duplicate(true))
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var type_id := String(row.get("type_id", "sword"))
		var unit := arena.spawn_unit(1, type_id,
				Vector3(float(row.get("x", 0.0)), 0.0, float(row.get("z", 0.0))),
				float(row.get("yaw", 0.0)))
		if unit == null:
			continue
		var slot := int(row.get("slot", 0))
		unit.set_meta("foe_squad_index", int(row.get("squad_index", 0)))
		unit.set_meta("foe_slot", slot)
		unit.set_level(clampi(int(row.get("level", 1)), 1, GameConfig.ROGUELIKE_LEVEL_MAX))
		var active := _techs_from_ids(type_id, row.get("tech_ids", []))
		unit.set_techs(active)
		if slot == 0 and active.has("sword_saint"):
			unit.set_saint(true)
		unit.zone_entered_round = int(row.get("zone_entered_round", round_index))


func _techs_from_ids(type_id: String, ids: Array) -> Dictionary:
	var wanted := {}
	for raw_id in ids:
		wanted[String(raw_id)] = true
	var out := {}
	for row in GameConfig.roguelike_tech_list(type_id):
		if not (row is Dictionary):
			continue
		var tech_id := String((row as Dictionary).get("id", ""))
		if wanted.has(tech_id):
			out[tech_id] = row
	return out


## 撤销上一次操作（界面那颗按钮与 `Ctrl+Z` 都走这里）。返回 true = 真撤了一步。
## ⚠️ 只在**准备阶段**可用（那些操作本来就只发生在准备阶段）；空栈时把原因写进反馈行。
func undo_last() -> bool:
	if phase != Phase.PREPARE:
		last_message = "撤销只能在准备阶段用（本回合的部署操作都在那一档）"
		return false
	if _undo_stack.is_empty():
		last_message = "本回合没有可撤销的操作"
		return false
	var entry: Dictionary = _undo_stack.pop_back()
	_restore_state(entry["data"])
	selected_squad = -1
	selected_foe_squad = -1
	selected_post = ""
	var label := String(entry["label"])
	_undo_note = "撤销：%s" % label
	_undo_note_ms = Time.get_ticks_msec() + UNDO_NOTE_MS
	last_message = "已撤销：%s（还可撤销 %d 步）" % [label, _undo_stack.size()]
	return true

## 界面读的那一行"撤销了什么"（过期自动变空；纯表现，不参与判定）
func undo_note() -> String:
	if _undo_note == "" or Time.get_ticks_msec() >= _undo_note_ms:
		return ""
	return _undo_note

## 还能撤销几步（界面用来灰按钮 / 写提示）
func undo_depth() -> int:
	return _undo_stack.size()

# ---------------------------------------------------------------- 第三块的状态（2026-09-26）


## 每队的指挥所：`posts_of_team[team]` = `[左方, 右方]` —— **"左右"按该队朝向分**（不变量 I-36）：
## 0 队朝 +X ⇒ 左 = −Z、右 = +Z；1 队镜像。左方卖**单回合**增益、右方卖**持续**增益。
var posts_of_team: Array = [[], []]
var selected_post: String = ""           ## 界面当前打开的指挥所（`""` / `"left"` / `"right"`）
## 界面当前**查看的敌方队伍**（2026-09-27 用户："敌方单位也可以被我方选中，只用来查看信息"，
## 同日裁决"给敌方建'队'记账"）—— 存的是 `foe_squads` 里的下标（`-1` = 没在看）。
## ⚠️ 只读：不进 `squads`（那本账只管我方队伍）、不能拖 / 转；与 `selected_squad` / `selected_post` **互斥**。
var selected_foe_squad: int = -1
## **敌方的"队"账本**（2026-09-27 新增）：每条 `{"type_id": String, "units": int, "team": 1}`。
## ⚠️ 与我方 `squads` 的分工：这本**只管"哪些兵算一队"** —— 敌人不布阵、不拖动 ⇒ 不需要锚点 / 旋转那套字段。
## ⚠️ 单位侧靠两个 meta 认领：`foe_squad_index` / `foe_slot`（与 `squad_index` / `squad_slot` 同式）。
## ⚠️ 目前唯一来源是测试敌人（1 队 1 个）；接口按"一队 N 个"写 ⇒ 以后真敌人按波次生成时直接调
## `_spawn_foe_squad()`，面板与界面一行都不用改。
var foe_squads: Array = []
var buff_levels: Dictionary = {}         ## **持续**增益的等级：kind -> 0..`ROGUELIKE_BUFF_MAX_LEVEL`
var round_buffs: Dictionary = {}         ## 本回合已买的**单回合**增益：kind -> true
var _loan_debt: int = 0                  ## 紧急补给留下的欠账（下回合开始扣；**补给可为负**）
var aid_offer: Array = []
var aid_pending: bool = false
var aid_income_bonus: int = 0
var aid_tech_cut: int = 0
var aid_extra_squads: int = 0
var aid_shield_mult: float = 1.0
var aid_prop_cd_cut: int = 0
var aid_flank_half: bool = false
var aid_elite_level: bool = false
var aid_cost_control: bool = false
var aid_speed_add: float = 0.0
var aid_hp_mult: float = 1.0
var aid_damage_mult: float = 1.0
var aid_range_add: float = 0.0
var aid_variant: Dictionary = {}
var aid_taken: Dictionary = {}
var aid_cards: Array = []
var aid_zones: Array = []
var _aid_seq: int = 1
var _aid_card_index: int = -1
var _aid_anchor := Vector3.ZERO
var _aid_anchor_set: bool = false
var _command_wiping: bool = false

## 点指挥所 / 点单位用的射线（掩码只留两队单位层、长度够到 40~75 m 高的观赛机位）。
## ⚠️ **2026-09-27 去重**：原先这里与沙盒**各持一份同值常量**（旧账）⇒ 现在只有 `GameConfig.UNIT_PICK_*`
## 一处出处（I-15），两个模式共用。
const PICK_MASK := GameConfig.UNIT_PICK_MASK
const PICK_RANGE := GameConfig.UNIT_PICK_RANGE

func bind(p_arena: Arena, p_camera: CameraRig) -> void:
	arena = p_arena
	camera_rig = p_camera
	## 指挥所被摧毁 ⇒ **那一队**全体吃减益（第三块）。⚠️ 走总线上的**既有信号**（不新增信号、也不改
	## `Unit3D`）：`Events.unit_died(unit)` 带的就是那个 `Unit3D`，判一下类型即可。
	## ⚠️ 连在 `bind()` 里而不是 `begin()`：`bind()` 只被 `main` 调一次，而 `begin()` 每次重开一局都会进
	## ⇒ 连在那里会重复连接。这里的 `is_connected()` 只是双保险。
	if not Events.unit_died.is_connected(_on_unit_died):
		Events.unit_died.connect(_on_unit_died)

# ---------------------------------------------------------------- 回合流程
## 进入肉鸽模式：重置整局经济并把相机摆到"竞猜下注阶段"那一套（全景机位 + 光标可见）。
## ⚠️ 与沙盒的 `begin()` 同一支相机调用（`on_betting_phase()`）—— 三个模式的相机操作同源，不各摆一套机位。
## ⚠️ **2026-09-26 第四块起肉鸽改用 `on_roguelike_phase()`**（只换姿态，仍是同一套状态机与同一支 `_apply_pose()`）。
func begin() -> void:
	MatchSave.erase_roguelike()
	round_index = 1
	supply = 0
	income_total = 0
	hp = GameConfig.ROGUELIKE_HP_MAX
	hp_max = GameConfig.ROGUELIKE_HP_MAX
	log_entries.clear()
	result = {}
	summary = {}
	## ---- 第二块的状态：起手池 / 队伍 / 占格 / 本回合计数全部回到初始 ----
	starter_chosen = false
	difficulty = GameConfig.ROGUELIKE_DIFFICULTY_DEFAULT
	difficulty_chosen = false
	pool.clear()
	squads.clear()
	_occupied.clear()
	bought_this_round = 0
	unlocked_this_round = 0
	last_message = ""
	_rng.randomize()
	starter_choices = GameConfig.roguelike_make_starter_choices(_rng)
	## ---- 第三块的状态：指挥所 / 增益 / 借款全部回到初始 ----
	selected_post = ""
	## ---- 第四块的状态：选中 / 拖动全部回到初始 ----
	selected_squad = -1
	_reset_drag()
	## ---- 第五块的道具：全清（外观一并收掉，挡弹登记表跟着重同步）----
	_cancel_place()
	_clear_props()
	buff_levels.clear()
	for kind in [GameConfig.ROGUELIKE_BUFF_ATTACK, GameConfig.ROGUELIKE_BUFF_DEFENSE,
			GameConfig.ROGUELIKE_BUFF_UPGRADE]:
		buff_levels[kind] = 0
	round_buffs.clear()
	_loan_debt = 0
	RoguelikeAid.reset(self)
	if arena != null:
		arena.team_damage_buff[0] = 1.0
		arena.clear_round_buffs()
	_spawn_posts()
	_enter_prepare()

## 回合开始：**先把收入打进补给**，再进 `PREPARE`（等玩家花钱）。
## ⚠️ 收入的唯一出处是 `GameConfig.roguelike_supply_income()`（不变量 I-15：数值只住 `config.gd`）。
func _enter_prepare() -> void:
	var income := GameConfig.roguelike_supply_income(round_index) + aid_income_bonus
	supply += income
	income_total += income
	## 每回合的两条闸门各自重置（"每回合最多买 2 队""每回合最多解锁 1 个"）。
	bought_this_round = 0
	unlocked_this_round = 0
	## ---- 第三块：单回合增益清空 + "紧急补给"的欠账到期 ----
	## ⚠️ 欠账在**收入进账之后**扣 ⇒ 补给确实可能被扣成负数（用户："补给可为负数"，口径允许）。
	if arena != null:
		arena.clear_round_buffs()
	round_buffs.clear()
	if _loan_debt > 0:
		supply -= _loan_debt
		last_message = "紧急补给到期：扣 %d 补给（本回合补给 %d）" % [_loan_debt, supply]
		_loan_debt = 0
	phase = Phase.PREPARE
	## ---- 第三轮：撤销栈**每回合清空**（用户："能够撤销本回合的上一次操作（只能是本回合）"）----
	_recall_used = false
	_undo_stack.clear()
	_undo_note = ""
	_undo_note_ms = 0
	## ---- 第四块：回合开始先把部队恢复原样（回满血 / 复活阵亡的 / 重建被打掉的指挥所）----
	_recover_army()
	## 道具同样按"回合开始"结算：打过的陷阱撤走、魔法盾回满血（用户两条口径，见 `_recover_props()`）
	_recover_props()
	## 敌方波次：每回合清掉上一波作战单位（指挥所留着），再按 `ROGUELIKE_ENEMY_WAVES` 重刷。
	## 单位身上的信标路线**回合开始一律清掉**（新一回合由 `start_battle()` 重新指派）。
	if difficulty_chosen:
		_spawn_round_enemies()
	else:
		_clear_enemy_combatants()
	_clear_unit_beacon_routes()
	## 第七块：信标回合开始清场（`_recover_props()` 里撤走）+ 这里给一行"可以免费重放"的提示。
	if _beacon_owned:
		last_message = "移动信标：点道具行那张卡**免费**重新部署（买过一次就永久可用）"
	_route_editing = -1
	_route_points.clear()
	_cancel_place()                      ## 上一回合如果正拖着道具开的战，这里把拖放状态收干净
	_reset_drag()                        ## 上一回合如果是在拖动中途开的战，这里把拖动状态收干净
	_build_grid()                        ## 幂等：只有第一次进来才真的建
	_rebuild_cells()                     ## 占位着色跟着一起刷新（复活 / 重建会改占位）
	_set_grid_visible(true)              ## 布兵阶段才看得到格子（开战即收，见 `start_battle()`）
	if camera_rig != null:
		## ⚠️ **2026-09-26 第四块起改用肉鸽自己的部署机位**（用户："修改肉鸽模式默认视角，方便操作与
		## 分清敌我关系"）：与下注机位同一套状态、只换姿态（镜头退到己方后方偏南 ⇒ 屏幕左下 = 我方）。
		## ⚠️ 沙盒的布兵阶段**仍用 `on_betting_phase()`** —— 两个模式的默认视角自此**不同**，这是刻意的。
		camera_rig.on_roguelike_phase()
	RoguelikeAid.on_prepare(self)
	if difficulty_chosen:
		_remember_round_opening()
	else:
		_round_opening = {}
	_change_state()

## 开战（界面上的「开始战斗」）：点火 + 切到指挥视角。
## ⚠️ 用 `start_skirmish()` 而不是 `start_match()`（见文件头第 ① 条）；本步场上没有单位，
## 所以它只是把相位推进到 `BATTLE`，随后的第一物理帧就会因为"敌方全灭"而结算。
func start_battle() -> void:
	if phase != Phase.PREPARE or not difficulty_chosen:
		return
	if aid_pending:
		last_message = "先选择援助，或放弃换成补给"
		return
	arena.start_skirmish()
	RoguelikeAid.on_battle(self)
	_capture_beacon_routes()             ## 第六块：战斗开始的这一刻指派路线（用户口径）
	_capture_zone_prep()                 ## 第七块：站在敌方延伸区里、且是**本回合**放进去的 ⇒ 吃 5 s 准备期
	_set_grid_visible(false)             ## 开打就把格子收掉（它只是布兵阶段的占位提示）
	phase = Phase.FIGHTING
	if camera_rig != null:
		camera_rig.on_fight_phase()
		camera_rig.open_pilot_gate(true)
	_change_state()


func accept_aid(index: int) -> bool:
	var ok := RoguelikeAid.accept(self, index)
	if ok:
		choice_hidden = false
		_change_state()
	return ok


func skip_aid() -> bool:
	var ok := RoguelikeAid.skip(self)
	if ok:
		choice_hidden = false
		_change_state()
	return ok


func begin_aid_card(index: int) -> void:
	RoguelikeAid.begin_card(self, index)


func aid_speed_mult_at(unit: Unit3D) -> float:
	return RoguelikeAid.speed_mult(self, unit)


func aid_range_cut_at(unit: Unit3D) -> float:
	return RoguelikeAid.range_cut(self, unit)


func note_aid_attack(unit: Unit3D) -> void:
	RoguelikeAid.note_attack(self, unit)


## `BATTLE` 期间的每物理帧：**本回合什么时候算打完**。
## 敌方作战单位没了 = 本回合守住。我方作战单位没了 = 没打退敌人，扣还活着的敌方权重。
## ⚠️ **敌人还没做**（用户："先不做，后面再说"）⇒ `arena.alive_count(1)` 恒为 0 ⇒
## 本步一进 `FIGHTING` 就在下一帧结算（观感是"按了开始战斗立刻出结果"）——这是**已知的、临时的**，
## 等敌人落地之后这一段才真正开始工作。
## ⚠️ 手动结束（暂停菜单的「结束回合」）走 `end_round()`，不经过这里。
func _physics_process(_delta: float) -> void:
	## 第五块：拖放预览在准备阶段也要跟着光标走。
	## 陷阱的上弦和爆炸只在开战之后（`_tick_props` 里另判）。
	_tick_placing()
	_tick_props()
	RoguelikeAid.tick(self)
	if arena != null:
		arena.sync_unit_wards()
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
	_refresh_upgrade_marks()
	if _hold_waiting:
		if arena != null and arena.presentation_frozen:
			_settle_round()
		return
	if phase != Phase.FIGHTING:
		return
	## 敌方作战单位没了 = 守住。我方作战单位没了 = 这一回合没打退敌人，同样结算（指挥所不算）。
	if _enemy_combatants() == 0 or _player_combatants() == 0:
		_arm_round_hold()

## 结算本回合：**没击败敌方 ⇒ 扣"敌方存活兵种总权重"的血**（用户口径）。
## ⚠️ 本步 `enemy_weight()` 恒为 0（没有敌人）⇒ 扣血 0；但这条路径**已经是完整的**，
## 敌人一落地（把它们生成成 1 队的单位）它就会开始扣血。
## 有「壁垒」且彼此在链接距离内的骑士：脚下画圈，两人之间拉一条线。
func _sync_bulwark_fx() -> void:
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
			segments.append({
				"a": knights[i].global_position,
				"b": knights[j].global_position,
			})
	for node in arena.units:
		var marked := node as Unit3D
		if marked != null:
			marked.set_bulwark_mark(linked.has(marked))
	arena.show_bulwark_links(segments)

func _clear_bulwark_marks() -> void:
	for node in arena.units:
		var unit := node as Unit3D
		if unit != null:
			unit.set_bulwark_mark(false)

func _arm_round_hold() -> void:
	_hold_waiting = true
	if camera_rig != null:
		camera_rig.close_pilot_gate()
	arena.begin_presentation_hold()


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
	if phase != Phase.PREPARE or not starter_chosen or aid_pending or arena == null:
		hint.hide_hint()
		return
	var centers := PackedVector3Array()
	var team := 0
	var reach := 0.0
	if _dragging and _drag_squad >= 0:
		var cand := _drag_candidate()
		if cand.is_empty():
			hint.hide_hint()
			return
		centers = _squad_centers(cand)
		team = 0
		reach = _squad_reach(_drag_squad, 0)
	elif selected_squad >= 0 and selected_squad < squads.size():
		centers = _squad_centers(squads[selected_squad])
		team = 0
		reach = _squad_reach(selected_squad, 0)
	elif selected_foe_squad >= 0:
		for raw in _foe_living(selected_foe_squad):
			var unit := raw as Unit3D
			if unit != null:
				centers.append(unit.global_position)
				reach = maxf(reach, unit.attack_reach())
		team = 1
	else:
		hint.hide_hint()
		return
	if centers.is_empty():
		hint.hide_hint()
		return
	var center := _centroid_of(centers)
	var aim := _majority_aim(centers, team)
	hint.show_hint(center, reach, aim, aim != Vector3.INF, team)


func _centroid_of(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())


func _squad_reach(index: int, team: int) -> float:
	var best := 0.0
	if team == 0:
		var living := _living_slots(index)
		for slot in living.keys():
			var unit := living[slot] as Unit3D
			if unit != null and is_instance_valid(unit) and unit.alive:
				best = maxf(best, unit.attack_reach())
		if best <= 0.0 and index >= 0 and index < squads.size():
			best = _profile_reach(String(squads[index].get("type_id", "")))
	return best


func _profile_reach(type_id: String) -> float:
	if type_id == "":
		return 0.0
	var profile := GameConfig.profile(type_id)
	var reach := float(profile.get("range", 0.0))
	if not bool(profile.get("is_ranged", false)):
		reach *= GameConfig.UNIT_CONTACT_RATIO
	return reach


func _nearest_enemy_from(at: Vector3, team: int) -> Unit3D:
	var best: Unit3D = null
	var best_d := INF
	for node in arena.units:
		var other := node as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive or other.team == team:
			continue
		if GameConfig.is_roguelike_only(String(other.type_id)):
			continue
		if other.is_burrowed() or other.is_in_shadow_form() or other.is_ember():
			continue
		var dist := at.distance_squared_to(other.global_position)
		if dist < best_d:
			best_d = dist
			best = other
	return best


func _majority_aim(centers: PackedVector3Array, team: int) -> Vector3:
	var tally := {}
	for center in centers:
		var other := _nearest_enemy_from(center, team)
		if other == null:
			continue
		var key := -1
		if team == 0 and other.has_meta("foe_squad_index"):
			key = int(other.get_meta("foe_squad_index"))
		elif team == 1 and other.has_meta("squad_index"):
			key = int(other.get_meta("squad_index"))
		if key < 0:
			continue
		tally[key] = int(tally.get(key, 0)) + 1
	var best_key := -1
	var best_n := 0
	for key in tally.keys():
		var count := int(tally[key])
		if count > best_n:
			best_n = count
			best_key = int(key)
	if best_key < 0:
		return Vector3.INF
	var points: Array = []
	if team == 0:
		for raw in _foe_living(best_key):
			var foe := raw as Unit3D
			if foe != null:
				points.append(foe.global_position)
	else:
		var living := _living_slots(best_key)
		for slot in living.keys():
			var ally := living[slot] as Unit3D
			if ally != null:
				points.append(ally.global_position)
	if points.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())


func _settle_round() -> void:
	_hold_waiting = false
	arena.park_combat()
	_clear_replicates()
	var defeated := _enemy_combatants() == 0
	var loss := 0 if defeated else enemy_weight()
	if loss > 0:
		hp = maxi(hp - loss, 0)
	result = {
		"round": round_index,
		"defeated": defeated,
		"loss": loss,
		"hp": hp,
		"hp_max": hp_max,
		"supply": supply,
	}
	log_entries.append(result.duplicate())
	phase = Phase.ROUND_RESULT
	if camera_rig != null:
		camera_rig.hold_battle_view()
	_change_state()
	## 失败条件（用户："血量降到0及以下则失败"）⇒ 当场结束；否则等玩家点「下一回合」。
	if hp <= 0:
		_finish(false)

## 下一回合（结果浮层的按钮）：回合 +1；打满 `ROGUELIKE_ROUND_COUNT` 就整局结束（胜）。
func next_round() -> void:
	if phase != Phase.ROUND_RESULT:
		return
	if round_index >= GameConfig.ROGUELIKE_ROUND_COUNT:
		_finish(true)
		return
	arena.park_combat()
	arena.clear_arrows()
	arena.clear_acid()
	arena.end_presentation_hold()
	round_index += 1
	_enter_prepare()

## 手动结束本回合（暂停菜单里的「结束回合」）。
## ⚠️ **自己解除暂停**（与 `Sandbox.end_battle()` 的分工完全一致）：`PauseMenu` 在黑透那一刻调它，
## 之后只负责渐亮、不会再补一次 `resume_match()`（补了会把暂停时长重复扣一遍）。
func end_round() -> void:
	_pause_from_ms = 0
	get_tree().paused = false
	if phase != Phase.FIGHTING or _hold_waiting:
		return                       ## 已经结算 / 还在准备 / 正在定格：只解除暂停，别覆盖已有结果
	_arm_round_hold()

## 整局结束：`reached_end = true` = 打满 10 回合（胜）；false = 血量归零（败）。
func _finish(reached_end: bool) -> void:
	summary = {
		"rounds": round_index,
		"hp": hp,
		"hp_max": hp_max,
		"supply": supply,
		"income_total": income_total,
		"reached_end": reached_end,
		"log": log_entries.duplicate(),
	}
	phase = Phase.GAME_OVER
	MatchSave.erase_roguelike()
	_round_opening = {}
	_change_state()

## 重开一局（结算浮层的按钮）：与 `begin()` 同一条路径（经济全部回到初始值）。
## ⚠️ 顺手解除暂停：调用方（界面）是在黑透那一刻调的，此时不该再让树停着（与 `Game.restart_game()` 同义）。
## ⚠️ **2026-09-26 经用户裁决改名**：`restart_run()` → **`restart_game()`** —— 与竞猜模式那个**同名同义**（§1.4）；
## "run" 虽然是肉鸽的惯用词，但本项目里"整局重置"这件事只允许有一个名字（见本批 `08_naming.md` 审计）。
func restart_game() -> void:
	_pause_from_ms = 0
	get_tree().paused = false
	arena.settle()
	arena.end_presentation_hold()
	begin()

func _change_state() -> void:
	phase_changed.emit(phase_name())

func phase_name() -> String:
	match phase:
		Phase.PREPARE:
			return "prepare"
		Phase.FIGHTING:
			return "fighting"
		Phase.ROUND_RESULT:
			return "round_result"
		Phase.GAME_OVER:
			return "over"
	return "unknown"

# ---------------------------------------------------------------- 查询
## 敌方（1 队）**存活兵种的总权重** —— 用户口径里"扣血扣多少"的那个数。
## ⚠️ 用的是 `PROFILES[*]["weight"]`（配平用的占位成本），不是 `mass`（击退用的物理质量）——
## 不变量 I-26 说过这两件事别混。
## ⚠️ **排除建筑**（指挥所）：它们是常驻的 999 权重，算进来会让"没打退敌人"扣血直接爆表
##（见 `_enemy_combatants()` 的同一条判据）。
func enemy_weight() -> int:
	var total := 0
	for unit in arena.units:
		var other := unit as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		if other.team != _enemy_team() or GameConfig.is_roguelike_only(String(other.type_id)):
			continue
		total += int(GameConfig.profile(other.type_id)["weight"])
	return total

## 敌方**作战单位**数（= 1 队里除"指挥所"这类建筑以外的存活单位）。
## ⚠️ 为什么不直接用 `arena.alive_count(1)`：场上常驻两座**敌方**指挥所，而"敌人"还没做 ⇒
## 没有任何东西能打掉它们 ⇒ 用 `alive_count` 的话"敌方全灭 = 本回合守住"这条**永远不成立**、
## 回合永远结算不了。判据与 `enemy_weight()` 同源：`is_roguelike_only()` 标出来的东西**不算作战单位**。
func _enemy_combatants() -> int:
	return _combatants_of(_enemy_team())

## 我方作战单位数。指挥所留下也不算还有兵，否则我方打光了回合不会结束。
func _player_combatants() -> int:
	return _combatants_of(0)

func _combatants_of(team: int) -> int:
	var total := 0
	for unit in arena.units:
		var other := unit as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		if other.team != team or GameConfig.is_roguelike_only(String(other.type_id)):
			continue
		total += 1
	return total

## 敌方是哪一队。⚠️ **玩家固定在 0 队（赤羽卫，出生在 −X = 西）** —— 与不变量 I-35 的既有约定一致，
## 不另开一套"谁是敌人"的约定；将来敌人落地时生成为 1 队即可。
func _enemy_team() -> int:
	return 1

# ---------------------------------------------------------------- 初始四选一（第二块）
## 选定起手部队（界面上的四选一）：那两个兵种进池子，并**每个兵种白送两队**（2026-10-01，原先各一队）。
## ⚠️ 白送的队**不花补给、也不计入"本回合已买"**（它是"初始部队"，不是买来的）。
func choose_difficulty(id: String) -> void:
	if difficulty_chosen or phase != Phase.PREPARE:
		return
	difficulty = GameConfig.roguelike_difficulty_id(id)
	difficulty_chosen = true
	_spawn_round_enemies()
	_remember_round_opening()
	_change_state()


func choose_starter(index: int) -> void:
	if starter_chosen or index < 0 or index >= starter_choices.size():
		return
	var pick: Array = starter_choices[index]
	for type_id in pick:
		var id := String(type_id)
		if not pool.has(id):
			pool.append(id)
		for _squad_n in GameConfig.ROGUELIKE_STARTER_SQUADS:
			_grant_squad(id)
	starter_chosen = true
	choice_hidden = false
	last_message = "起手部队：%s" % _pair_text(pick)

## 两个兵种 ID → "名字 + 名字"（界面与日志共用的一句话）
func _pair_text(pair: Array) -> String:
	var parts: Array = []
	for type_id in pair:
		parts.append(GameConfig.profile_name(String(type_id)))
	return " + ".join(parts)

# ---------------------------------------------------------------- 商店（购买 / 解锁）
## 这一队要花多少补给（界面显示用；口径的唯一出处仍是 `GameConfig`）
func squad_cost(type_id: String) -> int:
	var cost := GameConfig.roguelike_squad_cost(int(GameConfig.profile(type_id)["weight"]))
	cost += RoguelikeAid.recruit_delta(self, type_id)
	cost = maxi(cost, 0)
	## 「精英招募」生效时，招募价先把这一队的升级费算进去。
	if has_round_buff(GameConfig.ROGUELIKE_ROUND_BUFF_ELITE):
		cost += upgrade_price_of(type_id)
	return cost

## 现在解锁这个兵种要多少补给（= ⌊**招募一队这个兵种**的总权重 ÷ 2⌋）
## ⚠️ 第三块修正：口径是"**一队这个兵种**"，不是"全队"（旧版按全队算是误读，见 `99_decisions.md`）。
func unlock_cost(type_id: String) -> int:
	return GameConfig.roguelike_unlock_cost(type_id)

## 全队（**已拥有的所有兵**）总权重 —— 解锁价的基数。
## ⚠️ 按"买下的队"累加（`squads`），**不数场上的活人**：将来敌人做出来、有兵阵亡时，
## "全队"应当仍是"你这局攒下来的部队"（要改成按存活算，得先记一条决策）。
func squad_weight_total() -> int:
	var total := 0
	for squad in squads:
		var info: Dictionary = squad
		total += int(info["weight"]) * int(info["units"])
	return total

func can_buy(type_id: String) -> bool:
	return buy_block_reason(type_id) == ""

## 不能买的原因（空串 = 能买）。界面既用它灰卡片，也用它当点击后的提示文案。
func buy_block_reason(type_id: String) -> String:
	if phase != Phase.PREPARE:
		return "只能在准备阶段买兵"
	if not starter_chosen:
		return "先选初始部队"
	if aid_pending:
		return "先选择援助，或放弃换成补给"
	if not pool.has(type_id):
		return "尚未解锁（先花 %d 补给解锁它）" % unlock_cost(type_id)
	## ⚠️ **每回合的额度先于补给判定**：两条同时不满足时，玩家该先看到"本回合买满了"
	##（那是这一回合真正卡住他的闸门；只报"补给不足"会让人以为下一回合也买不了）。
	if bought_this_round >= squad_limit_this_round():
		return "本回合已经买满 %d 队" % squad_limit_this_round()
	var cost := squad_cost(type_id)
	if supply < cost:
		return "补给不足：一队要 %d，还剩 %d" % [cost, supply]
	if _free_anchor(int(GameConfig.profile(type_id)["weight"])) == Vector2i(-1, -1):
		return "己方半场放不下了"
	return ""

## 买一整队：扣补给 → 占格 → 生兵（用户："点一次买一整队"）。返回是否真的买成。
func buy_squad(type_id: String) -> bool:
	var reason := buy_block_reason(type_id)
	if reason != "":
		last_message = reason
		return false
	_push_undo("买下 %s" % GameConfig.profile_name(type_id))    ## 撤销点：买兵
	var weight := int(GameConfig.profile(type_id)["weight"])
	var cost := squad_cost(type_id)
	supply -= cost
	bought_this_round += 1
	_grant_squad(type_id, cost)          ## move_round = 本回合 ⇒ 本回合内可以拖动换位
	## 2026-09-27：① 「精英招募」生效 ⇒ 这一队 +1 级（**只给"买"的**，用户裁决）；
	##             ② 这一队演一次"从天上掉下来"（纯视觉）。
	_apply_elite_recruit(squads.size() - 1)
	_play_drop_in(squads.size() - 1)
	last_message = "买下 %s：一队 %d 个，花 %d 补给" % [
			GameConfig.profile_name(type_id), GameConfig.roguelike_squad_size(weight), cost]
	return true

func can_unlock(type_id: String) -> bool:
	return unlock_block_reason(type_id) == ""

## 不能解锁的原因（空串 = 能解锁）。⚠️ **已经解锁的兵种走 `buy_block_reason()` 那一支**（买兵）。
func unlock_block_reason(type_id: String) -> String:
	if phase != Phase.PREPARE:
		return "只能在准备阶段解锁"
	if not starter_chosen:
		return "先选初始部队"
	if pool.has(type_id):
		return "已经解锁"
	if unlocked_this_round >= GameConfig.ROGUELIKE_UNLOCK_PER_ROUND:
		return "本回合已经解锁过 %d 个" % GameConfig.ROGUELIKE_UNLOCK_PER_ROUND
	var cost := unlock_cost(type_id)
	if supply < cost:
		return "补给不足：解锁要 %d，还剩 %d" % [cost, supply]
	return ""

func unlock_type(type_id: String) -> bool:
	var reason := unlock_block_reason(type_id)
	if reason != "":
		last_message = reason
		return false
	_push_undo("解锁 %s" % GameConfig.profile_name(type_id))    ## 撤销点：解锁兵种
	var cost := unlock_cost(type_id)
	supply -= cost
	unlocked_this_round += 1
	pool.append(type_id)
	last_message = "解锁 %s：花 %d 补给（每回合最多解锁 %d 个）" % [
			GameConfig.profile_name(type_id), cost, GameConfig.ROGUELIKE_UNLOCK_PER_ROUND]
	return true

# ---------------------------------------------------------------- 本模式自己的格子几何（场地尺寸按模式给）
## ⚠️ **一律走这三个包装**，别直接调 `GameConfig` 里那三个同名函数：它们的默认值回落到**全局**场地
##（100 × 50），而肉鸽从第六块起与全局不同（`main.gd` 按模式写 `Arena.half_x` / `half_z`）。
## 直接在调用点上写默认值 = 在肉鸽的场地上按 100 × 50 算格子 ⇒ 只能画出一半的格子、坐标全歪。
func _grid_cols() -> int:
	return GameConfig.roguelike_grid_cols(arena.half_x)

func _grid_rows() -> int:
	return GameConfig.roguelike_grid_rows(arena.half_z)

func _cell_center(col: int, row: int) -> Vector3:
	return GameConfig.roguelike_cell_center(col, row, arena.half_x, arena.half_z)

# ---------------------------------------------------------------- 两条长边外侧的"前进布阵带"（第七块）
## 用户原文："在敌我场地的两边再延伸出一个特殊的场地…在部署阶段'我方'可以在'敌方'的这个场地布置兵种，
## 但我方单位每当部署到这个场地时需要5s准备时间…己方的这个特殊区域只有敌方能部署（敌方同理）。
## 在这个区域部署后的下一个回合开始则不需要启动时间。（同理边界向外扩）"
## ⚠️ **2026-09-27 两次订正**：
##   ① 位置（红笔标注）：贴**南北两条长边的外侧**（不是东西两端），各 **12 m 深（6 格）**；
##   ② 长度（用户原话）："我方可部署兵种的特殊区域**从敌方场地底线延伸到敌方场地四分之三处**，
##      敌方的可部署场地从我方底线延伸到我方四分之三处" ⇒ 每条 = **本方半场的 3/4 = 56.25 m**
##      （从**自己的底线**往内量），两条**不重叠**，中间留 **19 格死区**（两边都不能布阵）。
## ⇒ 竞技场仍是 **150 × 111.5** 的大矩形（南北各多 12 m），两条带子是它内部的南 / 北边带。
## ⚠️ 本文件里两个词的分工（**以"谁的地盘"为准**，不看屏幕）：
##   · **己方那段带子** = 从己方底线往内 3/4（列 0~27）—— **只有敌方能布阵**；
##   · **敌方那段带子** = 从敌方底线往内 3/4（列 47~74）—— **我方**能布阵，落子要吃 5 s 准备期；
##   · 中间那段（列 28~46）带子还在，但**两边都不能布阵**（染成中性灰）。
## 几何（边界 / 地板 / 墙 / 取景）全在 `Arena`（它只认一个更大的矩形），这里只用格坐标算"能不能放、算不算进带子"。

## 带子覆盖的行区间（闭区间；`side` = −1 北 / +1 南）。当前：北 0~5、南 50~55（各正好 6 行）。
func _zone_row_range(side: int) -> Vector2i:
	if side < 0:
		return Vector2i(GameConfig.roguelike_zone_row_north_min(),
				GameConfig.roguelike_zone_row_north_max())
	return Vector2i(GameConfig.roguelike_zone_row_south_min(),
			GameConfig.roguelike_zone_row_south_max())

## 主场地（不含两条带子）覆盖的行区间 —— 当前 6~49（就是第六块那版的 44 行）。
func _field_row_range() -> Vector2i:
	return Vector2i(GameConfig.roguelike_field_row_min(), GameConfig.roguelike_field_row_max())

## 某一行在任一条带子里吗
func _row_in_zone(row: int) -> bool:
	var south := _zone_row_range(1)
	if row >= south.x and row <= south.y:
		return true
	var north := _zone_row_range(-1)
	return row >= north.x and row <= north.y

## **某一方能布阵的那一段带子**（= 从**对方底线**往内 3/4 那一段）占哪些列（闭区间）。
## 0 队（西）⇒ 东侧那段（当前列 47~74）；1 队 ⇒ 西侧那段（当前列 0~27）。中间那段两边都不给。
func _zone_col_range(team: int) -> Vector2i:
	var cols := _grid_cols()
	if team == 0:
		return Vector2i(GameConfig.roguelike_zone_col_foe_min(cols),
				GameConfig.roguelike_zone_col_foe_max(cols))
	return Vector2i(GameConfig.roguelike_zone_col_own_min(),
			GameConfig.roguelike_zone_col_own_max())

## 一个格子在"这一方能布阵的带子"里吗（南北两条任一）—— 判准备期用的就是它
func _cell_in_forward_zone(col: int, row: int, team: int) -> bool:
	var range_cols := _zone_col_range(team)
	if col < range_cols.x or col > range_cols.y:
		return false
	return _row_in_zone(row)

## 这一队（锚点 + 外框）整块落在**同一条带子**里吗 ⇒ 开战时这些兵要吃准备期。
## ⚠️ 要求"整块在同一条"（不跨南北）：跨到主场地去的队形不算落在带子里。
func _anchored_in_forward_zone(anchor: Vector2i, fp: Vector2i, team: int) -> bool:
	var range_cols := _zone_col_range(team)
	if anchor.x < range_cols.x or anchor.x + fp.y - 1 > range_cols.y:
		return false
	for side in [-1, 1]:
		var bands := _zone_row_range(side)
		if anchor.y >= bands.x and anchor.y + fp.x - 1 <= bands.y:
			return true
	return false

# ---------------------------------------------------------------- 布阵（占格 + 自动落位 + 第四块的旋转）
## 一队**旋转后**的外框，返回 `Vector2i(width, depth)` —— 沿用 `GameConfig` 的口径
##（`width` = 沿 Z 的格数 / `depth` = 沿 X 的格数，见 `roguelike_squad_width()` 的注释）；
## 旋转 90° = 两者**互换**（用户口径："如横着变成竖着"）。
func _footprint(weight: int, rotated: bool) -> Vector2i:
	var w := GameConfig.roguelike_squad_width(weight)
	var d := GameConfig.roguelike_squad_depth(weight)
	if rotated:
		return Vector2i(d, w)
	return Vector2i(w, d)

## 一个**兵**占几格，返回 `Vector2i(unit_width, unit_depth)`（同上口径）；旋转后互换。全队每个兵一样大。
func _unit_extent(weight: int, rotated: bool) -> Vector2i:
	var def: Dictionary = GameConfig.roguelike_squad_def(weight)
	var uw := int(def.get("unit_width", 1))
	var ud := int(def.get("unit_depth", 1))
	if rotated:
		return Vector2i(ud, uw)
	return Vector2i(uw, ud)

## 一队每个兵（槽位）的**锚点格**（绝对格坐标）。顺序 = 生成顺序 ⇒ 拖动落位 / 复活阵亡都按它"对号入座"。
## ⚠️ 旋转**只改布阵的朝向，不改兵的朝向**（用户口径："单位的方向依旧是面向敌方"）。
func _unit_cells(info: Dictionary) -> Array:
	var weight := int(info["weight"])
	var rot: bool = info.get("rotated", false)
	var def: Dictionary = GameConfig.roguelike_squad_def(weight)
	var across := int(def.get("across", 1))
	var deep := int(def.get("deep", 1))
	var uw := int(def.get("unit_width", 1))
	var ud := int(def.get("unit_depth", 1))
	var col := int(info["anchor_col"])
	var row := int(info["anchor_row"])
	var out: Array = []
	for i in range(across):
		for j in range(deep):
			## ⚠️ 轴的映射（**别照直觉猜**，照 `04_physics.md#6` + I-36：纵 = 沿朝向 = 世界 X）：
			## **未旋转**时 `col`（X）走的是**纵深**索引 j、`row`（Z）走的是**横排**索引 i；
			## **旋转 90°** 后两者互换。（2026-09-27 顺手改正了一处写反了的注释文字 —— 代码本来就是对的。）
			if rot:
				out.append(Vector2i(col + i * uw, row + j * ud))
			else:
				out.append(Vector2i(col + j * ud, row + i * uw))
	return out

## 一队每个兵的**世界坐标**（它那 `unit_depth × unit_width` 格块的中心）。
## ⚠️ 初次布阵 / 复活阵亡 / 拖动落位**共用这一个算法** —— 否则会出现"拖过之后的位置和刚买来时对不上"。
func _squad_centers(info: Dictionary) -> PackedVector3Array:
	var ext := _unit_extent(int(info["weight"]), bool(info.get("rotated", false)))
	var cell := GameConfig.ROGUELIKE_CELL_SIZE
	var out := PackedVector3Array()
	for raw in _unit_cells(info):
		var c: Vector2i = raw
		var at := _cell_center(c.x, c.y)
		at.x += float(ext.y - 1) * cell * 0.5     ## ext.y = 沿 X 的格数
		at.z += float(ext.x - 1) * cell * 0.5     ## ext.x = 沿 Z 的格数
		out.append(at)
	return out

## 这一格在"地块"里吗（= 整个竞技场矩形：主场地 + 南北两条带子）—— 光标落点 / 预览判定用它。
func _cell_in_footprint(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _grid_cols() and cell.y >= 0 and cell.y < _grid_rows()

## 世界坐标 → 格坐标（与 `GameConfig.roguelike_cell_center()` **严格互逆**：那边减半格再加，这边加半格再减）。
func _cell_of(point: Vector3) -> Vector2i:
	var cell := GameConfig.ROGUELIKE_CELL_SIZE
	return Vector2i(
			int(floor((point.x + arena.half_x) / cell)),
			int(floor((point.z + arena.half_z) / cell)))

## 这个锚点是不是"**己方半场里**"的合法位置 —— 与 `_free_anchor()` 的扫描范围**同一套界**
##（手动拖动必须和自动落位守同一把尺子，否则会出现"自动摆得下、手动拖不进去"这种怪事）。
## ⚠️ 2026-09-27 订正后：除了己方半场，**对方底线起算的那两条带子**也是合法落点（用户："我方可以在
## 敌方的这个场地布置兵种"）⇒ 两个矩形任选其一装得下即可；`team` 默认 0（玩家）。
func _in_deploy_area(anchor: Vector2i, fp: Vector2i, team: int = 0) -> bool:
	if _fits_in_home_half(anchor, fp, team):
		return true
	return _anchored_in_forward_zone(anchor, fp, team)

## 己方半场（主场地内那一半）—— **含最外那一圈格子**。
## ⚠️ **2026-09-27 第二项任务：去掉原来的 1 格边距**（用户："我方场地在边缘的那些格子无法布兵"）。
## 去掉是安全的：格子边长 2.0 m ⇒ 站在最外那格的**格心**离墙 1.0 m，而单位判定半径只有 0.38 m
##（载具 / boss 的盒体半宽也在 1.3~2.4 m 以内，格块中心到墙还有余量）⇒ 不会半个身子卡进墙里。
## ⚠️ 边距原来是为了"别贴墙"这条观感理由，现在改成"整块己方半场都能放"（用户裁决）。
func _fits_in_home_half(anchor: Vector2i, fp: Vector2i, team: int) -> bool:
	var cols := _grid_cols()
	var field_rows := _field_row_range()
	var lo: int = 0 if team == 0 else cols / 2
	var hi: int = cols / 2 - 1 if team == 0 else cols - 1
	if anchor.x < lo or anchor.y < field_rows.x:
		return false
	if anchor.x + fp.y - 1 > hi:
		return false
	if anchor.y + fp.x - 1 > field_rows.y:
		return false
	return true

# ---------------------------------------------------------------- 收队 / 生兵
## 收下一队：**先找一块空地**（`_free_anchor()`），再把这一队的每个兵生到各自的格块中心。
## ⚠️ 只**加**不重建（`restart_game()` 那次才 `arena.settle()`）—— 同一帧"先释放再刷兵"会让节点名撞车
##（`08_naming.md#3.1` 登记过的那条边界情形）。
## ⚠️ **2026-09-26 第四块口径（用户："开局送的两队兵也能在第一回合进行移动"）**：既然起手白送的两队
## 也要能在第 1 回合换位，那"能不能移动"的判据就不是"是不是买的"，而是**"是不是在本回合拿到的"** ⇒
## 字段名从 `bought_round` 改成 **`move_round`**（"允许换位的回合"），起手两队记的也是 `round_index`。
## 于是买兵那条 `from_purchase` 参数失去了唯一用途（两处调用要的是同一件事）⇒ **删掉**，
## 免得留一个"名字说 A、行为是 B"的参数（`08_naming.md#1.4`）。
func _grant_squad(type_id: String, spent: int = 0) -> void:
	var weight := int(GameConfig.profile(type_id)["weight"])
	var anchor := _free_anchor(weight, false)          ## 新到手的一律未旋转
	if anchor == Vector2i(-1, -1):
		last_message = "己方半场放不下了（%s）" % GameConfig.profile_name(type_id)
		return
	var info := {
		"type_id": type_id,
		"weight": weight,
		"units": GameConfig.roguelike_squad_size(weight),
		"anchor_col": anchor.x,
		"anchor_row": anchor.y,
		"rotated": false,
		"move_round": round_index,
		"level": 2 if aid_elite_level else 1,
		"xp": 0,             ## 这一队攒的升级经验（满 = 该级的升级成本 ⇒ 不再累积，等玩家点升级）
		"supply_spent": spent,  ## 买队 + 已付升级。遣返退一半。科技和白送的等级不算。
		"cost_control": aid_cost_control,
	}
	squads.append(info)
	_occupy_squad(info, squads.size() - 1)
	_spawn_squad(info, squads.size() - 1)
	_rebuild_cells()

## 把一队的每个兵生到自己的格块中心。朝向由 `TEAM_META[*].spawn_sign` **单点推导**（与 `Arena` 同源，I-35）。
## ⚠️ 每个兵带两个 meta：`squad_index`（属于第几队）+ `squad_slot`（队内第几个槽位）——
## 拖动落位 / 复活阵亡都靠它们把"兵 ↔ 格子"对上，**不靠** `arena.units` 的顺序（那是全局的、还会被别的队插队）。
func _spawn_squad(info: Dictionary, index: int) -> void:
	var facing := GameConfig.team_spawn_sign(0) * PI * 0.5
	var centers := _squad_centers(info)
	for slot in range(centers.size()):
		_spawn_one_squad_unit(info, index, slot, centers[slot], facing)

## 生成**一个**槽位的兵（初次布阵 / 回合开始复活阵亡的都走它 ⇒ 两者加成完全一致）
## ⚠️ **2026-09-27（等级）**：出生时就把这一队的等级落到单位上（`set_level()`）—— 复活补位的兵
## 与新买的兵因此**同级**（用户口径"一队兵种的等级保持相同"）。
## ⚠️ 顺序：**先设等级、再发防御指令加成** —— `add_hp_bonus()` 记的是**加法池**，上限由
## `(原始血量 + 加法池) × 等级倍率` 算出 ⇒ 两者谁先谁后都对，但先设等级更直观（血量一步到位）。
func _spawn_one_squad_unit(info: Dictionary, index: int, slot: int, at: Vector3, facing: float) -> Unit3D:
	var spawned := arena.spawn_unit(0, String(info["type_id"]), at, facing)
	if spawned == null:
		return null
	spawned.set_meta("squad_index", index)
	spawned.set_meta("squad_slot", slot)
	spawned.set_level(squad_level(index))
	_grant_defense_bonus(spawned)   ## 防御指令：新上场的兵同样吃加成（用户裁决）
	## 兵种科技（2026-09-27 第十二轮）：**新出生的兵立刻带上本队已买下的科技** ——
	## 与"买下一条科技时把场上同兵种刷一遍"合起来，"本局永久 + 立即生效"这条口径才闭合。
	spawned.set_techs(tech_active_for(String(info["type_id"])))
	## 剑圣（「剑圣」科技，2026-09-27 第十二轮·第二批）：**每队一位**（用户："每一队剑盾兵都会有一位剑圣"）。
	## ⚠️ 认的是**槽位**（`squad_slot == 0`）而不是"当前活着的第一个人" ⇒ 剑圣阵亡后补位复活的那个**仍是剑圣**
	##（口径：一队永远只有一位，且位置固定 —— 随机挑一个会让"哪只是剑圣"在战斗里跳来跳去）。
	## ⚠️ 单独招募的散兵（不属于任何"队"）没有槽位 ⇒ 也就没有剑圣（用户当场确认过）。
	if slot == 0:
		spawned.set_saint(has_tech(String(info["type_id"]), "sword_saint"))
	RoguelikeAid.paint_unit(self, spawned)
	return spawned

## 第 `index` 队的等级（`1..ROGUELIKE_LEVEL_MAX`；队信息缺字段 ⇒ 1 ⇒ 老存档 / 老探测不受影响）
func squad_level(index: int) -> int:
	if index < 0 or index >= squads.size():
		return 1
	return clampi(int(squads[index].get("level", 1)), 1, GameConfig.ROGUELIKE_LEVEL_MAX)

# ---------------------------------------------------------------- 兵种科技（2026-09-27 第十二轮）
## 用户口径（原话在项目根的 `肉鸽兵种科技.txt`）："科技需要**选中相应兵种**后**花费补给激活**，
## 激活后**所有同类型兵种都能吃到科技加成**（如点了剑盾兵的某个科技，则所有剑盾兵都会吃到该科技加成）"。
## 实现 = **一份扁平状态**（`{兵种 ID: {科技 ID: true}}`，只记"买没买过"）+ **两处推送**：
##   ① 单位出生时（`_spawn_one_squad_unit()` 里 `set_techs()`）；
##   ② 买下一条科技时（`apply_techs_to_type()` 把场上同兵种立刻刷一遍）。
## ⚠️ 效果参数**不在这里**（唯一出处是 `GameConfig.ROGUELIKE_TECH_TABLE`，I-15）；这里只管"买没买"。
## ⚠️ 它进撤销快照（"买科技"是玩家操作，用户要求撤销覆盖全部部署操作）—— 回滚时连同场上的兵一起重建。
var techs: Dictionary = {}

## 我这一队在某兵种上已激活的科技 —— 形状正好是 `Unit3D.set_techs()` 要的那份扁平字典
##（`{科技 ID: 定义}`；没买过就是空字典 ⇒ 单位那边所有修正退化成 1.0 / 0.0）。
func tech_active_for(type_id: String) -> Dictionary:
	var owned: Dictionary = techs.get(type_id, {})
	var out: Dictionary = {}
	for tech_id in owned.keys():
		var def := GameConfig.roguelike_tech_def(type_id, String(tech_id))
		if not def.is_empty():
			out[String(tech_id)] = def
	return out

func has_tech(type_id: String, tech_id: String) -> bool:
	var owned: Dictionary = techs.get(type_id, {})
	return owned.has(tech_id)

## 这条科技现在的标价。表内 `cost` 是底价；同兵种每已经买下一条，还没买的每条再加 `ROGUELIKE_TECH_COST_STEP`。
func tech_price(type_id: String, tech_id: String) -> int:
	var def := GameConfig.roguelike_tech_def(type_id, tech_id)
	if def.is_empty():
		return 0
	var owned: Dictionary = techs.get(type_id, {})
	var price := int(def.get("cost", 0)) + owned.size() * GameConfig.ROGUELIKE_TECH_COST_STEP
	return maxi(price - RoguelikeAid.tech_cut(self, type_id), 0)

## 场上没有活兵时，面板仍按已买科技算攻击间隔（「狂暴」）。有活兵时直接问那个兵。
func _owned_interval_mult(type_id: String) -> float:
	if not has_tech(type_id, "rage"):
		return 1.0
	var def := GameConfig.roguelike_tech_def(type_id, "rage")
	return float(def.get("interval_mult", 1.0))

## 场上没有活兵时，面板仍按已买科技算伤害（「精英猎手」按队伍等级）。剑圣不进这里：没有兵就没有那一位。
func _owned_damage_mult(type_id: String, level: int) -> float:
	if not has_tech(type_id, "elite_hunter"):
		return 1.0
	var def := GameConfig.roguelike_tech_def(type_id, "elite_hunter")
	return 1.0 + float(def.get("damage_per_level", 0.0)) * float(level)

## 花补给激活一条科技。返回 true = 真买下了。
## ⚠️ 三道闸门：**这条科技已实现**（`pending` 的 5 条第二批才做，界面上也灰着）/ **没买过** / **补给够**。
## ⚠️ 成功后立刻把**场上同兵种**刷一遍（用户口径"所有同类型兵种都能吃到"——含已经摆下的）。
func buy_tech(type_id: String, tech_id: String) -> bool:
	var def := GameConfig.roguelike_tech_def(type_id, tech_id)
	if def.is_empty():
		last_message = "没有这条科技"
		return false
	if not GameConfig.roguelike_tech_ready(type_id, tech_id):
		last_message = "%s 还没实现（第二批）" % String(def.get("name", tech_id))
		return false
	if has_tech(type_id, tech_id):
		last_message = "已经买过 %s 了" % String(def.get("name", tech_id))
		return false
	var cost := tech_price(type_id, tech_id)
	if supply < cost:
		last_message = "补给不够：%s 要 %d，现在只有 %d" % [String(def.get("name", tech_id)), cost, supply]
		return false
	_push_undo("买下科技 %s" % String(def.get("name", tech_id)))   ## 撤销点：买兵种科技
	supply -= cost
	if not techs.has(type_id):
		techs[type_id] = {}
	(techs[type_id] as Dictionary)[tech_id] = true
	apply_techs_to_type(type_id)
	last_message = "%s 已激活：%s（%d 补给）" % [GameConfig.profile_name(type_id),
			String(def.get("name", tech_id)), cost]
	return true

## 把"某兵种已激活的科技"推给**场上所有该兵种的我方单位**（刚摆下的、以及以后出生的都由
## `_spawn_one_squad_unit()` 那一路覆盖）。
func apply_techs_to_type(type_id: String) -> void:
	var active := tech_active_for(type_id)
	if arena == null:
		return
	for node in arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or unit.team != 0:
			continue
		if unit.type_id == type_id:
			unit.set_techs(active)
			## 剑圣：买的是一条**兵种级**科技，但落点是"每队的 0 号槽位"（见 `_spawn_one_squad_unit()` 的说明）
			## ⇒ 这里把场上已有的剑盾兵按槽位补标一遍（新出生的兵在出生那一支已经标好了）。
			if type_id == "sword" and int(unit.get_meta("squad_slot", -1)) == 0:
				unit.set_saint(has_tech(type_id, "sword_saint"))

## 把**全部**科技推给场上的我方单位（撤销重建之后用：那时单位是刚生成的，走的是出生那一支；
## 这里是给"读档 / 状态回滚"留的兜底入口，幂等）。
func apply_all_techs() -> void:
	for type_id in GameConfig.ROGUELIKE_TECH_TYPES:
		apply_techs_to_type(String(type_id))

## 第 `index` 队升到下一级所需的经验。1→2 = 一队总权重，之后每一级在这个基数上加 50%。
## 已满级 ⇒ 0。基数仍是编制数 × 单价权重，不是单个兵的权重。
func squad_xp_cost(index: int) -> int:
	if index < 0 or index >= squads.size():
		return 0
	return GameConfig.roguelike_squad_xp_cost(squad_level(index), int(squads[index]["weight"]))

## 第 `index` 队当前的经验（满级时回落到 0 —— 满级不再攒经验）
func squad_xp(index: int) -> int:
	if index < 0 or index >= squads.size():
		return 0
	return int(squads[index].get("xp", 0))

## 「精英招募」生效时给**刚买下的**那一队 +1 级（用户："本回合招募的兵种等级增加1级"，
## 价 10、只给"买"的、封顶 9 级）。⚠️ 抽成函数是因为"买"这条路上**只有一处**叫它 —— 起手白送、
## 复活补位都**不**经过它（用户裁决"只给买的"）。
func _apply_elite_recruit(index: int) -> void:
	if not has_round_buff(GameConfig.ROGUELIKE_ROUND_BUFF_ELITE):
		return
	if index < 0 or index >= squads.size():
		return
	var lv := mini(squad_level(index) + 1, GameConfig.ROGUELIKE_LEVEL_MAX)
	if lv <= squad_level(index):
		return
	squads[index]["level"] = lv
	var living := _living_slots(index)
	for slot in living.keys():
		var raw = living[slot]
		if raw != null and is_instance_valid(raw):
			(raw as Unit3D).set_level(lv)

## **经验满 + 准备阶段 + 补给够** ⇒ 能点升级。返回空串 = 能升。
## 用户口径："满经验时可以在步兵阶段选中单位进行升级，升级价格为该队兵总权重的一半
##（即在数值上可以看作与该队兵种解锁价格相同）" ⇒ 价 = `roguelike_unlock_price(总权重)`（同一个公式）。
func upgrade_block_reason(index: int) -> String:
	if index < 0 or index >= squads.size():
		return "没有选中队伍"
	if phase != Phase.PREPARE:
		return "只能在准备阶段升级"
	if squad_level(index) >= GameConfig.ROGUELIKE_LEVEL_MAX:
		return "已经是最高等级（%d 级）" % GameConfig.ROGUELIKE_LEVEL_MAX
	if squad_xp(index) < squad_xp_cost(index):
		return "经验不足：%d / %d" % [squad_xp(index), squad_xp_cost(index)]
	var price := upgrade_price(index)
	if supply < price:
		return "补给不足：升级要 %d，还剩 %d" % [price, supply]
	return ""

## 升一级的价格 = **该队兵种的解锁价**（用户："升级价格为该队兵总权重的一半（即在数值上可以看作与该队兵种
## 解锁价格相同）"）⇒ 直接复用 `GameConfig.roguelike_unlock_cost()`，**不另写一遍 ⌊÷2⌋**（那必然漂移）。
func upgrade_price(index: int) -> int:
	if index < 0 or index >= squads.size():
		return 0
	if RoguelikeAid.module_free_upgrade(self, index):
		return 0
	return upgrade_price_of(String(squads[index]["type_id"]))

## 这一兵种升一级要的补给。和已经在场上的那一队用同一个价。
func upgrade_price_of(type_id: String) -> int:
	return maxi(GameConfig.roguelike_unlock_cost(type_id) + RoguelikeAid.upgrade_delta(self, type_id), 0)

## 升一级（用户口径 2 的第二半）：**扣补给 → 等级 +1 → 经验清零**（"升级后经验条空余了才能再次获得经验"），
## 并把新等级落到**这一队场上还活着的每个兵**身上（`set_level()` 会按新倍率重算血量上限）。
func upgrade_squad(index: int) -> bool:
	var reason := upgrade_block_reason(index)
	if reason != "":
		last_message = reason
		return false
	_push_undo("%s 升级" % GameConfig.profile_name(String(squads[index]["type_id"])))   ## 撤销点：升级
	var price := _apply_squad_upgrade(index)
	var lv := squad_level(index)
	last_message = "%s 升到 %d 级（花 %d 补给；攻 / 血 ×%d）" % [
			GameConfig.profile_name(String(squads[index]["type_id"])), lv, price, lv]
	return true

## 当前补给够付的、经验已满的同类型队伍。按队伍顺序能付几队算几队。
func upgrade_same_type_plan(type_id: String) -> Dictionary:
	var indexes: Array = []
	var budget := supply
	var price := 0
	for i in range(squads.size()):
		if String(squads[i]["type_id"]) != type_id:
			continue
		if upgrade_block_reason(i) != "":
			continue
		var one := upgrade_price(i)
		if budget < one:
			continue
		budget -= one
		price += one
		indexes.append(i)
	return {"count": indexes.size(), "price": price, "indexes": indexes}

## 把选中兵种里所有现在升得起的队伍各升一级。一次操作，撤一步就一起回去。
func upgrade_same_type(index: int) -> bool:
	if index < 0 or index >= squads.size():
		last_message = "没有选中队伍"
		return false
	var type_id := String(squads[index]["type_id"])
	var plan := upgrade_same_type_plan(type_id)
	var indexes: Array = plan["indexes"]
	if indexes.is_empty():
		var reason := upgrade_block_reason(index)
		last_message = reason if reason != "" else "没有可以升级的同类型队伍"
		return false
	_push_undo("升级全部 %s" % GameConfig.profile_name(type_id))
	for raw in indexes:
		_apply_squad_upgrade(int(raw))
	last_message = "%s 升了 %d 队（花 %d 补给）" % [
			GameConfig.profile_name(type_id), int(plan["count"]), int(plan["price"])]
	return true

func _apply_squad_upgrade(index: int) -> int:
	var price := upgrade_price(index)
	supply -= price
	squads[index]["supply_spent"] = int(squads[index].get("supply_spent", 0)) + price
	squads[index]["level"] = squad_level(index) + 1
	squads[index]["xp"] = 0
	var lv := squad_level(index)
	var living := _living_slots(index)
	for slot in living.keys():
		var raw = living[slot]
		if raw != null and is_instance_valid(raw):
			(raw as Unit3D).set_level(lv)
	return price

const UPGRADE_MARK_LIFT := 3.6
var _upgrade_marks: Array[Node3D] = []

## 准备阶段里，每一队现在就能升级的，在队形中心上方放一个标记。开战就收掉。
func _refresh_upgrade_marks() -> void:
	var show := phase == Phase.PREPARE and starter_chosen
	var used := 0
	if show:
		for index in range(squads.size()):
			if upgrade_block_reason(index) != "":
				continue
			var mark := _upgrade_mark_at(used)
			used += 1
			mark.visible = true
			mark.global_position = _squad_mark_pos(index)
	for i in range(used, _upgrade_marks.size()):
		_upgrade_marks[i].visible = false

func _upgrade_mark_at(slot: int) -> Node3D:
	while _upgrade_marks.size() <= slot:
		var label := Label3D.new()
		label.name = "UpgradeMark"
		label.text = "▲"
		label.font_size = 96
		label.modulate = Color(1.0, 0.78, 0.15)
		label.outline_modulate = Color(0.15, 0.08, 0.0)
		label.outline_size = 16
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.012
		label.top_level = true
		add_child(label)
		_upgrade_marks.append(label)
	return _upgrade_marks[slot]

func _squad_mark_pos(index: int) -> Vector3:
	var centers := _squad_centers(squads[index])
	if centers.is_empty():
		return Vector3(0.0, UPGRADE_MARK_LIFT, 0.0)
	var sum := Vector3.ZERO
	for point in centers:
		sum += point
	var at := sum / float(centers.size())
	at.y = UPGRADE_MARK_LIFT
	return at

## **击杀发经验**（用户口径 2 的前半）：击杀者所在的那一队拿"被杀单位的权重 × 它的等级"点经验。
## ⚠️ 三条边界：① 击杀者必须是我方**队伍单位**（有 `squad_index` meta，且那一队还在）；
## ② **经验满了就不再累积**（用户："兵种经验条一旦满了就不会再获得经验"）⇒ 夹在升级成本上；
## ③ 满级 / 满经验时也照常"记一笔在反馈行"，让玩家知道这条链路是活的。
func _award_kill_xp(dead: Unit3D) -> void:
	var killer := dead.killer()
	if killer == null or not is_instance_valid(killer) or killer.team != 0 or not killer.has_meta("squad_index"):
		return
	## 腐化师的经验来自策反，不来自击杀。
	if killer.is_corruptor():
		return
	if bool(killer.aid_mods.get("no_kill_xp", false)):
		return
	var index := int(killer.get_meta("squad_index"))
	var gain := int(GameConfig.profile(String(dead.type_id))["weight"]) * maxi(dead.level, 1)
	gain = int(round(float(gain) * float(killer.aid_mods.get("xp_mult", 1.0))))
	if gain <= 0:
		return
	_add_squad_xp(index, gain, "击杀 %s（%d 级）" % [
			GameConfig.profile_name(String(dead.type_id)), maxi(dead.level, 1)])

## 策反发经验。总额仍是「对方权重 × 等级」。多名腐化师一起策反时，每人一份，向上取整。
func award_convert_xp(turned: Unit3D, squad_indexes: Array) -> void:
	if turned == null or not is_instance_valid(turned) or squad_indexes.is_empty():
		return
	var gain := int(GameConfig.profile(String(turned.type_id))["weight"]) * maxi(turned.level, 1)
	if gain <= 0:
		return
	var share := ceili(float(gain) / float(squad_indexes.size()))
	var label := "策反 %s（%d 级）" % [
			GameConfig.profile_name(String(turned.type_id)), maxi(turned.level, 1)]
	for raw in squad_indexes:
		_add_squad_xp(int(raw), share, label)

func _add_squad_xp(index: int, gain: int, cause: String) -> void:
	if index < 0 or index >= squads.size() or gain <= 0:
		return
	var cost := squad_xp_cost(index)
	if cost <= 0:
		return
	var before := squad_xp(index)
	if before >= cost:
		last_message = "%s 经验已满（%d / %d）—— 准备阶段点【升级】" % [
				GameConfig.profile_name(String(squads[index]["type_id"])), before, cost]
		return
	var after := mini(before + gain, cost)
	squads[index]["xp"] = after
	last_message = "%s：%s 得 %d 经验（%d / %d）" % [
			cause, GameConfig.profile_name(String(squads[index]["type_id"])), gain, after, cost]

## 「自我复制」：生出**击杀者自己的兵种**，等级与击杀者相同。
## 影魔要累计 5 权重才生 1 个，同时最多 1 个；别的兵种仍按被杀者权重生，一次最多 `ROGUELIKE_REPLICATE_CAP` 个。
## 生出来的不进队伍格子，自己不再复制，打死它们也不给别人计数。回合结束清掉。
func _replicate_from_kill(dead: Unit3D) -> void:
	var killer := dead.killer()
	if killer == null or not is_instance_valid(killer) or not killer.has_tech("replicate"):
		return
	if arena == null:
		return
	var count := killer.replicate_spawn_count(dead)
	if count <= 0:
		return
	var spawn_type := killer.type_id
	for i in count:
		var angle := TAU * float(i) / float(count)
		var at := dead.global_position + Vector3(cos(angle), 0.0, sin(angle)) * GameConfig.ROGUELIKE_REPLICATE_SPREAD
		var spawned := arena.spawn_unit(killer.team, spawn_type, at, killer.rotation.y)
		if spawned == null:
			continue
		spawned.set_meta("replicated", true)
		spawned.set_meta("replicate_owner", killer.get_instance_id())
		_grant_defense_bonus(spawned)
		spawned.set_techs(tech_active_for(spawn_type))
		spawned.set_level(killer.level)
		spawned.active = arena.skirmish_elapsed_ms() >= 0

## 「弃马人」：轻骑兵死后，原地留下一名同等级的长矛兵。
## 科技 = 这名轻骑兵身上的全部 + 本局已经激活的长矛科技。只在轻骑兵身上生效，下地的人不会再弃一次马。
func _dismount_from(dead: Unit3D) -> void:
	if dead.type_id != "lightcav" or not dead.keeps_tech("dismount"):
		return
	if arena == null:
		return
	var facing := -dead.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3.RIGHT
	var at := dead.global_position + facing.normalized() * 1.2
	var spawned := arena.spawn_unit(dead.team, "spear", at, dead.rotation.y)
	if spawned == null:
		return
	spawned.set_meta("dismounted", true)
	_grant_defense_bonus(spawned)
	spawned.set_techs(dead.dismount_loadout(tech_active_for("spear")))
	spawned.set_level(dead.level)
	spawned.active = arena.skirmish_elapsed_ms() >= 0

func _clear_replicates() -> void:
	if arena == null:
		return
	for node in arena.units.duplicate():
		var unit := node as Unit3D
		if unit != null and is_instance_valid(unit) and (unit.has_meta("replicated") or unit.has_meta("dismounted") or unit.has_meta("brood") or unit.has_meta("afterimage") or unit.has_meta("summoned")):
			unit.queue_free()

## **买兵时的"从天上掉下来"**（2026-09-27 用户："新增动画购买兵种时令这一队兵种从天上掉下来
##（匀速，只是动画，0.5s内播放完）"）。
## ⚠️ **只有"买"这条路径调它**（用户在同一轮的选项里选了"只有买的放"）—— 起手白送的两队、回合开始复活的兵
## 都**不**演这段（它们本来就在阵位上，突然从天而降反而突兀）。
## ⚠️ 纯视觉：偏移加在模型上，判定与出生高度一概不动（见 `Unit3D.play_drop_in()` 的注）。
func _play_drop_in(index: int) -> void:
	if index < 0 or index >= squads.size():
		return
	var living := _living_slots(index)
	for slot in living.keys():
		var raw = living[slot]
		if raw == null or not is_instance_valid(raw):
			continue
		(raw as Unit3D).play_drop_in(GameConfig.UNIT_DROP_MS, GameConfig.UNIT_DROP_HEIGHT)

## 这一队**还活着**的兵：`{槽位 -> Unit3D}`（阵亡的槽位不在里面 ⇒ 复活时按"缺哪个补哪个"处理）
func _living_slots(index: int) -> Dictionary:
	var out := {}
	if arena == null:
		return out
	for unit in arena.units:
		var u: Unit3D = null
		if unit != null and is_instance_valid(unit):
			u = unit as Unit3D
		if u == null or not u.alive or u.team != 0 or not u.has_meta("squad_index"):
			continue
		if int(u.get_meta("squad_index")) != index:
			continue
		out[int(u.get_meta("squad_slot"))] = u
	return out

## 在**己方（0 队 = 西）半场**找一块放得下这一队外框的空地，返回外框的锚点格（"西北角"）。
## ⚠️ **2026-09-27 用户口径**："自动落位现在优先把第一队摆在我方场地中间" ⇒ 扫描顺序从
## "先纵深再横排（= 从底线贴墙码起）"改成 **以己方半场的中心为原点、由近及远**（见 `_anchor_order()`）；
## 仍然**稳定可复现**（同一串操作永远摆出同一个阵：距离相同时按"行 → 列"定序）。
## ⚠️ 与落点判定同步去掉了 1 格边距（`_fits_in_home_half()` 的注里有安全论证）⇒ 自动落位也能用最外那一圈。
## ⚠️ 场地的行里**含南北两条带子** ⇒ 扫描范围必须夹在**主场地**那 44 行里
##（`_field_row_range()`），否则自动落位会把新买的兵直接摆进带子（那是"敌方地盘"，要玩家自己拖过去）。
## 返回 `Vector2i(-1, -1)` = 放不下。
func _free_anchor(weight: int, rotated: bool = false) -> Vector2i:
	var fp := _footprint(weight, rotated)
	var width := fp.x
	var depth := fp.y
	if width <= 0 or depth <= 0:
		return Vector2i(-1, -1)
	for anchor in _anchor_order(width, depth):
		if _is_free(anchor.x, anchor.y, width, depth):
			return anchor
	return Vector2i(-1, -1)

## 己方半场里所有**放得下这个外框**的锚点，按"**离己方半场中心由近及远**"排序（用户口径：第一队摆中间）。
## ⚠️ 三个要点：
##   ① 中心 = **外框中心**离半场中心（`half/2` 列、主场地正中那行）的距离 —— 用外框中心而不是锚点，
##      否则大编队会被"锚点靠中间"骗到偏一边；
##   ② 平局按 **行 → 列** 定序（不用 `sort_custom` 的比较函数里再比浮点，避免帧间抖动）⇒ **可复现**；
##   ③ 只在**合法范围**内枚举（列 ∈ 己方半场、行 ∈ 主场地 44 行）⇒ 与 `_fits_in_home_half()` 同一套界。
func _anchor_order(width: int, depth: int) -> Array:
	var half := _grid_cols() / 2
	var field_rows := _field_row_range()
	var max_col := half - depth
	var max_row := field_rows.y - width + 1
	if max_col < 0 or max_row < field_rows.x:
		return []
	var center_col := float(half) * 0.5
	var center_row := (float(field_rows.x) + float(field_rows.y)) * 0.5
	var out: Array = []
	for col in range(0, max_col + 1):
		for row in range(field_rows.x, max_row + 1):
			var block_col := float(col) + float(depth) * 0.5
			var block_row := float(row) + float(width) * 0.5
			var dx := block_col - center_col
			var dy := block_row - center_row
			out.append({"anchor": Vector2i(col, row), "d2": dx * dx + dy * dy})
	out.sort_custom(func(a, b):
		if not is_equal_approx(a["d2"], b["d2"]):
			return a["d2"] < b["d2"]
		var aa: Vector2i = a["anchor"]
		var bb: Vector2i = b["anchor"]
		if aa.y != bb.y:
			return aa.y < bb.y
		return aa.x < bb.x)
	var anchors: Array = []
	for item in out:
		anchors.append(item["anchor"])
	return anchors

## 这块外框能不能放：格子要么**没占**、要么占的就是**本队自己**（`ignore_index` = 拖动时忽略自己原来的格）。
func _is_free(col: int, row: int, width: int, depth: int, ignore_index: int = -999) -> bool:
	for c in range(col, col + depth):
		for r in range(row, row + width):
			var owner := int(_occupied.get("%d,%d" % [c, r], -999))
			if owner != -999 and owner != ignore_index:
				return false
	return true

## 把一块矩形格子写上占位值（`value` = 队序号；**`-1` 留给建筑**，如指挥所）
func _fill_cells(col: int, row: int, cols: int, rows: int, value: int) -> void:
	for c in range(col, col + cols):
		for r in range(row, row + rows):
			_occupied["%d,%d" % [c, r]] = value

## 一队占的格子 = 每个兵那 `unit_depth × unit_width` 的格块，值 = **队序号**（清的时候只清自己那一份）。
func _occupy_squad(info: Dictionary, index: int) -> void:
	var ext := _unit_extent(int(info["weight"]), bool(info.get("rotated", false)))
	for raw in _unit_cells(info):
		var c: Vector2i = raw
		_fill_cells(c.x, c.y, ext.y, ext.x, index)

## 释放一队的格子：**扫全表、只清值等于本队序号的格** ⇒ 不管这一队搬过几次家、形状改没改
##（拖动中可以改旋转 ⇒ 形状会变），都不会留下"幽灵占格"，也不会误伤指挥所（值 −1）或别的队。
func _vacate_squad(index: int) -> void:
	for key in _occupied.keys():
		if int(_occupied[key]) == index:
			_occupied.erase(key)

# ---------------------------------------------------------------- 场地格子（本模式自建，零碰撞）
## 2.0 m 的格子线：**一件** `ArrayMesh`（`PRIMITIVE_LINES`）画完 —— 零碰撞、不参与玩法，
## 连材质都用 `unshaded`（不吃光，观感是"地上的标注"而不是"场上的几何"）。
## ⚠️ 用 `ArrayMesh` 而**不是** `ImmediateMesh`：后者是"每帧重建"的类型（画一次就没了），
## 而这块格子要一直在那儿 —— 静态网格一次建好、之后只切 `visible`。
## ⚠️ 用户 2026-09-26 裁决："**肉鸽自己建**" ⇒ `Arena` 一行不动（场地那边只认"边界墙之外的风景"）。
## ⚠️ 只在 `PREPARE` 显示（`_set_grid_visible()`），开战就收掉。
func _build_grid() -> void:
	if _grid != null:
		return
	_grid = Node3D.new()
	_grid.name = "PlacementGrid"
	add_child(_grid)
	var cols := _grid_cols()
	var rows := _grid_rows()
	var cell := GameConfig.ROGUELIKE_CELL_SIZE
	var verts := PackedVector3Array()
	for c in range(cols + 1):
		var x := -arena.half_x + float(c) * cell
		verts.append(Vector3(x, GRID_LIFT, -arena.half_z))
		verts.append(Vector3(x, GRID_LIFT, arena.half_z))
	for r in range(rows + 1):
		var z := -arena.half_z + float(r) * cell
		verts.append(Vector3(-arena.half_x, GRID_LIFT, z))
		verts.append(Vector3(arena.half_x, GRID_LIFT, z))
	## ---- 第七块（2026-09-27 订正版）：两条带子就在这个矩形里，格子线已经自动铺到了 ----
	## 唯一要补的是**主场地与带子之间那条分界线**（z = ±主场地半深）：它是"能不能布阵"的可见分界，
	## 也是玩家判断"我的兵站在哪一侧"的参照。纯表现，零碰撞。
	var field_rows := _field_row_range()
	for edge_row in [field_rows.x, field_rows.y + 1]:
		var z := -arena.half_z + float(edge_row) * cell
		verts.append(Vector3(-arena.half_x, GRID_LIFT, z))
		verts.append(Vector3(arena.half_x, GRID_LIFT, z))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var lines := MeshInstance3D.new()
	lines.name = "GridLines"
	lines.mesh = mesh
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = GRID_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.material_override = mat
	_grid.add_child(lines)
	## 第四块：再叠三层填充 —— `GridCells`（可部署的格子，很淡）、`GridTaken`（被占的格子，更深）、
	## `GridPreview`（拖动候选格，跟着光标走）。三层都是半透明、不吃光、无碰撞。
	_cells = _make_cell_layer("GridCells", CELL_FREE)
	_cells_taken = _make_cell_layer("GridTaken", CELL_TAKEN)
	_cells_taken_movable = _make_cell_layer("GridTakenMovable", CELL_TAKEN_MOVABLE)
	_preview = _make_cell_layer("GridPreview", CELL_OK)
	_grid.add_child(_cells)
	_grid.add_child(_cells_taken)
	_grid.add_child(_cells_taken_movable)
	_grid.add_child(_preview)
	## 第七块：两条布阵带各一层（**我们能布阵的那段** / **只有敌方能用那段** / **中间死区**，
	## 三段权利不同 ⇒ 不用区分的话玩家会以为自己也能往己方那段里摆）。
	_cells_zone_ours = _make_cell_layer("GridZoneOurs", CELL_ZONE_OURS)
	_cells_zone_theirs = _make_cell_layer("GridZoneTheirs", CELL_ZONE_THEIRS)
	_cells_zone_dead = _make_cell_layer("GridZoneDead", CELL_ZONE_DEAD)
	_grid.add_child(_cells_zone_ours)
	_grid.add_child(_cells_zone_theirs)
	_grid.add_child(_cells_zone_dead)

## 格子**填充层**：一个 `MeshInstance3D` 画一层格子，颜色 = 材质的 `albedo_color`（**不用顶点色**，理由见
## `CELL_FREE` 上面那段）。⚠️ 两面都画（`CULL_DISABLED`）：这是贴地的色块，从任何角度看都该看得见 ——
## 俯视时"背面剔除"会把整层抹掉。
func _make_cell_layer(layer_name: String, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = layer_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	return node

## 往顶点数组里塞一格（每格往里缩 `CELL_INSET` ⇒ 格子线还露得出来；整层一个颜色 ⇒ 颜色在材质上）
func _append_cell_quad(verts: PackedVector3Array, col: int, row: int, lift: float) -> void:
	var cell := GameConfig.ROGUELIKE_CELL_SIZE
	var a := _cell_center(col, row)
	var x0 := a.x - cell * 0.5 + CELL_INSET
	var x1 := a.x + cell * 0.5 - CELL_INSET
	var z0 := a.z - cell * 0.5 + CELL_INSET
	var z1 := a.z + cell * 0.5 - CELL_INSET
	verts.append(Vector3(x0, lift, z0))
	verts.append(Vector3(x1, lift, z0))
	verts.append(Vector3(x1, lift, z1))
	verts.append(Vector3(x0, lift, z0))
	verts.append(Vector3(x1, lift, z1))
	verts.append(Vector3(x0, lift, z1))

func _push_cell_mesh(layer: MeshInstance3D, verts: PackedVector3Array) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	if verts.is_empty():
		layer.mesh = null                     ## 一格都不画（如"没在拖动"时的预览层）
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	layer.mesh = mesh

## 重画**占位填充**：己方半场每格一块，**分成两层** —— 空 = `GridCells`（`CELL_FREE`，很淡）、
## 被占 = `GridTaken`（`CELL_TAKEN`，**更深**）。用户口径："被单位占据的格子颜色比可部署的格子颜色深"。
## 指挥所那 3×3 也是"被占"（它在 `_occupied` 里占着，值 −1）。
## ⚠️ 2026-09-27 订正后："己方半场"= **主场地**（`_field_row_range()`）里靠西那一半 —— 别用整个竞技场的
## 行数，否则南北两条带子会被当成"可自由部署的己方半场"染成淡色。
## ⚠️ 2026-09-27 再加一档（用户："能移动的兵种格子用更加艳丽的绿色，不能移动用现在的深绿色"）：
## 被占的格子按 `squad_movable(owner)` **分两层** —— 能拖的那几队走 `GridTakenMovable`（艳丽绿）。
func _rebuild_cells() -> void:
	if _grid == null:
		return
	var free := PackedVector3Array()
	var taken := PackedVector3Array()
	var taken_movable := PackedVector3Array()
	var zone_ours := PackedVector3Array()
	var zone_theirs := PackedVector3Array()
	var zone_dead := PackedVector3Array()
	var half := _grid_cols() / 2
	var field_rows := _field_row_range()
	for c in range(half):
		for r in range(field_rows.x, field_rows.y + 1):
			if _occupied.has("%d,%d" % [c, r]):
				_append_taken_cell(taken, taken_movable, c, r)
			else:
				_append_cell_quad(free, c, r, CELL_LIFT)
	## 第七块（订正版）：南北两条带子各铺一层 —— **我方能用**的那段（敌方底线往内 3/4）= 琥珀、
	## 只有**敌方能用**的那段（己方底线往内 3/4）= 暗红、**中间那段（两边都不能布阵）= 中性灰**。
	## ⚠️ 2026-09-27 第二次订正后两条带子各 56.25 m、**不重叠**，中间留 19 格死区（用户："从敌方场地底线
	## 延伸到敌方场地四分之三处"）⇒ 所以这里必须三分支，不能再按"非我即敌"两分支染。
	## **被占的格子照旧走"更深"的那一层** —— 占位记账与颜色是一件事的两种看法，别让带子里的兵"看不见"。
	var cols := _grid_cols()
	var foe_cols := _zone_col_range(0)          ## 我方（0 队）能布阵的那段 = 敌方底线起算
	var own_cols := _zone_col_range(1)          ## 只有敌方（1 队）能布阵的那段 = 己方底线起算
	for side in [-1, 1]:
		var bands := _zone_row_range(side)
		for r in range(bands.x, bands.y + 1):
			for c in range(cols):
				if _occupied.has("%d,%d" % [c, r]):
					_append_taken_cell(taken, taken_movable, c, r)
				elif c >= foe_cols.x and c <= foe_cols.y:
					_append_cell_quad(zone_ours, c, r, CELL_LIFT)
				elif c >= own_cols.x and c <= own_cols.y:
					_append_cell_quad(zone_theirs, c, r, CELL_LIFT)
				else:
					_append_cell_quad(zone_dead, c, r, CELL_LIFT)
	_push_cell_mesh(_cells, free)
	_push_cell_mesh(_cells_taken, taken)
	_push_cell_mesh(_cells_taken_movable, taken_movable)
	_push_cell_mesh(_cells_zone_ours, zone_ours)
	_push_cell_mesh(_cells_zone_theirs, zone_theirs)
	_push_cell_mesh(_cells_zone_dead, zone_dead)

## 把一个"被占"的格子放进对应的那一层：**能移动的那几队**（`squad_movable(owner)`）走
## `movable`（`CELL_TAKEN_MOVABLE`，艳丽绿）、其余（不能移动的队 + 建筑 `−1`）走 `plain`（`CELL_TAKEN`）。
## ⚠️ 抽出来是因为 `_rebuild_cells()` 里**两处**都要走这套判断（主场地那一半 + 南北两条带子），
## 各写一份必然漂移（用户口径要的是"一眼看出哪些还能拖"，两处不一致就白做了）。
func _append_taken_cell(plain: PackedVector3Array, movable: PackedVector3Array, col: int, row: int) -> void:
	var owner := int(_occupied.get("%d,%d" % [col, row], -999))
	if squad_movable(owner):
		_append_cell_quad(movable, col, row, CELL_LIFT)
	else:
		_append_cell_quad(plain, col, row, CELL_LIFT)

## 重画**拖动预览**：候选位置上那整块外框（绿 = 放得下 / 红 = 放不下）。
## ⚠️ 用户裁决："不能被放置则把**预览（光标下）那几格**标红" ⇒ 标红的是**候选那几格**，
## 不是这一队原来占的格子；"松开鼠标自动回到原来位置"= 单位根本没离开过（见 `_end_press()`）。
## ⚠️ 红 / 绿是同一个层、只换材质的 `albedo_color`（层名保持 `GridPreview`，免得节点名跟着状态变）。
func _rebuild_preview() -> void:
	if _grid == null or _preview == null:
		return
	var verts := PackedVector3Array()
	if _drag_squad >= 0 and _dragging and _drag_anchor != Vector2i(-1, -1):
		var cand := _drag_candidate()
		if not cand.is_empty():
			var fp := _footprint(int(cand["weight"]), bool(cand["rotated"]))
			var mat := _preview.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = CELL_OK if _drag_valid else CELL_BAD
			for col in range(_drag_anchor.x, _drag_anchor.x + fp.y):
				for row in range(_drag_anchor.y, _drag_anchor.y + fp.x):
					_append_cell_quad(verts, col, row, PREVIEW_LIFT)
	_push_cell_mesh(_preview, verts)
	_update_ghost()                        ## 幽灵与预览同源：候选一变就一起重摆（见 `_update_ghost()`）

# ---------------------------------------------------------------- 拖动"幽灵"（跟着光标的预演）
## 拖动时在**候选格块中心**摆一排半透明盒子，让玩家在松手前就看见"会摆成什么样"。
## ⚠️ 盒子**不是**单位：它们没有碰撞体、不进 `arena.units`、不进 `_occupied`（纯表现，与格子那几层同类）。
## ⚠️ 尺寸取 `GameConfig.UNIT_BODY_BOX`（与判定体 / 血条挂点同源的那个体型盒）⇒ 大单位（载具 / boss）
## 的幽灵自然也是大的；表里没有的兵种回落到一个人形缺省盒。
func _update_ghost() -> void:
	if _grid == null:
		return
	## 只在"真拖动 + 候选锚点有效"时露出来；其余时候（点选 / 没在拖 / 光标出了场地）一律收掉。
	## ⚠️ 判据用 `_drag_anchor`（它本身就是"光标落在场内某一格"才被填上的），**不借 `_place_on_field`**
	## —— 那个标志属于"拖放道具"那条路，拿它当判据会在两条路之间串味。
	if _drag_squad < 0 or not _dragging or _drag_anchor == Vector2i(-1, -1):
		_hide_ghost()
		return
	var cand := _drag_candidate()
	if cand.is_empty():
		_hide_ghost()
		return
	_ensure_ghost(String(cand["type_id"]), _squad_centers(cand).size())
	var centers := _squad_centers(cand)
	var box := _body_box_of(String(cand["type_id"]))
	for i in range(_ghost_boxes.size()):
		var ghost: MeshInstance3D = _ghost_boxes[i]
		ghost.visible = i < centers.size()
		if not ghost.visible:
			continue
		ghost.global_position = Vector3(centers[i].x, float(box["lift"]), centers[i].z)
		## ⚠️ 幽灵用**跨模式共用**的 `GHOST_*_COLOR`（沙盒的摆兵幽灵用的是同一对），
		## 而格子那一层填充仍用自己的 `CELL_OK` / `CELL_BAD`（含透明度，另一件事）
		ghost.material_override = _ghost_material(
				GameConfig.GHOST_OK_COLOR if _drag_valid else GameConfig.GHOST_BAD_COLOR)

## 幽灵的体型盒：`UNIT_BODY_BOX` 里没登记的兵种回落到"人形缺省盒"（半径 0.38 / 高 1.80 那一档的方盒）
func _body_box_of(type_id: String) -> Dictionary:
	var box: Dictionary = GameConfig.UNIT_BODY_BOX.get(type_id, {})
	if box.has("size"):
		return {"size": Vector3(box["size"]), "lift": float(box.get("lift", 0.9))}
	return {"size": Vector3(0.9, 1.8, 0.9), "lift": 0.9}

## 按需建 / 重建幽灵盒子（队一换、槽位数一改就重建；同一队反复拖动时**一个节点都不新建**）
func _ensure_ghost(type_id: String, count: int) -> void:
	if _ghost_root == null or not is_instance_valid(_ghost_root):
		_ghost_root = Node3D.new()
		_ghost_root.name = "DragGhost"
		add_child(_ghost_root)
	if _ghost_type == type_id and _ghost_boxes.size() == count:
		return
	for raw_old in _ghost_boxes:
		var old: MeshInstance3D = raw_old
		if old != null and is_instance_valid(old):
			old.queue_free()
	_ghost_boxes.clear()
	_ghost_type = type_id
	var box := _body_box_of(type_id)
	for i in range(count):
		var ghost := MeshInstance3D.new()
		ghost.name = "Ghost_%d" % i          ## §3.1：序号写在 `_` 之后
		var mesh := BoxMesh.new()
		mesh.size = Vector3(box["size"])
		ghost.mesh = mesh
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.material_override = _ghost_material(GameConfig.GHOST_OK_COLOR)
		_ghost_root.add_child(ghost)
		_ghost_boxes.append(ghost)

func _hide_ghost() -> void:
	for raw in _ghost_boxes:
		var ghost: MeshInstance3D = raw
		if ghost != null and is_instance_valid(ghost):
			ghost.visible = false

## 幽灵的材质：与格子预览同一套语言（绿 = 放得下 / 红 = 放不下），比格子更透明一点（别挡住兵）
func _ghost_material(tint: Color) -> StandardMaterial3D:
	return _prop_material(Color(tint.r, tint.g, tint.b, 0.28))

func _set_grid_visible(on: bool) -> void:
	if _grid != null:
		_grid.visible = on

# ---------------------------------------------------------------- 指挥所（第三块）
## 摆指挥所：**每方半场两个**（用户 2026-09-26 裁决），位置 = 己方半场的纵深中间（±`ROGUELIKE_POST_X`）、
## 左右各偏 `ROGUELIKE_POST_Z`。⚠️ **"左右"按该队朝向分**（不变量 I-36）：0 队朝 +X ⇒ 左 = −Z、右 = +Z，
## 1 队镜像。左方卖**单回合**增益、右方卖**持续**增益（见 `ROGUELIKE_POST_SIDE_*`）。
## ⚠️ 它们是**建筑**：`is_roguelike_only()` 标记让它们不进任何池子、也不算"作战单位"（见 `_enemy_combatants()`）。
func _spawn_posts() -> void:
	posts_of_team = [[], []]
	for team in [0, 1]:
		var facing := GameConfig.team_spawn_sign(team) * PI * 0.5
		## 顺序 = `[左方, 右方]`：左 = 单回合增益那一座、右 = 持续增益那一座
		for i in range(2):
			var post := arena.spawn_unit(team, GameConfig.ROGUELIKE_POST_TYPE,
					_post_pos_of(team, i), facing)
			_reserve_post_cells(post)          ## 它占的那几格登记成"建筑占格"
			_grant_post_bonuses(post, team)    ## 防御指令 + 指挥部升级（**只给我方**，见函数注释）
			_apply_post_round_hp(post)
			posts_of_team[team].append(post)

## 某一队第 `i` 座指挥所的位置（`i` = 0 左方 / 1 右方；"左右"按该队朝向分，见 `_spawn_posts()` 的注释）。
## ⚠️ 抽成函数是为了"被打掉之后**原地**重建"（第四块用户口径①）：重建必须回到同一个位置，
## 否则买过的增益指向的"左 / 右"两座会串位。
func _post_pos_of(team: int, i: int) -> Vector3:
	var west: bool = team == 0
	## ⚠️ 位置从**场地尺寸**推（用户第六块口径："指挥所的位置依旧保持为己方左半场和右半场的中心"）
	## ⇒ 场地放大 1.75 倍后，指挥所自动跟着到新的半场中心（旧的写死值 25 / 9 已删除）。
	var x := -GameConfig.roguelike_post_x() if west else GameConfig.roguelike_post_x()
	var z_left := -GameConfig.roguelike_post_z() if west else GameConfig.roguelike_post_z()
	return Vector3(x, 0.0, z_left if i == 0 else -z_left)

## 指挥所占的格子登记成"**建筑占格**"（`_occupied` 的值 = −1）⇒ 兵不会被自动摆进指挥所里、
## 拖动时也放不进去（用户口径"格子被其他单位占据则无法放置"）。
## ⚠️ 占几格**从体型盒推**（`UNIT_BODY_BOX["commandpost"].size` = 6 m ⇒ 6 / 2 m 格 = 3 ⇒ 3×3），
## 不在这里另写一个 3 —— 以后改指挥所体型，这里自动跟上。
func _reserve_post_cells(post: Unit3D) -> void:
	if post == null or not is_instance_valid(post):
		return
	var box: Dictionary = GameConfig.UNIT_BODY_BOX.get(GameConfig.ROGUELIKE_POST_TYPE, {})
	var size: Vector3 = box.get("size",
			Vector3(GameConfig.ROGUELIKE_CELL_SIZE, 1.0, GameConfig.ROGUELIKE_CELL_SIZE))
	var span := maxi(int(round(maxf(size.x, size.z) / GameConfig.ROGUELIKE_CELL_SIZE)), 1)
	var half := span / 2                      ## 3 格 ⇒ 半宽 1（中心那一格算自己的）
	var c := _cell_of(post.global_position)
	_fill_cells(c.x - half, c.y - half, span, span, -1)

## 一座指挥所该带的加成：防御指令（全体生命）+ 指挥部升级（每级 +血）。
## ⚠️ **只给我方**（0 队）：增益是玩家花补给买的，敌人那两座一点不加 ——
## 旧代码在 `_spawn_posts()` 里**无条件**调 `_grant_defense_bonus()`，等于把玩家的防御指令也送给了敌方指挥所，
## 本块顺手修掉（买过防御指令后敌方指挥所白涨 12% × 级数 的血）。
func _grant_post_bonuses(post: Unit3D, team: int) -> void:
	if post == null or not is_instance_valid(post) or team != 0:
		return
	_grant_defense_bonus(post)
	var level := buff_level(GameConfig.ROGUELIKE_BUFF_UPGRADE)
	if level > 0:
		post.add_hp_bonus(GameConfig.ROGUELIKE_BUFF_HP_PER_LEVEL * float(level))


## 回合自带的指挥所等级：每级 +`ROGUELIKE_BUFF_HP_PER_LEVEL`。已经加过的不重复加。
func _apply_post_round_hp(post: Unit3D) -> void:
	if post == null or not is_instance_valid(post):
		return
	var want := GameConfig.ROGUELIKE_BUFF_HP_PER_LEVEL * float(GameConfig.roguelike_post_round_level(round_index))
	var have := float(post.get_meta("post_round_hp", 0.0))
	if want > have:
		post.add_hp_bonus(want - have)
	post.set_meta("post_round_hp", want)

# ---------------------------------------------------------------- 回合开始：把部队恢复原样（第四块用户口径①）
## 用户原文："每回合开始时复活阵亡兵种并回满血，指挥所被打掉以后在回合开始时重建"。
## ⚠️ "复活"是**按队补槽位**：一队该有几个兵（`units`）在买的时候定死 ⇒ 缺哪个槽位补哪个槽位，
## 位置 = 那个槽位本来占的格块中心（`_squad_centers()`）⇒ 打完一回合回来，阵型**原样复原**。
## ⚠️ 复活的兵走的是与买兵同一个生成函数 ⇒ 同样吃防御指令加成（不会出现"复活的兵血更少"）。
## ⚠️ 只在 `_enter_prepare()` 里调一次（那一刻战场已经结算完：`Phase.RESULT` → 下一回合）。
## ⚠️ **2026-09-27 修 bug（用户："回合开始时兵种未回到原位"）**：原先这里对活着的兵**只 `heal_to_full()`**、
## 位置一动不动 —— 于是上一场打散之后，活人留在战场原地、复活的却回到阵位（表现就是"两团兵错开"）。
## 现在活着的也走 `Unit3D.reset_to()` 摆回槽位格块中心 ⇒ **回合一开始，整队按当初的布阵原样站好**。
func _recover_army() -> void:
	if arena == null:
		return
	var facing := GameConfig.team_spawn_sign(0) * PI * 0.5
	for index in range(squads.size()):
		var info: Dictionary = squads[index]
		var centers := _squad_centers(info)
		var living := _living_slots(index)
		for slot in range(centers.size()):
			var unit: Unit3D = null
			if living.has(slot):
				unit = living[slot] as Unit3D
			if unit != null and is_instance_valid(unit) and unit.alive:
				unit.heal_to_full()                      ## 活着的：回满血（用户口径"回满血"）
				unit.reset_to(centers[slot], facing)     ## 2026-09-27：**并摆回阵位**（上面那段的 bug 修复）
				continue
			_spawn_one_squad_unit(info, index, slot, centers[slot], facing)
	_revive_posts()
	RoguelikeAid.paint_all(self)

## 指挥所被打掉 ⇒ 回合开始时**原地重建**（用户口径①）。
## ⚠️ 两队都重建：敌人半场那两座同样是"指挥所"（我方部队打的就是它们），重建才谈得上"每回合都有的打"。
## ⚠️ **2026-09-26 第四块（用户："指挥部每回合开始时回满血"）**：活着的指挥所也一起回满 ——
## 这一条**推翻了第三块当时的判断**（那时按"只有兵种回满"实现）。连带事实：既然每回合都满血，
## "指挥所被摧毁 ⇒ 该队全体吃减益"（`09_roguelike.md#9.2`）就只在**同一场战斗之内**被打掉时才可能触发
##（那是战斗中的事，本函数在回合开始跑，不受影响）。
func _revive_posts() -> void:
	for team in [0, 1]:
		var list: Array = posts_of_team[team]
		while list.size() < 2:
			list.append(null)                     ## 兜底：正常流程不会走到
		for i in range(2):
			var raw = list[i]
			var old: Unit3D = null
			if raw != null and is_instance_valid(raw):
				old = raw as Unit3D
			if old != null and old.alive:
				_apply_post_round_hp(old)
				old.heal_to_full()                ## 用户 2026-09-26：指挥所每回合开始回满血
				continue
			var post := arena.spawn_unit(team, GameConfig.ROGUELIKE_POST_TYPE,
					_post_pos_of(team, i), GameConfig.team_spawn_sign(team) * PI * 0.5)
			list[i] = post
			_reserve_post_cells(post)
			_grant_post_bonuses(post, team)
			_apply_post_round_hp(post)

## 我方某一座指挥所（`side` 取 `ROGUELIKE_POST_SIDE_ROUND` = 左 / `_STEADY` = 右）
func our_post(side: String) -> Unit3D:
	var list: Array = posts_of_team[0]
	if list.size() < 2:
		return null
	return list[0] if side == GameConfig.ROGUELIKE_POST_SIDE_ROUND else list[1]

## 这一座卖的是不是**单回合**增益（左方 = 是、右方 = 否）
func post_sells_round_buffs(side: String) -> bool:
	return side == GameConfig.ROGUELIKE_POST_SIDE_ROUND

## 点场地上的指挥所 ⇒ 打开/切换它的增益面板（界面每 100 ms 轮询 `selected_post`）。
## ⚠️ 只在 `PREPARE` 且**已选起手部队**时认（别的时候要么光标被锁、要么商店还没出来）。
func select_post(side: String) -> void:
	selected_post = side
	if side != "":
		selected_foe_squad = -1      ## 与"查看敌方"互斥（同一块面板）

## 屏幕坐标下面是哪一座**我方**指挥所（返回 `"left"` / `"right"`；空串 = 没点到）。
## ⚠️ 射线只打"两队单位层"（`PICK_MASK`），命中的是单位节点 ⇒ 再核一次类型与队伍。
func post_side_at(screen_pos: Vector2) -> String:
	var cam: Camera3D = camera_rig.camera() if camera_rig != null else null
	if cam == null or arena == null:
		return ""
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * PICK_RANGE, PICK_MASK)
	query.collide_with_areas = false
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var unit := hit["collider"] as Unit3D
	if unit == null or not is_instance_valid(unit) or not unit.alive:
		return ""
	if String(unit.type_id) != GameConfig.ROGUELIKE_POST_TYPE or unit.team != 0:
		return ""
	var list: Array = posts_of_team[0]
	for i in range(list.size()):
		if list[i] == unit:
			return GameConfig.ROGUELIKE_POST_SIDE_ROUND if i == 0 else GameConfig.ROGUELIKE_POST_SIDE_STEADY
	return ""

# ---------------------------------------------------------------- 布阵交互（第四块：点选 / 拖动 / 右键旋转）
## 用户口径（原文）：
##   ③ "点击我方单位可以选中这一队单位，查看其最终数值（比如攻击、血量，要把增益的增幅也算进去）"
##   ④ "靠拖动单位可以移动其位置（单位必须限定在格子内，格子被其他单位占据则无法放置），
##      但只有当回合购买的兵能够移动位置"；补充："被单位占据的格子颜色比可部署的格子颜色深"、
##      "移动时若现在拖动的位置不能被放置则把…标为红色，松开鼠标时自动回到原来位置"
##   ⑤ 先："选中单位或拖动单位时按 R 可以使单位的布阵旋转 90°（如横着变成竖着），
##      但单位的方向依旧是面向敌方"；**随后两次改口：只有拖动移动单位时才转、R 改成鼠标右键**
##      —— 本文件按改口后的口径实现（旋转只在拖动中、触发键 = 右键）。
## ⚠️ 表现取舍（已向用户报备）：拖动时**单位不跟着光标走**，跟着走的是"候选格子的颜色预览"
##   （绿 = 放得下 / 红 = 放不下）；松开鼠标时放得下就整队瞬移过去、放不下就什么都不做
##   —— 这就是"自动回到原来位置"（单位根本没离开过）。
## ⚠️ 用 `_unhandled_input()`：界面（底部商店 / 浮层）会把落在自己身上的事件吃掉，剩下的才到这里 ——
## 与沙盒布兵那条纪律完全一致（`sandbox.gd#_unhandled_input()`）。
func selection_gate() -> bool:
	return phase == Phase.PREPARE and difficulty_chosen and (not starter_chosen or aid_pending)


func _view_choice_unit(screen_pos: Vector2) -> void:
	var own := _squad_at(screen_pos)
	if own >= 0:
		select_squad(own)
		return
	var foe := _foe_at(screen_pos)
	if foe >= 0:
		select_foe(foe)
		return
	note_choice_blocked()


func note_choice_blocked() -> void:
	choice_notice = "先选择"
	_choice_notice_ms = Time.get_ticks_msec() + 1600


func choice_notice_text() -> String:
	if choice_notice == "":
		return ""
	if Time.get_ticks_msec() >= _choice_notice_ms:
		choice_notice = ""
		return ""
	return choice_notice


func _passes_choice_look(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return true
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if event.is_action("cam_forward") or event.is_action("cam_back") or event.is_action("cam_left") \
			or event.is_action("cam_right") or event.is_action("cam_up") or event.is_action("cam_down") \
			or event.is_action("cam_boost") or event.is_action("cam_overview") or event.is_action("cam_reset"):
		return true
	return event is InputEventKey and (event as InputEventKey).keycode == KEY_ALT


func _take_result_continue(event: InputEvent) -> bool:
	if get_tree().paused or (phase != Phase.ROUND_RESULT and phase != Phase.GAME_OVER):
		return false
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return false
	get_viewport().set_input_as_handled()
	var action_name := "restart_game" if phase == Phase.GAME_OVER else "next_round"
	ScreenFade.attach(self).play(Callable(self, action_name))
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _take_result_continue(event):
		return
	if choice_hidden and selection_gate():
		if _passes_choice_look(event):
			return
		if camera_rig != null and camera_rig.mode == CameraRig.Mode.OVERVIEW:
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT:
				_view_choice_unit(button.position)
			elif button.button_index != MOUSE_BUTTON_WHEEL_UP and button.button_index != MOUSE_BUTTON_WHEEL_DOWN:
				note_choice_blocked()
			else:
				return
			get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo and key.keycode != KEY_ESCAPE:
				note_choice_blocked()
				get_viewport().set_input_as_handled()
		return
	if phase != Phase.PREPARE or not starter_chosen:
		return
	## 撤销的快捷键（2026-09-27 用户："快捷键 ctrl+z"）。⚠️ 排在鼠标之前、且**不吞事件**（不 `return`）：
	## 键盘事件本来也不会被下面那几支处理。⚠️ `echo` 是操作系统的按键重复 ⇒ 按住不放不该连撤。
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_Z:
			undo_last()
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		## 画路线优先（第六块）：这两下点击**只**属于信标 —— 不选队、不点指挥所、不拖放道具。
		if _route_editing >= 0:
			if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				var ground := _ground_under_cursor(click.position)
				if ground != Vector3.INF:
					_add_route_point(ground)
			elif click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
				_route_step_back()
			return
		if click.button_index == MOUSE_BUTTON_RIGHT:
			if click.pressed:
				if _placing != "":
					cancel_place()             ## 拖放道具时右键 = **取消**（不落地、不扣补给）
				else:
					_rotate_dragging()         ## 否则右键 = 拖动中旋转布阵 90°（用户改的口径）
			return
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			if _placing == "":
				_begin_press(click.position)   ## 拖放中压在场上不当作"再选一队"
		elif _placing != "":
			finish_place()                     ## 松手落地（与 `_tick_placing()` 的轮询互为保险）
		else:
			_end_press()
		return
	if event is InputEventMouseMotion and (_drag_squad >= 0 or _press_squad >= 0):
		var motion := event as InputEventMouseMotion
		## ⚠️ 判"左键还按着"用**事件自带**的 `button_mask`，不轮询 `Input`：
		## 它记的是"这一帧事件产生时"的按键状态 ⇒ 松手落在窗口外时下一次移动就能把拖动收掉
		##（轮询全局状态在"事件是合成出来的 / 焦点刚回来"这些时刻并不可靠）。
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_reset_drag()                      ## 兜底：松手事件丢在窗口外时别让预览挂在那儿
			return
		_update_drag(motion.position)

## 左键按下：光标下有我方单位 ⇒ **选中这一队**（口径③"拖动会直接选中该单位"，不必先点一下），
## 能拖的再进入"待拖动"状态（口径④）；没点到单位 ⇒ 走老行为（点指挥所开增益面板 / 点空地收起面板）。
## ⚠️ "选中一队"与"指挥所增益面板"**互斥**：两块面板占同一片角落，同时开着会叠在一起。
func _begin_press(screen_pos: Vector2) -> void:
	var index := _squad_at(screen_pos)
	if index >= 0:
		select_squad(index)                    ## 选中 + 收掉指挥所面板（互斥）；**拖动与点选走同一条路**
		last_message = ""
		_reset_drag()                          ## 每次按下都从干净状态开始
		_press_squad = index                   ## 先记下"按在哪一队上"（含拖不动的队）—— 拖动时好给原因
		_drag_press = screen_pos               ## ⚠️ 按下点对**每一队**都要记：拖不动的那队也要靠它算"动没动"
		if squad_movable(index):
			_drag_squad = index
			_drag_rotated = bool(squads[index].get("rotated", false))
		return
	## 2026-09-27（用户："敌方单位也可以被我方选中，只用来查看信息"）：
	## 没点到我方单位 ⇒ 再看是不是**敌方的一个兵**（只读面板，不能拖也不能转）。
	## ⚠️ 排在"点指挥所"**之前**、但**不认**敌方指挥所（用户："只有兵可以，指挥所不变"）——
	## 指挥所那两个 3×3 建筑仍然走 `post_side_at()` 那条老路（只有我方的能开增益面板）。
	var foe := _foe_at(screen_pos)
	if foe >= 0:
		select_foe(foe)
		last_message = ""
		_reset_drag()
		return
	var side := post_side_at(screen_pos)
	selected_squad = -1
	selected_foe_squad = -1
	_reset_drag()
	if side != selected_post:
		selected_post = side
		last_message = ""

## 左键松开：真拖过 ⇒ 放得下就整队挪过去、放不下就什么都不做（口径④"自动回到原来位置"）；
## 没拖过（位移没超过 `ROGUELIKE_DRAG_SLOP`）⇒ 那只是一次点选，只留选中状态。
func _end_press() -> void:
	if _drag_squad >= 0 and _dragging:
		if _drag_valid:
			_push_undo("挪动 %s" % GameConfig.profile_name(String(squads[_drag_squad]["type_id"])))  ## 撤销点：换位
			_move_squad(_drag_squad, _drag_anchor, _drag_rotated)
		else:
			last_message = "这个位置放不下（格子被占 / 超出己方半场）"
	_reset_drag()
	_rebuild_cells()

## 鼠标移动（左键按住）：先判"点选还是拖动"（阈值），再更新候选锚点与红 / 绿预览。
## ⚠️ 候选锚点 = **外框以光标所在格为中心** ⇒ 拖到哪，落点就是哪一片。
## ⚠️ 拖不动的那两队（**不是本回合拿到的**）也要走到这里：给一行原因，比"拖了没反应"好。
func _update_drag(screen_pos: Vector2) -> void:
	if _drag_squad < 0:
		if _press_squad >= 0 and _press_squad < squads.size() \
				and screen_pos.distance_to(_drag_press) >= GameConfig.ROGUELIKE_DRAG_SLOP:
			last_message = "只有本回合拿到手的兵能换位置（这一队是第 %d 回合的）" \
					% int(squads[_press_squad].get("move_round", 0))
		return
	if _drag_squad >= squads.size():
		_reset_drag()
		return
	if not _dragging and screen_pos.distance_to(_drag_press) < GameConfig.ROGUELIKE_DRAG_SLOP:
		return                                 ## 还在阈值内 ⇒ 仍可能是一次点选
	_dragging = true
	var fp := _footprint(int(squads[_drag_squad]["weight"]), _drag_rotated)
	var cell := _cell_under_cursor(screen_pos)
	var anchor := Vector2i(-1, -1)
	var valid := false
	if cell != Vector2i(-1, -1):
		anchor = Vector2i(cell.x - fp.y / 2, cell.y - fp.x / 2)
		valid = _in_deploy_area(anchor, fp) and _is_free(anchor.x, anchor.y, fp.x, fp.y, _drag_squad)
	if anchor == _drag_anchor and valid == _drag_valid:
		return                                 ## 判据没变就别白重画一层网格
	_drag_anchor = anchor
	_drag_valid = valid
	_rebuild_preview()

## 右键（**只在拖动中**，用户改的口径）：把这一队的布阵旋转 90°（宽深互换，"横着变竖着"）。
## ⚠️ 旋转**只改布阵**：兵的朝向不碰 —— 它们永远面向敌方（`team_spawn_sign(0) · 90°`，I-35）。
## ⚠️ 旋转先记在 `_drag_rotated` 上、**松手且放得下才写回队信息** —— 否则"转了一下又放不下"会让
## 队信息（`rotated`）、场上实际摆法、占格登记三者对不上，下一回合复活时阵型就乱了。
func _rotate_dragging() -> void:
	if _drag_squad < 0 or _drag_squad >= squads.size() or not _dragging:
		return
	_drag_rotated = not _drag_rotated
	last_message = "布阵已旋转 90°（%s）" % ("竖" if _drag_rotated else "横")
	## 外框换了 ⇒ 候选锚点与合法性都要重判（先把旧判据清掉，免得"看起来没变"而跳过重画）
	_drag_anchor = Vector2i(-1, -1)
	_drag_valid = false
	_update_drag(get_viewport().get_mouse_position())

## 收掉拖动状态（松手 / 取消 / 重开一局）⇒ 预览层清空
func _reset_drag() -> void:
	_drag_squad = -1
	_dragging = false
	_drag_anchor = Vector2i(-1, -1)
	_drag_valid = false
	_drag_rotated = false
	_press_squad = -1
	_rebuild_preview()

## 整队挪到 `anchor`（外框与旋转一起定下来）：先清旧格、再占新格、最后把每个兵瞬移到它槽位的格块中心。
## ⚠️ 兵 ↔ 槽位的对应靠 meta（`squad_slot`），**不靠** `arena.units` 的顺序 —— 中途死过又复活过，顺序不可靠。
func _move_squad(index: int, anchor: Vector2i, rotated: bool) -> void:
	var info: Dictionary = squads[index]
	_vacate_squad(index)
	info["anchor_col"] = anchor.x
	info["anchor_row"] = anchor.y
	info["rotated"] = rotated
	_occupy_squad(info, index)
	var centers := _squad_centers(info)
	var living := _living_slots(index)
	for slot in range(centers.size()):
		var unit: Unit3D = null
		if living.has(slot):
			unit = living[slot] as Unit3D
		if unit != null and is_instance_valid(unit):
			## ⚠️ y 保持原样：单位是重力落定在地面上的，动它会埋进地里 / 弹到空中
			unit.global_position = Vector3(centers[slot].x, unit.global_position.y, centers[slot].z)
	_mark_zone_entry(index)               ## 第七块：挪进 / 挪出敌方延伸区 ⇒ 重记"是不是本回合进去的"
	last_message = "已移动 %s（%s）" % [GameConfig.profile_name(String(info["type_id"])),
			"竖" if rotated else "横"]

## 拖动中的"候选队信息"：位置 = 光标下的锚点、旋转 = 待定的那一个，其余照抄原队 —— 预览与落位共用它算格子。
func _drag_candidate() -> Dictionary:
	if _drag_squad < 0 or _drag_squad >= squads.size():
		return {}
	var src: Dictionary = squads[_drag_squad]
	return {
		"type_id": src["type_id"],
		"weight": src["weight"],
		"anchor_col": _drag_anchor.x,
		"anchor_row": _drag_anchor.y,
		"rotated": _drag_rotated,
	}

## 屏幕坐标下面是**我方哪一队**（返回队序号；`-1` = 没点到我方单位）。
## 两条路，先精确后宽松（用户 2026-09-26 **第六块**："点击兵种所占的格子也能选中（拖动同理）"）：
##   ① **射线打单位本体**（`PICK_MASK`，与点指挥所同一个掩码）—— 点得准时走它；
##   ② **落点格 → `_occupied` 反查** —— 点在**那一队占的格子里任意位置**（哪怕没碰到兵本体）也算选中。
## ⚠️ ② 是"格子那一层记账"的第二次利用（第一次是拖动落点判定）：`_occupied` 的值本来就是**队序号**
## ⇒ 一次查表就够，不必再算距离；值为 −1（建筑占格）时**不返回队伍**（指挥所仍走 `post_side_at()` 的射线）。
func _squad_at(screen_pos: Vector2) -> int:
	var cam: Camera3D = camera_rig.camera() if camera_rig != null else null
	if cam == null or arena == null:
		return -1
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * PICK_RANGE, PICK_MASK)
	query.collide_with_areas = false
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var raw = hit["collider"]
		var unit: Unit3D = null
		if raw != null and is_instance_valid(raw):
			unit = raw as Unit3D
		if unit != null and unit.alive and unit.team == 0 and unit.has_meta("squad_index"):
			var index := int(unit.get_meta("squad_index"))
			if index >= 0 and index < squads.size():
				return index
	## ② 兜底：光标落点**那一格**是谁占的？
	var point := _ground_under_cursor(screen_pos)
	if point == Vector3.INF:
		return -1
	var cell := _cell_of(point)
	var owner := int(_occupied.get("%d,%d" % [cell.x, cell.y], -1))
	if owner < 0 or owner >= squads.size():
		return -1
	return owner

## 光标在**哪一格**：先求"光标落在地面上的世界坐标"，再换算成格。
## 返回 `Vector2i(-1, -1)` = 光标不在场地里（射线朝上 / 与地面平行 / 打到场地外）。
func _cell_under_cursor(screen_pos: Vector2) -> Vector2i:
	var hit := _ground_under_cursor(screen_pos)
	if hit == Vector3.INF:
		return Vector2i(-1, -1)
	var c := _cell_of(hit)
	if not _cell_in_footprint(c):
		return Vector2i(-1, -1)
	return c

## 屏幕坐标下面是**敌方哪一队**（返回 `foe_squads` 的下标；`-1` = 没点到敌方单位）。
## 2026-09-27 用户："敌方单位也可以被我方选中，只用来查看信息"，同日裁决把敌方也做成**按队**查看。
## ⚠️ **只认兵**：敌方指挥所（`ROGUELIKE_POST_TYPE`）照样走 `post_side_at()` 那条老路 ——
## 用户裁决"只有兵可以，指挥所不变"（那两座另有增益面板的语义，混在一起会打架）。
## ⚠️ 与 `_squad_at()` 同一个拾取掩码 / 同一个射程：点得准才认（这里**不做** `_occupied` 兜底 ——
## 敌方不占我们的格子账）。
func _foe_at(screen_pos: Vector2) -> int:
	var cam: Camera3D = camera_rig.camera() if camera_rig != null else null
	if cam == null or arena == null:
		return -1
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * PICK_RANGE, PICK_MASK)
	query.collide_with_areas = false
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var raw = hit["collider"]
	var unit: Unit3D = null
	if raw != null and is_instance_valid(raw):
		unit = raw as Unit3D
	if unit == null or not unit.alive:
		return -1
	if unit.team == 0:                    ## 我方（0 队）走 `_squad_at()`，这里只认敌方
		return -1
	if String(unit.type_id) == GameConfig.ROGUELIKE_POST_TYPE:
		return -1
	if not unit.has_meta("foe_squad_index"):
		return -1                         ## 没打标的敌方单位（理论上不该有）不进这条路
	var index := int(unit.get_meta("foe_squad_index"))
	if index < 0 or index >= foe_squads.size():
		return -1
	return index

## 光标落在地面上的**世界坐标**（射线与 y = 0 平面求交）。
## ⚠️ 打的是**数学平面**而不是物理层：单位挡不住光标（拖动时鼠标扫过自己的兵不该丢目标）。
## 返回 `Vector3.INF` = 没交到（射线朝上 / 与地面平行 / 交点在身后）。
## ⚠️ 道具的落点用**连续坐标**（不吸附到格）：它们"不占用格子"（用户口径），
## 而魔法盾那个 14 m 的圆是**以圆心为准**的判定 —— 吸附到 2 m 的格只会白白丢掉精度。
func _ground_under_cursor(screen_pos: Vector2) -> Vector3:
	var cam: Camera3D = camera_rig.camera() if camera_rig != null else null
	if cam == null:
		return Vector3.INF
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := -from.y / dir.y
	if t <= 0.0:
		return Vector3.INF
	return from + dir * t

# ---------------------------------------------------------------- 场地道具（第五块：陷阱 / 魔法盾，2026-09-26）
## 用户口径（原文）：
##   陷阱 —— "当自身 8m 范围内出现敌军时，延迟 1s，然后以那名敌军为中心触发半径 10m 的爆炸，造成 200 点伤害
##            并使移动速度降低 80%，持续 3s，价格 5。陷阱只要未触发就会一直存在，直至触发后在下回合开始时移除"；
##   魔法盾 —— "与陷阱相同的放置方式，不占用格子。血量 100，不移动，不攻击。大小为 14m 半径的圆，可以抵挡所有
##            敌方的远程攻击（不会被主动锁定，火枪无法穿透），没有碰撞体积……若敌方远程在圆圈内发动攻击，
##            攻击也无法穿过魔法盾的边……价格 10……回合开始时回满血。放置时不能放置到会把敌方领地包括住的位置"。
## 用户 2026-09-26 同一批补充三条：**放置 = 从商店按钮拖到场上**（松手时位置不可部署 ⇒ 不部署、**不扣补给**）；
## 陷阱"半径 10m 内**所有敌方单位**都吃 200 + 都减速 3s"；"敌方领地" = **敌方半场（中心线以东 x > 0）**。
## ⚠️ 两件都是**肉鸽自己的场地道具**（用户裁决）⇒ 不进 `PROFILES`、不算兵种、**不在 `arena.units` 里**：
##    · "不会被主动锁定"因此是**结构上**成立的（索敌只遍历 `arena.units`）；
##    · "没有碰撞体积"同理（不建任何 `CollisionShape3D`）；
##    · 挡弹是**几何判定**（`Arrow._magic_shield_crossing()` 读 `Arena.arrow_blockers`），不走物理射线。

## 现在能不能买 / 放这一件（界面用它决定卡片灰不灰、拖不拖得动）
func prop_block_reason(kind: String) -> String:
	if phase != Phase.PREPARE:
		return "只能在准备阶段放置道具"
	if not starter_chosen:
		return "先选起手部队"
	## ⚠️ 移动信标是**两步**的（用户裁决：先在右方指挥所买、再从道具行拖到场上）⇒ 它的闸门是**拥有权**、
	## 不是补给（补给在"买"那一步已经扣过了，这里再扣一次就是收两遍钱）。
	## ⚠️ 第七块口径：买过之后**每回合免费重新部署**（不扣补给、不限次数）⇒ 这里只问"买过没有"。
	if kind == GameConfig.ROGUELIKE_PROP_BEACON:
		if not _beacon_owned:
			return "还没买：先去【右方】指挥所买一个移动信标（%d 补给，买一次永久可用）" % GameConfig.ROGUELIKE_BEACON_PRICE
		return ""
	var price := GameConfig.roguelike_prop_price(kind)
	if supply < price:
		return "补给不足：%s 要 %d，还剩 %d" % [GameConfig.roguelike_prop_name(kind), price, supply]
	return ""

## 现在能不能放这一件（`can_*` 只做"原因为空"的包装，与 `can_buy()` / `can_unlock()` 同式）
func can_place_prop(kind: String) -> bool:
	return prop_block_reason(kind) == ""

## 场上这一件还有几件（界面与探针共用）
func prop_count(kind: String) -> int:
	var total := 0
	for prop in props:
		if String(prop["kind"]) == kind:
			total += 1
	return total

## 现在正在拖放道具吗（界面用它显示"松手放下 / 右键取消"）
func is_placing() -> bool:
	return _placing != ""

## ---- 拖放（用户："直接对着按钮拖动放置"）----
## 在商店卡片上**按下**就进入拖放（**此时不扣钱**）；拖动期间预览圈跟着光标；**松手时放得下才扣钱并落地**。
## ⚠️ 拖放的整个生命周期由玩法侧自己轮询（`Roguelike._physics_process()` → `_tick_placing()`）：
## 界面只报"按下了"这一个事件。理由是**松手的位置多半在场地中央**，那个事件根本不会回到按钮上
##（`Button.button_up` 只在按钮自己的矩形内有保证）⇒ 把"结束"交给轮询，两边都不依赖事件落点。
func begin_place(kind: String) -> void:
	if not GameConfig.roguelike_prop_kinds().has(kind):
		return
	var reason := prop_block_reason(kind)
	if reason != "":
		last_message = reason
		return
	_placing = kind
	_place_pos = Vector3.ZERO
	_place_on_field = false
	_place_valid = false
	_place_press_seen = false
	last_message = "拖到场上松手放下 %s（放不下就不放、也不扣补给）" % GameConfig.roguelike_prop_name(kind)
	_build_prop_preview()
	_tick_placing()

## 取消拖放（右键 / 换回合 / 重开一局都走它）：**不扣补给、不落地**
func cancel_place() -> void:
	_cancel_place()

func _cancel_place() -> void:
	_aid_anchor_set = false
	_aid_card_index = -1
	if _placing == "":
		return
	_placing = ""
	_place_valid = false
	if _prop_preview != null and is_instance_valid(_prop_preview):
		_prop_preview.mesh = null                    ## 预览清空（节点留着，下次拖放复用）
		_prop_preview.visible = false

## 拖放期间的每物理帧：预览摆到光标下的地面点、判一次"能不能放"，**左键一松就结算**。
func _tick_placing() -> void:
	if _placing == "":
		return
	if _placing == "aid":
		RoguelikeAid._tick_place(self)
		return
	if _placing == "recall":
		_tick_recall_drag()
		return
	var hit := _ground_under_cursor(get_viewport().get_mouse_position())
	_place_on_field = hit != Vector3.INF
	if _place_on_field:
		_place_pos = hit                                 ## ⚠️ 光标离开场地时**保留上一个落点**（预览不跳回原点）
	_place_valid = _place_on_field and _place_reason(_placing, _place_pos) == ""
	_rebuild_prop_preview()
	## 松手 = 结算。⚠️ 两条保险：
	##   ① 用轮询而不是等事件（理由见 `begin_place()` 的注释）；
	##   ② **先见过"左键按着"才认松手** —— 否则"按下与松开挤在同一帧 / 探针里根本没有真按键"这两种情形
	##      会在第一帧就把拖放结算掉（落点还是原点，必然被判"不在场地上"）。
	## `_unhandled_input()` 里另外接了一条"左键松开"的事件路径，两条都指向 `finish_place()`（幂等）。
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_place_press_seen = true
	elif _place_press_seen:
		finish_place()

## 松手：放得下 ⇒ **扣补给 + 落地**；放不下 ⇒ 什么都不做。
## 用户口径："若鼠标松开时当前位置不可部署，则不进行部署并不扣除补给"。
func finish_place() -> void:
	if _placing == "aid":
		return
	if _placing == "recall":
		var index := _squad_at(get_viewport().get_mouse_position())
		_finish_recall(index)
		return
	var kind := _placing
	if kind == "":
		return
	var pos := _place_pos
	var reason := _place_reason(kind, pos) if _place_on_field else "松手的位置不在场地上"
	_cancel_place()
	if reason != "":
		last_message = reason
		return
	var price := GameConfig.roguelike_prop_price(kind)
	var is_beacon := kind == GameConfig.ROGUELIKE_PROP_BEACON
	_push_undo("放置%s" % GameConfig.roguelike_prop_name(kind))   ## 撤销点：放道具（含信标重放）
	if is_beacon:
		## ⚠️ 重新部署 = **先把场上那个撤掉**（用户第七块口径：点卡片就是重新部署 ⇒ 不允许多个信标叠加）。
		_remove_beacons("")
	else:
		supply -= price                    ## ⚠️ 信标**不在这里扣**：它在"买"那一步就付过钱了（用户裁决）
	var index := _spawn_prop(kind, pos)
	if is_beacon:
		_start_route_edit(index)          ## 放下之后接着画路线（两次点击，见 `_add_route_point()`）
		return
	last_message = "%s 已放置（−%d 补给）" % [GameConfig.roguelike_prop_name(kind), price]

## 这个落点能不能放（返回 `""` = 能；否则是人话原因）。
## ⚠️ 与 `prop_block_reason()` 分工：那条管"买得起吗 / 现在是不是准备阶段"，这条管"这一块地皮行不行"。
func _place_reason(kind: String, pos: Vector3) -> String:
	var reason := prop_block_reason(kind)
	if reason != "":
		return reason
	## ① 必须在**地块**里（留 1 m 边距，别把道具压进墙里）。⚠️ 地块 = 整个竞技场矩形
	##（主场地 + 南北两条带子；2026-09-27 订正后就是一个矩形）。
	var margin := 1.0
	if absf(pos.x) > arena.half_x - margin or absf(pos.z) > arena.half_z - margin:
		return "超出场地范围"
	## ①' **布阵带的"死区"不能放道具**（2026-09-27 用户裁决："死区不能放道具，但是算在场地内（比如移动信标
	## 可以包括那块地）"）⇒ 只禁"放道具"这一件事：单位照常能走能站、**信标路线点与 10 m 影响半径照样覆盖它**、
	## 格子照铺（`_clamp_into_field()` 也仍是整个矩形，不受这条影响）。
	var cell := _cell_of(pos)
	if _row_in_zone(cell.y) and not GameConfig.roguelike_col_in_zone(cell.x, _grid_cols()):
		return "这里在布阵带的死区里（两边都不能布阵，也放不了道具）"
	## ② 不能和别的道具叠在一起（中心距太近）
	for prop in props:
		if Vector3(prop["pos"]).distance_to(pos) < GameConfig.ROGUELIKE_PROP_MIN_SPACING:
			return "离另一件道具太近（至少 %0.1f m）" % GameConfig.ROGUELIKE_PROP_MIN_SPACING
	## ③ 魔法盾专属：**圆不能罩到敌方半场**（用户 2026-09-26 裁决："敌方领地" = 敌方半场，中心线以东 x > 0）
	if kind == GameConfig.ROGUELIKE_PROP_SHIELD:
		if pos.x + GameConfig.ROGUELIKE_SHIELD_RADIUS > 0.0:
			return "魔法盾的圆会罩到敌方半场（圆心要离中心线至少 %0.0f m）" % GameConfig.ROGUELIKE_SHIELD_RADIUS
	## ④ 陷阱专属：本体在我方半场（x ≤ 0）。8 m / 10 m 的圈可以罩进敌方。
	if kind == GameConfig.ROGUELIKE_PROP_TRAP and pos.x > 0.0:
		return "陷阱只能放在我方半场（爆炸范围可以进入敌方）"
	return ""

## ---- 道具的节拍 ----
## 每物理帧：先结算"上一帧被魔法盾挡下的弹"，再跑陷阱的"找敌军 → 上弦 → 到点爆炸"。
func _tick_props() -> void:
	if arena == null:
		return
	_poll_arrow_blocks()
	## 准备阶段场上已经有敌军。陷阱等到开战才找人、才上弦。
	if phase != Phase.FIGHTING:
		return
	var now := Time.get_ticks_msec()
	for prop in props:
		if String(prop["kind"]) != GameConfig.ROGUELIKE_PROP_TRAP or bool(prop["triggered"]):
			continue
		if int(prop["armed_ms"]) <= 0:
			var enemy := _enemy_in_trap_range(prop)
			if enemy != null:
				prop["armed_ms"] = now
				prop["target"] = enemy
				last_message = "陷阱上弦：%0.1f s 后爆炸" % (float(GameConfig.ROGUELIKE_TRAP_DELAY_MS) / 1000.0)
			continue
		if now - int(prop["armed_ms"]) >= GameConfig.ROGUELIKE_TRAP_DELAY_MS:
			_explode_trap(prop)

## 陷阱的 8 m 里有没有敌军（取**最近的那个**）。三条与既有口径一致：
##   · 只认**非建筑**的敌方单位（判据与 `_enemy_combatants()` 同源：`roguelike_only` 的指挥所不算"敌军"）；
##   · 跳过**潜地**单位（它"不可锁定 + 免疫一切状态"，踩不到陷阱）；
##   · 距离用**三维中心距**（与"落点溅射 / 玉面手雷王自爆"同一口径）。
func _enemy_in_trap_range(prop: Dictionary) -> Unit3D:
	var best: Unit3D = null
	var best_dist := GameConfig.ROGUELIKE_TRAP_TRIGGER_RADIUS
	for node in arena.units:
		if node == null or not is_instance_valid(node):
			continue
		var other := node as Unit3D
		if other == null or not other.alive:
			continue
		if other.team == 0 or GameConfig.is_roguelike_only(String(other.type_id)):
			continue
		if other.is_burrowed():
			continue
		var dist := Vector3(prop["pos"]).distance_to(other.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = other
	return best

## 陷阱爆炸：以**上弦时锁定的那名敌军**为中心（它中途死了 / 被回收 ⇒ 回落到陷阱自己的位置，
## 与火焰拳炎爆"对象中途死亡 ⇒ 回落自身位置"同一条口径），半径 10 m 内**所有敌方单位**都吃
## 200 伤害 + 减速 3 s（用户 2026-09-26 裁决）。
## ⚠️ 伤害走 `apply_hit(amount, null)`：**没有攻击方** ⇒ 不吃"攻击方那一队的伤害倍率"
##（陷阱不是谁打出来的；`from == null` 正是 `apply_hit()` 明说允许的那一类"无来源伤害"）。
## ⚠️ 表现复用场地的**落点扬尘池**：观感半径 = 判定半径，且**运行期不新建资源**
##（与玉面手雷王自爆 / 石弹落地同一条规矩 —— 现造网格 + 透明材质会当场编译着色器）。
func _explode_trap(prop: Dictionary) -> void:
	prop["triggered"] = true
	var center := Vector3(prop["pos"])
	var target = prop.get("target")
	if target != null and is_instance_valid(target) and (target as Unit3D).alive:
		center = (target as Unit3D).global_position
	var radius := GameConfig.ROGUELIKE_TRAP_BLAST_RADIUS
	if arena.has_method("show_impact_dust"):
		arena.show_impact_dust(center, radius)
	var hits := 0
	for node in arena.units:
		if node == null or not is_instance_valid(node):
			continue
		var other := node as Unit3D
		if other == null or not other.alive:
			continue
		if other.team == 0 or GameConfig.is_roguelike_only(String(other.type_id)):
			continue
		if other.is_burrowed():
			continue
		if center.distance_to(other.global_position) > radius:
			continue
		other.apply_hit(GameConfig.ROGUELIKE_TRAP_DAMAGE, null)
		other.apply_slow(GameConfig.ROGUELIKE_TRAP_SLOW_MULT, GameConfig.ROGUELIKE_TRAP_SLOW_MS)
		hits += 1
	## 炸过之后外观跟着变 —— **2026-09-27 用户口径**："陷阱触发后边框由红色变为绿色"。
	## ⚠️ 改的是**颜色**（旧版是 `visible = false`，把环整个收掉）：现在环留着、只是从红变绿 ⇒
	## 玩家一眼能看出"这一个已经炸过了"（而且底盘的深色还在，不会与没炸过的陷阱混淆）。
	var node = prop.get("node")
	if node != null and is_instance_valid(node):
		var ring := (node as Node3D).get_node_or_null("Ring")
		if ring != null:
			(ring as MeshInstance3D).material_override = _prop_material(TRAP_RING_DONE)
	last_message = "陷阱爆炸：%d 名敌军吃 %d 伤害并减速 %0.0f%%（%0.1f s）" % [
			hits, int(GameConfig.ROGUELIKE_TRAP_DAMAGE),
			(1.0 - GameConfig.ROGUELIKE_TRAP_SLOW_MULT) * 100.0,
			float(GameConfig.ROGUELIKE_TRAP_SLOW_MS) / 1000.0]

## 读走"这一帧被魔法盾挡下的弹"（`Arrow` 只负责追加，血量的主人始终是玩法侧）。
## ⚠️ **挡一发掉那发的伤害**：用户只说了"盾有 100 血"、没说血怎么掉 —— 本实现的取舍是
## "被挡下的弹打掉盾的血"（否则那 100 永远不动、盾等于永久免伤）。要改成"纯免伤、不掉血"
## 就把本函数里减血那一行删掉（并保留"血掉光即撤走"那条分支给将来的敌方范围伤害用）。
func _poll_arrow_blocks() -> void:
	arena.drain_ward_blocks()
	if arena.arrow_blocks.is_empty():
		return
	for raw in arena.arrow_blocks:
		var record: Dictionary = raw
		var index := _prop_index_by_id(int(record.get("id", -1)))
		if index < 0:
			continue
		var prop: Dictionary = props[index]
		prop["hp"] = float(prop["hp"]) - float(record.get("damage", 0.0))
	arena.arrow_blocks.clear()
	_sync_arrow_blockers()
	## 血掉光的盾**当场**撤走（与"指挥所被打掉"同一条思路：不等回合开始）
	for i in range(props.size() - 1, -1, -1):
		if String(props[i]["kind"]) == GameConfig.ROGUELIKE_PROP_SHIELD and float(props[i]["hp"]) <= 0.0:
			_remove_prop(i, "魔法盾被打碎了（%d 血）" % int(GameConfig.ROGUELIKE_SHIELD_HP))

## 回合开始的道具结算（用户两条口径合起来就是这一段）：
##   · **打过的陷阱移除**（"直至触发后在下回合开始时移除"）；**没触发的留着**（"只要未触发就会一直存在"）；
##   · **魔法盾回满血**（"回合开始时回满血"）；
##   · 顺手把"上弦到一半"的状态重置（上一回合上弦后没炸完就换回合了 ⇒ 下一回合重新判定）。
## 回合开始的结算：**炸过的陷阱撤走 + 魔法盾回满血 + 信标清场**。
## ⚠️ 信标清场是第七块用户裁决："只需要在回合开始时重新部署（只要买了信标就能一直免费部署，
## 点击信标的卡片以重新部署）" ⇒ 这里把上一回合的信标（连路线）一并撤走，拥有权不受影响。
func _recover_props() -> void:
	var kept: Array = []
	for prop in props:
		if String(prop["kind"]) == GameConfig.ROGUELIKE_PROP_TRAP and bool(prop["triggered"]):
			var node = prop.get("node")
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		if String(prop["kind"]) == GameConfig.ROGUELIKE_PROP_BEACON:
			var beacon_node = prop.get("node")
			if beacon_node != null and is_instance_valid(beacon_node):
				beacon_node.queue_free()
			continue
		if String(prop["kind"]) == "aid_ward":
			var ward_node = prop.get("node")
			if ward_node != null and is_instance_valid(ward_node):
				ward_node.queue_free()
			continue
		if String(prop["kind"]) == GameConfig.ROGUELIKE_PROP_SHIELD:
			prop["hp"] = prop["hp_max"]
		prop["armed_ms"] = 0
		prop["target"] = null
		kept.append(prop)
	props = kept
	_route_editing = -1
	_route_points.clear()
	_rebuild_routes()
	_sync_arrow_blockers()

## 重开一局：道具全清（外观一并收掉，挡弹表跟着清空、路线也跟着没了）+ 信标拥有权归零
func _clear_props() -> void:
	props.clear()
	if _prop_root != null and is_instance_valid(_prop_root):
		for child in _prop_root.get_children():
			child.queue_free()
	_sync_arrow_blockers()
	_beacon_owned = false
	_recall_owned = false
	_recall_used = false
	_route_editing = -1
	_route_points.clear()
	_rebuild_routes()

## 落地一件道具：登记 → 建外观 → （魔法盾）重同步挡弹表。返回它在 `props` 里的下标（信标要用）。
func _spawn_prop(kind: String, pos: Vector3) -> int:
	var is_shield := kind == GameConfig.ROGUELIKE_PROP_SHIELD
	var prop := {
		"id": _next_prop_id,
		"kind": kind,
		"pos": Vector3(pos.x, 0.0, pos.z),
		"hp": magic_shield_hp() if is_shield else 0.0,
		"hp_max": magic_shield_hp() if is_shield else 0.0,
		"armed_ms": 0,              ## 陷阱上弦的那一刻（绝对毫秒；0 = 还没上弦）
		"target": null,             ## 上弦时锁定的那名敌军（爆炸以**它**为中心）
		"triggered": false,         ## 陷阱：已经炸过了（下回合开始时移除）
		"points": [],               ## 移动信标：路线点（信标 → P1 → P2；空 = 还没画完）
		"node": null,
	}
	_next_prop_id += 1
	prop["node"] = _build_prop_node(prop)
	props.append(prop)
	_sync_arrow_blockers()
	return props.size() - 1

## 撤走一件道具（外观 + 登记 + 挡弹表）
func _remove_prop(index: int, reason: String) -> void:
	if index < 0 or index >= props.size():
		return
	var prop: Dictionary = props[index]
	var node = prop.get("node")
	if node != null and is_instance_valid(node):
		node.queue_free()
	props.remove_at(index)
	_sync_arrow_blockers()
	if reason != "":
		last_message = reason

func _prop_index_by_id(id: int) -> int:
	for i in range(props.size()):
		if int(props[i]["id"]) == id:
			return i
	return -1

## 把"场上有哪些魔法盾"同步给场地 —— 投射物拿它做几何判定（`Arrow._magic_shield_crossing()`）。
## ⚠️ 每次道具增删都**整体重写**：数量个位数，重写比增量维护省心，也不会漏。
## ⚠️ 只放**魔法盾**：陷阱不挡弹（用户口径里挡弹的只有盾）。
## ⚠️ 只放**值**（编号 / 圆心 / 半径 / 归属队），不是活对象 —— 投射物那一侧不持有任何道具引用。
func magic_shield_hp(scale: float = 1.0) -> float:
	return GameConfig.ROGUELIKE_SHIELD_HP * aid_shield_mult * scale


func _sync_arrow_blockers() -> void:
	if arena == null:
		return
	arena.arrow_blockers.clear()
	for prop in props:
		var kind := String(prop["kind"])
		if kind != GameConfig.ROGUELIKE_PROP_SHIELD and kind != "aid_ward":
			continue
		if float(prop.get("hp", 0.0)) <= 0.0:
			continue
		var radius := float(prop.get("radius", GameConfig.ROGUELIKE_SHIELD_RADIUS))
		if kind == GameConfig.ROGUELIKE_PROP_SHIELD:
			radius = GameConfig.ROGUELIKE_SHIELD_RADIUS
		arena.arrow_blockers.append({
			"id": int(prop["id"]),
			"center": Vector3(prop["pos"]),
			"radius": radius,
			"team": 0,
		})
	arena.sync_unit_wards()

## ---- 道具的外观（**纯表现**：零碰撞体）----
## 节点名按 §3.1 的"角色 + 下划线后缀"：`Prop_<kind>_<id>`（与 `UnitA_sword_0` 同式）。
func _build_prop_node(prop: Dictionary) -> Node3D:
	if _prop_root == null or not is_instance_valid(_prop_root):
		_prop_root = Node3D.new()
		_prop_root.name = "PropRoot"
		add_child(_prop_root)
	var kind := String(prop["kind"])
	var root := Node3D.new()
	root.name = "Prop_%s_%d" % [kind, int(prop["id"])]
	root.position = Vector3(prop["pos"])
	_prop_root.add_child(root)
	if kind == GameConfig.ROGUELIKE_PROP_TRAP:
		## 陷阱：贴地的一块暗色底盘 + 一圈警示环 —— 一眼看得见，但不像个"单位"
		var disc := MeshInstance3D.new()
		disc.name = "Disc"
		var disc_mesh := CylinderMesh.new()
		disc_mesh.top_radius = 0.9
		disc_mesh.bottom_radius = 0.9
		disc_mesh.height = 0.06
		disc.mesh = disc_mesh
		disc.position = Vector3(0.0, 0.03, 0.0)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.material_override = _prop_material(Color(0.20, 0.09, 0.07, 1.0))
		root.add_child(disc)
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.80
		ring_mesh.outer_radius = 0.94
		ring.mesh = ring_mesh
		ring.position = Vector3(0.0, 0.07, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = _prop_material(Color(1.0, 0.45, 0.22, 0.95))
		root.add_child(ring)
	elif kind == GameConfig.ROGUELIKE_PROP_BEACON:
		## 移动信标（第六块）：一根**细高的信标杆** + 底座环 —— 它是个"地标"，要能在远处一眼找到；
		## 它自己那两条路线的折线由 `_rebuild_routes()` 单独画（那是另一层，不属于这个节点）。
		var base := MeshInstance3D.new()
		base.name = "Base"
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.55
		base_mesh.bottom_radius = 0.75
		base_mesh.height = 0.12
		base.mesh = base_mesh
		base.position = Vector3(0.0, 0.06, 0.0)
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		base.material_override = _prop_material(Color(0.10, 0.22, 0.20, 1.0))
		root.add_child(base)
		var stem := MeshInstance3D.new()
		stem.name = "Stem"
		var stem_mesh := CylinderMesh.new()
		stem_mesh.top_radius = 0.07
		stem_mesh.bottom_radius = 0.07
		stem_mesh.height = 3.0
		stem.mesh = stem_mesh
		stem.position = Vector3(0.0, 1.5, 0.0)
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stem.material_override = _prop_material(Color(0.45, 0.95, 0.85, 0.95))
		root.add_child(stem)
	else:
		## 魔法盾：贴地圆仍标出判定边界，球壳把上半球的曲面画出来。壳很透，避免挡住场上的兵。
		var radius := GameConfig.ROGUELIKE_SHIELD_RADIUS
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = radius - 0.12
		ring_mesh.outer_radius = radius
		ring.mesh = ring_mesh
		ring.position = Vector3(0.0, 0.08, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = _prop_material(Color(0.45, 0.85, 1.0, 0.28))
		root.add_child(ring)
		var shell := MeshInstance3D.new()
		shell.name = "Shell"
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = radius
		shell_mesh.height = radius * 2.0
		shell_mesh.is_hemisphere = true
		shell.mesh = shell_mesh
		shell.position = Vector3(0.0, 0.0, 0.0)
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shell_mat := _prop_material(Color(0.55, 0.88, 1.0, 0.09))
		shell_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		shell.material_override = shell_mat
		root.add_child(shell)
		var wires := MeshInstance3D.new()
		wires.name = "Meridians"
		wires.mesh = _shield_dome_lines(radius)
		wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wires.material_override = _prop_material(Color(0.62, 0.92, 1.0, 0.34))
		root.add_child(wires)
	return root


func _shield_dome_lines(radius: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var meridians := 8
	var steps := 18
	for m in meridians:
		var yaw := TAU * float(m) / float(meridians)
		var verts := PackedVector3Array()
		for s in steps + 1:
			var phi := PI * 0.5 * float(s) / float(steps)
			var ring := sin(phi) * radius
			verts.append(Vector3(cos(yaw) * ring, cos(phi) * radius, sin(yaw) * ring))
		_add_line_surface(mesh, verts)
	for band in [0.35, 0.7]:
		var verts := PackedVector3Array()
		var band_phi := PI * 0.5 * float(band)
		var ring := sin(band_phi) * radius
		var height := cos(band_phi) * radius
		var segments := 48
		for i in segments + 1:
			var yaw := TAU * float(i) / float(segments)
			verts.append(Vector3(cos(yaw) * ring, height, sin(yaw) * ring))
		_add_line_surface(mesh, verts)
	return mesh


func _add_line_surface(mesh: ArrayMesh, verts: PackedVector3Array) -> void:
	if verts.size() < 2:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)

## 道具外观用的材质。⚠️ 颜色走**材质**（一层一个色），**不用顶点色** —— 与格子那几层同一条理由
##（见 `CELL_FREE` 上面那段实测：三角形 + 顶点色那一层在本场景里不出画）。
func _prop_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## 拖放预览：**一圈线**（半径 = 这件道具自己的圆：陷阱 8 m 检测圈 / 魔法盾 14 m 半径），
## 颜色 = 能不能放（绿 / 红）。与格子那几层同一套写法（`PRIMITIVE_LINE_STRIP` + 材质色）。
func _build_prop_preview() -> void:
	if _prop_preview != null and is_instance_valid(_prop_preview):
		return
	_prop_preview = MeshInstance3D.new()
	_prop_preview.name = "PropPreview"
	_prop_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop_preview.material_override = _prop_material(PROP_PREVIEW_OK)
	add_child(_prop_preview)

func _rebuild_prop_preview() -> void:
	if _prop_preview == null or not is_instance_valid(_prop_preview):
		return
	if _placing == "" or not _place_on_field:
		_prop_preview.mesh = null
		_prop_preview.visible = false
		return
	var radius := GameConfig.ROGUELIKE_TRAP_TRIGGER_RADIUS \
			if _placing == GameConfig.ROGUELIKE_PROP_TRAP else GameConfig.ROGUELIKE_SHIELD_RADIUS
	var mat := _prop_preview.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = PROP_PREVIEW_OK if _place_valid else PROP_PREVIEW_BAD
	var verts := PackedVector3Array()
	var segments := 96
	for i in range(segments + 1):
		var angle := TAU * float(i) / float(segments)
		verts.append(Vector3(_place_pos.x + cos(angle) * radius, PROP_PREVIEW_LIFT,
				_place_pos.z + sin(angle) * radius))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	_prop_preview.mesh = mesh
	_prop_preview.visible = true

# ---------------------------------------------------------------- 敌方波次（十回合固定名单，见 `ROGUELIKE_ENEMY_WAVES`）
## 每回合开始：清掉敌方作战单位（指挥所不动），再按本回合名单刷兵。
## 队形与我方同一套外框，格心对格心。主场地只进敌方那一半（不含布阵带、不含死区），
## 指挥所占着的格子跳过。远程（含火焰拳、持续照射）在自己这块区域里躲开边缘与面向我方的内缩；
## 其余近战整块半场里随机，更常落在已经摆下的远程前方。
## 侧翼从这份名单里抽队，不另加权重：近战贴我方边际，远程躲到带子外侧、且前方要有近战。
func _spawn_round_enemies() -> void:
	_clear_enemy_combatants()
	if arena == null:
		return
	var plan := _enemy_spawn_plan(GameConfig.roguelike_enemy_wave_for(difficulty, round_index))
	var reserved := {}
	var tech_roll := {}
	_place_enemy_flanks(plan, reserved, tech_roll)
	_place_enemy_home(plan, reserved, tech_roll)

## 把波次名单摊成一队一条。每一队从对应总权重的兵种里抽一个，并按出生顺序写上等级。
## 侧翼抽走的队带着自己的等级和抽到的兵种走。
func _enemy_spawn_plan(wave: Array) -> Array:
	var total := _enemy_wave_squad_count(wave)
	var ordinal := 0
	var weight_sum := 0
	var plan: Array = []
	for raw_entry in wave:
		var entry: Dictionary = raw_entry
		var squad_weight := int(entry.get("squad_weight", 0))
		var squad_count := int(entry.get("squads", 0))
		if squad_weight <= 0 or squad_count <= 0:
			continue
		var pool: Array = GameConfig.roguelike_enemy_types_for_squad_weight(squad_weight)
		if pool.is_empty():
			continue
		for _squad_i in squad_count:
			var type_id := String(pool[_rng.randi_range(0, pool.size() - 1)])
			var weight := int(GameConfig.profile(type_id).get("weight", 1))
			var level := GameConfig.roguelike_enemy_squad_level_for(difficulty, round_index, ordinal, total)
			var tech_count := GameConfig.roguelike_enemy_squad_tech_count(difficulty, round_index, ordinal, total)
			ordinal += 1
			weight_sum += squad_weight
			plan.append({
				"type_id": type_id,
				"weight": weight,
				"level": level,
				"tech_count": tech_count,
			})
	var target := GameConfig.roguelike_enemy_weight_target_for(difficulty, round_index)
	var miracle := difficulty == GameConfig.ROGUELIKE_DIFFICULTY_MIRACLE
	if (miracle and weight_sum != target) or (not miracle and weight_sum > target):
		push_warning("敌方波次权重 %d 与目标 %d 不一致（第 %d 回合）" % [weight_sum, target, round_index])
	return plan

## 这一波要在哪些侧翼落子。`-1` 北带，`+1` 南带。第 10 回合不落。
func _enemy_flank_sides() -> Array:
	if not GameConfig.roguelike_enemy_uses_flank(difficulty):
		return []
	if round_index < GameConfig.ROGUELIKE_ENEMY_FLANK_FROM_ROUND:
		return []
	if round_index > GameConfig.ROGUELIKE_ENEMY_FLANK_LAST_ROUND:
		return []
	if round_index >= GameConfig.ROGUELIKE_ENEMY_FLANK_BOTH_ROUND:
		return [-1, 1]
	if round_index >= GameConfig.ROGUELIKE_ENEMY_FLANK_SPLIT_FROM_ROUND:
		var sides: Array = []
		if _rng.randf() < GameConfig.ROGUELIKE_ENEMY_FLANK_CHANCE:
			sides.append(-1)
		if _rng.randf() < GameConfig.ROGUELIKE_ENEMY_FLANK_CHANCE:
			sides.append(1)
		return sides
	if _rng.randf() >= GameConfig.ROGUELIKE_ENEMY_FLANK_CHANCE:
		return []
	return [-1] if _rng.randi_range(0, 1) == 0 else [1]

## 每一侧：先抽一队近战贴着我方边际，再抽一队远程放到更远离边际、且近战在它前方的格子。
## 没有近战可放时，这一侧不放远程。
func _place_enemy_flanks(plan: Array, reserved: Dictionary, tech_roll: Dictionary) -> void:
	for raw_side in _enemy_flank_sides():
		var side := int(raw_side)
		var melee_i := _pick_flank_melee(plan, side, reserved)
		if melee_i < 0:
			continue
		var melee: Dictionary = plan[melee_i]
		var melee_weight := int(melee["weight"])
		var melee_fp := _footprint(melee_weight, false)
		var melee_row := _flank_melee_row(side, melee_fp.x)
		var cols := _flank_columns(melee_weight, melee_row, reserved)
		if cols.is_empty():
			continue
		var melee_anchor := Vector2i(int(cols[_rng.randi_range(0, cols.size() - 1)]), melee_row)
		plan.remove_at(melee_i)
		_commit_enemy_squad(melee, melee_anchor, reserved, tech_roll)
		var ranged_i := _pick_flank_ranged(plan, side, melee_anchor, melee_fp, reserved)
		if ranged_i < 0:
			continue
		var ranged: Dictionary = plan[ranged_i]
		var spots := _flank_ranged_anchors(int(ranged["weight"]), side, melee_anchor, melee_fp, reserved)
		if spots.is_empty():
			continue
		var ranged_anchor: Vector2i = spots[_rng.randi_range(0, spots.size() - 1)]
		plan.remove_at(ranged_i)
		_commit_enemy_squad(ranged, ranged_anchor, reserved, tech_roll)

## 剩下的队留在敌方半场。先随机放远程，再让近战偏向它们的前侧。
func _place_enemy_home(plan: Array, reserved: Dictionary, tech_roll: Dictionary) -> void:
	var back: Array = []
	var front: Array = []
	for raw in plan:
		var entry: Dictionary = raw
		if GameConfig.roguelike_enemy_stands_back(String(entry["type_id"])):
			back.append(entry)
		else:
			front.append(entry)
	_shuffle_entries(back)
	var blocks: Array = []
	for raw in back:
		var entry: Dictionary = raw
		var anchors := _enemy_home_anchors(String(entry["type_id"]), int(entry["weight"]), reserved)
		if anchors.is_empty():
			continue
		var anchor: Vector2i = anchors[_rng.randi_range(0, anchors.size() - 1)]
		_commit_enemy_squad(entry, anchor, reserved, tech_roll)
		var fp := _footprint(int(entry["weight"]), false)
		blocks.append({"col": anchor.x, "row": anchor.y, "width": fp.x, "depth": fp.y})
	for raw in front:
		var entry: Dictionary = raw
		var anchors := _enemy_home_anchors(String(entry["type_id"]), int(entry["weight"]), reserved)
		if anchors.is_empty():
			continue
		var anchor := _pick_melee_anchor(anchors, int(entry["weight"]), blocks)
		_commit_enemy_squad(entry, anchor, reserved, tech_roll)

func _commit_enemy_squad(entry: Dictionary, anchor: Vector2i, reserved: Dictionary,
		_tech_roll: Dictionary) -> void:
	var type_id := String(entry["type_id"])
	var weight := int(entry["weight"])
	var fp := _footprint(weight, false)
	var info := {
		"weight": weight,
		"rotated": false,
		"anchor_col": anchor.x,
		"anchor_row": anchor.y,
	}
	_reserve_enemy_block(reserved, anchor.x, anchor.y, fp.x, fp.y)
	var active := _enemy_tech_for_squad(type_id, int(entry.get("tech_count", 0)))
	var index := _spawn_foe_squad_at(type_id, _squad_centers(info), int(entry["level"]), active,
			_enemy_facing_at(anchor, fp))
	if index < 0 or not _anchored_in_forward_zone(anchor, fp, 1):
		return
	for raw in _foe_living(index):
		var unit := raw as Unit3D
		if unit != null:
			unit.zone_entered_round = round_index

## 敌方半场里这块外框放得下、且没压到指挥所或已经摆下的队的全部锚点。
## 远程还要整块躲开边缘内缩和面向我方的内缩。
func _enemy_home_anchors(type_id: String, weight: int, reserved: Dictionary) -> Array:
	var fp := _footprint(weight, false)
	var out: Array = []
	if fp.x <= 0 or fp.y <= 0:
		return out
	var backline := GameConfig.roguelike_enemy_stands_back(type_id)
	var half := _grid_cols() / 2
	var field := _field_row_range()
	var max_col := _grid_cols() - fp.y
	var max_row := field.y - fp.x + 1
	for col in range(half, max_col + 1):
		for row in range(field.x, max_row + 1):
			var anchor := Vector2i(col, row)
			if backline:
				if not _enemy_backline_fits(type_id, anchor, fp):
					continue
			elif not _fits_in_home_half(anchor, fp, 1):
				continue
			if not _enemy_block_free(col, row, fp.x, fp.y, reserved):
				continue
			out.append(anchor)
	return out

## 远程外框整块落在内缩之后的矩形里。`fp.x` 是横（Z），`fp.y` 是纵（X）。
func _enemy_backline_fits(type_id: String, anchor: Vector2i, fp: Vector2i) -> bool:
	if not _fits_in_home_half(anchor, fp, 1):
		return false
	var edge := GameConfig.roguelike_enemy_edge_cells(type_id)
	var front := GameConfig.roguelike_enemy_front_cells(type_id)
	var cols := _grid_cols()
	var field := _field_row_range()
	var col0 := anchor.x
	var col1 := anchor.x + fp.y - 1
	var row0 := anchor.y
	var row1 := anchor.y + fp.x - 1
	if col0 < cols / 2 + front:
		return false
	if col1 > cols - 1 - edge:
		return false
	if row0 < field.x + edge:
		return false
	if row1 > field.y - edge:
		return false
	return true

## 这一块近战是不是已经落在某支远程的前侧（更靠近我方，横排有重叠）。
func _enemy_melee_ahead(anchor: Vector2i, fp: Vector2i, blocks: Array) -> bool:
	var melee_east := anchor.x + fp.y - 1
	var row0 := anchor.y
	var row1 := anchor.y + fp.x - 1
	for raw in blocks:
		var block: Dictionary = raw
		if melee_east >= int(block["col"]):
			continue
		var brow0 := int(block["row"])
		var brow1 := brow0 + int(block["width"]) - 1
		if row1 < brow0 or row0 > brow1:
			continue
		return true
	return false

func _pick_melee_anchor(anchors: Array, weight: int, blocks: Array) -> Vector2i:
	var fp := _footprint(weight, false)
	var cols := _grid_cols()
	var total := 0
	var scores: Array[int] = []
	for raw in anchors:
		var anchor: Vector2i = raw
		var score := cols - anchor.x
		if _enemy_melee_ahead(anchor, fp, blocks):
			score += GameConfig.ROGUELIKE_ENEMY_MELEE_FRONT_WEIGHT
		scores.append(score)
		total += score
	var roll := _rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for i in scores.size():
		acc += scores[i]
		if roll <= acc:
			return anchors[i]
	return anchors[0]

## 贴着我方边际的那一行。北带的边际是靠主场地的南边，南带相反。放不下则返回 −1。
func _flank_melee_row(side: int, width: int) -> int:
	var band := _zone_row_range(side)
	if width <= 0 or width > band.y - band.x + 1:
		return -1
	if side < 0:
		return band.y - width + 1
	return band.x

func _flank_columns(weight: int, row: int, reserved: Dictionary) -> Array:
	var fp := _footprint(weight, false)
	var out: Array = []
	if row < 0 or fp.y <= 0:
		return out
	var span := _zone_col_range(1)
	var max_col := span.y - fp.y + 1
	for col in range(span.x, max_col + 1):
		if _enemy_block_free(col, row, fp.x, fp.y, reserved):
			out.append(col)
	return out

## 远程锚点：整块在同一条带子里，面向我方的那一边比近战更远，并且取离边际最远的那一档。
func _flank_ranged_anchors(weight: int, side: int, melee_anchor: Vector2i, melee_fp: Vector2i,
		reserved: Dictionary) -> Array:
	var fp := _footprint(weight, false)
	var out: Array = []
	if fp.x <= 0 or fp.y <= 0:
		return out
	var band := _zone_row_range(side)
	var max_row := band.y - fp.x + 1
	if max_row < band.x:
		return out
	var melee_edge := melee_anchor.y + melee_fp.x - 1 if side < 0 else melee_anchor.y
	var span := _zone_col_range(1)
	var max_col := span.y - fp.y + 1
	var best := -1
	var ranked: Array = []
	for row in range(band.x, max_row + 1):
		var edge := row + fp.x - 1 if side < 0 else row
		var farther := edge < melee_edge if side < 0 else edge > melee_edge
		if not farther:
			continue
		var gap := melee_edge - edge if side < 0 else edge - melee_edge
		for col in range(span.x, max_col + 1):
			if not _enemy_block_free(col, row, fp.x, fp.y, reserved):
				continue
			ranked.append({"anchor": Vector2i(col, row), "gap": gap})
			if gap > best:
				best = gap
	for raw in ranked:
		var spot: Dictionary = raw
		if int(spot["gap"]) == best:
			out.append(spot["anchor"])
	return out

func _pick_flank_melee(plan: Array, side: int, reserved: Dictionary) -> int:
	var options: Array[int] = []
	for i in plan.size():
		var entry: Dictionary = plan[i]
		var type_id := String(entry["type_id"])
		if GameConfig.roguelike_enemy_stands_back(type_id):
			continue
		var weight := int(entry["weight"])
		var fp := _footprint(weight, false)
		var row := _flank_melee_row(side, fp.x)
		if row < 0:
			continue
		if _flank_columns(weight, row, reserved).is_empty():
			continue
		options.append(i)
	if options.is_empty():
		return -1
	return options[_rng.randi_range(0, options.size() - 1)]

func _pick_flank_ranged(plan: Array, side: int, melee_anchor: Vector2i, melee_fp: Vector2i,
		reserved: Dictionary) -> int:
	var options: Array[int] = []
	for i in plan.size():
		var entry: Dictionary = plan[i]
		if not GameConfig.roguelike_enemy_stands_back(String(entry["type_id"])):
			continue
		if _flank_ranged_anchors(int(entry["weight"]), side, melee_anchor, melee_fp, reserved).is_empty():
			continue
		options.append(i)
	if options.is_empty():
		return -1
	return options[_rng.randi_range(0, options.size() - 1)]

func _shuffle_entries(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp

## 这一波名单里一共几队（摆不下的也算在分母里，队尾的高等级不会因为前面少摆一队而前移）。
func _enemy_wave_squad_count(wave: Array) -> int:
	var total := 0
	for raw_entry in wave:
		var entry: Dictionary = raw_entry
		var squad_weight := int(entry.get("squad_weight", 0))
		var squad_count := int(entry.get("squads", 0))
		if squad_weight <= 0 or squad_count <= 0:
			continue
		if GameConfig.roguelike_enemy_types_for_squad_weight(squad_weight).is_empty():
			continue
		total += squad_count
	return total

func _enemy_block_free(col: int, row: int, width: int, depth: int, reserved: Dictionary) -> bool:
	if not _is_free(col, row, width, depth):
		return false
	for c in range(col, col + depth):
		for r in range(row, row + width):
			if reserved.has("%d,%d" % [c, r]):
				return false
	return true

func _reserve_enemy_block(reserved: Dictionary, col: int, row: int, width: int, depth: int) -> void:
	for c in range(col, col + depth):
		for r in range(row, row + width):
			reserved["%d,%d" % [c, r]] = true

## 这一回合这个兵种抽到的科技。同一兵种只抽一次，人数再多也吃同一批。
func _enemy_tech_for_squad(type_id: String, count: int) -> Dictionary:
	var out := {}
	if count <= 0:
		return out
	var rows: Array = []
	for row in GameConfig.roguelike_tech_list(type_id):
		if row is Dictionary and GameConfig.roguelike_tech_ready(type_id, String(row.get("id", ""))):
			rows.append(row)
	var n := mini(count, rows.size())
	for _pick_i in range(n):
		if rows.is_empty():
			break
		var pick := _rng.randi_range(0, rows.size() - 1)
		var picked: Dictionary = rows[pick]
		rows.remove_at(pick)
		var tech_id := String(picked.get("id", ""))
		if tech_id == "":
			continue
		out[tech_id] = picked
	return out


## 清掉敌方作战单位（指挥所留下）。账本一并清空，查看面板下一帧自己收起。
func _clear_enemy_combatants() -> void:
	foe_squads.clear()
	selected_foe_squad = -1
	if arena == null:
		return
	for raw in arena.units.duplicate():
		var unit: Unit3D = null
		if raw != null and is_instance_valid(raw):
			unit = raw as Unit3D
		if unit == null:
			continue
		## 敌方被策反后队伍变成 0，仍带着 `foe_squad_index`。回合开始也要清掉。
		var turned_enemy := unit.has_meta("foe_squad_index")
		if unit.team != 1 and not turned_enemy:
			continue
		if String(unit.type_id) == GameConfig.ROGUELIKE_POST_TYPE:
			continue
		arena.units.erase(unit)
		unit.queue_free()

# ---------------------------------------------------------------- 测试敌人（第六块：用户"先在敌方场地中心放置一个敌人以便测试"）
## ⚠️ 它**不是"敌人系统"** —— 只是让"陷阱触发 / 魔法盾挡弹 / 指挥所被打掉"这些路径有东西可打。
## 关掉它：`GameConfig.ROGUELIKE_TEST_ENEMY_ENABLED := false`（一行，回到"场上没有敌人"的老状态）。
## 位置 = **敌方半场的中心**（从场地尺寸推 ⇒ 场地放大后自动跟着走）。
func _test_enemy_pos() -> Vector3:
	return Vector3(arena.half_x * 0.5, 0.0, 0.0)

## 场上还有没有活着的测试敌人（按 meta 认，**不按兵种** —— 玩家自己也可能摆同一个兵种）
func _test_enemy_alive() -> bool:
	for unit in arena.units:
		if unit == null or not is_instance_valid(unit):
			continue
		var u := unit as Unit3D
		if u != null and u.alive and u.has_meta("test_enemy"):
			return true
	return false

## 补一个测试敌人。回合波次已经改走 `_spawn_round_enemies()`，这里不再被回合流程调用。
## ⚠️ 2026-09-27 起它走 **`_spawn_foe_squad()`**（会记进 `foe_squads` 并给每个兵打 `foe_squad_index` meta）
## —— 这是"敌方按队查看"的第一份数据来源。
func _ensure_test_enemy() -> void:
	if not GameConfig.ROGUELIKE_TEST_ENEMY_ENABLED or arena == null:
		return
	if _test_enemy_alive():
		return
	_compact_foe_squads()                ## 先把"全死光的空壳"收掉，账本不会越滚越长
	var index := _spawn_foe_squad(GameConfig.ROGUELIKE_TEST_ENEMY,
			GameConfig.ROGUELIKE_TEST_ENEMY_COUNT, _test_enemy_pos(),
			GameConfig.ROGUELIKE_TEST_ENEMY_LEVEL)
	## ⚠️ `test_enemy` 这个 meta 由 `_test_enemy_alive()` 认（**不按兵种** —— 玩家自己也可能摆同一个兵种）
	## ⇒ 补兵之后必须补打，否则下一帧又会认为"场上没有测试敌人"而再放一支。
	for raw in _foe_living(index):
		(raw as Unit3D).set_meta("test_enemy", true)

## 生成**一支敌方队伍**。测试敌人以 `at` 为中心沿横排铺开。
## 波次走 `_spawn_foe_squad_at()`，每人站在自己那格的中心。
## 返回它在 `foe_squads` 里的下标；`-1` = 没生成（场地没绑好 / 数量非法）。
func _spawn_foe_squad(type_id: String, count: int, at: Vector3, level: int = 1) -> int:
	if arena == null or count <= 0:
		return -1
	var index := foe_squads.size()
	foe_squads.append({"type_id": type_id, "units": count, "team": 1,
			"level": clampi(level, 1, GameConfig.ROGUELIKE_LEVEL_MAX)})
	var facing := GameConfig.team_spawn_sign(1) * PI * 0.5
	var gap := GameConfig.SPAWN_MIN_GAP * 2.0      ## 一个身位再多一点（与"簇内最小间距"同量级）
	for slot in range(count):
		var offset := (float(slot) - float(count - 1) * 0.5) * gap
		var unit := arena.spawn_unit(1, type_id, at + Vector3(0.0, 0.0, offset), facing)
		if unit == null:
			continue
		unit.set_meta("foe_squad_index", index)
		unit.set_meta("foe_slot", slot)
		unit.set_level(clampi(level, 1, GameConfig.ROGUELIKE_LEVEL_MAX))
	return index

## 波次用：每个人站在给定的格心上，并带上这一兵种本回合抽到的科技。
func _enemy_facing_at(anchor: Vector2i, fp: Vector2i) -> float:
	if _anchored_in_forward_zone(anchor, fp, 1):
		var row0 := anchor.y
		var row1 := anchor.y + fp.x - 1
		var north := _zone_row_range(-1)
		var south := _zone_row_range(1)
		if row0 >= north.x and row1 <= north.y:
			return PI
		if row0 >= south.x and row1 <= south.y:
			return 0.0
	return GameConfig.team_spawn_sign(1) * PI * 0.5


func _spawn_foe_squad_at(type_id: String, centers: PackedVector3Array, level: int,
		active: Dictionary, facing: float = INF) -> int:
	if arena == null or centers.is_empty():
		return -1
	var index := foe_squads.size()
	foe_squads.append({"type_id": type_id, "units": centers.size(), "team": 1,
			"level": clampi(level, 1, GameConfig.ROGUELIKE_LEVEL_MAX)})
	var yaw := facing if facing != INF else GameConfig.team_spawn_sign(1) * PI * 0.5
	for slot in range(centers.size()):
		var unit := arena.spawn_unit(1, type_id, centers[slot], yaw)
		if unit == null:
			continue
		unit.set_meta("foe_squad_index", index)
		unit.set_meta("foe_slot", slot)
		unit.set_level(clampi(level, 1, GameConfig.ROGUELIKE_LEVEL_MAX))
		unit.set_techs(active)
		if slot == 0 and active.has("sword_saint"):
			unit.set_saint(true)
	return index

## 把敌方那本队账**整体重建**：只留住"还有活兵"的队，丢掉空壳，并**重写每个兵的 `foe_squad_index`**
##（下标会变）。⚠️ 只在"要生成新的敌方队伍之前"调（测试敌人每回合补一次 ⇒ 账本不会随回合数膨胀）。
## ⚠️ 正在查看的那一队跟着做重映射；它要是被收掉了就置 −1（界面下一帧自己把面板收起）。
func _compact_foe_squads() -> void:
	if arena == null:
		return
	var alive_by_old := {}
	for node in arena.units:
		var u: Unit3D = null
		if node != null and is_instance_valid(node):
			u = node as Unit3D
		if u == null or not u.alive or u.team == 0 or not u.has_meta("foe_squad_index"):
			continue
		var old := int(u.get_meta("foe_squad_index"))
		if not alive_by_old.has(old):
			alive_by_old[old] = []
		alive_by_old[old].append(u)
	var rebuilt: Array = []
	var remap := {}
	for old in alive_by_old.keys():
		var list: Array = alive_by_old[old]
		var first: Unit3D = list[0]
		var planned := list.size()
		if old >= 0 and old < foe_squads.size():
			planned = maxi(int(foe_squads[old].get("units", planned)), planned)
		remap[old] = rebuilt.size()
		rebuilt.append({"type_id": String(first.type_id), "units": planned, "team": 1})
	for old in remap.keys():
		for raw in alive_by_old[old]:
			(raw as Unit3D).set_meta("foe_squad_index", int(remap[old]))
	foe_squads = rebuilt
	if selected_foe_squad >= 0:
		selected_foe_squad = int(remap.get(selected_foe_squad, -1))

# ---------------------------------------------------------------- 移动信标（第六块：路线 + 沿路线平移）
## 用户口径见 `GameConfig.ROGUELIKE_PROP_BEACON` 上面那一段（放置 → 两次点击定路线 → 战斗开始后
## 半径 10 m 内的我方单位沿两条线**保持队形**平移、攻击时也走、到终点恢复自由移动）。
## ⚠️ 与陷阱 / 魔法盾的不同：① 它**不花补给放置**（钱在指挥所那一步付过）⇒ 判据是**拥有权**；
## ② 放下之后还要**两次点击**画路线 ⇒ 这中间多一个状态 `_route_editing`。
## ---- 2026-09-27 第七块的用户裁决（**推翻第六块的"库存次数"口径**）----
## 原文："信标不会被锁定，只需要在回合开始时重新部署（只要买了信标就能一直免费部署，
## 点击信标的卡片以重新部署）。任意兵种，只要在部署阶段时在信标范围内，就会被影响，
## 如果被影响，兵种的朝向改成信标第一段移动的朝向。"
## ⇒ 三条落地：**买一次永久拥有**（`_beacon_owned`）、**回合开始自动清场**（`_recover_props()` 里撤走）、
## **点道具卡免费重放**（`begin_place()` 不再看库存）；影响仍按用户的第二次裁决走"**开战那一刻统一判一次**"，
## 只多一条"被影响的单位朝向 = 路线第一段方向"（`Unit3D.set_facing()`）。
func has_beacon() -> bool:
	return _beacon_owned

func has_recall() -> bool:
	return _recall_owned

func recall_ready() -> bool:
	return _recall_owned and not _recall_used and phase == Phase.PREPARE and starter_chosen

func buy_recall() -> bool:
	if phase != Phase.PREPARE:
		last_message = "只能在准备阶段买增益"
		return false
	if selected_post != GameConfig.ROGUELIKE_POST_SIDE_STEADY:
		last_message = "先点【右方】指挥所（持续增益）"
		return false
	if _recall_owned:
		last_message = "遣返已经买过了：每回合从道具行那张卡拖到一队兵上用一次"
		return false
	if supply < GameConfig.ROGUELIKE_RECALL_PRICE:
		last_message = "补给不足：遣返要 %d，还剩 %d" % [GameConfig.ROGUELIKE_RECALL_PRICE, supply]
		return false
	_push_undo("买下遣返")
	supply -= GameConfig.ROGUELIKE_RECALL_PRICE
	_recall_owned = true
	last_message = "遣返：买下了（每回合可拖到一队兵上用一次）"
	return true

func begin_recall() -> void:
	if phase != Phase.PREPARE or not starter_chosen:
		last_message = "只能在准备阶段遣返"
		return
	if not _recall_owned:
		last_message = "还没买：先去【右方】指挥所买下遣返（%d 补给，买一次永久可用）" % GameConfig.ROGUELIKE_RECALL_PRICE
		return
	if _recall_used:
		last_message = "这一回合已经遣返过了"
		return
	_placing = "recall"
	_place_valid = false
	_place_press_seen = false
	last_message = "把遣返拖到一队兵上松手"
	_tick_placing()

func _tick_recall_drag() -> void:
	var index := _squad_at(get_viewport().get_mouse_position())
	_place_valid = index >= 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_place_press_seen = true
	elif _place_press_seen:
		finish_place()

func _finish_recall(index: int) -> void:
	_cancel_place()
	if index < 0:
		last_message = "没拖到我方的队上，这一次不算用掉"
		return
	_recall_squad(index)

func _recall_squad(index: int) -> void:
	if index < 0 or index >= squads.size():
		return
	var info: Dictionary = squads[index]
	var squad_name := GameConfig.profile_name(String(info["type_id"]))
	_push_undo("遣返 %s" % squad_name)
	var refund := int(int(info.get("supply_spent", 0)) / 2)
	supply += refund
	_recall_used = true
	_remove_squad(index)
	last_message = "遣返 %s：退回 %d 补给" % [squad_name, refund]


func _remove_squad(index: int) -> void:
	if index < 0 or index >= squads.size():
		return
	if arena != null:
		for raw in arena.units.duplicate():
			if raw == null or not is_instance_valid(raw):
				continue
			var unit := raw as Unit3D
			if unit == null or unit.team != 0 or not unit.has_meta("squad_index"):
				continue
			if int(unit.get_meta("squad_index")) != index:
				continue
			arena.units.erase(unit)
			unit.queue_free()
	_vacate_squad(index)
	squads.remove_at(index)
	for key in _occupied.keys():
		var owner := int(_occupied[key])
		if owner > index:
			_occupied[key] = owner - 1
	if arena != null:
		for raw in arena.units:
			if raw == null or not is_instance_valid(raw):
				continue
			var unit := raw as Unit3D
			if unit == null or not unit.has_meta("squad_index"):
				continue
			var owner := int(unit.get_meta("squad_index"))
			if owner > index:
				unit.set_meta("squad_index", owner - 1)
	if selected_squad == index:
		selected_squad = -1
	elif selected_squad > index:
		selected_squad -= 1
	_rebuild_cells()

func _tick_scavengers() -> void:
	if arena == null:
		return
	var row := GameConfig.roguelike_tech_def("fan", "scavenger")
	var radius := float(row.get("radius", 5.0)) if not row.is_empty() else 5.0
	for raw in arena.units:
		var unit: Unit3D = null
		if raw != null and is_instance_valid(raw):
			unit = raw as Unit3D
		if unit == null or not unit.alive or not unit.has_tech("scavenger"):
			continue
		arena.clear_ground_near(unit.global_position, radius)

## 买一个移动信标（右方指挥所的增益面板走这里）：**只需买一次**，此后每回合免费重新部署。
func buy_beacon() -> bool:
	if phase != Phase.PREPARE:
		last_message = "只能在准备阶段买增益"
		return false
	if selected_post != GameConfig.ROGUELIKE_POST_SIDE_STEADY:
		last_message = "先点【右方】指挥所（持续增益）"
		return false
	if _beacon_owned:
		last_message = "移动信标已经买过了：每回合开始都能从道具行那张卡**免费**重新部署"
		return false
	if supply < GameConfig.ROGUELIKE_BEACON_PRICE:
		last_message = "补给不足：移动信标要 %d，还剩 %d" % [GameConfig.ROGUELIKE_BEACON_PRICE, supply]
		return false
	_push_undo("买下移动信标")                                    ## 撤销点：买信标（拥有权）
	supply -= GameConfig.ROGUELIKE_BEACON_PRICE
	_beacon_owned = true
	last_message = "移动信标：买下了（此后每回合免费重新部署）—— 从道具行那张卡拖到场上，再点两下画路线"
	return true

## 撤走场上所有信标（回合开始清场 / 重新部署时先撤旧的）。
## ⚠️ 走 `_remove_prop()` 而不是自己删数组：外观节点、挡弹表、路线折线都由它一并收干净。
func _remove_beacons(reason: String) -> void:
	var i := props.size() - 1
	while i >= 0:
		if String(props[i]["kind"]) == GameConfig.ROGUELIKE_PROP_BEACON:
			_remove_prop(i, "")
		i -= 1
	if _route_editing >= 0:
		_route_editing = -1
		_route_points.clear()
	_rebuild_routes()
	if reason != "":
		last_message = reason

## 放下信标之后立刻进"画路线"（`index` = 它在 `props` 里的下标）
func _start_route_edit(index: int) -> void:
	if index < 0 or index >= props.size():
		return
	_route_editing = index
	_route_points = [Vector3(props[index]["pos"])]
	last_message = "画路线：点第 1 下决定第一段（最远 %0.0f m，右键退一步 / 取消）" % \
			GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX
	_rebuild_routes()

## 把任意点夹进**地块**里（第七块裁决："路线点也要落在场地内"）。
## ⚠️ 2026-09-27 订正后地块就是**一个矩形**（150 × 111.5，含南北两条带子）⇒ 一次夹取即可。
func _clamp_into_field(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -arena.half_x, arena.half_x), 0.0,
			clampf(p.z, -arena.half_z, arena.half_z))

## 路线编辑中：点一个点。⚠️ 两步约束（用户裁决）：
##   ① 超出 30 m ⇒ **自动夹到 30 m**（方向取点击方向）；
##   ② 落点先**夹进地块**（第七块裁决，免得路线把队伍带出场外）。
func _add_route_point(world_pos: Vector3) -> void:
	if _route_editing < 0 or _route_points.is_empty():
		return
	var from: Vector3 = _route_points[_route_points.size() - 1]
	var target := _clamp_into_field(world_pos)
	var delta := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if delta.length() > GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX:
		delta = delta.normalized() * GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX
	_route_points.append(from + delta)
	if _route_points.size() > GameConfig.ROGUELIKE_BEACON_POINT_COUNT:
		_finish_route()
		return
	last_message = "画路线：点第 2 下决定第二段（最远 %0.0f m）" % GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX
	_rebuild_routes()

## 右键：回退一步；已经没有点了 ⇒ 整个放置取消（**拥有权不动** —— 买与放是两步，没放成不影响下回合重放）
func _route_step_back() -> void:
	if _route_editing < 0:
		return
	if _route_points.size() <= 1:
		_cancel_route_edit(true)
		return
	_route_points.remove_at(_route_points.size() - 1)
	last_message = "路线回退一步（现在 %d 段）" % (_route_points.size() - 1)
	_rebuild_routes()

## 路线画完：写进道具 + 重画线（⚠️ 不再扣"库存"：第七块起买一次永久拥有）
func _finish_route() -> void:
	if _route_editing < 0 or _route_editing >= props.size():
		_cancel_route_edit(true)
		return
	_push_undo("画完信标路线")                                    ## 撤销点：路线画完
	props[_route_editing]["points"] = _route_points.duplicate()
	var length := 0.0
	for i in range(1, _route_points.size()):
		length += Vector3(_route_points[i]).distance_to(Vector3(_route_points[i - 1]))
	last_message = "移动信标就位：路线全长 %0.0f m —— 战斗开始后半径 %0.0f m 内的我方单位沿它移动" % [
			length, GameConfig.ROGUELIKE_BEACON_RADIUS]
	_route_editing = -1
	_route_points.clear()
	_rebuild_routes()

func _cancel_route_edit(remove_prop: bool) -> void:
	if remove_prop and _route_editing >= 0 and _route_editing < props.size():
		var node = props[_route_editing].get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
		props.remove_at(_route_editing)
		last_message = "移动信标取消放置（拥有权还在，随时能从卡片重新部署）"
	_route_editing = -1
	_route_points.clear()
	_rebuild_routes()

## 路线可视化：**每条路线一条折线**（`PRIMITIVE_LINE_STRIP`）+ 信标处一根短杆。
## ⚠️ 颜色走材质（顶点色在本场景不出画，见 `CELL_FREE` 的注）；⚠️ 一次全量重建（信标个位数，够用）。
func _rebuild_routes() -> void:
	if _routes_root == null or not is_instance_valid(_routes_root):
		_routes_root = Node3D.new()
		_routes_root.name = "RouteRoot"
		add_child(_routes_root)
	for child in _routes_root.get_children():
		child.queue_free()
	for prop in props:
		if String(prop["kind"]) != GameConfig.ROGUELIKE_PROP_BEACON:
			continue
		var pts: Array = prop.get("points", [])
		if pts.size() >= 2:
			_add_route_line(pts, ROUTE_COLOR)
	if _route_editing >= 0 and _route_points.size() >= 2:
		_add_route_line(_route_points, ROUTE_EDIT_COLOR)

func _add_route_line(points: Array, tint: Color) -> void:
	var verts := PackedVector3Array()
	for p in points:
		var v: Vector3 = p
		verts.append(Vector3(v.x, ROUTE_LIFT, v.z))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	var line := MeshInstance3D.new()
	line.name = "RouteLine_%d" % _routes_root.get_child_count()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.material_override = _prop_material(tint)
	_routes_root.add_child(line)

## 战斗开始时指派路线（用户："在战斗开始后会优先跟着移动信标标定的路线移动"）：
## 对每个**路线完整**的信标，把半径 `ROGUELIKE_BEACON_RADIUS` 内的**我方单位**逐个挂上那条路线
##（"同一队兵只有被包括的那一部分兵被影响" ⇒ 逐个判，不按队）。
## ⚠️ 建筑（指挥所 / `no_attack`）跳过：用户口径是"所有**兵种**"，而它们本来就不移动。
## ⚠️ 第七块补一条（用户："任意兵种，只要在部署阶段时在信标范围内，就会被影响，如果被影响，
## 兵种的朝向改成信标第一段移动的朝向"）：判定时机**不变**（仍是开战这一刻统一判一次 ——
## 用户第二次裁决否掉了"逐帧实时判定"），只把**朝向**一并拧到第一段方向。
func _capture_beacon_routes() -> void:
	if arena == null:
		return
	var affected := 0
	for prop in props:
		if String(prop["kind"]) != GameConfig.ROGUELIKE_PROP_BEACON:
			continue
		var pts: Array = prop.get("points", [])
		if pts.size() <= GameConfig.ROGUELIKE_BEACON_POINT_COUNT:
			continue                       ## 路线没画完 ⇒ 这一件这回合不生效（下回合还能接着画）
		var center := Vector3(prop["pos"])
		var first_dir := Vector3(pts[1]) - Vector3(pts[0])
		for unit in arena.units:
			if unit == null or not is_instance_valid(unit):
				continue
			var u := unit as Unit3D
			if u == null or not u.alive or u.team != 0:
				continue
			if GameConfig.is_no_attack(String(u.type_id)):
				continue
			if center.distance_to(u.global_position) > GameConfig.ROGUELIKE_BEACON_RADIUS:
				continue
			u.set_beacon_route(pts)
			u.set_facing(first_dir)        ## 朝向 = **信标第一段移动的方向**（用户第七块口径）
			affected += 1
	if affected > 0:
		last_message = "移动信标：%d 个单位开始沿路线移动（朝向已对齐第一段）" % affected

## ---- 第七块：前进布阵带的准备期（2026-09-27 订正为"南北两条长边外侧的带子"）----
## 用户原文："在部署阶段'我方'可以在'敌方'的这个场地布置兵种，但我方单位每当部署到这个场地时需要
## 5s准备时间（5s后才能行动，期间会被敌方攻击）。…在这个区域部署后的下一个回合开始则不需要启动时间。"
## ⚠️ 两条判据缺一不可：**落在"这一方能布阵的带子"里**（= 对方底线起算的那两条）+ **是本回合被放进去的**
##（`Unit3D.zone_entered_round`）。只在 `start_battle()` 里跑一次（开战那一刻起算，用户裁决）。
func _capture_zone_prep() -> void:
	if arena == null:
		return
	var affected := 0
	for unit in arena.units:
		if unit == null or not is_instance_valid(unit):
			continue
		var u := unit as Unit3D
		if u == null or not u.alive:
			continue
		var cell := _cell_of(u.global_position)
		## "落在前进布阵带里" = 它自己那一方**能布阵**的那两条（对方底线起算）⇒ 与落点判定同一把尺子
		if not _cell_in_forward_zone(cell.x, cell.y, u.team):
			continue
		if u.zone_entered_round != round_index:
			continue                       ## 上一回合就在这儿的老兵 ⇒ 免启动（用户后半句）
		var prep_ms := GameConfig.ROGUELIKE_ZONE_PREP_MS
		if aid_flank_half:
			prep_ms = int(prep_ms / 2)
		u.apply_prep(prep_ms)
		affected += 1
	if affected > 0:
		var shown := GameConfig.ROGUELIKE_ZONE_PREP_MS
		if aid_flank_half:
			shown = int(shown / 2)
		last_message = "前进布阵带：%d 个单位落在对方底线外的带子里，%0.0f s 后才能行动（期间会被攻击）" % [
				affected, float(shown) / 1000.0]

## 落位 / 挪位之后登记"这一队是不是本回合被放进敌方延伸区的"（写进每个兵的 `zone_entered_round`）。
## ⚠️ 放回自家半场 ⇒ 一律清成 `-1`（否则第 2 回合挪回家、第 3 回合再挪出去时，"上一回合就在里面"
## 这条免启动判据会被旧值骗到）。复活的兵由 `_spawn_one_squad_unit()` 新造 ⇒ 默认 `-1`。
func _mark_zone_entry(index: int) -> void:
	if index < 0 or index >= squads.size():
		return
	var info: Dictionary = squads[index]
	var fp := _footprint(int(info["weight"]), bool(info.get("rotated", false)))
	var anchor := Vector2i(int(info["anchor_col"]), int(info["anchor_row"]))
	var in_zone := _anchored_in_forward_zone(anchor, fp, 0)   ## `squads` 里的队全是我方（0 队）
	var living := _living_slots(index)
	for slot in living.keys():
		var u: Unit3D = living[slot] as Unit3D
		if u != null and is_instance_valid(u):
			u.zone_entered_round = round_index if in_zone else -1

## 回合开始时把所有人身上的路线清掉（新一回合由 `start_battle()` 重新指派）
func _clear_unit_beacon_routes() -> void:
	if arena == null:
		return
	for unit in arena.units:
		if unit == null or not is_instance_valid(unit):
			continue
		var u := unit as Unit3D
		if u != null and u.has_beacon_route():
			u.clear_beacon_route()

# ---------------------------------------------------------------- 给界面读的"选中那一队"（第四块用户口径③）
## 选中某一队（界面「关闭」按钮走这里；点场地选队走 `_begin_press()`）。
## ⚠️ 与指挥所增益面板**互斥**：两块面板占同一片角落 ⇒ 选一队时把 `selected_post` 收掉（`index < 0` = 取消选中）。
## ⚠️ 界面不许直接写玩法字段（R-07），所以"取消选中"也得由这里提供。
func select_squad(index: int) -> void:
	selected_squad = index
	if index >= 0:
		selected_post = ""
		selected_foe_squad = -1      ## 与"查看敌方"互斥（同一块面板）

## 点中**敌方的一支队伍**（2026-09-27 用户："敌方单位也可以被我方选中，只用来查看信息"；
## `index` = `foe_squads` 的下标）。
## ⚠️ 它是**只读**的：不能拖动 / 旋转，也不进 `squads` —— 界面那半段文案由 `foe_stats(index)` 供数，
## 与 `squad_stats()` **同一套键** ⇒ 面板不需要第二套排版。
func select_foe(index: int) -> void:
	selected_foe_squad = index
	if index >= 0:
		selected_squad = -1
		selected_post = ""

## 被查看的那支**敌方队伍**的只读数值（键与 `squad_stats()` 对齐，多一个 `"foe": true` 供界面分辨）。
## ⚠️ 数字取"这一队里**第一个活着的兵**"的实例读数（与我方 `squad_stats()` 同源）；队伍级的倍率
##（进攻 / 减益）按**敌方那一队**取 —— 敌人的指挥所被打掉时它也会吃减益。
## ⚠️ **一个活的都没有 ⇒ 返回空字典**（界面据此把面板收起来）。
func foe_stats(index: int) -> Dictionary:
	if index < 0 or index >= foe_squads.size():
		return {}
	var entry: Dictionary = foe_squads[index]
	var living := _foe_living(index)
	if living.is_empty():
		return {}
	var sample: Unit3D = living[0]
	var type_id := String(entry.get("type_id", sample.type_id))
	var profile: Dictionary = GameConfig.profile(type_id)
	var foe_team := sample.team
	var ranged := bool(profile.get("is_ranged", false))
	var dmg_mult := arena.damage_mult_for(foe_team) if arena != null else 1.0
	return {
		"foe": true,
		"index": index,
		"name": GameConfig.profile_name(type_id),
		"type_id": type_id,
		"count": maxi(int(entry.get("units", living.size())), living.size()),
		"alive": living.size(),
		"movable": false,
		"rotated": false,
		"weight": int(profile["weight"]),
		"mass": GameConfig.mass(type_id),
		"damage": GameConfig.hit_damage(type_id),
		"damage_mult": dmg_mult,
		"level_mult": sample.level_mult(),
		## ⚠️ 伤害的**最终值** = 面板伤害 × 队伍倍率 × **等级倍率**（两个倍率各自独立乘区，用户口径）
		"damage_final": GameConfig.hit_damage(type_id) * dmg_mult * sample.level_mult(),
		"level": sample.level,
		"attack_speed": float(profile["attack_speed"]),
		"hp_max": sample.max_hp,
		"hp_now": sample.hp,
		"reach": sample.attack_reach(),
		"speed": sample.current_speed(),
		"is_ranged": ranged,
		"defense_level": 0,
		"debuff": arena.debuff_active(foe_team) if arena != null else false,
		"range_bonus": arena.range_bonus_for(foe_team) if arena != null else 0.0,
		"speed_bonus": float(arena.team_speed_bonus[foe_team]) if arena != null else 0.0,
	}

## 敌方第 `index` 队**还活着的**兵（按槽位 / 生成顺序返回）
func _foe_living(index: int) -> Array:
	var out: Array = []
	if arena == null:
		return out
	for node in arena.units:
		var u: Unit3D = null
		if node != null and is_instance_valid(node):
			u = node as Unit3D
		if u == null or not u.alive or u.team == 0 or not u.has_meta("foe_squad_index"):
			continue
		if int(u.get_meta("foe_squad_index")) == index:
			out.append(u)
	return out

## 这一队现在能不能移动 = **本回合拿到手的**（用户 2026-09-26："开局送的两队兵也能在第一回合进行移动"
## ⇒ 判据是 `move_round == round_index`，**与"是不是买的"无关**），且当前在准备阶段。
func squad_movable(index: int) -> bool:
	if index < 0 or index >= squads.size():
		return false
	if phase != Phase.PREPARE:
		return false
	if RoguelikeAid.module_move_always(self, index):
		return true
	return int(squads[index].get("move_round", 0)) == round_index

## 这一队的**最终数值**（口径③："要把增益的增幅也算进去"）。界面轮询它，只读叶子字段。
## ⚠️ 三项"跟实例走"的读数（当前血 / 射程 / 移速）取该队**一个普通兵**、问它自己的 getter ——
## 那几个 getter 内部已经把场地增益算进去了（`attack_reach()` / `current_speed()`），这里**不再乘一遍**。
## ⚠️ 剑圣是槽位 0 的特例（生命 ×3 / 接触距离 ×2）。它往往是这队第一个活着的兵；
## 拿它当样本，点选普通剑盾兵会显示剑圣的数值。有普通兵活着时跳过剑圣；只剩剑圣时才用它。
## 一个活着的都没有时（战斗中全灭、还没到回合开始）回落到"按档案 + 场地倍率算"，好过界面直接空掉。
## ⚠️ 返回的是**自己拼的小字典**（数字 / 字符串 / 布尔），不把 `Unit3D`、`Arena` 这些活对象递出去。
func squad_stats(index: int) -> Dictionary:
	if index < 0 or index >= squads.size():
		return {}
	var info: Dictionary = squads[index]
	var type_id := String(info["type_id"])
	var profile: Dictionary = GameConfig.profile(type_id)
	var ranged := bool(profile.get("is_ranged", false))
	var def_level := buff_level(GameConfig.ROGUELIKE_BUFF_DEFENSE)
	var living := _living_slots(index)
	var sample: Unit3D = null
	var saint_only: Unit3D = null
	for slot in living.keys():
		var raw = living[slot]
		if raw == null or not is_instance_valid(raw):
			continue
		var unit := raw as Unit3D
		if unit == null:
			continue
		if unit.is_saint():
			if saint_only == null:
				saint_only = unit
			continue
		sample = unit
		break
	if sample == null:
		sample = saint_only
	## 回落值：按档案 + 场地倍率算（有活兵时下面会被 getter 覆盖掉）
	var hp_max := GameConfig.max_hp(type_id) + _defense_bonus_total(type_id, def_level)
	var hp_now := hp_max
	var reach := float(profile["range"])
	if not ranged:
		reach *= GameConfig.UNIT_CONTACT_RATIO
	elif arena != null:
		reach += arena.range_bonus_for(0)
	var speed := GameConfig.move_speed(type_id)
	if arena != null:
		speed = arena.speed_for(0, speed)
	var interval_mult := 1.0
	var tech_mult := 1.0
	if sample != null and is_instance_valid(sample):
		hp_max = sample.max_hp
		hp_now = sample.hp
		reach = sample.attack_reach()
		speed = sample.current_speed()
		interval_mult = sample.tech_interval_mult()
		tech_mult = sample.tech_damage_mult()
	else:
		interval_mult = _owned_interval_mult(type_id)
		tech_mult = _owned_damage_mult(type_id, squad_level(index))
	var dmg_mult := arena.damage_mult_for(0) if arena != null else 1.0
	var attack_speed := float(profile["attack_speed"]) / maxf(interval_mult, 0.001)
	var upgrade_all := upgrade_same_type_plan(type_id)
	return {
		"index": index,
		"name": GameConfig.profile_name(type_id),
		"type_id": type_id,
		"count": int(info["units"]),
		"alive": living.size(),
		"movable": squad_movable(index),
		"rotated": bool(info.get("rotated", false)),
		"weight": int(info["weight"]),
		"mass": GameConfig.mass(type_id),
		"damage": GameConfig.hit_damage(type_id),
		"damage_mult": dmg_mult,
		"level_mult": float(squad_level(index)),
		## ⚠️ 伤害的**最终值** = 面板伤害 × 科技倍率 × 队伍倍率 × **等级倍率**（各自独立乘区）
		"tech_mult": tech_mult,
		"damage_final": GameConfig.hit_damage(type_id) * tech_mult * dmg_mult * squad_level(index),
		"level": squad_level(index),
		"level_max": GameConfig.ROGUELIKE_LEVEL_MAX,
		"xp": squad_xp(index),
		"xp_cost": squad_xp_cost(index),
		"upgrade_price": upgrade_price(index),
		"can_upgrade": upgrade_block_reason(index) == "",
		"upgrade_reason": upgrade_block_reason(index),
		"upgrade_all_count": int(upgrade_all["count"]),
		"upgrade_all_price": int(upgrade_all["price"]),
		"attack_speed": attack_speed,
		"armor": sample.tech_armor() if sample != null else 0.0,
		"kb_bonus": sample.tech_kb_bonus() if sample != null else 0.0,
		"shield_max": sample.tech_shield_max() if sample != null else 0.0,
		"hp_max": hp_max,
		"hp_now": hp_now,
		"reach": reach,
		"speed": speed,
		"is_ranged": ranged,
		"defense_level": def_level,
		"debuff": arena.debuff_active(0) if arena != null else false,
		## 本回合那两个场地加成（界面用来解释"射程 / 移速为什么比平时高"）
		"range_bonus": arena.range_bonus_for(0) if arena != null else 0.0,
		"speed_bonus": float(arena.team_speed_bonus[0]) if arena != null else 0.0,
	}

# ---------------------------------------------------------------- 增益（第三块）
## 指挥所被摧毁后的减益时长 = **5 s − 指挥部升级数 × 1 s**（用户："指挥部升级…被摧毁后受到的减益持续时间减少1s"）。
## ⚠️ 下限取 1 s（三级升满 = 2 s；再加一条 `maxi` 只是防负数，不是口径）。
func post_debuff_ms() -> int:
	var level := buff_level(GameConfig.ROGUELIKE_BUFF_UPGRADE)
	return maxi(GameConfig.ROGUELIKE_POST_DEBUFF_MS - level * GameConfig.ROGUELIKE_POST_DEBUFF_CUT_MS,
			GameConfig.ROGUELIKE_POST_DEBUFF_CUT_MS)

## 指挥所被打掉 ⇒ 它**所属那一队**全体吃减益。⚠️ 两个都被摧毁时**只刷新持续时间、不叠加**
##（`Arena.apply_team_debuff()` 就是重设截止时刻，用户口径）。
## ⚠️ **2026-09-27 起这一支还管"经验"**（用户口径 2）：敌方单位阵亡时，把经验发给**击杀者所在的那一队**
##（`dead.killer()` —— 击杀归因记在 `Unit3D._last_hitter`，**没有新信号**）。
## 经验值 = **被杀单位的权重 × 它的等级**（用户例子：1 级矛兵 1 点、5 级长矛兵 5 点）。
func _on_unit_died(unit: Node3D) -> void:
	var dead := unit as Unit3D
	if dead == null:
		return
	if String(dead.type_id) == GameConfig.ROGUELIKE_POST_TYPE:
		arena.apply_team_debuff(dead.team, post_debuff_ms())
		var supply_note := ""
		if dead.team == _enemy_team() and phase == Phase.FIGHTING and _enemy_combatants() > 0:
			var gain := GameConfig.ROGUELIKE_POST_KILL_SUPPLY
			supply += gain
			income_total += gain
			supply_note = "，+%d 补给" % gain
		last_message = "%s的指挥所被摧毁：全体减益 −90%%%s，持续 %0.1f s" % [
				GameConfig.team_name(dead.team), supply_note, float(post_debuff_ms()) / 1000.0]
		return
	_award_kill_xp(dead)
	_replicate_from_kill(dead)
	_dismount_from(dead)
	RoguelikeAid.command_down(self, dead)

## ---- 持续增益（右方指挥所）----
func buff_level(kind: String) -> int:
	return int(buff_levels.get(kind, 0))

## 下一级的价格；**已满级 ⇒ −1**（界面据此把按钮写成"已满级"）
func buff_price(kind: String) -> int:
	var level := buff_level(kind)
	var prices: Array = GameConfig.ROGUELIKE_BUFF_PRICES.get(kind, [])
	if level >= GameConfig.ROGUELIKE_BUFF_MAX_LEVEL or level >= prices.size():
		return -1
	return int(prices[level])

## 不能买的原因（空串 = 能买）。⚠️ 与 `can_buy()` 同一套写法：界面既拿它灰按钮、也拿它当提示文案。
func buff_block_reason(kind: String) -> String:
	if phase != Phase.PREPARE:
		return "只能在准备阶段买增益"
	if selected_post != GameConfig.ROGUELIKE_POST_SIDE_STEADY:
		return "先点【右方】指挥所（持续增益）"
	if buff_level(kind) >= GameConfig.ROGUELIKE_BUFF_MAX_LEVEL:
		return "已经满级"
	var price := buff_price(kind)
	if supply < price:
		return "补给不足：这一级要 %d，还剩 %d" % [price, supply]
	return ""

## 买一级持续增益：扣钱 → 升级 → **立刻落到场上**（用户："增益买了就永久生效、与指挥所是否被摧毁无关"）。
## ⚠️ 它**不占**"每回合最多 2 队"的额度（用户裁决：两条经济分开）。
func buy_buff(kind: String) -> bool:
	var reason := buff_block_reason(kind)
	if reason != "":
		last_message = reason
		return false
	_push_undo("买下%s" % buff_name(kind))                        ## 撤销点：持续增益
	var price := buff_price(kind)
	supply -= price
	buff_levels[kind] = buff_level(kind) + 1
	_apply_steady_buff(kind)
	last_message = "买下%s：%s（花 %d 补给）" % [buff_name(kind), buff_level_text(kind), price]
	return true

## 增益的中文名（玩法侧给文案，界面不自己拼）
func buff_name(kind: String) -> String:
	match kind:
		GameConfig.ROGUELIKE_BUFF_ATTACK:
			return "进攻指令"
		GameConfig.ROGUELIKE_BUFF_DEFENSE:
			return "防御指令"
		GameConfig.ROGUELIKE_BUFF_UPGRADE:
			return "指挥部升级"
		GameConfig.ROGUELIKE_ROUND_BUFF_SUPPLY:
			return "紧急补给"
		GameConfig.ROGUELIKE_ROUND_BUFF_RANGE:
			return "射程增加"
		GameConfig.ROGUELIKE_ROUND_BUFF_SPEED:
			return "速度增加"
		GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT:
			return "紧急招募"
		GameConfig.ROGUELIKE_ROUND_BUFF_ELITE:
			return "精英招募"
	return kind

## 当前这条增益的效果文案（持续增益用）
func buff_level_text(kind: String) -> String:
	var level := buff_level(kind)
	match kind:
		GameConfig.ROGUELIKE_BUFF_ATTACK:
			return "全体伤害 +%d%%（%d 级）" % [int(GameConfig.ROGUELIKE_BUFF_STEP * 100.0) * level, level]
		GameConfig.ROGUELIKE_BUFF_DEFENSE:
			return "全体生命 +%d%%（%d 级）" % [int(GameConfig.ROGUELIKE_BUFF_STEP * 100.0) * level, level]
		GameConfig.ROGUELIKE_BUFF_UPGRADE:
			return "指挥所 +%d 血 / 减益 −%0.1f s（%d 级）" % [
					int(GameConfig.ROGUELIKE_BUFF_HP_PER_LEVEL) * level,
					float(GameConfig.ROGUELIKE_POST_DEBUFF_CUT_MS * level) / 1000.0, level]
	return "%d 级" % level

## 把某一项持续增益**立刻落到场上**。
## ⚠️ 三个 kind 各有各的落法（见各自的注释）—— 这是本块唯一一处"买完就改场上状态"的地方。
func _apply_steady_buff(kind: String) -> void:
	match kind:
		GameConfig.ROGUELIKE_BUFF_ATTACK:
			## 伤害：只写场地上那个倍率（单位每帧自己读，见 `Arena.damage_mult_for()`）
			arena.team_damage_buff[0] = 1.0 + GameConfig.ROGUELIKE_BUFF_STEP * float(buff_level(kind))
		GameConfig.ROGUELIKE_BUFF_DEFENSE:
			## 生命：**一次性加上限并补血**（用户裁决"加上限并补血"）—— 场上每个我方单位加"这一级的增量"
			for unit in arena.units_of_team(0):
				var other := unit as Unit3D
				if other != null and is_instance_valid(other) and other.alive:
					other.add_hp_bonus(_defense_bonus_total(String(other.type_id), 1))
		GameConfig.ROGUELIKE_BUFF_UPGRADE:
			## 指挥部升级：我方**两座**指挥所各 +300 血（上限与当前血一起加）
			for post in posts_of_team[0]:
				var unit := post as Unit3D
				if unit != null and is_instance_valid(unit) and unit.alive:
					unit.add_hp_bonus(GameConfig.ROGUELIKE_BUFF_HP_PER_LEVEL)

## 某一类单位在"防御指令 `levels` 级"下应得的**总加成** = 基础血上限 × 12% × 级数。
## ⚠️ 基数取**基础血上限**（`GameConfig.max_hp()`），不是"当前上限" —— 否则三级会在这上面累乘成 ×1.40，
## 而口径是 ×1.36（12% × 3）。
func _defense_bonus_total(type_id: String, levels: int) -> float:
	return GameConfig.max_hp(type_id) * GameConfig.ROGUELIKE_BUFF_STEP * float(levels)

## 给**一个刚上场的单位**补上它该有的防御加成（买过防御指令的话）。买兵 / 摆指挥所 / 四选一白送都走它。
func _grant_defense_bonus(unit: Unit3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var levels := buff_level(GameConfig.ROGUELIKE_BUFF_DEFENSE)
	if levels > 0:
		unit.add_hp_bonus(_defense_bonus_total(String(unit.type_id), levels))

## 某一队还活着几座指挥所（界面与探针共用）。
## ⚠️ **先判 `is_instance_valid()` 再 `as Unit3D`**：指挥所被打掉后 `posts_of_team` 里留的是**失效引用**
##（重建发生在下一回合开始，见 `_revive_posts()`），而对失效对象做 `as` 转型会直接报
## "Trying to cast a freed object" —— 实测撞到过（敌方长弓手打掉我方指挥所之后，界面每 100 ms 报一次）。
func posts_alive(team: int) -> int:
	var total := 0
	for post in posts_of_team[team]:
		if post == null or not is_instance_valid(post):
			continue
		var unit := post as Unit3D
		if unit != null and unit.alive:
			total += 1
	return total

## ---- 单回合增益（左方指挥所）----
## 价格：射程 / 速度各 `ROGUELIKE_ROUND_BUFF_PRICE`；**紧急补给是"借"、价 0**（它靠下回合的欠账还）；
## **精英招募价 10**（2026-09-27 用户给定）。
func round_buff_price(kind: String) -> int:
	if kind == GameConfig.ROGUELIKE_ROUND_BUFF_SUPPLY:
		return 0
	if kind == GameConfig.ROGUELIKE_ROUND_BUFF_ELITE:
		return GameConfig.ROGUELIKE_ELITE_PRICE
	return GameConfig.ROGUELIKE_ROUND_BUFF_PRICE

func has_round_buff(kind: String) -> bool:
	return round_buffs.has(kind)

## 本回合还欠多少"紧急补给"的账（界面显示用）
func loan_debt() -> int:
	return _loan_debt

func round_buff_block_reason(kind: String) -> String:
	if phase != Phase.PREPARE:
		return "只能在准备阶段买增益"
	if selected_post != GameConfig.ROGUELIKE_POST_SIDE_ROUND:
		return "先点【左方】指挥所（单回合增益）"
	if has_round_buff(kind):
		return "本回合已经买过了（单回合增益每回合各限一次）"
	var price := round_buff_price(kind)
	if supply < price:
		return "补给不足：这一项要 %d，还剩 %d" % [price, supply]
	return ""

## 买单回合增益：只在**当回合**有效（回合开始时由 `_enter_prepare()` 清掉）。
## ⚠️ 射程 / 速度对**当回合新买的兵**同样生效（用户裁决）：它们写的是场地上那两个字段，
## 而单位是每帧去读的 ⇒ 新兵天生就吃 ✓（不需要再补一遍）。
func buy_round_buff(kind: String) -> bool:
	var reason := round_buff_block_reason(kind)
	if reason != "":
		last_message = reason
		return false
	_push_undo("买下%s" % buff_name(kind))                        ## 撤销点：单回合增益
	supply -= round_buff_price(kind)
	round_buffs[kind] = true
	match kind:
		GameConfig.ROGUELIKE_ROUND_BUFF_SUPPLY:
			supply += GameConfig.ROGUELIKE_LOAN_GAIN
			_loan_debt += GameConfig.ROGUELIKE_LOAN_DEBT
			last_message = "紧急补给：现在 +%d，下回合开始扣 %d（补给可为负）" % [
					GameConfig.ROGUELIKE_LOAN_GAIN, GameConfig.ROGUELIKE_LOAN_DEBT]
		GameConfig.ROGUELIKE_ROUND_BUFF_RANGE:
			arena.team_range_bonus[0] = GameConfig.ROGUELIKE_ROUND_RANGE_BONUS
			last_message = "射程增加：本回合我方远程 +%0.0f m" % GameConfig.ROGUELIKE_ROUND_RANGE_BONUS
		GameConfig.ROGUELIKE_ROUND_BUFF_SPEED:
			arena.team_speed_bonus[0] = GameConfig.ROGUELIKE_ROUND_SPEED_BONUS
			last_message = "速度增加：本回合我方全体 +%0.1f m/s" % GameConfig.ROGUELIKE_ROUND_SPEED_BONUS
		GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT:
			## 紧急招募（第六块）：**只是本回合的组队名额 +1** —— 额度不写进任何字段，
			## 由 `squad_limit_this_round()` 现算（买过就在基准上加，回合开始时 `round_buffs` 清空即失效）。
			last_message = "紧急招募：本回合可额外招募 %d 队（本回合上限 %d 队）" % [
					GameConfig.ROGUELIKE_RECRUIT_BONUS_SQUADS, squad_limit_this_round()]
		GameConfig.ROGUELIKE_ROUND_BUFF_ELITE:
			## 精英招募（2026-09-27 第三轮）：**本回合"买"下的兵 +1 级**（用户："本回合招募的兵种等级增加1级"）。
			## ⚠️ 它是个**标记**：生效点在 `buy_squad()` 末尾（买完再补一级），**不改已到手的队**
			##（用户裁决"只给买的"⇒ 起手白送的两队就算买了也不算）。回合开始 `round_buffs` 清空即失效。
			last_message = "精英招募：本回合买下的兵 +1 级，招募价加上这一队的升级费（封顶 %d 级）" % GameConfig.ROGUELIKE_LEVEL_MAX
	return true

## 本回合的**组队名额**：基准 `ROGUELIKE_SQUADS_PER_ROUND` + 本回合买过的「紧急招募」加成。
## ⚠️ 买卖判据（`buy_block_reason()`）与界面显示**共用这一个口** —— 两边各写一遍必然漂移
##（"界面说还能买、点了却说买满"这一类 bug 的根就在这种地方）。
func squad_limit_this_round() -> int:
	var bonus := GameConfig.ROGUELIKE_RECRUIT_BONUS_SQUADS if has_round_buff(
			GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT) else 0
	return GameConfig.ROGUELIKE_SQUADS_PER_ROUND + bonus + aid_extra_squads

# ---------------------------------------------------------------- 暂停 / 恢复（暂停菜单用）
## 与 `Game.pause_match()` / `Sandbox.pause_match()` 同一套语义与同一条实现路径（`MatchPause`）。
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
## 探针用：每个移动信标一行 `[id, 点数, 路线全长 m, 圆心 x, 圆心 z]`（点数 < 3 = 路线还没画完）
func _beacon_route_rows() -> Array:
	var out: Array = []
	for prop in props:
		if String(prop["kind"]) != GameConfig.ROGUELIKE_PROP_BEACON:
			continue
		var pts: Array = prop.get("points", [])
		var length := 0.0
		for i in range(1, pts.size()):
			length += Vector3(pts[i]).distance_to(Vector3(pts[i - 1]))
		var pos: Vector3 = prop["pos"]
		out.append([int(prop["id"]), pts.size(), snappedf(length, 0.1), snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)])
	return out

## 每件道具一行：`[编号, kind, x, z, 血量, 上弦剩余 ms, 已触发]`
## ⚠️ 只报**数字 / 字符串**（不把外观节点递出去）—— 与 `squad_rows` 同一条纪律。
func _prop_rows() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for prop in props:
		var armed_ms := 0
		if int(prop["armed_ms"]) > 0:
			armed_ms = maxi(GameConfig.ROGUELIKE_TRAP_DELAY_MS - (now - int(prop["armed_ms"])), 0)
		var pos: Vector3 = prop["pos"]
		out.append([int(prop["id"]), String(prop["kind"]), snappedf(pos.x, 0.01), snappedf(pos.z, 0.01),
				snappedf(float(prop["hp"]), 0.1), armed_ms, bool(prop["triggered"])])
	return out

## 每队一行摘要（探针用）：`[锚点格 x, 锚点格 y, 旋转, 允许换位的回合, 活着的兵数, 该队兵数]`
func _squad_rows() -> Array:
	var out: Array = []
	for i in range(squads.size()):
		var info: Dictionary = squads[i]
		out.append([int(info["anchor_col"]), int(info["anchor_row"]), bool(info.get("rotated", false)),
				int(info.get("move_round", 0)), _living_slots(i).size(), int(info["units"])])
	return out

func _mcp_state() -> Dictionary:
	return {
		"phase": phase_name(),
		"round": round_index,
		"round_count": GameConfig.ROGUELIKE_ROUND_COUNT,
		"supply": supply,
		"income_total": income_total,
		"income_this_round": GameConfig.roguelike_supply_income(round_index),
		"hp": hp,
		"hp_max": hp_max,
		## 敌人还没做 ⇒ 这两个读数本步应当恒为 0（探针靠它们确认"扣血路径没被误触发"）
		"enemy_weight": enemy_weight(),
		"enemy_alive": arena.alive_count(_enemy_team()) if arena != null else 0,
		"units": arena.units.size() if arena != null else 0,
		## ---- 第二块（商店 / 起手 / 布阵）----
		"starter_chosen": starter_chosen,
		"starter_choices": starter_choices,
		"pool": pool.duplicate(),
		"squads": squads.size(),
		"squad_weight_total": squad_weight_total(),
		"bought_this_round": bought_this_round,
		"unlocked_this_round": unlocked_this_round,
		"grid_visible": _grid != null and _grid.visible,
		"last_message": last_message,
		## ---- 第四块（布阵交互：点选 / 拖动 / 右键旋转 / 回合开始恢复）----
		"selected_squad": selected_squad,
		"dragging": _dragging,
		"drag_squad": _drag_squad,
		"drag_anchor": [_drag_anchor.x, _drag_anchor.y],
		"drag_valid": _drag_valid,
		"drag_rotated": _drag_rotated,
		"occupied_cells": _occupied.size(),
		## 道具（陷阱 / 魔法盾）：每件一行 + 拖放状态 + 场地上登记的挡弹物数量
		"props": _prop_rows(),
		"trap_count": prop_count(GameConfig.ROGUELIKE_PROP_TRAP),
		"shield_count": prop_count(GameConfig.ROGUELIKE_PROP_SHIELD),
		"placing": _placing,
		"place_pos": [snappedf(_place_pos.x, 0.01), snappedf(_place_pos.z, 0.01)],
		"place_valid": _place_valid,
		"arrow_blockers": arena.arrow_blockers.size() if arena != null else 0,
		## 第六 / 七块：信标拥有权 / 路线编辑状态 / 测试敌人 / 本回合的组队名额
		"beacon_owned": _beacon_owned,
		"route_editing": _route_editing,
		"route_points": _route_points.size(),
		"beacon_routes": _beacon_route_rows(),
		"test_enemy_alive": _test_enemy_alive(),
		"squad_limit": squad_limit_this_round(),
		## ---- 第七块（场地长 ×1.5 + 南北两条前进布阵带 + 准备期；2026-09-27 按红笔标注订正位置）----
		"arena_half": [arena.half_x, arena.half_z] if arena != null else [0.0, 0.0],
		"zone_span_x": GameConfig.roguelike_zone_span_x(),
		"zone_depth": GameConfig.ROGUELIKE_ZONE_DEPTH,
		"zone_cells_x": GameConfig.roguelike_zone_cells(),
		"zone_rows_north": [_zone_row_range(-1).x, _zone_row_range(-1).y],
		"zone_rows_south": [_zone_row_range(1).x, _zone_row_range(1).y],
		"field_rows": [_field_row_range().x, _field_row_range().y],
		"zone_cols_team0": [_zone_col_range(0).x, _zone_col_range(0).y],
		"zone_cols_team1": [_zone_col_range(1).x, _zone_col_range(1).y],
		"zone_prep_ms": GameConfig.ROGUELIKE_ZONE_PREP_MS,
		## 每队一行：`[锚点格 x, 锚点格 y, 旋转, 允许换位的回合, 活着的兵数, 该队兵数]`
		"squad_rows": _squad_rows(),
		"selected_squad_stats": squad_stats(selected_squad),
		## ---- 第三块（指挥所 / 增益）----
		"posts_alive": [posts_alive(0), posts_alive(1)],
		"selected_post": selected_post,
		"buff_levels": buff_levels.duplicate(),
		"round_buffs": round_buffs.keys(),
		"loan_debt": _loan_debt,
		"post_debuff_ms": post_debuff_ms(),
		"debuff_active": [arena.debuff_active(0), arena.debuff_active(1)] if arena != null else [],
		"team_damage_mult": [arena.damage_mult_for(0), arena.damage_mult_for(1)] if arena != null else [],
		"team_range_bonus": [arena.range_bonus_for(0), arena.range_bonus_for(1)] if arena != null else [],
		"team_speed_bonus": arena.team_speed_bonus.duplicate() if arena != null else [],
		"enemy_combatants": _enemy_combatants(),
		"last_result": result,
		"summary": summary,
	}
