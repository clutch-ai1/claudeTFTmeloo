extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	await get_tree().create_timer(0.3).timeout
	m._start_calibration()
	await get_tree().create_timer(2.0).timeout
	print("calib? ", m.calib != null, " win ", get_window().size, " ", get_window().position)
	get_viewport().get_texture().get_image().save_png("/tmp/cal1.png")
	var c = m.calib
	# Rahmen ziehen per simulierten Maus-Events
	for ev in [[true, Vector2(300,700)], [false, Vector2(900,800)]]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = ev[0]; e.position = ev[1]; e.global_position = ev[1]
		get_viewport().push_input(e)
		await get_tree().process_frame
		await get_tree().process_frame
	print("rects nach Ziehen: ", c.rects, " size ", c.size, " main ", m.size)
	print("hit: ", get_viewport().gui_get_hovered_control() if get_viewport().has_method("gui_get_hovered_control") else "")
	get_viewport().get_texture().get_image().save_png("/tmp/cal2.png")
	for i in 6: c._next()
	await get_tree().create_timer(0.5).timeout
	print("fertig: calib=", m.calib, " rects=", m.rects.keys(), " win ", get_window().size)
	get_tree().quit()
