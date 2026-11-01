extends Node
## 全局事件总线（Autoload 名：Events）
##
## 职责：让"玩法层"与"表现层（相机 / HUD / 音效）"互不认识，只通过信号通信。
## 边界：这里不放任何状态，也不放任何数值。数值一律去 GameConfig。
## 依据：docs/bible/02_entities.md#5-分组与标签、07_file_layout.md#5-依赖方向

## —— 局流程 ——
signal phase_changed(phase: String)
signal round_started(round_index: int, roster_a: Array, roster_b: Array, wager: int)
signal match_finished(result: Dictionary)
signal game_over(summary: Dictionary)
## 暂停菜单点了「主菜单」：请求**拆掉当前比赛、回到开始界面**。
## ⚠️ 这个动作只有装配层（`main.gd`）做得了（要释放 Arena / CameraRig / Game / Hud 再重建开始界面），
## 而 UI 层按 `07_file_layout.md#5` **不允许认识 `main`** ⇒ 只能走总线。请求类用原形动词（§3.4）。
signal main_menu_requested

## —— 单位 ——
## 命名：一律用**过去式/分词**表达"已经发生"。注意 `hit` 的原形与过去式同形，
## 因此受击信号写成 `unit_was_hit` 以明确时态（见 08_naming.md#3.4）。
signal unit_spawned(unit: Node3D)
signal unit_died(unit: Node3D)
signal unit_was_hit(unit: Node3D)
signal unit_was_blocked(unit: Node3D)

## —— 表现层（供后续加音效 / 特效时挂接，见 06_audio.md#3-音频事件名清单）——
## 请求类信号用**原形动词**（`fx_request` = "请放这个特效"），与"已发生"类信号区分开。
signal fx_request(event: String, world_pos: Vector3)
