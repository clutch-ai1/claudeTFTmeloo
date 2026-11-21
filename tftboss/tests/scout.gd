extends Node
var tr: TextureRect
func show_player(p: int):
	tr.texture = ImageTexture.create_from_image(Image.load_from_file("/home/claude/tbtest/scout%d.png" % p))
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1280,1024)
	tr = TextureRect.new(); W.add_child(tr); add_child(W); W.show()
	show_player(1)
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	get_window().position = Vector2i(400, 600); get_window().size = Vector2i(460, 400)
	var fp = load("res://tests/fakepilot.gd").new()
	fp.on_click = func(p: Vector2i):
		if p.x > 1100: show_player(clampi((p.y - 180) / 40, 0, 7))
	m.pilot = fp
	m.vision.forget_all()
	var v = m.vision
	var L = func(p): return Image.load_from_file("/home/claude/tbtest/" + p)
	for pair in [["g34.png","34"],["s32.png","3-2"],["l7.png","7"],["g52.png","52"],["g10.png","10"]]:
		var rr = v.read_number("t" + pair[0], L.call(pair[0])); v.learn_number(rr["glyphs"], pair[1], rr["meta"])
	m.rects = {"stage":[0.78125,0.01953,0.0547,0.0293],"gold":[0.78125,0.1172,0.0547,0.0293],"level":[0.78125,0.1953,0.0547,0.0293],
		"traits":[120.0/1280, 80.0/1024, 50.0/1280, 320.0/1024, 8], "lobby":[1150.0/1280, 180.0/1024, 110.0/1280, 320.0/1024, 8], "hp":[1150.0/1280, 220.0/1024, 110.0/1280, 40.0/1024]}
	m.running = true
	# Fragen automatisch beantworten (wie ein Nutzer): Zahlen und Stufen
	var answers := 0
	for k in 40:
		await get_tree().create_timer(0.7).timeout
		if m.prompt_box.visible:
			var pr = m.prompt
			if pr["kind"] == "num":
				var x = v.read_number("q", pr["img"])
				var guess = {"hp": "92", "lobby": str([100,92,88,75,61,54,40,22][0])}
				# Lobby-Zahl: anhand der Bildposition schwer, daher Text aus dem Bild nehmen
				m._prompt_submit("92" if pr["key"] == "hp" else "1")
			elif pr["kind"] == "tier":
				var f: PackedByteArray = pr["sig"]
				var col := Color8(f[0], f[1], f[2])
				var lab := "inaktiv"
				if f[3] < 10: lab = "(leer)"
				elif col.s < 0.25 and col.v > 0.55: lab = "silber"
				elif col.s < 0.3: lab = "inaktiv"
				elif col.h > 0.7: lab = "prisma"
				elif col.h < 0.08: lab = "bronze"
				else: lab = "gold"
				m._answer(lab)
			answers += 1
	print("Antworten gegeben: ", answers)
	print("Erkannt: ", m.lbl_seen.text)
	print("Mein Leben: ", m.brain.hp, " Lobby: ", m.brain.lobby_hp, " eigene Traits: ", m.brain.my_score)
	m.brain.stage = "2-1"
	m.auto_on = true; m.auto_title = "TFT"; m.stage_changed_ms = 0; m.scouted_stage = ""
	await get_tree().create_timer(6.0).timeout
	print("Gegner-Scores: ", m.brain.opp_scores, " Siegchance: ", m.brain.win_chance)
	print("Klicks: ", fp.actions.filter(func(a): return a.begins_with("click 12")).size(), " Plan: ", m.brain.plan, " | ", m.brain.plan_why)
	print("Log: ", m.auto_log.slice(-3))
	get_tree().quit()
