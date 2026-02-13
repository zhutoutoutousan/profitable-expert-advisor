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
from indicator_utils import calculate_rsi, calculate_ema, calculate_sma, calculate_atr, calculate_macd


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
        
        # Store required indicators config (we'll calculate them from data)
        self.required_indicators = self.strategy.get_required_indicators()
        
        # Pre-calculate indicators from historical data
        self.indicator_data = {}
        self._precalculate_indicators()
        
    def _precalculate_indicators(self):
        """Pre-calculate all indicators from historical data."""
        # Fetch all historical data first
        rates = mt5.copy_rates_range(
            self.strategy.symbol,
            self.strategy.timeframe,
            self.start_date - timedelta(days=100),  # Extra data for indicator calculation
            self.end_date
        )
        
        if rates is None or len(rates) == 0:
            print("Warning: Could not fetch historical data for indicators")
            return
        
        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)
        
        # Calculate indicators
        for indicator_name, params in self.required_indicators.items():
            if indicator_name.lower() == 'rsi':
                period = params.get('period', 14)
                self.indicator_data['rsi'] = calculate_rsi(df['close'], period)
            elif indicator_name.lower() == 'ema':
                period = params.get('period', 50)
                self.indicator_data['ema'] = calculate_ema(df['close'], period)
            elif indicator_name.lower() == 'sma':
                period = params.get('period', 50)
                self.indicator_data['sma'] = calculate_sma(df['close'], period)
            elif indicator_name.lower() == 'atr':
                period = params.get('period', 14)
                self.indicator_data['atr'] = calculate_atr(df, period)
            elif indicator_name.lower() == 'macd':
                fast = params.get('fast', 12)
                slow = params.get('slow', 26)
                signal = params.get('signal', 9)
                macd_df = calculate_macd(df['close'], fast, slow, signal)
                self.indicator_data['macd'] = macd_df['macd']
                self.indicator_data['macd_signal'] = macd_df['signal']
                self.indicator_data['macd_histogram'] = macd_df['histogram']
    
    def get_indicator_value(self, indicator_name: str, time: datetime) -> Optional[float]:
        """
        Get indicator value for a specific time.
        
        Args:
            indicator_name: Name of the indicator
            time: Bar time
        
        Returns:
            Indicator value or None
        """
        if indicator_name.lower() not in self.indicator_data:
            return None
        
        series = self.indicator_data[indicator_name.lower()]
        if time in series.index:
            value = series.loc[time]
            return float(value) if not pd.isna(value) else None
        
        # Try to find closest time
        try:
            closest_time = series.index[series.index <= time][-1] if len(series.index[series.index <= time]) > 0 else None
            if closest_time:
                value = series.loc[closest_time]
                return float(value) if not pd.isna(value) else None
        except:
            pass
        
        return None
    
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
        for indicator_name in self.required_indicators.keys():
            value = self.get_indicator_value(indicator_name, bar_data['time'])
            if value is not None:
                bar_data['indicators'][indicator_name] = value
                # Also add to top level for convenience
                bar_data[indicator_name.lower()] = value
        
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
        """Clean up MT5 connection."""
        mt5.shutdown()
