"""
API Blueprints
"""

from flask import Blueprint

def create_api_blueprint():
    """Create and register all API blueprints"""
    from api.markets import markets_bp
    from api.strategy import strategy_bp
    from api.backtest import backtest_bp
    
    api_bp = Blueprint('api', __name__, url_prefix='/api')
    
    api_bp.register_blueprint(markets_bp)
    api_bp.register_blueprint(strategy_bp)
    api_bp.register_blueprint(backtest_bp)
    
    return api_bp
