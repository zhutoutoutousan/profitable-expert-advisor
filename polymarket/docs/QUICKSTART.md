# Polymarket Trading Framework - Quick Start Guide

## Installation

```bash
cd polymarket
pip install -r requirements.txt

# For live trading, also install:
pip install py-clob-client ethers
```

## Configuration

Create a `.env` file in the `polymarket` directory:

```env
# Required for live trading
POLYMARKET_PRIVATE_KEY=your_private_key_here
POLYMARKET_CHAIN_ID=137
POLYMARKET_SIGNATURE_TYPE=0
POLYMARKET_FUNDER_ADDRESS=your_wallet_address

# Optional
POLYMARKET_INITIAL_BALANCE=1000.0
POLYMARKET_MAX_POSITION_SIZE=0.5
POLYMARKET_REQUEST_DELAY=0.1
```

## Quick Examples

### 1. Discover Markets

```python
from polymarket import GammaClient

gamma = GammaClient()
events = gamma.get_events(active=True, closed=False, limit=10)
for event in events:
    print(f"{event['title']}: {event['slug']}")
```

### 2. Get Market Prices

```python
from polymarket import GammaClient, ClobClient

gamma = GammaClient()
clob = ClobClient()

# Get market
market = gamma.get_market_by_slug('will-bitcoin-reach-100k-by-2025')
prices = gamma.get_market_prices(market)

# Get orderbook
token_id = market['clobTokenIds'][0]
best_bid_ask = clob.get_best_bid_ask(token_id)
print(f"Best Bid: {best_bid_ask['bid']}, Best Ask: {best_bid_ask['ask']}")
```

### 3. Run a Backtest

```python
from datetime import datetime, timedelta
from polymarket import BacktestEngine
from polymarket.strategies.examples import SimpleProbabilityStrategy

# Create strategy
strategy = SimpleProbabilityStrategy(
    threshold=0.15,  # Trade when probability deviates 15% from 0.5
    min_confidence=0.7
)

# Set period
end_date = datetime.now()
start_date = end_date - timedelta(days=30)

# Run backtest
engine = BacktestEngine(strategy, start_date, end_date, initial_balance=1000.0)
results = engine.run()
engine.generate_report()
```

### 4. Live Trading

```python
from polymarket import LiveTradingEngine
from polymarket.strategies.examples import SimpleProbabilityStrategy

# Create strategy
strategy = SimpleProbabilityStrategy()

# Create engine
engine = LiveTradingEngine(strategy, poll_interval=60)

# Add markets to monitor
engine.monitor_tag(tag_id=21, limit=10)  # Monitor crypto markets

# Start trading
engine.start()
```

## Creating Your Own Strategy

```python
from polymarket.strategies import BaseStrategy, MarketSignal

class MyStrategy(BaseStrategy):
    def __init__(self):
        super().__init__(name="MyStrategy", initial_balance=1000.0)
        self.my_parameter = 0.2
    
    def analyze_market(self, market_data):
        prices = market_data.get('prices', {})
        yes_price = prices.get('Yes', 0.5)
        
        # Your trading logic here
        if yes_price < 0.3:  # Undervalued
            return MarketSignal(
                action='BUY',
                token_id=market_data['market']['clobTokenIds'][0],
                size=0.2,  # 20% of balance
                confidence=0.8,
                reason="Yes probability is undervalued",
                metadata={}
            )
        
        return None
    
    def get_parameters(self):
        return {'my_parameter': self.my_parameter}
```

## API Reference

### GammaClient (Market Discovery)

- `get_events()` - Fetch active events
- `get_event_by_slug()` - Get event by slug
- `get_market_by_slug()` - Get market by slug
- `get_tags()` - Get all categories
- `get_sports()` - Get sports leagues
- `search_events()` - Search events

### ClobClient (Trading Data)

- `get_price()` - Get current price
- `get_orderbook()` - Get full orderbook
- `get_best_bid_ask()` - Get best bid/ask
- `get_market_depth()` - Get market depth
- `calculate_impact()` - Calculate price impact

### DataClient (Portfolio)

- `get_positions()` - Get user positions
- `get_trades()` - Get trade history
- `get_portfolio()` - Get portfolio summary

## Notes

1. **Historical Data**: Polymarket API may not provide full historical data. The backtesting engine uses simulated price evolution. For production, you'd need to store historical snapshots.

2. **Rate Limits**: Be mindful of API rate limits. The framework includes request delays, but check Polymarket documentation for current limits.

3. **Authentication**: Live trading requires proper authentication with `py-clob-client`. See Polymarket documentation for setup.

4. **Testing**: Always test strategies thoroughly in backtesting before live trading.

## Next Steps

- Read [Strategy Development Guide](STRATEGIES.md)
- Read [Backtesting Guide](BACKTESTING.md)
- Read [Live Trading Guide](LIVE_TRADING.md)
