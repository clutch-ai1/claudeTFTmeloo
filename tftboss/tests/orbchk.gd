extends Node
func _ready():
	var h := Hud.new()
	for f in ["00046_3_7_davor.jpg", "00066_3_7_davor.jpg", "00068_3_7_davor.jpg", "00090_3_7_davor.jpg", "00092_4_1_davor.jpg", "00102_4_1_davor.jpg"]:
		var img := Image.load_from_file("/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_042302/" + f)
		img.convert(Image.FORMAT_RGB8)
		print(f, " gold ", h.gold(img), " lvl ", h.level(img), " lobby ", h.lobby(img).map(func(e): return ("ICH" if e["own"] else "") + str(e["hp"])), " orbs ", Hud.orbs(img), " items ", Hud.item_slots(img).size(), " units ", Hud.units(img))
	get_tree().quit()
