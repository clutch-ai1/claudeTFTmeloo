extends Node
func show(b, title):
	print("== ", title, " | Ziel: ", b.target.get("name","-"), " (", Brain.style_de(b.target) if not b.target.is_empty() else "", ") locked=", b.locked)
	for a in b.advise(): print("   [", a["k"], "] ", a["t"])
func _ready():
	await get_tree().process_frame
	var M = Meta
	print("comps ", M.comps.size(), " units ", M.units.size())
	var b := Brain.new()
	b.stage = "2-1"; b.level = 4; b.gold = 12
	b.shop = ["Annie", "Zoe", "Elise", "Gnar", Vision.EMPTY]
	b.owned = {"Annie": 1, "Zoe": 1, "Taric": 1}
	b.comps_have = {"Recurve Bow": 1, "Needlessly Large Rod": 1}
	show(b, "2-1 früh")
	b.aug_offer = ["Investment Strategy II", "Arcanist Circlet", M.aug_names[100]]
	show(b, "2-1 Augmentwahl")
	b.aug_offer = []
	b.stage = "3-2"; b.level = 6; b.gold = 34
	b.owned = {"Annie": 2, "Zoe": 2, "Renekton": 1, "Graves": 1, "Zac": 1}
	b.shop = ["Graves", "Aurora", "Gnar", "Elise", "Taliyah"]
	show(b, "3-2 mid")
	b.stage = "4-2"; b.level = 8; b.gold = 58
	show(b, "4-2 Lvl 8")
	b.reset(); b.stage = "3-2"; b.level = 5; b.gold = 56
	b.owned = {"Kobuko": 3, "Ziggs": 2, "Teemo": 2, "Lulu": 1}
	b.shop = ["Kobuko", "Ziggs", "Lulu", "Teemo", "Elise"]
	show(b, "Reroll-Szenario")
	get_tree().quit()
