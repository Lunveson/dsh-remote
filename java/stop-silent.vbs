' ============================================================
'  dsh-link  -  stop
'  Double-click this file to stop the background dsh-link.
' ============================================================
Option Explicit
Dim fso, ws, base, ps1
Set fso = CreateObject("Scripting.FileSystemObject")
Set ws  = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = base & "\dsh-link-stop.ps1"
ws.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """", 0, True