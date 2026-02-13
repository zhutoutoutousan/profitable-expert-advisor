"""
Performance Metrics and Analytics

Calculates various performance metrics for strategies.
"""

from typing import Dict, List
import numpy as np
import pandas as pd


class PerformanceMetrics:
    """Calculate performance metrics from backtest results"""
    
    @staticmethod
    def calculate_sharpe_ratio(returns: List[float], risk_free_rate: float = 0.0) -> float:
        """
        Calculate Sharpe ratio.
        
        Args:
            returns: List of daily returns
            risk_free_rate: Annual risk-free rate
        
        Returns:
            Sharpe ratio
        """
        if not returns:
            return 0.0
        
        returns_array = np.array(returns)
        excess_returns = returns_array - (risk_free_rate / 365)
        
        if returns_array.std() == 0:
            return 0.0
        
        sharpe = np.sqrt(365) * excess_returns.mean() / returns_array.std()
        return sharpe
    
    @staticmethod
    def calculate_sortino_ratio(returns: List[float], risk_free_rate: float = 0.0) -> float:
        """
        Calculate Sortino ratio (downside deviation only).
        
        Args:
            returns: List of daily returns
            risk_free_rate: Annual risk-free rate
        
        Returns:
            Sortino ratio
        """
        if not returns:
            return 0.0
        
        returns_array = np.array(returns)
        excess_returns = returns_array - (risk_free_rate / 365)
        
        # Calculate downside deviation
        downside_returns = excess_returns[excess_returns < 0]
        if len(downside_returns) == 0:
            return 0.0
        
        downside_std = np.std(downside_returns)
        if downside_std == 0:
            return 0.0
        
        sortino = np.sqrt(365) * excess_returns.mean() / downside_std
        return sortino
    
    @staticmethod
    def calculate_max_drawdown(equity_curve: List[float]) -> Dict[str, float]:
        """
        Calculate maximum drawdown.
        
        Args:
            equity_curve: List of equity values over time
        
        Returns:
            Dictionary with max_drawdown, max_drawdown_percent, and drawdown_duration
        """
        if not equity_curve:
            return {'max_drawdown': 0.0, 'max_drawdown_percent': 0.0, 'drawdown_duration': 0}
        
        equity_array = np.array(equity_curve)
        peak = np.maximum.accumulate(equity_array)
        drawdown = peak - equity_array
        drawdown_percent = (drawdown / peak) * 100
        
        max_dd = float(np.max(drawdown))
        max_dd_percent = float(np.max(drawdown_percent))
        
        # Calculate drawdown duration
        in_drawdown = drawdown > 0
        if np.any(in_drawdown):
            # Count consecutive periods in drawdown
            durations = []
            current_duration = 0
            for in_dd in in_drawdown:
                if in_dd:
                    current_duration += 1
                else:
                    if current_duration > 0:
                        durations.append(current_duration)
                    current_duration = 0
            if current_duration > 0:
                durations.append(current_duration)
            
            max_duration = max(durations) if durations else 0
        else:
            max_duration = 0
        
        return {
            'max_drawdown': max_dd,
            'max_drawdown_percent': max_dd_percent,
            'drawdown_duration': max_duration
        }
    
    @staticmethod
    def calculate_calmar_ratio(total_return: float, max_drawdown_percent: float) -> float:
        """
        Calculate Calmar ratio (return / max drawdown).
        
        Args:
            total_return: Total return percentage
            max_drawdown_percent: Maximum drawdown percentage
        
        Returns:
            Calmar ratio
        """
        if max_drawdown_percent == 0:
            return 0.0
        return total_return / max_drawdown_percent
    
    @staticmethod
    def calculate_profit_factor(total_profit: float, total_loss: float) -> float:
        """
        Calculate profit factor.
        
        Args:
            total_profit: Total profit
            total_loss: Total loss (absolute value)
        
        Returns:
            Profit factor
        """
        if total_loss == 0:
            return 0.0 if total_profit == 0 else float('inf')
        return abs(total_profit / total_loss)
    
    @staticmethod
    def calculate_expectancy(win_rate: float, avg_win: float, avg_loss: float) -> float:
        """
        Calculate expectancy per trade.
        
        Args:
            win_rate: Win rate (0-1)
            avg_win: Average winning trade
            avg_loss: Average losing trade (absolute value)
        
        Returns:
            Expectancy
        """
        return (win_rate * avg_win) - ((1 - win_rate) * avg_loss)
    
    @staticmethod
    def generate_report(backtest_results: Dict) -> str:
        """
        Generate formatted performance report.
        
        Args:
            backtest_results: Results dictionary from backtest
        
        Returns:
            Formatted report string
        """
        equity_curve = [point['equity'] for point in backtest_results.get('equity_curve', [])]
        daily_returns = backtest_results.get('daily_returns', [])
        
        # Calculate additional metrics
        sharpe = PerformanceMetrics.calculate_sharpe_ratio(daily_returns)
        sortino = PerformanceMetrics.calculate_sortino_ratio(daily_returns)
        dd_metrics = PerformanceMetrics.calculate_max_drawdown(equity_curve)
        
        report = f"""
{'='*70}
POLYMARKET BACKTEST REPORT
{'='*70}

Strategy: {backtest_results.get('strategy', 'Unknown')}
Period: {backtest_results.get('start_date')} to {backtest_results.get('end_date')}

INITIAL METRICS:
  Initial Balance: ${backtest_results.get('initial_balance', 0):,.2f}
  Final Equity: ${backtest_results.get('final_equity', 0):,.2f}
  Total Return: {backtest_results.get('total_return', 0):.2f}%

TRADE STATISTICS:
  Total Trades: {backtest_results.get('total_trades', 0)}
  Winning Trades: {backtest_results.get('winning_trades', 0)}
  Losing Trades: {backtest_results.get('losing_trades', 0)}
  Win Rate: {backtest_results.get('win_rate', 0):.2f}%

PROFITABILITY:
  Total Profit: ${backtest_results.get('total_profit', 0):,.2f}
  Total Loss: ${backtest_results.get('total_loss', 0):,.2f}
  Net Profit: ${backtest_results.get('net_profit', 0):,.2f}
  Profit Factor: {backtest_results.get('profit_factor', 0):.2f}

RISK METRICS:
  Maximum Drawdown: {dd_metrics['max_drawdown_percent']:.2f}%
  Drawdown Duration: {dd_metrics['drawdown_duration']} periods
  Sharpe Ratio: {sharpe:.2f}
  Sortino Ratio: {sortino:.2f}

{'='*70}
"""
        return report
