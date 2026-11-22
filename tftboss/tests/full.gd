extends Node
func _ready():
	var path := OS.get_environment("BILD")
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1920,1080)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file(path))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	var fp = load("res://tests/fakeocr.gd").new()
	m.pilot = fp
	add_child(m)
	get_window().position = Vector2i(1400, 600); get_window().size = Vector2i(400, 300)
	m.rects = {}; m._apply_defaults(); m.screen_idx = 0; m.use_ocr = true; m.running = true
	await get_tree().create_timer(4.0).timeout
	print("Brain: stage=", m.brain.stage, " gold=", m.brain.gold, " lvl=", m.brain.level, " hp=", m.brain.hp, " lobby=", m.brain.lobby_hp, " streak=", m.brain.streak, " plan=", m.brain.plan)
	print("HUD: units=", m.hud_units, " orbs=", m.hud_orbs, " items=", m.hud_items.size())
	m.auto_on = true; m.auto_title = "TFT"; m.scouted_stage = m.brain.stage
	m.bot_dir = "/tmp/bt"; DirAccess.make_dir_recursive_absolute("/tmp/bt")
	if OS.get_environment("ARR") != "":
		m.brain.target = Meta.comps[0]
		m.arranged_stage = ""
		m.stage_changed_ms = Time.get_ticks_msec() - 5000
	if OS.get_environment("SCOUT") != "":
		m.scouted_stage = ""
	await get_tree().create_timer(int(OS.get_environment("SEK")) if OS.get_environment("SEK") != "" else 15).timeout
	print("Aktionen: ", fp.actions)
	print("Log: ", m.auto_log)
	get_tree().quit()
