extends Node
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1920,1080)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file("/mnt/user-data/uploads/cdf58647-image.png"))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	var fp = load("res://tests/fakeocr.gd").new()
	m.pilot = fp
	add_child(m)
	get_window().position = Vector2i(1400, 600); get_window().size = Vector2i(400, 300)
	m.rects = {}
	m._apply_defaults()
	m.screen_idx = 0
	m.use_ocr = true
	m.running = true
	await get_tree().create_timer(4.0).timeout
	print("SEEN: ", m.lbl_seen.text)
	print("Brain: stage=", m.brain.stage, " gold=", m.brain.gold, " lvl=", m.brain.level, " lobby=", m.brain.lobby_hp, " traits=", m.brain.my_traits, " score=", m.brain.my_score)
	print("DO: ", m.lbl_do.get_parsed_text().replace("\n", " / "))
	m.auto_on = true; m.auto_title = "TFT"; m.scouted_stage = m.brain.stage
	await get_tree().create_timer(3.0).timeout
	print("Klicks: ", fp.actions)
	var shot := Image.load_from_file("/mnt/user-data/uploads/cdf58647-image.png")
	var gc: Image = shot.get_region(m._grow(shot, m._rect_px(shot, "gold"), 0.3, 0.3, 0.2, 0.2))
	print("Selbst gelernt, Gold ohne OCR: ", m._digits_selflearn("gold", gc, -1, 300))
	print("Lobby: ", m._lobby_entries(shot)); print("Streak: ", m.brain.streak, " seen ", m.brain.streak_seen, " Plan ", m.brain.plan, " ", m.brain.plan_why)
	print("Log: ", m.auto_log.slice(-5))
	get_tree().quit()
