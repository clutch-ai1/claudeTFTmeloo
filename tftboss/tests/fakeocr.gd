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
func ocr_lines(path: String) -> String:
	var out := []
	OS.execute("tesseract", [path, "stdout", "--psm", "6", "tsv"], out)
	var lines := {}
	var order := []
	for row in str(out[0] if out.size() > 0 else "").split("\n", false):
		var c := row.split("\t")
		if c.size() < 12 or c[0] != "5" or c[11].strip_edges() == "":
			continue
		var key := c[2] + "_" + c[3] + "_" + c[4]
		if not lines.has(key):
			lines[key] = {"t": [], "y": int(c[7]) + int(c[9]) / 2}
			order.append(key)
		lines[key]["t"].append(c[11])
	var res := []
	for k in order:
		res.append("%s ~%d" % [" ".join(lines[k]["t"]), lines[k]["y"]])
	return " # ".join(res)
func rclick(p: Vector2i) -> void:
	actions.append("rclick %d,%d" % [p.x, p.y])
func drag(a: Vector2i, b: Vector2i) -> void:
	actions.append("drag %d,%d->%d,%d" % [a.x, a.y, b.x, b.y])
func hover_key(p: Vector2i, vk: int) -> void:
	actions.append("hover %d,%d key %s" % [p.x, p.y, char(vk)])
