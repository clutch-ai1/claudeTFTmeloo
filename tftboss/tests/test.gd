extends SceneTree
func L(p): return Image.load_from_file("/home/claude/tbtest/" + p)
func _init():
	var v := Vision.new()
	v.db = {"shop": [], "aug": [], "glyph": []}
	# Zahlen lernen
	var r = v.read_number(L("g34.png")); print("g34 first ", r["text"], " ok=", r["ok"], " n=", r["glyphs"].size())
	print("learn34 ", v.learn_number(r["glyphs"], "34"))
	r = v.read_number(L("s32.png")); print("s32 ", r["text"], " n=", r["glyphs"].size()); print("learn ", v.learn_number(r["glyphs"], "3-2"))
	r = v.read_number(L("g52.png")); print("g52 ", r["text"]); v.learn_number(r["glyphs"], "52")
	r = v.read_number(L("s41.png")); print("s41 ", r["text"]); v.learn_number(r["glyphs"], "4-1")
	r = v.read_number(L("l7.png")); print("l7 ", r["text"]); v.learn_number(r["glyphs"], "7")
	r = v.read_number(L("g10.png")); print("g10 ", r["text"]); v.learn_number(r["glyphs"], "10")
	for f in ["g34.png","s32.png","g52.png","s41.png","l7.png","g10.png"]:
		print("re ", f, " -> ", v.read_number(L(f))["text"])
	# Karten
	for n in ["A","B","C"]:
		var c = v.read_card("shop", L("card%s.png" % n), 9.0)
		v.learn("shop", c["s"], "Unit" + n)
	for n in ["A","B","C"]:
		var c = v.read_card("shop", L("card%s_dark.png" % n), 9.0)
		print("dark ", n, " -> ", c["l"], " d=", snappedf(c["d"], 0.1))
	print("empty -> ", v.read_card("shop", L("empty.png"), 9.0)["l"])
	quit()
