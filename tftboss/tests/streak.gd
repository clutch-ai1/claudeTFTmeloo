extends Node
func step(b, st, lv, g, hp, res=""):
	if res != "": b.results.append(res)
	b.stage = st; b.level = lv; b.gold = g; b.hp = hp
	var adv = b.advise()
	var lines = []
	for a in adv:
		if a["k"] in ["level", "roll", "info"]: lines.append("[" + a["k"] + "] " + a["t"])
	print("  ", st, " Lv", lv, " ", g, "G ", hp, "HP ", "".join(b.results), " -> Plan=", b.plan, " | ", " / ".join(lines))
func _ready():
	await get_tree().process_frame
	print("== Starkes Board")
	var b := Brain.new()
	b.owned = {"Annie": 3, "Zoe": 2, "Renekton": 2, "Taric": 1}; b.comps_have = {"Recurve Bow": 1, "Sparring Gloves": 1, "B.F. Sword": 1}
	b.shop = ["", "", "", "", ""]
	step(b, "2-1", 3, 14, 96); step(b, "2-2", 4, 12, 96, "W"); step(b, "2-3", 4, 16, 96, "W"); step(b, "2-5", 4, 24, 96, "W"); step(b, "3-2", 5, 30, 90, "W")
	print("== Schwaches Board")
	b = Brain.new(); b.owned = {"Elise": 1, "Gnar": 1, "Lulu": 1}; b.comps_have = {"Tear Of The Goddess": 1}; b.my_augs = ["Investment Strategy II"]
	step(b, "2-1", 3, 14, 96); step(b, "2-2", 3, 16, 92, "L"); step(b, "2-5", 3, 28, 84, "L"); step(b, "3-1", 3, 44, 70, "L"); step(b, "3-2", 3, 58, 62, "L"); step(b, "3-3", 6, 30, 58, "L")
	print("== Winstreak kippt")
	b = Brain.new(); b.owned = {"Annie": 3, "Zoe": 2, "Renekton": 2}; b.comps_have = {"Recurve Bow": 2, "Sparring Gloves": 1}
	step(b, "2-1", 3, 14, 100); step(b, "2-2", 4, 8, 94, "L"); step(b, "2-3", 4, 12, 88, "L"); step(b, "2-5", 4, 22, 80, "L")
	print("== Wenig Leben spät")
	b = Brain.new(); b.owned = {"Graves": 1, "Zac": 2}
	step(b, "4-2", 8, 52, 36, "L"); step(b, "4-5", 8, 40, 18, "L")
	get_tree().quit()
