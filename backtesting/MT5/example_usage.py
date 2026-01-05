"""
Example usage of the backtesting framework

This script demonstrates how to use the framework programmatically
without using the command-line interface.
"""

from datetime import datetime
import MetaTrader5 as mt5
from backtest_engine import BacktestEngine
from example_strategies import RSIReversalStrategy, RSIScalpingStrategy, EMAStrategy
from performance_analyzer import PerformanceAnalyzer


def example_rsi_reversal():
    """Example: RSI Reversal Strategy backtest"""
    print("="*60)
    print("Example 1: RSI Reversal Strategy")
    print("="*60)
    
    # Create strategy
    strategy = RSIReversalStrategy(
        symbol='XAUUSD',
        timeframe=mt5.TIMEFRAME_H1,
        initial_balance=10000.0,
        rsi_period=14,
        rsi_overbought=70,
        rsi_oversold=30,
        rsi_exit=50,
        lot_size=0.1,
        stop_loss_pips=50,
        take_profit_pips=100
    )
    
    # Run backtest
    engine = BacktestEngine(
        strategy,
        start_date=datetime(2023, 1, 1),
        end_date=datetime(2024, 1, 1)
    )
    
    results = engine.run()
    
    # Analyze results
    analyzer = PerformanceAnalyzer(results)
    analyzer.generate_report('example_results/rsi_reversal')
    
    return results


def example_rsi_scalping():
    """Example: RSI Scalping Strategy backtest"""
    print("\n" + "="*60)
    print("Example 2: RSI Scalping Strategy")
    print("="*60)
    
    # Create strategy
    strategy = RSIScalpingStrategy(
        symbol='EURUSD',
        timeframe=mt5.TIMEFRAME_M15,
        initial_balance=10000.0,
        rsi_period=14,
        rsi_overbought=71,
        rsi_oversold=57,
        rsi_target_buy=80,
        rsi_target_sell=20,
        lot_size=0.1,
        stop_loss_pips=30,
        take_profit_pips=50
    )
    
    # Run backtest
    engine = BacktestEngine(
        strategy,
        start_date=datetime(2023, 6, 1),
        end_date=datetime(2023, 12, 31)
    )
    
    results = engine.run()
    
    # Analyze results
    analyzer = PerformanceAnalyzer(results)
    analyzer.generate_report('example_results/rsi_scalping')
    
    return results


def example_ema_crossover():
    """Example: EMA Crossover Strategy backtest"""
    print("\n" + "="*60)
    print("Example 3: EMA Crossover Strategy")
    print("="*60)
    
    # Create strategy
    strategy = EMAStrategy(
        symbol='BTCUSD',
        timeframe=mt5.TIMEFRAME_H4,
        initial_balance=10000.0,
        ema_period=50,
        lot_size=0.1,
        stop_loss_pips=100,
        take_profit_pips=200
    )
    
    # Run backtest
    engine = BacktestEngine(
        strategy,
        start_date=datetime(2023, 1, 1),
        end_date=datetime(2024, 1, 1)
    )
    
    results = engine.run()
    
    # Analyze results
    analyzer = PerformanceAnalyzer(results)
    analyzer.generate_report('example_results/ema_crossover')
    
    return results


def compare_strategies():
    """Compare multiple strategies"""
    print("\n" + "="*60)
    print("Example 4: Strategy Comparison")
    print("="*60)
    
    strategies = [
        ('RSI Reversal', RSIReversalStrategy(
            'XAUUSD', mt5.TIMEFRAME_H1, 10000.0,
            rsi_period=14, rsi_overbought=70, rsi_oversold=30
        )),
        ('RSI Scalping', RSIScalpingStrategy(
            'XAUUSD', mt5.TIMEFRAME_H1, 10000.0,
            rsi_period=14, rsi_overbought=71, rsi_oversold=57
        )),
        ('EMA Crossover', EMAStrategy(
            'XAUUSD', mt5.TIMEFRAME_H1, 10000.0,
            ema_period=50
        ))
    ]
    
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2024, 1, 1)
    
    results_list = []
    
    for name, strategy in strategies:
        print(f"\nBacktesting {name}...")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        results_list.append((name, results))
        
        analyzer = PerformanceAnalyzer(results)
        print(f"\n{name} Results:")
        analyzer.print_summary()
    
    # Print comparison
    print("\n" + "="*60)
    print("STRATEGY COMPARISON")
    print("="*60)
    print(f"{'Strategy':<20} {'Return %':<12} {'Win Rate %':<12} {'Profit Factor':<15} {'Max DD %':<10}")
    print("-"*60)
    
    for name, results in results_list:
        metrics = results['metrics']
        print(f"{name:<20} {metrics['total_return_pct']:>10.2f}% "
              f"{metrics['win_rate_pct']:>10.2f}% "
              f"{metrics['profit_factor']:>13.2f} "
              f"{metrics['max_drawdown_pct']:>8.2f}%")


if __name__ == '__main__':
    # Initialize MT5 (will be done by BacktestEngine, but good to check)
    if not mt5.initialize():
        print("MT5 initialization failed. Please ensure MT5 is installed and running.")
        exit(1)
    
    print("MetaTrader5 Python Backtesting Framework - Examples")
    print("="*60)
    
    # Run examples (comment out the ones you don't want to run)
    
    # Example 1: RSI Reversal
    # example_rsi_reversal()
    
    # Example 2: RSI Scalping
    # example_rsi_scalping()
    
    # Example 3: EMA Crossover
    # example_ema_crossover()
    
    # Example 4: Compare strategies
    compare_strategies()
    
    mt5.shutdown()
    print("\nExamples completed!")
