#!/usr/bin/env python3
"""
Command-line interface for running Polymarket backtests
"""

import argparse
from datetime import datetime
from strategies.examples import SimpleProbabilityStrategy
from backtesting.engine import BacktestEngine


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Run Polymarket strategy backtest')
    
    parser.add_argument('--strategy', type=str, default='SimpleProbability',
                       help='Strategy name')
    parser.add_argument('--start', type=str, required=True,
                       help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end', type=str, required=True,
                       help='End date (YYYY-MM-DD)')
    parser.add_argument('--balance', type=float, default=1000.0,
                       help='Initial balance in USDC')
    parser.add_argument('--threshold', type=float, default=0.15,
                       help='Probability deviation threshold')
    
    return parser.parse_args()


def main():
    """Main entry point"""
    args = parse_args()
    
    # Parse dates
    start_date = datetime.strptime(args.start, '%Y-%m-%d')
    end_date = datetime.strptime(args.end, '%Y-%m-%d')
    
    # Create strategy
    if args.strategy == 'SimpleProbability':
        strategy = SimpleProbabilityStrategy(
            initial_balance=args.balance,
            threshold=args.threshold
        )
    else:
        raise ValueError(f"Unknown strategy: {args.strategy}")
    
    # Create and run backtest
    engine = BacktestEngine(strategy, start_date, end_date, args.balance)
    results = engine.run()
    
    # Generate report
    engine.generate_report()
    
    return results


if __name__ == '__main__':
    main()
