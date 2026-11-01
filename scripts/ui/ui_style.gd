class_name UiStyle
extends RefCounted
## 选项按钮的**统一外观**（开始界面的「开始游戏」与暂停菜单的三个按钮共用这一份）。
##
## 依据：`05_ui_hud.md#9.2`（开始界面）与 `#10.2`（暂停菜单）都写着"同一套样式"；`07_file_layout.md#5` 的依赖方向。
## ⚠️ 存在的理由：这两套按钮原先**各自持有一份完全相同的**样式常量 —— 而 `hud.gd` 与 `start_screen.gd`
## 是 `scripts/ui/` 下的**兄弟**，互相引用会变成"兄弟依赖"（依赖规则只允许自上而下）。抽成这个**同级工具**之后，
## 两边都只依赖它 ⇒ 样式只有一处事实来源，"改一处忘了另一处"的风险消失。
## 全是**表现参数**，按既有惯例不进 `GameConfig`（不变量 I-15 管的是可调**玩法**数值）。

const FONT := 30                                          ## 常态字号 px
const FONT_HOVER := 42                                    ## 悬停**目标**字号 px（= 常态字号 × `HOVER_GROW`，见那里的说明）
const MIN_SIZE := Vector2(280.0, 66.0)
const TEXT := Color(0.92, 0.93, 0.95)                     ## 常态白
const TEXT_HOVER := Color(0.98, 0.72, 0.25)               ## 悬停金 = HUD 的"警告橙"，全项目唯一一份
const PANEL := Color(0.06, 0.07, 0.09, 0.88)
const PANEL_HOVER := Color(0.13, 0.15, 0.19, 0.94)
const BORDER := Color(0.42, 0.46, 0.52)

# ---------------------------------------------------------------- 字号档位与调色板（HUD 也读这里）
## 依据 `05_ui_hud.md#6`（字号档位与对比度口径）。2026-09-25 从 `hud.gd` 搬到这里：
## 沙盒模式的 HUD（`sandbox_hud.gd`）是它的**兄弟**、要用同一套字号与颜色，而兄弟之间不能互相引用
##（`07_file_layout.md#5`）—— 两套 HUD 现在都从这里取，"改一处忘另一处"的风险随之消失。
## ⚠️ 队色**刻意与 `GameConfig.team_color()`（赤羽卫 / 青锋卫）不同值**：那条是 3D 单位与看台的
## 材质色（受光照影响），这里是界面文字色（要在深底上读得清）。两者不是同一件事，别合并。
const FONT_LARGE := 34
const FONT_MID := 22
const FONT_SMALL := 16
const FONT_TINY := 14
const COLOR_TEAM := [Color(0.95, 0.36, 0.34), Color(0.38, 0.68, 0.98)]
const COLOR_TEXT := TEXT
const COLOR_DIM := Color(0.68, 0.71, 0.76)
const COLOR_WARN := TEXT_HOVER
const COLOR_OK := Color(0.40, 0.93, 0.50)

## 右下角那行**视角操作提示**的文案。2026-09-25 从 `hud.gd` 搬到这里：沙盒模式的 HUD 要显示
## 完全相同的一行（用户口径："相机 / 自由视角的操作与竞猜模式一样"），而两套 HUD 是兄弟。
## ⚠️ **2026-09-25 其后修过（用户："沙盒模式中的操作提示过期了"）**：第十一条把镜头按键重映射过
##（`cam_up` E→**Space**、`cam_down` Q→**Shift**、`cam_boost` Shift→**Ctrl**，权威口径见 `05_ui_hud.md#5.1`），
## 而这行提示当时没跟着改，还写着"Q/E 升降 · Shift 加速" ⇒ **三处全错**。
## ⚠️ **以后再改键位记得回来改这一行** —— 它是唯一一处"把键位写给玩家看"的文案。
## 前进 / 后退 / 左移 / 右移 / 自由视角读 `InputBindings`，玩家在设置里改过就显示改后的键。
static func camera_hint() -> String:
	return "视角：%s/%s/%s/%s 移动镜头 · 鼠标转向 · Space/Shift 升降 · Ctrl 加速 · 1/2/3 锁定 · R 回自由 · %s 自由视角（点鼠标左/右键退出）" % [
		InputBindings.key_label("cam_forward"),
		InputBindings.key_label("cam_left"),
		InputBindings.key_label("cam_back"),
		InputBindings.key_label("cam_right"),
		InputBindings.key_label("cam_overview"),
	]

## 建一个统一口径的 `Label`（字号 + 字色）。两套 HUD 共用这一份（`hud.gd#_make_label` 现在只是转调）。
static func make_label(text: String, size: int, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## 悬停**不再改大小**（2026-10-01）：原先用 `HOVER_GROW` / `CHIP_GROW` 把控件 `scale` 放大。
## 缩放不进容器的最小尺寸，但画出来的按钮和包着它的面板都会变大。
## 现在悬停只换字色和底色，尺寸锁在 `custom_minimum_size` 上。
const HOVER_GROW := 1.0
const CHIP_GROW := 1.0

## 套用"常态 / 悬停"两套字色 + **原地缩放**。
## ⚠️ 必须连 `font_hover_color` 一起覆盖 —— 主题里它的优先级**高于** `font_color`，
## 只改后者的话鼠标一悬停就被主题顶回去（开始界面第一版踩过）。
static func apply_option_hover(button: Button, hovered: bool) -> void:
	_apply_hover(button, hovered, TEXT_HOVER, TEXT, HOVER_GROW)

## 兵种小卡的悬停（同一套机制，只是字色与倍数不同）。
static func apply_chip_hover(button: Button, hovered: bool) -> void:
	_apply_hover(button, hovered, CHIP_TEXT_HOVER, CHIP_TEXT, CHIP_GROW)

## 两套悬停共用的实现：只换字色。`grow` 留下是为了调用点不用改，大小始终是 1。
static func _apply_hover(button: Button, hovered: bool, hot: Color, cold: Color, _grow: float) -> void:
	var color := hot if hovered else cold
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(slot, color)
	button.scale = Vector2.ONE
	button.pivot_offset = Vector2.ZERO

static func option_style(bg: Color, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = BORDER
	style.set_border_width_all(border)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	return style

## 一次性把按钮装扮成统一外观（尺寸 + 常态字色 + 四档样式盒）。
## ⚠️ `focus_mode = NONE`：本作没有键盘 UI 导航，而 `Space` 是 `cam_up` / 引擎内置 `ui_accept`，
## 按钮一旦持有焦点，"升高镜头"会顺带把它按下去（开始界面第一版的口径）。
static func decorate_option(button: Button) -> void:
	button.custom_minimum_size = MIN_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", FONT)
	apply_option_hover(button, false)
	## 四档边框同一宽度：悬停把边框从 2 改成 3 会把按钮的最小尺寸撑大一圈。
	button.add_theme_stylebox_override("normal", option_style(PANEL, 2))
	button.add_theme_stylebox_override("hover", option_style(PANEL_HOVER, 2))
	button.add_theme_stylebox_override("pressed", option_style(PANEL, 2))
	button.add_theme_stylebox_override("focus", option_style(PANEL, 2))

# ---------------------------------------------------------------- 兵种小卡（沙盒模式的底部兵种栏）
## 与「开始游戏」那一套的差别：**尺寸小、字号小、能选中**。
## 选中态 = 金色边框 + 暖底，与"悬停只是字色变金"区分开 —— 玩家要一眼看出"现在手里是哪种兵"。
## ⚠️ `CHIP_FONT_HOVER` / `FONT_HOVER` 现在**只是"放大幅度"的出处**（`CHIP_GROW` ≈ 21/18、
## `HOVER_GROW` = 42/30）—— 字号本身在悬停时不再变，见 `apply_option_hover()` 的说明。
const CHIP_FONT := 18
const CHIP_FONT_HOVER := 21
const CHIP_MIN_SIZE := Vector2(118.0, 62.0)
const CHIP_TEXT := Color(0.88, 0.90, 0.93)
const CHIP_TEXT_HOVER := Color(0.98, 0.72, 0.25)
const CHIP_PANEL := Color(0.09, 0.10, 0.13, 0.90)
const CHIP_PANEL_HOVER := Color(0.16, 0.18, 0.22, 0.95)
const CHIP_PANEL_SELECTED := Color(0.22, 0.16, 0.06, 0.96)
const CHIP_BORDER_SELECTED := Color(0.98, 0.72, 0.25)

static func chip_style(bg: Color, border: int, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(border)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6)
	return style

## 选中 / 未选中的四档样式盒。
## ⚠️ 必须**三档一起盖**：只改 `normal` 的话鼠标一悬停就掉回灰色（`hud.gd#ALL_GLOW_SLOTS` 同款教训）。
static func apply_chip_selected(button: Button, selected: bool) -> void:
	if not selected:
		button.add_theme_stylebox_override("normal", chip_style(CHIP_PANEL, 2, BORDER))
		button.add_theme_stylebox_override("hover", chip_style(CHIP_PANEL_HOVER, 2, BORDER))
		button.add_theme_stylebox_override("pressed", chip_style(CHIP_PANEL, 2, BORDER))
		button.add_theme_stylebox_override("focus", chip_style(CHIP_PANEL, 2, BORDER))
		return
	button.add_theme_stylebox_override("normal", chip_style(CHIP_PANEL_SELECTED, 3, CHIP_BORDER_SELECTED))
	button.add_theme_stylebox_override("hover", chip_style(CHIP_PANEL_SELECTED, 3, CHIP_BORDER_SELECTED))
	button.add_theme_stylebox_override("pressed", chip_style(CHIP_PANEL_SELECTED, 3, CHIP_BORDER_SELECTED))
	button.add_theme_stylebox_override("focus", chip_style(CHIP_PANEL_SELECTED, 3, CHIP_BORDER_SELECTED))

static func decorate_chip(button: Button) -> void:
	button.custom_minimum_size = CHIP_MIN_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", CHIP_FONT)
	apply_chip_hover(button, false)
	apply_chip_selected(button, false)

# ---------------------------------------------------------------- 齿轮（暂停菜单入口）
## **程序化画**（`Image` 逐像素 + 缩放平滑），不依赖字体里有没有 `⚙` 字形 ——
## 与本项目"零外部资源"的口径一致（血条贴图也是这么生成的，见 `unit_factory.gd#health_bar_texture()`）。
## 2026-09-25：从 `hud.gd` 搬到这里 —— 经典 HUD 与沙盒 HUD 用的是**同一个**齿轮。
const GEAR_BUTTON_PX := 40.0
const GEAR_IMAGE_PX := 40
const GEAR_TEETH := 8
const GEAR_COLOR := Color(0.90, 0.91, 0.94)

## 装一个齿轮按钮（位置 / 命名 / 接线由调用方负责：两套 HUD 的挂点不同）。
static func decorate_gear(button: Button) -> void:
	button.custom_minimum_size = Vector2(GEAR_BUTTON_PX, GEAR_BUTTON_PX)
	button.icon = gear_texture()
	button.tooltip_text = "菜单（Esc）"
	button.focus_mode = Control.FOCUS_NONE           ## Space 是 cam_up / ui_accept，别误触发
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## 程序化画一个齿轮贴图（画 2× 再缩到 1× ⇒ 边缘平滑）。
static func gear_texture() -> ImageTexture:
	var px := GEAR_IMAGE_PX * 2
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(float(px) * 0.5, float(px) * 0.5)
	var r_tooth := float(px) * 0.42
	var r_disc := float(px) * 0.30
	var r_hole := float(px) * 0.13
	var sector := TAU / float(GEAR_TEETH)
	for y in px:
		for x in px:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
			var dist := d.length()
			if dist < r_hole:
				continue                                  ## 中心孔：透明
			var in_tooth := false
			if dist <= r_tooth:
				var t := fposmod(atan2(d.y, d.x), sector) / sector
				in_tooth = absf(t - 0.5) < 0.30            ## 齿：每个扇区正中一段
			if dist <= r_disc or in_tooth:
				img.set_pixel(x, y, GEAR_COLOR)
	img.resize(GEAR_IMAGE_PX, GEAR_IMAGE_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- 倍速按钮（2026-11-01）
## 右上角那颗"1× / 2×"。⚠️ 三套 HUD 用**同一个**按钮、同一份接线（与齿轮同一条口径），
## 免得三处各写一套、改一处忘两处。倍速**本身**的实现在 `MatchSpeed`，这里只管图标与点击。
const SPEED_BUTTON_PX := Vector2(58.0, 40.0)
const SPEED_CHEVRONS := 2           ## 两个向右的尖角 ⇒ 一眼是"快进"，不用写字解释
## ⚠️ 快捷键 `F`（Fast）—— 2026-11-01 修 bug：用户"战斗开始后无法点加速，只能在战斗前设置"。
## 原因是战斗阶段 `CameraRig._fight_started` 把光标锁进窗口（`MOUSE_MODE_CAPTURED`）⇒ **鼠标点不到
## 任何 UI**，齿轮因此只在押注 / 结算出现。但倍速恰恰是战斗里最想用的那个 ⇒ 给它一条**不看鼠标**的路：
## `Button.shortcut` 由窗口直接派发键盘事件，与鼠标模式无关 ⇒ 战斗中按 `F` 照样能切。
##（`1`=技能 / `X`=肩位 / `Q`=交还 / WASD=镜头 都已占用，`F` 是空的。）
const SPEED_SHORTCUT_KEY := KEY_F

static func decorate_speed(button: Button) -> void:
	button.custom_minimum_size = SPEED_BUTTON_PX
	button.icon = speed_texture()
	button.focus_mode = Control.FOCUS_NONE        ## 同齿轮：`Space` 是 cam_up，别让按钮抢焦点
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## 建好一颗倍速按钮（**接线也在这里**）：点一下 2×、再点一下 1×，按钮上的字由 `MatchSpeed` 给。
## 调用方只需要 `row.add_child(...)`，剩下的三套 HUD 完全一致。
static func make_speed_button(node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	decorate_speed(button)
	## 快捷键：见 `SPEED_SHORTCUT_KEY`。⚠️ `Button.shortcut` 只在按钮**可见且在树里**时才派发
	## ⇒ 三套 HUD 都必须让它常显（不能跟着齿轮一起藏）。
	var key_event := InputEventKey.new()
	key_event.keycode = SPEED_SHORTCUT_KEY
	key_event.physical_keycode = SPEED_SHORTCUT_KEY      ## 物理键位一起写：换键盘布局也不失灵
	var shortcut := Shortcut.new()
	shortcut.events = [key_event]
	button.shortcut = shortcut
	button.text = MatchSpeed.label()
	button.tooltip_text = "倍速（F）：点一下 2×、再点一下 1×"
	button.pressed.connect(_on_speed_pressed.bind(button))
	return button

## 切倍速并把新档位的文字写回按钮。**抽成具名函数**而不是内联 lambda：三套 HUD 共用同一份接线，
## 具名函数才能在调用栈里看出"是谁切的倍速"（`08_naming.md` 的可读性口径）。
static func _on_speed_pressed(button: Button) -> void:
	button.text = MatchSpeed.toggle()

## 两个向右的尖角，画在 40×40 里（与齿轮同一档尺寸）。
static func speed_texture() -> ImageTexture:
	var px := GEAR_IMAGE_PX
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in SPEED_CHEVRONS:
		var x0 := 6 + i * 11
		for t in 11:
			var top := int(round(8.0 + float(t) * 1.2))
			var bottom := int(round(32.0 - float(t) * 1.2))
			for y in range(top, bottom + 1):
				img.set_pixel(x0 + t, y, GEAR_COLOR)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- 顶栏读数图标（2026-11-01）
## 肉鸽顶栏的**补给 / 生命**两格：以前只有文字（"补给 12" / "血量 8 / 20"），玩家分不清哪一行是哪一个
##（用户："补给和生命感觉有点不太明显，可以加个图案后跟数字"）⇒ 各配一个图案，图案后面只跟数字。
## ⚠️ 与齿轮**同一套做法**：`Image` 逐像素画 → `resize(LANCZOS)` → `ImageTexture`。
## 既不用外部资源，也不依赖字体里有没有对应字形（齿轮那段的注释写了同样的理由）。
const STAT_ICON_PX := 28
const SUPPLY_FILL := Color(0.95, 0.78, 0.35)   ## 箱体：与顶栏"补给"那个暖色同族
const SUPPLY_LINE := Color(0.40, 0.28, 0.10)   ## 外框与捆带
const HP_FILL := Color(0.88, 0.26, 0.32)       ## 心：与"血量告警"那个橙红同族

## 补给箱：外框 + 对角捆带 + 中缝 ⇒ 一眼是"箱子"，不会跟心形混。
static func supply_texture() -> ImageTexture:
	var px := STAT_ICON_PX * 2
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var lo := float(px) * 0.14
	var hi := float(px) - lo
	var mid := float(px) * 0.5
	var band := float(px) * 0.075
	for y in px:
		for x in px:
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			if fx < lo or fx > hi or fy < lo or fy > hi:
				continue
			var on_edge := fx < lo + 2.0 or fx > hi - 2.0 or fy < lo + 2.0 or fy > hi - 2.0
			var on_diag := absf((fx - lo) - (fy - lo)) < band or absf((fx - lo) + (fy - hi)) < band
			var on_seam := absf(fy - mid) < band * 0.7
			img.set_pixel(x, y, SUPPLY_LINE if (on_edge or on_diag or on_seam) else SUPPLY_FILL)
	img.resize(STAT_ICON_PX, STAT_ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

## 心：经典心形不等式 (x² + y² − 1)³ − x²·y³ ≤ 0。⚠️ `ny` 已经把屏幕 y（向下）翻正了。
static func heart_texture() -> ImageTexture:
	var px := STAT_ICON_PX * 2
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in px:
		for x in px:
			var nx := (float(x) + 0.5) / float(px) * 2.6 - 1.3
			var ny := 1.15 - (float(y) + 0.5) / float(px) * 2.6
			var a := nx * nx + ny * ny - 1.0
			if a * a * a - nx * nx * ny * ny * ny <= 0.0:
				img.set_pixel(x, y, HP_FILL)
	img.resize(STAT_ICON_PX, STAT_ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

## "图案 + 数字"的一格（顶栏读数用）。⚠️ **只建一次**，刷新只改返回的那个 `label.text`
##（硬规则 `05_ui_hud.md#7.1`：节点只构建一次，禁止 `queue_free()` 重建）。
## 返回 `{ root: HBoxContainer, label: Label }`，调用方把 `root` 挂进顶栏、自己留着 `label`。
static func make_icon_label(icon: Texture2D, text: String, size: int, color: Color, node_name: String) -> Dictionary:
	var root := HBoxContainer.new()
	root.name = node_name
	root.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.name = "Icon"
	pic.texture = icon
	pic.custom_minimum_size = Vector2(STAT_ICON_PX, STAT_ICON_PX)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE    ## 贴图不参与最小尺寸计算，格子大小只由上面那行定
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE      ## 别把顶栏的鼠标事件吃掉
	root.add_child(pic)
	var label := make_label(text, size, color)
	label.name = "Value"
	root.add_child(label)
	return {"root": root, "label": label}


## 战斗定格时的上下两条。不挡鼠标，继续靠 Enter。
static func make_battle_banner() -> Dictionary:
	var root := Control.new()
	root.name = "Overlay"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	var top := PanelContainer.new()
	top.name = "HoldTop"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 108.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.03, 0.04, 0.07, 0.90)
	top_style.set_content_margin_all(8)
	top.add_theme_stylebox_override("panel", top_style)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top_box.name = "HoldTopBox"
	top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	var title := make_label("", FONT_LARGE, COLOR_TEXT)
	title.name = "OverlayTitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(title)
	var body := make_label("", FONT_SMALL, COLOR_DIM)
	body.name = "OverlayBodyLabel"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(body)
	var bottom := PanelContainer.new()
	bottom.name = "HoldBottom"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -78.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.03, 0.04, 0.07, 0.90)
	bottom_style.set_content_margin_all(8)
	bottom.add_theme_stylebox_override("panel", bottom_style)
	root.add_child(bottom)
	var prompt := make_label("按[Enter]继续", FONT_MID, COLOR_TEXT)
	prompt.name = "HoldPrompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.add_child(prompt)
	return {"root": root, "title": title, "body": body}
