class_name MatchSpeed
extends RefCounted
## 倍速（2026-11-01 新增；用户："加个加速，放右上角来个图标，点击 x2、再点 x1"）。
##
## ⚠️ **为什么不能只写 `Engine.time_scale = 2`** —— 这是本项目**已经踩过一次**的坑
##（教训记在 `99_decisions.md`，代码侧的注记在 `scripts/game/debug_autoplay.gd` 的文件头）：
## 全项目的玩法计时一律走 `Time.get_ticks_msec()`（不变量 I-13），**不受 `Engine.time_scale` 影响**；
## 而移动与物理走 `_physics_process(delta)`，**受影响**。只改 `time_scale` 的结果是
## "人跑 2 倍快、出手还是实时" ⇒ 8× 那次实测单场从 ~23 游戏秒变成 ~60 游戏秒。
##
## ⇒ 倍速 = **两半一起缩放**：
##   ① `Engine.time_scale` —— 缩放移动 / 物理 / 相机 / 动画（凡是走 `delta` 的自动跟上）；
##   ② 每物理帧把所有**绝对毫秒的截止时刻整体前移** —— 缩放出手节拍 / 冷却 / 眩晕 / 冲刺时长 /
##      比赛上限（凡是走 `Time.get_ticks_msec()` 的靠这一步跟上）。
## 前移复用暂停补偿那一套（`MatchPause` + `Unit3D` 的 `_*_ms` 属性扫描），**只是方向相反**：
## 暂停是"往后推 Δ"（把停掉的那段补回来），倍速是"往前拉 Δ"（让游戏时间走快）。
##
## ⚠️ **不变量 I-13 仍然成立**：计时依旧是绝对毫秒、依旧不随帧率漂移 ——
## 每帧前移的量来自 `delta` 且**带余数结转**（`_carry_ms`）⇒ 掉帧时前移总量不变。
##
## ⚠️ 已知边界（记在这里，别当 bug 修）：
##   · 三套 HUD 的**刷新节流**（每 100 ms 一次）走的是墙上时钟 ⇒ 倍速下 UI 刷新频率不变（这正是想要的）；
##   · `Roguelike` 自己那份"回合 / 结算"的绝对时刻**不在这条链上**（它不在 `units` 组里、也不是 arena）
##     ⇒ 生存模式的倍速只加速战斗本身，不加速回合流程计时。

const NORMAL := 1.0
const FAST := 2.0

static var _speed: float = NORMAL
static var _carry_ms := 0.0        ## 不足 1 ms 的余量结转下一帧（不结转的话取整误差会让倍速略慢）

static func speed() -> float:
	return _speed

static func set_speed(value: float) -> void:
	_speed = maxf(NORMAL, value)
	Engine.time_scale = _speed
	if _speed <= NORMAL:
		_carry_ms = 0.0

## 点一下换档（1× ⇄ 2×），返回**新档位的文字**（HUD 直接拿去写按钮）。
static func toggle() -> String:
	set_speed(FAST if _speed <= NORMAL else NORMAL)
	return label()

static func label() -> String:
	return "2×" if _speed > NORMAL else "1×"

## 每个物理帧调一次。⚠️ 挂在 `arena._physics_process` **最前面**：父节点先于单位 ⇒
## 这一步一定发生在"任何人出手 / 走位"之前，不会出现"这一帧按旧时刻、下一帧才追上"。
## `delta` 用引擎给的那一份（**已经被 `time_scale` 缩放过**的）就对。
static func tick(delta: float, tree: SceneTree, arena: Node) -> void:
	if _speed <= NORMAL:
		return
	## 本帧模拟推进了 `delta × 1000` 毫秒（游戏内时间），而真实时间只过了 `delta / _speed` 秒
	## ⇒ 截止时刻要往前拉 (1 − 1/_speed) × delta × 1000 毫秒，两边的"时间感"才一致。
	_carry_ms += (_speed - NORMAL) / _speed * delta * 1000.0
	var pull := int(_carry_ms)
	if pull <= 0:
		return
	_carry_ms -= float(pull)
	MatchPause.pull_deadlines(tree, arena, pull)
