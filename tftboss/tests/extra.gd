extends Node
func _ready():
	await get_tree().process_frame
	var b := Brain.new()
	b.owned = {"Annie": 3, "Zoe": 2}; b.comps_have = {"Recurve Bow": 1}; b.stage = "2-4"; b.level = 4; b.gold = 20; b.hp = 90
	b.shop = ["", "", "", "", ""]
	for a in b.advise(): print("  2-4: ", a["t"])
	# Augment je nach Plan
	var gold_aug := ""
	var fight_aug := ""
	for n in Meta.aug_names:
		var c: Array = Meta.augs[n]["c"]
		if gold_aug == "" and "Gold" in c and Meta.augs[n]["t"].is_empty(): gold_aug = n
		if fight_aug == "" and "Kampf" in c and Meta.augs[n]["t"].is_empty(): fight_aug = n
	b.stage = "2-1"
	for p in ["win", "loss"]:
		b.plan = p
		print("  Plan ", p, ": ", gold_aug, "=", snappedf(b.aug_score(gold_aug), 0.1), "  ", fight_aug, "=", snappedf(b.aug_score(fight_aug), 0.1))
	get_tree().quit()
