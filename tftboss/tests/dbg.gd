extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	await get_tree().create_timer(0.3).timeout
	m._start_calibration("gold")
	await get_tree().create_timer(0.8).timeout
	var c = m.calib
	var W: Window = m.calib_win
	var btn
	for b in c.panel.find_children("*", "Button", true, false):
		if b.text == "Speichern": btn = b
	btn.gui_input.connect(func(e): print("BTN bekam ", e.pressed if e is InputEventMouseButton else ""))
	btn.pressed.connect(func(): print("PRESSED signal"))
	btn.button_down.connect(func(): print("DOWN signal"))
	print("action_mode ", btn.action_mode, " disabled ", btn.disabled, " mask ", btn.button_mask, " toggle ", btn.toggle_mode)
	c.gui_input.connect(func(e): if e is InputEventMouseButton: print("CALIB bekam ", e.position))
	c.panel.gui_input.connect(func(e): print("PANEL bekam ", e))
	for i in 3: await get_tree().process_frame
	var p = btn.get_global_rect().get_center()
	print("btn ", btn.get_global_rect(), " panel ", c.panel.get_global_rect(), " win ", W.size, " vis ", W.get_visible_rect())
	for q in [p, Vector2(300, 300)]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = q; e.global_position = q
		W.push_input(e)
		await get_tree().process_frame
		e = e.duplicate(); e.pressed = false
		W.push_input(e)
		await get_tree().process_frame
	get_tree().quit()
