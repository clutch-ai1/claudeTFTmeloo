extends Node
func _ready():
	var m = load("res://main.tscn").instantiate()
	m.pilot = load("res://tests/fakeocr.gd").new()
	add_child(m)
	get_window().size = Vector2i(443, 815)
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/ui.png")
	get_tree().quit()
