"""
Polymarket Automatic Backtesting and Trading Framework

A comprehensive framework for developing, backtesting, and deploying
trading strategies on Polymarket prediction markets.
"""

__version__ = '1.0.0'

from .api import GammaClient, ClobClient, DataClient
from .strategies import BaseStrategy, MarketSignal, Position
from .backtesting.engine import BacktestEngine

__all__ = [
    'GammaClient',
    'ClobClient', 
    'DataClient',
    'BaseStrategy',
    'MarketSignal',
    'Position',
    'BacktestEngine'
]
