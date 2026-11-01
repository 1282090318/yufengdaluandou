class_name Game
extends Node
## 单人对局流程状态机
##
## 三轮决策 -> 每轮两支总权重相同的队伍自动对战 -> 押中得分 / 押错掉一次机会
## 依据：docs/bible/01_core_loop.md、03_rules.md#1-胜负判定、03_rules.md#4-礼物点数表

enum Phase { INIT, BETTING, FIGHTING, ROUND_RESULT, GAME_OVER }

var phase: int = Phase.INIT
var round_index: int = 0
var points: int = GameConfig.START_POINTS
var peak_points: int = GameConfig.START_POINTS   ## 本局到达过的最高点数（"点生点"按这个判定）
var chances: int = GameConfig.CHANCES_MAX
var roster_a: Array = []
var roster_b: Array = []
var bet_team: int = -1
var bet_all_in: bool = false
var bet_wager: int = 0
var log_entries: Array = []
var last_result: Dictionary = {}
var summary: Dictionary = {}

var arena: Arena = null
var camera_rig: CameraRig = null

var _state_sent_ms: int = 0
## 暂停开始时刻（0 = 没在暂停）。⚠️ 存在的唯一理由：本项目的计时**一律是绝对毫秒**（不变量 I-13），
## 而 `get_tree().paused` **不会停表** —— 暂停 N 秒后，赛程倒计时、出手冷却、技能冷却、眩晕、冲刺时长
## 都会"凭空过去 N 秒"。所以恢复时必须把所有绝对时刻**整体后移 N**（见 `match_pause.gd`）。
var _pause_from_ms: int = 0

func _ready() -> void:
	pass

func bind(p_arena: Arena, p_camera: CameraRig) -> void:
	arena = p_arena
	camera_rig = p_camera
	arena.match_ended.connect(_on_arena_ended)

# ---------------------------------------------------------------- 轮次流程
func setup_first_round() -> void:
	MatchSave.erase_quiz()
	if arena != null:
		arena.roll_battle_scene()
	round_index = 1
	points = GameConfig.START_POINTS
	peak_points = GameConfig.START_POINTS
	chances = GameConfig.CHANCES_MAX
	log_entries.clear()
	_roll_teams()
	_enter_betting()

func _roll_teams() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var match: Array = GameConfig.make_match(round_index, rng)
	roster_a = match[0]
	roster_b = match[1]
	# 押注阶段就把两队摆到场上，方便观众先看阵型再决定（见 01_core_loop.md）
	arena.settle()
	arena.spawn_roster(0, roster_a)
	arena.spawn_roster(1, roster_b)

func _enter_betting() -> void:
	## 押注阶段**没有倒计时**（优化 2）：玩家想清楚再点，游戏会一直等。
	## 因此不存在"超时自动观望"这条路径——按钮里的"观望本轮"是唯一出入口。
	bet_team = -1
	bet_all_in = false
	bet_wager = GameConfig.wager_of(round_index)
	phase = Phase.BETTING
	_change_state()

func _change_state() -> void:
	_state_sent_ms = Time.get_ticks_msec()
	Events.phase_changed.emit(phase_name())

## 玩家下注。all_in 从 `ALL_IN_FROM_ROUND` 轮起才生效（2026-09-18 由第 6 轮提前到第 3 轮）
func place_bet(team: int, all_in: bool = false) -> void:
	if phase != Phase.BETTING:
		return
	var wager := GameConfig.wager_of(round_index)
	## 强制全力支持（2026-09-18）：**点数不够付本轮固定投入时，直接按 ALL 处理**，
	## 也就是同样享受 ALL 的 ×2 奖励（原先只是把投入 clamp 到点数，不给奖励）。
	## ALL 未解锁的轮次（第 1~2 轮）不适用，仍然只 clamp。
	var forced_all_in := points < wager
	var effective_all_in := (all_in or forced_all_in) and GameConfig.all_in_unlocked(round_index)
	if effective_all_in:
		wager = points
	wager = clampi(wager, 0, points)
	bet_team = team
	bet_all_in = effective_all_in
	bet_wager = wager
	_start_round()

func _start_round() -> void:
	## ⚠️ 这里**不再重新 spawn**（修 bug 2026-09-18：押注阶段与开赛瞬间兵种位置不一致）。
	## 原因：`_roll_teams()` 已经在押注阶段把两队摆好了，而 `make_spawn_layout` 用的是**随机布局**；
	## 开赛再 spawn 一次会换一批随机位置 —— 观感就是"兵种瞬间移位"。
	## `_roll_teams()` 总在 `_enter_betting()` 之前调用，所以场上一定有兵。
	## 兜底：万一没兵（异常路径），补一次 spawn，避免开出一场空比赛。
	if arena.units.is_empty():
		arena.spawn_roster(0, roster_a)
		arena.spawn_roster(1, roster_b)
	phase = Phase.FIGHTING
	Events.round_started.emit(round_index, roster_a, roster_b, bet_wager)
	if camera_rig != null:
		camera_rig.on_fight_phase()
	_change_state()
	arena.start_match()

func _on_arena_ended(result: Dictionary) -> void:
	if phase != Phase.FIGHTING:
		return
	last_result = result
	var winner := int(result.get("winner", -1))
	var reason := String(result.get("reason", ""))
	# 四种结算（docs/bible/03_rules.md#1-胜负判定）：
	#   观望（没押注）→ 既不赚也不赔（观望机会在 `skip_round()` 按下时就扣掉了）
	#   平局          → 押注全额返还，不消耗机会（不变量 I-25）
	#   押中          → 加奖励
	#   押错          → 只扣投入，**不再消耗机会**（2026-09-18 不变量 I-21 改写：机会 = 观望配额）
	var observed := bet_team < 0
	var draw := winner < 0
	var hit := (not observed) and (not draw) and winner == bet_team
	var gain := 0
	if observed:
		gain = 0
	elif draw:
		gain = 0
	elif hit:
		var bonus := GameConfig.ALL_IN_BONUS if bet_all_in else GameConfig.NORMAL_BONUS
		gain = int(round(float(bet_wager) * bonus))
		points += gain
	else:
		gain = -bet_wager
		points = maxi(0, points - bet_wager)

	var tag := "观望"
	if not observed:
		if draw and bet_wager > 0:
			tag = "平局返还"
		elif draw:
			tag = "平局"
		elif hit:
			tag = "全力支持命中·双倍奖励" if bet_all_in else "押中"
		else:
			tag = "押错"
	log_entries.append({
		"round": round_index,
		"bet": bet_team,
		"winner": winner,
		"reason": reason,
		"wager": bet_wager,
		"gain": gain,
		"hit": hit,
		"draw": draw,
		"observed": observed,
		"all_in": bet_all_in,
		"tag": tag,
	})

	var payload := {
		"round": round_index,
		"winner": winner,
		"reason": reason,
		"bet": bet_team,
		"hit": hit,
		"draw": draw,
		"observed": observed,
		"wager": bet_wager,
		"gain": gain,
		"points": points,
		"chances": chances,
		"all_in": bet_all_in,
	}
	peak_points = maxi(peak_points, points)
	phase = Phase.ROUND_RESULT
	Events.match_finished.emit(payload)
	if camera_rig != null:
		## 定格后镜头仍可移动、转向；Enter 继续，不靠屏幕中间的按钮。
		camera_rig.hold_battle_view()
		camera_rig.shake(0.25)
	_change_state()
	## 失败条件（2026-09-18，不变量 I-21）：**点数归零 = 破产**，立刻结算结束。
	## 原先这里是 `chances <= 0`——机会改成"观望配额"后它不再是失败条件（点一次观望就自杀），
	## 于是押错 → 扣光点数成了唯一的死法；只要点数 > 0 就能继续玩（不足固定投入时强制 ALL）。
	if points <= 0:
		_finish_game(false)
	elif round_index >= GameConfig.ROUND_COUNT:
		_finish_game(true)

func next_round() -> void:
	if phase != Phase.ROUND_RESULT:
		return
	round_index += 1
	arena.settle()
	arena.end_presentation_hold()
	if arena != null:
		arena.roll_battle_scene()
	_roll_teams()
	_enter_betting()
	if camera_rig != null:
		camera_rig.on_quiz_phase()

func skip_round() -> void:
	## 观望：不输不赢，但**消耗 1 次观望机会**（2026-09-18，不变量 I-21：
	## 机会从"押错的惩罚"改成"观望的配额"）。机会用完就只剩押注一条路，所以先挡一道。
	if phase != Phase.BETTING or chances <= 0:
		return
	chances -= 1
	bet_team = -1
	bet_all_in = false
	bet_wager = 0
	_start_round()

func _finish_game(reached_end: bool) -> void:
	var successes := 0
	for entry in log_entries:
		if bool(entry["hit"]):
			successes += 1
	phase = Phase.GAME_OVER
	MatchSave.erase_quiz()
	summary = {
		"points": points,
		"peak_points": peak_points,
		"chances": chances,
		"rounds_played": log_entries.size(),
		"successes": successes,
		"reached_end": reached_end,
		"full_support": peak_points >= GameConfig.FULL_SUPPORT_THRESHOLD,
		"log": log_entries.duplicate(),
	}
	Events.game_over.emit(summary)
	_change_state()

func acknowledge_game_over() -> void:
	if phase != Phase.GAME_OVER:
		return
	arena.settle()
	arena.end_presentation_hold()
	log_entries.clear()
	setup_first_round()
	if camera_rig != null:
		camera_rig.on_quiz_phase()

# ---------------------------------------------------------------- 暂停 / 重开（暂停菜单用）
## 暂停比赛（暂停菜单打开时由 `Hud` 调用）。
## ⚠️ 用 `get_tree().paused` **整棵树暂停**（用户口径）：单位 / 兴奋圈 / 镜头 / 计时全停。
## ⚠️ 但**树暂停不会停表** —— 本项目的计时一律是绝对毫秒（不变量 I-13）⇒ 暂停时长必须记账，
## 由 `resume_match()` 平移所有截止时刻，否则赛程倒计时、出手与技能冷却、眩晕、冲刺时长
## 都会"凭空过去 N 秒"（暂停 20 s 回来，冲刺就没了、圈也缩了、全员技能就绪）。
func pause_match() -> void:
	if _pause_from_ms > 0:
		return
	_pause_from_ms = Time.get_ticks_msec()
	MatchPause.pause_tree(get_tree())

## 恢复比赛（「继续」）：解除暂停，并把暂停期间流逝的时间**从所有绝对时刻里扣掉**（即整体后移 Δ）。
## ⚠️ 平移的实现已抽到 `MatchPause`（竞猜模式与沙盒模式共用），见那里的说明。
func resume_match() -> void:
	var delta_ms := 0
	if _pause_from_ms > 0:
		delta_ms = Time.get_ticks_msec() - _pause_from_ms
	_pause_from_ms = 0
	MatchPause.resume_tree(get_tree())
	if delta_ms > 0:
		MatchPause.shift_deadlines(get_tree(), arena, camera_rig, delta_ms)
		_state_sent_ms += delta_ms     ## 免得恢复那一帧立刻补发一次 phase_changed（HUD 刷新节流用的时刻）

## 重开一局（暂停菜单的「重新开始」）：**任何相位**都能调 —— 把这一局整个扔掉、从第 1 轮重来。
## 与 `acknowledge_game_over()`（结算浮层的「再来一局」）走的是同一条 `setup_first_round()`：
## 点数回 `START_POINTS`、观望机会回 `CHANCES_MAX`、`round_index` 回 1、重抽两队并摆到押注阶段。
## ⚠️ 顺手解除暂停：调用方（`Hud`）是在黑透那一刻调的，此时不该再让树停着。
func restart_game() -> void:
	_pause_from_ms = 0
	get_tree().paused = false
	log_entries.clear()
	setup_first_round()
	if camera_rig != null:
		camera_rig.on_quiz_phase()

## 把"绝对毫秒的截止 / 起点时刻"整体后移（**暂停恢复专用**）—— 实现已抽到 `MatchPause`（经典 / 沙盒共用）。

## 暂停菜单里的「保存并退出」。已经结束的一局只删档。
func write_resume() -> void:
	if phase == Phase.GAME_OVER or arena == null:
		MatchSave.erase_quiz()
		return
	var frozen := Time.get_ticks_msec()
	if _pause_from_ms > 0:
		frozen = _pause_from_ms
	MatchSave.write_quiz({
		"phase": phase,
		"round_index": round_index,
		"points": points,
		"peak_points": peak_points,
		"chances": chances,
		"roster_a": roster_a.duplicate(true),
		"roster_b": roster_b.duplicate(true),
		"bet_team": bet_team,
		"bet_all_in": bet_all_in,
		"bet_wager": bet_wager,
		"log_entries": log_entries.duplicate(true),
		"last_result": last_result.duplicate(true),
		"scene_id": arena.battle_scene_id(),
		"clock": arena.capture_match_clock(frozen),
		"units": arena.capture_units(frozen),
	})

## 从存档回到退出时的那一帧。单位位置、血量和技能截止时刻都按当时记下的来。
func restore_from_save(data: Dictionary) -> void:
	if data.is_empty() or arena == null:
		setup_first_round()
		return
	phase = int(data.get("phase", Phase.BETTING))
	round_index = int(data.get("round_index", 1))
	points = int(data.get("points", GameConfig.START_POINTS))
	peak_points = int(data.get("peak_points", points))
	chances = int(data.get("chances", GameConfig.CHANCES_MAX))
	roster_a = data.get("roster_a", [])
	roster_b = data.get("roster_b", [])
	bet_team = int(data.get("bet_team", -1))
	bet_all_in = bool(data.get("bet_all_in", false))
	bet_wager = int(data.get("bet_wager", 0))
	log_entries = data.get("log_entries", [])
	last_result = data.get("last_result", {})
	arena.use_battle_scene(String(data.get("scene_id", "")))
	var now_ms := Time.get_ticks_msec()
	arena.restore_units(data.get("units", []), now_ms)
	arena.restore_match_clock(data.get("clock", {}), now_ms)
	_change_state()
	if camera_rig == null:
		return
	if phase == Phase.FIGHTING:
		camera_rig.on_fight_phase()
	elif phase == Phase.ROUND_RESULT or phase == Phase.GAME_OVER:
		camera_rig.hold_battle_view()
		arena.begin_presentation_hold({}, 0)
	else:
		camera_rig.on_quiz_phase()

# ---------------------------------------------------------------- 查询
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if phase != Phase.GAME_OVER and phase != Phase.ROUND_RESULT:
		return
	get_viewport().set_input_as_handled()
	var action_name := "acknowledge_game_over"
	if phase == Phase.ROUND_RESULT and round_index < GameConfig.ROUND_COUNT:
		action_name = "next_round"
	ScreenFade.attach(self).play(Callable(self, action_name))


func phase_name() -> String:
	match phase:
		Phase.INIT:
			return "init"
		Phase.BETTING:
			return "betting"
		Phase.FIGHTING:
			return "fighting"
		Phase.ROUND_RESULT:
			return "round_result"
		Phase.GAME_OVER:
			return "over"
	return "unknown"

func recommended_team() -> int:
	## "系统推荐倾向"：按阵容评分，分数更高的那队。
	## 优化 2 之后不再有"倒计时末段隐藏"的防跟票机制（没有倒计时了），恒为可见。
	var score_a := _roster_score(roster_a)
	var score_b := _roster_score(roster_b)
	return 0 if score_a >= score_b else 1

func all_in_value() -> int:
	return points

func _roster_score(units: Array) -> float:
	var counts := {}
	for type_id in units:
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var total := 0.0
	for type_id in counts:
		var p: Dictionary = GameConfig.profile(type_id)
		var n: int = int(counts[type_id])
		total += (float(p["hp"]) + float(p["damage"]) * float(p["attack_speed"]) * 4.0) * float(n)
	return total

func _process(delta: float) -> void:
	## HUD 刷新节流到 10Hz，避免每帧重建标签
	if Time.get_ticks_msec() - _state_sent_ms < 100:
		return
	_state_sent_ms = Time.get_ticks_msec()
	Events.phase_changed.emit(phase_name())
