"""Simple launcher for the dashboard"""
import sys
import os
from pathlib import Path

# Get the project root directory
script_dir = Path(__file__).parent.resolve()
project_root = script_dir.parent.parent.resolve()

# Add to Python path
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

print("=" * 60)
print("CYBERPUNK POLYMARKET DASHBOARD")
print("=" * 60)
print(f"Project root: {project_root}")
print(f"GUI directory: {script_dir}")
print("=" * 60)
print("\nStarting server...")
print("Open http://localhost:5000 in your browser\n")

# Change to gui directory for Flask templates
os.chdir(script_dir)

# Now import and run the app
try:
    from app import app, socketio
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
except Exception as e:
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()
    input("\nPress Enter to exit...")
