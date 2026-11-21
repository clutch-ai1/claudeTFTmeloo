extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	var fp = load("res://tests/fakeocr.gd").new()
	m.pilot = fp
	add_child(m)
	await get_tree().process_frame
	m.running = false
	m.use_ocr = true
	for f in ["d9b0cff2", "a30daba4", "016a0d21", "b04f681a", "d9b0cff2"]:
		var img := Image.load_from_file("/mnt/user-data/uploads/%s-image.png" % f)
		m.menu_ms = -100000
		m._update_phase(img)
		print(f, " -> ", m.phase, " (", m.PHASE_DE[m.phase], ")")
	# Ladebildschirm: nach Match gefunden ein unbekanntes Bild
	m.phase = "match"; m.menu_ms = -100000
	var black := Image.create(1920, 1080, false, Image.FORMAT_RGB8)
	m._update_phase(black)
	print("schwarz nach Match -> ", m.phase)
	get_tree().quit()
