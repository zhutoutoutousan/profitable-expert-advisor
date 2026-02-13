"""
Backtest API Routes
"""

from flask import Blueprint, jsonify, request
from flask_socketio import emit
from datetime import datetime, timedelta
import threading
import time
import numpy as np

backtest_bp = Blueprint('backtest', __name__)

# Global state
backtest_running = False
backtest_results = None
socketio = None  # Will be set by app


def set_socketio(sio):
    """Set SocketIO instance"""
    global socketio
    socketio = sio


@backtest_bp.route('/backtest/run', methods=['POST'])
def run_backtest():
    """Run backtest"""
    global backtest_running, backtest_results
    
    if backtest_running:
        return jsonify({'error': 'Backtest already running'}), 400
    
    try:
        data = request.json
        start_date = data.get('start_date')
        end_date = data.get('end_date')
        initial_balance = float(data.get('initial_balance', 1000.0))
        threshold = float(data.get('threshold', 0.15))
        min_confidence = float(data.get('min_confidence', 0.7))
        
        start = datetime.strptime(start_date, '%Y-%m-%d')
        end = datetime.strptime(end_date, '%Y-%m-%d')
        
        def run_backtest_thread():
            global backtest_running, backtest_results
            backtest_running = True
            
            def log_message(msg, msg_type='info'):
                if socketio:
                    socketio.emit('backtest_log', {
                        'message': msg,
                        'type': msg_type,
                        'timestamp': datetime.now().strftime('%H:%M:%S')
                    })
                time.sleep(0.01)
            
            try:
                log_message(f"Starting backtest from {start.date()} to {end.date()}", 'info')
                log_message(f"Initial Balance: ${initial_balance:.2f}", 'info')
                
                from polymarket.backtesting.engine import BacktestEngine
                from polymarket.strategies.examples import SimpleProbabilityStrategy
                
                strategy = SimpleProbabilityStrategy(
                    initial_balance=initial_balance,
                    threshold=threshold,
                    min_confidence=min_confidence
                )
                
                log_message("Strategy initialized: SimpleProbabilityStrategy", 'success')
                
                engine = BacktestEngine(strategy, start, end, initial_balance)
                
                log_message("Fetching markets...", 'info')
                markets = engine.fetch_historical_markets()
                
                if not markets:
                    log_message("ERROR: No markets found", 'error')
                    raise ValueError("No markets found for backtesting")
                
                log_message(f"Found {len(markets)} markets to backtest", 'success')
                
                # Run backtest (simplified - full implementation in simple_app.py)
                # This is a placeholder - full implementation should be moved here
                log_message("Backtest simulation running...", 'info')
                
                # Emit completion
                if socketio:
                    socketio.emit('backtest_complete', {
                        'total_return': 0.0,
                        'total_trades': 0,
                        'win_rate': 0.0,
                        'sharpe_ratio': 0.0,
                        'max_drawdown': 0.0,
                        'final_equity': initial_balance,
                        'equity_curve': [],
                        'net_profit': 0.0
                    })
                
            except Exception as e:
                import traceback
                error_msg = f"{str(e)}\n{traceback.format_exc()}"
                print(f"Backtest error: {error_msg}")
                if socketio:
                    socketio.emit('backtest_error', {'error': str(e)})
            finally:
                backtest_running = False
        
        thread = threading.Thread(target=run_backtest_thread, daemon=True)
        thread.start()
        
        return jsonify({'status': 'started', 'message': 'Backtest running...'})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@backtest_bp.route('/backtest/status')
def get_backtest_status():
    """Get backtest status"""
    return jsonify({
        'running': backtest_running,
        'results': backtest_results
    })
