extends Node
func _ready():
	var h := Hud.new()
	var d := "/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_043808/"
	for f in DirAccess.get_files_at(d):
		if not f.ends_with(".jpg"): continue
		var img := Image.load_from_file(d + f)
		img.convert(Image.FORMAT_RGB8)
		print(f, " gold ", h.gold(img), " lvl ", h.level(img), " lobby ", h.lobby(img).map(func(e): return ("ICH" if e["own"] else "") + str(e["hp"])), " OWN ", h.own_hp(img), " units b", Hud.units(img)["board"].size(), "/", Hud.units(img)["bench"].size(), " items ", Hud.item_slots(img).size(), " orbs ", Hud.orbs(img).size())
	get_tree().quit()
