extends Node
func _ready():
	for t in ["Lvl. 5", "Lvl.5 4/20", "LvI. 7", "Wallis", "Lvl. 10", "4 2-6", "2-1", "• 3 — 2"]:
		print("'", t, "' -> Level ", OcrRead.level(t), "  Stage ", OcrRead.stage(t))
	get_tree().quit()
