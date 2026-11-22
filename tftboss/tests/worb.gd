extends Node
func _ready():
	var d := "/mnt/user-data/uploads/Desktop/TFT Boss/bot_spiele/20261122_064133/"
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".jpg"):
			var img := Image.load_from_file(d + f); img.convert(Image.FORMAT_RGB8)
			print(f, " weiß ", Hud.white_orbs(img), " blau ", Hud.orbs(img))
	for f in ["/mnt/user-data/uploads/cdf58647-image.png", "/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_043808/00840_3_3_davor.jpg", "/mnt/user-data/uploads/Desktop/TFT Boss/lernen/20261122_043808/00960_3_6_danach.jpg"]:
		var img := Image.load_from_file(f); img.convert(Image.FORMAT_RGB8)
		print(f.get_file(), " weiß ", Hud.white_orbs(img))
	get_tree().quit()
