# Polymarket API Reference

Complete API reference for the Polymarket Trading Framework.

## Table of Contents

- [Rate Limits](#rate-limits)
- [Gamma API Client](#gamma-api-client)
- [CLOB API Client](#clob-api-client)
- [Data API Client](#data-api-client)
- [Base Strategy](#base-strategy)
- [Backtesting Engine](#backtesting-engine)
- [Live Trading Engine](#live-trading-engine)
- [Error Handling](#error-handling)

## Rate Limits

### Overview

Polymarket APIs implement rate limiting to ensure fair usage. The framework includes built-in rate limit handling.

### Rate Limit Specifications

**Gamma API (Market Discovery)**
- **Rate Limit**: 60 requests per minute per IP
- **Burst**: Up to 10 requests in a single second
- **Headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

**CLOB API (Trading & Orderbook)**
- **Rate Limit**: 120 requests per minute per authenticated user
- **Burst**: Up to 20 requests in a single second
- **Headers**: Same as Gamma API

**Data API (Positions & History)**
- **Rate Limit**: 30 requests per minute per authenticated user
- **Burst**: Up to 5 requests in a single second

### Handling Rate Limits

The framework automatically handles rate limits with:
- Automatic request queuing
- Exponential backoff on 429 (Too Many Requests) errors
- Configurable delays between requests (default: 100ms)

```python
from polymarket.utils.config import Config

# Configure request delay
Config.REQUEST_DELAY = 0.2  # 200ms between requests
Config.MAX_REQUESTS_PER_MINUTE = 60
```

### Rate Limit Errors

When rate limited, the API returns:
- **Status Code**: 429 Too Many Requests
- **Response Body**: `{"error": "Rate limit exceeded", "retry_after": 60}`
- **Headers**: `Retry-After: 60` (seconds to wait)

The framework will automatically retry after the specified delay.

## Gamma API Client

### Class: `GammaClient`

Client for Polymarket Gamma API - Market discovery and metadata.

#### Constructor

```python
GammaClient(timeout: int = 30)
```

**Parameters:**
- `timeout` (int): Request timeout in seconds (default: 30)

#### Methods

##### `get_events()`

Fetch active events/markets.

```python
get_events(
    active: bool = True,
    closed: bool = False,
    limit: int = 100,
    tag_id: Optional[int] = None,
    series_id: Optional[int] = None,
    order: Optional[str] = None,
    ascending: bool = True
) -> List[Dict]
```

**Parameters:**
- `active` (bool): Filter for active events (default: True)
- `closed` (bool): Filter for closed events (default: False)
- `limit` (int): Maximum number of results (default: 100, max: 1000)
- `tag_id` (Optional[int]): Filter by tag/category ID
- `series_id` (Optional[int]): Filter by series ID (for sports)
- `order` (Optional[str]): Sort order (e.g., 'startTime', 'volume')
- `ascending` (bool): Sort ascending or descending (default: True)

**Returns:**
- `List[Dict]`: List of event dictionaries with fields:
  - `id`: Event ID
  - `title`: Event title
  - `slug`: Event slug (URL-friendly identifier)
  - `description`: Event description
  - `startDate`: Start date (ISO 8601)
  - `endDate`: End date (ISO 8601)
  - `markets`: List of markets in this event
  - `tags`: List of tag IDs

**Example:**
```python
from polymarket import GammaClient

gamma = GammaClient()
events = gamma.get_events(active=True, limit=10, tag_id=21)  # Get 10 active crypto events
```

##### `get_event_by_slug()`

Get event details by slug.

```python
get_event_by_slug(slug: str) -> Optional[Dict]
```

**Parameters:**
- `slug` (str): Event slug (e.g., 'will-bitcoin-reach-100k-by-2025')

**Returns:**
- `Optional[Dict]`: Event dictionary or None if not found

**Example:**
```python
event = gamma.get_event_by_slug('will-bitcoin-reach-100k-by-2025')
```

##### `get_market_by_slug()`

Get market details by slug.

```python
get_market_by_slug(slug: str) -> Optional[Dict]
```

**Parameters:**
- `slug` (str): Market slug

**Returns:**
- `Optional[Dict]`: Market dictionary with:
  - `clobTokenIds`: List of CLOB token IDs for Yes/No outcomes
  - `outcomes`: JSON string of outcome names (e.g., '["Yes", "No"]')
  - `outcomePrices`: JSON string of current prices (e.g., '[0.65, 0.35]')
  - `question`: Market question
  - `endDate`: Market end date

**Example:**
```python
market = gamma.get_market_by_slug('bitcoin-100k-2025')
prices = gamma.get_market_prices(market)
print(f"Yes: {prices['Yes']:.2%}, No: {prices['No']:.2%}")
```

##### `get_tags()`

Get all available tags/categories.

```python
get_tags(limit: int = 100) -> List[Dict]
```

**Returns:**
- `List[Dict]`: List of tag dictionaries with `id` and `name` fields

**Example:**
```python
tags = gamma.get_tags()
for tag in tags:
    print(f"{tag['id']}: {tag['name']}")
```

##### `get_sports()`

Get all supported sports leagues.

```python
get_sports() -> List[Dict]
```

**Returns:**
- `List[Dict]`: List of sports league dictionaries

##### `get_market_prices()`

Extract current prices from market data.

```python
get_market_prices(market: Dict) -> Dict[str, float]
```

**Parameters:**
- `market` (Dict): Market dictionary with outcomes and outcomePrices

**Returns:**
- `Dict[str, float]`: Dictionary mapping outcome to price (probability)

**Example:**
```python
prices = gamma.get_market_prices(market)
yes_prob = prices['Yes']  # 0.65 = 65% probability
```

## CLOB API Client

### Class: `ClobClient`

Client for Polymarket CLOB API - Trading and orderbook data.

#### Methods

##### `get_price()`

Get current price for a token.

```python
get_price(token_id: str, side: str = 'buy') -> float
```

**Parameters:**
- `token_id` (str): CLOB token ID
- `side` (str): 'buy' or 'sell' (default: 'buy')

**Returns:**
- `float`: Current price (0.0 to 1.0)

**Example:**
```python
from polymarket import ClobClient

clob = ClobClient()
token_id = market['clobTokenIds'][0]
price = clob.get_price(token_id, side='buy')
```

##### `get_orderbook()`

Get orderbook depth for a token.

```python
get_orderbook(token_id: str) -> Dict
```

**Returns:**
- `Dict`: Dictionary with:
  - `bids`: List of bid orders `[{"price": float, "size": float}, ...]`
  - `asks`: List of ask orders `[{"price": float, "size": float}, ...]`

**Example:**
```python
book = clob.get_orderbook(token_id)
best_bid = book['bids'][0]['price']
best_ask = book['asks'][0]['price']
```

##### `get_best_bid_ask()`

Get best bid and ask prices.

```python
get_best_bid_ask(token_id: str) -> Dict[str, float]
```

**Returns:**
- `Dict[str, float]`: Dictionary with:
  - `bid`: Best bid price
  - `ask`: Best ask price
  - `spread`: Bid-ask spread
  - `mid`: Mid price ((bid + ask) / 2)

##### `get_market_depth()`

Get market depth up to specified levels.

```python
get_market_depth(token_id: str, levels: int = 10) -> Dict
```

**Returns:**
- `Dict`: Dictionary with:
  - `bids`: Top N bid levels
  - `asks`: Top N ask levels
  - `bid_depth`: Cumulative bid depth
  - `ask_depth`: Cumulative ask depth
  - `total_depth`: Total market depth

##### `calculate_impact()`

Calculate estimated price impact for a trade size.

```python
calculate_impact(token_id: str, size: float, side: str) -> Dict
```

**Parameters:**
- `token_id` (str): CLOB token ID
- `size` (float): Trade size in tokens
- `side` (str): 'buy' or 'sell'

**Returns:**
- `Dict`: Dictionary with:
  - `average_price`: Average execution price
  - `best_price`: Best available price
  - `price_impact`: Price impact percentage
  - `levels_consumed`: Number of orderbook levels consumed
  - `slippage`: Price slippage

**Example:**
```python
impact = clob.calculate_impact(token_id, size=100, side='buy')
print(f"Price impact: {impact['price_impact']:.2%}")
print(f"Average price: {impact['average_price']:.4f}")
```

## Data API Client

### Class: `DataClient`

Client for Polymarket Data API - Positions and history.

#### Constructor

```python
DataClient(api_key: Optional[str] = None, timeout: int = 30)
```

**Parameters:**
- `api_key` (Optional[str]): API key for authenticated requests
- `timeout` (int): Request timeout in seconds

#### Methods

##### `get_positions()`

Get user positions.

```python
get_positions(user_address: str) -> List[Dict]
```

**Parameters:**
- `user_address` (str): User wallet address (0x...)

**Returns:**
- `List[Dict]`: List of position dictionaries

##### `get_trades()`

Get user trade history.

```python
get_trades(user_address: str, limit: int = 100) -> List[Dict]
```

**Parameters:**
- `user_address` (str): User wallet address
- `limit` (int): Maximum number of trades (default: 100)

**Returns:**
- `List[Dict]`: List of trade dictionaries

##### `get_portfolio()`

Get user portfolio summary.

```python
get_portfolio(user_address: str) -> Dict
```

**Returns:**
- `Dict`: Portfolio dictionary with balances, positions, etc.

## Base Strategy

### Class: `BaseStrategy`

Base class for all Polymarket trading strategies.

#### Constructor

```python
BaseStrategy(name: str, initial_balance: float = 1000.0)
```

#### Abstract Methods

##### `analyze_market()`

Analyze market and generate trading signal.

```python
@abstractmethod
def analyze_market(self, market_data: Dict) -> Optional[MarketSignal]:
    """
    Args:
        market_data: Dictionary containing:
            - 'event': Event information
            - 'market': Market information
            - 'prices': Current outcome prices
            - 'orderbook': Orderbook data
            - 'history': Historical price data (if available)
    
    Returns:
        MarketSignal or None if no trade
    """
```

##### `get_parameters()`

Return strategy parameters.

```python
@abstractmethod
def get_parameters(self) -> Dict[str, Any]:
    """Returns: Dictionary of parameter names and values"""
```

#### Properties

- `name`: Strategy name
- `initial_balance`: Starting USDC balance
- `current_balance`: Current USDC balance
- `equity`: Current equity (balance + unrealized PnL)
- `positions`: Dictionary of open positions (token_id -> Position)
- `total_trades`: Total number of trades executed
- `winning_trades`: Number of winning trades
- `losing_trades`: Number of losing trades
- `max_drawdown`: Maximum drawdown (0.0 to 1.0)

#### Methods

##### `update_position()`

Update position with current price.

```python
update_position(token_id: str, current_price: float) -> None
```

##### `calculate_equity()`

Calculate current equity (balance + unrealized PnL).

```python
calculate_equity(self) -> float
```

##### `can_open_position()`

Check if strategy can open a new position.

```python
can_open_position(self, size: float, token_id: str) -> bool
```

##### `get_performance_metrics()`

Get current performance metrics.

```python
get_performance_metrics(self) -> Dict[str, Any]
```

**Returns:**
- Dictionary with: `total_trades`, `winning_trades`, `losing_trades`, `win_rate`, `total_profit`, `total_loss`, `net_profit`, `profit_factor`, `max_drawdown`, `current_balance`, `equity`, `unrealized_pnl`, `open_positions`

## Backtesting Engine

### Class: `BacktestEngine`

Main backtesting engine for Polymarket strategies.

#### Constructor

```python
BacktestEngine(
    strategy: BaseStrategy,
    start_date: datetime,
    end_date: datetime,
    initial_balance: float = 1000.0
)
```

#### Methods

##### `run()`

Run the backtest.

```python
run(self, markets: Optional[List[Dict]] = None) -> Dict[str, Any]
```

**Returns:**
- Dictionary with backtest results including:
  - `total_return`: Total return percentage
  - `total_trades`: Number of trades
  - `win_rate`: Win rate percentage
  - `sharpe_ratio`: Sharpe ratio
  - `max_drawdown`: Maximum drawdown percentage
  - `equity_curve`: List of equity values over time
  - `trades`: List of all trades executed

##### `generate_report()`

Generate backtest report.

```python
generate_report(self, output_file: Optional[str] = None) -> None
```

## Live Trading Engine

### Class: `LiveTradingEngine`

Live trading engine for Polymarket.

#### Constructor

```python
LiveTradingEngine(
    strategy: BaseStrategy,
    poll_interval: int = 60
)
```

**Parameters:**
- `strategy`: Strategy instance to trade
- `poll_interval`: Seconds between market checks (default: 60)

#### Methods

##### `add_market()`

Add a market to monitor.

```python
add_market(
    event_slug: Optional[str] = None,
    market_slug: Optional[str] = None
) -> None
```

##### `monitor_tag()`

Monitor all active markets in a tag/category.

```python
monitor_tag(self, tag_id: int, limit: int = 20) -> None
```

##### `start()`

Start the live trading engine.

```python
start(self) -> None
```

##### `stop()`

Stop the trading engine.

```python
stop(self) -> None
```

## Error Handling

### Common Errors

#### `ConnectionError`
- **Cause**: Network connectivity issues
- **Solution**: Check internet connection, retry with exponential backoff

#### `TimeoutError`
- **Cause**: Request timeout exceeded
- **Solution**: Increase timeout value or check API status

#### `RateLimitError`
- **Cause**: Rate limit exceeded
- **Solution**: Framework automatically handles with retry logic

#### `AuthenticationError`
- **Cause**: Invalid API credentials
- **Solution**: Verify API keys and wallet address in `.env` file

#### `MarketNotFoundError`
- **Cause**: Market slug or ID not found
- **Solution**: Verify market exists and is active

### Error Response Format

All API errors return JSON:

```json
{
  "error": "Error message",
  "code": "ERROR_CODE",
  "details": {}
}
```

### Retry Logic

The framework implements automatic retry for:
- Network errors (up to 3 retries)
- Rate limit errors (with exponential backoff)
- 5xx server errors (up to 3 retries)

No retry for:
- 4xx client errors (except 429)
- Authentication errors
- Validation errors
