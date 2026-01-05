"""
Main script to run backtests

Example usage:
    python run_backtest.py --strategy RSIReversalStrategy --symbol XAUUSD --start 2023-01-01 --end 2024-01-01
"""

import argparse
from datetime import datetime
import MetaTrader5 as mt5
from backtest_engine import BacktestEngine
from example_strategies import RSIScalpingStrategy, EMAStrategy, RSIReversalStrategy
from performance_analyzer import PerformanceAnalyzer
from base_strategy import BaseStrategy


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Run backtest on trading strategy')
    
    parser.add_argument('--strategy', type=str, required=True,
                       choices=['RSIScalpingStrategy', 'EMAStrategy', 'RSIReversalStrategy'],
                       help='Strategy to backtest')
    parser.add_argument('--symbol', type=str, default='XAUUSD',
                       help='Trading symbol (default: XAUUSD)')
    parser.add_argument('--timeframe', type=str, default='H1',
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Timeframe (default: H1)')
    parser.add_argument('--start', type=str, required=True,
                       help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end', type=str, required=True,
                       help='End date (YYYY-MM-DD)')
    parser.add_argument('--balance', type=float, default=10000.0,
                       help='Initial balance (default: 10000)')
    parser.add_argument('--output', type=str, default='backtest_results',
                       help='Output directory for results (default: backtest_results)')
    
    # Strategy-specific parameters
    parser.add_argument('--rsi-period', type=int, default=14,
                       help='RSI period (default: 14)')
    parser.add_argument('--rsi-overbought', type=float, default=70.0,
                       help='RSI overbought level (default: 70)')
    parser.add_argument('--rsi-oversold', type=float, default=30.0,
                       help='RSI oversold level (default: 30)')
    parser.add_argument('--ema-period', type=int, default=50,
                       help='EMA period (default: 50)')
    parser.add_argument('--lot-size', type=float, default=0.1,
                       help='Lot size (default: 0.1)')
    parser.add_argument('--stop-loss', type=int, default=50,
                       help='Stop loss in pips (default: 50)')
    parser.add_argument('--take-profit', type=int, default=100,
                       help='Take profit in pips (default: 100)')
    
    return parser.parse_args()


def get_timeframe(timeframe_str: str) -> int:
    """Convert timeframe string to MT5 constant."""
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1
    }
    return timeframe_map.get(timeframe_str, mt5.TIMEFRAME_H1)


def create_strategy(strategy_name: str, symbol: str, timeframe: int, 
                   initial_balance: float, args) -> BaseStrategy:
    """Create strategy instance based on name."""
    if strategy_name == 'RSIScalpingStrategy':
        return RSIScalpingStrategy(
            symbol=symbol,
            timeframe=timeframe,
            initial_balance=initial_balance,
            rsi_period=args.rsi_period,
            rsi_overbought=args.rsi_overbought,
            rsi_oversold=args.rsi_oversold,
            lot_size=args.lot_size,
            stop_loss_pips=args.stop_loss,
            take_profit_pips=args.take_profit
        )
    elif strategy_name == 'EMAStrategy':
        return EMAStrategy(
            symbol=symbol,
            timeframe=timeframe,
            initial_balance=initial_balance,
            ema_period=args.ema_period,
            lot_size=args.lot_size,
            stop_loss_pips=args.stop_loss,
            take_profit_pips=args.take_profit
        )
    elif strategy_name == 'RSIReversalStrategy':
        return RSIReversalStrategy(
            symbol=symbol,
            timeframe=timeframe,
            initial_balance=initial_balance,
            rsi_period=args.rsi_period,
            rsi_overbought=args.rsi_overbought,
            rsi_oversold=args.rsi_oversold,
            lot_size=args.lot_size,
            stop_loss_pips=args.stop_loss,
            take_profit_pips=args.take_profit
        )
    else:
        raise ValueError(f"Unknown strategy: {strategy_name}")


def main():
    """Main function to run backtest."""
    args = parse_args()
    
    # Parse dates
    start_date = datetime.strptime(args.start, '%Y-%m-%d')
    end_date = datetime.strptime(args.end, '%Y-%m-%d')
    
    # Get timeframe
    timeframe = get_timeframe(args.timeframe)
    
    # Create strategy
    print(f"Creating {args.strategy} strategy...")
    strategy = create_strategy(
        args.strategy,
        args.symbol,
        timeframe,
        args.balance,
        args
    )
    
    # Create and run backtest
    print("Initializing backtest engine...")
    engine = BacktestEngine(strategy, start_date, end_date)
    
    print("Running backtest...")
    results = engine.run()
    
    # Analyze results
    print("Analyzing results...")
    analyzer = PerformanceAnalyzer(results)
    analyzer.generate_report(args.output)
    
    print("\nBacktest completed successfully!")


if __name__ == '__main__':
    main()
