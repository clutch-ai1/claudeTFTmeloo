extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	m.pilot = load("res://tests/fakeocr.gd").new()
	add_child(m)
	await get_tree().process_frame
	m.use_ocr = true
	m.brain.target = Meta.comps.filter(func(c): return c["name"] == "Renegade Graves")[0] if Meta.comps.any(func(c): return c["name"] == "Renegade Graves") else Meta.comps[0]
	for f in ["00004_2_1_alle_5s.jpg", "00014_2_2_alle_5s.jpg"]:
		var img := Image.load_from_file("/mnt/user-data/uploads/Desktop/TFT Boss/bot_spiele/20261122_064133/" + f)
		m.pick_ms = -100000
		m.auto_last_img_size = img.get_size()
		m._pick_ocr(img)
		print(f, " on=", m.pick_on, " items=", m.pick_names, " scores=", m.pick_names.map(func(n): return m._pick_score(n)))
		m._pick_step(Time.get_ticks_msec())
		print("  ", m.pilot.actions)
	get_tree().quit()
