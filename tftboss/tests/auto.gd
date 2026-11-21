extends Node
func _ready():
	var W := Window.new()
	W.borderless = true; W.position = Vector2i(0,0); W.size = Vector2i(1280,1024)
	var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(Image.load_from_file("/home/claude/tbtest/fake2.png"))
	W.add_child(tr); add_child(W); W.show()
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	get_window().position = Vector2i(400, 100); get_window().size = Vector2i(460, 500)
	var fp = load("res://tests/fakepilot.gd").new()
	m.pilot = fp
	m.vision.forget_all()
	var v = m.vision
	var L = func(p): return Image.load_from_file("/home/claude/tbtest/" + p)
	for pair in [["g34.png","34"],["s32.png","3-2"],["l7.png","7"]]:
		var rr = v.read_number("t" + pair[0], L.call(pair[0])); v.learn_number(rr["glyphs"], pair[1], rr["meta"])
	for pair in [["cardA.png","Annie"],["cardB.png","Graves"],["cardC.png","Zoe"]]:
		v.learn("shop", Vision.norm_sig(L.call(pair[0]).resized(140,110) if false else L.call(pair[0]), 16, 12), pair[1])
	m.rects = {"stage":[0.78125,0.01953,0.0547,0.0293],"gold":[0.78125,0.1172,0.0547,0.0293],"level":[0.78125,0.1953,0.0547,0.0293],"shop":[0.4375,0.8594,0.5469,0.1074]}
	m.running = true
	m.auto_on = true; m.auto_title = "TFT"
	await get_tree().create_timer(6.0).timeout
	print("Shop erkannt: ", m.brain.shop)
	print("Aktionen: ", fp.actions)
	print("Log: ", m.auto_log)
	# Not-Aus
	fp.panic = true
	await get_tree().create_timer(1.0).timeout
	print("nach F8: auto_on=", m.auto_on)
	# Fenster nicht vorne
	m.auto_on = true; fp.title = "Discord"; var n = fp.actions.size()
	await get_tree().create_timer(1.5).timeout
	print("TFT nicht vorne -> neue Aktionen: ", fp.actions.size() - n, " Status: ", m.lbl_auto.get_parsed_text().split("\n")[0])
	get_tree().quit()
