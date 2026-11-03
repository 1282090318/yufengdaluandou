extends Node3D
## 临时渲染脚本（用后即删）：狂战士成品 + 五个"新补眼睛"兵种的面部对照。

const ROW := ["fan", "master", "longbow", "musket", "lightcav"]

func _ready() -> void:
	var berserker := UnitFactory.build("berserker", 0)["visual"] as Node3D
	add_child(berserker)
	## 一排"新补眼睛"的兵种，间距 0.95 m
	for i in ROW.size():
		var visual := UnitFactory.build(String(ROW[i]), 0)["visual"] as Node3D
		visual.position = Vector3(-1.9 + 0.95 * float(i), 0.0, 2.2)
		add_child(visual)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.62, 0.70, 0.0)
	light.light_energy = 1.5
	light.shadow_enabled = false
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.35, -2.4, 0.0)
	fill.light_energy = 0.6
	fill.shadow_enabled = false
	add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.76)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	var shots := [
		["res://berserker_full.png", Vector3(1.15, 1.25, -2.9), Vector3(0.0, 1.00, 0.0)],
		["res://berserker_head.png", Vector3(0.55, 1.80, -1.25), Vector3(0.0, 1.58, -0.02)],
		["res://faces_row.png", Vector3(0.0, 1.75, -3.3), Vector3(0.0, 1.50, 2.2)],
	]
	for shot in shots:
		cam.position = shot[1]
		cam.look_at(shot[2])
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(shot[0]))
		print("SHOT_SAVED=", shot[0])
	get_tree().quit()
