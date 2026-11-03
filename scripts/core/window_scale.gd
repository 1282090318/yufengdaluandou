class_name WindowScale
extends RefCounted
## 让"**不是 16:9**"的窗口也把界面和画面一起放大（高比矮、宽比窄两个方向都补）。
##
## 依据：**不变量 I-04 一个字没改** —— stretch 仍是 `canvas_items` + `expand`，基准仍是 1600×900
##（`project.godot` / `docs/bible/_index.md`）。这里只是在这套模式之上补一个运行时缩放档。
##
## ⚠️ 问题的根：`expand` 自己算的缩放系数是 **min(宽比, 高比)** ——
##   · 16:9 放大（1600×900 → 1920×1080 → 2560×1440）：宽比 = 高比 ⇒ 界面和画面一起放大 ✓
##   · 窗口变"高"（1600×1200：宽比 1.00 / 高比 1.33）：**取的是宽比** ⇒ 缩放卡在 1.00，
##     界面与画面都停在原尺寸，只是可见范围变高 —— 用户报的"界面不跟着放大"就是这一档。
##   · 窗口变"宽"（2560×1080：宽比 1.60 / 高比 1.20）：同理卡在 1.20，只多看见横向。
## 补法：按**没被取到的那个比值**算出想达到的缩放，再换算成 `Window.content_scale_factor`
##（它乘在 `expand` 自己算出的那个缩放上 ⇒ 实际缩放 = min(宽比, 高比) × 本因子），
## 于是 1600×1200 的实际缩放变成 1.33、逻辑分辨率变成 1200×900 —— 与 1600×900 下看到的一模一样，只是更大。
##
## ⚠️ **2026-11-03**：两个方向都补（用户："这次必须随着窗口能放大"，并同意改这条口径）。
## 补缩放会压缩**另一条边**的逻辑尺寸，所以两头各留一条下限：
##   · 变高 ⇒ 逻辑宽度 ≥ 基准宽的 75%（顶栏那排标签不被挤出去）
##   · 变宽 ⇒ 逻辑高度 ≥ 基准高的 90%（顶栏 / 下注面板还站得下）

## 基准分辨率从 `project.godot` 读（不在这里写死第二份，免得改了设置忘了这里）。
const BASE_WIDTH_KEY := "display/window/size/viewport_width"
const BASE_HEIGHT_KEY := "display/window/size/viewport_height"
const DEFAULT_BASE := Vector2(1600.0, 900.0)

## 逻辑宽度下限 = 基准宽的 **75%**。
## 补缩放会让逻辑分辨率变窄，太窄的话顶栏那一排标签（轮次 / 点数 / 两队存活 / 计时）会挤出右边。
## 4:3（1600×1200）刚好落在这一档 ⇒ 逻辑分辨率 1200×900，界面比原来大 1/3，顶栏也还装得下。
const LOGICAL_MIN_WIDTH_RATIO := 0.75

## 逻辑高度下限 = 基准高的 **90%**（⚠️ **2026-11-03 新增**，用户同意"无论窗口什么形状都等比放大"）。
## 窗口比 16:9 **更宽**（21:9 / 超宽屏）时也按宽比补齐 ⇒ 逻辑分辨率变**矮**，太矮的话顶栏和下注面板没地方站。
## 留 90% 这条下限：2560×1080（21:9）只补到逻辑 1920×810，画面已经明显变大，面板也还站得下。
const LOGICAL_MIN_HEIGHT_RATIO := 0.90

var _window: Window = null
var _base: Vector2 = DEFAULT_BASE


## 装到主窗口上，并立刻按当前尺寸算一次。**返回值要留着**（`RefCounted` 被回收后信号就断了）。
func install(window: Window) -> void:
	if window == null:
		return
	_window = window
	_base = Vector2(
		float(ProjectSettings.get_setting(BASE_WIDTH_KEY, DEFAULT_BASE.x)),
		float(ProjectSettings.get_setting(BASE_HEIGHT_KEY, DEFAULT_BASE.y)))
	if not _window.size_changed.is_connected(refresh):
		_window.size_changed.connect(refresh)
	refresh()


## 按当前窗口尺寸重算 `content_scale_factor`。窗口尺寸变化时由信号调进来，也可以手动调。
func refresh() -> void:
	if _window == null or _base.x <= 0.0 or _base.y <= 0.0:
		return
	## 无头跑测试时没有真窗口（尺寸是假的），别去动它。
	if DisplayServer.get_name() == "headless":
		return
	var win := Vector2(_window.size)
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var ratio_w := win.x / _base.x
	var ratio_h := win.y / _base.y
	var engine_scale := minf(ratio_w, ratio_h)          ## `expand` 自己算出的那个（见文件头）
	if engine_scale <= 0.0:
		return
	## 目标 = **尽量填满窗口**：变高按高比补、变宽按宽比补，两头各留一条逻辑下限（见上面两个常量）。
	var want := engine_scale
	if ratio_h > ratio_w:
		want = minf(ratio_h, win.x / (_base.x * LOGICAL_MIN_WIDTH_RATIO))
	else:
		## ⚠️ **2026-11-03**：原来这一档**刻意不补**（"超宽只多看见横向"）—— 用户要的是"画面随窗口变大"，
		## 于是改成按宽比补，只受逻辑高度下限约束。
		want = minf(ratio_w, win.y / (_base.y * LOGICAL_MIN_HEIGHT_RATIO))
	want = maxf(want, engine_scale)                     ## 只放大、不缩小：窗口变小由 `expand` 自己管
	var factor := want / engine_scale
	if absf(factor - _window.content_scale_factor) < 0.0001:
		return
	_window.content_scale_factor = factor
