# 07 工程目录结构与放置约定

> **权威范围**：什么东西放在哪个目录、怎么命名、怎样才算"放对了"。
> 新增目录前必须先改本文件，再建目录。

## 1. 当前实际结构（与本文件一致）

```
yufengdaluandou/                      # Godot 项目根（res://）。游戏名《羽锋大乱斗》
├── project.godot                     # Godot 4.7 / Forward+ / Jolt / d3d12 / 1600×900
├── icon.svg
├── .editorconfig / .gitignore / .gitattributes
├── addons/
│   └── godot_mcp/                    # MCP 编辑器插件 + 游戏内桥（第三方，勿改）
├── default_bus_layout.tres           # 音频总线树（`06_audio.md#1`，2026-09-25 建：8 条总线 + Master 限制器）
├── assets/
│   └── audio/                        # 音频素材（**6 个，用户提供**；文件名 = 事件名，见 `06_audio.md#3`）：
│                                     #   combat_hit_flesh.wav / combat_shield_block.mp3 / combat_bow_release.mp3
│                                     #   combat_catapult_launch.mp3 / combat_ballista_launch.mp3 / unit_vehicle_move.wav
├── resources/
│   └── audio/                        # 音频资源（导入后的 .tres 等；**当前为空** —— 2026-09-25 起不再放 `.gitkeep`）
├── scenes/
│   └── main/
│       ├── main.tscn                 # 主场景：只有一个 Node3D 根 + main.gd
│       ├── debug_autoplay.tscn       # 调试：无头跑完整局
│       └── debug_balance_stats.tscn  # 调试：数值平衡统计（兵种优势度）
├── scripts/
│   ├── core/
│   │   ├── events.gd                 # Autoload "Events"：全局事件总线
│   │   ├── config.gd                 # Autoload "GameConfig"：全部数值 + 配平 + 出生点布局
│   │   ├── audio_manager.gd          # 音频层：事件名 → 音频流（⚠️ **不是 Autoload**；2026-09-25 起由 main.gd 在 `_ready()` 里建、**全程常驻不释放**——旧注"随比赛创建/释放"已过期，见 `06_audio.md#7.1`）
│   │   ├── match_pause.gd            # 暂停记账 + **绝对截止时刻整体后移**（三个模式共用；纯静态工具）
│   │   ├── user_prefs.gd             # 音量、战场勾选、全屏和按键的本机文件（2026-10-22；`class_name UserPrefs`，**不是 Autoload**）
│   │   └── input_bindings.gd         # 八个可改按键（2026-10-22；`class_name InputBindings`，**不是 Autoload**）
│   ├── game/
│   │   ├── main.gd                   # 装配与接线（两段式：先开始界面，**选完模式**、黑透后才装真比赛）
│   │   ├── game.gd                   # 对局状态机（轮次/点数/机会）—— **竞猜模式**
│   │   ├── sandbox.gd                # 沙盒模式：自由布兵 / 开战 / 按剩余总血量判胜（不启赛程）
│   │   ├── roguelike.gd              # 肉鸽模式：10 回合 / 每回合领补给 / 血量记账（**当前只有骨架 + 经济**，不启赛程）
│   │   ├── roguelike_aid.gd          # 肉鸽援助（2026-10-16）：四选一、专家 / 变种 / 道具 / 模块。逐条数据在 `config.gd`
│   │   ├── range_hint.gd             # 部署射程圈和锁定箭头（2026-10-23；`class_name RangeHint`，纯表现）
│   │   ├── match_save.gd             # 竞猜、生存各一份存档（2026-10-22；`class_name MatchSave`，**不是 Autoload**）
│   │   ├── start_showcase.gd         # 开始界面的背景演示（灰色场地 + 固定阵容的静止战斗 + 环绕镜头）
│   │   ├── debug_autoplay.gd         # 自动对局（调试）
│   │   └── debug_balance_stats.gd    # 数值平衡回归（调试）
│   ├── arena/
│   │   ├── arena.gd                  # 场地 / 兴奋圈 / 刷兵 / 箭矢 / 胜负判定
│   │   └── arrow.gd                  # 箭矢
│   ├── units/
│   │   ├── unit3d.gd                 # 选手（AI + 攻击 + 受击 + 状态机）
│   │   └── unit_factory.gd           # 程序化模型与血条贴图
│   ├── camera/
│   │   └── camera_rig.gd             # 观赛相机（全景 / 自由飞行 / 跟随）
│   └── ui/
│       ├── hud.gd                    # **竞猜模式**的界面（顶栏 / 下注面板 / 结算浮层 / 操作提示；代码构建，无 .tscn）
│       ├── sandbox_hud.gd            # **沙盒模式**的界面（顶栏双方总权重 / 底部兵种栏 / 开战 / 战果浮层）
│       ├── roguelike_hud.gd          # **肉鸽模式**的界面（顶栏回合 / 补给 / 血量 / 敌方权重 + 底部行动栏 + 结算浮层）
│       ├── pause_menu.gd             # 暂停菜单（齿轮 / `Esc`；**三个模式共用这一层**）
│       ├── settings_screen.gd        # 设置界面（视频 / 音频 / 地图 / 按键四块 + 退出 / 启用；开始界面与暂停菜单**共用这一层**）
│       ├── codex_screen.gd           # 图鉴（兵种七项 / 特性 / 技能 + 旋转模型；开始界面与暂停菜单**共用这一层**，2026-10-18）
│       ├── start_screen.gd           # 开始界面（左侧选项列**三档** + 渐黑/渐亮过渡；同样代码构建。2026-10-22 起第一档多「继续游戏」）
│       ├── screen_fade.gd            # 战果按 Enter 继续时的渐黑/渐亮（2026-10-23；`class_name ScreenFade`，三个模式共用，不是 Autoload）
│       └── ui_style.gd               # 界面**统一外观**（选项按钮 / 兵种小卡 / 齿轮 / 字号与调色板；纯静态工具）
└── docs/
    └── bible/                        # 本目录：项目设定与约定（唯一事实来源）
        ├── _index.md  00_world.md   01_core_loop.md   02_entities.md
        ├── 03_rules.md  04_physics.md  05_ui_hud.md  06_audio.md
        └── 07_file_layout.md  08_naming.md  09_roguelike.md  99_decisions.md
```

### 1.1 规模

| 项 | 数量 |
| --- | --- |
| GDScript 文件 | **30**（含 2 个调试脚本；2026-09-25 新增 `game/start_showcase.gd`、`ui/start_screen.gd`、`ui/ui_style.gd`、`core/audio_manager.gd`，随后又新增 `core/match_pause.gd`、`game/sandbox.gd`、`ui/pause_menu.gd`、`ui/sandbox_hud.gd`、**`ui/settings_screen.gd`**；**2026-09-26 再新增 `game/roguelike.gd` 与 `ui/roguelike_hud.gd`**；**2026-10-16 再新增 `game/roguelike_aid.gd`**；**2026-10-18 再新增 `ui/codex_screen.gd`**；**2026-10-22 再新增 `core/user_prefs.gd` 与 `game/match_save.gd`**；同日再新增 **`core/input_bindings.gd`**；**2026-10-23 再新增 `game/range_hint.gd`**；同日再新增 **`ui/screen_fade.gd`**） |
| 场景文件 | 3（含 2 个调试场景） |
| 外部美术资源 | 0（全部程序化生成） |
| 音频素材 | **6**（`assets/audio/`，**用户提供**的 `.wav` / `.mp3`；文件名 = 事件名，见上面的目录树与 `06_audio.md#3`）。⚠️ **2026-09-25 修正**：这一格原先写"**0**（路线 = 程序化合成）"，是"第一批音效接入"那一批**漏改**留下的过期事实 —— 与上一节目录树里列的 6 个素材自相矛盾；"程序化合成"这条路线**当场就被用户提供的现成素材取代**了（见 `99_decisions.md` 同日条目） |
| 音频总线 | **8**（`default_bus_layout.tres`，2026-09-25 建，见 `06_audio.md#1`） |
| bible 文档 | 12 |

## 2. 规划中的结构（尚未创建）

> 需要时**按本表创建**，不要即兴命名。

```
yufengdaluandou/
├── scenes/
│   ├── main/            # 已有
│   ├── ui/              # 若界面复杂到需要 .tscn 时
│   └── units/           # 若选手需要可视化编辑时
├── resources/
│   ├── config/          # 数值配置 .tres（当前数值在 config.gd，迁移时同步改 bible）
│   ├── materials/       # 材质与物理材质
│   └── audio/           # ✅ **已创建**（2026-09-25，当前为空目录）：音频资源与总线布局
├── assets/              # 原始美术与音频素材（models/ textures/ audio/ fonts/）
│                        #   ✅ `audio/` **已创建**（2026-09-25，现有 6 个素材，见第 1 节）
├── shaders/             # .gdshader（兴奋圈目前用 StandardMaterial3D，暂不需要）
└── tests/               # 之后的测试脚本
```

## 3. 放置约定（硬规则）

| # | 规则 | 理由 |
| --- | --- | --- |
| R-01 | `addons/` 只放第三方代码，游戏逻辑永不写进 `addons/` | 便于升级插件 |
| R-02 | 一个场景配一个同名脚本，脚本路径镜像场景路径 | 找文件不靠搜索 |
| R-03 | 数值只放在 `config.gd`（或后续 `resources/config/`），**禁止散落字面量** | 见 `03_rules.md#4` |
| R-04 | Autoload 只放全局状态与事件总线，且必须在 `_index.md` 登记 | 防止隐式全局依赖 |
| R-05 | 生成物（`.godot/`、导出物、临时截图）不纳入版本管理 | 已有 `.gitignore` |
| R-06 | 目录名一律英文 snake_case；**项目里已经不存在中文目录名**（`新建文件夹/bible/` 已于 2026-09-18 改名为 `docs/bible/`） | 跨平台与脚本友好 |
| R-07 | 表现层（相机 / UI）不得直接改玩法数据，只走 `Events` 或 `Game` 的公开方法 | 见 `02_entities.md#1.1` |
| R-08 | 调试脚本以 `debug_` 前缀命名，并配一个 `scenes/main/debug_*.tscn` | 便于一键回归 |

## 4. 命名规范

> ⚠️ **已迁移**：节点名 / 脚本名 / 变量名 / 信号名 / 枚举名与命名细则，全部以
> [`08_naming.md`](08_naming.md) 为唯一权威。本文件不再重复这些内容
> （遵守 `_index.md#0` 规则 3「约定只出现在一处」）。
> 不变量 I-31 ~ I-34 的出处同步指向 `08_naming.md`。

## 5. 依赖方向（防止架构腐化）

```
main ──> game ──> arena ──> unit ──> arrow
  │        │        │         │
  └────> hud      camera_rig  └──> unit_factory
                     │
        events / game_config（Autoload，任何层都可用）
```

- **只允许自上而下依赖**：`Arena` 不认识 `Game`，`Unit3D` 不认识 `Arena` 的具体类型
  （`Unit3D` 只通过 `has_method("spawn_arrow")` 找到场地，见 `unit3d.gd#_arena`）。
- **禁止循环依赖**：两个脚本互相 `preload` 即为错误，改用 `Events` 信号。
- **跨层通信**：只走 `scripts/core/events.gd`。
- ⚠️ **2026-09-25 新增的两个脚本带来的两条边**（都仍然自上而下，图不必改）：
  `main ──> start_screen`（UI 层，与 `hud` 同级）与 `main ──> start_showcase`（game 层）。
  ⚠️ `start_showcase` 是**唯一一条"不经 `Arena` 直接用单位"的路径**：它只往下用 `unit` / `unit_factory`，
  **不建 `Arena`**、不发 `Events.unit_spawned`、不进任何名单，换场时被 `main` 整棵释放。
  代价是演示里的远程单位拿不到 `_arena()` ⇒ **只拉弓、不放箭**（`05_ui_hud.md#9.3`）。
- ⚠️ **同日又多了第三条跨层边（暂停菜单的「主菜单」）**：`hud ──(Events.main_menu_requested)──> main`。
  "拆掉比赛、重建开始界面"只有装配层做得了，而 UI 层**不允许认识 `main`** ⇒ 走 `Events` 总线
  （新增的信号 `main_menu_requested` 是**请求类**，用原形动词，见 `08_naming.md#3.4`）。
  ⚠️ **暂停菜单本身没有新建文件** —— 它写进了 `ui/hud.gd`（"全部界面"那一份）。
- ⚠️ **同日还多了一条"main → 音频层"的边**：`main ──> audio_manager`（由 `main.gd#_setup_audio()` 在
  **`_ready()` 里** `new`、**全程常驻不释放** —— ⚠️ **2026-09-25 改**：此前是"随比赛创建 / 退回主菜单释放"，
  改成常驻是因为用户要求"BGM 加入**每一个界面**"，而开始界面在"一场比赛"之外 ⇒ 音频层必须活得比一场比赛长）。
  ⚠️ 它**故意不做 Autoload** —— Autoload 顺序是不变量 **I-06**，改它要先动不变量；改成常驻之后
  **I-06 仍然一个字没动**（它只是 `main` 的子节点，退回主菜单时被遍历逻辑**显式跳过**）。
  它只**听** `Events`（既有信号 + `fx_request` 的 `shot_<兵种ID>` / `lance_charge`），**不反向调用任何玩法 API** ⇒ 方向仍是自上而下。
- ⚠️ **同日还抽出 `ui/ui_style.gd`（`class_name UiStyle`）**：多了 `hud ──> ui_style` 与
  `start_screen ──> ui_style` 两条边 —— 它们**同级**，但方向是"两个界面 → 一个纯静态工具"，
  **不存在互相引用**，所以**不构成**上面说的兄弟依赖。它存在的理由恰恰是"另外两个文件不许互相依赖"
  （选项按钮的外观原先各持一份，见 `05_ui_hud.md#10.4` 与 `08_naming.md#3.3` 的补记）。
- ⚠️ **2026-09-25 第三条（模式选择 + 沙盒）新增的边**（全部仍然自上而下）：

  ```
  main ──> sandbox ──> arena        main ──> sandbox_hud ──> ui_style
    │          └────> camera_rig      │            └──────> pause_menu ──> ui_style
    └────> start_screen               └────> pause_menu（竞猜侧：hud ──> pause_menu）
  game / sandbox ──> match_pause（纯静态工具，只做"暂停 + 平移绝对时刻"）
  ```

  1. **`pause_menu` 从 `hud.gd` 里搬出来成了独立一层**（`ui/pause_menu.gd`）：它现在被
     **三套 HUD**（`hud` / `sandbox_hud` / **`roguelike_hud`，2026-09-26 起**）持有 —— 若留在 `hud.gd` 里，`sandbox_hud` 引用它就变成
     **兄弟依赖**（`07_file_layout.md#5` 只允许自上而下）⇒ 抽成同级独立文件、两边都往下依赖它。
     ⚠️ 它的**宿主契约**分两半：玩法侧只出 `pause_match()` / `resume_match()`（`Game` / `Sandbox`），
     界面侧出 `pause_allowed()` / `pause_actions()` / `pause_action()`（三套 HUD）——
     "哪个相位能唤出菜单""中间那一项叫什么"是**界面的知识**，菜单自己不猜。
  2. **`match_pause`（`core/`）**：`pause_tree()` / `resume_tree()` / `shift_deadlines()` 三个静态方法，
     三个模式**共用同一份**"树暂停 + 恢复时把暂停时长从所有绝对时刻里扣掉"（`Game` / `Sandbox` / `Roguelike`
     各自保留自己的记账字段 `_pause_from_ms`，算法只有一处）。
  3. **`game` / `sandbox` / `roguelike` 是并列的三种模式**，都由 `main` 装配、**互不认识**（后两者都不建 `Game`、
     竞猜也不建它们）；它们对 `Arena` / `CameraRig` 的用法也各自独立。
  4. ⚠️ **`sandbox ──> arena` 这条边上多了一个刻意的例外**：沙盒**不调用 `Arena.start_match()`**
     （那是"启动赛程"，会把兴奋圈 / 90 s 时限 / 僵持判平 / 平局判定一起打开），改用
     `Arena.start_skirmish()` / `stop_skirmish()`。口径见 `03_rules.md#10`。

- ⚠️ **2026-09-25 第四条（设置界面 + BGM）新增的边**：

  ```
  start_screen ──> settings_screen ──> audio_manager（core/）
  pause_menu   ──> settings_screen          ↑ 经组查找（"audio"）拿到实例
  main ──> audio_manager（改成"全程常驻"）
  ```

  1. **`settings_screen`（`ui/`）是第三个"独立一层"的界面**（同 `pause_menu` / `ui_style` 的由来）：
     它被**开始界面**与**暂停菜单**两处打开，而那两者是 `scripts/ui/` 下的**兄弟** ——
     若把它写进其中任意一个，另一个引用它就变成**兄弟依赖**（本节只允许自上而下）⇒ 抽成同级独立文件，
     两边都往下依赖它。⚠️ **它由打开它的那一层 `new()` 并挂在那一层下面**（`start_screen` 或 `pause_menu`），
     "返回"就是把自己收起来（底下那一层一直原样在）。
  2. ⚠️ **`settings_screen ──> audio_manager` 是第一条"界面 → `core/`"的边**，理由是**它调的只有音量**：
     `AudioManager` 暴露的是 `music_db() / sfx_db() / set_*_db() / preview_sfx()` —— 全是**表现层状态**
     （`AudioServer` 的总线音量）与"放一声试听"，**一个玩法数据都不碰** ⇒ **不违反 R-07**
     （R-07 管的是"表现层不得直接改**玩法**数据"）。
     ⚠️ 而"界面不认识 `main`"这条也保住了：找到音频层走的是**组查找**
     （`AudioManager.find(tree)` → `get_first_node_in_group("audio")`，与 `units` 组同一种既有做法），
     **不新增信号、也不需要 `main` 参与**。
  3. **为什么不让 `main` 直接把音频层发给界面**：那会给界面加一条"认识 `main`"的边，而
     `main_menu_requested` 那条信号当初就是为了避开它才走总线的（见上面第 3 条）。

- ⚠️ **2026-09-26 第五条（肉鸽模式）新增的边**（同样全部自上而下）：

  ```
  main ──> roguelike ──> arena        main ──> roguelike_hud ──> ui_style
    │            └────> camera_rig      │              └──────> pause_menu ──> ui_style
    │            └────> match_pause     └────> pause_menu（与 hud / sandbox_hud 同一份契约）
    └────> start_screen（第二档多一个模式按钮：肉鸽）
  ```

  1. **`roguelike` 与 `game` / `sandbox` 是并列的第三种模式**，同样由 `main` 装配、**互不认识**
     （肉鸽不建 `Game`，也不建 `Sandbox`）。
  2. ⚠️ **`roguelike ──> arena` 上照抄沙盒那个刻意的例外**：肉鸽**也从不调用 `Arena.start_match()`**，
     改用 `start_skirmish()` / `stop_skirmish()`（理由同沙盒：兴奋圈 / 90 s 时限 / 僵持判平都不是它的规则，
     见 `09_roguelike.md#1`）。
  3. **`match_pause` 的第三个调用方**：肉鸽的 `pause_match()` / `resume_match()` 与另外两个模式逐字同构
     （各自的记账字段都叫 `_pause_from_ms`，算法仍只有一处）。
  4. **`roguelike_hud` 是第三个持有 `pause_menu` 的界面**（`hud` / `sandbox_hud` / `roguelike_hud`），
     三者的界面侧契约同名同义（`pause_allowed()` / `pause_actions()` / `pause_action()`）——
     这正是 `pause_menu` 当初抽成独立一层的原因。

- ⚠️ **2026-10-18（图鉴）新增的边**：

  ```
  start_screen ──> codex_screen ──> ui_style
  pause_menu   ──> codex_screen ──> unit_factory
                         └──> game_config（Autoload，只读 profile）
  ```

  1. **`codex_screen` 与 `settings_screen` 同一条理由**：被开始界面和暂停菜单两处打开，那两者是兄弟，所以单独成文件，由打开它的那一层 `new()` 并挂在自己下面。
  2. **`codex_screen ──> unit_factory` 只取外观**。`UnitFactory.build()` 交出模型，不建 `Unit3D`，不进 `units` 组，不发 `unit_spawned`。与 `start_showcase` 那条「不经 Arena、只往下用单位工厂」同类。不改玩法数据，不违反 R-07。
  3. 七项读 `GameConfig.profile()`。图鉴不另存一份数值。

- ⚠️ **2026-10-22（设置留在本机、竞猜与生存存档）新增的边**：

  ```
  main ──> user_prefs（启动时读；静态方法，不是 Autoload）
  settings_screen ──> user_prefs（「启用」时写）
  start_screen ──> match_save（只问这份文件在不在）
  game / roguelike ──> match_save（「保存并退出」、读档、结束或重开时删）
  pause_menu ──> game 或 roguelike 的 write_resume()（暂停菜单最后一颗「保存并退出」；已有的宿主公开方法）
  ```

  1. **`UserPrefs` 与 `MatchSave` 都不进 Autoload**。Autoload 顺序仍是不变量 I-06。
  2. **`start_screen ──> match_save` 只读文件在不在**，不改场上的单位。删档发生在新的一局真正开始时，由 `Game.setup_first_round()` 或 `Roguelike.begin()` 去做。
  3. **`settings_screen ──> user_prefs` 与原先写音量、写战场勾选是同一次「启用」**。没启用的草稿不进文件。⚠️ **2026-10-22 同日** 这一下还写全屏和八个按键。

- ⚠️ **2026-10-22 同日（雪地再调浅、保存改到暂停菜单、设置分块与改键）新增的边**：

  ```
  main ──> user_prefs（启动时还读全屏和按键，仍在音频层之前）
  settings_screen ──> input_bindings（改键时改 InputMap；「启用」仍经 user_prefs 写入）
  camera_rig / unit3d / ui_style ──> input_bindings（读当前键名）
  ```

  1. **`InputBindings` 不进 Autoload**。Autoload 顺序仍是不变量 I-06。
  2. **调用 `write_resume()` 的是暂停菜单最后一颗「保存并退出」**。设置里的「退出」不调用它，也不写 `user_prefs.cfg`。
  3. **`camera_rig` / `unit3d` / `ui_style` 读的是当前绑定**。键的默认在 `project.godot` 的 InputMap，不进 `GameConfig`。

- ⚠️ **2026-10-23（战果继续的渐黑渐亮）新增的边**：

  ```
  game / sandbox / roguelike ──> screen_fade
  ```

  1. **`ScreenFade` 不进 Autoload**。三个模式各自 `ScreenFade.attach()`，挂在自己下面。层号 40，盖过 HUD。
  2. 时长与开始界面同一档（620 / 760 ms），写在这个类里，不进 `GameConfig`。与 `StartScreen` 的 `FADE_*_MS` 同一类表现常量。
  3. 黑透那一帧才调用已经有的 `next_round()` / `acknowledge_game_over()` / `roll_again()` / `restart_game()`。不暂停整棵树。

## 6. 新增文件时的操作顺序

1. 确认它属于本文件第 1/2 节的哪个目录；没有合适目录 → 先改本文件。
2. 按第 4 节命名；若是调试用，加 `debug_` 前缀。
3. 若引入新全局依赖或新数值 → 同步更新 `_index.md` 与 `03_rules.md`。
4. 若推翻既有约定 → 在 `99_decisions.md` 追加一条。
5. 新增 `.gd` 且带 `class_name` 时，必须让编辑器扫描一次才能被其他脚本引用：
   `godot --headless --editor --path . --quit`（否则报 `Identifier not declared`）。

## 7. 验证与回归

| 目的 | 命令 |
| --- | --- |
| 语法 / 类注册检查 | `godot --headless --editor --path . --quit` |
| 整局逻辑回归 | `godot --headless --path . res://scenes/main/debug_autoplay.tscn` |
| **数值平衡回归** | `godot --headless --path . res://scenes/main/debug_balance_stats.tscn` |
| 运行时状态观测 | MCP：`godot_runtime_state`（`Unit3D` / `Arena` / `CameraRig` 都实现了 `_mcp_state()`） |

## 8. 待办

- [x] ~~决定 `新建文件夹/` 是否改名~~ → **已于 2026-09-18 改名为 `docs/bible/`**（见 `99_decisions.md`）
- [ ] 音效接入后创建 `resources/audio/` 与 `assets/audio/`
- [ ] 若数值表继续膨胀，迁移到 `resources/config/*.tres`
- [ ] 若将来要让"可调参数"在编辑器里可视化，需要先给 `Arena` / `CameraRig` 建 `.tscn` 模板（当前它们都是代码 `new()` 出来的，`@export` 无处存放）
- [ ] 若数值表膨胀，迁移到 `resources/config/*.tres`
