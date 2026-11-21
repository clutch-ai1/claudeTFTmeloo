extends Node
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1280,1024)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file("/home/claude/tbtest/fake2.png"))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	get_window().position = Vector2i(400, 100); get_window().size = Vector2i(460, 500)
	m.vision.forget_all()
	var v = m.vision
	var L = func(p): return Image.load_from_file("/home/claude/tbtest/" + p)
	for pair in [["g34.png","34"],["s32.png","3-2"],["l7.png","7"]]:
		v.learn_number(v.read_number("t", L.call(pair[0]))["glyphs"], pair[1])
	m.rects = {"stage":[0.78125,0.01953,0.0547,0.0293],"gold":[0.78125,0.1172,0.0547,0.0293],"level":[0.78125,0.1953,0.0547,0.0293],"shop":[0.4375,0.8594,0.5469,0.1074],"items":[0.046875, 0.390625, 0.03125, 0.234375]}
	m.running = true
	W.grab_focus()
	var answers = {"shop": ["Annie","Graves","Zoe"], "item": ["Recurve Bow","Sparring Gloves","B.F. Sword"]}
	for step in 12:
		await get_tree().create_timer(1.3).timeout
		if m.prompt_box.visible:
			var k = m.prompt["kind"]
			print("FRAGE: ", m.prompt_q.text)
			if k == "item":
				m._answer(["Recurve Bow", "Sparring Gloves", "(leer)", "B.F. Sword", "Recurve Bow", "(leer)"][m.prompt["slot"]])
			elif answers.has(k) and answers[k].size() > 0:
				m._answer(answers[k].pop_front())
	await get_tree().create_timer(1.5).timeout
	print("SEEN: ", m.lbl_seen.text)
	print("DO: ", m.lbl_do.get_parsed_text().replace("\n", " / "))
	get_viewport().get_texture().get_image().save_png("/tmp/e2e.png")
	get_tree().quit()
