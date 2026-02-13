#!/usr/bin/env python3
"""
Example usage of Polymarket Trading Framework

Demonstrates backtesting and live trading setup.
"""

from datetime import datetime, timedelta
from strategies.examples import SimpleProbabilityStrategy
from backtesting.engine import BacktestEngine
from trading.engine import LiveTradingEngine
from analytics.metrics import PerformanceMetrics


def example_backtest():
    """Example: Run a backtest"""
    print("="*60)
    print("EXAMPLE: Running Backtest")
    print("="*60)
    
    # Create strategy
    strategy = SimpleProbabilityStrategy(
        name="SimpleProbability",
        initial_balance=1000.0,
        threshold=0.15,  # 15% deviation threshold
        min_confidence=0.7
    )
    
    # Set backtest period
    end_date = datetime.now()
    start_date = end_date - timedelta(days=30)  # Last 30 days
    
    # Create and run backtest
    engine = BacktestEngine(strategy, start_date, end_date, initial_balance=1000.0)
    results = engine.run()
    
    # Generate report
    engine.generate_report()
    
    # Calculate additional metrics
    metrics = PerformanceMetrics.generate_report(results)
    print(metrics)
    
    return results


def example_live_trading():
    """Example: Setup live trading"""
    print("="*60)
    print("EXAMPLE: Live Trading Setup")
    print("="*60)
    
    # Create strategy
    strategy = SimpleProbabilityStrategy(
        name="SimpleProbability",
        initial_balance=1000.0,
        threshold=0.15,
        min_confidence=0.7
    )
    
    # Create trading engine
    engine = LiveTradingEngine(strategy, poll_interval=60)  # Check every 60 seconds
    
    # Add markets to monitor
    # Option 1: Monitor specific event
    # engine.add_market(event_slug='will-bitcoin-reach-100k-by-2025')
    
    # Option 2: Monitor all markets in a category (e.g., Crypto tag_id=21)
    engine.monitor_tag(tag_id=21, limit=10)  # Monitor top 10 crypto markets
    
    # Start trading (uncomment to run)
    # engine.start()
    
    print("Live trading engine configured. Uncomment engine.start() to begin trading.")
    return engine


def example_market_discovery():
    """Example: Discover and analyze markets"""
    print("="*60)
    print("EXAMPLE: Market Discovery")
    print("="*60)
    
    from api import GammaClient, ClobClient
    
    gamma = GammaClient()
    clob = ClobClient()
    
    # Get all active events
    events = gamma.get_events(active=True, closed=False, limit=10)
    print(f"Found {len(events)} active events\n")
    
    # Analyze first event
    if events:
        event = events[0]
        print(f"Event: {event.get('title', 'Unknown')}")
        print(f"Slug: {event.get('slug', 'Unknown')}")
        
        for market in event.get('markets', []):
            print(f"\nMarket: {market.get('question', 'Unknown')}")
            
            # Get prices
            prices = gamma.get_market_prices(market)
            print(f"Prices: {prices}")
            
            # Get orderbook
            token_ids = market.get('clobTokenIds', [])
            if token_ids:
                best_bid_ask = clob.get_best_bid_ask(token_ids[0])
                print(f"Best Bid: {best_bid_ask['bid']:.4f}")
                print(f"Best Ask: {best_bid_ask['ask']:.4f}")
                print(f"Spread: {best_bid_ask['spread']:.4f}")
    
    return events


if __name__ == '__main__':
    print("\nPolymarket Trading Framework - Examples\n")
    
    # Run examples
    # example_market_discovery()
    # example_backtest()
    # example_live_trading()
    
    print("\nUncomment examples above to run them.")
