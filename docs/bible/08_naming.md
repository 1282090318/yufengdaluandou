# 08 命名规范（节点 / 脚本 / 变量 / 信号 / 枚举）

> **权威范围**：全项目所有标识符的命名规则。
> 本文件由 `07_file_layout.md#4-命名规范` 迁移而来，**迁完之后命名只以本文件为准**。
> 速查表见 `_index.md#2.4-命名与坐标`（不变量 I-31 ~ I-34）。
> 代码落点：全项目 `.gd` / `.tscn`。

## 1. 总则

1. **一个名字只描述一件事**：名字里出现 `And` / `Or` / `Manager`，通常说明这个对象该拆。
2. **名字说"是什么"，不说"怎么用"**：用 `alive_count()` 而不是 `get_alive_count_for_ui()`。
3. **长度与作用域成正比**：循环变量可以叫 `i`，跨文件常量必须写全 `MATCH_LIMIT_MS`。
4. **同一概念全局同名**：选手指的是 `unit`，就不要在别处叫 `fighter` / `soldier` / `pawn`。
5. **禁止拼音与中英混拼**：`bingzhong`、`unitLeiXing` 一律不允许（目录侧的同一条约束见 `07_file_layout.md#3` R-06：**项目里已不存在中文目录名**，`新建文件夹/` 已于 2026-09-18 改名为 `docs/`）。

## 2. 命名风格对照表

| 对象 | 风格 | 示例 |
| --- | --- | --- |
| 目录 | 全小写 snake_case，复数表集合 | `units/`、`arena/`、`camera/` |
| 脚本文件 | snake_case | `camera_rig.gd`、`unit_factory.gd` |
| 场景文件 | snake_case | `main.tscn`、`debug_autoplay.tscn` |
| 资源文件 | snake_case + 类型后缀 | `player_body.tscn`、`stone_mat.tres` |
| 脚本类名（`class_name`） | PascalCase | `Unit3D`、`CameraRig`、`UnitFactory` |
| Autoload 名 | PascalCase | `Events`、`GameConfig` |
| 节点名 | PascalCase | `CameraRig`、`BetPanel`、`ExciteRing` |
| 常量 | SCREAMING_SNAKE_CASE | `MATCH_LIMIT_MS`、`ARENA_HALF_X` |
| 枚举类型 | PascalCase | `State`、`Mode` |
| 枚举成员 | SCREAMING_SNAKE_CASE | `State.ATTACK`、`Mode.OVERVIEW` |
| 信号 | snake_case，动词过去式 | `unit_died`、`round_started` |
| 局部变量 / 参数 | snake_case | `attack_timer`、`knockback` |
| 私有成员 | 前缀 `_` + snake_case | `_attack_timer`、`_kb_until` |
| 公开成员 | snake_case | `team`、`type_id`、`alive` |
| 布尔量 | 读起来像断言 | `alive`、`match_active`、`is_ranged`、`has_shield` |
| 实体 ID | 全小写 snake_case | `sword` / `spear` / `shortbow` / `longbow` / `lightcav` |
| **组**（`add_to_group()` / `get_nodes_in_group()`） | **全小写 snake_case**，无前缀、不加复数变化 | `units`、`audio` |

> ⚠️ **"组"这一行是 2026-09-25 由用户裁决补进来的**（此前表里**没有这一档**，项目里已有 `units` 与 `audio`
> 两个组只是"沿用先例"）。依据与沿革：`99_decisions.md` 同日条目（"设置界面 + BGM"那条的复查条件 +
> 用户"在 §2 补一行"的指示）。⚠️ 组名**只用于"跨层找东西"这一件事**（`Unit3D` 归入 `units`、
> 音频层归入 `audio`）—— 它是**运行时的查找键**，不是标识符命名空间，所以**不进 §3 的细则**、也不参与
> "同一概念全局同名"（§1.4）那一条的判定。

## 3. 命名规则（细则）

### 3.1 节点名

- 用 PascalCase，且**描述这个节点在场景里的角色**，不是它的类型：
  `CameraRig`（好） / `Node3D2`（坏） / `Camera3D1`（坏）。
- 动态生成的节点也必须命名：`unit.name = "UnitA_sword_0"`，方便在运行时状态面板里定位。
- **后缀一律用下划线**，方向 / 序号都写在 `_` 之后：
  `Bounds_north` / `Bounds_east`（方位）、`UnitA_sword_0`（序号）。
  不要写成连写（`WallNorth`）或把序号塞进中部（`UnitA0_sword`）。

### 3.1.1 Inspector 分组标签（`@export_group`）

- `@export_group()` 的参数是**给人看的显示文字**，不是标识符，**允许中文**：
  `@export_group("选手数值 · 剑盾兵")`。
- 分段名用"名词 + 可选的中点补充"格式，同一文件内不重复。
- 这条是与 §1.5"禁止中英混拼"的**明确例外**：§1.5 管的是标识符，显示文字不受它约束。

> ⚠️ 项目现状：**当前代码里已经没有 `@export`**（见 `99_decisions.md#删除全部-export`）。
> 保留本节是因为以后给 `Arena` / `CameraRig` 建 `.tscn` 模板时还会用到。

### 3.2 脚本名与类名

- 文件名 snake_case ↔ 类名 PascalCase，**一一对应**：`camera_rig.gd` ↔ `class_name CameraRig`。
- 一个文件只放一个 `class_name`；辅助类放同目录的独立文件（如 `unit_factory.gd`）。
- 工具类以角色结尾：`*Factory`（造对象）、`*Rig`（装配体）、`*Config`（数据）。
- 调试脚本以 `debug_` 前缀开头，并配同名 `debug_*.tscn`（见 `07_file_layout.md#3` R-08）。

### 3.3 变量名

- 不用缩写，除非是公认缩写（`hp`、`dps`、`ui`、`id`、`pos`、`dir`、`kb`）。自定义缩写必须在定义处写注释。
- 单位写进名字：`_born_ms`、`match_start_ms`、`ARENA_HALF_X`（米）、`DECIDE_LIMIT_MS`（毫秒）。
- 集合用复数：`units`、`arrows`、`stat_labels`。
- 索引用 `i`，二维用 `x` / `y`，坐标用 `pos` / `world_pos`。
- 临时变量按用途命名，不叫 `temp` / `data` / `value`（`value` 只允许出现在真正的泛型上下文里，如 setter）。
- **参数按域加前缀**，且前缀取自 `_index.md#2.4` 的既有域：
  `UNIT_*`（选手动作与手感）、`CAM_*`（相机）、`RING_*`（兴奋圈）、`SPAWN_*`（出生布局）、
  `TEAM_WEIGHT_*`（权重）、`CIRCLE_*`（圈外状态）、`HIT_*`（全场倍率）。
  同域的参数必须连续放在同一段里，段首写一行 `# ---- 域名 ----` 注释。
- **另允许"功能域"前缀**（2026-09-19 追认既有实践，见 `99_decisions.md` 同日条目）：某一个**兵种 / 部件 /
  子系统自己的一组纯表现常量**，可以用它自己的域当前缀，写法与上一条**同规则**（SCREAMING_SNAKE_CASE、
  同域连续成段、段首一行注释）。现有实例：
  `FAN_*`（扇子兵扇面）、`KITE_*`（骑士筝形盾）、`VEHICLE_*`（投石车 / 弩车两台载具）、
  `MOUNT_*`（**轻骑兵（矛）的马**：几何 / 毛色 / 鬃尾色，2026-09-25 第四条新增 —— 马是"部件"，
  与 `KITE_*` 同类）、
  `SIEGE_*`（投石车抛臂动作）、`BALLISTA_*`（弩车上弦动作）、`BAR_*` / `HEALTH_BAR_*`（单位血条）、
  `FLAME_FX_*`（火焰拳炎爆的三段特效：时长 / 自转 / 离地高度，2026-09-19 追认）、
  `SHADOW_*`（**影魔的整套剪影**：配色 / 亮度 / 腰际束带 / 影子下摆 / 拖尾 / 影滩 / 多面体头 / 前突尖 /
  尖冠 / 破碎披风 / 双持短刃，**2026-09-25 第三轮新增，37 个** —— 它是**当代最大的一支**，
  与 `CORRUPTOR_*` / `GRENADIER_*` 同一类"**一个兵种的整套几何**"，见本文件 `#3.3` 最新一条审计）、
  `SANDWORM_*`（**已废除**，2026-09-19 当天改：沙虫潜地的下沉深度不再写成常量，
  改为从判定体高度推导 —— `unit3d.gd#_resolve_sink_depth()` = `UNIT_BODY_BOX["sandworm"].size.y + 0.6`。
  ⚠️ 这条留在这里只为说明"为什么没有这个前缀"，新代码不要再用它 —— 2026-09-25 新增的
  `UNIT_SANDWORM_SURFACE_STUN_RADIUS` 是**既有常量改值**、不是复活本前缀）。
  ⚠️ **只限表现参数**：玩法数值（血量 / 伤害 / 攻速 / 射程 / 移速 / 重量 / 击退 / 权重…）**不许自开域**，
  仍必须住进 `GameConfig`（不变量 I-15）。

> ✅ **2026-09-25 审计（新增 `longbow` / `lightcav` 两个兵种时）**：**没有新开功能域前缀** ——
> 两个兵种的**玩法数值**（含轻骑兵技能的 7 m 触发 / 3 s 时长 / 14 m/s 冲刺 / 5 s 冷却 /
> 1×3.4 m 命中矩形 / 附加伤害斜率 / 2 次额度（⚠️ **同日第四条已改成 1 次**，见下条审计）/ 10~16 m 游走环带）全部作为 `UNIT_LANCE_*` 住进 `GameConfig`，
> 沿用既有 `UNIT_*` 域；`UNIT_LONGBOW_ARROW_SPEED` / `UNIT_LONGBOW_ARROW_GRAVITY` 同理
>（与 `UNIT_STONE_*` / `UNIT_BOLT_SPEED` / `UNIT_SHORTBOW_ARROW_*` 并列）。
> 新标识符逐条对照本文件：实体 ID `shortbow` / `longbow` / `lightcav` 合 §2 与 §3.3；
> 私有成员与方法 `_lance_until_ms` / `_lance_charges_left` / `_lance_sped_up` / `_lance_stopped` /
> `_lance_patrol_turn_ms` / `_lance_tick()` / `_start_lance()` / `_lance_patrol()` / `_set_pass_all()` /
> `_steer_toward()` / `is_mid_dash()` / `_solve_ballistic()` / `_aim_ballistic()` / `_aim_straight()`
> 合 §3.3（`_` + snake_case + **单位写进名字**，与既有 `_born_ms` / `_dying_ms` 同式）；
> 节点名 `Longbow` / `LightHelm` / `HunterBrim` / `LanceShaft` / `CrestMane` 等合 §3.1（PascalCase）；
> **无新信号**（§3.4 不涉及）。⇒ **本文件无冲突、无规则改动、无不变量改动**。
> ⚠️ **同日两处"废弃但保留"**（**2026-09-25 第三条经用户裁决：「保留」** ⇒ 这不是待清理项，是**既定状态**）：
> ① `UNIT_LANCE_LOCK_MS`（"方向锁死"的时长）随"转弯限速 180°/s"取代两段制而**不再被引用**；
> ② `UNIT_LANCE_STOP_DISTANCE`（冲刺停步的贴近阈值）随**两条停步判据全部删除**而**不再被引用**。
> 两者都**保留在 `GameConfig` 里并注明沿革**（与 `CAM_OVERVIEW_SWAY` 同一处理），命名本身仍合规则，**不构成冲突**。
>
> ✅ **2026-09-25 第三条审计（"冲刺不再停步 / 穿透延时还原 / 沙环朝向 / 数值下调"这一批）**：
> 新标识符 `_pass_clear_due_ms`（单位 `_ms` 已写进名字）、`_release_pass_all()` / `_unit_overlapping()` /
> `_tick_pass_clear()` 合 §3.3（`_` + snake_case + 按用途命名）；
> **没有新开功能域前缀**，也**没有新常量**（延时还原直接复用既有的 `UNIT_ALLY_GHOST_MAX_HOLD_MS`）；
> 数值改动（长弓 90 / 28 m、短弓 35）只动 `GameConfig.PROFILES` 的值，**不涉及命名**；
> 沙环朝向那处**只删了一行**、没有引入任何名字。
> ⇒ **无新信号**（§3.4 不涉及）、**无冲突、无规则改动、无不变量改动**。
>
> ✅ **2026-09-25 第四条审计（"骑马 / 突刺 / 10 s + 1 次 / 眩晕退还"这一批）**：
> 新标识符 `rider_lift()` / `_build_mount()` / `MOUNT_*`（12 个几何常量）合 §3.3
> （`MOUNT_*` 是**功能域前缀**，已登记进上面那张清单，与 `KITE_*` 同类 —— 马是"部件"）；
> 新节点名 `Rider`（PascalCase，§3.1）+ 马的 22 件 `Mount*`（`MountBarrel` / `MountLeg_front_left` /
> `MountSock_rear_right` / `MountStirrup_left` / `MountMane` / `MountTail` …：
> PascalCase + **下划线后缀写方位与序号**，§3.1 明令"后缀一律用下划线"）；
> 数值改动（`UNIT_LANCE_CHARGE_MS` 3000 → **10000**、`UNIT_LANCE_CHARGES_MAX` 2 → **1**）
> 只改 `GameConfig` 里的**值**、不涉及命名；`_interrupt_skill()` 只增加对既有成员的读写（无新成员）。
> ⇒ **无新信号**（§3.4 不涉及）、**无新玩法常量**（马的比例全在 `MOUNT_*`，玩法数值仍全在 `GameConfig`）、
> **无冲突、无规则改动、无不变量改动**。
> ⚠️ ~~一处**一个常量担两个职责**（不是命名冲突）：`UNIT_LANCE_CHARGES_MAX` 现在既是"发动闸门"
> 又是"被打断退还的**封顶**"~~ ⇒ **这段随 2026-09-25 第五条作废**（退还已取消，见下条审计）。
>
> ✅ **2026-09-25 第五条审计（"投石车权重 / 伤害 / 落点眩晕 + 冲刺改暂停"这一批）**：
> 新标识符 `UNIT_STONE_STUN_MS` 合 §3.3 —— 它是 `UNIT_STONE_*` 域里的第 5 个常量
>（与 `UNIT_STONE_AOE_RADIUS` / `_SPLASH_DAMAGE` / `_SPEED` / `_GRAVITY` 同段、同风格）；
> 新增局部变量 `added_ms`（snake_case + **单位写进名字**，§3.3 明令）合规则；
> `config.gd` 那三处数值只改**值**、`arrow.gd` / `unit3d.gd` 只是**改写既有成员**（无新成员、无新节点）。
> ⇒ **无新信号**（§3.4 不涉及）、**无新玩法域前缀**、**无冲突、无规则改动、无不变量改动**。
> ⚠️ **更正上一条审计**：`UNIT_LANCE_CHARGES_MAX` 现在只担**"初值 + 发动闸门"**两件事
>（"退还封顶"这一职责随第五条取消）—— 名字仍然准确（它就是"上限"），故**不改名**。
>
> ✅ **2026-09-25 第七条审计（"冲刺斜率 10 / 箭钉盾牌 / 格挡不闪白 / 载具免疫眩晕"这一批）**：
> 新标识符 `is_stun_immune()` 合 §3.3（**布尔判据读起来像断言**，`is_*` 族，与既有 `is_boss()` 并列）；
> PROFILE 新字段 `stun_immune` 全小写 snake_case ✓；`shield_anchor()` 是公开方法、按用途命名
>（与既有 `_bar_anchor_height()` 同一套"挂点"词汇）；`_stick_to_anchor()` / `_start_stick_timer()` /
> `_measure_tip_offset()` 是 `_` + snake_case 的私有方法；`_arena` / `_tip_offset` 是私有成员；
> `SHIELD_STICK_INSET` 是 SCREAMING_SNAKE_CASE 的**表现常量**（与 `arrow.gd` 的既有风格一致，无需域前缀）。
> ⇒ **无新信号**（§3.4 不涉及）、**无新节点名**（`ShieldPivot` 是既有节点）、**无冲突、无规则改动、无不变量改动**。
> ⚠️ 一处**易误读**（不是命名冲突，故**不改名**）：`UNIT_LANCE_SPEED_BONUS_PER_MS` 里的 `MS` 是"**米/秒**"
>（相对速度的单位），**不是毫秒** —— 它算的是"每 1 m/s 相对速度差给多少伤害"，已在常量注释里写明。
>
> ✅ **2026-09-25 第八 / 九条审计（"斜率 10 → 8 / 击退不再中断冲锋 / 冲刺冲满 10 s"这一批）**：
> 唯一的新标识符 `_lance_active()` 合 §3.3（`_` + snake_case 私有方法、按用途命名、**布尔语义读作断言**）；
> **无新常量、无新 PROFILE 字段、无新节点、无新信号**（`_lance_tick()` 只是重排了分支与判断顺序）。
> ⇒ **无冲突、无规则改动、无不变量改动**。
> ⚠️ **一条必须记住的"名字陷阱"**（本文件存在的意义正在于此）：**`is_mid_dash()` 的名字比它的语义窄** ——
> 它是**预判闸门**的判据（`04_physics.md#5.3`），对"**被击退** / 骑士冲撞 / 火焰拳炎爆 / 轻骑兵冲刺"
> **四种情形**都为真。我第一版把"禁移豁免"写成 `not is_mid_dash()`，结果豁免被发给了**所有正在被击退的单位**
>（引擎内探针的**对照组**当场报错：一个**没在冲刺**的扇子兵 `_kb_added` 从 0 变成 216）。
> ⇒ 要判"**是不是正在冲刺**"只能用 `_lance_active()`。**两者都不改名**（`is_mid_dash()` 的语义已由它自己的
> 注释与 `04_physics.md#5.3` 的引用界定清楚），但**新代码不要想当然地把它当"冲刺中"用**。

> ✅ **2026-09-25 第十条审计（"冲刺转弯 180° / 270° 自动切 + 矩形结算改 400 ms 跳拍"这一批）**：
> 新常量两个，均 SCREAMING_SNAKE_CASE + 域前缀 ✓ —— `UNIT_LANCE_TURN_FAST_DEG_PER_SEC`（**放宽后的那一档**，
> 与既有 `UNIT_LANCE_TURN_DEG_PER_SEC` 构成"同域 + 限定词"的一对，限定词 `FAST` 直接说清"更快的那一档"）、
> `UNIT_LANCE_BOX_TICK_MS`（**结算跳拍间隔**，`_MS` 后缀 = 毫秒，与全库 `*_MS` 的既有口径一致 ✓）；
> 新私有方法 `_lance_turn_deg_per_sec(dist)` 合 §3.3（`_` + snake_case、**按用途命名**、返回"这一帧该用哪一档"）；
> `_mcp_state()` 新增观测字段 `lance_box_next_ms`（与既有 `lance` / `lance_charges_left` 同族，snake_case ✓，
> `_next_ms` 后缀与 `_lance_until_ms` / `_stun_until_ms` 的"绝对毫秒表"词汇一致 ✓）。
> ⇒ **无新信号**（§3.4 不涉及）、**无新节点名**、**无新枚举**、**无冲突、无规则改动、无不变量改动**。
> ⚠️ **一处容易读错的"同域双档"**：转弯限速现在是**两个常量**，**不是**旧值被换个数值 ——
> `..._DEG_PER_SEC`（180）仍是**基准档、也是冷却期游走的唯一档位**，`..._FAST_DEG_PER_SEC`（270）
> **只作用于冲刺**（判据 `dist > UNIT_LANCE_BOX_LENGTH` 在 `_lance_turn_deg_per_sec()` 里）。
> ⇒ 不要把 270 当成"现行全局转弯限速"：`_lance_patrol()` 走的仍然是 180。
> ⚠️ 同日**另一批（第十一条，镜头按键重映射：`cam_down` Q → Shift、`cam_up` E → Space、`cam_boost` Shift → Ctrl）**
> **没有引入任何新标识符** —— 只改了 `project.godot` 里三个 `physical_keycode`，动作名
> `cam_up` / `cam_down` / `cam_boost` **全部沿用既有名字** ⇒ 不进本审计（键位口径见 `05_ui_hud.md#输入映射`）。

> ✅ **2026-09-25 审计（"轻骑兵矩形加宽 / 结算加快 + 开始界面"这一批）**：
> **轻骑兵那两个数只改了 `GameConfig` 里的值**（`UNIT_LANCE_BOX_WIDTH` 1.0 → 1.5、`UNIT_LANCE_BOX_TICK_MS` 400 → 300 ms），
> **没有引入任何新标识符** ⇒ 与 §3.3 无涉。
> 开始界面新增**两个类**：`StartScreen`（`ui/start_screen.gd`）与 `StartShowcase`（`game/start_showcase.gd`）——
> 文件名 snake_case ↔ 类名 PascalCase **一一对应** ✓（§3.2），类名都以角色结尾（`*Screen` / `*Showcase`，与
> `*Factory` / `*Rig` 同一族）✓。
> 新信号三个：`start_pressed` / `screen_blacked_out` / `roll_finished` —— 全部是**域 + 动词过去式**、
> 描述"**已经发生了什么**"（§3.4）✓，没有一个是"请去做某事"。
> ⚠️ **2026-09-25 其后**：其中 `start_pressed` **已删除**，由 `mode_selected(mode: String)` 取代
>（"开始游戏"不再直接进游戏，改为先选模式，见本文件末尾的最新审计）。`screen_blacked_out` /
> `roll_finished` 一字未动。
> 新节点名一律 PascalCase 且描述角色 ✓：`StartScreen` / `FadeOverlay` / `OptionList` / `StartShowcase` /
> `Battle` / `OrbitPivot` / `ShowcaseCamera` / `Floor` / `Surface` / `Sun` / `WorldEnvironment`。
> 新常量全是 SCREAMING_SNAKE_CASE 的**表现参数**（`FLOOR_COLOR` / `SKY_COLOR` / `SUN_*` / `AMBIENT_*` / `ORBIT_*` /
> `PREROLL_*` / `RANK_*` / `LINEUP_A|B` / `BUTTON_FONT*` / `COLOR_*` / `FADE_*_MS` / `OPTION_*`）——
> 按既有惯例**住在各自脚本里、不进 `GameConfig`**（同 `hud.gd` 的 `FONT_*` / `COLOR_*`、`unit3d.gd` 的 `FLAME_FX_*`、
> `arrow.gd` 的 `SHIELD_STICK_INSET`）⇒ **不与不变量 I-15 冲突**（那条管的是"可调**玩法**数值"）。
> ⚠️ **2026-09-25 其后**：这里点名的 `hud.gd` 的 `FONT_*` / `COLOR_*` **已搬进 `scripts/ui/ui_style.gd`**
>（经典与沙盒两套 HUD 共用一份）—— "住在各自脚本里、不进 `GameConfig`"这条口径**不变**，只是换了住处。
> 私有成员 / 方法与布尔量 ✓：`_fade` / `_option_list` / `_start_button` / `_mode` / `_from_ms` / `_black_emitted` /
> `_input_ready` / `_closing` / `_battle` / `_pivot` / `_cam` / `_units` / `_spawn_ms` / `_frozen`，
> `_add_option()` / `_apply_button_colors()` / `_button_style()` / `_on_option_hover()` / `_build_floor()` …；
> `_frozen` / `_input_ready` / `_closing` / `has_frozen()` 读起来都像断言 ✓。
> 三个过渡状态用**具名常量** `FADE_IDLE / FADE_OUT / FADE_IN` 而不是裸整数 ✓（§3.5 的同一个精神，同 `hud.gd` 的既有写法）。
>
> ⚠️ **一处冲突（当场发现 → 当场裁决 → 已改代码）**：`start_screen.gd#_add_option()` 原先写的是
> `button.name = "Option_%s" % text` ⇒ 节点名实际是 **`Option_开始游戏`**：**把中文显示文字塞进了标识符**，
> 与 §1.5"**禁止拼音与中英混拼**"、§3.1.1"中文只允许出现在 `@export_group` 的显示文字里（那是**明确例外**）"相抵，
> 也与 `hud.gd` 给动态控件命名用的 `"TeamRow%d" % team` 不一致。
> ✅ **用户裁决（2026-09-25）：改代码、不动命名约定** ⇒ 现在是
> `button.name = "Option_%d" % _option_list.get_child_count()` —— **纯英文 + 序号写在 `_` 之后**，
> 正是 §3.1 那条"序号写在 `_` 之后"（例：`UnitA_sword_0`）的写法；运行时可读到 `Option_0`。
> ⚠️ 顺手记一条教训（本文件存在的意义正在于此）：**动态控件的名字不要从显示文字派生** ——
> 显示文字随时会改（换词、本地化），标识符不该跟着变。

> ✅ **2026-09-25 审计（"冲刺漏判修复 + 开始按钮打飞 / 背景推近 + 权重 5 / 时长 8 s"这一批）**：
> **数值改动**（`PROFILES["lightcav"]["weight"]` 4 → 5、`UNIT_LANCE_CHARGE_MS` 10000 → 8000）
> **不引入任何标识符** ⇒ 与 §3.3 无涉。
> 冲刺判定重构引入的标识符：新私有方法 `_lance_scan_box()` / `_lance_settle_box()`（`_` + snake_case、
> **按用途命名**：一个"扫描登记"、一个"结算扣血"）✓；新私有成员 `_lance_box_pending` ✓（集合语义、
> 与既有 `_lance_hit_units` 同族）；⚠️ **旧名 `_lance_resolve_box()` 已删除**（拆成上面两个）——
> 它只被本文件内部与注释引用，**没有外部调用点**，删名不涉及约定。
> 界面侧新增：`begin_zoom()`（公开方法，按用途命名）✓、`_tick_zoom()` / `_tick_fly_out()`（私有 + snake_case）✓、
> 常量 `ZOOM_MS` / `ZOOM_RADIUS_END` / `ZOOM_HEIGHT_END` / `FLY_OUT_V0` / `FLY_OUT_A`（SCREAMING_SNAKE_CASE，
> **表现参数**住各自脚本、不进 `GameConfig`，同 §3.3 既有惯例）✓、私有成员 `_zooming` / `_zoom_from_ms` /
> `_flying` / `_fly_from_ms` ✓（布尔量 `_zooming` / `_flying` 读起来像断言）。
> ⇒ **无新信号、无新节点名、无新枚举、无冲突、无规则改动、无不变量改动**。
> ⚠️ 一处**用词提醒**：`FLY_OUT_V0` / `FLY_OUT_A` 里的 `V0` / `A` 是物理量符号（初速度 / 加速度），
> 注释里已写明单位是 **px/s** 与 **px/s²** —— 本项目"单位写进名字"那条对这两个符号名做了**明确让步**
>（写成 `FLY_OUT_V0_PX_PER_SEC` 会过长且失去公式的可读性），如需严格化请先走决策条目。

> ✅ **2026-09-25 审计（"押注机位调低 + 暂停菜单（齿轮 / `Esc`）"这一批）**：
> **相机只改了一个值**（`CAM_OVERVIEW_PITCH` −0.72 → −0.58）⇒ 不引入任何标识符。
> 暂停菜单引入的标识符全部合 §3.3：常量 `PAUSE_FADE_OUT_MS` / `PAUSE_FADE_IN_MS` / `PAUSE_SCRIM_COLOR` /
> `PAUSE_FONT` / `PAUSE_FONT_HOVER` / `PAUSE_BUTTON_MIN` / `PAUSE_PANEL` / `PAUSE_PANEL_HOVER` / `PAUSE_BORDER` /
> `PAUSE_TEXT` / `PAUSE_TEXT_HOVER` / `PAUSE_IDLE` / `PAUSE_FADE_OUT` / `PAUSE_FADE_IN`（都是**表现参数**，
> 按既有惯例住 `hud.gd`、不进 `GameConfig`）✓；`GEAR_BUTTON_PX` / `GEAR_IMAGE_PX` / `GEAR_TEETH` / `GEAR_COLOR` ✓；
> 私有成员 `_gear` / `_pause_root` / `_pause_fade` / `_pause_mode` / `_pause_from_ms` / `_pause_action` /
> `_pause_black_done` ✓（`_pause_from_ms` 带了 `_ms` 单位后缀 ✓）；公开方法 `open_pause_menu()` / `close_pause_menu()`，
> 私有方法 `_build_pause_menu()` / `_add_pause_option()` / `_apply_pause_colors()` / `_pause_style()` /
> `_on_pause_resume()` / `_on_pause_restart()` / `_on_pause_main_menu()` / `_begin_pause_transition()` /
> `_tick_pause_fade()` / `_apply_pause_action()` / `_gear_texture()` ✓；节点名一律 PascalCase ✓：
> `PauseMenu` / `Scrim` / `PauseOptions` / `PauseFade` / `GearButton` / **`TopBarRow`**
>（⚠️ 顶栏那一行**原先没命名**，这次顺手补上 —— §3.1 要求"动态生成的节点也必须命名"）、按钮 `PauseOption_<序号>` ✓。
> 玩法层新增：`Game.pause_match()` / `resume_match()` / `restart_game()` / `_shift_deadlines()` + `_pause_from_ms`；
> `Arena` / `CameraRig` / `Unit3D` 各一个**同名**公开方法 `shift_deadlines()` ✓（同一概念全局同名，§1.4）。
> 新信号一个：`Events.main_menu_requested` —— **请求类用原形动词**（同 `fx_request` 的既有例外，§3.4）✓。
> ⇒ **无新枚举、无裸整数代替枚举**（那三个过渡状态是具名常量）✓、**无冲突、无规则改动、无不变量改动**。
> ✅ **补记（2026-09-25 同日稍后）**：上面那条"**刻意的复制**"**已作废** —— 用户要求"把『暂停菜单按钮样式』
> 抽成共享" ⇒ 新增 `scripts/ui/ui_style.gd`（`class_name UiStyle extends RefCounted`，**纯静态工具**：
> 常量 `FONT` / `FONT_HOVER` / `MIN_SIZE` / `TEXT` / `TEXT_HOVER` / `PANEL` / `PANEL_HOVER` / `BORDER`，
> 静态方法 `apply_option_colors()` / `option_style()` / `decorate_option()`）。
> ⚠️ **2026-09-25 其后**：`apply_option_colors()` **已改名并扩展**为 `apply_option_hover()`（悬停改成整体缩放），
> 另加 `apply_chip_hover()` / `_apply_hover()` 与两个倍数常量 `HOVER_GROW` / `CHIP_GROW`
> —— 见本文件 §3.3 末尾的最新审计。
> 文件名 snake_case ↔ 类名 PascalCase ✓（§3.2）；类名以角色结尾（`*Style`，与 `*Factory` / `*Rig` 同族）✓；
> 静态方法 snake_case、按用途命名 ✓；常量 SCREAMING_SNAKE_CASE ✓。
> **两边都只往下依赖它** ⇒ 不再是兄弟依赖，**样式只剩一处事实来源**（"改一处忘另一处"的风险消失）。
> 同批还新增一个**公开方法** `Unit3D.heal_to_full()`（读起来是动作、按用途命名 ✓）—— 给开始界面的演示兵
> 在冻结前回满血用（`05_ui_hud.md#9.3`）。
> ⚠️ **2026-09-25 再往后（"模式选择 + 沙盒 + 暂停菜单搬家"那一批）**：上面这条审计里登记的"暂停菜单那一族"
> **绝大多数换了住处、也换了名字** —— `PAUSE_FADE_OUT_MS` / `PAUSE_FADE_IN_MS` / `PAUSE_SCRIM_COLOR` /
> `PAUSE_IDLE` / `PAUSE_FADE_OUT` / `PAUSE_FADE_IN`、`_pause_root` / `_pause_fade` / `_pause_mode` /
> `_pause_from_ms` / `_pause_action` / `_pause_black_done`、`_build_pause_menu()` / `_add_pause_option()` /
> `_on_pause_resume()` / `_on_pause_restart()` / `_on_pause_main_menu()` / `_begin_pause_transition()` /
> `_tick_pause_fade()` / `_apply_pause_action()` / `_gear_texture()`，以及两个公开方法
> `open_pause_menu()` / `close_pause_menu()` —— **全部随菜单搬进 `scripts/ui/pause_menu.gd`**（并按下一条审计
> 改名 / 精简）。`hud.gd` 那边只剩 `_gear`、`_pause` 与三个 `pause_*()` 契约方法。
> ⚠️ 同一条旧审计点名的 **`Game._shift_deadlines()` 也删了** —— 它的职责（把绝对截止时刻整体后移）
> 搬进 `core/match_pause.gd#shift_deadlines()`，经典与沙盒共用；`Game.pause_match()` / `resume_match()` /
> `restart_game()` 三个**公开方法原样保留**（只是内部改调 `MatchPause`）。
> **命名约定本身一个字没改**（不是"悄悄换约定"，是"换了住处"）。

> ✅ **2026-09-25 审计（"第一批音效接入"这一批）**：
> 新文件 `scripts/core/audio_manager.gd` ↔ `class_name AudioManager`（snake_case ↔ PascalCase ✓ §3.2；
> 名字说清"是什么" = 音频层）。常量 SCREAMING_SNAKE_CASE ✓：`AUDIO_DIR` / `AUDIO_EXTENSIONS` / `POOL_SIZE` /
> `BUS_COMBAT` / `BUS_UNIT` / `VEHICLE_MOVE_EPS` / `VOLUME_*_DB`（单位后缀 `_DB` ✓）/ `PITCH_*`；
> 私有成员 `_events` / `_pool` / `_next` / `_vehicle_loops` ✓；私有方法 `_build_events()` / `_entry()` /
> `_sibling_files()` / `_play()` / `_take_player()` / `_on_unit_was_hit()` / `_on_unit_died()` / `_on_unit_was_blocked()` /
> `_on_fx_request()`（**信号回调一律 `_on_<信号名>`** ✓，与 `hud.gd` / `main.gd` 同一套）/ `_tick_vehicle_loops()` /
> `_make_loop_player()` ✓。动态节点名 PascalCase 且序号写在 `_` 之后 ✓：`SfxPlayer_<序号>` / `VehicleMove_<序号>`（§3.1）。
> **新信号 0 个** ✓（`06_audio.md#3` 的口径就是"表现层不新增信号、统一走 `fx_request`"）。
> ⚠️ **新增一族 `fx_request` 事件名 `shot_<兵种ID>`**（`shot_shortbow` / `shot_longbow` / `shot_catapult` /
> `shot_ballista`）：`shot_` 是域，后缀直接取**实体 ID**（§3.3 的实体 ID 全小写 snake_case ✓）
> ⇒ 与既有的 `arrow_hit` / `arrow_blocked` / `unit_jump` 同一风格 ✓。
> ⚠️ **素材文件名**改成"事件名 + 类型后缀"（如 `combat_shield_block.mp3`）✓ 合 §2 的"资源文件 = snake_case + 类型后缀"；
> 用户最初给的是**中文文件名**（`受伤、死亡.wav` 之类）⇒ 与 §1.5"禁止拼音与中英混拼"相抵，**已按用户裁决改名并搬迁**
>（不是悄悄改约定）。
> ⇒ **无新枚举、无裸整数代枚举、无冲突、无规则改动、无不变量改动**。

> ✅ **2026-09-25 审计（"开始界面加一档模式选择 + 新增沙盒模式 + 暂停菜单搬家"这一批）**：
>
> **新文件 / 新类**（文件名 snake_case ↔ 类名 PascalCase ✓ §3.2）：
> `core/match_pause.gd` ↔ `MatchPause`（**纯静态工具**，角色后缀 `*Pause` 说明"管暂停这摊事"）、
> `game/sandbox.gd` ↔ `Sandbox`（模式名，与既有 `Game` 并列）、
> `ui/pause_menu.gd` ↔ `PauseMenu`（**层级**名，与 `Hud` / `StartScreen` 同族）、
> `ui/sandbox_hud.gd` ↔ `SandboxHud`（`<模式>Hud`，一眼看出它是沙盒那套界面）。
>
> **新增信号一个 + 改名一个**（§3.4）：
> `StartScreen.mode_selected(mode: String)` —— **域 + 动词过去式** ✓（"玩家选了模式"是**已经发生**的事）；
> ⚠️ 同时**删除** `start_pressed`（见上面 2026-09-25 那条审计的补记）—— 它改名不是"换约定"，而是
> **语义变了**：按下「开始游戏」不再进游戏，进游戏的是"按下某个模式"。
> `Sandbox.phase_changed(phase: String)` —— 同样是**域 + 过去式** ✓；⚠️ 它与全局总线上的
> `Events.phase_changed` **同名但不同作用域**（沙盒那个是 `Sandbox` 自己的信号、**不上总线**）——
> 按 §1.4"同一概念全局同名"这**正是要的**（都是"相位变了"），且 `Sandbox.phase_name()` 与
> `Game.phase_name()` 同名同义 ✓。
>
> **新枚举一个**（§3.5）：`Sandbox.Phase { PLACING, FIGHTING, RESULT }` —— 枚举名 PascalCase 单数 ✓、
> 成员 SCREAMING_SNAKE_CASE 且**不带类型前缀** ✓、**配了名字转换函数** `phase_name()` ✓、
> 代码里**没有一处裸整数**（全是 `Phase.XXX`）✓。⚠️ 成员 `FIGHTING` 与 `Game.Phase.FIGHTING`
> **同名**是有意的（同一个概念：两军正在打），两个枚举各自独立、互不引用。
>
> **新常量**（全 SCREAMING_SNAKE_CASE ✓）：
> `PauseMenu.MENU_LAYER` / `FADE_OUT_MS` / `FADE_IN_MS` / `SCRIM_COLOR` / `OPTION_SEPARATION` /
> `FADE_IDLE` / `FADE_OUT` / `FADE_IN` —— ⚠️ 比原来少了个 `PAUSE_` 前缀：**文件本身已经是"暂停菜单"这个域**，
> 同 `start_screen.gd` 的 `FADE_*_MS`（§3.3 的"功能域前缀"那一条写的就是"子系统自己的一组常量"）；
> 状态三档仍用**具名常量**而不是裸整数 ✓；
> `Sandbox.PICK_MASK` / `PICK_RANGE`（拾取用的碰撞层掩码与射线长度）、
> `SandboxHud.CHIP_COLUMNS` / `REFRESH_MS`（`_MS` 后缀 = 毫秒 ✓，与全库一致）；
> `StartScreen.MODE_CLASSIC` / `MODE_SANDBOX`（**模式 ID 的唯一出处**，值是 `"classic"` / `"sandbox"` ——
> 与既有 `phase_name()` 返回的 `"betting"` 这类**全小写 snake_case 状态串**同一风格 ✓）；
> `UiStyle.CHIP_*`（8 个：兵种小卡的尺寸 / 字号 / 配色）—— 走 §3.3 那条"**功能域前缀**"，
> 与 `hud.gd` 既有的 `ALL_GLOW_*`、`unit3d.gd` 的 `FLAME_FX_*` 同类（都是**纯表现**常量，不进 `GameConfig`）✓；
> `UiStyle.GEAR_BUTTON_PX` / `GEAR_IMAGE_PX` / `GEAR_TEETH` / `GEAR_COLOR`（从 `hud.gd` **原样搬来**）✓；
> `UiStyle.FONT_LARGE|MID|SMALL|TINY` 与 `COLOR_TEAM|TEXT|DIM|WARN|OK`（从 `hud.gd` 搬来，两套 HUD 共用）✓；
> `UiStyle.CAMERA_HINT`（一行**界面文案**常量 —— ⚠️ 这是本文件第一次登记"文案常量"：它存在的理由与
> `UiStyle` 其它常量一致（**两套 HUD 必须显示逐字相同的一句提示**，各持一份必然漂移），不是新约定。
> `UiStyle.make_label()` 是**纯静态工厂**，与既有 `decorate_option()` / `option_style()` 同族 ✓。
>
> **新节点名**（§3.1：PascalCase，**序号 / 种类一律写在 `_` 之后**）：
> `Sandbox` / `SandboxHud` / `PauseMenu`（层名）、`Scrim` / `PauseFade` / `PauseOptions` / `PauseOption_<序号>`、
> `TopBar` / `TopBarRow` / `GearButton`、`PalettePanel` / `PaletteRow` / `PaletteBox` / `ChipGrid` /
> `Chip_<兵种ID>`（⚠️ 后缀是**实体 ID**，与既有 `UnitA_sword_0`、`Scenery_pillar_east_0` 同一种写法）/
> `ActionBox` / `StartButton` / `OverviewButton` / `Overlay` / `RollAgainButton` —— 全部描述角色、无中文 ✓。
>
> **新增公开方法**（snake_case、按用途命名 ✓）：`PauseMenu.configure()` / `open()` / `close()` / `is_open()` /
> `allowed()`；`Sandbox.begin()` / `start_battle()` / `end_battle()` / `roll_again()` / `phase_name()` /
> `select_type()` / `selected_type()` / `roster_of()` / `total_weight()` / `pause_match()` / `resume_match()`；
> `SandboxHud.pause_allowed()` / `pause_actions()` / `pause_action()`（与 `Hud` 的三个**同名同义** ✓ §1.4）；
> `Arena.start_skirmish()` / `stop_skirmish()` / `spawn_unit()`；`CameraRig.camera()`。
> **新增私有成员 / 方法**合 §3.3（`_` + snake_case + 单位写进名字）：
> `_mode_host` / `_ui_host` / `_fade_mode` / `_fade_from_ms` / `_action` / `_black_done`（`PauseMenu`）、
> `_selected_type` / `_types_a` / `_types_b`（**集合用复数** ✓）/ `_pause_from_ms`（`Sandbox`）、
> `_chips` / `_refresh_ms` / `_weight_a|b` / `_alive_a|b` / `_hp_a|b`（`SandboxHud`）、
> `_mode_buttons` / `_fade_mode`（`StartScreen`）、`_pause`（`Hud` / `SandboxHud`）；
> `_place()` / `_remove_unit()` / `_cursor_on_ground()` / `_unit_under_cursor()` / `_camera()` /
> `_settle_battle()` / `_sync_chips()` / `_type_weight()` / `_rebuild_options()` / `_apply_action()` /
> `_build_stage()` / `_start_classic()` / `_start_sandbox()` / `_release_showcase()`。
> 布尔语义读起来像断言 ✓（`is_open()` / `allowed()` / `pause_allowed()`）。
>
> ⚠️ **三处"刻意同名 / 刻意不同名"，都不是冲突，但要记住**：
> 1. `Sandbox.phase_changed` 与 `Events.phase_changed`、`Sandbox.phase_name()` 与 `Game.phase_name()`
>    —— **同一概念全局同名**（§1.4），区别只在作用域（前者是节点自己的信号，不上总线）；
> 2. `Arena.start_skirmish()` / `stop_skirmish()` **刻意不与 `start_match()` 同名**：两者语义不同
>    （"启动赛程" vs "只点火不启赛程"），共用名字会让 `03_rules.md#10.1` 那条唯一分界读不出来。
>    ⚠️ `skirmish` 是本项目新用的词（中文口径是"开战 / 收兵"）—— **若用户觉得该换个词，改名成本很低**
>    （只涉及 `arena.gd` 两处 + `sandbox.gd` 两处调用）；
> 3. `Sandbox.PICK_RANGE` **不带单位后缀**（它是米）—— 合 §3.3 举的例子 `ARENA_HALF_X`（米，同样不带上标），
>    **不是**新惯例。
>
> ⚠️ **顺带登记一条 §3.1 的既有边界情形（本次发现、本次未修、也不新增约定）**：
> **同一帧内先 `Arena.settle()`（`queue_free` 旧单位）再刷兵**时，新节点的名字会与"还没被真正释放"的旧节点
> 撞名 ⇒ 引擎把新节点改名为 `@CharacterBody3D@41` 这种自动名（实测：无头探针里 `settle()` + 立即 `spawn`
> 就复现）。**竞猜模式的换轮历来走这条路**（`game.gd#next_round()`：`settle()` → `_roll_teams()` 同一帧），
> 沙盒的正常路径不会（玩家点一下是一帧）。它**只影响调试可读性**（单位靠 `Arena.units` 数组管理，不靠节点名），
> 故本批**不改**；要治的话是在 `settle()` 里改成立即 `free()`，或给单位序号加一个**单调递增**的计数器。
>
> ⇒ **无新玩法域前缀**（`CHIP_*` 是纯表现的功能域，已按 §3.3 追认）、**无裸整数代枚举**、
> **无拼音 / 中英混拼**、**无命名冲突**。
> ⚠️ **不变量清单本次有改动**（I-20 / I-25 / I-28 加了"适用范围 = 竞猜模式"）—— **那是用户的明确裁决**，
> 不是本文件（命名）的事，见 `99_decisions.md` 同日条目与 `_index.md#2.3` 开头的说明。

> ✅ **2026-09-25 审计（"沙盒拖动放置 + 左键不再收兵 + 兵种按权重排 + 悬停改成原地缩放"这一批）**：
> **无新文件、无新类、无新信号、无新枚举**（改动全落在既有 5 个脚本里）。
>
> **`ui_style.gd`（悬停机制换实现）**：
> 新常量 `HOVER_GROW` / `CHIP_GROW` —— SCREAMING_SNAKE_CASE ✓，都是**倍数**（无量纲）⇒ 不带单位后缀 ✓；
> 新静态方法 `apply_option_hover()` / `apply_chip_hover()`（**动词短语 + 域限定词**，与既有的
> `apply_option_colors()` / `decorate_option()` / `decorate_chip()` 同一族 ✓）与 `_apply_hover()`
> （`_` + snake_case 的**共用实现** ✓）。
> ⚠️ **删除两个名字**：`apply_option_colors()` / `apply_chip_colors()` —— 它们**不是被废弃，是被取代**
>（现在还要管缩放，只叫 "colors" 就名不副实了）。调用点共 4 个文件、8 处，已全部改到新名字。
> ⚠️ **`FONT_HOVER` / `CHIP_FONT_HOVER` 语义收窄**（现在只是"放大幅度"的出处：42/30 与 21/18，
> 字号本身不再变）—— 它们**仍然准确**（就是"悬停目标字号"），故**不改名**，但在定义处写明了新用途。
>
> **`sandbox.gd`（拖动放置）**：
> 新常量 `DRAG_MIN_SPACING` / `DRAG_STROKE_LIMIT` —— SCREAMING_SNAKE_CASE ✓；前者是**米**但不带单位后缀
> —— 与 §3.3 举的例子 `ARENA_HALF_X`（米）以及**同一文件里既有的 `PICK_RANGE`** 同例 ✓（不是新惯例）；
> 后者是**个数上限**，`_LIMIT` 与既有 `PAIR_RETRY_LIMIT` 同族 ✓。
> 新私有成员 `_painting` / `_paint_has_last`（**布尔量，读起来像断言** ✓）/ `_paint_last` / `_paint_count`
> （集合语义不适用 —— 它们是"当前这一笔"的标量记账）；新私有方法 `_begin_paint()` / `_finish_paint()` /
> `_tick_paint()` / `_can_paint_at()` / `_try_paint()` ✓
>（`_tick_*` 与既有 `_tick_pause_fade()` / `_tick_fly_out()` / `_tick_zoom()` 同族；`_can_*` 读作断言；
> `_try_*` 表示"尝试一次、不保证成功"）。
> ⚠️ **一处需要用户裁决的边界**：`_paint_last` 存的是**坐标**（`Vector3`），而 §3.3 写着"坐标用 `pos` / `world_pos`"
> ⇒ 严格说应叫 `_paint_last_pos`。**✅ 2026-09-25 用户裁决："都改" ⇒ 已改名为 `_paint_last_pos`**（代码已同步）。
> ✅ **同批另一处也经用户裁决落地**：`DRAG_MIN_SPACING` / `DRAG_STROKE_LIMIT` 原先住在 `sandbox.gd`，
> 用户裁定"搬进 `GameConfig`" ⇒ 现在是 `GameConfig.DRAG_MIN_SPACING` / `GameConfig.DRAG_STROKE_LIMIT`
>（`sandbox.gd` 只读，不保存副本 —— 合不变量 I-15）。⚠️ 因此上面"新常量"那一段里
> "`sandbox.gd` 新常量 `DRAG_*`"的说法**已作废**：它们现在是 `GameConfig` 的常量，命名本身没变。
>
> **`sandbox_hud.gd`（兵种栏）**：
> 新节点名 `RightPad`（PascalCase ✓、描述角色：右侧留白）—— 它由代码建、必须命名（§3.1）✓；
> 新私有方法 `_types_by_weight()`（`_` + snake_case + 按用途命名 ✓）。
> ⚠️ **顺序不再由 `GameConfig.TYPE_ORDER` 决定**，但**没有动 `TYPE_ORDER` 这个名字、也没有新增"排序表"常量**
>（排序是**运行时**用 `PROFILES[*].weight` 算的，权重仍在 `GameConfig` —— 不变量 I-15 / I-27 都没碰）。
>
> ⇒ **无新玩法域前缀、无裸整数代枚举、无拼音 / 中英混拼**；
> ⚠️ **不变量清单本次无改动**（I-15 / I-20 / I-27 / I-31…I-36 一条都没动）；
> ⚠️ 曾"贴边"的那一处（`DRAG_MIN_SPACING` 的住处）**已按用户裁决搬进 `GameConfig`**，见上面那条补记。

> ✅ **2026-09-25 审计（"拖动根因修复 + 改名竞猜模式 + 三按钮同款 + 两个清空 + 布局保留；下注面板尺寸改回"这两批）**：
> **无新文件、无新类、无新信号、无新枚举**（改动落在既有 6 个脚本里）。
>
> **① 改名（用户裁决"连内部 ID 一起改"）**：`StartScreen.MODE_CLASSIC` → **`MODE_QUIZ`**、
> 字符串 `"classic"` → **`"quiz"`**、`main.gd#_start_classic()` → **`_start_quiz()`**，
> 界面文案「经典模式」→「**竞猜模式**」，4 个文件里 13 处注释一并跟进。
> ⚠️ 这不是"换命名约定"：**约定没变**（模式 ID 仍是全小写 snake_case 的字符串、常量仍 SCREAMING_SNAKE_CASE ✓），
> 换的是"这个模式叫什么"；`08_naming.md` 只留沿革。
>
> **② `sandbox.gd`（拖动修复 + 布局记账 + 清空）**：
> 新公开方法 `clear_team(team)`（**动词开头 + 单数参数**，与既有 `place_bet()` / `skip_round()` 同族 ✓）；
> 新私有成员 `_layout`（`Array[Dictionary]`，**单数名**——它是一个整体"布局"，与既有 `Game.roster_a`（单数名的数组）同例 ✓）；
> 新私有方法 `_ground_at(screen_pos)` / `_begin_paint_at_screen(screen_pos)` / `_try_paint_at_screen(screen_pos)`
>（**`_at_screen` 后缀说清"参数是屏幕坐标"**，避免与"世界坐标"混淆）与 `_respawn_layout()` ✓；
> 之前的 `_cursor_on_ground()` / `_unit_under_cursor()`（无参、内部读视口缓存）**已删除/改签名**
> —— 它们的无参形式正是本次 bug 的温床（见 §下面那条 ⚠️）。
> 裁决①落地：`_paint_last` → **`_paint_last_pos`**（坐标带 `pos` ✓ §3.3）。
>
> **③ `sandbox_hud.gd`（两个「清空」）**：
> 新节点名 `ClearTeam_0` / `ClearTeam_1`（PascalCase + **序号写在 `_` 之后** ✓ §3.1）；
> 新私有方法 `_make_clear_button(team)`（与既有 `_make_label()` 同族 ✓）与 `_on_clear_pressed(team)`
>（**信号回调一律 `_on_<信号名/动作>`** ✓ 与既有 `_on_chip_pressed()` 一致）；新私有成员 `_clear_a` / `_clear_b`
>（⚠️ **`_a` / `_b` 后缀是既有惯例**：同文件的 `_alive_a` / `_hp_a` / `_alive_b` / `_hp_b` ✓）。
>
> **④ `hud.gd`（三按钮同款 + 面板尺寸）**：新私有方法 `_decorate_action_button(button)`
>（**"装扮一个按钮"这一件事**，与 `UiStyle.decorate_*` 同一套词汇 ✓）。
> ⚠️ **本批没有任何新名字掩盖一次真实事故**：插入这个函数时把 `_build_bet_panel()` 末尾的三行
> `_hint_label` **误吞进了新函数体**（缩进一致）⇒ "每装扮一个按钮就多造一个空提示标签"，
> 下注面板凭空高 52 px。它**不是命名冲突**（名字都合规则），是**结构事故** ——
> 已记进 `05_ui_hud.md#3.4` 与 `99_decisions.md` 同日条目，并在那里的"复查条件"里留了一条
> "改这块必须量 `_bet_col` 子节点数（4）与面板高度（247）"。
>
> ⚠️ **一条与命名有关的教训（本批最有价值的一条）**：**"读全局状态"的函数不要藏起它的输入** ——
> 旧代码 `_cursor_on_ground()` 无参、内部直接读 `get_viewport().get_mouse_position()`，
> 于是"界面用事件位置命中、玩法用缓存位置摆兵"这两套位置**在源码上看不出区别**，
> 直到用户报"第一个兵放不出来"才暴露。现在改成 `_ground_at(screen_pos)`：
> **位置由调用方显式传入**（按下传 `event.position`、拖动传视口位置），一眼就能看出两处来源不同。
>
> ⇒ **无新玩法域前缀、无裸整数代枚举、无拼音 / 中英混拼、无命名冲突**；
> ⚠️ **不变量清单本次无改动**（I-15 / I-20 / I-27 / I-31…I-36 一条都没动）。

> ✅ **2026-09-25 审计（"兵种模型预热 + 沙盒右键拖动批量移除 + 操作提示文案 + 右下角提示溢出"这两批）**：
> **无新文件、无新类、无新信号、无新枚举、无新常量**（改动落在既有 6 个脚本里）。
>
> **① `main.gd` + `unit3d.gd`（兵种模型预热）**：
> 新私有方法 `_prewarm_unit_models()`（`_` + snake_case + **按用途命名** ✓）；新私有成员 `_prewarmed`
> （**布尔量读起来像断言** ✓，与既有 `_match_started` 同族）；
> 新公开方法 `Unit3D.warmup_show_all_fx()`（**动词短语 + 域限定词** ✓，与既有 `_show_fx(root, on)` 同一套词汇）。
> 新节点名 `WarmupStage`（PascalCase、描述角色 ✓ §3.1）与 `Warmup_<序号>`（**序号写在 `_` 之后** ✓ §3.1，
> 与既有 `SfxPlayer_<序号>` / `UnitA_sword_0` 同一种写法）。
> ⚠️ **一处用词说明（不是冲突）**：`warmup_show_all_fx()` 里的 **`fx` 不在 §3.3 那张"公认缩写"名单里**
> （名单只列 `hp` / `dps` / `ui` / `id` / `pos` / `dir` / `kb`），但它是本项目**早就立住的词**：
> 信号 `fx_request`、成员 `_fx_blast` / `_fx_burrow` / `_fx_burst`、方法 `_show_fx()`、
> 常量族 `FLAME_FX_*` 都是它 —— ⇒ **沿用既有词汇，不算新缩写、不新增约定**（若哪天要严格化，
> 这是**低成本改名**，只涉及 `unit3d.gd` 一处定义 + `main.gd` 一处调用）。
>
> **② `sandbox.gd`（右键拖动批量移除）**：
> 新私有成员 `_erasing`（**布尔量读起来像断言** ✓，与既有 `_painting` 成对）；
> 新私有方法 `_begin_erase_at_screen(screen_pos)` / `_try_erase_at_screen(screen_pos)` / `_finish_erase()` /
> `_tick_erase()` —— 与左键那一族 `_begin_paint_at_screen()` / `_try_paint_at_screen()` / `_finish_paint()` /
> `_tick_paint()` **逐条同名对称** ✓（`_at_screen` 后缀照旧说清"参数是屏幕坐标"，`_tick_*` 与既有
> `_tick_pause_fade()` / `_tick_fly_out()` 同族）。
> ⚠️ **一处刻意的不对称（记下来免得后人"补全"）**：左键那一侧还有"世界坐标版"的内层
> `_begin_paint(at)` / `_try_paint(at)`（它们要过间距 / 上限两道闸门），**右键这一侧没有对应物** ——
> 收兵是**射线拾取**、从屏幕坐标直接出结果，没有"世界坐标落点"这个概念。⇒ **不要为了对称硬造一个
> `_try_erase(at)`**；真需要闸门时加在 `_try_erase_at_screen()` 里。
> ⚠️ 一处**"读全局状态"的坑已按上一条审计的教训避开**：`_tick_erase()` 与 `_tick_paint()` 一样是
> **轮询兜底**（每物理帧读视口鼠标位置），而"按下 / 拖动"两条路仍**显式传屏幕坐标**
> —— 与 `_ground_at(screen_pos)` 同一条纪律。
>
> **③ `ui_style.gd` / `sandbox_hud.gd` / `hud.gd`**：本批**只改文案与一个数值** ——
> `UiStyle.CAMERA_HINT` 的**值**（`Q/E 升降 · Shift 加速` → `Space/Shift 升降 · Ctrl 加速`，常量名未动）、
> 兵种栏说明行那一串**显示文字**（不带标识符）、`Hud._build_bottom()` 里 `box.offset_left` 的
> **数值**（−640 → −820，属性名未动）⇒ **与 §3.3 / §3.1 均无涉**。
> ⚠️ 但本批给 `05_ui_hud.md#7.2` 留了一条**与命名无关、与数字有关**的约束：
> `CAMERA_HINT` 变长会把右下角那个盒子撑出窗口 ⇒ **改文案要重量槽位宽**（802 ≥ 780）。
>
> ⇒ **无新玩法域前缀、无裸整数代枚举、无拼音 / 中英混拼、无命名冲突、无规则改动**；
> ⚠️ **不变量清单本次无改动**（I-15 / I-20 / I-27 / I-31…I-36 一条都没动 —— 预热用的是 `main.gd` 里
> 几个**内联数值**（临时台子的摆位：间距 2.4 m / 高度 0.6 m，纯表现、玩家看不见，**不是可调玩法参数**）、
> 拖动闸门仍在 `GameConfig`，I-15 未被触碰）。

> ✅ **2026-09-25 审计（"滚轮推拉 + 血条放大 + 音效 3D 空间化"这一批）**：
> **无新文件、无新类、无新信号、无新枚举、无新节点名**（改动落在既有 5 个脚本里）。
>
> **① `config.gd`（滚轮推拉的旋钮）**：新常量 5 个，全 SCREAMING_SNAKE_CASE + `CAM_*` 域 ✓ ——
> `CAM_ZOOM_STEP_RATIO`（倍数，**无量纲** ⇒ 不带单位后缀 ✓）、`CAM_ZOOM_STEP_MIN` / `CAM_ZOOM_STEP_MAX`
>（米，**不带 `_M`** —— 与 §3.3 举的 `ARENA_HALF_X`（米）、以及同一文件里的 `PICK_RANGE` / `CAM_FLY_SPEED`
> 同例，**不是新惯例**）、`CAM_ZOOM_MIN_HEIGHT`（米；`HEIGHT` 与既有 `CAM_FIGHT_HEIGHT` /
> `CAM_FOLLOW_HEIGHT` 同一套词汇 ✓）、`CAM_ZOOM_MIN_DISTANCE`（米）。
> ⚠️ 命名里刻意**没有**出现"线性 / FOV"之类实现词：它描述的是"推拉"这件事，怎么算住在 `camera_rig.gd`。
>
> **② `camera_rig.gd`**：新私有成员 `_zoom_allowed`（**布尔量读起来像断言** ✓，与既有 `_fight_started` 成对）；
> 新私有方法 `_apply_zoom(notches)`（`_` + snake_case + 按用途命名 ✓；参数 `notches` = 滚轮格数，
> **无量纲**，所以不带 `_m`）、`_look_direction()`（返回**方向**向量 ✓，与既有局部变量 `forward` / `right` /
> `back` 同一套词汇）；新 `_input(event)` 是**引擎回调**（与 `_unhandled_input` 同一族，不是自造名字）。
> ⚠️ **一处刻意的"同一件事两个名字"，不是冲突、但必须记住**：`_physics_process()` 里的 `forward`
> 是**水平**视线方向（y 恒为 0，WASD 用），而 `_look_direction()` 是**完整**视线方向（含俯仰，滚轮用）。
> 两者**不是同一个概念**（§1.4"同一概念全局同名"管不到它们），而且**这个分工正是用户定的口径**
>（"w 只能沿镜头方向水平移动，而滚轮能够同时在水平和竖直方向上移动"）⇒ **不要为了"统一"把 `forward`
> 换成 `_look_direction()`**（那会让 W 变成会飞的键，直接违反用户口径）。两者的正确性都按同一套验收：
> 与相机 `basis` 点积 = **1.000**（实测）。
>
> **③ `unit3d.gd` / `unit_factory.gd`（血条放大）**：**只改了 3 个数值、没引入任何标识符** ——
> `BAR_PIXEL_SIZE` 0.011 → 0.022、`HEALTH_BAR_INNER_PX` 30 → 46、局部常量 `HEIGHT_PX` 6 → 9。
> ⚠️ 后两个是 `unit_factory.gd` 里的**既有名字**（`HEALTH_BAR_*` 属 §3.3 追认的表现域前缀），
> 名字本身仍然准确（"内区像素数"就是内区像素数）⇒ **不改名**。
>
> **④ `audio_manager.gd`（3D 空间化）**：
> 新常量 3 个，走 §3.3 的"**功能域前缀**"那条 ⇒ **`SPATIAL_*` 是本批新登记的一个域**
>（音频层的空间化参数，纯表现、不进 `GameConfig`，与 `FLAME_FX_*` / `CHIP_*` / `MOUNT_*` 同类）：
> `SPATIAL_UNIT_SIZE`（米）、`SPATIAL_MAX_DISTANCE`（米）、`SPATIAL_SILENT_DB`（`_DB` 后缀 ✓ 与既有
> `VOLUME_*_DB` 同族）。
> 新私有方法 `_tick_spatial_volumes()`（`_tick_*` 与既有 `_tick_vehicle_loops()` /
> `_tick_pause_fade()` 同族 ✓）、`_apply_spatial_volume(player, listener)`（`_apply_*` 与既有
> `_apply_overview_pose()` / `_apply_mouse_mode()` 同族 ✓）、`_listener_position()` /
> `_source_position(node)`（**坐标用 `position`/`pos`** ✓ §3.3，且两个名字一眼能看出"听者 / 声源"）。
> `_play()` 新增参数 `source_pos`（同上 ✓）。
> ⚠️ **节点名刻意不改**：`SfxPlayer_<序号>` / `VehicleMove_<序号>` 沿用旧名，**没有**加 `3D` 字样 ——
> §3.1 明写"节点名描述**角色**，不是类型"（反例就是 `Node3D2` / `Camera3D1`）⇒ 换成 `AudioStreamPlayer3D`
> 是**实现细节**，不该出现在节点名里。
> ⚠️ 播放器上的元数据键 `"base_db"`（字符串键，snake_case ✓）—— 它是"播放器自己在两帧之间记的账"
>（基础音量），不是跨模块标识符；若以后要加第二个这样的键，沿用同一风格即可。
> ⇒ **无新信号**（§3.4 不涉及 —— 空间化用的全是**既有**信号，`unit_*` 三支本来就带节点）、
> **无裸整数代枚举**、**无拼音 / 中英混拼**、**无命名冲突**；
> ⚠️ **不变量清单本次无改动**（I-15 反而更清楚：新相机旋钮全进 `GameConfig`，血条与音频参数是纯表现、
> 住各自脚本；I-31…I-36 一条没动）。

> ✅ **2026-09-25 审计（"滚轮改缓动 + 定身 + 火枪兵 + 武士大师（四技能）+ 两段音效"这一批）**：
> **无新文件、无新类、无新信号**（改动落在既有 7 个脚本 + 两个音频素材上）。
>
> **① 两个新兵种的实体 ID**：`musket`（火枪兵）/ `master`（武士大师）—— 全小写 snake_case ✓（§2 / §3.3 / **I-33**），
> 与 `PROFILES` 的键、`TYPE_ORDER`、`SILHOUETTE` 的键、`PROFILES[*]["id"]` 四处一字不差 ✓。
>
> **② `config.gd`**：`CAM_ZOOM_SMOOTH`（**1/s**，纳入既有 `CAM_ZOOM_*` 段 ✓）；
> `UNIT_MUSKET_BULLET_SPEED`（`UNIT_*` 域，值是**表达式** `UNIT_BOLT_SPEED × 2` —— 与既有
> `UNIT_SHORTBOW_ARROW_SPEED := UNIT_LONGBOW_ARROW_SPEED * 0.75` 同一手法 ✓）；
> **`UNIT_MASTER_*` 共 22 个**（全 SCREAMING_SNAKE_CASE + `UNIT_*` 域 ✓）：后缀语义清楚 ——
> `_MS`（绝对时长）、`_CHARGES` / `_PER_COOLDOWN`（次数）、`_DISTANCE` / `_WIDTH` / `_RETREAT` / `_DASH`（米）、
> `_SPEED`（m/s，⚠️ **按 `CAM_FLY_SPEED` 的既有先例不带 `_MPS`**）、`_DEG`（角度）、`_RATIO`（无量纲）。
> ⚠️ **一处用户口径的换算被写进名字旁边而不是名字里**：用户说"前摇 0.1 s"，而本项目的前摇是**比例**
> ⇒ 落在 `PROFILES["master"]["windup_ratio"] = 0.15`（**字段名沿用既有的 `windup_ratio`**，没有新名字）。
>
> **③ `unit3d.gd`（定身 + 武士大师四技能）**：新私有成员 `_root_until_ms`（`_*_ms` 单位后缀 ✓，
> **顺带被 `shift_deadlines()` 的属性扫描自动覆盖** ✓）；新公开方法 `apply_root(duration_ms)` /
> `is_rooted()` / `is_incapacitated()`（三者都是"读起来像断言"的动词/形容词短语 ✓，与既有 `apply_stun()` /
> `is_stunned()` 逐条对称 ✓）；新私有方法 `_pause_lance(added_ms)`（眩晕与定身**共用**的冲刺计时补偿 ✓）。
> 武士大师那一族：新枚举 **`Iai { NONE, RETREAT, CHARGE, DASH, SELF_ROOT }`** —— 枚举名 PascalCase 单数 ✓、
> 成员 SCREAMING_SNAKE_CASE 且**不带类型前缀** ✓（§3.5），与既有 `Flame` / `Burrow` 同一套做法
>（⚠️ 那两个**也没有**"名字转换函数"，`Iai` 与它们一致；§3.5 那条要求是写给"要显示给玩家 / 写日志"的枚举的）。
> 新字段 `_deflect_charges_left` / `_deflect_since_cd` / `_deflect_cd_until_ms` / `_dash_until_ms` / `_dash_dir` /
> `_master_dash_cd_until` / `_backstep_cd_until` / `_iai_phase` / `_iai_until_ms` / `_iai_from_ms` / `_iai_cd_until` /
> `_iai_dir` / `_iai_dash_from` / `_iai_dash_to` / `_iai_targets`（集合用复数 ✓，每条都带 `_ms` / `_dir` /
> `_from` / `_to` 这类单位或角色后缀 ✓）；新方法 `_tick_master()` / `try_deflect(arrow)` / `_can_master_dash()` /
> `_start_master_dash()` / `_tick_master_dash()` / `_tick_backstep()` / `_enemy_pressing_me()` / `_can_iai()` /
> `_start_iai()` / `_iai_dash_ms()` / `_tick_iai()` / `_iai_mark_passed()` / `_iai_has()` / `_iai_settle_targets()` /
> `_distance_to_segment()` / `_clamp_into_arena()` / `is_winding_up_at(who)`（`_tick_*` / `_can_*` / `is_*` /
> `_start_*` / `_iai_*` 全部与既有族同名式 ✓）。
> ⚠️ **一处"刻意不同名"，必须记住**：`is_rooted()`（**定身**）与 `is_knockback_immobile()`（**击退禁移**，
> 2026-09-18 就有）是**两件不同的事** —— 前者"根本推不动"，后者"被推着走但不能自主移动"。
> 本批给"定身"选 `root` 而**不是** `immobilize`，正是为了不与后者撞车（§1.4 的同一个精神，见
> `02_entities.md#2.6` 与 `04_physics.md#5`）。
>
> **④ `arrow.gd`**：新字段 `pierce`（次数 ✓）、`_pierced`（**被穿过的那些单位的 RID**）、`deflected`
>（布尔量读作断言，与既有 `alive` / `active` 同一形态 ✓）；新方法 `is_small_projectile()`（`is_*` 判据 ✓）、
> `_build_bullet()`（与既有 `_build_stone()` / `_build_bolt()` / `_build_arrow()` 同族 ✓）。
> ⚠️ 新分支名 `"deflected"` / `"musket_bullet"` 是**内部协议串**（`kind` 取值），与既有
> `"stone"` / `"bolt"` / `"shortbow_arrow"` / `"longbow_arrow"` 同一风格 ✓（全小写 snake_case）。
>
> **⑤ `unit_factory.gd`（两个新模型）**：新节点名全 PascalCase 且描述角色 ✓ —— `Musket`（枪管 / 枪口箍 /
> 枪托 / 枪机 / 通条各件）、`Katana`（刀身 / 圆镡 / 缠柄）、`Tricorne*`（帽冠 / **`TricorneFlap_0/1/2`**
> —— 序号写在 `_` 之后 ✓ §3.1）、`Cockade`、`Headband` 等；`SILHOUETTE` 的两条新键 = 实体 ID ✓。
>
> **⑥ 两段音效**：新事件名 `combat_musket_fire`（`<域>_<对象>_<动作>` ✓ 与 `combat_bow_release` 同族）；
> `combat_lance_charge` 是**§3 早已登记**的名字（本次只是接通）⇒ **没有新名字**。
> 新常量 `VOLUME_LANCE_DB`（`VOLUME_*_DB` 族 ✓）。
>
> ⚠️ **两处自查出来的瑕疵（本次只同步文档、未动代码 ⇒ 留给下一批，请用户裁决）**：
> ① **`UNIT_MASTER_STEP_SPEED` 定义了但没有任何引用** —— 后撤步最后落到"瞬移"（不需要速度），
>    它成了死常量；且它的注释里写的 `_backstep()` **函数名不存在**（实际是 `_tick_backstep()`）。
>    建议：**删掉常量 + 改注释**（或改回"平滑位移"再用上它）；
> ② **`_dash_until_ms` 与 `_master_dash_cd_until` 前缀不对称**（同一技能的"进行中"与"冷却"两个字段，
>    一个有 `_master_` 一个没有）。建议统一成 `_master_dash_until_ms`。⚠️ **两条都不是命名约定冲突**
>（都合 §3.3），只是**新引入的不一致**，所以按规矩**报告、不悄悄改**。
> ⇒ **无拼音 / 中英混拼、无裸整数代枚举**（`Iai` 全用具名成员）、**无不变量改动**
>（I-33 新增两个合规 ID；I-31…I-36 其余一条未动）。

> ✅ **2026-09-25 审计（"偏折只归大师 + 三处数值 + 拔刀斩/冲刺/后撤步改口径 + 沙盒自由视角输入"这一批）**：
> **无新文件、无新类、无新信号、无新枚举、无新节点名**（改动落在既有 3 个脚本里）。
>
> **① `config.gd`**：新常量 **4 个**，全 SCREAMING_SNAKE_CASE + `UNIT_*` 域 ✓ ——
> `UNIT_MASTER_IAI_RANGE` / `UNIT_MASTER_DASH_RANGE`（米，`_RANGE` 与既有 `UNIT_LANCE_CHARGE_RANGE` 同词 ✓）、
> `UNIT_MASTER_BACKSTEP_MS` / `UNIT_MASTER_DASH_LOCK_MS`（`_MS` = 毫秒 ✓）。
> 其余只改**值**、不涉及命名：`PROFILES["musket"]["weight"]` 5 → 4、`PROFILES["master"]["hp"]` 800 → 1000、
> `UNIT_MASTER_DEFLECT_CD_MS` 4000 → 2000、`UNIT_MASTER_IAI_DASH_SPEED` 70 → 105。
>
> **② `unit3d.gd`**：新私有成员 `_backstep_from` / `_backstep_to`（**`_from` / `_to` 说清两端** ✓）、
> `_backstep_until_ms` / `_dash_lock_until_ms`（`_ms` ✓）；`_tick_backstep()` **签名变了**（void → bool：
> 滑行段要"独占整帧"）但**名字没变** ✓；`_deflect_charges_left` 的**默认值**从 15 改成 0 并移进 `_ready()` 发放 ✓。
>
> **③ `sandbox.gd`**：新私有方法 `_overview_active()`（**布尔判据读起来像断言** ✓，与既有 `_can_paint_at()` 同族），
> 三处调用它（`_unhandled_input()` / `_tick_paint()` / `_tick_erase()`）✓。
>
> ⚠️ **一条与命名直接相关的"真问题"（必须记住：**名字决定行为**）**：
> **`shift_deadlines()` 只平移"名字以 `_ms` 结尾的 int 字段"**（`unit3d.gd` 的属性扫描）——
> 这是 pause 补偿的唯一入口。⇒ **凡是"绝对毫秒截止时刻"没有以 `_ms` 结尾，暂停恢复时就不会被后移**，
> 表现是"暂停 10 秒回来，那个冷却已经走完了"（与 `03_rules.md#7` / I-13 的口径相反）。
> 现状盘点（本批查过一遍）：**6 个字段没带 `_ms`** ——
> **本批之前就有的 3 个**：`_skill_cd_until` / `_kb_until` / `_bash_cd_until`；
> **我上一批引入的 3 个**：`_master_dash_cd_until` / `_backstep_cd_until` / `_iai_cd_until`
>（⚠️ **我上一批还引入了 `_deflect_cd_until_ms` / `_dash_until_ms` / `_backstep_until_ms` / `_dash_lock_until_ms`
> —— 这四个带了 `_ms`，**是好的**；同一个技能里两种写法混着，正是这条要治的病）。
> ✅ **修法与 §3.3 完全一致**（"单位写进名字"）：把这 6 个改名为 `*_until_ms`（纯改名、零逻辑改动，
> 改完 pause 补偿自动覆盖）。⚠️ **本次只同步文档、未动代码** ⇒ **请用户裁决是否下一批改名**
>（它既是命名问题、也有行为后果，所以按规矩**报告而不悄悄改**）。
>
> ⚠️ **另一条教训（与"字段的默认值也是接口的一部分"有关）**：`try_deflect()` 定义在 `Unit3D` 上、
> 但**只有武士大师该能用** —— 第一版把"额度"的**字段默认值**写成 15 且函数里**没有身份闸门**，
> 于是"任何被打中的敌人"都能反弹（火枪手被自己的子弹打死）。⇒ **跨兵种复用的方法必须自带"我是谁"的判据**；
> **默认值不要写成"某个兵种才配有的量"**（默认 0 + 在 `_ready()` 里按兵种发放 ✓）。
> ⇒ **无拼音 / 中英混拼、无裸整数代枚举、无功**能域前缀新增**（四个常量都在既有 `UNIT_MASTER_*` 组里）、
> **无不变量改动**（I-33 未新增 ID；I-15 的落点不变：新常量全在 `GameConfig`）。

> ✅ **2026-09-25 审计（设置界面 + BGM + 音量接口 + 移除两条音效这一批）**：
> **无新信号、无新枚举、无新实体 ID、无新功能域前缀**；新增 **1 个脚本文件**（§3.2）。
>
> **① 脚本与类名（§3.2）**：`scripts/ui/settings_screen.gd` ↔ `class_name SettingsScreen` 一一对应 ✓，
> 与同目录 `pause_menu.gd` / `PauseMenu`、`ui_style.gd` / `UiStyle` 同式。
>
> **② 常量（§2 对照表）**：新增 **15 个**，全 SCREAMING_SNAKE_CASE ✓ ——
> `audio_manager.gd`：`BUS_MUSIC` / `BUS_SFX`（与既有 `BUS_COMBAT` / `BUS_UNIT` 同族，`BUS_*` 是**既有实践**、
> 不是新开域）、`GROUP`、`MIN_VOLUME_DB`、`VOLUME_BGM_DB`、`BGM_MAIN`、`PREVIEW_EVENT`；
> `settings_screen.gd`：`SETTINGS_LAYER` / `SCRIM_COLOR` / `ROW_SEPARATION` / `LABEL_MIN_WIDTH` /
> `SLIDER_MIN_SIZE` / `PERCENT_MIN_WIDTH` / `BUTTON_SEPARATION` / `PREVIEW_MIN_INTERVAL_MS`。
> ⚠️ 它们**全是"纯表现参数"** ⇒ 按既有惯例住脚本、**不进 `GameConfig`**（不变量 I-15 管的是可玩数值）；
> 单位照 §3.3"写进名字"：`_DB`（分贝）、`_MS`（毫秒）✓。
> ⚠️ **一处沿用现状、值得记下**：`LABEL_MIN_WIDTH` / `PERCENT_MIN_WIDTH` / `MIN_VOLUME_DB` 一族是**像素**却
> **不带 `_PX`** —— 与 `ui_style.gd` 既有的 `MIN_SIZE` / `CHIP_MIN_SIZE` 及 `pause_menu.gd` 的
> `SCRIM_COLOR` / `OPTION_SEPARATION` 同例（本项目的 UI 尺寸**历来不写 `_PX`**，只有齿轮那两个老常量写了）。
> ⇒ **属于沿用现状，不是本次新立的约定**；要统一成"UI 尺寸一律 `_PX`"是**另一件事**，本次不动。
>
> **③ 成员名（§3.3）**：私有成员全 `_` + snake_case ✓ —— `_music` / `_ui` / `_bgm_table` / `_bgm_id` /
> `_snapshot_music_db` / `_snapshot_sfx_db` / `_applying` / `_dragging_sfx` / `_last_preview_ms` / `_built` /
> `_audio` / `_settings` / `_settings_button` / `_back_button` / `_music_slider` / `_sfx_slider` /
> `_music_value` / `_sfx_value` / `_last_preview_ms`。
> ⚠️ `_ui` 用的是**公认缩写** —— §3.3 第一条把 `ui` 明确列进白名单（`hp` / `dps` / `ui` / `id` / `pos` / `dir` / `kb`）✓；
> `_applying` / `_dragging_sfx` 是布尔量、**读起来像断言**（与既有 `_flying` / `_closing` 同式）✓；
> `_last_preview_ms` 带 `_ms` 单位 ✓（⚠️ 它是**节流时间戳**、不是"绝对截止时刻"，所以**不参与**
> `MatchPause.shift_deadlines()` 的属性扫描 —— 那条扫描只跑在 `Arena` / `CameraRig` / `Unit3D` 上，UI 层不在其列）。
>
> **④ 方法名**：`play_bgm()` / `stop_bgm()` / `current_bgm()` / `preview_sfx()` / `music_db()` / `sfx_db()` /
> `set_music_db()` / `set_sfx_db()` —— 动词或"名词 + 单位"、**getter 无前缀 / setter 加 `set_`** 成对 ✓；
> 静态访问器 `AudioManager.find(tree)` 沿用既有写法（同 `MatchPause.pause_tree()` 的静态工具口径）；
> 私有方法 `_build_bgm_table()` / `_bgm_stream()` / `_bus_db()` / `_set_bus_db()` / `_apply_screen_bgm()` /
> `_setup_audio()` / `_ensure_built()` / `_add_slider_row()` / `_write_buses()` / `_refresh_value_labels()` /
> `_slider_to_db()` / `_db_to_slider()` / `_preview_sfx()` 全 `_` + snake_case ✓。
> ⚠️ **一处自查**：`SettingsScreen.open()` / `close()` / `cancel()` / `apply()` 是**公开**方法（按钮与 `Esc`
> 两条路径都调），**故意不带 `_`** —— 与 `PauseMenu.open()` / `close()` 同一取舍（它们是给外面调的 API）。
>
> **⑤ 节点名（§3.1）**：`SettingsRoot` / `SettingsPanel` / `SettingsBox` / `MusicRow` / `MusicRowSlider` /
> `MusicRowValue` / `SfxRow` / `SfxRowSlider` / `SfxRowValue` / `ButtonRow` / `Scrim` —— 全 PascalCase 且
> **描述角色而不是类型** ✓；`SettingButton_0` / `SettingButton_1` 的**序号写在 `_` 之后** ✓
>（与既有 `Option_0` / `PauseOption_0` / `SfxPlayer_0` / `UnitA_sword_0` 同式）；
> 新增两个 2D 播放器节点 `MusicPlayer` / `UiPlayer` 同理 ✓。
>
> **⑥ 组名**（⚠️ **这一档 §2 对照表里原本没有**）：新增了一个组 `"audio"`（`AudioManager.GROUP`，供界面组查找）。
> 项目现存的唯一先例是 `"units"`（全小写、无前缀、无复数变化），新组**沿用那个写法**。
> ⇒ **不构成冲突**（没有任何规则被违反），但**表里确实缺"组名"这一档** —— ✅ **2026-09-25 用户裁决：
> "在 §2 补一行『组名 = 全小写 snake_case（`units` / `audio`）』"** ⇒ 已补进 §2 对照表末尾（并按 §4 的规矩
> 在同一条决策记录里留痕），`"audio"` 这个新组名**当场转为合规**；本文件除此之外**没有别的规则改动**。
>
> **⑦ "移除音效"在命名侧的影响**：删掉的 `combat_hit_flesh` / `unit_die` 两个**事件名不留空位、也不改名**
>（"事件名一经使用不再改名"是 `06_audio.md#3` 的口径），命名侧只确认**没有引入新名字**。
> ⇒ **无拼音 / 中英混拼、无裸整数代枚举、无新域前缀、无新信号**（§3.4 不涉及）。

> ✅ **2026-09-25 审计（武士大师前摇 + 偏折 6 m + 新增两个兵种：心灵腐化师 / 玉面手雷王）**：
> **无新信号、无新枚举、无裸整数代枚举、无拼音与中英混拼、`§2` 对照表本批没有新增档位**
>（两个新兵种落在**既有**档位 10 与 1 上，见 `02_entities.md#4` 的 I-27。⚠️ 本条与**上一条**审计
> 记的是同一天的两批，别混：上一条补的是"**组**"那一档）。
>
> **① 新实体 ID（I-33 / §2）**：**`corruptor`**（心灵腐化师）、**`grenadier`**（玉面手雷王）——
> 全小写 snake_case ✓，与既有 `lightcav` / `sandworm` / `musket` / `master` 同式；两者同时进了
> `PROFILES`、`TYPE_ORDER`、工厂的 `SILHOUETTE` 与 `00_world.md#4.4` 的轮廓表 ⇒ **四处同名**（§1.4）。
>
> **② 新常量（§2 表：常量 = SCREAMING_SNAKE_CASE）**：**5 个，全在 `GameConfig`** ⇒ 与不变量 **I-15**
>（可调参数的唯一住处）一致，且**沿用既有 `UNIT_*` 域**、**没有新开功能域前缀** ——
> `UNIT_MASTER_DEFLECT_RANGE`（6.0 m，与同组的 `UNIT_MASTER_DEFLECT_*` 连成一段）、
> `UNIT_CORRUPT_CHARGE_MS`（500）/ `UNIT_CORRUPT_HOLD_MS`（200）/ `UNIT_GRENADE_BLAST_RADIUS`（4.0）/
> `UNIT_GRENADE_BLAST_DAMAGE`（150.0），后四个单独成段并写了段首注释（新兵种自己的域段）。
> ⚠️ 单位后缀照 §3.3 写进名字：`_MS`（毫秒）、`_RANGE` / `_RADIUS`（米）、`_DAMAGE`（点数）✓。
>
> **③ 新成员（§3.3）**：**1 个公开 + 6 个私有** ——
> `corrupt`（**公开**：它要被 `_mcp_state()`、腐化条与"换边判据"三处读，与既有的 `hp` / `team` / `alive`
> 同级，**不加 `_`** ✓）；私有的 `_corrupt_last_ms`、`_laser_charge_until_ms`、`_laser_target`、
> `_corrupt_bar`、`_corrupt_fill_px`、`_laser_beam` —— 全部 `_` + snake_case ✓；
> ⚠️ **两个"时刻"字段都带 `_ms`**：`_corrupt_last_ms`（最近一次被照射）与 `_laser_charge_until_ms`（蓄力截止）
> ⇒ **自动进 `match_pause.gd#shift_deadlines()` 的属性扫描**（暂停恢复时一起后移）——
> 这一点是**刻意**的：`_corrupt_last_ms` 若不平移，"暂停 10 s 回来"会被算成"早就不在被照了"、
> 腐化值凭空清掉（与 I-13 的暂停口径相反）。⚠️ 这条正好呼应本文件**上上条审计**里那两个
> `_*_until`（缺 `_ms`）的改名待办 —— **新代码一律带 `_ms`，不再添新的**。
>
> **④ 新方法**：`is_corruptor()` / `is_self_destructor()`（**布尔判据读起来像断言** ✓，与既有
> `is_ranged()` / `has_shield()` / `is_burrower()` 同族 —— ⚠️ 它们都是**查 PROFILE 标记**而不是查 `type_id`，
> 沿用"我是什么只有一处出处"这条老教训）；`_add_corruption()` / `_tick_corruption()` / `_convert_to()` /
> `_refresh_corrupt_bar()` / `_laser_beam_active()` / `_build_laser_beam()` / `_update_laser_beam()` /
> `_self_destruct()` —— 全 `_` + snake_case、动词开头 ✓。
>
> **⑤ 新节点名（§3.1：PascalCase + 描述角色）**：本批直接建的只有两个 —— **`CorruptBar`**（腐化条）与
> **`LaserBeam`**（激光光束）✓ 都描述角色、不是类型。工厂（`unit_factory.gd`）为两个新模型建的一大批
> 也逐条合规则：`Robe` / `RobeHem` / `HemTrail` / `Hood` / `HoodBrim` / `VoidFace` / `MindEye_left|right` /
> `RobeCollar` / `Mantle_left|right` / `Prism` / `OrbCore` / `Shard_0..2` / `HaloShard_0..5`（腐化师）与
> `Body` / `StubLeg_front_left|front_right|rear_left|rear_right` / `Belt` / `Buckle` / `JadeMask` /
> `Smile_0..2` / `EyeSlit_left|right` / `CheekPlate_left|right` / `Bomb` / `BombBand` / `Fuse_Cap` / `Fuse` /
> `SparkTip` / `SparkTongue_0..2` / `Arms` / `StubArm_left|right` / `Mitt_left|right` / `FxHit` /
> `BlastCore` / `BlastRing` / `BlastEdge` / `BlastFlame_0..3`（手雷王）——
> ⚠️ **序号一律写在 `_` 之后**（`Shard_0` / `HaloShard_0..5` / `Smile_0..2` / `SparkTongue_0..2` /
> `BlastFlame_0..3`）✓，复合名用 `_` 连（`StubLeg_front_left` / `EyeSlit_left`）✓，**没有中英混拼** ✓。
>
> **⑥ 表现参数常量（住各自脚本、不进 `GameConfig`，合 I-15）**：`LASER_BEAM_RADIUS` / `_COLOR` /
> `_EMISSION` / `_FALLBACK_Y` / `_AIM_Y`、`CORRUPT_BAR_COLOR` / `CORRUPT_BAR_LIFT`（都在 `unit3d.gd`）；
> 工厂里两支各成一段：`CORRUPTOR_*`（`HOVER` / `ROBE_*` / `HEM_GAP` / `HALO_*` / `ORB_*` / `SHARD_ORBIT`）、
> `GRENADIER_*`（`FUSE_*` / `MASK_*` / `BOMB_*` / `BLAST_*`）——
> 与既有 `FAN_*` / `KITE_*` / `VEHICLE_*` / `MOUNT_*` / `FLAME_FX_*` / `BAR_*` **同一条"功能域前缀"惯例** ✓
>（§3.3 那条"另允许功能域前缀"，2026-09-19 追认）⇒ **不是新开域**。
> ⚠️ **两处如实自查（沿用现状，不是本批新立的约定）**：
> ① `LASER_BEAM_FALLBACK_Y` / `LASER_BEAM_AIM_Y` / `CORRUPT_BAR_LIFT` / `CORRUPTOR_HOVER` 等**米制偏移
>   没有统一后缀**（只有 `_RADIUS` / `_Y` / `_LIFT` 这类位置词）—— 与本项目 UI / 表现常量历来不写单位后缀
>   的习惯一致（同 `MIN_SIZE` / `SCRIM_COLOR` / `GEAR_BUTTON_PX` 一族）；
> ② 新增常量 **`HEADLESS_TYPES`**（工厂里"不建头 / 鼻尖"的两个兵种）是**复数集合名** ⇒ 合 §3.3"集合用复数" ✓，
>   且它**刻意没有并进** `NO_HUMANOID_TYPES`（并进去会连躯干一起跳过 ⇒ 队伍色与受击闪白静默失效），
>   两条集合的语义差别已写在工厂的常量注释里。
>
> ⇒ **本文件无冲突、无规则改动、无不变量改动**（I-15 落点不变：5 个新玩法常量全在 `GameConfig`；
> I-33 两个新 ID 合规；I-27"只补例子、规则未动"；I-06 / I-13 未动）。
> ⚠️ **遗留待办照旧**：本文件 `#3.3` 上上条审计里那 6 个 `_*_until`（缺 `_ms`）字段**仍等用户裁决改名** ——
> 本批**没有**新增同类问题（见上面③）。

> ✅ **2026-09-25 审计（第三轮：腐化师闸门 + 前摇给定值 + 影魔 `shadow` 及其模型）**：
> **无新信号、无新枚举、无裸整数代枚举、无拼音、§2 对照表本批没有新增档位**。
>
> **① 新实体 ID（§2 表 / I-33）**：**`shadow`** 全小写 snake_case ✓，**四处同名**：
> `GameConfig.PROFILES["shadow"]` / `TYPE_ORDER` / `UnitFactory.SILHOUETTE` / `00_world.md#4.4`。
> （另外本批给 `HEADLESS_TYPES` 追加了 `"shadow"` —— 那是**已有的集合常量**、不是新名字。）
>
> **② 新常量（§2 常量档 / I-15）**：**6 个玩法常量全部住进 `GameConfig`、沿用既有 `UNIT_*` 域、没有新开域** ——
> `UNIT_SHADOW_STRIKE_CD_MS`（4000）/ `UNIT_SHADOW_STUN_MS`（2000）/ `UNIT_SHADOW_DASH_SPEED`（120）/
> `UNIT_SHADOW_LAND_RATIO`（0.9）/ `UNIT_SHADOW_HOUR_STEP`（80）/ `UNIT_SHADOW_HOUR_MAX`（320），
> 外加一个**推导式**常量 `UNIT_SHADOW_HOUR_FULL_MS := int(UNIT_SHADOW_HOUR_MAX / UNIT_SHADOW_HOUR_STEP * 1000.0)`
>（= 4000）—— ⚠️ 写成推导式是刻意的：**两个数一旦改动不会脱钩**（它们本是同一个量的两种说法）。
> 单位后缀照 §3.3 写进名字：`_MS`（毫秒）、`_SPEED`（m/s）、`_RATIO`（无量纲比例）、`_STEP` / `_MAX`（伤害值）✓。
> ⚠️ `UNIT_SHADOW_LAND_RATIO` 是**比例** ⇒ 按 §3.3"单位写进名字"的口径，**比例不带单位后缀**是对的（与既有的
> `UNIT_CONTACT_RATIO` / `windup_ratio` 同例）。
>
> **③ `SHADOW_*` 是"功能域前缀"的**新实例**（§3.3 第二段那张清单要加一笔）**：**37 个纯表现常量**全部住在
> `unit_factory.gd`、`SCREAMING_SNAKE_CASE`、**同域连续成段 + 段首 `# ---- 影魔 ----` 注释** ⇒ 与
> `FAN_*` / `KITE_*` / `VEHICLE_*` / `MOUNT_*` / `CORRUPTOR_*` / `GRENADIER_*` **并列**，规则照旧：
> **只限表现参数**，玩法数值一个都不许自开域。⚠️ **它没有进 `GameConfig`**（I-15 只管可玩数值）✓。
>
> **④ 新成员（§3.3）**：`_strike_cd_until_ms` / `_shadow_until_ms` / `_shadow_from_ms` / `_hour_anchor_ms` /
> `_shadow_from` / `_shadow_to` —— 全 `_` + snake_case ✓。⚠️ **前四个都带 `_ms`** ⇒
> **自动进 `shift_deadlines()` 的属性扫描**；其中 `_shadow_from_ms` 与 `_hour_anchor_ms` 是**起点**（不是截止时刻），
> **跟着平移正是要的**：否则暂停 10 s 回来，"蓄势"会凭空涨到封顶 —— 与 I-13 的暂停口径相反。
> `_shadow_from` / `_shadow_to` 是**位置**（`Vector3`）⇒ 不带时间后缀 ✓（与既有 `_backstep_from/_to` 同式）。
>
> **⑤ 新方法**：2 个**断言式** `is_shadow_demon()` / `is_in_shadow_form()`（读起来像断言 ✓，与
> `is_corruptor()` / `is_self_destructor()` 同族 —— 都是"我是什么"的 PROFILE 判据）+ 7 个 `_` 私有动词式：
> `_try_shadow_strike()` / `_tick_shadow()` / `_end_shadow()` / `_hour_bonus()` / `_outgoing_damage()` /
> `_nearest_enemy_of_type()` / `_shadow_landing()` ✓（`_try_*` 返回"吃没吃掉这次伤害"、`_tick_*` 推进一帧，
> 与既有 `_try_paint()` / `_tick_*` 同族）。
>
> **⑥ 新节点名（§3.1）**：影魔那 **28 个**全部 PascalCase 且描述角色 ✓，序号 / 方位一律写在 `_` 之后：
> `ShadowHead` / `VisorSpike` / `CrownShard_0..2` / `ShadowTail_0..3`（**0 = 正前**）/ `ShadowTrail` /
> `ShadowPool` / `WaistSash` / `CapeYoke` / `CapeShard_0..2` / `DualBlades` / `Hand_left|right` /
> `Blade_left|right` / `BladeEdge_*` / `Guard_*` / `Hilt_*` ✓。
> ⚠️ 两条如实登记：① **`_headgear()` 对 `shadow` 无支**（刻意的：它的"头饰"是多面体头 + 前突尖 + 尖冠，
> 由分支自己建）—— **将来别给它加 `_` 兜底支**，否则影魔头上会再扣一顶盔；
> ② `ShadowPool`（影滩）挂在 `visual` 下 ⇒ **随待机浮动一起上下**（沿用现状；要钉死在地面得 reparent 到本体根，
> 那是 `unit3d.gd` 的范围、超出建模批次）。
> ⚠️ ③ 模型里**一件 `Fx*` 根都没有**（37 个常量全是普通 `_mesh()` + 自发光）—— 这不是命名问题，是**上面那条
> "常亮件挂 `Fx*` 必被每帧藏掉"的实测坑**的正面写法（已在 `00_world.md#4.4` 登记）。
>
> ⇒ **本文件无冲突、无规则改动、无不变量改动**（I-15 落点不变：6 个玩法常量进 `GameConfig`、37 个表现常量住脚本；
> I-27"只补例子"；I-33 新 ID 合规；I-06 / I-13 未动）。
> ⚠️ **遗留待办照旧**：那 6 个 `_*_until`（缺 `_ms`）字段仍等用户裁决 —— 本批新增的 4 个 `_ms` 字段
> **一律带后缀**，没有再添同类问题。

> ✅ **2026-09-25 审计（第四轮：影魔伤害封顶改口径 + 大师后撤窗口收窄 + 腐化绕过无敌 + 手雷王自爆 120）**：
> 本批**没有新文件、没有新兵种、没有新信号、没有新枚举、没有新节点名**（改动全落在既有 3 个脚本的既有函数里）。
>
> **① 新常量 1 个**：`UNIT_MASTER_BACKSTEP_LEAD_MS`（= **150**）—— 沿用既有 `UNIT_MASTER_*` 玩法域、
> `_MS` 单位后缀 ✓、住 `GameConfig`（合不变量 I-15）✓。
> ⚠️ 另有 **3 个既有常量的"值/语义"变化，名字一个没改**：
> `UNIT_GRENADE_BLAST_DAMAGE` 150 → **120**（`UNIT_*` 域 ✓）；
> `UNIT_SHADOW_HOUR_MAX` 的**语义收窄**（"额外伤害上限" → "**总伤害上限**"）—— ⚠️ **这是本批唯一"名字没变、
> 含义变了"的地方，如实登记；它不是命名冲突**（名字本身没歧义："伤害上限"本来就该是总量的上限，
> 上一轮把它当额外伤害用才是偏的）；`UNIT_SHADOW_HOUR_FULL_MS` 4000 → **3000**（跟着上面那个上限走）。
>
> **② 一处签名变更（加法，不是改约定）**：`Unit3D.is_winding_up_at(who)` → **`is_winding_up_at(who, lead_ms: int = 0)`**
> —— **新增一个带默认值的可选参数**，默认 0 = 旧行为（"整个出手窗口都算"）⇒ **所有既有调用点的行为一字不变**；
> 只有武士大师的后撤步传 `UNIT_MASTER_BACKSTEP_LEAD_MS`。⚠️ 参数名 `lead_ms` 合 §3.3（`_ms` 单位写进名字、
> 语义 = "命中帧前多久"）✓。**这不是"改命名约定"，是"给既有名字加一个可选维度"**。
>
> **③ 一个名字被删除**：`_hour_bonus()` **已删**（它的职责并进 `_outgoing_damage()`）——
> 因为口径改成"**总伤害**封顶"之后，"面板伤害 + 加成"这个二分法本身就不存在了，留着会变成
> **同一个概念两个名字**（§1.4）。⇒ 现在只有 `_outgoing_damage()` 一个出口，
> 且它对非影魔**逐位返回 `GameConfig.hit_damage()`**（不给全场带来数值漂移）。
>
> **④ 无新增档位、无新域、无拼音、无裸整数代枚举**：本批不涉及 I-27 / I-33（没有新兵种、没有新 ID）。
> 既有成员名（`_hour_anchor_ms` / `_shadow_*` / `_strike_cd_until_ms`）**一个都没动** ✓。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**（I-15 落点不变：新常量仍进 `GameConfig`）。

> ✅ **2026-09-25 第七轮审计（"竞猜前四轮种数收窄 + 影魔重做 + 召唤石柱 + 沙盒权重递增"这一批）**：
> **无新文件、无新类、无新信号（0 个）、无新枚举**。
>
> **① 新兵种 ID 1 个**：`pillar` —— 全小写 snake_case ✓（§2 与 **I-33**）；它同时是**第一个沙盒专属**兵种
> （`PROFILE["sandbox_only"]`，数据字段小写 ✓，与 `stun_immune` / `self_destruct` / `boss` 同族）。
>
> **② 新常量（全部 SCREAMING_SNAKE_CASE ✓）**：
> `GameConfig`：`EXACT_KINDS_BY_ROUND`、`SUMMONER_TYPE`、`UNIT_SUMMON_INTERVAL_MS` / `_WINDOW_MS` / `_MAX_BATCH` /
> `_RING_RADIUS`、`UNIT_ESCALATION_START_MS` / `_WEIGHT_START` / `_WEIGHT_STEP`
> —— 玩法数值沿用既有 `UNIT_*` 域、**住 `GameConfig`** ⇒ 合 I-15 ✓；
> `unit_factory.gd` 新增**一族表现域前缀 `PILLAR_*`**（底座 / 柱身 / 石箍 / 晶体 / 光环 / 石料色，
> 与 `MOUNT_*` / `CORRUPTOR_*` 同类的"一个兵种的整套几何"，已按 §3.3 的"功能域前缀"登记）；
> `SHADOW_*` 这一族**扩编**（`SHADOW_WISP_*` / `SHADOW_ARM_*` / `SHADOW_EYE_*` / `SHADOW_FORM_*`）；
> `unit3d.gd`：`SHADOW_FORM_STRETCH`、`SUMMON_BEAM_COLOR` / `SUMMON_BEAM_EMISSION`（表现常量住脚本，同 `FLAME_FX_*` / `LASER_BEAM_*`）。
> ⚠️ **一处跨文件的同域**：`SHADOW_*` 这一族现在**同时出现在 `unit_factory.gd`（几何）与 `unit3d.gd`（动画）** ——
> §3.3 只要求"同域常量连续成段"，**没有"必须同文件"这一条** ⇒ **不是冲突**，但登记在此备查。
>
> **③ 新方法**（公开 snake_case ✓ / 私有 `_` + snake_case ✓）：
> `GameConfig.exact_kinds_for_round()` / `kind_cap_for_round()` / `is_sandbox_only()` / `summon_pool()` /
> `summon_weight_cap()` / `summon_candidates()`；`UnitFactory.rest_body_color()` / `_shadow_wisp()`；
> `Unit3D._repaint_team_accents()` / `_aim_shadow_form()` / `_beam_shooter()` / `_beam_active()` /
> `_tick_summon()` / `_summon_one()`；`Arena.skirmish_elapsed_ms()`；
> `Sandbox.set_weight_escalation()` / `weight_escalation()` / `_push_escalation()`；
> `SandboxHud._build_summon_panel()` / `_open_summon_panel()` / `_close_summon_panel()` / `_on_escalation_pressed()`
> —— `_on_<动作>` 与既有 `_on_clear_pressed()` 同式 ✓。
> ⚠️ `_random_composition()` 多了第三个参数 `kind_cap: int`（带默认值 ⇒ 既有调用点行为不变）。
>
> **④ 新节点名**（§3.1：PascalCase、后缀一律下划线 ✓）：
> `ShadowWisp_0..9` / `ShadowArm_left|right` / `TeamAccent_Eye_left|right` / `FxShadowForm` / `FormCore` / `FormTail_0..1`；
> `Plinth` / `Band_low` / `Band_high` / `CrystalPivot` / `CrystalTop` / `CrystalBottom`；
> `SummonScrim` / `SummonCenter` / `SummonPanel` / `SummonBox` / `SummonRow` / `EscalateOnButton` / `EscalateOffButton`。
> ⚠️ **一处改名**：`WaistSash` → **`TeamAccent_Sash`** ——
> **不是换约定**（PascalCase + 下划线后缀一字未变），是**语义变了**：本轮起影魔的躯干也是墨色，
> 队伍色不再挂在躯干上 ⇒ 束带与双眼成了**唯一的团队锚点**，必须有一个能被
> `Unit3D._repaint_team_accents()`（按名字前缀 `TeamAccent*` 找件）认出来的名字。
> 另两个新件 `TeamAccent_Eye_left/right`（影魔）与 `TeamAccent_Ring`（石柱光环）走同一个前缀。
>
> **⑤ 新成员**：`_fx_shadow_form` / `_summon_tick` / `_summon_count`（`Unit3D`）、
> `skirmish_start_ms` / `summon_escalation`（`Arena`）、`_weight_escalation`（`Sandbox`）、
> `_summon_scrim` / `_summon_panel` / `_summon_body`（`SandboxHud`）—— `_` + snake_case ✓；
> ⚠️ `summon_escalation` / `_weight_escalation` **是布尔量却读起来不像断言**（§3.3 那一行要求"读起来像断言"）——
> **本文件如实登记为"贴边项"**，**用户 2026-09-26 裁决：登记为例外、不改名**（先例：`Game.bet_all_in` 同样是"名词短语布尔量"）。
> ⚠️ **另一处贴边项（同一批裁决）**：`UNIT_ESCALATION_START_MS` 里的 `START` 易读成"什么时候开始"，
> 它其实是"**每一档持续多久**"—— **保留原名 + 在此注明**（与 `is_mid_dash()` / `UNIT_LANCE_SPEED_BONUS_PER_MS`
> 那两处"易误读但不改名"的先例同处理）。
>
> **⑥ 无新增档位、无拼音、无中英混拼、无裸整数代枚举**：本批不涉及 I-27（沙盒专属兵种的 999 **不进竞猜档位集合**）、
> I-33 新 ID 合规。既有成员名**只有 `WaistSash` 那一个改名**（见 ④）。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**。

> ✅ **2026-09-26 审计（"腐化师攻速 7 + 绕巨物不摇摆 + 石柱锚定 + 石柱首拍提前"这一批）**：
> **无新文件、无新类、无新信号、无新枚举、无新兵种、无新节点名**。
>
> **① 新常量 5 个**（全部 SCREAMING_SNAKE_CASE + 既有 `UNIT_*` 域 ✓，**住 `GameConfig`** ✓）：
> `UNIT_SIDESTEP_BIG_RADIUS` / `_CLEARANCE` / `_MIN_MS` / `_MAX_MS` / `_BIG_STROKES`。
> ⚠️ **这一批顺手修掉了一处旧违规**：那三个字面量（`0.5` / `260` / `420`）此前**散在 `unit3d.gd#_start_sidestep()` 里**，
> 按 **I-15**"可调参数全部住 `GameConfig`"搬进来 —— **不是新增约定，是把既有约定执行到位**。
>
> **② 新 PROFILE 字段 1 个**：`"anchored"`（小写数据字段 ✓，与 `stun_immune` / `sandbox_only` 同族）+
> 判据 `GameConfig.is_anchored()`（**`is_*` 族、读起来像断言** ✓）。
>
> **③ 新方法**：`Unit3D.is_anchored()` / `_capture_anchor()` / `_hold_anchor()`（`_` + snake_case + 按用途命名 ✓）。
>
> **④ 新成员 3 个**：`_anchor_pos` / `_anchor_set` / `_stuck_big_strokes`。
> ⚠️ **一处改名（用户当天裁决）：`_anchor_xz` → `_anchor_pos`** ——
> 它**确实违反了明条**（§3.3："坐标用 `pos` / `world_pos`"）⇒ 按既有先例（`_paint_last` → `_paint_last_pos`）
> **改代码、不动约定**（共 3 处：定义 + `_capture_anchor()` + `_hold_anchor()`）。
> ✅ 同批另一处贴边项（`summon_escalation`）经用户裁决**登记为例外、不改名**，见上一条审计的 ⑤。
>
> **⑤ 一处"名字没变、值变了"**：`PROFILES["corruptor"]["attack_speed"]` **8.0 → 7.0**
>（用户："心灵腐化师攻击力：40变成35"，实现口径由用户选定为"每跳仍 10、动攻速"）——
> 名字本身仍然准确（它就是"每秒出手次数"）⇒ **不改名**，只改值（并已在 `02_entities.md#3` 登记沿革）。
>
> **⑥ 无新档位、无拼音、无中英混拼、无裸整数代枚举**：本批不涉及 I-27 / I-33。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**（唯一动过名字的 `_anchor_pos` 是**向约定靠拢**，不是改约定）。

> ✅ **2026-09-26 审计（"火焰拳 / 火枪兵权重两改 + 肉鸽模式（骨架 + 经济记账）"这一批）**：
> **新文件 2 个、新类 2 个、新信号 1 个、新枚举 1 个**（少见的一次"新模块级"批次）。
> ⚠️ 本批查出 **1 处真冲突 + 3 处贴边项**，四处都按规矩**先停下问、再动手** —— 逐条见下。
>
> **① 新文件 / 新类（§3.2）**：`game/roguelike.gd` ↔ `class_name Roguelike`、
> `ui/roguelike_hud.gd` ↔ `class_name RoguelikeHud` —— 文件名 snake_case ↔ 类名 PascalCase 一一对应 ✓。
> `Roguelike` 是**模式名**（与既有 `Game` / `Sandbox` 并列，同 2026-09-25 对 `Sandbox` 的判定）、
> `RoguelikeHud` 走既有的 `<模式>Hud` 式（与 `SandboxHud` 同族）✓ —— **都不是新约定**。
>
> **② 新信号 1 个（§3.4）**：`Roguelike.phase_changed(phase: String)` —— 域 + 动词过去式 ✓。
> ⚠️ 它与 `Sandbox.phase_changed`、`Events.phase_changed` **三个同名**，按 §1.4「同一概念全局同名」
> 这**正是要的**（三个都是"相位变了"），区别只在作用域（前两个是节点自己的信号、**不上总线**）；
> `Roguelike.phase_name()` 与 `Game.phase_name()` / `Sandbox.phase_name()` 同义 ✓。
>
> **③ 新枚举 1 个（§3.5）**：`Roguelike.Phase { PREPARE, FIGHTING, ROUND_RESULT, GAME_OVER }` ——
> 枚举名 PascalCase 单数 ✓、成员 SCREAMING_SNAKE_CASE 且**不带类型前缀** ✓、配了名字转换函数 `phase_name()` ✓、
> 代码里**没有一处裸整数**（全是 `Phase.XXX`）✓。
> ⚠️ **一处真冲突（本批唯一一处）**：第一版把战斗那一档写成 **`BATTLE` / `"battle"`**，
> 而另外两个模式的同名成员逐字都是 **`FIGHTING` / `"fighting"`**（`Game.Phase.FIGHTING`、`Sandbox.Phase.FIGHTING`）
> ⇒ 违反 §1.4「同一概念全局同名」，也与 2026-09-25 那条审计里"`FIGHTING` 与 `Game.Phase.FIGHTING` **同名是有意的**"
> 的先例相抵。✅ **用户 2026-09-26 裁决："改代码、不动约定"** ⇒ 现在三处逐字一致
>（共 6 处：枚举成员 + `phase_name()` 返回值 + `_physics_process()` / `end_round()` 两处比较 + HUD 的两处引用）。
> ⚠️ **成员 `PREPARE` 与另外两个模式的 `BETTING` / `PLACING` 不同名，这不是冲突**：
> 三者是**三种不同的准备活动**（押注 / 布兵 / 领补给买兵）；而 `ROUND_RESULT` / `GAME_OVER` 与 `Game.Phase`
> 的同名成员**逐字一致** ✓。
>
> **④ 新常量（§2 常量档 / I-15）**：`GameConfig` 新增 **4 个玩法常量 + 1 个取值函数**，全部 SCREAMING_SNAKE_CASE ✓、
> **住 `GameConfig`** ✓，并**新开了一个"模式域"前缀 `ROGUELIKE_*`** ——
> `ROGUELIKE_ROUND_COUNT` / `_SUPPLY_START` / `_SUPPLY_STEP` / `_HP_MAX` + `roguelike_supply_income(round_index)`。
> ⚠️ **`ROGUELIKE_*` 登记进 §3.3 的"功能域前缀"那一族**（与 `RING_*` / `CAM_*` / `TEAM_WEIGHT_*` 同类：
> 一个子系统的成组常量、同域连续成段、段首注释）—— **但它与那些"纯表现域"有一点不同**：
> 它是**玩法数值**，所以照 I-15 **必须住 `GameConfig`**（只有表现域才允许住各自脚本）。
> ⚠️ `roguelike_supply_income()` 是**公开取值函数**（与既有 `exact_kinds_for_round()` / `attack_interval()`
> 同族：名词短语 + 返回一个数），是"每回合收入"的**唯一出处** ✓。
> ⚠️ 界面侧 3 个常量（`RoguelikeHud.REFRESH_MS` / `TOP_BAR_HEIGHT` / `ACTION_PANEL_HEIGHT`）是**表现参数** ⇒
> 住脚本、不进 `GameConfig`（同 `SandboxHud.REFRESH_MS` / `PALETTE_HEIGHT` 的既有做法；`_MS` 单位写进名字 ✓）。
>
> **⑤ 新成员 / 新方法（§3.3）**：公开成员 `phase` / `round_index` / `supply` / `income_total` / `hp` / `hp_max` /
> `log_entries` / `result` / `summary` / `arena` / `camera_rig`（全 snake_case ✓；`log_entries` 与 `Game.log_entries`
> **同名同义** §1.4 ✓）；私有成员 `_pause_from_ms`（**`_ms` 单位写进名字** ✓，与 `Game` / `Sandbox` 的同名字段逐字一致）
> 与 HUD 那一族 `_mode_label` / `_round_label` / `_supply_label` / `_hp_label` / `_foe_label` / `_gear` /
> `_action_panel` / `_start_button` / `_next_button` / `_overview_button` / `_hint` / `_overlay*` / `_pause` /
> `_refresh_ms` ✓。
> 公开方法 `bind()` / `begin()` / `start_battle()` / `end_round()` / `next_round()` / `restart_game()` /
> `phase_name()` / `enemy_weight()` / `pause_match()` / `resume_match()` / `_mcp_state()` ——
> ⚠️ **其中 5 个与 `Sandbox` 逐字同名**（`begin` / `start_battle` / `phase_name` / `pause_match` / `resume_match`）
> **刻意如此**（§1.4）✓；`end_round()` **刻意不与 `end_battle()` 同名**（沙盒结束的是"一场战斗"、
> 肉鸽结束的是"一个回合"，**是两件事**）。
> 私有方法 `_enter_prepare()` / `_settle_round()` / `_finish()` / `_enemy_team()` / `_change_state()` /
> `_build_top_bar()` / `_build_action_panel()` / `_build_overlay()` / `_refresh*()` / `_make_label()` /
> `_on_phase_changed()` / `_on_*_pressed()` ✓（`_on_<信号>` 与既有回调同式）。
> ⚠️ **两处改名（同一批用户裁决，都是"向既有名字靠拢"）**：
> ① `restart_run()` → **`restart_game()`**（与 `Game.restart_game()` **同名同义** §1.4；"run" 虽是肉鸽惯用词，
>   但本项目里"整局重置"只允许一个名字）；
> ② HUD 的开战按钮节点 `StartBattleButton` → **`StartButton`**（与 `SandboxHud.StartButton` 逐字同名；
>   ⚠️ **界面上的显示文字仍是「开始战斗」，一个字没改** —— 那是文案，不是标识符）。
> ⚠️ **删除 1 个死方法**：`Roguelike.phase_allows_pause()` —— 它**从来没有调用点**（暂停契约走界面侧的
> `RoguelikeHud.pause_allowed()`，那一侧恒为真）⇒ 按用户裁决删掉，**不留在那里当摆设**
>（⚠️ 与 §3.3 里两次"废弃但保留"的登记（`UNIT_LANCE_LOCK_MS` / `UNIT_LANCE_STOP_DISTANCE`）**性质不同**：
> 那两个是**常量**、保留是为了留沿革；这是一个从未被用过的**方法**）。
>
> **⑥ 新节点名（§3.1）**：`TopBar` / `TopBarRow` / `GearButton` / `ActionPanel` / `ActionRow` / `ActionBox` /
> `ButtonBox` / `StartButton` / `NextRoundButton` / `OverviewButton` / `RightPad` / `Overlay` / `OverlayCenter` /
> `OverlayPanel` / `OverlayBox` / `OverlayButton` / `PauseMenu` —— 全 PascalCase、全部**描述角色** ✓；
> 与 `SandboxHud` 的同名件（`TopBar` / `TopBarRow` / `GearButton` / `ActionBox` / `OverviewButton` / `Overlay` /
> `RightPad`）**逐字一致**（§1.4：同一件事一个名字）✓，**没有中文、没有拼音** ✓。
>
> **⑦ 数值改动（不涉及命名，登记备查）**：`PROFILES["flamefist"]["weight"]` **6 → 5**、
> `PROFILES["musket"]["weight"]` **4 → 5**、`PROFILES["musket"]["attack_speed"]` **0.20 → 0.22**
>（⚠️ 用户那句"**伤害变回 200**"对的是**现行值** ⇒ `damage` 一字未动）—— 名字全部仍然准确，只改值。
>
> **⑧ 无拼音 / 中英混拼、无裸整数代枚举**；本批动了 1 处真冲突（③）与 3 处贴边项（⑤，**全部经用户当天裁决**）。
> ⇒ **本文件无规则改动、无不变量改动**（I-15 落点：新玩法常量全在 `GameConfig`；I-33 无新实体 ID；
> I-31 / I-32 / I-34 逐条已核；I-27 只改例子）。
> ⚠️ **遗留待办照旧**：那 6 个 `_*_until`（缺 `_ms`）字段仍等用户裁决 —— 本批新增的 `_pause_from_ms`
> **带了 `_ms`**（且与另外两个模式同名同义），没有再添同类问题。
> ✅ **2026-09-27 结清**：6 个字段已按裁决改名（见文件末尾"第三轮修订批"审计）。

> ✅ **2026-09-26 审计（"肉鸽第二块：商店 / 解锁 / 初始四选一 / 2.0 m 格子 / 六档队形"这一批）**：
> **无新文件、无新类、无新信号、无新枚举成员**（改动落在既有 3 个脚本里）。
> ⚠️ 本批查出 **2 处"同一概念两个名字"**，经用户 2026-09-26 裁决**改代码统一**（见 ④）。
>
> **① `GameConfig`（§2 常量档 / I-15）**：新增 **7 个玩法常量**，全 SCREAMING_SNAKE_CASE ✓、**住 `GameConfig`** ✓、
> **沿用已登记的 `ROGUELIKE_*` 参数域**（**不新开域**）—— `ROGUELIKE_SQUADS_PER_ROUND` / `_UNLOCK_PER_ROUND` /
> `_UNLOCK_DIVISOR` / `_CELL_SIZE` / `_START_CHOICE_COUNT` / `_START_WEIGHTS` / `ROGUELIKE_SQUAD_TABLE`。
> 单位照 §3.3"写进名字"：`_SIZE`（米）、`_COUNT` / `_PER_ROUND` / `_DIVISOR`（无量纲）✓；
> ⚠️ `ROGUELIKE_START_WEIGHTS` **集合名用复数** ✓；`ROGUELIKE_SQUAD_TABLE` 是**数据表**（`_TABLE` 与既有
> `PROFILES` / `TEAM_META` 同一类角色）✓。
> 新增 **12 个取值函数**（公开、snake_case、**名词短语 + 返回一个数**，与 `exact_kinds_for_round()` /
> `attack_interval()` 同族）：`roguelike_grid_cols()` / `_rows()` / `roguelike_cell_center(col, row)` /
> `roguelike_squad_def()` / `_size()` / `_width()` / `_depth()` / `_cost()` / `roguelike_unlock_cost()` /
> `roguelike_buyable_types()` / `roguelike_starter_pool()` / `roguelike_make_starter_choices(rng)` ——
> ⚠️ 最后那个**把随机数当参数收进来**（不读全局源），与 `make_match(round, rng)` 是同一条纪律 ✓。
>
> **② `Roguelike`（玩法侧）**：新增公开状态 **7 个**（`starter_choices` / `starter_chosen` / `pool` / `squads` /
> `bought_this_round` / `unlocked_this_round` / `last_message`）—— 全 snake_case ✓；
> **布尔量 `starter_chosen` 读起来像断言** ✓（与既有 `_match_started` 同族）；**集合名用复数** ✓。
> 新增公开方法 **10 个**：`choose_starter(index)` / `squad_cost()` / `unlock_cost()` / `squad_weight_total()` /
> `can_buy()` / `can_unlock()` / `buy_squad()` / `unlock_type()` / `buy_block_reason()` / `unlock_block_reason()` ——
> ⚠️ **`can_*` 与 `*_block_reason()` 是刻意的一对**：前者给界面判"能不能点"（**布尔读作断言** ✓）、
> 后者给**同一句话的文案**（点不动时显示给玩家），两者**共用同一个判据函数** ⇒ 不会各写一份而漂移。
> 私有 **8 个**：`_pair_text()` / `_grant_squad()` / `_spawn_squad()` / `_free_anchor()` / `_is_free()` /
> `_occupy()` / `_build_grid()` / `_set_grid_visible()` ✓（`_` + snake_case + 按用途命名；`_is_free()` 读作断言 ✓）。
> 新增私有成员 `_rng` / `_occupied` / `_grid` ✓；表现常量 `GRID_COLOR` / `GRID_LIFT` ——
> ⚠️ **`GRID_*` 登记为"功能域前缀"的新实例**（§3.3 第二段那张清单加一笔）：一个子系统自己的纯表现常量组，
> 与 `FLAME_FX_*` / `PILLAR_*` / `CORRUPTOR_*` 同类；**不进 `GameConfig`**（I-15 只管可玩数值）✓。
> ⚠️ **一处刻意"不新增"**：`Phase` **仍是四个成员** —— "初始四选一"做成 `PREPARE` 里的一道门
> （`starter_chosen` 把关），**不加第五个相位** ⇒ §3.5 不涉及、`phase_name()` 的四个串一字未动。
>
> **③ `RoguelikeHud`（界面侧）**：新增节点名（§3.1：PascalCase + 描述角色 + 序号写在 `_` 之后 ✓）：
> `ShopBox` / `ChipGrid` / **`Chip_<兵种ID>`**（⚠️ **刻意与沙盒兵种栏同名同式** —— 同一件事一个名字，§1.4）/
> `StarterScrim` / `StarterCenter` / `StarterPanel` / `StarterBox` / **`StarterButton_<序号>`** ✓。
> 新增私有成员 `_shop_box` / `_shop_status` / `_shop_message` / `_starter_scrim` / `_starter_buttons` / `_squads_label` ✓；
> 新增私有方法 `_add_card()` / `_types_by_weight()` / `_on_card_pressed()` / `_build_starter()` /
> `_on_starter_pressed()` / `_refresh_starter()` / `_refresh_shop()` ✓（`_on_<动作>` 与既有回调同式；
> `_types_by_weight()` **与沙盒同名同义** ✓）。
>
> **④ 两处"同一概念两个名字"（§1.4）—— 用户 2026-09-26 裁决"改代码统一"**：
> ① `SHOP_COLUMNS` → **`CHIP_COLUMNS`**（= 6）：沙盒兵种栏里同一个概念（兵种卡一行几张）就叫 `CHIP_COLUMNS`，
>    而本文件的卡片节点本来就叫 `Chip_<兵种ID>` / `ChipGrid` ⇒ 旧名与自己的节点名**自相矛盾**；
> ② `_cards` → **`_chips`**：与 `SandboxHud._chips` 同名同义（"兵种 ID → 卡片按钮"的字典）。
> ⚠️ **同批第三处刻意不改**：`CARD_SEPARATION`（= 14）—— 沙盒那一侧是**内联的 14、没有对应常量**
> ⇒ 它**不构成**"同一概念两个名字"，保留原名（要严格统一成 `CHIP_SEPARATION` 属于另一件事）。
> ⇒ **本文件无规则改动、无不变量改动**：I-15 落点不变（7 个玩法常量全在 `GameConfig`、表现常量住脚本）；
> I-31 / I-32 / I-34 逐条已核；I-33 无新实体 ID；**I-27 只被读**（购买价 = 权重、解锁价 = ⌊全队总权重 ÷ 2⌋）。

> ✅ **2026-09-26 审计（"肉鸽第三块：指挥所 / 两个建筑标记 / 两套增益 / 队伍级状态"这一批）**：
> **无新文件、无新类、无新信号、无新枚举成员**（改动落在既有 8 个脚本里 —— 其中两个只是"池子过滤"）。
> ⚠️ 本批又查出 **3 处"与既有名字不同族"**，经用户 2026-09-26 裁决**改代码统一**（见 ④）。
>
> **① `GameConfig`（§2 常量档 / I-15）**：新增 **24 个玩法常量** —— 全 SCREAMING_SNAKE_CASE ✓、**住 `GameConfig`** ✓、
> **沿用已登记的 `ROGUELIKE_*` 域**（**不新开域**）：`ROGUELIKE_POST_TYPE` / `_PER_TEAM` / `_X` / `_Z` / `_DEBUFF_MULT` /
> `_DEBUFF_MS` / `_DEBUFF_CUT_MS`、`ROGUELIKE_BUFF_ATTACK` / `_DEFENSE` / `_UPGRADE` / `_STEP` / `_MAX_LEVEL` /
> `_HP_PER_LEVEL` / `_PRICES`、`ROGUELIKE_ROUND_BUFF_SUPPLY` / `_RANGE` / `_SPEED` / `_PRICE`、
> `ROGUELIKE_LOAN_GAIN` / `_DEBT`、`ROGUELIKE_ROUND_RANGE_BONUS` / `_SPEED_BONUS`、`ROGUELIKE_POST_SIDE_ROUND` / `_STEADY` ——
> ⚠️ 后两个与那 6 个 `*_BUFF_*` 的**值是状态串**（`"left"` / `"right"` / `"attack"` …），与 `MODE_QUIZ` /
> `phase_name()` 的全小写串**同一风格** ✓；单位后缀照 §3.3 写进名字（`_MS` / `_X` `_Z`（米）/ `_MULT`（倍率））✓。
> 新增判据 **2 个**：`is_roguelike_only()` / `is_no_attack()`（**`is_*` 读作断言** ✓，与 `is_sandbox_only()` /
> `is_anchored()` 同族）；对应 PROFILE 新字段 `roguelike_only` / `no_attack`（**小写数据字段** ✓，与 `sandbox_only` 同族）。
> ⚠️ **如实登记一处"同一串字面量写了两处"（不是命名冲突）**：`ROGUELIKE_BUFF_PRICES` 的**键**是字符串字面量
> （`"attack"` / `"defense"` / `"upgrade"`），而那三个 `ROGUELIKE_BUFF_*` 常量的**值**正是这三串 ——
> 键是"数据"、常量是"标识符"，两层各有用途；要收成一处可以让 const 字典直接引用 const（**可行，属另一件事**）。
>
> **② `Arena`（本项目第一处"全队状态"）**：新增 4 个队伍级字段 `team_damage_buff` / `team_speed_bonus` /
> `team_range_bonus` / `_team_debuff_until_ms` ✓（snake_case；`_ms` 单位后缀 ✓）。
> ⚠️ **"按队索引的定长数组"是 `Arena` 里首次出现的形状**（此前都是 `*_of_team(team)` 这类按参数取）——
> 与 `GameConfig.TEAM_META` 那种"按队索引的数组"同源，且它被 `damage_mult_for(team)` 一族包着 ⇒ **不是新约定**，
> 如实登记备查。
> 新增 6 个方法：`damage_mult_for(team)` / `speed_for(team, base_speed)` / `range_bonus_for(team)`
>（**`*_for()` 与既有 `exact_kinds_for_round()` 同族** ✓）、`debuff_active(team)`（**布尔，与既有 `match_active` /
> `_overview_active()` / `_lance_active()` 同族** ✓）、`apply_team_debuff(team, duration_ms)` / `clear_round_buffs()` ✓。
>
> **③ `Unit3D` / `Roguelike` / `RoguelikeHud` / `UnitFactory`**：`Unit3D.add_hp_bonus(amount)` ✓（动词 + 域）；
> `Roguelike` 侧 `_spawn_posts()` / `our_post(side)` / `post_sells_round_buffs(side)` / `select_post(side)` /
> `post_side_at(screen_pos)` / `post_debuff_ms()`（`_ms` ✓）/ `posts_alive(team)` / `buff_level(kind)` /
> `buff_price(kind)` / `buff_block_reason(kind)` / `buy_buff(kind)` / `buff_name(kind)` / `buff_level_text(kind)`
>（与既有 `roster_text()` 同族 ✓）/ `round_buff_price()` / `has_round_buff()` / `loan_debt()` /
> `round_buff_block_reason()` / `buy_round_buff()` ✓；
> **`_on_unit_died(unit)`** —— **`_on_<信号名>` 逐字对得上总线上的 `Events.unit_died`** ✓
>（⚠️ 本批**没有新增信号**，直接复用它 ⇒ §3.4 不涉及）。
> HUD 侧 `_build_buff_panel()` / `_on_buff_pressed()` / `_on_buff_close_pressed()` / `_refresh_buff_panel()` /
> `_is_round_kind(kind)`（**`_is_*` 读作断言** ✓）/ `_posts_note()` ✓；节点名 `BuffPanel` / `BuffBox` /
> `BuffRow_<kind>` / `BuffBuy_<kind>` / `BuffCloseButton` ✓（后半段取"增益种类串"，与既有 `Chip_<兵种ID>` 同式）。
> `UnitFactory` 新增 **11 个 `COMMANDPOST_*` 表现常量** ✓ —— 走 §3.3 的"**功能域前缀**"那条（与 `PILLAR_*` /
> `MOUNT_*` / `CORRUPTOR_*` 同类：一个兵种的整套几何），**不进 `GameConfig`**（I-15 只管可玩数值）。
>
> **④ 三处"与既有名字不同族" —— 用户 2026-09-26 裁决"改代码统一"**：
> ① `can_buff()` → **`can_buy_buff()`**、`can_round_buff()` → **`can_buy_round_buff()`** —— 这一族是 `can_<动词>`
>    （`can_buy()` / `can_unlock()` 各配自己的 `buy_*()` / `unlock_*()`），而 `buff` 是名词，旧名读起来像"能增益"。
>    ⚠️ **如实登记：这两个方法目前没有调用点**（界面用的是 `*_block_reason()` 那两句文案）—— 与上一批按裁决删掉的
>    `phase_allows_pause()` 同类，**要不要删由用户定**（本批只按裁决改名）。
> ② `GameConfig.balance_types()` → **`balance_pool()`** —— "一池子候选"这一族统一以 `_pool` 结尾
>    （`summon_pool()` / `roguelike_starter_pool()`），旧名不合族。
> ③ 指挥所四角立柱 `Post_wn` / `Post_ws` / `Post_en` / `Post_es` → **`Post_north_west` / `Post_north_east` /
>    `Post_south_west` / `Post_south_east`** —— §3.1 的既有例子一律**写全词**（`Bounds_north` /
>    `MountLeg_front_left`），第一版用了两字母缩写 ⇒ 改成"纵向 × 横向"两段全词
>    （方位口径：**−Z 北 / +Z 南 / −X 西 / +X 东**，与 I-35 的"0 队在西"同源）。
> ⚠️ **另有两处刻意保留 / 刻意不做，如实登记**：
> `CARD_SEPARATION`（沙盒侧是**内联的 14、没有对应常量** ⇒ 不构成"同概念两名"，沿用上一批的裁决保留）；
> **指挥所没有 `SILHOUETTE` 条目**（石柱与两台载具都"留一行占位"，而本支走 `NO_HUMANOID_TYPES` 自己建、
> 那条兜底值没有任何一处会读到它 ⇒ **刻意不补**，已在 `00_world.md#4.4` 写明）。
> ⇒ **本文件无规则改动、无不变量改动**：I-15 落点不变（24 个玩法常量全在 `GameConfig`；表现常量住脚本）；
> I-31 / I-32 / I-34 逐条已核；**I-33 新增一个实体 ID `commandpost`**（全小写 snake_case ✓）；**I-27 只被读**。

> ✅ **2026-09-26 第四 / 五块审计（"布阵交互 + 场地道具（陷阱 / 魔法盾）"这一批）**：
> **新常量**（全在 `GameConfig`，I-15）：`ROGUELIKE_DRAG_SLOP`（像素阈值）、
> `ROGUELIKE_PROP_TRAP` / `ROGUELIKE_PROP_SHIELD`、`ROGUELIKE_TRAP_PRICE` / `ROGUELIKE_SHIELD_PRICE`、
> `ROGUELIKE_TRAP_TRIGGER_RADIUS` / `_DELAY_MS` / `_BLAST_RADIUS` / `_DAMAGE` / `_SLOW_MULT` / `_SLOW_MS`、
> `ROGUELIKE_SHIELD_RADIUS` / `ROGUELIKE_SHIELD_HP`、`ROGUELIKE_PROP_MIN_SPACING`
> —— 沿用既有 `ROGUELIKE_*` **功能域前缀**（同域连续成段、段首一行注释），**时长一律带 `_MS`**、
> **距离沿用 `*_RADIUS` / `*_SPACING`**（与 `UNIT_STONE_AOE_RADIUS` 同式，本项目的米数历来不写 `_M`）
> ⇒ 合 §2 与 §3.3。**新函数**：`roguelike_prop_price()` / `_name()` / `_kinds()`（snake_case，与
> `roguelike_squad_*()` / `roguelike_unlock_cost()` 同族）⇒ 合 §3.3。
> **纯表现常量**（住脚本、不进 `GameConfig`，按 §3.3 的"表现参数"惯例）：`Roguelike.CELL_FREE` /
> `CELL_TAKEN` / `CELL_OK` / `CELL_BAD` / `CELL_INSET` / `CELL_LIFT` / `PREVIEW_LIFT` /
> `PROP_PREVIEW_OK` / `PROP_PREVIEW_BAD` / `PROP_PREVIEW_LIFT` —— 与既有的 `GRID_COLOR` / `GRID_LIFT`
> **同一族同一段**（`CELL_*` / `PROP_PREVIEW_*` 是这两个族名的自然延伸）⇒ §2 的 SCREAMING_SNAKE 合规则。
> **新成员**：`Roguelike` 侧 `props` / `selected_squad`（公开，读起来像名词）、`_next_prop_id` / `_prop_root` /
> `_placing` / `_place_pos` / `_place_on_field` / `_place_valid` / `_place_press_seen` / `_prop_preview` /
> `_press_squad`（私有，`_` + snake_case）、方法 `prop_block_reason()` / `can_place_prop()` / `prop_count()` /
> `is_placing()` / `begin_place()` / `cancel_place()` / `finish_place()` / `select_squad()` / `squad_movable()` /
> `squad_stats()` 与一批私有助手（`_footprint()` / `_unit_cells()` / `_squad_centers()` / `_cell_of()` /
> `_in_deploy_area()` / `_living_slots()` / `_fill_cells()` / `_occupy_squad()` / `_vacate_squad()` /
> `_make_cell_layer()` / `_append_cell_quad()` / `_push_cell_mesh()` / `_rebuild_cells()` / `_rebuild_preview()` /
> `_post_pos_of()` / `_reserve_post_cells()` / `_grant_post_bonuses()` / `_recover_army()` / `_revive_posts()` /
> `_recover_props()` / `_clear_props()` / `_spawn_prop()` / `_remove_prop()` / `_prop_index_by_id()` /
> `_sync_arrow_blockers()` / `_build_prop_node()` / `_prop_material()` / `_build_prop_preview()` /
> `_rebuild_prop_preview()` / `_prop_rows()` / `_tick_props()` / `_tick_placing()` / `_enemy_in_trap_range()` /
> `_explode_trap()` / `_poll_arrow_blocks()` / `_place_reason()` / `_begin_press()` / `_end_press()` /
> `_update_drag()` / `_rotate_dragging()` / `_reset_drag()` / `_move_squad()` / `_drag_candidate()` /
> `_squad_at()` / `_cell_under_cursor()` / `_ground_under_cursor()`）—— 全部 `_` + snake_case + 按用途命名，
> 合 §3.3。**`Unit3D`**：`_slow_until_ms` / `_slow_mult` + `apply_slow()` / `is_slowed()` / `slow_factor()`
> —— ⚠️ **`_ms` 后缀在这里不是装饰**：整型 `_*_ms` 成员会被 `shift_deadlines()` 的属性扫描自动纳入暂停补偿
> ⇒ 这是**由规则驱动的命名**（改名会静默破坏暂停语义）。布尔量 `is_slowed()` 读起来像断言 ⇒ 合 §3.3。
> **`Arena`**：`arrow_blockers` / `arrow_blocks`（集合用复数 ⇒ 合 §3.3；⚠️ 名字里带 `arrow` 是为了说明
> "只挡投射物、不是碰撞体"）。**`Arrow`**：`_magic_shield_crossing()` / `_segment_sphere_entry()` /
> `_block_at_shield()`—— 第一个把**对象**写进名字（是"与魔法盾求交"而不是泛泛的 `_check_block()`）。
> **新节点名**（全部 PascalCase，后缀一律下划线 ⇒ 合 §3.1）：`PlacementGrid` / `GridLines` / `GridCells` /
> `GridTaken` / `GridPreview`（格子四层）、`PropRoot` / `Prop_<kind>_<编号>` + 子件 `Disc` / `Ring` / `Shell`、
> `PropPreview`（道具与预览）、`SquadPanel` / `SquadBox` / `SquadCloseButton`（与 `BuffPanel` / `BuffBox` /
> `BuffCloseButton` **同族同式**）、`PropRow` 与卡 `Prop_<kind>`（与 `Chip_<兵种ID>` **同族同式**，
> 与场上的 `Prop_<kind>_<编号>` 靠**父节点**区分）。**无新信号**（§3.4 不涉及：挡弹登记走的是
> `Arena.arrow_blocks` 这个场地字段 + 既有的 `fx_request("arrow_blocked")`，**没有往 `Events` 上加东西**）。
> **一处已知的"未命名"**：底栏那行布阵提示是**未命名的 `Label`** —— 与既有的视角提示 `_hint`、
> `_shop_status`、`_shop_message`、`_buff_title` 等**同例**（本 HUD 里"纯文字标签"历来不命名，只给容器与
> 交互件命名）⇒ **沿用现状，不算本批新增的违规**；若将来要按 §3.1 的"动态节点也要命名"统一收口，
> 那是一次**跨三个 HUD 的单独一笔**（记进 `99_decisions.md` 的复查条件）。
> **一处改名**：`Roguelike` 的队信息字段 **`bought_round` → `move_round`** —— 用户 2026-09-26 的口径
>（"开局送的两队兵也能在第一回合进行移动"）让"是不是买的"不再是判据，旧名会**撒谎**（起手白送的队也记本回合）
> ⇒ 改成"**允许换位的回合**"；连带删掉 `_grant_squad()` 里那个只剩一种取值的 `from_purchase` 参数
>（"名字说 A、行为是 B"的参数正是 §1.4 要防的）。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（13 个玩法常量全进 `GameConfig`；格子 / 预览那 10 个
> 是纯表现，按惯例住脚本）、I-13（`_slow_until_ms` / `armed_ms` 都是绝对毫秒，且前者**靠命名**自动进
> 暂停补偿扫描）、I-31 / I-32 / I-33 / I-34 逐条已核；⚠️ **I-26 / I-27 只被读**（两件道具**不是兵种**、
> 不进 `PROFILES` / `TYPE_ORDER` ⇒ 权重的口径与例子一个字没动）。

> ✅ **2026-09-26 第六块审计（"布阵交互收尾（点格子选中 / 拖动幽灵 / Label 命名）+ 场地放大 + 紧急招募 /
> 移动信标 + 临时测试敌人 + 相机重扫"这一批）**：
> **新常量**（17 个，全在 `GameConfig` —— I-15）：场地 `ROGUELIKE_ARENA_HALF_X` / `ROGUELIKE_ARENA_HALF_Z`；
> 信标 `ROGUELIKE_PROP_BEACON` / `ROGUELIKE_BEACON_PRICE` / `_RADIUS` / `_SEGMENT_MAX` / `_POINT_COUNT`；
> 单回合增益 `ROGUELIKE_ROUND_BUFF_RECRUIT` / `ROGUELIKE_RECRUIT_BONUS_SQUADS`；
> 测试敌人 `ROGUELIKE_TEST_ENEMY_ENABLED` / `ROGUELIKE_TEST_ENEMY`；
> 机位 `CAM_ROGUELIKE_FOCUS_RATIO` / `_DISTANCE_RATIO` / `_YAW` / `_PITCH`；
> 跨模式共用表现色 `GHOST_OK_COLOR` / `GHOST_BAD_COLOR`
> —— 沿线既有前缀与"同域连续成段 + 段首一行注释"的写法 ⇒ 合 §2 / §3.3（其中 11 个是可玩数值、
> 4 个是机位、2 个是**跨模式共用**的表现色；`ROGUELIKE_SHIELD_HP` 只是**改值** 100 → 1000，不是新名字）。
> ⚠️ **三处要指名的判断，如实登记**：
> ① `CAM_ROGUELIKE_FOCUS` / `CAM_ROGUELIKE_DISTANCE` → **`..._FOCUS_RATIO` / `..._DISTANCE_RATIO`**：
>    场地一放大，写死的"绝对米数"就会把新场地切掉 ⇒ 改成**比例**（与既有 `CAM_ZOOM_STEP_RATIO` /
>    `UNIT_WINDUP_RATIO` 同族）。这不是"换个好听的名字"，是**旧名描述的东西已经不成立**（§1.4）。
> ② `ROGUELIKE_POST_X` / `ROGUELIKE_POST_Z` → **删除**，改成函数 `roguelike_post_x()` / `roguelike_post_z()`：
>    值现在是**从场地尺寸推出来的**（"己方半场的中心"），常量形式得把 25 / 9 再抄一遍、场地一变就撒谎 ⇒
>    与 `roguelike_squad_*()` / `roguelike_prop_price()` 那族 getter 同式 ✓。
> ③ `ROGUELIKE_TEST_ENEMY_ENABLED` 是**本仓第一个 `*_ENABLED` 开关常量**（此前没有这个后缀）——
>    读起来像断言、语义无歧义，暂按它落地；若日后要统一"开关"的写法，那是一次单独的收口。
> **改签名的函数**（`GameConfig`）：`roguelike_grid_cols(half_x := -1.0)` / `roguelike_grid_rows(half_z := -1.0)` /
> `roguelike_cell_center(col, row, half_x := -1.0, half_z := -1.0)`
> —— ⚠️ **`-1.0` 是"用本模式默认值"的哨兵、不是尺寸**：GDScript 的默认值必须是**常量表达式**，而调用方
> 手里那个半宽是**运行时字段**（`Arena.half_x`）⇒ 不能拿它当默认值（本项目已因此踩过一次"自我引用"的
> 解析错误，记在 `99_decisions.md`）。参数名与 `Arena` 字段**同名同义**（`half_x` / `half_z`）✓。
> **`Arena`**：新实例字段 `half_x` / `half_z` —— 公开、无下划线（与既有 `arrow_blockers` 同类），
> 且**用轴名而不是"宽 / 深"**：场地表把 X 叫"半宽"是历史叫法，而用户说的"宽"是 Z（I-36）⇒ 轴名不会撒谎。
> **新成员**（`Roguelike`）：`_ghost_root` / `_ghost_boxes` / `_ghost_type`、`_beacon_stock` / `_route_editing` /
> `_route_points` / `_routes_root`（私有，`_` + snake_case）；方法 `squad_limit_this_round()`（读起来是个值，
> `_this_round` 与既有"本回合"口径一致）、`beacon_stock()` / `buy_beacon()`（对齐 `buy_buff()` / `unlock_*()`
> 那族 `buy_<名词>`）、`_grid_cols()` / `_grid_rows()` / `_cell_center()`（**与 `GameConfig` 那三个同名同义**，
> 是本地的转发壳 ⇒ 呼应 §1.4"同一件事只允许一个名字"）、`_update_ghost()` / `_hide_ghost()` /
> `_ghost_material()` / `_body_box_of()`、`_start_route_edit()` / `_add_route_point()` / `_route_step_back()` /
> `_finish_route()` / `_cancel_route_edit()` / `_rebuild_routes()` / `_add_route_line()` /
> `_capture_beacon_routes()` / `_clear_unit_beacon_routes()` / `_beacon_route_rows()`、`_test_enemy_pos()` /
> `_test_enemy_alive()` / `_ensure_test_enemy()` ⇒ 合 §3.3。
> **`Unit3D`**：`_beacon_points` / `_beacon_offset` / `_beacon_s` / `_beacon_total` + `set_beacon_route()` /
> `clear_beacon_route()` / `has_beacon_route()`（`has_*` 读作断言 ✓）+ `_flat_gap()` / `_route_point_at()` /
> `_route_project()` / `_tick_beacon_route()`。
> ⚠️ **一处"短到读不出来"的名字，如实登记**：`_beacon_s`（以及 `_route_project()` 返回字典里的 `"s"`）是
> **弧长**。§1.4 要的是"看名字就知道是什么"，单个 `s` 只有物理系读者能猜到 ⇒ 建议改 `_beacon_arc` /
> `"arc"`；这属于**改代码**，本批只登记、不动。
> **`CameraRig`**：`on_roguelike_phase()`（与 `on_betting_phase()` 同族同式）、`_enter_deploy_state()`；
> **改名** `_overview_offset()` → **`_offset_for(yaw, pitch, distance)`** —— 旧名说"全景"，实际**两套姿态都在
> 用它**（部署机位 + 全景机位）⇒ 名字在撒谎（§1.4）；同时把"落地一套姿态"抽成
> `_apply_pose(focus, yaw, pitch, distance)`，四个参数就是一套机位的全部定义 ✓。
> **新节点名**（PascalCase、序号写在 `_` 之后 ⇒ 合 §3.1）：`DragGhost` / `Ghost_<序号>`（肉鸽的换位幽灵）、
> `PlaceGhost`（沙盒的摆兵幽灵，单节点复用 ⇒ 无序号）、`RouteRoot` / `RouteLine_<序号>`（信标路线）、
> `BeaconRow` / `BeaconLabel` / `BeaconBuyButton`（增益面板里那一行）。
> ⚠️ **`BeaconBuyButton` 与 `BuffBuy_<kind>` 看似两式，其实是两族**：前者是**单个交互件**（与
> `BuffCloseButton` / `SquadCloseButton` / `StartButton` 同族），后者是**每个 kind 一张的循环件**（ID 写在
> `_` 之后）⇒ 不构成"同概念两名"。
> **新 kind 串**：`"beacon"`（道具）/ `"recruit"`（单回合增益）—— 与既有 `"trap"` / `"shield"` / `"supply"`
> 同式（小写英文 ID）✓，与任何兵种 ID / 实体 ID 都不撞（I-33 不涉及：它既不是兵种也不是实体）。
> **HUD**：`_beacon_row` / `_beacon_label` / `_beacon_button` + `_on_beacon_pressed()`（`_on_<节点名>` 逐字对得上）
> ✓。**本批最大的一条规则收紧**：三个 HUD 的 `_make_label(text, size, color, node_name)` 第四参**改成必填**
> ⇒ 上一批登记的那笔"底栏布阵提示是未命名 `Label`"**已还清**（现在是 `DeployHintLabel`），而且**结构上不可能
> 再漏**（漏了就是解析错误，不是"悄悄放过"）。实测：竞猜 HUD 16 个 `Label` / 未命名 0，沙盒 13 / 0。
> ⚠️ **另外两笔遗留**（都要**改代码** ⇒ 本批只报告、等用户裁决）：
> ① `hud.gd#_overlay_button`（结算浮层那个"下一轮 / 查看结果"按钮）**至今没有名字** —— 它是**交互件**、
>    落在 §3.1"动态节点也要命名"的范围内，属于**本批之前**就存在的欠账；
> ② `Roguelike._route_preview`（`MeshInstance3D`）**声明了但全仓没有任何一处读写**（死成员）——
>    与上一批按裁决删掉的 `phase_allows_pause()` 同类。
> **无新信号**（§3.4 不涉及：幽灵 / 路线 / 测试敌人全走既有字段与 `fx_request`，没往 `Events` 上加东西）。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（本批 17 个常量全进 `GameConfig`，`GHOST_*` 两个是
> **跨模式共用**的表现色、按 §3.3 的例外住 `GameConfig`，同段已写明理由）、I-36（轴的叫法：**`half_z` 才是
> 用户说的"宽"** ⇒ 全程用轴名，不写"宽 / 深"）、I-31 / I-32 / I-33 / I-34 逐条已核；
> **I-13 只被读**（路线推进用既有的 `delta`，本批没有引入自己的时间源）；⚠️ **I-26 / I-27 只被读**
> （测试敌人是**既有兵种** `"sword"` 的一个实例，权重表与例子一个字没动）。

> ✅ **2026-09-27 第七块审计（"场地长 ×1.5 + 南北两条布阵带 + 5 s 准备期 + 信标改成买一次永久"这一批）**：
> **新常量**（全在 `GameConfig` —— I-15）：`ROGUELIKE_ZONE_DEPTH`（**12.0**，带子沿 Z 的深度）、
> `ROGUELIKE_ZONE_PREP_MS`（**5000**，准备期）—— 沿用 `ROGUELIKE_*` 功能域前缀；⚠️ **时长带 `_MS`**、
> **长度不带单位后缀**（与本项目既有口径一致）。`ROGUELIKE_ARENA_HALF_X` **只改值**（50 → 75，长 ×1.5），
> 名字不变；`ROGUELIKE_ARENA_HALF_Z`（43.75）**保持不变**，含义被写清楚成"**主场地**半深（不含带子）"。
> **新函数**（`GameConfig`，snake_case 且按"是谁的、沿哪条轴"命名，合 §3.3）：
> `roguelike_zone_span_x()`（带子沿 X 的长度）、`roguelike_arena_half_z()`（**竞技场**半深 = 主场地 + 带子）、
> `roguelike_zone_cells()`、`roguelike_zone_row_north_min/max()` / `_row_south_min/max()`、
> `roguelike_field_row_min/max()`（**主场地**的行区间）、`roguelike_zone_col_own_min/max()` /
> `_col_foe_min/max(cols)`、`roguelike_col_in_zone(col, cols)`。
> ⚠️ **两条命名判断如实登记**：
> ① `_own` / `_foe` 这一对是**"谁的地盘"**（`_own` = 己方底线往内那一段带子、**只有敌方能布阵**；
>    `_foe` = 敌方底线往内那一段、**我方**能布阵）—— 与既有 `ROGUELIKE_POST_SIDE_ROUND/_STEADY` 那对
>    "按语义命名、注释写清是谁"的做法同源；**不叫** `_left/_right`（那是按屏幕读的，I-36 明确不许）。
> ② `roguelike_field_row_*()` 与 `roguelike_zone_row_*()` 成对出现，读起来就是"主场地 / 带子各占哪些行"，
>    比 `_row_min/_row_max` 那种无主语的写法少一次歧义。
> **新成员**（`Roguelike`）：`_cells_zone_ours` / `_cells_zone_theirs` / `_cells_zone_dead`（三层填充，
> 与既有 `_cells` / `_cells_taken` / `_preview` 同族同式）；方法 `_zone_row_range(side)` /
> `_field_row_range()` / `_row_in_zone(row)` / `_zone_col_range(team)` / `_cell_in_forward_zone(col,row,team)` /
> `_anchored_in_forward_zone(anchor,fp,team)` / `_fits_in_home_half(anchor,fp,team)` /
> `_capture_zone_prep()` / `_mark_zone_entry(index)` / `_remove_beacons(reason)` / `_clamp_into_field(p)`
> —— 全部 `_` + snake_case + 按用途命名，合 §3.3（`_cell_in_*` / `_row_in_*` 读作断言 ✓）。
> **改名**：`Unit3D._beacon_s` → **`_beacon_arc`**（弧长），连带 `_route_project()` 返回字典的键
> `"s"` → **`"arc"`** —— 单字母 `s` 读不出"弧长"，正是 §1.4 要防的那类名字（上一批已登记为待办）。
> **删除**：`Roguelike._route_preview`（死成员，上一批登记的欠账）**已按裁决删掉** ✓；
> 中间两版试过的 `ROGUELIKE_ZONE_HALF_Z` / `roguelike_zone_len()` / `roguelike_zone_outer_x()` /
> `roguelike_zone_row_min/max()`（旧义）**随"位置订正"一起消失**，**从未进过任何文档** ⇒ 不必登记为"删除项"。
> **新节点名**（PascalCase ⇒ 合 §3.1）：`GridZoneOurs` / `GridZoneTheirs` / `GridZoneDead`（三层填充，
> 挂在既有 `PlacementGrid` 下、与 `GridCells` / `GridTaken` / `GridPreview` 同族）；
> **HUD 侧**：`ZoneLabel`（顶栏第六格读数，名字 = "它显示的是哪件事"）。
> ✅ **两笔旧欠账本批结清**：① `hud.gd#_overlay_button` 补名 **`OverlayButton`**（§3.1 的"动态节点也要命名"）；
> ② `Roguelike._route_preview` 删除。⇒ 上一批"如实登记的两笔遗留"**全部归零**。
> **无新信号**（§3.4 不涉及：准备期 / 布阵带 / 信标重放全是既有字段与既有 `Events`）。
> ⚠️ **一处"编号口径"的不一致，如实登记（不是命名冲突，但会让人对不上号）**：本批在**代码注释里**自称
> "**第六块之二**"（因为它是第六块那套场地/信标口径的续改），而 **bible 把它算作第七块**（`09_roguelike.md`
> 文件头 / §8.6 / `99_decisions.md`）—— 两边都没有"块号必须统一"的规则，但**下次同步前先对齐一下**
> 更省事（要不要把注释改成"第七块"是**改代码**，本批只登记、不动）。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（本批只有 2 个新常量 + 8 个派生函数，全在 `GameConfig`；
> 三层填充色 `CELL_ZONE_*` 是纯表现，按 §3.3 住脚本）、I-36（**"长" = X、"宽" = Z** 全程用轴名；
> `_own`/`_foe` 不按屏幕左右命名）、I-13（`ROGUELIKE_ZONE_PREP_MS` 是毫秒常量、`Unit3D._prep_until_ms`
> 用 `Time.get_ticks_msec()` 且**靠 `_ms` 后缀**自动进 `shift_deadlines()`）、I-31 / I-32 / I-33 / I-34 逐条已核；
> **I-26 / I-27 只被读**（本批没有新兵种、没有动权重）。

> ✅ **2026-09-27 第七块修订批审计（"布阵去边距 / 死区禁道具 / 块号口径统一 / 机位按参考图"）**：
> **本批没有引入任何新标识符** —— 新机器一行没加：去边距改的是 `Roguelike._fits_in_home_half()` 与
> `_free_anchor()` 里的**边界算式**（函数名不变）、死区那条改的是 `_place_reason()` 里**多一个分支**
> （它调用的是第七块已登记的 `GameConfig.roguelike_col_in_zone()` 与既有的 `Roguelike._row_in_zone()`）、
> 机位改的是 `CAM_ROGUELIKE_*` **五个常量的值**（名字一个没动）。⇒ §2 / §3.1 / §3.3 / §3.4 逐条复核：
> **无新增常量、无新增函数、无新增成员、无新增节点、无新增信号**。
> ⚠️ **一处"账目口径"的修订（不是命名规则改动，如实登记）**：用户 2026-09-27 要求"**块号口径统一**" ⇒
> 本次把代码注释里 **159 处 `第N块`** 逐条对照 bible 的七块定义重排（**只改注释、零行为改动**），
> 修掉的是**三处历史错位**：① 场地道具（陷阱 / 魔法盾）曾被标成"第四块"（bible 是**第五块**）；
> ② 场地放大 / 紧急招募 / 移动信标 / 测试敌人 / Label 收口曾被标成"第五块 / 第四块"（bible 是**第六块**）；
> ③ 本批与第七块那套（长 ×1.5 / 布阵带 / 准备期 / 信标永久 / 机位重扫）自称"第六块 / 第六块之二"
> （bible 是**第七块**）。`第四块 = 布阵交互`（点选 / 拖动 / 右键旋转 / 拖动幽灵 / 部署机位）**保持不变**。
> ⚠️ **顺带查出 bible 自己的一处同类错位（本次只报告、不改）**：`09_roguelike.md#6.4` 那节的标题写的是
> "第四块"，而它内部同时收着**第六块**才落地的两行（"点格子也能选中"与"拖动幽灵"）—— 代码现在按
> **§6.4（第四块）**标注这两项，与那一节的归属一致；要不要把那一节的标题/归属理清，**留待用户裁决**。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（本批没有新常量；机位那五个常量本来就在 `GameConfig`）、
> I-36（机位只用 yaw / pitch 与"半宽 / 半深"的比例描述，注释里的"西南 / 东北"是口语、参数不含方位名）、
> I-13 / I-31 / I-32 / I-33 / I-34 逐条已核；**I-26 / I-27 只被读**。

> ✅ **2026-09-27 第二轮修订批审计（"回合开始回原位 / 信标边打边走 / 肉鸽镜头加速 / 查看敌方 / 机位微调"）**：
> **7 个新标识符，全部贴着既有的成对写法造**（§1.4"同一件事只有一处出处"的延伸 —— 新名字要么与老名字成对、
> 要么沿用同族动词）：
> ① `Unit3D.reset_to(at, facing)` —— `<动词>_to` 家族（与 `heal_to_full()` 同族）；⚠️ **不叫** `teleport()` /
>    `warp()`：它做的**不只是位移**（还清瞬时状态），名字必须让人以为"只是摆个位置"是错的 ——
>    注释里逐条列了清哪些、不清哪些（§2.10）。
> ② `Roguelike.selected_foe` / `select_foe()` / `foe_stats()` / `_foe_at()` —— **逐字对齐**既有的
>    `selected_squad` / `select_squad()` / `squad_stats()` / `_squad_at()` 四件套（`foe` 与 `squad` 是这一对
>    的区分词：一个是"我方一队"、一个是"敌方一个兵"）。⚠️ `foe_stats()` 返回的字典**键与 `squad_stats()`
>    完全对齐**、只多一个 `"foe": true`（布尔标记，供界面分辨两栏文案）—— 这是"界面不另开一套排版"的前提。
> ③ `CameraRig._fly_mult` —— 私有 snake_case；与同族既有字段 `_zoom_allowed`（准不准推拉）、
>    `_fight_started`（打没开打）并列，语义是"这一次飞行的模式倍率"。
> ④ `GameConfig.CAM_FLY_SPEED_ROGUELIKE_MULT` —— **SCREAMING_SNAKE + 模式后缀**，紧跟既有那对
>    `CAM_FLY_SPEED` / `CAM_FLY_BOOST_MULT`（§2 的常量族）；⚠️ 没叫 `..._MULTIPLIER`（同族用的是 `MULT`）。
> **新节点名：0 个**（敌方只读面板复用 `SquadPanel`，没有新节点）。
> **新信号：0 个**（三条玩法改动全走既有字段 / 既有 `Events`；§3.4 不涉及）。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（`CAM_FLY_SPEED_ROGUELIKE_MULT` 进 `GameConfig`；
> 界面文案与 `foe_stats()` 的键都不是常量）、I-36（机位仍只用 yaw / pitch 与"半宽 / 半深"的比例描述）、
> I-13（新代码只读绝对毫秒，`reset_to()` 主动**清掉** `_prep_until_ms` ⇒ 不引入新的时间源）、
> I-31 / I-32 / I-33 / I-34 逐条已核；**I-26 / I-27 只被读**（本批没有新兵种、没动权重）。

### 3.4 信号名

- 格式：`<域>_<动词过去式>`，表达"**已经发生了什么**"，不表达"请去做某事"。
  好：`unit_died`、`round_started`、`game_over`。坏：`die_unit`、`start_round_now`。
- **时态必须能一眼看出来**。原形与过去式同形的动词要显式补齐：
  `hit` 写成 **`unit_was_hit`**（不要写 `unit_hit`）；同理可写 `unit_has_died` 之类。
- **只有"请求类"信号允许用原形动词**，且必须能一眼区分：
  `fx_request(event, world_pos)` —— 语义是"请放这个特效"，与"已经发生"的过去式信号分开。
  表现层专用信号统一走 `fx_request`，不要为每种特效各开一个信号。
- 带参数时参数名写进声明：`signal round_started(round_index: int, roster_a: Array, ...)`。
- 信号名与 `06_audio.md` 的音频**事件名故意不同**：信号是"发生了什么"，事件名是"放什么声音"，中间有一层映射表。

> **历史**：`unit_hit` / `unit_blocked` / `fx_requested` 曾违反本条（原形、形容词、过去式混用），
> 2026-09-17 统一改为 `unit_was_hit` / `unit_was_blocked` / `fx_request`。见 `99_decisions.md`。

### 3.5 枚举名

- 枚举类型 PascalCase、单数：`State`、`Mode`、`Phase`。
- 成员 SCREAMING_SNAKE_CASE，**不带类型前缀**：`State.ATTACK`（好） / `State.STATE_ATTACK`（坏）。
- 枚举一定配一个"名字转换函数"，用于 UI 与日志：`_phase_text()`、`["待机","移动","攻击","阵亡"][_state]`。
- 数值必须显式可读，不用裸整数散落：禁止 `if phase == 2`，只能 `if phase == Game.Phase.FIGHTING`。

> ✅ **2026-09-27 第三轮修订批审计（"敌方按队 / 落位居中 / 买兵掉落 / 格子两色 / 陷阱变绿 + 老账七条"）**：
> **新标识符 15 个 + 新节点名 1 个 + 新 meta 2 个，逐条对照如下**（§1.4「同一件事只有一处出处」与
> §2 / §3.1 / §3.3 的既有写法）：
> ① **`GameConfig` 五个新常量**：`UNIT_DROP_HEIGHT`（14.0 m）/ `UNIT_DROP_MS`（500，**时长带 `_MS`**）——
>    掉落的"高度 / 时长"两个可调量；`UNIT_PICK_MASK` / `UNIT_PICK_RANGE` —— **旧账去重的产物**（把
>    `Roguelike.POST_PICK_*` 与 `Sandbox.PICK_*` 两份同值常量合成一处，I-15）；`ROGUELIKE_TEST_ENEMY_COUNT`
>    —— 测试敌人的**编制数**（沿用 `ROGUELIKE_*` 功能域前缀，与 `_TEST_ENEMY` / `_TEST_ENEMY_ENABLED` 并排）。
> ② **`Unit3D` 一个方法 + 五个字段**：`play_drop_in(duration_ms, height)`（`<动词>_<副词>` 家族，与
>    `heal_to_full()` / `reset_to()` 同族）；`_drop_until_ms`（**`_ms` 后缀 + 整型 ⇒ 自动进
>    `shift_deadlines()` 的暂停补偿扫描**，I-13）/ `_drop_total_ms` / `_drop_height` / `_drop_y`；
>    `_ground_lock`（贴地件挂点的缓存，私有 snake_case）。⚠️ 两条命名判断如实登记：`_drop_y` 里的 `y` 是
>    轴名（§1.4 允许的"物理量名"），不是拼音；`_ground_lock` 与节点名 `GroundLock` **同名不同型**
>    （一个是 `Node3D` 引用、一个是节点名）—— 与 `_visual` / `Visual` 那对同一写法。
> ③ **`Roguelike` 五个新方法 + 两个新字段**：`_spawn_foe_squad()` / `_compact_foe_squads()` /
>    `_foe_living()` / `_play_drop_in()` / `_anchor_order()` / `_append_taken_cell()`（全是 `_` + snake_case
>    + 按用途命名；`_foe_*` 与既有的 `_squad_*` 成对）；`foe_squads`（**敌方队账本**，与 `squads` 成对）、
>    `selected_foe_squad`（与 `selected_squad` / `selected_post` 三者同族）。
> ④ **两个新 meta 键**：`foe_squad_index` / `foe_slot` —— **逐字对齐**既有的 `squad_index` / `squad_slot`
>    （§3.3 的"同概念同写法"）。
> ⑤ **一个新节点名**：`GroundLock`（PascalCase，§3.1）—— 模型里"贴地件"的挂点，目前只有影魔建它。
> ⑥ **改名 / 删除（老账结清）**：6 个 `_*_until` → **`_*_until_ms`**（`_skill_cd_until_ms` / `_kb_until_ms` /
>    `_bash_cd_until_ms` / `_master_dash_cd_until_ms` / `_backstep_cd_until_ms` / `_iai_cd_until_ms`；
>    ⚠️ **连带的行为修正**：它们从此进 `shift_deadlines()` 的属性扫描 ⇒ 暂停期间不再白吃冷却）；
>    删 `can_buy_buff()` / `can_buy_round_buff()`（无调用点）、删 `UNIT_MASTER_STEP_SPEED`（死常量）、
>    删 `POST_PICK_MASK` / `POST_PICK_RANGE`（并入 `GameConfig.UNIT_PICK_*`）。
> ⑦ **无新信号**：三条玩法改动全走既有字段 / 既有 `Events`，§3.4 不涉及。
> ⇒ **本文件无冲突、无规则改动、无不变量改动**：I-15（五个新常量全进 `GameConfig`；格子颜色按 §3.3 的先例
> 住脚本：`CELL_TAKEN_MOVABLE` / `TRAP_RING_DONE`）、I-13（`_drop_until_ms` 带 `_ms` 后缀；6 个改名让既有
> 冷却也纳入暂停补偿）、I-31（`GroundLock` PascalCase）、I-36（敌方队伍沿**横排 = 世界 Z** 铺开）、
> I-32 / I-33 / I-34 逐条已核；**I-26 / I-27 只被读**（本批没有新兵种、没动权重）。

> ✅ **2026-09-27 第四轮审计（"单位等级 / 经验 / 精英招募 / 撤销"）**：
> **新文件 0、新类 0、新信号 0**（⚠️ 击杀归因**故意没有**动 `Events.unit_died` —— 那会改 §3.4 的信号签名，
> 所以改用单位上的 `_last_hitter` / `killer()`）。
> ① **`GameConfig` 四个新常量**：`ROGUELIKE_LEVEL_MAX`（9）/ `ROGUELIKE_ROUND_BUFF_ELITE`（`"elite"`，
> 与 `ROGUELIKE_ROUND_BUFF_SUPPLY|RANGE|SPEED|RECRUIT` **同一族写法**）/ `ROGUELIKE_ELITE_PRICE`（10，
> 与 `ROGUELIKE_RECRUIT_BONUS_SQUADS` 那种"某条增益自己的量"同式）/ `ROGUELIKE_TEST_ENEMY_LEVEL`（1，
> 与既有的 `ROGUELIKE_TEST_ENEMY_ENABLED` / `ROGUELIKE_TEST_ENEMY` **前缀成组**）。
> ② **`Unit3D` 三个新方法 + 四个新字段**：`level_mult()`（派生值，动词短语）/ `set_level()` / `_apply_hp_total()`
> / `killer()`（**列表里的既有先例**：`is_*` / `has_*` 断言语义、普通名词指"就绪状态"、`owner_team()` 那种查询
> —— `killer()` 属最后一种：**查询"谁打死了我"**）；字段 `level`（**语义直白，与既有 `team` / `type_id` 同类**）、
> `_hp_base` / `_hp_bonus_flat`（私有 + snake_case；⚠️ `_flat` 是**口径标记**（加法池），不是拼音）、
> `_last_hitter`（私有；⚠️ 用 `_hitter` 而不是 `_killer`：它记的是"最后打到我的人"，**未必是击杀者**）。
> ③ **`Roguelike` 七个新方法 + 六个新字段 + 一个新常量**：`squad_level()` / `squad_xp()` / `squad_xp_cost()` /
> `upgrade_price()` / `upgrade_block_reason()`（**与既有的 `buff_block_reason()` / `round_buff_block_reason()` /
> `buy_block_reason()` 逐字同族**——"不能做的原因"这套已经有三处先例）/ `upgrade_squad()`（**与 `buy_squad()` /
> `buy_buff()` / `buy_round_buff()` 同族**：动作 + 目标）；字段 `_undo_stack`（私有 + 名词复数，栈）/
> `_undo_note` / `_undo_note_ms`（**`_ms` 后缀 + 整型 ⇒ 自动进 `shift_deadlines()`，I-13**）；
> 常量 `UNDO_NOTE_MS` / `UNDO_STACK_MAX`（**表现参数 ⇒ 按 §3.3 的先例住脚本**，与 `TRAP_RING_DONE`
> 那类同一处）。⚠️ 内部方法 `_push_undo()` / `_snapshot_state()` / `_restore_state()`（动词 +
> `_undo_` / `_snapshot_` / `_restore_` 前缀）。⚠️ 队字典只加**两个键**：`"level"` / `"xp"`（与既有的
> `"type_id"` / `"weight"` / `"units"` / `"anchor_col"` … 同一层，**没有新 meta**）。
> ④ **`RoguelikeHud` 三个新节点名**：`SquadUpgradeButton` / `UndoButton`（**PascalCase，§3.1**；
> 与既有的 `SquadCloseButton` / `OverviewButton` / `StartButton` 同族）+ `UndoToastLabel`（⚠️ `Toast` 是
> **表现层通名**（转瞬即逝的一行提示），本项目首次出现 —— 它是**新词但不是新约定**，按"控件类型作后缀"的
> 既有写法（`*Label` / `*Button` / `*Row`）命名；新容器 `SquadButtons`（HBox，§3.1 ✓）。
> ⑤ **一个新 meta 键：无**（等级住在队上、击杀归因住在字段上 ⇒ **没有再往单位上挂 meta**）。
> ⑥ **删除 / 改名：无**（本批纯新增）。
> ⇒ **无冲突、不改任何规则与不变量**：I-13（`_undo_note_ms` / 升级用的 `xp` 是**计数不是时刻**，无需后缀；
> 时长常量 `UNDO_NOTE_MS` 带 `_MS`）、I-15（四个新常量全在 `GameConfig`；两个表现常量按先例住脚本）、
> I-31（三个新节点 PascalCase）、I-34（**无新信号，且刻意不改既有信号的签名**）、I-36（未触碰）、
> I-26 / I-27 / I-28 **只被读**（等级**不进配平评分**：`score()` 仍按表值算 ⇒ I-28 的口径一个字没动）。

> ✅ **2026-09-27 第五~八轮审计（"经验基数改正 + 未解锁单位独立成一栏 + 悬停不放大 + 界面四轮重排"）**：
> **新文件 0、新类 0、新信号 0、新 meta 0**；改动全在 `ui/roguelike_hud.gd`（+ 一处 `game/roguelike.gd`
> 的算式修正）。逐条对照：
> ① **`GameConfig`：无新常量**（⚠️ 经验基数改正是**换用既有函数** `roguelike_squad_cost()`，不是新常量）。
> ② **`Roguelike`：无新方法 / 字段**（`squad_xp_cost()` 的实现改了，签名与语义没变）。
> ③ **`RoguelikeHud` 新方法 17 个**（全是 `_` + snake_case + 按用途命名）：构建类 `_build_start_bar()` /
>    `_build_left_column()` / `_build_prop_panel()` / `_build_shop_panel()` / `_build_bottom_bar()` /
>    `_build_prop_cards()` / `_build_unlock_panel()`；交互类 `_on_unlock_pressed()` / `_on_unlock_close_pressed()` /
>    `_on_unlock_card_pressed()` / `_on_unlock_chip_hover()` / `_on_prop_hover()` / `_on_hint_fold_pressed()` /
>    `_on_chip_hover()`（既有）；工具类 `_hover()` / `_apply_chip_text()` / `_locked_types()` / `_bar_height()` /
>    `_apply_bottom_anchors()` / `_types_by_weight()`（既有）。
>    ⚠️ 三处**判断**如实登记：`_hover(button, hovered, as_option)` 的 `as_option` 是**布尔开关**（两种悬停口径
>    只有字色不同 ⇒ 用一个函数 + 一个开关，比两个函数少一份重复）；`_bar_height()` 是**查询式**（"底栏现在多高"
>    —— 与 `level_mult()` / `killer()` 同族）；`_apply_bottom_anchors()` 的 `_apply_` 前缀与既有
>    `_apply_steady_buff()` / `_apply_defense_bonus()` 同族（"把某个口径落到一组对象上"）。
> ④ **`RoguelikeHud` 新字段 15 个**：`_start_bar` / `_beacon_panel` / `_prop_panel` / `_shop_panel` /
>    `_prop_panels` / `_prop_base_text` / `_prop_hover_text` / `_unlock_button` / `_unlock_panel` / `_unlock_hint` /
>    `_unlock_grid` / `_unlock_cards` / `_unlock_close` / `_unlock_open` / `_hint_box` / `_hint_col` / `_hint_fold` /
>    `_hints_open` / `_chip_base_text` / `_chip_hover_text`。⚠️ **两处"成对命名"的既有先例**：
>    `*_base_text` / `*_hover_text` 是"常态 / 悬停两套文案"（本项目首次，但对称且自解释）；
>    `_hints_open` 是**状态布尔**（与 `_unlock_open` 同族）。
> ⑤ **`RoguelikeHud` 新常量 8 个**：`BOTTOM_INSET` / `START_BUTTON_SIZE` / `START_BUTTON_FONT` /
>    `SIDE_BUTTON_SIZE` / `SHOP_PANEL_WIDTH` / `HINT_BLOCK_WIDTH` / `COLLAPSED_BAR_HEIGHT` / `SIDE_PANEL_TOP`
>    （+ 既有 `ACTION_PANEL_HEIGHT` / `CHIP_COLUMNS` / `CARD_SEPARATION` / `BUFF_PANEL_TOP` 改值）。
>    ⚠️ `START_BUTTON_FONT` **带单位后缀的"字号"**属首次：既有字号常量叫 `FONT` / `FONT_MID`（不带单位），
>    但这里要强调"它与 `UiStyle.FONT` 不是同一个数" ⇒ 保留此名并在此登记（**不构成约定冲突**：它是本文件
>    私有的表现常量，且名字里说明了对象与量）。
> ⑥ **新节点名 22 个（全 PascalCase，§3.1）**：`StartBar` / `StartBox` / `BeaconPanel` / `BeaconBox` /
>    `BeaconHintLabel` / `PropPanel` / `PropBox` / `PropHintLabel` / `ShopPanel` / `UnlockPanel` / `UnlockBox` /
>    `UnlockGrid` / `UnlockHintLabel` / `UnlockButton` / `UnlockCloseButton` / `UnlockChip_<兵种ID>` /
>    `HintBox` / `HintCol` / `HintFoldButton` / `SquadButtons`（+ 既有的 `Prop_<kind>` / `Chip_<兵种ID>` 沿用）。
>    ⚠️ `UnlockChip_<兵种ID>` 是与 `Chip_<兵种ID>` **刻意成对**的写法（同一个"兵种卡"概念的两个去处）。
> ⑦ **删除 / 合并**：节点 `PropRow`（卡片不再挤在一行）、`ShopHintLabel`（那句话随卡片一起走了）、
>    `RightColumn`（第四轮加、第五轮删：商店搬去右下后右列不再需要）、容器 `ButtonBox`（按钮搬去顶部）；
>    常量 `HINT_PAD_LEFT` / `HINT_PAD_RIGHT`（第六轮加、第七轮删）、`UNLOCK_PANEL_DROP`（同）；
>    方法 `_build_prop_row()` → `_build_prop_cards()`（改名 + 语义变准：它建的是"卡"、挂到两处面板里）。
> ⑧ **无新信号、无新 meta**（用户那条"悬停不放大"是**表现**，不碰信号）。
> ⇒ **无冲突、不改任何规则与不变量**：I-13（没新增时刻字段）、I-15（**没有**新增玩法常量；
>    经验基数改正是换用既有函数）、I-31（22 个新节点全 PascalCase）、I-34（无新信号）、
>    I-32 / I-33 / I-36 逐条已核；I-26 / I-27 / I-28 **只被读**（玩法数值一个没动，只有"经验的基数"按用户口径改正）。

## 4. 命名与不变量的关系

| 不变量 | 内容 | 本文件对应章节 |
| --- | --- | --- |
| I-31 | 节点命名 PascalCase | §2、§3.1 |
| I-32 | 脚本文件命名 snake_case | §2、§3.2 |
| I-33 | 实体 ID 全小写 snake_case | §2、§3.3 |
| I-34 | 信号名 `动词_过去式` | §3.4 |

> ✅ **2026-09-27 第九~十轮审计（"权重 2 队形 + 卡片定宽 + 腐化师攻速 + 新 boss 湮灭之瞳"）**：
> **新文件 0、新类 0、新信号 0、新 meta 0**；改动落在 4 个文件（`core/config.gd` / `units/unit3d.gd` /
> `units/unit_factory.gd` / `ui/roguelike_hud.gd`，外加 `game/roguelike.gd` 一处**注释**改正）。
> ① **新实体 ID 1 个**：**`doom_eye`**（全小写 + 下划线，§3.3 ✓；`PROFILES` / `TYPE_ORDER` / `UNIT_BODY_BOX` /
>    `SILHOUETTE` / `NO_HUMANOID_TYPES` 五处登记 ✓）。⚠️ **它的中文名与英文名由用户在三个候选里选定**
>    （「湮灭之瞳」/「Doom Eye」）—— 名字**不是**我起的（凡用户没给名字的新实体，本轮一律先问再落地）。
> ② **`GameConfig` 新常量 6 个 + 新函数 4 个**：`UNIT_DOOM_HITS_PER_STAGE`（4，**档位的分母**）、
>    `UNIT_DOOM_STAGE_DAMAGE`（三档伤害的数组）、`UNIT_DOOM_BEAM_RADIUS`（三档光束半径的数组）——
>    全是 `UNIT_*` 家族、名字里带对象（`DOOM`）与量（`HITS` / `DAMAGE` / `RADIUS`）✓；
>    `is_sustained_beam()` / `doom_stage()` / `doom_damage()` / `doom_beam_radius()` ——
>    `is_*` 断言 + 三个纯查询（与 `is_boss()` / `is_sandbox_only()` / `hit_damage()` 同族）✓。
> ③ **`Unit3D` 新方法 3 个 + 新字段 2 个 + 新常量 2 个**：`is_sustained_beam()`（**实例上的同名查询**，
>    ⚠️ **与 `GameConfig` 那个同名不同源**：实例版读 `type_id`、配置版读 `type_id` 实参 —— 这是本项目
>    "同概念同名"的既有写法（`is_corruptor()` 也有两处：`Unit3D` 上的实例版 + PROFILE 的 `"corrupt"` 旗标），
>    已在两处注释里互相点名 ✓）、`is_doom_eye()` / `focus_stage()`；字段 `_focus_hits`（私有 + 语义直白，
>    与 `_jump_count` / `_first_bite_double` 这类"计数"同族）、`_beam_stage_drawn`（**记录"上一次画过的档位"**
>    —— `_drawn` 后缀是本项目首次，含义是"已经落到画面上的那一个值"，用于避免每帧重建图元网格）；
>    常量 `DOOM_BEAM_COLOR` / `DOOM_BEAM_EMISSION`（与 `LASER_BEAM_*` / `SUMMON_BEAM_*` **逐字成组** ✓）。
> ④ **`UnitFactory` 新常量 13 个**：`DOOM_RING_R` / `_RING_THICK` / `_CORE_Y` / `_CORE_R` / `_GLOW_R` /
>    `_SHELL_R` / `_SHELL_H` / `_SHELL_W` / `_SHELL_Y` / `_LENS_LIFT` / `_METAL` / `_METAL_RIM` /
>    `_GLOW_COLOR` / `_GLOW_ENERGY` —— 与既有的 `PILLAR_*`（石柱）、`VEHICLE_*` 三段**同一套命名法**：
>    `<兵种族>_<部位或量>` ✓。**新节点名 7 个**（全 PascalCase）：`Shell_<序号>` / `ShellRim_<序号>` /
>    `Body`（**沿用既有保留名** ⇒ 受击闪白 / 换边自动生效 ✓）/ `CoreGlow` / `TeamAccent_Ring`
>    （**沿用既有的"队伍色锚点"前缀** ⇒ `_repaint_team_accents()` 自动认它 ✓）/ `LensPivot` / `Lens`。
> ⑤ **`RoguelikeHud` 新常量 2 个**：`CARD_MIN_WIDTH`（120，**卡片固定最小宽**）/ `CARD_MIN_HEIGHT`（34）
>    —— 名字直白；`CHIP_COLUMNS` 4 → **3**（同一常量改值，不是新名字）。
> ⑥ **删除 / 改名**：无（`_build_right_column()` 早在第五轮就删了，本轮没有新的删除）。
> ⑦ **无新信号**（「能量汇集」是纯伤害改写 + 一个计数，不广播任何东西 ⇒ I-34 不涉及）。
> ⇒ **无冲突、不改任何规则与不变量**：I-15（**6 个新常量全在 `GameConfig`**；`DOOM_*` 那 13 个是**模型尺寸**
>    —— 与既有 `PILLAR_*` / `VEHICLE_*` 同例住工厂，属既有先例，不是新违规）、
>    I-26（七项数值全是用户给的，没有替用户定过任何一项；⚠️ **权重由 5 改成 25 是用户当场改口**，已在
>    `02_entities.md#3` 那段原文里逐字留痕）、I-27（**只加例子**：25 是既有档位，没有开新档位）、
>    I-13（`_focus_hits` 是**计数**不是时刻，不需要 `_ms` 后缀；本轮没有新增任何时刻字段）、
>    I-31（7 个新节点名全 PascalCase）、I-32 / I-33 / I-34 / I-36 逐条已核。
>    ⚠️ **一处规则理解被订正**（不是命名问题）：`02_entities.md#4` 的"boss 上限"原写成"每队最多一个 boss"，
>    实际代码是"**同一 boss 兵种**每队最多一个" ⇒ 本轮已改正并留痕（`99_decisions.md` 有完整说明）。

> ✅ **2026-09-27 第十一轮审计（"湮灭之瞳 25 m / 攻速 3 + 大师闪避修 bug + 沙盒兵种栏单排滚动 + 模型改成'一只眼'"）**：
> **新文件 0、新类 0、新信号 0、新 meta 0**；改动落在 4 个文件（`core/config.gd` / `units/unit3d.gd` /
> `units/unit_factory.gd` / `ui/sandbox_hud.gd`，外加 `ui/roguelike_hud.gd` 的**两句注释**）。
> ① **无新实体 / 无新 ID**（改的是既有 `doom_eye` 的数值与模型）。⚠️ **也没有新常量进 `GameConfig`**：
>    射程 / 攻速是**改值**，判定体那条是**按实测重标**（`UNIT_BODY_BOX["doom_eye"]` 3.19 × 3.05 × 3.34 / lift 2.63）✓。
> ② **`UnitFactory` 删 8 个 / 增 6 个 `DOOM_*` 常量**：
>    删 `DOOM_GLOW_R`、`DOOM_SHELL_R/H/W/Y`、`DOOM_LENS_LIFT`、`DOOM_LID_W/THICK/TILT`（"能量核心"那版遗留）；
>    增 `DOOM_GAZE_PITCH`、`DOOM_GLINT_R/OUT`、`DOOM_PUPIL_R/BACK`、`DOOM_IRIS_R/BACK`、
>    `DOOM_LID_R_IN/OUT`（第十一轮沿用"`<兵种族>_<部位或量>`"这一族 ✓）。⚠️ 其中 `DOOM_*_BACK` 是**首次**用
>    "相对瞳孔往后多少"这种**相对量**命名（不是绝对坐标）—— 理由写在常量注释里（三件沿视线排开、绝对坐标会随
>    仰角一起错），**不构成约定冲突**（名字仍说清了对象与量，且都在 `DOOM_*` 段内）。
> ③ **节点名**：删 `CoreGlow` / `LensPivot` / `Lens` / `Shell_<序号>` / `ShellRim_<序号>`；
>    增 `Eyelid_Upper` / `Eyelid_Lower` / `GazePivot` / `Glint` / `Pupil` / `Iris`（全 PascalCase ✓，§3.1）。
>    ⚠️ **`Body` 仍是眼球、`TeamAccent_Ring` 仍是贴地光环**（两个保留名沿用 ⇒ 闪白 / 换边继续自动生效 ✓）。
> ④ **`SandboxHud` 删 2 个 / 增 4 个常量 + 增 4 个方法 + 增 5 个字段 + 5 个新节点名**：
>    删 `CHIP_COLUMNS`、`ChipGrid`（网格改单排）；增 `CHIP_ROW_SEPARATION` / `CHIP_ROW_GROW_PAD` /
>    `PALETTE_ARROW_W` / `CHIP_VISIBLE_TARGET`；增 `_on_palette_gui_input` / `_scroll_palette` /
>    `_refresh_palette_arrows` / `_apply_palette_arrow`（`_palette_*` 私有族 + 动词开头 ✓）；
>    字段 `_palette_scroll` / `_palette_left_button` / `_palette_right_button` / `_palette_order`；
>    节点 `ChipStrip` / `ChipScroll` / `ChipScrollLeft` / `ChipScrollRight` / `ChipRow`（全 PascalCase ✓）。
>    ⚠️ **`ChipGrid` 这个名字在沙盒侧消失了、肉鸽侧仍在**（那边确实还是网格）⇒ **不是"同名不同物"**，是两侧
>    真的形态不同 ✓（肉鸽 `CHIP_COLUMNS` 现在**只有一个出处**，那条旧注释已同步）。
> ⑤ **无新信号**（滚轮走的是 Godot 既有的 `gui_input` 信号 ⇒ I-34 不涉及）。
> ⇒ **无冲突、不改任何不变量**：I-15（本轮**没有**新增玩法常量；模型尺寸照旧住工厂 = 既有先例）、
>    I-26（射程 / 攻速是**用户逐条给的**："湮灭之瞳射程变为25m""攻速变为3"）、I-27（**未动**：权重还是 25）、
>    I-13（本轮没有新增任何时刻字段）、I-31、I-32 / I-33 / I-34 / I-36 逐条已核。
>    ⚠️ **一条"同一概念两个名字"现在成立了**（本轮才出现）：卡片间距在肉鸽叫 `CARD_SEPARATION`（= 8）、
>    在沙盒叫 `CHIP_ROW_SEPARATION`（= 14）。**值本来就不同**（窄侧栏 vs 通栏底栏）⇒ 已按流程
>    **登记待办、没有偷偷改名**（见 `ui/roguelike_hud.gd` 那句注释与 `99_decisions.md` 的复查条件）。
>    ⚠️ **两条"踩过的坑"写进了代码注释**（不是命名问题，但下次会撞）：① `accept_event()` 是 `Control` 的方法，
>    而 `SandboxHud extends CanvasLayer` ⇒ 写了**编译不过**（该用 `get_viewport().set_input_as_handled()`）；
>    ② `SphereMesh.is_hemisphere` 自带**平底盖**、`BoxMesh` 是直板 ⇒ 两者都不能当"贴球面的眼睑"（会穿模 / 锯齿）。

> ✅ **2026-09-27 第十二轮审计（"肉鸽兵种科技 12 条 + 湮灭之瞳不再触发大师后撤"）**：
> **新文件 0、新类 0、新信号 0、新 meta 0**；改动落在 **7 个文件**（`core/config.gd` / `units/unit3d.gd` /
> `units/unit_factory.gd` / `ui/roguelike_hud.gd` / `game/roguelike.gd` / `arena/arena.gd` / `arena/arrow.gd`）。
> ① **`GameConfig` 新增**：`ROGUELIKE_TECH_TABLE`（**12 条科技的唯一数据源**）、`ROGUELIKE_TECH_TYPES`
>    （有科技的兵种名单）、`ROGUELIKE_BURN_TICK_MS`（点燃节拍 1000，**带 `_MS`** ✓ 与既有 `UNIT_*_MS` 同式）、
>    4 个纯查询 `roguelike_tech_list()` / `roguelike_tech_def()` / `roguelike_tech_ready()` /
>    `roguelike_tech_desc()` —— 全 `roguelike_*` 前缀，与既有 `roguelike_squad_*()` 同族 ✓。
> ② **`Unit3D` 新增（科技效果层）**：字段 `_tech` / `_shield_hp` / `_shield_bar` / `_shield_fill_px`、
>    `_burn_until_ms` / `_burn_next_tick_ms` / `_burn_ratio` / `_burn_from`（**`_ms` 后缀 ⇒ 自动进
>    `MatchPause.shift_deadlines()`** ✓ I-13）、`_saint` / `_saint_ring`、`_spartan_thrown`；
>    方法 `set_techs()` / `has_tech()` / `tech_def()` / `tech_armor()` / `tech_hp_mult()` /
>    `tech_interval_mult()` / `tech_move_speed_delta()` / `tech_range_bonus()` / `tech_damage_mult()` /
>    `tech_kb_bonus()` / `tech_shield_max()` / `shield_hp()` / `_refresh_shield_bar()` / `_build_shield_bar()`、
>    `ignite()` / `is_burning()` / `_tick_burn()` / `_ignite_from_attacker()`、`set_saint()` / `is_saint()` /
>    `saint_spin_radius()` / `_update_saint_spin()`、`spartan_can_throw()` / `_spartan_throwing()`、
>    `can_block_projectile()`；常量 `SHIELD_BAR_COLOR` / `SHIELD_BAR_LIFT`（与既有 `CORRUPT_BAR_*` 成组 ✓）；
>    `apply_hit()` 新增第 5 个**默认参数** `skip_armor`（默认 false ⇒ 既有调用点一个都不用改 ✓）；
>    节点名 `ShieldBar`（与 `CorruptBar` / 血条同式 ✓）。
> ③ **`UnitFactory` 新增**：`SLASH_RING_R` / `SLASH_RING_TUBE` / `SLASH_RING_Y`（模型尺寸住工厂 = 既有先例 ✓）；
>    节点 `SlashRing` —— ⚠️ **刻意不叫 `Fx*`**：那个前缀是"每帧按技能开合"的整段特效根，挂上去会被
>    `_update_flame_fx()` 第一帧藏掉（`00_world.md#4.4` 那条通用坑 ✓）。
> ④ **`Roguelike` 新增**：字段 `techs`、方法 `tech_active_for()` / `has_tech()` / `buy_tech()` /
>    `apply_techs_to_type()` / `apply_all_techs()`（动词开头、`tech` 前缀统一 ✓）；快照多一个 `techs` 字段 ✓。
> ⑤ **`Arrow` 新增**：`max_flight` / `_born_pos`（投矛射程闸门；`max_flight = 0` ⇒ 不限 ⇒ 其余投射物逐位不变 ✓）；
>    `kind` 多一个取值 **`"spear"`**（既有取值 `arrow` / `shortbow_arrow` / `longbow_arrow` / `stone` /
>    `bolt` / `musket_bullet` ⇒ 同族小写蛇形 ✓）。
> ⑥ **`Arena` 新增**：`spawn_spear_throw()`（与 `spawn_arrow()` 同族动词 ✓）。
> ⑦ **`RoguelikeHud` 新增**：`TechButton`、`TechPanel` / `TechBox` / `TechHintLabel` / `TechTypeGrid` /
>    `TechTypeChip_<兵种ID>` / `TechGrid` / `Tech_<兵种ID>_<科技ID>` / `TechEffectLabel` / `TechCloseButton`
>    （全 PascalCase ✓，卡名沿用 `*Chip_<ID>` 的既有写法 ✓）；字段与方法 `_tech_*` / `_on_tech_*` / `_refresh_tech_*`
>    （与 `_unlock_*` 一族逐字对应 ✓）。
> ⑧ **删除 / 改名**：无。⚠️ **`pending` 标记全部摘掉**（5 条已实现）—— 字段本身**保留**
>    （`roguelike_tech_ready()` 与界面那两种灰态仍读它），为的是"下次再分批加科技"时不用动界面 ✓。
> ⑨ **无新信号**（点燃 / 剑圣 / 投矛都不广播；投矛的发射音走既有 `fx_request` ⇒ I-34 不涉及 ✓）。
> ⇒ **无冲突、不改任何不变量**：I-15（12 条科技的**全部参数**住 `GameConfig.ROGUELIKE_TECH_TABLE` ✓）、
>    I-26（**没有为了"免疫击退"去改任何兵种的重量** —— 那是面板第七项数值；剑圣的免疫单列一条特权 ✓）、
>    I-13（新增的时刻字段都带 `_ms` ✓）、I-31 / I-32 / I-33 / I-34 / I-36 逐条已核。
>    ⚠️ 本轮**没有新的"同一概念两个名字"**（`SLASH_RING_R` 与 `saint_spin_radius()` 是"常数副本 + 现算函数"，
>    注释里已互相点名并说明"只用于视觉" ✓）。

> ✅ **2026-10-01 审计（"剑圣外形 / 选中面板跳过剑圣 / 格挡箭不带进下一回合 / This is SPARTA！月牙盾"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。科技 id 仍是 `spartan`，只改了**显示名**
> 「this is Spartan！」→「This is SPARTA！」（显示文字，不是标识符，§1.5 不约束它）。
> ① **新节点**（§3.1 PascalCase，描述角色）：`SaintKit` / `SaintCirclet` / `SaintPlume` / `SaintCape` /
>    `SaintBlade` / `SaintEdge` / `SaintGuard` / `CrescentShield`。没有把序号或方位塞进名字中部。
> ② **新常量**（工厂里的表现色，与 `COMMANDPOST_*` / `SLASH_RING_*` 同一先例，不进 `GameConfig`）：
>    `SAINT_GOLD` / `SAINT_CLOTH` / `SAINT_BLADE`。`SAINT_` 是本批的表现域前缀，**没有改 §3.3 的规则**。
> ③ **新私有方法**：`_add_saint_look()` / `_apply_saint_look()` / `_apply_spartan_look()` /
>    `_crescent_shield_mesh()`（`_` + snake_case ✓）。局部变量 `saint_only` ✓。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"面板显示科技后的数值 / 同兵种科技涨价 / 起手两队 / 补给 +10 / 矛兵两条数值 / 骑士·狂战士·玉面手雷王各 4 条科技"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。科技 id 全是 snake_case（`armor_up` / `mend` / `bulwark` / `holy_strike` / `rage` / `ember` / `destroyer` / `acid_bomb` / `damage_amp` / `replicate`），与既有 `defense_mode` 同一套。
> ① **新常量**（全在 `GameConfig`，I-15）：`ROGUELIKE_STARTER_SQUADS` / `ROGUELIKE_TECH_COST_STEP` / `ROGUELIKE_REPLICATE_CAP` / `ROGUELIKE_REPLICATE_SPREAD`。`ROGUELIKE_` 前缀沿用，没有新开前缀规则。
> ② **新节点**（§3.1 PascalCase + 序号）：`AcidPool_<序号>`。池容量 `ACID_POOL_SIZE` 写在 `Arena` 上，与 `DUST_POOL_SIZE` 同一先例（表现池，不是玩法可调数）。
> ③ **新方法 / 参数**（`_` + snake_case，或已有入口加默认参数）：`tech_price()` / `tech_blast_mult()` / `tech_jump_mult()` / `is_ember()` / `place_acid()` / `tick_acid()` / `clear_acid()`；`apply_hit` 增加 `bulwark_piece`、`from_acid`。单位 meta `replicated` 是既有 meta 写法，不是新信号。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"沙盒滚轮让开兵种栏 / 直线弹打中湮灭之瞳 / 投矛与科技特效"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。
> ① **新组名** `palette_wheel`（全小写 snake_case，§2）。初稿写成 `PaletteWheel`，与组名规则冲突，已改回，**没有改这条规则**。
> ② **新常量**：`ROGUELIKE_SPARTAN_ROOT_MS` 在 `GameConfig`（I-15）。`IAI_SLASH_FX_MS` 与既有 `BURROW_FX_BURST_MS` 一样是表现时长，住在单位脚本上。`HOLY_BURST_POOL` / `HOLY_BURST_MS` / `BULWARK_LINK_POOL` 与 `ACID_POOL_SIZE` 一样住在 `Arena`。
> ③ **新节点**（§3.1 PascalCase，序号在 `_` 之后）：`FireEdge` / `FireTongue_<序号>` / `BulwarkRing` / `IaiFx` / `IaiCharge` / `IaiDash` / `IaiSlash` / `EmberAura` / `SpearShaft` / `SpearHead` / `FireTip` / `HolyBurst_<序号>` / `BulwarkLink_<序号>`。
> ④ **新方法与字段**（snake_case，布尔读起来像断言）：`shot_aim_point()` / `set_bulwark_mark()` / `show_holy_burst()` / `show_bulwark_links()` / `shield_bar_texture()`；`_move_lock_until_ms` / `_iai_slash_until_ms` 带 `_ms`（I-13）；`ignited` 与既有 `deflected` 同一类。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"投矛每回合刷新 / 投矛与盾、弹反 / 遣返 / 扇子兵四条科技"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。
> ① **科技 id**（snake_case）：`gale` / `intercept` / `scavenger`。`armor_up` 与剑盾兵那条共用，没有新开一条命名。
> ② **新常量**（全在 `GameConfig`，I-15）：`ROGUELIKE_RECALL_PRICE` / `FAN_INTERCEPT_FULL_MS` / `FAN_INTERCEPT_STOP_MS`。`INTERCEPT_FLASH_POOL` / `INTERCEPT_FLASH_MS` 住在 `Arena`，与 `HOLY_BURST_POOL` 同一先例。
> ③ **新节点**（§3.1 PascalCase，序号在 `_` 之后）：`InterceptFlash_<序号>` / `RecallCard` / `RecallRow` / `RecallLabel` / `RecallBuyButton`。
> ④ **新方法与字段**（snake_case）：`buy_recall()` / `begin_recall()` / `recall_ready()` / `has_recall()` / `fan_intercept_hits()` / `clear_ground_near()` / `show_intercept_flash()`；`_recall_owned` / `_recall_used` / `supply_spent` / `intercept_left` / `intercept_reserved` / `_intercept_arrow`。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"沙盒勾选科技放兵 / 查看模式 / 底栏收掉空档"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。科技 id 没有新开，仍读 `ROGUELIKE_TECH_TABLE`。
> ① **新节点**（§3.1 PascalCase）：`ViewModeButton` / `PlaceTechRow` / `PlaceTech_<兵种>_<科技>` / `PlaceTechEffectLabel` / `InspectPanel` / `InspectTitleLabel` / `InspectBodyLabel` / `InspectNoteLabel` / `InspectCloseButton` / `ActionRow`。
> ② **新方法与字段**（snake_case）：`toggle_place_tech()` / `place_tech_on()` / `view_mode()` / `set_view_mode()` / `viewed_stats()` / `tech_ids()` / `_fit_palette()`；`_picked_techs` / `_view_mode` / `_viewed`。
> ③ `PlaceTechRow` 加入既有组 `palette_wheel`，没有新组名。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"按钮悬停不再改大小 / 拦截在进射程的瞬间结算 / 长弓手·投石车·弩车科技"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **科技 id**（snake_case，与既有 `range_up` / `elite_hunter` 同一套）：`explosive_arrow` / `scatter_shot` / `rapid_throw` / `siege_mode` / `fireball` / `silence_shot` / `rapid_shot` / `assault`。`range_up` 与 `elite_hunter` 是旧 id 复用到新兵种，没有另起名字。
> ② **新节点**（§3.1 PascalCase，序号在 `_` 之后）：`FirePool_<序号>`，与既有 `AcidPool_<序号>` 同一写法。池容量 `FIRE_POOL_SIZE` 写在 `Arena` 上，与 `ACID_POOL_SIZE` 同一先例（表现池，不是玩法可调数）。
> ③ **新方法与字段**（snake_case；带时长的带 `_ms`，I-13）：`intercept_ready()` / `intercept_segment_t()` / `spend_intercept_swing()` / `try_instant_intercept()` / `flight_velocity()` / `apply_silence()` / `is_silenced()` / `attack_min_reach()` / `tech_kb_mult()` / `place_fire()` / `tick_fire()`；`_silence_until_ms` / `_silence_move_mult` / `_silence_shield` / `_intercept_frame_ms` / `silence_ms` / `silence_move_mult` / `explosive_radius` / `explosive_ratio` / `fire_damage` / `stone_scale`。布尔量 `fireball` / `splash_knockback` 读起来像状态。`apply_stun` 与既有 `ignores_shield` 一样，是弹上的「这一发要不要做某件事」，没有新开一条布尔命名规则。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-01 审计（"自我复制带等级 / 狂战士三条改价 / 火枪兵·火焰拳·影魔科技"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **科技 id**（snake_case）：`energy_leech` / `energy_burst` / `flame_barrier` / `shadow_guard` / `revenge`。`mend` / `range_up` / `elite_hunter` / `rapid_shot` / `silence_shot` / `replicate` / `armor_up` 是旧 id 复用，没有另起名字。
> ② **新方法与字段**（snake_case；带时长的带 `_ms`，I-13）：`receive_kill()` / `_try_revenge()` / `_cast_revenge()` / `_energy_burst()` / `_tick_flame_barrier()` / `_receive_barrier()` / `_barrier_damage_mult()`；`_peak_max_hp` / `_barrier_until_ms` / `_barrier_taken_mult`。布尔量 `_barrier_cast` / `_revenge_half_used` / `_revenge_zero_used` 读起来像断言。`hp` 是既有缩写。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。能量爆发复用既有的落点扬尘，没有新节点。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"轻骑兵·心灵腐化师科技 / 湮灭之瞳第四档"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **科技 id**（snake_case）：`wild_horse` / `horse_speed` / `dismount` / `control_heal` / `multi_beam` / `shelter`。`armor_up` 与 `range_up` 是旧 id 复用，没有另起名字。
> ② **新节点**（§3.1 PascalCase，序号在 `_` 之后）：`LaserBeam_1` … `LaserBeam_4`（主光束仍是既有的 `LaserBeam`）、`WardRing`。
> ③ **新方法与字段**（snake_case；带时长的带 `_ms`，I-13）：`keeps_tech()` / `dismount_loadout()` / `refresh_ward()` / `has_ward()` / `ward_radius()` / `take_ward_damage()` / `sync_unit_wards()` / `drain_ward_blocks()`；`_corrupt_from` / `_beam_target_1` … `_beam_target_4` / `_beam_charge_ms_1` … `_beam_charge_ms_4` / `_ward_hp` / `_ward_ring`。布尔量 `has_ward()` / `keeps_tech()` / `_beam_target_ok()` / `_beam_slot_ready()` 读起来像断言。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。第四档只加了伤害和光束半径两处数组，没有新标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"暗影守护减伤 / 复制体不再复制 / 复仇 150% / 快速射击 −50% / 影魔复制攒权重 / 壁垒不分沉默 / 火焰屏障与复仇特效 / 庇护随等级 / 地面效果压暗 / 手雷王生命 80"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **没有新科技 id**。`shadow_guard` / `revenge` / `rapid_shot` / `replicate` / `shelter` / `flame_barrier` 都是旧 id。新字段名 `damage_reduction`（快速射击的百分比减伤）、常量 `ROGUELIKE_SHADOW_REPLICATE_WEIGHT` / `ROGUELIKE_SHADOW_REPLICATE_CAP`。`damage_taken_mult` 与火焰屏障那条相同，没有另起名字。
> ② **新节点**（§3.1 PascalCase，序号在 `_` 之后）：`FlameBarrierPulse_<序号>`、`RevengeBurst_<序号>`、`FlameBarrierShell`。
> ③ **新方法与字段**（snake_case）：`replicate_spawn_count()` / `_living_replicates()` / `_shadow_guard_taken_mult()` / `_update_barrier_shell()` / `show_flame_barrier()` / `tick_flame_barrier()` / `show_revenge_burst()` / `tick_revenge()`；`_replicate_bank` / `_barrier_shell`。meta `replicate_owner` 存的是实例编号。既有 meta `replicated` 复用。表现时长 `FLAME_BARRIER_MS` / `REVENGE_BURST_MS` 写在 `Arena` 上，与既有 `HOLY_BURST_MS` 同一先例。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"沙虫 / 武士大师 / 湮灭之瞳科技，以及百分数池与倍率的三处归位"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **科技 id**（snake_case）：`sandstorm` / `burrow_mend` / `broodmother` / `ambush` / `deflect_up` / `afterimage` / `sidestep` / `riposte` / `thunder_breath` / `leech` / `energy_scatter` / `summon_grenadier`。`armor_up` / `range_up` / `shelter` 是旧 id 复用。玩法数字写在科技行上，没有新开 `GameConfig` 常量（I-15）。
> ② **新节点**（§3.1 PascalCase）：`SandstormDisc`。
> ③ **新方法与字段**（snake_case；带时长的带 `_ms`，I-13）：`move_pct()` / `deflect_flight_range()` / `try_sidestep()` / `_tick_burrow_mend()` / `_tick_summon_grenadiers()` / `_tick_afterimage_life()` / `_begin_sandstorm()` / `_spawn_brood()` / `_spawn_afterimage()` / `_storm_move_pct()` / `_storm_taken_mult()` / `_try_riposte()` / `_update_storm_disc()` / `_extra_beam_id()`；`_hp_scale` / `_damage_scale` / `_guard_until_ms` / `_storm_until_ms` / `_storm_at` / `_storm_disc` / `_sidestep_until_ms` / `_riposte_until_ms` / `_summon_next_ms` / `_summon_until_ms` / `_burrow_mend_next_ms`。箭上的 `_deflect_range` 是这一发记下的米数。meta `brood` / `afterimage` / `summoned`。`hp` 是既有缩写。`from_melee` 是既有参数上多出来的布尔量，默认 false。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⑤ **两处易误读，不改名**：科技 id `sidestep` 是大师的侧闪，和绕路用的 `_start_sidestep()` / `UNIT_SIDESTEP_*` 不是同一个东西。`_summon_until_ms` 是影分身的消失时刻，手雷王的召唤节拍是 `_summon_next_ms`。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"索敌格子 / 冲刺直接挪位置 / 马合成两张网格 / 手雷分帧 / 血条预先画好 / 远处藏零件和血条"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **新常量**（`GameConfig`，I-15）：`UNIT_QUERY_CELL` / `UNIT_QUERY_SLACK_M` / `UNIT_LOD_HIDE_M` 放在轻骑兵冲刺矩形那一段之后。`UNIT_GRENADE_BLASTS_PER_FRAME` 与 `UNIT_GRENADE_BLAST_RADIUS` / `UNIT_GRENADE_BLAST_DAMAGE` 同一段。原先曾写成 `GRENADE_BLASTS_PER_FRAME`，并曾把 `UNIT_LOD_HIDE_M` 放在出生高度旁边；同步前已改回这条。
> ② **新节点**（§3.1 PascalCase）：`MountBody` / `MountDetail`。马不再是 22 个 `Mount*` 零件节点。
> ③ **新方法与字段**（snake_case）：`rebuild_unit_grid()` / `units_near()` / `nearest_enemy()` / `queue_blast()` / `tick_blasts()` / `_cell_key()` / `_cell_units()` / `_enemy_candidate()` / `_update_lod()`；`_unit_cells` / `_blast_queue` / `_empty_cell` / `_mount_detail`。布尔量 `_lod_far` 读起来像断言。`prior_target` 是上一帧的目标。`LOD` 与既有 `FX` 一样，是这一处用的缩写，定义处的注释写了藏的是马的零件和血条。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-28 审计（"索敌分桶 + 节流开关"，性能优化 A 组）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **新常量**（`GameConfig`，I-15）：`UNIT_RELOCK_MS`（**0 = 关**），紧跟 `UNIT_QUERY_SLACK_M`。
> ② **新方法与字段**（snake_case）：`arena._max_query_ring()` / `arena._cell_min_gap_m()` / `arena._purge_nearest_due()`；字段 `arena._nearest_due_ms`（节流表，默认一直是空的）。
> ③ **无新节点、无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **无冲突、不改任何命名规则**。⚠️ **不变量**：默认（`UNIT_RELOCK_MS = 0`）一条不动；打开节流会放宽 `04_physics.md#3` 那条"随时 `target` == 最近敌人"，已在那里登记。

> ✅ **2026-11-01 审计（"倍速按钮 / 补给与生命加图案 / 玩法说明"）**：
> **新文件 2**：`scripts/core/match_speed.gd`（`class_name MatchSpeed`，`extends RefCounted`，与 `MatchPause` 同一种"静态方法仓库"）；`scripts/ui/tutorial_screen.gd`（`class_name TutorialScreen extends CanvasLayer`，与 `CodexScreen` / `SettingsScreen` 同族）。⚠️ **新信号 0、新类枚举 0、新组名 0**。
> ① **新常量**：`MatchSpeed.NORMAL` / `FAST`（倍速两档，纯表现参数 ⇒ 留脚本，按 §3.3 的"功能域前缀"自成一域）；`TutorialScreen.TUTORIAL_LAYER` / `CHAPTERS` / `SCRIM_COLOR` / `PANEL_MARGIN_X` / `PANEL_MARGIN_Y` / `CHAPTER_COL_W`（层号与排版，与图鉴的 `CODEX_LAYER` 同一类，不进 `GameConfig`）；`UiStyle.SPEED_BUTTON_PX` / `SPEED_CHEVRONS` / `SPEED_SHORTCUT_KEY`（= `KEY_F`，倍速快捷键；⚠️ `1`=技能 / `X`=肩位 / `Q`=交还 / WASD=镜头 / `Space`=cam_up / `Tab`=自由视角 / `Ctrl+Z`=撤销 都已占用，`F` 是空的）/ `STAT_ICON_PX` / `SUPPLY_FILL` / `SUPPLY_LINE` / `HP_FILL`（与 `GEAR_*` 同段）。
> ② **新方法**：`MatchSpeed.speed()` / `set_speed()` / `toggle()` / `label()` / `tick()`；`MatchPause.pull_deadlines()`（与既有 `shift_deadlines()` 成对：一推一拉）；`Unit3D.pull_deadlines()` / `_shift_ms()`；`Arena.pull_deadlines()`；`UiStyle.supply_texture()` / `heart_texture()` / `make_icon_label()` / `speed_texture()` / `decorate_speed()` / `make_speed_button()` / `_on_speed_pressed()`（私有静态回调，与 `TutorialScreen._on_chapter_pressed()` 同构；三套 HUD 共用同一份接线 ⇒ 具名函数比内联 lambda 好在调用栈里看得出"是谁切的倍速"）；`TutorialScreen.open()` / `close()` / `_show_chapter()` / `_on_chapter_pressed()`。
> ③ **新字段**：`MatchSpeed._speed` / `_carry_ms`（静态，与 `MatchPause` 无状态那条不冲突 —— 倍速**是**全局状态）；`Unit3D._ms_props`（静态缓存的属性名单）；三套 HUD 各多一个 `_speed_button`（与 `_gear` 同款）。
> ④ **新节点**（§3.1 PascalCase）：`SpeedButton`；肉鸽顶栏 `SupplyRow` / `HpRow`（**里面的 Label 沿用旧名 `SupplyLabel` / `HpLabel`**，文档与自检按名字找它们）；教程面板 `Root` / `Scrim` / `Panel` / `Box` / `Columns` / `ChapterColumn` / `Chapter_%d`（序号在 `_` 后）/ `BodyScroll` / `Body` / `CameraHint` / `Footer` / `BackButton`。
> ⑤ **字体 / 资源**：补给箱与心、倍速尖角全是 `Image` 逐像素画的（与 `gear_texture()` 同一手法）⇒ **零外部资源**这条没破。
> ⇒ **无冲突、不改任何命名规则**。⚠️ **不变量**：倍速**不动** I-13（计时仍是绝对毫秒、仍不随帧率漂移，前移量带余数结转），详见 `05_ui_hud.md#16`。

> ✅ **2026-10-02 审计（"有人的格子才比 / 行进少滑动 / 布兵停更 / 同兵种共用网格 / 样式按需刷新"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **新常量**（`GameConfig`，I-15，与 `UNIT_QUERY_*` 同一段）：`UNIT_MARCH_SLIDE_M` / `UNIT_MARCH_BODY_M`。米写在名字里。同段已有的 `UNIT_STAND_SLIDE_SPEED` 是站定不跑滑动的门槛，这次一并记上。
> ② **新方法与字段**（snake_case）：`_nearest_on_grid()` / `_march_clear()` / `_march_hits_world()` / `_park_placed_unit()` / `_wake_placed_units()` / `_own_model_materials()` / `_recolor_team_materials()` / `_paint_team_color()` / `_same_rgb()` / `_own_bow_string_meshes()` / `_build_fresh()` / `_place_tech_style_key()`；`_open_cells` / `_open_keys` / `_model_templates` / `_chip_style_key` / `_tech_style_key`。布尔量 `_march_clear` 读起来像断言。`rgb` 是颜色分量的既有缩写。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。弩车弦杆仍叫 `BowStringBar_*`，没有新节点名。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"肉鸽十回合波次 / 我方死光也结算 / 爆炸箭溅射认盾 / 四选一不裁字 / 释放了的箭不参与拦截"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **新常量**（`GameConfig`，I-15，沿用 `ROGUELIKE_*`）：`ROGUELIKE_ENEMY_WAVES`、`ROGUELIKE_ENEMY_WAVE_RANK_M`、`ROGUELIKE_ENEMY_WAVE_FRONT_X` / `_SKIP_X` / `_REAR_X`。米写在 `_M` 或 `_X` 里，与既有 `ROGUELIKE_POST_X` 同式。取值函数 `roguelike_enemy_wave(round_index)`。
> ② **新方法**（snake_case）：`_spawn_round_enemies()` / `_enemy_wave_next_rank()` / `_clear_enemy_combatants()` / `_player_combatants()` / `_combatants_of()` / `_keep_arrow()` / `_on_arrow_exiting()`。`_on_arrow_exiting` 与既有 `_on_unit_exiting` 同一式。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。`StarterButton_<序号>` 没有改名。测试敌人那几个常量还在，回合流程不再调用。
> ⇒ **无冲突、不改任何命名规则、不改任何不变量**。

> ✅ **2026-10-02 审计（"索敌不拿已经释放的上一帧目标"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **新方法**（`_` + snake_case，按用途命名）：`_living_unit(node)`。返回还在的单位，已经释放的返回空。不是布尔量。
> ② 陷阱那两条没有新名字。圆心用既有的半场线 `x > 0`，相位用既有的 `FIGHTING`。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ 爆炸箭参数 `on_hit` 仍未通过布尔量那条（要读起来像断言）。它不在本条里，命名约定不改。

> ✅ **2026-10-03 审计（"腐化师策反得分 / 被策反的敌人回合开始清掉 / 爆炸不转换已释放的来源"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **新方法**（snake_case，按用途命名）：公开 `award_convert_xp()`；私有 `_add_squad_xp()` / `_notify_convert_xp()`。
> ② **新字段**（`_` + snake_case）：`_corrupt_contributors`（实例编号 → 所在的队）。不是布尔量。局部布尔 `turned_enemy` 读起来像断言。
> ③ **无新信号**（I-34 不涉及）。策反经验是玩法侧方法，不走新信号。无拼音、无中英混拼标识符。爆炸结算复用已有的 `_living_unit()`。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-03 审计（"指挥所改受伤 / 经验加 50% / 敌方科技 / 升级标记 / 全部升级 / 敌方按格落位"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **新常量**（`GameConfig`，I-15，沿用 `ROGUELIKE_*`）：`ROGUELIKE_ENEMY_TECH_FROM_ROUND` / `ROGUELIKE_ENEMY_TECH_STEP_ROUNDS`。回合写在名字里。取值函数 `roguelike_enemy_tech_count()` / `roguelike_squad_xp_cost()`。旧的 `ROGUELIKE_ENEMY_WAVE_FRONT_X` 等四个排距常量还在，波次不再读。
> ② **新节点**（§3.1 PascalCase）：`UpgradeMark`、`SquadUpgradeAllButton`。标记的高度 `UPGRADE_MARK_LIFT` 写在 `Roguelike` 上，与既有 `GRID_LIFT` 一样是表现参数，不进 `GameConfig`。
> ③ **新方法与字段**（snake_case）：`is_command_post()` / `upgrade_same_type()` / `upgrade_same_type_plan()` / `_apply_squad_upgrade()` / `_refresh_upgrade_marks()` / `_upgrade_mark_at()` / `_squad_mark_pos()` / `_take_enemy_anchor()` / `_enemy_block_free()` / `_reserve_enemy_block()` / `_enemy_tech_roll()` / `_spawn_foe_squad_at()`；`_upgrade_marks` / `_squad_upgrade_all`。布尔量 `is_command_post()` / `_enemy_block_free()` 读起来像断言。回调 `_on_squad_upgrade_all_pressed` 与既有 `_on_squad_upgrade_pressed` 同一式。
> ④ **删掉的方法**：`_enemy_wave_next_rank()`。波次改走格子之后没有调用点。
> ⑤ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-03 审计（"投矛出手点 / 拦截优先 / 投石预判 / 护盾挡射线 / 小沙虫体型 / 地下不互锁 / 拔刀换锁 / 开战召手雷 / 射线不提前亮"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新节点 0、新成员变量 0、新常量 0**。
> 新的都是方法，沿用既有 snake_case，私有的带 `_`。
> ① **公开方法**：`Arrow.mark_flight_origin()`、`Unit3D.aim_velocity()`、`Unit3D.beam_reach()`、`Arena.shield_crossing()`、`Arena.note_shield_block()`。名字是动作或名词，和 `spawn_spear_throw()` / `attack_reach()` 同一式。
> ② **私有方法**：`_segment_sphere_hit()`、`_drop_untargetable()`、`_land_open_intercept()`、`_summon_grenadier_wave()`、`_apply_body_scale()`、`_beam_in_draw_range()`、`_beam_origin()`、`_clip_beam_end()`、`_beam_stopped_by_shield()`。布尔返回的 `_beam_in_draw_range()`、`_beam_stopped_by_shield()` 读起来像断言。
> ③ **无新信号**（I-34 不涉及）。挡盾仍写进既有的 `Arena.arrow_blocks`。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-04 审计（"石弹初速 / 生存模式显示名 / 敌方等级 / 沙虫攻速 / 火 5 秒与酸液不叠加 / 地面池不够就补 / 提前量丢掉朝射手的分量 / 射线锁盾边"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0**。
> ① **新常量**（`GameConfig`，I-15）：`UNIT_FIRE_DURATION_MS` / `UNIT_GROUND_TICK_MS` 放在石弹眩晕后面，毫秒写在 `_MS` 里。`ROGUELIKE_ENEMY_LEVEL_FROM_ROUND` / `ROGUELIKE_ENEMY_LEVEL_LAST` 沿用 `ROGUELIKE_*`，紧挨敌方科技那两个回合常量。`UNIT_STONE_SPEED` 只改了值。
> ② **新方法**（snake_case，私有的带 `_`）：`roguelike_enemy_squad_level()` / `_enemy_level_slice()` / `_enemy_wave_squad_count()`；`_claim_ground_visual()` / `_ground_tick_ready()` / `_hide_ground_visual()` / `_shift_tick_book()`；`nearest_shield_rim()` / `shield_rim()` / `_shield_rim_of()` / `_rim_toward()`；`_lock_nearer_shield()` / `_shield_gap()` / `_tick_move_to_shield()` / `_note_shield_damage()` / `_resolve_shield_beam()`；`_remember_motion()`。布尔返回的 `_ground_tick_ready()`、`_shield_lock_alive()`、`_shield_attack_ready()` 读起来像断言。局部量 `used` 也是。`_aim_step_ready` 同样是断言。
> ③ **新字段**（`_` + snake_case，时刻带 `_ms`）：`_fire_tick_ms` / `_acid_tick_ms`（单位实例编号 → 下一次还能吃这一跳的时刻）。`_shield_lock_id` / `_shield_point` / `_laser_shield_id`。`_aim_prev` / `_aim_flat` / `_aim_delta`。
> ④ **没有新节点名**。火和酸液仍是 `FirePool_<序号>` / `AcidPool_<序号>`，序号可以超过预建的 8。开始界面节点仍是 `Option_4`，按钮文字改成「生存模式」。顶栏节点仍是 `ModeLabel`。
> ⑤ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-05 审计（"沙盒摆放按脚印留空"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新组名 0、新节点 0**。
> ① **新常量**（`GameConfig`，I-15，沿用 `UNIT_*`）：`UNIT_LIGHTCAV_VISUAL_X` / `_Y` / `_Z`。轴写在名字里，单位是米。只给沙盒脚印用，不进 `body_radius()`。
> ② **新方法**（snake_case）：公开 `place_footprint_size()`。私有 `_place_facing()` / `_place_world_half()` / `_place_overlaps()`。布尔返回的 `_place_overlaps()` 读起来像断言。
> ③ **无新信号**（I-34 不涉及）。预览节点仍叫 `PlaceGhost`。无拼音、无中英混拼标识符。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-14 审计（"手雷爆炸吃等级、冲锋重锁、精英招募加价、火焰屏障免火免酸、陷阱 500、开战召唤手雷王"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新节点 0、新常量名 0**。`ROGUELIKE_TRAP_DAMAGE` 只改了值（200 → 500），名字没动。
> ① **新公开方法**：`Unit3D.has_flame_barrier()` 读起来像断言，和 `has_tech()` 同一式。`Roguelike.upgrade_price_of(type_id)` 是名词，`upgrade_price()` 改成调用它。
> ② **新私有字段**：`_summon_skirmish_ms`。`_ms` 后缀，暂停时和 `Arena.skirmish_start_ms` 一起被 `shift_deadlines()` 推后。`reset_to()` 里清成 0。
> ③ **无新信号**（I-34 不涉及）。无新节点。无拼音、无中英混拼标识符。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-16 审计（"生存模式援助、首回合补给 25、摧毁敌方指挥所 +10 补给"）**：
> **新文件 1、新类 1、新信号 0、新实体 ID 0、新组名 0**。
> ① **新文件 / 新类**：`scripts/game/roguelike_aid.gd` ↔ `class_name RoguelikeAid`（§3.2）。
> ② **新节点**（PascalCase，序号在 `_` 后面，§3.1）：`AidScrim`、`AidCenter`、`AidPanel`、`AidBox`、`AidTitleLabel`、`AidBodyLabel`、`AidButton_<序号>`、`AidSkipButton`、`AidTray`、`AidCard_<序号>`。场地上的标记是 `AidMark_<序号>`、`AidZone_<序号>`。
> ③ **新常量**（仍在 `GameConfig` 既有的 `ROGUELIKE_` 段，没有新的功能域前缀）：`ROGUELIKE_AID_FROM_ROUND`、`ROGUELIKE_AID_OFFER_COUNT`、`ROGUELIKE_AID_SKIP_SUPPLY`、`ROGUELIKE_POST_KILL_SUPPLY`、`ROGUELIKE_AID_POST_CLEAR_M`、`ROGUELIKE_AID_OIL_SPEED_MULT`、`ROGUELIKE_AID_SMOKE_RANGE_CUT`、`ROGUELIKE_AID_BURN_TICK`、`ROGUELIKE_AID_BURN_MS`、`ROGUELIKE_AID_GROUND_TICK_MS`、`ROGUELIKE_AID_ACID_RATIO`、`ROGUELIKE_AID_SQUAD_CLEAR_M`、`ROGUELIKE_AID_MODULE_WEIGHT`、`ROGUELIKE_AID_COST_CONTROL_MULT`、`ROGUELIKE_AID_SHIELD_DROP_SCALE`、`ROGUELIKE_AID_WARD_HP`、`ROGUELIKE_AID_WARD_RADIUS`。`ROGUELIKE_SUPPLY_START` 只改了值（20 → 25）。空投落点间距读已有的 `ROGUELIKE_REPLICATE_SPREAD`。空投火焰屏障的时长和受伤倍率读火拳科技表的 `duration_ms` / `damage_taken_mult`。
> ④ **新布尔量**读得成断言：`aid_pending`、`aid_flank_half`、`aid_elite_level`、`aid_cost_control`、`_aid_anchor_set`、`_command_wiping`、`aid_blast_used`。
> ⑤ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。标记圆的半径 0.6 m 是表现，留在脚本里。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-17 审计（"敌方总权重改直线、按队权重随机兵种、随机站位与侧翼、战场道具并入信标栏"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。
> ① **新节点**（PascalCase，§3.1）：`AidPropBox`。卡仍叫 `AidCard_<序号>`。
> ② **新常量**（仍在 `GameConfig` 既有的 `ROGUELIKE_ENEMY_` 段，没有新的功能域前缀）：`ROGUELIKE_ENEMY_WEIGHT_PER_ROUND`、`ROGUELIKE_ENEMY_EDGE_CELLS`、`ROGUELIKE_ENEMY_FRONT_CELLS`、`ROGUELIKE_ENEMY_SIEGE_FRONT_CELLS`、`ROGUELIKE_ENEMY_SIEGE_TYPES`、`ROGUELIKE_ENEMY_BACKLINE_MELEE`、`ROGUELIKE_ENEMY_MELEE_FRONT_WEIGHT`、`ROGUELIKE_ENEMY_FLANK_FROM_ROUND`、`ROGUELIKE_ENEMY_FLANK_SPLIT_FROM_ROUND`、`ROGUELIKE_ENEMY_FLANK_BOTH_ROUND`、`ROGUELIKE_ENEMY_FLANK_LAST_ROUND`、`ROGUELIKE_ENEMY_FLANK_CHANCE`。`ROGUELIKE_ENEMY_WEIGHT_BASE` 的值是 60。
> ③ **新方法**（snake_case）：`roguelike_enemy_weight_target()`、`roguelike_enemy_types_for_squad_weight()`、`roguelike_enemy_stands_back()`、`roguelike_enemy_front_cells()`、`roguelike_enemy_edge_cells()`。`stands_back` 读起来像断言。私有 `_has_aid_prop_card()`、`_enemy_melee_ahead()`、`_enemy_backline_fits()` 同样读起来像断言。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。波次表的键 `squad_weight` 是数据字段，不是新的实体 ID。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-18 审计（"沙盒与生存战斗中操控单位"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。
> ① **新枚举** `PilotGate { CLOSED, ANY, OWN }`：类型 PascalCase、成员不带类型前缀（§3.5）。它不进界面文字，也没有单独的名字函数，与既有的 `Burrow` / `Flame` 一样。
> ② **新节点**（PascalCase，§3.1）：`PilotLayer`、`PilotOverlay`、`PilotCrosshair`、`PilotStatus`、`PilotHpLabel`、`PilotSkillLabel`、`PilotHalo`。没有带序号的一组，所以没有 `_序号` 后缀。
> ③ **新常量**（仍在 `GameConfig` 既有的 `CAM_*` 段，没有新的功能域前缀）：`CAM_PILOT_ABOVE`、`CAM_PILOT_AHEAD`、`CAM_PILOT_SHOULDER_LIFT`、`CAM_PILOT_SHOULDER_BACK`、`CAM_PILOT_SHOULDER_RIGHT`、`CAM_PILOT_PICK_RADIUS_PX`、`CAM_PILOT_AIM_CONE_DEG`、`CAM_PILOT_BEAM_TOLERANCE`。角度写了 `_DEG`，屏幕半径写了 `_PX`。米数沿用 `CAM_FOLLOW_DISTANCE` 那种写法，单位在注释里。
> ④ **新方法与字段**（snake_case）：`pilot_body_top()`、`pilot_body_front()`、`open_pilot_gate()`、`close_pilot_gate()`、`begin_pilot()`、`exit_pilot()`、`set_piloted()`、`pilot_cast_skill()`、`pilot_skill_line()`、`spawn_arrow_along()`、`spawn_spear_along()`。公开字段 `piloted`、`pilot_aim`。
> ⑤ **新布尔量**读得成断言：`piloted`、`_pilot_attack_armed`、`_pilot_has_return`、参数 `own_team_only`。`_pilot_shoulder` 表示当前是越肩视角，与既有的 `_flying` 同一类状态断言。
> ⑥ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。准星的像素和光晕多出来的 0.35 m 是表现，留在脚本里。
> ⇒ **这一条无冲突、不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-18 审计（"图鉴"）**：
> **新文件 1**（`scripts/ui/codex_screen.gd`）、**新类 1**（`CodexScreen`，与文件名对应）、**新信号 0、新实体 ID 0**。
> ① **新节点**（PascalCase，§3.1）：`CodexRoot`、`Scrim`、`CodexFrame`、`CodexColumn`、`CodexHeader`、`CodexTitle`、`HeaderSpacer`、`CloseButton`、`CodexBody`、`UnitListScroll`、`UnitList`、`UnitPick_%d`、`UnitDetailScroll`、`UnitDetail`、`DetailHeading_%d`、`DetailLine_%d`、`DetailGap_%d`、`ModelView`、`ModelViewport`、`ModelSky`、`ModelKey`、`ModelFill`、`ModelStage`、`ModelFloor`、`ModelPivot`、`ModelCamera`、`CodexModel`。成组的用 `_` 加序号。`Scrim` 与暂停菜单、设置界面是同一个「压暗」概念，沿用同一个名字。
> ② **新常量**留在这个界面脚本里，与 `SETTINGS_LAYER` 一类：`CODEX_LAYER`、`SCRIM_COLOR`、`CODEX_SPIN_RAD`、`LIST_WIDTH`、`MODEL_WIDTH`。
> ③ **新方法**（snake_case）：`open()`、`close()`、`is_open()`，与 `SettingsScreen` 同名同义。`is_open` 读起来像断言。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。
> ⑤ **没有和已有名字撞车。** 两处比 §3.3 松，规则不改：私有方法 `_cd`、`_fmt` 不在公认缩写表里，定义处也没有注释；`CODEX_SPIN_RAD` 写了弧度，没写「每秒」。单位写在 `05_ui_hud.md#15`（0.45 弧度/秒）。要改名或补注释，先改代码。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-18 审计（"战场场景 + 图鉴排序 / 科技 / 正面"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0**。
> ① **新常量**（`GameConfig`，`BATTLE_SCENE_` 一段）：`BATTLE_SCENE_PLAIN`、`BATTLE_SCENE_IDS`。标识是小写 `forest` / `mountain` / `desert` / `snow` / `city` / `plain`。`CODEX_FRONT_YAW_RAD` 留在图鉴脚本里，单位写在名字上。
> ② **新方法**（snake_case）：`battle_scene_ids()`、`battle_scene_name()`、`is_battle_scene_enabled()`、`set_battle_scene_enabled()`、`battle_scene_snapshot()`、`pick_battle_scene()`、`roll_battle_scene()`。`is_battle_scene_enabled` 和参数 `enabled` 读起来像断言。
> ③ **新节点**（PascalCase，成组的用 `_` 加序号，沿用 `Scenery_<种类>_<序号>`）：`Scenery_peak_%d`、`Scenery_building_%d`（`Wall` / `Roof`）、`Scenery_glacier_%d`、`Scenery_cactus_%d`（`Trunk` / `Arm_%d`）、`Scenery_snowman_%d`（`Body` / `Head`）、`Scenery_cloud_%d`（`Puff_%d`）。树仍叫 `Scenery_tree_%d`，柳枝是 `Hanging_%d`。设置里的勾选是 `SceneForest`、`SceneMountain`、`SceneDesert`、`SceneSnow`、`SceneCity`。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。没有和已有名字撞车。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-19 审计（"每轮换景 + 景物外形"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新常量 0**。
> ① **新节点**（PascalCase，§3.1；成组的用 `_` 加序号，沿用 `Scenery_<种类>_<序号>`）：`Scenery_south_%d`（`Bush` / `Scrub` / `Mound` / `Hedge` / `Stone_%d`）。山峰 `Scenery_peak_%d` 的子节点改为 `Mass`、`Spur_0`、`Spur_1`、`Ridge`。松树的树冠改成 `Cone_%d`。柳树在已有的 `Hanging_%d` 之外加 `Tip_%d`。仙人掌的 `Arm_%d` 南侧也有。
> ② **新方法**都是 `arena.gd` 里的私有方法，snake_case、前缀 `_`：`_paint_sky()`、`_make_sun_panorama()`、`_build_near_camera()` 以及拼山、拼树、拼南侧矮景物的那几个。没有新的公开方法。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。没有和已有名字撞车。太阳贴图不另起节点，方向光仍叫 `Sun`。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-19 审计（"景物外形与场地外起伏"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新常量 0**。
> ① **新节点**（PascalCase，§3.1；成组的用 `_` 加序号）：`Scenery_ground`（场地外的起伏地面，只有一个）、`Scenery_bush_%d`（`Sprig_%d`）。枫树和樱花的树冠是 `Lobe_%d`。银杏是 `Blade_%d`。山峰在 `Mass` / `Spur_0` / `Spur_1` 之外加 `Facet_%d`，不再用 `Ridge`。冰川的子节点是 `Base` / `Mid` / `Tip` / `Shard`。
> ② **不再生成**：`Scenery_south_%d` 和它下面的 `Bush` / `Scrub` / `Mound` / `Hedge` / `Stone_%d`，柳树的 `Hanging_%d` / `Tip_%d`，雪人 `Scenery_snowman_%d`。`_build_near_camera()` 已删。
> ③ **新的私有字段与方法**（snake_case、前缀 `_`）：`_relief_noise`、`_relief_amplitude`、`_prepare_relief()`、`_ground_y()`、`_seat()`、`_build_relief_mesh()`、`_build_bushes()`，以及排树、排楼、拼树冠、拼冰川的那几个。没有新的公开方法。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。没有和已有名字撞车。
> ⑤ 一处比 §3.3 松，规则不改：`_relief_amplitude` 是米，名字里没写单位。1.75 m 和 5.2 m 写在 `04_physics.md#2.4.1`。要改名，先改代码。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-21 审计（"去掉看台和柱子，树冠、起伏与雪地松树"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新常量 0**。
> ① **没有新节点**。列柱 `Scenery_pillar_*` / `Scenery_block_*`、看台 `Scenery_stand_%s` 及其 `Tier_%d` / `TeamEdge` 不再生成。队旗 `Scenery_banner_%s` 还在。树冠仍是 `Lobe_%d` / `Blade_%d`，山仍是 `Mass` / `Spur_0` / `Spur_1` / `Facet_%d`，地面仍是 `Scenery_ground`。
> ② **新的私有字段与方法**（snake_case、前缀 `_`）：`_relief_blend`、`_relief_apron`、`_forest_band()`、`_place_north_pines()`、`_jostle_tree()`、`_lowest_ground()`。字典键 `north_tree_count`、`north_glacier_count` 是全小写 snake_case。没有新的公开方法。
> ③ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。没有和已有名字撞车。
> ④ 两处比 §3.3 松，规则不改：`_relief_blend`、`_relief_apron` 都是米，名字里没写单位。12 m、18 m、32 m、5.2 m、16 m 写在 `04_physics.md#2.4.1`。要改名，先改代码。`_relief_amplitude` 仍是上一则那一处。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-21 审计（"游戏定名羽锋大乱斗，目录改为 yufengdaluandou"）**：
> **新文件 0、新类 0、新信号 0、新实体 ID 0、新常量 0**。脚本里的标识符没有改。
> ① 工程目录从 `zhengfengpindao` 改为 `yufengdaluandou`。这是拼音路径，不是 GDScript 标识符，不进 §3。
> ② `project.godot` 的 `application/config/name` 改为「羽锋大乱斗」。这是窗口标题用的项目名，不是节点名、脚本名或实体 ID。
> ③ **无新信号**（I-34 不涉及）。没有和已有名字撞车。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-22 审计（"雪地压暗，设置与竞猜/生存存档"）**：
> **新文件 2、新类 2、新信号 1（本层，不上 `Events`）、新实体 ID 0、新常量 0（没有新的 `GameConfig` 玩法数）**。
> ① `scripts/core/user_prefs.gd` ↔ `class_name UserPrefs`；`scripts/game/match_save.gd` ↔ `class_name MatchSave`。文件名与类名对得上 §3.2。后缀是角色词，与已有的 `MatchPause`、`UiStyle`、`RoguelikeAid` 同一类，不另立一条命名规则。两者都不是 Autoload。
> ② 新信号只有 `StartScreen.resume_selected(mode: String)`。过去式，与已有的 `mode_selected` 并列。没有新的 `Events` 信号（I-34）。
> ③ 新节点 `ConfirmOverlay` / `ConfirmDim` / `ConfirmPanel` / `ConfirmBox` / `ConfirmLabel` / `ConfirmButtons` / `ConfirmYes` / `ConfirmNo`，都是 PascalCase。开始界面的 `Option_%d` 序号后移，pattern 没变。暂停菜单的 `PauseOption_%d` 没动。
> ④ 新方法与布尔都是 snake_case：`write_resume`、`restore_from_save`、`restore_opening`、`any_exists`、`has_quiz`、`has_roguelike`、`has_mode`、`_loading_save`。截止时刻仍走已有的 `_*_ms`，0 表示没排期。
> ⑤ 类里的路径常量 `PATH` / `QUIZ_PATH` / `ROGUELIKE_PATH` 是这份文件自己的常量，不是新的全局命名规则。`data` 这个参数名沿用 `_restore_state(data)`，不另立约定。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。没有和已有名字撞车。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-22 审计（"雪地再调浅，主菜单改为保存并退出，设置分块并可改键"）**：
> **新文件 1、新类 1、新信号 0、新实体 ID 0、新的 `GameConfig` 玩法数 0**。
> ① `scripts/core/input_bindings.gd` ↔ `class_name InputBindings`。文件名与类名对得上 §3.2。后缀是角色词，与已有的 `UserPrefs`、`MatchSave`、`MatchPause` 同一类，不另立一条命名规则。不是 Autoload。
> ② 新的 InputMap 动作是 `pilot_skill` / `pilot_shoulder` / `pilot_release`，全小写 snake_case，与已有的 `cam_forward` 一类。`cam_forward` / `cam_back` / `cam_left` / `cam_right` / `cam_overview` 的名字没改。没有新的 `Events` 信号（I-34）。
> ③ 新节点 `SettingsScroll` / `SettingsList` / `SectionVideo` / `VideoFullscreen` / `SectionAudio` / `SectionMap` / `SectionKeys` / `KeyHint` / `KeyRow_%d` / `KeyButton_%d`，都是 PascalCase，序号在 `_` 后面（I-31）。
> ④ 类里的常量 `ACTIONS` 是 SCREAMING_SNAKE_CASE。`_LABELS` / `_DEFAULT_CODE` 带下划线，只在这个文件里用。方法 `ensure_actions` / `key_label` / `pad_matches` / `set_physical` 是 snake_case。`UiStyle.CAMERA_HINT` 这个常量改成了静态方法 `camera_hint()`，方法名按 §2 用 snake_case。不另立一条「文案必须是常量」的规则。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。没有和已有名字撞车。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"设置按区块显示，生存增加难度"）**：
> **新文件 0、新类 0、新信号 0、新组名 0**。没有新的功能域前缀。
> ① **新节点**（PascalCase，成组的序号在 `_` 后面，§3.1 / I-31）：`SectionTabs`、`SectionTab_%d`、`SectionPage_%d`。页里面原来的 `SectionVideo` / `SectionAudio` / `SectionMap` / `SectionKeys` 还在。`DifficultyScrim`、`DifficultyCenter`、`DifficultyPanel`、`DifficultyBox`、`DifficultyTitle`、`DifficultyButton_%d`。
> ② **新常量**都在 `GameConfig` 已有的 `ROGUELIKE_` 段里：`ROGUELIKE_DIFFICULTY_VERY_EASY` 到 `_MIRACLE`、`ROGUELIKE_DIFFICULTY_ORDER`、`ROGUELIKE_DIFFICULTY_DEFAULT`、`ROGUELIKE_DIFFICULTY_WEIGHT_BASE`、`_WEIGHT_STEP`、`_STEP_BONUS`、`_BASE_BONUS`、`_LEVEL_FROM_ROUND`、`_EASY_LEVEL_DENOM`、`_HARD_LEVEL_DENOM`、`_LEVEL3_FROM_ROUND`、`_TECH_FROM_ROUND`、`_TECH_ALL_ROUND`、`_TECH_HALF_DENOM`、`_PACK_EARLY_10`、`_PACK_LATE_10`、`_PACK_EARLY_25`、`_PACK_LATE_25`。标识是全小写 snake_case：`very_easy` / `easy` / `normal` / `hard` / `very_hard` / `transcend` / `miracle`（I-33）。
> ③ **新方法与字段**（snake_case）：`roguelike_difficulty_id()`、`roguelike_difficulty_name()`、`roguelike_enemy_weight_target_for()`、`roguelike_enemy_uses_flank()`、`roguelike_enemy_wave_for()`、`roguelike_enemy_squad_level_for()`、`roguelike_enemy_squad_tech_count()`、`choose_difficulty()`。私有 `_roguelike_difficulty_rank()`、`_roguelike_enemy_pack()`、`_enemy_tech_for_squad()`、`_build_difficulty()`、`_refresh_difficulty()`、`_on_difficulty_pressed()`、`_show_section()`。公开字段 `difficulty`、`difficulty_chosen`。`difficulty_chosen` 和 `roguelike_enemy_uses_flank` 读起来像断言。
> ④ **无新信号**（I-34 不涉及）。无拼音、无中英混拼标识符。没有和已有节点名撞车。
> ⑤ 两处不改规则：`DifficultyTitle` 没有 `Label` 后缀，起手那层叫 `StarterTitleLabel`、援助那层叫 `AidTitleLabel`。§3.1 不要求这个后缀。难度标识 `normal` 和竞猜按钮槽里的键 `"normal"` 不是同一个概念。`_commit_enemy_squad()` 里没再用的参数写成 `_tech_roll`，沿用前缀 `_` 表示不读它。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"战斗定格、指挥所等级、图鉴援助、部署射程圈"）**：
> **新文件 1、新类 1、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① `scripts/game/range_hint.gd` ↔ `class_name RangeHint`。文件名与类名对得上 §3.2。表现常量留在这个类里，不进 `GameConfig`：`RANGE_CIRCLE_LIFT_M`、`RANGE_CIRCLE_TINT`、`LOCK_ARROW_LIFT_M`、`LOCK_ARROW_TINT`。高度带 `_M`。它们不以 `RING_` 或 `CIRCLE_` 开头，不占用兴奋圈和圈外状态那两域。
> ② **新的 `GameConfig` 常量**只有 `BATTLE_HOLD_DELAY_MS`（200）。单位写在名字里。回合起始等级是函数 `roguelike_post_round_level()`，不是另一套魔法数字。`ROGUELIKE_BUFF_HP_PER_LEVEL` 与 `ROGUELIKE_RECALL_PRICE` 只改了值。
> ③ **新节点**（PascalCase，序号在 `_` 后面）：`HoldTop`、`HoldTopBox`、`HoldBottom`、`HoldPrompt`、`ChoiceEye`、`ChoiceEyeHint`、`ChoiceNotice`、`TechGap`、`CodexTab_%d`、`AidGroup_%s`、`AidPick_%d`、`RangeRing`、`RangeAim`、`Meridians`。`Overlay`、`OverlayTitleLabel`、`OverlayBodyLabel` 还在。
> ④ **新方法与字段**是 snake_case。布尔 `presentation_frozen`、`choice_hidden` 读起来像断言。截止时刻 `_presentation_at_ms` 进 `Arena.shift_deadlines()`。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"定格自由视角、生存眼睛、竞猜机位、图鉴排序"）**：
> **新文件 1、新类 1、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① `scripts/ui/screen_fade.gd` ↔ `class_name ScreenFade`。文件名与类名对得上 §3.2。后缀是角色词，与 `RangeHint`、`UiStyle` 同一类。不是 Autoload。类里的 `FADE_OUT_MS` / `FADE_IN_MS` / `FADE_LAYER` 与 `StartScreen` 的 `FADE_*` 同一条：文件本身就是这个域，不再加一层前缀。
> ② **新的 `GameConfig` 常量**只有 `CAM_QUIZ_PITCH`。前缀是已有的 `CAM_*`，不是新域。`CAM_ROGUELIKE_*` 五个只改了值。
> ③ **新节点**（PascalCase，序号在 `_` 后面）：`ScreenFade`、`FadeRect`、`UnitListColumn`、`CodexSortRow`、`SortPrice`、`SortKind`、`CodexFilterRow`、`FilterMelee`、`FilterRanged`、`FilterFree`、`FilterVariant`、`FilterExpert`、`FilterProp`、`FilterModule`、`CodexEmpty`、`UnitPrice_%d`。`ChoiceEye` 还在，只换了锚点。
> ④ **新方法与字段**是 snake_case：`on_quiz_phase()`、`_overview_keeps_pose`、`_view_choice_unit()`、`_aid_sort_kind`。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"渐黑后点击、生存镜头、图鉴远程、散射与蓄力"）**：
> **新文件 0、新类 0、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① **没有新的 `GameConfig` 常量**。`CAM_ROGUELIKE_PITCH` 只改了值（−1.02 → −0.92）。`is_ranged` 没改。
> ② **新节点**（PascalCase，序号在 `_` 后面）：`OrbitOrbs`、`OrbitOrb_%d`、`ChargeGather`、`ChargeCore`、`ChargeMote_%d`、`ScatterOrbs`、`ScatterOrb_%d`、`ScatterMote_%d`。每颗虚边球里面的 `Core` / `Haze` 是这颗球自己的子节点，不另立一条命名规则。
> ③ **新方法**是 snake_case，并且带前缀 `_`：`_listed_as_ranged()`、`_soft_ball()`、`_cache_beam_fx()`、`_hold_extra_beams()`、`_beam_source()`、`_update_beam_fx()`、`_spin_scatter_orbs()`、`_charge_amount()`、`_update_doom_charge()`。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"部署外观、射线距离、结束战斗、实心圈"）**：
> **新文件 0、新类 0、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① **没有新的 `GameConfig` 常量**。`CAM_QUIZ_PITCH` 只改了值（−0.46 → −0.38）。`is_ranged` 没改。
> ② **新节点** `RangeFill`，PascalCase。它换掉射程圈原来的线框 `RangeRing`。`RANGE_FILL_LIFT_M` / `RANGE_FILL_TINT` 留在 `RangeHint` 里，和原来的 `RANGE_CIRCLE_*` 一样，不进 `GameConfig`，也不另开一条全局前缀。
> ③ **新方法**是 snake_case：`_apply_deploy_pose()`、`_charge_finished()`、`_set_cylinder_radius()`、`set_range_glow()`、`set_hover_glow()`、`_sync_outline()`。布尔 `_range_glow`、`_hover_glow`、`_outline_on` 读起来像断言。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-23 审计（"蓄力不出射线、关窗口存档、火枪烟雾、大师对沙虫"）**：
> **新文件 0、新类 0、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① **没有新的 `GameConfig` 常量**。`BULLET_SMOKE_SPACING_M` / `BULLET_SMOKE_FADE_MS` / `BULLET_SMOKE_ALPHA` / `BULLET_SMOKE_MESH` 留在 `Arrow` 里，和 `IMPACT_DUST_*`、`SHIELD_STICK_INSET` 一样，不进全局前缀表。
> ② **新节点** `BulletSmoke_%d`，PascalCase，序号在 `_` 后面。
> ③ **新方法与字段**是 snake_case，并且私有的带前缀 `_`：`_laser_arming`、`_laser_engaged`、`_laser_lock_held()`、`_beam_hits_1`～`_beam_hits_4`、`_save_match_on_quit()`、`_lay_bullet_smoke()`。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> ✅ **2026-10-24 审计（"散射中心球、腐化师法球曲线"）**：
> **新文件 0、新类 0、新信号 0、新组名 0**。没有新开功能域前缀，没有改命名规则。
> ① **没有新的 `GameConfig` 常量**。球的半径仍写在 `UnitFactory` 里，和原来的 `ScatterOrb_%d` 一样。蓄力仍读 `UNIT_CORRUPT_CHARGE_MS`。
> ② **新节点**（PascalCase，序号在 `_` 后面）：`ScatterHub`、`ScatterPulse_%d`、`OrbitLeg_%d`、`OrbitLegSeg_%d`。前缀沿用已有的 `Scatter*` / `Orbit*`，不是新域。
> ③ **新方法与字段**是 snake_case，并且私有的带前缀 `_`：`_orbit_legs`、`_orbit_leg_bead()`、`_place_corruptor_orbs()`、`_emit_scatter_pulses()`。没有新的 `Events` 信号（I-34）。
> ⇒ **这一条不改任何命名规则、不改任何不变量**。
> ⚠️ `on_hit` 仍未改名，命名约定不改。

> 改本文件的任何一条，等于动不变量：先在 `99_decisions.md` 追加一条。

## 5. 提交前自查

- [ ] 新文件按 §2 的风格表命名
- [ ] 新 `class_name` 与文件名一一对应
- [ ] 新增信号是过去式，且描述"发生了什么"
- [ ] 没有裸整数代替枚举
- [ ] 没有拼音 / 中英混拼
- [ ] 单位（m / s / ms）写进了变量名或常量名
