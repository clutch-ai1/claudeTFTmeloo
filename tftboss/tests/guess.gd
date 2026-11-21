extends Node
func _ready():
	await get_tree().process_frame
	var b := Brain.new()
	b.stage = ""; b.level = 6; b.gold = 63; b.shop = ["", "Jax", "Camille", "Kayn", "Kennen"]
	for a in b.advise(): print("  [", a["k"], "] ", a["t"])
	print("  geschätzte Stage: ", b.stage)
	get_tree().quit()
