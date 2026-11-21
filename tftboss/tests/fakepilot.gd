extends Autopilot
var actions := []
var title := "TFT"
var panic := false
func start() -> bool:
	ok = true
	return true
func state() -> Dictionary:
	var p := panic
	panic = false
	return {"panic": p, "title": title}
func click(p: Vector2i) -> void:
	actions.append("click %d,%d" % [p.x, p.y])
func key(vk: int) -> void:
	actions.append("key " + char(vk))
