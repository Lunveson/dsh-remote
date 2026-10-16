' ============================================================
'  dsh-link  -  start silently (no window)
'  Double-click this file to start dsh-link in the background.
'  To stop it, double-click: stop-silent.vbs
' ============================================================
Option Explicit
Dim fso, ws, base, ps1
Set fso = CreateObject("Scripting.FileSystemObject")
Set ws  = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = base & "\dsh-link.ps1"
' 0 = hidden window, False = do not wait
ws.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """", 0, False