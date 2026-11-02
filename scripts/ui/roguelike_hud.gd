class_name RoguelikeHud
extends CanvasLayer
## 肉鸽模式的界面层：**顶栏（回合 / 补给 / 血量）** + **底部行动栏（开始战斗 / 下一回合）** + 结算浮层 + 暂停菜单。
##
## 依据（用户 2026-09-26 口径）："一共10个回合，每个回合开始时会获得一定的补给…基础血量为200…
## 血量降到0及以下则失败" ⇒ 玩家在这一屏要能一眼看到**第几回合、还剩多少补给、还剩多少血**。
##
## ⚠️ **本层按"一步一步来"分步落地：第一块（骨架 + 经济记账）与第二块（商店 / 解锁 / 初始四选一 /
## 场地格子的说明）都已落地** —— 现在底部有**兵种卡**（点已解锁的卡 = 买一队、点未解锁的卡 = 解锁），
## 回合开始时还会弹一层**初始四选一**（选定之前挡住一切操作）。**只剩敌人**（界面上暂时没有敌方读数之外的体现）。
##
## ⚠️ 为什么**另起一个文件**而不是往 `hud.gd` / `sandbox_hud.gd` 里塞分支：三套界面的数据源完全不同
##（竞猜 = 轮次 / 点数 / 观望机会；沙盒 = 双方总权重 / 兵种栏；肉鸽 = 回合 / 补给 / 血量 / 兵种池），
## 共用件早已抽走：外观 → `scripts/ui/ui_style.gd`（`UiStyle`）、暂停菜单 → `scripts/ui/pause_menu.gd`。
##
## 边界同另外两套 HUD：只读 `Roguelike` 的公开状态、只调它的公开方法，不直接改玩法数据（R-07）。

const REFRESH_MS := 100                  ## 顶栏刷新节流（与另外两套 HUD 的 10 Hz 同频）
const TOP_BAR_HEIGHT := 64.0             ## 顶栏高度 px（与沙盒顶栏同高）
## ⚠️ **2026-09-27 第四轮（用户："操作过多导致操作界面的 ui 挡住了太多画面，现对 ui 进行优化，
## 不要全挤在上面或下面"）**：底栏从 **300 px 收到 150 px**，卡片全部搬去两侧与顶部 —— 见下面四个
## 定位常量。`ACTION_PANEL_HEIGHT` 这个名字**保留**（它仍是那块底部条的高度、`UndoToastLabel` 也按它算偏移）。
const ACTION_PANEL_HEIGHT := 110.0       ## 底部条高度 px（第五轮 150 → 110：按钮搬去顶部、商店搬去右下）
const SIDE_PANEL_TOP := 76.0             ## 两侧面板的顶边距 px（贴顶栏下沿）
const SIDE_PANEL_WIDTH := 250.0          ## 两侧"道具"面板宽度 px（左上信标 / 右上陷阱魔法盾）
const START_BAR_TOP := 76.0              ## 顶部中央那条（自由视角 / 开始战斗 / 撤销）的顶边距 px
## ⚠️ **2026-09-27 第五轮**：用户"减小『开始战斗』按钮的大小" + "购买单位的界面做到右下角" ⇒
## 顶部那颗从 `UiStyle.MIN_SIZE`（280 × 66）缩到 `START_BUTTON_SIZE`，商店从右上搬到右下并加宽成 4 列。
const START_BUTTON_SIZE := Vector2(200.0, 54.0)
const START_BUTTON_FONT := 24            ## 「开始战斗」的字号（`UiStyle.FONT` = 30 太大）
const SIDE_BUTTON_SIZE := Vector2(120.0, 44.0)   ## 「自由视角」/「撤销」：**两者同尺寸**（用户要求一致），且比开始战斗小
## 底部那一排的统一下边距 px（底栏与两块角面板都贴这条线 ⇒ 不再有"面板下面还空一截"）。
const BOTTOM_INSET := 16.0
## ⚠️ **第七轮 470 → 430**：两块面板落到与底栏同一条底线之后，必须给中间那条提示条（居中 674 宽）
## 让出位置 —— 430 宽时商店左缘 = 1600 − 16 − 430 = **1154**，提示条右缘 = **1137** ⇒ 留 17 px 缝。
## 4 列卡因此从 ~110 px 缩到 ~96 px（5 字兵种名仍放得下）。
const SHOP_PANEL_WIDTH := 430.0
## ⚠️ **2026-09-27 第六轮**：底部那两条提示缩到中间、两侧让给面板，并加一颗折叠按钮。
const HINT_BLOCK_WIDTH := 580.0          ## 提示文字那一块的宽度 px（两条提示都按这个宽度折行）
const COLLAPSED_BAR_HEIGHT := 44.0       ## 提示收起后底栏的高度 px（只留那颗折叠按钮）
## ⚠️ **2026-09-26 经用户裁决改名**：`SHOP_COLUMNS` → **`CHIP_COLUMNS`** —— 当时沙盒兵种栏里同一个概念
## （兵种卡一行几张）叫的就是 `CHIP_COLUMNS`，而本文件的卡片节点本来就叫 `Chip_<兵种ID>` / `ChipGrid`
## ⇒ 旧名与自己的节点名自相矛盾（§1.4「同一概念全局同名」，见本批 `08_naming.md` 审计）。
## ⚠️ **2026-09-27 第十一轮**：沙盒兵种栏改成了**单排横向滚动**（不再是网格）⇒ 那边这个常量**已删除**，
## 本文件是它**唯一**的出处（名字照旧，概念在本文件里仍然是"一行几张"）。
const CHIP_COLUMNS := 3                  ## 兵种卡一行几张（⚠️ 第九轮 4 → **3**：见 `CARD_MIN_WIDTH`）
## ⚠️ **2026-09-27 第九轮修 bug**（用户："购买兵种界面那边的按钮有些兵种在鼠标移上去的时候会改变大小
## （如心灵腐化师、玉面手雷王、轻骑兵（矛））"）：卡片的 `custom_minimum_size.x` 原先给的是 **0**，
## 于是"最小宽度跟着文字走" —— 实测「心灵腐化师」（6 字 × 字号 18 + 内边距 12）= **102 px**，
## 悬停时文字换成「10 补给」（约 75 px）⇒ 这一列的宽度当场缩回去、**整个网格重排**，
## 玩家就看到"鼠标一移上去按钮变大/变小"。⇒ 现在**所有卡给同一个固定最小宽度**：
## 6 个汉字（当前最长的兵种名）× 18 px + 12 px 内边距 = **120 px** ⇒ 文字再怎么换都不动布局。
const CARD_MIN_WIDTH := 120.0
const CARD_MIN_HEIGHT := 34.0            ## 卡高（单行文字）
const CARD_SEPARATION := 8               ## 卡片间距 px（⚠️ 2026-09-27 第四轮 14 → **8**：卡片搬进侧栏变窄了）
const BUFF_PANEL_TOP := 168.0            ## 指挥所增益 / 队伍面板的顶边距 px
## ⚠️ **2026-09-27 第五轮 80 → 168**：用户要求「移动信标」那一栏放到**左上角**，而左上角原本是这两块
## 浮动面板的地盘 ⇒ 把浮动面板整体下移一行半（用户口径优先，且两块面板只在选中时才出现）。
const BUFF_PANEL_WIDTH := 330.0          ## 面板里说明文字那一列的宽度 px（换行用）
const BUFF_LABEL_WIDTH := 210.0          ## 每一行"名字 + 效果"那一列的宽度 px
## ⚠️ `CARD_SEPARATION` **刻意不改名**（同上审计的登记项）：当时沙盒那一侧是**内联的 14、没有对应常量**
## ⇒ 它不构成"同一概念两个名字"；要严格统一成 `CHIP_SEPARATION` 属于另一件事。
## ⚠️ **2026-09-27 第十一轮补记**：沙盒兵种栏改成单排滚动时**把那个 14 提成了常量**
##（`sandbox_hud.gd#CHIP_ROW_SEPARATION`）⇒ 现在两侧**各有一个"卡片间距"常量、名字不同**
##（本文件的 `CARD_SEPARATION` = 8、沙盒的 `CHIP_ROW_SEPARATION` = 14）。
## 值本来就不同（一个在窄侧栏、一个在通栏底栏）⇒ **不是同一个数**，但"同一概念两个名字"这条**现在成立了**
## ⇒ 登记待办：真要统一，得同时决定"统一成哪个名字"与"要不要连值一起统一"（本批不动）。

const FONT_LARGE := UiStyle.FONT_LARGE
const FONT_MID := UiStyle.FONT_MID
const FONT_SMALL := UiStyle.FONT_SMALL
const FONT_TINY := UiStyle.FONT_TINY
const COLOR_TEXT := UiStyle.COLOR_TEXT
const COLOR_DIM := UiStyle.COLOR_DIM
const COLOR_WARN := UiStyle.COLOR_WARN
const COLOR_OK := UiStyle.COLOR_OK

var roguelike: Roguelike = null
var camera_rig: CameraRig = null

var _mode_label: Label = null
var _round_label: Label = null
var _supply_label: Label = null
var _hp_label: Label = null
var _foe_label: Label = null             ## 敌方存活权重（本步恒为 0；敌人落地后它才有读数）
var _zone_label: Label = null            ## 两条布阵带（南北长边外侧）的一句话口径（2026-09-27 第七块）
var _squads_label: Label = null          ## 本回合已买几队（第二块新增：上限 `ROGUELIKE_SQUADS_PER_ROUND`）
var _gear: Button = null
## 倍速按钮（2026-11-01）：顶栏右端、齿轮左边。外观与接线在 `UiStyle.make_speed_button()`（三套 HUD 共用）。
## ⚠️ 生存模式的倍速只加速**战斗本身**（回合 / 结算的计时不在那条链上，见 `MatchSpeed` 文件头）。
var _speed_button: Button = null

var _action_panel: PanelContainer = null
var _start_bar: PanelContainer = null    ## 顶部中央那颗「开始战斗 / 下一回合」的外壳（2026-09-27 第四轮搬上去）
var _start_button: Button = null
var _next_button: Button = null
var _overview_button: Button = null
var _hint: Label = null

## ---- 2026-09-27 第四轮：界面重排（卡片搬去两侧）----
var _prop_panel: PanelContainer = null   ## 右上角的场地道具面板（陷阱 / 魔法盾）
var _beacon_panel: PanelContainer = null ## 左上角的移动信标面板（买过才显示）
var _hint_box: HBoxContainer = null      ## 底栏中央那块「折叠按钮 + 两行提示」（第六轮）
var _hint_col: VBoxContainer = null      ## 两行提示（收起时只隐藏这一列，按钮留着）
var _hint_fold: Button = null            ## 折叠按钮（提示块的左上角）
var _hints_open: bool = true             ## 提示现在是展开还是收起（用户："按一下隐藏，再按一下打开"）
var _shop_panel: PanelContainer = null   ## 右侧"已解锁兵种"面板
var _prop_panels: Dictionary = {}        ## kind -> 该卡片要挂进去的 VBox（信标走左上、陷阱/魔法盾走右上）
var _prop_base_text: Dictionary = {}     ## 道具卡：常态文字（名字）
var _prop_hover_text: Dictionary = {}    ## 道具卡：悬停文字（价格 / "点一下免费重放"）
var _unlock_button: Button = null        ## 「解锁单位」（点开未解锁单位那一栏）
var _unlock_panel: PanelContainer = null ## 未解锁单位列表（居中弹层）
var _unlock_hint: Label = null
var _unlock_grid: GridContainer = null
var _unlock_cards: Dictionary = {}       ## 兵种 ID → 解锁卡按钮
var _unlock_close: Button = null
var _unlock_open: bool = false           ## 玩家是否点开了那一栏
## ⚠️ 卡片文案**两套**：常态 = 兵种名（缩到最小），悬停 = 所需补给（用户口径（2）："单位的按钮（购买和解锁）
## 只列出单位名字，鼠标移上去时将内容变为所需补给数，以此缩小按钮大小"）。刷新时按 `is_hovered()` 二选一。
var _chip_base_text: Dictionary = {}
var _chip_hover_text: Dictionary = {}

## ---- 兵种科技（2026-09-27 第十二轮）----
## 结构（用户口径："选中兵种卡后弹出的界面在下方有 4 个按钮，鼠标移上去后按钮内容变消耗补给数，
## 并另有提示技能效果"）⇒ `[三张兵种卡（选兵种）]` + `[四个科技按钮]` + `[效果提示行]` + `[关闭]`。
var _tech_button: Button = null          ## 商店底部那颗「兵种科技」
var _tech_panel: PanelContainer = null   ## 弹层本体（居中，与解锁栏同一套做法）
var _tech_hint: Label = null             ## 面板顶部那行说明 / 底部那行"效果提示"
var _tech_effect: Label = null           ## 悬停某个科技时显示它的效果（用户要的"另有提示技能效果"）
var _tech_type_grid: GridContainer = null## 上方那一排兵种卡
var _tech_type_cards: Dictionary = {}    ## 兵种 ID → 选兵种卡
var _tech_grid: GridContainer = null     ## 下方那四个科技按钮的容器
var _tech_buttons: Array = []            ## 与"当前选中兵种的科技清单"逐位对应（刷新时只改文字/禁用态）
var _tech_open: bool = false
var _tech_selected: String = ""          ## 当前选中的兵种 ID（空 = 还没选）

## ---- 第二块：商店（兵种卡）与初始四选一 ----
var _shop_box: VBoxContainer = null
var _shop_status: Label = null           ## "本回合还可买 N 队 · 已解锁 K / M"
var _shop_message: Label = null          ## 最近一次买卖的结果 / 被拒绝的原因（玩法侧给的文案）
var _chips: Dictionary = {}              ## 兵种 ID → 卡片按钮（刷新时只改文字与颜色，**不重建**）
## ⚠️ **2026-09-26 经用户裁决改名**：`_cards` → **`_chips`** —— 与 `SandboxHud._chips` 同名同义
##（同一个概念：兵种 ID → 卡片按钮的字典），见本批 `08_naming.md` 审计。
var _starter_scrim: ColorRect = null
var _starter_buttons: Array[Button] = []
var _difficulty_scrim: ColorRect = null
var _difficulty_buttons: Array[Button] = []
var _aid_scrim: ColorRect = null
var _aid_buttons: Array[Button] = []
var _aid_skip: Button = null
var _aid_tray: HBoxContainer = null
var _aid_prop_box: VBoxContainer = null
var _aid_card_sig: Dictionary = {}

## ---- 第三块：指挥所增益面板（点场地上的指挥所才出现）----
var _buff_panel: PanelContainer = null
var _buff_title: Label = null
var _buff_note: Label = null             ## 我方两座指挥所的血量 + 减益警告
var _buff_rows: Dictionary = {}          ## kind -> {"row": Control, "label": Label, "button": Button}
## 第六块：**移动信标**那一行（右方指挥所卖的道具，与上面那些"等级增益"不是一回事 ⇒ 单独一组控件）
var _beacon_row: HBoxContainer = null
var _beacon_label: Label = null
var _beacon_button: Button = null
var _recall_row: HBoxContainer = null
var _recall_label: Label = null
var _recall_button: Button = null
var _recall_card: Button = null

## ---- 第五块：场地道具（陷阱 / 魔法盾）的卡片 ----
var _prop_cards: Dictionary = {}         ## kind -> Button（**按住 = 进入拖放**，不是点买）

## ---- 第四块：选中队伍面板（点我方单位才出现；与上面那块**互斥地占同一片角落**）----
var _squad_panel: PanelContainer = null
var _squad_title: Label = null
var _squad_body: Label = null            ## 最终数值（攻击 / 血量 / 射程 / 移速…，增益已算进去）
var _squad_note: Label = null            ## 增益来路 + "能不能拖 / 当前横竖"
var _squad_upgrade: Button = null        ## 升级按钮（2026-09-27 第三轮：经验满 + 准备阶段才可按）
var _squad_upgrade_all: Button = null    ## 把现在升得起的同类型队伍一次升完
var _deploy_hint: Label = null           ## 底部右栏那行布阵操作提示（第四块新增）
var _undo_button: Button = null          ## 撤销按钮（2026-09-27 第三轮）
var _undo_toast: Label = null            ## 撤销时**屏幕中央**那一行字（纯表现，2.6 s 后自己消失）

var _overlay: Control = null
var _top_bar: PanelContainer = null
var _eye_button: Button = null
var _eye_hint: Label = null
var _choice_notice: Label = null
var _overlay_title: Label = null
var _overlay_body: Label = null
var _overlay_button: Button = null

var _pause: PauseMenu = null
var _refresh_ms: int = 0

func build(p_roguelike: Roguelike, p_camera: CameraRig) -> void:
	roguelike = p_roguelike
	camera_rig = p_camera
	## ⚠️ 与另外两套 HUD 同一个理由：暂停菜单（含它的渐暗 / 渐亮）必须在"整棵树暂停"时照样跑。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	_pause.configure(roguelike, self)    ## `Roguelike` 管暂停 / 恢复，本层管"哪一项能出现"
	_build_top_bar()
	_build_action_panel()
	_build_overlay()
	_build_starter()
	_build_difficulty()
	_build_buff_panel()
	_build_squad_panel()
	_build_undo_toast()
	_build_aid()
	_build_choice_eye()
	roguelike.phase_changed.connect(_on_phase_changed)
	_refresh()

# ---------------------------------------------------------------- 顶栏（回合 / 补给 / 血量）
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	_top_bar = bar
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.34, 0.40, 1.0)
	style.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	var row := HBoxContainer.new()
	row.name = "TopBarRow"               ## §3.1：动态生成的节点也必须命名（齿轮挂在这一行里）
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	_mode_label = _make_label("生存模式", FONT_MID, COLOR_DIM, "ModeLabel")
	row.add_child(_mode_label)
	_round_label = _make_label("", FONT_MID, COLOR_TEXT, "RoundLabel")
	row.add_child(_round_label)
	## 2026-11-01（用户："补给和生命感觉有点不太明显，可以加个图案后跟数字"）：
	## 两格都改成 **图案 + 数字**。图案由 `UiStyle` 程序化画（零外部资源，与齿轮同一套做法），
	## 文字只留数字 —— 图案本身已经说明是哪一样。⚠️ 节点**只建一次**（`05_ui_hud.md#7.1`），
	## 刷新只改 `_supply_label` / `_hp_label` 的 `text`。
	var supply_row := UiStyle.make_icon_label(UiStyle.supply_texture(), "", FONT_MID, COLOR_WARN, "SupplyRow")
	_supply_label = (supply_row["label"] as Label)
	_supply_label.name = "SupplyLabel"          ## 沿用旧节点名：文档与自检里按这个名字找它
	(supply_row["root"] as Control).tooltip_text = "补给：买兵 / 解锁 / 升级 / 增益 / 道具 / 遣返"
	row.add_child(supply_row["root"] as Node)
	var hp_row := UiStyle.make_icon_label(UiStyle.heart_texture(), "", FONT_MID, COLOR_OK, "HpRow")
	_hp_label = (hp_row["label"] as Label)
	_hp_label.name = "HpLabel"
	(hp_row["root"] as Control).tooltip_text = "生命：回合结束时没拦住的敌人会扣它，归零即失败"
	row.add_child(hp_row["root"] as Node)
	## 本回合的购买额度（第二块新增）："每回合最多买 2 队"是玩家花钱时最要紧的一条约束。
	_squads_label = _make_label("", FONT_SMALL, COLOR_DIM, "SquadsLabel")
	row.add_child(_squads_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	## 敌方读数（本步恒为 0，见 `Roguelike.enemy_weight()` 的说明）：留着它是为了让"敌人落地"那一刻
	## 这一行**不用改结构**就有读数。
	_foe_label = _make_label("", FONT_SMALL, COLOR_DIM, "FoeLabel")
	row.add_child(_foe_label)
	## 第七块：两条**布阵带**（南北长边外侧）的一句话说明（塞在顶栏里 ⇒ **不占额外高度**，见 `DeployHintLabel` 那段的注）
	_zone_label = _make_label("", FONT_TINY, COLOR_DIM, "ZoneLabel")
	row.add_child(_zone_label)

	## 倍速（2026-11-01）：插在齿轮左边（齿轮是顶栏最右一格）。
	## ⚠️ 倍速**常显**（2026-11-01 修 bug：用户"战斗开始后无法点加速"）：
	## 战斗中正要用它，而那时光标被 `CameraRig` 锁住 ⇒ 靠快捷键 `F` 切（见 `UiStyle`），
	## 按钮本身必须一直亮着（`Button.shortcut` 只在可见时才派发），顺便让人看见当前是几倍。
	_speed_button = UiStyle.make_speed_button("SpeedButton")
	row.add_child(_speed_button)

	_gear = Button.new()
	_gear.name = "GearButton"
	UiStyle.decorate_gear(_gear)         ## 与另外两套 HUD 是**同一个**齿轮（`UiStyle` 里只有一份）
	_gear.visible = false                ## 只在"光标可见"的相位显示（见 `_refresh_top()`）
	_gear.pressed.connect(_pause.open)
	row.add_child(_gear)

# ---------------------------------------------------------------- 四块界面（重排历史）
## 第四轮（用户："操作过多导致操作界面的 ui 挡住了太多画面，不要全挤在上面或下面"）先把底栏 300 → 150、
## 卡片搬去两侧；**第五轮再按用户新口径收到这里**：
##   · **顶部中央** `StartBar`：`[自由视角] [开始战斗] [撤销]` —— 后两颗在"开始战斗"两边、比它小且**同尺寸**
##   · **左上角** `BeaconPanel`：「移动信标」道具卡 —— ⚠️ **买过才显示**（`has_beacon()`）
##   · **右上角** `PropPanel`：陷阱 / 魔法盾 —— 卡上只写名字，**悬停才显示价格**
##   · **右下角** `ShopPanel`：「购买单位」那一栏（已解锁兵种 + 状态 + 「解锁单位」）
##   · **底部细条** `ActionPanel`（110 px）：布阵提示 + 相机提示（按钮都搬走了）
## ⚠️ 卡片**一次建好、永不重建**（同既有硬规则）：刷新只改 `text` / `visible` / `modulate`。
## ⚠️ **悬停一律不放大**（用户第五轮："肉鸽模式所有按钮鼠标移上去的时候大小不要变"）⇒ 全层走 `_hover()`。
func _build_action_panel() -> void:
	_build_start_bar()
	_build_left_column()
	_build_prop_panel()
	_build_shop_panel()
	_build_bottom_bar()
	_build_unlock_panel()
	_build_tech_panel()

## 顶部中央：本回合那颗大按钮 + 它两边的两颗小按钮
## （用户 2026-09-27 第五轮："减小『开始战斗』按钮的大小，将『自由视角』和『撤销』移至『开始战斗』两边
##  （大小比『开始战斗』小，且这两个按钮大小一致）"）。
## ⚠️ `StartButton` / `NextRoundButton` 两个相位二选一，占**同一个位置**（中间那一格）。
func _build_start_bar() -> void:
	_start_bar = PanelContainer.new()
	_start_bar.name = "StartBar"
	_start_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_start_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_start_bar.offset_top = START_BAR_TOP
	_start_bar.add_theme_stylebox_override("panel", _bar_style(0.86))
	add_child(_start_bar)
	var box := HBoxContainer.new()
	box.name = "StartBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	_start_bar.add_child(box)

	## 左边那颗：「自由视角」（与下面「撤销」同尺寸 —— 用户要求两者一致）
	_overview_button = Button.new()
	_overview_button.name = "OverviewButton"
	_overview_button.text = "自由视角"
	_overview_button.tooltip_text = "进入自由视角（隐藏界面、隐藏光标；鼠标转向，点左键或右键退出）"
	UiStyle.decorate_chip(_overview_button)
	_overview_button.custom_minimum_size = SIDE_BUTTON_SIZE
	_overview_button.mouse_entered.connect(_hover.bind(_overview_button, true))
	_overview_button.mouse_exited.connect(_hover.bind(_overview_button, false))
	_overview_button.pressed.connect(_on_overview_pressed)
	box.add_child(_overview_button)

	## 中间那颗：「开始战斗」：与开始界面的「开始游戏」同一种外观（同一份 `UiStyle.decorate_option`），
	## 但**尺寸与字号都缩小**（第五轮用户要求）。
	_start_button = Button.new()
	## ⚠️ **2026-09-26 经用户裁决改名**：`StartBattleButton` → **`StartButton`** —— 与 `SandboxHud` 里那个"开战按钮"
	## 逐字同名（同一件事只允许一个名字，§1.4）。⚠️ **界面上显示的文字仍是「开始战斗」** —— 那是文案，不是标识符。
	_start_button.name = "StartButton"
	_start_button.text = "开始战斗"
	_start_button.tooltip_text = "让本回合的进攻开始（本步还没有敌人 ⇒ 会立刻结算）"
	UiStyle.decorate_option(_start_button)
	_start_button.custom_minimum_size = START_BUTTON_SIZE
	_start_button.add_theme_font_size_override("font_size", START_BUTTON_FONT)
	_start_button.mouse_entered.connect(_hover.bind(_start_button, true, true))
	_start_button.mouse_exited.connect(_hover.bind(_start_button, false, true))
	_start_button.pressed.connect(_on_start_battle_pressed)
	box.add_child(_start_button)

	## 「下一回合」：结算浮层的那个按钮的**同义副本**（浮层黑着的时候它更方便，故两处都留）。
	## ⚠️ 它与「开始战斗」**占同一格**（同一相位二选一），所以尺寸也照抄那一套。
	_next_button = Button.new()
	_next_button.name = "NextRoundButton"
	_next_button.text = "下一回合"
	_next_button.tooltip_text = "领下一回合的补给（第 10 回合之后整局结束）"
	UiStyle.decorate_option(_next_button)
	_next_button.custom_minimum_size = START_BUTTON_SIZE
	_next_button.add_theme_font_size_override("font_size", START_BUTTON_FONT)
	_next_button.mouse_entered.connect(_hover.bind(_next_button, true, true))
	_next_button.mouse_exited.connect(_hover.bind(_next_button, false, true))
	_next_button.pressed.connect(_on_next_round_pressed)
	box.add_child(_next_button)

	## 右边那颗：「撤销」（2026-09-27 第四轮新增，第五轮搬到顶栏右格）
	## 能不能按由玩法侧的 `undo_depth()` 决定；文字里的 N = 还能撤几步。
	_undo_button = Button.new()
	_undo_button.name = "UndoButton"
	_undo_button.text = "撤销"
	_undo_button.tooltip_text = "撤销本回合的上一次操作（买兵 / 升级 / 换位 / 买增益 / 买道具 / 放信标 / 画路线）；快捷键 Ctrl+Z"
	UiStyle.decorate_chip(_undo_button)
	_undo_button.custom_minimum_size = SIDE_BUTTON_SIZE
	_undo_button.mouse_entered.connect(_hover.bind(_undo_button, true))
	_undo_button.mouse_exited.connect(_hover.bind(_undo_button, false))
	_undo_button.pressed.connect(_on_undo_pressed)
	box.add_child(_undo_button)

## 悬停：**换字色但不放大**（用户 2026-09-27 第五轮："肉鸽模式所有按钮鼠标移上去的时候大小不要变"）。
## ⚠️ 为什么是"调完再把 `scale` 拉回去"而不是自己抄一遍字色：四档字色与缩放写在 `UiStyle._apply_hover()`
## 的**同一个函数体**里，而那个函数同时服务另外两套 HUD（用户只要求改肉鸽）⇒ 复用它的字色口径、
## 只把"要不要放大"这一件事收回来。⚠️ 这样"颜色的唯一出处"仍然是 `UiStyle`（§1.4）。
func _hover(button: Button, hovered: bool, as_option: bool = false) -> void:
	if as_option:
		UiStyle.apply_option_hover(button, hovered)
	else:
		UiStyle.apply_chip_hover(button, hovered)
	button.scale = Vector2.ONE

## 左上角：**移动信标**那一栏。信标卡买过才出现，遣返卡买过才出现。
## 援助给的战场道具也挂在这一栏，不再另开底栏。
## 显隐由 `_refresh_shop()` 把关：有信标、有遣返，或手里还有战场道具，才露出。
## ⚠️ 增益 / 队伍两块浮动面板因此下移到 `BUFF_PANEL_TOP` = 168，免得与它叠在一起。
func _build_left_column() -> void:
	_beacon_panel = PanelContainer.new()
	_beacon_panel.name = "BeaconPanel"
	_beacon_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_beacon_panel.offset_left = 16.0
	_beacon_panel.offset_top = SIDE_PANEL_TOP
	_beacon_panel.add_theme_stylebox_override("panel", _bar_style(0.90))
	_beacon_panel.visible = false
	add_child(_beacon_panel)
	var box := VBoxContainer.new()
	box.name = "BeaconBox"
	box.add_theme_constant_override("separation", 8)
	_beacon_panel.add_child(box)
	box.add_child(_make_label("道具（按住卡片拖出去）", FONT_TINY, COLOR_DIM, "BeaconHintLabel"))
	_prop_panels[GameConfig.ROGUELIKE_PROP_BEACON] = box
	_recall_card = Button.new()
	_recall_card.name = "RecallCard"
	UiStyle.decorate_chip(_recall_card)
	_recall_card.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - 40.0, 40.0)
	_recall_card.text = "遣返"
	_recall_card.button_down.connect(_on_recall_card_pressed)
	_recall_card.mouse_entered.connect(_hover.bind(_recall_card, true))
	_recall_card.mouse_exited.connect(_hover.bind(_recall_card, false))
	box.add_child(_recall_card)
	_aid_prop_box = VBoxContainer.new()
	_aid_prop_box.name = "AidPropBox"
	_aid_prop_box.add_theme_constant_override("separation", 8)
	_aid_prop_box.visible = false
	box.add_child(_aid_prop_box)

## 右边缘（上）：两张**场地道具**（陷阱 / 魔法盾）
func _build_prop_panel() -> void:
	_prop_panel = PanelContainer.new()
	_prop_panel.name = "PropPanel"
	_prop_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_prop_panel.offset_right = -16.0
	_prop_panel.offset_top = SIDE_PANEL_TOP
	_prop_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_prop_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0.0)
	_prop_panel.add_theme_stylebox_override("panel", _bar_style(0.90))
	add_child(_prop_panel)
	var props := VBoxContainer.new()
	props.name = "PropBox"
	props.add_theme_constant_override("separation", 8)
	_prop_panel.add_child(props)
	props.add_child(_make_label("场地道具（按住卡片拖到场上松手放置）", FONT_TINY, COLOR_DIM, "PropHintLabel"))
	for kind in [GameConfig.ROGUELIKE_PROP_TRAP, GameConfig.ROGUELIKE_PROP_SHIELD]:
		_prop_panels[String(kind)] = props

## **右下角**（用户第七轮："兵种购买界面移至右下角" —— 与"选中单位"对调）
func _build_shop_panel() -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_shop_panel.offset_right = -16.0
	_shop_panel.offset_bottom = -BOTTOM_INSET
	_shop_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_shop_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_shop_panel.custom_minimum_size = Vector2(SHOP_PANEL_WIDTH, 0.0)
	_shop_panel.add_theme_stylebox_override("panel", _bar_style(0.90))
	add_child(_shop_panel)
	var left := VBoxContainer.new()
	left.name = "ShopBox"
	left.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(left)
	_shop_box = left
	## ⚠️ **第四轮起列表里只列已解锁**的兵种（用户："未解锁单位不要列出来，而是有一个专门的『解锁单位』按钮"）
	## ⇒ 未解锁的那一栏搬进了 `UnlockPanel`（见 `_build_unlock_panel()`）。
	_shop_status = _make_label("", FONT_TINY, COLOR_WARN, "ShopStatusLabel")
	left.add_child(_shop_status)
	_shop_message = _make_label("", FONT_TINY, COLOR_DIM, "ShopMessageLabel")
	_shop_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_message.custom_minimum_size = Vector2(SHOP_PANEL_WIDTH - 40.0, 0.0)
	left.add_child(_shop_message)

	var grid := GridContainer.new()
	grid.name = "ChipGrid"
	grid.columns = CHIP_COLUMNS
	grid.add_theme_constant_override("h_separation", CARD_SEPARATION)
	grid.add_theme_constant_override("v_separation", CARD_SEPARATION)
	left.add_child(grid)
	## ⚠️ 顺序**按权重从小到大**（与沙盒兵种栏同一套口径，用户 2026-09-25："兵种按权重大小排列"）。
	for type_id in _types_by_weight():
		_add_card(grid, String(type_id))

	## 「解锁单位」：点开才出现那一栏未解锁的兵种（用户第四轮口径（1））
	_unlock_button = Button.new()
	_unlock_button.name = "UnlockButton"
	_unlock_button.text = "解锁单位"
	_unlock_button.tooltip_text = "打开未解锁兵种的列表（每回合最多解锁 %d 个）" % GameConfig.ROGUELIKE_UNLOCK_PER_ROUND
	UiStyle.decorate_chip(_unlock_button)
	_unlock_button.custom_minimum_size = Vector2(0.0, 38.0)
	_unlock_button.mouse_entered.connect(_hover.bind(_unlock_button, true))
	_unlock_button.mouse_exited.connect(_hover.bind(_unlock_button, false))
	_unlock_button.pressed.connect(_on_unlock_pressed)
	left.add_child(_unlock_button)

	## 「兵种科技」（2026-09-27 第十二轮）：与「解锁单位」并列的第二颗按钮。
	## ⚠️ 为什么另起一颗而不是"点兵种卡顺带弹"：商店卡**点一下就是买一队**（这是它的主功能），
	## 再让它兼任"开科技面板"必然互相打断。⇒ 面板里自带"选兵种"那一排卡（用户口径原话是
	## "选中兵种卡后弹出的界面在下方有 4 个按钮" ⇒ 面板结构 = 上方选兵种、下方 4 个科技按钮 ✓）。
	_tech_button = Button.new()
	_tech_button.name = "TechButton"
	_tech_button.text = "兵种科技"
	_tech_button.tooltip_text = "给某个兵种买科技（本局永久、所有同兵种立即生效）"
	UiStyle.decorate_chip(_tech_button)
	_tech_button.custom_minimum_size = Vector2(0.0, 38.0)
	_tech_button.mouse_entered.connect(_hover.bind(_tech_button, true))
	_tech_button.mouse_exited.connect(_hover.bind(_tech_button, false))
	_tech_button.pressed.connect(_on_tech_pressed)
	left.add_child(_tech_button)

	## 道具卡：按 kind 分派到左上（信标）/ 右上（陷阱、魔法盾）—— 见 `_build_prop_cards()`
	_build_prop_cards()

## 底部细条：**只包住中间那两条提示**（用户第七轮："你文字在中间了旁边两边这么空不会删掉吗"
## ⇒ 底栏不再通栏，改成"按内容收缩 + 屏幕居中"的窄条：两侧不再留大片空暗条，场地直接露出来）。
## 结构 = `[折叠按钮][两行提示]`，整块居中；收起时连高度一起收（`COLLAPSED_BAR_HEIGHT`）。
## ⚠️ 两块角面板（左下"选中单位" / 右下"兵种购买"）都在**这条的上方**（底边比它高 8 px）⇒
## 彼此不重叠，所以提示块两侧**不需要**再留"保留区"（`HINT_PAD_*` 两个常量已随本轮删除）。
func _build_bottom_bar() -> void:
	_action_panel = PanelContainer.new()
	_action_panel.name = "ActionPanel"
	_action_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_panel.offset_bottom = -16.0
	_action_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_panel.add_theme_stylebox_override("panel", _bar_style(0.93))
	add_child(_action_panel)

	var row := HBoxContainer.new()
	row.name = "ActionRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_action_panel.add_child(row)

	_hint_box = HBoxContainer.new()
	_hint_box.name = "HintBox"
	_hint_box.add_theme_constant_override("separation", 10)
	row.add_child(_hint_box)

	## 折叠按钮：**在提示块的左上角**（`SIZE_SHRINK_BEGIN` = 贴着这一行的顶边）
	_hint_fold = Button.new()
	_hint_fold.name = "HintFoldButton"
	_hint_fold.text = "收起"
	_hint_fold.tooltip_text = "收起 / 展开这两行提示"
	UiStyle.decorate_chip(_hint_fold)
	_hint_fold.custom_minimum_size = Vector2(64.0, 28.0)
	_hint_fold.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_hint_fold.mouse_entered.connect(_hover.bind(_hint_fold, true))
	_hint_fold.mouse_exited.connect(_hover.bind(_hint_fold, false))
	_hint_fold.pressed.connect(_on_hint_fold_pressed)
	_hint_box.add_child(_hint_fold)

	_hint_col = VBoxContainer.new()
	_hint_col.name = "HintCol"
	_hint_col.add_theme_constant_override("separation", 4)
	_hint_box.add_child(_hint_col)

	## 第四块：布阵操作提示（用户口径③④⑤ 三条操作在这里一次说清）
	_deploy_hint = _make_label("布阵：点我方单位 = 选中看数值 · 按住拖动 = 换位置（只有本回合买的兵能拖）\n"
			+ "拖动到放不下的地方会标红，松手留在原位 · 拖动中按右键 = 布阵旋转 90°（朝向不变）",
			FONT_TINY, COLOR_DIM, "DeployHintLabel")
	_deploy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deploy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deploy_hint.custom_minimum_size = Vector2(HINT_BLOCK_WIDTH, 0.0)
	_hint_col.add_child(_deploy_hint)

	_hint = _make_label(UiStyle.camera_hint(), FONT_TINY, COLOR_DIM, "CameraHintLabel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(HINT_BLOCK_WIDTH, 0.0)
	_hint_col.add_child(_hint)

## 折叠 / 展开那两条提示（用户："按一下隐藏，再按一下打开"）。⚠️ **按钮自己始终留着** ——
## 否则收起之后就没有东西可以再点开。
func _on_hint_fold_pressed() -> void:
	_hints_open = not _hints_open
	_refresh()

## 底部条**当前**高度：提示收起时只留那一颗折叠按钮（场地多出 `ACTION_PANEL_HEIGHT − COLLAPSED_BAR_HEIGHT`）
func _bar_height() -> float:
	return ACTION_PANEL_HEIGHT if _hints_open else COLLAPSED_BAR_HEIGHT

## 把所有"挂在底部条之上"的面板重新贴一遍。
## ⚠️ **第七轮（用户："选中单位跳出来的那个界面和兵种购买界面不是还能往下移吗"）**：
## 底栏收成"只包住文字"的窄条之后，它两侧那一整条高度就空出来了 ⇒ 两块面板**落到与底栏同一条底线**
##（`BOTTOM_INSET` = 16，与底栏一样），左右夹住中间那条提示，底部这一排不再有空白。
## ⚠️ 代价是"面板宽度 + 提示条宽度"必须放得下：提示条居中 674 宽（`HINT_BLOCK_WIDTH` 580 + 按钮），
## 商店 430 宽 ⇒ 左右各留出 ≥ 20 px 的缝（见 `SHOP_PANEL_WIDTH` 的注）。
func _apply_bottom_anchors() -> void:
	if _action_panel != null:
		_action_panel.offset_top = -_bar_height()
	if _shop_panel != null:
		_shop_panel.offset_bottom = -BOTTOM_INSET
	if _squad_panel != null:
		_squad_panel.offset_bottom = -BOTTOM_INSET

## 一个"侧栏/顶栏"用的面板底样式（与底栏同一套配色，只是透明度略高）
func _bar_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, alpha)
	style.border_color = Color(0.32, 0.36, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style

# ---------------------------------------------------------------- 结算浮层
func _build_overlay() -> void:
	var banner := UiStyle.make_battle_banner()
	_overlay = banner["root"]
	_overlay_title = banner["title"]
	_overlay_body = banner["body"]
	add_child(_overlay)

# ---------------------------------------------------------------- 刷新
## 相位跳变即刻刷新；另外每 `REFRESH_MS` 轮询一次（补给 / 血量会随操作变化，靠相位信号刷不全）。
func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _refresh_ms < REFRESH_MS:
		return
	_refresh_ms = Time.get_ticks_msec()
	_refresh()

func _on_phase_changed(_phase: String) -> void:
	_refresh()

func _refresh() -> void:
	if roguelike == null:
		return
	## 自由视角下隐藏整个界面（与另外两套 HUD 同一条口径：那时只能靠鼠标左右键出来）
	visible = camera_rig == null or camera_rig.mode != CameraRig.Mode.OVERVIEW
	if not visible:
		return
	_refresh_top()
	if _hint != null:
		_hint.text = UiStyle.camera_hint()
	_refresh_actions()
	_refresh_overlay()
	_refresh_difficulty()
	_refresh_starter()
	_refresh_aid()
	_refresh_choice_eye()
	_refresh_shop()
	_refresh_buff_panel()
	_refresh_squad_panel()
	_refresh_undo()
	_refresh_tech_panel()

## ---- 撤销（2026-09-27 第三轮）----
## 屏幕中央那一行"撤销了什么"：单独一个 `Label`（`PRESET_CENTER`，鼠标穿透），
## 只在玩法侧 `undo_note()` 非空时显示 —— 到期由玩法侧判（界面不自己算时间，I-13 只有一处时间源）。
func _build_undo_toast() -> void:
	_undo_toast = _make_label("", FONT_MID, COLOR_TEXT, "UndoToastLabel")
	## ⚠️ 用 **FULL_RECT + 双向居中**（而不是 `PRESET_CENTER`）：`PRESET_CENTER` 只挪锚点、不改尺寸，
	## 标签会以"左上角落在屏幕正中"的姿态出现、且首帧可能还是 0 尺寸 ⇒ 实测**看不见**。
	## 铺满全屏 + 文本居中 = 无论标签多大都正好落在画面正中（底栏上沿之上那一片）。
	_undo_toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	_undo_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_undo_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_undo_toast.offset_bottom = -ACTION_PANEL_HEIGHT * 0.5   ## 往上挪半个底栏 ⇒ 落在可见的场地中央
	_undo_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_undo_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_undo_toast.add_theme_constant_override("shadow_offset_x", 2)
	_undo_toast.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_undo_toast)

func _on_undo_pressed() -> void:
	if roguelike != null:
		roguelike.undo_last()
	_refresh()

func _refresh_undo() -> void:
	if _undo_button != null:
		var depth := roguelike.undo_depth()
		_undo_button.text = "撤销" if depth <= 0 else "撤销（%d）" % depth
		_undo_button.disabled = depth <= 0 or roguelike.phase != Roguelike.Phase.PREPARE
	if _undo_toast != null:
		var note := roguelike.undo_note()
		_undo_toast.text = note
		_undo_toast.visible = note != ""

func _refresh_top() -> void:
	var round_text := "回合 %d / %d" % [roguelike.round_index, GameConfig.ROGUELIKE_ROUND_COUNT]
	if roguelike.difficulty_chosen:
		round_text += " · %s" % GameConfig.roguelike_difficulty_name(roguelike.difficulty)
	_round_label.text = round_text
	## 图案已经说明是哪一样 ⇒ 这里只给数字（"12" / "8 / 20"），不再重复"补给 / 血量"四个字。
	_supply_label.text = "%d" % roguelike.supply
	_hp_label.text = "%d / %d" % [roguelike.hp, roguelike.hp_max]
	_squads_label.text = "本回合 %d / %d 队 · 部队权重 %d" % [
			roguelike.bought_this_round, roguelike.squad_limit_this_round(),
			roguelike.squad_weight_total()]
	## 血量告警：低于 1/4 变橙（纯表现，不改任何玩法数据）
	_hp_label.add_theme_color_override("font_color", COLOR_WARN if roguelike.hp * 4 <= roguelike.hp_max else COLOR_OK)
	_foe_label.text = "敌方存活权重 %d" % roguelike.enemy_weight()
	## 第七块（2026-09-27 订正）：两条带子贴**南北两条长边**，各 = 本方半场的 3/4（从**自己的底线**往内量）。
	## **琥珀 = 我方可用、暗红 = 敌方专用、灰 = 中间死区（谁都不能布阵）**；文案带秒数 = 不必猜 5 s 从哪一刻起算。
	if _zone_label != null:
		_zone_label.text = "布阵带（南北长边外侧）：琥珀 = 我方可用（落地后 %0.0f s 准备）· 暗红 = 敌方专用 · 灰 = 死区" % \
				(float(GameConfig.ROGUELIKE_ZONE_PREP_MS) / 1000.0)
	## 齿轮只在"玩家能用鼠标点"的相位出现：战斗中光标被锁进窗口（`CameraRig` 的 `_fight_started`）
	## ⇒ 那时只认 Esc（与另外两套 HUD 同一条口径）。
	if _gear != null:
		_gear.visible = roguelike.phase != Roguelike.Phase.FIGHTING
	## 倍速按钮**不跟着齿轮藏**：它常显（见建它时那条注释），战斗中也亮着。
	var holding := roguelike.phase == Roguelike.Phase.ROUND_RESULT or roguelike.phase == Roguelike.Phase.GAME_OVER
	if _top_bar != null:
		_top_bar.visible = not holding

func _refresh_actions() -> void:
	var prepare := roguelike.phase == Roguelike.Phase.PREPARE
	var settled := roguelike.phase == Roguelike.Phase.ROUND_RESULT
	if _start_button != null:
		_start_button.visible = prepare
		_start_button.disabled = roguelike.aid_pending or not roguelike.difficulty_chosen
		_start_button.tooltip_text = "先选择援助，或放弃换成补给" if roguelike.aid_pending \
			else "让本回合的进攻开始"
	if _next_button != null:
		_next_button.visible = false
		_next_button.disabled = roguelike.round_index >= GameConfig.ROGUELIKE_ROUND_COUNT
	## 定格后只留上下两条，继续靠 Enter。准备阶段仍用顶部那颗「开始战斗」。
	if _start_bar != null:
		_start_bar.visible = prepare
	if _action_panel != null:
		_action_panel.visible = prepare
	## ⚠️ 第六轮：底栏高度随"提示收起"变 ⇒ 每帧把挂在它上面的两块面板重新贴一遍（见 `_apply_bottom_anchors()`）
	_apply_bottom_anchors()
	## 两行提示的显隐 + 折叠按钮的文案（收起时按钮**仍然留着**，否则就没东西可以点开）
	if _hint_col != null:
		_hint_col.visible = _hints_open
	if _hint_fold != null:
		_hint_fold.text = "收起" if _hints_open else "展开"
	if _hint != null:
		_hint.visible = _action_panel != null and _action_panel.visible
	if _deploy_hint != null:
		_deploy_hint.visible = _hint != null and _hint.visible

func _refresh_overlay() -> void:
	var over := roguelike.phase == Roguelike.Phase.GAME_OVER
	var settled := roguelike.phase == Roguelike.Phase.ROUND_RESULT
	if _overlay != null:
		_overlay.visible = over or settled
	if not _overlay.visible:
		return
	if over:
		var reached_end := bool(roguelike.summary.get("reached_end", false))
		_overlay_title.text = "通关" if reached_end else "失败"
		_overlay_title.add_theme_color_override("font_color", COLOR_OK if reached_end else COLOR_WARN)
		var rounds := int(roguelike.summary.get("rounds", 0))
		var progress := "打满 %d 回合" % rounds if reached_end else "倒在第 %d 回合" % rounds
		_overlay_body.text = "%s · 剩余血量 %d / %d · 累计补给 %d" % [
			progress, roguelike.hp, roguelike.hp_max,
			int(roguelike.summary.get("income_total", 0))]
		return
	var res: Dictionary = roguelike.result
	var held := bool(res.get("defeated", true))
	_overlay_title.text = "守住了" if held else "没守住"
	_overlay_title.add_theme_color_override("font_color", COLOR_OK if held else COLOR_WARN)
	_overlay_body.text = "第 %d 回合 · %s · 扣血 %d · 剩余血量 %d / %d" % [
		int(res.get("round", roguelike.round_index)),
		"敌方全灭" if held else "没打退敌人",
		int(res.get("loss", 0)), roguelike.hp, roguelike.hp_max]

# ---------------------------------------------------------------- 兵种卡（商店）
## 一张卡 = 一个兵种。**已解锁**的卡点一下 = 买一整队（未解锁的那一栏在 `UnlockPanel` 里，见用户口径（1））。
## ⚠️ 文案与"能不能点"由 `_refresh_shop()` 每次刷新时写；这里只建一次（同 §7.1"按钮只构建一次"）。
## ⚠️ **2026-09-27 第四轮（用户口径（2））**：卡上**只写兵种名**（按钮因此缩到一行高），
## **鼠标移上去才把文字换成"所需补给"**（见 `_chip_base_text` / `_chip_hover_text` 与刷新时的二选一）。
func _add_card(grid: GridContainer, type_id: String) -> void:
	var button := Button.new()
	button.name = "Chip_%s" % type_id        ## 与沙盒兵种栏同名同式：纯英文 + 兵种 ID（§3.1）
	UiStyle.decorate_chip(button)
	## ⚠️ 固定最小宽度（**不是 0**）：见 `CARD_MIN_WIDTH` 的注 —— 文字两套切换时布局必须纹丝不动
	button.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
	button.mouse_entered.connect(_on_chip_hover.bind(button, type_id, true))
	button.mouse_exited.connect(_on_chip_hover.bind(button, type_id, false))
	button.pressed.connect(_on_card_pressed.bind(type_id))
	grid.add_child(button)
	_chips[type_id] = button

## 悬停进出：**立刻**把文字换成另一套（不等下一次 100 ms 刷新），同时保留原有的缩放反馈
func _on_chip_hover(button: Button, type_id: String, entered: bool) -> void:
	_hover(button, entered)
	_apply_chip_text(button, type_id, entered)

## 未解锁单位的一栏（`UnlockPanel` 里的卡）：同样是"名字 / 悬停显示解锁价"两套文案
func _add_unlock_card(grid: GridContainer, type_id: String) -> void:
	var button := Button.new()
	button.name = "UnlockChip_%s" % type_id
	UiStyle.decorate_chip(button)
	## ⚠️ 与商店卡同一个固定宽度（同一条 bug：悬停换文字不能让卡片变大小）
	button.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
	button.mouse_entered.connect(_on_unlock_chip_hover.bind(button, type_id, true))
	button.mouse_exited.connect(_on_unlock_chip_hover.bind(button, type_id, false))
	button.pressed.connect(_on_unlock_card_pressed.bind(type_id))
	grid.add_child(button)
	_unlock_cards[type_id] = button

func _on_unlock_chip_hover(button: Button, type_id: String, entered: bool) -> void:
	_hover(button, entered)
	## ⚠️ 与商店卡**共用同一对文案表**：一个兵种要么在"已解锁"那一栏、要么在"未解锁"这一栏，
	## 两个集合不相交 ⇒ 一套表就够（多一套必然漂移）。
	_apply_chip_text(button, type_id, entered)

## 按"指针在不在上面"写卡片文字（常态 = 名字、悬停 = 价格）
func _apply_chip_text(button: Button, type_id: String, hovered: bool) -> void:
	var table := _chip_hover_text if hovered else _chip_base_text
	if table.has(type_id):
		button.text = String(table[type_id])

## 点一张卡：已解锁 ⇒ 买一队。（未解锁的卡不在这一栏里 —— 见 `_on_unlock_card_pressed()`）
func _on_card_pressed(type_id: String) -> void:
	if roguelike == null:
		return
	roguelike.buy_squad(type_id)
	_refresh()

## 点一张**未解锁**的卡 ⇒ 解锁它，并在成功后把这一栏收起来（没得解锁了）
func _on_unlock_card_pressed(type_id: String) -> void:
	if roguelike == null:
		return
	roguelike.unlock_type(type_id)
	if _locked_types().is_empty():
		_unlock_open = false
	_refresh()

## 「解锁单位」按钮：点开 / 收起那一栏
func _on_unlock_pressed() -> void:
	_unlock_open = not _unlock_open
	_refresh()

func _on_unlock_close_pressed() -> void:
	_unlock_open = false
	_refresh()

## 还没解锁的兵种（**按权重从小到大**，与主栏同一套排序）
func _locked_types() -> Array:
	var out: Array = []
	if roguelike == null:
		return out
	for type_id in _types_by_weight():
		if not roguelike.pool.has(String(type_id)):
			out.append(type_id)
	return out

## 未解锁单位那一栏（用户口径（1）："未解锁单位不要列出来，而是有一个专门的『解锁单位』按钮，
## 按下后跳出解锁单位的界面，里面是未解锁单位"）。**居中弹层**（与结算浮层同一手法，但不挡满屏、
## 也不加 scrim —— 玩家开着它也能看见场地）。⚠️ 与增益 / 队伍面板一样：卡片一次建好、只改文字与可见性。
func _build_unlock_panel() -> void:
	_unlock_panel = PanelContainer.new()
	_unlock_panel.name = "UnlockPanel"
	## ⚠️ **第七轮**：锚点从"左侧居中"改成**右侧居中** —— 左下角归了"选中单位"面板之后，
	## 两者会在左侧叠在一起；而这一栏是从右下角商店那颗「解锁单位」点开的，落在它上方更顺。
	## `offset_top = -40`：略上移，避开右下角商店面板的顶边（实测商店顶边 ≈ 595）。
	_unlock_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_unlock_panel.offset_right = -16.0
	_unlock_panel.offset_top = -40.0
	_unlock_panel.offset_bottom = -40.0
	_unlock_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_unlock_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_unlock_panel.add_theme_stylebox_override("panel", _bar_style(0.96))
	_unlock_panel.visible = false
	add_child(_unlock_panel)
	var box := VBoxContainer.new()
	box.name = "UnlockBox"
	box.add_theme_constant_override("separation", 10)
	_unlock_panel.add_child(box)
	_unlock_hint = _make_label("", FONT_TINY, COLOR_DIM, "UnlockHintLabel")
	_unlock_hint.custom_minimum_size = Vector2(360.0, 0.0)
	_unlock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_unlock_hint)
	_unlock_grid = GridContainer.new()
	_unlock_grid.name = "UnlockGrid"
	_unlock_grid.columns = 3
	_unlock_grid.add_theme_constant_override("h_separation", CARD_SEPARATION)
	_unlock_grid.add_theme_constant_override("v_separation", CARD_SEPARATION)
	box.add_child(_unlock_grid)
	for type_id in _types_by_weight():
		_add_unlock_card(_unlock_grid, String(type_id))
	_unlock_close = Button.new()
	_unlock_close.name = "UnlockCloseButton"
	_unlock_close.text = "关闭"
	UiStyle.decorate_chip(_unlock_close)
	_unlock_close.custom_minimum_size = Vector2(120.0, 34.0)
	_unlock_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_unlock_close.pressed.connect(_on_unlock_close_pressed)
	box.add_child(_unlock_close)

# ---------------------------------------------------------------- 兵种科技面板（2026-09-27 第十二轮）
## 用户口径（原话）："科技需要**选中相应兵种**后花费补给激活，激活后**所有同类型兵种都能吃到科技加成**"，
## 界面上"选中兵种卡后弹出的界面在**下方有 4 个按钮**，鼠标移上去后**按钮内容变消耗补给数**，
## 并**另有提示技能效果**"。
## ⇒ 结构逐条对应：
##   · 上方 `TechTypeGrid` = 兵种卡（有科技的兵种各一张）—— **点一下 = 选中**（描金框），
##     不是买东西 ⇒ 与商店卡（点一下 = 买一队）职责分开，两颗按钮各管一件事；
##   · 下方 `TechGrid` = **该兵种的 4 个科技按钮**：常态写**科技名**、悬停写**消耗补给数**（与商店卡
##     同一套"名字 ⇄ 价格"手法）；已经买过的写"已激活"并禁用；第二批那 5 条写"第二批"并禁用；
##   · `TechEffectLabel` = 悬停时显示这条科技的**效果说明**（`GameConfig.roguelike_tech_desc()`）；
##   · `TechHintLabel` = 顶部一行状态（"本局永久 · 立即对场上同兵种生效 · 现有补给 N"）。
## ⚠️ 面板是**居中弹层、不加 scrim**（与解锁栏一致：开着它也能看见场地）；⚠️ 按钮一次建好（每个兵种
## 4 个 ⇒ 共 12 个），刷新时只改文字 / 禁用态 / 可见性，**不重建**（与商店卡同一条纪律）。
func _build_tech_panel() -> void:
	_tech_panel = PanelContainer.new()
	_tech_panel.name = "TechPanel"
	_tech_panel.set_anchors_preset(Control.PRESET_CENTER)
	_tech_panel.offset_top = -60.0
	_tech_panel.offset_bottom = -60.0
	_tech_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tech_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tech_panel.add_theme_stylebox_override("panel", _bar_style(0.96))
	_tech_panel.visible = false
	add_child(_tech_panel)

	var box := VBoxContainer.new()
	box.name = "TechBox"
	box.add_theme_constant_override("separation", 10)
	_tech_panel.add_child(box)

	_tech_hint = _make_label("", FONT_TINY, COLOR_DIM, "TechHintLabel")
	_tech_hint.custom_minimum_size = Vector2(420.0, 0.0)
	_tech_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tech_hint)

	_tech_type_grid = GridContainer.new()
	_tech_type_grid.name = "TechTypeGrid"
	_tech_type_grid.columns = 3
	_tech_type_grid.add_theme_constant_override("h_separation", CARD_SEPARATION)
	_tech_type_grid.add_theme_constant_override("v_separation", CARD_SEPARATION)
	box.add_child(_tech_type_grid)
	for type_id in GameConfig.ROGUELIKE_TECH_TYPES:
		var tid := String(type_id)
		var card := Button.new()
		card.name = "TechTypeChip_%s" % tid
		card.text = GameConfig.profile_name(tid)
		card.tooltip_text = "选中%s，看它的 %d 条科技" % [
				GameConfig.profile_name(tid), GameConfig.roguelike_tech_list(tid).size()]
		UiStyle.decorate_chip(card)
		card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
		card.mouse_entered.connect(_hover.bind(card, true))
		card.mouse_exited.connect(_hover.bind(card, false))
		card.pressed.connect(_on_tech_type_pressed.bind(tid))
		_tech_type_grid.add_child(card)
		_tech_type_cards[tid] = card

	var tech_gap := Control.new()
	tech_gap.name = "TechGap"
	tech_gap.custom_minimum_size = Vector2(0.0, 18.0)
	tech_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tech_gap)

	_tech_grid = GridContainer.new()
	_tech_grid.name = "TechGrid"
	_tech_grid.columns = 2
	_tech_grid.add_theme_constant_override("h_separation", CARD_SEPARATION)
	_tech_grid.add_theme_constant_override("v_separation", CARD_SEPARATION)
	box.add_child(_tech_grid)
	## ⚠️ 按钮按每个兵种的科技各建一个，刷新时只让当前兵种那几个可见 ——
	## 这样切换兵种不需要重建节点（本项目在"刷新时重建控件"上踩过（焦点 / 悬停态会丢））。
	for type_id in GameConfig.ROGUELIKE_TECH_TYPES:
		for row in GameConfig.roguelike_tech_list(String(type_id)):
			var tech_id := String(row.get("id", ""))
			var button := Button.new()
			button.name = "Tech_%s_%s" % [type_id, tech_id]
			UiStyle.decorate_chip(button)
			button.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
			button.mouse_entered.connect(_on_tech_hover.bind(button, String(type_id), tech_id, true))
			button.mouse_exited.connect(_on_tech_hover.bind(button, String(type_id), tech_id, false))
			button.pressed.connect(_on_tech_buy_pressed.bind(String(type_id), tech_id))
			_tech_grid.add_child(button)
			_tech_buttons.append({"type_id": String(type_id), "tech_id": tech_id, "button": button})

	_tech_effect = _make_label("", FONT_TINY, COLOR_TEXT, "TechEffectLabel")
	## 高度先占住：悬停才写说明。高度跟着文字长，面板会在鼠标移上去时被撑大。
	_tech_effect.custom_minimum_size = Vector2(420.0, 62.0)
	_tech_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tech_effect.max_lines_visible = 3
	_tech_effect.clip_text = true
	box.add_child(_tech_effect)

	var close := Button.new()
	close.name = "TechCloseButton"
	close.text = "关闭"
	UiStyle.decorate_chip(close)
	close.custom_minimum_size = Vector2(120.0, 34.0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_on_tech_close_pressed)
	box.add_child(close)

## 「兵种科技」按钮：点开 / 收起（第一次点开时默认选中第一个有科技的兵种，省一次点击）。
func _on_tech_pressed() -> void:
	_tech_open = not _tech_open
	if _tech_open and not _tech_type_unlocked(_tech_selected):
		_tech_selected = _first_unlocked_tech_type()
	_refresh()

func _on_tech_close_pressed() -> void:
	_tech_open = false
	_refresh()

## 点一张兵种卡 = 选中它（不是买东西）⇒ 下方那 4 个按钮换成它的科技。
func _on_tech_type_pressed(type_id: String) -> void:
	_tech_selected = type_id
	_tech_effect.text = ""
	_refresh()

## 悬停一个科技按钮：常态显示**科技名**、悬停显示**消耗补给数**，并把效果写进提示行。
func _on_tech_hover(button: Button, type_id: String, tech_id: String, entered: bool) -> void:
	_hover(button, entered)
	var def := GameConfig.roguelike_tech_def(type_id, tech_id)
	if def.is_empty():
		return
	var owned := roguelike != null and roguelike.has_tech(type_id, tech_id)
	var tech_name := String(def.get("name", tech_id))
	if entered:
		if owned:
			button.text = tech_name
		else:
			var price := int(def.get("cost", 0))
			if roguelike != null:
				price = roguelike.tech_price(type_id, tech_id)
			button.text = "%d 补给" % price
		_tech_effect.text = "%s：%s" % [tech_name, GameConfig.roguelike_tech_desc(type_id, tech_id)]
	else:
		_tech_effect.text = ""
		if not button.disabled:
			button.text = "已激活" if owned else tech_name
	## ⚠️ **不要在这里顺手刷一遍按钮文字**：那会把刚写上的"消耗补给数"又顶回科技名
	##（刷新那一支按 `is_hovered()` 判，而此刻指针确实在按钮上 ⇒ 真机上看着是对的，
	## 但这条隐式依赖没必要留着 —— 买下 / 切兵种时才需要刷新，那两处各自调 `_refresh()`）。

## 点一个科技按钮 = 花补给激活它（玩法侧做全部判定；界面只负责把结果画出来）。
func _on_tech_buy_pressed(type_id: String, tech_id: String) -> void:
	if roguelike == null:
		return
	roguelike.buy_tech(type_id, tech_id)
	_refresh()

## 把科技面板整块画一遍（`_refresh()` 每 100 ms 调一次；只改文字 / 禁用态 / 可见性，不重建节点）。
func _refresh_tech_panel() -> void:
	if _tech_panel == null:
		return
	_tech_panel.visible = _tech_open
	_tech_button.disabled = false
	if not _tech_open:
		return
	if not _tech_type_unlocked(_tech_selected):
		_tech_selected = _first_unlocked_tech_type()
	_tech_hint.text = "兵种科技：只列出已解锁的兵种。选中后点下方科技。本局永久，立刻对场上同兵种生效。现有补给 %d" % roguelike.supply
	for type_id in _tech_type_cards.keys():
		var card := _tech_type_cards[type_id] as Button
		var unlocked := _tech_type_unlocked(String(type_id))
		card.visible = unlocked
		if unlocked:
			UiStyle.apply_chip_selected(card, String(type_id) == _tech_selected)
	_refresh_tech_buttons()

func _tech_type_unlocked(type_id: String) -> bool:
	return roguelike != null and type_id != "" and roguelike.pool.has(type_id)


func _first_unlocked_tech_type() -> String:
	for type_id in GameConfig.ROGUELIKE_TECH_TYPES:
		var id := String(type_id)
		if _tech_type_unlocked(id):
			return id
	return ""


func _refresh_tech_buttons() -> void:
	for row in _tech_buttons:
		var button: Button = row["button"]
		var type_id := String(row["type_id"])
		var tech_id := String(row["tech_id"])
		var mine := type_id == _tech_selected
		button.visible = mine
		if not mine:
			continue
		var def := GameConfig.roguelike_tech_def(type_id, tech_id)
		var owned := roguelike != null and roguelike.has_tech(type_id, tech_id)
		var ready := GameConfig.roguelike_tech_ready(type_id, tech_id)
		var price := roguelike.tech_price(type_id, tech_id) if roguelike != null else int(def.get("cost", 0))
		button.disabled = not ready
		button.modulate = Color(0.72, 0.76, 0.82) if owned else Color.WHITE
		if not ready:
			button.text = "第二批"
		elif owned and button.is_hovered():
			button.text = String(def.get("name", tech_id))
		elif owned:
			button.text = "已激活"
		elif button.is_hovered():
			button.text = "%d 补给" % price
		else:
			button.text = String(def.get("name", tech_id))
		button.tooltip_text = "%s（%d 补给）\n%s" % [String(def.get("name", tech_id)),
				price, GameConfig.roguelike_tech_desc(type_id, tech_id)]

## 卡片的**显示顺序**：按权重**从小到大**（同沙盒 `_types_by_weight()` 的写法：先收集权重升序、
## 再按权重分桶遍历 `TYPE_ORDER` ⇒ 稳定可复现，不用不保证稳定的 `sort_custom()`）。
func _types_by_weight() -> Array:
	var weights: Array = []
	for type_id in GameConfig.roguelike_buyable_types():
		var w := int(GameConfig.profile(String(type_id))["weight"])
		if not weights.has(w):
			weights.append(w)
	weights.sort()
	var out: Array = []
	for w in weights:
		for type_id in GameConfig.roguelike_buyable_types():
			if int(GameConfig.profile(String(type_id))["weight"]) == w:
				out.append(type_id)
	return out

# ---------------------------------------------------------------- 道具卡（第五块：陷阱 / 魔法盾 / 信标）
## 三张**可拖动**的道具卡 —— 用户口径："直接对着按钮拖动放置，若鼠标松开时当前位置不可部署，
## 则不进行部署并不扣除补给"。
## ⚠️ 只接 `button_down`（**按下**就进入拖放），**不接 `pressed`**：`pressed` 要等松开才发，
## 而玩家松手的位置多半在场地中央 ⇒ 那个信号根本不会到按钮上。拖放的"结束"由玩法侧轮询左键
##（`Roguelike._tick_placing()`），与事件落在哪个控件无关。
## ⚠️ **2026-09-27 第四轮**：不再挤在底栏一行里 —— **信标挂左列、陷阱 / 魔法盾挂右列**
##（`_prop_panels` 在 `_build_left_column()` / `_build_prop_panel()` 里登记好挂点）。
func _build_prop_cards() -> void:
	for kind in GameConfig.roguelike_prop_kinds():
		var k := String(kind)
		var parent: VBoxContainer = _prop_panels.get(k)
		if parent == null:
			continue
		var button := Button.new()
		button.name = "Prop_%s" % k                 ## 与 `Chip_<兵种ID>` 同式：英文 + ID（§3.1）
		UiStyle.decorate_chip(button)
		button.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - 40.0, 40.0)
		button.mouse_entered.connect(_on_prop_hover.bind(button, k, true))
		button.mouse_exited.connect(_on_prop_hover.bind(button, k, false))
		button.button_down.connect(_on_prop_pressed.bind(k))
		parent.add_child(button)
		_prop_cards[k] = button

## 道具卡悬停：**只换文字（名字 ⇄ 价格），不放大**（第五轮用户两条口径一起落在这里）
func _on_prop_hover(button: Button, kind: String, entered: bool) -> void:
	_hover(button, entered)
	button.text = String(_prop_hover_text.get(kind, button.text)) if entered \
			else String(_prop_base_text.get(kind, button.text))

## 在道具卡上按下 ⇒ 交给玩法侧进入拖放（买不起 / 不在准备阶段 ⇒ 玩法侧只回一行原因、不进入拖放）
func _on_prop_pressed(kind: String) -> void:
	if roguelike == null:
		return
	roguelike.begin_place(kind)
	_refresh()

## 道具卡的文字与浓淡：**只写名字**（第五轮用户："陷阱魔法盾不再显示场上有几件，只显示名字，
## 在鼠标移上去后内容由名字变成价格"）+ 现在能不能拖（只改 `text` / `disabled` / `modulate`，不重建）。
## ⚠️ 文字有**两套**（名字 / 价格）：`_prop_base_text` 与 `_prop_hover_text`，由 `_on_prop_hover()` 切换；
## 这里按 `is_hovered()` 写当前该显示的那一套（否则每 100 ms 的刷新会把悬停效果抹掉）。
func _refresh_props() -> void:
	if roguelike == null:
		return
	for kind in _prop_cards.keys():
		var k := String(kind)
		var button: Button = _prop_cards[kind]
		var base := GameConfig.roguelike_prop_name(k)
		var hover := "%d 补给" % GameConfig.roguelike_prop_price(k)
		if k == GameConfig.ROGUELIKE_PROP_BEACON:
			## 信标是**两步**的：钱在右方指挥所花掉了 ⇒ 这里报的是"能不能免费重放"，不报价格。
			## 买过才露出这张卡。这一栏本身在还有战场道具或遣返时也会开着。
			base = GameConfig.roguelike_prop_name(k)
			hover = "点一下免费重放"
			button.visible = roguelike.has_beacon()
		_prop_base_text[k] = base
		_prop_hover_text[k] = hover
		button.text = hover if button.is_hovered() else base
		button.tooltip_text = _prop_tooltip(k)
		var usable := roguelike.can_place_prop(k)
		button.disabled = not usable
		button.modulate = Color(1, 1, 1, 1) if usable else Color(0.66, 0.66, 0.72, 1)
	if _recall_card != null:
		var ready := roguelike.recall_ready()
		_recall_card.visible = roguelike.has_recall()
		_recall_card.disabled = not ready
		_recall_card.text = "本回合已用" if roguelike.has_recall() and not roguelike.recall_ready() and roguelike.phase == Roguelike.Phase.PREPARE else "遣返"
		_recall_card.tooltip_text = "拖到一队兵上：永久撤走，退回买队和升级所花补给的一半（不含科技）。每回合一次。"
		_recall_card.modulate = Color(1, 1, 1, 1) if ready else Color(0.66, 0.66, 0.72, 1)

## 两张道具卡的悬停说明（口径写在卡上，玩家不用猜 8 m / 14 m 是什么意思）
func _prop_tooltip(kind: String) -> String:
	if kind == GameConfig.ROGUELIKE_PROP_BEACON:
		return _beacon_tooltip()
	if kind == GameConfig.ROGUELIKE_PROP_TRAP:
		return "陷阱（%d 补给）：本体只能放在我方半场，爆炸范围可以进入敌方。开战之后，敌军进到 %0.0f m 内 ⇒ 延迟 %0.1f s 后以那名敌军为中心炸开 —— 半径 %0.0f m 内所有敌方单位吃 %d 伤害，并减速 %0.0f%% 持续 %0.1f s。未触发就一直留着，炸过的下回合开始时撤走。" % [
				GameConfig.ROGUELIKE_TRAP_PRICE, GameConfig.ROGUELIKE_TRAP_TRIGGER_RADIUS,
				float(GameConfig.ROGUELIKE_TRAP_DELAY_MS) / 1000.0, GameConfig.ROGUELIKE_TRAP_BLAST_RADIUS,
				int(GameConfig.ROGUELIKE_TRAP_DAMAGE),
				(1.0 - GameConfig.ROGUELIKE_TRAP_SLOW_MULT) * 100.0,
				float(GameConfig.ROGUELIKE_TRAP_SLOW_MS) / 1000.0]
	return "魔法盾（%d 补给）：半径 %0.0f m 的圆，挡住所有穿过圆边界的敌方远程攻击（火枪也穿不过；在圆里开的枪同样出不去）。血量 %d，每回合开始回满；不会被主动锁定、没有碰撞体积。⚠️ 圆心必须离中心线 ≥ %0.0f m（圆不能罩到敌方半场）。" % [
			GameConfig.ROGUELIKE_SHIELD_PRICE, GameConfig.ROGUELIKE_SHIELD_RADIUS,
			int(GameConfig.ROGUELIKE_SHIELD_HP), GameConfig.ROGUELIKE_SHIELD_RADIUS]

## 移动信标那张卡的悬停说明（第七块起：买一次永久可用、每回合免费重放、朝向一起对齐）
func _beacon_tooltip() -> String:
	return "移动信标：先在【右方】指挥所花 %d 补给**买一次**（此后永久可用），再回到这张卡**按住拖到场上**松手放下；放下后**点两下**画路线（第 1 下从信标起算、第 2 下从第 1 个点起算，每段最远 %0.0f m，超了自动夹到 %0.0f m；右键退一步 / 取消；路线点会被夹进场地内）。⚠️ **每回合开始信标自动清场**，想用就再点一下这张卡免费重放。战斗开始时半径 %0.0f m 内的我方单位会沿这条路线**保持队形**移动（攻击时也走），到终点恢复自由移动；被影响单位的**朝向**会改成路线第一段的方向。⚠️ 信标不会被锁定、也不会被打掉，可以放在任意位置（包括敌方半场与两端延伸区）。" % [
			GameConfig.ROGUELIKE_BEACON_PRICE, GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX,
			GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX, GameConfig.ROGUELIKE_BEACON_RADIUS]

# ---------------------------------------------------------------- 初始四选一
## 一进模式就弹的一层挡屏浮层（`PREPARE` 且**还没选起手部队**时可见）：四个选项，选完才露出商店。
## ⚠️ 它**不是新相位**（`Roguelike.Phase` 仍是四个）—— 只是 `PREPARE` 里的一个门，`Roguelike.starter_chosen` 把关。
func _build_starter() -> void:
	_starter_scrim = ColorRect.new()
	_starter_scrim.name = "StarterScrim"
	_starter_scrim.color = Color(0.02, 0.02, 0.03, 0.86)
	_starter_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_starter_scrim.visible = false
	_starter_scrim.mouse_filter = Control.MOUSE_FILTER_STOP   ## 没选完不许操作底下那一层
	add_child(_starter_scrim)

	var center := CenterContainer.new()
	center.name = "StarterCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_starter_scrim.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "StarterPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = Color(0.38, 0.42, 0.50, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "StarterBox"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := _make_label("选择初始部队", FONT_LARGE, COLOR_TEXT, "StarterTitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := _make_label("", FONT_SMALL, COLOR_DIM, "StarterBodyLabel")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(560.0, 0.0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "四个选项里选一个：那两个兵种进入你的兵种池，并【各白送两队】（已经摆到场上）。"
	col.add_child(body)
	for i in range(GameConfig.ROGUELIKE_START_CHOICE_COUNT):
		var button := Button.new()
		button.name = "StarterButton_%d" % i      ## 序号写在 `_` 之后（§3.1）
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UiStyle.decorate_option(button)
		## 开始界面那套会把按钮锁在 280 宽并裁字。这里一条是「A + B」两队，裁了就只剩前半个兵种。
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.mouse_entered.connect(_hover.bind(button, true, true))
		button.mouse_exited.connect(_hover.bind(button, false, true))
		button.pressed.connect(_on_starter_pressed.bind(i))
		col.add_child(button)
		_starter_buttons.append(button)

## 进生存后、起手四选一之前的难度挡屏。选一次写入这一局，之后不能改。
func _build_difficulty() -> void:
	_difficulty_scrim = ColorRect.new()
	_difficulty_scrim.name = "DifficultyScrim"
	_difficulty_scrim.color = Color(0.02, 0.02, 0.03, 0.86)
	_difficulty_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_difficulty_scrim.visible = false
	_difficulty_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_difficulty_scrim)

	var center := CenterContainer.new()
	center.name = "DifficultyCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_difficulty_scrim.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "DifficultyPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = Color(0.38, 0.42, 0.50, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "DifficultyBox"
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := _make_label("选择难度", FONT_LARGE, COLOR_TEXT, "DifficultyTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var ids: Array = GameConfig.ROGUELIKE_DIFFICULTY_ORDER
	for i in range(ids.size()):
		var button := Button.new()
		button.name = "DifficultyButton_%d" % i
		button.text = GameConfig.roguelike_difficulty_name(String(ids[i]))
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UiStyle.decorate_chip(button)
		button.custom_minimum_size = Vector2(320.0, 44.0)
		button.clip_text = false
		button.mouse_entered.connect(_hover.bind(button, true))
		button.mouse_exited.connect(_hover.bind(button, false))
		button.pressed.connect(_on_difficulty_pressed.bind(i))
		col.add_child(button)
		_difficulty_buttons.append(button)

func _build_aid() -> void:
	_aid_scrim = ColorRect.new()
	_aid_scrim.name = "AidScrim"
	_aid_scrim.color = Color(0.02, 0.02, 0.03, 0.86)
	_aid_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aid_scrim.visible = false
	_aid_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_aid_scrim)
	var center := CenterContainer.new()
	center.name = "AidCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aid_scrim.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "AidPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = Color(0.38, 0.42, 0.50, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "AidBox"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := _make_label("援助", FONT_LARGE, COLOR_TEXT, "AidTitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := _make_label("选一个援助，或放弃这次并获得 %d 补给。" % GameConfig.ROGUELIKE_AID_SKIP_SUPPLY,
			FONT_SMALL, COLOR_DIM, "AidBodyLabel")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(560.0, 0.0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	for i in range(GameConfig.ROGUELIKE_AID_OFFER_COUNT):
		var button := Button.new()
		button.name = "AidButton_%d" % i
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UiStyle.decorate_option(button)
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		button.mouse_entered.connect(_hover.bind(button, true, true))
		button.mouse_exited.connect(_hover.bind(button, false, true))
		button.pressed.connect(_on_aid_pressed.bind(i))
		col.add_child(button)
		_aid_buttons.append(button)
	_aid_skip = Button.new()
	_aid_skip.name = "AidSkipButton"
	_aid_skip.text = "放弃，获得 %d 补给" % GameConfig.ROGUELIKE_AID_SKIP_SUPPLY
	_aid_skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStyle.decorate_option(_aid_skip)
	_aid_skip.pressed.connect(_on_aid_skip)
	col.add_child(_aid_skip)
	_aid_tray = HBoxContainer.new()
	_aid_tray.name = "AidTray"
	_aid_tray.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_aid_tray.offset_left = 16.0
	_aid_tray.offset_top = -168.0
	_aid_tray.offset_right = 720.0
	_aid_tray.offset_bottom = -96.0
	_aid_tray.add_theme_constant_override("separation", 8)
	_aid_tray.visible = false
	_aid_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_aid_tray)


func _on_aid_pressed(index: int) -> void:
	if roguelike == null:
		return
	roguelike.accept_aid(index)
	_refresh()


func _on_aid_skip() -> void:
	if roguelike == null:
		return
	roguelike.skip_aid()
	_refresh()


func _on_aid_card(index: int) -> void:
	if roguelike == null:
		return
	roguelike.begin_aid_card(index)


func _refresh_aid() -> void:
	if _aid_scrim == null or roguelike == null:
		return
	var pending := roguelike.phase == Roguelike.Phase.PREPARE and roguelike.starter_chosen and roguelike.aid_pending
	_aid_scrim.visible = pending and not roguelike.choice_hidden
	if pending:
		for i in range(_aid_buttons.size()):
			var button := _aid_buttons[i]
			if i >= roguelike.aid_offer.size():
				button.visible = false
				continue
			button.visible = true
			var row := GameConfig.roguelike_aid_def(String(roguelike.aid_offer[i]))
			var cost := int(row.get("cost", 0))
			button.text = String(row.get("name", "")) if cost <= 0 else "%s（%d 补给）" % [String(row.get("name", "")), cost]
			button.tooltip_text = String(row.get("blurb", ""))
			button.disabled = roguelike.supply < cost
			button.custom_minimum_size = Vector2(520.0, UiStyle.MIN_SIZE.y)
	_refresh_aid_tray()


func _refresh_aid_tray() -> void:
	if _aid_tray == null or roguelike == null:
		return
	var show := roguelike.phase == Roguelike.Phase.PREPARE and roguelike.starter_chosen \
			and not roguelike.aid_pending
	var prop_index: Array[int] = []
	var module_index: Array[int] = []
	if show:
		for i in range(roguelike.aid_cards.size()):
			var card: Dictionary = roguelike.aid_cards[i]
			var row := GameConfig.roguelike_aid_def(String(card.get("aid_id", "")))
			if String(row.get("group", "")) == "prop":
				prop_index.append(i)
			else:
				module_index.append(i)
	_sync_aid_cards(_aid_prop_box, prop_index, show and not prop_index.is_empty(), "prop", true)
	_sync_aid_cards(_aid_tray, module_index, show and not module_index.is_empty(), "module", false)


func _sync_aid_cards(box: Container, indices: Array[int], visible_now: bool, sig_key: String,
		in_column: bool) -> void:
	if box == null:
		return
	box.visible = visible_now
	if not visible_now:
		_aid_card_sig[sig_key] = ""
		return
	var parts: Array[String] = []
	for i in indices:
		var card: Dictionary = roguelike.aid_cards[i]
		parts.append("%d:%s:%s" % [int(card.get("uid", 0)), str(bool(card.get("placed", false))), str(int(card.get("ready_round", 1)))])
	var sig := "%d|%s" % [roguelike.round_index, "|".join(parts)]
	if sig == String(_aid_card_sig.get(sig_key, "")):
		return
	_aid_card_sig[sig_key] = sig
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for i in indices:
		box.add_child(_make_aid_card_button(i, in_column))


func _make_aid_card_button(index: int, in_column: bool) -> Button:
	var card: Dictionary = roguelike.aid_cards[index]
	var row := GameConfig.roguelike_aid_def(String(card.get("aid_id", "")))
	var button := Button.new()
	button.name = "AidCard_%d" % index
	var label := String(row.get("name", "援助"))
	if bool(card.get("placed", false)):
		label += "（已放置）"
	elif roguelike.round_index < int(card.get("ready_round", 1)):
		label += "（第 %d 回合）" % int(card["ready_round"])
	button.text = label
	button.tooltip_text = String(row.get("blurb", ""))
	button.disabled = bool(card.get("placed", false)) or roguelike.round_index < int(card.get("ready_round", 1)) or roguelike.aid_pending
	if in_column:
		button.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH - 40.0, 40.0)
		button.clip_text = true
	UiStyle.decorate_chip(button)
	button.mouse_entered.connect(_hover.bind(button, true))
	button.mouse_exited.connect(_hover.bind(button, false))
	button.pressed.connect(_on_aid_card.bind(index))
	return button


## 手里还有没消耗掉的援助战场道具（战术模块不算，它们仍在底栏）。
func _has_aid_prop_card() -> bool:
	if roguelike == null:
		return false
	for raw in roguelike.aid_cards:
		var card: Dictionary = raw
		var row := GameConfig.roguelike_aid_def(String(card.get("aid_id", "")))
		if String(row.get("group", "")) == "prop":
			return true
	return false


func _on_difficulty_pressed(index: int) -> void:
	if roguelike == null:
		return
	var ids: Array = GameConfig.ROGUELIKE_DIFFICULTY_ORDER
	if index < 0 or index >= ids.size():
		return
	roguelike.choose_difficulty(String(ids[index]))
	_refresh()

func _refresh_difficulty() -> void:
	if _difficulty_scrim == null or roguelike == null:
		return
	_difficulty_scrim.visible = roguelike.phase == Roguelike.Phase.PREPARE and not roguelike.difficulty_chosen

func _build_choice_eye() -> void:
	_eye_button = Button.new()
	_eye_button.name = "ChoiceEye"
	_eye_button.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_eye_button.offset_left = 16.0
	_eye_button.offset_top = -30.0
	_eye_button.offset_right = 76.0
	_eye_button.offset_bottom = 30.0
	_eye_button.icon = _eye_texture()
	_eye_button.expand_icon = true
	_eye_button.focus_mode = Control.FOCUS_NONE
	_eye_button.tooltip_text = "隐藏选择界面。隐藏后可以移动镜头，鼠标保持显示，不能转向。可以点单位查看，不能操作。按 Tab 进入自由视角。再点一次眼睛恢复。"
	_eye_button.visible = false
	_eye_button.pressed.connect(_on_eye_pressed)
	add_child(_eye_button)
	_eye_hint = _make_label("", FONT_TINY, COLOR_TEXT, "ChoiceEyeHint")
	_eye_hint.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_eye_hint.offset_left = 16.0
	_eye_hint.offset_top = 36.0
	_eye_hint.offset_right = 240.0
	_eye_hint.offset_bottom = 64.0
	_eye_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_eye_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_hint.visible = false
	add_child(_eye_hint)
	_choice_notice = _make_label("", FONT_MID, COLOR_TEXT, "ChoiceNotice")
	_choice_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_choice_notice.offset_top = 140.0
	_choice_notice.offset_bottom = 190.0
	_choice_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_notice.visible = false
	add_child(_choice_notice)


func _eye_texture() -> Texture2D:
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 48:
		for x in 48:
			var px := (float(x) - 23.5) / 18.0
			var py := (float(y) - 23.5) / 11.0
			if px * px + py * py > 1.0:
				continue
			var pupil := Vector2(px, (float(y) - 23.5) / 18.0).length()
			var color := Color(0.93, 0.95, 0.98, 0.95)
			if pupil < 0.22:
				color = Color(0.06, 0.08, 0.12, 1.0)
			elif pupil < 0.38:
				color = Color(0.45, 0.72, 0.95, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _on_eye_pressed() -> void:
	if roguelike == null:
		return
	roguelike.choice_hidden = not roguelike.choice_hidden
	_apply_choice_look()
	_refresh()


func _refresh_choice_eye() -> void:
	if _eye_button == null or roguelike == null:
		return
	var gate := roguelike.selection_gate()
	if not gate:
		roguelike.choice_hidden = false
	_eye_button.visible = gate
	_eye_button.modulate = Color(1.0, 0.94, 0.45) if roguelike.choice_hidden else Color(0.55, 0.60, 0.68)
	if _eye_hint != null:
		_eye_hint.visible = gate and roguelike.choice_hidden
		_eye_hint.text = "再点一次眼睛恢复"
	if _choice_notice != null:
		var note := roguelike.choice_notice_text()
		_choice_notice.visible = note != ""
		_choice_notice.text = note
	_apply_choice_look()


func _apply_choice_look() -> void:
	if camera_rig == null or roguelike == null:
		return
	if roguelike.phase != Roguelike.Phase.PREPARE:
		return
	if camera_rig.mode == CameraRig.Mode.OVERVIEW:
		return
	camera_rig.release_look()


func _on_starter_pressed(index: int) -> void:
	if roguelike == null:
		return
	roguelike.choose_starter(index)
	_refresh()

func _refresh_starter() -> void:
	if _starter_scrim == null or roguelike == null:
		return
	_starter_scrim.visible = roguelike.phase == Roguelike.Phase.PREPARE and roguelike.difficulty_chosen \
			and not roguelike.starter_chosen and not roguelike.choice_hidden
	if not _starter_scrim.visible:
		return
	for i in range(_starter_buttons.size()):
		var button := _starter_buttons[i]
		if i >= roguelike.starter_choices.size():
			button.visible = false
			continue
		button.visible = true
		var pair: Array = roguelike.starter_choices[i]
		var parts: Array = []
		for type_id in pair:
			var id := String(type_id)
			parts.append("%s（权重 %d · 一队 %d 个）" % [
					GameConfig.profile_name(id), int(GameConfig.profile(id)["weight"]),
					GameConfig.roguelike_squad_size(int(GameConfig.profile(id)["weight"]))])
		button.text = "%s   +   %s" % [parts[0], parts[1]]
		button.custom_minimum_size = Vector2(0.0, UiStyle.MIN_SIZE.y)
	var widest := UiStyle.MIN_SIZE.x
	for button in _starter_buttons:
		if button.visible:
			widest = maxf(widest, button.get_minimum_size().x)
	for button in _starter_buttons:
		button.custom_minimum_size = Vector2(widest, UiStyle.MIN_SIZE.y)

## 商店那一栏：本回合额度 / 已解锁数 / 每张卡的文字与浓淡。
## ⚠️ 只改 `text` 与 `modulate`，**不重建节点**（重建会让"按下与抬起之间"的点击失效 —— bug 2c 的老坑）。
## 商店（右侧那一栏）刷新：**只列已解锁的兵种**（用户口径（1））+ 卡片两套文案 + 解锁按钮的状态。
## ⚠️ 未解锁的那一栏由 `_refresh_unlock_panel()` 管（同一时刻只有一处显示某个兵种）。
func _refresh_shop() -> void:
	if _shop_box == null or roguelike == null:
		return
	var show := roguelike.phase == Roguelike.Phase.PREPARE and roguelike.starter_chosen \
			and not (roguelike.choice_hidden and roguelike.selection_gate())
	_shop_panel.visible = show
	_prop_panel.visible = show
	## 左上角这一栏：买过信标、买过遣返，或手里还有援助战场道具，才露出。
	## 信标卡本身仍只在买过之后出现（见 `_refresh_props()`）。
	_beacon_panel.visible = show and (roguelike.has_beacon() or roguelike.has_recall() or _has_aid_prop_card())
	if not show:
		_unlock_panel.visible = false
		return
	var limit := roguelike.squad_limit_this_round()
	var left := limit - roguelike.bought_this_round
	var limit_note := ""
	if roguelike.has_round_buff(GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT):
		limit_note += "·含紧急招募"
	if roguelike.aid_extra_squads > 0:
		limit_note += "·含部署专家"
	_shop_status.text = "本回合还可买 %d 队（上限 %d%s）· 已解锁 %d / %d" % [
			maxi(left, 0), limit, limit_note,
			roguelike.pool.size(), GameConfig.roguelike_buyable_types().size()]
	_shop_message.text = roguelike.last_message
	_refresh_props()
	## ---- 兵种卡：只显示已解锁的；文字 = 名字（悬停 = 一队花多少补给）----
	for type_id in _chips.keys():
		var button: Button = _chips[type_id]
		var id := String(type_id)
		var weight := int(GameConfig.profile(id)["weight"])
		var size := GameConfig.roguelike_squad_size(weight)
		var unlocked: bool = roguelike.pool.has(id)
		button.visible = unlocked                      ## 未解锁的**不列出来**（用户口径（1））
		if not unlocked:
			continue
		var cost := roguelike.squad_cost(id)
		_chip_base_text[id] = GameConfig.profile_name(id)
		_chip_hover_text[id] = "%d 补给" % cost
		_apply_chip_text(button, id, button.is_hovered())
		button.tooltip_text = "买一整队 %s（权重 %d）：%d 个，花 %d 补给（每回合最多 %d 队）" % [
				GameConfig.profile_name(id), weight, size, cost, GameConfig.ROGUELIKE_SQUADS_PER_ROUND]
		button.modulate = Color(1, 1, 1, 1) if roguelike.can_buy(id) else Color(0.72, 0.72, 0.78, 1)
	## ---- 「解锁单位」按钮：还有没解锁的就亮着，并报个数 ----
	var locked := _locked_types()
	if _unlock_button != null:
		_unlock_button.visible = true
		_unlock_button.text = "解锁单位（%d）" % locked.size() if not locked.is_empty() else "解锁单位"
		_unlock_button.disabled = locked.is_empty()
	_refresh_unlock_panel(locked)

## 未解锁单位那一栏（点「解锁单位」才出现；解锁光了自动收起）。
## ⚠️ **卡片自身的 `visible` / 文字每次刷新都要写**（不能因为"面板这会儿没开"就早退）：否则第一次点开时
## 拿到的是建卡那一刻的默认状态（实测踩到：17 张卡全亮着，其中 2 张其实已解锁）。
func _refresh_unlock_panel(locked: Array) -> void:
	if _unlock_panel == null:
		return
	if locked.is_empty():
		_unlock_open = false
	for type_id in _unlock_cards.keys():
		var button: Button = _unlock_cards[type_id]
		var id := String(type_id)
		var is_locked: bool = not roguelike.pool.has(id)
		button.visible = is_locked
		if not is_locked:
			continue
		var unlock := roguelike.unlock_cost(id)
		_chip_base_text[id] = GameConfig.profile_name(id)
		_chip_hover_text[id] = "解锁 %d" % unlock
		_apply_chip_text(button, id, button.is_hovered())
		button.tooltip_text = "解锁 %s：花 %d 补给（= ⌊一队总权重 ÷ %d⌋，每回合最多解锁 %d 个）" % [
				GameConfig.profile_name(id), unlock, GameConfig.ROGUELIKE_UNLOCK_DIVISOR,
				GameConfig.ROGUELIKE_UNLOCK_PER_ROUND]
		button.modulate = Color(1, 1, 1, 1) if roguelike.can_unlock(id) else Color(0.70, 0.70, 0.78, 1)
	_unlock_panel.visible = _unlock_open
	if not _unlock_panel.visible:
		return
	## ⚠️ 普通 `Label` **不解析 markdown** —— 这里不能写 `**…**`（实测会原样显示星号）
	_unlock_hint.text = "未解锁的兵种：卡上写名字，鼠标移上去看解锁价；点一下即解锁（每回合最多 %d 个）" % \
			GameConfig.ROGUELIKE_UNLOCK_PER_ROUND

# ---------------------------------------------------------------- 指挥所增益面板（第三块）
## **贴左上角**的一栏（不是全屏挡屏）：点场地上的指挥所才出现，点别处自动收起。
## ⚠️ 为什么不挡屏：买增益是**反复操作**（三级要买三次），挡住场地会逼玩家每买一次先关掉；
## 那种"一次性选择"（初始四选一）才值得挡屏。
## ⚠️ 面板 `MOUSE_FILTER_STOP`（点在自己身上不会穿到场地 ⇒ 不会顺手把面板关掉）；
## 另有「关闭」按钮与"点空地收起"两条同义的退路（后者由玩法侧清空 `selected_post`）。
func _build_buff_panel() -> void:
	## ⚠️ **第六轮**：锚点从左上角改成**顶部中央** —— 左下角让给兵种购买面板之后，左侧那一列
	##（信标 76~154 + 本面板 ~330 高）与购买面板（~324 高）在 750 px 的屏幕上排不下，而它只在
	## 点指挥所时才出现 ⇒ 落在顶部中央，既不压左侧两栏、也不压右下角那块。
	_buff_panel = _make_floating_panel("BuffPanel", Control.PRESET_CENTER_TOP)

	var col := VBoxContainer.new()
	col.name = "BuffBox"
	col.add_theme_constant_override("separation", 10)
	_buff_panel.add_child(col)
	_buff_title = _make_label("", FONT_MID, COLOR_TEXT, "BuffTitleLabel")
	col.add_child(_buff_title)
	_buff_note = _make_label("", FONT_TINY, COLOR_DIM, "BuffNoteLabel")
	_buff_note.custom_minimum_size = Vector2(BUFF_PANEL_WIDTH, 0.0)
	_buff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_buff_note)
	## 八行 = 持续三条（右方）+ 单回合**五**条（左方，第六块加「紧急招募」、第三轮加「精英招募」）；
	## **一次全建好**，靠 `visible` 决定该露哪几条。
	## ⚠️ 第六块另加一行**移动信标**（`BeaconRow`）：它是**右方**那条（持续侧）的东西，但不是"增益等级"，
	## 所以没混进这个 kind 表 —— 它有自己的按钮与刷新分支（见 `_build_beacon_row()`）。
	for kind in [GameConfig.ROGUELIKE_BUFF_ATTACK, GameConfig.ROGUELIKE_BUFF_DEFENSE,
			GameConfig.ROGUELIKE_BUFF_UPGRADE, GameConfig.ROGUELIKE_ROUND_BUFF_SUPPLY,
			GameConfig.ROGUELIKE_ROUND_BUFF_RANGE, GameConfig.ROGUELIKE_ROUND_BUFF_SPEED,
			GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT, GameConfig.ROGUELIKE_ROUND_BUFF_ELITE]:
		var row := HBoxContainer.new()
		row.name = "BuffRow_%s" % kind
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var label := _make_label("", FONT_SMALL, COLOR_TEXT, "BuffLabel_%s" % kind)
		label.custom_minimum_size = Vector2(BUFF_LABEL_WIDTH, 0.0)
		row.add_child(label)
		var button := Button.new()
		button.name = "BuffBuy_%s" % kind        ## 种类写在 `_` 之后（§3.1）
		UiStyle.decorate_chip(button)
		button.custom_minimum_size = Vector2(120.0, 36.0)
		button.mouse_entered.connect(_hover.bind(button, true))
		button.mouse_exited.connect(_hover.bind(button, false))
		button.pressed.connect(_on_buff_pressed.bind(kind))
		row.add_child(button)
		_buff_rows[kind] = {"row": row, "label": label, "button": button}
	## 第六块：**移动信标**那一行（右方指挥所卖的道具，不是等级增益 ⇒ 单独一行、单独刷新）
	_beacon_row = HBoxContainer.new()
	_beacon_row.name = "BeaconRow"
	_beacon_row.add_theme_constant_override("separation", 10)
	col.add_child(_beacon_row)
	_beacon_label = _make_label("", FONT_SMALL, COLOR_TEXT, "BeaconLabel")
	_beacon_label.custom_minimum_size = Vector2(BUFF_LABEL_WIDTH, 0.0)
	_beacon_row.add_child(_beacon_label)
	_beacon_button = Button.new()
	_beacon_button.name = "BeaconBuyButton"
	UiStyle.decorate_chip(_beacon_button)
	_beacon_button.custom_minimum_size = Vector2(120.0, 36.0)
	_beacon_button.mouse_entered.connect(_hover.bind(_beacon_button, true))
	_beacon_button.mouse_exited.connect(_hover.bind(_beacon_button, false))
	_beacon_button.pressed.connect(_on_beacon_pressed)
	_beacon_row.add_child(_beacon_button)
	_recall_row = HBoxContainer.new()
	_recall_row.name = "RecallRow"
	_recall_row.add_theme_constant_override("separation", 10)
	col.add_child(_recall_row)
	_recall_label = _make_label("", FONT_SMALL, COLOR_TEXT, "RecallLabel")
	_recall_label.custom_minimum_size = Vector2(BUFF_LABEL_WIDTH, 0.0)
	_recall_row.add_child(_recall_label)
	_recall_button = Button.new()
	_recall_button.name = "RecallBuyButton"
	UiStyle.decorate_chip(_recall_button)
	_recall_button.custom_minimum_size = Vector2(120.0, 36.0)
	_recall_button.mouse_entered.connect(_hover.bind(_recall_button, true))
	_recall_button.mouse_exited.connect(_hover.bind(_recall_button, false))
	_recall_button.pressed.connect(_on_recall_pressed)
	_recall_row.add_child(_recall_button)
	var close := Button.new()
	close.name = "BuffCloseButton"
	close.text = "关闭"
	UiStyle.decorate_chip(close)
	close.custom_minimum_size = Vector2(120.0, 36.0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_on_buff_close_pressed)
	col.add_child(close)

func _on_buff_pressed(kind: String) -> void:
	if roguelike == null:
		return
	## 面板上永远是"某一座指挥所的那一套" ⇒ 按它分流（玩法侧还会再判一次能不能买）
	if roguelike.post_sells_round_buffs(roguelike.selected_post):
		roguelike.buy_round_buff(kind)
	else:
		roguelike.buy_buff(kind)
	_refresh()

func _on_buff_close_pressed() -> void:
	if roguelike != null:
		roguelike.select_post("")
	_refresh()

## 买一个移动信标（第六块）：**5 补给只花这一次**（第七块起买过即永久拥有）；**放到场上**是第二步（从道具行那张卡拖）。
func _on_beacon_pressed() -> void:
	if roguelike == null:
		return
	roguelike.buy_beacon()
	_refresh()

func _on_recall_pressed() -> void:
	if roguelike == null:
		return
	roguelike.buy_recall()
	_refresh()

func _on_recall_card_pressed() -> void:
	if roguelike == null:
		return
	roguelike.begin_recall()
	_refresh()

## 面板刷新：只改 `text` / `disabled` / `visible`，**不重建节点**（同 §7.1 那条硬规则）。
func _refresh_buff_panel() -> void:
	if _buff_panel == null or roguelike == null:
		return
	var show := roguelike.phase == Roguelike.Phase.PREPARE and roguelike.starter_chosen \
			and roguelike.selected_post != ""
	_buff_panel.visible = show
	if not show:
		return
	var round_side := roguelike.post_sells_round_buffs(roguelike.selected_post)
	_buff_title.text = "左方指挥所 · 单回合增益" if round_side else "右方指挥所 · 持续增益"
	_buff_note.text = _posts_note()
	for kind in _buff_rows.keys():
		var row: Dictionary = _buff_rows[kind]
		var applies: bool = _is_round_kind(String(kind)) == round_side
		(row["row"] as Control).visible = applies
		if not applies:
			continue
		var label: Label = row["label"]
		var button: Button = row["button"]
		var name := roguelike.buff_name(String(kind))
		if round_side:
			var price := roguelike.round_buff_price(String(kind))
			label.text = "%s（%s）" % [name, "免费 · 下回合 −30" if price == 0 else "%d 补给" % price]
			var bought := roguelike.has_round_buff(String(kind))
			button.text = "已买" if bought else "买"
			button.disabled = bought
			button.tooltip_text = roguelike.round_buff_block_reason(String(kind))
		else:
			var price := roguelike.buff_price(String(kind))
			label.text = "%s：%s" % [name, roguelike.buff_level_text(String(kind))]
			button.text = "已满级" if price < 0 else "买（%d）" % price
			button.disabled = price < 0
			button.tooltip_text = roguelike.buff_block_reason(String(kind))
	## 第六块：**移动信标**那一行（只在右方 = 持续侧出现）—— 它卖的是**道具**，不是等级增益
	if _beacon_row != null:
		_beacon_row.visible = not round_side
		if not round_side:
			var beacon_price := GameConfig.ROGUELIKE_BEACON_PRICE
			var owned := roguelike.has_beacon()
			## ⚠️ 第七块：买过一次就永久可用（每回合免费重新部署）⇒ 按钮变"已买"并停用
			_beacon_label.text = "移动信标：%s" % ("已买（每回合免费重放）" if owned else "买一次（%d 补给）" % beacon_price)
			_beacon_button.text = "已买" if owned else "买（%d）" % beacon_price
			_beacon_button.disabled = owned or roguelike.supply < beacon_price
			_beacon_button.tooltip_text = "买下后到**道具行**那张「移动信标」卡上：**每回合**都能免费重新部署（点卡 → 拖到场上 → 点两下画路线，每段最远 %0.0f m）。战斗开始时半径 %0.0f m 内的我方单位会沿这条路线移动，**朝向**也一起对齐到第一段方向；信标本身不会被锁定、也不会被打掉。" % [
					GameConfig.ROGUELIKE_BEACON_SEGMENT_MAX, GameConfig.ROGUELIKE_BEACON_RADIUS]
	if _recall_row != null:
		_recall_row.visible = not round_side
		if not round_side:
			var recall_price := GameConfig.ROGUELIKE_RECALL_PRICE
			var owned := roguelike.has_recall()
			_recall_label.text = "遣返：%s" % ("已买（每回合一次）" if owned else "买一次（%d 补给）" % recall_price)
			_recall_button.text = "已买" if owned else "买（%d）" % recall_price
			_recall_button.disabled = owned or roguelike.supply < recall_price
			_recall_button.tooltip_text = "买下后到左上道具行，每回合把「遣返」拖到一队兵上。这一队永久离场，退回买队和升级所花补给的一半。科技不算。"

# ---------------------------------------------------------------- 选中队伍面板（第四块用户口径③）
## 两块**浮动面板**的公共壳子（指挥所增益面板与选中队伍面板共用同一套外观与位置口径）。
## ⚠️ 抽出来是因为它俩**互斥地占同一片**（选一队时玩法侧会把 `selected_post` 收掉）⇒
## 外观只能有一处出处，否则改一处忘一处、两块面板会长得不一样。
## ⚠️ **2026-09-27 第六轮**：位置不再写死左上角 —— 用户把"选中单位"那块指到了**右下角**、
## 而"指挥所增益"挪到了**顶部中央**（左下角让给兵种购买面板之后，左侧那一列排不下它）。
## `anchor` 用 `Control.LayoutPreset` 传进来（默认值仍是左上角，保持既有调用点不变）。
func _make_floating_panel(panel_name: String, anchor: int = Control.PRESET_TOP_LEFT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.set_anchors_preset(anchor as Control.LayoutPreset)
	match anchor:
		Control.PRESET_TOP_LEFT:
			panel.offset_left = 16.0
			panel.offset_top = BUFF_PANEL_TOP
			panel.grow_vertical = Control.GROW_DIRECTION_END
		Control.PRESET_CENTER_TOP:
			panel.offset_top = BUFF_PANEL_TOP
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
			panel.grow_vertical = Control.GROW_DIRECTION_END
		Control.PRESET_BOTTOM_RIGHT:
			panel.offset_right = -16.0
			panel.offset_bottom = -BOTTOM_INSET
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			panel.offset_left = 16.0
			panel.offset_bottom = -BOTTOM_INSET
			panel.grow_horizontal = Control.GROW_DIRECTION_END
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	style.border_color = Color(0.32, 0.36, 0.44, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	add_child(panel)
	return panel

## 选中一队的"最终数值"面板（用户口径③："点击我方单位可以选中这一队单位，查看其最终数值
## （比如攻击、血量，要把增益的增幅也算进去）"）。
## ⚠️ 数据只有一个来源：`Roguelike.squad_stats()` 返回的那本**小字典**（数字 / 字符串）——
## 界面自己再乘一遍增益必然会与玩法侧算法分叉，所以"最终值"一律由玩法侧算好。
func _build_squad_panel() -> void:
	## ⚠️ **第七轮**：用户"选中单位跳出来的那个界面移至左下角" ⇒ 锚点从右下角改成左下角
	##（与兵种购买面板对调）。
	_squad_panel = _make_floating_panel("SquadPanel", Control.PRESET_BOTTOM_LEFT)
	var col := VBoxContainer.new()
	col.name = "SquadBox"
	col.add_theme_constant_override("separation", 10)
	_squad_panel.add_child(col)
	_squad_title = _make_label("", FONT_MID, COLOR_TEXT, "SquadTitleLabel")
	col.add_child(_squad_title)
	_squad_body = _make_label("", FONT_SMALL, COLOR_TEXT, "SquadBodyLabel")
	_squad_body.custom_minimum_size = Vector2(BUFF_PANEL_WIDTH, 0.0)
	_squad_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_squad_body)
	_squad_note = _make_label("", FONT_TINY, COLOR_DIM, "SquadNoteLabel")
	_squad_note.custom_minimum_size = Vector2(BUFF_PANEL_WIDTH, 0.0)
	_squad_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_squad_note)
	## 升级按钮（2026-09-27 第三轮：用户"满经验时可以在步兵阶段选中单位进行升级"）——
	## ⚠️ 与"关闭"同一行：面板本身不高，多一行会往下压到场地。
	var buttons := HBoxContainer.new()
	buttons.name = "SquadButtons"
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	_squad_upgrade = Button.new()
	_squad_upgrade.name = "SquadUpgradeButton"
	_squad_upgrade.text = "升级"
	UiStyle.decorate_chip(_squad_upgrade)
	_squad_upgrade.custom_minimum_size = Vector2(170.0, 36.0)
	_squad_upgrade.pressed.connect(_on_squad_upgrade_pressed)
	buttons.add_child(_squad_upgrade)
	_squad_upgrade_all = Button.new()
	_squad_upgrade_all.name = "SquadUpgradeAllButton"
	_squad_upgrade_all.text = "全部升级"
	UiStyle.decorate_chip(_squad_upgrade_all)
	_squad_upgrade_all.custom_minimum_size = Vector2(170.0, 36.0)
	_squad_upgrade_all.pressed.connect(_on_squad_upgrade_all_pressed)
	buttons.add_child(_squad_upgrade_all)
	var close := Button.new()
	close.name = "SquadCloseButton"
	close.text = "关闭"
	UiStyle.decorate_chip(close)
	close.custom_minimum_size = Vector2(120.0, 36.0)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_on_squad_close_pressed)
	buttons.add_child(close)

## 点「升级」：走玩法侧的公开方法（界面不直接写玩法字段，R-07）
func _on_squad_upgrade_pressed() -> void:
	if roguelike != null:
		roguelike.upgrade_squad(roguelike.selected_squad)
	_refresh()

func _on_squad_upgrade_all_pressed() -> void:
	if roguelike != null:
		roguelike.upgrade_same_type(roguelike.selected_squad)
	_refresh()

func _on_squad_close_pressed() -> void:
	if roguelike != null:
		roguelike.select_squad(-1)           ## 走玩法侧的公开方法：界面不直接写玩法字段（R-07）
	_refresh()

## 面板刷新：只改 `text` / `visible`，**不重建节点**（同 §7.1 那条硬规则）。
## ⚠️ **2026-09-27**：这块面板现在也用来显示**敌方单位**（用户："敌方单位也可以被我方选中，只用来查看信息"）
## ⇒ 数据源在 `squad_stats()`（我方一队）与 `foe_stats(index)`（敌方一队）之间二选一，**键完全对齐**，
## 所以下面这半段文案两条路共用；差别只在标题、以及最后那两条"能不能拖"的注（敌方恒为只读）。
func _refresh_squad_panel() -> void:
	if _squad_panel == null or roguelike == null:
		return
	var viewing_foe := roguelike.selected_squad < 0 and roguelike.selected_foe_squad >= 0
	var show := roguelike.phase == Roguelike.Phase.PREPARE and roguelike.starter_chosen \
			and (roguelike.selected_squad >= 0 or viewing_foe)
	_squad_panel.visible = show
	if not show:
		return
	var s: Dictionary = roguelike.foe_stats(roguelike.selected_foe_squad) if viewing_foe \
			else roguelike.squad_stats(roguelike.selected_squad)
	if s.is_empty():
		_squad_panel.visible = false          ## 那一队已经不在场上了（阵亡 / 全灭 / 被撤掉）
		return
	var is_foe := bool(s.get("foe", false))
	var view_only := roguelike.choice_hidden and roguelike.selection_gate()
	if is_foe:
		## 2026-09-27：敌方也**按队**显示（用户同日裁决给敌方建了"队"记账）⇒ 标题格式与我方对齐，
		## 只把"选中"换成"查看敌方"、并把末行注解换成只读说明（见下面 `notes`）。
		_squad_title.text = "查看敌方：%s（一队 %d 个 · 在场 %d）" % [s["name"], int(s["count"]), int(s["alive"])]
	else:
		var verb := "查看" if view_only else "选中"
		_squad_title.text = "%s：%s（一队 %d 个 · 在场 %d）" % [verb, s["name"], int(s["count"]), int(s["alive"])]
	var dps := float(s["attack_speed"])
	var lines: Array = []
	## 等级与经验（2026-09-27 第三轮）：**我方**才有等级条，敌方只报等级（它不升级）。
	## ⚠️ 倍率口径按用户原话写进文案："等级每增 1 级，攻 / 血各 +1 倍" ⇒ 最终值已在上面两行里体现。
	var lv := int(s.get("level", 1))
	var lv_max := int(s.get("level_max", GameConfig.ROGUELIKE_LEVEL_MAX))
	if is_foe:
		lines.append("等级 %d 级（攻 / 血 ×%d）" % [lv, maxi(lv, 1)])
	else:
		var cost := int(s.get("xp_cost", 0))
		if cost > 0:
			lines.append("等级 %d / %d 级（攻 / 血 ×%d）· 经验 %d / %d" % [lv, lv_max, maxi(lv, 1), int(s.get("xp", 0)), cost])
		else:
			lines.append("等级 %d / %d 级（攻 / 血 ×%d）· 已满级" % [lv, lv_max, maxi(lv, 1)])
	lines.append("生命 %d / %d" % [int(s["hp_now"]), int(s["hp_max"])])
	## ⚠️ **2026-09-27 修显示**（用户："升级之后只有血量改了，伤害数值错误，应为 90"）：原先只写
	## `伤害 45 × 1.00 = 90` —— 那个 1.00 是**队伍倍率**，等级的 ×2 藏在结果里 ⇒ 等式看着不成立。
	## 现在把**两个独立乘区**都摊开写：面板伤害 × 队伍倍率 × 等级倍率 = 最终伤害（数字自己会对上）。
	var tech_mult := float(s.get("tech_mult", 1.0))
	if is_equal_approx(tech_mult, 1.0):
		lines.append("伤害 %d × 队伍 %0.2f × 等级 %0.2f = %d" % [int(s["damage"]), float(s["damage_mult"]),
				float(s.get("level_mult", 1.0)), int(s["damage_final"])])
	else:
		lines.append("伤害 %d × 科技 %0.2f × 队伍 %0.2f × 等级 %0.2f = %d" % [int(s["damage"]), tech_mult,
				float(s["damage_mult"]), float(s.get("level_mult", 1.0)), int(s["damage_final"])])
	lines.append("攻击速度 %0.2f 次/秒（每 %0.2f s 一次）" % [dps, 1.0 / maxf(dps, 0.01)])
	lines.append("%s %0.1f m" % ["射程" if bool(s["is_ranged"]) else "接触距离", float(s["reach"])])
	lines.append("移速 %0.2f m/s" % float(s["speed"]))
	lines.append("权重 %d · 质量 %0.1f" % [int(s["weight"]), float(s["mass"])])
	_squad_body.text = "\n".join(lines)
	## 下面这半段解释"这些最终值是怎么来的"（增益来路）+ 这一队能不能拖 / 现在是横是竖
	var notes: Array = []
	if not is_equal_approx(float(s["damage_mult"]), 1.0):
		notes.append("进攻指令：伤害 ×%0.2f" % float(s["damage_mult"]))
	if int(s["defense_level"]) > 0:
		notes.append("防御指令：生命 +%d%%（%d 级）" % [
				int(GameConfig.ROGUELIKE_BUFF_STEP * 100.0) * int(s["defense_level"]), int(s["defense_level"])])
	if bool(s["is_ranged"]) and float(s["range_bonus"]) > 0.0:
		notes.append("射程增加：+%0.0f m（本回合）" % float(s["range_bonus"]))
	if float(s["speed_bonus"]) > 0.0:
		notes.append("速度增加：+%0.1f m/s（本回合）" % float(s["speed_bonus"]))
	if float(s.get("armor", 0.0)) > 0.0:
		notes.append("护甲升级：每次受伤 −%d" % int(s["armor"]))
	if float(s.get("kb_bonus", 0.0)) > 0.0:
		notes.append("防御模式：攻击击退 +%d" % int(s["kb_bonus"]))
	if float(s.get("shield_max", 0.0)) > 0.0:
		notes.append("魔法护盾：%d" % int(s["shield_max"]))
	if bool(s["debuff"]):
		notes.append("⚠ 指挥所被摧毁：移速 / 伤害 −90%%，持续中")
	if is_foe:
		notes.append("敌方单位（只读）：不能拖动、不能旋转 —— 这里只是用来看它的最终数值")
	elif view_only:
		notes.append("只读：完成选择前不能拖动、旋转、升级或遣返")
	elif bool(s["movable"]):
		notes.append("本回合买的 ⇒ 可拖动换位；拖动中按右键旋转 90°（当前%s）"
				% ("竖" if bool(s["rotated"]) else "横"))
	else:
		notes.append("起手部队 / 往回合买的 ⇒ 不能移动位置")
	## 升级按钮（只有我方一队有它）：能升 ⇒ 亮着并写价；不能升 ⇒ 灰掉并把原因写在按钮上
	if _squad_upgrade != null:
		if is_foe or view_only:
			_squad_upgrade.visible = false
		else:
			_squad_upgrade.visible = true
			var price := int(s.get("upgrade_price", 0))
			var can := bool(s.get("can_upgrade", false))
			_squad_upgrade.disabled = not can
			if can:
				_squad_upgrade.text = "升级到 %d 级（%d 补给）" % [int(s.get("level", 1)) + 1, price]
				notes.append("经验已满 ⇒ 可以升级（花 %d 补给）" % price)
			else:
				_squad_upgrade.text = "升级（%s）" % String(s.get("upgrade_reason", "不可用"))
	if _squad_upgrade_all != null:
		if is_foe or view_only:
			_squad_upgrade_all.visible = false
		else:
			_squad_upgrade_all.visible = true
			var all_count := int(s.get("upgrade_all_count", 0))
			var all_price := int(s.get("upgrade_all_price", 0))
			_squad_upgrade_all.disabled = all_count <= 0
			if all_count > 0:
				_squad_upgrade_all.text = "全部升级（%d 队 · %d 补给）" % [all_count, all_price]
			else:
				_squad_upgrade_all.text = "全部升级（没有可升的同类）"
	_squad_note.text = "\n".join(notes)

## 四个"单回合增益"的 kind 集合（与持续那三个分开）—— 2026-09-27 加了「精英招募」
func _is_round_kind(kind: String) -> bool:
	return kind == GameConfig.ROGUELIKE_ROUND_BUFF_SUPPLY \
			or kind == GameConfig.ROGUELIKE_ROUND_BUFF_RANGE \
			or kind == GameConfig.ROGUELIKE_ROUND_BUFF_SPEED \
			or kind == GameConfig.ROGUELIKE_ROUND_BUFF_RECRUIT \
			or kind == GameConfig.ROGUELIKE_ROUND_BUFF_ELITE

## 面板顶部那行说明：我方两座指挥所的血量（活着才报血量，死了报"已毁"）+ 减益警告 + 欠账
func _posts_note() -> String:
	var parts: Array = []
	for side in [GameConfig.ROGUELIKE_POST_SIDE_ROUND, GameConfig.ROGUELIKE_POST_SIDE_STEADY]:
		var tag := "左" if side == GameConfig.ROGUELIKE_POST_SIDE_ROUND else "右"
		var post: Unit3D = roguelike.our_post(side)
		if post != null and is_instance_valid(post) and post.alive:
			parts.append("%s %d / %d" % [tag, int(post.hp), int(post.max_hp)])
		else:
			parts.append("%s 已毁" % tag)
	var text := "我方指挥所：%s" % " · ".join(parts)
	if roguelike.arena != null and roguelike.arena.debuff_active(0):
		text += "\n⚠ 指挥所被摧毁：全体移速 / 伤害 −90%%，持续中"
	if roguelike.loan_debt() > 0:
		text += "\n下一回合开始将扣 %d 补给（紧急补给的欠账）" % roguelike.loan_debt()
	return text

# ---------------------------------------------------------------- 交互
func _on_start_battle_pressed() -> void:
	roguelike.start_battle()

func _on_next_round_pressed() -> void:
	roguelike.next_round()

## 浮层那颗按钮：相位决定它是「下一回合」还是「重新开始」（文本在 `_refresh_overlay()` 里设）。
func _on_overlay_pressed() -> void:
	if roguelike.phase == Roguelike.Phase.GAME_OVER:
		roguelike.restart_game()
		return
	roguelike.next_round()

func _on_overview_pressed() -> void:
	if camera_rig != null:
		camera_rig.toggle_overview()

# ---------------------------------------------------------------- 暂停菜单的**界面侧契约**
## 与 `hud.gd` / `sandbox_hud.gd` 的同名方法对称（见 `pause_menu.gd` 的文件头）。
## ⚠️ **肉鸽四个相位都能唤出**（与沙盒"任何相位都能唤出"同一口径）⇒ 这里恒为真。
## ⚠️ 玩法侧原本那个 `Roguelike.phase_allows_pause()` 因此**从来没有调用点**，已按用户裁决**删除**
##（不留在那里当摆设 —— 同 `08_naming.md#3.3` 对"废弃但保留"的两次登记是不同性质：那两个是常量，这是死方法）。
func pause_allowed() -> bool:
	return roguelike != null

## ⚠️ 中间那一项随相位而变，**与沙盒同一套口径**：准备阶段**不给**「重新开始」（玩家正在花钱，
## 误点会把整局清空 —— 与沙盒"布兵阶段不许出现重新开始"是同一条理由）；战斗中给「结束回合」；
## 结算 / 结束后什么都不给（浮层上已经有对应的按钮了）。
func pause_actions() -> Array:
	if roguelike == null:
		return []
	if roguelike.phase == Roguelike.Phase.FIGHTING:
		return [{"text": "结束回合", "action": "end_round"}]
	return []

func pause_action(action: String) -> void:
	if action == "end_round" and roguelike != null:
		roguelike.end_round()        ## 它自己会解除暂停（见 `Roguelike.end_round()`）

# ---------------------------------------------------------------- 小工具
## 造一个**带名字**的文字标签。⚠️ `node_name` **必填**（`08_naming.md#3.1`："动态生成的节点也必须命名"）
## —— 去掉默认值就是为了让"忘了命名"变成**编译错误**，而不是一个只在运行时才发现的空洞。
## ⚠️ 2026-09-26 第六块：三个模式 HUD 的每一行文字都在各自的这个口子上统一命名（本项目的"Label 收口"），
## 名字一律取"这个标签在界面里的角色"的 PascalCase（与它存进的那个变量同名、去掉下划线）；
## **同一概念跨 HUD 必须同名**（例：三个 HUD 的视角提示都叫 `CameraHintLabel`，见 `08_naming.md#1.4`）。
func _make_label(text: String, size: int, color: Color, node_name: String) -> Label:
	var label := UiStyle.make_label(text, size, color)
	label.name = node_name
	return label
