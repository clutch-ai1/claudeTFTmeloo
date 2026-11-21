extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	m.pilot = load("res://tests/fakeocr.gd").new()
	add_child(m)
	await get_tree().process_frame
	var d := "/mnt/user-data/uploads/Desktop/TFT Boss/aufnahmen/ocrcheck/"
	var c := m._hcat([Image.load_from_file(d + "level.png"), Image.load_from_file(d + "gold.png")]) as Image
	c.save_png("/tmp/goldx.png")
	var t: String = m.pilot.ocr(["/tmp/goldx.png"])[0]
	print("Text: '", t, "' -> Gold ", OcrRead.gold(OcrRead.after_level(t)))
	get_tree().quit()
