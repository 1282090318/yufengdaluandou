extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var window := get_window()
	var sizes := [
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(1600, 1200),
	]
	for target in sizes:
		DisplayServer.window_set_size(target)
		for i in 5:
			await get_tree().process_frame
		var viewport := get_viewport()
		print("PROBE target=", target, " window=", window.size,
				" visible=", viewport.get_visible_rect().size,
				" factor=", window.content_scale_factor,
				" final=", viewport.get_final_transform())
	get_tree().quit()
