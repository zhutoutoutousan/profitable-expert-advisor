# Polymarket Automatic Backtesting and Trading Framework

A comprehensive Python framework for backtesting and live trading on Polymarket prediction markets.

## Features

- **API Integration**: Full integration with Polymarket Gamma API, CLOB API, and Data API
- **Backtesting Engine**: Historical data backtesting with realistic order execution
- **Live Trading**: Real-time order placement and position management
- **Strategy Framework**: Easy-to-use base class for developing prediction market strategies
- **Performance Analytics**: Comprehensive metrics and visualization
- **Market Data**: Real-time and historical market data fetching
- **Position Management**: Automatic position tracking and risk management

## Installation

```bash
pip install -r requirements.txt
```

Required packages:
- `requests` - API communication
- `pandas` - Data manipulation
- `numpy` - Numerical operations
- `python-dotenv` - Environment variable management
- `websocket-client` - Real-time data streaming (optional)

## Quick Start

### 1. Setup API Credentials

Create a `.env` file:

```env
POLYMARKET_PRIVATE_KEY=your_private_key_here
POLYMARKET_CHAIN_ID=137  # Polygon mainnet
POLYMARKET_SIGNATURE_TYPE=0  # 0=EOA, 1=POLY_PROXY, 2=GNOSIS_SAFE
POLYMARKET_FUNDER_ADDRESS=your_wallet_address
```

### 2. Run a Backtest

```python
from polymarket import BacktestEngine
from strategies import SimpleProbabilityStrategy

strategy = SimpleProbabilityStrategy()
engine = BacktestEngine(strategy, start_date="2024-01-01", end_date="2024-12-31")
results = engine.run()
engine.generate_report()
```

### 3. Live Trading

```python
from polymarket import LiveTradingEngine
from strategies import SimpleProbabilityStrategy

strategy = SimpleProbabilityStrategy()
engine = LiveTradingEngine(strategy)
engine.start()
```

## Architecture

```
polymarket/
├── api/              # API client wrappers
│   ├── gamma_client.py      # Market discovery & metadata
│   ├── clob_client.py        # Order placement & orderbook
│   └── data_client.py        # Positions & history
├── strategies/       # Trading strategies
│   ├── base_strategy.py      # Base class for all strategies
│   └── examples/             # Example strategies
├── backtesting/     # Backtesting engine
│   ├── engine.py            # Main backtesting engine
│   └── data_loader.py       # Historical data loading
├── trading/         # Live trading
│   ├── engine.py            # Live trading engine
│   └── position_manager.py  # Position tracking
├── analytics/       # Performance analysis
│   ├── metrics.py           # Performance metrics
│   └── visualization.py     # Charts and reports
└── utils/          # Utilities
    ├── config.py           # Configuration management
    └── logger.py           # Logging utilities
```

## Documentation

### Getting Started
- [Quick Start Guide](docs/QUICKSTART.md) - Get started in minutes
- [Example Usage](example_usage.py) - Complete code examples

### Core Documentation
- [API Reference](docs/API_REFERENCE.md) - Complete API documentation with rate limits, endpoints, and error handling
- [Strategy Development Guide](docs/STRATEGY_GUIDE.md) - How to create and test trading strategies
- [Glossary](docs/GLOSSARY.md) - Complete terminology reference

### Framework Details
- [Implementation Notes](IMPLEMENTATION_NOTES.md) - Framework details, limitations, and next steps

## API Documentation References

This framework is built based on Polymarket's official API documentation:
- [Polymarket Developer Docs](https://docs.polymarket.com/quickstart/overview)
- [Fetching Market Data](https://docs.polymarket.com/quickstart/fetching-data)
- [Placing Orders](https://docs.polymarket.com/quickstart/first-order)

## Disclaimer

This framework is for educational and research purposes. Trading prediction markets involves financial risk. Always test strategies thoroughly in backtesting before live trading.
