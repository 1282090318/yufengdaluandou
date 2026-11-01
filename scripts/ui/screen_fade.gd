class_name ScreenFade
extends CanvasLayer
## 结算后按 Enter 继续：先渐黑，黑透时换场，再渐亮。
## 时长与开始界面同一档（620 / 760 ms），按绝对时刻走，不用暂停树。

const FADE_OUT_MS := 620
const FADE_IN_MS := 760
const FADE_LAYER := 40

var _rect: ColorRect = null
var _from_ms: int = 0
var _phase: int = 0
var _on_black: Callable = Callable()


static func attach(host: Node) -> ScreenFade:
	var existing := host.get_node_or_null("ScreenFade") as ScreenFade
	if existing != null:
		return existing
	var fade := ScreenFade.new()
	fade.name = "ScreenFade"
	host.add_child(fade)
	return fade


func _ready() -> void:
	layer = FADE_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "FadeRect"
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## 已经在渐的时候返回 false，避免 Enter 连按把换场跑两遍。
func play(on_black: Callable) -> bool:
	if _phase != 0:
		return false
	_on_black = on_black
	_phase = 1
	_from_ms = Time.get_ticks_msec()
	_rect.color.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return true


func _process(_delta: float) -> void:
	if _phase == 0 or _rect == null:
		return
	var limit := FADE_OUT_MS if _phase == 1 else FADE_IN_MS
	var t := clampf(float(Time.get_ticks_msec() - _from_ms) / float(limit), 0.0, 1.0)
	if _phase == 1:
		_rect.color.a = smoothstep(0.0, 1.0, t)
		if t >= 1.0:
			_phase = 2
			_from_ms = Time.get_ticks_msec()
			var done := _on_black
			_on_black = Callable()
			if done.is_valid():
				done.call()
		return
	_rect.color.a = 1.0 - smoothstep(0.0, 1.0, t)
	if t >= 1.0:
		_phase = 0
		_rect.color.a = 0.0
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
