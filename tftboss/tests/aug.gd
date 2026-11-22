extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	m.pilot = load("res://tests/fakeocr.gd").new()
	add_child(m)
	await get_tree().process_frame
	m.use_ocr = true
	m.brain.stage = "4-2"
	for f in ["00144_4_2_davor.jpg", "00150_4_2_davor.jpg", "00164_4_2_davor.jpg", "00184_4_2_davor.jpg"]:
		var img := Image.load_from_file("/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_042302/" + f)
		m.aug_ocr_ms = -100000
		m.auto_last_img_size = img.get_size()
		m._aug_ocr(img)
		print(f, " screen=", m.aug_screen, " offer=", m.brain.aug_offer, " scores=", m.brain.aug_offer.map(func(a): return snappedf(m.brain.aug_score(a), 0.1)))
		if m.aug_screen and m.brain.aug_offer.size() == 3:
			var r: bool = m._aug_reroll_step(Time.get_ticks_msec())
			print("   reroll? ", r, " ", m.pilot.actions)
	get_tree().quit()
