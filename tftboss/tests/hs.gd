extends Node
func _ready():
	await get_tree().process_frame
	var b := Brain.new()
	b.stage = "5-2"; b.level = 8; b.gold = 65; b.hp = 13
	b.lobby_hp = [23, 69, 36, 30, 22, 13]
	b.my_traits = {"Heartsteel": 7, "Slayer": 1, "Frontman": 0}
	for shop in [["Kai'Sa", "Bard", "K'Sante", "Graves", "Jax"], ["Gnar", "Draven", "Yunara", "Draven", "Elise"], ["Shyvana", "Renekton", "Syndra", "Graves", "Kayn"]]:
		b.shop = shop
		print("Shop ", shop)
		for a in b.advise(): print("  [", a["k"], "] ", a["t"])
		print("  Ziel: ", b.target.get("name", "?"))
	var hs := []
	for u in Meta.units.keys():
		if "Heartsteel" in Meta.units[u]["t"]: hs.append(u)
	print("Heartsteel-Units: ", hs)
	get_tree().quit()
