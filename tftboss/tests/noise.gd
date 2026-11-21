extends Node
func L(p): return Image.load_from_file("/home/claude/tbtest/" + p)
func _ready():
	var v := Vision.new()
	v.forget_all()
	var r = v.read_number("a", L("n34.png"))
	print("n34 roh: ", r["text"], " Teile=", r["glyphs"].size())
	print("lerne 34: '", v.learn_number(r["glyphs"], "34", r["meta"]), "'")
	r = v.read_number("b", L("ns32.png")); print("ns32 Teile=", r["glyphs"].size(), " lerne: '", v.learn_number(r["glyphs"], "3-2", r["meta"]), "'")
	r = v.read_number("c", L("n52.png")); print("n52 vor: ", r["text"]); print(" lerne: '", v.learn_number(r["glyphs"], "52", r["meta"]), "'")
	r = v.read_number("d", L("n7.png")); print("n7 vor: ", r["text"]); print(" lerne: '", v.learn_number(r["glyphs"], "7", r["meta"]), "'")
	r = v.read_number("e", L("ns41.png")); print("ns41 vor: ", r["text"]); v.learn_number(r["glyphs"], "4-1", r["meta"])
	for f in ["n34.png", "n34s.png", "n52.png", "n7.png", "ns32.png", "ns41.png"]:
		var x = v.read_number("z" + f, L(f))
		print("  ", f, " -> '", x["text"], "' ok=", x["ok"])
	get_tree().quit()
