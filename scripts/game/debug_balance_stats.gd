extends Node
## 数值平衡统计（调试用，不参与正式发布）
##
## 用途：不渲染任何东西，在逻辑层跑大量对局，统计
##   ① 每轮总权重下的"配平质量"（两队阵容评分差距）
##   ② 混编对局的胜率与"兵种优势度"（多兵种的一方是否更容易赢）
##   ③ 纯兵种对局的胜率矩阵
## 运行：godot --headless --path . res://scenes/main/debug_balance_stats.tscn
##
## ⚠️ 这是**近似模拟**：忽略空间遮挡与射界，只用距离 + 走位 + 集火 + 击退。
## 它的价值在于"同一套规则下横向比较兵种强度"，不能当成实机手感的替代品。

const ROUNDS_TO_PROBE := [1, 4, 7, 10]
const COMPOSITION_SAMPLE := 20        ## 每个轮次总权重下的混编对局采样数
const PURE_SAMPLE := 40               ## 纯兵种对局采样数
const PURE_COUNT := 8                 ## 纯兵种对局的单位数
const MAX_SIM_SECONDS := 90.0
const SIM_DT := 1.0 / 30.0            ## 模拟步长（只做统计，30 Hz 足够）
var _rng := RandomNumberGenerator.new()
var _next_id: int = 0

# 走位常数（对应 unit3d.gd 的行为）
## 短弓手后撤已按优化 5 取消：三种兵走位一致（射程外前进、射程内站定射击）
## 索敌已按优化 6 统一为"只打最近的敌人"（不再有射界优先）
## 击退推开量**从 GameConfig 推导**，不要写死，否则工具会与实机脱节。
## 2026-09-18 改口径：推开距离 = `KNOCKBACK_SPEED × 击退数值 ÷ 目标重量 ÷ KNOCKBACK_DECAY`。
static func knockback_push(kb_value: float, target_mass: float) -> float:
	return GameConfig.KNOCKBACK_SPEED * kb_value / maxf(target_mass, 0.01) / GameConfig.KNOCKBACK_DECAY

func _ready() -> void:
	_rng.randomize()
	_report_pairing_quality()
	_report_mixed_winrate()
	_report_duel_matrix()
	_report_pure_matrix()
	get_tree().quit()

# ---------------------------------------------------------------- 报告
func _report_pairing_quality() -> void:
	print("[balance] ===== ① 配平质量：两队阵容评分差距 =====")
	for round_index in ROUNDS_TO_PROBE:
		var total := GameConfig.total_weight_for_round(round_index)
		var gaps: Array = []
		var unit_counts: Array = []
		for _i in 12:
			var match: Array = GameConfig.make_match(round_index, _rng)
			gaps.append(absf(_roster_score(match[0]) - _roster_score(match[1])))
			unit_counts.append(match[0].size())
		print("[balance]   第%2d轮 总权重%3d（每队约%3d人）｜平均评分差 %.1f｜最大 %.1f" % [
			round_index, total, int(round(_mean(unit_counts))), _mean(gaps), _max_of(gaps)])

func _report_mixed_winrate() -> void:
	print("[balance] ===== ② 混编对局：兵种优势度（%d 局/轮次）=====" % COMPOSITION_SAMPLE)
	for round_index in ROUNDS_TO_PROBE:
		## 每个兵种一个桶（2026-09-19 修：旧代码只有"剑盾/长矛/其它"三桶，
		## 于是扇子兵/骑士/投石车/弩车/狂战士全被算成"短弓手"，看起来像"出场比偏向短弓手"）
		var counts := {}
		for type_id in GameConfig.balance_pool():
			counts[type_id] = 0
		var wins_with_more := 0
		var decisions := 0
		var durations: Array = []
		var shortbow_advantage_wins := 0
		var shortbow_advantage_games := 0
		for _i in COMPOSITION_SAMPLE:
			## 2026-09-19：改用**真实配平**（`make_match`）而不是本地按人头均匀抽——
			## 旧写法无视权重与"每队 ≤3 种兵"的规则，测出来的阵容在实机里根本不会出现。
			var match: Array = GameConfig.make_match(round_index, _rng)
			var roster_a: Array = match[0]
			var roster_b: Array = match[1]
			var result := _battle(roster_a, roster_b)
			for type_id in roster_a + roster_b:
				counts[String(type_id)] = int(counts[String(type_id)]) + 1
			if result["winner"] < 0:
				continue
			decisions += 1
			durations.append(result["duration"])
			var winner_roster: Array = roster_a if int(result["winner"]) == 0 else roster_b
			var loser_roster: Array = roster_b if int(result["winner"]) == 0 else roster_a
			## ⚠️ 2026-09-25：`"archer"` → **`"shortbow"`**（弓兵改名短弓手，ID 跟着改）。
			## 这一桶仍然是"短弓手优势度"：长弓手是**另一个兵种**，混编优势度按既有口径**不单独统计**
			##（`03_rules.md#8` 的判据只登记了短弓手这一桶；要加长弓手的桶是新一轮的判据变更）。
			if _count(winner_roster, "shortbow") > _count(loser_roster, "shortbow"):
				shortbow_advantage_wins += 1
			if _count(roster_a, "shortbow") != _count(roster_b, "shortbow"):
				shortbow_advantage_games += 1
		var parts: Array = []
		for type_id in GameConfig.balance_pool():
			parts.append("%s%d" % [GameConfig.profile_name(type_id).substr(0, 1), int(counts[type_id])])
		print("[balance]   第%2d轮 分胜负 %2d/%2d｜平均时长 %.1fs｜出场比 %s" % [
			round_index, decisions, COMPOSITION_SAMPLE, _mean(durations), " ".join(parts)])
		if shortbow_advantage_games > 0:
			print("[balance]      └ 短弓手更多的一方获胜率：%d%%（%d 局可比）" % [
				int(round(100.0 * float(shortbow_advantage_wins) / float(shortbow_advantage_games))),
				shortbow_advantage_games])

func _report_pure_matrix() -> void:
	print("[balance] ===== ③ 纯兵种对局胜率（每边 %d 人）=====" % PURE_COUNT)
	for a in GameConfig.balance_pool():
		var line: Array = []
		for b in GameConfig.balance_pool():
			var roster_a: Array = []
			var roster_b: Array = []
			for _i in PURE_COUNT:
				roster_a.append(a)
				roster_b.append(b)
			var wins := 0
			var draws := 0
			var durations: Array = []
			var blocked_total := 0
			var hits_total := 0
			var alive_winner: Array = []
			for _i in PURE_SAMPLE:
				var result := _battle(roster_a, roster_b)
				durations.append(result["duration"])
				blocked_total += int(result["blocked"])
				hits_total += int(result["hits"])
				if int(result["winner"]) == 0:
					wins += 1
					alive_winner.append(int(result["alive_winner"]))
				elif int(result["winner"]) < 0:
					draws += 1
			line.append("%s→%s %3d%%(平%2d%%, %.0fs, 挡%d/%d, 余%d)" % [
				GameConfig.profile_name(a).substr(0, 2), GameConfig.profile_name(b).substr(0, 2),
				int(round(100.0 * float(wins) / float(PURE_SAMPLE))),
				int(round(100.0 * float(draws) / float(PURE_SAMPLE))), _mean(durations),
				blocked_total, blocked_total + hits_total,
				int(round(_mean(alive_winner))) if not alive_winner.is_empty() else 0])
		print("[balance]   " + "｜".join(line))

## 单对兵种 1v1 对拼诊断：谁先死、接触后能打几下
func _report_duel_matrix() -> void:
	print("[balance] ===== ④ 单挑诊断（1v1，接触后有效 DPS 与击杀耗时）=====")
	for a in GameConfig.balance_pool():
		var line: Array = []
		for b in GameConfig.balance_pool():
			var dps_a := GameConfig.hit_damage(a) / GameConfig.attack_interval(a)
			var dps_b := GameConfig.hit_damage(b) / GameConfig.attack_interval(b)
			var ttk_a := GameConfig.max_hp(b) / dps_a
			var ttk_b := GameConfig.max_hp(a) / dps_b
			line.append("%s→%s 需%.1fs/%s→%s 需%.1fs" % [
				GameConfig.profile_name(a).substr(0, 2), GameConfig.profile_name(b).substr(0, 2), ttk_a,
				GameConfig.profile_name(b).substr(0, 2), GameConfig.profile_name(a).substr(0, 2), ttk_b])
		print("[balance]   " + "｜".join(line))

# ---------------------------------------------------------------- 随机阵容
func _random_roster(total: int) -> Array:
	## ⚠️ 用**配平池**（`balance_types()`）而不是 `TYPE_ORDER`：后者现在含"不属于任何池子"的实体
	##（沙盒的召唤石柱、肉鸽的指挥所），拿它们去对局会测出"0 伤害、永远打不死"的垃圾数据甚至跑不完。
	var pool := GameConfig.balance_pool()
	var out: Array = []
	for _i in total:
		out.append(pool[_rng.randi_range(0, pool.size() - 1)])
	return out

func _count(roster: Array, type_id: String) -> int:
	var n := 0
	for item in roster:
		if String(item) == type_id:
			n += 1
	return n

# ---------------------------------------------------------------- 逻辑层对局模拟
class SimUnit:
	var id: int = 0
	var team: int = 0
	var type_id: String = ""
	var hp: float = 0.0
	var max_hp: float = 0.0
	var pos: Vector2 = Vector2.ZERO
	var facing: Vector2 = Vector2.RIGHT
	var cooldown: float = 0.0
	var knockback_cd: float = 0.0
	var alive: bool = true
	var blocked_count: int = 0
	var hit_count: int = 0
	var striking: bool = false            ## 是否在出手窗口内（出手时盾让开，挡不住箭）
	var target: SimUnit = null

	func dps() -> float:
		return GameConfig.hit_damage(type_id) / GameConfig.attack_interval(type_id)

## 返回 {winner: 0/1/-1, duration: 秒}
func _battle(roster_a: Array, roster_b: Array) -> Dictionary:
	var units: Array[SimUnit] = []
	for team in [0, 1]:
		var roster: Array = roster_a if team == 0 else roster_b
		var sign_x := GameConfig.team_spawn_sign(team)
		var index := 0
		for type_id in roster:
			var unit := SimUnit.new()
			_next_id += 1
			unit.id = _next_id
			unit.team = team
			unit.type_id = String(type_id)
			unit.max_hp = GameConfig.max_hp(unit.type_id)
			unit.hp = unit.max_hp
			# 出生：己方后半段随机站位（与真实刷新一致的粗略近似）
			unit.pos = Vector2(sign_x * _rng.randf_range(GameConfig.ARENA_HALF_X * 0.55, GameConfig.ARENA_HALF_X * 0.9),
				_rng.randf_range(-GameConfig.ARENA_HALF_Z * 0.85, GameConfig.ARENA_HALF_Z * 0.85))
			unit.cooldown = _rng.randf() * GameConfig.attack_interval(unit.type_id)
			units.append(unit)
			index += 1
	return _run(units)

func _run(units: Array[SimUnit]) -> Dictionary:
	var dt := SIM_DT
	var elapsed := 0.0
	while elapsed < MAX_SIM_SECONDS:
		elapsed += dt
		var alive_a := _alive_count(units, 0)
		var alive_b := _alive_count(units, 1)
		if alive_a == 0 or alive_b == 0:
			break
		for unit in units:
			if not unit.alive:
				continue
			unit.cooldown -= dt
			# 出手窗口：攻击间隔的前 55%（前摇 + 命中帧）内剑盾兵举不起盾（优化 6）
			var interval := GameConfig.attack_interval(unit.type_id)
			unit.striking = unit.cooldown > interval * 0.45
			unit.knockback_cd = maxf(0.0, unit.knockback_cd - dt)
			# 目标缓存：只在目标失效时重找（对应真实的 alive 判定），避免每步 O(n²)
			if unit.target == null or not unit.target.alive:
				unit.target = _nearest_enemy(units, unit)
			var target := unit.target
			if target == null:
				continue
			var my_range := float(GameConfig.profile(unit.type_id)["range"])
			var speed := GameConfig.move_speed(unit.type_id)
			var to_target := target.pos - unit.pos
			var dist := to_target.length()
			if dist > 0.001:
				to_target /= dist
				unit.facing = to_target      ## 选手始终面向自己的目标（对应真实的 _face）
			if dist > my_range:
				unit.pos += to_target * speed * dt
			elif unit.cooldown <= 0.0:
				unit.cooldown = interval
				# 盾牌挡箭：只挡箭，不挡近战（对应 unit3d.gd#blocks_from 的扇形判定）
				# ⚠️ 2026-09-19：弩车的大型弹射物**无视盾牌**（`ignores_shield`），这里必须同步，
				# 否则模拟器会继续按"盾能挡住弩箭"算，得出偏乐观的剑盾胜率。
				if bool(GameConfig.profile(unit.type_id).get("is_ranged", false)) \
						and not bool(GameConfig.profile(unit.type_id).get("ignores_shield", false)) \
						and _is_blocked(target, to_target):
					target.blocked_count += 1
					continue
				var kb_scale := float(GameConfig.profile(unit.type_id).get("knockback", 0.0))
				if kb_scale > 0.0 and target.knockback_cd <= 0.0:
					target.knockback_cd = float(GameConfig.KNOCKBACK_CD_MS) / 1000.0
					target.pos += to_target * knockback_push(kb_scale, GameConfig.mass(target.type_id))
				target.hp -= GameConfig.hit_damage(unit.type_id)
				target.hit_count += 1
				if target.hp <= 0.0:
					target.hp = 0.0
					target.alive = false
	var alive_a := _alive_count(units, 0)
	var alive_b := _alive_count(units, 1)
	var blocked := 0
	var hits := 0
	for unit in units:
		blocked += unit.blocked_count
		hits += unit.hit_count
	var winner := -1
	if alive_a > 0 and alive_b == 0:
		winner = 0
	elif alive_b > 0 and alive_a == 0:
		winner = 1
	else:
		var hp_a := _pool(units, 0)
		var hp_b := _pool(units, 1)
		if not is_equal_approx(hp_a, hp_b):
			winner = 0 if hp_a > hp_b else 1
	var alive_winner := alive_a if winner == 0 else alive_b
	return {"winner": winner, "duration": elapsed, "blocked": blocked, "hits": hits, "alive_winner": alive_winner}

func _alive_count(units: Array[SimUnit], team: int) -> int:
	var n := 0
	for unit in units:
		if unit.alive and unit.team == team:
			n += 1
	return n

func _pool(units: Array[SimUnit], team: int) -> float:
	var total := 0.0
	for unit in units:
		if unit.alive and unit.team == team:
			total += unit.hp
	return total

func _nearest_enemy(units: Array[SimUnit], self_unit: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var best_dist := INF
	for other in units:
		if not other.alive or other.team == self_unit.team:
			continue
		var d := self_unit.pos.distance_squared_to(other.pos)
		if d < best_dist:
			best_dist = d
			best = other
	return best

## 盾牌挡箭：箭从防守方正面扇形内来时被挡下（对应 unit3d.gd#blocks_from）
## 优化 6：防守方**正在出手**时盾让开，这一窗口内挡不住箭。
func _is_blocked(defender: SimUnit, arrow_dir: Vector2) -> bool:
	if not bool(GameConfig.profile(defender.type_id).get("has_shield", false)):
		return false
	if defender.striking:
		return false
	var to_source := -arrow_dir
	if to_source.length_squared() < 0.0001:
		return false
	var forward := defender.facing
	if forward.length_squared() < 0.0001:
		return false
	var threshold := float(GameConfig.profile(defender.type_id)["shield_arc_dot"])
	return forward.normalized().dot(to_source.normalized()) >= threshold

# ---------------------------------------------------------------- 统计工具
func _roster_score(units: Array) -> float:
	var counts := {}
	for type_id in units:
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var total := 0.0
	for type_id in counts:
		var p: Dictionary = GameConfig.profile(type_id)
		var n: int = int(counts[type_id])
		var hp := float(p["hp"]) * GameConfig.HIT_HP_MULT * float(n)
		var dps := float(p["damage"]) * float(p["attack_speed"]) * float(n)
		total += hp + (dps * 2.0 if bool(p["is_ranged"]) else dps * 1.4)
	return total

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())

func _max_of(values: Array) -> float:
	var best := 0.0
	for v in values:
		best = maxf(best, float(v))
	return best
