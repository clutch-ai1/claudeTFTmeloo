extends Node
func drag(a: Vector2, b: Vector2):
	for ev in [[true, a], [false, b]]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = ev[0]; e.position = ev[1]; e.global_position = ev[1]
		get_viewport().push_input(e)
		await get_tree().process_frame
func _ready():
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	await get_tree().create_timer(0.3).timeout
	m.rects = {}
	m._start_calibration("gold")
	await get_tree().create_timer(1.0).timeout
	print("gold: calib=", m.calib != null, " text=", m.calib.info.text.split("\n")[0])
	await drag(Vector2(100,100), Vector2(160,130))
	get_viewport().get_texture().get_image().save_png("/tmp/cal_gold.png")
	m.calib._next()
	await get_tree().create_timer(0.3).timeout
	print("nach Gold: ", m.rects.keys(), " calib=", m.calib, " win ", get_window().size)
	m._start_calibration("augs")
	await get_tree().create_timer(1.0).timeout
	m.calib._next()  # ohne Rahmen: bleibt offen
	print("augs ohne Rahmen offen: ", m.calib != null)
	m.calib._cancel()
	await get_tree().create_timer(0.3).timeout
	print("nach Abbrechen: ", m.rects.keys(), " calib=", m.calib)
	m._render_advice()
	print("DO: ", m.lbl_do.get_parsed_text().replace("\n"," / "))
	get_tree().quit()
