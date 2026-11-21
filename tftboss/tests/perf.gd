extends Node
func _ready():
	var v := Vision.new()
	v.forget_all()
	var img := Image.load_from_file("/home/claude/tbtest/cardA.png")
	var s := Vision.norm_sig(img, 16, 12)
	for i in 470:
		var x := s.duplicate(); x[i % s.size()] = (x[i % s.size()] + 50) % 255
		v.db["shop"].append({"l": "U%d" % (i / 5), "s": x})
	var t := Time.get_ticks_usec()
	for k in 5:
		v.cache.clear(); v.read_slot("s%d" % k, "shop", img, 9.0)
	print("5 Shop-Karten mit 470 gelernten Bildern: ", (Time.get_ticks_usec() - t) / 1000, " ms")
	get_tree().quit()
