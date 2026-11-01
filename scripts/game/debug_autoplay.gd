extends Node3D
## 调试用自动对局脚本（不参与正式发布，见 docs/bible/07_file_layout.md#6-新增文件时的操作顺序）
##
## 用途：无头环境下把整局 10 轮跑完，用来验证状态机、胜负判定与点数结算。
## 运行：godot --headless --path . res://scenes/main/debug_autoplay.tscn

## ⚠️ 2026-09-19：**1.0（真机速度）**，不再是 8× 快进。
## 原因：全项目的**玩法计时一律走 `Time.get_ticks_msec()`**（不变量 I-13，**不受 `Engine.time_scale` 影响**）——
## 攻击冷却、潜地四个闸门、眩晕、击退冷却、兴奋圈、平局/比赛上限全是绝对时刻；而移动与物理受 `time_scale`。
## 于是 8× 下"人跑得快 8 倍、出手还是实时"，实测单场从 ~23 游戏秒变成 ~60 游戏秒，**对局结果不能当平衡依据**。
## 代价：跑满十轮从 ~40 秒变成 ~4~5 分钟（真机时间）。要测平衡就用这个速度跑，或者用 `debug_balance_stats`（自带独立节拍）。
const SPEED := 1.0

var game: Game = null
var _stuck_samples: Dictionary = {}

func _ready() -> void:
	Engine.time_scale = SPEED
	var arena := Arena.new()
	arena.name = "Arena"
	add_child(arena)
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.setup(arena)
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.bind(arena, rig)
	game.setup_first_round()
	print("[autoplay] 开局：第 %d 轮 点数 %d 机会 %d" % [game.round_index, game.points, game.chances])
	print("[autoplay] A 队 %s（权重 %d）" % [GameConfig.roster_text(game.roster_a), GameConfig.roster_weight(game.roster_a)])
	print("[autoplay] B 队 %s（权重 %d）" % [GameConfig.roster_text(game.roster_b), GameConfig.roster_weight(game.roster_b)])
	_report_spawn_layout()
	var margin := 0.15
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	print("[autoplay] time_scale=%s 帧率余量=%s" % [str(SPEED), str(margin)])
	get_tree().create_timer(0.05).timeout.connect(_loop)

func _loop() -> void:
	while true:
		match game.phase:
			Game.Phase.BETTING:
				# 交替押 A / B，保证胜负两种情况都会被走到
				var pick := (game.round_index % 2)
				game.place_bet(pick, GameConfig.all_in_unlocked(game.round_index) and game.points > 0)
				print("[autoplay] 第 %d 轮 押 %d 投入 %d" % [game.round_index, pick, game.bet_wager])
			Game.Phase.FIGHTING:
				await get_tree().create_timer(0.4).timeout
				_report_states()
			Game.Phase.ROUND_RESULT:
				var entry: Dictionary = game.log_entries[-1]
				print("[autoplay] 第 %d 轮 结果：胜方 %s | %s | 判定 %s | 存活 %s | 耗时 %.1fs | 本次 %+d | 点数 %d | 机会 %d" % [
					entry["round"], str(entry["winner"]), str(entry["tag"]),
					str(entry.get("reason", "")), str(game.last_result.get("alive", [])),
					float(game.last_result.get("duration_ms", 0)) / 1000.0,
					int(entry["gain"]), game.points, game.chances])
				## 2026-09-18（轮 C）：续局只看轮次——观望机会不再是失败条件，
				## 破产由 `Game` 自己在 `_on_arena_ended()` 里判（点数归零）。
				if game.round_index < GameConfig.ROUND_COUNT:
					game.next_round()
				else:
					await get_tree().create_timer(0.2).timeout
			Game.Phase.GAME_OVER:
				var s := game.summary
				print("[autoplay] === 结束 最终点数 %d 最高 %d 押中 %d/%d 剩余观望机会 %d 跑满十轮=%s 点生点=%s ===" % [
					int(s["points"]), int(s["peak_points"]), int(s["successes"]), int(s["rounds_played"]),
					int(s["chances"]), str(s["reached_end"]), str(s["full_support"])])
				await get_tree().create_timer(0.2).timeout
				get_tree().quit()
				return
			_:
				await get_tree().create_timer(0.2).timeout

## 出生点布局诊断：确认"己方后半段成簇刷新"生效，并报告簇的横向铺开程度
func _report_spawn_layout() -> void:
	var arena := game.arena
	if arena == null:
		return
	for team in [0, 1]:
		var xs: Array = []
		var zs: Array = []
		for unit in arena.units_of_team(team):
			xs.append(unit.global_position.x)
			zs.append(unit.global_position.z)
		if xs.is_empty():
			continue
		var span_x: float = float(xs.max()) - float(xs.min())
		var span_z: float = float(zs.max()) - float(zs.min())
		print("[autoplay]   %s队出生：x∈[%.1f, %.1f]（跨 %.1f） z∈[%.1f, %.1f]（跨 %.1f） 共%d人｜横纵比 %.2f" % [
			"A" if team == 0 else "B", xs.min(), xs.max(), span_x, zs.min(), zs.max(), span_z,
			xs.size(), (span_z / maxf(span_x, 0.01))])

## 诊断打印：只在"疑似卡住"时输出，避免刷屏（bug 2b 回归用）
## 判定标准：**移动态 + 速度 < 1.0 + 离目标远于自己的射程**，且连续 2 次采样
## （约 1 秒游戏时间）都如此，才算真卡住。单帧 0 速度是正常现象（攻击/减速交接帧）。
func _report_states() -> void:
	var arena := game.arena
	if arena == null:
		return
	var total := 0
	var stuck: Array = []
	var bad_target: Array = []
	var lock_hits := 0
	var lock_total := 0
	for team in [0, 1]:
		for unit in arena.units_of_team(team):
			total += 1
			# 索敌规则核对：锁定的目标必须就是场上最近的敌人（优化 6）
			lock_total += 1
			if unit.is_targeting_nearest():
				lock_hits += 1
			else:
				bad_target.append("%s(%.1f,%.1f)" % [
					GameConfig.profile_name(unit.type_id),
					unit.global_position.x, unit.global_position.z])
			var tgt: Unit3D = unit.target
			var dist := -1.0
			if tgt != null and is_instance_valid(tgt):
				dist = unit.global_position.distance_to(tgt.global_position)
			var key: int = unit.get_instance_id()
			var speed := Vector2(unit.velocity.x, unit.velocity.z).length()
			var my_range := float(GameConfig.profile(unit.type_id)["range"])
			# 真卡住 = 移动态 + 速度≈0 + **离目标远于自己的射程**（在射程内停住是正常的）
			var far := dist > my_range * 1.35
			var bad: bool = unit._state == 1 and speed < 1.0 and far
			_stuck_samples[key] = (int(_stuck_samples.get(key, 0)) + 1) if bad else 0
			if int(_stuck_samples[key]) >= 2:
				stuck.append("%s(%.1f,%.1f) 距%.1f 速度%.2f 绕行%d" % [
					GameConfig.profile_name(unit.type_id),
					unit.global_position.x, unit.global_position.z, dist, speed, unit._stuck_switches])
	print("[autoplay]   卡住检测：%d / %d%s　｜　锁定最近者 %d/%d（%.0f%%）%s" % [
		stuck.size(), total,
		("　⚠ " + " | ".join(stuck)) if not stuck.is_empty() else "",
		lock_hits, lock_total,
		(100.0 * float(lock_hits) / float(maxi(lock_total, 1))),
		("　⚠ 偏离：" + " | ".join(bad_target)) if not bad_target.is_empty() else ""])
