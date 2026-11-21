class_name Autopilot
extends RefCounted
## Führt die Tipps selbst aus: Maus und Tastatur über einen kleinen PowerShell-Helfer (Windows).
## Sicherheit: handelt nur, wenn das gemerkte TFT-Fenster vorne ist. F8 schaltet sofort aus.

const HELPER := """
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public static class TB {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Title() { var sb = new StringBuilder(256); GetWindowText(GetForegroundWindow(), sb, 256); return sb.ToString(); }
  public static void Click(int x, int y, bool right) {
    SetCursorPos(x, y); Thread.Sleep(35);
    uint d = right ? 0x0008u : 0x0002u, u = right ? 0x0010u : 0x0004u;
    mouse_event(d, 0, 0, 0, UIntPtr.Zero); Thread.Sleep(45); mouse_event(u, 0, 0, 0, UIntPtr.Zero);
  }
  public static void Key(byte vk) {
    byte sc = (byte)MapVirtualKey(vk, 0);
    keybd_event(vk, sc, 0, UIntPtr.Zero); Thread.Sleep(45); keybd_event(vk, sc, 0x0002, UIntPtr.Zero);
  }
}
'@
[TB]::SetProcessDPIAware() | Out-Null
[TB]::GetAsyncKeyState(0x77) | Out-Null
while ($true) {
  $l = [Console]::In.ReadLine()
  if ($l -eq $null) { break }
  $p = $l.Split(' ')
  switch ($p[0]) {
    'click'  { [TB]::Click([int]$p[1], [int]$p[2], $false) }
    'rclick' { [TB]::Click([int]$p[1], [int]$p[2], $true) }
    'key'    { [TB]::Key([byte][int]$p[1]) }
    'state'  { [Console]::Out.WriteLine(('{0}|{1}' -f ([TB]::GetAsyncKeyState(0x77) -band 1), [TB]::Title())); [Console]::Out.Flush() }
    'quit'   { exit }
  }
}
"""

const VK_D := 0x44
const VK_F := 0x46

var pipe: FileAccess = null
var pid := -1
var ok := false
var error := ""

func start() -> bool:
	if OS.get_name() != "Windows":
		error = "Der Autopilot läuft nur unter Windows."
		return false
	if ok:
		return true
	var path := OS.get_user_data_dir().path_join("eingabe_helfer.ps1")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		error = "Kann den Eingabe-Helfer nicht speichern."
		return false
	f.store_string(HELPER)
	f.close()
	var r := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", path])
	if r.is_empty():
		error = "PowerShell konnte nicht gestartet werden."
		return false
	pipe = r["stdio"]
	pid = int(r["pid"])
	ok = true
	return true

func stop() -> void:
	if ok and pipe:
		pipe.store_line("quit")
		pipe.flush()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	ok = false
	pipe = null
	pid = -1

func _send(cmd: String) -> void:
	if not ok or pipe == null:
		return
	pipe.store_line(cmd)
	pipe.flush()

## Fragt ab: F8 gedrückt? Welches Fenster ist vorne? Ergebnis {"panic": bool, "title": String}
func state() -> Dictionary:
	if not ok or not OS.is_process_running(pid):
		ok = false
		return {"panic": false, "title": "", "dead": true}
	_send("state")
	var line := pipe.get_line()
	var i := line.find("|")
	if i < 0:
		return {"panic": false, "title": line}
	return {"panic": line.substr(0, i).strip_edges() == "1", "title": line.substr(i + 1).strip_edges()}

func click(p: Vector2i) -> void:
	_send("click %d %d" % [p.x, p.y])

func key(vk: int) -> void:
	_send("key %d" % vk)
