# MetaTrader5 Python Backtesting Framework

A comprehensive Python backtesting framework for algorithmic trading strategies using MetaTrader5 historical data.

## Features

- **Easy Strategy Development**: Inherit from `BaseStrategy` and implement your trading logic
- **MT5 Integration**: Uses MetaTrader5 Python library for historical data and indicators
- **Multiple Indicators**: Built-in support for RSI, EMA, SMA, ATR, MACD, and more
- **Risk Management**: Built-in position sizing, stop loss, take profit, and drawdown protection
- **Performance Analysis**: Comprehensive metrics and visualization tools
- **Example Strategies**: Ready-to-use example strategies (RSI Scalping, EMA Crossover, RSI Reversal)

## Installation

1. **Install MetaTrader5**: Make sure you have MetaTrader5 installed on your system.

2. **Install Python dependencies**:
```bash
pip install -r requirements.txt
```

3. **Initialize MT5 Connection**: The framework will automatically connect to MT5 when you run a backtest. Make sure MT5 is installed and you have a demo or live account configured.

## Quick Start

### Running a Backtest

Use the command-line interface to run a backtest:

```bash
python run_backtest.py --strategy RSIReversalStrategy --symbol XAUUSD --start 2023-01-01 --end 2024-01-01
```

### Creating Your Own Strategy

1. Create a new Python file or add to `example_strategies.py`:

```python
from base_strategy import BaseStrategy
import MetaTrader5 as mt5

class MyStrategy(BaseStrategy):
    def __init__(self, symbol, timeframe, initial_balance=10000.0):
        super().__init__(symbol, timeframe, initial_balance)
        # Initialize your strategy parameters
        self.my_param = 42
    
    def get_required_indicators(self):
        return {
            'rsi': {'period': 14, 'applied_price': mt5.PRICE_CLOSE},
            'ema': {'period': 50, 'applied_price': mt5.PRICE_CLOSE}
        }
    
    def on_bar(self, bar_data):
        # Your trading logic here
        rsi = bar_data.get('rsi')
        ema = bar_data.get('ema')
        current_price = bar_data['close']
        
        # Example: Buy when RSI < 30 and price > EMA
        if rsi < 30 and current_price > ema:
            if self.position is None:
                self.open_position('BUY', 0.1, current_price)
    
    def get_parameters(self):
        return {'my_param': self.my_param}
```

2. Run your strategy:

```python
from datetime import datetime
from backtest_engine import BacktestEngine
from performance_analyzer import PerformanceAnalyzer

# Create strategy
strategy = MyStrategy('XAUUSD', mt5.TIMEFRAME_H1, initial_balance=10000.0)

# Run backtest
engine = BacktestEngine(
    strategy,
    start_date=datetime(2023, 1, 1),
    end_date=datetime(2024, 1, 1)
)

results = engine.run()

# Analyze results
analyzer = PerformanceAnalyzer(results)
analyzer.generate_report('my_backtest_results')
```

## Available Strategies

### RSIScalpingStrategy
RSI-based scalping strategy that enters on RSI crossovers.

**Parameters:**
- `rsi_period`: RSI period (default: 14)
- `rsi_overbought`: Overbought level (default: 70)
- `rsi_oversold`: Oversold level (default: 30)
- `rsi_target_buy`: Exit target for long positions (default: 80)
- `rsi_target_sell`: Exit target for short positions (default: 20)

### EMAStrategy
Simple EMA crossover strategy.

**Parameters:**
- `ema_period`: EMA period (default: 50)

### RSIReversalStrategy
RSI reversal strategy similar to your MQL5 implementations.

**Parameters:**
- `rsi_period`: RSI period (default: 14)
- `rsi_overbought`: Overbought level (default: 70)
- `rsi_oversold`: Oversold level (default: 30)
- `rsi_exit`: Neutral exit level (default: 50)

## Command Line Options

```bash
python run_backtest.py --help
```

**Required Arguments:**
- `--strategy`: Strategy name (RSIScalpingStrategy, EMAStrategy, RSIReversalStrategy)
- `--start`: Start date (YYYY-MM-DD)
- `--end`: End date (YYYY-MM-DD)

**Optional Arguments:**
- `--symbol`: Trading symbol (default: XAUUSD)
- `--timeframe`: Timeframe M1, M5, M15, M30, H1, H4, D1 (default: H1)
- `--balance`: Initial balance (default: 10000)
- `--output`: Output directory (default: backtest_results)
- `--rsi-period`: RSI period (default: 14)
- `--rsi-overbought`: RSI overbought level (default: 70)
- `--rsi-oversold`: RSI oversold level (default: 30)
- `--ema-period`: EMA period (default: 50)
- `--lot-size`: Lot size (default: 0.1)
- `--stop-loss`: Stop loss in pips (default: 50)
- `--take-profit`: Take profit in pips (default: 100)

## Example Commands

```bash
# RSI Scalping on Gold, 1-hour timeframe
python run_backtest.py --strategy RSIScalpingStrategy --symbol XAUUSD --timeframe H1 --start 2023-01-01 --end 2024-01-01

# EMA Strategy on EUR/USD, 4-hour timeframe
python run_backtest.py --strategy EMAStrategy --symbol EURUSD --timeframe H4 --start 2023-01-01 --end 2024-01-01 --ema-period 100

# RSI Reversal with custom parameters
python run_backtest.py --strategy RSIReversalStrategy --symbol XAUUSD --start 2023-01-01 --end 2024-01-01 --rsi-period 28 --rsi-overbought 64 --rsi-oversold 13
```

## Output

The backtest generates:

1. **Console Summary**: Performance metrics printed to console
2. **Equity Curve Chart**: Visual representation of account balance over time
3. **Drawdown Chart**: Drawdown visualization
4. **Monthly Returns Chart**: Monthly performance breakdown
5. **Trades CSV**: Detailed trade log in CSV format

All files are saved in the specified output directory (default: `backtest_results/`).

## Performance Metrics

The framework calculates:

- **Total Return**: Percentage return on initial balance
- **Win Rate**: Percentage of winning trades
- **Profit Factor**: Total profit / Total loss
- **Average Win/Loss**: Average profit per winning/losing trade
- **Maximum Drawdown**: Largest peak-to-trough decline
- **Total Trades**: Number of completed trades

## BaseStrategy API

### Methods to Override

- `on_bar(bar_data)`: Called on each new bar with market data and indicators
- `get_parameters()`: Return strategy parameters for logging
- `get_required_indicators()`: Specify which indicators are needed

### Available Methods

- `open_position(order_type, volume, price, sl=None, tp=None, comment="")`: Open a position
- `close_position(close_price)`: Close current position
- `check_stop_loss_take_profit(current_price)`: Check SL/TP (called automatically)
- `get_performance_metrics()`: Get performance statistics

### Bar Data Structure

The `bar_data` dictionary passed to `on_bar()` contains:

```python
{
    'time': datetime,           # Bar timestamp
    'open': float,              # Opening price
    'high': float,              # High price
    'low': float,               # Low price
    'close': float,             # Closing price
    'tick_volume': int,         # Tick volume
    'spread': int,              # Spread in points
    'rsi': float,              # RSI value (if requested)
    'ema': float,              # EMA value (if requested)
    'indicators': {             # All requested indicators
        'rsi': float,
        'ema': float,
        ...
    }
}
```

## Supported Indicators

- **RSI**: Relative Strength Index
- **EMA**: Exponential Moving Average
- **SMA**: Simple Moving Average
- **ATR**: Average True Range
- **MACD**: Moving Average Convergence Divergence

To add more indicators, modify `BacktestEngine.setup_indicators()`.

## Risk Management

The framework includes built-in risk management:

- **Position Sizing**: Configurable min/max lot sizes
- **Stop Loss/Take Profit**: Automatic SL/TP checking
- **Spread Filtering**: Skip trades when spread is too high
- **Drawdown Protection**: Track and limit maximum drawdown
- **Margin Management**: Prevent over-leveraging

## Tips

1. **Test on Demo First**: Always test strategies on demo accounts before live trading
2. **Start Small**: Begin with small position sizes and gradually increase
3. **Multiple Timeframes**: Test strategies on different timeframes
4. **Parameter Optimization**: Use the framework to optimize strategy parameters
5. **Compare Strategies**: Run multiple strategies and compare results

## Troubleshooting

### MT5 Connection Issues
- Ensure MetaTrader5 is installed and running
- Check that you have a demo or live account configured
- Verify symbol names match MT5 format (e.g., 'XAUUSD' not 'GOLD')

### No Data Available
- Check date range - ensure data exists for the specified period
- Verify symbol name is correct
- Check that MT5 has historical data for the symbol/timeframe

### Indicator Errors
- Ensure indicator parameters are valid
- Check that enough bars are available for indicator calculation
- Verify indicator handle creation succeeded

## Contributing

Feel free to extend this framework with:
- Additional indicators
- More sophisticated risk management
- Optimization tools
- Walk-forward analysis
- Monte Carlo simulation

## License

This framework is provided for educational and research purposes.

## Disclaimer

Trading involves substantial risk of loss. This framework is provided for educational purposes only. Always test thoroughly on a demo account before using with real money. Past performance does not guarantee future results.
