"""
Base Strategy Class for MetaTrader5 Backtesting

This module provides a base class that all trading strategies should inherit from.
Implement your trading logic by overriding the on_bar() method.
"""

from abc import ABC, abstractmethod
from datetime import datetime
from typing import Optional, Dict, Any
import MetaTrader5 as mt5


class BaseStrategy(ABC):
    """
    Base class for all trading strategies.
    
    Inherit from this class and implement:
    - on_bar(): Your trading logic for each bar
    - get_parameters(): Return strategy parameters
    """
    
    def __init__(self, symbol: str, timeframe: int, initial_balance: float = 10000.0):
        """
        Initialize the strategy.
        
        Args:
            symbol: Trading symbol (e.g., 'XAUUSD', 'EURUSD')
            timeframe: MT5 timeframe constant (e.g., mt5.TIMEFRAME_H1)
            initial_balance: Starting account balance
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.initial_balance = initial_balance
        self.current_balance = initial_balance
        self.equity = initial_balance
        
        # Position tracking
        self.position = None  # {'type': 'BUY'/'SELL', 'volume': float, 'open_price': float, 'open_time': datetime}
        self.trades = []
        self.closed_trades = []
        
        # Performance metrics
        self.max_drawdown = 0.0
        self.peak_equity = initial_balance
        self.total_profit = 0.0
        self.total_loss = 0.0
        self.winning_trades = 0
        self.losing_trades = 0
        
        # Risk management
        self.max_lot_size = 0.1
        self.min_lot_size = 0.01
        self.max_spread = 1000  # in points
        self.max_drawdown_percent = 0.2  # 20% max drawdown
        
    @abstractmethod
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        """
        Called on each new bar. Implement your trading logic here.
        
        Args:
            bar_data: Dictionary containing:
                - 'time': datetime of the bar
                - 'open': float opening price
                - 'high': float high price
                - 'low': float low price
                - 'close': float closing price
                - 'tick_volume': int tick volume
                - 'spread': int spread in points
                - 'rsi': Optional[float] RSI value if requested
                - 'ema': Optional[float] EMA value if requested
                - 'indicators': Dict with any other requested indicators
        """
        pass
    
    @abstractmethod
    def get_parameters(self) -> Dict[str, Any]:
        """
        Return strategy parameters for logging/reporting.
        
        Returns:
            Dictionary of parameter names and values
        """
        pass
    
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        """
        Specify which indicators are needed by the strategy.
        
        Returns:
            Dictionary mapping indicator names to their parameters.
            Example: {
                'rsi': {'period': 14, 'applied_price': mt5.PRICE_CLOSE},
                'ema': {'period': 50, 'applied_price': mt5.PRICE_CLOSE}
            }
        """
        return {}
    
    def open_position(self, order_type: str, volume: float, price: float, 
                     sl: Optional[float] = None, tp: Optional[float] = None,
                     comment: str = "") -> bool:
        """
        Open a trading position.
        
        Args:
            order_type: 'BUY' or 'SELL'
            volume: Lot size
            price: Entry price
            sl: Stop loss price (optional)
            tp: Take profit price (optional)
            comment: Trade comment
        
        Returns:
            True if position opened successfully
        """
        if self.position is not None:
            return False  # Position already open
        
        # Validate volume
        volume = max(self.min_lot_size, min(volume, self.max_lot_size))
        
        # Calculate margin requirement
        # For XAUUSD (Gold): 1 lot = 100 oz, typical margin 1-2% of contract value
        # For Forex pairs: 1 lot = 100,000 units, typical margin 1-2%
        if 'XAU' in self.symbol or 'GOLD' in self.symbol:
            contract_size = 100  # 1 lot = 100 oz for gold
            margin_percent = 0.02  # 2% margin for gold (more volatile)
        else:
            contract_size = 100000  # Standard forex lot size
            margin_percent = 0.01  # 1% margin for forex
        
        margin_required = volume * contract_size * price * margin_percent
        
        if margin_required > self.equity * 0.9:  # Don't use more than 90% of equity
            return False
        
        self.position = {
            'type': order_type,
            'volume': volume,
            'open_price': price,
            'open_time': datetime.now(),
            'sl': sl,
            'tp': tp,
            'comment': comment
        }
        
        return True
    
    def close_position(self, close_price: float) -> Optional[Dict[str, Any]]:
        """
        Close the current position.
        
        Args:
            close_price: Price at which to close
        
        Returns:
            Trade result dictionary or None if no position
        """
        if self.position is None:
            return None
        
        # Calculate profit/loss
        if self.position['type'] == 'BUY':
            pips = (close_price - self.position['open_price']) * 10000  # For 5-digit brokers
            profit = pips * self.position['volume'] * 10  # Simplified P&L calculation
        else:  # SELL
            pips = (self.position['open_price'] - close_price) * 10000
            profit = pips * self.position['volume'] * 10
        
        trade_result = {
            'type': self.position['type'],
            'volume': self.position['volume'],
            'open_price': self.position['open_price'],
            'close_price': close_price,
            'open_time': self.position['open_time'],
            'close_time': datetime.now(),
            'profit': profit,
            'pips': pips,
            'comment': self.position.get('comment', '')
        }
        
        # Update balance and metrics
        self.current_balance += profit
        self.equity = self.current_balance
        
        if profit > 0:
            self.winning_trades += 1
            self.total_profit += profit
        else:
            self.losing_trades += 1
            self.total_loss += abs(profit)
        
        # Update drawdown
        if self.equity > self.peak_equity:
            self.peak_equity = self.equity
        
        drawdown = (self.peak_equity - self.equity) / self.peak_equity
        if drawdown > self.max_drawdown:
            self.max_drawdown = drawdown
        
        self.closed_trades.append(trade_result)
        self.position = None
        
        return trade_result
    
    def check_stop_loss_take_profit(self, current_price: float) -> bool:
        """
        Check if stop loss or take profit should be triggered.
        
        Args:
            current_price: Current market price
        
        Returns:
            True if position was closed
        """
        if self.position is None:
            return False
        
        should_close = False
        
        if self.position['type'] == 'BUY':
            if self.position.get('sl') and current_price <= self.position['sl']:
                should_close = True
            if self.position.get('tp') and current_price >= self.position['tp']:
                should_close = True
        else:  # SELL
            if self.position.get('sl') and current_price >= self.position['sl']:
                should_close = True
            if self.position.get('tp') and current_price <= self.position['tp']:
                should_close = True
        
        if should_close:
            self.close_position(current_price)
            return True
        
        return False
    
    def get_performance_metrics(self) -> Dict[str, Any]:
        """
        Calculate and return performance metrics.
        
        Returns:
            Dictionary with performance statistics
        """
        total_trades = len(self.closed_trades)
        win_rate = (self.winning_trades / total_trades * 100) if total_trades > 0 else 0
        
        avg_win = (self.total_profit / self.winning_trades) if self.winning_trades > 0 else 0
        avg_loss = (self.total_loss / self.losing_trades) if self.losing_trades > 0 else 0
        profit_factor = (self.total_profit / self.total_loss) if self.total_loss > 0 else 0
        
        total_return = ((self.equity - self.initial_balance) / self.initial_balance) * 100
        
        return {
            'initial_balance': self.initial_balance,
            'final_balance': self.equity,
            'total_return_pct': total_return,
            'total_trades': total_trades,
            'winning_trades': self.winning_trades,
            'losing_trades': self.losing_trades,
            'win_rate_pct': win_rate,
            'total_profit': self.total_profit,
            'total_loss': self.total_loss,
            'profit_factor': profit_factor,
            'avg_win': avg_win,
            'avg_loss': avg_loss,
            'max_drawdown_pct': self.max_drawdown * 100,
            'parameters': self.get_parameters()
        }
