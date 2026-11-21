extends Node
func _ready():
	print(OcrRead.lobby("meloo 13 ~40 # Gegner 23 ~95 # Bob 69 ~150"))
	get_tree().quit()
