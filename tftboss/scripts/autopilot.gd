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
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  public static string Cursor() { POINT p; GetCursorPos(out p); return p.X + "," + p.Y; }
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
  public static void Drag(int x1, int y1, int x2, int y2) {
    if (!SetCursorPos(x1, y1)) Blocked++;
    Thread.Sleep(60);
    Send(new INPUT[] { M(0x0002u) }); Thread.Sleep(90);
    for (int i = 1; i <= 12; i++) { SetCursorPos(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12); Thread.Sleep(18); }
    Thread.Sleep(80);
    Send(new INPUT[] { M(0x0004u) });
  }
  public static void Key(byte vk) {
    ushort sc = (ushort)MapVirtualKey(vk, 0);
    Send(new INPUT[] { K(sc, 0) }); Thread.Sleep(45); Send(new INPUT[] { K(sc, 0x0002) });
  }
}
'@
[TB]::SetProcessDPIAware() | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
# ---- Windows-Texterkennung (OCR) ----
$ocrErr = ''
$ocr = $null
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  [void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
  [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
  [void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
  [void][Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
  $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, $type) { $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
  try { $ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US')) } catch { }
  if ($ocr -eq $null) { $ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
  if ($ocr -eq $null) { $ocrErr = 'keine OCR-Sprache installiert' }
} catch { $ocrErr = $_.Exception.Message }
function ReadText($path, $pos = $false) {
  try {
    $path = [System.IO.Path]::GetFullPath($path.Replace('/', '\'))
    # Bild direkt als Datenstrom öffnen (robuster als StorageFile)
    $fs = [System.IO.File]::OpenRead($path)
    $st = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($fs)
    $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bmp = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Await ($ocr.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
    $st.Dispose(); $fs.Dispose()
    if ($pos) { return (($res.Lines | ForEach-Object { $w = $_.Words[0].BoundingRect; '{0} ~{1}' -f $_.Text, [int]($w.Y + $w.Height / 2) }) -join ' # ') }
    return (($res.Lines | ForEach-Object { $_.Text }) -join ' # ')
  } catch {
    $e = $_.Exception
    while ($e.InnerException -ne $null) { $e = $e.InnerException }
    return ('ERR ' + $e.Message)
  }
}
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
    'hoverkey' { [TB]::SetCursorPos([int]$p[1], [int]$p[2]) | Out-Null; Start-Sleep -Milliseconds 150; [TB]::Key([byte][int]$p[3]) }
    'drag'   { [TB]::Drag([int]$p[1], [int]$p[2], [int]$p[3], [int]$p[4]) }
    'state'  { [Console]::Out.WriteLine(('{0}|{1}|{2}|{3}' -f ([TB]::GetAsyncKeyState(0x77) -band 1), [TB]::Blocked, [int]$admin, [TB]::Title())); [Console]::Out.Flush() }
    'move'   { [TB]::SetCursorPos([int]$p[1], [int]$p[2]) | Out-Null }
    'cursor' { [Console]::Out.WriteLine([TB]::Cursor()); [Console]::Out.Flush() }
    'ocrinfo' { if ($ocr -eq $null) { [Console]::Out.WriteLine('ERR ' + $ocrErr) } else { [Console]::Out.WriteLine('OK ' + $ocr.RecognizerLanguage.LanguageTag) }; [Console]::Out.Flush() }
    'ocr'    {
      $paths = $l.Substring(4).Split('|')
      $out = @()
      foreach ($pp in $paths) { if ($ocr -eq $null) { $out += ('ERR ' + $ocrErr) } else { $out += (ReadText $pp) } }
      [Console]::Out.WriteLine(($out -join ' @@ ')); [Console]::Out.Flush()
    }
    'ocrl'   { if ($ocr -eq $null) { [Console]::Out.WriteLine('ERR ' + $ocrErr) } else { [Console]::Out.WriteLine((ReadText $l.Substring(5) $true)) }; [Console]::Out.Flush() }
    'quit'   { exit }
  }
}
"""

const VK_D := 0x44
const VK_F := 0x46
const VK_E := 0x45

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

func rclick(p: Vector2i) -> void:
	_send("rclick %d %d" % [p.x, p.y])

func hover_key(p: Vector2i, vk: int) -> void:
	_send("hoverkey %d %d %d" % [p.x, p.y, vk])

func drag(a: Vector2i, b: Vector2i) -> void:
	_send("drag %d %d %d %d" % [a.x, a.y, b.x, b.y])

func key(vk: int) -> void:
	_send("key %d" % vk)

## Startet TFT Boss mit Adminrechten neu (Windows fragt einmal nach)
static func restart_as_admin() -> void:
	var exe := OS.get_executable_path()
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", "Start-Process -FilePath '%s' -Verb RunAs" % exe.replace("'", "''")])

func _ask_line(cmd: String) -> String:
	if not ok or not OS.is_process_running(pid):
		ok = false
		return ""
	_send(cmd)
	return pipe.get_line()

## Ergebnis: "OK en-US" oder "ERR ..."
func ocr_info() -> String:
	return _ask_line("ocrinfo")

## Liest Text aus mehreren Bilddateien. Eine Zeile pro Datei, Zeilen im Bild mit " # " getrennt.
func ocr(paths: Array) -> Array:
	var line := _ask_line("ocr " + "|".join(paths))
	if line == "":
		return []
	return Array(line.split(" @@ "))

## Wie ocr(), aber jede Zeile endet mit " ~Y" (Mitte der Zeile im Bild, in Pixeln)
func ocr_lines(path: String) -> String:
	return _ask_line("ocrl " + path)

func cursor() -> Vector2i:
	var l := _ask_line("cursor")
	var p := l.split(",")
	if p.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(p[0]), int(p[1]))

func move(p: Vector2i) -> void:
	_send("move %d %d" % [p.x, p.y])
