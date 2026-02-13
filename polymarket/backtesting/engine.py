"""
Backtesting Engine for Polymarket

Simulates trading on historical market data.
"""

from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
import pandas as pd
import numpy as np

# Configure numpy to handle division by zero gracefully
np.seterr(divide='ignore', invalid='ignore')
from ..strategies.base_strategy import BaseStrategy, MarketSignal, Position
from ..api.gamma_client import GammaClient
from ..api.clob_client import ClobClient
import time


class BacktestEngine:
    """
    Main backtesting engine for Polymarket strategies.
    
    Simulates trading on historical data with realistic execution.
    """
    
    def __init__(self, 
                 strategy: BaseStrategy,
                 start_date: datetime,
                 end_date: datetime,
                 initial_balance: float = 1000.0):
        """
        Initialize backtesting engine.
        
        Args:
            strategy: Strategy instance to backtest
            start_date: Start date for backtesting
            end_date: End date for backtesting
            initial_balance: Starting USDC balance
        """
        self.strategy = strategy
        self.start_date = start_date
        self.end_date = end_date
        self.initial_balance = initial_balance
        
        # Initialize API clients (for data fetching)
        self.gamma_client = GammaClient()
        self.clob_client = ClobClient()
        
        # Backtest state
        self.current_date = start_date
        self.market_snapshots: List[Dict] = []
        self.trades: List[Dict] = []
        
        # Performance tracking
        self.equity_curve: List[Dict] = []
        self.daily_returns: List[float] = []
    
    def fetch_historical_markets(self, tag_id: Optional[int] = None) -> List[Dict]:
        """
        Fetch markets that were active during backtest period.
        
        Note: Polymarket API may not provide full historical data.
        This is a simplified implementation.
        
        Args:
            tag_id: Optional tag ID to filter markets
        
        Returns:
            List of market dictionaries
        """
        # Get current active markets (as proxy for historical)
        # In production, you'd need to store historical snapshots
        events = self.gamma_client.get_events(
            active=True,
            closed=False,
            limit=100,
            tag_id=tag_id
        )
        
        markets = []
        for event in events:
            for market in event.get('markets', []):
                markets.append({
                    'event': event,
                    'market': market,
                    'timestamp': datetime.now()  # Would be historical in real implementation
                })
        
        return markets
    
    def simulate_price_evolution(self, 
                                  initial_price: float,
                                  days: int,
                                  volatility: float = 0.05) -> List[float]:
        """
        Simulate price evolution for backtesting.
        
        In production, use actual historical price data.
        
        Args:
            initial_price: Starting price
            days: Number of days to simulate
            volatility: Daily volatility
        
        Returns:
            List of prices over time
        """
        prices = [initial_price]
        for _ in range(days):
            # Random walk with mean reversion
            change = np.random.normal(0, volatility)
            new_price = prices[-1] + change
            new_price = max(0.01, min(0.99, new_price))  # Bound between 0 and 1
            prices.append(new_price)
        
        return prices
    
    def execute_signal(self, 
                      signal: MarketSignal,
                      market_data: Dict,
                      timestamp: datetime) -> Optional[Dict]:
        """
        Execute a trading signal.
        
        Args:
            signal: Trading signal from strategy
            market_data: Current market data
            timestamp: Current timestamp
        
        Returns:
            Trade dictionary or None if execution failed
        """
        # Get market from market_data first (needed for prices)
        market = market_data.get('market', {})
        
        # Use token_id from signal if available, otherwise get from market
        if signal.token_id:
            token_id = signal.token_id
        else:
            token_ids = market.get('clobTokenIds', [])
            if not token_ids:
                return None
            token_id = token_ids[0]
        
        outcome = 'Yes'  # Default outcome
        
        # Get current price from market data
        import json
        prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
        if signal.action == 'BUY':
            current_price = float(prices[0])  # Yes price
        else:
            current_price = float(prices[0])  # Use Yes price for exit too
        
        # Validate price
        if current_price <= 0 or current_price >= 1:
            return None  # Invalid price
        
        # Calculate position_size based on action
        if signal.action == 'SELL':
            if token_id not in self.strategy.positions:
                return None  # No position to close
            # For SELL, position_size represents the value we'll get back
            pos = self.strategy.positions[token_id]
            # Validate position data
            if not (pos.size > 0 and np.isfinite(pos.size) and 
                    current_price > 0 and current_price < 1 and 
                    np.isfinite(current_price)):
                return None  # Invalid position or price data
            position_size = pos.size * current_price * signal.size  # signal.size = 1.0 for full close
            if not np.isfinite(position_size) or position_size <= 0:
                return None
        else:
            # For BUY, calculate position size and check limits
            # Validate balance
            if not (np.isfinite(self.strategy.current_balance) and self.strategy.current_balance > 0):
                return None
            
            position_size = min(
                signal.size * self.strategy.current_balance,
                self.strategy.current_balance * self.strategy.max_position_size
            )
            
            # Validate position_size
            if not (np.isfinite(position_size) and position_size > 0):
                return None
            
            # Check if can open position
            if not self.strategy.can_open_position(position_size, token_id):
                return None
            
            # Ensure we have enough balance
            if position_size > self.strategy.current_balance:
                return None
        
        # Execute trade
        if signal.action == 'BUY':
            # Buy tokens - safe division
            if current_price > 0 and current_price < 1 and np.isfinite(current_price):
                tokens_bought = position_size / current_price
                # Validate tokens_bought
                if not (np.isfinite(tokens_bought) and tokens_bought > 0):
                    return None
            else:
                return None  # Invalid price, skip trade
            
            # Validate balance before subtraction
            if not (np.isfinite(self.strategy.current_balance) and 
                    self.strategy.current_balance >= position_size):
                return None
            
            self.strategy.current_balance -= position_size
            
            # Ensure balance is still finite
            if not np.isfinite(self.strategy.current_balance):
                self.strategy.current_balance = 0.0
                return None
            
            # Create position
            position = Position(
                token_id=token_id,
                outcome=outcome,
                size=tokens_bought,
                entry_price=current_price,
                entry_time=timestamp,
                current_price=current_price,
                unrealized_pnl=0.0
            )
            self.strategy.positions[token_id] = position
            
        elif signal.action == 'SELL':
            # Close existing position
            if token_id in self.strategy.positions:
                pos = self.strategy.positions[token_id]
                # Validate position data
                if not (np.isfinite(pos.size) and pos.size > 0 and 
                        np.isfinite(pos.entry_price) and pos.entry_price > 0):
                    return None
                
                # Close fraction of position (signal.size = 1.0 means close all)
                close_size = pos.size * signal.size
                if not (np.isfinite(close_size) and close_size > 0):
                    return None
                
                exit_value = close_size * current_price
                entry_cost = close_size * pos.entry_price
                
                # Validate calculations
                if not (np.isfinite(exit_value) and np.isfinite(entry_cost)):
                    return None
                
                pnl = exit_value - entry_cost
                if not np.isfinite(pnl):
                    pnl = 0.0
                
                # Validate balance before addition
                if not np.isfinite(self.strategy.current_balance):
                    self.strategy.current_balance = 0.0
                
                self.strategy.current_balance += exit_value
                
                # Ensure balance is still finite
                if not np.isfinite(self.strategy.current_balance):
                    self.strategy.current_balance = 0.0
                    return None
                
                self.strategy.total_trades += 1
                
                if pnl > 0:
                    self.strategy.winning_trades += 1
                    self.strategy.total_profit += pnl if np.isfinite(pnl) else 0.0
                else:
                    self.strategy.losing_trades += 1
                    self.strategy.total_loss += abs(pnl) if np.isfinite(pnl) else 0.0
                
                # Update or remove position
                if signal.size >= 1.0:
                    # Close entire position
                    pos.realized_pnl = pnl if np.isfinite(pnl) else 0.0
                    self.strategy.closed_positions.append(pos)
                    del self.strategy.positions[token_id]
                else:
                    # Partial close
                    pos.size -= close_size
                    if not (np.isfinite(pos.size) and pos.size >= 0):
                        pos.size = 0.0
                    pos.realized_pnl += pnl if np.isfinite(pnl) else 0.0
                    if not np.isfinite(pos.realized_pnl):
                        pos.realized_pnl = 0.0
        
        trade = {
            'timestamp': timestamp,
            'action': signal.action,
            'token_id': token_id,
            'outcome': outcome,
            'price': current_price,
            'size': position_size,
            'reason': signal.reason,
            'confidence': signal.confidence
        }
        
        self.trades.append(trade)
        return trade
    
    def run(self, markets: Optional[List[Dict]] = None) -> Dict[str, Any]:
        """
        Run the backtest.
        
        Args:
            markets: Optional list of markets to backtest. If None, fetches markets.
        
        Returns:
            Dictionary with backtest results
        """
        print(f"Starting backtest from {self.start_date} to {self.end_date}")
        
        # Fetch markets if not provided
        if markets is None:
            markets = self.fetch_historical_markets()
        
        if not markets:
            raise ValueError("No markets found for backtesting")
        
        print(f"Found {len(markets)} markets to backtest")
        
        # Simulate time progression
        current_date = self.start_date
        day_count = 0
        
        while current_date <= self.end_date:
            # Update positions with current prices
            for token_id, position in self.strategy.positions.items():
                # Simulate price movement
                # In production, use actual historical prices
                price_change = np.random.normal(0, 0.02)
                new_price = max(0.01, min(0.99, position.current_price + price_change))
                self.strategy.update_position(token_id, new_price)
            
            # Process each market
            for market_snapshot in markets:
                market_data = {
                    'event': market_snapshot['event'],
                    'market': market_snapshot['market'],
                    'timestamp': current_date
                }
                
                # Get current prices
                market = market_snapshot['market']
                import json
                outcomes = json.loads(market.get('outcomes', '["Yes", "No"]'))
                prices = json.loads(market.get('outcomePrices', '[0.5, 0.5]'))
                
                market_data['prices'] = {
                    outcome: float(price) 
                    for outcome, price in zip(outcomes, prices)
                }
                
                # Get strategy signal
                signal = self.strategy.analyze_market(market_data)
                
                if signal and signal.confidence >= self.strategy.min_confidence:
                    self.execute_signal(signal, market_data, current_date)
            
            # Update equity curve
            self.strategy.update_drawdown()
            equity = self.strategy.calculate_equity()
            
            self.equity_curve.append({
                'date': current_date,
                'equity': equity,
                'balance': self.strategy.current_balance,
                'unrealized_pnl': sum(pos.unrealized_pnl for pos in self.strategy.positions.values())
            })
            
            # Calculate daily return
            if len(self.equity_curve) > 1:
                prev_equity = self.equity_curve[-2]['equity']
                daily_return = (equity - prev_equity) / prev_equity if prev_equity > 0 else 0.0
                self.daily_returns.append(daily_return)
            
            # Advance to next day
            current_date += timedelta(days=1)
            day_count += 1
            
            if day_count % 10 == 0:
                print(f"Progress: {day_count} days, Equity: ${equity:.2f}")
        
        # Close all open positions at end
        final_equity = self.strategy.calculate_equity()
        for token_id, position in list(self.strategy.positions.items()):
            # Assume final price is entry price (or use last known price)
            exit_value = position.size * position.current_price
            pnl = exit_value - (position.size * position.entry_price)
            
            self.strategy.current_balance += exit_value
            self.strategy.total_trades += 1
            
            if pnl > 0:
                self.strategy.winning_trades += 1
                self.strategy.total_profit += pnl
            else:
                self.strategy.losing_trades += 1
                self.strategy.total_loss += abs(pnl)
            
            del self.strategy.positions[token_id]
        
        # Calculate final metrics with safe division
        if self.initial_balance > 0:
            total_return = (final_equity - self.initial_balance) / self.initial_balance * 100
        else:
            total_return = 0.0
        
        sharpe_ratio = self._calculate_sharpe_ratio()
        
        # Safe win rate calculation
        if self.strategy.total_trades > 0:
            win_rate = (self.strategy.winning_trades / self.strategy.total_trades * 100)
        else:
            win_rate = 0.0
        
        # Safe profit factor calculation
        if abs(self.strategy.total_loss) > 1e-10:
            profit_factor = abs(self.strategy.total_profit / self.strategy.total_loss)
        else:
            profit_factor = 0.0 if abs(self.strategy.total_profit) < 1e-10 else float('inf')
        
        # Ensure all values are finite
        total_return = total_return if np.isfinite(total_return) else 0.0
        win_rate = win_rate if np.isfinite(win_rate) else 0.0
        profit_factor = profit_factor if (np.isfinite(profit_factor) and profit_factor != float('inf')) else 0.0
        sharpe_ratio = sharpe_ratio if np.isfinite(sharpe_ratio) else 0.0
        max_dd = self.strategy.max_drawdown * 100 if np.isfinite(self.strategy.max_drawdown) else 0.0
        
        results = {
            'strategy': self.strategy.name,
            'start_date': self.start_date,
            'end_date': self.end_date,
            'initial_balance': self.initial_balance,
            'final_balance': self.strategy.current_balance,
            'final_equity': final_equity if np.isfinite(final_equity) else self.initial_balance,
            'total_return': total_return,
            'total_trades': self.strategy.total_trades,
            'winning_trades': self.strategy.winning_trades,
            'losing_trades': self.strategy.losing_trades,
            'win_rate': win_rate,
            'total_profit': self.strategy.total_profit if np.isfinite(self.strategy.total_profit) else 0.0,
            'total_loss': self.strategy.total_loss if np.isfinite(self.strategy.total_loss) else 0.0,
            'net_profit': (self.strategy.total_profit + self.strategy.total_loss) if np.isfinite(self.strategy.total_profit + self.strategy.total_loss) else 0.0,
            'profit_factor': profit_factor,
            'max_drawdown': max_dd,
            'sharpe_ratio': sharpe_ratio,
            'trades': self.trades,
            'equity_curve': self.equity_curve
        }
        
        return results
    
    def _calculate_sharpe_ratio(self, risk_free_rate: float = 0.0) -> float:
        """Calculate Sharpe ratio from daily returns"""
        if not self.daily_returns:
            return 0.0
        
        returns = np.array(self.daily_returns)
        if len(returns) == 0:
            return 0.0
        
        excess_returns = returns - (risk_free_rate / 365)  # Daily risk-free rate
        
        std_dev = returns.std()
        if std_dev == 0 or np.isnan(std_dev) or not np.isfinite(std_dev):
            return 0.0
        
        mean_return = excess_returns.mean()
        if not np.isfinite(mean_return):
            return 0.0
        
        sharpe = np.sqrt(365) * mean_return / std_dev
        return sharpe if np.isfinite(sharpe) else 0.0
    
    def generate_report(self, output_file: Optional[str] = None) -> None:
        """Generate backtest report"""
        results = {
            'strategy': self.strategy.name,
            'performance': self.strategy.get_performance_metrics()
        }
        
        print("\n" + "="*60)
        print("BACKTEST RESULTS")
        print("="*60)
        print(f"Strategy: {results['strategy']}")
        print(f"Period: {self.start_date.date()} to {self.end_date.date()}")
        print(f"Initial Balance: ${self.initial_balance:.2f}")
        print(f"Final Equity: ${self.strategy.equity:.2f}")
        print(f"Total Return: {((self.strategy.equity - self.initial_balance) / self.initial_balance * 100):.2f}%")
        print(f"Total Trades: {self.strategy.total_trades}")
        print(f"Win Rate: {(self.strategy.winning_trades / self.strategy.total_trades * 100) if self.strategy.total_trades > 0 else 0:.2f}%")
        print(f"Max Drawdown: {self.strategy.max_drawdown * 100:.2f}%")
        print("="*60)
