extends Autopilot
## Ersatz-Helfer für Linux: Texterkennung mit tesseract, Klicks werden nur notiert
var actions := []
var title := "TFT"
func start() -> bool:
	ok = true
	return true
func state() -> Dictionary:
	return {"panic": false, "title": title, "blocked": 0, "admin": true}
func ocr_info() -> String:
	return "OK test"
func ocr(paths: Array) -> Array:
	var res := []
	for p in paths:
		var out := []
		OS.execute("tesseract", [p, "stdout", "--psm", "6"], out)
		var lines := []
		for l in str(out[0] if out.size() > 0 else "").split("\n", false):
			if l.strip_edges() != "":
				lines.append(l.strip_edges())
		res.append(" # ".join(lines))
	return res
func click(p: Vector2i) -> void:
	actions.append("click %d,%d" % [p.x, p.y])
func key(vk: int) -> void:
	actions.append("key " + char(vk))
func cursor() -> Vector2i:
	return Vector2i(960, 540)
func move(p: Vector2i) -> void:
	pass
