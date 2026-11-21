extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	add_child(m)
	get_window().size = Vector2i(460, 1500)
	await get_tree().create_timer(0.5).timeout
	m.running = false
	m.rects = {"shop": [0.25,0.88,0.5,0.1]}
	var b = m.brain
	b.stage = "3-2"; b.level = 6; b.gold = 34
	b.owned = {"Annie": 2, "Zoe": 2, "Renekton": 1, "Graves": 1, "Zac": 1}
	b.shop = ["Graves", "Aurora", "Gnar", "Elise", "Taliyah"]
	b.comps_have = {"Recurve Bow": 1, "Sparring Gloves": 1, "B.F. Sword": 1}
	b.my_augs = ["Arcanist Circlet"]
	m._refresh_all()
	var v := Vision.new()
	m._ask({"kind": "shop", "sig": PackedByteArray(), "img": Image.load_from_file("/home/claude/tbtest/cardA.png"), "slot": 2})
	m.prompt_edit.text = "ga"; m._prompt_typed("ga")
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/shot.png")
	get_tree().quit()
