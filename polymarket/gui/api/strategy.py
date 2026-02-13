"""
Strategy API Routes
"""

from flask import Blueprint, jsonify, request

strategy_bp = Blueprint('strategy', __name__)

# Global state
is_trading = False
strategy_balance = 1000.0
strategy_equity = 1000.0
strategy_positions = 0
strategy_trades = 0


@strategy_bp.route('/strategy/status')
def get_strategy_status():
    """Get strategy status"""
    return jsonify({
        'active': is_trading,
        'balance': strategy_balance,
        'equity': strategy_equity,
        'positions': strategy_positions,
        'trades': strategy_trades,
        'win_rate': 0,
        'profit': 0,
        'drawdown': 0
    })


@strategy_bp.route('/strategy/positions')
def get_positions():
    """Get positions"""
    return jsonify({'positions': []})


@strategy_bp.route('/strategy/start', methods=['POST'])
def start_strategy():
    """Start trading strategy"""
    global is_trading
    is_trading = True
    return jsonify({'status': 'started'})


@strategy_bp.route('/strategy/stop', methods=['POST'])
def stop_strategy():
    """Stop trading strategy"""
    global is_trading
    is_trading = False
    return jsonify({'status': 'stopped'})
