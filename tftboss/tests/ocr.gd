extends Node
func _ready():
	await get_tree().process_frame
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ocr_sample.json"))
	print("Stage: ", OcrRead.stage(d["stage"]), "  Gold: ", OcrRead.gold(d["gold"]), "  Level: ", OcrRead.level(d["level"]))
	var shop := []
	for t in d["shop"]: shop.append(OcrRead.match_name(t, Meta.unit_names))
	print("Shop: ", shop)
	var tr := OcrRead.traits(d["traits"], Meta.traits.keys())
	print("Traits: ", tr, "  Stärke: ", OcrRead.trait_power(tr))
	print("Lobby: ", OcrRead.lobby(d["lobby"]))
	get_tree().quit()
