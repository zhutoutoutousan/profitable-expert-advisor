"""
Backtesting Engine for MetaTrader5

This module provides the core backtesting functionality using MT5 historical data.
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from base_strategy import BaseStrategy


class BacktestEngine:
    """
    Main backtesting engine that runs strategies on historical data.
    """
    
    def __init__(self, strategy: BaseStrategy, start_date: datetime, end_date: datetime):
        """
        Initialize the backtesting engine.
        
        Args:
            strategy: Strategy instance to backtest
            start_date: Start date for backtesting
            end_date: End date for backtesting
        """
        self.strategy = strategy
        self.start_date = start_date
        self.end_date = end_date
        
        # Initialize MT5 connection
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialization failed: {mt5.last_error()}")
        
        # Indicator handles
        self.indicator_handles = {}
        self.setup_indicators()
        
    def setup_indicators(self):
        """Setup all required indicators for the strategy."""
        required_indicators = self.strategy.get_required_indicators()
        
        for indicator_name, params in required_indicators.items():
            handle = None
            
            if indicator_name.lower() == 'rsi':
                handle = mt5.iRSI(
                    self.strategy.symbol,
                    self.strategy.timeframe,
                    params.get('period', 14),
                    params.get('applied_price', mt5.PRICE_CLOSE)
                )
            elif indicator_name.lower() == 'ema':
                handle = mt5.iMA(
                    self.strategy.symbol,
                    self.strategy.timeframe,
                    params.get('period', 50),
                    0,  # shift
                    mt5.MODE_EMA,
                    params.get('applied_price', mt5.PRICE_CLOSE)
                )
            elif indicator_name.lower() == 'sma':
                handle = mt5.iMA(
                    self.strategy.symbol,
                    self.strategy.timeframe,
                    params.get('period', 50),
                    0,  # shift
                    mt5.MODE_SMA,
                    params.get('applied_price', mt5.PRICE_CLOSE)
                )
            elif indicator_name.lower() == 'atr':
                handle = mt5.iATR(
                    self.strategy.symbol,
                    self.strategy.timeframe,
                    params.get('period', 14)
                )
            elif indicator_name.lower() == 'macd':
                handle = mt5.iMACD(
                    self.strategy.symbol,
                    self.strategy.timeframe,
                    params.get('fast', 12),
                    params.get('slow', 26),
                    params.get('signal', 9),
                    params.get('applied_price', mt5.PRICE_CLOSE)
                )
            
            if handle is not None and handle != mt5.INVALID_HANDLE:
                self.indicator_handles[indicator_name] = handle
            else:
                print(f"Warning: Failed to create {indicator_name} indicator")
    
    def get_indicator_values(self, indicator_name: str, count: int = 1) -> Optional[np.ndarray]:
        """
        Get indicator values.
        
        Args:
            indicator_name: Name of the indicator
            count: Number of values to retrieve
        
        Returns:
            Array of indicator values or None
        """
        if indicator_name not in self.indicator_handles:
            return None
        
        handle = self.indicator_handles[indicator_name]
        buffer = np.zeros(count, dtype=float)
        
        if indicator_name.lower() == 'macd':
            # MACD returns 3 buffers
            result = mt5.copy_buffer(handle, 0, 0, count)  # Main line
            if result is None:
                return None
            return np.array(result)
        else:
            result = mt5.copy_buffer(handle, 0, 0, count)
            if result is None:
                return None
            return np.array(result)
    
    def get_bar_data(self, time: datetime) -> Optional[Dict[str, Any]]:
        """
        Get bar data and indicator values for a specific time.
        
        Args:
            time: Bar time
        
        Returns:
            Dictionary with bar data and indicators
        """
        # Get rates
        rates = mt5.copy_rates_from(
            self.strategy.symbol,
            self.strategy.timeframe,
            time,
            1
        )
        
        if rates is None or len(rates) == 0:
            return None
        
        rate = rates[0]
        
        # Get spread
        symbol_info = mt5.symbol_info(self.strategy.symbol)
        spread = symbol_info.spread if symbol_info else 0
        
        # Build bar data
        bar_data = {
            'time': datetime.fromtimestamp(rate['time']),
            'open': float(rate['open']),
            'high': float(rate['high']),
            'low': float(rate['low']),
            'close': float(rate['close']),
            'tick_volume': int(rate['tick_volume']),
            'spread': spread,
            'indicators': {}
        }
        
        # Get indicator values
        for indicator_name in self.indicator_handles.keys():
            values = self.get_indicator_values(indicator_name, 2)
            if values is not None and len(values) >= 1:
                bar_data['indicators'][indicator_name] = values[0]
                # Also add to top level for convenience
                bar_data[indicator_name.lower()] = values[0]
        
        return bar_data
    
    def run(self) -> Dict[str, Any]:
        """
        Run the backtest.
        
        Returns:
            Dictionary with backtest results and performance metrics
        """
        print(f"Starting backtest from {self.start_date} to {self.end_date}")
        print(f"Symbol: {self.strategy.symbol}, Timeframe: {self.strategy.timeframe}")
        
        # Get all bars in the date range
        rates = mt5.copy_rates_range(
            self.strategy.symbol,
            self.strategy.timeframe,
            self.start_date,
            self.end_date
        )
        
        if rates is None or len(rates) == 0:
            raise ValueError(f"No data available for {self.strategy.symbol} in the specified date range")
        
        print(f"Processing {len(rates)} bars...")
        
        # Process each bar
        processed_bars = 0
        for i, rate in enumerate(rates):
            bar_time = datetime.fromtimestamp(rate['time'])
            
            # Get full bar data with indicators
            bar_data = self.get_bar_data(bar_time)
            if bar_data is None:
                continue
            
            # Check stop loss/take profit on current position
            if self.strategy.position is not None:
                self.strategy.check_stop_loss_take_profit(bar_data['close'])
            
            # Call strategy on_bar method
            try:
                self.strategy.on_bar(bar_data)
            except Exception as e:
                print(f"Error in strategy on_bar at {bar_time}: {e}")
                continue
            
            # Update equity (unrealized P&L)
            if self.strategy.position is not None:
                if self.strategy.position['type'] == 'BUY':
                    unrealized_pnl = (bar_data['close'] - self.strategy.position['open_price']) * \
                                    self.strategy.position['volume'] * 10000 * 10
                else:
                    unrealized_pnl = (self.strategy.position['open_price'] - bar_data['close']) * \
                                    self.strategy.position['volume'] * 10000 * 10
                self.strategy.equity = self.strategy.current_balance + unrealized_pnl
            else:
                self.strategy.equity = self.strategy.current_balance
            
            processed_bars += 1
            
            if processed_bars % 100 == 0:
                print(f"Processed {processed_bars}/{len(rates)} bars...")
        
        # Close any open position at the end
        if self.strategy.position is not None:
            last_bar = rates[-1]
            last_price = float(last_bar['close'])
            self.strategy.close_position(last_price)
        
        print(f"Backtest completed. Processed {processed_bars} bars.")
        
        # Get performance metrics
        metrics = self.strategy.get_performance_metrics()
        
        # Cleanup
        self.cleanup()
        
        return {
            'metrics': metrics,
            'trades': self.strategy.closed_trades,
            'strategy_name': self.strategy.__class__.__name__
        }
    
    def cleanup(self):
        """Clean up indicator handles and MT5 connection."""
        for handle in self.indicator_handles.values():
            mt5.indicator_release(handle)
        mt5.shutdown()
