Set WshShell = CreateObject("WScript.Shell") 
WshShell.Run "powershell.exe .\scripts\backup.ps1 " & Wscript.Arguments(0) & " " & Wscript.Arguments(1), 0
Set WshShell = Nothing