extends Node
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1280,1024)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file("/home/claude/tbtest/fake.png"))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	get_window().position = Vector2i(0, 0); get_window().size = Vector2i(460, 820)
	m.vision.db = {"shop": [], "aug": [], "glyph": []}
	var v = m.vision
	var L = func(p): return Image.load_from_file("/home/claude/tbtest/" + p)
	for pair in [["g34.png","34"],["s32.png","3-2"],["l7.png","7"]]:
		v.learn_number(v.read_number(L.call(pair[0]))["glyphs"], pair[1])
	m.rects = {"stage":[0.78125,0.01953,0.0547,0.0293],"gold":[0.78125,0.1172,0.0547,0.0293],"level":[0.78125,0.1953,0.0547,0.0293],"shop":[0.4375,0.8594,0.5469,0.1074]}
	m.running = true
	W.grab_focus()
	await get_tree().create_timer(2.0).timeout
	print("SEEN: ", m.lbl_seen.text)
	print("PROMPT: ", m.prompt_box.visible, " ", m.prompt_q.text)
	# Prompt beantworten: Platz 1 = Annie, dann weiter
	if m.prompt_box.visible: m._answer("Annie")
	await get_tree().create_timer(1.5).timeout
	if m.prompt_box.visible: print("PROMPT2: ", m.prompt_q.text); m._answer("Graves")
	await get_tree().create_timer(1.5).timeout
	if m.prompt_box.visible: print("PROMPT3: ", m.prompt_q.text); m._answer("Zoe")
	await get_tree().create_timer(1.5).timeout
	print("SEEN: ", m.lbl_seen.text)
	print("DO: ", m.lbl_do.get_parsed_text())
	get_tree().quit()
