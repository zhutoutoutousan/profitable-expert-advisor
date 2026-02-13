"""
Parameter Optimization for ONNX Strategy

This script optimizes strategy parameters (prediction_threshold, min_confidence,
stop_loss_pips, take_profit_pips, lot_size) using grid search or random search.
"""

import os
import sys
from datetime import datetime, timedelta
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from itertools import product
import json

# Add paths
current_dir = os.path.dirname(os.path.abspath(__file__))
backtest_dir = os.path.join(os.path.dirname(current_dir), 'backtesting', 'MT5')
sys.path.insert(0, backtest_dir)

from backtest_engine import BacktestEngine
from onnx_backtest_strategy import ONNXBacktestStrategy
from performance_analyzer import PerformanceAnalyzer


class ONNXParameterOptimizer:
    """Optimize ONNX strategy parameters."""
    
    def __init__(self, symbol: str, timeframe: int, model_path: str, scaler_path: str,
                 start_date: datetime, end_date: datetime, initial_balance: float = 10000.0):
        """
        Initialize optimizer.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe
            model_path: Path to ONNX model
            scaler_path: Path to scaler
            start_date: Backtest start date
            end_date: Backtest end date
            initial_balance: Starting balance
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.model_path = model_path
        self.scaler_path = scaler_path
        self.start_date = start_date
        self.end_date = end_date
        self.initial_balance = initial_balance
        
    def grid_search(self, param_grid: dict, metric: str = 'sharpe_ratio') -> pd.DataFrame:
        """
        Perform grid search optimization.
        
        Args:
            param_grid: Dictionary of parameter ranges
                Example: {
                    'prediction_threshold': [0.0001, 0.0002, 0.0005],
                    'min_confidence': [0.2, 0.3, 0.4],
                    'stop_loss_pips': [30, 50, 70],
                    'take_profit_pips': [60, 100, 150],
                    'lot_size': [0.1, 0.2]
                }
            metric: Metric to optimize ('sharpe_ratio', 'total_return', 'max_drawdown', 'profit_factor')
        
        Returns:
            DataFrame with results sorted by metric
        """
        print("="*60)
        print("Grid Search Parameter Optimization")
        print("="*60)
        
        # Generate all parameter combinations
        param_names = list(param_grid.keys())
        param_values = list(param_grid.values())
        combinations = list(product(*param_values))
        
        total_combinations = len(combinations)
        print(f"\nTotal parameter combinations: {total_combinations}")
        print(f"Optimizing for: {metric}\n")
        
        results = []
        
        for i, combo in enumerate(combinations, 1):
            params = dict(zip(param_names, combo))
            
            print(f"[{i}/{total_combinations}] Testing: {params}")
            
            try:
                # Create strategy with these parameters
                strategy = ONNXBacktestStrategy(
                    symbol=self.symbol,
                    timeframe=self.timeframe,
                    model_path=self.model_path,
                    scaler_path=self.scaler_path,
                    initial_balance=self.initial_balance,
                    **params
                )
                
                # Run backtest
                engine = BacktestEngine(strategy, self.start_date, self.end_date)
                backtest_results = engine.run()
                
                # Calculate metrics
                analyzer = PerformanceAnalyzer(backtest_results)
                metrics = analyzer.metrics
                
                # Store results
                result = params.copy()
                # Map metric names to match what we're looking for
                result['total_return'] = metrics.get('total_return_pct', 0) / 100.0
                result['max_drawdown'] = metrics.get('max_drawdown_pct', 0) / 100.0
                result['sharpe_ratio'] = metrics.get('sharpe_ratio', 0.0) if 'sharpe_ratio' in metrics else 0.0
                result['profit_factor'] = metrics.get('profit_factor', 0.0)
                result['win_rate'] = metrics.get('win_rate_pct', 0) / 100.0
                result['total_trades'] = metrics.get('total_trades', 0)
                result['final_balance'] = metrics.get('final_balance', self.initial_balance)
                results.append(result)
                
                metric_value = result.get(metric, 0)
                print(f"  -> {metric}: {metric_value:.4f} | Trades: {result['total_trades']}")
                
            except Exception as e:
                print(f"  X Error: {e}")
                continue
        
        # Convert to DataFrame
        df_results = pd.DataFrame(results)
        
        if len(df_results) == 0:
            raise ValueError("No successful backtests!")
        
        # Sort by metric (descending for most metrics, ascending for max_drawdown)
        if metric == 'max_drawdown':
            df_results = df_results.sort_values(metric, ascending=True)
        else:
            df_results = df_results.sort_values(metric, ascending=False)
        
        return df_results
    
    def random_search(self, param_ranges: dict, n_iter: int = 50, 
                     metric: str = 'sharpe_ratio') -> pd.DataFrame:
        """
        Perform random search optimization.
        
        Args:
            param_ranges: Dictionary of parameter ranges
                Example: {
                    'prediction_threshold': (0.0001, 0.001),
                    'min_confidence': (0.1, 0.5),
                    'stop_loss_pips': (20, 100),
                    'take_profit_pips': (40, 200),
                    'lot_size': (0.1, 0.5)
                }
            n_iter: Number of random combinations to test
            metric: Metric to optimize
        
        Returns:
            DataFrame with results sorted by metric
        """
        print("="*60)
        print("Random Search Parameter Optimization")
        print("="*60)
        print(f"\nTesting {n_iter} random parameter combinations")
        print(f"Optimizing for: {metric}\n")
        
        results = []
        np.random.seed(42)  # For reproducibility
        
        for i in range(1, n_iter + 1):
            # Generate random parameters
            params = {}
            for param_name, (min_val, max_val) in param_ranges.items():
                if isinstance(min_val, int) and isinstance(max_val, int):
                    params[param_name] = np.random.randint(min_val, max_val + 1)
                else:
                    params[param_name] = np.random.uniform(min_val, max_val)
            
            print(f"[{i}/{n_iter}] Testing: {params}")
            
            try:
                # Create strategy
                strategy = ONNXBacktestStrategy(
                    symbol=self.symbol,
                    timeframe=self.timeframe,
                    model_path=self.model_path,
                    scaler_path=self.scaler_path,
                    initial_balance=self.initial_balance,
                    **params
                )
                
                # Run backtest
                engine = BacktestEngine(strategy, self.start_date, self.end_date)
                backtest_results = engine.run()
                
                # Calculate metrics
                analyzer = PerformanceAnalyzer(backtest_results)
                metrics = analyzer.metrics
                
                # Store results
                result = params.copy()
                # Map metric names to match what we're looking for
                result['total_return'] = metrics.get('total_return_pct', 0) / 100.0
                result['max_drawdown'] = metrics.get('max_drawdown_pct', 0) / 100.0
                result['sharpe_ratio'] = metrics.get('sharpe_ratio', 0.0) if 'sharpe_ratio' in metrics else 0.0
                result['profit_factor'] = metrics.get('profit_factor', 0.0)
                result['win_rate'] = metrics.get('win_rate_pct', 0) / 100.0
                result['total_trades'] = metrics.get('total_trades', 0)
                result['final_balance'] = metrics.get('final_balance', self.initial_balance)
                results.append(result)
                
                metric_value = result.get(metric, 0)
                print(f"  -> {metric}: {metric_value:.4f} | Trades: {result['total_trades']}")
                
            except Exception as e:
                print(f"  X Error: {e}")
                continue
        
        # Convert to DataFrame
        df_results = pd.DataFrame(results)
        
        if len(df_results) == 0:
            raise ValueError("No successful backtests!")
        
        # Sort by metric
        if metric == 'max_drawdown':
            df_results = df_results.sort_values(metric, ascending=True)
        else:
            df_results = df_results.sort_values(metric, ascending=False)
        
        return df_results
    
    def save_results(self, df_results: pd.DataFrame, output_file: str = 'optimization_results.csv'):
        """Save optimization results to CSV."""
        df_results.to_csv(output_file, index=False)
        print(f"\nResults saved to: {output_file}")
        
        # Also save top 10 as JSON
        top_10 = df_results.head(10).to_dict('records')
        json_file = output_file.replace('.csv', '_top10.json')
        with open(json_file, 'w') as f:
            json.dump(top_10, f, indent=2, default=str)
        print(f"Top 10 results saved to: {json_file}")


def main():
    """Main optimization function."""
    # Configuration
    symbol = 'XAUUSD'
    timeframe = mt5.TIMEFRAME_H1
    model_path = 'models/XAUUSD_H1_model.onnx'
    scaler_path = 'models/XAUUSD_H1_scaler.pkl'
    initial_balance = 10000.0
    
    # Backtest date range (use last 6 months for optimization)
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)
    
    # Check if model exists
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found: {model_path}")
        print("Please train the model first using train_onnx_model.py")
        return
    
    # Initialize MT5
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        return
    
    try:
        # Create optimizer
        optimizer = ONNXParameterOptimizer(
            symbol=symbol,
            timeframe=timeframe,
            model_path=model_path,
            scaler_path=scaler_path,
            start_date=start_date,
            end_date=end_date,
            initial_balance=initial_balance
        )
        
        # Choose optimization method (use command line args or defaults)
        import sys
        choice = "2"  # Default to random search
        n_iter = 30   # Default iterations
        
        if len(sys.argv) > 1:
            choice = sys.argv[1]
        if len(sys.argv) > 2:
            n_iter = int(sys.argv[2])
        
        print("\nOptimization Configuration:")
        print(f"Method: {'Grid Search' if choice == '1' else 'Random Search'}")
        if choice != "1":
            print(f"Iterations: {n_iter}")
        print()
        
        if choice == "1":
            # Grid search parameters
            param_grid = {
                'prediction_threshold': [0.0001, 0.0002, 0.0005, 0.001],
                'min_confidence': [0.1, 0.2, 0.3, 0.4],
                'stop_loss_pips': [30, 50, 70, 100],
                'take_profit_pips': [60, 100, 150, 200],
                'lot_size': [0.1, 0.2]
            }
            
            results = optimizer.grid_search(param_grid, metric='sharpe_ratio')
            
        else:
            # Random search parameters
            param_ranges = {
                'prediction_threshold': (0.00005, 0.002),  # Lower threshold to get more trades
                'min_confidence': (0.05, 0.5),  # Lower confidence requirement
                'stop_loss_pips': (20, 150),
                'take_profit_pips': (40, 300),
                'lot_size': (0.05, 0.3)
            }
            
            results = optimizer.random_search(param_ranges, n_iter=n_iter, metric='sharpe_ratio')
        
        # Display top results
        print("\n" + "="*60)
        print("Top 10 Results")
        print("="*60)
        print(results.head(10).to_string(index=False))
        
        # Save results
        optimizer.save_results(results, 'onnx_optimization_results.csv')
        
        # Display best parameters
        best = results.iloc[0]
        print("\n" + "="*60)
        print("Best Parameters")
        print("="*60)
        print(f"Prediction Threshold: {best['prediction_threshold']:.6f}")
        print(f"Min Confidence: {best['min_confidence']:.2f}")
        print(f"Stop Loss (pips): {best['stop_loss_pips']}")
        print(f"Take Profit (pips): {best['take_profit_pips']}")
        print(f"Lot Size: {best['lot_size']:.2f}")
        print(f"\nPerformance Metrics:")
        print(f"  Sharpe Ratio: {best.get('sharpe_ratio', 'N/A'):.4f}")
        print(f"  Total Return: {best.get('total_return', 'N/A'):.2%}")
        print(f"  Max Drawdown: {best.get('max_drawdown', 'N/A'):.2%}")
        print(f"  Profit Factor: {best.get('profit_factor', 'N/A'):.2f}")
        
    except KeyboardInterrupt:
        print("\n\nOptimization interrupted by user")
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
