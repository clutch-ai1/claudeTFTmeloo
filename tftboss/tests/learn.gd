extends Node
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1920,1080)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file("/mnt/user-data/uploads/cdf58647-image.png"))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	var fp = load("res://tests/fakeocr.gd").new()
	fp.ok = true
	m.pilot = fp
	add_child(m)
	get_window().position = Vector2i(1400, 600); get_window().size = Vector2i(400, 300)
	m.rects = {}; m._apply_defaults(); m.screen_idx = 0; m.use_ocr = true
	m._toggle_learn()
	await get_tree().create_timer(2.0).timeout
	fp.fake_events = [{"ms": 1, "ev": "L_DOWN", "x": 650, "y": 1000}, {"ms": 90, "ev": "L_UP", "x": 650, "y": 1000}, {"ms": 500, "ev": "D_DOWN", "x": 650, "y": 1000}]
	await get_tree().create_timer(6.0).timeout
	m._toggle_learn()
	print("Dir: ", m.learn_dir, " Bilder ", m.learn_frames, " Eingaben ", m.learn_events)
	print(FileAccess.get_file_as_string(m.learn_dir.path_join("ereignisse.jsonl")).substr(0, 900))
	print(DirAccess.get_files_at(m.learn_dir))
	get_tree().quit()
