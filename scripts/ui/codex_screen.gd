class_name CodexScreen
extends CanvasLayer
## 图鉴：查看作战兵种和召唤石柱的基础七项、特性、技能、科技，并转着看模型。
##
## 入口在开始界面和三个模式的暂停菜单。本层盖在它们上面，关掉就回到打开它的那一屏。
## 数值读 `GameConfig` 的兵种表，不在这里另存一份。
## ⚠️ `PROCESS_MODE_ALWAYS`：从暂停菜单进来时整棵树是停的，列表和模型还要能动。

const CODEX_LAYER := 21
const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.82)
const CODEX_SPIN_RAD := 0.45
## 单位正面是局部 −Z。预览相机在 +Z，起步转 180° 才是对着镜头的正面。
const CODEX_FRONT_YAW_RAD := PI
const LIST_WIDTH := 280.0
const MODEL_WIDTH := 460.0

var _root: Control = null
var _list: VBoxContainer = null
var _detail: VBoxContainer = null
var _picks: Dictionary = {}
var _selected_id: String = ""
var _viewport: SubViewport = null
var _pivot: Node3D = null
var _cam: Camera3D = null
var _model: Node3D = null
var _model_box: Control = null
var _built: bool = false
var _section_index: int = 0
var _section_tabs: Array = []
var _sort_row: HBoxContainer = null
var _filter_box: FlowContainer = null
var _sort_price: Button = null
var _sort_kind: Button = null
var _filter_buttons: Dictionary = {}
## 援助默认仍按种类分组。兵种只有按价格一种。
var _aid_sort_kind: bool = true
var _unit_tags: Dictionary = {"melee": false, "ranged": false}
var _aid_tags: Dictionary = {
	"free": false, "variant": false, "expert": false, "prop": false, "module": false,
}

func open() -> void:
	_ensure_built()
	_show_section(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true

func is_open() -> bool:
	return _root != null and _root.visible

func close() -> void:
	if _root != null:
		_root.visible = false

func _process(delta: float) -> void:
	if not is_open() or _pivot == null:
		return
	_pivot.rotate_y(CODEX_SPIN_RAD * delta)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	close()
	get_viewport().set_input_as_handled()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	layer = CODEX_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "CodexRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)
	var frame := MarginContainer.new()
	frame.name = "CodexFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 36.0
	frame.offset_top = 28.0
	frame.offset_right = -36.0
	frame.offset_bottom = -28.0
	frame.add_theme_constant_override("margin_left", 8)
	frame.add_theme_constant_override("margin_right", 8)
	frame.add_theme_constant_override("margin_top", 4)
	frame.add_theme_constant_override("margin_bottom", 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)
	var column := VBoxContainer.new()
	column.name = "CodexColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)
	column.add_child(_build_header())
	var body := HBoxContainer.new()
	body.name = "CodexBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	body.add_child(_build_list())
	body.add_child(_build_detail())
	body.add_child(_build_model())

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "CodexHeader"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UiStyle.make_label("图鉴", UiStyle.FONT_LARGE, UiStyle.COLOR_TEXT)
	title.name = "CodexTitle"
	header.add_child(title)
	var titles: PackedStringArray = ["兵种", "援助"]
	for index in titles.size():
		var tab := Button.new()
		tab.name = "CodexTab_%d" % index
		tab.text = titles[index]
		UiStyle.decorate_chip(tab)
		tab.custom_minimum_size = Vector2(108.0, 40.0)
		tab.pressed.connect(_show_section.bind(index))
		header.add_child(tab)
		_section_tabs.append(tab)
	var spacer := Control.new()
	spacer.name = "HeaderSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "返回"
	UiStyle.decorate_option(close_button)
	close_button.custom_minimum_size = Vector2(160.0, 52.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	return header

func _build_list() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "UnitListColumn"
	column.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_sort_row = HBoxContainer.new()
	_sort_row.name = "CodexSortRow"
	_sort_row.add_theme_constant_override("separation", 6)
	column.add_child(_sort_row)
	_sort_price = _tool_chip("SortPrice", "按价格")
	_sort_price.pressed.connect(_on_sort_price)
	_sort_row.add_child(_sort_price)
	_sort_kind = _tool_chip("SortKind", "按种类")
	_sort_kind.pressed.connect(_on_sort_kind)
	_sort_row.add_child(_sort_kind)
	_filter_box = FlowContainer.new()
	_filter_box.name = "CodexFilterRow"
	_filter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_box.add_theme_constant_override("h_separation", 6)
	_filter_box.add_theme_constant_override("v_separation", 6)
	column.add_child(_filter_box)
	var filters: Array = [
		["melee", "FilterMelee", "近战"],
		["ranged", "FilterRanged", "远程"],
		["free", "FilterFree", "免费"],
		["variant", "FilterVariant", "兵种变种"],
		["expert", "FilterExpert", "专家"],
		["prop", "FilterProp", "战场道具"],
		["module", "FilterModule", "战术模块"],
	]
	for spec in filters:
		var key := String(spec[0])
		var chip := _tool_chip(String(spec[1]), String(spec[2]))
		chip.pressed.connect(_toggle_tag.bind(key))
		_filter_box.add_child(chip)
		_filter_buttons[key] = chip
	var scroll := ScrollContainer.new()
	scroll.name = "UnitListScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.name = "UnitList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	column.add_child(scroll)
	return column

func _build_detail() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "UnitDetailScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.name = "UnitDetail"
	_detail.custom_minimum_size = Vector2(360.0, 0.0)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	scroll.add_child(_detail)
	return scroll

func _build_model() -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.name = "ModelView"
	box.custom_minimum_size = Vector2(MODEL_WIDTH, 0.0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_model_box = box
	_viewport = SubViewport.new()
	_viewport.name = "ModelViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(_viewport)
	var sky := WorldEnvironment.new()
	sky.name = "ModelSky"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.70)
	env.ambient_light_energy = 0.9
	sky.environment = env
	_viewport.add_child(sky)
	var key := DirectionalLight3D.new()
	key.name = "ModelKey"
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key.light_energy = 1.15
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "ModelFill"
	fill.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)
	var stage := Node3D.new()
	stage.name = "ModelStage"
	_viewport.add_child(stage)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 6.0
	floor_mesh.bottom_radius = 6.0
	floor_mesh.height = 0.04
	var floor := MeshInstance3D.new()
	floor.name = "ModelFloor"
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.02, 0.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.13, 0.15)
	floor.material_override = floor_mat
	stage.add_child(floor)
	_pivot = Node3D.new()
	_pivot.name = "ModelPivot"
	stage.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.name = "ModelCamera"
	_cam.current = true
	_cam.fov = 30.0
	_cam.near = 0.05
	_cam.far = 80.0
	_viewport.add_child(_cam)
	return box

func _show_section(index: int) -> void:
	_section_index = index
	for tab_index in _section_tabs.size():
		var tab := _section_tabs[tab_index] as Button
		if tab == null:
			continue
		UiStyle.apply_chip_selected(tab, tab_index == index)
		UiStyle.apply_chip_hover(tab, tab_index == index)
	if _model_box != null:
		_model_box.visible = index == 0
	_sync_tools()
	_present_list(true)


func _on_sort_price() -> void:
	if _section_index != 0:
		_aid_sort_kind = false
	_sync_tools()
	_present_list(false)


func _on_sort_kind() -> void:
	_aid_sort_kind = true
	_sync_tools()
	_present_list(false)


func _toggle_tag(tag: String) -> void:
	if tag == "melee" or tag == "ranged":
		_unit_tags[tag] = not bool(_unit_tags[tag])
	else:
		_aid_tags[tag] = not bool(_aid_tags[tag])
	_sync_tools()
	_present_list(false)


func _sync_tools() -> void:
	if _sort_price == null:
		return
	var units := _section_index == 0
	_sort_kind.visible = not units
	UiStyle.apply_chip_selected(_sort_price, units or not _aid_sort_kind)
	UiStyle.apply_chip_hover(_sort_price, units or not _aid_sort_kind)
	UiStyle.apply_chip_selected(_sort_kind, not units and _aid_sort_kind)
	UiStyle.apply_chip_hover(_sort_kind, not units and _aid_sort_kind)
	for key in _filter_buttons.keys():
		var button := _filter_buttons[key] as Button
		if button == null:
			continue
		var unit_tag: bool = String(key) == "melee" or String(key) == "ranged"
		button.visible = unit_tag == units
		var on := bool(_unit_tags.get(key, false)) if unit_tag else bool(_aid_tags.get(key, false))
		UiStyle.apply_chip_selected(button, on)
		UiStyle.apply_chip_hover(button, on)


func _tool_chip(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	UiStyle.decorate_chip(button)
	button.clip_text = false
	button.custom_minimum_size = Vector2(0.0, 34.0)
	return button


func _present_list(pick_first: bool) -> void:
	var keep := "" if pick_first else _selected_id
	_rebuild_list()
	if keep != "" and _picks.has(keep):
		if _section_index == 0:
			_select(keep)
		else:
			_select_aid(keep)
		return
	if _picks.is_empty():
		_selected_id = ""
		_clear_detail()
		return
	var first := String(_picks.keys()[0])
	if _section_index == 0:
		_select(first)
	else:
		_select_aid(first)


func _clear_detail() -> void:
	if _detail == null:
		return
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_add_body("无")
	if _model != null and _pivot != null:
		_pivot.remove_child(_model)
		_model.queue_free()
		_model = null


func _rebuild_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_picks.clear()
	if _section_index == 0:
		_rebuild_units()
	else:
		_rebuild_aids()
	if _picks.is_empty():
		var empty := UiStyle.make_label("无", UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
		empty.name = "CodexEmpty"
		_list.add_child(empty)


func _rebuild_units() -> void:
	var rows: Array = []
	for type_id in GameConfig.TYPE_ORDER:
		var id := String(type_id)
		if GameConfig.is_roguelike_only(id):
			continue
		var profile := GameConfig.profile(id)
		var ranged := _listed_as_ranged(id, profile)
		if not _tag_allows(_unit_tags, "melee", not ranged):
			continue
		if not _tag_allows(_unit_tags, "ranged", ranged):
			continue
		rows.append({
			"id": id,
			"price": int(profile.get("weight", 0)),
			"order": GameConfig.TYPE_ORDER.find(id),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["price"]) != int(b["price"]):
			return int(a["price"]) < int(b["price"])
		return int(a["order"]) < int(b["order"])
	)
	var last_price := -1
	var index := 0
	for raw in rows:
		var row: Dictionary = raw
		var price := int(row["price"])
		if price != last_price:
			last_price = price
			var heading := UiStyle.make_label("价格 %d" % price, UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
			heading.name = "UnitPrice_%d" % price
			_list.add_child(heading)
		var id := String(row["id"])
		var profile := GameConfig.profile(id)
		_add_pick("UnitPick_%d" % index, id, "%s    %s" % [String(profile.get("name", id)), str(price)], true)
		index += 1


func _rebuild_aids() -> void:
	var rows: Array = []
	for raw in GameConfig.roguelike_aid_catalog():
		var row: Dictionary = raw
		if not _aid_row_visible(row):
			continue
		rows.append(row)
	if _aid_sort_kind:
		var order := ["variant", "expert", "prop", "module"]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var group_a := order.find(String(a.get("group", "")))
			var group_b := order.find(String(b.get("group", "")))
			if group_a < 0:
				group_a = 99
			if group_b < 0:
				group_b = 99
			if group_a != group_b:
				return group_a < group_b
			return String(a.get("name", "")) < String(b.get("name", ""))
		)
	else:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var cost_a := int(a.get("cost", 0))
			var cost_b := int(b.get("cost", 0))
			if cost_a != cost_b:
				return cost_a < cost_b
			return String(a.get("name", "")) < String(b.get("name", ""))
		)
	var last_key := ""
	var index := 0
	for raw in rows:
		var row: Dictionary = raw
		var key := String(row.get("group", "")) if _aid_sort_kind else str(int(row.get("cost", 0)))
		if key != last_key:
			last_key = key
			var title := _aid_group_name(key) if _aid_sort_kind else "价格 %s" % key
			var heading := UiStyle.make_label(title, UiStyle.FONT_SMALL, UiStyle.COLOR_DIM)
			heading.name = "AidGroup_%s" % key
			_list.add_child(heading)
		var id := String(row.get("id", ""))
		_add_pick("AidPick_%d" % index, id, String(row.get("name", id)), false)
		index += 1


func _aid_row_visible(row: Dictionary) -> bool:
	var cost := int(row.get("cost", 0))
	var group := String(row.get("group", ""))
	if not _tag_allows(_aid_tags, "free", cost == 0):
		return false
	if not _tag_allows(_aid_tags, "variant", group == "variant"):
		return false
	if not _tag_allows(_aid_tags, "expert", group == "expert"):
		return false
	if not _tag_allows(_aid_tags, "prop", group == "prop"):
		return false
	if not _tag_allows(_aid_tags, "module", group == "module"):
		return false
	return true


## 没选中的标签不参与。选中了就必须命中，多个标签是交集。
## 图鉴里的「远程」包含持续照射。玩法表上的 `is_ranged` 仍只表示会射出箭。
func _listed_as_ranged(type_id: String, profile: Dictionary) -> bool:
	if bool(profile.get("is_ranged", false)):
		return true
	return bool(profile.get("sustained_beam", false)) or type_id == "corruptor" or type_id == "doom_eye"


func _tag_allows(tags: Dictionary, tag: String, matches: bool) -> bool:
	if not bool(tags.get(tag, false)):
		return true
	return matches


func _add_pick(node_name: String, id: String, text: String, unit: bool) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiStyle.decorate_chip(button)
	button.clip_text = false
	button.custom_minimum_size = Vector2(LIST_WIDTH - 16.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unit:
		button.pressed.connect(_select.bind(id))
	else:
		button.pressed.connect(_select_aid.bind(id))
	_list.add_child(button)
	_picks[id] = button


func _aid_group_name(group: String) -> String:
	match group:
		"variant":
			return "兵种变种"
		"expert":
			return "专家"
		"prop":
			return "战场道具"
		"module":
			return "战术模块"
	return group


func _select_aid(aid_id: String) -> void:
	_selected_id = aid_id
	for id in _picks.keys():
		var button := _picks[id] as Button
		if button != null:
			UiStyle.apply_chip_selected(button, String(id) == aid_id)
	_fill_aid(aid_id)


func _fill_aid(aid_id: String) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var row := GameConfig.roguelike_aid_def(aid_id)
	_add_heading(String(row.get("name", aid_id)), UiStyle.FONT_LARGE)
	_add_body(_aid_group_name(String(row.get("group", ""))))
	var cost := int(row.get("cost", 0))
	_add_body("补给  %d" % cost if cost > 0 else "不花补给")
	_add_gap()
	_add_heading("效果", UiStyle.FONT_MID)
	_add_body(String(row.get("blurb", "")))


func _select(type_id: String) -> void:
	_selected_id = type_id
	for id in _picks.keys():
		var button := _picks[id] as Button
		if button != null:
			UiStyle.apply_chip_selected(button, String(id) == type_id)
	_fill_detail(type_id)
	_show_model(type_id)

func _fill_detail(type_id: String) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var profile := GameConfig.profile(type_id)
	_add_heading(String(profile.get("name", type_id)), UiStyle.FONT_LARGE)
	if GameConfig.is_sandbox_only(type_id):
		_add_body("仅沙盒")
	_add_gap()
	_add_heading("数值", UiStyle.FONT_MID)
	var damage := _fmt(float(profile.get("damage", 0.0)))
	var swings := int(profile.get("attacks_per_swing", 1))
	if swings > 1:
		damage += " × %d" % swings
	_add_body("血量  %s" % _fmt(float(profile.get("hp", 0.0))))
	_add_body("伤害  %s" % damage)
	_add_body("攻速  %s 次/秒" % _fmt(float(profile.get("attack_speed", 0.0))))
	_add_body("射程  %s 米" % _fmt(float(profile.get("range", 0.0))))
	_add_body("权重  %s" % str(profile.get("weight", 0)))
	_add_body("重量  %s" % str(profile.get("mass", 0)))
	_add_body("移速  %s 米/秒" % _fmt(float(profile.get("move_speed", 0.0))))
	_add_gap()
	_add_heading("特性", UiStyle.FONT_MID)
	var traits: Array = _traits(type_id)
	if traits.is_empty():
		_add_body("无")
	else:
		for entry in traits:
			var row: Dictionary = entry
			_add_body(String(row["name"]))
			_add_body(String(row["line"]))
	_add_gap()
	_add_heading("技能", UiStyle.FONT_MID)
	var skills: Array = _skills(type_id)
	if skills.is_empty():
		_add_body("无")
	else:
		for entry in skills:
			var row: Dictionary = entry
			_add_body(String(row["name"]))
			_add_body("触发  %s" % String(row["trigger"]))
			_add_body("效果  %s" % String(row["effect"]))
			_add_body("冷却  %s" % String(row["cooldown"]))
			_add_gap()
	_add_heading("科技", UiStyle.FONT_MID)
	var techs: Array = GameConfig.roguelike_tech_list(type_id)
	if techs.is_empty():
		_add_body("无")
		return
	for entry in techs:
		var tech: Dictionary = entry
		_add_body("%s    补给 %s" % [String(tech.get("name", "")), str(tech.get("cost", 0))])
		_add_body(GameConfig.roguelike_tech_desc(type_id, String(tech.get("id", ""))))
		_add_gap()

func _traits(type_id: String) -> Array:
	var rows: Array = []
	match type_id:
		"sword":
			rows.append(_trait("挡箭", "正面来的箭会被盾挡住。出手时盾让开，这一下挡不住。"))
		"spear":
			rows.append(_trait("强击退", "命中会把对方推开。"))
		"shortbow":
			rows.append(_trait("抛物线", "箭会下坠，并预判落点。"))
		"longbow":
			rows.append(_trait("抛物线", "箭更快、飞得更远，会下坠并预判落点。"))
		"fan":
			rows.append(_trait("扇形", "一挥打中面前的一片敌人，并把他们推开。"))
		"knight":
			rows.append(_trait("挡箭", "正面来的箭会被盾挡住。普通出手时盾让开，猛击时仍然挡着。"))
		"catapult":
			rows.append(_trait("抛射", "石弹落地炸开。直接命中更疼，旁边的人吃较轻的一击，并被击退、眩晕。盾挡不住。"))
		"ballista":
			rows.append(_trait("重弩", "命中把人推得很远。被推开的人还会把伤害传给旁边的敌人。盾挡不住。"))
		"berserker":
			rows.append(_trait("双斧", "一次出手两把斧各打一下。"))
		"sandworm":
			rows.append(_trait("扇形撕咬", "普通攻击打中面前的一片敌人。"))
		"musket":
			rows.append(_trait("火枪", "子弹很快，盾挡不住，还能再打穿后面一名敌人。"))
		"corruptor":
			rows.append(_trait("策反", "激光不掉血，改成往目标身上叠腐化。叠过剩余血量，目标整队换边。要先蓄力，停照就清掉。"))
		"doom_eye":
			rows.append(_trait("能量汇集", "激光照着同一个人会越来越疼。换目标或丢掉锁定就回到最初。"))
		"grenadier":
			rows.append(_trait("自爆", "真正阵亡时炸开周围的敌人。收掉或中途拆掉不会炸。"))
		"shadow":
			rows.append(_trait("影袭", "受到伤害时免掉这一下，化成影子扑到伤害来源那一类最近的敌人身边，并眩晕它。"))
			rows.append(_trait("时候已到", "隔得越久，下一刀越疼。出手后重新积攒，从影子回来时直接到顶。"))
	if GameConfig.is_anchored(type_id):
		rows.append(_trait("锚定", "自己不走，也推不动。"))
	if GameConfig.is_stun_immune(type_id):
		rows.append(_trait("免疫眩晕", "不会被眩晕。"))
	return rows

func _skills(type_id: String) -> Array:
	match type_id:
		"knight":
			return [
				_skill("冲撞", "最近的敌人靠近，且自己不在出手。", "冲过去撞伤并击退，途中穿过队友。", _cd(GameConfig.UNIT_CHARGE_CD_MS)),
				_skill("盾牌猛击", "目标在射程内，且猛击已经冷却好。", "打出一记近战，并附带击退。", _cd(GameConfig.UNIT_BASH_CD_MS)),
			]
		"berserker":
			return [
				_skill("火箭跳跃", "最近的敌人在中距离，且自己不在出手。", "跳到目标附近。滞空和落地的一小段时间不受伤害，途中穿过队友。", _cd(GameConfig.UNIT_JUMP_CD_MS)),
			]
		"flamefist":
			return [
				_skill("炎爆", "锁定的目标在中距离。太近或太远都不会放。", "蓄力后冲过去。撞上的人被击退并眩晕，稍后再爆炸，自己也会晕一下。目标离开那段距离，蓄力就取消。", "无"),
			]
		"lightcav":
			return [
				_skill("冲刺", "锁定的目标靠近，且这一场还有次数。", "朝目标冲锋，刮到面前的敌人。每场 %d 次。" % GameConfig.UNIT_LANCE_CHARGES_MAX, "%s，从结束起算" % _cd(GameConfig.UNIT_LANCE_CD_MS)),
			]
		"sandworm":
			return [
				_skill("潜地", "攻击范围内没有敌人就钻入，有敌人就钻出。", "地下时打不中，也锁不住。钻出时震晕周围，第一口更疼。", "无"),
			]
		"master":
			return [
				_skill("高级偏折", "小型投射物打到自己。", "把这一发弹回去，变成己方的。次数用完就不再挡。", "每挡满 %d 次，冷却 %s" % [GameConfig.UNIT_MASTER_DEFLECT_PER_COOLDOWN, _cd(GameConfig.UNIT_MASTER_DEFLECT_CD_MS)]),
				_skill("冲刺", "锁定的目标在攻击范围之外，又还没走远。", "冲到能打到的距离就停，不造成伤害，也不击退。", _cd(GameConfig.UNIT_MASTER_DASH_CD_MS)),
				_skill("后撤步", "敌方近战正要打到自己，或冲锋中的轻骑兵已经贴近。", "滑到自己身后的一段弧上。", _cd(GameConfig.UNIT_MASTER_BACKSTEP_CD_MS)),
				_skill("拔刀斩", "冷却结束，且锁定的目标就在身边。", "先后撤再蓄力，然后穿过沿途的敌人。被穿过的人会被定身，定身结束时吃一记重击。全程无敌。", _cd(GameConfig.UNIT_MASTER_IAI_CD_MS)),
			]
		"pillar":
			return [
				_skill("单位召唤", "战斗进行中，按固定节拍。", "每一拍召来本队的兵。打得越久，一拍越多，最多 %d 个。" % GameConfig.UNIT_SUMMON_MAX_BATCH, "每 %s 一拍" % _cd(GameConfig.UNIT_SUMMON_INTERVAL_MS)),
			]
	return []

func _trait(trait_name: String, line: String) -> Dictionary:
	return {"name": trait_name, "line": line}

func _skill(skill_name: String, trigger: String, effect: String, cooldown: String) -> Dictionary:
	return {"name": skill_name, "trigger": trigger, "effect": effect, "cooldown": cooldown}

func _cd(ms: int) -> String:
	var seconds := float(ms) / 1000.0
	if is_equal_approx(seconds, round(seconds)):
		return "%d 秒" % int(round(seconds))
	return "%.1f 秒" % seconds

func _fmt(n: float) -> String:
	var text := "%.2f" % n
	while text.contains(".") and (text.ends_with("0") or text.ends_with(".")):
		text = text.substr(0, text.length() - 1)
	return text

func _add_heading(text: String, size: int) -> void:
	var color := UiStyle.COLOR_TEXT
	if size < UiStyle.FONT_LARGE:
		color = UiStyle.COLOR_WARN
	var label := UiStyle.make_label(text, size, color)
	label.name = "DetailHeading_%d" % _detail.get_child_count()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(label)

func _add_body(text: String) -> void:
	var label := UiStyle.make_label(text, UiStyle.FONT_SMALL, UiStyle.COLOR_TEXT)
	label.name = "DetailLine_%d" % _detail.get_child_count()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(label)

func _add_gap() -> void:
	var gap := Control.new()
	gap.name = "DetailGap_%d" % _detail.get_child_count()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(gap)

func _show_model(type_id: String) -> void:
	if _model != null:
		_pivot.remove_child(_model)
		_model.queue_free()
		_model = null
	var parts := UnitFactory.build(type_id, 0)
	var visual := parts["visual"] as Node3D
	visual.name = "CodexModel"
	for node in visual.find_children("*", "", true, false):
		if String(node.name).begins_with("Fx"):
			var shown := node as Node3D
			if shown != null:
				shown.visible = false
	_pivot.add_child(visual)
	_pivot.rotation = Vector3(0.0, CODEX_FRONT_YAW_RAD, 0.0)
	_model = visual
	_frame_camera(type_id)

func _frame_camera(type_id: String) -> void:
	var top := GameConfig.pilot_body_top(type_id)
	var front := GameConfig.pilot_body_front(type_id)
	var span := maxf(maxf(top, front * 2.0), 1.6)
	var look := Vector3(0.0, top * 0.42, 0.0)
	_cam.position = look + Vector3(span * 1.15, span * 0.28, span * 2.6)
	_cam.look_at(look, Vector3.UP)
