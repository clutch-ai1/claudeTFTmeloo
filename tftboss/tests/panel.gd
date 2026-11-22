extends Node
func _ready():
	var fp = load("res://tests/fakeocr.gd").new()
	var img := Image.load_from_file("/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_043808/00717_3_1_danach.jpg")
	var W := img.get_width(); var H := img.get_height()
	var c := img.get_region(Rect2i(int(0.872 * W), int(0.05 * H), int(0.125 * W), int(0.36 * H)))
	c.resize(c.get_width() * 2, c.get_height() * 2)
	c.save_png("/tmp/panel.png")
	var t: String = fp.ocr(["/tmp/panel.png"])[0]
	print("Text: ", t.replace("\n", " # "))
	print("Name: ", OcrRead.match_name(t, Meta.unit_names))
	get_tree().quit()
