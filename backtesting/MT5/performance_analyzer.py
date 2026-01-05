"""
Performance Analysis and Reporting

This module provides tools for analyzing backtest results and generating reports.
"""

from typing import Dict, Any, List
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime


class PerformanceAnalyzer:
    """
    Analyzes backtest performance and generates reports.
    """
    
    def __init__(self, backtest_results: Dict[str, Any]):
        """
        Initialize with backtest results.
        
        Args:
            backtest_results: Results dictionary from BacktestEngine.run()
        """
        self.results = backtest_results
        self.metrics = backtest_results['metrics']
        self.trades = backtest_results['trades']
        self.strategy_name = backtest_results['strategy_name']
        
    def print_summary(self):
        """Print a summary of the backtest results."""
        print("\n" + "="*60)
        print(f"BACKTEST SUMMARY: {self.strategy_name}")
        print("="*60)
        print(f"\nInitial Balance: ${self.metrics['initial_balance']:,.2f}")
        print(f"Final Balance: ${self.metrics['final_balance']:,.2f}")
        print(f"Total Return: {self.metrics['total_return_pct']:.2f}%")
        print(f"\nTotal Trades: {self.metrics['total_trades']}")
        print(f"Winning Trades: {self.metrics['winning_trades']}")
        print(f"Losing Trades: {self.metrics['losing_trades']}")
        print(f"Win Rate: {self.metrics['win_rate_pct']:.2f}%")
        print(f"\nTotal Profit: ${self.metrics['total_profit']:,.2f}")
        print(f"Total Loss: ${self.metrics['total_loss']:,.2f}")
        print(f"Profit Factor: {self.metrics['profit_factor']:.2f}")
        print(f"\nAverage Win: ${self.metrics['avg_win']:,.2f}")
        print(f"Average Loss: ${self.metrics['avg_loss']:,.2f}")
        print(f"Max Drawdown: {self.metrics['max_drawdown_pct']:.2f}%")
        
        if self.metrics.get('parameters'):
            print(f"\nStrategy Parameters:")
            for key, value in self.metrics['parameters'].items():
                print(f"  {key}: {value}")
        
        print("="*60 + "\n")
    
    def get_trades_dataframe(self) -> pd.DataFrame:
        """Convert trades list to pandas DataFrame."""
        if not self.trades:
            return pd.DataFrame()
        
        df = pd.DataFrame(self.trades)
        df['open_time'] = pd.to_datetime(df['open_time'])
        df['close_time'] = pd.to_datetime(df['close_time'])
        df['duration'] = df['close_time'] - df['open_time']
        
        return df
    
    def plot_equity_curve(self, save_path: str = None):
        """
        Plot equity curve over time.
        
        Args:
            save_path: Optional path to save the plot
        """
        if not self.trades:
            print("No trades to plot")
            return
        
        df = self.get_trades_dataframe()
        df = df.sort_values('close_time')
        
        # Calculate cumulative equity
        cumulative_profit = df['profit'].cumsum()
        equity_curve = self.metrics['initial_balance'] + cumulative_profit
        
        plt.figure(figsize=(12, 6))
        plt.plot(df['close_time'], equity_curve, linewidth=2, label='Equity')
        plt.axhline(y=self.metrics['initial_balance'], color='r', linestyle='--', label='Initial Balance')
        plt.xlabel('Time')
        plt.ylabel('Equity ($)')
        plt.title(f'Equity Curve - {self.strategy_name}')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            print(f"Equity curve saved to {save_path}")
        else:
            plt.show()
    
    def plot_drawdown(self, save_path: str = None):
        """
        Plot drawdown over time.
        
        Args:
            save_path: Optional path to save the plot
        """
        if not self.trades:
            print("No trades to plot")
            return
        
        df = self.get_trades_dataframe()
        df = df.sort_values('close_time')
        
        # Calculate cumulative equity
        cumulative_profit = df['profit'].cumsum()
        equity_curve = self.metrics['initial_balance'] + cumulative_profit
        
        # Calculate running maximum
        running_max = equity_curve.expanding().max()
        drawdown = (equity_curve - running_max) / running_max * 100
        
        plt.figure(figsize=(12, 6))
        plt.fill_between(df['close_time'], drawdown, 0, alpha=0.3, color='red', label='Drawdown')
        plt.plot(df['close_time'], drawdown, linewidth=1, color='darkred')
        plt.xlabel('Time')
        plt.ylabel('Drawdown (%)')
        plt.title(f'Drawdown Chart - {self.strategy_name}')
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            print(f"Drawdown chart saved to {save_path}")
        else:
            plt.show()
    
    def plot_monthly_returns(self, save_path: str = None):
        """
        Plot monthly returns.
        
        Args:
            save_path: Optional path to save the plot
        """
        if not self.trades:
            print("No trades to plot")
            return
        
        df = self.get_trades_dataframe()
        df = df.sort_values('close_time')
        
        # Group by month
        df['month'] = df['close_time'].dt.to_period('M')
        monthly_returns = df.groupby('month')['profit'].sum()
        monthly_returns_pct = (monthly_returns / self.metrics['initial_balance']) * 100
        
        plt.figure(figsize=(12, 6))
        colors = ['green' if x > 0 else 'red' for x in monthly_returns_pct]
        plt.bar(range(len(monthly_returns_pct)), monthly_returns_pct, color=colors, alpha=0.7)
        plt.xlabel('Month')
        plt.ylabel('Return (%)')
        plt.title(f'Monthly Returns - {self.strategy_name}')
        plt.xticks(range(len(monthly_returns_pct)), [str(x) for x in monthly_returns_pct.index], rotation=45)
        plt.axhline(y=0, color='black', linestyle='-', linewidth=0.5)
        plt.grid(True, alpha=0.3, axis='y')
        plt.tight_layout()
        
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            print(f"Monthly returns chart saved to {save_path}")
        else:
            plt.show()
    
    def export_trades_csv(self, filepath: str):
        """
        Export trades to CSV file.
        
        Args:
            filepath: Path to save CSV file
        """
        df = self.get_trades_dataframe()
        df.to_csv(filepath, index=False)
        print(f"Trades exported to {filepath}")
    
    def generate_report(self, output_dir: str = "backtest_results"):
        """
        Generate a comprehensive report with all charts and data.
        
        Args:
            output_dir: Directory to save report files
        """
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        prefix = f"{self.strategy_name}_{timestamp}"
        
        # Print summary
        self.print_summary()
        
        # Generate plots
        self.plot_equity_curve(os.path.join(output_dir, f"{prefix}_equity_curve.png"))
        self.plot_drawdown(os.path.join(output_dir, f"{prefix}_drawdown.png"))
        self.plot_monthly_returns(os.path.join(output_dir, f"{prefix}_monthly_returns.png"))
        
        # Export trades
        self.export_trades_csv(os.path.join(output_dir, f"{prefix}_trades.csv"))
        
        print(f"\nReport generated in {output_dir}/")
