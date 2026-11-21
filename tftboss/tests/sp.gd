extends Node
func _ready():
	var img := Image.load_from_file("/home/claude/tbtest/fake2.png")
	var whole := img.get_region(Rect2i(60,400,40,240))
	for sr in Calib.split("items", Rect2(Vector2.ZERO, Vector2(whole.get_size()))):
		var s := whole.get_region(Rect2i(sr))
		print(Rect2i(sr), " spread ", snappedf(Vision.spread(s), 0.1))
	get_tree().quit()
