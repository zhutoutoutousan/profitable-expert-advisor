# Strategy Development Guide

Complete guide to developing trading strategies for Polymarket.

## Table of Contents

- [Strategy Basics](#strategy-basics)
- [Creating Your First Strategy](#creating-your-first-strategy)
- [Advanced Patterns](#advanced-patterns)
- [Best Practices](#best-practices)
- [Common Strategies](#common-strategies)
- [Testing Strategies](#testing-strategies)

## Strategy Basics

### What is a Strategy?

A strategy is a Python class that:
1. Analyzes market data
2. Generates trading signals
3. Manages risk and positions
4. Tracks performance

### Strategy Lifecycle

1. **Initialization**: Set up parameters and initial state
2. **Market Analysis**: Receive market data and analyze
3. **Signal Generation**: Decide whether to trade
4. **Position Management**: Track open positions
5. **Performance Tracking**: Monitor PnL and metrics

## Creating Your First Strategy

### Step 1: Inherit from BaseStrategy

```python
from polymarket.strategies import BaseStrategy, MarketSignal

class MyStrategy(BaseStrategy):
    def __init__(self):
        super().__init__(name="MyStrategy", initial_balance=1000.0)
        # Your initialization code
```

### Step 2: Implement analyze_market()

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    """
    Analyze market and generate signal.
    
    Args:
        market_data: Dictionary with:
            - 'event': Event information
            - 'market': Market information
            - 'prices': Current outcome prices {'Yes': 0.65, 'No': 0.35}
            - 'orderbook': Orderbook data
            - 'timestamp': Current timestamp
    
    Returns:
        MarketSignal or None
    """
    prices = market_data.get('prices', {})
    yes_price = prices.get('Yes', 0.5)
    
    # Your trading logic here
    if yes_price < 0.4:  # Undervalued
        return MarketSignal(
            action='BUY',
            token_id=market_data['market']['clobTokenIds'][0],
            size=0.2,  # 20% of balance
            confidence=0.8,
            reason="Yes probability is undervalued",
            metadata={'yes_price': yes_price}
        )
    
    return None  # No trade
```

### Step 3: Implement get_parameters()

```python
def get_parameters(self) -> Dict[str, Any]:
    """Return strategy parameters"""
    return {
        'threshold': 0.4,
        'position_size': 0.2
    }
```

### Complete Example

```python
from typing import Dict, Optional
from polymarket.strategies import BaseStrategy, MarketSignal

class MeanReversionStrategy(BaseStrategy):
    """
    Simple mean reversion strategy.
    Buys when price deviates significantly from 0.5.
    """
    
    def __init__(self, threshold: float = 0.15):
        super().__init__(name="MeanReversion", initial_balance=1000.0)
        self.threshold = threshold
    
    def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
        prices = market_data.get('prices', {})
        yes_price = prices.get('Yes', 0.5)
        
        # Calculate deviation from fair value (0.5)
        deviation = abs(yes_price - 0.5)
        
        if deviation < self.threshold:
            return None  # Not enough deviation
        
        # Determine action
        if yes_price < (0.5 - self.threshold):
            # Yes is undervalued, buy
            confidence = min(1.0, deviation / self.threshold)
            
            return MarketSignal(
                action='BUY',
                token_id=market_data['market']['clobTokenIds'][0],
                size=0.2,
                confidence=confidence,
                reason=f"Yes price {yes_price:.2%} is {deviation:.2%} below fair value",
                metadata={'yes_price': yes_price, 'deviation': deviation}
            )
        
        elif yes_price > (0.5 + self.threshold):
            # Yes is overvalued, close position if we have one
            token_id = market_data['market']['clobTokenIds'][0]
            if token_id in self.positions:
                return MarketSignal(
                    action='SELL',
                    token_id=token_id,
                    size=1.0,  # Close entire position
                    confidence=confidence,
                    reason=f"Yes price {yes_price:.2%} is {deviation:.2%} above fair value",
                    metadata={'yes_price': yes_price, 'deviation': deviation}
                )
        
        return None
    
    def get_parameters(self) -> Dict:
        return {'threshold': self.threshold}
```

## Advanced Patterns

### Using Orderbook Data

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    orderbook = market_data.get('orderbook', {})
    bids = orderbook.get('bids', [])
    asks = orderbook.get('asks', [])
    
    if not bids or not asks:
        return None
    
    # Calculate bid-ask spread
    best_bid = bids[0]['price']
    best_ask = asks[0]['price']
    spread = best_ask - best_bid
    
    # Trade when spread is tight (good liquidity)
    if spread < 0.02:  # 2% spread
        # Your trading logic
        pass
```

### Using Historical Data

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    history = market_data.get('history', [])
    
    if len(history) < 20:
        return None  # Not enough data
    
    # Calculate moving average
    recent_prices = [h['price'] for h in history[-20:]]
    ma = sum(recent_prices) / len(recent_prices)
    
    current_price = market_data['prices']['Yes']
    
    # Mean reversion: buy when below MA
    if current_price < ma * 0.95:
        return MarketSignal(...)
```

### Position Sizing Based on Confidence

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    # Calculate confidence
    confidence = self.calculate_confidence(market_data)
    
    # Size position based on confidence
    # Higher confidence = larger position
    base_size = 0.1  # 10% base
    size = base_size * confidence  # Scale by confidence
    
    return MarketSignal(
        action='BUY',
        token_id=...,
        size=size,
        confidence=confidence,
        ...
    )
```

### Risk Management

```python
class RiskManagedStrategy(BaseStrategy):
    def __init__(self):
        super().__init__(name="RiskManaged", initial_balance=1000.0)
        # Override risk limits
        self.max_position_size = 0.3  # Max 30% per position
        self.max_total_exposure = 0.6  # Max 60% total
        self.min_confidence = 0.7  # Only trade high confidence
    
    def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
        # Check if we can open new position
        if len(self.positions) >= 3:
            return None  # Max 3 positions
        
        # Your trading logic
        signal = self.generate_signal(market_data)
        
        if signal and signal.confidence >= self.min_confidence:
            # Verify we can open position
            size_usdc = signal.size * self.current_balance
            if self.can_open_position(size_usdc, signal.token_id):
                return signal
        
        return None
```

## Best Practices

### 1. Always Check Data Availability

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    prices = market_data.get('prices', {})
    if not prices:
        return None  # No price data
    
    yes_price = prices.get('Yes')
    if yes_price is None:
        return None  # Missing Yes price
```

### 2. Validate Token IDs

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    market = market_data.get('market', {})
    token_ids = market.get('clobTokenIds', [])
    
    if not token_ids:
        return None  # No token IDs available
    
    token_id = token_ids[0]
    # Use token_id...
```

### 3. Use Confidence Thresholds

```python
# Only trade high-confidence signals
if signal.confidence < self.min_confidence:
    return None
```

### 4. Log Trading Decisions

```python
import logging

logger = logging.getLogger(__name__)

def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    signal = self.generate_signal(market_data)
    
    if signal:
        logger.info(f"Signal: {signal.action} {signal.token_id} "
                   f"size={signal.size:.2%} confidence={signal.confidence:.2f} "
                   f"reason: {signal.reason}")
    
    return signal
```

### 5. Handle Edge Cases

```python
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    prices = market_data.get('prices', {})
    yes_price = prices.get('Yes', 0.5)
    no_price = prices.get('No', 0.5)
    
    # Check if prices are valid
    if yes_price <= 0 or yes_price >= 1:
        return None  # Invalid price
    
    # Check if market is close to resolution
    market = market_data.get('market', {})
    end_date = market.get('endDate')
    if end_date and self.is_near_resolution(end_date):
        return None  # Too close to resolution, avoid trading
```

## Common Strategies

### 1. Mean Reversion

Buy when price deviates from fair value (0.5), sell when it returns.

### 2. Momentum

Buy when price is trending up, sell when trend reverses.

### 3. Arbitrage

Exploit price differences between related markets.

### 4. Market Making

Provide liquidity by placing both buy and sell orders.

### 5. News-Based

Trade based on external information and news events.

### 6. Statistical Arbitrage

Use statistical models to identify mispriced markets.

## Testing Strategies

### Unit Testing

```python
import unittest
from polymarket.strategies.examples import SimpleProbabilityStrategy

class TestStrategy(unittest.TestCase):
    def setUp(self):
        self.strategy = SimpleProbabilityStrategy(threshold=0.15)
    
    def test_analyze_market_undervalued(self):
        market_data = {
            'market': {'clobTokenIds': ['token123']},
            'prices': {'Yes': 0.3, 'No': 0.7}  # Undervalued
        }
        
        signal = self.strategy.analyze_market(market_data)
        
        self.assertIsNotNone(signal)
        self.assertEqual(signal.action, 'BUY')
        self.assertGreater(signal.confidence, 0.7)
```

### Backtesting

```python
from datetime import datetime, timedelta
from polymarket import BacktestEngine

strategy = MyStrategy()
end_date = datetime.now()
start_date = end_date - timedelta(days=30)

engine = BacktestEngine(strategy, start_date, end_date)
results = engine.run()

print(f"Total Return: {results['total_return']:.2f}%")
print(f"Win Rate: {results['win_rate']:.2f}%")
```

### Paper Trading

Test strategies with live data but simulated execution:

```python
from polymarket import LiveTradingEngine

strategy = MyStrategy()
engine = LiveTradingEngine(strategy, poll_interval=60)

# Add markets
engine.monitor_tag(tag_id=21, limit=10)

# Start (will simulate orders)
engine.start()
```

## Strategy Checklist

Before deploying a strategy:

- [ ] Strategy inherits from `BaseStrategy`
- [ ] `analyze_market()` implemented
- [ ] `get_parameters()` implemented
- [ ] Risk management limits set
- [ ] Edge cases handled
- [ ] Data validation included
- [ ] Backtested on historical data
- [ ] Paper traded successfully
- [ ] Performance metrics reviewed
- [ ] Error handling implemented
- [ ] Logging added

## Next Steps

- Read [API Reference](API_REFERENCE.md) for detailed API documentation
- Check [Glossary](GLOSSARY.md) for terminology
- Review example strategies in `strategies/examples/`
- Test your strategy thoroughly before live trading
