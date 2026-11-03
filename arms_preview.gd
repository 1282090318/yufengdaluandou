extends Node

func _ready() -> void:
	call_deferred("_preview")

func _preview() -> void:
	var window := get_tree().root
	window.size = Vector2i(1000, 1000)
	var stage := Node3D.new()
	window.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.12, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.86, 0.94)
	environment.ambient_light_energy = 0.80
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_energy = 1.3
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.28, 0.31, 0.33)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	var specs := [
		["sword", Vector3(2.6, 1.60, -3.2), Vector3(0.0, 1.0, 0.0), 38.0],
		["spear", Vector3(2.9, 1.70, -4.0), Vector3(0.0, 1.0, -0.4), 38.0],
		["shortbow", Vector3(2.6, 1.60, -3.1), Vector3(0.0, 1.0, -0.1), 38.0],
	]
	for spec in specs:
		var parts: Dictionary = UnitFactory.build(String(spec[0]), 0)
		var model := parts["visual"] as Node3D
		model.rotation.y = -0.35
		stage.add_child(model)
		camera.position = spec[1]
		camera.look_at(spec[2])
		camera.fov = float(spec[3])
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		window.get_texture().get_image().save_png("res://arms_%s.png" % spec[0])
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()
