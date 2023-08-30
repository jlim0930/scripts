$text = @"
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& {iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/jlim0930/scripts/master/gcp-postinstall.ps1'))}"
"@

Add-Content -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\startup.bat" -Value $text -NoNewline -Force
