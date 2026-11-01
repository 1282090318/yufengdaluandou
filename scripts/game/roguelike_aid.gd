class_name RoguelikeAid
extends RefCounted
## 生存模式的援助：抽四个、选一个或放弃换补给，以及变种 / 专家 / 道具 / 模块的落地。
## 数值只读 `GameConfig`（I-15）。不新增信号。


static func reset(host: Roguelike) -> void:
	host.aid_offer.clear()
	host.aid_pending = false
	host.aid_income_bonus = 0
	host.aid_tech_cut = 0
	host.aid_extra_squads = 0
	host.aid_shield_mult = 1.0
	host.aid_prop_cd_cut = 0
	host.aid_flank_half = false
	host.aid_elite_level = false
	host.aid_cost_control = false
	host.aid_speed_add = 0.0
	host.aid_hp_mult = 1.0
	host.aid_damage_mult = 1.0
	host.aid_range_add = 0.0
	host.aid_variant.clear()
	host.aid_taken.clear()
	_clear_cards(host)
	host.aid_zones.clear()


static func on_prepare(host: Roguelike) -> void:
	var bonus := 0
	for info in host.squads:
		var module_id := String(info.get("module_id", ""))
		if module_id == "":
			continue
		bonus += int(GameConfig.roguelike_aid_def(module_id).get("income", 0))
	if bonus > 0:
		host.supply += bonus
		host.income_total += bonus
	_expire_zones(host)
	if host.round_index < GameConfig.ROGUELIKE_AID_FROM_ROUND:
		host.aid_pending = false
		host.aid_offer.clear()
		return
	_roll(host)


static func on_battle(host: Roguelike) -> void:
	paint_all(host)
	for index in host.squads.size():
		var info: Dictionary = host.squads[index]
		var module_id := String(info.get("module_id", ""))
		if module_id == "":
			continue
		var ratio := float(GameConfig.roguelike_aid_def(module_id).get("heal_ratio", 0.0))
		if ratio <= 0.0:
			continue
		var living: Dictionary = host._living_slots(index)
		for slot in living.keys():
			var unit := living[slot] as Unit3D
			if unit != null and is_instance_valid(unit) and unit.alive:
				unit.hp = minf(unit.max_hp, unit.hp + unit.max_hp * ratio)
	for card in host.aid_cards:
		card["ran_round"] = -1
		card["cooled_round"] = -1
	_refresh_wards(host)


static func tick(host: Roguelike) -> void:
	_tick_wards(host)
	_tick_zones(host)
	if host.phase != Roguelike.Phase.FIGHTING or host.arena == null:
		return
	var elapsed := int(host.arena.skirmish_elapsed_ms())
	if elapsed < 0:
		return
	var now := Time.get_ticks_msec()
	for card in host.aid_cards:
		if not bool(card.get("placed", false)):
			continue
		if host.round_index < int(card.get("ready_round", 1)):
			continue
		var row := GameConfig.roguelike_aid_def(String(card["aid_id"]))
		var delay := int(row.get("delay_ms", 0))
		if elapsed < delay:
			continue
		var pulse := int(row.get("pulse_ms", 0))
		var duration := int(row.get("duration_ms", 0))
		if int(card.get("ran_round", -1)) != host.round_index:
			card["ran_round"] = host.round_index
			card["next_ms"] = now + pulse
			_emit(host, card, row, true)
			if pulse <= 0:
				_cool(host, card, row)
		elif pulse > 0:
			var age := elapsed - delay
			if age >= duration:
				if int(card.get("cooled_round", -1)) != host.round_index:
					card["cooled_round"] = host.round_index
					_cool(host, card, row)
			elif now >= int(card.get("next_ms", 0)):
				_emit(host, card, row, false)
				card["next_ms"] = now + pulse


static func accept(host: Roguelike, index: int) -> bool:
	if not host.aid_pending or index < 0 or index >= host.aid_offer.size():
		return false
	var id := String(host.aid_offer[index])
	var row := GameConfig.roguelike_aid_def(id)
	if row.is_empty():
		return false
	var cost := int(row.get("cost", 0))
	if host.supply < cost:
		host.last_message = "补给不足：%s 要 %d，还剩 %d" % [String(row["name"]), cost, host.supply]
		return false
	host._push_undo("援助：%s" % String(row["name"]))
	host.supply -= cost
	match String(row["group"]):
		"variant":
			host.aid_variant[String(row["type_id"])] = id
		"expert":
			host.aid_taken[id] = true
			_apply_expert(host, row)
		"prop", "module":
			_add_card(host, id)
	host.aid_pending = false
	host.aid_offer.clear()
	paint_all(host)
	host.last_message = "援助：%s" % String(row["name"])
	return true


static func skip(host: Roguelike) -> bool:
	if not host.aid_pending:
		return false
	var gain := GameConfig.ROGUELIKE_AID_SKIP_SUPPLY
	host._push_undo("放弃援助")
	host.supply += gain
	host.income_total += gain
	host.aid_pending = false
	host.aid_offer.clear()
	host.last_message = "放弃援助：+%d 补给" % gain
	return true


static func begin_card(host: Roguelike, index: int) -> void:
	if host.phase != Roguelike.Phase.PREPARE or host.aid_pending:
		return
	if index < 0 or index >= host.aid_cards.size():
		return
	var card: Dictionary = host.aid_cards[index]
	if bool(card.get("placed", false)):
		host.last_message = "这件已经放在场上了"
		return
	if host.round_index < int(card.get("ready_round", 1)):
		host.last_message = "还在冷却，第 %d 回合才能再用" % int(card["ready_round"])
		return
	var row := GameConfig.roguelike_aid_def(String(card["aid_id"]))
	if bool(row.get("beacon", false)):
		_use_beacon(host, index)
		return
	host._placing = "aid"
	host._aid_card_index = index
	host._aid_anchor_set = false
	host._place_press_seen = false
	host.last_message = "把「%s」拖到目标上松手。右键取消" % String(row["name"])


static func paint_all(host: Roguelike) -> void:
	if host.arena == null:
		return
	for node in host.arena.units:
		var unit := node as Unit3D
		if unit != null and is_instance_valid(unit):
			paint_unit(host, unit)


static func paint_unit(host: Roguelike, unit: Unit3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit.team != 0 or unit.has_meta("summoned"):
		unit.set_aid_mods({})
		return
	var mods := {
		"hp_mult": host.aid_hp_mult,
		"damage_mult": host.aid_damage_mult,
		"speed_add": host.aid_speed_add,
		"range_add": host.aid_range_add if unit.is_ranged() else 0.0,
		"interval_mult": 1.0,
		"xp_mult": 1.0,
	}
	if host.aid_variant.has(unit.type_id):
		_fold(mods, GameConfig.roguelike_aid_def(String(host.aid_variant[unit.type_id])))
	if unit.has_meta("squad_index"):
		var index := int(unit.get_meta("squad_index"))
		if index >= 0 and index < host.squads.size():
			var info: Dictionary = host.squads[index]
			if bool(info.get("cost_control", false)):
				mods["hp_mult"] = float(mods["hp_mult"]) * GameConfig.ROGUELIKE_AID_COST_CONTROL_MULT
				mods["damage_mult"] = float(mods["damage_mult"]) * GameConfig.ROGUELIKE_AID_COST_CONTROL_MULT
			var module_id := String(info.get("module_id", ""))
			if module_id != "":
				_fold(mods, GameConfig.roguelike_aid_def(module_id))
	unit.set_aid_mods(mods)


static func recruit_delta(host: Roguelike, type_id: String) -> int:
	if not host.aid_variant.has(type_id):
		return 0
	return int(GameConfig.roguelike_aid_def(String(host.aid_variant[type_id])).get("recruit_delta", 0))


static func upgrade_delta(host: Roguelike, type_id: String) -> int:
	if not host.aid_variant.has(type_id):
		return 0
	return int(GameConfig.roguelike_aid_def(String(host.aid_variant[type_id])).get("upgrade_delta", 0))


static func tech_cut(host: Roguelike, type_id: String) -> int:
	var cut := host.aid_tech_cut
	if host.aid_variant.has(type_id):
		## tech_delta 是标价的增减（−5 = 更便宜）。cut 是从标价里减掉的数。
		cut -= int(GameConfig.roguelike_aid_def(String(host.aid_variant[type_id])).get("tech_delta", 0))
	return cut


static func module_free_upgrade(host: Roguelike, index: int) -> bool:
	if index < 0 or index >= host.squads.size():
		return false
	var module_id := String(host.squads[index].get("module_id", ""))
	if module_id == "":
		return false
	return bool(GameConfig.roguelike_aid_def(module_id).get("free_upgrade", false))


static func module_move_always(host: Roguelike, index: int) -> bool:
	if index < 0 or index >= host.squads.size():
		return false
	var module_id := String(host.squads[index].get("module_id", ""))
	if module_id == "":
		return false
	return bool(GameConfig.roguelike_aid_def(module_id).get("move_always", false))


static func speed_mult(host: Roguelike, unit: Unit3D) -> float:
	if not _standing_in(host, unit, "oil"):
		return 1.0
	if unit.team == 0 and shield_covers(host, unit):
		return 1.0
	return GameConfig.ROGUELIKE_AID_OIL_SPEED_MULT


static func range_cut(host: Roguelike, unit: Unit3D) -> float:
	if not unit.is_ranged() or not _standing_in(host, unit, "smoke"):
		return 0.0
	if unit.team == 0 and shield_covers(host, unit):
		return 0.0
	return GameConfig.ROGUELIKE_AID_SMOKE_RANGE_CUT


static func shield_covers(host: Roguelike, unit: Unit3D) -> bool:
	if host.arena == null:
		return false
	var pos := unit.global_position
	for blocker in host.arena.arrow_blockers:
		if int(blocker.get("team", 0)) != 0:
			continue
		var center: Vector3 = blocker["center"]
		if pos.distance_to(center) <= float(blocker["radius"]):
			return true
	return false


static func chip_shield(host: Roguelike, _unit: Unit3D, amount: float) -> void:
	var left := maxf(amount, 1.0)
	for prop in host.props:
		if String(prop.get("kind", "")) != GameConfig.ROGUELIKE_PROP_SHIELD and String(prop.get("kind", "")) != "aid_ward":
			continue
		if float(prop.get("hp", 0.0)) <= 0.0:
			continue
		var taken := minf(float(prop["hp"]), left)
		prop["hp"] = float(prop["hp"]) - taken
		left -= taken
		if float(prop["hp"]) <= 0.0 and String(prop["kind"]) == GameConfig.ROGUELIKE_PROP_SHIELD:
			host.last_message = "魔法盾被战场道具打碎了"
		if left <= 0.0:
			break
	host._sync_arrow_blockers()


static func note_attack(host: Roguelike, unit: Unit3D) -> void:
	var every := int(unit.aid_mods.get("xp_every", 0))
	if every <= 0 or not unit.has_meta("squad_index"):
		return
	unit.aid_attack_count += 1
	if unit.aid_attack_count < every:
		return
	unit.aid_attack_count = 0
	host._add_squad_xp(int(unit.get_meta("squad_index")), 1, "辅助型扇子兵的攻击")


static func command_down(host: Roguelike, dead: Unit3D) -> void:
	if host._command_wiping or not dead.has_meta("squad_index"):
		return
	var index := int(dead.get_meta("squad_index"))
	if index < 0 or index >= host.squads.size():
		return
	var module_id := String(host.squads[index].get("module_id", ""))
	if module_id == "" or not bool(GameConfig.roguelike_aid_def(module_id).get("doom", false)):
		return
	if host._living_slots(index).size() > 0:
		return
	host._command_wiping = true
	host.last_message = "统御核心：这队被消灭，我方单位全部倒下"
	for node in host.arena.units.duplicate():
		if not is_instance_valid(node):
			continue
		var unit := node as Unit3D
		if unit != null and unit.alive and unit.team == 0 and not unit.is_command_post():
			unit.apply_hit(unit.max_hp + unit.hp + 1.0, null)
	host._command_wiping = false


static func _roll(host: Roguelike) -> void:
	var bag: Array[String] = []
	for row in GameConfig.roguelike_aid_catalog():
		if _eligible(host, row):
			bag.append(String(row["id"]))
	bag.shuffle()
	host.aid_offer = bag.slice(0, mini(GameConfig.ROGUELIKE_AID_OFFER_COUNT, bag.size()))
	host.aid_pending = not host.aid_offer.is_empty()


static func _eligible(host: Roguelike, row: Dictionary) -> bool:
	var group := String(row["group"])
	var id := String(row["id"])
	if group == "variant":
		var type_id := String(row["type_id"])
		if host.aid_variant.has(type_id):
			return false
		var gate := String(row.get("gate", "open"))
		if gate == "bulk" and not host.pool.has(type_id):
			return false
		if gate == "improve" and _squad_count(host, type_id) > GameConfig.ROGUELIKE_AID_SQUAD_CLEAR_M:
			return false
		return true
	if group == "expert":
		return not host.aid_taken.has(id)
	return true


static func _squad_count(host: Roguelike, type_id: String) -> int:
	var count := 0
	for info in host.squads:
		if String(info.get("type_id", "")) == type_id:
			count += 1
	return count


static func _apply_expert(host: Roguelike, row: Dictionary) -> void:
	match String(row.get("effect", "")):
		"speed":
			host.aid_speed_add += float(row.get("amount", 0.0))
		"income":
			var gain := int(row.get("amount", 0))
			host.aid_income_bonus += gain
			host.supply += gain
			host.income_total += gain
		"tech":
			host.aid_tech_cut += int(row.get("amount", 0))
		"hp":
			host.aid_hp_mult *= float(row.get("amount", 1.0))
		"damage":
			host.aid_damage_mult *= float(row.get("amount", 1.0))
		"range":
			host.aid_range_add += float(row.get("amount", 0.0))
		"flank":
			host.aid_flank_half = true
		"shield":
			var next := float(row.get("amount", 1.0))
			var old := host.aid_shield_mult
			host.aid_shield_mult = next
			if old > 0.0:
				for prop in host.props:
					if String(prop.get("kind", "")) != GameConfig.ROGUELIKE_PROP_SHIELD:
						continue
					prop["hp_max"] = float(prop["hp_max"]) * next / old
					prop["hp"] = minf(float(prop["hp"]) * next / old, float(prop["hp_max"]))
		"squad":
			host.aid_extra_squads += 1
		"elite":
			host.aid_elite_level = true
		"cost":
			host.aid_cost_control = true
			var gain := int(row.get("amount", 0))
			host.aid_income_bonus += gain
			host.supply += gain
			host.income_total += gain
		"prop_cd":
			host.aid_prop_cd_cut += int(row.get("amount", 0))


static func _add_card(host: Roguelike, id: String) -> void:
	host.aid_cards.append({
		"uid": host._aid_seq,
		"aid_id": id,
		"placed": false,
		"pos": Vector3.ZERO,
		"aim": Vector3.ZERO,
		"ready_round": host.round_index,
		"ran_round": -1,
		"cooled_round": -1,
		"next_ms": 0,
		"node": null,
	})
	host._aid_seq += 1


static func _clear_cards(host: Roguelike) -> void:
	for card in host.aid_cards:
		_free_node(card)
	host.aid_cards.clear()
	for zone in host.aid_zones:
		_free_node(zone)
	host.aid_zones.clear()


static func rehydrate(host: Roguelike) -> void:
	for card in host.aid_cards:
		card["node"] = null
		if bool(card.get("placed", false)):
			_show_mark(host, card, GameConfig.roguelike_aid_def(String(card["aid_id"])))
	paint_all(host)


static func _tick_place(host: Roguelike) -> void:
	if host._placing != "aid":
		return
	if host._aid_card_index < 0 or host._aid_card_index >= host.aid_cards.size():
		host._cancel_place()
		return
	var hit := host._ground_under_cursor(host.get_viewport().get_mouse_position())
	host._place_on_field = hit != Vector3.INF
	if host._place_on_field:
		host._place_pos = hit
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		host._place_press_seen = true
	elif host._place_press_seen:
		host._place_press_seen = false
		_aid_click(host)


static func _aid_click(host: Roguelike) -> void:
	var card: Dictionary = host.aid_cards[host._aid_card_index]
	var row := GameConfig.roguelike_aid_def(String(card["aid_id"]))
	var use := String(row.get("use", "point"))
	if use == "squad":
		var index := host._squad_at(host.get_viewport().get_mouse_position())
		if index < 0:
			host.last_message = "没拖到我方的队上，这一次不算用掉"
			host._cancel_place()
			return
		if _use_on_squad(host, host._aid_card_index, index, row):
			host._cancel_place()
		return
	if not host._place_on_field or not _inside_arena(host, host._place_pos):
		host.last_message = "这个位置不在场地上"
		return
	if bool(row.get("post_clear", false)) and not _clear_of_posts(host, host._place_pos):
		host.last_message = "要离敌方指挥所至少 %0.0f 米" % GameConfig.ROGUELIKE_AID_POST_CLEAR_M
		return
	if use == "rect" and not host._aid_anchor_set:
		host._aid_anchor = host._place_pos
		host._aid_anchor_set = true
		host.last_message = "再点一次，定矩形的另一侧"
		return
	host._push_undo("放置 %s" % String(row["name"]))
	card["placed"] = true
	card["pos"] = host._aid_anchor if use == "rect" else host._place_pos
	card["aim"] = host._place_pos
	_show_mark(host, card, row)
	host.last_message = "%s 已放好，开战之后生效" % String(row["name"])
	host._cancel_place()


static func _use_on_squad(host: Roguelike, card_index: int, squad_index: int, row: Dictionary) -> bool:
	if bool(row.get("train", false)):
		host._push_undo("训练")
		var cost := host.squad_xp_cost(squad_index)
		host.squads[squad_index]["xp"] = cost
		host.last_message = "训练：这队经验已补满"
		_cool(host, host.aid_cards[card_index], row)
		return true
	if bool(row.get("redeploy", false)):
		host._push_undo("再部署")
		host.squads[squad_index]["move_round"] = host.round_index
		host.last_message = "再部署：这队本回合可以移动"
		_cool(host, host.aid_cards[card_index], row)
		return true
	if bool(row.get("full_recall", false)):
		host._push_undo("高效遣返")
		var info: Dictionary = host.squads[squad_index]
		var refund := int(info.get("supply_spent", 0))
		host.supply += refund
		host._remove_squad(squad_index)
		host.last_message = "高效遣返：返还 %d 补给" % refund
		if card_index >= host.aid_cards.size():
			return true
		_cool(host, host.aid_cards[card_index], row)
		return true
	if String(row.get("group", "")) == "module":
		return _equip_module(host, card_index, squad_index, row)
	return false


static func _equip_module(host: Roguelike, card_index: int, squad_index: int, row: Dictionary) -> bool:
	var info: Dictionary = host.squads[squad_index]
	var type_id := String(info["type_id"])
	var weight := int(GameConfig.profile(type_id)["weight"])
	if weight < int(row.get("min_weight", 0)):
		host.last_message = "这队权重不够，装备不了"
		return false
	if bool(row.get("ranged_only", false)) and not bool(GameConfig.profile(type_id)["is_ranged"]):
		host.last_message = "只有远程队伍能装备"
		return false
	var current := String(info.get("module_id", ""))
	if current != "" and int(info.get("module_round", -1)) != host.round_index:
		host.last_message = "这队的模块从下回合起不能再换，除非把这队遣返"
		return false
	host._push_undo("装备 %s" % String(row["name"]))
	if current != "":
		_add_card(host, current)
	info["module_id"] = String(row["id"])
	info["module_round"] = host.round_index
	host.aid_cards.remove_at(card_index)
	paint_all(host)
	host.last_message = "已装备 %s" % String(row["name"])
	return true


static func _use_beacon(host: Roguelike, index: int) -> void:
	host._push_undo("移动信标")
	host.aid_cards.remove_at(index)
	if host._beacon_owned:
		host.last_message = "已经有移动信标了"
		return
	host._beacon_owned = true
	host.last_message = "获得移动信标：去道具栏放置"


static func _emit(host: Roguelike, card: Dictionary, row: Dictionary, opening: bool) -> void:
	if String(row.get("spawn_type", "")) != "" and opening:
		_spawn_drop(host, card, String(row["spawn_type"]))
		return
	if bool(row.get("shield_drop", false)) and opening:
		host._spawn_prop(GameConfig.ROGUELIKE_PROP_SHIELD, card["pos"])
		var prop: Dictionary = host.props[host.props.size() - 1]
		prop["hp"] = host.magic_shield_hp(GameConfig.ROGUELIKE_AID_SHIELD_DROP_SCALE)
		prop["hp_max"] = prop["hp"]
		host._sync_arrow_blockers()
		return
	if bool(row.get("barrier", false)) and opening:
		var tech := GameConfig.roguelike_tech_def("flamefist", "flame_barrier")
		_drop_barrier(host, Vector3(card["pos"]), float(row.get("radius", tech.get("radius", 0.0))))
		return
	var shape := _shape_of(card, row)
	if String(row.get("zone", "")) != "" and opening:
		_lay_zone(host, card, row, shape)
		return
	if opening and float(row.get("slow_mult", 1.0)) < 1.0:
		_hurt(host, shape, 0.0, false, false, false, 0, float(row["slow_mult"]), int(row.get("slow_ms", 0)), float(row.get("radius", 0.0)))
	var damage := float(row.get("damage", 0.0))
	var radius := float(row.get("pulse_radius", row.get("radius", 0.0)))
	var pulse_shape := shape
	if int(row.get("pulse_ms", 0)) > 0:
		pulse_shape = _random_in(shape, radius)
	if damage > 0.0 or int(row.get("silence_ms", 0)) > 0:
		_hurt(host, pulse_shape, damage, bool(row.get("hits_friendly", false)),
				bool(row.get("shieldable", false)), bool(row.get("ignore_shield", false)),
				int(row.get("silence_ms", 0)), 1.0, 0, radius)


static func _spawn_drop(host: Roguelike, card: Dictionary, type_id: String) -> void:
	if host.arena == null:
		return
	var weight := int(GameConfig.profile(type_id)["weight"])
	var count := GameConfig.roguelike_squad_size(weight)
	var facing := GameConfig.team_spawn_sign(0) * PI * 0.5
	for index in count:
		var at: Vector3 = card["pos"] + Vector3(float(index) * GameConfig.ROGUELIKE_REPLICATE_SPREAD, 0.0, 0.0)
		var spawned := host.arena.spawn_unit(0, type_id, at, facing)
		if spawned == null:
			continue
		spawned.set_meta("summoned", true)
		spawned.set_level(1)
		spawned.active = true


static func _drop_barrier(host: Roguelike, at: Vector3, radius: float) -> void:
	var tech := GameConfig.roguelike_tech_def("flamefist", "flame_barrier")
	var until := Time.get_ticks_msec() + int(tech.get("duration_ms", 0))
	var taken := float(tech.get("damage_taken_mult", 1.0))
	for node in host.arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive or unit.team != 0:
			continue
		if unit.global_position.distance_to(at) > radius:
			continue
		unit.grant_flame_barrier(until, taken)


static func _lay_zone(host: Roguelike, card: Dictionary, row: Dictionary, shape: Dictionary) -> void:
	var kind := String(row["zone"])
	if kind == "fire":
		_burn_oil(host, shape)
		var zone: Dictionary = shape.duplicate()
		zone["kind"] = "fire"
		zone["until_ms"] = Time.get_ticks_msec() + GameConfig.ROGUELIKE_AID_BURN_MS
		zone["next_ms"] = Time.get_ticks_msec() + GameConfig.ROGUELIKE_AID_GROUND_TICK_MS
		zone["node"] = _zone_visual(host, zone, Color(0.85, 0.28, 0.08, 0.35))
		host.aid_zones.append(zone)
		return
	if kind == "oil":
		_burn_oil(host, shape)
	var lasting: Dictionary = shape.duplicate()
	lasting["kind"] = kind
	lasting["until_round"] = host.round_index + int(row.get("zone_rounds", 2)) - 1
	lasting["next_ms"] = Time.get_ticks_msec() + GameConfig.ROGUELIKE_AID_GROUND_TICK_MS
	var tint := Color(0.15, 0.12, 0.08, 0.4)
	if kind == "acid":
		tint = Color(0.35, 0.75, 0.2, 0.35)
	elif kind == "smoke":
		tint = Color(0.45, 0.45, 0.48, 0.35)
	lasting["node"] = _zone_visual(host, lasting, tint)
	host.aid_zones.append(lasting)


static func _burn_oil(host: Roguelike, shape: Dictionary) -> void:
	var kept: Array = []
	for zone in host.aid_zones:
		if String(zone.get("kind", "")) == "oil" and _shapes_touch(zone, shape):
			_free_node(zone)
			var fire: Dictionary = zone.duplicate()
			fire["kind"] = "fire"
			fire["until_ms"] = Time.get_ticks_msec() + GameConfig.ROGUELIKE_AID_BURN_MS
			fire["next_ms"] = Time.get_ticks_msec()
			fire["node"] = _zone_visual(host, fire, Color(0.85, 0.28, 0.08, 0.35))
			kept.append(fire)
			continue
		kept.append(zone)
	host.aid_zones = kept


static func _tick_zones(host: Roguelike) -> void:
	if host.phase != Roguelike.Phase.FIGHTING or host.arena == null:
		return
	var now := Time.get_ticks_msec()
	var kept: Array = []
	for zone in host.aid_zones:
		if String(zone.get("kind", "")) == "fire" and now >= int(zone.get("until_ms", 0)):
			_free_node(zone)
			continue
		if String(zone.get("kind", "")) == "fire" or String(zone.get("kind", "")) == "acid":
			if now >= int(zone.get("next_ms", 0)):
				zone["next_ms"] = now + GameConfig.ROGUELIKE_AID_GROUND_TICK_MS
				if String(zone["kind"]) == "fire":
					_hurt(host, zone, GameConfig.ROGUELIKE_AID_BURN_TICK, true, true, false, 0, 1.0, 0, 0.0)
				else:
					_acid_tick(host, zone)
		kept.append(zone)
	host.aid_zones = kept


static func _acid_tick(host: Roguelike, zone: Dictionary) -> void:
	for node in host.arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive or unit.is_command_post():
			continue
		if unit.is_burrowed() or unit.has_flame_barrier():
			continue
		if not _point_in(unit.global_position, zone, 0.0):
			continue
		if unit.team == 0 and shield_covers(host, unit):
			chip_shield(host, unit, unit.max_hp * GameConfig.ROGUELIKE_AID_ACID_RATIO)
			continue
		unit.apply_hit(unit.max_hp * GameConfig.ROGUELIKE_AID_ACID_RATIO, null, Vector3.ZERO, 0.0, true, false, true)


static func _expire_zones(host: Roguelike) -> void:
	var kept: Array = []
	for zone in host.aid_zones:
		if String(zone.get("kind", "")) == "fire":
			_free_node(zone)
			continue
		if int(zone.get("until_round", 0)) < host.round_index:
			_free_node(zone)
			continue
		kept.append(zone)
	host.aid_zones = kept


static func _hurt(host: Roguelike, shape: Dictionary, damage: float, hits_friendly: bool,
		shieldable: bool, ignore_shield: bool, silence_ms: int, slow_mult: float, slow_ms: int,
		pulse_radius: float) -> void:
	if host.arena == null:
		return
	for node in host.arena.units:
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive or unit.is_command_post():
			continue
		if not _point_in(unit.global_position, shape, pulse_radius):
			continue
		var friendly := unit.team == 0
		if not hits_friendly and friendly and damage > 0.0 and silence_ms <= 0 and slow_ms <= 0:
			continue
		if friendly and shieldable and not ignore_shield and shield_covers(host, unit):
			if damage > 0.0:
				chip_shield(host, unit, damage)
			continue
		if not friendly or hits_friendly:
			if damage > 0.0 and not (String(shape.get("kind", "")) == "fire" and unit.has_flame_barrier()):
				unit.apply_hit(damage, null, Vector3.ZERO, 0.0, true)
		if silence_ms > 0 and not friendly:
			unit.apply_silence(silence_ms, 1.0)
		if slow_ms > 0 and slow_mult < 1.0 and not friendly:
			unit.apply_slow(slow_mult, slow_ms)


static func _refresh_wards(host: Roguelike) -> void:
	var kept: Array = []
	for prop in host.props:
		if String(prop.get("kind", "")) == "aid_ward":
			var node = prop.get("node")
			if node != null and is_instance_valid(node):
				node.queue_free()
			continue
		kept.append(prop)
	host.props = kept
	for index in host.squads.size():
		var info: Dictionary = host.squads[index]
		if not bool(GameConfig.roguelike_aid_def(String(info.get("module_id", ""))).get("ward", false)):
			continue
		var living: Dictionary = host._living_slots(index)
		for slot in living.keys():
			var unit := living[slot] as Unit3D
			if unit == null or not is_instance_valid(unit) or not unit.alive:
				continue
			var bonus := 0.0
			if unit.has_tech("shelter"):
				var shelter := unit.tech_def("shelter")
				bonus = float(shelter.get("shield_hp", 0.0))
			var hp := (GameConfig.ROGUELIKE_AID_WARD_HP + bonus) * float(maxi(unit.level, 1)) * host.aid_shield_mult
			host.props.append({
				"id": host._next_prop_id,
				"kind": "aid_ward",
				"pos": unit.global_position,
				"hp": hp,
				"hp_max": hp,
				"follow_id": unit.get_instance_id(),
				"radius": GameConfig.ROGUELIKE_AID_WARD_RADIUS,
				"node": null,
				"armed_ms": 0,
				"target": null,
				"triggered": false,
				"points": [],
			})
			host._next_prop_id += 1
	host._sync_arrow_blockers()


static func _tick_wards(host: Roguelike) -> void:
	if host.arena == null:
		return
	var changed := false
	for prop in host.props:
		if String(prop.get("kind", "")) != "aid_ward":
			continue
		var follow_node := instance_from_id(int(prop.get("follow_id", 0)))
		if not is_instance_valid(follow_node):
			prop["hp"] = 0.0
			changed = true
			continue
		var follow := follow_node as Unit3D
		if follow == null or not follow.alive or float(prop.get("hp", 0.0)) <= 0.0:
			prop["hp"] = 0.0
			changed = true
			continue
		var next := follow.global_position
		if Vector3(prop["pos"]).distance_squared_to(next) > 0.01:
			prop["pos"] = next
			changed = true
	if changed:
		host._sync_arrow_blockers()


static func _cool(host: Roguelike, card: Dictionary, row: Dictionary) -> void:
	var cooldown := maxi(int(row.get("cooldown", 0)) - host.aid_prop_cd_cut, 0)
	card["ready_round"] = host.round_index + 1 + cooldown


static func _fold(mods: Dictionary, row: Dictionary) -> void:
	if row.is_empty():
		return
	for key in ["hp_mult", "damage_mult", "interval_mult", "xp_mult", "blast_mult"]:
		if row.has(key):
			mods[key] = float(mods.get(key, 1.0)) * float(row[key])
	for key in ["speed_add", "range_add", "mass_add", "interval_add"]:
		if row.has(key):
			mods[key] = float(mods.get(key, 0.0)) + float(row[key])
	for key in ["pierce_add", "xp_every", "cd_add_ms", "summon_count", "summon_interval_ms"]:
		if row.has(key):
			mods[key] = int(mods.get(key, 0)) + int(row[key])
	for key in ["blast_once", "no_kill_xp", "block_corrupt", "block_silence", "block_post"]:
		if bool(row.get(key, false)):
			mods[key] = true
	if String(row.get("summon_type", "")) != "":
		mods["summon_type"] = String(row["summon_type"])


static func _shape_of(card: Dictionary, row: Dictionary) -> Dictionary:
	return {
		"use": String(row.get("use", "point")),
		"pos": Vector3(card["pos"]),
		"aim": Vector3(card.get("aim", card["pos"])),
		"radius": float(row.get("radius", 0.0)),
		"length": float(row.get("length", 40.0)),
		"width": float(row.get("width", 20.0)),
	}


static func _random_in(shape: Dictionary, pulse_radius: float) -> Dictionary:
	var angle := randf() * TAU
	var dist := randf() * float(shape.get("radius", 1.0))
	var at: Vector3 = shape["pos"] + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	return {"use": "point", "pos": at, "aim": at, "radius": pulse_radius, "length": 0.0, "width": 0.0}


static func _point_in(pos: Vector3, shape: Dictionary, extra_radius: float) -> bool:
	if String(shape.get("kind", "")) == "fire" or String(shape.get("kind", "")) == "acid" \
			or String(shape.get("kind", "")) == "oil" or String(shape.get("kind", "")) == "smoke" \
			or String(shape.get("use", "")) == "rect":
		return _in_rect(pos, shape)
	var center: Vector3 = shape["pos"]
	var radius := float(shape.get("radius", 0.0))
	if extra_radius > 0.0:
		radius = extra_radius
	var flat := pos - center
	flat.y = 0.0
	return flat.length() <= radius


static func _in_rect(pos: Vector3, shape: Dictionary) -> bool:
	var a: Vector3 = shape["pos"]
	var b: Vector3 = shape.get("aim", a)
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length_squared() < 0.01:
		dir = Vector3(1.0, 0.0, 0.0)
	else:
		dir = dir.normalized()
	var length := float(shape.get("length", 40.0))
	var width := float(shape.get("width", 20.0))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var delta := Vector3(pos.x - a.x, 0.0, pos.z - a.z)
	var along := delta.dot(dir)
	var across := delta.dot(side)
	return along >= 0.0 and along <= length and absf(across) <= width * 0.5


static func _shapes_touch(left: Dictionary, right: Dictionary) -> bool:
	return _point_in(Vector3(left["pos"]), right, 0.0) or _point_in(Vector3(right["pos"]), left, 0.0)


static func _standing_in(host: Roguelike, unit: Unit3D, kind: String) -> bool:
	for zone in host.aid_zones:
		if String(zone.get("kind", "")) == kind and _point_in(unit.global_position, zone, 0.0):
			return true
	return false


static func _inside_arena(host: Roguelike, pos: Vector3) -> bool:
	if host.arena == null:
		return false
	return absf(pos.x) <= host.arena.half_x - 1.0 and absf(pos.z) <= host.arena.half_z - 1.0


static func _clear_of_posts(host: Roguelike, pos: Vector3) -> bool:
	var list: Array = host.posts_of_team[1]
	for raw in list:
		if not is_instance_valid(raw):
			continue
		var post := raw as Unit3D
		if post == null or not post.alive:
			continue
		if pos.distance_to(post.global_position) < GameConfig.ROGUELIKE_AID_POST_CLEAR_M:
			return false
	return true


static func _show_mark(host: Roguelike, card: Dictionary, _row: Dictionary) -> void:
	_free_node(card)
	if host.arena == null:
		return
	var node := MeshInstance3D.new()
	node.name = "AidMark_%d" % int(card["uid"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = 0.08
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.72, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.position = Vector3(card["pos"].x, 0.2, card["pos"].z)
	host.arena.add_child(node)
	card["node"] = node


static func _zone_visual(host: Roguelike, zone: Dictionary, tint: Color) -> Node:
	if host.arena == null:
		return null
	var node := MeshInstance3D.new()
	node.name = "AidZone_%d" % host.aid_zones.size()
	var mesh := CylinderMesh.new()
	var radius := maxf(float(zone.get("radius", 0.0)), float(zone.get("length", 8.0)) * 0.25)
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	var pos: Vector3 = zone["pos"]
	node.position = Vector3(pos.x, 0.12, pos.z)
	host.arena.add_child(node)
	return node


static func _free_node(bag: Dictionary) -> void:
	var node = bag.get("node")
	if node != null and is_instance_valid(node):
		node.queue_free()
	bag["node"] = null
