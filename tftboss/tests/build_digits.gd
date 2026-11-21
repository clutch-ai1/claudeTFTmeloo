extends Node
const A := "/mnt/user-data/uploads/Desktop/TFT Boss/aufnahmen/"
var S := [
	["/mnt/user-data/uploads/cdf58647-image.png", {"gold": "31", "lvl": "4", "streak": "3", "own": [1788, 668, "84"], "lob": [[198, "100"], [278, "100"], [358, "99"], [438, "96"], [518, "90"], [598, "89"], [768, "82"]]}],
	[A + "20261121_195043_2_2_eigenes.jpg", {"gold": "7", "lvl": "3", "streak": "1", "own": [1788, 668, "95"], "lob": [[198, "105"], [278, "100"], [358, "100"], [438, "100"], [518, "100"], [598, "95"], [768, "95"]]}],
	[A + "20261121_194840_1_4_eigenes.jpg", {"gold": "1", "lvl": "3", "streak": "0"}],
	[A + "20261121_165942_2_6_eigenes.jpg", {"gold": "35", "lvl": "5", "streak": "1", "own": [1788, 426, "92"], "lob": [[198, "100"], [278, "100"], [358, "96"], [529, "90"], [609, "85"], [689, "79"], [769, "78"]]}],
	[A + "20261121_165836_2_5_eigenes.jpg", {"gold": "27", "lvl": "5", "streak": "1", "own": [1788, 426, "92"], "lob": [[198, "100"], [278, "100"], [358, "100"], [529, "91"], [609, "90"], [689, "85"], [769, "84"]]}],
]
func crops(img: Image, spec: Dictionary) -> Array:
	var out := []
	if spec.has("gold"): out.append([img.get_region(Hud.rect(img, Hud.R_GOLD)), spec["gold"]])
	if spec.has("lvl"): out.append([img.get_region(Hud.rect(img, Hud.R_LEVEL)), spec["lvl"]])
	if spec.has("streak"): out.append([img.get_region(Hud.rect(img, Hud.R_STREAK)), spec["streak"]])
	if spec.has("own"): out.append([img.get_region(Rect2i(spec["own"][0], spec["own"][1], 40, 34)), spec["own"][2]])
	for l in spec.get("lob", []):
		out.append([img.get_region(Rect2i(1824, l[0] - 11, 30, 22)), l[1]])
	return out
func _ready():
	var all := []
	for s in S:
		var img := Image.load_from_file(s[0])
		img.convert(Image.FORMAT_RGB8)
		for c in crops(img, s[1]):
			var sigs := Hud.segment(c[0])
			if sigs.size() != str(c[1]).length():
				print("SEGMENT FAIL ", s[0].get_file(), " ", c[1], " got ", sigs.size())
				continue
			for i in sigs.size():
				all.append({"l": str(c[1])[i], "s": sigs[i], "src": s[0].get_file()})
	var cnt := {}
	for e in all: cnt[e["l"]] = cnt.get(e["l"], 0) + 1
	print("Ziffern: ", cnt)
	# Leave-one-image-out
	var h := Hud.new()
	var bad := 0
	var tot := 0
	for s in S:
		h.templates = all.filter(func(e): return e["src"] != s[0].get_file())
		var img := Image.load_from_file(s[0]); img.convert(Image.FORMAT_RGB8)
		for c in crops(img, s[1]):
			tot += 1
			var v := h.read_int(c[0])
			if str(v) != str(c[1]):
				bad += 1
				print("  falsch: ", s[0].get_file(), " soll ", c[1], " ist ", v)
	print("Kreuztest: ", tot - bad, "/", tot)
	var arr := []
	for e in all: arr.append({"l": e["l"], "s": Marshalls.raw_to_base64(e["s"])})
	var f := FileAccess.open("res://data/digits.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(arr)); f.close()
	h = Hud.new()
	h.templates = all
	for s in S:
		var img := Image.load_from_file(s[0]); img.convert(Image.FORMAT_RGB8)
		print(s[0].get_file(), " Gold ", h.gold(img), " Level ", h.level(img), " Streak ", h.streak_num(img), " Lobby ", h.lobby(img).map(func(e): return "%s%d@%d" % ["ICH " if e["own"] else "", e["hp"], e["y"]]))
		print("   Kugeln ", Hud.orbs(img), " Units ", Hud.units(img), " Items ", Hud.item_slots(img).size(), " Infofenster ", Hud.info_panel_open(img))
	get_tree().quit()
