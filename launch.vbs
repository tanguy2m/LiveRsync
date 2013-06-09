Set WshShell = CreateObject("WScript.Shell") 
WshShell.Run "powershell.exe .\scripts\main.ps1", 0
Set WshShell = Nothing