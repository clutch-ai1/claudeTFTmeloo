class_name Autopilot
extends RefCounted
## Führt die Tipps selbst aus: Maus und Tastatur über einen kleinen PowerShell-Helfer (Windows).
## Sicherheit: handelt nur, wenn das gemerkte TFT-Fenster vorne ist. F8 schaltet sofort aus.

const HELPER := """
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public static class TB {
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static int Blocked = 0;
  public static string Title() { var sb = new StringBuilder(256); GetWindowText(GetForegroundWindow(), sb, 256); return sb.ToString(); }
  static void Send(INPUT[] a) { uint r = SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(INPUT))); if (r != a.Length) Blocked++; }
  static INPUT M(uint f) { var i = new INPUT(); i.type = 0; i.u.mi.dwFlags = f; return i; }
  static INPUT K(ushort sc, uint f) { var i = new INPUT(); i.type = 1; i.u.ki.wScan = sc; i.u.ki.dwFlags = f | 0x0008; return i; }
  public static void Click(int x, int y, bool right) {
    if (!SetCursorPos(x, y)) Blocked++;
    Thread.Sleep(35);
    Send(new INPUT[] { M(right ? 0x0008u : 0x0002u) }); Thread.Sleep(45); Send(new INPUT[] { M(right ? 0x0010u : 0x0004u) });
  }
  public static void Key(byte vk) {
    ushort sc = (ushort)MapVirtualKey(vk, 0);
    Send(new INPUT[] { K(sc, 0) }); Thread.Sleep(45); Send(new INPUT[] { K(sc, 0x0002) });
  }
}
'@
[TB]::SetProcessDPIAware() | Out-Null
[TB]::GetAsyncKeyState(0x77) | Out-Null
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
while ($true) {
  $l = [Console]::In.ReadLine()
  if ($l -eq $null) { break }
  $p = $l.Split(' ')
  switch ($p[0]) {
    'click'  { [TB]::Click([int]$p[1], [int]$p[2], $false) }
    'rclick' { [TB]::Click([int]$p[1], [int]$p[2], $true) }
    'key'    { [TB]::Key([byte][int]$p[1]) }
    'state'  { [Console]::Out.WriteLine(('{0}|{1}|{2}|{3}' -f ([TB]::GetAsyncKeyState(0x77) -band 1), [TB]::Blocked, [int]$admin, [TB]::Title())); [Console]::Out.Flush() }
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
	var parts := line.split("|", true, 3)
	if parts.size() < 4:
		return {"panic": false, "title": line, "blocked": 0, "admin": true}
	return {"panic": parts[0].strip_edges() == "1", "blocked": int(parts[1]), "admin": parts[2].strip_edges() == "1", "title": parts[3].strip_edges()}

func click(p: Vector2i) -> void:
	_send("click %d %d" % [p.x, p.y])

func key(vk: int) -> void:
	_send("key %d" % vk)

## Startet TFT Boss mit Adminrechten neu (Windows fragt einmal nach)
static func restart_as_admin() -> void:
	var exe := OS.get_executable_path()
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", "Start-Process -FilePath '%s' -Verb RunAs" % exe.replace("'", "''")])
