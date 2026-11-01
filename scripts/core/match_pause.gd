class_name MatchPause
extends RefCounted
## 暂停 / 恢复的**共用实现**（三个模式都要用：竞猜 `Game` / 沙盒 `Sandbox` / 肉鸽 `Roguelike`）。
##
## ⚠️ 为什么单独抽出来：三个模式都要"整棵树暂停 + 恢复时把时间补回来"，
## 而**树暂停不会停表** —— 本项目所有计时都是**绝对毫秒**（不变量 I-13）⇒ 暂停 N 秒后，赛程倒计时、
## 出手与技能冷却、眩晕、冲刺时长都会"凭空过去 N 秒"。
## ⇒ 恢复时必须把 arena / 相机 / **所有单位**的截止时刻一起后移 Δ。
##
## 全是静态方法（不持有状态）："暂停开始时刻"由调用方自己记（`Game._pause_from_ms` /
## `Sandbox._pause_from_ms` / `Roguelike._pause_from_ms`）。

## 暂停整棵树（⚠️ 调用方要保证"**菜单自己是 ALWAYS 模式**"，否则暂停后菜单也点不动）。
static func pause_tree(tree: SceneTree) -> void:
	if tree != null:
		tree.paused = true

static func resume_tree(tree: SceneTree) -> void:
	if tree != null:
		tree.paused = false

## 把"绝对毫秒的截止 / 起点时刻"整体后移 `delta_ms`。
## 单位那一侧走 `Unit3D.shift_deadlines()` 的**属性扫描**（所有 `_*_ms` 整型字段一起平移 ⇒ 以后新增计时字段不会漏）。
static func shift_deadlines(tree: SceneTree, arena: Node, camera_rig: Node, delta_ms: int) -> void:
	if delta_ms <= 0:
		return
	if arena != null and arena.has_method("shift_deadlines"):
		arena.shift_deadlines(delta_ms)
	if camera_rig != null and camera_rig.has_method("shift_deadlines"):
		camera_rig.shift_deadlines(delta_ms)
	if tree == null:
		return
	for node in tree.get_nodes_in_group("units"):
		var unit := node as Unit3D
		if unit != null:
			unit.shift_deadlines(delta_ms)
