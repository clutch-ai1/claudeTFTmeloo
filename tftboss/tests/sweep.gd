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
	m.rects = {}; m._apply_defaults(); m.screen_idx = 0; m.use_ocr = true; m.running = true
	await get_tree().create_timer(3.0).timeout
	m.auto_on = true; m.auto_title = "TFT"; m.scouted_stage = m.brain.stage
	m.last_stage_num = 17   # tun so, als käme gerade eine Monster-Runde zu Ende
	m._on_stage("2-5")
	m.last_stage_num = 17
	m.brain.stage = "2-7"; m._on_stage("2-5")
	await get_tree().create_timer(12.0).timeout
	print("Aktionen: ", fp.actions)
	print("Log: ", m.auto_log.slice(-6))
	get_tree().quit()
