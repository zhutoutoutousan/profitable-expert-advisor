# Quick Start Guide

Get up and running with the MT5 Python backtesting framework in 5 minutes!

## Step 1: Install Dependencies

```bash
cd backtesting/MT5
pip install -r requirements.txt
```

## Step 2: Test Your Setup

Before running backtests, verify that MT5 is properly configured:

```bash
python test_setup.py
```

This will:
- Test MT5 connection
- Check account access
- Verify symbol availability
- Test historical data retrieval
- Test indicator creation

**If this fails**, make sure:
1. MetaTrader5 is installed
2. MT5 is running
3. You're logged into a demo or live account
4. You have historical data downloaded in MT5

## Step 3: Run Your First Backtest

### Option A: Command Line (Easiest)

```bash
python run_backtest.py --strategy RSIReversalStrategy --symbol XAUUSD --start 2023-01-01 --end 2024-01-01
```

This will:
- Run the RSI Reversal strategy on Gold (XAUUSD)
- Backtest from Jan 1, 2023 to Jan 1, 2024
- Generate performance reports in `backtest_results/`

### Option B: Python Script

```python
from datetime import datetime
import MetaTrader5 as mt5
from backtest_engine import BacktestEngine
from example_strategies import RSIReversalStrategy
from performance_analyzer import PerformanceAnalyzer

# Create strategy
strategy = RSIReversalStrategy(
    symbol='XAUUSD',
    timeframe=mt5.TIMEFRAME_H1,
    initial_balance=10000.0
)

# Run backtest
engine = BacktestEngine(
    strategy,
    start_date=datetime(2023, 1, 1),
    end_date=datetime(2024, 1, 1)
)

results = engine.run()

# View results
analyzer = PerformanceAnalyzer(results)
analyzer.generate_report('my_results')
```

## Step 4: Create Your Own Strategy

1. **Copy an example strategy** from `example_strategies.py`

2. **Modify the `on_bar()` method** with your trading logic:

```python
def on_bar(self, bar_data):
    rsi = bar_data.get('rsi')
    current_price = bar_data['close']
    
    # Your logic here
    if rsi < 30 and self.position is None:
        self.open_position('BUY', 0.1, current_price)
```

3. **Specify required indicators**:

```python
def get_required_indicators(self):
    return {
        'rsi': {'period': 14, 'applied_price': mt5.PRICE_CLOSE},
        'ema': {'period': 50, 'applied_price': mt5.PRICE_CLOSE}
    }
```

4. **Run your strategy**:

```python
from backtest_engine import BacktestEngine
# ... (same as above)
```

## Common Commands

### Different Symbols
```bash
python run_backtest.py --strategy RSIReversalStrategy --symbol EURUSD --start 2023-01-01 --end 2024-01-01
```

### Different Timeframes
```bash
python run_backtest.py --strategy RSIScalpingStrategy --symbol XAUUSD --timeframe M15 --start 2023-01-01 --end 2024-01-01
```

### Custom Parameters
```bash
python run_backtest.py --strategy RSIReversalStrategy --symbol XAUUSD --start 2023-01-01 --end 2024-01-01 --rsi-period 28 --rsi-overbought 64 --rsi-oversold 13 --lot-size 0.2
```

## Understanding the Output

After running a backtest, you'll get:

1. **Console Summary**: Key metrics printed to terminal
2. **Equity Curve**: `*_equity_curve.png` - Account balance over time
3. **Drawdown Chart**: `*_drawdown.png` - Drawdown visualization
4. **Monthly Returns**: `*_monthly_returns.png` - Monthly performance
5. **Trades CSV**: `*_trades.csv` - Detailed trade log

## Next Steps

- **Optimize Parameters**: Try different parameter combinations
- **Test Multiple Strategies**: Compare different approaches
- **Add More Indicators**: Extend `BacktestEngine.setup_indicators()`
- **Improve Risk Management**: Customize position sizing and risk rules

## Troubleshooting

### "MT5 initialization failed"
- Make sure MT5 is installed and running
- Try logging into MT5 manually first
- Check that you have a demo/live account configured

### "No data available"
- Check date range - ensure data exists
- Verify symbol name (e.g., 'XAUUSD' not 'GOLD')
- Download historical data in MT5 (Tools > History Center)

### "Failed to create indicator"
- Ensure enough bars are available (need more bars than indicator period)
- Check indicator parameters are valid

## Need Help?

- Check the main [README.md](README.md) for detailed documentation
- Review `example_strategies.py` for strategy examples
- Look at `example_usage.py` for more usage examples

Happy backtesting! 🚀
