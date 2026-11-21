extends Node
func _ready():
	await get_tree().process_frame
	var b := Brain.new()
	b.stage = "2-1"; b.level = 4; b.gold = 8; b.hp = 100
	b.shop = ["Kayn", "Neeko", "Lillia", "Varus", "Nasus"]
	for a in b.advise(): print("  2-1 leeres Board: [", a["k"], "] ", a["t"])
	print("  Plan: '", b.plan, "' ", b.plan_why)
	b.stage = "2-5"; b.level = 4; b.gold = 22; b.owned = {"Neeko": 1, "Lillia": 1}
	b.shop = ["Zoe", "Annie", "Elise", "Gnar", "Kayn"]
	for a in b.advise(): print("  2-5: [", a["k"], "] ", a["t"])
	get_tree().quit()
