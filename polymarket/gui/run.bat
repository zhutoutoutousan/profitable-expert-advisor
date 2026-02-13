@echo off
echo ==========================================
echo 🚀 STARTING CYBERPUNK POLYMARKET DASHBOARD
echo ==========================================
echo.
echo 📦 Installing dependencies...
pip install -r requirements.txt
echo.
echo 🌐 Starting server...
echo 💀 Open http://localhost:5000 in your browser
echo.
python app.py
pause
