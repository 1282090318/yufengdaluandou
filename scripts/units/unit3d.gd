class_name Unit3D
extends CharacterBody3D
## 选手（战斗单位）
##
## 属性来自 GameConfig.PROFILES：血量 / 伤害 / 攻速 / 射程 / 权重 / 移速（六项）。
## 状态机：idle -> move -> attack ->（dead）
## 依据：docs/bible/02_entities.md、03_rules.md#5-状态机
##
## 说明：动作手感参数（转向速度 / 前摇比例 / 闪白时长 / 命中宽容 / 减速度 / 浮动幅度）
## 定义在 `GameConfig` 的"选手动作手感"段，本节点不保存副本。

enum State { IDLE, MOVE, ATTACK, DEAD }

## 炎爆（火焰拳技能，2026-09-19 新增）的四段流程：蓄力 → 冲刺 → 撞上后的待爆 →（回到 IDLE）。
## 当前段的截止时刻存在 `_flame_until_ms`（绝对 ms，遵守不变量 I-13）。
enum Flame { IDLE, CHARGE, DASH, DELAY }

## 潜地（沙虫技能，2026-09-19 新增）的四段：露出 → 钻入 → 地下 → 钻出。
## 只有 `SURFACED` 能被锁定 / 挨打；两个过渡段锁住移动与出手；`UNDER` 是**唯一的移动态**。
enum Burrow { SURFACED, SINKING, UNDER, RISING }

## 拔刀斩（武士大师技能，2026-09-25 新增）的五段：没在放 → 后撤 10 m → 蓄力 1 s → 穿人冲 35 m → 自己定身 1.5 s。
## `NONE` 之外的四段各自把截止时刻写进 `_iai_until_ms`（绝对 ms，遵守不变量 I-13）；
## 被眩晕 / 定身打断时由 `_interrupt_skill()` 直接清回 `NONE`（技能作废，冷却照走）。
enum Iai { NONE, RETREAT, CHARGE, DASH, SELF_ROOT }
## 扇子兵出手时**上下扇动**的幅度（弧度，2026-09-24）：扇面水平铺开，绕本体 X 轴（水平轴）
## 抬起/压下这么多——观感是"扇了一下"，不是"横扫了一下"。
## ⚠️ 这只是一个**表现**角度：出手节奏（前摇 / 间隔 / 伤害 / ±45° 扇形判定）全部不变，
## 判定与手感仍只由 `GameConfig.PROFILES` 决定（见 `04_physics.md#5.2`）。
const FAN_FLAP_ANGLE := 0.55

## 眩晕的**最小可视反馈**（2026-09-19 新增状态）：眩晕期间模型原地左右摇晃到这个角度，平时归零。
## ⚠️ 写的是 `_visual.rotation.z`，与 `_tick_dying()` 的阵亡倒地**共用同一个属性** ⇒ 只在 `alive` 时写
##（`_process` 里那一支本来就是 `alive` 门控的），且不眩晕时必须显式归零。
const STUN_SWAY_ANGLE := 0.12

## 炎爆三段特效的时长（2026-09-19 新增）：纯**表现参数**，按 `08_naming.md#3.3` 的特性域前缀留在本脚本里
##（不进 `GameConfig` —— 那里只放会影响判定的数值，不变量 I-15）。
##   · `FLAME_FX_HIT_MS` = 冲撞爆燃烧多久；
##   · `FLAME_FX_BLAST_MS` = 爆炸火池烧多久（取 900 < 自晕 1000 ms ⇒ 火池收干净时人刚好恢复行动）；
##   · `FLAME_FX_SPIN` = 特效自转角速度（rad/ms），纯观感。
const FLAME_FX_HIT_MS := 320
const FLAME_FX_BLAST_MS := 900
const FLAME_FX_SPIN := 0.0045
## 爆炸火池离地高度（m，纯表现）：火盘/火墙的挂点在爆炸中心，抬高一点点免得和地面共面闪烁。
const FLAME_FX_BLAST_LIFT := 0.06

## 沙虫**浮出"震地"特效**（2026-09-19 用户："沙柱爆开（更重的版本）"）的播放参数：同样是纯**表现参数**，
## 按 `08_naming.md#3.3` 的技能特效域前缀留在本脚本里（与 `FLAME_FX_*` 同一类，不进 `GameConfig`）。
## ⚠️ 半径**不在这里**：它直接读 `GameConfig.UNIT_SANDWORM_SURFACE_STUN_RADIUS`（4 m）⇒
## 观感与眩晕判定边界重合（与炎爆火池取 `UNIT_FLAME_BLAST_RADIUS` 同一条规矩）。
const BURROW_FX_BURST_MS := 420       ## 一次爆发的总时长（ms）：沙浪撑开 + 沙环扩散 + 沙团外飞 + 淡出
const IAI_SLASH_FX_MS := 400          ## 拔刀斩落地那一圈刀光留多久
const BURROW_FX_BURST_RISE := 1.35    ## 结束时沙浪/沙团离地高度（m，纯观感，读起来是"炸起来"）
const BURROW_FX_BURST_SPREAD := 1.0   ## 沙团外散距离 = 判定半径 × 本值（1.0 ⇒ 正好散到圈边）

## 潜地的**视觉下沉深度**（m，纯表现）：⚠️ 2026-09-19 用户："钻地太浅了模型穿帮，应让它完全潜到地里" ⇒
## 不再写死（原来固定 2.6 m，而模型已经有 5.12 m 高，必然露头），改成**按判定体高度推导**：
## 沙虫的盒子多高就沉多深、再留 0.6 m 余量 ⇒ 以后换模型自动跟着走。
## ⚠️ 只压 `visual.position.y`（与呼吸浮动、血条同一处），**不动碰撞体**：身体照旧站在地面上，只是看不见；
## "不可锁定 / 无敌 / 免疫状态"是另一套（`is_burrowed()`）。
func _resolve_sink_depth() -> float:
	var body_box: Dictionary = GameConfig.body_box(type_id)
	if body_box.is_empty():
		return 3.0                      ## 人形不会潜地，给个够用的兜底值
	return (body_box["size"] as Vector3).y + 0.6

var team: int = 0
var type_id: String = "sword"
var alive: bool = true
var active: bool = false        ## 比赛开始后才行动

var max_hp: float = 1.0
var hp: float = 1.0
## ---- 等级（2026-09-27 肉鸽第三轮：新增"单位等级"）----
## 用户口径："等级每增加1，攻击和血量就增加一倍" + 后一条澄清"**倍率 = L**（2 级 2 倍、9 级 9 倍）"，
## 并且**倍率是独立乘区**：百分比加成彼此相加（同一乘区），倍率与它们**逐个相乘**。
## ⚠️ 本字段是**通用单位属性**（不限于肉鸽）：别的模式不设它 ⇒ 恒为 1 ⇒ `level_mult()` = 1.0
## ⇒ 伤害 / 血量与改动前**逐位相同**。上限（9 级）由**调用方**（肉鸽）把住，本类只保证 ≥ 1。
var level: int = 1
var _hp_base: float = 1.0          ## `_ready()` 里记下的**原始**血量（不含任何加成 / 倍率）
var _hp_bonus_flat: float = 0.0    ## 累加进来的**加法**血量（防御指令那类百分比折算出来的平量）
## 最后一个打到我的单位（击杀归因用，2026-09-27）。⚠️ **不改任何信号**（I-34 不受影响）：
## `Events.unit_died(unit)` 照旧只带死者，击杀者由肉鸽侧读 `killer()` 拿。
var _last_hitter: Unit3D = null
var stack_count: int = 0        ## 兴奋圈外的内伤层数
var excited: bool = false

var target: Unit3D = null
## 玩家正在操作这个单位（沙盒任意作战单位 / 生存只限我方）。为真时不自己走、不自己打、不自己放技能。
var piloted: bool = false
## 当前镜头的瞄准方向（含俯仰）。相机每物理帧写入。
var pilot_aim: Vector3 = Vector3(0.0, 0.0, -1.0)
var _pilot_attack_armed: bool = false
var _pilot_charge_dir: Vector3 = Vector3.ZERO
var _pilot_flame_dir: Vector3 = Vector3.ZERO
var _pilot_dash_from: Vector3 = Vector3.ZERO
var _pilot_iai_dir: Vector3 = Vector3.ZERO
## 起手时面前已经有人在攻击距离内，这次冲刺就不再因为“进入攻击距离”提前停下。
var _pilot_dash_stops_at_reach: bool = true
var _pilot_halo: MeshInstance3D = null
var _range_glow: bool = false
var _hover_glow: bool = false
var _outline_on: bool = false

var _state: int = State.IDLE
## ⚠️ 2026-09-19 用户："攻击速度重定义：将攻击变为类似技能冷却的样子（如原来攻速为 2 则攻击冷却 0.5 s），
## 只要冷却结束就能攻击，所有单位现在的普通攻击都得跟着普攻动画（即和动画同步）"。
## ⇒ 攻击节奏改成**绝对时刻的冷却**（不变量 I-13，与技能冷却同源）；`_attack_timer` 从"逐帧累加器"
## **降级为只读的动画时钟**（0 = 起手、`windup` = 命中帧、`interval` = 收招结束），
## 由 `_tick_attack()` 每帧从下面两个绝对时刻推导 ⇒ `_animate_attack()` 的姿态曲线**一个字节都不用改**。
var _attack_timer: float = 0.0
## 这一刀的**命中帧**（绝对 ms；0 = 还没有排程）。冷却 = `attack_interval()`（含圈外 ×2 倍率），
## 并且**从命中那一刻重新起算**（用户口径："在造成伤害后重新冷却"）⇒ 命中间隔恒等于面板间隔。
var _next_hit_ms: int = 0
## 当前动画链的**第 0 帧**（= 命中帧 − 前摇）⇒ 动画顶点与命中帧**逐帧同一格**（用户举的两个例子：
## 剑盾/骑士/狂战士"挥到最低点"、弩车"弦复位的瞬间"，都是这一刻）。
## 0 = 链条已断（刚进 ATTACK / 目标出射程 / 被眩晕）⇒ 下一刀**从头挥**，不会再出现"半截动画就命中"。
var _swing_from_ms: int = 0
var _flash: float = 0.0
## 被击退速度（不变量 I-26 第七项「重量」：冲量已在 `_add_knockback()` 里按重量缩小）
var _kb: Vector3 = Vector3.ZERO
## 本次击退的**击退数值**（= 冲量 ÷ `KNOCKBACK_SPEED`）：用于判"重量 < 击退数值 ⇒ 禁移"。
## 击退结束时清零。
var _kb_value: float = 0.0
## 可移动档里"上一帧叠加进 `velocity` 的击退分量"：本帧先收回，避免击退被逐帧累积。
var _kb_added: Vector3 = Vector3.ZERO
## 本次击退在"动量传递"时附带的伤害（只有弩车的击退 > 0，见 `04_physics.md#5.1` 的特例行）。
## 击退结束时清零。
var _kb_damage: float = 0.0
## 技能冷却截止时刻（绝对 ms，遵守不变量 I-13）。技能机制见 `02_entities.md#2.3`。
var _skill_cd_until_ms: int = 0
## 眩晕截止时刻（绝对 ms，遵守不变量 I-13）。**数值 = 持续时间**（用户 2026-09-19 新增的状态）：
## 眩晕期间无法进行任何行动（不移动 / 不转向 / 不攻击 / 不放技能），进行中的技能被打断。
## 施加入口 `apply_stun()`、判定 `is_stunned()`；⚠️ 它**不免疫**伤害与击退（那是两回事）。
var _stun_until_ms: int = 0
## **定身**（2026-09-25 用户："新增效果：定身：与眩晕同样为无法进行任何操作，但与眩晕的区别为
## 被定身的单位**无法被位移（包括击退）**"）：施加入口 `apply_root()`、判定 `is_rooted()`。
## ⚠️ 与眩晕的**唯一区别**就是"位移免疫"，"不能行动"那一半两者一样（见 `is_incapacitated()`）；
## 两者**可以同时挂着**，各自计时、互不覆盖。
## ⚠️ 名字用 `root` 而**不是** `immobilize`：本文件里 `immobile` / `is_knockback_immobile()`
## 已经被"击退禁移"占用了（另一件事），叫 `immobilize` 会与它撞车 —— 见 `08_naming.md#1.4`。
var _root_until_ms: int = 0
## **减速**（2026-09-26 肉鸽的陷阱：用户"使移动速度降低 80%，持续 3s"）：施加入口 `apply_slow()`、
## 判定 `is_slowed()`、取值 `slow_factor()`（`current_speed()` 末尾乘它）。
## ⚠️ 与「眩晕 / 定身」是**三件不同的事**：减速**照样能行动**（走位 / 出手 / 放技能全不受影响），
## 只是走得慢 ⇒ **不进 `is_incapacitated()`**，也不碰 `_interrupt_skill()`。
## ⚠️ 字段名以 `_ms` 结尾、整型 ⇒ 自动进 `shift_deadlines()` 的"`_*_ms` 属性扫描"（暂停恢复的补偿，
## 见本文件 `shift_deadlines()`）—— 这是**必须**的命名约定，改名会让暂停期间白流逝减速时间。
var _slow_until_ms: int = 0
## 减速生效时的**倍率**（0.20 = −80%）。⚠️ 与截止时刻分开存：同时挨两次减速时取"**更慢**的那个倍率
## + **更晚**的截止时刻"（与眩晕"取较长者"同一条口径，见 `apply_slow()`）。
var _slow_mult: float = 1.0
## ---- 移动信标（肉鸽第六块）：沿路线"**保持队形平移**" ----
## ⚠️ 与其余一切位移机制的分工：它**不改**基础移速、**不进**状态机，只在 `_think()` 里**接管这一帧的走位**
##（技能 / 击退 / 眩晕 / 定身都照旧优先 —— 见 `_think()` 里插入的那一行）。
## ⚠️ "保持队形"的落法：挂上路线的那一刻记下**自己到路线的垂直偏移**（`_beacon_offset`），之后每帧沿路线推进
## 同样的弧长、落点 = 路线上的点 + 那个偏移 ⇒ 全队像一块板子沿折线滑过去（不会挤到线上、也不会各自找路）。
var _beacon_points: PackedVector3Array = PackedVector3Array()  ## 路线（信标 → P1 → P2，世界坐标）
var _beacon_offset := Vector3.ZERO      ## 自己相对路线的垂直偏移（挂上那一刻定死）
var _beacon_arc: float = 0.0            ## 已沿路线推进的**弧长**（米）—— ⚠️ 原来叫 `_beacon_s`，单字母读不出来（用户裁决改名）
var _beacon_total: float = 0.0          ## 路线全长（米）
## ---- 前进布阵区的**准备期**（肉鸽第七块：用户"我方单位每当部署到这个场地时需要5s准备时间"）----
## 绝对毫秒（I-13），`0` = 没有准备期；施加入口 `apply_prep()`、判定 `is_preparing()`。
## ⚠️ 与「眩晕 / 定身」的异同：**"不能行动"那一半一样**（跳过 `_think()` ⇒ 不移动 / 不转向 / 不攻击 /
## 不放技能，`is_incapacitated()` 里也算数），**区别在"能不能被位移"** —— 准备期**不免疫**击退与动量转移
##（用户裁决："期间会被敌方攻击"）；而"连击退都免疫"只有定身有。
## ⚠️ 字段名以 `_ms` 结尾、整型 ⇒ 自动进 `shift_deadlines()` 的暂停补偿扫描（改名会破坏暂停语义）。
var _prep_until_ms: int = 0
## 这个单位是**哪一个回合被放进敌方延伸区的**（`-1` = 不在那儿）。由 `Roguelike` 在落位 / 挪位那一刻写。
## ⚠️ 它实现的是用户那句话的后半截："在这个区域部署后的**下一个回合开始则不需要启动时间**" ——
## 开战时只给"本回合刚被放进去的"（`zone_entered_round == round_index`）发准备期；上一回合就在里面、
## 一直没挪过的单位（字段还停在旧回合号）⇒ 免启动 ✓。复活 / 新生的兵默认 `-1`（重新从零算）。
var zone_entered_round: int = -1
## 炎爆的当前段与截止时刻（见 `enum Flame` 与 `_tick_flame_burst()`）。
var _flame_phase: int = Flame.IDLE
var _flame_until_ms: int = 0
## 蓄力开始时**锁定的那个单位**：蓄力期间一换目标就作废（2026-09-19 用户第二条），
## 冲刺也以它为准（而不是每帧重取 `target`，免得半路改道）。
var _flame_charge_target: Unit3D = null
## 被**冲撞**到的那个对象（2026-09-19 用户第五条）：爆炸改成**以它为中心**，所以要留住引用。
## 只有"真的撞上了"才记（`_flame_hit()`）；冲刺超时 / 对象半路死掉 ⇒ 保持 null ⇒ 爆炸回落到自身位置。
var _flame_blast_target: Unit3D = null
## 这一次爆炸的**中心**（世界坐标，爆炸那一刻定下）：判定与特效共用同一个点，观感=判定。
## 由 `_flame_explode()` 写、`_update_flame_fx()` 读（火池就画在这个点上）。
var _flame_blast_center: Vector3 = Vector3.ZERO
## 潜地（沙虫技能）当前段与过渡截止时刻（绝对 ms，遵守不变量 I-13），见 `enum Burrow` / `_tick_burrow()`。
var _burrow: int = Burrow.SURFACED
var _burrow_until_ms: int = 0
## "射程内连续没有敌人"的**起点**（绝对 ms；0 = 当前射程内有敌人 / 计时未开始）。
## ⚠️ 2026-09-19 用户："钻回地需要在范围内没有敌人并持续 0.6 秒才行" ⇒ 只有它满
## `GameConfig.UNIT_SANDWORM_SINK_DELAY_MS`（600 ms）才允许 `SURFACED → SINKING`；中途有敌人回来即归零。
var _no_enemy_since_ms: int = 0
## **浮出闸门**的截止时刻（绝对 ms；到达 `UNDER` 时写 = 那一刻 + `UNIT_SANDWORM_UNDER_MIN_MS`）。
## ⚠️ 与"移动闸门" `_burrow_until_ms` 是两件事：那条管"能不能在地下移动"，这条管"能不能浮出"
## （用户："钻到地里需过 0.6 秒才能钻出来"）。
var _rise_after_ms: int = 0
## 视觉下沉量 0~1（纯表现，`_process` 用它压 `visual.position.y`）。死亡时 `_die()` 直接归零 ⇒ 尸体看得见。
var _sink: float = 0.0
## 浮出后的**第一口是不是双倍**（沙虫技能，2026-09-19 用户："钻出地后的第一下攻击造成双倍伤害"）：
## `RISING → SURFACED` 那一帧置真，**真正咬中至少一个目标**之后才消耗掉（咬空保留，见 `_resolve_attack()`）；
## 重新钻地（`SURFACED → SINKING`）与押注阶段清除。数值住在 `GameConfig.UNIT_SANDWORM_FIRST_BITE_MULT`。
var _first_bite_double: bool = false
## 炎爆三段特效的挂点（`unit_factory.gd#_build_flame_fx()` 造好并出厂隐藏）：`_fx_charge` 挂在拳组下
##（跟着火球走）、`_fx_hit` 与 `_fx_blast` 挂在本体上。**只有火焰拳有**，其余兵种三个都是 null。
var _fx_charge: Node3D = null
var _fx_hit: Node3D = null
var _fx_blast: Node3D = null
## 两个**一次性**特效的截止时刻（绝对 ms，遵守不变量 I-13）：0 = 没在放。
## 蓄力那一段不用存，它由 `_flame_phase` 直接推出来（见 `_update_flame_fx()`）。
var _fx_hit_until_ms: int = 0
var _fx_blast_until_ms: int = 0
## 冲撞（骑士技能）的结束时刻：> 0 表示正在冲锋，撞到人或超时就归零。
var _charge_until_ms: int = 0
## 火箭跳跃（狂战士技能）：结束时刻 > 0 表示正在空中。
## ⚠️ 2026-09-19 用户第四条：跳跃水平距离改成**按被锁定对象的当前距离自适应**（取消了旧的
## "第二次起距离减半"）⇒ 记录跳跃次数的 `_jump_count` 随之删除，见 `_start_jump()`。
var _jump_until_ms: int = 0
## "穿队友"掩码的**待还原**时刻（绝对 ms，0 = 没有请求）：由 `_release_ally_ghost()` 起算，
## 由 `_tick_ally_ghost()` 在"身边没有队友"或超时时真正还原（见 `UNIT_ALLY_GHOST_CLEAR_RADIUS`）。
var _ghost_off_due_ms: int = 0
## 免疫窗口截止时刻（火箭跳跃的滞空 + 落地 0.5 s，见 `04_physics.md#5.2`）：窗口内 `apply_hit` 直接返回。
var _invuln_until_ms: int = 0
var _kb_until_ms: int = 0
## 尸体滑行截止时刻（ms）；> 0 表示"被击退致死、当前仍是实体"（2026-09-19）
var _corpse_slide_until_ms: int = 0
## 盾牌猛击的冷却截止时刻（ms），骑士第二技能，与冲撞各算各的（2026-09-19）
var _bash_cd_until_ms: int = 0
var _stack_due: int = 0
var _dying_ms: int = 0
# 卡住检测（修 bug 2b：被友军/围墙/被推开的目标顶住时，原地"假装在走"）
var _last_dist: float = -1.0
var _progress_ms: int = 0
var _sidestep_ms: int = 0
var _stuck_switches: int = 0
## 连续绕**巨物**的笔画数（2026-09-26）：巨物平时不左右交替，但连续
## `UNIT_SIDESTEP_BIG_STROKES` 次都没进展就换一次边（防"顶着盒子 + 围墙的夹角"死绕）。
var _stuck_big_strokes: int = 0

var _visual: Node3D = null
var _mount_detail: MeshInstance3D = null
var _lod_far: bool = false
## 模型自身的基准高度（= 工厂 `build()` 里设的 `visual.position.y`，载具的抬升量就在那里）。
## ⚠️ 2026-09-24 修 bug：走路浮动那一行原先**直接赋值** `_visual.position.y`（= 从 0 起算），
## 把载具的抬升量整个抹掉 ⇒ 投石车/弩车永远停在"未抬起"的高度、轮子与底座陷进地里
##（用户连续数轮报告的"依旧陷地"，根因在此，不在抬升量数值上）。
var _visual_base_y: float = 0.0
var _weapon: Node3D = null
var _weapon_rest: Vector3 = Vector3.ZERO
var _weapon_rest_pos: Vector3 = Vector3.ZERO
var _shield: Node3D = null
var _shield_rest: Vector3 = Vector3.ZERO
var _shield_rest_pos: Vector3 = Vector3.ZERO
var _striking: bool = false        ## 是否正在出手（出手期间剑盾兵的盾让开、挡不住箭）
var _body: MeshInstance3D = null
## 投石车的兜/石弹挂点（`unit_factory.gd#BucketPivot`）：每帧反向抵消抛臂角度，保持碗口朝上
var _siege_bucket: Node3D = null
## 弩车"上弦"的挂点（`unit_factory.gd#"ballista"` 分支）：顺序恒为 **[左, 右]**，四个数组一一对应。
## 只有弩车取到值；其余兵种四个数组都为空（`_apply_bow_draw` 会直接返回）。
var _bow_halves: Array[Node3D] = []        ## 两半弦的枢轴（位置就在弓臂梢上）
var _bow_bars: Array[MeshInstance3D] = []  ## 两半弦的弦杆（拉弦时长度跟着变，见 `_apply_bow_draw`）
var _bow_limbs: Array[Node3D] = []         ## 两根弓臂的枢轴（绕弓臂根转一点 = 整根弓臂后仰）
var _bow_tips: Array[Vector3] = []         ## 两半弦枢轴的**静止**位置（= 弓臂梢，`BowAssembly` 局部坐标）
## 弩车的上弦进度（0 = 静止的直弦，1 = 拉满）。只由 `_animate_attack` 推进，纯表现。
var _bow_draw: float = 0.0
## 潜地沙尘的挂点（`unit_factory.gd#_build_burrow_fx()`，只有沙虫有）：潜入地下时显示，示意它的位置。
var _fx_burrow: Node3D = null
## 沙尘的浓淡 0~1（纯表现）：只在"在地下 **且** 真的在动"时淡入，否则淡出（用户："只有在沙虫移动的时候
## 才会出现，且要逐渐出现和消失"）。`_dust_puffs` 是那六团小沙尘，用于"时不时外冒"。
var _dust: float = 0.0
var _dust_puffs: Array[MeshInstance3D] = []
## 浮出"震地"特效的挂点（`unit_factory.gd#_build_burst_fx()`，只有沙虫有）：
## 与 `_fx_burrow`（潜地时的**待机**沙尘）分开两套 —— 这一套是**一次性爆发**，由
## `_tick_burrow()` 的 `RISING → SURFACED` 触发、`_update_burst_fx()` 在 `_process` 里放完。
var _fx_burst: Node3D = null
var _burst_dome: MeshInstance3D = null
var _burst_pillar: Node3D = null
var _burst_ring: MeshInstance3D = null
var _burst_puffs: Array[MeshInstance3D] = []
## 这一次爆发结束的绝对时刻（0 = 没在播；遵守不变量 I-13，与其它一次性特效同一套写法）。
var _fx_burst_until_ms: int = 0
## 钻出地面后的**出手封锁**截止时刻（绝对 ms，遵守不变量 I-13）：用户："钻出地后 0.3 秒后才能攻击"。
var _attack_block_until_ms: int = 0
## 轻骑兵（矛）技能·**冲刺**（2026-09-25 新增 / 同日大改，见 `02_entities.md#2.3`）：
## 结束的截止时刻（绝对 ms，遵守不变量 I-13）。> 0 = 正在冲刺。
var _lance_until_ms: int = 0
## 冲刺方向（世界 XZ 单位向量，y 恒为 0）。⚠️ **2026-09-25 起它是"当前朝向"而不是"锁死的方向"**：
## 用户把"不能更改方向"改成"**转弯时每秒最多旋转 180°**" ⇒ 方向每帧都可能变，
## 但**每帧的转角被转弯限速限住**（基档 180°/s；目标够不到时切 270°/s，见 `_lance_turn_deg_per_sec()`）。
var _lance_dir: Vector3 = Vector3.FORWARD
## 冲刺是不是已经打满 `UNIT_LANCE_CHARGE_SPEED`（一次冲刺只允许"提速"一次，见 `_lance_tick()`）：
## 发动时"锁定的目标"通常还在 7 m 外，那一段是**助跑**（按面板移速接近），
## 进到 `attack_reach()` 之内才切冲刺速度 —— 否则 7 m 外一发技能就直接以 14 m/s 撞上去，形同瞬移。
var _lance_sped_up: bool = false
## 这一次冲刺是否**已经停下脚步**。⚠️ **2026-09-25 第二条起恒为 false** ——
## 两条停步判据都已删除（用户两次报"冲到对面面前就停下"）。成员保留只为 `_mcp_state()` 与
## 回归探针的字段兼容；**不要再让它变成移动开关**（沿革与理由见 `_lance_tick()`）。
var _lance_stopped: bool = false
## **剩余冲刺次数**（用户："冲刺次数限制：2 次"，且"额度用完就只剩平 A，且不再游走"）。
## 每场（每个单位一生）只有 `UNIT_LANCE_CHARGES_MAX` 次，**不是**"每次冷却又给 N 次"。
## ⚠️ **2026-09-25 第四条起这个数是 1**（用户："且只能使用一次"）。
## ⚠️ **同日第五条把眩晕语义从"打断"改成"暂停"**（用户："被眩晕打断后能在眩晕结束时继续冲锋，
## （眩晕持续期间不进行技能持续时间计时），直到 10s 为止"）⇒ 冲刺**不会**因为挨晕而作废、
## 也**不退额度**：它压根没被消耗掉，只是"表停走"（见 `apply_stun()` / `_lance_tick()`）。
## ⚠️ 沿革：第四条曾短暂实现"被打断就退还额度"，**同日第五条已推翻** —— 别再往回调。
var _lance_charges_left: int = GameConfig.UNIT_LANCE_CHARGES_MAX
## 本次冲刺里**已经挨过矩形伤害**的单位（用户："每个进入矩形的兵种只会受到一次伤害，**离开矩形后重置**"）。
## ⚠️ 2026-09-25 修 bug（用户："有时候轻骑兵明显冲刺到了但没有反应"）：它现在只表示
## "**这一轮已经结算过**、且**此刻仍在矩形里**"的人 —— 逐帧用"还在框里"对齐，离开就移出 ⇒ 出去再进来可以再吃一次。
var _lance_hit_units: Dictionary = {}
## **自上一跳以来"进过矩形"、但还没结算的人**（逐帧累积，到跳拍帧一次性结算）。
## ⚠️ 它存在的唯一理由：**14 m/s × 0.3 s = 4.2 m > 矩形长 3.4 m** —— 只在跳拍帧才扫描的话，
## 目标待在框里的那 **0.243 s** 若整个落在两跳之间，就**一次都采不到**（典型几何：发动瞬间离静止目标
## 4.0~4.4 m ⇒ 第 1 跳在 t=0 还没进框、第 2 跳在 t=0.3 s 时它已经在身后）。修法是把两件事拆开：
## **"谁被扫到"逐帧不漏，"什么时候掉血"仍是 0.3 s 一跳。**
var _lance_box_pending: Dictionary = {}
## **矩形伤害的下一次结算时刻**（绝对 ms，0 = 立刻可结算，遵守不变量 I-13）。
## 2026-09-25（用户："冲刺时每 0.4 秒最多造成一次伤害"，同日又改口"冲刺期间攻击间隔变为 0.3"）：
## 结算**按 `UNIT_LANCE_BOX_TICK_MS` 的节拍**跑（原 400 → **现 300 ms**），不再每帧跑。
## ⚠️ 是**整条技能**的节拍、**不是**每个目标各自的冷却（一次结算里所有"新进入"的人都吃伤害）。
var _lance_next_box_ms: int = 0
## 冲锋**累计**打中过多少次（只增不减，与 `_lance_hit_units` 的"当前还在矩形里的人数"不同）：
## `_lance_hit_units` 是瞬时值、每帧会被清成"还在矩形里的人"，隔一会儿再读很容易读到 0；
## `_lance_hit_total` 单调递增，是"这趟冲锋到底打中没有"唯一可靠的读法（也进 `_mcp_state()`）。
var _lance_hit_total: int = 0
## 冷却期间游走的"横向绕行方向"（+1 / −1，每 `UNIT_LANCE_PATROL_TURN_MS` 翻转一次）
## 与下一次翻转的时刻（绝对 ms，遵守不变量 I-13）。
var _lance_patrol_side: float = 1.0
var _lance_patrol_turn_ms: int = 0
## "穿过所有单位"掩码的**待还原**时刻（绝对 ms，0 = 没有请求）：冲刺结束时由 `_release_pass_all()` 起算，
## 由 `_tick_pass_clear()` 在"身边没有单位与之交叠"或超时时真正恢复判定体。
## ⚠️ 与 `_ghost_off_due_ms`（穿队友的延时还原）是**两套独立机制**：那个只摘己方层、
## 这个连判定体一起停用，还原的条件也不同（那个只看队友，这个敌友都看）。
var _pass_clear_due_ms: int = 0
## 潜地的**视觉下沉深度**（m）：`_ready()` 里按判定体高度算一次，见 `_resolve_sink_depth()`。
var _sink_depth_m: float = 3.0

# ---- 武士大师的四技能（boss，2026-09-25 新增；数值全在 `GameConfig.UNIT_MASTER_*`）----
## ① 高级偏折（被动）：剩余额度 / 本冷却周期内已挡次数 / 冷却截止时刻（绝对 ms，遵守 I-13）。
## ⚠️ **默认 0**（2026-09-25 修 bug）：只有武士大师在 `setup()` 里被发到 15 次 —— 见 `try_deflect()`。
var _deflect_charges_left: int = 0
var _deflect_since_cd: int = 0
var _deflect_cd_until_ms: int = 0
## ② 冲刺：进行中的截止时刻（兜底）与方向、冷却截止时刻。
var _dash_until_ms: int = 0
var _dash_dir: Vector3 = Vector3.FORWARD
var _master_dash_cd_until_ms: int = 0
## ③ 后撤步：滑行段的起终点与截止时刻（2026-09-25 用户："后撤步应有动画" ⇒ 从瞬移改成 ~0.2 s 平滑滑出）、
## 冷却截止时刻、以及**禁冲刺**的截止时刻（用户："后撤步未完成时即后撤步完成后 0.3 s 内不得冲刺"）。
## ⚠️ 禁冲刺用的是**独立字段**而不是"滑行截止 + 300"：滑行结束时 `_backstep_until_ms` 会归 0，
## 拿它加 300 会把锁一起清掉。
var _backstep_from: Vector3 = Vector3.ZERO
var _backstep_to: Vector3 = Vector3.ZERO
var _backstep_until_ms: int = 0
var _backstep_cd_until_ms: int = 0
var _dash_lock_until_ms: int = 0
## ④ 拔刀斩：阶段枚举 + 各段的截止时刻 / 起点 / 终点 / 方向 / 待结算名单。
var _iai_phase: int = Iai.NONE
var _iai_until_ms: int = 0
var _iai_from_ms: int = 0
var _iai_cd_until_ms: int = 0
var _iai_dir: Vector3 = Vector3.FORWARD
var _iai_dash_from: Vector3 = Vector3.ZERO
var _iai_dash_to: Vector3 = Vector3.ZERO
## 被这一刀**穿过**、等着吃"定身结束那一刀"的人：`[{unit, due_ms}]`（`due_ms` = 它的定身结束时刻）。
var _iai_targets: Array = []

# ---------------------------------------------------------------- 心灵腐化（2026-09-25 第二轮）
## 「心灵腐化值」：`corruptor` 的攻击**不掉血**，改成往这里加数（见 `apply_hit()`）。
## 当它**大于自己的剩余血量**时，自己**整队换边**（用户口径）——判据在 `_tick_corruption()` 里。
var corrupt: float = 0.0
## 这一轮腐化是哪些我方腐化师叠上去的（实例编号 → 它所在的队）。停照清零时一起丢掉。
## 策反时按人数把经验分摊。同一人反复照射只记一次。
var _corrupt_contributors: Dictionary = {}
## 最近一次被「心灵腐化师」照射的绝对时刻 ms。⚠️ **名字带 `_ms`** ⇒ 自动进 `shift_deadlines()` 的
## 属性扫描（暂停恢复时一起后移）：否则暂停 10 s 回来，"刚才还在被照"会被算成"早就没照了"，
## 腐化值会凭空清掉 —— 与 I-13 的暂停口径相反。
var _corrupt_last_ms: int = 0
## 最近一次把腐化值叠上来的那名腐化师（「强化控制」回血时问它有没有这条科技）。
var _corrupt_from: Unit3D = null
## 激光的**蓄力截止时刻** ms（用户："经过 0.5s 蓄力后持续攻击这个目标"）。0 = 没在蓄力。
var _laser_charge_until_ms: int = 0
## 正在被这道激光照着的对象（≠ `target`：`target` 每帧可能被重锁，这个只在"换目标"时跟着变）。
var _laser_target: Unit3D = null
## 正在蓄力或照射的那面盾。-1 = 没有。和 `_laser_target` 不会同时有效。
var _laser_shield_id: int = -1
## 持续照射锁住的盾（魔法盾或「庇护」）。-1 = 没锁盾。边缘点每帧重算。
var _shield_lock_id: int = -1
var _shield_point: Vector3 = Vector3.ZERO
## 腐化条（2026-09-25 第二轮，用户要"看得见"）：与血条同一套做法（`UnitFactory.health_bar_texture`），
## 只是颜色换成紫色、且**挂在血条上方** —— 血条说"还剩多少血"，这一条说"离被策反还有多远"。
var _corrupt_bar: Sprite3D = null
var _corrupt_fill_px: int = -1
## 激光的可见光束（**持续照射那一族**会建：腐化师 / 湮灭之瞳，懒建，见 `_build_laser_beam()`）。
var _laser_beam: MeshInstance3D = null
## 「多重控制」多出来的四根射线（主锁仍走上面那根 `LaserBeam`）。节点名 `LaserBeam_1` … `LaserBeam_4`。
var _extra_beam_1: MeshInstance3D = null
var _extra_beam_2: MeshInstance3D = null
var _extra_beam_3: MeshInstance3D = null
var _extra_beam_4: MeshInstance3D = null
## 这四根各自锁着谁、蓄力到什么时候。截止时刻是成员而不是字典里的数，暂停扫描才移得到（I-13）。
var _beam_target_1: Unit3D = null
var _beam_target_2: Unit3D = null
var _beam_target_3: Unit3D = null
var _beam_target_4: Unit3D = null
var _beam_charge_ms_1: int = 0
var _beam_charge_ms_2: int = 0
var _beam_charge_ms_3: int = 0
var _beam_charge_ms_4: int = 0
## 额外射线各自的命中数。和主锁的 `_focus_hits` 分开：换一个人就从第 0 档重新蓄。
var _beam_hits_1: int = 0
var _beam_hits_2: int = 0
var _beam_hits_3: int = 0
var _beam_hits_4: int = 0
var _orbit_root: Node3D = null
var _orbit_orbs: Array = []
var _orbit_legs: Array = []
var _scatter_root: Node3D = null
var _scatter_orbs: Array = []
var _charge_root: Node3D = null
var _charge_core: Node3D = null
var _charge_motes: Array = []
var _scatter_motes: Array = []
## 「庇护」剩余血量。0 = 这回合的盾已经碎了，下一回合 `refresh_ward()` 再补满。
var _ward_hp: float = 0.0
var _ward_ring: MeshInstance3D = null
## 「能量汇集」（湮灭之瞳，2026-09-27 第十轮）：**对同一个目标**的连续命中数 —— 每 4 下升一档
##（伤害 30 → 90 → 300 → 1000、光束逐档变粗）。⚠️ 换目标 / 丢锁 / 这次照射中断后再打 ⇒ 归零。
var _focus_hits: int = 0
## 这档命中数是打在谁身上的。对不上当前目标时，这一下按第 0 档算。
var _focus_for: Unit3D = null
## 这次照射正在蓄力。蓄力没走完不出射线、也不结算伤害。
var _laser_arming: bool = false
## 这次照射已经蓄完，可以照着打。离开攻击或丢锁就清掉，下次必须重新蓄。
var _laser_engaged: bool = false
## 上一次给光束设过的档位（−1 = 还没设过）—— 用来**只在换档那一帧**改网格半径（免得每帧重建图元网格）。
var _beam_stage_drawn: int = -1

# ---------------------------------------------------------------- 影魔（2026-09-25 第三轮）
## 「影袭」冷却截止时刻 ms（用户："冷却4s"）。
var _strike_cd_until_ms: int = 0
## 影子形态的结束时刻 ms（0 = 不在影子里）。⚠️ 带 `_ms` ⇒ 自动进 `shift_deadlines()`。
var _shadow_until_ms: int = 0
## 影子形态的起点（位置 + 时刻）——滑行按"起终点线性插值"，与后撤步同一手法。
var _shadow_from: Vector3 = Vector3.ZERO
var _shadow_to: Vector3 = Vector3.ZERO
var _shadow_from_ms: int = 0
## 「时候已到」的**计时锚点**（上次出手那一刻 / 上一次"变回原身"那一刻）。
## ⚠️ 它是**起点**而不是截止时刻，但同样必须进 `shift_deadlines()`（不然暂停 10 s 回来，
## 加成会凭空涨到封顶 —— 与 I-13 的暂停口径相反）。带 `_ms` 就自动被扫到。
var _hour_anchor_ms: int = 0
## 影袭位移期间**贴在地上的那一道影子**（`UnitFactory` 建的 `FxShadowForm`，出厂即隐藏）。
## ⚠️ 它挂在**本体根**上（`_ready()` 里 re-parent）而不是 `_visual` 下：影子形态要求把整个人藏起来
##（`_visual.visible = false`），挂在它下面的话这道影子会跟着一起消失。
var _fx_shadow_form: Node3D = null

# ---------------------------------------------------------------- 召唤石柱（2026-09-25 第七轮，**仅沙盒模式**）
## 已经结算过的**召唤拍号**（= `⌊战斗已过毫秒 ÷ UNIT_SUMMON_INTERVAL_MS⌋`，0 = 还没召唤过）。
## ⚠️ 它记的是"完成了几拍"而不是"下一拍在什么时刻"——**时间锚点唯一地来自场地的沙盒战斗时钟**
##（`Arena.skirmish_elapsed_ms()`），于是暂停恢复只需平移场地那一个字段，这里不用自己记账。
var _summon_tick: int = 0
## 本场已经召唤出来的单位数（**只用于探针**：`_mcp_state()` 报它，验证"每 5 s 至少来一个"）。
var _summon_count: int = 0

# ---------------------------------------------------------------- 锚定（2026-09-26，目前只有召唤石柱）
## 出生点（**只看水平面**：x / z）。⚠️ 它**不是**"出生点快照"那种只读数据 —— 锚定单位每物理帧
## 的 x/z 都会被写回这里（见 `_hold_anchor()`），因为 `_anchor_pos` 是**权威值**，`global_position`
## 那一对分量只是它的影子。
## ⚠️ 名字带 `pos`（§3.3"坐标用 `pos` / `world_pos`"）：2026-09-26 由 `_anchor_xz` 改名，
## **不是换约定、是这次违反了明条**（用户当天裁决"只改这一处；`summon_escalation` 另案登记为例外"）。
var _anchor_pos: Vector2 = Vector2.ZERO
## 锚点是否已经捕获（第一个物理帧开头捕获，见 `_capture_anchor()`）。
var _anchor_set: bool = false

var _base_color: Color = Color.WHITE
## 血条（2026-09-19 重做：底槽 + 队伍色填充画在**同一张**贴图里，见 `_build_health_bar`）。
var _bar: Sprite3D = null
## 上一次烘进贴图的填充宽度（内区像素）—— 只有跨档才重建贴图，其余帧零开销；-1 = 还没建过。
var _bar_fill_px: int = -1
var _bar_ratio: float = 1.0
## 判定体节点（`_ready()` 里建的那个 `CollisionShape3D`）：**冲刺穿透**要临时把它的
## `disabled` 置真（见 `_set_pass_all()` —— 只摘碰撞层不够，因为层只决定"谁能看见我"，
## 真正让人穿过去的是"我身上有没有挡路的形状"）。
var _shape: CollisionShape3D = null

## 暂停恢复：把所有"**绝对毫秒截止时刻**"整体后移 `delta_ms`（见 `match_pause.gd#shift_deadlines()`）。
## ⚠️ 用**属性扫描**而不是逐个列字段：本项目所有计时都是绝对时刻（不变量 I-13），凡形如 `_xxx_ms`
## 的整型成员都是"截止时刻 / 起点时刻"，一起平移就对了 —— 逐个列字段的写法以后每加一个计时字段
## 就会漏一个（本项目在"注释/清单漂移"上已经踩过多次）。
## ⚠️ 只平移**正值**：0 在本项目的约定里是"没排程"（`_lance_until_ms == 0` = 没在冲刺），
## 平移它会把"没有的事"变成"未来某个时刻有事"。
## ⚠️ 2026-11-01：**属性名单改成只扫一次、之后缓存**（`_ms_props`）。
## 原先每调一次就 `get_property_list()` 全量扫一遍 —— 暂停补偿每场只调一两次，怎么都行；
## 可倍速（`MatchSpeed`）是**每物理帧**拉一次 ⇒ 74 个单位 × 每帧全量扫属性会立刻变成新的热点
##（那正是我们要消灭的东西）。同一个脚本的属性名单是固定的 ⇒ 缓存后逐位等价。
static var _ms_props: Array = []

func shift_deadlines(delta_ms: int) -> void:
	_shift_ms(delta_ms)

## 倍速那一半：把所有截止时刻**前移** `delta_ms`（正数 = 提前这么多毫秒）。见 `MatchSpeed` 的文件头。
## ⚠️ 方向记清楚：`shift_deadlines(+Δ)` = 往后推（暂停补偿），`pull_deadlines(+Δ)` = 往前拉（加速）。
func pull_deadlines(delta_ms: int) -> void:
	_shift_ms(-delta_ms)

func _shift_ms(delta_ms: int) -> void:
	if delta_ms == 0:
		return
	if _ms_props.is_empty():
		for prop in get_property_list():
			var prop_name := String(prop["name"])
			if not prop_name.begins_with("_") or not prop_name.ends_with("_ms"):
				continue
			if int(prop["type"]) != TYPE_INT:
				continue
			_ms_props.append(prop_name)
	for prop_name in _ms_props:
		var value := int(get(prop_name))
		if value > 0:
			set(prop_name, value + delta_ms)


## 竞猜存档用。截止时刻改成相对 `frozen_ms` 的剩余毫秒，读档时再加回当时的时钟。
func capture_for_save(frozen_ms: int) -> Dictionary:
	var deadlines := {}
	for prop in get_property_list():
		var prop_name := String(prop["name"])
		if not prop_name.begins_with("_") or not prop_name.ends_with("_ms"):
			continue
		if int(prop["type"]) != TYPE_INT:
			continue
		var value := int(get(prop_name))
		if value > 0:
			deadlines[prop_name] = value - frozen_ms
	return {
		"team": team,
		"type_id": type_id,
		"x": global_position.x,
		"y": global_position.y,
		"z": global_position.z,
		"yaw": rotation.y,
		"hp": hp,
		"alive": alive,
		"active": active,
		"level": level,
		"state": _state,
		"stack_count": stack_count,
		"excited": excited,
		"vel_x": velocity.x,
		"vel_z": velocity.z,
		"burrow": _burrow,
		"flame_phase": _flame_phase,
		"sink": _sink,
		"slow_mult": _slow_mult,
		"kb_x": _kb.x,
		"kb_z": _kb.z,
		"deadlines": deadlines,
	}


func apply_for_save(data: Dictionary, now_ms: int) -> void:
	var saved_level := int(data.get("level", 1))
	if saved_level > 1:
		set_level(saved_level)
	hp = float(data.get("hp", hp))
	alive = bool(data.get("alive", true))
	active = bool(data.get("active", false))
	global_position = Vector3(float(data.get("x", 0.0)), float(data.get("y", GameConfig.SPAWN_HEIGHT)), float(data.get("z", 0.0)))
	rotation.y = float(data.get("yaw", 0.0))
	_state = int(data.get("state", State.IDLE))
	stack_count = int(data.get("stack_count", 0))
	excited = bool(data.get("excited", false))
	velocity = Vector3(float(data.get("vel_x", 0.0)), 0.0, float(data.get("vel_z", 0.0)))
	_burrow = int(data.get("burrow", Burrow.SURFACED))
	_flame_phase = int(data.get("flame_phase", Flame.IDLE))
	_sink = float(data.get("sink", 0.0))
	_slow_mult = float(data.get("slow_mult", 1.0))
	_kb = Vector3(float(data.get("kb_x", 0.0)), 0.0, float(data.get("kb_z", 0.0)))
	var deadlines: Dictionary = data.get("deadlines", {})
	for key in deadlines.keys():
		set(String(key), now_ms + int(deadlines[key]))
	if not alive:
		_state = State.DEAD
		collision_layer = 0
		collision_mask = 0
	_bar_ratio = health_ratio()


func setup(p_team: int, p_type: String) -> void:
	team = p_team
	type_id = p_type

func _ready() -> void:
	add_to_group("units")
	add_to_group("team_%d" % team)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1 << (team + 1)          # 2 队 -> layer2，1 队 -> layer3
	collision_mask = 1 | (1 << 1) | (1 << 2)
	max_hp = GameConfig.max_hp(type_id)
	hp = max_hp
	_hp_base = max_hp
	_stack_due = Time.get_ticks_msec()
	## ① 高级偏折的**额度发放**（2026-09-25）：只有武士大师（`skill == "master"`）拿得到 15 次 ——
	## ⚠️ 字段默认值是 **0**，别改回"默认 15"：那会让**全场每个单位**都能反弹投射物
	##（火枪手因此开一枪就被自己的子弹打死，见 `try_deflect()` 的说明）。
	if String(GameConfig.profile(type_id).get("skill", "")) == "master":
		_deflect_charges_left = GameConfig.UNIT_MASTER_DEFLECT_CHARGES

	## 判定体（2026-09-19 用户："判定体应和视觉模型相符"）：人形 = 胶囊（历史 0.38 / 1.80，逐位不变），
	## 投石车 / 弩车 / 沙虫 = **盒体**，尺寸取引擎内实测的视觉包围盒（全部住 `GameConfig`，不变量 I-15）。
	## ⚠️ 胶囊中心在 0.90（脚底 + 半高）；盒体用 `lift` 直接给"盒心离地高度"。
	var shape := CollisionShape3D.new()
	var body_box: Dictionary = GameConfig.body_box(type_id)
	if body_box.is_empty():
		var capsule := CapsuleShape3D.new()
		capsule.radius = GameConfig.UNIT_BODY_CAPSULE_RADIUS
		capsule.height = GameConfig.UNIT_BODY_CAPSULE_HEIGHT
		shape.shape = capsule
		shape.position = Vector3(0.0, GameConfig.UNIT_BODY_CAPSULE_HEIGHT * 0.5, 0.0)
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = body_box["size"]
		shape.shape = box_shape
		shape.position = Vector3(0.0, float(body_box["lift"]), 0.0)
	add_child(shape)
	_shape = shape

	var parts: Dictionary = UnitFactory.build(type_id, team)
	_visual = parts["visual"]
	_visual_base_y = _visual.position.y
	_mount_detail = _visual.get_node_or_null("MountDetail") as MeshInstance3D
	## 模型里若有 `GroundLock`（**贴地件**的挂点，目前只有影魔的影滩 / 十片影摆 / 拖尾用它），
	## 就在 `_process()` 里**反向抵消**走路浮动 ⇒ 身体呼吸、影子始终贴地（见 `_visual.position.y` 那一行）。
	_ground_lock = _visual.get_node_or_null("GroundLock") as Node3D
	## 剑圣的刀光环（只有剑盾兵模型里才有这个件；其余兵种拿到 null ⇒ 那一支自动跳过）。
	_saint_ring = _visual.get_node_or_null("SlashRing") as MeshInstance3D
	_weapon = parts["weapon"]
	_shield = parts["shield"]
	_cache_beam_fx()
	add_child(_visual)
	if _weapon != null:
		_weapon_rest = _weapon.rotation
		_weapon_rest_pos = _weapon.position
		## 投石车才有这个挂点；其它兵种取到 null，后面按需判空。
		_siege_bucket = _weapon.get_node_or_null("BucketPivot")
		## 弩车才有这套上弦挂点（`unit_factory.gd#BowLimb_*` / `#BowStringHalf_*`）；
		## 其它兵种的弓组件里没有这些节点 ⇒ 两个都取不到就跳过，四个数组留空。
		for side in ["left", "right"]:
			var limb := _weapon.get_node_or_null("BowLimb_%s" % side) as Node3D
			var half := _weapon.get_node_or_null("BowString/BowStringHalf_%s" % side) as Node3D
			if limb == null or half == null:
				continue
			var bar := half.get_node_or_null("BowStringBar_%s" % side) as MeshInstance3D
			if bar == null:
				continue
			_bow_limbs.append(limb)
			_bow_halves.append(half)
			_bow_bars.append(bar)
			## 工厂把半弦枢轴放在臂梢上，所以此刻的 `position` 就是弦端的静止坐标；
			## 上弦后这个值会被逐帧改写，必须先缓存下来。
			_bow_tips.append(half.position)
	if _shield != null:
		_shield_rest = _shield.rotation
		_shield_rest_pos = _shield.position
	## 火焰拳的三段特效挂点（2026-09-19 新增）：只有火焰拳有这三个节点，其余兵种取到 null，
	## `_update_flame_fx()` 会直接返回 ⇒ 零开销。
	if _weapon != null:
		_fx_charge = _weapon.get_node_or_null("FxCharge") as Node3D
		_fire_edge = _weapon.get_node_or_null("FireEdge") as Node3D
	_bulwark_ring = _visual.get_node_or_null("BulwarkRing") as MeshInstance3D
	if _bulwark_ring != null:
		_bulwark_ring.reparent(self)
		_bulwark_ring.position = Vector3(0.0, 0.08, 0.0)
	_ember_aura = _visual.get_node_or_null("EmberAura") as MeshInstance3D
	var iai_fx := _visual.get_node_or_null("IaiFx") as Node3D
	if iai_fx != null:
		iai_fx.reparent(self)
		iai_fx.position = Vector3.ZERO
		_iai_charge = iai_fx.get_node_or_null("IaiCharge") as MeshInstance3D
		_iai_dash = iai_fx.get_node_or_null("IaiDash") as MeshInstance3D
		_iai_slash = iai_fx.get_node_or_null("IaiSlash") as MeshInstance3D
	_fx_hit = _visual.get_node_or_null("FxHit") as Node3D
	_fx_blast = _visual.get_node_or_null("FxBlast") as Node3D
	## ⚠️ 地面火池**不留在 `visual` 下**：`visual` 每帧有呼吸浮动、眩晕时还整体左右摇晃
	##（`STUN_SWAY_ANGLE`），6 m 的火盘挂在那儿会跟着倾斜/浮起 —— 而爆炸必然触发自晕 1 s，
	## 正好全程撞上。改挂到本体根上（本体根只有 yaw）；⚠️ 爆炸中心还可能不是自己
	##（2026-09-19 起以**被撞对象**为中心）⇒ 世界坐标由 `_update_flame_fx()` 每帧写死。
	if _fx_blast != null:
		_fx_blast.reparent(self)
	## 沙虫的潜地沙尘（只有沙虫有）：挂到**本体根**上 —— 它要留在地面上示意位置，
	## 不能跟着模型一起沉下去（`visual.position.y` 会被潜深压下去）。
	_fx_burrow = _visual.get_node_or_null("FxBurrow") as Node3D
	if _fx_burrow != null:
		_fx_burrow.reparent(self)
		for i in 6:
			var puff := _fx_burrow.get_node_or_null("DustPuff_%d" % i) as MeshInstance3D
			if puff != null:
				_dust_puffs.append(puff)
	## 沙虫**浮出"震地"**那一下（2026-09-19 新增）：同样挂到**本体根**上 —— 它是"从地里炸出来"的一层，
	## 必须留在地面高度上，不能跟着模型的下沉/呼吸浮动（`FxBurst` 出厂即隐藏，见 `_build_burst_fx()`）。
	_fx_burst = _visual.get_node_or_null("FxBurst") as Node3D
	if _fx_burst != null:
		_fx_burst.reparent(self)
		_burst_dome = _fx_burst.get_node_or_null("BurstDome") as MeshInstance3D
		_burst_pillar = _fx_burst.get_node_or_null("BurstPillar") as Node3D
		_burst_ring = _fx_burst.get_node_or_null("BurstRing") as MeshInstance3D
		for i in 6:
			var burst_puff := _fx_burst.get_node_or_null("BurstPuff_%d" % i) as MeshInstance3D
			if burst_puff != null:
				_burst_puffs.append(burst_puff)
	## 影袭的"地上影子"（2026-09-25 第七轮，只有影魔有这个节点）：与上面几个特效根**同一条理由**
	## 挂到本体根上 —— 影子形态会把 `_visual` 整个藏掉，挂在它下面这道影子就跟着没了。
	_fx_shadow_form = _visual.get_node_or_null("FxShadowForm") as Node3D
	if _fx_shadow_form != null:
		_fx_shadow_form.reparent(self)
		_fx_shadow_form.visible = false
	_sink_depth_m = _resolve_sink_depth()
	## ⚠️ 载具（投石车/弩车）没有躯干节点（`unit_factory.gd#VEHICLE_TYPES`）⇒ 用 `get_node_or_null`，
	## 否则会报 `Node not found: "Body"`（2026-09-24 实机抓到）。`_body` 只在染色/受击闪白里用，
	## 为 null 时下面两处都做了空判断。
	## ⚠️ **2026-09-25 起改成递归查找**（`find_child`，`owned = false`）：骑乘兵种（轻骑兵（矛））
	## 的人形被挂在 `Visual/Rider` 下面（见 `unit_factory.gd#rider_lift()`），**直接子节点查找会取到 null**
	## ⇒ 受击闪白对它**静默失效**（不报错、只是不闪 = 最难发现的那类回归）。
	## ⚠️ `owned` 必须显式传 false：这些节点是运行时 `new` 出来的，`owner` 为空，默认 true 会一个都匹配不到。
	_body = _visual.find_child("Body", true, false) as MeshInstance3D
	## 躯干**静止底色**的唯一出处（2026-09-25 第七轮）：除了影魔（它的躯干是**墨色**——用户要求
	## "整个人看起来要像一个影子"）之外，所有兵种都等于队伍色 ⇒ 逐位不变。
	## ⚠️ 为什么不能在这里写死 `team_color(team)`：受击闪白与「心灵腐化」换边都是**以这个值为基准**
	## 往白色 / 新队伍色上插值，基准要是取错了，影魔被打一下就会"变回一个彩色的人"。
	_base_color = UnitFactory.rest_body_color(type_id, team)
	_repaint_team_accents()
	_build_health_bar()
	Events.unit_spawned.emit(self)

## 重绘**队伍色锚点件**（节点名以 `TeamAccent` 开头的那几件，目前只有影魔的腰际束带与双眼）。
## ⚠️ 存在的理由：别的兵种把队伍色穿在**躯干**上，换边时由受击闪白那一路顺带改写；而影魔的躯干是
## 墨色（影子），它的队伍色单独挂在这几个件上 ⇒ **换边必须显式重绘一次**，否则策反后它仍戴着旧队的颜色。
## 没有这类件的兵种走一遍空循环（`find_children` 返回空数组）⇒ 零影响。
func _repaint_team_accents() -> void:
	if _visual == null:
		return
	var color := GameConfig.team_color(team)
	for node in _visual.find_children("TeamAccent*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = color
		if mat.emission_enabled:
			mat.emission = color

## 血条自己的常量（纯表现）：像素尺寸 × 贴图宽度 = 整条血条的世界长度。
## ⚠️ **2026-09-25 用户："增大兵种的血条，使其更容易被观察"** ⇒ 世界尺寸**等比放大到 3 倍**：
## 旧值 32 px × 0.011 = **0.35 × 0.066 m**（指挥视角下只有 ~5×1 像素，`05_ui_hud.md#6.1` 记的"已知限制"）
## → 现在 48 px × 0.022 = **1.06 × 0.198 m**。
## ⚠️ **为什么是 3 倍而不是 2 倍**：先按 2 倍做了一版，实机截图量下来指挥视角（43.9 m）只有
## **11 × 2.1 像素**、全景机位（74 m）只有 **6.4 × 1.2 像素** —— 宽度够了、**高度仍是一条 2 像素的细线**，
## 而"还剩多少"要靠高度分辨。3 倍下同一机位是 **16.7 × 3.1 像素**（全景 9.5 × 1.8），才真正读得出来。
## 贴图分辨率同步从 32×6 提到 **48×9**（`unit_factory.gd#HEALTH_BAR_INNER_PX` 30 → 46）：
## 放大之后**边缘不发虚**、填充档位反而更细（30 档 → 46 档）。
## ⚠️ 两个数必须一起改：只抬 `BAR_PIXEL_SIZE` 会把低分辨率贴图拉糊（每像素 0.022 m ⇒ 1 m 长的条只有 48 px）。
const BAR_PIXEL_SIZE := 0.022
const BAR_RENDER_PRIORITY := 4
## 腐化条（2026-09-25 第二轮）的两个表现参数：颜色与"挂在血条上方多高"。
## 紫色刻意与两队的世界队伍色（赤羽卫红 / 青锋卫蓝）、与 HUD 的警告橙都不一样 ⇒ 一眼分得开。
const CORRUPT_BAR_COLOR := Color(0.72, 0.36, 0.98)
const CORRUPT_BAR_LIFT := 0.18
## 激光光束（2026-09-25 第二轮）的两个表现参数 + 两个几何挂点。
## ⚠️ 材质**不透明 + 自发光**（不是透明 / 加色）：见 `_build_laser_beam()` 的理由（避免新着色器变体）。
const LASER_BEAM_RADIUS := 0.055
const LASER_BEAM_COLOR := Color(0.78, 0.42, 1.0)
const LASER_BEAM_EMISSION := 2.6
const LASER_BEAM_FALLBACK_Y := 1.18    ## 没有 `Prism` 节点时，光束起点取本体上方这么高（与工厂那颗棱镜同值）
const LASER_BEAM_AIM_Y := 0.9          ## 瞄目标身上的哪一点（大致胸口高；纯观感，不影响判定）
## 召唤石柱那道**琥珀色**光束的配色（2026-09-25 第七轮）：与腐化师的紫色刻意分开 ——
## 两种"无弹体直击"兵种同时在场时，一眼能看出是谁在打。
const SUMMON_BEAM_COLOR := Color(0.98, 0.72, 0.34)
const SUMMON_BEAM_EMISSION := 2.2
## 湮灭之瞳的**青白**光束（2026-09-27 第十轮）：与腐化师紫、石柱琥珀三者一眼分得开。
const DOOM_BEAM_COLOR := Color(0.45, 0.95, 1.0)
const DOOM_BEAM_EMISSION := 3.0
## 影袭"地上影子"沿滑行方向的**拉长倍数**（纯表现，2026-09-25 第七轮）：拉了才读得出"窜过去"，
## 不拉就是一个圆盘平移。⚠️ 它与 `unit_factory.gd` 的 `SHADOW_FORM_*`（那片影子的半径 / 厚度 / 配色）
## 属于**同一族** `SHADOW_*`（影魔的整套剪影），只是分居两个文件：几何在工厂、动画在本体。
const SHADOW_FORM_STRETCH := 1.8

## 血条挂点的高度：**跟着判定体走**（2026-09-19）——三个巨物的盒体很高（投石车盒顶 ≈ 3.1 m），
## 历史固定值 2.10 m 会把血条埋进模型里。人形取"胶囊顶 1.80 + 0.30"（= 历史值 2.10，逐位不变），
## 盒体取"盒顶 + 0.35"。
## ⚠️ **2026-09-25 追加"骑乘抬高"**（`UnitFactory.rider_lift()`）：骑马的轻骑兵视觉比判定体高出一大截，
## 血条留在 2.10 m 会**横穿骑手胸口 / 压在马颈上**。这是**纯表现**补偿 —— 判定体仍是胶囊 0.38 / 1.80，
## 出生间距 / 簇心间距 / 动量传递半径一概不动（用户裁定"判定体不变，只改视觉"）。
## 非骑乘兵种 `rider_lift()` 恒为 **0.0** ⇒ 这一项对其它 11 个兵种**逐位不变**。
func _bar_anchor_height() -> float:
	var body_box: Dictionary = GameConfig.body_box(type_id)
	if body_box.is_empty():
		return GameConfig.UNIT_BODY_CAPSULE_HEIGHT + 0.30 + UnitFactory.rider_lift(type_id)
	var size: Vector3 = body_box["size"]
	return float(body_box["lift"]) + size.y * 0.5 + 0.35

## 血条（2026-09-19 重做）：贴图里同时画着**长度恒定的底槽**与**按血量比例填充的队伍色**，
## 所以"还剩多少"可以直接比出来。两条口径都来自 bible：
##   · 受伤才出现 ——`01_core_loop.md#1`"血条实时下降，未满血才显示"；
##   · 颜色 = 自身队伍色 —— 取 `GameConfig.team_color()`，即 `00_world.md#4.3` 的**世界**队伍色
##     （⚠️ **不是** `05_ui_hud.md#1` 规则 3 那组 HUD 调色板，两套值不同，见 `99_decisions.md` 2026-09-19 条目）。
## ⚠️ 用**一张** sprite（不做两层叠加）：`material_override` 会让 sprite 自己的贴图失效
## （老代码的血条因此一直渲染成纯色方块），两层之间还会互相压 —— 详见 `unit_factory.gd#health_bar_texture`。
func _build_health_bar() -> void:
	_bar = Sprite3D.new()
	_bar.name = "HealthBar"
	_bar.texture = UnitFactory.health_bar_texture(1.0, GameConfig.team_color(team))
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.pixel_size = BAR_PIXEL_SIZE
	_bar.no_depth_test = true     ## `05_ui_hud.md#6` 的可读性要求：永远画在模型之上
	_bar.render_priority = BAR_RENDER_PRIORITY
	_bar.position = Vector3(0.0, _bar_anchor_height(), 0.0)
	## 起点就是**隐藏**：`visible` 只在 `_process` 里按血量刷新，若这里不置 false，
	## 满血单位在"`_ready` 之后、第一次 `_process` 之前"会闪一帧满血条。
	_bar.visible = false
	add_child(_bar)

## 腐化条（2026-09-25 第二轮）：**与血条同一套做法**（同一张"底槽 + 填充"贴图、同一个
## `UnitFactory.health_bar_texture()`），只有三处不同：
##   · 颜色是固定的**紫色**（表现参数 `CORRUPT_BAR_COLOR`）—— 它不该跟着队伍色走：
##     它表示的正是"你快要不是这一队的人了"；
##   · 挂在血条**上方** 0.18 m（战况一眼看两行：上面"策反进度"、下面"血量"）；
##   · 只在 `corrupt > 0` 时出现（满血那条的隐藏口径一样：没有就不占画面）。
## ⚠️ 宽度比例 = `corrupt / max_hp`：用户口径是"腐化值**大于剩余血量**就换边"，而剩余血量 ≤ 血上限
## ⇒ 取血上限当分母，这条就正好在**满格**位置对应"刚够把满血单位策反"。
func _build_corrupt_bar() -> void:
	_corrupt_bar = Sprite3D.new()
	_corrupt_bar.name = "CorruptBar"
	_corrupt_bar.texture = UnitFactory.health_bar_texture(1.0, CORRUPT_BAR_COLOR)
	_corrupt_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_corrupt_bar.pixel_size = BAR_PIXEL_SIZE
	_corrupt_bar.no_depth_test = true
	_corrupt_bar.render_priority = BAR_RENDER_PRIORITY
	_corrupt_bar.position = Vector3(0.0, _bar_anchor_height() + CORRUPT_BAR_LIFT, 0.0)
	_corrupt_bar.visible = false
	add_child(_corrupt_bar)

## 护盾条的常量（2026-09-27 第十二轮，「魔法护盾」科技）：青白 —— 与腐化条的紫、血条的队伍色都分得开。
## ⚠️ 挂在血条**下方** 0.18 m（血条上方那 0.18 m 已经是腐化条的地盘）。
const SHIELD_BAR_COLOR := Color(0.45, 0.95, 1.0)
const SHIELD_BAR_LIFT := -0.28

## 护盾条（「魔法护盾」科技）：与腐化条、血条**同一套做法**（同一张贴图 / 同一个 `pixel_size`），
## 只有三处不同：颜色固定青白、挂在血条**下方**、只在"有护盾上限"的单位身上建（懒建）。
## ⚠️ 分母取 `tech_shield_max()`（= 激活那一刻的最大生命值）⇒ 满格 = 满盾。
func _build_shield_bar() -> void:
	_shield_bar = Sprite3D.new()
	_shield_bar.name = "ShieldBar"
	_shield_bar.texture = UnitFactory.shield_bar_texture(1.0)
	_shield_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shield_bar.pixel_size = BAR_PIXEL_SIZE
	_shield_bar.no_depth_test = true
	_shield_bar.render_priority = BAR_RENDER_PRIORITY
	_shield_bar.position = Vector3(0.0, _bar_anchor_height() + SHIELD_BAR_LIFT, 0.0)
	_shield_bar.visible = false
	add_child(_shield_bar)

# ---------------------------------------------------------------- 外部接口
## ---- 肉鸽兵种科技（2026-09-27 第十二轮）----
## 一支队伍（玩家那一方）买下的科技由 `Roguelike` 持有，并在两个时机**推进单位**：
##   ① 单位出生时（新买的"队"立刻带上）；② 买下某条科技时（**场上所有同兵种立即生效** —— 用户口径）。
## ⇒ 单位这边只存一份**扁平字典**（`tech_id → 定义`），所有修正都从它算，不缓存派生值。
## ⚠️ 竞猜模式与没点科技的沙盒兵：这份字典为空 ⇒ 全部修正退化成 1.0 / 0.0。
## 沙盒可以在摆下去的时候带上选中的几条（`Sandbox._apply_place_techs()`），跟肉鸽不是同一份账。
## 用户口径原文在项目根的 `肉鸽兵种科技.txt`；数值与文案的唯一出处是 `GameConfig.ROGUELIKE_TECH_TABLE`（I-15）。
var _tech: Dictionary = {}
## 魔法护盾的剩余护盾值（> 0 时伤害先扣它、且**打不穿** ⇒ 单次伤害不会溢出到生命）。
var _shield_hp: float = 0.0
## 护盾条（只有吃到「魔法护盾」的单位才建，懒建）—— 与腐化条同一套做法，挂在血条上方、青白色。
var _shield_bar: Sprite3D = null
var _shield_fill_px: int = -1

## 由 `Roguelike` 调用：把"我这一队已激活的科技"整份推过来（幂等；空字典 = 没有科技）。
## ⚠️ 会**顺手把护盾补满**（「魔法护盾」口径是"获得等同于最大生命值的护盾"）—— 所以它也是
## "买了护盾科技之后立刻生效"的落点。
func set_techs(active: Dictionary) -> void:
	_tech = active.duplicate()
	## ⚠️ **先重算血上限**（2026-09-27 第十二轮补丁，用户报的 bug："点了防御模式和防御升级选中兵种后
	## 血量并没有变"）：`tech_hp_mult()` 只在 `_apply_hp_total()` 里被读到，而那一支原先只在
	## "升级 / 加血池"时跑 ⇒ 买下科技后 `hp_mult` 变了、`max_hp` 却一动不动。
	## ⚠️ **顺序也重要**：血先涨、盾再按**新的**血上限补满（「魔法护盾」= 等于最大生命值）。
	_apply_hp_total()
	_shield_hp = tech_shield_max()
	_refresh_shield_bar()
	_apply_spartan_look()
	refresh_ward()
	var deflect := tech_def("deflect_up")
	if not deflect.is_empty():
		_deflect_charges_left = maxi(_deflect_charges_left, int(deflect.get("charges", 20)))
	_update_beam_fx()

func has_tech(tech_id: String) -> bool:
	if is_silenced():
		return false
	return _tech.has(tech_id)

## 死后还认不认这条科技。`has_tech()` 在 `alive = false` 之后不再看见沉默，弃马要在报丧时问。
func keeps_tech(tech_id: String) -> bool:
	if Time.get_ticks_msec() < _silence_until_ms:
		return false
	return _tech.has(tech_id)

## 弃马后那名长矛兵的科技：先抄这名轻骑兵身上的全部，再盖上本局已经激活的长矛科技。
func dismount_loadout(spear_rows: Dictionary) -> Dictionary:
	var merged := {}
	for tech_id in _tech.keys():
		merged[String(tech_id)] = _tech[tech_id]
	for tech_id in spear_rows.keys():
		merged[String(tech_id)] = spear_rows[tech_id]
	return merged

## 身上已有的科技 id（沙盒查看面板用）。空 = 没有科技。
func tech_ids() -> Array:
	var out: Array = []
	for tech_id in _tech.keys():
		out.append(String(tech_id))
	return out

func tech_def(tech_id: String) -> Dictionary:
	if is_silenced():
		return {}
	return _tech.get(tech_id, {})

## 护甲（「护甲升级」）：**每次受伤减少 `15 × 兵种等级` 点**（用户 2026-09-27 选定）。
func tech_armor() -> float:
	var def := tech_def("armor_up")
	if def.is_empty():
		return 0.0
	return float(def.get("armor_per_level", 0.0)) * float(level)

## 生命倍率（「护甲升级」+30% / 「防御模式」+80% / 「精英猎手」每级 +7%）。
## ⚠️ 按项目的乘区规则：**这三个百分比先进一个池子相加**，再作为一个独立乘区乘上去。
func tech_hp_mult() -> float:
	var pct := 0.0
	for tech_id in ["armor_up", "defense_mode", "bulwark", "rage"]:
		var row := tech_def(tech_id)
		if row.is_empty() or not row.has("hp_mult"):
			continue
		pct += float(row["hp_mult"]) - 1.0
	var elite := tech_def("elite_hunter")
	if not elite.is_empty():
		pct += float(elite.get("hp_per_level", 0.0)) * float(level)
	## ⚠️ 剑圣的 3 倍生命是**另一个独立乘区**（"拥有 3 倍生命" ⇒ 在其它加成之后再 ×3），
	## 不是往上面那个百分比池子里加 +200% —— 这一点与"百分比同池相加"的规则不冲突：
	## 池子里装的是**百分比加成**，而"3 倍"是**倍率**。
	var mult := 1.0 + pct
	var assault := tech_def("assault")
	if not assault.is_empty() and assault.has("hp_mult"):
		mult *= float(assault["hp_mult"])
	## 「自我修复」的生命是倍率（×1.60），不进上面的百分比池。
	var mend := tech_def("mend")
	if not mend.is_empty() and mend.has("hp_mult"):
		mult *= float(mend["hp_mult"])
	if _saint and not is_silenced():
		var saint := GameConfig.roguelike_tech_def(type_id, "sword_saint")
		if not saint.is_empty():
			return mult * float(saint.get("hp_mult", 1.0))
	return mult

## 攻击间隔倍率（「狂暴」×0.5 = 攻速翻倍）。
func tech_interval_mult() -> float:
	var mult := 1.0
	for tech_id in ["rage", "rapid_throw", "rapid_shot"]:
		var row := tech_def(tech_id)
		if row.is_empty() or not row.has("interval_mult"):
			continue
		mult *= float(row["interval_mult"])
	return mult

## 移速增量 m/s（「防御模式」−2 / 「狂暴」+2；两者若同时有，按加法叠加）。
func tech_move_speed_delta() -> float:
	var delta := 0.0
	for tech_id in ["defense_mode", "rage", "assault", "horse_speed"]:
		var def := tech_def(tech_id)
		if not def.is_empty():
			delta += float(def.get("move_speed_delta", 0.0))
	return delta

## 射程增量 m（「射程增加」+10 / 「精英猎手」每级 +floor(1.5 × 等级)）。
## ⚠️ 「向下取整」的口径由用户当场给定（2026-09-27）：**按原数值算完再对结果取整**
## ⇒ L1/L2/L3/L4 = **+1 / +3 / +4 / +6 m**（1.5 / 3.0 / 4.5 / 6.0 各自 floor）。
func tech_range_bonus() -> float:
	var bonus := 0.0
	for tech_id in ["range_up", "rapid_throw", "siege_mode", "assault", "multi_beam", "energy_scatter", "ambush"]:
		var row := tech_def(tech_id)
		if row.is_empty() or not row.has("range_bonus"):
			continue
		bonus += float(row["range_bonus"])
	var elite := tech_def("elite_hunter")
	if not elite.is_empty():
		bonus += floorf(float(elite.get("range_per_level", 0.0)) * float(level))
	return bonus

## 伤害倍率（「精英猎手」每级 +7%）。⚠️ 只在**这个单位自己出手**时乘（近战走 `_outgoing_damage()`、
## 远程走 `Arrow` 里那一处），与"攻击方的等级倍率"是两个独立乘区。
## 「快速射击」的伤害减少进**同一个百分比池**（−50% 与精英猎手相加），击退仍是单独的 ×0.5。
func tech_damage_mult() -> float:
	var pct := 0.0
	var def := tech_def("elite_hunter")
	if not def.is_empty():
		pct += float(def.get("damage_per_level", 0.0)) * float(level)
	var rapid := tech_def("rapid_shot")
	if not rapid.is_empty():
		pct -= float(rapid.get("damage_reduction", 0.0))
	var amp := tech_def("damage_amp")
	if not amp.is_empty():
		pct += float(amp.get("damage_pct", 0.0))
	var mult := maxf(1.0 + pct, 0.0)
	for tech_id in ["rage", "destroyer", "explosive_arrow"]:
		var row := tech_def(tech_id)
		if row.is_empty() or not row.has("damage_mult"):
			continue
		mult *= float(row["damage_mult"])
	## 剑圣的 2.5 倍攻击（独立乘区，理由同 `tech_hp_mult()`）。
	if _saint and not is_silenced():
		var saint := GameConfig.roguelike_tech_def(type_id, "sword_saint")
		if not saint.is_empty():
			mult *= float(saint.get("damage_mult", 1.0))
	return mult

## 攻击的**额外击退数值**（「防御模式」+2）。
## 自爆伤害倍率（「伤害增幅」）。普通攻击的 ×3 不进这里。
func tech_blast_mult() -> float:
	var row := tech_def("damage_amp")
	if row.is_empty():
		return 1.0
	if row.has("damage_pct"):
		return 1.0 + float(row["damage_pct"])
	return float(row.get("damage_mult", 1.0))

## 最远跳跃距离倍率（狂战士「狂暴」）。没有这个字段的狂暴 = ×1。
func tech_jump_mult() -> float:
	var row := tech_def("rage")
	if row.is_empty() or not row.has("jump_mult"):
		return 1.0
	return float(row["jump_mult"])

func tech_kb_bonus() -> float:
	var bonus := 0.0
	for tech_id in ["defense_mode", "gale"]:
		var def := tech_def(tech_id)
		if not def.is_empty():
			bonus += float(def.get("kb_bonus", 0.0))
	return bonus

## 击退倍率（弩车「快速射击」×0.5）。没有就 ×1。
func tech_kb_mult() -> float:
	var row := tech_def("rapid_shot")
	if row.is_empty() or not row.has("kb_mult"):
		return 1.0
	return float(row["kb_mult"])

## 护盾上限（「魔法护盾」= 一层"等于最大生命值"的护盾；没有该科技就是 0）。
func tech_shield_max() -> float:
	var def := tech_def("magic_shield")
	if def.is_empty():
		return 0.0
	return max_hp * float(def.get("shield_hp_mult", 1.0))

## 「庇护」：跟着自己走的魔法盾。血 = 表上的盾血 × 等级，半径在科技行上。
func refresh_ward() -> void:
	var row: Dictionary = _tech.get("shelter", {})
	_ward_hp = 0.0 if row.is_empty() else float(row.get("shield_hp", 0.0)) * level_mult()
	_update_ward_ring()

func has_ward() -> bool:
	return has_tech("shelter") and _ward_hp > 0.0

func ward_radius() -> float:
	var row := tech_def("shelter")
	if row.is_empty():
		return 0.0
	return float(row.get("radius", 0.0))

## 这一发打在盾上。返回 true = 这笔记到我头上了，玩法侧不用再拿去扣道具盾。
func take_ward_damage(amount: float) -> bool:
	if _ward_hp <= 0.0:
		return false
	_ward_hp = maxf(_ward_hp - amount, 0.0)
	_update_ward_ring()
	return true

# ---------------------------------------------------------------- 第二批科技（2026-09-27 第十二轮·续）
## ---- ① 点燃（「火焰附加」剑盾 8%/s、「火矢」短弓 6%/s）----
## 用户口径（`肉鸽兵种科技.txt`）："攻击能点燃敌方，令其每秒损失最大生命值 8% 的生命值，持续 5 秒"。
## 两条共享一套状态（当场问答定的两个口径）：
##   · **只刷新、取最高**：同一目标身上只有一个点燃；再点火刷新持续时间，百分比取较高的那条；
##   · **不吃护甲**：跳伤按"最大生命 × 百分比"原额结算（否则 15×等级的护甲会把 6~8% 的小额跳伤减到 0）。
## ⚠️ 跳伤走 `apply_hit(..., skip_armor = true)` ⇒ 仍然吃无敌闸门 / 影袭 / 护盾 / 归因（击杀者 = 点火的人）。
var _burn_until_ms: int = 0              ## 点燃到期时刻（绝对 ms，I-13 ⇒ 自动进 `shift_deadlines()`）
var _burn_next_tick_ms: int = 0          ## 下一跳的时刻（绝对 ms）
var _burn_ratio: float = 0.0             ## 每秒损失最大生命的比例（同一时刻只有一个，取最高）
var _burn_from: Unit3D = null            ## 点火的人（击杀归因 / 经验）

## 点火（幂等；`ratio` 更低时只刷新时间、不改百分比 —— 见上面那条"取最高"）。
func ignite(ratio: float, duration_ms: int, from: Unit3D) -> void:
	if not alive or ratio <= 0.0 or duration_ms <= 0 or has_flame_barrier():
		return
	var now := Time.get_ticks_msec()
	_burn_ratio = maxf(_burn_ratio, ratio)
	_burn_until_ms = maxi(_burn_until_ms, now + duration_ms)
	if _burn_next_tick_ms <= 0:
		_burn_next_tick_ms = now + GameConfig.ROGUELIKE_BURN_TICK_MS
	_burn_from = from
	is_burning()                        ## 只读查询，这里调一次是让"点燃"在探针里立刻可见

func is_burning() -> bool:
	return alive and _burn_ratio > 0.0 and Time.get_ticks_msec() < _burn_until_ms

## 挨打时的点火判定：**由打我的那个人的科技决定**（近战 / 箭矢 / 溅射全都经过 `apply_hit()`）。
##   · 「火焰附加」= 剑盾兵的近战（8%/s）；
##   · 「火矢」= 短弓手的远程（6%/s）。
## ⚠️ 两个科技分属不同兵种 ⇒ 不会同时存在，取到哪个用哪个（表里各自带自己的百分比）。
func _ignite_from_attacker(from: Unit3D) -> void:
	if from == null or not is_instance_valid(from):
		return
	for tech_id in ["fire_blade", "fire_arrow"]:
		if not from.has_tech(tech_id):
			continue
		var def := from.tech_def(tech_id)
		ignite(float(def.get("burn_ratio_per_sec", 0.0)), int(def.get("burn_ms", 0)), from)
		return

## 每物理帧推一次点燃：到点扣一跳、到期清状态。
func _tick_burn() -> void:
	if _burn_ratio <= 0.0 or has_flame_barrier():
		return
	var now := Time.get_ticks_msec()
	if now >= _burn_until_ms:
		_burn_ratio = 0.0
		_burn_next_tick_ms = 0
		_burn_from = null
		return
	if now < _burn_next_tick_ms:
		return
	_burn_next_tick_ms += GameConfig.ROGUELIKE_BURN_TICK_MS
	## ⚠️ 用 `+=` 而不是 `= now + 节拍`：与出手节拍同一条理由（不让每帧抖动累加进相位）。
	## ⚠️ `skip_armor = true`：点燃不吃护甲（用户 2026-09-27 选定）。
	## 点火的人可能已经收掉或阵亡被释放。typed 参数不接受已释放的对象，归因改成无来源。
	if not is_instance_valid(_burn_from):
		_burn_from = null
	apply_hit(max_hp * _burn_ratio, _burn_from, Vector3.ZERO, 0.0, true)

var _silence_until_ms: int = 0
var _silence_move_mult: float = 0.7
var _silence_shield: float = 0.0
## 本场战斗里到过的最大生命（火焰拳「能量爆发」的伤害）。0 = 这场还没记。
var _peak_max_hp: float = 0.0
## 火焰屏障：截止时刻，以及屏障期间受到的攻击伤害倍率。
var _barrier_until_ms: int = 0
var _barrier_taken_mult: float = 1.0
var _barrier_cast: bool = false
## 生存模式援助写在这只单位身上的乘区。空字典 = 没有援助。
var aid_mods: Dictionary = {}
var aid_attack_count: int = 0
var aid_blast_used: bool = false
var aid_summon_next_ms: int = 0
var aid_summon_skirmish_ms: int = 0
## 影魔「复仇」：50% 和 0% 各一次。
var _revenge_half_used: bool = false
var _revenge_zero_used: bool = false
## 影魔「自我复制」已经攒下的击杀权重。凑满一档就生一个，生完扣掉这一档。
var _replicate_bank: int = 0
var _barrier_shell: MeshInstance3D = null
## 母虫 / 影分身改生命和伤害用的独立倍率。普通单位是 1。
var _hp_scale: float = 1.0
var _damage_scale: float = 1.0
## 暗影守护：影袭之后这一小段里受到的伤害 ×0.5。
var _guard_until_ms: int = 0
## 沙暴：钻出那一帧记下圆心和截止时刻。
var _storm_until_ms: int = 0
var _storm_at: Vector3 = Vector3.ZERO
var _storm_disc: MeshInstance3D = null
var _sidestep_until_ms: int = 0
var _riposte_until_ms: int = 0
var _summon_next_ms: int = 0
## 上一场已经对过的开战时刻。换一场就清掉召唤节拍，开战那一帧重新召。
var _summon_skirmish_ms: int = 0
var _summon_until_ms: int = 0
var _burrow_mend_next_ms: int = 0

func is_silenced() -> bool:
	return alive and Time.get_ticks_msec() < _silence_until_ms

## 科技暂时失效，移速按倍率下降。再次命中只刷新时间。
func apply_silence(duration_ms: int, move_mult: float) -> void:
	if not alive or duration_ms <= 0 or _barrier_damage_mult() < 1.0:
		return
	if bool(aid_mods.get("block_silence", false)):
		return
	var was := is_silenced()
	var now := Time.get_ticks_msec()
	_silence_until_ms = maxi(_silence_until_ms, now + duration_ms)
	_silence_move_mult = move_mult
	if was:
		return
	_silence_shield = _shield_hp
	_shield_hp = 0.0
	_apply_hp_total()
	_refresh_shield_bar()
	_apply_spartan_look()

func _tick_silence() -> void:
	if _silence_until_ms <= 0:
		return
	if Time.get_ticks_msec() < _silence_until_ms:
		return
	_silence_until_ms = 0
	_shield_hp = _silence_shield
	_apply_hp_total()
	_refresh_shield_bar()
	_apply_spartan_look()

## ---- ② 剑圣（「剑圣」剑盾兵）----
## 用户口径："每一队剑盾兵都会有一位剑圣，拥有 3 倍生命、2.5 倍攻击和两倍攻击范围，
## 攻击时（攻击动画为类似于'旋风斩'）对范围内所有敌方单位造成伤害，免疫击退"。
## ⚠️ "哪一个是剑圣"由**玩法侧**决定（`Roguelike` 把每队 `squad_slot == 0` 那个标上）——
## 单位自己只知道"我是不是"，这对"队伍重建后仍是同一个槽位"很关键（复活补位不会换人当剑圣）。
var _saint: bool = false
## 剑圣那一圈可见刀光（`UnitFactory` 给**每个剑盾兵**都建好、出厂即隐藏 —— 见工厂里 `SlashRing` 的说明）。
var _saint_ring: MeshInstance3D = null
var _fire_edge: Node3D = null
var _bulwark_ring: MeshInstance3D = null
var _ember_aura: MeshInstance3D = null
var _iai_charge: MeshInstance3D = null
var _iai_dash: MeshInstance3D = null
var _iai_slash: MeshInstance3D = null
var _iai_slash_until_ms: int = 0

func set_saint(on: bool) -> void:
	if _saint == on:
		return
	_saint = on
	_apply_saint_look()
	_apply_hp_total()                   ## 3 倍生命是乘区 ⇒ 改完必须重算血上限（同 `set_techs()` 那条教训）
	_refresh_shield_bar()

## 剑圣外形：披风 / 金环 / 盔顶金穗，以及换成更长的金刃。
## 这些件在 `UnitFactory` 里给每个剑盾兵都建好、出厂隐藏（与 `SlashRing` 同一条理由：买科技时现造会卡顿）。
func _apply_saint_look() -> void:
	if _visual == null:
		return
	var kit := _visual.get_node_or_null("SaintKit") as Node3D
	if kit != null:
		kit.visible = _saint
	if _weapon == null:
		return
	var short_blade := _weapon.get_node_or_null("Blade") as MeshInstance3D
	var saint_blade := _weapon.get_node_or_null("SaintBlade") as MeshInstance3D
	if short_blade != null and saint_blade != null:
		short_blade.visible = not _saint
		saint_blade.visible = _saint
	var guard := _weapon.get_node_or_null("SaintGuard") as MeshInstance3D
	if guard != null:
		guard.visible = _saint

func is_saint() -> bool:
	return _saint

## 剑圣的旋转动画 + 那一圈可见刀光（`SlashRing`，2026-09-27 第十二轮·第二批；用户当场选定"加一圈可见刀光"）。
## 旋转窗口 = **这一刀的起手到命中帧**（0 → `windup`），命中帧转到 **180°**（刀刃正好扫过全场一圈的后半）。
## ⚠️ 非剑圣 / 不在出手窗口里：`rotation.y` 与刀光的可见性都**显式归零**（不留残留）。
func _update_saint_spin() -> void:
	if _saint_ring != null:
		if not _saint:
			_saint_ring.visible = false
		else:
			var iv := maxf(_attack_interval(), 0.001)
			var wu := iv * GameConfig.windup_ratio(type_id)
			_saint_ring.visible = _state == State.ATTACK and _striking and _attack_timer <= wu
	if not _saint:
		return
	var interval_s := maxf(_attack_interval(), 0.001)
	var windup_s := interval_s * GameConfig.windup_ratio(type_id)
	if _state == State.ATTACK and _striking and windup_s > 0.0:
		_visual.rotation.y = PI * clampf(_attack_timer / windup_s, 0.0, 1.0)
	else:
		_visual.rotation.y = 0.0

## 剑圣的攻击半径（"两倍攻击范围" ⇒ 2 × 面板射程，**含接触宽容**：它本来就是近战）。
## ⚠️ 只给剑圣用：普通单位的范围伤害各有各的来源（扇形 / 炎爆）。
func saint_spin_radius() -> float:
	return attack_reach()

## ---- ③ Spartan（「this is Spartan！」长矛兵）----
## 用户口径："所有矛兵获得能够抵挡小型投射物的盾（不能抵挡子弹），同时**第一下攻击变为射程为 16 m 的投矛**，
## 造成 1.5 倍伤害"；当场问答补充："**无条件第一下必投**（哪怕贴脸）"+"**造弹体**"。
## ⇒ 实现：`_spartan_thrown` 一行状态；`attack_reach()` 在"这一回合还没投过"时放宽到 16 m（这样 AI 会走到 16 m 就停、
## 投出去之后自动回落到普通射程继续近战）；回合开始 `reset_to()` 把这一格清掉。`_resolve_attack()` 里那一支负责生成弹体。
var _spartan_thrown: bool = false
## 投矛之后这一小段不能自己走。绝对毫秒，暂停会后移。
var _move_lock_until_ms: int = 0
## 余烬：致命伤害后还能打一会儿（`_ember_until_ms` 以 `_ms` 结尾，暂停会把它往后推）。
var _ember_until_ms: int = 0
var _ember_used: bool = false
## 神圣打击冷却、自我修复节拍、毁灭者自残节拍。都是绝对毫秒。
var _holy_until_ms: int = 0
var _mend_next_ms: int = 0
var _destroyer_next_ms: int = 0

func spartan_can_throw() -> bool:
	return has_tech("spartan") and not _spartan_thrown

## 这次出手是不是"投矛"（贴脸也投 —— 用户当场选定"无条件第一下必投"）。
func _spartan_throwing() -> bool:
	if not spartan_can_throw():
		return false
	return _target_valid() and surface_distance_to(target) <= attack_reach()

## ---- ④ 高级格挡（「高级格挡」剑盾兵）----
## 用户口径："允许剑盾兵**在攻击时**格挡小型远程投射物，**也能格挡子弹**"。
## ⚠️ 本作的盾牌原本有两条闸门：**出手时不挡**（`has_shield()` 那一支要在 `Arrow` 里判"没在出手"）、
## 以及**子弹穿盾**（`Arrow.ignores_shield`）。这条科技把**两条一起掀掉**，但**只对剑盾兵、只对它自己生效**。
## 判定统一收在这一处：`Arrow` 只问 `can_block_projectile(arrow)`，不在弹体那一侧散着猜兵种。
func can_block_projectile(is_small: bool, ignores_shield: bool, kind: String = "") -> bool:
	if kind == "spear":
		return has_tech("block_ranged")  ## 投矛：只有「高级格挡」挡得住
	if has_tech("block_ranged"):
		return is_small                  ## 高级格挡：小型投射物 **含子弹**；大型（弩箭 / 石弹）仍然挡不了
	if has_tech("spartan"):
		return is_small and not ignores_shield   ## 月牙盾：小型但**挡不了子弹**；出手窗口在 `is_guard_up()`
	if has_shield():
		return is_small and not ignores_shield   ## 普通盾：小型、子弹穿盾；扇形与出手窗口在 `blocks_from()`
	return false

func shield_hp() -> float:
	return _shield_hp

## 把护盾条按当前剩余护盾重画（只有吃到了「魔法护盾」的单位才有这条）。
## ⚠️ 与腐化条同例：条只在"有护盾上限"时存在，且**护盾满了不显示**（口径与血条一致：满 = 不显示）。
func _refresh_shield_bar() -> void:
	if tech_shield_max() <= 0.0:
		if _shield_bar != null:
			_shield_bar.visible = false
		return
	if _shield_bar == null:
		_build_shield_bar()
	var ratio := clampf(_shield_hp / maxf(tech_shield_max(), 0.001), 0.0, 1.0)
	var fill_px := int(round(ratio * float(UnitFactory.HEALTH_BAR_INNER_PX)))
	if fill_px != _shield_fill_px:
		_shield_fill_px = fill_px
		_shield_bar.texture = UnitFactory.shield_bar_texture(ratio)
	_shield_bar.visible = alive and _shield_hp > 0.5 and not is_burrowed() and not _lod_far

## 壁垒连上别人时，脚下那一圈才亮。线由场地画。
func set_bulwark_mark(on: bool) -> void:
	if _bulwark_ring != null:
		_bulwark_ring.visible = on and alive

func _update_skill_fx() -> void:
	if _fire_edge != null:
		_fire_edge.visible = alive and has_tech("fire_blade")
	if _ember_aura != null:
		var ember_on := is_ember()
		_ember_aura.visible = ember_on
		if ember_on:
			var pulse := 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.018)
			_ember_aura.scale = Vector3.ONE * pulse
	if _iai_charge == null:
		return
	var now := Time.get_ticks_msec()
	_iai_charge.visible = _iai_phase == Iai.CHARGE
	_iai_dash.visible = _iai_phase == Iai.DASH
	_iai_slash.visible = now < _iai_slash_until_ms
	if _iai_phase == Iai.CHARGE:
		var span := float(maxi(GameConfig.UNIT_MASTER_IAI_CHARGE_MS, 1))
		var t := 1.0 - float(maxi(_iai_until_ms - now, 0)) / span
		var grown := lerpf(0.45, 1.85, clampf(t, 0.0, 1.0))
		_iai_charge.scale = Vector3(grown, 1.0, grown)

func current_speed() -> float:
	var base := GameConfig.move_speed(type_id)
	var speed := base * GameConfig.CIRCLE_HIT_MULT if excited else base
	## 肉鸽兵种科技：移速增量（「防御模式」−2 / 「狂暴」+2）。⚠️ 没有科技时 +0.0 ⇒ 逐位不变。
	speed += tech_move_speed_delta()
	speed += float(aid_mods.get("speed_add", 0.0))
	## 肉鸽第三块：**队伍级修正**（左方指挥所的"移速 +1 m/s" × 指挥所被打掉后的 −90%）。
	## ⚠️ 别的模式里场地那两个数恒为 0 / 1.0 ⇒ 结果与改动前**逐位相同**。
	var arena_node := _arena()
	if arena_node != null:
		speed = arena_node.speed_for(team, speed)
		speed = _aid_undo_post_debuff(speed)
	## 肉鸽第五块：**陷阱的减速**（−80%）—— 最后乘一次。⚠️ 别的模式里 `_slow_until_ms` 恒为 0
	## ⇒ 结果与改动前**逐位相同**。
	## 移速百分数进同一个池：陷阱、沉默、沙暴相加，再作为一份倍率。
	return speed * maxf(1.0 + move_pct(), 0.0) * _aid_zone_speed_mult()

## 上一帧真正走出的水平位移。堵住时 `velocity` 仍指着敌人，但人没动，不能拿那个数去预判。
var _aim_step_ready: bool = false
var _aim_prev: Vector3 = Vector3.ZERO
var _aim_flat: Vector3 = Vector3.ZERO
var _aim_delta: float = 0.0167

func _remember_motion(delta: float) -> void:
	if not _aim_step_ready:
		_aim_prev = global_position
		_aim_step_ready = true
		_aim_flat = Vector3.ZERO
		return
	var step := global_position - _aim_prev
	_aim_prev = global_position
	_aim_delta = maxf(delta, 0.001)
	_aim_flat = Vector3(step.x, 0.0, step.z)

## 给投射物提前量用的速度。站着砍人、被挤开、收招时的滑动都不算在走，
## 否则投石车互打会按挤开的速度把石头瞄到两人中间。
## 用的是上一帧的实际位移，不是这一帧打算走的 `velocity`：被队友堵住时后者仍是满速。
func aim_velocity() -> Vector3:
	if _state != State.MOVE or not _aim_step_ready:
		return Vector3.ZERO
	var flat := _aim_flat / _aim_delta
	var cap := current_speed()
	if cap <= 0.0 or flat.length_squared() <= 0.0001:
		return Vector3.ZERO
	if flat.length() > cap:
		flat = flat.normalized() * cap
	return flat

## 移速百分数（相互加算）。陷阱的 −80%、沉默的 −30%、沙暴的 −40% 都在这里。
func move_pct() -> float:
	var pct := 0.0
	if is_slowed():
		pct -= 1.0 - _slow_mult
	if is_silenced():
		pct -= 1.0 - _silence_move_mult
	pct += _storm_move_pct()
	return pct

## 现在的减速倍率（没被减速 = 1.0）。`current_speed()` 与探针共用同一个口。
func slow_factor() -> float:
	return _slow_mult if Time.get_ticks_msec() < _slow_until_ms else 1.0

## 是否正被减速（布尔量读起来像断言，见 `08_naming.md#3.3`）。阵亡后一律为假。
func is_slowed() -> bool:
	return alive and Time.get_ticks_msec() < _slow_until_ms

func set_excited(value: bool) -> void:
	if excited == value:
		return
	excited = value
	## 进出圈都重新起算"下一层"：进圈后第 1 层在 1 秒后落，不会立刻白吃一下
	_stack_due = Time.get_ticks_msec()
	if not excited:
		stack_count = 0

## 投石车的抛臂摆幅（rad，2026-09-24）：用户要"扔之前大幅摆动、扔出后逐渐复位"，
## 所以取一个远大于通用远程（0.35）的角度——前摇期间整条抛臂大幅抬起，投出后按 `recover` 平滑落回。
const SIEGE_THROW_ANGLE := 1.81
## 投石车摆臂/复位的**时间轴倍数**（2026-09-24 用户："攻击前的摆动速度 ×4、复原速度 ×3"）：
## 前摇段时长 ÷4、收招段时长 ÷3（曲线形状不变，只是跑得更快）。
const SIEGE_WINDUP_SPEEDUP := 4.0
const SIEGE_RECOVER_SPEEDUP := 3.0

## 弩车"上弦"的六个**纯表现**参数（2026-09-19 用户："攻击前把弦像拉弓一样往后、弓臂也略微往后，
## 攻击的一瞬间在极短时间内按原动画的反动画迅速回位"；同日第二轮："怎么是向上仰而不是向下"、
## "弦心后退程度变为原来的 2 倍"）。
## ⚠️ 出手节奏一概不动：前摇 / 间隔 / 伤害 / 弩箭速度仍只由 `GameConfig.PROFILES["ballista"]` 决定
## （见 `04_physics.md#3.5`）。这里只决定"弦与弓臂怎么动"。
const BALLISTA_LIMB_FLEX_ANGLE := 0.14   ## 弓臂绕弓臂根**向后**让开（绕 Y，rad ≈ 8°）
const BALLISTA_LIMB_DIP_ANGLE := 0.22    ## 弓臂绕弓臂根**向下**弯（绕 Z，rad ≈ 12.6°）⇒ 臂梢下沉 ≈0.50 m
const BALLISTA_DRAW_DISTANCE := 1.00     ## 弦心后退距离（`BowAssembly` 局部；世界 = ×`VEHICLE_SCALE` = 2 m）
const BALLISTA_DRAW_DROP := 0.10         ## 弦心后退时**同时**下沉的距离（局部）⇒ 世界 0.20 m，落到箭槽上方
const BALLISTA_RELEASE_TIME := 0.04      ## 出手后**倒放**前摇、弹回静止所用的时间（秒；2026-09-19 用户："变为原来的三分之一"）
## 弓组件整体的俯仰角（rad）；**正角 = 后段（弦那一侧）向下压**。
## ⚠️ 两个坑都在这一个数上：
##   ① 符号与远程兵那条 `-swing * 0.35`（`04_physics.md#3.5` 的"远程小幅抬"）**相反**——
##      照抄负号会把弓的**后段抬起来**（弦心在转轴**后面**，转轴一"低头"弦就翘头，正是用户看到的上仰）。
##   ② 角度**不能放大**：弦心在转轴后面 ≈1.14（局部）、臂梢只在 ≈0.14，所以弦的下沉量是臂梢的 8 倍；
##      再叠上 `BALLISTA_DRAW_DROP`，超过 ≈0.13 rad 弦就会压到箭槽条上（本值 0.08 时弦底离槽顶还有
##      0.015 局部 ≈3 cm 世界）。臂梢"向下"主要靠 `BALLISTA_LIMB_DIP_ANGLE`，**不要**靠加大这个角。
const BALLISTA_TILT_ANGLE := 0.08

## 投石车：抛射石弹的攻城机械（`PROFILE.projectile == "stone"`）。
## 2026-09-24 独立出来的原因：它的出手动作与短弓手/弩车**方向相反**——短弓手是把弓往前压，
## 投石车要把抛臂**抬起来甩出去**（见 `_animate_attack`）。
func is_siege_thrower() -> bool:
	return String(GameConfig.profile(type_id).get("projectile", "")) == "stone"

## 弩车：射出的是**大型弩箭**（`PROFILE.projectile == "bolt"`）。
## 2026-09-19 独立出来的原因：它的出手动作是**上弦**——弓臂后仰 + 弦心一路后退，命中帧按反动画弹回
## （见 `_animate_attack` / `_apply_bow_draw`）。
## ⚠️ 弩车从此**不再走** `_animate_attack` 的 `is_ranged()` 支，所以那一支现在是**短弓手 / 长弓手共用**；
## 它是远程兵的共用通道，别为了弩车去改它（会一起改掉两种弓手的动作；`99_decisions.md` 2026-09-24 已记过）。
func is_bolt_shooter() -> bool:
	return String(GameConfig.profile(type_id).get("projectile", "")) == "bolt"

func is_ranged() -> bool:
	return bool(GameConfig.profile(type_id)["is_ranged"])

## 出手的有效距离上限。
## **近战**带命中宽容（`UNIT_CONTACT_RATIO`）：击退会把目标瞬间推出射程，
## 不留宽容就会出现"打到了却不掉血"（`03_rules.md#6.1`）。
## **远程**不带：射程就是射程，箭不该从 16 m 之外飞出去（这个是 2026-09-18 修掉的 bug）。
func attack_reach() -> float:
	var reach := float(GameConfig.profile(type_id)["range"])
	## 肉鸽兵种科技：射程增量（「射程增加」+10 m / 「精英猎手」每级 +floor(1.5 × 等级)）。
	## ⚠️ **加在宽容之前**、且**近战也吃**（用户这两条科技都点名了兵种：短弓手；但"射程 +N m"是
	## 面板射程的增量，近战若将来也有这类科技，加在这里语义才一致）。没有科技时 +0.0 ⇒ 逐位不变。
	reach += tech_range_bonus()
	## 剑圣："两倍攻击范围"（同样是**面板射程**的倍率，故摆在宽容之前）。
	if _saint and not is_silenced():
		var saint := GameConfig.roguelike_tech_def(type_id, "sword_saint")
		if not saint.is_empty():
			reach *= float(saint.get("range_mult", 1.0))
	## Spartan：**还没投出那一支标枪**时，把"出手距离"临时放宽到投矛射程 —— 这样 AI 会照常走位，
	## 但一进 16 m 就停下来投；投完这个放宽自动消失（`_spartan_thrown` 置位），它再走上去近战。
	reach = reach if is_ranged() else reach * GameConfig.UNIT_CONTACT_RATIO
	## 还没投矛时停在 16 m。放在接触宽容之后，免得停得比标枪飞得更远。
	if spartan_can_throw():
		var spartan := tech_def("spartan")
		reach = maxf(reach, float(spartan.get("throw_range", 0.0)))
	## 肉鸽第三块：左方指挥所的"射程 +4 m" —— ⚠️ **只给远程**（用户："我方所有**远程**单位射程增加4m"）。
	## 近战加了会变成"隔空砍人"，所以这里显式判一次；别的模式里那个加成恒为 0.0。
	if is_ranged():
		var arena_node := _arena()
		if arena_node != null:
			reach += arena_node.range_bonus_for(team)
	reach += float(aid_mods.get("range_add", 0.0))
	return maxf(reach - _aid_range_cut(), 0.0)

## 光束画到和出手同一个距离。停在面板射程外沿时，线要和伤害一起出现。
func beam_reach() -> float:
	return attack_reach()

## 攻城模式的内圈：这个距离以内不攻击。没有这条科技就是 0。
func attack_min_reach() -> float:
	var row := tech_def("siege_mode")
	if row.is_empty():
		return 0.0
	return float(row.get("min_range", 0.0))

## 远程瞄准点：人形仍瞄胸口（1.05 m）。盒体若胸口高度落在盒子外面，改瞄盒心。
## 湮灭之瞳的盒子底在 1.10 m 以上，直线弹瞄 1.05 会从肚子下面飞过去。
func shot_aim_point() -> Vector3:
	var height := 1.05
	var body_box: Dictionary = GameConfig.body_box(type_id)
	if not body_box.is_empty():
		var lift := float(body_box["lift"])
		var half_y := float((body_box["size"] as Vector3).y) * 0.5
		if height < lift - half_y or height > lift + half_y:
			height = lift
	return global_position + Vector3(0.0, height, 0.0)

func has_shield() -> bool:
	return bool(GameConfig.profile(type_id).get("has_shield", false))

## 是不是**心灵腐化师**（2026-09-25 第二轮）：判据是 PROFILE 的 `"corrupt"` 标记 ——
## ⚠️ 与高级偏折那条教训同一个道理（`try_deflect()` 的"是不是大师"闸门）：**别在调用点上猜兵种**，
## 让"我是什么"只有一处出处。
func is_corruptor() -> bool:
	return bool(GameConfig.profile(type_id).get("corrupt", false))

## 肉鸽指挥所。腐化师照到它时不叠腐化值，改走普通伤害。
func is_command_post() -> bool:
	return type_id == GameConfig.ROGUELIKE_POST_TYPE

## 是不是"**锁定后持续照射**"那一族（心灵腐化师 / 湮灭之瞳，2026-09-27 第十轮抽出）：
## 蓄力（0.5 s）→ 持续照射 → 目标死亡 / 出射程 ⇒ 丢锁、换人重新蓄力。判据在 `GameConfig` 里
##（`is_sustained_beam()`，与 `is_corruptor()` 同一种做法：**不在调用点猜兵种名**）。
func is_sustained_beam() -> bool:
	return GameConfig.is_sustained_beam(type_id)

## 是不是**湮灭之瞳**（2026-09-27 第十轮）：判据 = 它在持续照射那一族里、且不是腐化师
##（腐化师叠腐化值、它造成伤害并逐档升高，两条支路要在 `_resolve_attack()` 之后分开走）。
func is_doom_eye() -> bool:
	return is_sustained_beam() and not is_corruptor()

## 「能量汇集」当前档位（0 / 1 / 2 / 3）—— 见 `GameConfig.doom_stage()`
func focus_stage() -> int:
	if _focus_for != target:
		return 0
	return GameConfig.doom_stage(_focus_hits)

## 会不会**死亡自爆**（2026-09-25 第二轮，玉面手雷王）。
func is_self_destructor() -> bool:
	return bool(GameConfig.profile(type_id).get("self_destruct", false))

## 是不是**影魔**（2026-09-25 第三轮）：判据是它的技能名 —— 与 `is_corruptor()` 同一种做法
##（"我是什么"只有 PROFILE 一处出处，不在调用点上猜兵种）。
func is_shadow_demon() -> bool:
	return String(GameConfig.profile(type_id).get("skill", "")) == "shadow"

## 现在**在影子形态里**吗（= 影袭那一段无敌 + 不可被锁定的位移）。
## ⚠️ 公开：`apply_hit()` 的免疫闸门、`_find_target()` 的"不可被锁定"、以及 `_mcp_state()` 都读它。
func is_in_shadow_form() -> bool:
	return _shadow_until_ms > 0

## 攻击动作是不是"沿武器轴向前后突刺"（当前只有长矛兵）。
## 突刺动的是**位置**，挥砍动的是**旋转**，见 `_animate_attack`。
func is_thrusting() -> bool:
	return bool(GameConfig.profile(type_id).get("thrust", false))

## 到**目标表面**的距离（2026-09-19 用户报告"判定体变大导致有些攻击距离近的单位打不到"）。
##   = 中心距 − `max(0, 目标判定半径 − 自身判定半径)`（下限 0）
## ⚠️ 为什么需要它：三个巨物的判定体是盒体（半宽 1.3~2.9 m），而"打得到"与"进 ATTACK 就不再前进"
## 两处比的都是**中心距** ⇒ 近战被碰撞体挡在巨物表面时中心距 2.8~3.3 m > `attack_reach()`（≈2.07 m）
## ⇒ 永远进不了 ATTACK：既打不到、也只会顶着箱子推。
## ⚠️ 为什么减去的是**半径之差**而不是目标半径：两个**同尺寸**单位（人形之间、巨物之间）相减为 0
## ⇒ 中心距原样返回，**既有手感一个字节都不变**；只有"小个子打巨物"才真正按表面算。
func surface_distance_to(other: Unit3D) -> float:
	if other == null:
		return INF
	var extra := maxf(GameConfig.body_radius(other.type_id) - GameConfig.body_radius(type_id), 0.0)
	return maxf(global_position.distance_to(other.global_position) - extra, 0.0)

## 攻击动作是不是"扇面上下扇动"（当前只有扇子兵，2026-09-24）。
## 与挥砍的区别只在**旋转轴**：挥扇只绕水平轴（本体 X）上下扇，见 `_animate_attack`。
## 判定与它无关——扇子兵的命中仍走 `_resolve_cone_attack()` 的 ±45° 扇形。
func is_flapping() -> bool:
	return type_id == "fan"

## 这个兵种会不会潜地（= 技能是 `burrow`，当前只有沙虫，2026-09-19）。
## 出手动作据此改走"下颚前咬"那一支，见 `_animate_attack`。
func is_burrower() -> bool:
	return String(GameConfig.profile(type_id).get("skill", "")) == "burrow"

## 现在是不是"在地下"（含钻入 / 钻出的过渡段，`enum Burrow`）。
## 语义 = 用户口径的三件事：**无法被锁定**（`_find_target()` 跳过）、**无敌**（`is_invulnerable()`）、
## **免疫一切状态**（`_add_knockback()` / `can_receive_momentum()` 跳过；眩晕另有 boss 免疫）。
func is_burrowed() -> bool:
	return _burrow != Burrow.SURFACED

## 是否正被击退（`_kb` 还有速度）。⚠️ 2026-09-18 起它**不再等于"禁移"**：
## 是否禁止自主移动要看 `is_knockback_immobile()`（重量 vs 本次击退数值）。
## 位移怎么接管见 `_physics_process` 与 `_tick_move`。
func is_knocked_back() -> bool:
	return _kb.length_squared() > 0.01

## 自身重量（不变量 I-26 第七项，`04_physics.md#5`）：被击退的位移 = 击退数值 ÷ 它
func mass() -> float:
	return maxf(GameConfig.mass(type_id) + float(aid_mods.get("mass_add", 0.0)), 0.01)

## 2026-09-18（用户要求）：**自身重量 < 本次击退数值 ⇒ 击退期间禁止自主移动**；
## 否则击退只是叠加在自主移动上（被推着照常走位）。
## 现状：长矛兵击退数值 2 vs 三种兵重量 1 ⇒ 恒为真 ⇒ 行为与改之前一致。
func is_knockback_immobile() -> bool:
	return _kb_value > mass()

## 受一次击退冲量：冲量先在**这里**按自身重量缩小（距离 = 击退数值 ÷ 重量），
## 同时记下"本次击退数值"（= 冲量 ÷ 每单位初速）供 `is_knockback_immobile()` 判断。
## `apply_hit()` 与 `receive_knockback()` 两条路都走它，避免漏掉任何一处。
## `damage_on_transfer` > 0 时（只有弩车的击退），本次击退在撞人时**附带伤害**（`04_physics.md#5.1`）。
func _add_knockback(push: Vector3, damage_on_transfer: float = 0.0) -> void:
	## ⚠️ 2026-09-19：**潜地期间免疫一切状态**（用户口径）⇒ 击退也吃不上（含动量转移那条路）。
	if is_burrowed():
		return
	## ⚠️ **2026-09-25 定身**：**一切位移都吃不上**（用户口径："无法被位移（包括击退）"）——
	## 这是定身与眩晕的唯一区别。⚠️ 只挡**位移**：伤害在 `apply_hit()` 里另行结算，
	## 定身**不免疫伤害**（与眩晕一致）；`receive_knockback()`（动量转移）走的也是本函数 ✓。
	if is_rooted():
		return
	## ⚠️ **2026-09-27 第十二轮·第二批（「剑圣」科技）**：用户口径"**免疫击退**" ⇒ 剑圣这一格恒为 0。
	## ⚠️ 放在这里（而不是把重量改成 9999）：重量是**面板第七项数值**（I-26），改它等于改了兵种属性；
	## 而"剑圣免疫击退"是它的一条技能特权，与沙虫那种"重量无穷大"是两码事（那条本来就写在数值表里）。
	if _saint:
		return
	if push.length_squared() < 0.0001:
		return
	_kb += push / mass()
	_kb_value = maxf(_kb_value, push.length() / GameConfig.KNOCKBACK_SPEED)
	_kb_damage = maxf(_kb_damage, damage_on_transfer)

## 受到一次**外部击退**（不含伤害）：用于"被击退的单位撞到别人"时的动量转移。
## 刻意不算命中——不闪白、不发 `unit_was_hit`，避免被误读成"挨了一下"。
func receive_knockback(push: Vector3) -> void:
	_add_knockback(push)

# ---------------------------------------------------------------- 锚定（2026-09-26 新增：石柱推不动）
## 是不是**锚定**单位（判据在 `GameConfig.is_anchored()`，目前只有召唤石柱）。
func is_anchored() -> bool:
	return GameConfig.is_anchored(type_id)

## 锚点捕获：在**第一个物理帧的开头**记下当前位置。
## ⚠️ 为什么不在 `_ready()` 里记：`Arena.spawn_unit()` 的顺序是 `add_child()`（`_ready()` 在这里跑）
## **之后**才写 `global_position` ⇒ `_ready()` 里读到的是 (0,0,0)。
## ⚠️ 为什么必须赶在第一次 `move_and_slide()` 之前：沙盒允许把兵摆在石柱身上，那一刻引擎的
## 穿透修正就会给出一个位移 —— 锚点要是记在修正之后，石柱的第一帧就已经被挪走了。
func _capture_anchor() -> void:
	if _anchor_set or not is_anchored():
		return
	_anchor_pos = Vector2(global_position.x, global_position.z)
	_anchor_set = true

## 锚定单位每物理帧的水平复位（必须在 `move_and_slide()` **之后**调）。
##
## 用户口径（2026-09-26）："有些兵种**不知道为什么能够推动 9999 重量的石柱**（特别是位移类技能）"。
## ⚠️ **真因不是击退**：`_add_knockback()` 早把冲量除以重量（9999）⇒ `_kb` 只有 0.006 m/s 量级，
## 一秒钟走 6 mm，肉眼看不见。真正把石柱推走的是**引擎自己的穿透修正**：
##   技能位移（骑士冲撞 / 狂战士跳跃 / 火焰拳炎爆 / 轻骑兵冲刺 / 武士大师拔刀斩）里有好几支是
##   **直接写 `global_position`** 的，落点若在石柱的判定盒里（2.2 × 5.2 × 2.2）就形成**初始穿透**；
##   而石柱**自己**那一帧的 `move_and_slide()` 会把"我先陷在别人身体里"当成要修正的位移，
##   于是把它推出去 —— 沙盒里"把兵摆在石柱身上"同样是这条路（一摆下去石柱就挪窝）。
## ⇒ 锚定单位的两条水平轴由**锚点**说了算：本函数把这一帧引擎算出来的位移整段作废。
## ⚠️ **只钉水平**：y 交给重力与贴地（石柱要正常坐在地面上），伤害 / 眩晕 / 策反一概照吃。
## ⚠️ 顺手清掉 `_kb` 与水平速度：否则"被推的速度"会一直挂在 `velocity` 上，下一帧又被写回去。
func _hold_anchor() -> void:
	if not _anchor_set or not is_anchored():
		return
	global_position.x = _anchor_pos.x
	global_position.z = _anchor_pos.y
	velocity.x = 0.0
	velocity.z = 0.0
	_kb = Vector3.ZERO
	_kb_added = Vector3.ZERO

## 施加一次**眩晕**（2026-09-19 用户新增的状态）：`duration_ms` = 持续时间，即用户口径里的"眩晕 N"（N 秒）。
## 同时挨多次时取**较长**的那一次（不叠加、也不会被更短的一次"刷新"变短）。
## 眩晕 = 无法进行任何行动：`_physics_process` 会跳过 `_think()`（不移动 / 不转向 / 不攻击 / 不放技能），
## 进行中的技能交给 `_interrupt_skill()` 收尾。⚠️ 眩晕**不免疫**伤害与击退——那是另一套闸门。
func apply_stun(duration_ms: int) -> void:
	if not alive or duration_ms <= 0:
		return
	## **免疫眩晕的单位直接返回**（判据 `GameConfig.is_stun_immune()`，是**两个来源的并集**）：
	##   · **boss**（沙虫）—— 2026-09-19 的既有特权；
	##   · **载具**（投石车 / 弩车）—— **2026-09-25 第六条**（用户："投石车和弩车不会被眩晕"）。
	## 这里挡的是**任何来源**的眩晕（炎爆撞击 / 炎爆爆炸 / **石弹落点** / 沙虫浮出 / 后续新技能）。
	if GameConfig.is_stun_immune(type_id):
		return
	var now := Time.get_ticks_msec()
	## 本次眩晕**实际延长**了多少：已经晕着时，只有"新结束时刻比原来更晚"的那一段才算数
	##（更短的一次会被 `maxi` 吞掉 ⇒ 延长量 0 ⇒ 下面那笔"技能计时补偿"也正好是 0）。
	var was_until := maxi(_stun_until_ms, now)
	_stun_until_ms = maxi(_stun_until_ms, now + duration_ms)
	var added_ms := _stun_until_ms - was_until
	## ⚠️ **2026-09-25 第五条（用户："轻骑兵的冲锋在被眩晕打断后能在眩晕结束时继续冲锋
	## （眩晕持续期间不进行技能持续时间计时），直到 10s 为止"）** ⇒ 冲刺的眩晕语义定为 **暂停**：
	## **不作废、不退还额度**，只是"表停走" —— 把 `_lance_until_ms` 往后推 `added_ms`，
	## 于是眩晕期间流逝的时间**不会**从冲刺的 8 s 里扣掉，晕完接着冲剩下的那一段。
	## ⚠️ 补偿量必须用 `added_ms` 而**不是** `duration_ms`：否则"晕着又挨一次更短的眩晕"会把冲刺表凭空虚增。
	## ⚠️ 2026-09-25：这段"冲刺计时补偿 + 收起穿透掩码"已抽成 `_pause_lance()`，与**定身**共用一支
	##（`apply_root()` 要的是同一套语义）—— 两处各写一遍必然漂移。
	_pause_lance(added_ms)
	_interrupt_skill()

## 施加一次**减速**（2026-09-26 肉鸽陷阱）：`mult` = 生效时的移速倍率（0.20 = −80%）、`duration_ms` = 持续。
## ⚠️ 同时挨两次的合成规则（与眩晕"取较长者"同源，只是多了一维倍率）：
##   · **截止时刻取较晚的**；⚠️ 若新的一次**更短**，则**不缩短**原来那次（`maxi` 吞掉）；
##   · **倍率取更慢的那个**（`minf`）—— 两条各自最优，不会被"轻的那次"顶掉重的那次。
## ⚠️ 倍率在**本次结束时刻**到点后失效：`slow_factor()` 只在 `now < _slow_until_ms` 时用它 ⇒
## "先挨 −80% 3 s、0.5 s 后又挨 −20% 1 s"的结果是"前 3 s −80%、之后 −20% 直到 3.5 s"（合理且单调）。
func apply_slow(mult: float, duration_ms: int) -> void:
	if not alive or duration_ms <= 0:
		return
	var now := Time.get_ticks_msec()
	if now >= _slow_until_ms:
		_slow_mult = mult                     ## 上一次已经过期 ⇒ 这一次从干净的倍率起算
	else:
		_slow_mult = minf(_slow_mult, mult)
	_slow_until_ms = maxi(_slow_until_ms, now + duration_ms)

## 是否处于眩晕（布尔量读起来像断言，见 `08_naming.md#3.3`）。阵亡后一律为假。
func is_stunned() -> bool:
	return alive and Time.get_ticks_msec() < _stun_until_ms

## 施加一次**定身**（2026-09-25 用户新增）：`duration_ms` = 持续时间；同时挨多次取**较长**者（同眩晕）。
## 语义 = 眩晕的"不能行动" + **额外的"不能被位移"**（见 `_add_knockback()` 的闸门）：
##   · 跳过 `_think()`（不移动 / 不转向 / 不攻击 / 不放技能），进行中的技能走 `_interrupt_skill()`；
##   · 一切外力位移（击退 / 动量转移 / 被冲撞推开）**吃不上**，本帧攒下的击退速度也被清掉；
##   · ⚠️ **不免疫伤害**（与眩晕一致）；阵亡后无效。
## ⚠️ **刻意无视 `is_stun_immune()`**（boss ∪ 载具那道闸门）—— 用户 2026-09-25 明确裁决：
## 「定身无视 boss / 载具的免疫」，因为拔刀斩的口径是"**包括 boss 单位**"。
## 这是"整类免疫"的一个**成文例外**（见 `99_decisions.md` 同日条目），**不要照抄到眩晕上**。
func apply_root(duration_ms: int) -> void:
	if not alive or duration_ms <= 0:
		return
	var now := Time.get_ticks_msec()
	var was_until := maxi(_root_until_ms, now)
	_root_until_ms = maxi(_root_until_ms, now + duration_ms)
	## 冲刺的"暂停"语义与眩晕一致（晕着 / 定着的那一段不占它的 8 s，也不作废、不退额度）
	_pause_lance(_root_until_ms - was_until)
	_interrupt_skill()

## 是否处于定身。阵亡后一律为假。
func is_rooted() -> bool:
	return alive and Time.get_ticks_msec() < _root_until_ms

## 施加一次**前进布阵区的准备期**（肉鸽第七块）：`duration_ms` = 时长；同时挨多次取**较长**者。
## 语义 = **只有眩晕的"不能行动"那一半**（跳过 `_think()` ⇒ 不移动 / 不转向 / 不攻击 / 不放技能），
## ⚠️ **不免疫伤害、也不免疫位移**（用户裁决："5s后才能行动，期间会被敌方攻击" —— 击退照吃；
## 这一点与「定身」正相反，所以**不要**在这里加 `is_rooted()` 那类闸门）。
## ⚠️ 施加入口只有一处：`Roguelike` 在开战那一刻按"单位站不站在敌方延伸区里"发（见 `_capture_zone_prep()`）。
func apply_prep(duration_ms: int) -> void:
	if not alive or duration_ms <= 0:
		return
	_prep_until_ms = maxi(_prep_until_ms, Time.get_ticks_msec() + duration_ms)

## 是否还在准备期里（布尔量读起来像断言）。阵亡后一律为假。
func is_preparing() -> bool:
	return alive and Time.get_ticks_msec() < _prep_until_ms

## **无法行动**（眩晕 ∪ 定身 ∪ 准备期）：这三者对"能不能行动"完全一样，区别只在"能不能被位移"
##（眩晕 / 准备期不免疫，定身免疫）。
## ⇒ "跳过 `_think()` / 收武器 / 断动画链"这些地方一律用它；只有"位移"那一处才问 `is_rooted()`。
func is_incapacitated() -> bool:
	return is_stunned() or is_rooted() or is_preparing()

## 冲刺表的"暂停"补偿：把"被定住的那一段"从 `_lance_until_ms` 里扣掉，并先收掉"穿过所有单位"的掩码。
## ⚠️ 眩晕（`apply_stun()`）与定身（`apply_root()`）**共用这一支** —— 两处各写一遍必然漂移。
## ⚠️ 补偿量必须是"本次**实际延长**了多少"（`added_ms`）：更短的一次会被 `maxi` 吞掉 ⇒ 延长量 0；
## 若拿 `duration_ms` 当补偿，`_lance_until_ms` 会凭空虚增（2026-09-25 第五条已踩过一次）。
func _pause_lance(added_ms: int) -> void:
	if _lance_until_ms > 0 and added_ms > 0:
		_lance_until_ms += added_ms
		_release_pass_all()

## 眩晕打断：把"进行中的技能"收干净——骑士冲撞、狂战士跳跃、火焰拳炎爆的三段。
## ⚠️ 炎爆被打断时**不会爆炸**（蓄力 / 冲刺都没走完）。
## ⚠️ 2026-09-19：**三个技能都可能正在"穿队友"**（冲撞 / 跳跃 / 冲刺）⇒ "己方队伍层"改成在所有
## 分支之后**统一还原一次**（`_set_ally_ghost(false)` 幂等：没摘过就是白写一次位）。
## ⚠️ **2026-09-25 第五条：轻骑兵（矛）的冲刺**不在这里**处理** —— 它的眩晕语义是"**暂停**"、不是"打断"
##（用户："被眩晕打断后能在眩晕结束时继续冲锋（眩晕持续期间不进行技能持续时间计时），直到 10s 为止"）。
## 计时补偿在 `apply_stun()`、穿透掩码的收与放在 `apply_stun()` / `_lance_tick()`。
## ⚠️ **沿革（别改回去）**：2026-09-25 第四条曾在这里做"真打断 + 退还额度"，**同日第五条已推翻**。
## 不要再往这里加 `charge_lance` 分支 —— 那会让冲刺同时吃到"暂停"和"打断"两套语义，
## 表现是"一次眩晕就直接吃掉一次冲刺"（与用户要的"晕完接着冲完 10 s"相反）。
func _interrupt_skill() -> void:
	_charge_until_ms = 0
	_jump_until_ms = 0
	_pilot_charge_dir = Vector3.ZERO
	_pilot_flame_dir = Vector3.ZERO
	_flame_blast_target = null
	if _flame_phase != Flame.IDLE:
		_flame_phase = Flame.IDLE
		_flame_until_ms = 0
		_flame_charge_target = null
	## 武士大师的拔刀斩（2026-09-25）：被打断 ⇒ **技能作废** —— 阶段清空、穿透掩码收回、待结算表清掉。
	## ⚠️ **冷却照走**（`_iai_cd_until_ms` 在发动那一刻就起算了，与骑士冲撞同一个口径）：
	##    被打断不等于"白送一次"，否则"被控一下就重放"会变成没有代价的最强技能。
	## ⚠️ 已经中了定身的那些人不撤销（状态是独立的事），但他们**不再吃那 300+**（技能都作废了）。
	if _iai_phase != Iai.NONE:
		_iai_phase = Iai.NONE
		_iai_targets.clear()
		_set_pass_all(false)
	_set_ally_ghost(false)

## 盾牌的**挂点**（2026-09-25 第七条）：被盾牌挡下的箭会**改挂到这个节点下**，
## 于是"箭插在盾上"跟着人走，也跟着出手期间盾牌让位的那段摆动走。
## ⚠️ 没有盾的兵种返回 `null` ⇒ 调用方（`Arrow`）自己退回"钉在世界坐标"那条老路。
## ⚠️ 返回的是**内部节点**、不做拷贝：调用方只许把它当父节点用，不要改它的 transform。
func shield_anchor() -> Node3D:
	return _shield

## 剑盾兵在**攻击期间举不起盾**（优化 6：给弓手留出可被击中的窗口）。
## 盾牌会随攻击动作移开，所以只有"不在出手中"的时候才算有格挡。
## ⚠️ **2026-09-27 第十二轮（第二批科技）**：这一条现在也管两种**科技给的盾** ——
##   · 「高级格挡」（剑盾兵）：**出手时也挡**（用户："允许剑盾兵在攻击时格挡小型远程投射物，也能格挡子弹"）；
##   · 「This is SPARTA！」（长矛兵）：月牙盾能挡小型投射物，**攻击出手期间不能挡**。
## ⇒ 判据 = "本来有盾 **或** 科技给了盾"；"出手时算不算举盾"只对高级格挡豁免。
func is_guard_up() -> bool:
	if not has_shield() and not has_tech("block_ranged") and not has_tech("spartan"):
		return false
	if has_tech("block_ranged"):
		return true
	if has_tech("spartan"):
		return not _striking
	if type_id != "sword":
		return true
	return not _striking

## 买下「This is SPARTA！」后亮出月牙盾；撤销科技时收回。盾件出厂就挂在长矛兵身上，这里只改可见性。
func _apply_spartan_look() -> void:
	if type_id != "spear" or _shield == null:
		return
	_shield.visible = has_tech("spartan")

## 盾牌是否能挡住来自 dir 方向（箭矢飞行方向）的箭
func blocks_from(dir: Vector3) -> bool:
	if not is_guard_up():
		return false
	var to_source := -dir
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	## ⚠️ `.get(..., -1.0)`：**没有 `shield_arc_dot` 的兵种**（例如靠 Spartan 科技才拿到盾的长矛兵）按
	## **全向盾**算 —— 用户只说"获得一面盾"，没提方向 ⇒ 不替它编一个扇形。
	var threshold := float(GameConfig.profile(type_id).get("shield_arc_dot", -1.0))
	return forward.normalized().dot(to_source.normalized()) >= threshold

func tap_knockback() -> bool:
	var now := Time.get_ticks_msec()
	if now < _kb_until_ms:
		return false
	_kb_until_ms = now + GameConfig.KNOCKBACK_CD_MS
	return true

func is_ember() -> bool:
	return alive and _ember_until_ms > 0 and Time.get_ticks_msec() < _ember_until_ms

func _enter_ember() -> bool:
	if _ember_used or not has_tech("ember"):
		return false
	_ember_used = true
	var row := tech_def("ember")
	_ember_until_ms = Time.get_ticks_msec() + int(row.get("endure_ms", 2000))
	hp = 1.0
	return true

func _tick_ember() -> bool:
	if _ember_until_ms <= 0 or Time.get_ticks_msec() < _ember_until_ms:
		return false
	_ember_until_ms = 0
	_die()
	return true

func _tick_mend() -> void:
	if not has_tech("mend"):
		return
	var now := Time.get_ticks_msec()
	if _mend_next_ms <= 0:
		_mend_next_ms = now + GameConfig.ROGUELIKE_BURN_TICK_MS
		return
	if now < _mend_next_ms:
		return
	_mend_next_ms += GameConfig.ROGUELIKE_BURN_TICK_MS
	var ratio := float(tech_def("mend").get("heal_ratio", 0.0))
	hp = minf(max_hp, hp + max_hp * ratio)

func _tick_destroyer() -> void:
	if not has_tech("destroyer"):
		return
	var now := Time.get_ticks_msec()
	if _destroyer_next_ms <= 0:
		_destroyer_next_ms = now + GameConfig.ROGUELIKE_BURN_TICK_MS
		return
	if now < _destroyer_next_ms:
		return
	_destroyer_next_ms += GameConfig.ROGUELIKE_BURN_TICK_MS
	var ratio := float(tech_def("destroyer").get("self_ratio", 0.0))
	apply_hit(max_hp * ratio, null, Vector3.ZERO, 0.0, true)

func _tick_burrow_mend() -> void:
	if not is_burrower() or _burrow != Burrow.UNDER or not has_tech("burrow_mend"):
		return
	var now := Time.get_ticks_msec()
	if _burrow_mend_next_ms <= 0:
		_burrow_mend_next_ms = now + GameConfig.ROGUELIKE_BURN_TICK_MS
		return
	if now < _burrow_mend_next_ms:
		return
	_burrow_mend_next_ms += GameConfig.ROGUELIKE_BURN_TICK_MS
	var ratio := float(tech_def("burrow_mend").get("heal_ratio", 0.15))
	hp = minf(max_hp, hp + max_hp * ratio)

func _tick_summon_grenadiers() -> void:
	if not is_doom_eye() or has_meta("summoned") or not has_tech("summon_grenadier"):
		return
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("skirmish_elapsed_ms"):
		return
	var elapsed := int(arena_node.skirmish_elapsed_ms())
	if elapsed < 0:
		return
	## 换一场战斗就从头算。上一场留下的截止时刻不能把这一场的第一波推迟。
	var start := int(arena_node.get("skirmish_start_ms"))
	if start != _summon_skirmish_ms:
		_summon_skirmish_ms = start
		_summon_next_ms = 0
	var row := tech_def("summon_grenadier")
	var interval := int(row.get("interval_ms", 15000))
	var now := Time.get_ticks_msec()
	if _summon_next_ms > 0 and now < _summon_next_ms:
		return
	_summon_next_ms = now + interval
	_summon_grenadier_wave(row)

func _summon_grenadier_wave(row: Dictionary) -> void:
	var arena_node := _arena()
	if arena_node == null:
		return
	var count := int(row.get("count", 4))
	for index in count:
		var angle := TAU * float(index) / float(maxi(count, 1))
		var at := global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.5
		var summoned: Unit3D = arena_node.spawn_unit(team, "grenadier", at, rotation.y)
		summoned.set_meta("summoned", true)
		summoned.set_level(level)
		summoned.active = true

func _tick_aid_summon() -> void:
	var summon_type := String(aid_mods.get("summon_type", ""))
	if summon_type == "" or has_meta("summoned"):
		return
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("skirmish_elapsed_ms"):
		return
	var elapsed := int(arena_node.skirmish_elapsed_ms())
	if elapsed < 0:
		return
	var start := int(arena_node.get("skirmish_start_ms"))
	if start != aid_summon_skirmish_ms:
		aid_summon_skirmish_ms = start
		aid_summon_next_ms = 0
	var interval := int(aid_mods.get("summon_interval_ms", 10000))
	var now := Time.get_ticks_msec()
	if aid_summon_next_ms > 0 and now < aid_summon_next_ms:
		return
	aid_summon_next_ms = now + maxi(interval, 1)
	var count := int(aid_mods.get("summon_count", 4))
	for index in count:
		var angle := TAU * float(index) / float(maxi(count, 1))
		var at := global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.5
		var summoned: Unit3D = arena_node.spawn_unit(team, summon_type, at, rotation.y)
		if summoned == null:
			continue
		summoned.set_meta("summoned", true)
		summoned.set_level(level)
		summoned.active = true

func _tick_afterimage_life() -> void:
	if not has_meta("afterimage") or _summon_until_ms <= 0:
		return
	if Time.get_ticks_msec() >= _summon_until_ms:
		queue_free()

func _begin_sandstorm(now: int) -> void:
	if has_meta("brood") or not has_tech("sandstorm"):
		return
	var row := tech_def("sandstorm")
	_storm_at = global_position
	_storm_until_ms = now + int(row.get("duration_ms", 6000))

func _spawn_brood() -> void:
	if has_meta("brood") or not has_tech("broodmother"):
		return
	var arena_node := _arena()
	if arena_node == null:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var child: Unit3D = arena_node.spawn_unit(team, type_id, global_position + forward * 3.0, rotation.y)
	child.set_meta("brood", true)
	var row := tech_def("broodmother")
	child._hp_scale = float(row.get("hp_scale", 0.5))
	child._damage_scale = float(row.get("damage_scale", 0.5))
	child._apply_body_scale(child._hp_scale)
	child.set_level(level)
	child.set_techs(_tech)
	child.active = active

## 母虫召出来的小沙虫：外观和碰撞都按血量比例缩小，比例直接用科技行上的 `hp_scale`。
func _apply_body_scale(mult: float) -> void:
	if _visual != null:
		_visual.scale = Vector3.ONE * mult
	if _shape == null:
		return
	var box := _shape.shape as BoxShape3D
	if box == null:
		return
	var body_box: Dictionary = GameConfig.body_box(type_id)
	if body_box.is_empty():
		return
	box.size = (body_box["size"] as Vector3) * mult
	_shape.position = Vector3(0.0, float(body_box["lift"]) * mult, 0.0)

func _spawn_afterimage() -> void:
	if has_meta("afterimage") or not has_tech("afterimage"):
		return
	var arena_node := _arena()
	if arena_node == null:
		return
	var ghost: Unit3D = arena_node.spawn_unit(team, type_id, global_position, rotation.y)
	ghost.set_meta("afterimage", true)
	var row := tech_def("afterimage")
	ghost._hp_scale = float(row.get("hp_scale", 1.0 / 3.0))
	ghost.set_level(level)
	ghost.set_techs(_tech)
	ghost.active = active
	ghost._summon_until_ms = Time.get_ticks_msec() + int(row.get("duration_ms", 1000))

func _storm_row_at(other: Unit3D) -> Dictionary:
	if other == null or Time.get_ticks_msec() >= other._storm_until_ms:
		return {}
	if not other._tech.has("sandstorm"):
		return {}
	var radius := float(other._tech["sandstorm"].get("radius", 10.0))
	var flat := global_position - other._storm_at
	flat.y = 0.0
	if flat.length() > radius:
		return {}
	return other._tech["sandstorm"]

func sandstorm_fields() -> Dictionary:
	if Time.get_ticks_msec() >= _storm_until_ms or not _tech.has("sandstorm"):
		return {}
	var row: Dictionary = _tech["sandstorm"]
	return {
		"at": _storm_at,
		"radius": float(row.get("radius", 10.0)),
		"move_pct": float(row.get("move_pct", -0.40)),
		"taken_mult": float(row.get("damage_taken_mult", 0.6)),
	}

func _storm_move_pct() -> float:
	var arena_node := _arena()
	if arena_node != null and arena_node.has_method("storm_move_pct_at"):
		return float(arena_node.storm_move_pct_at(global_position))
	var pct := 0.0
	var tree := get_tree()
	if tree == null:
		return 0.0
	for node in tree.get_nodes_in_group("units"):
		var row := _storm_row_at(node as Unit3D)
		if row.is_empty():
			continue
		pct += float(row.get("move_pct", -0.40))
	return pct

func _storm_taken_mult() -> float:
	if not is_burrower():
		return 1.0
	var arena_node := _arena()
	if arena_node != null and arena_node.has_method("storm_taken_mult_at"):
		return float(arena_node.storm_taken_mult_at(global_position))
	var mult := 1.0
	var tree := get_tree()
	if tree == null:
		return mult
	for node in tree.get_nodes_in_group("units"):
		var row := _storm_row_at(node as Unit3D)
		if row.is_empty():
			continue
		mult *= float(row.get("damage_taken_mult", 0.6))
	return mult

func _try_riposte(from: Unit3D) -> bool:
	if not has_tech("riposte"):
		return false
	if from == null or not is_instance_valid(from) or not from.alive or from.team == team:
		return false
	var now := Time.get_ticks_msec()
	if now < _riposte_until_ms:
		return false
	var row := tech_def("riposte")
	_riposte_until_ms = now + int(row.get("cooldown_ms", 2000))
	var amount := GameConfig.hit_damage(type_id) * float(row.get("damage_mult", 1.0)) * _damage_scale
	from.apply_hit(amount, self)
	return true

func _update_storm_disc() -> void:
	var on := Time.get_ticks_msec() < _storm_until_ms and _tech.has("sandstorm")
	if not on:
		if _storm_disc != null:
			_storm_disc.visible = false
		return
	if _storm_disc == null:
		_storm_disc = MeshInstance3D.new()
		_storm_disc.name = "SandstormDisc"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 0.2
		_storm_disc.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.42, 0.30, 0.12, 0.28)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_storm_disc.material_override = mat
		add_child(_storm_disc)
	var radius := float(_tech["sandstorm"].get("radius", 10.0))
	_storm_disc.visible = true
	_storm_disc.global_position = Vector3(_storm_at.x, 0.15, _storm_at.z)
	_storm_disc.scale = Vector3(radius, 1.0, radius)

func has_flame_barrier() -> bool:
	return alive and Time.get_ticks_msec() < _barrier_until_ms

func _barrier_damage_mult() -> float:
	if not has_flame_barrier():
		return 1.0
	return _barrier_taken_mult

## 「暗影守护」：影袭触发后的那几秒里，打进来的伤害按表上的倍率收下。窗口外是 ×1。
func _shadow_guard_taken_mult() -> float:
	var row := tech_def("shadow_guard")
	if row.is_empty() or Time.get_ticks_msec() >= _guard_until_ms:
		return 1.0
	return float(row.get("damage_taken_mult", 1.0))

## 脚下那圈火环，屏障还在就亮着。
func _update_barrier_shell() -> void:
	var on := alive and Time.get_ticks_msec() < _barrier_until_ms and _barrier_taken_mult < 1.0
	if not on:
		if _barrier_shell != null:
			_barrier_shell.visible = false
		return
	if _barrier_shell == null:
		_barrier_shell = MeshInstance3D.new()
		_barrier_shell.name = "FlameBarrierShell"
		_barrier_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.72
		mesh.outer_radius = 0.95
		mesh.rings = 16
		mesh.ring_segments = 6
		_barrier_shell.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.32, 0.06, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.38, 0.08)
		mat.emission_energy_multiplier = 1.4
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_barrier_shell.material_override = mat
		add_child(_barrier_shell)
	var pulse := 1.0 + 0.08 * sin(float(Time.get_ticks_msec()) * 0.009)
	_barrier_shell.position = Vector3(0.0, 0.12, 0.0)
	_barrier_shell.scale = Vector3(pulse, 1.0, pulse)
	_barrier_shell.visible = true

## 这一次击杀该生出几个自己。复制体不再生，打死复制体也不算。
## 影魔要先把击杀权重攒到一档，并且自己名下同时只留一个。
func replicate_spawn_count(victim: Unit3D) -> int:
	if has_meta("replicated") or victim.has_meta("replicated"):
		return 0
	var weight := int(GameConfig.profile(String(victim.type_id)).get("weight", 0))
	if weight <= 0:
		return 0
	if type_id != "shadow":
		return mini(weight, GameConfig.ROGUELIKE_REPLICATE_CAP)
	_replicate_bank += weight
	if _replicate_bank < GameConfig.ROGUELIKE_SHADOW_REPLICATE_WEIGHT:
		return 0
	if _living_replicates() >= GameConfig.ROGUELIKE_SHADOW_REPLICATE_CAP:
		return 0
	_replicate_bank -= GameConfig.ROGUELIKE_SHADOW_REPLICATE_WEIGHT
	return 1

func _living_replicates() -> int:
	var owner_id := get_instance_id()
	var count := 0
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		if other.has_meta("replicated") and int(other.get_meta("replicate_owner", -1)) == owner_id:
			count += 1
	return count

## 火焰拳「火焰屏障」：开战满 delay 后放一次，给半径内友方（含自己、含潜地）挂上截止时刻。
func _tick_flame_barrier() -> void:
	if _barrier_cast or not has_tech("flame_barrier"):
		return
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("skirmish_elapsed_ms"):
		return
	var elapsed := int(arena_node.skirmish_elapsed_ms())
	if elapsed < 0:
		return
	var row := tech_def("flame_barrier")
	if elapsed < int(row.get("delay_ms", 1000)):
		return
	_barrier_cast = true
	var radius := float(row.get("radius", 18.0))
	var until := Time.get_ticks_msec() + int(row.get("duration_ms", 10000))
	var taken := float(row.get("damage_taken_mult", 0.6))
	if arena_node.has_method("show_flame_barrier"):
		arena_node.show_flame_barrier(global_position, radius)
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or not is_instance_valid(other) or not other.alive or other.team != team:
			continue
		if global_position.distance_to(other.global_position) > radius:
			continue
		other._receive_barrier(until, taken)

func grant_flame_barrier(until_ms: int, taken_mult: float) -> void:
	_receive_barrier(until_ms, taken_mult)


func _receive_barrier(until_ms: int, damage_mult: float) -> void:
	if until_ms <= _barrier_until_ms:
		return
	_barrier_until_ms = until_ms
	_barrier_taken_mult = damage_mult

## 火焰拳「能量汲取」：回复被击杀者最大生命的一半。装满之后多出来的部分加进最大生命。
func receive_kill(dead: Unit3D) -> void:
	if not alive or dead == null or not has_tech("energy_leech"):
		return
	var ratio := float(tech_def("energy_leech").get("hp_ratio", 0.5))
	var gain := dead.max_hp * ratio
	if gain <= 0.0:
		return
	var room := maxf(max_hp - hp, 0.0)
	if gain <= room:
		hp += gain
		return
	var overflow := gain - room
	hp = max_hp
	var denom := maxf(level_mult() * tech_hp_mult(), 0.001)
	_hp_bonus_flat += overflow / denom
	_apply_hp_total()

## 影魔「复仇」：生命降到 50% 和降到 0 各一次。打场上最近的敌人，并波及它周围。
func _try_revenge() -> void:
	if not has_tech("revenge") or max_hp <= 0.0:
		return
	var half := not _revenge_half_used and hp / max_hp <= 0.5
	var zero := not _revenge_zero_used and hp <= 0.0
	if half:
		_revenge_half_used = true
	if zero:
		_revenge_zero_used = true
	if half:
		_cast_revenge()
	if zero and alive:
		_cast_revenge()

func _cast_revenge() -> void:
	var row := tech_def("revenge")
	if row.is_empty():
		return
	var nearest := _find_target()
	if nearest == null:
		return
	var amount := GameConfig.hit_damage(type_id) * float(row.get("damage_mult", 1.5))
	var radius := float(row.get("radius", 4.0))
	var center := nearest.global_position
	var arena_fx := _arena()
	if arena_fx != null and arena_fx.has_method("show_revenge_burst"):
		arena_fx.show_revenge_burst(center, radius)
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team or other.is_burrowed():
			continue
		if center.distance_to(other.global_position) > radius:
			continue
		other.apply_hit(amount, self)

func _acid_taken_mult() -> float:
	if has_flame_barrier():
		return 1.0
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("acid_vuln_at"):
		return 1.0
	return float(arena_node.acid_vuln_at(global_position))

## 和自己连成一片的壁垒骑士（5 m 内互相够得着的都算同一片）。
func _bulwark_group() -> Array:
	var radius := float(tech_def("bulwark").get("link_radius", 5.0))
	var radius_sq := radius * radius
	var seen := {}
	var stack: Array = [self]
	var out: Array = []
	while not stack.is_empty():
		var cur := stack.pop_back() as Unit3D
		if cur == null or not is_instance_valid(cur):
			continue
		var key := cur.get_instance_id()
		if seen.has(key):
			continue
		seen[key] = true
		if not cur.alive or cur.team != team or not cur.has_tech("bulwark"):
			continue
		out.append(cur)
		for node in get_tree().get_nodes_in_group("units"):
			var other := node as Unit3D
			if other == null or not is_instance_valid(other) or other == cur:
				continue
			if not other.alive or other.team != team or not other.has_tech("bulwark"):
				continue
			var flat := other.global_position - cur.global_position
			flat.y = 0.0
			if flat.length_squared() <= radius_sq:
				stack.append(other)
	return out

func _holy_splash(center: Vector3, amount: float) -> void:
	if not has_tech("holy_strike"):
		return
	var now := Time.get_ticks_msec()
	if now < _holy_until_ms:
		return
	var row := tech_def("holy_strike")
	_holy_until_ms = now + int(row.get("cooldown_ms", 8000))
	var radius := float(row.get("radius", 4.0))
	var arena_fx := _arena()
	if arena_fx != null and arena_fx.has_method("show_holy_burst"):
		arena_fx.show_holy_burst(center, radius)
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team or other.is_burrowed() or other == target:
			continue
		if center.distance_to(other.global_position) > radius:
			continue
		other.apply_hit(amount, self)

## from 允许为 null：兴奋圈内伤等"无来源"的伤害会传 null
func apply_hit(amount: float, from: Unit3D = null, knockback: Vector3 = Vector3.ZERO,
		damage_on_transfer: float = 0.0, skip_armor: bool = false, bulwark_piece: bool = false,
		from_acid: bool = false, silence_ms: int = 0, silence_move_mult: float = 0.7,
		from_melee: bool = false) -> void:
	if not alive:
		return
	## ---- 肉鸽第三块：**攻击方那一队的伤害倍率**（进攻指令的加成 × 指挥所被打掉后的 −90%）----
	## ⚠️ 摆在本函数**最前面**、对所有来源一视同仁：近战 / 投射物 / 技能 / 溅射 / 传递伤害全都经过这里，
	## 在这一处乘就够（散在各攻击点上乘必然有漏网的）。⚠️ **腐化也吃这个倍率** —— 腐化师那一支把数值
	## 当腐化值用，而用户口径说的是"伤害下降 90%"，它那一跳就是它的"伤害"。
	## ⚠️ `from == null`（兴奋圈内伤）不受影响；⚠️ 其它模式里这个倍率恒为 1.0 ⇒ 行为与改动前**逐位相同**。
	var hit_amount := amount
	if not bulwark_piece and from != null and is_instance_valid(from):
		var arena_node := _arena()
		if arena_node != null:
			hit_amount *= arena_node.damage_mult_for(from.team)
		hit_amount = from._aid_undo_post_debuff(hit_amount)
		## ---- 肉鸽：**攻击方的等级倍率**（2026-09-27）----
		## ⚠️ 与上面那条一样摆在"所有来源的入口" ⇒ 近战 / 投射物 / 技能 / 溅射 / 传递伤害一次覆盖。
		## ⚠️ **独立乘区**（用户口径）：与百分比加成（彼此相加）**相乘**、与队伍伤害倍率也**相乘**；
		## 别的模式里 `level` 恒为 1 ⇒ ×1.0，逐位不变。
		hit_amount *= from.level_mult()
	## 魔法盾 / 「庇护」挡住腐化师和湮灭之瞳：线段穿过圆就不落在目标身上，盾自己吃这次伤害。
	if from != null and is_instance_valid(from) and from.is_sustained_beam() and from._beam_stopped_by_shield(self, hit_amount):
		return
	## 击杀归因（经验用）：记下最后一个打到我的单位。⚠️ 摆在腐化分流**之前** ——
	## 腐化那一路"不掉血"，但用户要的是"击杀者"，而腐化本身不产生击杀（不改 hp）。
	## 放在这儿也让"被箭射死 / 被技能打死 / 被溅射打死"三种来源一并覆盖（它们都走本函数）。
	if from != null and is_instance_valid(from) and from.team != team:
		_last_hitter = from
	## ⚠️ **心灵腐化师的攻击不掉血**（2026-09-25 第二轮，用户："攻击不会使敌方失去生命，而是给敌方
	## 叠加『心灵腐化值』"）⇒ 在这里**分流**：把"伤害"数值直接当腐化值加上去，`hp` 一个字不动、
	## 也**不发 `unit_was_hit`**（那条信号的含义是"受伤"，而这里没有受伤 —— 它现在只剩僵持计时一个用途）。
	## ⚠️ **2026-09-25 第四轮两处用户裁决（这一支因此被提到"无敌闸门"之前）**：
	##   ① "**无敌**不会免疫心灵腐化值" ⇒ 腐化**绕过** `is_invulnerable()`（滞空 / 拔刀斩 / 影子形态里照叠）；
	##   ② "**施加心灵腐化值也会触发影魔技能**" ⇒ 影袭的触发点也摆在这一支里（先问影袭、再决定加不加腐化）。
	##    ⇒ 顺序：**先影袭（免疫这一次"施加"）→ 再叠腐化**。两条都只在"来源是腐化师"时才走。
	## 指挥所不吃腐化：同一跳改成直接扣血，后面的护甲 / 扣血照常走。
	if from != null and is_instance_valid(from) and from.is_corruptor() and not is_command_post():
		if _try_shadow_strike(from):
			return                       ## 影魔把这一次"施加"也免疫掉了（并扑向来源）
		_add_corruption(hit_amount, from)
		return
	## 火箭跳跃的免疫窗口（2026-09-18 R3）：**一切伤害源**都在这里被挡下——
	## 近战、箭矢/石弹/弩箭、圈外内伤（`tick_circle_dot` 也走本函数）全都走这一道闸。
	## ⚠️ 2026-09-19 收窄（用户要求"无敌期间只是不受伤害，不免疫击退"）：这一支**只免伤害**，
	## 击退照常施加——所以滞空/落地 0.5 s 里挨打不会掉血，但照样会被推开（也因此会被推出射程、
	## 撞到队友时照常传递动量）。
	## ⚠️ 位置在腐化分流**之后**（见上：腐化刻意绕过这一闸）。
	if is_invulnerable():
		if knockback.length_squared() > 0.0001:
			_add_knockback(knockback, damage_on_transfer)
		return
	## 影袭（影魔，2026-09-25 第三轮）：**受到任意伤害时**免疫这一次并化成影子扑向来源（用户口径）。
	## ⚠️ 在"无敌闸门"之后 ⇒ 已经在无敌 / 影子里的单位不会重复触发（那一下本来就没打进来）。
	if _try_shadow_strike(from):
		return
	## ---- 点燃（「火焰附加」剑盾 8%/s、「火矢」短弓 6%/s，2026-09-27 第十二轮·第二批）----
	## 判据 = **打我的那个人**身上有没有点火科技（收在 `_ignite_from_attacker()` 里）。
	## ⚠️ 摆在这里（所有闸门之后、扣血之前）：被无敌挡下 / 被影袭吃掉的那一下**不点火**；
	## 而被盾挡下的箭**根本走不到 `apply_hit()`** ⇒ 天然满足火矢那条"**未被格挡的**攻击才能点燃"。
	if not bulwark_piece:
		_ignite_from_attacker(from)
	## 酸液：站在池里时受到的伤害翻倍。池自己的那一跳（`from_acid`）不再乘，分摊出去的那份也不再乘。
	if not from_acid and not bulwark_piece:
		hit_amount *= _acid_taken_mult()
	## ---- 肉鸽兵种科技（2026-09-27 第十二轮）：**护甲** → **魔法护盾** → 生命，三道按序结算 ----
	## ⚠️ 位置刻意选在"无敌 / 影袭两道德闸门**之后**"：那两道闸门是"这一下根本没打进来"（不是减伤），
	## 而护甲与护盾都是"打进来了、但被削掉"。⚠️ 也刻意在**腐化分流之后**：腐化不是伤害，护甲不该削它。
	## ① 护甲（「护甲升级」）：**每次受伤减少 `15 × 兵种等级` 点**，减到 0 为止（用户 2026-09-27 选定）。
	## ⚠️ `skip_armor = true` 只有一处调用者：**点燃的跳伤**（用户 2026-09-27 当场裁决"点燃不吃护甲"）——
	## 否则 15 × 等级的护甲会把 6~8%/s 的小额跳伤直接减到 0，点燃对高护甲单位等于无效。
	var incoming := hit_amount if skip_armor or bulwark_piece else maxf(hit_amount - tech_armor(), 0.0)
	## 壁垒：先在挨打的这个人身上扣护甲，再把剩下的平分给连在一起的骑士。分出去的那份不再扣护甲。
	if not bulwark_piece and has_tech("bulwark"):
		var linked := _bulwark_group()
		if linked.size() > 1:
			var each := incoming / float(linked.size())
			for mate in linked:
				var other := mate as Unit3D
				if other == null or other == self:
					continue
				other.apply_hit(each, from, Vector3.ZERO, 0.0, true, true, true, 0, silence_move_mult)
			incoming = each
	## 沉默放在分摊之后：先分摊再沉默，否则这一下会把「壁垒」自己关掉，伤害就分不出去。
	## 分到队友身上的那一份不带沉默。直接吃到这一发的人仍会沉默。
	if incoming > 0.0 and silence_ms > 0:
		apply_silence(silence_ms, silence_move_mult)
	## 火焰屏障：攻击伤害按倍率收下。燃烧和酸液在各自的结算里直接跳过。
	if not skip_armor and not from_acid:
		incoming *= _barrier_damage_mult()
		incoming *= _storm_taken_mult()
	incoming *= _shadow_guard_taken_mult()
	if from_melee and _try_riposte(from):
		return
	## ② 魔法护盾（「魔法护盾」）：**打不穿** —— 只要盾还在，这一发无论多大都只扣盾，溢出部分不落到生命上
	##（用户当场口径："受伤先扣盾、打不穿"，也正是"能完全抵挡至少一次伤害"的来源）。
	if _shield_hp > 0.0:
		_shield_hp = maxf(_shield_hp - incoming, 0.0)
		_flash = GameConfig.UNIT_HIT_FLASH_MS / 1000.0
		if knockback.length_squared() > 0.0001:
			_add_knockback(knockback, damage_on_transfer)
		Events.unit_was_hit.emit(self)     ## 挨打照报（僵持计时 / 音效都读它），但**不掉血、也不会死**
		_refresh_shield_bar()
		return
	var hp_before := hp
	hp = maxf(0.0, hp - incoming)
	if from != null and from != self and is_instance_valid(from) and from.has_tech("leech"):
		var dealt := hp_before - hp
		var ratio := float(from.tech_def("leech").get("heal_ratio", 0.5))
		from.hp = minf(from.max_hp, from.hp + dealt * ratio)
	_flash = GameConfig.UNIT_HIT_FLASH_MS / 1000.0
	if knockback.length_squared() > 0.0001:
		_add_knockback(knockback, damage_on_transfer)
	Events.unit_was_hit.emit(self)
	_try_revenge()
	if not alive:
		return
	if hp <= 0.0:
		if is_ember() or _enter_ember():
			hp = 1.0
			return
		_die()

## 盾牌挡下一发（由 `Arrow._resolve_segment()` 的 `"blocked"` 分支调用）。
## ⚠️ **2026-09-25 第七条（用户："箭矢被盾牌格挡时兵种不应该有受伤特效"）**：这里原先有一句
## `_flash = UNIT_HIT_FLASH_MS / 1000.0` —— 那是**和挨打同一个白闪**，所以挡下箭的单位看起来"被打了"。
## 已删除：**挡下 = 没受伤，不该有任何受伤反馈**；白闪只属于真正挨伤害的那条路（`apply_hit()`）。
## ⚠️ `unit_was_blocked` 事件**保留**，它有两个既有用途、都与"受伤"无关：
##   ① `Arena._on_any_hit()` 用它刷新 `_last_hit_ms`（僵持 20 s 判平局的计时）；
##   ② `06_audio.md` 的 `combat_shield_block` 事件名挂在它上面。
func on_shield_block() -> void:
	Events.unit_was_blocked.emit(self)

## 回到满血（血条一并复位、立刻隐藏）。
## 给"演示用的假战斗"收尾：`StartShowcase` 故意让那 8 个兵**真打到有人挨第一下**（好让冻结姿势正好落在
## 挥砍动画的顶点），冻住之前再把它们治好 ⇒ 开始界面背景里不会挂着"已经在掉血"的兵。
## ⚠️ 必须连 `_bar_ratio`（血条的平滑值）与贴图一起复位：冻结会停掉 `_process`，不复位就会定格在带伤的样子。
func heal_to_full() -> void:
	hp = max_hp
	_bar_ratio = 1.0
	_bar_fill_px = UnitFactory.HEALTH_BAR_INNER_PX
	if _bar != null:
		_bar.texture = UnitFactory.health_bar_texture(1.0, GameConfig.team_color(team))
		_bar.visible = false

func health_ratio() -> float:
	return hp / maxf(max_hp, 0.001)

## ---- 买兵时的"从天上掉下来"（2026-09-27 用户："新增动画购买兵种时令这一队兵种从天上掉下来
##（匀速，只是动画，0.5s内播放完）"）----
## ⚠️ **纯视觉**：偏移只加在**模型**（`_visual.position.y`）上 ⇒ 碰撞体 / 出生高度 / 判定一概不动 ——
##    它落地那一帧就能打、也能被打（I-31~I-34 与"出生点"那套口径都不受影响）。
## ⚠️ **匀速**（线性，不是自由落体）：偏移 = 起始高度 × **剩余比例**。
## ⚠️ 字段以 `_ms` 结尾且整型 ⇒ 自动进 `shift_deadlines()` 的暂停补偿扫描（暂停期间不白掉动画时间）。
var _drop_until_ms: int = 0        ## 掉落演出的结束时刻（绝对毫秒，I-13；0 = 没在演）
var _drop_total_ms: int = 0        ## 本次演出的总时长（算"还剩多少"用）
var _drop_height: float = 0.0      ## 本次演出的起始高度 m
var _drop_y: float = 0.0           ## 当前帧加在模型上的高度偏移 m（0 = 站在地上）
## 模型里的**贴地件挂点**（`GroundLock`；只有影魔建了它）—— 它的子件（影滩 / 影摆 / 拖尾）不跟着待机浮动。
var _ground_lock: Node3D = null

## 播一次"从天上掉下来"（**买兵**那条路专门调它；参数由调用方从 `GameConfig` 取 —— 默认值必须是常量表达式，
## 本项目一贯把默认值写死成 `-1` 那种哨兵或干脆不给默认值，这里选后者，免得跨脚本常量踩 GDScript 的限制）。
func play_drop_in(duration_ms: int, height: float) -> void:
	if not alive or duration_ms <= 0 or height <= 0.0:
		return
	_drop_total_ms = duration_ms
	_drop_height = height
	_drop_until_ms = Time.get_ticks_msec() + duration_ms
	_drop_y = height

## 把单位**摆回阵位**（肉鸽"回合开始恢复阵型"用，2026-09-27 用户："回合开始时兵种未回到原位"）。
## 位置与朝向直接写死，并把"这一场攒下来的瞬时状态"就地清掉：
##   速度 / 击退 / 状态机 / 出手链 / 进行中的技能 / 影子形态 / 潜地 / 穿透掩码 / 准备期。
## ⚠️ 与 `heal_to_full()` 分工：那条只管血，这条只管"人和状态回到出厂"。
## ⚠️ **刻意不动**眩晕 / 定身 / 减速这三个"附加状态"的**计时**：它们是战场上已经发生的既成事实，
##    且都很短（1~3 s）—— 本函数只负责位移与技能层面的残留。
## ⚠️ 高度一律取 `SPAWN_HEIGHT`（与 `Arena.spawn_unit()` 同一条口径）：y 交给重力落定，
##    免得"从空中掉下来的兵"被直接摆到地面上而与地形穿插。
func reset_to(at: Vector3, facing: float) -> void:
	if not alive:
		return
	global_position = Vector3(at.x, GameConfig.SPAWN_HEIGHT, at.z)
	rotation.y = facing
	velocity = Vector3.ZERO
	_kb = Vector3.ZERO
	_state = State.IDLE
	_striking = false
	_interrupt_skill()
	_set_pass_all(false)
	if _shadow_until_ms > 0:
		_end_shadow()
	_burrow = Burrow.SURFACED
	_burrow_until_ms = 0
	_no_enemy_since_ms = 0
	_rise_after_ms = 0
	_sink = 0.0
	_prep_until_ms = 0
	_last_hitter = null          ## 击杀归因不跨回合（上一场谁打死我的，与下一场无关）
	_ember_until_ms = 0
	_ember_used = false
	_move_lock_until_ms = 0
	_spartan_thrown = false
	_drop_intercept_claim()
	_silence_until_ms = 0
	_drop_laser_lock()
	_clear_extra_beams()
	refresh_ward()
	_peak_max_hp = 0.0
	_barrier_until_ms = 0
	_barrier_taken_mult = 1.0
	_barrier_cast = false
	_revenge_half_used = false
	_revenge_zero_used = false
	_replicate_bank = 0
	_holy_until_ms = 0
	_mend_next_ms = 0
	_destroyer_next_ms = 0
	_guard_until_ms = 0
	_storm_until_ms = 0
	_sidestep_until_ms = 0
	_riposte_until_ms = 0
	_summon_next_ms = 0
	_summon_skirmish_ms = 0
	_summon_until_ms = 0
	_burrow_mend_next_ms = 0

## **加上限并补等量当前血**（肉鸽第三块的"防御指令"与"指挥部升级"用；用户 2026-09-26 裁决：
## "加上限并补血"）。⚠️ 这是**一次性**的加法，不是每帧计算：调用方（肉鸽模式）在"买增益那一下"
## 对场上所有我方单位调一遍，之后**每个新上场的兵在出生后也调一遍**（`Roguelike._apply_defense_bonus()`）。
## ⇒ 所以这里**不记等级、也不参与任何逐帧结算**；`max_hp` 与 `hp` 同步长 ⇒ 血条比例天然不变。
## ⚠️ **2026-09-27（等级）**：这一笔改记进 `_hp_bonus_flat`（**加法池**），上限由 `_apply_hp_total()`
## 统一算成 `(原始血量 + 加法池) × 等级倍率` —— 用户那条乘区规则：**百分比相加、倍率独立相乘**。
func add_hp_bonus(amount: float) -> void:
	if amount <= 0.0:
		return
	_hp_bonus_flat += amount
	_apply_hp_total()

## 等级带来的**独立乘区倍率**（用户 2026-09-27："倍率 = L，2 级 2 倍、9 级 9 倍"）：
## 它与百分比加成（同一乘区、彼此相加）**逐个相乘**，也和"进攻 / 减益"那类倍率各自独立。
func level_mult() -> float:
	return float(maxi(level, 1))

## 设成第 L 级（调用方负责封顶，本类只保证 ≥ 1）。血量按"加法池 × 新倍率"重算，
## **当前血同步平移**（`hp += 新上限 − 旧上限`）⇒ 已经掉掉的那部分血不会被等级补回来。
func set_level(new_level: int) -> void:
	level = maxi(new_level, 1)
	_apply_hp_total()
	refresh_ward()


func set_aid_mods(mods: Dictionary) -> void:
	aid_mods = mods.duplicate()
	aid_blast_used = false
	_apply_hp_total()

## 按 `(原始血量 + 加法池) × 倍率` 重算上限（唯一的写 `max_hp` 的地方，除 `_ready()` 那一次）
func _apply_hp_total() -> void:
	## ⚠️ 科技的生命倍率（「护甲升级」/「防御模式」/「精英猎手」）是**独立乘区**（与等级倍率相乘），
	## 没有科技时它恒为 1.0 ⇒ 别的模式与改动前逐位相同。
	var new_max := (_hp_base + _hp_bonus_flat) * level_mult() * tech_hp_mult() * _hp_scale
	new_max *= float(aid_mods.get("hp_mult", 1.0))
	var delta := new_max - max_hp
	max_hp = new_max
	hp = maxf(hp + delta, 1.0)
	if active:
		_peak_max_hp = maxf(_peak_max_hp, max_hp)

## 击杀归因（2026-09-27 肉鸽的"经验"用）：最后一个对我造成伤害的单位；没挨过打 = null。
## ⚠️ 只记"最后打到的那个"——**不给伤害排名、也不累计**（用户口径只说"击杀者"）。
func killer() -> Unit3D:
	return _last_hitter if _last_hitter != null and is_instance_valid(_last_hitter) else null

func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	var hide_m := GameConfig.UNIT_LOD_HIDE_M
	_lod_far = cam != null and global_position.distance_squared_to(cam.global_position) > hide_m * hide_m
	if _mount_detail != null:
		_mount_detail.visible = not _lod_far

# ---------------------------------------------------------------- 主循环
func _process(delta: float) -> void:
	_update_lod()
	if _bar == null:
		return
	_bar_ratio = lerpf(_bar_ratio, health_ratio(), 1.0 - exp(-14.0 * delta))
	## 填充宽度按**内区像素**步进：只有跨过一档才重建那张 32×6 的贴图（一次受伤最多 30 次），
	## 其余帧零开销。底槽长度恒定、填充从左端长出去 ⇒ "还剩多少"是能直接比出来的。
	var fill_px := int(round(clampf(_bar_ratio, 0.0, 1.0) * float(UnitFactory.HEALTH_BAR_INNER_PX)))
	if fill_px != _bar_fill_px:
		_bar_fill_px = fill_px
		_bar.texture = UnitFactory.health_bar_texture(_bar_ratio, GameConfig.team_color(team))
	## 受伤才出现（`01_core_loop.md#1` 的口径是"未满血才显示"）：这里用**即时**血量判定，
	## 不等平滑值降下来 —— 否则刚挨打的那几帧还看不见条。
	## ⚠️ 2026-09-19：**潜地期间不显示**（那时它不可锁定、也无敌，头顶挂一条血条只会误导）。
	_bar.visible = alive and health_ratio() < 0.999 and not is_burrowed() and not _lod_far
	## 护盾条（「魔法护盾」科技）：与血条同频刷新（只有吃到该科技的单位才有这条；没有就是空调用）。
	_refresh_shield_bar()
	_update_skill_fx()
	_update_barrier_shell()
	_update_storm_disc()

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		var lit := _flash / (GameConfig.UNIT_HIT_FLASH_MS / 1000.0)
		if _body != null:
			(_body.material_override as StandardMaterial3D).albedo_color = _base_color.lerp(Color(1, 1, 1), lit * 0.85)
	if _visual != null and alive:
		## 影子形态（影袭，2026-09-25 第七轮）：**整个人变回"地上的一道影子"** —— 用户口径
		## "影魔触发技能『影袭』后移动时会直接变成地上的影子，到锁定单位面前时才会变回来"。
		## ⇒ 3D 模型整个藏掉、只留本体的 `FxShadowForm`（贴地那一片），落点由 `_tick_shadow()` 决定。
		## ⚠️ 状态**每帧从这里同步**（而不是在起手 / 落地那两处各写一次）：战斗中途被 `stop_skirmish()`
		## 收掉、或者哪一帧的推进被跳过，这条式子都能把外观拉回正确的样子。
		_visual.visible = not is_in_shadow_form()
		_show_fx(_fx_shadow_form, is_in_shadow_form())
		## 潜地的视觉下沉（纯表现）：`_sink` 按过渡时长平滑到 0 / 1，再乘 `_sink_depth_m`
		##（= 判定体高度 + 0.6 m，见 `_resolve_sink_depth()`）⇒ 整条虫埋进地板网格里，完全看不见。
		var sink_target := 1.0 if is_burrowed() else 0.0
		_sink = move_toward(_sink, sink_target, delta / (float(GameConfig.UNIT_SANDWORM_SINK_MS) / 1000.0))
		## 掉落演出（纯表现，**匀速**）：剩余比例 × 起始高度 ⇒ 线性下降，到点归零。
		## ⚠️ 与"走路浮动 / 潜地下沉"**相加**，三者各管各的偏移，谁都不覆盖谁。
		if _drop_until_ms > 0:
			var drop_left := _drop_until_ms - Time.get_ticks_msec()
			if drop_left <= 0:
				_drop_until_ms = 0
				_drop_y = 0.0
			else:
				_drop_y = _drop_height * (float(drop_left) / float(maxi(_drop_total_ms, 1)))
		_visual.position.y = _visual_base_y + absf(sin(Time.get_ticks_msec() * 0.004)) * GameConfig.UNIT_BOB_AMPLITUDE - _sink * _sink_depth_m + _drop_y
		## 贴地件反向抵消浮动（2026-09-27 结清旧账："影滩随待机浮动 / 触地尖梢受浮动影响"）：
		## `GroundLock` 底下挂的是"必须踩在地面上"的件 ⇒ 把上面那一行加进去的**浮动量**减回来
		##（只减浮动，**不减**潜地 / 掉落那两项 —— 那两项是"整个人一起动"，贴地件理应跟着）。
		if _ground_lock != null:
			_ground_lock.position.y = -absf(sin(Time.get_ticks_msec() * 0.004)) * GameConfig.UNIT_BOB_AMPLITUDE
		## 眩晕的可视反馈 = 原地摇晃；不眩晕时显式归零（阵亡倒地也用 `_visual.rotation`，不能留残留角度）
		_visual.rotation.z = STUN_SWAY_ANGLE * sin(Time.get_ticks_msec() * 0.012) if is_stunned() else 0.0
		## 剑圣的**旋风斩**（2026-09-27 第十二轮·第二批）：出手那一刀期间本体绕 Y 轴**转满一圈**
		##（用户："攻击动画为类似于'旋风斩'"），命中帧正好转到 180° = 刀刃扫过半场。
		## ⚠️ 只动 `_visual`（不动本体 `rotation.y`）—— 本体朝向仍是"面朝目标"，索敌 / 开火判定一个字节不变；
		## ⚠️ 不在攻击窗口里时**显式归零**（同上面那条眩晕摇晃的纪律：绝不留残留角度）。
		_update_saint_spin()
		## 潜地沙尘（纯表现，2026-09-19 用户三条优化）：① 只在**沙虫移动时**出现；② **逐渐出现 / 消失**；
		## ③ 时不时有小沙尘外冒。⇒ 用一个 0~1 的 `_dust` 统一驱动：目标是"在地下 且 真的在动"，
		## 按 0.25 s 的时间常数平滑（不写死具体秒数 ⇒ 观感自然）；半球的高度按 `_dust` 压扁、
		## 六团小沙尘各自错相位"冒一下"。
		if _fx_burrow != null:
			var moving := is_burrowed() and Vector2(velocity.x, velocity.z).length() > 0.35
			_dust = move_toward(_dust, 1.0 if moving else 0.0, delta / 0.25)
			_fx_burrow.visible = _dust > 0.01
			if _fx_burrow.visible:
				var now_ms := Time.get_ticks_msec()
				var breath := 1.0 + 0.06 * sin(now_ms * 0.0025)
				_fx_burrow.scale = Vector3(breath, (0.70 + 0.30 * _dust) * breath, breath) * _hp_scale
				for i in _dust_puffs.size():
					var k := fmod(float(now_ms) * 0.000625 + float(i) / float(_dust_puffs.size()), 1.0)
					var pop := maxf(0.0, 1.0 - k * 3.0)
					_dust_puffs[i].scale = Vector3.ONE * (0.65 + 0.9 * pop * _dust)
	_animate_attack()
	## 沙虫浮出"震地"特效（非沙虫 / 没在播时是一次空判断，直接返回）
	_update_burst_fx(Time.get_ticks_msec())
	## 炎爆的三段特效（非火焰拳直接返回，见 `_update_flame_fx()`）
	_update_flame_fx()
	## 激光光束（2026-09-25 第二轮）：与特效件同一档 —— 纯表现，每帧跟着目标重摆（非腐化师直接返回）。
	_update_beam_fx()
	_update_laser_beam()
	_update_ward_ring()

## 攻击动作：前摇抬起、命中帧落下（纯表现，不影响判定）
func _animate_attack() -> void:
	if _weapon == null or not alive:
		return
	if is_doom_eye():
		if has_tech("energy_scatter"):
			_weapon.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			_weapon.position = Vector3(0.0, UnitFactory.DOOM_CORE_Y + UnitFactory.DOOM_CORE_R + 0.25, 0.0)
		else:
			_weapon.rotation = _weapon_rest
			_weapon.position = _weapon_rest_pos
		return
	if is_corruptor() and has_tech("multi_beam"):
		_weapon.visible = false
		return
	if is_corruptor():
		_weapon.visible = true
	if _state != State.ATTACK or is_incapacitated():
		_weapon.rotation = _weapon.rotation.lerp(_weapon_rest, 0.25)
		_weapon.position = _weapon.position.lerp(_weapon_rest_pos, 0.25)
		_striking = false
		## ⚠️ 2026-09-19（攻击节奏重做）：**断开动画链** ⇒ 下一次出手必须从头挥。
		## 眩晕走同一支：被晕期间武器收回静止姿态，醒来后 `_tick_attack()` 会按"命中帧 − 前摇"重新起手。
		_swing_from_ms = 0
		_drop_intercept_claim()
		## 弩车：退出攻击态（换目标 / 目标出射程）时弦与弓臂也一起收回静止姿态，
		## 用与上面同一个平滑系数 ⇒ 走到一半被打断不会僵在"拉满"上（其它兵种是空数组，直接返回）。
		_bow_draw = lerpf(_bow_draw, 0.0, 0.25)
		_apply_bow_draw(_bow_draw)
		if _shield != null:
			_shield.rotation = _shield.rotation.lerp(_shield_rest, 0.25)
			_shield.position = _shield.position.lerp(_shield_rest_pos, 0.25)
		return
	var interval := _attack_interval()
	# 前摇比例按兵种取（长矛兵比全局值短一半，见 `GameConfig.PROFILES.spear`）
	var windup := interval * GameConfig.windup_ratio(type_id)
	## 2026-09-24 用户："攻击前的摆动速度 ×4""旋转到最上方的瞬间就是石头飞出去的瞬间"。
	## ⚠️ 上一版把整段**压缩**（`t = timer / (windup/4)`）⇒ 抛臂在前摇 1/4 处就到顶、然后干等到命中帧，
	## 用户看到的正是"到最高处过一会儿石头才飞"。现在改成**把起点推后**：前摇的最后 1/4 才起摆，
	## 用 4 倍速在 `windup` 那一刻正好甩到顶 ⇒ 到顶瞬间 == 命中帧（石弹实体就在那一帧生成，攻击逻辑没动）。
	var swing_time := windup / SIEGE_WINDUP_SPEEDUP if is_siege_thrower() else windup
	var swing_start := windup - swing_time if is_siege_thrower() else 0.0
	var settle_time := (interval - windup) / SIEGE_RECOVER_SPEEDUP if is_siege_thrower() else (interval - windup)
	var t := clampf((_attack_timer - swing_start) / maxf(swing_time, 0.001), 0.0, 1.0)
	var swing := lerpf(0.0, 1.15, t)
	# 出手窗口 = **起手 → 命中帧 → 收招 55%**，这段时间剑盾兵的盾让开（优化 6）。
	# ⚠️ 2026-09-19：这个窗口由"动画链是否已起手 + 收招进度"推导（不再有 `_windup_swing` 闩锁）——
	# "这一口已经结算"等价于"动画时钟已经越过命中帧（`_attack_timer >= windup`）"，
	# 因为命中帧就是动画顶点所在的同一格（见 `_tick_attack()` 的排程）。
	_striking = _swing_from_ms > 0 and Time.get_ticks_msec() >= _swing_from_ms
	if _attack_timer >= windup:
		var recover := clampf((_attack_timer - windup) / maxf(settle_time, 0.001), 0.0, 1.0)
		swing = lerpf(1.15, 0.0, recover)
		_striking = recover < 0.55
	# 出手动作按兵种分派，前几类共用上面这条 0 → 1.15 → 0 的 `swing` 曲线，只是作用在不同通道：
	#   突刺型（长矛）：动**位置**——矛杆沿自身轴（本体 −Z）向前推出去再收回来；
	#   挥扇型（扇子兵）：动**旋转**，但**只绕本体 X 轴**——扇面水平铺开，绕水平轴就是**上下扇动**
	#     （扇柄在身侧、扇面朝前，绕 X 转 = 扇面整体往上抬 / 往下压，不是左右横扫）；
	#   挥砍型（剑盾 / 骑士 / 狂战士）：动**旋转**，X（劈）+ Z（横扫）两轴一起给；
	#   上弦型（弩车，2026-09-19）：不走 `swing`，改由 `draw` 驱动弓臂与弦，见下面那一支。
	if is_thrusting():
		_weapon.position = _weapon_rest_pos + Vector3(0.0, 0.0, -swing * GameConfig.UNIT_THRUST_DISTANCE)
	elif is_burrower():
		## 沙虫（2026-09-19）：出手是**下颚前咬** —— 与长矛同一手法（动位置、不动旋转），但幅度更大，
		## 让这只 boss 的每一口都有分量。判定与它无关：伤害仍走 `_resolve_cone_attack()` 的 ±60° 扇形。
		_weapon.position = _weapon_rest_pos + Vector3(0.0, 0.0, -swing * GameConfig.UNIT_SANDWORM_BITE_DISTANCE)
	elif is_flapping():
		_weapon.rotation = _weapon_rest + Vector3(-swing * FAN_FLAP_ANGLE, 0.0, 0.0)
	elif is_siege_thrower():
		## 投石车（2026-09-24 用户两条）：① "扔石头的方向是反的" ⇒ 改**正向**——绕 +X 转**正角**
		## 才会把指向 −Z 的抛臂**抬起来**（负角是往下压，那正是改前的错误方向）；
		## ② "扔之前大幅摆动、扔出后逐渐复位" ⇒ 复用上面那条 `0 → 1.15 → 0` 曲线，
		## 但摆幅用 `SIEGE_THROW_ANGLE`（0.90 rad ≈ 52°，通用远程只有 0.35）：前摇期间大幅后仰抬起、
		## 命中帧到达最大摆幅（= 甩出去），随后按 `recover` 平滑落回静止姿态。
		## 2026-09-24 用户："是**顺时针**旋转不是逆时针" ⇒ 方向取反（角度**减小**）。
		## 实测：−2.40（我方最低处）减 2.08 rad ⇒ 走到 −4.48 ≡ +1.80 = 枢轴正上方（垂直），
		## 与正向绕行是同一个终点，只是转的另一侧。曲线峰值系数 1.15 ⇒ 摆幅 = 2.08 / 1.15 ≈ 1.81。
		_weapon.rotation = _weapon_rest + Vector3(-swing * SIEGE_THROW_ANGLE, 0.0, 0.0)
		## 兜与石弹**永远保持水平**（碗口朝上）：把抛臂当前角度反向抵消。
		## 否则臂一后仰，碗口就朝下，石头看起来要掉出去（2026-09-24 用户："这不掉下去了"）。
		if _siege_bucket != null:
			_siege_bucket.rotation = Vector3(-_weapon.rotation.x, 0.0, 0.0)
	elif is_bolt_shooter():
		## 弩车（2026-09-19 用户逐条）：
		##   ① "攻击前把弦像拉弓一样往后" ⇒ 前摇期间弦心一路后退，到 **`windup` = 命中帧**正好拉满
		##      （弩箭就是那一帧生成的，与投石车"甩到顶即命中"同一条规矩：动画顶点对齐命中帧）；
		##   ② "弓臂也略微往后" ⇒ 两根弓臂绕各自的弓臂根后仰 `BALLISTA_LIMB_FLEX_ANGLE`；
		##   ③ "攻击的一瞬间在极短时间内按原动画的反动画迅速回位" ⇒ 命中后用 `BALLISTA_RELEASE_TIME`
		##      把同一条曲线**倒放**回 0（`smoothstep(1 − u) ≡ 1 − smoothstep(u)`，曲线关于 0.5 对称），
		##      而不是像短弓手那样慢慢复位。⚠️ **倒放的起点钉死在命中帧**：`draw` 只由 `_attack_timer` 决定，
		##      转折点就是 `_attack_timer == windup`（= 弩箭生成那一帧），所以改 `BALLISTA_RELEASE_TIME`
		##      只影响"回位多快"，**不可能移动出手时机**（出手判定在 `_tick_attack` 里，与动画无关）。
		##   ④ 补（同日第二轮）："怎么是向上仰而不是向下" ⇒ ① 弓臂再绕 Z **向下弯** `BALLISTA_LIMB_DIP_ANGLE`
		##      （臂梢下沉 ≈0.50 m，这是"向下"的主体）；② 整弓改成**后段下压**（正角，见常量处）；
		##      ③ 弦心后退翻倍并在后退时同步下沉。所以两臂梢是"向后 + 向下"沉、弦心是"向后 + 向下"退进箭槽。
		var draw := 0.0
		if _attack_timer < windup:
			draw = smoothstep(0.0, 1.0, _attack_timer / maxf(windup, 0.001))
		else:
			draw = 1.0 - smoothstep(0.0, 1.0,
					clampf((_attack_timer - windup) / BALLISTA_RELEASE_TIME, 0.0, 1.0))
		_bow_draw = draw
		_apply_bow_draw(draw)
		_weapon.rotation = _weapon_rest + Vector3(draw * BALLISTA_TILT_ANGLE, 0.0, 0.0)
	elif is_ranged():
		_weapon.rotation = _weapon_rest + Vector3(-swing * 0.35, 0.0, 0.0)
	else:
		_weapon.rotation = _weapon_rest + Vector3(-swing * 1.25, swing * 0.35, 0.0)
	# 盾牌随出手让到身侧（纯表现；格挡判定只看 _striking，见 `04_physics.md#7.1.1`）。
	# 平时盾面朝前挡在身前，出手窗口内旋转 + 横移让开——观感要能对上"这会儿挡不住箭"。
	if _shield != null:
		var across := 1.0 if _striking else 0.0
		_shield.rotation = _shield.rotation.lerp(
			_shield_rest + GameConfig.UNIT_SHIELD_SWING * across, 0.25)
		_shield.position = _shield.position.lerp(
			_shield_rest_pos + GameConfig.UNIT_SHIELD_OFFSET * across, 0.25)

## 弩车"上弦"的姿态：把 `draw`（0 = 静止的直弦，1 = 拉满）落到弓臂与弦上（纯表现，不碰判定）。
##   · 弓臂：绕弓臂根**向后**（绕 Y，`BALLISTA_LIMB_FLEX_ANGLE`）+ **向下**（绕 Z，`BALLISTA_LIMB_DIP_ANGLE`）
##     一起让开 ⇒ 两臂梢向后下方沉下去（用户 2026-09-19："怎么是向上仰而不是向下"）；
##   · 弦  ：两半弦的**外端钉在当前臂梢上**（臂梢一动，弦端跟着动）、内端在木身中线上对接，
##          一起后退 `BALLISTA_DRAW_DISTANCE` 并下沉 `BALLISTA_DRAW_DROP` ⇒ 拼成一个朝后开的 V、落进箭槽上方。
##   ⚠️ 内端的高度**不跟着臂梢走**：真实的弩是"臂弯下去、弦被拉进箭槽"。若内端跟着臂梢一起沉，
##      弦会扎穿木身——弦心在弓组件转轴后面 ≈1.14、臂梢只在 ≈0.14，下沉比是 8:1（见常量处的说明）。
##   两半弦是**刚性**的，所以内端退开时按"枢轴 → 弦心"的实长改写弦杆长度（最多长 23% 左右，
##   肉眼看不出来），换来的是**内端永远落在中线上**、弦不会在中间撕成两截。
func _apply_bow_draw(draw: float) -> void:
	if _bow_halves.is_empty():
		return
	var flex := draw * BALLISTA_LIMB_FLEX_ANGLE
	var dip := draw * BALLISTA_LIMB_DIP_ANGLE
	for i in _bow_halves.size():
		var limb := _bow_limbs[i]
		## 两侧对称：绕 Y 与绕 Z 的符号都相反（左 +、右 −）才会**一起向后下方**让开。
		var flex_sign := 1.0 if i == 0 else -1.0
		limb.rotation = Vector3(0.0, flex_sign * flex, flex_sign * dip)
		## 弓臂枢轴自己不会被移动，所以 `position` 恒为弓臂根；臂梢按枢轴**当前姿态**取，
		## 于是"弦端钉在臂梢上"这件事对任何旋转都自动成立（不必手算两轴复合）。
		var tip: Vector3 = limb.position + limb.transform.basis * (_bow_tips[i] - limb.position)
		var vertex := Vector3(0.0, _bow_tips[i].y - draw * BALLISTA_DRAW_DROP,
				tip.z + draw * BALLISTA_DRAW_DISTANCE)
		var span := vertex - tip
		var half := _bow_halves[i]
		var bar := _bow_bars[i]
		half.position = tip
		## 与弓臂段同一套"+Z 对上这一段"的朝向（俯仰 `asin` + 偏航 `atan2`）
		half.rotation = Vector3(-asin(span.y / span.length()), atan2(span.x, span.z), 0.0)
		var half_len := span.length()
		var bar_mesh := bar.mesh as BoxMesh
		var bar_size := bar_mesh.size        ## 只改长度，截面（0.048 见方）沿用工厂里那一份
		bar_size.z = half_len
		bar_mesh.size = bar_size
		bar.position.z = half_len * 0.5

func _physics_process(delta: float) -> void:
	if not alive:
		## 尸体滑行（2026-09-19）：被击退致死的单位在停稳前**仍是实体**，
		## 由 `_tick_corpse_slide()` 继续推着走并把动量传出去。
		if _corpse_slide_until_ms > 0:
			_tick_corpse_slide(delta)
			return
		# 阵亡演出期间不再参与物理：否则失去碰撞后会一直往下掉
		_tick_dying(delta)
		return

	## ⚠️ 2026-09-24：兜与抛臂按用户要求**刚性固定**，这里不再做水平抵消（原先每帧调用已删除）。

	## 锚定单位（召唤石柱）：第一个物理帧开头先记下"玩家摆下的那个点"——此时还没跑过任何
	## `move_and_slide()`，所以记下的是干净坐标（捕获的详细理由见 `_hold_anchor()`）。
	_capture_anchor()

	_apply_gravity(delta)

	## ⚠️ 影子形态（影袭）**不受 `active` 闸门约束**：它平时由 `_think() → _tick_skill()` 推进，而
	## "战斗在冲刺途中被 `stop_skirmish()` 收掉"（沙盒点「结束战斗」/ 一方全灭）之后 `_think()` 再也不跑
	## ⇒ 它会永远停在"没有模型的影子"上（连尸体都看不见）。这里补一条只认 `not active` 的推进。
	if _shadow_until_ms > 0 and not active:
		_tick_shadow()

	## 心灵腐化：每物理帧两件事 —— ① "停照即清" ② 腐化值 > 剩余血量 ⇒ 整队换边（见 `_tick_corruption()`）。
	## ⚠️ 放在 `_think()` **之前**：换边要当帧就生效，否则这一帧它还会按旧阵营索敌、开一枪。
	_tick_corruption()

	## 点燃（「火焰附加」/「火矢」，2026-09-27 第十二轮·第二批）：每物理帧推进一次跳伤 / 到期清理。
	## ⚠️ 与腐化并列摆在这里（`_think()` 之前）：让"这一帧被点着"当帧就开始计时，不受走位影响。
	_tick_burn()
	_tick_silence()
	## 自我修复 / 毁灭者 / 余烬只在开战之后走（准备阶段停手，不在布阵时掉血或猝死）。
	if active:
		if _peak_max_hp <= 0.0:
			_peak_max_hp = max_hp
		_tick_mend()
		_tick_burrow_mend()
		_tick_destroyer()
		_tick_flame_barrier()
		_tick_summon_grenadiers()
		_tick_aid_summon()
		_tick_afterimage_life()
		if not alive or _tick_ember():
			_remember_motion(delta)
			return

	## 击退期间的位移处理分两档（2026-09-18 用户要求）：
	##   禁移档（自身重量 < 本次击退数值）—— 位移完全由 `_kb` 接管，自主移动整个让位；
	##   可移动档（重量 ≥ 击退数值）—— 照常自主走位，击退只**叠加**位移。
	## ⚠️ 顺序很重要：`_think()` 里的 `_tick_move()` 会写 `velocity`，所以击退速度必须在它**之后**
	## 再叠一次，否则"边走边被推"会互相抵消（这正是改动前的表现：只有站定攻击的单位才推得动）。
	var knocked := is_knocked_back()
	if not knocked:
		_kb_value = 0.0
		_kb_damage = 0.0
	## ⚠️ **2026-09-25 第八条（用户："轻骑兵似乎有时候被击退时就停止了冲锋"）**：
	## **冲刺期间强制按"可移动档"处理** —— 击退从"整体覆盖 `velocity`"降级为"叠加"。
	## 根因：禁移档在 `_physics_process` 里**两次**用 `_kb` 覆盖 `velocity`，而**第二次在 `_think()` 之后**
	##（`_think()` → `_lance_tick()` 刚把速度写成 14 m/s）⇒ 冲刺速度被当场冲掉，单位只能被推着走，
	## 观感就是"冲锋停了"。⚠️ 判据是 **`_lance_active()`（只认冲刺本身）** ——
	## **不要用 `is_mid_dash()`**：那个把"被击退 / 骑士冲撞 / 火焰拳炎爆"都算成真，
	## 拿它当豁免条件会把豁免发给所有正在被击退的单位（实测踩到过，见 `_lance_active()` 的注释）。
	## ⇒ 只豁免"冲刺正在驱动位移"这一种：其余单位、其余状态下的"禁移"一个字都没改。
	## ⚠️ 由此**冲刺中的轻骑兵仍会被推**（位移真的发生），只是不再被"顶掉自主速度" ⇒ 它一边被推一边继续冲。
	## 叠加档那套"本帧先收回上一帧叠进去的分量"的记账（`_kb_added`）在这里同样成立，不会被 `_lance_tick()`
	## 的赋值污染 —— 那个赋值发生在收账**之后**、叠加**之前**。
	var immobile := knocked and is_knockback_immobile() and not _lance_active()
	## 可移动档的击退是**叠加**在 velocity 上的，所以本帧要先把上一帧叠进去的分量收回来，
	## 否则它会被 `_think()` 当成"自主速度"留在 velocity 里、逐帧累积成 2 倍击退
	##（禁移档是整体覆盖 velocity，不存在这个问题，`_kb_added` 恒为 0）。
	if _kb_added.length_squared() > 0.0:
		velocity.x -= _kb_added.x
		velocity.z -= _kb_added.z
		_kb_added = Vector3.ZERO
	## ⚠️ **2026-09-25 定身：位移一律冻结**（用户："无法被位移（包括击退）"）——
	## 把攒下的击退速度就地清掉 ⇒ 本帧既不进"禁移档"也不进"可移动档"，水平位移为 0
	##（重力仍在 y 上：定身不是浮空，也不免疫伤害）。
	if is_rooted():
		_kb = Vector3.ZERO
	if knocked:
		_kb = _kb.lerp(Vector3.ZERO, clampf(GameConfig.KNOCKBACK_DECAY * delta, 0.0, 1.0))
		if immobile:
			velocity.x = _kb.x
			velocity.z = _kb.z
	## 自主移动没有被禁止时，照常跑"停下就减速"（原来是 `elif`，现在只有禁移档才跳过）。
	## ⚠️ 火箭跳跃期间也必须跳过：此时 `_think()` 不跑（技能接管），若还按"停下"减速，
	## 起跳的水平速度会在几帧内被减没，人只在原地起落（2026-09-18 R3 实测踩到过）。
	## 眩晕 / 定身（2026-09-19 / 2026-09-25 两个状态）：一切自主行动停摆 —— `_think()` 被跳过
	##（不移动 / 不转向 / 不攻击 / 不放技能），状态拨回 IDLE ⇒ 下面那条"停下就减速"会把自主速度收干净。
	## 重力 / 击退 / 碰撞照常（眩晕不等于无敌，见 `apply_stun()`）。
	## ⚠️ **定身额外冻结位移**（上面已经清了 `_kb`），眩晕不冻 —— 这是两者唯一的区别。
	if is_incapacitated():
		_state = State.IDLE
	## ⚠️ 拔刀斩的「自己定身」那一段（2026-09-25）：它**不能行动**（`_root_until_ms` 已置），
	## 但技能还得继续跑 —— "被穿过那些人"的定身结束时要把那 300+ 打出去。
	## 定身会让下面的 `_think()` 整个不跑（连带 `_tick_skill()`），所以这一段**在这里单独推进**。
	if _iai_phase == Iai.SELF_ROOT:
		_tick_iai(Time.get_ticks_msec())
	if ((not knocked) or (not immobile)) and _jump_until_ms <= 0:
		if _state != State.MOVE:
			velocity.x = move_toward(velocity.x, 0.0, GameConfig.UNIT_STOP_DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0.0, GameConfig.UNIT_STOP_DECELERATION * delta)

	if piloted and _shadow_until_ms > 0:
		_tick_shadow()
	elif piloted and active and not is_incapacitated():
		_tick_pilot(delta)
	elif active and not is_incapacitated():
		_think(delta)

	## "穿队友"的延时还原：必须在 `move_and_slide()` 之前跑，掩码本帧才生效（见 `_release_ally_ghost()`）
	_tick_ally_ghost()
	## 冲刺"穿过所有单位"的延时还原：同样必须在 `move_and_slide()` 之前（见 `_release_pass_all()`）
	_tick_pass_clear()

	if knocked:
		if immobile:
			velocity.x = _kb.x
			velocity.z = _kb.z
		else:
			## 可移动档：`_think()` 刚写好的自主速度加上击退位移（本帧速度 = 自主 + 击退）
			velocity.x += _kb.x
			velocity.z += _kb.z
			_kb_added = Vector3(_kb.x, 0.0, _kb.z)

	## 轻骑兵冲刺时碰撞体是关掉的，`move_and_slide` 推不开任何人，只是在空跑物理。
	## 直接按速度挪位置。击退速度在上面已经加进 velocity，所以仍会被推着走，只是不再被挤开。
	var stand_speed := GameConfig.UNIT_STAND_SLIDE_SPEED
	var horiz_sq := velocity.x * velocity.x + velocity.z * velocity.z
	var standing := not knocked and velocity.y == 0.0 and horiz_sq < stand_speed * stand_speed
	var marching := not standing and not knocked and velocity.y == 0.0 and _march_clear(delta)
	if _lance_until_ms > 0 and _shape != null and _shape.disabled:
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
		if global_position.y < GameConfig.SPAWN_HEIGHT:
			global_position.y = GameConfig.SPAWN_HEIGHT
		velocity.y = 0.0
	elif standing:
		## 站定砍人：碰撞体还在，走过来的人仍会被挡住。自己不再参加这一帧的挤压求解。
		velocity.x = 0.0
		velocity.z = 0.0
	elif marching:
		## 走向敌人、身边还没人：不参加挤压，队友挤不歪这一列。靠近敌人才改回滑动。
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
	else:
		move_and_slide()

	## 锚定单位：**这一帧的位移一概作废**（必须在 `move_and_slide()` 之后、动量转移之前）。
	## 位置先钉回锚点，之后那段动量转移读到的仍是"我正贴着谁"，但它推不动我。
	_hold_anchor()

	## 动量转移（2026-09-18 / 2026-09-19 扩展到技能位移）：
	## 被推着走、或正在冲撞 / 跳跃时撞到别人，把自己的一部分动量传过去。
	## 必须在 `move_and_slide()` **之后**取碰撞，否则拿不到本帧真正撞到的对象。
	## ⚠️ 两个狂战士互跳撞到一起时，双方都会走这一支 ⇒ 彼此把动量传给对方（用户要求"遵守动量传递"）。
	if knocked:
		_transfer_motion_momentum(_kb)
		## 被击退的一方也要跑按距离判定：否则"先被撞开的一方"从此只剩滑动碰撞，
		## 于是 A 撞 B 之后 B 推不回 A（2026-09-19 实测到的另一半不对称）
		_transfer_motion_to_contacts(_kb)
	elif _charge_until_ms > 0 or _jump_until_ms > 0:
		## 技能位移（冲撞 / 跳跃）：2026-09-19 用户第六条起是"纯穿过队友" ⇒ 两处都跳过己方
		_transfer_motion_momentum(velocity, true)
		## 技能位移同样补一次**按距离**的对称判定
		_transfer_motion_to_contacts(velocity, true)

	# 移动之后再锁一次目标（优化 6）：本帧所有单位都已经走完，
	# 这时算出的"最近者"才是玩家在这一帧真正看到的那一个。
	# 顺序很关键——放在移动之前会留下"目标相对位置已变"的一帧滞后。
	if active and _state != State.DEAD and not piloted:
		_lock_nearest_target()

	## ⚠️ 被击退时**不按速度方向转身**（2026-09-19 修 bug）：被推着走的那几帧里 velocity 就是
	## 击退方向，单位会朝着"被推走的方向"转过去——盾牌正面、扇子兵的扇形攻击正面都跟着乱。
	## 朝向只由目标方向（`_tick_move()` / `_tick_attack()` 里的 `_face()`）决定，击退不参与。
	if _state == State.MOVE and not knocked:
		var dir := Vector3(velocity.x, 0.0, velocity.z)
		if dir.length_squared() > 0.04:
			_face(dir, delta)
	_remember_motion(delta)
	## 照射一旦离开攻击态，这次蓄力作废。下次再打要重新蓄，伤害档也从最低一档起。
	if is_sustained_beam() and _state != State.ATTACK:
		_laser_arming = false
		_laser_engaged = false

## 贴地判定改为**射线自查**，不用 is_on_floor()。
## 原因（bug 2a/2b 真因）：即便接触法线是 (0,1,0)、穿透只有 1 mm，引擎仍返回
## is_on_floor()=false / is_on_wall()=true，导致每帧"重力→被地板挡住→不算着地"，
## 水平位移被一起吃掉，表现就是选手站在原地下坠/不动。详见 99_decisions.md。
## 行进中可以不跑滑动：最近的敌人还远，而且正前方碰不到地面上的东西。
func _march_clear(delta: float) -> bool:
	if target != null and is_instance_valid(target) and target.alive and target.team != team:
		var flat := global_position - target.global_position
		flat.y = 0.0
		var limit := GameConfig.UNIT_MARCH_SLIDE_M
		if flat.length_squared() <= limit * limit:
			return false
	return not _march_hits_world(delta)

func _march_hits_world(delta: float) -> bool:
	var speed_sq := velocity.x * velocity.x + velocity.z * velocity.z
	if speed_sq < 0.0001:
		return false
	var speed := sqrt(speed_sq)
	var reach := speed * delta + GameConfig.UNIT_MARCH_BODY_M
	var from := global_position + Vector3(0.0, 0.6, 0.0)
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(velocity.x / speed, 0.0, velocity.z / speed) * reach)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _grounded() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var to := global_position + Vector3(0.0, -0.25, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _apply_gravity(delta: float) -> void:
	if _grounded():
		velocity.y = 0.0
		return
	velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)) * delta
	# 终端速度：避免单帧位移超过地板厚度而穿地（修 bug 2a/2b）
	velocity.y = maxf(velocity.y, -GameConfig.TERMINAL_VELOCITY)

func _tick_dying(delta: float) -> void:
	_dying_ms += int(delta * 1000.0)
	var t := clampf(float(_dying_ms) / float(GameConfig.UNIT_CORPSE_FADE_MS), 0.0, 1.0)
	if _visual != null:
		_visual.rotation = Vector3(0.0, 0.0, lerpf(0.0, -PI * 0.5, t))
		_visual.position.y = lerpf(_visual_base_y, _visual_base_y - 0.35, t)
	if _dying_ms >= GameConfig.UNIT_CORPSE_FADE_MS:
		queue_free()

# ---------------------------------------------------------------- AI
## ---- 移动信标（肉鸽第六块）：挂路线 / 清路线 / 这一帧的路线走位 ----
## 挂上一条路线（`points` = 信标 → P1 → P2 的世界坐标；由 `Roguelike._capture_beacon_routes()` 在开战那一刻调）。
func set_beacon_route(points: Array) -> void:
	if points.size() < 2:
		return
	_beacon_points = PackedVector3Array()
	for p in points:
		_beacon_points.append(Vector3(p))
	_beacon_total = 0.0
	for i in range(1, _beacon_points.size()):
		_beacon_total += _flat_gap(_beacon_points[i - 1], _beacon_points[i])
	## 起点 = 自己位置在路线上的**投影**（取最近那一段的垂足）⇒ 后面的 `_beacon_arc` 从那里往前推
	var proj := _route_project(global_position)
	_beacon_arc = float(proj["arc"])
	var foot: Vector3 = proj["point"]
	_beacon_offset = Vector3(global_position.x - foot.x, 0.0, global_position.z - foot.z)

func clear_beacon_route() -> void:
	_beacon_points = PackedVector3Array()
	_beacon_offset = Vector3.ZERO
	_beacon_arc = 0.0
	_beacon_total = 0.0

func has_beacon_route() -> bool:
	return _beacon_points.size() >= 2

func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## 路线上的取点：给定弧长 `arc` 返回世界坐标（超出末端 ⇒ 返回终点）
func _route_point_at(arc: float) -> Vector3:
	var acc := 0.0
	for i in range(1, _beacon_points.size()):
		var a := _beacon_points[i - 1]
		var b := _beacon_points[i]
		var seg := _flat_gap(a, b)
		if seg <= 0.001:
			continue
		if acc + seg >= arc:
			return a.lerp(b, clampf((arc - acc) / seg, 0.0, 1.0))
		acc += seg
	return _beacon_points[_beacon_points.size() - 1]

## 把世界坐标投到路线上：返回 `{arc, point}`（`arc` = 最近那一段起点弧长 + 垂足在本段内的长度）
func _route_project(p: Vector3) -> Dictionary:
	var best := {"arc": 0.0, "point": _beacon_points[0]}
	var best_dist := INF
	var acc := 0.0
	for i in range(1, _beacon_points.size()):
		var a := _beacon_points[i - 1]
		var b := _beacon_points[i]
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var seg := ab.length()
		if seg <= 0.001:
			continue
		var ap := Vector3(p.x - a.x, 0.0, p.z - a.z)
		var t := clampf(ap.dot(ab) / (seg * seg), 0.0, 1.0)
		var foot := a + ab * t
		var dist := _flat_gap(p, foot)
		if dist < best_dist:
			best_dist = dist
			best = {"arc": acc + seg * t, "point": foot}
		acc += seg
	return best

## 这一帧的路线走位（返回 true = 这一帧的位移由信标接管）。
## ⚠️ 用户口径"攻击时也会移动" ⇒ 够得着就**先**按常规打一下（`_tick_attack()`），**再**把速度改成沿路线的
## —— 顺序不能反：`_tick_attack()` 里的收招 / 走位都会写 `velocity`。
## ⚠️ 速度要**夹到自己的移速**：转弯处"这一帧该到的点"除以 delta 会大于面板移速，不夹会在拐角弹射一下。
## ⚠️ **2026-09-27 修 bug（用户："在被移动信标影响移动的时候兵种也是能攻击的（不影响移动）"）**：
##    原先这里既调 `_tick_attack()`（它内部 `_face(目标)`）、又在后面无条件 `_face(路线方向)` ——
##    **两个朝向每帧互相打架**，命中帧那一刀/那一箭的朝向永远指向行进方向 ⇒ 看起来就是"不攻击"。
##    现在按"够得着 ⇒ `_state = ATTACK` + 朝向交给目标；够不着 ⇒ 沿路线走 + 朝向交给路线"分工，
##    **移动一秒不停**（速度照样每帧按路线写）—— 这就是用户要的"能攻击、但不影响移动"。
func _tick_beacon_route(delta: float) -> bool:
	if not has_beacon_route() or not alive:
		return false
	_beacon_arc += current_speed() * delta
	var want := _route_point_at(_beacon_arc) + _beacon_offset
	## 这一帧够不够得着（与 `_tick_attack()` 内部的出射程判据同式）
	var attacking := (target != null and _target_valid() and surface_distance_to(target) <= attack_reach()) \
			or _can_fan_intercept()
	if attacking:
		_state = State.ATTACK
		_tick_attack(delta)
	elif _state == State.ATTACK:
		_state = State.MOVE          ## 目标出射程 ⇒ 回到"沿路线移动"（命中帧与冷却不在这里复位，同既有口径）
	var cap := current_speed()
	var flat := Vector2((want.x - global_position.x) / maxf(delta, 0.001),
			(want.z - global_position.z) / maxf(delta, 0.001))
	if flat.length() > cap:
		flat = flat.normalized() * cap
	velocity.x = flat.x
	velocity.z = flat.y
	## 朝向：**攻击中交给目标**（`_tick_attack()` 已经转过一次），没在攻击时才沿路线
	if not attacking and flat.length() > 0.01:
		_face(Vector3(flat.x, 0.0, flat.y).normalized(), delta)
	if _beacon_arc >= _beacon_total:
		clear_beacon_route()               ## 到终点 ⇒ 交还自由移动（用户："移动到终点时开始自由移动"）
	return true

func _think(delta: float) -> void:
	## ---- 肉鸽第三块：**无攻击能力的建筑**（指挥所）----
	## 用户口径："无攻击能力，不移动" ⇒ 这类单位**连索敌都不做**（`is_no_attack()` 是 PROFILE 标记，
	## 与 `is_corruptor()` 同一种"我是什么只有一处出处"的做法）。⚠️ 放在函数最前面：
	## `_tick_skill()` 与整条走位 / 出手分支都跳过 ⇒ 每帧只花一次标记查询的钱。
	## ⚠️ 这也是它的 `attack_speed` 敢写 0 的前提 —— `attack_interval()` 是 `1.0 / attack_speed`。
	if GameConfig.is_no_attack(type_id):
		_state = State.IDLE
		return
	_drop_untargetable()
	# 目标由 _lock_nearest_target() 维护（每物理帧移动前后各锁一次），
	# 始终指向"距离最近的敌人"（优化 6）。这里只按目标远近切换状态。
	## ⚠️ 2026-09-19：**技能判定提前到"没有目标就待机"之前**。原因只有一个 —— 潜地（沙虫）必须能在
	## **完全没有敌人**时也钻地（用户口径："攻击范围内没有敌人时会钻入地中" ⇒ 一个敌人都没有当然更该钻）。
	## 安全性：其余技能自己都会先校验目标（`_can_charge()` / `_can_jump()` / `_can_flame_burst()` 都要求
	## `_target_valid()`），没有目标的单位调用它们只会原样返回 false ⇒ 行为不变。
	if _tick_skill():
		return
	## ---- 肉鸽第六块：**移动信标**（沿路线平移，攻击时也走）----
	## ⚠️ 排在技能**之后**：冲刺 / 跳跃 / 炎爆是"这一帧整体接管"的更强语义，信标不该把它们顶掉；
	## ⚠️ 排在"没有目标就待机"**之前**：没有敌人时信标照样该走（用户口径"优先跟着路线移动"）。
	if _tick_beacon_route(delta):
		return
	if target == null and not _shield_lock_alive():
		if _can_fan_intercept():
			_state = State.ATTACK
			_tick_attack(delta)
			return
		_drop_intercept_claim()
		if is_sustained_beam():
			_drop_laser_lock()
			if _extra_beam_id() != "":
				_state = State.ATTACK
				_tick_attack(delta)
				return
		_state = State.IDLE
		return
	if target == null:
		if _state == State.IDLE:
			_state = State.MOVE
		match _state:
			State.MOVE:
				_tick_move(delta)
			State.ATTACK:
				_tick_attack(delta)
			State.DEAD:
				pass
		return
	if _state == State.IDLE:
		_face((target.global_position - global_position).normalized(), delta)
		_state = State.MOVE

	match _state:
		State.MOVE:
			_tick_move(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.DEAD:
			pass

## 技能（2026-09-18 新机制，见 `02_entities.md#2.3`）：满足条件且冷却结束时自动释放。
## 返回 true 表示"这一帧由技能接管"——调用方不再跑常规走位/攻击。
func _tick_skill() -> bool:
	var skill := String(GameConfig.profile(type_id).get("skill", ""))
	if skill == "":
		return false
	## 冲锋进行中：锁住冲锋，直到撞到人或超时
	if _charge_until_ms > 0:
		if Time.get_ticks_msec() >= _charge_until_ms:
			_charge_until_ms = 0
			_release_ally_ghost()      ## 冲超时了 ⇒ 请求收掉"穿队友"（撞到人那条在 `_charge_tick` 里收）
			return false
		_charge_tick()
		return true
	## 跳跃进行中：只保持水平速度，竖直方向交给重力画抛物线
	if _jump_until_ms > 0:
		if Time.get_ticks_msec() >= _jump_until_ms:
			_jump_until_ms = 0
			_release_ally_ghost()      ## 落地（滞空结束）⇒ 请求让队友重新变成实体（可能延时几帧，见 `_release_ally_ghost()`）
			return false
		return true
	if skill == "charge" and _can_charge():
		_charge_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_CHARGE_MAX_MS
		_skill_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_CHARGE_CD_MS
		_set_ally_ghost(true)           ## 2026-09-19 用户第六条：冲撞也能穿过队友
		return true
	## 冲刺进行中：接管到 3 s 走完或被锁定对象中途失效（撞到人**不停** ——
	## 用户口径是"持续时间内对锁定对象发动冲刺"，所以它是一段 3 s 的持续推进，不是单次撞击）。
	## ⚠️ **这一段必须排在"能不能发动"的判断之前**：`_lance_tick()` 在 `_can_lance()` 之前返回时
	## 会**落到下面的发动判断**，而此刻冷却还没起算（冷却按用户口径"从技能结束后开始计算"）
	## ⇒ `_can_lance()` 恒为真 ⇒ **每帧都重新发动一次冲刺**（`_lance_until_ms` 被逐帧刷新、
	## 3 s 永不结束、矩形一次都判不出，而且**额度会被瞬间扣光**）。
	## 2026-09-25 引擎内探针实测到的就是这个：`start` 每帧 +1 而 `tick` 恒为 0。
	## 其它技能的 `_charge_until_ms` 分支自带 `return`，所以它们没有这个问题 —— 这是本技能独自踩到的坑。
	if skill == "charge_lance" and _lance_until_ms > 0:
		return _lance_tick()
	if skill == "rocket_jump" and _can_jump():
		_start_jump()
		return true
	## 炎爆（火焰拳，2026-09-19）：四段流程全部由它接管；**无冷却**，所以没有 `_skill_cd_until_ms` 那一步。
	if skill == "flame_burst":
		return _tick_flame_burst()
	## 潜地（沙虫，2026-09-19）：boss 单位的技能，逐帧决定"露出还是钻地"，并接管两个过渡段。
	if skill == "burrow":
		return _tick_burrow()
	## 冲刺（轻骑兵（矛），2026-09-25 新增 / 同日大改）：三件事都归它管 ——
	##   ① **冲刺进行中**（上面的 `_lance_until_ms > 0` 分支）⇒ 接管这 3 s；
	##   ② **冷却结束 + 目标进 7 m + 还有剩余次数** ⇒ 发动（三道闸门**全在 `_can_lance()` 里**；
	##      ⚠️ "还有剩余次数"这一条是 2026-09-25 第三条才补上的 —— 此前漏判 ⇒ 额度用完后还能再冲，
	##      实测表现为"每场能冲 3 次"。根因与修法见 `_can_lance()` 的注释）；
	##   ③ 其余时间 ⇒ `_lance_patrol()` 在 ≥10 m 处游走（**额度用完后它直接返回 false**，
	##      于是退化为普通近战：走常规走位、只打平 A）。
	##   ⚠️ 它必须夹在"常规走位"之前：`_lance_patrol()` 返回 true 时这一帧不会走到 `_tick_move()`。
	## ⚠️ 与骑士的 `"charge"` 是**两个不同的技能**：骑士是"撞到一个人就停"的单次冲撞（0.9 s）；
	##   轻骑兵是"8 s 内持续冲刺、矩形范围反复结算"（2026-09-25：3 s → 10 s → 8 s）。
	## ⚠️ **2026-09-25 起它是第 4 套掩码口径**：冲刺期间**穿过所有单位**（用户："能穿过所有单位"）
	##   且**不推开任何人** —— 既不同于骑士/狂战士/火焰拳的"只穿队友"，
	##   也推翻了它自己上一版"队友照旧挡路、只推敌人"的口径。见 `_set_pass_all()`。
	if skill == "charge_lance":
		if _can_lance():
			_start_lance()
			return true
		return _lance_patrol()
	## 武士大师（boss，2026-09-25 新增）：**四个技能共用一条循环**（`_tick_master()` 里有优先级说明）。
	if skill == "master":
		return _tick_master()
	## 影魔（2026-09-25 第三轮新增）：只有**一个"进行中"的东西** —— 影子形态那一段位移。
	## ⚠️ 另一个技能「时候已到」是**纯被动**（伤害加成），没有循环、也不接管帧（见 `_outgoing_damage()`）。
	## ⚠️ 注意它**不像影袭那样靠"技能分发"发动**：影袭的入口在 `apply_hit()`（受击那一刻），
	## 这里只是把"已经在影子里的那几帧"推进完。
	if skill == "shadow":
		return _tick_shadow()
	## 召唤石柱（2026-09-25 第七轮，**仅沙盒模式**）：技能「单位召唤」是**被动排程**，**不接管这一帧**
	##（返回 false）—— 石柱一边按节拍召唤，一边照常对 10 m 内的敌人开火。见 `_tick_summon()`。
	if skill == "summon":
		_tick_summon()
		return false
	## 盾牌猛击（骑士第二技能，2026-09-19）：与冲撞**并存**，且**不接管这一帧**——它就是一次额外出手，
	## 做完继续走常规走位/攻击（用户选的"就按面板出手"）。
	_tick_bash()
	return false

## 盾牌猛击（骑士，2026-09-19 用户要求）：射程内 + 冷却（`UNIT_BASH_CD_MS` = 3 s）结束 ⇒ 一次
## 伤害 ×1（`UNIT_BASH_DAMAGE_MULT`）、击退数值 2（`UNIT_BASH_KNOCKBACK`）的强化出手。
## ⚠️ 与普通出手的唯一差别：**不去动 `_striking`**。盾牌失效只看那一个标志（`blocks_from()`），
## 不动它就是用户要的"盾牌猛击期间仍能格挡弓箭"。
func _tick_bash() -> void:
	if not bool(GameConfig.profile(type_id).get("bash", false)):
		return
	if not alive or not _target_valid() or Time.get_ticks_msec() < _bash_cd_until_ms:
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if surface_distance_to(target) > attack_reach():
		return
	_bash_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_BASH_CD_MS
	var knock := to_target / dist * GameConfig.KNOCKBACK_SPEED * GameConfig.UNIT_BASH_KNOCKBACK
	target.apply_hit(GameConfig.hit_damage(type_id) * GameConfig.UNIT_BASH_DAMAGE_MULT, self, knock)

# ---------------------------------------------------------------- 武士大师（boss，四技能，2026-09-25 新增）
## 四个技能**共用这一条循环**（`PROFILES["master"]["skill"] = "master"`）。返回 true = 这一帧由技能接管。
## 优先级从上到下：④拔刀斩进行中 → ④可发动 → ②冲刺进行中 → ②可发动 → ③后撤步（不接管帧）→ 交回常规走位。
## ⚠️ **①高级偏折不在这一支**：它是**被动**（挨打那一刻才判），入口是 `try_deflect()`，
## 由 `arrow.gd#_resolve_segment()` 在"射线查到这个人"时调用。
func _tick_master() -> bool:
	var now := Time.get_ticks_msec()
	## ④ 拔刀斩进行中：独占整帧（四段全在 `_tick_iai()` 里）
	if _iai_phase != Iai.NONE:
		return _tick_iai(now)
	## ③ 后撤步的**滑行段**：也独占整帧（2026-09-25 用户："后撤步应有动画"）
	if _backstep_until_ms > 0:
		return _tick_backstep(now)
	if _can_iai(now):
		_start_iai(now)
		return true
	if _dash_until_ms > 0:
		return _tick_master_dash(now)
	if _can_master_dash(now):
		_start_master_dash(now)
		return true
	_tick_backstep(now)
	return false

## ① 高级偏折：**这一发小型投射物要不要被我弹回去**（由 `Arrow` 在射线查到本单位时调用）。
## ⚠️ **第一道闸门必须是"我是不是武士大师"**（2026-09-25 修 bug）：
## 本函数挂在 `Unit3D` 上、而 `arrow.gd#_resolve_segment()` 对**任何被打中的敌人**都会调它 ——
## 第一版没有这道判断，而 `_deflect_charges_left` 的字段默认值是 15 ⇒ **全场每个单位都自带 15 次偏折额度**。
## 用户报的现象："**火枪手在射击的时候自己会死去**"：它的 200 伤害子弹被对面（哪怕是个剑盾兵）
## 原样弹回来，而它只有 150 血 ⇒ **开一枪自己就死**。⚠️ 同一时刻所有弓手的箭也在被悄悄弹回，
## 只是先在火枪身上暴露出来。
func try_deflect(arrow: Arrow) -> bool:
	if not alive or arrow == null or arrow.deflected:
		return false
	if String(GameConfig.profile(type_id).get("skill", "")) != "master":
		return false
	if _deflect_charges_left <= 0:
		return false
	if Time.get_ticks_msec() < _deflect_cd_until_ms:
		return false
	_deflect_charges_left -= 1
	_deflect_since_cd += 1
	var per_cooldown := GameConfig.UNIT_MASTER_DEFLECT_PER_COOLDOWN
	var deflect_up := tech_def("deflect_up")
	if not deflect_up.is_empty():
		per_cooldown = int(deflect_up.get("per_cooldown", per_cooldown))
	if _deflect_since_cd >= per_cooldown:
		_deflect_since_cd = 0
		_deflect_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_MASTER_DEFLECT_CD_MS
	return true

## ② 冲刺：**类似冲撞，但不造成伤害与击退**（用户口径）—— 只把自己送到"锁定目标进攻击范围"。
## 三条闸门：目标在**攻击范围之外**、**8 m 以内**（2026-09-25 用户："冲刺新增触发条件：锁定单位在8m内"），
## 且**不在后撤步的锁里**（用户："后撤步未完成时即后撤步完成后 0.3 s 内不得冲刺"）。
func deflect_flight_range() -> float:
	var up := tech_def("deflect_up")
	if up.is_empty():
		return GameConfig.UNIT_MASTER_DEFLECT_RANGE
	return float(up.get("flight_range", GameConfig.UNIT_MASTER_DEFLECT_RANGE))

## 偏折正在冷却时才能闪过一发远程投射物。闪过的那一发继续飞，不打在自己身上。
func try_sidestep() -> bool:
	if not alive or has_meta("afterimage"):
		return false
	if String(GameConfig.profile(type_id).get("skill", "")) != "master":
		return false
	if not has_tech("sidestep"):
		return false
	var now := Time.get_ticks_msec()
	if now < _sidestep_until_ms or now >= _deflect_cd_until_ms:
		return false
	_sidestep_until_ms = now + int(tech_def("sidestep").get("cooldown_ms", 5000))
	return true

func _can_master_dash(now: int) -> bool:
	if has_meta("afterimage"):
		return false
	if now < _master_dash_cd_until_ms or now < _dash_lock_until_ms or not _target_valid():
		return false
	var dist := surface_distance_to(target)
	return dist > attack_reach() and dist <= GameConfig.UNIT_MASTER_DASH_RANGE

func _start_master_dash(now: int) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	_dash_dir = to_target.normalized()
	_dash_until_ms = now + GameConfig.UNIT_MASTER_DASH_MAX_MS
	_master_dash_cd_until_ms = now + GameConfig.UNIT_MASTER_DASH_CD_MS + int(aid_mods.get("cd_add_ms", 0))
	_face(_dash_dir, get_physics_process_delta_time())

## 冲刺的每帧：直着压过去，**一进攻击范围就停**（不造成任何伤害与击退）。
## ⚠️ 它**不穿单位**（与骑士冲撞一样会被挡住）—— 用户只说"类似冲撞"，没提穿透；
##    真被挡住时靠兜底时限收手（`UNIT_MASTER_DASH_MAX_MS`），不会永远推着墙走。
func _tick_master_dash(now: int) -> bool:
	if not _target_valid():
		_dash_until_ms = 0
		return false
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		_dash_dir = to_target.normalized()
	if surface_distance_to(target) <= attack_reach() or now >= _dash_until_ms:
		_dash_until_ms = 0
		velocity.x = 0.0
		velocity.z = 0.0
		return false
	_face(_dash_dir, get_physics_process_delta_time())
	velocity.x = _dash_dir.x * GameConfig.UNIT_MASTER_DASH_SPEED
	velocity.z = _dash_dir.z * GameConfig.UNIT_MASTER_DASH_SPEED
	return true

## ③ 后撤步：**敌方近战要对我出手**（或冲锋中的轻骑兵已经贴近）⇒ 撤到身后那条弧上。
## ⚠️ **2026-09-25 改为"有动画的滑行"**（用户："后撤步应有动画"）：位移从**瞬移**改成
## `UNIT_MASTER_BACKSTEP_MS`（200 ms）内从起点**平滑滑到**落点 —— 本函数因此有**两态**：
##   · `_backstep_until_ms > 0`：正在滑行 ⇒ 每帧插值位置，**返回 true**（这一帧由它接管，不跑走位 / 出手）；
##   · 否则：做触发判定，触发时**开一段滑行**（同样返回 true）。
## ⚠️ 滑行期间与结束后 `UNIT_MASTER_DASH_LOCK_MS`（300 ms）内**禁止冲刺**（`_can_master_dash()` 里的锁）。
## ⚠️ 本项目**没有骨骼动画**，所以"动画"= 看得见的位移（与拔刀斩的后撤段同一手法）。
func _tick_backstep(now: int) -> bool:
	if has_meta("afterimage"):
		return false
	if _backstep_until_ms > 0:
		var total := maxi(GameConfig.UNIT_MASTER_BACKSTEP_MS, 1)
		var t := 1.0 - float(maxi(_backstep_until_ms - now, 0)) / float(total)
		global_position = _backstep_from.lerp(_backstep_to, clampf(t, 0.0, 1.0))
		if now >= _backstep_until_ms:
			_backstep_until_ms = 0
			velocity = Vector3.ZERO
		return true
	if not alive or now < _backstep_cd_until_ms:
		return false
	if not _enemy_pressing_me():
		return false
	var back := global_transform.basis.z           ## 正后方 = **+Z**（本体正面是 −Z，见 `_face()` 的推导）
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return false
	back = back.normalized()
	## 用户："后撤至自身后方 7m、张角共 60° 的圆弧上" ⇒ 以正后方为轴，在 ±30° 内随机取一点
	var half := deg_to_rad(GameConfig.UNIT_MASTER_BACKSTEP_ARC_DEG * 0.5)
	var dir := back.rotated(Vector3.UP, randf_range(-half, half))
	var to := _clamp_into_arena(global_position + dir * GameConfig.UNIT_MASTER_BACKSTEP_DISTANCE)
	to.y = global_position.y
	_backstep_from = global_position
	_spawn_afterimage()
	_backstep_to = to
	_backstep_until_ms = now + GameConfig.UNIT_MASTER_BACKSTEP_MS
	_backstep_cd_until_ms = now + GameConfig.UNIT_MASTER_BACKSTEP_CD_MS + int(aid_mods.get("cd_add_ms", 0))
	_dash_lock_until_ms = now + GameConfig.UNIT_MASTER_BACKSTEP_MS + GameConfig.UNIT_MASTER_DASH_LOCK_MS
	_face(-dir, get_physics_process_delta_time())  ## 撤完仍面朝原来那一侧
	velocity.x = 0.0
	velocity.z = 0.0
	return true

## 有没有**敌方近战**正压着我打。两条判据取或：
##   ① 有敌人在 `is_winding_up_at(self)`（**已经进了出手窗口**、锁定的就是我）；
##   ② 有轻骑兵**正在冲锋**且已经贴近到 `UNIT_MASTER_BACKSTEP_CHARGE_RANGE` —— 用户点名的那种情况
##      （"如果为轻骑兵且正在冲锋则靠近他就后撤"）。
## ⚠️ 判据①刻意用**出手窗口**而不是"距离够得着"：后者会让它一有近战贴脸就无限后撤、永远不还手。
func _enemy_pressing_me() -> bool:
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team or other.is_burrowed():
			continue
		if other.is_winding_up_at(self, GameConfig.UNIT_MASTER_BACKSTEP_LEAD_MS):
			## 沙虫的扇形从 5 m 外就开始前摇。大师剑程只有 2.2 m，最后 150 ms 一撤就是 7 m，
			## 刀还没落下人已经退出去，单挑会一整场一刀不中。贴到自己的剑程里就站住砍。
			if other.is_burrower() and _target_valid() and target == other and surface_distance_to(other) <= attack_reach():
				continue
			return true
		if other._lance_until_ms > 0 and global_position.distance_to(other.global_position) \
				<= GameConfig.UNIT_MASTER_BACKSTEP_CHARGE_RANGE:
			return true
	return false

## ④ 拔刀斩：**冷却完成 + 有合法目标 + 锁定单位在 `UNIT_MASTER_IAI_RANGE`（5 m）以内**即可发动。
## ⚠️ **2026-09-25 用户："发动条件变为锁定单位在5m以内且冷却完成"** —— 此前**没有距离条件**
##（冷却一到、只要有目标就起手）⇒ 它从"半场外随时开大"变成**贴身技**。
func _can_iai(now: int) -> bool:
	if has_meta("afterimage"):
		return false
	if _iai_phase != Iai.NONE or now < _iai_cd_until_ms:
		return false
	if not _target_valid():
		return false
	return surface_distance_to(target) <= GameConfig.UNIT_MASTER_IAI_RANGE

## 发动：进入后撤段；同时把**整段技能的无敌**一次算好（用户："技能持续时间内无敌
##（在自身定身结束后解除无敌）"）—— 无敌截止 = 后撤 + 蓄力 + 位移 + 自身定身 四段之和。
## ⚠️ 冷却**在这里**起算（不是结束时）：被打断也照走，见 `_interrupt_skill()`。
func _start_iai(now: int) -> void:
	_iai_phase = Iai.RETREAT
	_iai_from_ms = now
	_iai_until_ms = now + GameConfig.UNIT_MASTER_IAI_RETREAT_MS
	_iai_cd_until_ms = now + GameConfig.UNIT_MASTER_IAI_CD_MS
	_iai_targets.clear()
	_iai_dash_from = global_position
	var back := global_transform.basis.z           ## 正后方 = **+Z**（本体正面是 −Z，见 `_face()` 的推导）
	back.y = 0.0
	_iai_dir = back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK
	## ⚠️ 这里填的是**后撤方向**（正后方）；蓄力段一定会把它改写成"朝锁定目标"
	## （目标在蓄力期间失效 ⇒ 技能当场作废，见 `_tick_iai()` 的 `Iai.CHARGE` 分支）。
	_iai_dash_to = _clamp_into_arena(global_position + _iai_dir * GameConfig.UNIT_MASTER_IAI_RETREAT)
	_invuln_until_ms = now + GameConfig.UNIT_MASTER_IAI_RETREAT_MS + GameConfig.UNIT_MASTER_IAI_CHARGE_MS \
		+ _iai_dash_ms() + GameConfig.UNIT_MASTER_IAI_SELF_ROOT_MS
	velocity = Vector3.ZERO
	## 技能全程**站定不能自主移动**，由各段自己写位置（走位交给技能）
	_state = State.IDLE

## 位移段时长（ms）：`35 m ÷ 70 m/s = 500 ms`（两个常量都在 `GameConfig.UNIT_MASTER_IAI_*`）。
func _iai_dash_ms() -> int:
	return int(round(GameConfig.UNIT_MASTER_IAI_DASH / GameConfig.UNIT_MASTER_IAI_DASH_SPEED * 1000.0))

## 拔刀斩的逐帧推进（四段共用）。返回值恒为 true —— 技能进行中**独占整帧**。
func _tick_iai(now: int) -> bool:
	match _iai_phase:
		Iai.RETREAT:
			## 后撤 10 m：**快速倒飞**（不是瞬移）—— 220 ms 内平滑退到落点，读得出"拉开距离再斩"
			var t := 1.0 - float(maxi(_iai_until_ms - now, 0)) / float(maxi(GameConfig.UNIT_MASTER_IAI_RETREAT_MS, 1))
			global_position = _iai_dash_from.lerp(_iai_dash_to, clampf(t, 0.0, 1.0))
			if now >= _iai_until_ms:
				_iai_phase = Iai.CHARGE
				_iai_until_ms = now + GameConfig.UNIT_MASTER_IAI_CHARGE_MS
				velocity = Vector3.ZERO
			return true
		Iai.CHARGE:
			## 蓄力 1 s：站定、面朝锁定目标。⚠️ **可被打断**（被眩晕 / 定身 ⇒ `_interrupt_skill()` 把整段作废）。
			## 锁定的人死了就换一个还活着的，蓄力接着走。场上没人了才把技能停掉。
			## 玩家操作时方向锁在按下的准星上，没有锁定目标也不取消。
			if piloted:
				var aim := _pilot_iai_dir
				if aim.length_squared() < 0.0001:
					aim = _pilot_flat_aim()
				_iai_dir = aim
				set_facing(_iai_dir)
				velocity = Vector3.ZERO
				if now >= _iai_until_ms:
					_iai_phase = Iai.DASH
					_iai_from_ms = now
					_iai_until_ms = now + _iai_dash_ms()
					_iai_dash_from = global_position
					_iai_dash_to = _clamp_into_arena(global_position + _iai_dir * GameConfig.UNIT_MASTER_IAI_DASH)
					_set_pass_all(true)
				return true
			if not _target_valid():
				_lock_nearest_target()
			if not _target_valid():
				_iai_phase = Iai.NONE
				return true
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.0001:
				_iai_dir = to_target.normalized()
				_face(_iai_dir, get_physics_process_delta_time())
			if now >= _iai_until_ms:
				_iai_phase = Iai.DASH
				_iai_from_ms = now
				_iai_until_ms = now + _iai_dash_ms()
				_iai_dash_from = global_position
				_iai_dash_to = _clamp_into_arena(global_position + _iai_dir * GameConfig.UNIT_MASTER_IAI_DASH)
				## **穿过所有单位**（用户："能够穿过所有单位"）—— 与轻骑兵冲刺共用同一套掩码
				_set_pass_all(true)
			return true
		Iai.DASH:
			var t2 := 1.0 - float(maxi(_iai_until_ms - now, 0)) / float(maxi(_iai_until_ms - _iai_from_ms, 1))
			var prev := global_position
			global_position = _iai_dash_from.lerp(_iai_dash_to, clampf(t2, 0.0, 1.0))
			_iai_mark_passed(prev, global_position)
			if now >= _iai_until_ms:
				_set_pass_all(false)
				## 落地：**自己也定身 1.5 s**（用户："移动完后自身也被定身1.5s"）。
				## ⚠️ **这里必须直接写 `_root_until_ms`，不能调 `apply_root()`** —— 后者会走
				## `_interrupt_skill()`，而那一支的作用正是"把拔刀斩整段作废" ⇒ 自己把自己打断，
				## 待结算的那几刀全丢。自己定身是**技能的一段**，不是外部施加的状态。
				_root_until_ms = maxi(_root_until_ms, now + GameConfig.UNIT_MASTER_IAI_SELF_ROOT_MS)
				_iai_phase = Iai.SELF_ROOT
				_iai_until_ms = now + GameConfig.UNIT_MASTER_IAI_SELF_ROOT_MS
				_iai_slash_until_ms = now + IAI_SLASH_FX_MS
				velocity = Vector3.ZERO
			return true
		Iai.SELF_ROOT:
			## 自己定身期间站定不动，等**被穿过那些人的定身先结束** ⇒ 逐个结算"定身结束那一刀"。
			## ⚠️ 本段由 `_physics_process()` 在"无法行动"那道闸门**之外**调用（见那里的注释）：
			## 定身会让 `_think()` 整个不跑，而这几刀必须在定身期间结算。
			_iai_settle_targets(now)
			if _iai_targets.is_empty() and now >= _iai_until_ms:
				_iai_phase = Iai.NONE
			return true
	return false

## 把"这一帧扫过的那一小段"里的敌人记进待结算表。判定宽度 `UNIT_MASTER_IAI_WIDTH` ⇒ 以自身为轴 ±半宽。
## 每人只记一次（`_iai_has()`），并**当场**给它上定身 1 s —— 伤害要等定身结束才结算（见 `_iai_settle_targets()`）。
func _iai_mark_passed(from: Vector3, to: Vector3) -> void:
	var half := GameConfig.UNIT_MASTER_IAI_WIDTH * 0.5
	var breath := tech_def("thunder_breath")
	if not breath.is_empty():
		half *= float(breath.get("width_mult", 2.0))
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team or other.is_burrowed() or _iai_has(other):
			continue
		## 2 m 是斩击带的宽度。身体有半径，中心在带外、身子仍可能被切到。巨物（沙虫半宽 1.41 m）尤其明显。
		var limit := half + GameConfig.body_radius(other.type_id)
		if _distance_to_segment(other.global_position, from, to) > limit:
			continue
		## 定身 1 s（用户："立即使所有被穿过的敌方单位（宽度为2m）定身1s（**包括boss单位**）"）。
		## ⚠️ 走 `apply_root()`：它**不走** `is_stun_immune()` 那道闸门 ⇒ 连沙虫、投石车
		## 与另一只武士大师都定得住（这正是用户点名要的，见 `apply_root()` 的注释）。
		other.apply_root(GameConfig.UNIT_MASTER_IAI_ROOT_ENEMY_MS)
		_iai_targets.append({"unit": other, "due_ms": Time.get_ticks_msec() + GameConfig.UNIT_MASTER_IAI_ROOT_ENEMY_MS})

func _iai_has(other: Unit3D) -> bool:
	for entry in _iai_targets:
		var raw: Variant = entry["unit"]
		if is_instance_valid(raw) and raw == other:
			return true
	return false

## 逐个结算"定身结束那一刀"：`300 + 目标血上限 × 0.25`（用户："造成300+x（"x"的值为被定身单位
## 血上限的四分之一）的伤害"）。⚠️ 目标在这 1 s 里死了 / 被释放就**跳过**（不补刀、不报错）。
func _iai_settle_targets(now: int) -> void:
	var kept := []
	for entry in _iai_targets:
		var raw: Variant = entry["unit"]
		if not is_instance_valid(raw):
			continue
		var other := raw as Unit3D
		if other == null or not other.alive:
			continue
		if now < int(entry["due_ms"]):
			kept.append(entry)
			continue
		var amount: float = GameConfig.UNIT_MASTER_IAI_DAMAGE \
			+ other.max_hp * GameConfig.UNIT_MASTER_IAI_DAMAGE_HP_RATIO
		var breath := tech_def("thunder_breath")
		if not breath.is_empty():
			amount *= float(breath.get("damage_mult", 2.0))
		other.apply_hit(amount, self)
		Events.fx_request.emit("iai_slash", other.global_position)
	_iai_targets = kept

## 点到线段的最短距离（**只看 XZ 平面**）：拔刀斩的宽度是地面上的横向宽度，与高度无关。
func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := Vector3(point.x - a.x, 0.0, point.z - a.z)
	var ba := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var denom := ba.length_squared()
	if denom < 0.0001:
		return pa.length()
	var t := clampf(pa.dot(ba) / denom, 0.0, 1.0)
	return (pa - ba * t).length()

## 把坐标夹进场地内（四周各留 1 m）：后撤步 / 拔刀斩的位移都可能越过边界墙，
## 而墙外**没有地板** —— 退出去会直接掉出世界（`04_physics.md#2.2` 的边界处理是给走位用的，管不到瞬移）。
func _clamp_into_arena(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -GameConfig.ARENA_HALF_X + 1.0, GameConfig.ARENA_HALF_X - 1.0)
	p.z = clampf(p.z, -GameConfig.ARENA_HALF_Z + 1.0, GameConfig.ARENA_HALF_Z - 1.0)
	return p

## 这个单位**是不是正要对我出手**（供武士大师的「后撤步」判定"敌方近战要对自己发起攻击"，2026-09-25）。
## 判据 = 四件事同时成立：
##   ① 它锁定的就是我；② 它是**近战**（远程兵走过来放箭，后撤步没有意义）；③ 我确实在它的出手距离内；
##   ④ 它的出手动画正处在**命中帧之前**那一段（`phase ∈ [0, windup]`）。
## ⚠️ **第 ④ 条是踩过坑才这么写的**：第一版用 `_striking`（= 前摇开始 → 收招 55%，约占攻击周期的 90%），
##    于是"刚砍过一刀、正在收招"的敌人也算"要出手" ⇒ 武士大师每贴上去就被吓退，
##    实测 13 秒里**风筝了 4 个来回、一刀没还**。收到"命中帧之前"（剑盾兵约 214/714 ms ≈ 30%）之后，
##    它才有还手的窗口 —— 这才是用户那句"**要**对自己发起攻击时"的意思。
## ⚠️ 动画链是**按周期回绕**的（见 `_tick_attack()`）：`phase` 每 `interval` 归零一次，
##    所以"下一刀"的窗口会自动重现，不需要额外状态。
## ⚠️ `lead_ms > 0` ⇒ **只认"命中帧前 `lead_ms` 以内"那一段**（2026-09-25 第四轮，用户裁决"**选 A**"）：
## 默认 0 = 整个出手窗口都算（历史行为）；武士大师的「后撤步」传
## `UNIT_MASTER_BACKSTEP_LEAD_MS`（150）—— 治的是"沙虫 600 ms 长前摇一开就把大师赶走、它永远贴不上去"
##（实测 30 s 双方 0 伤害）。⚠️ 若 `lead_ms` 大于整个前摇，则整段都算"临近"（判据退化成默认行为，不会出错）
## —— ⚠️ **2026-09-27 第十一轮：这句注释写的是"应该怎样"，而当时代码写的是另一回事**（短前摇时窗口
## 反而塌成几毫秒）⇒ 本轮按这句注释修好了，见函数体里的说明。
func is_winding_up_at(who: Unit3D, lead_ms: int = 0) -> bool:
	## ⚠️ **2026-09-25 第三轮（用户："武士大师不会对心灵腐化师的攻击后撤"）**：**心灵腐化师不算"近战要出手"**。
	## 根因：它的 `is_ranged` 是 false（激光没有弹体、走单体直接结算）而射程 20 m —— 若不排除它，
	## `_enemy_pressing_me()` 会在 **23.6 m 外**就把大师判成"有人贴着我前摇"⇒ 大师对着半场外的一道激光
	## 一路后撤（这正是"后撤步把自己推走"那条 bug 的同一个源头）。⚠️ 判据用 `is_corruptor()` 而不是"射程大小"：
	## 用户口径是"**不对心灵腐化师的攻击后撤**"，把它写清比猜一个距离阈值稳。
	## ⚠️ **2026-09-27 第十二轮（用户："湮灭之瞳的攻击不会触发武士大师的后撤"）**：判据由
	## `is_corruptor()` 放宽到 **`is_sustained_beam()`**（= 腐化师 **∪** 湮灭之瞳）—— 两者是同一族
	##（都是"无弹体 + 超远射程 + 持续照射"），对后撤步的失效方式逐字相同：湮灭之瞳的
	## `attack_reach()` 是 **29.5 m**，不排除的话大师在**小半场之外**就开始后撤 ✗。
	## 用户先要"能闪"（第十一轮按通用修法把窗口算对了）、再要"别对这道光后撤"（本轮）——
	## **两件事不冲突**：窗口那条修的是"**该闪不闪**"（对其它短前摇对手仍然生效），
	## 这一条修的是"**不该闪的别闪**"（对持续照射族整体豁免）。
	if not alive or is_ranged() or is_sustained_beam() or target != who or _swing_from_ms <= 0:
		return false
	var interval_ms := int(round(_attack_interval() * 1000.0))
	if interval_ms <= 0:
		return false
	var windup_ms := int(round(_attack_interval() * GameConfig.windup_ratio(type_id) * 1000.0))
	var phase := posmod(Time.get_ticks_msec() - _swing_from_ms, interval_ms)
	## ⚠️ 2026-09-25 第四轮（方案 A）：`lead_ms > 0` 时只认"命中帧前 lead_ms 以内"那一段 ——
	## 也就是"这一刀真的快落下来了"才闪，而不是"它一开始抬手我就闪"。
	## ⚠️ **2026-09-27 第十一轮修 bug（用户："武士大师不会闪避湮灭之瞳的攻击"）**：
	## 旧写法是 `phase ∈ [windup − lead, windup]`，而 `phase = posmod(...) ≥ 0` ⇒ **只要 `windup < lead`
	## 下界就是负数、永远不成立**，窗口塌成"只剩命中帧那一瞬"。湮灭之瞳的 `windup_ratio` 是 **0.02**
	##（间隔 333 ms ⇒ 前摇只有 **6.7 ms**）⇒ 实际可闪窗口 = **6.7 / 333 ≈ 2 %** ⇒ 大师**几乎永远判不到**
	##（长前摇的对手——长矛兵 / 沙虫等——因为 `windup > lead` 一直是对的，所以这个 bug 以前没暴露）。
	## 正解：**把判据改成"距下一次命中帧还有多久"**（`posmod` 天生处理回绕）——
	##   窗口 = `until_hit ≤ lead_ms`，即"接下来 lead_ms 之内会挨这一下"。
	## ⚠️ 长前摇对局**逐位不变**（旧式与新式在 `windup ≥ lead` 时等价：都取命中帧前那 lead_ms）；
	## 变的是短前摇（`windup < lead`）与"命中后回绕到下一轮"的那一小段 —— 两种情况以前都**漏判**。
	var until_hit := posmod(windup_ms - phase, interval_ms)
	if until_hit > lead_ms:
		return false
	return surface_distance_to(who) <= attack_reach()

## 火箭跳跃（狂战士，2026-09-18 R3）：前方较远处有敌人、自身不在出手、冷却已结束时发动。
func _can_jump() -> bool:
	if _striking:
		return false
	if Time.get_ticks_msec() < _skill_cd_until_ms:
		return false
	if not _target_valid():
		return false
	## 已经贴到出手距离就别跳了 —— "跳跃过去"是**拉近**手段，
	## 否则冷却只有 2 s 时会一直原地起跳、永远不挥斧（2026-09-18 R3 实测踩到过）。
	if surface_distance_to(target) <= attack_reach():
		return false
	var d := global_position.distance_to(target.global_position)
	## 2026-09-19 用户第四条：跳跃距离改成按目标距离自适应 ⇒ 太近时那一跳没有意义
	##（落点会越过目标），所以触发下限 = `UNIT_JUMP_MIN_DISTANCE`（距离下限）+ `UNIT_JUMP_LAND_GAP`
	##（落点与目标之间的贴身间隙）—— 两个常量一起把关，保证实际跳跃距离**不会低于下限**。
	if d < GameConfig.UNIT_JUMP_MIN_DISTANCE + GameConfig.UNIT_JUMP_LAND_GAP:
		return false
	return d <= GameConfig.UNIT_JUMP_RANGE * tech_jump_mult()

## 起跳：水平分量 = **自适应距离** ÷ 滞空时间，上抛分量 = ½·g·滞空
##（之后不再干预竖直速度，抛物线由 `_apply_gravity` 画完）；同时开启免疫窗口。
## ⚠️ 2026-09-19 用户第四条：距离不再固定、也**不再"第二次起减半"** ——
## 每次都以"起跳那一刻与目标的距离 − `UNIT_JUMP_LAND_GAP`"为准（下限 `UNIT_JUMP_MIN_DISTANCE`），
## 于是第一次与第二次完全同规则。⚠️ 距离在**起跳帧**取一次就定住（空中不追人，与冲刺的"每帧重定向"不同）。
func _start_jump() -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var d := to_target.length()
	if d < 0.0001:
		return
	var dir := to_target / d
	var air_s := float(GameConfig.UNIT_JUMP_AIR_MS) / 1000.0
	var travel := clampf(d - GameConfig.UNIT_JUMP_LAND_GAP,
			GameConfig.UNIT_JUMP_MIN_DISTANCE, GameConfig.UNIT_JUMP_RANGE * tech_jump_mult())
	travel = minf(travel, d)
	_jump_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_JUMP_AIR_MS
	_invuln_until_ms = _jump_until_ms + GameConfig.UNIT_JUMP_INVULN_MS
	_skill_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_JUMP_CD_MS
	_set_ally_ghost(true)              ## 2026-09-19 用户第六条：滞空期间穿过队友
	## 上抛分量按 `_apply_gravity()` 用的同一个重力源算（项目设置的 default_gravity，18 m/s²），
	## 不另开常量 —— 否则抛物线与重力会各用一套值（2026-09-18 R3：曾误写成不存在的 `GameConfig.GRAVITY`，
	## 运行时直接报错并把帧卡在调试器里）。
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	velocity = dir * (travel / air_s) + Vector3.UP * (0.5 * g * air_s)
	_face(dir, 0.016)
	## 空中不再自主移动：由 `_tick_skill()` 返回 true 接管，但水平速度要被"锁住"——
	## 否则 `_tick_move` 不会跑（技能接管），速度会被重力的 y 分量带走而水平不变，正好是对的。
	Events.fx_request.emit("unit_jump", global_position)

## 是否在免疫窗口内（火箭跳跃的滞空 + 落地 0.5 s）。
## ⚠️ 2026-09-19：潜地（沙虫）**共用这一套**——用户口径"拥有无敌（狂战士跳跃同款）"⇒ 直接并进来，
## 于是"所有伤害源都走 `apply_hit()`"这条既有性质自动覆盖潜地，不必另开一处伤害豁免。
func is_invulnerable() -> bool:
	## ⚠️ **2026-09-25 第三轮：影子形态并进来**（用户裁决"无敌 + 不可被锁定"）——
	## 与潜地同一种做法（都靠这一道闸门覆盖"所有伤害源"）。
	return Time.get_ticks_msec() < _invuln_until_ms or is_burrowed() or is_in_shadow_form()

## 触发条件：目标在 `UNIT_CHARGE_RANGE` 内、冷却已结束、且自身不在出手动作中
func _can_charge() -> bool:
	if _striking:
		return false
	if Time.get_ticks_msec() < _skill_cd_until_ms:
		return false
	if not _target_valid():
		return false
	return global_position.distance_to(target.global_position) <= GameConfig.UNIT_CHARGE_RANGE

# ---------------------------------------------------------------- 冲锋（轻骑兵（矛）技能，2026-09-25 新增）
## 触发条件（用户口径）：**距离锁定对象 7 m 时发动**，且冲锋冷却已结束（冷却**从技能结束起算**）。
## ⚠️ **额度是与冷却并列的第二道闸门**（2026-09-25 第三条修 bug ——
## 用户："轻骑兵冲锋最多两次，但是我发现他能冲锋三次"）。
## 根因：这里原先**只比冷却与距离**，`UNIT_LANCE_CHARGES_MAX` 只在 `_lance_patrol()` 里被查过 ——
## 而那个函数管的是"**冷却期要不要游走**"，不是"能不能发动"。额度一旦用完：
##   · `_lance_patrol()` 返回 false ⇒ 它改用**常规走位**，于是会主动压进 7 m；
##   · 冷却一结束，`_can_lance()` 只看"冷却 + 距离" ⇒ **又冲一次**；
##   · 而 `_start_lance()` 里那句 `maxi(_lance_charges_left - 1, 0)` 把计数**钳在 0**，
##     所以计数既不拦、也不再变小 ⇒ 表现就是"每场能冲第 3 次、第 4 次……"。
## ⇒ 修法：**把额度也判在发动闸门上**（`_lance_patrol()` 里那道保留，它还负责"不再游走"）。
## ⚠️ 扣次数的时机**不在这里、也不在正常结束时**，而在 `_start_lance()`（**发动即扣**）——
## 这样"冲刺中途阵亡"不退次数（人都没了），也堵住"反复发动 / 反复退次数"的漏洞。
## ⚠️ **2026-09-25 第五条的连带结论**：眩晕**不再**影响额度 —— 语义是"暂停"（表停走），
## 冲刺既不作废也不退还（见 `apply_stun()`）⇒ **扣点只有 `_start_lance()` 一处，没有任何退还路径**。
func _can_lance() -> bool:
	if _lance_charges_left <= 0:
		return false
	if Time.get_ticks_msec() < _skill_cd_until_ms:
		return false
	if not _target_valid():
		return false
	return global_position.distance_to(target.global_position) <= GameConfig.UNIT_LANCE_CHARGE_RANGE

## 发动冲刺：记下方向与截止时刻、**扣一次额度**、开启"穿过所有单位"掩码。
## 速度**不在这里**给（见 `_lance_tick()` 的助跑口径）。
func _start_lance() -> void:
	var now := Time.get_ticks_msec()
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	_lance_until_ms = now + _lance_duration_ms()
	_lance_dir = to_target.normalized()
	_lance_sped_up = false
	_lance_stopped = false
	_lance_charges_left = maxi(_lance_charges_left - 1, 0)
	_lance_hit_units.clear()
	_lance_box_pending.clear()
	## 清 0 ⇒ 发动那一帧就允许第一次矩形结算（"起步就撞上"不会被延迟一个节拍）
	_lance_next_box_ms = 0
	_lance_patrol_turn_ms = now + GameConfig.UNIT_LANCE_PATROL_TURN_MS
	_set_pass_all(true)
	_face(_lance_dir, get_physics_process_delta_time())
	## 冲锋起手音（2026-09-25，用户："轻骑兵矛开始冲锋的音效已引进"）：走**既有的** `fx_request`
	##（与上面的 `unit_jump` 同一支），**不新增信号** —— `06_audio.md#3` 的口径是"事件名只是音频层
	## 内部的映射键"。⚠️ 素材只覆盖**起手**那一下（§6 裁定过：这条音效要"起手 / 持续循环 / 收尾"
	## 三段，后两段还没有素材），所以这里只在发动瞬间发一次。
	Events.fx_request.emit("lance_charge", global_position)

## 冲刺主流程。返回 true = 这一帧由技能接管（不跑常规走位 / 攻击）。
## 结束只有两种：① **8 s 到点**（2026-09-25：3 s → 10 s → 8 s，见 `UNIT_LANCE_CHARGE_MS`）；
## ② **全场没有可打的敌人**（全灭 / 只剩潜地的沙虫）。
## ⚠️ **2026-09-25 第九条（用户："轻骑兵有时候冲了一会儿就不冲了，应冲满10秒"）**：
## 这里原先写的是"被锁定的对象中途死亡 / 失效 ⇒ `_end_lance()`"，**太急** ——
## `_lock_nearest_target()` 只在**每帧末尾**跑一次，而**同一帧里排在它前面的单位**（另一个轻骑兵 /
## 任何一次出手）完全可能把这个目标打死 ⇒ 轮到它这一帧时 `target` 已经是个死单位 ⇒ **冲刺当场结束**。
## 探针实测（3 轻骑兵 + 4 短弓手）：结束前 6 帧一切正常（`_target_valid=true`、目标活着、还剩 **9252 ms**），
## 下一帧就断了，实跑 **44 帧**（应 600）—— 与"冲了多久"无关，只取决于**目标有没有被别人抢杀**，
## 所以表现为"**有时候**"。
## ⇒ 现在改成：**失效就当场重锁**，重锁后仍无可打目标才收手。
## ⚠️ **不要**退回"失效即结束"：那会让"队友抢了它的人头"变成"它的技能被取消"。
func _lance_tick() -> bool:
	var now := Time.get_ticks_msec()
	if now >= _lance_until_ms:
		_end_lance()
		return true
	if piloted:
		_set_pass_all(true)
		## 冲刺跟着当前准星转，不再锁死按下那一瞬间的方向。
		_lance_dir = _pilot_flat_aim()
		velocity.x = _lance_dir.x * GameConfig.UNIT_LANCE_CHARGE_SPEED
		velocity.z = _lance_dir.z * GameConfig.UNIT_LANCE_CHARGE_SPEED
		_face(_lance_dir, get_physics_process_delta_time())
		_lance_scan_box()
		if now >= _lance_next_box_ms:
			_lance_next_box_ms = now + GameConfig.UNIT_LANCE_BOX_TICK_MS
			_lance_settle_box()
		return true
	## 锁定目标失效 ⇒ **就地重锁**（不再直接结束）。`_lock_nearest_target()` 是幂等的：
	## 最近者没变时它原样返回，所以这里每帧判一次也不会有额外开销。
	if not _target_valid():
		_lock_nearest_target()
		## 本帧开头的最近目标表还指着刚死的那个人。表没刷新时再按活人搜一次，
		## 否则队友抢杀会让这一次冲锋当场结束。
		if not _target_valid():
			var arena := _arena()
			if arena != null:
				var fresh: Unit3D = arena.nearest_enemy(self, attack_min_reach(), null)
				if fresh != null and is_instance_valid(fresh) and fresh.alive:
					target = fresh
					_striking = false
		## 重锁之后仍然没有可打的敌人（全灭 / 只剩潜地的沙虫）⇒ 这才是真正该收手的时候
		if not _target_valid():
			_end_lance()
			return true
	## 到这里目标一定是有效的 ⇒ 可以安全取"朝目标的水平向量"
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	## ⚠️ **"暂停"语义的配套**（2026-09-25 第五条）：眩晕期间 `apply_stun()` 会把"穿过所有单位"的掩码
	## **收掉**（不这么做的话，定住不动的单位反而"打不中" —— 见那里的注释）。
	## 所以**重新接管的第一帧必须把掩码戴回去**，否则"晕完接着冲"会退化成"晕完接着冲、但一路被人挡住"。
	## ⚠️ `_set_pass_all()` 幂等，而且会顺手清掉待还原请求（`_pass_clear_due_ms = 0`）⇒ 每帧调一次最省心。
	_set_pass_all(true)
	var delta := get_physics_process_delta_time()
	## 到目标的水平距离：**转向限速**（够不够得到 ⇒ 180 / 270）与"是否提速"都要用它，所以先算出来。
	var to_target_dist := to_target.length()
	## 限速转向：朝目标走，但这一帧至多转 `_lance_turn_deg_per_sec(距离) × delta`。
	## ⚠️ 追踪的是**目标当前位置**（不是锁定点）—— 这正是"能转弯"的含义。
	## ⚠️ 2026-09-25 第十条：限速不再是固定 180 —— **目标超出矩形可及范围时切 270** 去把圈子收紧。
	if to_target.length_squared() > 0.0001:
		_lance_dir = _steer_toward(_lance_dir, to_target, delta,
				_lance_turn_deg_per_sec(to_target_dist))
	## ⚠️ **2026-09-25 第二条修 bug（用户："轻骑兵依旧冲到对面面前就停下了"）**：
	## **两条停步判据全部删除**，冲刺期间**全程保持移动、不再停步**。沿革：
	##   · 最初（有碰撞体挡着的年代）：撞到就停 —— 合理，因为根本冲不过去；
	##   · 改成"穿过所有单位"之后（判定体停用）：加过"掉到身后就停"，结果**一贴近就停**（掠过时点积必然转负）；
	##   · 再改成"又掉到身后又贴到 1.20 m 才停"：仍然**在贴到 1.70 m（矩形半长）时就停住** —— 用户还是那句
	##     "冲到对面面前就停下了"。
	## ⇒ 结论：**只要还在"穿"的语义里，任何停步都是错的**。现在改为**不停**：
	## 目标跑到身后时由 `_steer_toward()` 的**转弯限速**（180°/s，够不到时切 270°/s）自然把它绕回来 ——
	## 8 s 内它至多能转 **1440°（4 整圈）**，足够绕几个回环再压上去，观感是"冲过去、兜回来、再冲一趟"。
	## （2026-09-25：时长 3 s → 10 s → 8 s ⇒ 可转角度同步由 540° 变 1800°、再变 **1440°**。）
	## ⚠️ 因此**不要**再往这里加停步条件（两个方向都试过了，都会变成"停在对手面前"）。
	## ⚠️ `_lance_stopped` 成员**保留但恒为 false**（只为 `_mcp_state()` 与回归探针的字段兼容），
	## 不要再让它变成移动开关。
	_lance_stopped = false
	if not _lance_sped_up and to_target_dist <= attack_reach():
		_lance_sped_up = true
	var speed := GameConfig.UNIT_LANCE_CHARGE_SPEED if _lance_sped_up else current_speed()
	velocity.x = _lance_dir.x * speed
	velocity.z = _lance_dir.z * speed
	_face(_lance_dir, delta)
	## ⚠️ **2026-09-25 修 bug（用户："有时候轻骑兵明显冲刺到了但没有反应"）**：矩形判定拆成两步 ——
	## **`_lance_scan_box()` 每帧跑**（只登记"谁进过框"，不掉血），**`_lance_settle_box()` 只在跳拍帧跑**（掉血）。
	## 根因：14 m/s 下**一跳之间要前进 4.2 m**，而目标留在 3.4 m 长的矩形里只有 **0.243 s** ⇒
	## 只在跳拍帧扫描时，那 0.243 s 若整个落在两跳之间就**一次都采不到**（= 明明冲过去了却没反应）。
	## 现在"**谁被扫到**"逐帧不漏，"**什么时候掉血**"仍旧是 `UNIT_LANCE_BOX_TICK_MS`（300 ms）一跳
	##（用户口径："冲刺期间伤害间隔 0.3 s（**类似于普通攻击的攻击速度**）"）。
	## ⚠️ 判定仍在**移动之前**（判的是"进入矩形的那一刻"，与观感一致：先看见人冲过来，再被撞飞）；
	## ⚠️ 第一跳在发动那一帧就发生（`_start_lance()` 把 `_lance_next_box_ms` 清 0）。
	_lance_scan_box()
	if now >= _lance_next_box_ms:
		_lance_next_box_ms = now + GameConfig.UNIT_LANCE_BOX_TICK_MS
		_lance_settle_box()
	return true

## 结束冲刺：清掉冲刺态、**收掉"穿过所有单位"掩码**，并把冷却**从这一刻**起算
##（用户明说"冷却 5s（技能持续时间结束后开始计算）"）。
func _end_lance() -> void:
	_lance_until_ms = 0
	_lance_sped_up = false
	_lance_stopped = false
	_lance_hit_units.clear()
	_lance_box_pending.clear()
	## ⚠️ **不直接 `_set_pass_all(false)`**：冲刺的语义是"穿过所有单位"，结束那一刻可能正和对手重叠，
	## 立刻恢复判定体会被引擎的穿透修正弹开 ⇒ 走**延时还原**（见 `_release_pass_all()`）。
	_release_pass_all()
	_lance_patrol_turn_ms = Time.get_ticks_msec() + GameConfig.UNIT_LANCE_PATROL_TURN_MS
	_skill_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_LANCE_CD_MS

## 「野马」：持续时间减半。没有这条科技就是面板上的 8 s。
func _lance_duration_ms() -> int:
	var ms := GameConfig.UNIT_LANCE_CHARGE_MS
	var row := tech_def("wild_horse")
	if row.is_empty():
		return ms
	return maxi(int(round(float(ms) * float(row.get("duration_mult", 1.0)))), 1)

## 「野马」：冲锋打出去的那一下（基础 + 速度附加）翻倍。
func _lance_hit_mult() -> float:
	var row := tech_def("wild_horse")
	if row.is_empty():
		return 1.0
	return float(row.get("damage_mult", 1.0))

## 前方矩形（**宽 `UNIT_LANCE_BOX_WIDTH` × 长 `UNIT_LANCE_BOX_LENGTH`**）的**逐帧扫描**：只登记，不掉血。
##   · 轴：`_lance_dir`（冲锋方向，世界 XZ）；起点：自身原点（y = 0 平面，长度量的是**水平面内**的前方，
##     不含高度 —— 与近战 / 扇形同一条写法）；
##   · 只登记**敌方**：与"只打敌方"的既有口径一致（扇形攻击 / 炎爆爆炸都只打敌方）；潜地单位跳过
##     （与索敌 / 扇形 / 爆炸同一条既有口径）；
##   · 进框的人记进 `_lance_box_pending`，等跳拍帧由 `_lance_settle_box()` 统一结算；
##   · **离开矩形就重置**：`_lance_hit_units` 只保留"此刻还在框里"的人 ⇒ 出去再进来可以再吃一次。
func _lance_scan_box() -> void:
	var arena := _arena()
	if arena == null:
		return
	var forward := Vector3(_lance_dir.x, 0.0, _lance_dir.z)
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var half_width := GameConfig.UNIT_LANCE_BOX_WIDTH * 0.5
	var inside := {}
	## ⚠️ 必须显式标注类型：`_arena()` 返回的是无类型的 `Node`，所以 `units_of_team()` 的返回值
	## 在编译器眼里是 `Variant`，用 `:=` 推断会直接报 "Cannot infer the type"。
	var reach := GameConfig.UNIT_LANCE_BOX_LENGTH + GameConfig.UNIT_LANCE_BOX_WIDTH
	var candidates: Array = arena.units_near(global_position, reach) if arena.has_method("units_near") else arena.units_of_team(1 - team)
	for node in candidates:
		var other := node as Unit3D
		if other == null or not other.alive or other.team == team:
			continue
		if other.is_burrowed():
			continue
		var offset := other.global_position - global_position
		offset.y = 0.0
		var along := offset.dot(forward)
		if along < 0.0 or along > GameConfig.UNIT_LANCE_BOX_LENGTH:
			continue
		if absf(offset.dot(Vector3(-forward.z, 0.0, forward.x))) > half_width:
			continue
		inside[other] = true
		## 已经结算过、且还在框里的人不再重复登记（"每个进入者只吃一次"）；
		## 还没结算过的人进 `pending` —— **哪怕他下一帧就出框**，也照样在跳拍帧吃到这一下。
		if not _lance_hit_units.has(other) and not _lance_box_pending.has(other):
			_lance_box_pending[other] = true
	## 离场重置：把"已经不在框里"的人从"这一轮已结算"名单里摘掉（出去再进来可以再吃一次）。
	for node in _lance_hit_units.keys():
		if not inside.has(node):
			_lance_hit_units.erase(node)

## 到跳拍帧才跑：把 `_lance_box_pending` 里的人**一次性**结算掉（伤害 + 击退），然后清空。
##   · 伤害 = **基础伤害 40**（= `PROFILES["lightcav"]["damage"]`）+ **附加伤害**
##     （= `UNIT_LANCE_SPEED_BONUS_PER_MS` × 被撞者与自己在**冲锋轴**上的相对速度）；
##   · 击退数值 3（`UNIT_LANCE_HIT_KNOCKBACK`）；
##   · **对象不限锁定目标**（用户口径："只要有单位在攻击范围内就会造成伤害，不一定要对锁定目标"）——
##     矩形里所有敌方都算，这一点在扫描时就定好了。
func _lance_settle_box() -> void:
	var forward := Vector3(_lance_dir.x, 0.0, _lance_dir.z)
	if forward.length_squared() < 0.0001:
		_lance_box_pending.clear()
		return
	forward = forward.normalized()
	for key in _lance_box_pending.keys():
		## ⚠️ 顺序不能反：`is_instance_valid()` 必须**先于** `as Unit3D`，否则对着已释放的对象做转换会
		## 直接抛 "Trying to cast a freed object"、把调用方整个打断（探针里踩过一次）。
		if not is_instance_valid(key):
			continue
		var other := key as Unit3D
		if other == null or not other.alive or other.team == team or other.is_burrowed():
			continue
		_lance_hit_units[other] = true
		_lance_hit_total += 1
		var closing := absf((velocity - other.velocity).dot(forward))
		var bonus := GameConfig.UNIT_LANCE_SPEED_BONUS_PER_MS * closing
		var knock := forward * GameConfig.KNOCKBACK_SPEED * GameConfig.UNIT_LANCE_HIT_KNOCKBACK
		other.apply_hit((GameConfig.hit_damage(type_id) + bonus) * _lance_hit_mult(), self, knock)
	_lance_box_pending.clear()

## 冷却期间的游走（**2026-09-25 整条重做**，用户："轻骑兵游走逻辑修改：**至少 10m 且尽量远离**"）。
## 返回 true = 这一帧由游走接管（跳过常规走位 / 攻击）。
## 口径（三条判据，按顺序）：
##   ⓪ **额度用完** ⇒ 返回 false（用户："额度用完就只剩平 A，**且不再游走**"）——
##      于是它退化为普通近战：走常规走位、只打平 A，不再保持距离；
##   ① **冷却还没结束** ⇒ 在 [`INNER`, `OUTER`] = [**10.0**, 16.0] m 里游走：
##      比 10 m 更近就**往远退**（用户："至少 10m 且尽量远离"）、比 16 m 更远就**横向来回**不再后退
##      （⚠️ **不往回靠近**：那会与"尽量远离"矛盾；上限只是防止无界后退把对局拖成僵持）；
##   ② **冷却已结束** ⇒ 返回 false，把这一帧交回常规走位 ——
##      只有这时它才会主动压进 7 m 去发动下一次冲刺。
##      ⚠️ **① 必须排在 ② 之前**：否则"冷却已结束"会被游走拦住，
##      而游走下限 10 m > 触发距离 7 m ⇒ **技能再也发不出来**（旧实现踩过的同类死局）。
## ⚠️ **与旧版的根本差别（连带事实，务必知道）**：旧版是"窄环带 [5.0, 8.6]、贴边待命"，
## 新版的游走下限 **10 m > 触发距离 7 m** ⇒ **冷却期内它永远够不着、也就永远不接敌**。
## 因此它的节奏变成：**退到 10 m 外待机 → 冷却一结束立刻压进 7 m 冲一次 → 冲完再退开**
##（2026-09-25 第四条起**每场只有 1 次**，见 `UNIT_LANCE_CHARGES_MAX`；⚠️ 第五条起眩晕只是"暂停"、不退额度）。
## ⚠️ 与 `04_physics.md#3.2` 的"射程外前进、射程内站定"是**刻意的例外**：
## 它刻意不贴上去，代价是冷却期完全不参与输出。
## ⚠️ 方向盘也**受同一个转弯限速**（`_steer_toward()`）：不能再靠瞬时转向把绕行做成直角折返。
func _lance_patrol() -> bool:
	if not _target_valid():
		return false
	if _lance_charges_left <= 0:
		return false                    ## ⓪ 额度用完 ⇒ 只剩平 A，不再游走
	if Time.get_ticks_msec() >= _skill_cd_until_ms:
		return false                    ## ② 冷却结束 ⇒ 交回常规走位，去把距离压进 7 m
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < 0.0001:
		return true
	var dir := to_target / dist
	var now := Time.get_ticks_msec()
	if now >= _lance_patrol_turn_ms:
		_lance_patrol_side = -_lance_patrol_side
		_lance_patrol_turn_ms = now + GameConfig.UNIT_LANCE_PATROL_TURN_MS
	var delta := get_physics_process_delta_time()
	var move_dir := dir
	if dist < GameConfig.UNIT_LANCE_PATROL_INNER:
		move_dir = -dir                                    ## 太近（< 10 m）⇒ 往远退
	else:
		move_dir = Vector3(-dir.z, 0.0, dir.x) * _lance_patrol_side   ## ≥ 10 m ⇒ 横向来回，不再靠近
	## 转弯限速：游走也受它约束（用户："轻骑兵在转弯时每秒最多旋转 180°"）
	move_dir = _steer_toward(velocity, move_dir, delta, GameConfig.UNIT_LANCE_TURN_DEG_PER_SEC)
	_face(move_dir, delta)
	velocity.x = move_dir.x * current_speed()
	velocity.z = move_dir.z * current_speed()
	return true


## 冲锋：朝目标直线冲（每帧重算方向 = 简单追踪），撞到**任意敌人**即结算并结束。
## 用"距离 = `attack_reach()`"判定撞击，与近战命中同源，不另开一套碰撞判定。
func _charge_tick() -> void:
	if _pilot_charge_dir.length_squared() > 0.0001:
		_pilot_charge_tick()
		return
	if not _target_valid():
		_charge_until_ms = 0
		_release_ally_ghost()
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var d := to_target.length()
	if d < 0.0001:
		_charge_until_ms = 0
		_release_ally_ghost()
		return
	var dir := to_target / d
	velocity.x = dir.x * GameConfig.UNIT_CHARGE_SPEED
	velocity.z = dir.z * GameConfig.UNIT_CHARGE_SPEED
	_face(dir, get_physics_process_delta_time())
	var arena := _arena()
	if arena == null:
		return
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if other == null or not other.alive:
			continue
		## ⚠️ 2026-09-19：潜地单位不可锁定 ⇒ 冲撞**不能**停在它身上（否则一次冲锋白费）
		if other.is_burrowed():
			continue
		if surface_distance_to(other) > attack_reach():
			continue
		_charge_hit(other, dir)
		_charge_until_ms = 0
		_release_ally_ghost()      ## 撞到敌人 ⇒ 冲锋结束，请求让队友重新变成实体
		return

## 玩家按 1 之后沿按下那一刻的准星冲，撞到面前的敌人就停。
func _pilot_charge_tick() -> void:
	var dir := _pilot_charge_dir
	velocity.x = dir.x * GameConfig.UNIT_CHARGE_SPEED
	velocity.z = dir.z * GameConfig.UNIT_CHARGE_SPEED
	_face(dir, get_physics_process_delta_time())
	var arena := _arena()
	if arena == null:
		return
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) > attack_reach():
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.0001 or dir.dot(to_enemy.normalized()) < 0.35:
			continue
		_charge_hit(other, dir)
		_charge_until_ms = 0
		_pilot_charge_dir = Vector3.ZERO
		_release_ally_ghost()
		return

## 撞击结算：伤害 = 自身伤害 × `UNIT_CHARGE_DAMAGE_MULT`；击退数值 `UNIT_CHARGE_KNOCKBACK`
##（冲量仍由 `_add_knockback()` 按**被撞者重量**缩小）。
func _charge_hit(other: Unit3D, dir: Vector3) -> void:
	## ⚠️ 2026-09-19 修 bug（用户报告"被赋予击退了但并没有被击退，似乎一段时间内只会被击退一次"）：
	## **直接命中不再走 `tap_knockback()` 闸门**。闸门是"每个单位 1 s 内只被推一次"，它本来只为
	## **连续传递**（`_push_other()` 每帧都在跑）而设；套在离散的出手上，攻速快的兵种就会丢击退
	## （扇子兵 0.71 s 一挥 ⇒ 每隔一次白给）。现在只有传递那条路保留闸门。
	var knock := dir * GameConfig.KNOCKBACK_SPEED * GameConfig.UNIT_CHARGE_KNOCKBACK
	other.apply_hit(GameConfig.hit_damage(type_id) * GameConfig.UNIT_CHARGE_DAMAGE_MULT, self, knock)

# ---------------------------------------------------------------- 炎爆（火焰拳技能，2026-09-19 新增）
## 触发条件（用户口径）：**锁定的目标**距离落在 [`UNIT_FLAME_RANGE_MIN`, `UNIT_FLAME_RANGE_MAX`] 内。
## **无冷却** ⇒ 不看 `_skill_cd_until_ms`：只要条件再次成立就能立刻再放。
func _can_flame_burst() -> bool:
	if bool(aid_mods.get("blast_once", false)) and aid_blast_used:
		return false
	if not _target_valid():
		return false
	var d := global_position.distance_to(target.global_position)
	return d >= GameConfig.UNIT_FLAME_RANGE_MIN and d <= GameConfig.UNIT_FLAME_RANGE_MAX

## 蓄力期间必须一直成立的承诺（2026-09-19 用户第二条）：**还是当初锁定的那个单位**，且它仍在 5~13 m 内。
## ⚠️ "换目标"必须用**引用比对**（`target != _flame_charge_target`）—— 只比距离会漏掉
## "两个敌人都在 5~13 m 内、但最近者换了人"这种切换。
func _flame_charge_still_valid() -> bool:
	if _flame_charge_target == null or not is_instance_valid(_flame_charge_target):
		return false
	if target != _flame_charge_target or not _flame_charge_target.alive:
		return false
	var d := global_position.distance_to(_flame_charge_target.global_position)
	return d >= GameConfig.UNIT_FLAME_RANGE_MIN and d <= GameConfig.UNIT_FLAME_RANGE_MAX

## 炎爆主流程（四段，见 `enum Flame`）。返回 true = 这一帧由技能接管，不跑常规走位 / 攻击。
##   ① 蓄力 1 s：原地不动（可被眩晕打断，**也可被"目标离开 5~13 m / 换目标"打断**）；
##   ② 极速冲刺到被锁定单位（每帧重定向 = 追踪；**穿过队友**）；
##   ③ 撞上只给**击退 4 + 眩晕 1**，**不造成伤害**；然后原地等 0.5 s；
##   ④ 以自身为中心 6 m 爆炸：范围内**所有敌方单位**吃 3× 攻击伤害 + 眩晕 1，**自己眩晕 1**。
## ⚠️ ① **不是死承诺**（2026-09-19 用户第二条）：目标离开 5~13 m 或换目标就中断，
## 不爆炸、不自晕 —— 见 `_flame_charge_still_valid()`。
## ⚠️ 但**起手之后**（②③④）必须走完：目标中途死了也照样冲到最后位置并爆炸 ——
## 否则"自晕 1 s"的代价会白付，观感也像技能丢了。
func _tick_flame_burst() -> bool:
	match _flame_phase:
		Flame.IDLE:
			if not _can_flame_burst():
				return false
			_flame_phase = Flame.CHARGE
			_flame_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_FLAME_CHARGE_MS
			_flame_charge_target = target          ## 记住"这次蓄力是给谁的"
			velocity.x = 0.0
			velocity.z = 0.0
			return true
		Flame.CHARGE:
			if piloted:
				if _pilot_flame_too_close():
					_flame_phase = Flame.IDLE
					_flame_until_ms = 0
					_flame_charge_target = null
					_pilot_flame_dir = Vector3.ZERO
					return false
				set_facing(_pilot_flame_dir)
				velocity.x = 0.0
				velocity.z = 0.0
				if Time.get_ticks_msec() >= _flame_until_ms:
					_flame_phase = Flame.DASH
					_flame_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_FLAME_DASH_MAX_MS
					_set_ally_ghost(true)
				return true
			## 2026-09-19 用户第二条：被锁定对象**离开 5~13 m** 或**换目标** ⇒ 蓄力中断。
			## 返回 false ⇒ 这一帧直接交回常规走位（不浪费一帧）。
			if not _flame_charge_still_valid():
				_flame_phase = Flame.IDLE
				_flame_until_ms = 0
				_flame_charge_target = null
				return false
			if Time.get_ticks_msec() >= _flame_until_ms:
				_flame_phase = Flame.DASH
				_flame_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_FLAME_DASH_MAX_MS
				_set_ally_ghost(true)
			return true
		Flame.DASH:
			if piloted:
				return _tick_pilot_flame_dash()
			return _tick_flame_dash()
		Flame.DELAY:
			if Time.get_ticks_msec() >= _flame_until_ms:
				_flame_phase = Flame.IDLE
				_flame_until_ms = 0
				_flame_explode()
			return true
	return false

## 进入"待爆"段：撞到了 / 目标没了 / 冲刺超时都走它，顺便把冲刺速度与"穿队友"掩码收干净。
## ⚠️ 到这里冲刺已经结束，`_flame_charge_target` 不再需要；但**爆炸的中心要另算**
##（2026-09-19 用户第五条：以被撞对象为中心）⇒ 中心在 `_flame_explode()` 里现算，见 `_flame_blast_target`。
func _flame_enter_delay() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_release_ally_ghost()
	_flame_charge_target = null
	_flame_phase = Flame.DELAY
	_flame_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_FLAME_BLAST_DELAY_MS

## 冲刺段。⚠️ 60 m/s ≈ 一帧 1 m，比单位胶囊（半径 0.38）还长 ⇒ **不能靠碰撞体判命中**
##（会直接穿过去），改成每帧比对"与被锁定单位的距离"；方向每帧重算 ⇒ 追踪，不会冲偏。
## ⚠️ 追踪的是**蓄力时锁定的那个单位**（`_flame_charge_target`），不是每帧重取的 `target`：
## 蓄力期间换目标已被拦下，冲刺途中再换目标也不该让它半路改道（2026-09-19 用户第二条的配套）。
## 冲刺**本身不可打断**（只有蓄力可以）——目标中途死了就停在原地照常进入爆炸段。
## 玩家的炎爆：蓄力结束后沿按下时的准星冲，撞到面前的人再炸。
func _tick_pilot_flame_dash() -> bool:
	var dir := _pilot_flame_dir
	if Time.get_ticks_msec() >= _flame_until_ms:
		_flame_enter_delay()
		return true
	_face(dir, get_physics_process_delta_time())
	velocity.x = dir.x * GameConfig.UNIT_FLAME_DASH_SPEED
	velocity.z = dir.z * GameConfig.UNIT_FLAME_DASH_SPEED
	velocity.y = 0.0
	var arena := _arena()
	if arena == null:
		return true
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) > GameConfig.UNIT_FLAME_HIT_DISTANCE:
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.0001 or dir.dot(to_enemy.normalized()) < 0.35:
			continue
		_flame_hit(other)
		_flame_enter_delay()
		return true
	return true

func _tick_flame_dash() -> bool:
	var victim := _flame_charge_target
	var victim_gone := victim == null or not is_instance_valid(victim) or not victim.alive
	if Time.get_ticks_msec() >= _flame_until_ms or victim_gone:
		_flame_enter_delay()
		return true
	var to_target := victim.global_position - global_position
	to_target.y = 0.0
	if surface_distance_to(victim) <= GameConfig.UNIT_FLAME_HIT_DISTANCE:
		_flame_hit(victim)
		_flame_enter_delay()
		return true
	var dir := to_target.normalized()
	_face(dir, get_physics_process_delta_time())
	velocity.x = dir.x * GameConfig.UNIT_FLAME_DASH_SPEED
	velocity.z = dir.z * GameConfig.UNIT_FLAME_DASH_SPEED
	velocity.y = 0.0
	return true

## 撞上被锁定单位：**只给击退 + 眩晕，不造成伤害**（用户口径）。
## 伤害传 0 ⇒ 仍然会闪白 / 发 `unit_was_hit`（观感上"确实挨了一下"，只是不掉血）；
## 击退冲量照旧由 `_add_knockback()` 按**被击退者的重量**缩小。
func _flame_hit(other: Unit3D) -> void:
	var dir := other.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	other.apply_hit(0.0, self,
			dir.normalized() * GameConfig.KNOCKBACK_SPEED * GameConfig.UNIT_FLAME_HIT_KNOCKBACK)
	other.apply_stun(GameConfig.UNIT_FLAME_HIT_STUN_MS)
	## 2026-09-19 用户第五条：**记住被撞到的这个对象** —— 0.5 s 后的爆炸以它为中心（判定 + 特效）。
	## 只有真的撞上了才记；冲刺超时 / 对象半路没了 ⇒ 保持 null ⇒ 爆炸回落到自身位置。
	_flame_blast_target = other
	## 表现（参考图 3）：撞上那一下的爆燃，一次性（时长见 `FLAME_FX_HIT_MS`）
	_fx_hit_until_ms = Time.get_ticks_msec() + FLAME_FX_HIT_MS

## 爆炸段：以 `UNIT_FLAME_BLAST_RADIUS` 内的**所有敌方单位**吃 3× 攻击伤害 + 眩晕 1，
## 随后**自己眩晕 1** —— 这就是用户口径里"爆炸后自身也会眩晕 1"那一句，也是这个技能唯一的代价。
## ⚠️ 只打敌方、**不误伤队友**（用户写的是"所有敌方单位"）；⚠️ 爆炸**不带击退**（用户没写）。
## ⚠️ 2026-09-19 用户第五条：**中心从"自身"改成"被撞到的那个对象"**（判定与特效同一个点）——
## 被撞的人被击退推开后，火仍然炸在它脚下；对象中途死亡 / 已被回收 ⇒ 回落到自身位置（不会炸空）。
func _flame_explode() -> void:
	if bool(aid_mods.get("blast_once", false)):
		aid_blast_used = true
	## 中心现算：优先被撞对象（还活着才算），否则自身
	var center := global_position
	if _flame_blast_target != null and is_instance_valid(_flame_blast_target) \
			and _flame_blast_target.alive:
		center = _flame_blast_target.global_position
	_flame_blast_center = center
	_flame_blast_target = null
	var arena := _arena()
	if arena != null:
		for enemy in arena.units_of_team(1 - team):
			var other := enemy as Unit3D
			if other == null or not other.alive:
				continue
			## ⚠️ 2026-09-19：潜地单位无敌 ⇒ 爆炸也不把它算进范围（连眩晕都不给）
			if other.is_burrowed():
				continue
			if center.distance_to(other.global_position) > GameConfig.UNIT_FLAME_BLAST_RADIUS:
				continue
			var blast := GameConfig.UNIT_FLAME_BLAST_DAMAGE_MULT * float(aid_mods.get("blast_mult", 1.0))
			other.apply_hit(GameConfig.hit_damage(type_id) * blast, self)
			other.apply_stun(GameConfig.UNIT_FLAME_BLAST_STUN_MS)
	## 表现（参考图 4）：地面火池，一次性，画在 `_flame_blast_center` 上（= 上面那个判定中心）。
	## ⚠️ 它**不进 `_interrupt_skill()`**：爆炸紧接着就是自晕 1 s，而自晕会调 `_interrupt_skill()` ——
	## 火池必须活过那一段（900 < 1000 ms）。⚠️ 挂点在 `_ready()` 里已经挂到本体根上（不受 `visual` 摇晃影响），
	## 具体世界坐标由 `_update_flame_fx()` 每帧按中心写死 ⇒ 火焰拳自己被击退也不会把火池带走。
	_fx_blast_until_ms = Time.get_ticks_msec() + FLAME_FX_BLAST_MS
	if _fx_blast != null:
		_fx_blast.global_position = _flame_blast_center + Vector3(0.0, FLAME_FX_BLAST_LIFT, 0.0)
	apply_stun(GameConfig.UNIT_FLAME_SELF_STUN_MS)

## 技能位移期间"穿过队友"（2026-09-19 起**三个技能共用**：骑士冲撞 / 狂战士跳跃 / 火焰拳炎爆冲刺）：
## 把**己方队伍层**从 `collision_mask` 里摘掉（世界与敌方照旧拦）。
## ⚠️ 语义是"**纯穿过**"（用户 2026-09-19 选定）：**不挡路、也不推队友** —— 所以按距离判定的那条
## 动量传递同时跳过己方，见 `_transfer_motion_to_contacts()` 的 `skip_allies`。
## ⚠️ 还原要看 `alive`：阵亡时 `_die()` 已经把掩码改成"只留世界层"，这里不能把己方层加回去。
## ⚠️ 2026-09-19：**技能结束时别直接调这里**，改调 `_release_ally_ghost()` —— 直接还原会把
## 正被自己压住的队友顶开（见那里与 `UNIT_ALLY_GHOST_CLEAR_RADIUS` 的说明）。
func _set_ally_ghost(on: bool) -> void:
	var ally_bit := 1 << (team + 1)
	if on:
		collision_mask &= ~ally_bit
	elif alive:
		collision_mask |= ally_bit
	## 无论走哪一支，待还原的请求都作废（立刻生效这条路径就是"抢先还原"）
	_ghost_off_due_ms = 0

## 请求解除"穿队友"（技能结束 / 冲撞撞到人 / 跳跃落地都走它）：**不立刻还原**，
## 记一个最迟时刻，交给 `_tick_ally_ghost()` 在"身边没有队友"时还原。
func _release_ally_ghost() -> void:
	if _ghost_off_due_ms <= 0:
		_ghost_off_due_ms = Time.get_ticks_msec() + GameConfig.UNIT_ALLY_GHOST_MAX_HOLD_MS

## 每物理帧检查待还原的"穿队友"（在 `move_and_slide()` 之前跑 ⇒ 掩码本帧就生效）。
## 身边没有队友（或已经等够 `UNIT_ALLY_GHOST_MAX_HOLD_MS`）⇒ 立刻还原。
func _tick_ally_ghost() -> void:
	if _ghost_off_due_ms <= 0:
		return
	if Time.get_ticks_msec() >= _ghost_off_due_ms or not _ally_nearby():
		_set_ally_ghost(false)

# ---------------------------------------------------------------- 冲刺穿透 / 转弯限速（轻骑兵（矛），2026-09-25）
## "穿过**所有**单位"（用户 2026-09-25："轻骑兵改为冲刺阶段能穿过所有单位"）。
## ⚠️ 这是**第 4 套**掩码口径，与下面三套都不同，别混：
##   · `_set_ally_ghost(on)`  —— 只摘**己方层**（骑士冲撞 / 狂战士跳跃 / 火焰拳冲刺：队友穿过、敌人照撞）；
##   · 本函数               —— **单位层整个不参与**（含敌人）+ **自己的判定体停用** ⇒ 谁都穿不过去也穿不过我；
##   · `_set_burrow_physics(on)` —— 沙虫潜地：`collision_layer = 0` + 掩码只留世界（**人也碰不到它**）；
##   · 阵亡 —— `collision_layer = 0` + 掩码只留世界。
## ⚠️ **为什么光改 `collision_mask` 不够**：掩码只决定"我去不去撞别人"，
## 而"别人撞不撞得到我"由**我的 `collision_layer`** 决定、**双方引擎的穿透修正**还看**我的形状**。
## 所以这里三件事一起做：① `collision_layer = 0`（别人看不见我）② 掩码只留世界层（我还能踩地）
## ③ **`shape.disabled = true`**（我身上没有挡路的形状 ⇒ 彻底不产生接触对）。
## ⚠️ 不推开任何人：`_lance_tick()` 在穿透期间**不调用**动量传递
##（`_transfer_motion_momentum` / `_transfer_motion_to_contacts` 那两条只在被击退或骑士/跳跃时跑）。
func _set_pass_all(on: bool) -> void:
	if on:
		collision_layer = 0
		collision_mask = 1
		if _shape != null:
			_shape.disabled = true
	elif alive:
		collision_layer = 1 << (team + 1)
		collision_mask = 1 | (1 << 1) | (1 << 2)
		if _shape != null:
			_shape.disabled = false
	## 无论走哪一支，待还原的请求都作废（这里既然已经落到"恢复"这一支，请求就没有意义了）
	_pass_clear_due_ms = 0

## 该单位是否**正处于"速度不可外推"的位移中**（击退 / 技能位移）。
## 这是 `arena.gd#_skip_prediction()` 的唯一判据（用户 2026-09-25："如果被锁定单位正在被击退或正在冲撞
##（目前只有骑士，火焰拳），则不预判"）。
## ⚠️ 判据落在 `Unit3D` 而不是 arena，是因为**只有单位自己知道**它是不是在被推 / 在冲刺。
## ⚠️ 覆盖 4 种情形：① 被击退（`is_knocked_back()`，外力、会衰减）
## ② 骑士冲撞 ③ 火焰拳炎爆（蓄力 / 冲刺 / 待爆三段都算）④ 轻骑兵（矛）自己的冲刺。
## ⚠️ **狂战士的火箭跳跃不算**（用户只点了"骑士、火焰拳"）—— 它是抛物线滞空，
## 水平速度在起跳帧就定死了（`_start_jump()` 写一次 `velocity`），反而**是**可以外推的。
func is_mid_dash() -> bool:
	if is_knocked_back():
		return true
	if _charge_until_ms > 0:
		return true
	if _flame_phase != Flame.IDLE:
		return true
	return _lance_until_ms > 0

## **轻骑兵（矛）的冲刺是否正在驱动位移**（2026-09-25 第八条，`_physics_process` 的"禁移豁免"判据）。
## ⚠️ **不要拿 `is_mid_dash()` 顶替它** —— 那个是**预判闸门**的判据，把"被击退 / 骑士冲撞 / 火焰拳炎爆"
## 也算成真；拿它当豁免条件会把"禁移豁免"发给**所有正在被击退的单位**。
## 引擎内实测（探针的对照组）：一个**没在冲刺**的扇子兵挨了同样的击退后也走了"叠加档"
##（`_kb_added` 从 0 变成 216）⇒ 当场失败。**这一条只管冲刺本身。**
func _lance_active() -> bool:
	return _lance_until_ms > 0

## 冲刺这一帧的**转弯限速**（度/秒，2026-09-25 第十条，用户："转弯速度可以在每秒 180 度和 270 度间切换，
## 防止一直转圈撞不到人"）。判据 = **目标是否落在命中矩形的可及范围内**：
##   · **够不到**（`dist > UNIT_LANCE_BOX_LENGTH` = 3.4 m）⇒ 用**快档** 270°/s，把圈子收紧、把人圈进矩形；
##   · **够得到**（≤ 3.4 m）⇒ 落回**基档** 180°/s，走原来那条好看的弧线。
## ⚠️ 几何依据：转弯半径 = 冲刺速度 ÷ 角速度 ⇒ 180°/s 是 **4.46 m**、270°/s 是 **2.97 m**，
##    而矩形只有 **3.4 m** 长 ⇒ 4.46 m 的目标永远在矩形之外。
## ⚠️ **诚实记录一个已知局限**（别以为切快档就一定能打到）：目标若是**静止**的，
##    "纯追踪 + 限速转向"会稳定在"**目标在正侧方 90°、距离 = 转弯半径**"的绕圈平衡上 ——
##    那时**任何**转速都罩不到它（矩形宽只有 1 m）。快档的作用是**把圈子从 4.46 m 收到 2.97 m、
##    增加擦到的机会**，不是保证命中。真机里目标都在朝它走，这个理想平衡很少长时间成立。
func _lance_turn_deg_per_sec(dist: float) -> float:
	if dist > GameConfig.UNIT_LANCE_BOX_LENGTH:
		return GameConfig.UNIT_LANCE_TURN_FAST_DEG_PER_SEC
	return GameConfig.UNIT_LANCE_TURN_DEG_PER_SEC

## 朝 `want` 转过去，但**每秒最多转 `deg_per_sec` 度**（用户 2026-09-25："轻骑兵在转弯时每秒最多旋转 180°"）。
## ⚠️ 2026-09-25 第十条起，这个上限**由调用方给**：冲刺按"够不够得到"在 180 / 270 之间切
##（见 `_lance_turn_deg_per_sec()`），游走固定用基档。
## 取代了旧的"1.5 s 后把方向彻底锁死"：现在方向**每帧都跟着目标更新**，
## 只是转不快 ⇒ 冲刺变成"带转弯半径的弧线"而不是"瞬时对准"。
## ⚠️ 它只改冲刺 / 游走的**移动方向**；`_face()`（模型朝向）仍照旧平滑转向，
## 所以本函数返回的是"这一帧实际允许走的方向"，调用方必须用它写 `velocity`。
func _steer_toward(current: Vector3, want: Vector3, delta: float, deg_per_sec: float) -> Vector3:
	var from := Vector3(current.x, 0.0, current.z)
	var to := Vector3(want.x, 0.0, want.z)
	if from.length_squared() < 0.0001:
		return to.normalized() if to.length_squared() > 0.0 else from
	if to.length_squared() < 0.0001:
		return from.normalized()
	from = from.normalized()
	to = to.normalized()
	var max_step := deg_to_rad(deg_per_sec) * delta
	var angle := from.angle_to(to)
	if angle <= max_step:
		return to
	return from.rotated(Vector3.UP, signf(from.cross(to).y) * max_step)

## 身边 `UNIT_ALLY_GHOST_CLEAR_RADIUS` 内还有活着的队友吗（只看 `arena.units`，与动量传递同源）。
## ⚠️ 必须用**水平**距离：狂战士的跳跃是从队友**头顶**飞过去的（滞空最高处 y≈1.5 m），
## 三维距离那时早就超过 1 m ⇒ 会误判成"身边没人"而提前还原掩码，落地正好砸进队友身上，
## 引擎的穿透修正会把它弹开（2026-09-19 实测 9 m）。
func _ally_nearby() -> bool:
	var arena := _arena()
	if arena == null:
		return false
	for node in arena.units:
		var other := node as Unit3D
		if other == null or other == self or not other.alive or other.team != team:
			continue
		var flat := other.global_position - global_position
		flat.y = 0.0
		if flat.length() <= GameConfig.UNIT_ALLY_GHOST_CLEAR_RADIUS:
			return true
	return false

## 请求解除"穿过所有单位"（冲刺结束时调）：**不立刻恢复判定体**，交给 `_tick_pass_clear()`。
## ⚠️ **为什么不能立刻恢复**（与"穿队友"那条完全同源的问题）：冲刺的语义是"穿过所有单位"，
## 结束那一刻它**本来就可能正和某个对手重叠**（判定体在被停用期间不会把它挡开）。
## 那一刻若立刻 `shape.disabled = false`，引擎的穿透修正会把它**弹开**（观感是冲刺末尾莫名一抖）。
## 所以：先记一个最迟时刻，等身边真的没人了再恢复；超时则**无条件恢复**（宁可挨一次修正，
## 也不能让"无判定体"变成永久状态 —— 那会连地面都踩不住）。
## ⚠️ 半径用 `UNIT_ALLY_GHOST_CLEAR_RADIUS` 还是 `KNOCKBACK_CONTACT_RADIUS` 都不合适：
## 这里要判的是"**任意单位**（敌友都算）有没有和我的判定体交叠"，所以按**双方判定半径之和**算。
func _release_pass_all() -> void:
	if _pass_clear_due_ms <= 0:
		_pass_clear_due_ms = Time.get_ticks_msec() + GameConfig.UNIT_ALLY_GHOST_MAX_HOLD_MS

## 身边（按**双方判定半径之和**算）还有活着的单位吗 —— 敌友都算（冲刺穿的是所有人）。
func _unit_overlapping() -> bool:
	var arena := _arena()
	if arena == null:
		return false
	for node in arena.units:
		if not is_instance_valid(node):
			continue
		var other := node as Unit3D
		if other == null or other == self or not other.alive:
			continue
		var flat := other.global_position - global_position
		flat.y = 0.0
		var reach := GameConfig.body_radius(type_id) + GameConfig.body_radius(other.type_id)
		if flat.length() <= reach:
			return true
	return false

## 每物理帧检查待解除的"穿过所有单位"（在 `move_and_slide()` 之前跑 ⇒ 判定体本帧就恢复）。
func _tick_pass_clear() -> void:
	if _pass_clear_due_ms <= 0:
		return
	if Time.get_ticks_msec() >= _pass_clear_due_ms or not _unit_overlapping():
		_set_pass_all(false)

# ---------------------------------------------------------------- 潜地（沙虫技能，2026-09-19 新增）
## 浮出瞬间的**范围眩晕**（2026-09-19 用户："钻出地时立即对以自身为中心、半径 4 m 的所有单位
##（包括友方）造成眩晕 1"）：以自身为中心的**三维**半径内，所有存活单位一律 `apply_stun()`。
## ⚠️ 三条与既有口径一致的取舍：
##   ① **不区分敌我**——用户明说"包括友方"，友方照晕（这是这个技能的代价）；
##   ② **跳过潜地单位**——与扇形群伤 / 炎爆爆炸 / 索敌同一条既有口径（地下的东西打不到）；
##   ③ **跳过自身**——沙虫是 boss，`apply_stun()` 本就免疫"任何来源"的眩晕，这里连计数都不算它。
## 返回真正被晕到的人数，供调试与回归验证用。
func _stun_units_around(radius: float, duration_ms: int) -> int:
	var arena := _arena()
	if arena == null:
		return 0
	var radius_sq := radius * radius
	var stunned := 0
	for node in arena.units:
		var other := node as Unit3D
		if other == null or other == self or not other.alive or other.is_burrowed():
			continue
		if global_position.distance_squared_to(other.global_position) > radius_sq:
			continue
		other.apply_stun(duration_ms)
		stunned += 1
	return stunned

## 潜地：boss 单位"沙虫"的核心机制，**无冷却**。用户口径：
##   · 攻击范围内没有敌人 ⇒ **钻入地中**（钻地期间**无法被锁定 + 无敌 + 免疫一切状态**）；
##   · **只有攻击时才钻出，不攻击就待在地下** ⇒ "要移动必须钻至地下"：`UNDER` 是唯一的移动态；
##   · 押注阶段（`active == false`）**不许钻地** —— 那时它要站在场地上给玩家看阵容。
## 返回 true = 这一帧由技能接管（两个**过渡段**锁住移动与出手）；`UNDER` 返回 false ⇒ 交给常规走位
##（`_tick_move()` 在射程外前进），而"地下不许出手"由 `UNDER` 分支自己保证（它会先钻出来）。
func _tick_burrow() -> bool:
	var now := Time.get_ticks_msec()
	if not active:
		_burrow = Burrow.SURFACED
		_first_bite_double = false       ## 押注阶段不攒双倍（那时它只是在场上站着给观众看阵容）
		## 两道新的时间闸门也一起清干净：押注阶段不钻地，开赛那一帧重新开始计时
		_no_enemy_since_ms = 0
		_rise_after_ms = 0
		return false
	## ⚠️ 2026-09-19（实测补漏）：**射程内有敌人 ⇒ "连续没敌人"的计时在任何状态下都作废**。
	## 原先只在 `SURFACED` 分支里复位，于是"下潜前的静默窗"会被跨状态地绕过：
	## 浮出那一帧若敌人刚走（或被打退），`_no_enemy_since_ms` 还留着上一轮的旧值 ⇒ 当帧就重新下潜、
	## 0.6 s 静默窗白设（实机探针复现：第二次下潜的 `no_enemy_ago` 直接是 1855 ms）。
	var in_range := _enemy_in_fan_range()
	if in_range:
		_no_enemy_since_ms = 0
	match _burrow:
		Burrow.SURFACED:
			if not in_range:
				## ⚠️ 2026-09-19 用户："钻回地需要在范围内没有敌人并**持续 0.6 秒**才行" ⇒ 不再"当帧就钻"：
				## 先记下"射程变空"的起点，连续满 `UNIT_SANDWORM_SINK_DELAY_MS` 才真正下潜；
				## 中途有敌人回到射程 ⇒ 上面那一句已经把计时归零，重新开始数。
				## ⚠️ 这 0.6 s 里它仍是 `SURFACED`：照样贴地、照样能被打到（只是没敌人可打）。
				if _no_enemy_since_ms <= 0:
					_no_enemy_since_ms = now
				if now - _no_enemy_since_ms < GameConfig.UNIT_SANDWORM_SINK_DELAY_MS:
					return false
				_burrow = Burrow.SINKING
				_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_SINK_MS
				_first_bite_double = false   ## 重新钻地 ⇒ 上一轮攒下的"第一口双倍"作废
				_set_burrow_physics(true)
				return true
			return false                  ## 射程内有敌人 ⇒ 照常站定出手（扇形群伤）
		Burrow.SINKING:
			## ⚠️ 2026-09-19 用户："沙虫只能在钻到地里后移动" ⇒ 两个**过渡段也不许滑行**：
			## 这里与 `RISING` 每帧清零水平速度（实机时间轴实测：不清零时它带着 3 m/s 的余速
			## 滑过整段 300 ms 过渡 ≈ 0.9 m）⇒ 位移只可能发生在 `UNDER` 段。
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _burrow_until_ms:
				_burrow = Burrow.UNDER
				## ⚠️ 2026-09-19 用户："钻到地里 0.3 秒后才能移动" ⇒ 这里**重设**截止时刻，
				## 让 UNDER 段再等这么久才放开移动（`_burrow_until_ms` 原本只是钻入过渡的截止时刻）。
				_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_UNDER_DELAY_MS
				## ⚠️ 2026-09-19 用户："钻到地里需过 0.6 秒才能钻出来" ⇒ 另记一个**浮出闸门**的截止时刻
				## （与上面那条移动闸门各自独立：能移动 ≠ 能浮出）。
				_rise_after_ms = now + GameConfig.UNIT_SANDWORM_UNDER_MIN_MS
			return true
		Burrow.UNDER:
			## ⚠️ 2026-09-19 用户："钻到地里 0.3 秒后才能移动" ⇒ 到达 UNDER 之后再等一段时间才放开移动。
			if now < _burrow_until_ms:
				return true
			## ⚠️ 2026-09-19 用户："钻到地里需过 0.6 秒才能钻出来" ⇒ 最短地下停留期内即使有敌人也不浮出
			##（这段里它照旧按上面的移动闸门在地下追过去，只是"憋着不出来"）。
			if in_range and now >= _rise_after_ms:
				_burrow = Burrow.RISING
				## ⚠️ 切换那一帧就要清零：清零写在 `RISING` 分支里要等下一帧，而本帧的
				## `move_and_slide()` 仍会按 3 m/s 走掉 ~0.1 m（实机时间轴实测到的唯一残留位移）。
				velocity.x = 0.0
				velocity.z = 0.0
				_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_SINK_MS
				return true
			return false                  ## 地下 = 移动态 ⇒ 交给 `_tick_move()` 追过去
		Burrow.RISING:
			## 同上：过渡段不许滑行（出土那一刻的水平速度也在这里被清掉，见上面的 SINKING 段）
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _burrow_until_ms:
				_burrow = Burrow.SURFACED
				_set_burrow_physics(false)
				## ⚠️ 2026-09-19 用户："钻出地后 0.3 秒后才能攻击" ⇒ 记一个出手封锁截止时刻。
				_attack_block_until_ms = now + GameConfig.UNIT_SANDWORM_SURFACE_DELAY_MS
				## ⚠️ 2026-09-19 用户："钻出地时立即对以自身为中心、半径 4 m 的所有单位（包括友方）
				## 造成眩晕 1，且钻出地后的第一下攻击造成双倍伤害" ⇒ **浮出这一帧**同时结算这两件事：
				## 范围眩晕当场落地；双倍只是**上膛**，等第一口真正咬中才消耗（咬空保留）。
				_stun_units_around(GameConfig.UNIT_SANDWORM_SURFACE_STUN_RADIUS,
					GameConfig.UNIT_SANDWORM_SURFACE_STUN_MS)
				_first_bite_double = true
				if not has_meta("brood"):
					_begin_sandstorm(now)
					_spawn_brood()
				## 浮出那一下的"震地"特效（纯表现，与范围眩晕同一帧起：观感=判定）
				_fx_burst_until_ms = now + BURROW_FX_BURST_MS
				## ⚠️ 2026-09-19 用户："沙虫只能在钻到地里后移动" ⇒ **出土即停**：
				## 清零水平速度，别让"停下就减速"那 0.2 s 的余速被看成"露出地面还在滑"。
				velocity.x = 0.0
				velocity.z = 0.0
			return true
	return false

## 攻击范围内（= 面板射程，沙虫就是扇形半径）还有敌人吗。
## ⚠️ 只看**距离**、不看扇形角度：它会先转向目标再出手（`_tick_move()` 里就 `_face()`），
## 所以"最近者在射程内"与"有敌人可咬"等价。⚠️ `target` 已经过 `_find_target()`，不会是被潜地的单位。
func _enemy_in_fan_range() -> bool:
	if not _target_valid() or target.is_burrowed():
		return false
	## ⚠️ 2026-09-19 修 bug（用户："攻击弩车投石车时依旧是沙尘特效没有钻出地，但依旧攻击"）：
	## 这里必须用**表面距离**，与攻击判定（`surface_distance_to()`）同源。原先比中心距 ⇒ 对弩车 / 投石车
	## 这种大目标：中心距 > 5 m（判定"没敌人" ⇒ 保持地下），表面距 < 5 m（判定"够得着" ⇒ 照常出手）
	## ⇒ 表现就是**埋在土里咬人**。
	return surface_distance_to(target) <= float(GameConfig.profile(type_id)["range"])

## 潜地期间的**物理隐身**：摘掉自己的碰撞层（谁都撞不到它）、掩码只留世界层（照旧贴地不掉下去）。
## ⚠️ 与"穿队友"那套掩码不是一回事：那个只摘己方层、人还留在场上；这里整个人从物理世界里拿掉。
## 阵亡时不还原（`_die()` 自己会把掩码改成"只留世界层"）⇒ 只看 `alive`。
func _set_burrow_physics(buried: bool) -> void:
	if buried:
		collision_layer = 0
		collision_mask = 1
	elif alive:
		collision_layer = 1 << (team + 1)
		collision_mask = 1 | (1 << 1) | (1 << 2)

# ---------------------------------------------------------------- 炎爆的三段特效（纯表现，2026-09-19 新增）
## 每帧驱动，由 `_process()` 调用；几何在 `unit_factory.gd#_build_flame_fx()`，出厂即隐藏。
##   · **蓄力**：进度直接由 `_flame_phase` + `_flame_until_ms` 推出来，不必另存起始时刻；
##   · **冲撞** / **爆炸**：两个一次性特效，各自一个截止时刻（`_fx_*_until_ms`）。
## ⚠️ 这里只写 `scale` / `rotation` / 自发光与透明度，**一个判定都不碰**（伤害与眩晕仍只看 `GameConfig`）。
## ⚠️ 用 `_process`（不是 `_physics_process`）：特效是画面层的东西，和 60 Hz 的判定循环解耦。
func _update_flame_fx() -> void:
	if _fx_charge == null:
		return
	var now := Time.get_ticks_msec()
	## ① 蓄力（参考图 2）：火球越烧越大、核心越来越白热，一边自转一边脉动
	var charging := alive and _flame_phase == Flame.CHARGE
	_show_fx(_fx_charge, charging)
	if charging:
		var total := float(maxi(GameConfig.UNIT_FLAME_CHARGE_MS, 1))
		var charge_t := clampf(1.0 - float(maxi(_flame_until_ms - now, 0)) / total, 0.0, 1.0)
		var pulse := 1.0 + 0.14 * sin(float(now) * 0.021)
		_fx_charge.scale = Vector3.ONE * (0.35 + 0.85 * charge_t) * pulse
		_fx_charge.rotation.y = float(now) * FLAME_FX_SPIN
		_glow_fx(_fx_charge, 0.6 + 1.5 * charge_t, 0.75 + 0.25 * charge_t)
	## ② 冲撞命中（参考图 3）：一下炸开、随即收干净
	var hit_t := _fx_elapsed(_fx_hit_until_ms, FLAME_FX_HIT_MS, now)
	_show_fx(_fx_hit, hit_t > 0.0)
	if hit_t > 0.0:
		_fx_hit.scale = Vector3.ONE * (0.50 + 1.25 * hit_t)
		_fx_hit.rotation.y = -float(now) * FLAME_FX_SPIN * 1.5
		_glow_fx(_fx_hit, 3.2 - 2.4 * hit_t, 1.0 - 0.85 * hit_t)
	## ③ 爆炸火池（参考图 4）：先前 30% 向外炸开，后段烧完收掉
	var blast_t := _fx_elapsed(_fx_blast_until_ms, FLAME_FX_BLAST_MS, now)
	_show_fx(_fx_blast, blast_t > 0.0)
	if blast_t > 0.0:
		## 火池钉在**爆炸那一刻的中心**（= 被撞对象的位置，见 `_flame_explode()`）：每帧写世界坐标 ⇒
		## 火焰拳自己被击退、模型呼吸浮动都不会把火池带走。旋转只留 Y（8 片火墙近似轴对称）⇒ 不受摇晃影响。
		_fx_blast.global_position = _flame_blast_center + Vector3(0.0, FLAME_FX_BLAST_LIFT, 0.0)
		var open := clampf(blast_t / 0.30, 0.0, 1.0)
		var fade := 1.0 - clampf((blast_t - 0.45) / 0.55, 0.0, 1.0)
		_fx_blast.scale = Vector3.ONE * (0.35 + 0.80 * open) * (0.86 + 0.14 * fade)
		_fx_blast.rotation.y = float(now) * FLAME_FX_SPIN * 0.35
		_glow_fx(_fx_blast, 0.6 + 2.6 * fade, fade)

## 一次性特效的进度：0 = 还没开始 / 已经结束，其余 0~1（从绝对 ms 算，遵守不变量 I-13）。
func _fx_elapsed(until_ms: int, duration_ms: int, now: int) -> float:
	if until_ms <= 0 or now >= until_ms:
		return 0.0
	return clampf(1.0 - float(until_ms - now) / float(duration_ms), 0.0, 1.0)

## **预热专用**（2026-09-25）：把本体身上所有**特效挂点**显示出来 —— 供渲染管线先把"透明 / 自发光"
## 那几套着色器与管线编译掉。
## ⚠️ 存在的理由：这些件**出厂即隐藏**（见 `unit_factory.gd#_fx_mesh()`），而"没被画过就不会编译"——
## 于是"游戏里第一次放炎爆 / 第一次浮出地面"都要付一笔一次性卡顿。本项目的落点扬尘踩过同一个坑
##（`arena.gd#_build_impact_dust_pool()` 的说明），这里用"先画一帧"来摊掉它。
## ⚠️ 调用方必须做到两件事：① 只在**整屏全黑**的那一屏调（见 `main.gd#_prewarm_unit_models()`）；
## ② 先把本体的 `set_process(false)` —— 否则同一帧里 `_process → _update_flame_fx()` 会把刚显示的件又藏回去。
func warmup_show_all_fx() -> void:
	for root in [_fx_charge, _fx_hit, _fx_blast, _fx_burrow, _fx_burst, _fx_shadow_form, _fire_edge, _bulwark_ring, _ember_aura, _iai_charge, _iai_dash, _iai_slash]:
		if root != null:
			(root as Node3D).visible = true

func _show_fx(root: Node3D, on: bool) -> void:
	if root != null:
		root.visible = on

## 亮度 / 透明度：`factor` 写进整段所有件的自发光倍率，`alpha` 写进 albedo 的 alpha
##（特效件都是 `TRANSPARENCY_ALPHA`，见 `unit_factory.gd#_fx_mesh()`）。
## 整段隐藏时直接跳过 ⇒ 待机 / 非火焰拳零开销。
## ⚠️ `find_children` 的 `owned` 必须传 false：代码里造出来的节点没有 `owner`，否则一个都找不到。
func _glow_fx(root: Node3D, factor: float, alpha: float) -> void:
	if root == null or not root.visible:
		return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_energy_multiplier = factor
		var col := mat.albedo_color
		col.a = alpha
		mat.albedo_color = col

## 沙虫**浮出"震地"特效**的播放（纯表现，2026-09-19 用户："沙柱爆开（更重的版本）"）。
## 触发点是与范围眩晕**同一帧**（`_tick_burrow()` 的 `RISING → SURFACED`）⇒ 观感=判定：
##   · `BurstDome` 沙浪由小撑到 **判定半径**（`UNIT_SANDWORM_SURFACE_STUN_RADIUS`）并往上扬；
##   · `BurstPillar` 沙柱从地里窜起来（节点原点在地面 ⇒ 压 `scale.y` 就是"往上长"），后段收细；
##   · `BurstRing` 地面沙环同步扩散到判定半径（网格半径就是 1 m ⇒ `scale` 直接读作米）；
##   · 六团 `BurstPuff_*` 沿各自的单位方向外飞 + 上扬，边飞边缩；
##   · 整段以 `_glow_fx()` 一起淡出，`BURROW_FX_BURST_MS` 到你后收干净。
## ⚠️ 非沙虫（`_fx_burst == null`）与没在播时都是一次空判断，零开销。
func _update_burst_fx(now: int) -> void:
	if _fx_burst == null:
		return
	var playing := _fx_burst_until_ms > 0 and now < _fx_burst_until_ms
	_show_fx(_fx_burst, playing)
	if not playing:
		_fx_burst_until_ms = 0
		return
	var u := _fx_elapsed(_fx_burst_until_ms, BURROW_FX_BURST_MS, now)
	var radius: float = GameConfig.UNIT_SANDWORM_SURFACE_STUN_RADIUS
	_glow_fx(_fx_burst, 1.6, 1.0 - u)          ## 整段一起淡出（自发光倍率 + alpha）
	if _burst_dome != null:
		var grow := lerpf(0.25, 1.0, ease(u, 0.35))
		_burst_dome.scale = Vector3(grow, lerpf(0.45, 1.0, u), grow)
		_burst_dome.position.y = lerpf(0.0, BURROW_FX_BURST_RISE, u)
	if _burst_pillar != null:
		## 沙柱：前段"窜起来"（`scale.y` 快速拉到 1），后段横向收细 ⇒ 读起来是"一股沙冲上去又散掉"
		_burst_pillar.scale = Vector3(
			lerpf(1.0, 0.55, u), lerpf(0.15, 1.0, ease(u, 0.30)), lerpf(1.0, 0.55, u))
	if _burst_ring != null:
		var rim := lerpf(0.35, radius, ease(u, 0.25))
		_burst_ring.scale = Vector3(rim, 1.0, rim)
	for puff in _burst_puffs:
		var dir := Vector3(puff.position.x, 0.0, puff.position.z)
		if dir.length_squared() < 0.0001:
			dir = Vector3.RIGHT
		dir = dir.normalized()
		var reach := lerpf(0.10, 1.0, ease(u, 0.4)) * radius * BURROW_FX_BURST_SPREAD
		puff.position = dir * reach + Vector3.UP * lerpf(0.15, BURROW_FX_BURST_RISE, u)
		puff.scale = Vector3.ONE * lerpf(1.15, 0.35, u)

## 收干净三段特效（阵亡 / 需要硬复位时用）：藏起三个挂点并清掉两个一次性截止时刻。
func _clear_flame_fx() -> void:
	_fx_hit_until_ms = 0
	_fx_blast_until_ms = 0
	_show_fx(_fx_charge, false)
	_show_fx(_fx_hit, false)
	_show_fx(_fx_blast, false)

## 锁定最近的敌人。**目标改变时只清掉"这一次出手"的进行态**——
## ⚠️ 2026-09-19 修 bug（用户报告）：这里原先还会把 `_attack_timer` 归零，
## 于是"打死一个敌人 → 锁定下一个 → 冷却被重置"，攻速实际比面板快得多
## （弩车一发秒杀时尤其明显）。现在**冷却不因换目标而重置**，只取消未完成的这次出手。
func _lock_nearest_target() -> void:
	## ⚠️ 2026-09-19 第六条（用户："炎爆蓄力时不会改变锁定对象，除非被锁定对象离开范围或死亡"）：
	## **炎爆进行中一律不再重锁**（蓄力 / 冲刺 / 待爆都算）——否则"另一个敌人变成最近者"会把 `target`
	## 换走，蓄力的引用校验 `_flame_charge_still_valid()` 随即失败 ⇒ 蓄力被打断（旧口径）。
	## 现在整条链只认"当初锁定的那个对象"：它**离开 5~13 m 或死亡** ⇒ 技能中断（`_flame_phase` 回 IDLE）
	## ⇒ 下一帧恢复重锁、若新最近者在射程内就重新蓄力。
	if _flame_phase != Flame.IDLE:
		return
	## ⚠️ 2026-09-25 第二轮 心灵腐化师：**照射期间不改锁**（用户："期间不会改变锁定目标"）。
	## 与上面炎爆那条并列、理由相同：能让"最近者"横跳的规则都会把已成立的技能打断。
	## 目标离开射程 / 死亡 / **变成友方**时 `_laser_lock_held()` 自然为假 ⇒ 自动恢复常规重锁。
	## 蓄力途中也按住这个人，但光束要等蓄力走完才画（`_laser_beam_active()`）。
	if _laser_lock_held():
		return
	var nearest := _find_target()
	if is_sustained_beam() and _lock_nearer_shield(nearest):
		return
	if _shield_lock_id >= 0:
		_shield_lock_id = -1
	if nearest == target:
		return
	target = nearest
	## ⚠️ 2026-09-19 修 bug（用户报告"投石车一下子扔出好多石头"）：
	## **不能在这里动出手节拍**（旧写法是清 `_windup_swing` 闩锁；2026-09-19 攻击节奏重做后，
	## 等价物是动画链 `_swing_from_ms` 与命中帧 `_next_hit_ms`）。最近者会在两个几乎等距的敌人之间
	## 逐帧横跳 ⇒ 每帧清闩锁 = 越过前摇之后**每帧都出手**（投石车前摇最长 ≈0.86 s 最明显）；
	## 在现在的模型里每帧清 `_swing_from_ms` 则相反：命中帧会被反复推到"现在 + 前摇"⇒ **永远打不出去**。
	## 只清"正在出手"的表现态，命中帧与动画链都留给 `_tick_attack()` 自己推进。
	_striking = false
	# 换了目标就重新开始卡住检测，避免沿用旧目标的进度判定
	_progress_ms = 0
	_last_dist = -1.0

func _tick_move(delta: float) -> void:
	if _shield_lock_alive() and not _target_valid():
		_tick_move_to_shield(delta)
		return
	if not _target_valid():
		_state = State.IDLE
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var my_range := float(GameConfig.profile(type_id)["range"])

	_face(to_target, delta)

	# 短弓手与其他兵种走位一致：射程外前进、进射程就站定射击（优化 5：取消后撤步）。
	# 历史：曾用"距离 < 射程×0.10 就后撤"来模拟风筝，但那会让短弓手在近战够不到的距离
	# 无限拉扯，且观感上像在逃跑。现在短弓手不后退——代价是它更怕被贴脸。
	## ⚠️ 2026-09-25：**长弓手同样走这一支**（它是 `is_ranged()`、没有 `charge_lance`），
	## 所以 30 m 射程也是"射程外前进、进 30 m 就站定拉弓"，没有专用走位。
	#
	# ⚠️ 这一步放在击退检查**之前**：被推着也能切入 ATTACK，攻击不受击退影响
	# （"被击退时无法移动"限制的是移动，不是出手）。
	## ⚠️ 2026-09-19 修 bug（用户："**沙虫钻出地有时候不攻击**"）：**潜地兵种进 `ATTACK` 的门槛不砍那 0.05 m**。
	## 那 0.05 是给"还能自己往前挪两厘米"的单位防抖用的；而沙虫露出地面后**一律站定**（见下面那道守卫）⇒
	## 它与潜地判定 `_enemy_in_fan_range()`（≤ 射程 **5.0**）之间留下一段 **(4.95, 5.0] 的 5 cm 死区**：
	## 浮出时若正好停在这一段（双方相对速度 ~6 m/s 时约有**一半**概率落进来），它就**既进不了 `ATTACK`、
	## 又不能挪过去**，站着不动且永远不下潜（`in_fan` 为真 ⇒ 下潜静默窗根本不会开始）。
	## 实机复现（修复前）：目标停在 4.98 m，13.3 s 内血一格没掉、状态一直是 `MOVE`。
	## 修法：潜地兵种用**完整射程**作门槛 ⇒ 与 `_enemy_in_fan_range()` 同口径，死区消失
	##（进了 `ATTACK` 之后仍按 `attack_reach()` = 射程 × 1.18 判出射程，所以不会在门槛上抖）。
	if _can_fan_intercept():
		_state = State.ATTACK
		return
	var entry_reach := my_range - 0.05
	if is_ranged() or spartan_can_throw() or is_sustained_beam():
		entry_reach = attack_reach() - 0.05
	elif is_burrower():
		entry_reach = my_range
	var gap := surface_distance_to(target)
	if gap <= entry_reach and gap >= attack_min_reach():
		_state = State.ATTACK
		## ⚠️ 2026-09-19 修 bug（用户报告"弩车的攻速有时依旧偏快，投石车可能也有"）：
		## **这里不能复位出手节拍**（`_next_hit_ms` / `_swing_from_ms`）。原先在 MOVE↔ATTACK 之间复位
		## 冷却 ⇒ 单位只要经历一次"目标出射程 → 走回来"就能立刻重新出手，实际射速变成**前摇**
		## 而不是面板间隔（弩车前摇 1.5 s、面板 5.00 s；一发秒杀后换目标时最明显）。
		## 规则见 `04_physics.md#3.4`：换目标只取消未完成的这次出手，**冷却不再重置**。
		## ⚠️ 2026-09-19 攻击节奏重做后这里也**不需要**手动起手：在 MOVE 期间动画链已被
		## `_animate_attack()` 断开（`_swing_from_ms = 0`）⇒ `_tick_attack()` 会自己把这一刀
		## 排成"命中帧 − 前摇"，**既不会白送一次出手，也保证这一刀从头挥**。
		return

	## ⚠️ 2026-09-19 用户："**沙虫只能在钻到地里后移动**" ⇒ 潜地兵种在**非 `UNDER`** 段一律**站定**：
	## 露出地面（含下潜前那 0.6 s 静默窗）只允许转向与切进 `ATTACK`，位置不许自己挪
	##（要换位置必须先钻下去 —— `_tick_burrow()` 在 `UNDER` 段返回 false、交回常规走位，那时才走得到下面）。
	## ⚠️ 必须**显式清零速度**：`_physics_process` 只在"非 MOVE"时才跑减速（`if _state != State.MOVE`），
	## 这里直接 return 会带着上一帧的速度继续滑 —— 观感上仍然是"露出地面也在移动"。
	## ⚠️ 这一段在击退处理**之前**：被别人推着走仍然照常（那是外力，不是自主移动）。
	if is_burrower() and _burrow != Burrow.UNDER:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if Time.get_ticks_msec() < _move_lock_until_ms:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# 被击退期间**暂停卡住检测**：位移已经交给 `_physics_process` 的击退项，
	# 此时若继续跑检测，"被推着后退"会被误判成"卡住"，白白累计绕行次数（`_stuck_switches`）。
	# 2026-09-18：只有**禁移档**才连自主移动一起停；可移动档（重量 ≥ 击退数值）照常走位。
	if is_knocked_back():
		_progress_ms = Time.get_ticks_msec()
		_last_dist = dist
		if is_knockback_immobile():
			return

	# 卡住检测：0.4 s 内没能靠近目标 0.25 m 就横向绕行。
	# 起因：被友军堵住 / 顶在隐形边界上 / 目标被长矛一直击退，表现就是"站在原地不动"。
	#
	# 注意（优化 6）：这里**不再换目标**。索敌规则是"所有兵种只打最近的敌人"，
	# 换目标会破坏这条规则；被堵住时只绕行，绕过去继续打同一个目标。
	if _progress_ms == 0:
		_progress_ms = Time.get_ticks_msec()
		_last_dist = dist
	## ⚠️ **2026-09-26 修 bug（用户："兵种会在投石车 / 弩车和召唤石柱后面左右摇摆"）**：
	## **侧滑（绕行）期间这一段独占走位**，下面两条"要不要起绕行"的判据全部让位。
	## 真因：横移**永远不会缩短到目标的距离** ⇒ 0.4 s 的进度判据每 400 ms 就判一次"没靠近"，
	## 于是把正在进行的侧滑**重启**（`_start_sidestep()` 会 `_stuck_switches += 1` ⇒ **左右对调**），
	## 而"贴到巨物立刻绕行"那一条下一帧又用**原方向**把它拉回来 ⇒ 一左一右地摇。
	## 现在侧滑期间把进度时钟**一直喂到当前帧**（`_progress_ms` / `_last_dist` 跟着更新）：
	## 出来之后要重新走满 0.4 s 才再判，而且那时障碍还在就照旧从"巨物"那条路起绕（方向不再被翻）。
	if Time.get_ticks_msec() < _sidestep_ms:
		_progress_ms = Time.get_ticks_msec()
		_last_dist = dist
		var perp := Vector3(-to_target.normalized().z, 0.0, to_target.normalized().x)
		var sign_side := 1.0 if (_stuck_switches % 2) == 0 else -1.0
		velocity.x = perp.x * sign_side * current_speed()
		velocity.z = perp.z * sign_side * current_speed()
		return
	## ⚠️ 2026-09-19 优化：贴到**大体积单位**时就起绕行（不等 0.4 s 的进度判据 —— 沿着大盒子侧滑时
	## 距离仍在缓慢缩短，那条判据有时根本不触发）。⚠️ 已"在绕行中"的情况由上面那条早退接管。
	var blocker := _blocking_unit_radius()
	if blocker > GameConfig.UNIT_SIDESTEP_BIG_RADIUS:
		_start_sidestep(blocker)
		## ⚠️ 起绕那一帧就**立刻按新方向走**（不再等到下一帧）：否则会先朝巨物撞一帧、下一帧才横移，
		## 在贴着盒子表面时那一下正好是"顶着墙不动"，读起来像卡顿。
		var perp_big := Vector3(-to_target.normalized().z, 0.0, to_target.normalized().x)
		var sign_big := 1.0 if (_stuck_switches % 2) == 0 else -1.0
		velocity.x = perp_big.x * sign_big * current_speed()
		velocity.z = perp_big.z * sign_big * current_speed()
		return
	var elapsed_ms := Time.get_ticks_msec() - _progress_ms
	if elapsed_ms >= 400:
		if dist > _last_dist - 0.25:
			## ⚠️ 把**障碍半径**一并传进去（2026-09-26）：巨物（> 0.5 m）**不左右对调**，
			## 小障碍（友军 / 围墙）照旧交替 —— 于是"绕着一台弩车"是一条稳定的弧，
			## 而不是每 400 ms 换一次边的来回摆。
			_start_sidestep(blocker)
			var perp_small := Vector3(-to_target.normalized().z, 0.0, to_target.normalized().x)
			var sign_small := 1.0 if (_stuck_switches % 2) == 0 else -1.0
			velocity.x = perp_small.x * sign_small * current_speed()
			velocity.z = perp_small.z * sign_small * current_speed()
			_progress_ms = Time.get_ticks_msec()
			_last_dist = dist
			return
		_progress_ms = Time.get_ticks_msec()
		_last_dist = dist

	var move_dir := to_target.normalized()
	velocity.x = move_dir.x * current_speed()
	velocity.z = move_dir.z * current_speed()

## 被堵住时只做横向绕行，**不换目标**（换目标会违反"只打最近"）。
## ⚠️ 2026-09-19 优化（用户："弩车、投石车碰撞体积变大后会卡住后面的单位"）：绕行时长按**障碍物判定半径**
## 放大（`obstacle_radius` > 0.5 m 才算"巨物"）——0.26 s 只走 ~0.8 m，远小于弩车 5.76 m 的宽度，
## 原先单位只会在巨物前面左右摆。大障碍**不左右交替**（来回换边等于原地摆），小障碍保持既有交替行为。
##
## ⚠️ **2026-09-26 两处重算**（配合上面 `_tick_move()` 的"侧滑独占"）：
##   ① **时长 = 横移距离 ÷ 自己的移速**（`lateral = 障碍半径 + 自身判定半径 + UNIT_SIDESTEP_CLEARANCE`）——
##      旧写法是"每米障碍半径 420 ms"，隐含了"移速 ≈ 3 m/s"这个假设：慢单位（投石车 2.4 m/s）绕不动、
##      快单位（轻骑兵 7.0）白绕一大圈。按各自速度算之后，**一次侧滑正好清过一个障碍**：
##      人形障碍 ≈ 0.29 s（旧值 0.26 s，手感不变）、召唤石柱 1.10 ⇒ ≈0.53 s（旧口径只有 0.51 s，
##      而它 2.2 m 宽的盒子需要 ~1.5 m 横移 ⇒ 以前要连起两三次才过得去）、弩车 2.88 ⇒ ≈0.99 s。
##   ② **连续绕巨物三次没进展就换一次边**（`_stuck_big_strokes`）：巨物**平时不交替**是有意的，
##      但顶死在"盒子 + 围墙"的夹角里时，同一边连绕三次都过不去 ⇒ 允许它掉一次头再试，
##      节奏是 ~3 s 一次（读起来是"换个方向再试"，而不是用户报的"左右摇摆"）。
func _start_sidestep(obstacle_radius: float = 0.0) -> void:
	if obstacle_radius > GameConfig.UNIT_SIDESTEP_BIG_RADIUS:
		## 巨物：不每次换边，但连续 `UNIT_SIDESTEP_BIG_STROKES` 次没进展就换一次（见上面 ②）
		_stuck_big_strokes += 1
		if _stuck_big_strokes >= GameConfig.UNIT_SIDESTEP_BIG_STROKES:
			_stuck_big_strokes = 0
			_stuck_switches += 1
	else:
		_stuck_switches += 1
	var lateral := obstacle_radius + GameConfig.body_radius(type_id) + GameConfig.UNIT_SIDESTEP_CLEARANCE
	var ms := int(round(lateral / maxf(current_speed(), 0.01) * 1000.0))
	_sidestep_ms = Time.get_ticks_msec() + clampi(ms, GameConfig.UNIT_SIDESTEP_MIN_MS,
			GameConfig.UNIT_SIDESTEP_MAX_MS)

## 本帧侧滑碰撞里"挡路单位"的最大判定半径（没有则 0）。⚠️ 只认**单位**：世界 / 围墙不算，
## 那种情况仍走 0.4 s 的进度判据。
func _blocking_unit_radius() -> float:
	var biggest := 0.0
	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider() as Unit3D
		if other == null:
			continue
		biggest = maxf(biggest, GameConfig.body_radius(other.type_id))
	return biggest

## 当前攻击间隔 / 冷却（秒）：面板值（`attack_speed` 的倒数，见 `04_physics.md#3.5`），
## 圈外（兴奋圈）按 `CIRCLE_HIT_MULT` 加速。⚠️ 出手冷却与动画链**都只读这一处** ——
## 以前这段算式（含圈外倍率）在 `_animate_attack()` 与 `_tick_attack()` 里各写一遍，是漂移隐患。
func _attack_interval() -> float:
	var interval := GameConfig.attack_interval(type_id)
	if excited:
		interval /= GameConfig.CIRCLE_HIT_MULT
	## 肉鸽兵种科技：「狂暴」×0.5（= 攻速翻倍）。没有科技时 ×1.0 ⇒ 逐位不变。
	## ⚠️ 乘在**圈外加速之后**：两条都是倍率，谁先谁后等价（这里只是让"圈外"那条保持原样）。
	interval *= tech_interval_mult()
	interval *= float(aid_mods.get("interval_mult", 1.0))
	interval += float(aid_mods.get("interval_add", 0.0))
	return maxf(interval, 0.05)

func _tick_attack(delta: float) -> void:
	if _shield_lock_alive() and not _target_valid():
		if _shield_attack_ready(delta):
			_advance_hit_clock()
		return
	var intercepting := _can_fan_intercept()
	if not _target_valid():
		if not intercepting:
			_drop_intercept_claim()
			## 主锁没了只清主锁。另外几根射线各自留着自己的目标。
			if is_sustained_beam():
				_drop_laser_lock()
			if _hold_extra_beams(delta):
				return
			_state = State.IDLE
			return
	var to_target := target.global_position - global_position if _target_valid() else Vector3.ZERO
	to_target.y = 0.0
	## ⚠️ 修 bug（2026-09-18）：目标走出射程就退回 MOVE。
	## 原先这里只检查"目标还活着"，于是目标一走远，单位就留在 ATTACK 态**空挥**——
	## 这就是"对着空气攻击"。远程更严重：`_resolve_attack()` 那条分支原先**没有距离检查**，
	## 目标跑到 16 m 外它照样放箭（箭能飞 88 m），属于超射程伤害。
	## `02_entities.md#2.2` 的状态机本来就写明 ATTACK 的退出条件是"目标出射程/死亡 → MOVE"。
	if _target_valid() and not intercepting and (surface_distance_to(target) > attack_reach() \
			or surface_distance_to(target) < attack_min_reach()):
		_drop_intercept_claim()
		_state = State.MOVE
		## 同上（2026-09-19）：退出 ATTACK 只切状态。命中帧（`_next_hit_ms`）与冷却**不在这里复位**
		## ⇒ "出射程 → 走回来"不是一次免费的冷却重置；动画链由 `_animate_attack()` 的静止分支断开，
		## 回来时 `_tick_attack()` 会重新排"命中帧 − 前摇"，这一刀照旧从头挥。
		_striking = false
		## 主锁出了射程，只断主锁。其余射线还锁着自己的人时，继续照。
		if is_sustained_beam():
			_drop_laser_lock()
		if _hold_extra_beams(delta):
			return
		_state = State.MOVE
		return
	if intercepting:
		var shot := _pick_intercept_arrow()
		if shot != null:
			_face(shot.global_position - global_position, delta)
		elif _target_valid() and surface_distance_to(target) <= attack_reach():
			_face(to_target, delta)
	elif _target_valid() and surface_distance_to(target) <= attack_reach():
		_face(to_target, delta)

	## 心灵腐化师：**锁定后先蓄力**（用户："经过 0.5s 蓄力后持续攻击这个目标"）。
	## ⚠️ 换锁定对象要**重新蓄力** —— 判据是"我现在照的还是不是同一个人"（`_laser_target != target`），
	## 而不是"有没有目标"：否则"换个人接着照"会白拿一次续照。
	if is_sustained_beam():
		var laser_now := Time.get_ticks_msec()
		## 换人、或这次照射已经断过（离开过攻击态）⇒ 重新蓄力，伤害档清零。
		## 只认“人还是不是同一个”会漏掉一种情况：人没换，但光束中间灭过，旧档位还在。
		var need_arm := _laser_target != target or _laser_shield_id >= 0 or (not _laser_engaged and not _laser_arming)
		if need_arm:
			_laser_shield_id = -1
			_laser_target = target
			_laser_charge_until_ms = laser_now + GameConfig.UNIT_CORRUPT_CHARGE_MS
			_focus_hits = 0
			_focus_for = target
			_laser_engaged = false
			_laser_arming = true
			if _extra_beam_id() == "":
				return
		if _laser_arming and _charge_finished(_laser_charge_until_ms):
			_laser_arming = false
			_laser_engaged = true
			_focus_hits = 0
			_focus_for = target
		if _extra_beam_id() != "":
			_sync_beam_slots()
			if not _beam_slot_ready() and not _laser_engaged:
				return
		elif not _laser_engaged:
			return

	## ⚠️ 2026-09-19 用户："攻击速度重定义：将攻击变为类似技能冷却的样子…只要冷却结束就能攻击，
	## 所有单位现在的普通攻击都得跟着普攻动画" ⇒ 这里是**唯一的出手节拍**（不变量 I-13：绝对时刻，
	## 不再逐帧累加 `delta`）：`_next_hit_ms` = 这一刀的**命中帧**，冷却 = `_attack_interval()`。
	## 动画链的第 0 帧固定在"命中帧 − 前摇" ⇒ **命中那一刻动画时钟正好等于 `windup`**（= 顶点）；
	## 命中后**从这一帧重新冷却**（用户口径"在造成伤害后重新冷却"）⇒ 命中间隔恒等于面板间隔。
	## 由此得到两条硬性质：① **没有完整前摇就绝不会命中**——冷却没走完、刚进射程、刚换目标时，
	## 只会把命中帧往后排到"现在 + 前摇"；② **命中时动画一定在关键帧上**（不再有"半截动画就命中"）。
	## 拦截除外：场地已经在这一帧的飞行线段上结算过。这里再排前摇，快弹会在挥下去之前飞出 16 m。
	if _swing_from_ms <= 0 and _can_fan_intercept() and intercept_ready():
		return
	_advance_hit_clock()

## 出手节拍：命中帧到了才结算。盾和人共用这一段，免得两套冷却。
func _advance_hit_clock() -> void:
	var interval := _attack_interval()
	var windup := interval * GameConfig.windup_ratio(type_id)
	var now := Time.get_ticks_msec()
	var windup_ms := int(round(windup * 1000.0))
	var interval_ms := int(round(interval * 1000.0))
	if _swing_from_ms <= 0:
		## 没有在播的动画链 ⇒ 重新起手：冷却还没走完就等它走完；已经走完（或压根没有排程）
		## 就把命中帧排到"现在 + 前摇"。⚠️ 这里**不补偿**已经过去的冷却（不会白送一次出手）。
		if _next_hit_ms <= 0 or _next_hit_ms - now < windup_ms:
			_next_hit_ms = now + windup_ms
		_swing_from_ms = _next_hit_ms - windup_ms
	## 动画时钟 = "距动画链起点多久"，**按周期回绕**（0 = 起手、windup = 命中帧、interval = 收招结束）。
	## ⚠️ 锚点只在起手时定一次、**命中后不动**：于是收招（windup → interval）自然接上下一刀的起手（回绕到 0），
	## 而每一刀的命中帧都恰好落在 `windup` 上（实测定点验证：4 次命中时时钟 = 0.335/0.343/0.339/0.338 s）。
	## 锚点还在未来 = 冷却没走完、这一刀还没到起手窗口 ⇒ 时钟停 0（武器静止等待）。
	if _swing_from_ms > now:
		_attack_timer = 0.0
	else:
		_attack_timer = fposmod(float(now - _swing_from_ms) / 1000.0, interval)
	if now >= _next_hit_ms:
		## 命中帧到点（动画此刻正好在顶点 = 关键帧）：结算这一口，冷却**从这一帧往后推一整格**。
		## ⚠️ 用 `+= interval` 而不是 `= now + interval`：后者会把每帧的抖动（命中最多晚 1 帧）累加进
		## 动画相位（实测每周期 +8 ms ⇒ 几十秒后"命中时动画已经过了顶点"）。`+=` 让命中帧**锁在
		## 动画相位的网格上**（网格的原点就是刚命中的这一帧）⇒ 间隔恒等于面板值、相位永不漂移。
		_resolve_attack()
		_next_hit_ms += interval_ms

## 盾比最近的人更近时锁盾。锁点是朝向自己的那一圈边缘。照射期间不进这里。
func _lock_nearer_shield(nearest: Unit3D) -> bool:
	var arena := _arena()
	if arena == null or not arena.has_method("nearest_shield_rim"):
		return false
	var shield: Dictionary = arena.nearest_shield_rim(global_position, team)
	if shield.is_empty():
		return false
	var shield_gap := float(shield["gap"])
	var unit_gap := INF
	if nearest != null:
		var flat := nearest.global_position - global_position
		flat.y = 0.0
		unit_gap = flat.length()
	if shield_gap >= unit_gap:
		return false
	var shield_id := int(shield["id"])
	_shield_point = shield["point"]
	if _shield_lock_id == shield_id and target == null:
		return true
	_shield_lock_id = shield_id
	if target != null:
		target = null
		_striking = false
		_progress_ms = 0
		_last_dist = -1.0
	return true

## 这面盾还在，并且是敌方的。边缘点写进 `_shield_point`。
func _shield_lock_alive() -> bool:
	if not is_sustained_beam() or _shield_lock_id < 0:
		return false
	var arena := _arena()
	if arena == null or not arena.has_method("shield_rim"):
		_shield_lock_id = -1
		return false
	var info: Dictionary = arena.shield_rim(_shield_lock_id, global_position, team)
	if info.is_empty():
		_shield_lock_id = -1
		return false
	_shield_point = info["point"]
	return true

func _shield_gap() -> float:
	var flat := _shield_point - global_position
	flat.y = 0.0
	return flat.length()

func _tick_move_to_shield(delta: float) -> void:
	var to_aim := _shield_point - global_position
	to_aim.y = 0.0
	var gap := to_aim.length()
	if gap > 0.001:
		_face(to_aim, delta)
	var entry := attack_reach() - 0.05 if is_sustained_beam() else float(GameConfig.profile(type_id)["range"]) - 0.05
	if gap <= entry:
		_state = State.ATTACK
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if Time.get_ticks_msec() < _move_lock_until_ms or gap <= 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := to_aim / gap
	if Time.get_ticks_msec() < _sidestep_ms:
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var sign_side := 1.0 if (_stuck_switches % 2) == 0 else -1.0
		velocity.x = perp.x * sign_side * current_speed()
		velocity.z = perp.z * sign_side * current_speed()
		return
	var blocker := _blocking_unit_radius()
	if blocker > GameConfig.UNIT_SIDESTEP_BIG_RADIUS:
		_start_sidestep(blocker)
		var perp_big := Vector3(-dir.z, 0.0, dir.x)
		var sign_big := 1.0 if (_stuck_switches % 2) == 0 else -1.0
		velocity.x = perp_big.x * sign_big * current_speed()
		velocity.z = perp_big.z * sign_big * current_speed()
		return
	velocity.x = dir.x * current_speed()
	velocity.z = dir.z * current_speed()

## 照着盾：出射程就回去走，换一面盾就重新蓄力。蓄力没完时这一帧不出手。
func _shield_attack_ready(delta: float) -> bool:
	if not _shield_lock_alive():
		_drop_laser_lock()
		_state = State.IDLE
		return false
	if _shield_gap() > attack_reach():
		_state = State.MOVE
		_striking = false
		_drop_laser_lock()
		return false
	_face(_shield_point - global_position, delta)
	var now := Time.get_ticks_msec()
	var need_arm := _laser_shield_id != _shield_lock_id or (not _laser_engaged and not _laser_arming)
	if need_arm:
		_laser_shield_id = _shield_lock_id
		_laser_target = null
		_laser_charge_until_ms = now + GameConfig.UNIT_CORRUPT_CHARGE_MS
		_focus_hits = 0
		_focus_for = null
		_laser_engaged = false
		_laser_arming = true
		if _extra_beam_id() == "":
			return false
	if _laser_arming and _charge_finished(_laser_charge_until_ms):
		_laser_arming = false
		_laser_engaged = true
		_focus_hits = 0
		_focus_for = null
	if _extra_beam_id() != "":
		_sync_beam_slots()
		if not _beam_slot_ready() and not _laser_engaged:
			return false
	elif not _laser_engaged:
		return false
	return true

func _beam_split_ratio() -> float:
	var beam_id := _extra_beam_id()
	if beam_id == "":
		return 1.0
	var row := tech_def(beam_id)
	if row.is_empty():
		return 1.0
	return float(row.get("damage_ratio", row.get("corrupt_ratio", 1.0)))

## 这一下打在锁住的盾上。线段中途先碰到另一面盾，就记在先碰到的那面。
func _note_shield_damage(ratio: float) -> void:
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("note_shield_block"):
		return
	var amount := _outgoing_damage() * ratio
	if arena_node.has_method("damage_mult_for"):
		amount *= arena_node.damage_mult_for(team)
	amount *= level_mult()
	var info := {"id": _shield_lock_id, "point": _shield_point}
	if arena_node.has_method("shield_crossing"):
		var crossed: Dictionary = arena_node.shield_crossing(_beam_origin(), _shield_point, team)
		if not crossed.is_empty():
			info = crossed
	arena_node.note_shield_block(info, amount)

func _resolve_shield_beam() -> void:
	if not _shield_lock_alive() or _shield_gap() > attack_reach():
		return
	var charged := _charge_finished(_laser_charge_until_ms)
	if charged:
		_note_shield_damage(_beam_split_ratio())
	if _extra_beam_id() != "":
		_resolve_multi_beams(_outgoing_damage())
	## 盾上的这一下只给主锁加档。额外射线的档位在 `_resolve_multi_beams()` 里按各自的目标加。
	if is_doom_eye() and charged:
		if _focus_for != target:
			_focus_hits = 0
			_focus_for = target
		_focus_hits += 1

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.alive

## 地下、影子、余烬都不能当目标。上一帧锁上的人这帧钻进去，这一帧就松开。
func _drop_untargetable() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.is_burrowed() or target.is_in_shadow_form() or target.is_ember():
		target = null

## 索敌：**所有兵种一视同仁，只打距离最近的敌人**（优化 6）。
##
## 历史：这里曾有"远程优先选有射界的敌人"的覆盖规则（`_has_line_of_sight`），
## 那是为了修"短弓手被自家前排挡住就傻站着"。但箭矢本来就**穿过友军**（`arrow.gd#_resolve_segment`），
## 所以那条规则既不必要，又违反了"只打最近"——已删除。
func _find_target() -> Unit3D:
	var arena := _arena()
	if arena != null and arena.has_method("cached_nearest"):
		return arena.cached_nearest(self) as Unit3D
	var best: Unit3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not other.alive or other.team == team:
			continue
		## ⚠️ 2026-09-19：**潜地的单位不可被锁定**（用户："无法被锁定"）⇒ 索敌直接跳过。
		## ⚠️ 2026-09-25 第三轮：**影子形态同样不可被锁定**（用户裁决）—— 与潜地同一条口径。
		if other.is_burrowed() or other.is_in_shadow_form() or other.is_ember():
			continue
		var min_reach := attack_min_reach()
		if min_reach > 0.0 and surface_distance_to(other) < min_reach:
			continue
		var d := global_position.distance_squared_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best

func _face(dir: Vector3, delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(GameConfig.UNIT_ROTATION_SPEED * delta, 0.0, 1.0))

## **立刻**把朝向拧到 `dir`（不走平滑）—— 肉鸽第七块：用户"如果被影响，兵种的朝向改成信标第一段移动的
## 朝向" ⇒ 那一刻就是"改朝向"，不该让它在几十帧里慢慢转过去（平滑入口是 `_face()`，两者共用同一个式子）。
func set_facing(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	rotation.y = atan2(-flat.x, -flat.z)

## 接管 / 交还。接管时停掉正在自己放的技能，下一帧起只听玩家。
func set_piloted(on: bool) -> void:
	piloted = on
	pilot_attacking_clear()
	if not on:
		show_pilot_halo(false)
		return
	_interrupt_skill()
	if _lance_until_ms > 0:
		_end_lance()
	target = null
	_state = State.IDLE
	velocity.x = 0.0
	velocity.z = 0.0

func pilot_attacking_clear() -> void:
	_pilot_attack_armed = false

func show_pilot_halo(on: bool) -> void:
	set_hover_glow(on)


func set_range_glow(on: bool) -> void:
	if _range_glow == on:
		return
	_range_glow = on
	_sync_outline()


func set_hover_glow(on: bool) -> void:
	if _hover_glow == on:
		return
	_hover_glow = on
	_sync_outline()


func _sync_outline() -> void:
	var want := alive and (_range_glow or _hover_glow)
	if want == _outline_on or _visual == null:
		return
	_outline_on = want
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if want:
			if mesh.has_meta("outline_copy"):
				mesh.material_override = mesh.get_meta("outline_copy")
				continue
			var mat := mesh.material_override as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			copy.rim_enabled = true
			copy.rim = 0.9
			copy.emission_enabled = true
			copy.emission = Color(1.0, 0.94, 0.55)
			copy.emission_energy_multiplier = maxf(copy.emission_energy_multiplier, 1.8)
			mesh.set_meta("outline_source", mat)
			mesh.set_meta("outline_copy", copy)
			mesh.material_override = copy
		elif mesh.has_meta("outline_source"):
			mesh.material_override = mesh.get_meta("outline_source")

## 数字键：单技能兵只有 1 号位。武士大师 1 是冲刺、2 是居合斩。后撤自己触发。
## 影袭仍是挨打才触发。偏折仍是被动。
func pilot_cast_skill(slot: int = 1) -> void:
	if not piloted or not alive or is_incapacitated():
		return
	var skill := String(GameConfig.profile(type_id).get("skill", ""))
	var dir := _pilot_flat_aim()
	if skill == "master":
		if slot == 1:
			_pilot_cast_master_dash(dir)
		elif slot == 2:
			_pilot_cast_iai(dir)
		return
	if slot != 1:
		return
	match skill:
		"charge":
			_pilot_cast_charge(dir)
		"rocket_jump":
			_pilot_cast_jump(dir)
		"flame_burst":
			_pilot_cast_flame(dir)
		"charge_lance":
			_pilot_cast_lance(dir)

## 操控面板用的一行字：技能名、按键、冷却。没有主动技能就返回空串。
func pilot_skill_line() -> String:
	var skill := String(GameConfig.profile(type_id).get("skill", ""))
	var now := Time.get_ticks_msec()
	var key_name := InputBindings.key_label("pilot_skill")
	match skill:
		"charge":
			return _pilot_cd_line("冲撞", key_name, _charge_until_ms > 0, _skill_cd_until_ms, now)
		"rocket_jump":
			return _pilot_cd_line("跳跃", key_name, _jump_until_ms > 0, _skill_cd_until_ms, now)
		"flame_burst":
			if _flame_phase != Flame.IDLE:
				return _pilot_cd_line("炎爆", key_name, true, 0, now)
			if _pilot_flame_too_close():
				return "炎爆  [%s]  太近" % key_name
			return _pilot_cd_line("炎爆", key_name, false, 0, now)
		"charge_lance":
			if _lance_charges_left <= 0 and _lance_until_ms <= 0:
				return "冲刺  [%s]  已用完" % key_name
			return _pilot_cd_line("冲刺", key_name, _lance_until_ms > 0, _skill_cd_until_ms, now)
		"master":
			var dash_line := _pilot_cd_line("冲刺", key_name, _dash_until_ms > 0, _master_dash_cd_until_ms, now)
			var iai_line := _pilot_cd_line("居合斩", "2", _iai_phase != Iai.NONE, _iai_cd_until_ms, now)
			var back_line := _pilot_cd_line("后撤", "自动", _backstep_until_ms > 0, _backstep_cd_until_ms, now)
			return "%s\n%s\n%s" % [dash_line, iai_line, back_line]
		"burrow":
			var state_name := "地上"
			match _burrow:
				Burrow.SINKING:
					state_name = "钻入"
				Burrow.UNDER:
					state_name = "地下"
				Burrow.RISING:
					state_name = "钻出"
			return "潜地  自动  %s" % state_name
		_:
			return ""

func _pilot_cd_line(skill_name: String, key_name: String, casting: bool, until_ms: int, now: int) -> String:
	if casting:
		return "%s  [%s]  施放中" % [skill_name, key_name]
	var remain := maxi(until_ms - now, 0)
	if remain <= 0:
		return "%s  [%s]  就绪" % [skill_name, key_name]
	return "%s  [%s]  %.1f 秒" % [skill_name, key_name, float(remain) / 1000.0]

func _tick_pilot(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _jump_until_ms > 0:
		if now >= _jump_until_ms:
			_jump_until_ms = 0
			_release_ally_ghost()
		return
	if _charge_until_ms > 0:
		if now >= _charge_until_ms:
			_charge_until_ms = 0
			_pilot_charge_dir = Vector3.ZERO
			_release_ally_ghost()
		else:
			_charge_tick()
		return
	if _lance_until_ms > 0:
		_lance_tick()
		return
	if _flame_phase != Flame.IDLE:
		if _tick_flame_burst():
			return
	if String(GameConfig.profile(type_id).get("skill", "")) == "master":
		if _iai_phase != Iai.NONE and _iai_phase != Iai.SELF_ROOT:
			_tick_iai(now)
			velocity = Vector3.ZERO
			return
		if _dash_until_ms > 0:
			if _tick_pilot_master_dash(now):
				return
		if _tick_backstep(now):
			velocity = Vector3.ZERO
			return
	if is_burrower() and _tick_pilot_burrow(now):
		return
	if String(GameConfig.profile(type_id).get("skill", "")) == "summon":
		_tick_summon()
	var flat := _pilot_flat_aim()
	set_facing(flat)
	var wish := _pilot_wish()
	var can_move := not GameConfig.is_anchored(type_id)
	if is_burrower() and _burrow != Burrow.UNDER:
		can_move = false
	if is_burrower() and _burrow == Burrow.UNDER and now < _burrow_until_ms:
		can_move = false
	if can_move and wish.length_squared() > 0.0:
		wish = wish.normalized()
		var right := Vector3(-flat.z, 0.0, flat.x)
		var move := right * wish.x + flat * wish.y
		velocity.x = move.x * current_speed()
		velocity.z = move.z * current_speed()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_state = State.IDLE
	if is_burrower() and _burrow != Burrow.SURFACED:
		return
	if not _pilot_wants_attack():
		return
	_state = State.ATTACK
	if is_sustained_beam():
		target = _pilot_beam_victim()
		if target == null:
			_drop_laser_lock()
			_state = State.IDLE
			return
		_tick_attack(delta)
		return
	_advance_hit_clock()

func _pilot_wish() -> Vector2:
	var wish := Vector2.ZERO
	if Input.is_action_pressed("cam_forward"):
		wish.y += 1.0
	if Input.is_action_pressed("cam_back"):
		wish.y -= 1.0
	if Input.is_action_pressed("cam_left"):
		wish.x -= 1.0
	if Input.is_action_pressed("cam_right"):
		wish.x += 1.0
	return wish

func _pilot_wants_attack() -> bool:
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not Input.is_key_pressed(KEY_ALT)
	if not held:
		_pilot_attack_armed = true
		return false
	return _pilot_attack_armed

func _pilot_flat_aim() -> Vector3:
	var flat := Vector3(pilot_aim.x, 0.0, pilot_aim.z)
	if flat.length_squared() < 0.0001:
		flat = -global_transform.basis.z
		flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return flat.normalized()

func _pilot_melee_victim() -> Unit3D:
	var flat := _pilot_flat_aim()
	var min_dot := cos(deg_to_rad(GameConfig.CAM_PILOT_AIM_CONE_DEG))
	var best: Unit3D = null
	var best_dot := min_dot
	var arena := _arena()
	if arena == null:
		return null
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) > attack_reach() or surface_distance_to(other) < attack_min_reach():
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.0001:
			continue
		var facing := flat.dot(to_enemy.normalized())
		if facing >= best_dot:
			best_dot = facing
			best = other
	return best

func _pilot_beam_victim() -> Unit3D:
	var flat := _pilot_flat_aim()
	var best: Unit3D = null
	var best_along := INF
	var arena := _arena()
	if arena == null:
		return null
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) > attack_reach():
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		var along := flat.dot(to_enemy)
		if along <= 0.0:
			continue
		var side := (to_enemy - flat * along).length()
		if side > GameConfig.CAM_PILOT_BEAM_TOLERANCE:
			continue
		if along < best_along:
			best_along = along
			best = other
	return best

func _pilot_enemy_open(other: Unit3D) -> bool:
	return other != null and other != self and other.alive \
			and not other.is_burrowed() and not other.is_in_shadow_form() and not other.is_ember()

## 沿准星打出普通攻击。返回 true = 已经选好单体目标，交给原来的结算。
func _resolve_pilot_attack() -> bool:
	var arena := _arena()
	if arena == null:
		return false
	var aim := pilot_aim
	if aim.length_squared() < 0.0001:
		aim = -global_transform.basis.z
	aim = aim.normalized()
	var from := global_position + Vector3(0.0, 1.25, 0.0) - global_transform.basis.z * 0.5
	if is_ranged():
		var reach := maxf(float(GameConfig.profile(type_id)["range"]), 4.0)
		arena.spawn_arrow_along(self, from + aim * reach)
		return false
	if _spartan_throwing():
		var spartan := tech_def("spartan")
		var throw_range := float(spartan.get("throw_range", 16.0))
		var flat := _pilot_flat_aim()
		arena.spawn_spear_along(self, from + flat * throw_range, throw_range,
				float(spartan.get("throw_damage_mult", 1.5)))
		_spartan_thrown = true
		_move_lock_until_ms = Time.get_ticks_msec() + GameConfig.ROGUELIKE_SPARTAN_ROOT_MS
		return false
	if _saint:
		_resolve_cone_attack(360.0, 1.0)
		return false
	var arc_deg := float(GameConfig.profile(type_id).get("attack_arc_deg", 0.0))
	if arc_deg > 0.0:
		var bite_mult := 1.0
		if _first_bite_double:
			var ambush := tech_def("ambush")
			bite_mult = float(ambush.get("damage_mult", GameConfig.UNIT_SANDWORM_FIRST_BITE_MULT)) if not ambush.is_empty() else GameConfig.UNIT_SANDWORM_FIRST_BITE_MULT
		if _resolve_cone_attack(arc_deg, bite_mult, true) > 0:
			_first_bite_double = false
		return false
	var victim := _pilot_melee_victim()
	if victim == null:
		return false
	target = victim
	return true

func _pilot_cast_charge(dir: Vector3) -> void:
	if _charge_until_ms > 0 or Time.get_ticks_msec() < _skill_cd_until_ms:
		return
	_pilot_charge_dir = dir
	_charge_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_CHARGE_MAX_MS
	_skill_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_CHARGE_CD_MS
	_set_ally_ghost(true)

func _pilot_cast_jump(dir: Vector3) -> void:
	if _jump_until_ms > 0 or Time.get_ticks_msec() < _skill_cd_until_ms:
		return
	var air_s := float(GameConfig.UNIT_JUMP_AIR_MS) / 1000.0
	var travel := GameConfig.UNIT_JUMP_RANGE * tech_jump_mult()
	_jump_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_JUMP_AIR_MS
	_invuln_until_ms = _jump_until_ms + GameConfig.UNIT_JUMP_INVULN_MS
	_skill_cd_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_JUMP_CD_MS
	_set_ally_ghost(true)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	velocity = dir * (travel / air_s) + Vector3.UP * (0.5 * g * air_s)
	set_facing(dir)
	Events.fx_request.emit("unit_jump", global_position)

func _pilot_cast_flame(dir: Vector3) -> void:
	if _flame_phase != Flame.IDLE:
		return
	if bool(aid_mods.get("blast_once", false)) and aid_blast_used:
		return
	if _pilot_flame_too_close():
		return
	_pilot_flame_dir = dir
	_flame_phase = Flame.CHARGE
	_flame_until_ms = Time.get_ticks_msec() + GameConfig.UNIT_FLAME_CHARGE_MS
	_flame_charge_target = null
	velocity.x = 0.0
	velocity.z = 0.0

## 敌人中心距小于 `UNIT_FLAME_RANGE_MIN` 时不能起手，蓄力中也会取消。和自动作战的“太近不发动”同一道闸门。
func _pilot_flame_too_close() -> bool:
	var arena := _arena()
	if arena == null:
		return false
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if global_position.distance_to(other.global_position) < GameConfig.UNIT_FLAME_RANGE_MIN:
			return true
	return false

## 沿按下时的水平准星冲，最远 `UNIT_MASTER_DASH_RANGE`。面前有人进入攻击距离就停。
func _pilot_cast_master_dash(dir: Vector3) -> void:
	if has_meta("afterimage"):
		return
	var now := Time.get_ticks_msec()
	if now < _master_dash_cd_until_ms or now < _dash_lock_until_ms or _dash_until_ms > 0:
		return
	if _iai_phase != Iai.NONE or _backstep_until_ms > 0:
		return
	if dir.length_squared() < 0.0001:
		return
	_dash_dir = dir
	_pilot_dash_from = global_position
	_pilot_dash_stops_at_reach = not _pilot_front_in_reach(dir)
	_dash_until_ms = now + GameConfig.UNIT_MASTER_DASH_MAX_MS
	_master_dash_cd_until_ms = now + GameConfig.UNIT_MASTER_DASH_CD_MS + int(aid_mods.get("cd_add_ms", 0))
	set_facing(dir)

func _tick_pilot_master_dash(now: int) -> bool:
	var traveled := global_position - _pilot_dash_from
	traveled.y = 0.0
	var arrived := traveled.length() >= GameConfig.UNIT_MASTER_DASH_RANGE
	var in_reach := _pilot_dash_stops_at_reach and _pilot_front_in_reach(_dash_dir)
	if arrived or in_reach or now >= _dash_until_ms:
		_dash_until_ms = 0
		velocity.x = 0.0
		velocity.z = 0.0
		return false
	set_facing(_dash_dir)
	velocity.x = _dash_dir.x * GameConfig.UNIT_MASTER_DASH_SPEED
	velocity.z = _dash_dir.z * GameConfig.UNIT_MASTER_DASH_SPEED
	return true

func _pilot_front_in_reach(dir: Vector3) -> bool:
	var arena := _arena()
	if arena == null:
		return false
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) > attack_reach():
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.0001:
			continue
		if dir.dot(to_enemy.normalized()) >= 0.35:
			return true
	return false

## 沿按下时的准星起手。后撤段仍朝当时的背后，蓄力段不再因为没有锁定目标而取消。
func _pilot_cast_iai(dir: Vector3) -> void:
	if has_meta("afterimage"):
		return
	var now := Time.get_ticks_msec()
	if _iai_phase != Iai.NONE or now < _iai_cd_until_ms:
		return
	if _dash_until_ms > 0 or _backstep_until_ms > 0:
		return
	if dir.length_squared() < 0.0001:
		return
	_pilot_iai_dir = dir
	set_facing(dir)
	_start_iai(now)

func _pilot_cast_lance(dir: Vector3) -> void:
	if _lance_charges_left <= 0 or _lance_until_ms > 0:
		return
	if Time.get_ticks_msec() < _skill_cd_until_ms:
		return
	var now := Time.get_ticks_msec()
	_lance_until_ms = now + _lance_duration_ms()
	_lance_dir = dir
	_lance_sped_up = true
	_lance_stopped = false
	_lance_charges_left = maxi(_lance_charges_left - 1, 0)
	_lance_hit_units.clear()
	_lance_box_pending.clear()
	_lance_next_box_ms = 0
	_set_pass_all(true)
	set_facing(dir)
	Events.fx_request.emit("lance_charge", global_position)

## 操作沙虫时：周围（面板射程内）没有敌人就钻入，有敌人就钻出。
## 钻入前仍等 `UNIT_SANDWORM_SINK_DELAY_MS`，地下最短停留仍走原来的闸门。
## 返回 true = 这一帧还在过渡或刚起步，不能走、不能打。
func _tick_pilot_burrow(now: int) -> bool:
	var near := _pilot_enemy_near()
	match _burrow:
		Burrow.SURFACED:
			if near:
				_no_enemy_since_ms = 0
				return false
			if _no_enemy_since_ms <= 0:
				_no_enemy_since_ms = now
			if now - _no_enemy_since_ms < GameConfig.UNIT_SANDWORM_SINK_DELAY_MS:
				return false
			_burrow = Burrow.SINKING
			_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_SINK_MS
			_first_bite_double = false
			_set_burrow_physics(true)
			velocity.x = 0.0
			velocity.z = 0.0
			return true
		Burrow.UNDER:
			if now < _burrow_until_ms:
				velocity.x = 0.0
				velocity.z = 0.0
				return true
			if near and now >= _rise_after_ms:
				velocity.x = 0.0
				velocity.z = 0.0
				_burrow = Burrow.RISING
				_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_SINK_MS
				return true
			return false
		_:
			pass
	match _burrow:
		Burrow.SINKING:
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _burrow_until_ms:
				_burrow = Burrow.UNDER
				_burrow_until_ms = now + GameConfig.UNIT_SANDWORM_UNDER_DELAY_MS
				_rise_after_ms = now + GameConfig.UNIT_SANDWORM_UNDER_MIN_MS
			return true
		Burrow.RISING:
			velocity.x = 0.0
			velocity.z = 0.0
			if now >= _burrow_until_ms:
				_burrow = Burrow.SURFACED
				_no_enemy_since_ms = 0
				_set_burrow_physics(false)
				_attack_block_until_ms = now + GameConfig.UNIT_SANDWORM_SURFACE_DELAY_MS
				_stun_units_around(GameConfig.UNIT_SANDWORM_SURFACE_STUN_RADIUS,
						GameConfig.UNIT_SANDWORM_SURFACE_STUN_MS)
				_first_bite_double = true
				if not has_meta("brood"):
					_begin_sandstorm(now)
					_spawn_brood()
				_fx_burst_until_ms = now + BURROW_FX_BURST_MS
				velocity.x = 0.0
				velocity.z = 0.0
			return true
		_:
			return false

func _pilot_enemy_near() -> bool:
	var arena := _arena()
	if arena == null:
		return false
	var reach := float(GameConfig.profile(type_id)["range"])
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if not _pilot_enemy_open(other):
			continue
		if surface_distance_to(other) <= reach:
			return true
	return false

# ---------------------------------------------------------------- 扇子兵「拦截」
## 普通攻击打向 16 m 内还没派够人的敌方投射物。弓箭 1 下、子弹和投矛 2 下、弩箭和石弹 5 下。
## 开战 10 s 内打得中，10–20 s 越来越容易打空，20 s 起不再拦截。
var _intercept_arrow: Arrow = null

func _intercept_range() -> float:
	var row := tech_def("intercept")
	if row.is_empty():
		return 0.0
	return float(row.get("range", 16.0))

func _intercept_accuracy() -> float:
	if not has_tech("intercept"):
		return 0.0
	var arena := _arena()
	if arena == null or not arena.has_method("skirmish_elapsed_ms"):
		return 0.0
	var elapsed := int(arena.skirmish_elapsed_ms())
	if elapsed < 0:
		return 0.0
	if elapsed < GameConfig.FAN_INTERCEPT_FULL_MS:
		return 1.0
	if elapsed >= GameConfig.FAN_INTERCEPT_STOP_MS:
		return 0.0
	var span := float(GameConfig.FAN_INTERCEPT_STOP_MS - GameConfig.FAN_INTERCEPT_FULL_MS)
	return 1.0 - float(elapsed - GameConfig.FAN_INTERCEPT_FULL_MS) / span

func _pick_intercept_arrow() -> Arrow:
	var reach := _intercept_range()
	if reach <= 0.0:
		return null
	var best: Arrow = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("arrows"):
		var arrow := node as Arrow
		if arrow == null or not is_instance_valid(arrow) or not arrow.intercept_open():
			continue
		if arrow.team == team:
			continue
		var dist := global_position.distance_to(arrow.global_position)
		if dist > reach or dist >= best_dist:
			continue
		best = arrow
		best_dist = dist
	return best

func _can_fan_intercept() -> bool:
	if _intercept_accuracy() <= 0.0:
		return false
	if _intercept_arrow != null and is_instance_valid(_intercept_arrow) and _intercept_arrow.active:
		return true
	return _pick_intercept_arrow() != null

## 这一下普通攻击还没打出去，可以拿来拦截。前摇里的那一刀也能被抢走，冷却中的不行。
func intercept_ready() -> bool:
	if _intercept_accuracy() <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if _next_hit_ms <= now:
		return true
	if _swing_from_ms <= 0 or now < _swing_from_ms:
		return false
	var windup_ms := int(round(_attack_interval() * GameConfig.windup_ratio(type_id) * 1000.0))
	return _next_hit_ms - now <= windup_ms

## 线段 `from → to` 第一次碰到拦截圈的比例。碰不到返回 −1。已经在圈里算 0。
func intercept_segment_t(from: Vector3, to: Vector3) -> float:
	var reach := _intercept_range()
	if reach <= 0.0:
		return -1.0
	return _segment_sphere_t(from, to, global_position, reach)

func _segment_sphere_t(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
	var offset := from - center
	if offset.length() <= radius:
		return 0.0
	var step := to - from
	var a := step.dot(step)
	if a < 0.0000001:
		return -1.0
	var b := 2.0 * offset.dot(step)
	var c := offset.dot(offset) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var t_enter := (-b - root) / (2.0 * a)
	if t_enter >= 0.0 and t_enter <= 1.0:
		return t_enter
	var t_exit := (-b + root) / (2.0 * a)
	if t_exit >= 0.0 and t_exit <= 1.0:
		return t_exit
	return -1.0

## 这一刀在投射物碰到 16 m 的位置上落下。打空也占用这一次普通攻击。
func spend_intercept_swing(arrow: Arrow, at: Vector3) -> void:
	if arrow == null or not is_instance_valid(arrow) or not arrow.active:
		return
	if not intercept_ready():
		return
	var now := Time.get_ticks_msec()
	var interval := _attack_interval()
	var interval_ms := int(round(interval * 1000.0))
	var windup_ms := int(round(interval * GameConfig.windup_ratio(type_id) * 1000.0))
	_state = State.ATTACK
	_next_hit_ms = now + interval_ms
	_swing_from_ms = now - windup_ms
	_striking = true
	var aim := at - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		rotation.y = atan2(-aim.x, -aim.z)
	if randf() > _intercept_accuracy():
		return
	arrow.global_position = at
	arrow.confirm_intercept()
	var arena := _arena()
	if arena != null and arena.has_method("show_intercept_flash"):
		arena.show_intercept_flash(at)

func _drop_intercept_claim() -> void:
	if _intercept_arrow != null and is_instance_valid(_intercept_arrow):
		_intercept_arrow.release_intercept()
	_intercept_arrow = null

func _claim_intercept() -> void:
	if _intercept_arrow != null:
		return
	if _intercept_accuracy() <= 0.0:
		return
	var arrow := _pick_intercept_arrow()
	if arrow == null or not arrow.reserve_intercept():
		return
	_intercept_arrow = arrow

## 这一刀打在已经派定的那发上。打中（含打空）就吃掉这次普通攻击。
func _land_intercept() -> bool:
	if _intercept_arrow == null:
		return false
	var arrow := _intercept_arrow
	_intercept_arrow = null
	if not is_instance_valid(arrow) or not arrow.active:
		return false
	if randf() > _intercept_accuracy():
		arrow.release_intercept()
		return true
	var at := arrow.global_position
	arrow.confirm_intercept()
	var arena := _arena()
	if arena != null and arena.has_method("show_intercept_flash"):
		arena.show_intercept_flash(at)
	return true

## 这一刀优先打 16 m 里的敌方投射物，没有才打人。打空同样吃掉这次普通攻击。
func _land_open_intercept() -> bool:
	if _intercept_accuracy() <= 0.0:
		return false
	var shot := _pick_intercept_arrow()
	if shot == null:
		return false
	var aim := shot.global_position - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		rotation.y = atan2(-aim.x, -aim.z)
	if randf() > _intercept_accuracy():
		return true
	var at := shot.global_position
	shot.confirm_intercept()
	var arena := _arena()
	if arena != null and arena.has_method("show_intercept_flash"):
		arena.show_intercept_flash(at)
	return true

# ---------------------------------------------------------------- 攻击判定
func _resolve_attack() -> void:
	## ⚠️ 2026-09-19 用户："钻出地后 0.3 秒后才能攻击" ⇒ 会潜地的兵种在封锁窗口内**不结算伤害**
	##（出手动作照常走完，只是这一口咬空）。
	if is_burrower() and Time.get_ticks_msec() < _attack_block_until_ms:
		return
	if piloted and not is_sustained_beam():
		if not _resolve_pilot_attack():
			return
	elif _land_intercept() or _land_open_intercept():
		return
	if _shield_lock_alive() and not _target_valid():
		_resolve_shield_beam()
		return
	var arena := _arena()
	if not _target_valid():
		return
	var dist := global_position.distance_to(target.global_position)
	## 两种兵型共用同一个上限；远程这里原先**没有检查**，是"短弓手超射程放箭"的根因
	if surface_distance_to(target) > attack_reach() or surface_distance_to(target) < attack_min_reach():
		return
	if is_ranged():
		if arena != null:
			arena.spawn_arrow(self, target)
		return
	## ---- 肉鸽兵种科技（2026-09-27 第十二轮·第二批）两支**取代**常规出手的攻击 ----
	## ① Spartan 投矛：**每回合一发**、**无条件第一下必投**（用户当场选定；贴脸也投），射程 16 m、伤害 ×1.5。
	##    判据走 `_spartan_throwing()`（它同时管着"还没投过"），打出去之后 `_spartan_thrown` 置位
	##    ⇒ `attack_reach()` 里的 16 m 放宽同时消失，它回落成普通矛兵走上去近战。
	if _spartan_throwing():
		if arena != null:
			var spartan := tech_def("spartan")
			arena.spawn_spear_throw(self, target, float(spartan.get("throw_range", 16.0)),
					float(spartan.get("throw_damage_mult", 1.5)))
		_spartan_thrown = true
		_move_lock_until_ms = Time.get_ticks_msec() + GameConfig.ROGUELIKE_SPARTAN_ROOT_MS
		return
	## ② 剑圣的**旋风斩**：以自身为圆心、半径 = 2 × 射程（`saint_spin_radius()`）的**整圆**里所有敌方各吃一下。
	##    ⚠️ 直接复用扇形那套（`arc_deg = 360` ⇒ `half_cos = cos(180°) = -1` ⇒ 谁都在扇形里），
	##    差别只有"不看朝向"与"伤害走 `_outgoing_damage()`"（好让剑圣的 2.5 倍攻击生效）。
	if _saint:
		_resolve_cone_attack(360.0, 1.0)
		return
	## 扇形攻击（扇子兵，2026-09-18）：一次挥扇命中面前一片扇形里的**所有敌人**。
	## 目标本身也在扇形内（它就是正前方最近的敌人），所以不再走下面的单体结算。
	var arc_deg := float(GameConfig.profile(type_id).get("attack_arc_deg", 0.0))
	if arc_deg > 0.0:
		## 2026-09-19 用户："钻出地后的第一下攻击造成双倍伤害"。
		## 口径：**这一口命中的全部目标**都 ×2（整条扇形通路一起翻倍）；**咬空不算用掉**
		## （扇形里没人 ⇒ `hits == 0` ⇒ buff 留到下一次真正命中）；重新钻地在 `_tick_burrow()` 里清除。
		## ⚠️ 上面那道"浮出后 0.3 s 内咬空"的闸门是 `return`，压根走不到这里 ⇒ 不会误消耗。
		var bite_mult := 1.0
		if _first_bite_double:
			var ambush := tech_def("ambush")
			bite_mult = float(ambush.get("damage_mult", GameConfig.UNIT_SANDWORM_FIRST_BITE_MULT)) if not ambush.is_empty() else GameConfig.UNIT_SANDWORM_FIRST_BITE_MULT
		if _resolve_cone_attack(arc_deg, bite_mult, true) > 0:
			_first_bite_double = false
		return
	var knock := Vector3.ZERO
	var kb_scale := float(GameConfig.profile(type_id).get("knockback", 0.0))
	var kb_damage := float(GameConfig.profile(type_id).get("knockback_damage", 0.0))
	## 肉鸽兵种科技：「防御模式」给**我打出去的每一刀**额外 +2 击退数值（用户口径"攻击额外造成 2 的击退"）。
	## ⚠️ 加在攻击方这一侧（不是受击方）—— 击退数值是"这一击的参数"，与挨打的人是谁无关。
	kb_damage += tech_kb_bonus()
	var swings := maxi(int(GameConfig.profile(type_id).get("attacks_per_swing", 1)), 1)
	## 双持武器（狂战士，2026-09-18 R3）：一次出手**连续结算**两次（左右手各一次）。
	## ⚠️ 2026-09-19：不再用 `tap_knockback()` 闸门（它会吞掉离散出手的击退，见 `_charge_hit()` 的注释）。
	## 同一帧的两把斧不会叠成两倍冲量——`_add_knockback()` 内部按 `maxf` 取值。
	## ⚠️ **先取伤害、再清锚点**：「时候已到」的口径是"这一刀吃**当下**的蓄势值，**攻击后**重置"
	##（用户："每过一秒造成的伤害增加80，伤害上限为320，**攻击后重置**"）。
	## 顺序反了就会变成"这一刀打完才涨、而且吃的是 0"。
	var outgoing := _outgoing_damage()
	if _extra_beam_id() != "":
		_resolve_multi_beams(outgoing)
		return
	if is_shadow_demon():
		_hour_anchor_ms = Time.get_ticks_msec()
	var struck_at := target.global_position
	var landed := false
	for _swing in swings:
		if not target.alive:
			break
		knock = Vector3.ZERO
		if kb_scale > 0.0:
			knock = (target.global_position - global_position).normalized() * GameConfig.KNOCKBACK_SPEED * kb_scale
			knock.y = 0.0
		target.apply_hit(outgoing, self, knock, kb_damage, false, false, false, 0, 0.7, true)
		landed = true
	if landed:
		_holy_splash(struck_at, outgoing)
	## 「能量汇集」计数（2026-09-27 第十轮）：**这一下打中了**才算一下 —— 而"打的是不是同一个人"
	## 由上面的锁定段把关（换目标那一刻已清零）⇒ 这里只负责累加。
	## ⚠️ 放在 `apply_hit()` **之后**：目标可能已经被这一下打死，但"我打中了第 N 下"是既成事实
	##（下一帧丢锁时才清零）。
	if is_doom_eye():
		if _focus_for != target:
			_focus_hits = 0
			_focus_for = target
		_focus_hits += 1

## 扇形攻击（扇子兵 / 沙虫）：对面前 ±`arc_deg`/2、半径 = `attack_reach()` 内的每个敌人各结算一次
## 「伤害 × `damage_mult` + 击退数值」。每个敌人各自走 `tap_knockback()` 闸门（1 s 冷却），
## 所以同一次挥扇不会对同一个人重复击退——与单体攻击的规则完全一致。
## ⚠️ `damage_mult` 是 2026-09-19 为沙虫的"浮出后第一口双倍"加的（默认 1.0 ⇒ 扇子兵一个字节都没变）。
## 返回值 = **真正被打到的目标数**：调用方靠它决定要不要消耗那个"第一口"buff（0 = 咬空 ⇒ 保留）。
func _resolve_cone_attack(arc_deg: float, damage_mult: float = 1.0, from_melee: bool = false) -> int:
	var arena := _arena()
	if arena == null:
		return 0
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0
	forward = forward.normalized()
	var half_cos := cos(deg_to_rad(arc_deg * 0.5))
	var kb_scale := float(GameConfig.profile(type_id).get("knockback", 0.0)) + tech_kb_bonus()
	var hits := 0
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if other == null or not other.alive:
			continue
		## ⚠️ 2026-09-19：扇形群伤（扇子兵 / 沙虫）**跳过潜地单位**（不可锁定 ⇒ 也不该被扫到）
		if other.is_burrowed():
			continue
		var to_enemy := other.global_position - global_position
		to_enemy.y = 0.0
		var d := to_enemy.length()
		if surface_distance_to(other) > attack_reach():
			continue
		var dir := to_enemy / d
		if forward.dot(dir) < half_cos:
			continue
		var knock := Vector3.ZERO
		if kb_scale > 0.0:
			knock = dir * GameConfig.KNOCKBACK_SPEED * kb_scale
		other.apply_hit(_outgoing_damage() * damage_mult, self, knock, 0.0, false, false, false, 0, 0.7, from_melee)
		hits += 1
	if hits > 0:
		_note_aid_attack()
	return hits

## 动量转移：**被击退 / 冲撞 / 跳跃**三种位移都会把"本帧移动速度"的一部分传给撞到的人。
## 用 `tap_knockback()` 做闸门（每个单位 1 s 内只能被推一次），所以"多米诺"链条会自然衰减。
## ⚠️ **不区分敌我**：被击退的方向是"远离攻击者"，所以实际撞上的多半是**自己人**——
## 这正是要的效果（被长矛捅飞的人会把自己那一排撞散）。
## ⚠️ 2026-09-19 用户第六条：**技能位移（冲撞 / 跳跃）改成"纯穿过队友"** ⇒ 那两处传 `skip_allies = true`，
## 于是撞到谁就推谁、**不再把队友挤开**（击退那条路照旧推队友，多米诺不受影响）。
func _transfer_motion_momentum(motion: Vector3, skip_allies: bool = false) -> void:
	var push := Vector3(motion.x, 0.0, motion.z)
	if push.length_squared() < 0.01:
		return
	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider() as Unit3D
		if skip_allies and other != null and other.team == team:
			continue
		_push_other(other, push)

## 技能位移（冲撞 / 跳跃）专用的**按距离**对称判定。
## ⚠️ 为什么不能只靠 `get_slide_collision_count()`：那是**逐体顺序解算**的结果——
## A 先把 B 撞开、自己滑过去之后，轮到 B 移动时它前面已经空了，B 不再上报碰撞，
## 于是"两个狂战士互跳撞到一起"只有一方吃到动量（2026-09-19 实测）。
## 这里用 `KNOCKBACK_CONTACT_RADIUS` 找**真正贴在一起**的单位（双方各自都会跑一遍 ⇒ 对称）。
## ⚠️ 2026-09-19 修 bug（用户报告"弩车打人堆会炸开来，就算没和被击退单位触碰有时也会被击退"）：
## 原先这里借用了 `attack_reach()`——对**远程**兵种它就是射程（弩车 44 m）⇒ 一次击退会把半个场地
## 的同队单位全推一遍。传递的前提是"撞上"，所以改成一个身体接触半径。
func _transfer_motion_to_contacts(motion: Vector3, skip_allies: bool = false) -> void:
	var arena := _arena()
	if arena == null:
		return
	var speed := Vector3(motion.x, 0.0, motion.z).length()
	if speed < 0.01:
		return
	var reach := GameConfig.KNOCKBACK_CONTACT_RADIUS
	for node in arena.units:
		## ⚠️ `is_instance_valid` 这一道是**防御性**的：正常情况下 `Arena._on_unit_exiting` 会
		## 在单位 `queue_free` 时把它从 `arena.units` 里摘掉，所以这里永远读不到失效节点。
		## 但 `as Unit3D` 遇到**已释放**的对象会直接抛 `Trying to cast a freed object`
		##（2026-09-25 引擎内探针踩到：探针自己往 `arena.units` 塞节点、却没接 `tree_exiting`）。
		## 加这一道让"数组里混进失效节点"从**崩循环**降级为**跳过**，代价是一次函数调用。
		if not is_instance_valid(node):
			continue
		var other := node as Unit3D
		if other == null or other == self or not other.can_receive_momentum():
			continue
		## 技能位移（冲撞 / 跳跃）是"纯穿过"（2026-09-19 用户第六条）：按距离这条判定也要跳过己方，
		## 否则掩码虽然摘了、队友仍会被这半米内的距离判定悄悄推开。
		if skip_allies and other.team == team:
			continue
		## ⚠️ 2026-09-19（判定体对齐视觉）：那个 0.9 原本是"胶囊半径 0.38 × 2 + 余量"推出来的 ⇒
		## 判定体改成盒体之后必须按**双方身体的等效半径之和**取大值，否则两个巨物贴着也不算"撞上"。
		## 人形之间仍是 max(0.9, 0.76) = 0.9 ⇒ 行为一个字节都没变。
		var pair_reach := maxf(reach, GameConfig.body_radius(type_id) + GameConfig.body_radius(other.type_id))
		if global_position.distance_to(other.global_position) > pair_reach:
			continue
		var away := other.global_position - global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			continue
		_push_other(other, away.normalized() * speed)

## 把一次动量（未乘比例）结算给某个单位：走同一个闸门与同一个比例，
## 弩车击退的"传递带伤害"特例也在这里统一处理。
func _push_other(other: Unit3D, push: Vector3) -> void:
	if other == null or other == self or not other.can_receive_momentum():
		return
	if push.length_squared() < 0.01:
		return
	if not other.tap_knockback():
		return
	var scaled := push * GameConfig.KNOCKBACK_TRANSFER
	if _kb_damage > 0.0 and other.team == team:
		other.apply_hit(_kb_damage, self, scaled)
	else:
		other.receive_knockback(scaled)

func _die() -> void:
	if not alive:
		return
	alive = false
	_state = State.DEAD
	target = null
	## 弩车：阵亡时把弦松开——否则尸体会僵在"拉满"的姿态上（`_animate_attack` 死后不再推进）。
	_bow_draw = 0.0
	_apply_bow_draw(0.0)
	## 表现：阵亡时把炎爆的三段特效一起收掉（尸体不该继续冒火，火池也没人再驱动）
	_clear_flame_fx()
	## "穿队友"的待还原请求一并作废：`_die()` 稍后会把掩码改成"只留世界层"，己方层已经不在里面了
	_ghost_off_due_ms = 0
	## ⚠️ **冲刺的"穿过所有单位"必须在这里硬还原**：它把判定体 `disabled` 了，
	## 而下面阵亡分支只改 `collision_layer` / `collision_mask`、**不碰形状** ⇒
	## 不在这里 `_set_pass_all(false)` 的话，**尸体会带着一个停用的判定体**：
	## 重力由 `_grounded()` 的射线负责所以它还踩得住地，但"尸体能挡活人/滑行"那条会失效。
	## 直接还原（不走延时）：阵亡的观感远不如"尸体挡不住人"这个 bug 严重。
	_set_pass_all(false)
	## 影子形态（影袭）：阵亡时**先把人形放回来**再走阵亡演出 —— 否则尸体会是"一道贴地的影子"，
	## 而 `_tick_dying()` 还要靠 `_visual.rotation / position` 演倒地。
	## ⚠️ 走到这一支本身极罕见（影子形态是"无敌 + 不可被锁定"），纯粹是防御。
	if _shadow_until_ms > 0:
		_end_shadow()
	## 潜地：阵亡时立刻回到"露出地面"（否则尸体会埋在地板网格里，看不见），下沉量一起归零
	_burrow = Burrow.SURFACED
	_burrow_until_ms = 0
	_no_enemy_since_ms = 0
	_rise_after_ms = 0
	_sink = 0.0
	if _bar != null:
		_bar.visible = false
	## 2026-09-19 用户要求：**被击退致死**时，尸体先是实体——保留单位层碰撞与击退速度，
	## 被推着滑一段再消失。这是弩车"传递伤害"能落地的前提：一发 400 秒杀时，被秒的人
	## 以前会立刻 `collision_layer = 0`，根本飞不到同队单位身上，那条伤害永远传不出去。
	if is_knocked_back():
		_corpse_slide_until_ms = Time.get_ticks_msec() + GameConfig.CORPSE_SLIDE_MAX_MS
		velocity = Vector3(_kb.x, 0.0, _kb.z)
	else:
		velocity = Vector3.ZERO
		# 保留世界层碰撞，避免尸体陷进地面；不再被选为目标由 alive 判断保证
		collision_layer = 0
		collision_mask = 1
	var scored := killer()
	if scored != null and scored.alive:
		scored.receive_kill(self)
	Events.unit_died.emit(self)
	## ⚠️ **自爆放在"报丧"之后**：先把"我死了"这件事发出去（结算 / 战果 / 音频都听这条），
	## 再让这一炸去杀别人 —— 顺序反过来的话，被炸死的人会**先于**我的死讯结算。
	if is_self_destructor():
		_self_destruct()
	_energy_burst()

# ---------------------------------------------------------------- 心灵腐化（2026-09-25 第二轮新增）
## 被心灵腐化师的激光照到**一跳**：不掉血，只加腐化值（由 `apply_hit()` 分流进来）。
## `amount` = 那一道激光的"伤害"数值（`damage` 10）—— 也就是每跳叠的腐化值（8 跳/s ⇒ 80/s）。
func _add_corruption(amount: float, from: Unit3D) -> void:
	if not alive:
		return
	## 只有**敌方**腐化师照得到才算：友军的心灵腐化师不该策反自己人（否则同队两个腐化师会互相"传染"）。
	if from != null and is_instance_valid(from) and from.team == team:
		return
	corrupt += amount
	_corrupt_last_ms = Time.get_ticks_msec()
	_corrupt_from = from
	if from != null and is_instance_valid(from) and from.team == 0 and from.has_meta("squad_index"):
		_corrupt_contributors[from.get_instance_id()] = int(from.get_meta("squad_index"))
	## 反馈：沿用挨打那一下的白闪（激光照在身上要有"被照着"的观感）。
	## ⚠️ 但**不发 `unit_was_hit`**：那条信号的含义是"受伤"（僵持计时用），这里既没掉血、也没有
	## "受伤音效"（那两条音效早已按用户要求移除）。
	_flash = GameConfig.UNIT_HIT_FLASH_MS / 1000.0

## 每物理帧推进"心灵腐化值"：① 停照即清 ② 超过剩余血量就换边。
func _tick_corruption() -> void:
	if corrupt <= 0.0:
		return
	var now := Time.get_ticks_msec()
	## ① **停照即清**（用户裁决 2026-09-25："停止被照射就立即清零（只要存在至少一个心灵腐化师在攻击他
	## 就不会清零）"）⇒ 判据是"最近一次被照射距今是否超过 `UNIT_CORRUPT_HOLD_MS`"。
	## ⚠️ 这个宽限**必须大于一个照射间隔**（8/s ⇒ 125 ms），否则连续照射期间会被自己的间隙清掉 ——
	## 那正是用户那句话要防的事（"只要还有人在照就不清"）。
	if now - _corrupt_last_ms > GameConfig.UNIT_CORRUPT_HOLD_MS:
		corrupt = 0.0
		_corrupt_contributors.clear()
		_refresh_corrupt_bar()
		return
	## ② **换边判据**（用户："当一个单位的心灵腐化值大于自身剩余血量时，自动变成另一方的单位（保留血量）"）
	## ⚠️ 是**严格大于**（"大于"），等于不换 —— 与用户原话逐字对齐。
	if corrupt > hp and alive:
		_convert_to(1 - team)
		return
	_refresh_corrupt_bar()

## **整队换边**（用户口径："自动变成另一方的单位（保留血量）"）。
## ⚠️ 换边**不是只改一个 `team` 字段** —— 队伍在这个项目里是三类事实的共同来源，必须一起改：
##   ① `team` 本身：索敌（`_find_target()`）、扇形群伤（`arena.units_of_team(1 - team)`）、
##      战果的"剩余总血量"判定、`is_winding_up_at()` 的敌我判断都读它；
##   ② **碰撞层**（`1 << (team + 1)`）：不改的话它会被"原来那队"的箭继续判定、且继续挡住原来那队的人；
##   ③ **外观**：`_base_color`（模型底色）与血条贴图色，两者都取 `GameConfig.team_color(team)`。
## ⚠️ 血量**保留**（用户明确"保留血量"）—— 这里一个字节都没动 `hp`。
func _convert_to(new_team: int) -> void:
	var shares: Array = []
	for squad_index in _corrupt_contributors.values():
		shares.append(int(squad_index))
	_corrupt_contributors.clear()
	team = new_team
	corrupt = 0.0
	_corrupt_last_ms = 0
	collision_layer = 1 << (team + 1)          # 2 队 -> layer2，1 队 -> layer3（与 `setup()` 同式）
	collision_mask = 1 | (1 << 1) | (1 << 2)
	## 外观：躯干底色走**与 `_ready()` 同一个出处**（`UnitFactory.rest_body_color()`）——
	## 换边不该把影魔的墨色躯干染成队伍色；队伍色锚点件由 `_repaint_team_accents()` 单独重绘。
	_base_color = UnitFactory.rest_body_color(type_id, team)
	_repaint_team_accents()
	if _bar != null:
		_bar.texture = UnitFactory.health_bar_texture(_bar_ratio, GameConfig.team_color(team))
	## 换边后**旧目标必然是友军了** ⇒ 立刻丢锁，下一帧按新阵营重新索敌
	##（不丢的话它会站着不动、继续对"现在是自己人"的那个目标挥空，直到对方走出射程）。
	target = null
	_swing_from_ms = 0
	_drop_intercept_claim()
	_next_hit_ms = 0
	_striking = false
	_state = State.IDLE
	## ⚠️ "穿队友"的掩码幽灵要一起收拾：它记的是**旧队伍**的层位，换边后那个位已经不属于"己方"了。
	## 传 false = 还原成"己方层在掩码里"（用的是**新** team 算的位），并把待还原请求一并作废。
	_set_ally_ghost(false)
	_refresh_corrupt_bar()
	if _corrupt_from != null and is_instance_valid(_corrupt_from) and _corrupt_from.has_tech("control_heal"):
		heal_to_full()
	_notify_convert_xp(shares)

func _notify_convert_xp(shares: Array) -> void:
	if shares.is_empty():
		return
	var arena := _arena()
	if arena == null:
		return
	var root := arena.get_parent()
	if root == null:
		return
	for child in root.get_children():
		if child.has_method("award_convert_xp"):
			child.award_convert_xp(self, shares)
			return

## 腐化条刷新：只在 `corrupt > 0` 时出现；宽度跨档才重建贴图（与血条同一套省法）。
## ⚠️ 节点**懒建**（第一次真被腐化才建）：全场几十个单位，没被照过的那些不必各背一个 sprite。
func _refresh_corrupt_bar() -> void:
	if corrupt <= 0.0:
		if _corrupt_bar != null:
			_corrupt_bar.visible = false
		return
	if _corrupt_bar == null:
		_build_corrupt_bar()
	if _corrupt_bar == null:
		return
	_corrupt_bar.visible = true
	## 分母取**血上限**：用户判据是"腐化值 > 剩余血量"，而剩余血量 ≤ 血上限
	## ⇒ 满格正好对应"够把一个满血单位策反"。
	var ratio := clampf(corrupt / maxf(max_hp, 0.001), 0.0, 1.0)
	var fill_px := int(round(ratio * float(UnitFactory.HEALTH_BAR_INNER_PX)))
	if fill_px == _corrupt_fill_px:
		return
	_corrupt_fill_px = fill_px
	_corrupt_bar.texture = UnitFactory.health_bar_texture(ratio, CORRUPT_BAR_COLOR)

## 这道激光现在是不是**正照在目标身上**（= 已蓄力完 + 目标还在射程内 + 目标还是敌人）。
## 用来挡住"照射期间改锁"（用户："期间不会改变锁定目标"）。
func _cache_beam_fx() -> void:
	if _visual == null:
		return
	_orbit_root = _visual.get_node_or_null("OrbitOrbs") as Node3D
	_scatter_root = _visual.get_node_or_null("ScatterOrbs") as Node3D
	if _weapon != null:
		_charge_root = _weapon.get_node_or_null("ChargeGather") as Node3D
	if _charge_root != null:
		_charge_core = _charge_root.get_node_or_null("ChargeCore") as Node3D
		for child in _charge_root.get_children():
			if String(child.name).begins_with("ChargeMote_"):
				_charge_motes.append(child)
	if _orbit_root != null:
		for child in _orbit_root.get_children():
			var orbit_name := String(child.name)
			if orbit_name.begins_with("OrbitOrb_"):
				_orbit_orbs.append(child)
			elif orbit_name.begins_with("OrbitLeg_"):
				_orbit_legs.append(child)
	if _scatter_root != null:
		for child in _scatter_root.get_children():
			var node_name := String(child.name)
			if node_name.begins_with("ScatterOrb_"):
				_scatter_orbs.append(child)
			elif node_name.begins_with("ScatterMote_"):
				_scatter_motes.append(child)


func _hold_extra_beams(delta: float) -> bool:
	if _extra_beam_id() == "":
		return false
	_sync_beam_slots()
	var aim: Unit3D = null
	var reach := attack_reach()
	for index in range(1, 5):
		var unit := _beam_target_at(index)
		if _beam_target_ok(unit, reach):
			aim = unit
			break
	if aim == null:
		return false
	_state = State.ATTACK
	_face(aim.global_position - global_position, delta)
	if _beam_slot_ready():
		_advance_hit_clock()
	return true


func _beam_source(slot: int) -> Vector3:
	if is_corruptor() and has_tech("multi_beam") and slot >= 0 and slot < _orbit_orbs.size():
		var orb := _orbit_orbs[slot] as Node3D
		if orb != null:
			return orb.global_position
	if is_doom_eye() and has_tech("energy_scatter") and slot >= 0 and slot < _scatter_orbs.size():
		var ball := _scatter_orbs[slot] as Node3D
		if ball != null:
			return ball.global_position
	return _beam_origin()


func _update_beam_fx() -> void:
	var now := Time.get_ticks_msec()
	var multi := is_corruptor() and has_tech("multi_beam")
	if _orbit_root != null:
		_orbit_root.visible = multi
	if multi:
		_place_corruptor_orbs()
	var scatter := is_doom_eye() and has_tech("energy_scatter")
	if _scatter_root != null:
		_scatter_root.visible = scatter
	if scatter:
		_spin_scatter_orbs(now)
		_emit_scatter_pulses(now)
	_update_doom_charge(now, scatter)


func _place_corruptor_orbs() -> void:
	var rest: Array[Vector3] = [
		Vector3(0.0, 2.15, 0.0),
		Vector3(-0.86, 1.36, 0.04),
		Vector3(0.86, 1.36, 0.04),
		Vector3(-0.40, 1.78, -0.04),
		Vector3(0.40, 1.78, -0.04),
	]
	var back := Vector3(0.0, 1.22, 0.38)
	for i in _orbit_orbs.size():
		var orb := _orbit_orbs[i] as Node3D
		if orb == null or i >= rest.size():
			continue
		var progress := _orbit_charge_progress(i)
		orb.position = rest[i] + Vector3(0.0, 0.0, -0.16 * progress)
		if i >= _orbit_legs.size():
			continue
		var leg := _orbit_legs[i] as Node3D
		if leg == null:
			continue
		var tip := orb.position
		var bow := back.lerp(tip, 0.45)
		bow.x += signf(tip.x) * 0.22
		bow.y += 0.16
		bow.z += 0.2
		var line := leg.get_node_or_null("OrbitLegMesh") as MeshInstance3D
		if line != null:
			line.mesh = _leg_ribbon(back, bow, tip, progress)


func _orbit_charge_progress(slot: int) -> float:
	var until := _laser_charge_until_ms if slot == 0 else _beam_charge_at(slot)
	if until <= 0:
		return 0.0
	var now := Time.get_ticks_msec()
	if now >= until:
		return 1.0
	return clampf(1.0 - float(until - now) / float(GameConfig.UNIT_CORRUPT_CHARGE_MS), 0.0, 1.0)


func _quad_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c


func _leg_ribbon(back: Vector3, bow: Vector3, tip: Vector3, progress: float) -> ArrayMesh:
	var steps := 10
	var half := 0.03
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var point := _quad_bezier(back, bow, tip, t)
		var ahead := _quad_bezier(back, bow, tip, minf(t + 0.08, 1.0))
		var tangent := ahead - point
		if tangent.length_squared() < 0.0001:
			tangent = Vector3(0.0, 0.0, -1.0)
		var side := tangent.normalized().cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized() * half
		verts.append(point + side)
		verts.append(point - side)
		var bright := 1.0 if t <= progress else 0.12
		var color := Color(0.72, 0.40, 1.0, lerpf(0.22, 0.7, bright))
		colors.append(color)
		colors.append(color)
	for i in steps:
		var base := i * 2
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _emit_scatter_pulses(now_ms: int) -> void:
	if _scatter_root == null:
		return
	var clock := float(now_ms) * 0.001
	var index := 0
	for child in _scatter_root.get_children():
		var node := child as Node3D
		if node == null or not String(node.name).begins_with("ScatterPulse_"):
			continue
		var phase := fposmod(clock * 0.38 + float(index) * 0.125, 1.0)
		var ang := TAU * float(index) / 8.0
		var elev := lerpf(-0.7, 0.95, float(index % 4) / 3.0)
		var dir := Vector3(cos(ang) * cos(elev), sin(elev), sin(ang) * cos(elev))
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
		node.position = dir * lerpf(0.2, 1.6, phase)
		_set_pulse_alpha(node.get_node_or_null("Core") as MeshInstance3D, lerpf(0.92, 0.0, phase))
		_set_pulse_alpha(node.get_node_or_null("Haze") as MeshInstance3D, lerpf(0.22, 0.0, phase))
		index += 1


func _set_pulse_alpha(mesh: MeshInstance3D, alpha: float) -> void:
	if mesh == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	var color := mat.albedo_color
	color.a = alpha
	mat.albedo_color = color


func _spin_scatter_orbs(now_ms: int) -> void:
	var t := float(now_ms) * 0.001
	var speeds: Array[float] = [0.65, 1.15, 0.82, 1.45, 0.5]
	var radii: Array[float] = [0.92, 1.22, 1.02, 1.38, 0.84]
	for i in _scatter_orbs.size():
		var orb := _scatter_orbs[i] as Node3D
		if orb == null:
			continue
		var speed := speeds[i] if i < speeds.size() else 0.8
		var radius := radii[i] if i < radii.size() else 0.5
		var ang := t * speed + float(i) * 1.35
		var axis := Vector3(sin(float(i) * 1.17), 0.28 + 0.18 * float(i % 3), cos(float(i) * 0.83)).normalized()
		var local := Vector3(cos(ang) * radius, sin(ang * (0.55 + 0.12 * float(i))) * radius * 0.7, sin(ang) * radius)
		orb.position = local.rotated(axis, float(i) * 0.85)


func _charge_amount(until_ms: int, now_ms: int) -> float:
	if until_ms <= now_ms:
		return -1.0
	var span := float(GameConfig.UNIT_CORRUPT_CHARGE_MS)
	return clampf(1.0 - float(until_ms - now_ms) / span, 0.0, 1.0)


func _update_doom_charge(now_ms: int, scatter: bool) -> void:
	if not is_doom_eye() or _state != State.ATTACK:
		if _charge_root != null:
			_charge_root.visible = false
		for mote in _scatter_motes:
			var hidden := mote as Node3D
			if hidden != null:
				hidden.visible = false
		return
	var main_t := _charge_amount(_laser_charge_until_ms, now_ms) if _laser_target != null else -1.0
	if _charge_root != null:
		_charge_root.visible = not scatter and main_t >= 0.0
	if not scatter and main_t >= 0.0 and _charge_core != null:
		_charge_core.scale = Vector3.ONE * lerpf(0.35, 1.45, main_t)
		var shown := clampi(1 + int(main_t * float(_charge_motes.size())), 1, _charge_motes.size())
		for i in _charge_motes.size():
			var mote := _charge_motes[i] as Node3D
			if mote == null:
				continue
			mote.visible = i < shown
			var ang := TAU * float(i) / float(maxi(_charge_motes.size(), 1)) + main_t * 2.4
			var rad := lerpf(1.25, 0.04, main_t)
			mote.position = Vector3(cos(ang) * rad, sin(float(i) * 0.7) * 0.1, sin(ang) * rad)
	if not scatter:
		for mote in _scatter_motes:
			var hidden := mote as Node3D
			if hidden != null:
				hidden.visible = false
		return
	for i in _scatter_motes.size():
		var mote := _scatter_motes[i] as Node3D
		if mote == null:
			continue
		var slot := i % maxi(_scatter_orbs.size(), 1)
		var until := _laser_charge_until_ms if slot == 0 else _beam_charge_at(slot)
		var amount := _charge_amount(until, now_ms)
		mote.visible = amount >= 0.0
		if amount < 0.0 or slot >= _scatter_orbs.size():
			continue
		var orb := _scatter_orbs[slot] as Node3D
		if orb == null:
			continue
		var ang := TAU * float(i) / 5.0 + amount * 1.6
		var rad := lerpf(1.05, 0.02, amount)
		var offset := Vector3(cos(ang) * rad, sin(float(i)) * 0.18, sin(ang) * rad)
		mote.position = orb.position + offset


func _drop_laser_lock() -> void:
	_laser_target = null
	_laser_shield_id = -1
	_laser_charge_until_ms = 0
	_focus_hits = 0
	_focus_for = null
	_laser_arming = false
	_laser_engaged = false

func _clear_extra_beams() -> void:
	_beam_target_1 = null
	_beam_target_2 = null
	_beam_target_3 = null
	_beam_target_4 = null
	_beam_charge_ms_1 = 0
	_beam_charge_ms_2 = 0
	_beam_charge_ms_3 = 0
	_beam_charge_ms_4 = 0
	_beam_hits_1 = 0
	_beam_hits_2 = 0
	_beam_hits_3 = 0
	_beam_hits_4 = 0

func _beam_target_at(index: int) -> Unit3D:
	var raw: Variant = null
	match index:
		1:
			raw = _beam_target_1
		2:
			raw = _beam_target_2
		3:
			raw = _beam_target_3
		4:
			raw = _beam_target_4
	if not is_instance_valid(raw):
		return null
	return raw as Unit3D

func _set_beam_slot(index: int, unit: Unit3D, charge_ms: int) -> void:
	match index:
		1:
			_beam_target_1 = unit
			_beam_charge_ms_1 = charge_ms
		2:
			_beam_target_2 = unit
			_beam_charge_ms_2 = charge_ms
		3:
			_beam_target_3 = unit
			_beam_charge_ms_3 = charge_ms
		4:
			_beam_target_4 = unit
			_beam_charge_ms_4 = charge_ms

func _beam_charge_at(index: int) -> int:
	match index:
		1:
			return _beam_charge_ms_1
		2:
			return _beam_charge_ms_2
		3:
			return _beam_charge_ms_3
		4:
			return _beam_charge_ms_4
	return 0

func _beam_hits_at(index: int) -> int:
	match index:
		1:
			return _beam_hits_1
		2:
			return _beam_hits_2
		3:
			return _beam_hits_3
		4:
			return _beam_hits_4
	return 0

func _set_beam_hits(index: int, hits: int) -> void:
	match index:
		1:
			_beam_hits_1 = hits
		2:
			_beam_hits_2 = hits
		3:
			_beam_hits_3 = hits
		4:
			_beam_hits_4 = hits

## 湮灭之瞳某一档的这一下。主锁走 `_outgoing_damage()`，额外射线各自用自己的命中数。
func _doom_hits_damage(hits: int) -> float:
	var amount := GameConfig.doom_damage(GameConfig.doom_stage(hits)) * tech_damage_mult() * _damage_scale
	return amount * float(aid_mods.get("damage_mult", 1.0))

func _beam_target_ok(node: Variant, reach: float) -> bool:
	if not is_instance_valid(node):
		return false
	var unit := node as Unit3D
	if unit == null or not unit.alive or unit.team == team:
		return false
	if unit.is_burrowed() or unit.is_in_shadow_form() or unit.is_ember():
		return false
	return surface_distance_to(unit) <= reach

## 主锁蓄力完成，或任意一根额外射线已经蓄完。
func _beam_slot_ready() -> bool:
	var reach := attack_reach()
	if _charge_finished(_laser_charge_until_ms) and (_beam_target_ok(target, reach) or (_shield_lock_alive() and _shield_gap() <= reach)):
		return true
	for index in range(1, 5):
		var unit := _beam_target_at(index)
		if unit != null and unit != target and _charge_finished(_beam_charge_at(index)) and _beam_target_ok(unit, reach):
			return true
	return false

## 五根射线：第 0 根跟主锁走，另外四根各锁一个还没被主锁占上的人。主锁断了，这四根不跟着断。
func _extra_beam_id() -> String:
	if is_corruptor() and has_tech("multi_beam"):
		return "multi_beam"
	if is_doom_eye() and has_tech("energy_scatter"):
		return "energy_scatter"
	return ""

func _sync_beam_slots() -> void:
	var beam_id := _extra_beam_id()
	var row := tech_def(beam_id) if beam_id != "" else {}
	if row.is_empty():
		_clear_extra_beams()
		return
	var extra := clampi(int(row.get("beam_count", 5)) - 1, 0, 4)
	var reach := attack_reach()
	var now := Time.get_ticks_msec()
	var kept_units: Array[Unit3D] = []
	var kept_charges: Array[int] = []
	var kept_hits: Array[int] = []
	for index in range(1, extra + 1):
		var current := _beam_target_at(index)
		## 主锁刚换到这个人身上时，不能让额外槽里那根已经蓄完的射线接着打他。
		if current == null or current == target or not is_instance_valid(current) or not _beam_target_ok(current, reach):
			continue
		if not kept_units.has(current):
			kept_units.append(current)
			kept_charges.append(_beam_charge_at(index))
			kept_hits.append(_beam_hits_at(index))
	var pool: Array[Unit3D] = []
	for node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node):
			continue
		var other := node as Unit3D
		if other == null or not _beam_target_ok(other, reach) or other == target:
			continue
		if kept_units.has(other):
			continue
		pool.append(other)
	pool.sort_custom(func(a: Unit3D, b: Unit3D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	for other in pool:
		if kept_units.size() >= extra:
			break
		kept_units.append(other)
		kept_charges.append(now + GameConfig.UNIT_CORRUPT_CHARGE_MS)
		kept_hits.append(0)
	for index in range(1, 5):
		var slot := index - 1
		if slot < kept_units.size():
			_set_beam_slot(index, kept_units[slot], kept_charges[slot])
			_set_beam_hits(index, kept_hits[slot])
		else:
			_set_beam_slot(index, null, 0)
			_set_beam_hits(index, 0)

## 同一人身上的多根射线合成一次施加，避免同一帧连触发多次影袭。
func _resolve_multi_beams(outgoing: float) -> void:
	var beam_id := _extra_beam_id()
	var row := tech_def(beam_id) if beam_id != "" else {}
	if row.is_empty():
		return
	var ratio := float(row.get("damage_ratio", row.get("corrupt_ratio", 1.0)))
	var reach := attack_reach()
	var totals := {}
	var main_landed := false
	if _laser_target == target and _charge_finished(_laser_charge_until_ms) and _beam_target_ok(target, reach):
		totals[target] = outgoing * ratio
		main_landed = true
	var landed: Array[int] = []
	for index in range(1, 5):
		var unit := _beam_target_at(index)
		if unit == null or unit == target or not _charge_finished(_beam_charge_at(index)) or not _beam_target_ok(unit, reach):
			continue
		var amount := outgoing
		if is_doom_eye():
			amount = _doom_hits_damage(_beam_hits_at(index))
		totals[unit] = float(totals.get(unit, 0.0)) + amount * ratio
		landed.append(index)
	for key in totals.keys():
		if not is_instance_valid(key):
			continue
		var other := key as Unit3D
		if other != null:
			other.apply_hit(float(totals[key]), self)
	if is_doom_eye():
		if main_landed:
			if _focus_for != target:
				_focus_hits = 0
				_focus_for = target
			_focus_hits += 1
		for index in landed:
			_set_beam_hits(index, _beam_hits_at(index) + 1)

## 已经选定这个人（含蓄力还没完）。用来按住锁定，不拿来画射线。
func _laser_lock_held() -> bool:
	if _state != State.ATTACK or not is_sustained_beam():
		return false
	## 截止时刻是 0 表示还没开始蓄，不算锁住。人死了、出射程、变成友方，下面自然放开。
	if _laser_charge_until_ms <= 0:
		return false
	if _shield_lock_alive() and _laser_shield_id == _shield_lock_id:
		return _shield_gap() <= attack_reach()
	if not _target_valid() or _laser_target != target:
		return false
	if target.team == team:
		return false                      ## 目标"变成友方" ⇒ 这道光到此为止（用户原话）
	return surface_distance_to(target) <= attack_reach()

func _laser_beam_active() -> bool:
	return _laser_lock_held() and _charge_finished(_laser_charge_until_ms)

## 光束只画到面板射程。接触宽容仍留给伤害，免得线比出手更远。
func _beam_in_draw_range(unit: Unit3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return surface_distance_to(unit) <= beam_reach()

func _beam_origin() -> Vector3:
	if _weapon != null:
		return _weapon.global_position
	return global_position + Vector3(0.0, LASER_BEAM_FALLBACK_Y, 0.0)

## 射线穿进敌方魔法盾或「庇护」就停在交点上。没穿过就原样返回终点。
func _clip_beam_end(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("shield_crossing"):
		return to_pos
	var info: Dictionary = arena_node.shield_crossing(from_pos, to_pos, team)
	if info.is_empty():
		return to_pos
	return info["point"] as Vector3

## 这一下照射被盾挡住。挡住就记一笔盾伤，调用方不再把伤害打到人身上。
func _beam_stopped_by_shield(victim: Unit3D, amount: float) -> bool:
	if victim == null:
		return false
	var arena_node := _arena()
	if arena_node == null or not arena_node.has_method("shield_crossing"):
		return false
	var info: Dictionary = arena_node.shield_crossing(_beam_origin(), victim.global_position + Vector3(0.0, LASER_BEAM_AIM_Y, 0.0), team)
	if info.is_empty():
		return false
	if arena_node.has_method("note_shield_block"):
		arena_node.note_shield_block(info, amount)
	return true

## 召唤石柱（2026-09-25 第七轮）的**可见光束**：与腐化师那条**共用同一套几何与每帧摆位**
##（`_build_laser_beam()` / `_update_laser_beam()`），只是"什么时候亮"的判据不同 ——
## 石柱没有蓄力、也没有"持续照射"，它的光束就是**出手那一刻的可见弹道**。
## ⚠️ 它**不参与任何判定**：伤害仍走 `_resolve_attack()` 的"无弹体直击"那一支。
func _beam_shooter() -> bool:
	return is_sustained_beam() or bool(GameConfig.profile(type_id).get("beam", false))

func _beam_active() -> bool:
	if not bool(GameConfig.profile(type_id).get("beam", false)):
		return false
	if not _target_valid() or _state != State.ATTACK:
		return false
	return surface_distance_to(target) <= attack_reach()

## 激光的**可见光束**（2026-09-25 第二轮）：没有它，"激光式持续攻击"在画面上就是"敌人莫名掉血"。
## 做法：一根**不透明自发光**的细圆柱（`height = 1.0` ⇒ 用基向量把它在 Y 上拉到目标距离），
## 每帧重摆成"棱镜 → 目标"那条线段。
## ⚠️ **刻意用不透明材质**：透明 / 加色会引入新的着色器变体（本项目在"首次绘制现编译"上踩过 ——
## 沙盒第一次摆某个兵种卡一整帧，见 `02_entities.md#2.5` 的预热），而不透明自发光与既有人形的
## 自发光件走**同一条**管线 ⇒ 不需要额外预热。
## ⚠️ `top_level = true`：它是**世界坐标**的一条线段（目标会跑），不能跟着本体旋转 / 呼吸浮动。
func _build_laser_beam() -> void:
	_laser_beam = MeshInstance3D.new()
	_laser_beam.name = "LaserBeam"
	_laser_beam.top_level = true
	var mesh := CylinderMesh.new()
	mesh.top_radius = LASER_BEAM_RADIUS
	mesh.bottom_radius = LASER_BEAM_RADIUS
	mesh.height = 1.0                     ## 单位长度 ⇒ 用基向量直接拉到实际距离
	mesh.radial_segments = 6
	_laser_beam.mesh = mesh
	## 配色按兵种分流：腐化师紫、召唤石柱琥珀、**湮灭之瞳青白**（2026-09-27 第十轮加第三色）。
	## 三条都走**同一个不透明自发光**材质。
	var color := LASER_BEAM_COLOR if is_corruptor() else SUMMON_BEAM_COLOR
	var energy := LASER_BEAM_EMISSION if is_corruptor() else SUMMON_BEAM_EMISSION
	if is_doom_eye():
		color = DOOM_BEAM_COLOR
		energy = DOOM_BEAM_EMISSION
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	_laser_beam.material_override = mat
	_laser_beam.visible = false
	add_child(_laser_beam)
	_beam_stage_drawn = -1                ## 半径交给下面"按档位同步"那一段重设

## 每帧摆光束（只在"正照着"时可见）。⚠️ 光束从**棱镜**射出（`_weapon` 就是工厂返回的 `Prism`）——
## 没有武器节点时退回"本体上方 1.18 m"（与工厂里那颗棱镜的世界高度同值）。
func _update_laser_beam() -> void:
	if not _beam_shooter():
		return
	if is_sustained_beam() and _state != State.ATTACK:
		if _laser_beam != null:
			_laser_beam.visible = false
		_hide_extra_beams()
		return
	## "什么时候该亮"按兵种分流：**持续照射那一族**（腐化师 / 湮灭之瞳）= 正照着的持续激光；
	## 召唤石柱 = 出手窗口内的可见弹道。
	if _extra_beam_id() != "":
		if _laser_beam == null:
			_build_laser_beam()
		_sync_doom_beam_width()
		_update_multi_beams()
		return
	_hide_extra_beams()
	var on_shield := is_sustained_beam() and not _target_valid() and _shield_lock_alive()
	var lit := _beam_active()
	if on_shield:
		lit = _laser_beam_active() and _shield_gap() <= beam_reach()
	elif is_sustained_beam():
		lit = _laser_beam_active() and _beam_in_draw_range(target)
	if not lit:
		if _laser_beam != null:
			_laser_beam.visible = false
		return
	if not on_shield and not _target_valid():
		return
	if _laser_beam == null:
		_build_laser_beam()
	_sync_doom_beam_width()
	var to := _shield_point if on_shield else target.global_position + Vector3(0.0, LASER_BEAM_AIM_Y, 0.0)
	_place_beam_between(_laser_beam, to, 2, true)

func _hide_extra_beams() -> void:
	for index in range(1, 5):
		var beam := _extra_beam_node(index)
		if beam != null:
			beam.visible = false

func _extra_beam_node(index: int) -> MeshInstance3D:
	match index:
		1:
			return _extra_beam_1
		2:
			return _extra_beam_2
		3:
			return _extra_beam_3
		4:
			return _extra_beam_4
	return null

func _ensure_extra_beam(index: int) -> MeshInstance3D:
	var existing := _extra_beam_node(index)
	if existing != null:
		return existing
	var beam := MeshInstance3D.new()
	beam.name = "LaserBeam_%d" % index
	beam.top_level = true
	var mesh := CylinderMesh.new()
	mesh.top_radius = LASER_BEAM_RADIUS
	mesh.bottom_radius = LASER_BEAM_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 6
	beam.mesh = mesh
	var tint := DOOM_BEAM_COLOR if is_doom_eye() else LASER_BEAM_COLOR
	var glow := DOOM_BEAM_EMISSION if is_doom_eye() else LASER_BEAM_EMISSION
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = glow
	beam.material_override = mat
	beam.visible = false
	add_child(beam)
	match index:
		1:
			_extra_beam_1 = beam
		2:
			_extra_beam_2 = beam
		3:
			_extra_beam_3 = beam
		4:
			_extra_beam_4 = beam
	return beam

func _charge_finished(until_ms: int) -> bool:
	return until_ms > 0 and Time.get_ticks_msec() >= until_ms


func _update_multi_beams() -> void:
	var reach := beam_reach()
	var primary := _laser_beam if _laser_beam != null else _build_primary_beam()
	if _shield_lock_alive() and not _target_valid():
		var shield_lit := _laser_shield_id == _shield_lock_id and _charge_finished(_laser_charge_until_ms) and _shield_gap() <= reach
		_place_beam_between(primary, _shield_point, 0, shield_lit)
	else:
		var primary_lit := _laser_target == target and _charge_finished(_laser_charge_until_ms) and _beam_target_ok(target, reach)
		_place_one_beam(primary, target, 0, primary_lit)
	for index in range(1, 5):
		var unit := _beam_target_at(index)
		var ready := unit != null and _charge_finished(_beam_charge_at(index)) and _beam_target_ok(unit, reach)
		var beam := _extra_beam_node(index)
		if ready and beam == null:
			beam = _ensure_extra_beam(index)
		_place_one_beam(beam, unit, index, ready)

func _build_primary_beam() -> MeshInstance3D:
	_build_laser_beam()
	return _laser_beam

func _place_one_beam(beam: MeshInstance3D, node: Variant, slot: int, lit: bool) -> void:
	if beam == null:
		return
	if not lit or not is_instance_valid(node):
		beam.visible = false
		return
	var unit := node as Unit3D
	if unit == null:
		beam.visible = false
		return
	_place_beam_between(beam, unit.global_position + Vector3(0.0, LASER_BEAM_AIM_Y, 0.0), slot, true)

## 「能量汇集」换档时把主光束改粗。腐化师档位恒为 0，半径不动。
func _sync_doom_beam_width() -> void:
	if not is_doom_eye():
		return
	_set_cylinder_radius(_laser_beam, _doom_draw_radius(focus_stage()))
	for index in range(1, 5):
		var stage := GameConfig.doom_stage(_beam_hits_at(index))
		_set_cylinder_radius(_extra_beam_node(index), _doom_draw_radius(stage))


## 能量散射时，光束最粗不超过那五颗小球。没点这条时仍用原来的四档半径。
func _doom_draw_radius(stage: int) -> float:
	var radius := GameConfig.doom_beam_radius(stage)
	if not has_tech("energy_scatter"):
		return radius
	return minf(radius, _scatter_ball_radius())


func _scatter_ball_radius() -> float:
	if _scatter_orbs.is_empty():
		return 0.26
	var orb := _scatter_orbs[0] as Node3D
	if orb == null:
		return 0.26
	var core := orb.get_node_or_null("Core") as MeshInstance3D
	if core == null:
		return 0.26
	var sphere := core.mesh as SphereMesh
	if sphere == null:
		return 0.26
	return sphere.radius


func _set_cylinder_radius(beam: MeshInstance3D, radius: float) -> void:
	if beam == null:
		return
	var beam_mesh := beam.mesh as CylinderMesh
	if beam_mesh == null or is_equal_approx(beam_mesh.top_radius, radius):
		return
	beam_mesh.top_radius = radius
	beam_mesh.bottom_radius = radius

func _place_beam_between(beam: MeshInstance3D, to: Vector3, slot: int, lit: bool) -> void:
	if beam == null or not lit:
		if beam != null:
			beam.visible = false
		return
	var from := _beam_source(slot)
	var dir := to - from
	var dist := dir.length()
	if dist < 0.01:
		beam.visible = false
		return
	dir /= dist
	var side := Vector3.UP.cross(dir)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	to += side * float(slot - 2) * 0.18
	if is_sustained_beam():
		to = _clip_beam_end(from, to)
	dir = to - from
	dist = dir.length()
	if dist < 0.01:
		beam.visible = false
		return
	dir /= dist
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := up.cross(dir).normalized()
	var z_axis := dir.cross(x_axis).normalized()
	beam.global_transform = Transform3D(Basis(x_axis, dir * dist, z_axis), from + dir * (dist * 0.5))
	beam.visible = true

func _update_ward_ring() -> void:
	if not has_ward():
		if _ward_ring != null:
			_ward_ring.visible = false
		return
	if _ward_ring == null:
		_ward_ring = MeshInstance3D.new()
		_ward_ring.name = "WardRing"
		_ward_ring.top_level = true
		_ward_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := TorusMesh.new()
		var radius := ward_radius()
		mesh.inner_radius = maxf(radius - 0.16, 0.1)
		mesh.outer_radius = radius
		_ward_ring.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LASER_BEAM_COLOR
		mat.emission_enabled = true
		mat.emission = LASER_BEAM_COLOR
		mat.emission_energy_multiplier = LASER_BEAM_EMISSION
		_ward_ring.material_override = mat
		add_child(_ward_ring)
	var at := global_position
	_ward_ring.global_position = Vector3(at.x, 0.08, at.z)
	_ward_ring.visible = true

# ---------------------------------------------------------------- 影魔（2026-09-25 第三轮新增）
## 「影袭」：**受到任意伤害时**免疫那一下，化成影子扑到"伤害来源那一类单位"身边，变回原身并眩晕它 2 s。
## 返回值 = "这一次伤害被我吃掉了"（调用方 `apply_hit()` 据此直接返回）。
##
## 用户口径逐条落地：
##   · "冷却4s" ⇒ `UNIT_SHADOW_STRIKE_CD_MS`；
##   · "免疫此次伤害" ⇒ 本函数返回 true 时 `apply_hit()` 立刻返回（不掉血、不白闪、不击退）；
##   · "移动到伤害来源处（为简化，被什么种类的单位攻击则移动至**最近的那一类单位**）" ⇒
##     `_nearest_enemy_of_type(from.type_id)`；⚠️ **找的是"敌方"里最近的那一个**（友方的同类不算 ——
##     否则被长弓手射中却扑到自家弓手身边）。⚠️ 传递伤害 / 溅射伤害照样算：它们的 `apply_hit(from)` 带的是
##     真正的来源单位，所以"被弩车传递伤害"会扑向最近的弩车 ✓；
##   · "变回原身然后使**锁定单位**眩晕2s" ⇒ 落地那一刻重新索敌，晕**新锁定的那个**（用户 2026-09-25 选定）；
##   · "被眩晕则无法发动" ⇒ `is_incapacitated()` 里直接 return false（那一下照常结算）。
##     ⚠️ **定身一并挡住**：定身的定义就是"无法被位移"，而瞬移也是位移 —— 口径一致（用户只说了眩晕，
##     这一条按定身的既有定义推的）。
##   · "无来源的伤害"（兴奋圈内伤，`from == null`）⇒ 无从"扑向来源"，不发动（那一下照常结算）。
func _try_shadow_strike(from: Unit3D) -> bool:
	if not is_shadow_demon() or not alive or _shadow_until_ms > 0:
		return false
	var now := Time.get_ticks_msec()
	if now < _strike_cd_until_ms or is_incapacitated():
		return false
	if from == null or not is_instance_valid(from) or not from.alive:
		return false
	var dest := _nearest_enemy_of_type(from.type_id)
	if dest == null:
		return false
	_strike_cd_until_ms = now + GameConfig.UNIT_SHADOW_STRIKE_CD_MS
	var guard := tech_def("shadow_guard")
	if not guard.is_empty():
		_guard_until_ms = now + int(guard.get("duration_ms", 2000))
	_shadow_from = global_position
	_shadow_to = _shadow_landing(dest)
	var dist := _shadow_from.distance_to(_shadow_to)
	var ms := maxi(int(round(dist / GameConfig.UNIT_SHADOW_DASH_SPEED * 1000.0)), 1)
	_shadow_from_ms = now
	_shadow_until_ms = now + ms
	## 影子形态：**无敌 + 不可被锁定 + 谁都碰不到我**（用户 2026-09-25 裁决）——
	## 层清零 + 掩码只留世界层，与"冲刺穿过所有单位"同一手法。
	## ⚠️ **刻意不复用 `_set_pass_all()`**：那一套带**延时还原**（身边还有人就一直戴着，最多 600 ms），
	## 而这里的形态是**按计时结束**的 —— 复用会让"变回原身"之后还戴着幽灵掩码。
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	return true

## 「影袭」的推进（由 `_tick_skill()` 在 `skill == "shadow"` 时调；返回 true = 接管这一帧）。
## 只有"影子形态进行中"这一段需要推进：起终点线性插值，与「后撤步 / 拔刀斩后撤段」同一手法。
## ⚠️ 2026-09-25 第七轮：这一段的**外观**是"地上的一道影子"（用户："移动时会直接变成地上的影子，
## 到锁定单位面前时才会变回来"）—— 3D 模型由 `_process()` 里的 `is_in_shadow_form()` 藏掉，
## 这里只负责给那道影子**定向 + 顺着滑行方向拉长**，让它读起来是"贴着地面扑过去"。
func _tick_shadow() -> bool:
	if _shadow_until_ms <= 0:
		return false
	var now := Time.get_ticks_msec()
	var total := maxi(_shadow_until_ms - _shadow_from_ms, 1)
	var t := 1.0 - float(maxi(_shadow_until_ms - now, 0)) / float(total)
	global_position = _shadow_from.lerp(_shadow_to, clampf(t, 0.0, 1.0))
	_aim_shadow_form()
	if now >= _shadow_until_ms:
		_end_shadow()
	return true

## 把"地上那一道影子"摆正：朝向 = 本次滑行方向（本体在影子形态里**不转向** —— `_think()` 整段不跑），
## 并沿滑行方向拉长 `SHADOW_FORM_STRETCH` 倍。
## ⚠️ 影子的位置**不用写**：它是本体的子节点（局部原点在脚下）⇒ 本体被插值到哪儿，它就贴到哪儿。
func _aim_shadow_form() -> void:
	if _fx_shadow_form == null:
		return
	var travel := _shadow_to - _shadow_from
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		return
	var want_yaw := atan2(-travel.x, -travel.z)           ## 与 `_face()` 同一式：让局部 −Z 指向行进方向
	_fx_shadow_form.rotation.y = want_yaw - rotation.y    ## 影子挂在本体下 ⇒ 写的是**相对**本体的方位角
	_fx_shadow_form.scale = Vector3(1.0, 1.0, SHADOW_FORM_STRETCH)

## 变回原身：还原碰撞 → 「时候已到」直接封顶 → 重新索敌 → 眩晕那个单位。
func _end_shadow() -> void:
	_shadow_until_ms = 0
	_shadow_from_ms = 0
	velocity = Vector3.ZERO
	## 影子收掉、人形放回来（用户口径的"到锁定单位面前时才会变回来"）。
	## ⚠️ `visible` 的**常态**由 `_process()` 每帧按 `is_in_shadow_form()` 同步，这里只是"当场"收一下，
	## 免得结算画面 / 暂停这类不再跑 `_process` 的场合留下一道多余的影子。
	if _fx_shadow_form != null:
		_fx_shadow_form.visible = false
		_fx_shadow_form.scale = Vector3.ONE
	if _visual != null:
		_visual.visible = true
	collision_layer = 1 << (team + 1)          # 与 `setup()` 同式：2 队 -> layer2，1 队 -> layer3
	collision_mask = 1 | (1 << 1) | (1 << 2)
	## 用户："从影子状态变回原身时**自动到达伤害上限**" ⇒ 把锚点回拨满额所需的 3 s（= (320−80)/80），
	## 于是 `_outgoing_damage()` 当场读出 **320（总伤害封顶）**。
	## ⚠️ 用一个"回拨"而不是另加一个 bool 标志：少一个状态，也不会与"攻击后重置"打架
	##（出手时把锚点设回 now 即可，两条路共用同一个字段）。
	_hour_anchor_ms = Time.get_ticks_msec() - GameConfig.UNIT_SHADOW_HOUR_FULL_MS
	## "变回原身然后使**锁定单位**眩晕 2 s" ⇒ 先按常规重新索敌（落地后最近的那个），再晕它。
	_lock_nearest_target()
	if _target_valid():
		target.apply_stun(GameConfig.UNIT_SHADOW_STUN_MS)

## 「时候已到」（被动）：**距上次出手每满 1 秒伤害 +80，封顶 320 —— 而 320 是这一刀的"总伤害"**。
## ⚠️ **2026-09-25 第四轮（用户："影魔的伤害封顶320是总伤害不是额外伤害"）**：封顶加在**总量**上，
## 不是"面板 80 再加 320"。⇒ 读数只可能是 **80 / 160 / 240 / 320** 四档（第三轮那版会到 400，已作废）。
## ⚠️ 用"整秒"而不是连续值（用户原话"每过一秒…增加80"）。
## ⚠️ 只有影魔走这一支 ⇒ 其它兵种与 `GameConfig.hit_damage()` **逐位相同**（不给全场带来任何数值漂移）。
## ⚠️ **2026-09-27 第十轮**：湮灭之瞳也走这里 —— 它的「能量汇集」按档位取
## `GameConfig.doom_damage(focus_stage())`（30 / 90 / 300）。⚠️ 同样"只有它走这一支"（其余兵种照旧表值）。
func _outgoing_damage() -> float:
	## ⚠️ **2026-09-27 第十二轮**：「精英猎手」（短弓手科技，每级 +7% 伤害）是**独立乘区**，
	## 乘在"这一刀/这一箭的基础值"上 —— 近战走本函数、远程走 `Arrow` 里那一处（两处各乘一次，
	## 不会重复）。没有科技时 ×1.0 ⇒ 逐位不变。
	var amount := 0.0
	if is_doom_eye():
		amount = GameConfig.doom_damage(focus_stage()) * tech_damage_mult() * _damage_scale
	elif not is_shadow_demon():
		amount = GameConfig.hit_damage(type_id) * tech_damage_mult() * _damage_scale
	else:
		var seconds := float(Time.get_ticks_msec() - _hour_anchor_ms) / 1000.0
		var ramped := GameConfig.hit_damage(type_id) + float(int(seconds)) * GameConfig.UNIT_SHADOW_HOUR_STEP
		amount = minf(ramped, GameConfig.UNIT_SHADOW_HOUR_MAX) * tech_damage_mult() * _damage_scale
	return amount * float(aid_mods.get("damage_mult", 1.0))

## "最近的那一类单位"：**敌方**里 `type_id` 与 `tid` 相同的、距离最近的一个（潜地的跳过 —— 它不可被锁定）。
func _nearest_enemy_of_type(tid: String) -> Unit3D:
	var best: Unit3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team or other.type_id != tid or other.is_burrowed():
			continue
		var d := global_position.distance_squared_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best

## 落点：**贴着目标站**，而不是与它重合（两个胶囊叠在一起会被引擎的穿透修正弹开）。
## 取"自己的出手距离 × `UNIT_SHADOW_LAND_RATIO`"（0.9）⇒ 落地就够得着，但还留了一点余量。
func _shadow_landing(dest: Unit3D) -> Vector3:
	var dir := global_position - dest.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD           # 完全重合时随便挑一个方向，避免 NaN
	dir = dir.normalized()
	var land := dest.global_position + dir * (attack_reach() * GameConfig.UNIT_SHADOW_LAND_RATIO)
	land.y = global_position.y
	return land

# ---------------------------------------------------------------- 召唤石柱（2026-09-25 第七轮，**仅沙盒模式**）
## 技能「单位召唤」（由 `_tick_skill()` 在 `skill == "summon"` 时调；**不接管帧**，见那里）。
##
## 用户口径："在战斗开始前60s，每5s会召唤随机一个召唤石柱以外的单位（要保证以后新增单位时
## 会自动加入召唤石柱的召唤名单），每过60s则多召唤一个，最多4个。"
##   · **时间锚点**：`Arena.skirmish_elapsed_ms()`（沙盒的开战时刻）——
##     ⚠️ 不能借 `match_start_ms`：沙盒**从不启赛程**（`match_active` 恒为假），那个字段永远是 0；
##   · **名单**：`GameConfig.summon_candidates()` 现推（`TYPE_ORDER` − 石柱自己，可选按权重上限过滤）
##     ⇒ 以后新增兵种**自动进名单**，这一处不需要跟着改；
##   · **每拍几个**：`1 + ⌊已过 / 60 s⌋`，封顶 `UNIT_SUMMON_MAX_BATCH`(4) ⇒ 0~60 s 每拍 1 个、
##     60~120 s 每拍 2 个、120~180 s 每拍 3 个、180 s 起每拍 4 个；
##   · **「权重递增模式」**（沙盒里玩家开局选的开关，读 `Arena.summon_escalation`）：开着时那一拍
##     只从"单兵权重 ≤ `GameConfig.summon_weight_cap()`"的兵种里抽。
##
## ⚠️ **2026-09-26 用户（"召唤石柱在战斗开始的一瞬间就会召唤一个兵种"）：第一拍提到开战那一刻** ——
## 拍号由 `⌊已过 / 5 s⌋` 改成 **`1 + ⌊已过 / 5 s⌋`**（于是 `elapsed = 0` 就是第 1 拍），
## 之后仍是每 5 s 一拍。⚠️ 改前那版的 `elapsed = 0 ⇒ due = 0` 正好被下面那句 `due <= _summon_tick`
## 挡掉（`_summon_tick` 从 0 起）⇒ 第一拍永远在开战后 5 s；**新口径下"开战那一帧"与"每 5 s"是同一条式子**，
## 不需要额外的特判，也不会重复召唤（结算完就把 `_summon_tick` 推到当前拍号）。
##
## ⚠️ 拍号（`_summon_tick`）**只记"已经结算到第几拍"**，不记"下一拍在什么时刻"：
## 时间唯一地来自场地那个绝对时刻，于是暂停恢复只需要平移场地的那一个字段
##（`Arena.shift_deadlines()`），这里天然不会漏账、也不会重复召唤。
func _tick_summon() -> void:
	var arena := _arena()
	if arena == null or not arena.has_method("skirmish_elapsed_ms"):
		return
	var elapsed := int(arena.skirmish_elapsed_ms())
	if elapsed < 0:
		return                              ## −1 = 现在没在战斗（布兵阶段 / 已收兵 / 已拆场）
	var due := 1 + elapsed / GameConfig.UNIT_SUMMON_INTERVAL_MS      ## 走完几拍（**开战那一帧就算第 1 拍**）
	if due <= _summon_tick:
		return
	_summon_tick = due
	var batch := mini(1 + elapsed / GameConfig.UNIT_SUMMON_WINDOW_MS, GameConfig.UNIT_SUMMON_MAX_BATCH)
	var candidates: Array = GameConfig.summon_candidates(elapsed, bool(arena.summon_escalation))
	if candidates.is_empty():
		return                              ## 理论上不会发生（第一档就有 4 个权重 1 的兵种），但仍不猜
	for _i in batch:
		_summon_one(arena, candidates)

## 召唤**一个**单位：名单里随机取一个兵种，摆到"以石柱为心的一个随机方位、半径
## `UNIT_SUMMON_RING_RADIUS`"的圆环上（夹回场地内，不摆到墙外）。
## ⚠️ 必须**手动把 `active` 置真**：`Arena.spawn_unit()` 建出来的单位一律是"未点火"的
##（沙盒布兵阶段要的就是那个），而战斗中刷出来的召唤物若不带这一句就会站着不动。
func _summon_one(arena: Node, candidates: Array) -> void:
	var picked := String(candidates[randi_range(0, candidates.size() - 1)])
	var angle := randf() * TAU
	var at := global_position + Vector3(cos(angle), 0.0, sin(angle)) * GameConfig.UNIT_SUMMON_RING_RADIUS
	at = _clamp_into_arena(at)
	var facing := GameConfig.team_spawn_sign(team) * PI * 0.5     ## 与沙盒摆兵 / 出生朝向同一式（I-30 / I-35）
	## ⚠️ 显式标注类型：`arena` 是 `Node`（由 `_arena()` 按方法名找出来的），`spawn_unit()` 的返回值
	## 在它眼里是 Variant ⇒ 用 `:=` 会报"无法推断类型"（实测：`GDScript::reload` 的 Parse Error）。
	var unit: Unit3D = arena.spawn_unit(team, picked, at, facing)
	if unit == null:
		return
	unit.active = true
	_summon_count += 1

## **死亡自爆**（玉面手雷王，用户："当自身死亡时，对自身范围 4m 以内的敌人造成 150 点伤害"）。
## ⚠️ 只在**真正阵亡**时炸（唯一调用点是 `_die()`）：沙盒里"右键收兵"、退出战斗、拆场景都走
## `_remove_unit()` / `queue_free()`，**不该引爆** —— 那不是死亡，是玩家把他拿走了。
## ⚠️ 半径按**中心距**算（与石弹落点溅射同一口径）：自爆是以自己为中心的球，不是"接触判定"。
## ⚠️ **连环爆是刻意的**：A 炸死 B ⇒ B 的 `_die()` 里再炸一次；递归深度受场上单位数天然限制。
func _self_destruct() -> void:
	var radius := GameConfig.UNIT_GRENADE_BLAST_RADIUS
	var damage := GameConfig.UNIT_GRENADE_BLAST_DAMAGE * tech_blast_mult()
	## 表现：复用场地的**落点扬尘池**（`Arena.show_impact_dust()`，池容量 4、预建不现造）。
	## 用户没单独要爆炸特效，而"每次现造一套网格 + 透明材质"会让渲染管线现编译着色器
	##（本项目在石弹扬尘上踩过：一出现就卡一帧，见 `00_world.md#4.4` 的预建池口径）。
	var arena := _arena()
	if has_tech("acid_bomb") and arena != null and arena.has_method("place_acid"):
		var acid := tech_def("acid_bomb")
		arena.place_acid(global_position, float(acid.get("radius", 2.0)),
				float(acid.get("tick_ratio", 0.0)), float(acid.get("vuln_mult", 1.0)))
	if arena != null and arena.has_method("show_impact_dust"):
		arena.show_impact_dust(global_position, radius)
	## 爆炸本体（`UnitFactory#_build_grenadier_blast_fx()` 建的那一组几何，出厂即隐藏）。
	## ⚠️ **借用火焰拳那套现成机制**：`_update_flame_fx()` 里 `hit_t > 0` 就显示 ⇒ 只要把
	## `_fx_hit_until_ms` 置成"未来某刻"即可，**不需要新状态机、也不需要新常量**
	##（时长复用 `FLAME_FX_HIT_MS`；两处必须用同一个时长，否则 `_fx_elapsed()` 的归一化 t 会错档）。
	## ⚠️ `_die()` 不会关 `_process`（阵亡演出走 `_tick_dying()`，`queue_free()` 发生在淡出之后）
	## ⇒ 这一帧之后 `_update_flame_fx()` 照常跑，特效真的会亮起来。
	_fx_hit_until_ms = Time.get_ticks_msec() + FLAME_FX_HIT_MS
	## 伤害排进场地的队列，一帧只结算几发。连环爆会晚一两帧，半径和伤害不变。
	if arena != null and arena.has_method("queue_blast"):
		arena.queue_blast(global_position, radius, damage, self, team, true)
		return
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.team == team:
			continue
		## 潜地单位跳过：它"不可锁定 + 免疫一切状态"（用户口径），自爆也不该把它从地里炸出来。
		if other.is_burrowed():
			continue
		if global_position.distance_to(other.global_position) > radius:
			continue
		other.apply_hit(damage, self)

## 火焰拳「能量爆发」：死亡时以自己为中心再炸一次。伤害是本场到过的最大生命，友方也吃。
func _energy_burst() -> void:
	## 人已经倒下，`has_tech()` 不再看沉默。死亡这一下仍按倒下前的沉默算。
	if Time.get_ticks_msec() < _silence_until_ms or not _tech.has("energy_burst"):
		return
	var row: Dictionary = _tech["energy_burst"]
	var radius := float(row.get("radius", 6.0))
	var damage := _peak_max_hp if _peak_max_hp > 0.0 else max_hp
	if damage <= 0.0:
		return
	var arena_node := _arena()
	if arena_node != null and arena_node.has_method("show_impact_dust"):
		arena_node.show_impact_dust(global_position, radius)
	_fx_hit_until_ms = Time.get_ticks_msec() + FLAME_FX_HIT_MS
	for node in get_tree().get_nodes_in_group("units"):
		var other := node as Unit3D
		if other == null or other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.is_burrowed():
			continue
		if global_position.distance_to(other.global_position) > radius:
			continue
		other.apply_hit(damage, self)

## 尸体是否还在"滑行"（= 被击退致死后的实体阶段）
func is_sliding_corpse() -> bool:
	return _corpse_slide_until_ms > 0

## 能不能接受别人传来的动量：活人照旧；**正在滑行的尸体也算**（它本来就是被推着走的那具）
func can_receive_momentum() -> bool:
	## ⚠️ 2026-09-19：潜地期间**一律不收**（"免疫一切状态"）——顺带也让传递判定不再把它当接触目标。
	return (alive or _corpse_slide_until_ms > 0) and not is_burrowed()

## 尸体滑行：保留击退速度继续 `move_and_slide()`，并把动量（含弩车的传递伤害）传给贴上的同队单位。
## 结束条件：超过 `CORPSE_SLIDE_MAX_MS`，或击退速度衰减到 `CORPSE_SLIDE_MIN_SPEED` 以下。
func _tick_corpse_slide(delta: float) -> void:
	_kb = _kb.lerp(Vector3.ZERO, clampf(GameConfig.KNOCKBACK_DECAY * delta, 0.0, 1.0))
	velocity = Vector3(_kb.x, 0.0, _kb.z)
	_apply_gravity(delta)
	move_and_slide()
	## ⚠️ 2026-09-19 修 bug（用户报告"投石车有时会有大范围击退但没伤害"）：尸体**只在带传递伤害时**
	## 才把动量传出去。否则任何被击退致死的单位都会变成 0.8 s 的"隐形击退源"（推人但不掉血）。
	if _kb_damage > 0.0:
		_transfer_motion_momentum(_kb)
		_transfer_motion_to_contacts(_kb)
	if Time.get_ticks_msec() >= _corpse_slide_until_ms or _kb.length() < GameConfig.CORPSE_SLIDE_MIN_SPEED:
		_end_corpse_slide()
	_tick_dying(delta)

## 结束尸体滑行：交回普通阵亡演出（失去单位层碰撞，只留世界层，免得陷进地面）
func _end_corpse_slide() -> void:
	_corpse_slide_until_ms = 0
	collision_layer = 0
	collision_mask = 1

# ---------------------------------------------------------------- 兴奋圈内伤
## 圈外**每秒叠 1 层**内伤，每层每秒造成 `CIRCLE_DOT_RATIO`（0.5%）最大生命的真伤；
## 层数 = "已经在圈外待了多少秒"。
##
## ⚠️ 入口是 `Arena._update_excited`，它**每个物理帧**都会调过来（60 次/秒），
## 所以"每秒一层"的节流必须在这里做，而且**加层与结算伤害必须共用同一个节拍**
## （两套 1 Hz 时钟会让伤害差一层）。
##
## 修 bug（2026-09-18）：此前 `stack_count` 是**每物理帧** +1，层数以 60/秒 累积 →
## 实测圈外 2.2 s 就掉 82/90 血（91% 最大生命），与 `01_core_loop.md#3` 写的
## "每秒叠 1 层内伤"差 60 倍。现在层数严格等于圈外秒数。
func tick_circle_dot() -> void:
	if not excited:
		return
	var now := Time.get_ticks_msec()
	if now - _stack_due < GameConfig.CIRCLE_DOT_INTERVAL_MS:
		return
	_stack_due = now
	stack_count += 1
	apply_hit(max_hp * GameConfig.CIRCLE_DOT_RATIO * float(stack_count), null)

# ---------------------------------------------------------------- 工具
func _roguelike() -> Node:
	var arena_node := _arena()
	if arena_node == null:
		return null
	var root := arena_node.get_parent()
	if root == null:
		return null
	for child in root.get_children():
		if child.has_method("aid_speed_mult_at"):
			return child
	return null


func _aid_zone_speed_mult() -> float:
	var host := _roguelike()
	if host == null:
		return 1.0
	return host.aid_speed_mult_at(self)


func _aid_range_cut() -> float:
	var host := _roguelike()
	if host == null:
		return 0.0
	return host.aid_range_cut_at(self)


func _note_aid_attack() -> void:
	var host := _roguelike()
	if host == null:
		return
	host.note_aid_attack(self)


func _aid_undo_post_debuff(amount: float) -> float:
	if not bool(aid_mods.get("block_post", false)):
		return amount
	var arena_node := _arena()
	if arena_node == null or not arena_node.debuff_active(team):
		return amount
	var scale := GameConfig.ROGUELIKE_POST_DEBUFF_MULT
	if scale <= 0.0:
		return amount
	return amount / scale


func _arena() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("spawn_arrow"):
			return node
		node = node.get_parent()
	return null

func hp_ratio_for_ui() -> float:
	return health_ratio()

## 调试断言：当前锁定的目标是否就是场上最近的敌人（供 dbg 工具核对"只打最近"）
func is_targeting_nearest() -> bool:
	var nearest := _find_target()
	return nearest == null or nearest == target

func _mcp_state() -> Dictionary:
	return {
		"team": team,
		"type": GameConfig.profile_name(type_id),
		"hp": int(round(hp)),
		"max_hp": int(round(max_hp)),
		"move_speed": GameConfig.move_speed(type_id),
		"state": ["待机", "移动", "攻击", "阵亡"][_state],
		"stunned": is_stunned(),
		## 定身（2026-09-25）：与眩晕分开报到 —— 探针要能区分"不能行动"与"不能被位移"两条口径
		"rooted": is_rooted(),
		## 减速（2026-09-26 肉鸽陷阱）：剩余毫秒 + 当前倍率 + 实际移速。
		## ⚠️ 三个都给：`slow_ms` 为 0 时倍率读数没有意义（"没被减速"与"倍率恰好 1.0"要能分开）。
		"slow_ms": maxi(_slow_until_ms - Time.get_ticks_msec(), 0),
		"slow_mult": slow_factor(),
		"speed_now": snappedf(current_speed(), 0.001),
		## 前进布阵区的准备期（2026-09-27 第七块）：剩余毫秒 + 它是哪个回合被放进那个区的。
		## ⚠️ 两个都给：`prep_ms` 为 0 时"是免启动的老兵"与"从没进过那个区"要能分开（后者 round = -1）。
		"prep_ms": maxi(_prep_until_ms - Time.get_ticks_msec(), 0),
		"zone_entered_round": zone_entered_round,
		## 武士大师的四技能（2026-09-25）：偏折额度 / 已挡几次 / 拔刀斩阶段与待结算人数
		"deflect_charges": _deflect_charges_left,
		"deflect_since_cd": _deflect_since_cd,
		"deflect_cd_ms": maxi(_deflect_cd_until_ms - Time.get_ticks_msec(), 0),
		## 后撤步 / 冲刺互斥（2026-09-25）：滑行剩余与禁冲刺剩余 —— 探针用它验"完成后 0.3 s 内不得冲刺"
		"backstep_ms": maxi(_backstep_until_ms - Time.get_ticks_msec(), 0),
		"dash_lock_ms": maxi(_dash_lock_until_ms - Time.get_ticks_msec(), 0),
		"iai_phase": _iai_phase,
		"iai_pending": _iai_targets.size(),
		## 心灵腐化（2026-09-25 第二轮）：腐化值 / 最近一次被照射距今多久 / 这道激光还在不在蓄力。
		## ⚠️ 探针要能区分"没被照"与"被照着但值还小" ⇒ 三个读数都给（`corrupt_hold_ms` 为负
		## 或很大 = 早就不在被照了；`laser_charge_ms` = 蓄力还剩多少）。
		"corrupt": int(round(corrupt)),
		"corrupt_percent_of_max_hp": int(round(clampf(corrupt / maxf(max_hp, 0.001), 0.0, 1.0) * 100.0)),
		"corrupt_since_last_ms": (0 if _corrupt_last_ms <= 0 else Time.get_ticks_msec() - _corrupt_last_ms),
		"laser_charge_ms": maxi(_laser_charge_until_ms - Time.get_ticks_msec(), 0),
		"laser_target": ("" if _laser_target == null else String(_laser_target.type_id)),
		"flame": ["待机", "蓄力", "冲刺", "待爆"][_flame_phase],
		"burrow": ["露出", "钻入", "地下", "钻出"][_burrow],
		## 冲锋（轻骑兵（矛），2026-09-25）：0 = 没在冲锋；> 0 = 剩余毫秒。
		## 与 `burrow` 同一套口径（枚举转中文），方便在运行时状态面板里直接读。
		"lance": 0 if _lance_until_ms <= 0 else maxi(_lance_until_ms - Time.get_ticks_msec(), 0),
		"lance_sped_up": _lance_sped_up,
		"lance_stopped": _lance_stopped,
		"lance_hits": _lance_hit_units.size(),
		"lance_hit_total": _lance_hit_total,
		"lance_charges_left": _lance_charges_left,
		## 距下一次**矩形结算**还有多少 ms（2026-09-25：结算按 `UNIT_LANCE_BOX_TICK_MS` 的节拍跑，
		## 400 → 300 ms）。探针用它验证"每个节拍内最多造成一次伤害"这条口径。
		"lance_box_next_ms": 0 if _lance_next_box_ms <= 0 else maxi(_lance_next_box_ms - Time.get_ticks_msec(), 0),
		"boss": GameConfig.is_boss(type_id),
		## 锚定（2026-09-26）：探针靠它 + 位置读数验"石柱被技能怼住时一动不动"。
		"anchored": is_anchored(),
		## 免疫眩晕（2026-09-25 第六条）：boss 与**两台载具**都为真 —— 探针用它区分
		## "本来就不该被晕"与"眩晕逻辑坏了"。
		"stun_immune": GameConfig.is_stun_immune(type_id),
		## 影袭的影子形态（2026-09-25 第七轮）：探针靠它验"位移期间 = 人形藏起来 + 地上有影子"。
		"in_shadow_form": is_in_shadow_form(),
		"shadow_form_visible": _fx_shadow_form != null and _fx_shadow_form.visible,
		"body_visible": _visual != null and _visual.visible,
		## 召唤石柱（2026-09-25 第七轮）：已经结算到第几拍 / 本场已召唤几个。
		"summon_tick": _summon_tick,
		"summon_count": _summon_count,
		"fx": [_fx_charge != null and _fx_charge.visible, _fx_hit != null and _fx_hit.visible,
				_fx_blast != null and _fx_blast.visible],
		"stacks": stack_count,
		"pos": {"x": snappedf(global_position.x, 0.01), "z": snappedf(global_position.z, 0.01)},
	}
