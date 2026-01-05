"""
Example Trading Strategies

These are example implementations of trading strategies that you can use as templates
or modify for your own strategies.
"""

from datetime import datetime
from typing import Dict, Any, Optional
import MetaTrader5 as mt5
from base_strategy import BaseStrategy


class RSIScalpingStrategy(BaseStrategy):
    """
    RSI Scalping Strategy - Example implementation
    
    Entry:
    - Buy when RSI crosses above oversold level
    - Sell when RSI crosses below overbought level
    
    Exit:
    - RSI reaches target levels
    - Stop loss and take profit
    """
    
    def __init__(self, symbol: str, timeframe: int, initial_balance: float = 10000.0,
                 rsi_period: int = 14, rsi_overbought: float = 70, rsi_oversold: float = 30,
                 rsi_target_buy: float = 80, rsi_target_sell: float = 20,
                 lot_size: float = 0.1, stop_loss_pips: int = 50, take_profit_pips: int = 100):
        super().__init__(symbol, timeframe, initial_balance)
        
        self.rsi_period = rsi_period
        self.rsi_overbought = rsi_overbought
        self.rsi_oversold = rsi_oversold
        self.rsi_target_buy = rsi_target_buy
        self.rsi_target_sell = rsi_target_sell
        self.lot_size = lot_size
        self.stop_loss_pips = stop_loss_pips
        self.take_profit_pips = take_profit_pips
        
        # Track previous RSI for crossover detection
        self.prev_rsi = None
    
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        return {
            'rsi': {
                'period': self.rsi_period,
                'applied_price': mt5.PRICE_CLOSE
            }
        }
    
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        rsi = bar_data.get('rsi')
        if rsi is None:
            return
        
        current_price = bar_data['close']
        spread = bar_data.get('spread', 0)
        
        # Check spread
        if spread > self.max_spread:
            return
        
        # Check if we have a position
        if self.position is not None:
            # Check exit conditions
            if self.position['type'] == 'BUY':
                if rsi >= self.rsi_target_buy:
                    self.close_position(current_price)
            elif self.position['type'] == 'SELL':
                if rsi <= self.rsi_target_sell:
                    self.close_position(current_price)
        else:
            # Check entry conditions
            if self.prev_rsi is not None:
                # Buy signal: RSI crosses above oversold
                if self.prev_rsi <= self.rsi_oversold and rsi > self.rsi_oversold:
                    sl = current_price - (self.stop_loss_pips / 10000)
                    tp = current_price + (self.take_profit_pips / 10000)
                    self.open_position('BUY', self.lot_size, current_price, sl, tp, 'RSI Scalping Buy')
                
                # Sell signal: RSI crosses below overbought
                elif self.prev_rsi >= self.rsi_overbought and rsi < self.rsi_overbought:
                    sl = current_price + (self.stop_loss_pips / 10000)
                    tp = current_price - (self.take_profit_pips / 10000)
                    self.open_position('SELL', self.lot_size, current_price, sl, tp, 'RSI Scalping Sell')
        
        self.prev_rsi = rsi
    
    def get_parameters(self) -> Dict[str, Any]:
        return {
            'rsi_period': self.rsi_period,
            'rsi_overbought': self.rsi_overbought,
            'rsi_oversold': self.rsi_oversold,
            'rsi_target_buy': self.rsi_target_buy,
            'rsi_target_sell': self.rsi_target_sell,
            'lot_size': self.lot_size,
            'stop_loss_pips': self.stop_loss_pips,
            'take_profit_pips': self.take_profit_pips
        }


class EMAStrategy(BaseStrategy):
    """
    EMA Crossover Strategy
    
    Entry:
    - Buy when price crosses above EMA
    - Sell when price crosses below EMA
    
    Exit:
    - Opposite crossover
    - Stop loss and take profit
    """
    
    def __init__(self, symbol: str, timeframe: int, initial_balance: float = 10000.0,
                 ema_period: int = 50, lot_size: float = 0.1,
                 stop_loss_pips: int = 50, take_profit_pips: int = 100):
        super().__init__(symbol, timeframe, initial_balance)
        
        self.ema_period = ema_period
        self.lot_size = lot_size
        self.stop_loss_pips = stop_loss_pips
        self.take_profit_pips = take_profit_pips
        
        self.prev_price = None
        self.prev_ema = None
    
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        return {
            'ema': {
                'period': self.ema_period,
                'applied_price': mt5.PRICE_CLOSE
            }
        }
    
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        ema = bar_data.get('ema')
        current_price = bar_data['close']
        
        if ema is None:
            return
        
        # Check if we have a position
        if self.position is not None:
            # Exit on opposite crossover
            if self.position['type'] == 'BUY' and current_price < ema:
                self.close_position(current_price)
            elif self.position['type'] == 'SELL' and current_price > ema:
                self.close_position(current_price)
        else:
            # Check entry conditions
            if self.prev_price is not None and self.prev_ema is not None:
                # Buy signal: price crosses above EMA
                if self.prev_price <= self.prev_ema and current_price > ema:
                    sl = current_price - (self.stop_loss_pips / 10000)
                    tp = current_price + (self.take_profit_pips / 10000)
                    self.open_position('BUY', self.lot_size, current_price, sl, tp, 'EMA Crossover Buy')
                
                # Sell signal: price crosses below EMA
                elif self.prev_price >= self.prev_ema and current_price < ema:
                    sl = current_price + (self.stop_loss_pips / 10000)
                    tp = current_price - (self.take_profit_pips / 10000)
                    self.open_position('SELL', self.lot_size, current_price, sl, tp, 'EMA Crossover Sell')
        
        self.prev_price = current_price
        self.prev_ema = ema
    
    def get_parameters(self) -> Dict[str, Any]:
        return {
            'ema_period': self.ema_period,
            'lot_size': self.lot_size,
            'stop_loss_pips': self.stop_loss_pips,
            'take_profit_pips': self.take_profit_pips
        }


class RSIReversalStrategy(BaseStrategy):
    """
    RSI Reversal Strategy - Similar to your MQL5 RSI Reversal strategies
    
    Entry:
    - Buy when RSI is oversold and starts rising
    - Sell when RSI is overbought and starts falling
    
    Exit:
    - RSI reaches neutral level
    - Stop loss and take profit
    """
    
    def __init__(self, symbol: str, timeframe: int, initial_balance: float = 10000.0,
                 rsi_period: int = 14, rsi_overbought: float = 70, rsi_oversold: float = 30,
                 rsi_exit: float = 50, lot_size: float = 0.1,
                 stop_loss_pips: int = 50, take_profit_pips: int = 100):
        super().__init__(symbol, timeframe, initial_balance)
        
        self.rsi_period = rsi_period
        self.rsi_overbought = rsi_overbought
        self.rsi_oversold = rsi_oversold
        self.rsi_exit = rsi_exit
        self.lot_size = lot_size
        self.stop_loss_pips = stop_loss_pips
        self.take_profit_pips = take_profit_pips
        
        self.prev_rsi = None
    
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        return {
            'rsi': {
                'period': self.rsi_period,
                'applied_price': mt5.PRICE_CLOSE
            }
        }
    
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        rsi = bar_data.get('rsi')
        if rsi is None:
            return
        
        current_price = bar_data['close']
        
        # Check if we have a position
        if self.position is not None:
            # Exit when RSI reaches neutral level
            if self.position['type'] == 'BUY' and rsi >= self.rsi_exit:
                self.close_position(current_price)
            elif self.position['type'] == 'SELL' and rsi <= self.rsi_exit:
                self.close_position(current_price)
        else:
            # Check entry conditions
            if self.prev_rsi is not None:
                # Buy signal: RSI was oversold and now rising
                if self.prev_rsi < self.rsi_oversold and rsi > self.prev_rsi:
                    sl = current_price - (self.stop_loss_pips / 10000)
                    tp = current_price + (self.take_profit_pips / 10000)
                    self.open_position('BUY', self.lot_size, current_price, sl, tp, 'RSI Reversal Buy')
                
                # Sell signal: RSI was overbought and now falling
                elif self.prev_rsi > self.rsi_overbought and rsi < self.prev_rsi:
                    sl = current_price + (self.stop_loss_pips / 10000)
                    tp = current_price - (self.take_profit_pips / 10000)
                    self.open_position('SELL', self.lot_size, current_price, sl, tp, 'RSI Reversal Sell')
        
        self.prev_rsi = rsi
    
    def get_parameters(self) -> Dict[str, Any]:
        return {
            'rsi_period': self.rsi_period,
            'rsi_overbought': self.rsi_overbought,
            'rsi_oversold': self.rsi_oversold,
            'rsi_exit': self.rsi_exit,
            'lot_size': self.lot_size,
            'stop_loss_pips': self.stop_loss_pips,
            'take_profit_pips': self.take_profit_pips
        }
