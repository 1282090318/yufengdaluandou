class_name TutorialScreen
extends CanvasLayer
## 玩法说明 / 新手教程（2026-11-01 新增；用户："开始可以做个介绍，功能和玩法，新手教程"）。
##
## ⚠️ 这是全项目**第一个**"说明 / 教程"界面 —— 加它之前，scripts 侧搜 `tutorial|help|intro|教程|指引|新手`
## **一条都不命中**，玩家第一次进游戏只能靠自己猜。骨架照 `pause_menu.gd`（背后暗底吃点击 + 标题 + 返回），
## 内容排成**左列分章 + 右侧正文**两栏（参照 `codex_screen.gd` 的"名单 + 说明"）。
##
## ⚠️ 五条约束（都是本项目自己的硬规矩）：
##   ① **零外部资源**：正文是纯文本（`Label` + 自动换行），没有一张贴图、没有 .tscn；
##   ② **节点只建一次**（`05_ui_hud.md#7.1`）：翻章只改 `_body.text` 和按钮高亮，**不** `queue_free()` 重建；
##   ③ 层号 **22** —— 高于图鉴（21）/ 设置（20）/ 开始界面（10）⇒ 盖在它们之上；
##   ④ `PROCESS_MODE_ALWAYS`：开始界面那层不暂停，但本层**要能在暂停时被打开**（以后接暂停菜单）；
##   ⑤ 镜头键位**一律走 `UiStyle.camera_hint()`**，不另抄一份 —— `ui_style.gd#camera_hint()` 的注释记着
##      教训：键位改过一次而提示文案没跟着改 ⇒ 三处全错。借它就不会再过期。
##
## ⚠️ 文案口径只对"玩法本身"负责：兵种七项 / 技能 / 科技的**细节归图鉴**（`codex_screen.gd`），
## 这里不复制一份，免得两处各说各的。

## 层号（见文件头 ③）。
const TUTORIAL_LAYER := 22

## 章：**标题 + 正文**。⚠️ 正文只写"玩家此刻需要知道的事"，不写实现细节。
const CHAPTERS := [
	{
		"title": "一句话玩法",
		"body": "两队在场上自己开打，你**不开任何一个兵**。\n\n你要做的是\"开打之前\"的那几件事：押注、布阵、买兵；开打之后只看结果。\n\n全场只有一条索敌规则：每个单位永远打**距离最近的那个敌人**。没有仇恨、没有集火、没有走位微操 —— 阵型决定了谁打谁，所以摆位就是你的战术。",
	},
	{
		"title": "你要做什么",
		"body": "**布阵**：左边选兵种，再在己方半场点一下就摆下（脚印不能重叠）。\n\n**押注**（竞猜模式）：先选你认为会赢的一队，再押上点数，开打后看结果结算。\n\n**买兵**（生存模式）：每回合发补给 → 买兵 / 解锁 / 升级 → 挡住这一回合的进攻。\n\n**看打**：开战中你不下令，只观察。想细看就锁定一个单位跟着它。\n\n（镜头怎么操作见下面那条 —— 键位以你设置里的为准。）",
	},
	{
		"title": "三个模式",
		"body": "**竞猜模式**：十轮。每轮先押注、再开打；场上的兴奋圈会随时间收缩，把两队往中间赶。点数是你的筹码。\n\n**沙盒模式**：没有押注、没有圈、不判平局。两队阵容你自己摆，点\"开始战斗\"就看。想试\"这两个兵种对上谁赢\"，用它最快。\n\n**生存模式**（肉鸽）：十个回合。每回合领补给 → 布阵 → 挡住进攻。没拦住的敌人会在回合结束时扣你的**生命**，归零就结束。",
	},
	{
		"title": "战斗里在发生什么",
		"body": "**走位与出手都是自动的**：近战贴上去砍，远程站着放箭，攻城类有**最小射程**（贴太近反而打不到）。\n\n**出手有前摇**：先挥一下，到命中帧才结算伤害；被打断或眩晕，这一下就白挥了。\n\n**击退**：伤害会附带推力。重的单位推不动，轻的会被撞飞甚至撞死。\n\n**技能**：部分兵种带冲锋 / 跳跃 / 炎爆之类，满足条件就自己放（每个兵种每场有次数限制）。\n\n**打不到的人**：钻进地里的、影子形态的，不会被锁定 —— 索敌直接跳过它们。\n\n**结束**：一局有时限；双方长时间都够不着对方就判平局。",
	},
	{
		"title": "术语",
		"body": "**权重**：一个兵的\"身价\"。肉鸽里敌人的进攻强度也按权重算 —— 没拦住多少权重，就扣多少生命。\n\n**兴奋圈**：竞猜模式里随时间收缩的圈，逼着两队正面撞上。\n\n**补给**：生存模式的钱（买兵 / 解锁 / 升级 / 增益 / 道具 / 遣返都花它）。\n\n**生命**：生存模式里你的血量，归零即结束。\n\n**科技 / 增益**：生存模式里给兵种加成的效果。\n\n兵种的七项数值、特性、技能、科技的**具体数字都在图鉴里**，这里不重复。",
	},
]

## 背后暗底：趁它还在铺满全屏，**把点击全吃掉**（`05_ui_hud.md#7.1` 那个"点了没反应"的同类坑，
## 根因是浮层 `mouse_filter` 设成 IGNORE 之后，点击穿到了下面的按钮上）。
const SCRIM_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_MARGIN_X := 120.0
const PANEL_MARGIN_Y := 80.0
const CHAPTER_COL_W := 210.0

var _chapter_buttons: Array[Button] = []
var _body: Label = null
var _title: Label = null
var _current := 0
## 显隐一律走 `Control`（`_root.visible`），**不**用 `CanvasLayer` 自己的 `visible` ——
## 与图鉴 / 设置界面**同一套写法**（`CodexScreen._root`），已被验证过，不在这里另赌一种。
var _root: Control = null

func _ready() -> void:
	layer = TUTORIAL_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS      ## 见文件头 ④
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	add_child(root)
	_root = root

	var dim := ColorRect.new()
	dim.name = "Scrim"
	dim.color = SCRIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = PANEL_MARGIN_X
	panel.offset_right = -PANEL_MARGIN_X
	panel.offset_top = PANEL_MARGIN_Y
	panel.offset_bottom = -PANEL_MARGIN_Y
	panel.add_theme_stylebox_override("panel", UiStyle.option_style(UiStyle.PANEL, 2))
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title = UiStyle.make_label("玩法说明", UiStyle.FONT_LARGE, UiStyle.COLOR_TEXT)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	var cols := HBoxContainer.new()
	cols.name = "Columns"
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	var chapter_col := VBoxContainer.new()
	chapter_col.name = "ChapterColumn"
	chapter_col.custom_minimum_size.x = CHAPTER_COL_W
	chapter_col.add_theme_constant_override("separation", 8)
	cols.add_child(chapter_col)

	for i in CHAPTERS.size():
		var button := Button.new()
		button.name = "Chapter_%d" % i            ## `08_naming.md#3.1`：动态节点也要命名，序号放 `_` 之后
		button.text = String((CHAPTERS[i] as Dictionary)["title"])
		UiStyle.decorate_chip(button)
		button.custom_minimum_size.x = CHAPTER_COL_W
		button.mouse_entered.connect(UiStyle.apply_chip_hover.bind(button, true))
		button.mouse_exited.connect(UiStyle.apply_chip_hover.bind(button, false))
		button.pressed.connect(_on_chapter_pressed.bind(i))
		chapter_col.add_child(button)
		_chapter_buttons.append(button)

	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(scroll)

	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", UiStyle.FONT_MID)
	_body.add_theme_color_override("font_color", UiStyle.COLOR_TEXT)
	scroll.add_child(_body)

	## 镜头那一章要"以玩家自己改过的键位为准" ⇒ 直接借 `UiStyle.camera_hint()`（见文件头 ⑤）。
	var hint := UiStyle.make_label(UiStyle.camera_hint(), UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
	hint.name = "CameraHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	box.add_child(footer)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "返回（Esc）"
	UiStyle.decorate_option(back)
	back.pressed.connect(close)
	footer.add_child(back)

func open() -> void:
	_show_chapter(0)
	_root.visible = true

func close() -> void:
	_root.visible = false

func is_open() -> bool:
	return _root != null and _root.visible

func _show_chapter(index: int) -> void:
	if index < 0 or index >= CHAPTERS.size():
		return
	_current = index
	var row := CHAPTERS[index] as Dictionary
	_title.text = "玩法说明 · " + String(row["title"])
	_body.text = String(row["body"])
	for i in _chapter_buttons.size():
		UiStyle.apply_chip_selected(_chapter_buttons[i], i == index)

func _on_chapter_pressed(index: int) -> void:
	_show_chapter(index)

## Esc 收起自己。⚠️ 与图鉴同一口径：**只收自己**，不影响下面的开始界面
##（`05_ui_hud.md#15`：图鉴的「返回」和 Esc 只收起自己）。
func _input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
