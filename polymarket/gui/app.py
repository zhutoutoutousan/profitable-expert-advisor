"""
Main Flask Application
Componentized version with blueprints
"""

from flask import Flask, render_template
from flask_socketio import SocketIO
from pathlib import Path
import sys
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Setup paths
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))
gui_path = Path(__file__).parent
sys.path.insert(0, str(gui_path))

# Import API blueprints
try:
    from api import create_api_blueprint
    from api.backtest import set_socketio
except ImportError:
    # Fallback for direct execution
    import importlib.util
    api_init_path = gui_path / 'api' / '__init__.py'
    spec = importlib.util.spec_from_file_location("api", api_init_path)
    api_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api_module)
    create_api_blueprint = api_module.create_api_blueprint
    
    backtest_path = gui_path / 'api' / 'backtest.py'
    spec = importlib.util.spec_from_file_location("backtest", backtest_path)
    backtest_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(backtest_module)
    set_socketio = backtest_module.set_socketio

app = Flask(__name__,
            template_folder='templates',
            static_folder='static')
app.config['SECRET_KEY'] = 'cyberpunk-polymarket-secret'

socketio = SocketIO(app, cors_allowed_origins="*")

# Set socketio for backtest routes
set_socketio(socketio)

# Register API blueprints
api_bp = create_api_blueprint()
app.register_blueprint(api_bp)


@app.route('/')
def index():
    """Main dashboard"""
    return render_template('dashboard.html')


@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection"""
    socketio.emit('status', {'message': 'Connected to Cyberpunk Dashboard'})


@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection"""
    pass


if __name__ == '__main__':
    print("=" * 60)
    print("CYBERPUNK POLYMARKET DASHBOARD")
    print("=" * 60)
    print("Starting server on http://localhost:5000")
    print("Press Ctrl+C to stop")
    print("=" * 60)
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
