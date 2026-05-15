@echo off
echo [1/3] Starting Node.js Bridge...
start "Bridge" cmd /c "cd /d D:\programme\CopilotRemote && npx tsx src/main.ts"
timeout /t 3 /nobreak >nul

echo [2/3] Starting Flutter client...
start "Flutter" cmd /c "cd /d D:\programme\CopilotRemote\flutter_client && flutter run -d chrome --web-port 7780"
timeout /t 8 /nobreak >nul

echo [3/3] Opening browser...
start chrome --new-window http://localhost:7780
echo Done! In Settings, just click Connect.
