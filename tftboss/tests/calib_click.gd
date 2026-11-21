extends Node
var W: Window
func ev_btn(p: Vector2, pr: bool):
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pr; e.position = p; e.global_position = p; e.button_mask = MOUSE_BUTTON_MASK_LEFT if pr else 0
	W.push_input(e)
	await get_tree().process_frame
func click(p: Vector2):
	var mm := InputEventMouseMotion.new(); mm.position = p; mm.global_position = p
	W.push_input(mm); await get_tree().process_frame
	await ev_btn(p, true); await ev_btn(p, false)
func drag(a: Vector2, b: Vector2):
	await ev_btn(a, true)
	var mm := InputEventMouseMotion.new(); mm.position = b; mm.global_position = b; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	W.push_input(mm); await get_tree().process_frame
	await ev_btn(b, false)
func save_btn(c) -> Vector2:
	for b in c.panel.find_children("*", "Button", true, false):
		if b.text == "Speichern": return b.get_global_rect().get_center()
	return Vector2.ZERO
func _ready():
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	await get_tree().create_timer(0.3).timeout
	m.rects = {}
	for k in ["gold", "shop", "stage", "level", "items"]:
		m._start_calibration(k)
		await get_tree().create_timer(0.8).timeout
		W = m.calib_win
		var c = m.calib
		for i in 3: await get_tree().process_frame
		c._next()
		var warn = c.info.text.find("Erst einen Rahmen") >= 0
		await drag(Vector2(300, 500), Vector2(500, 560))
		var saved_early = m.rects.has(k)
		for i in 2: await get_tree().process_frame
		c._next()
		await get_tree().create_timer(0.4).timeout
		print(k, ": Warnung=", warn, " sofort gespeichert=", saved_early, " zu=", m.calib_win == null, " läuft=", m.running, " Hauptfenster=", get_window().size)
	# Schließen per X
	m._start_calibration("augs")
	await get_tree().create_timer(0.8).timeout
	m.calib_win.close_requested.emit()
	await get_tree().create_timer(0.3).timeout
	print("X: zu=", m.calib_win == null, " läuft=", m.running, " rects=", m.rects.keys())
	get_tree().quit()
