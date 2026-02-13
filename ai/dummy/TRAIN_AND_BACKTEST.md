# XAUUSD ONNX Model Training and Backtesting Guide

This guide will help you train an ONNX model for XAUUSD and backtest it.

## Step 1: Install Dependencies

Make sure you have all required packages installed:

```bash
cd ai
pip install -r requirements.txt
```

If you encounter issues, install individually:
```bash
pip install tensorflow onnx onnxruntime tf2onnx scikit-learn pandas numpy MetaTrader5
```

## Step 2: Train the Model

Train an ONNX model for XAUUSD:

```bash
python train_onnx_model.py --symbol XAUUSD --timeframe H1 --lookback 60 --epochs 30
```

**Parameters:**
- `--symbol XAUUSD`: Trading symbol (Gold)
- `--timeframe H1`: 1-hour timeframe
- `--lookback 60`: Use 60 bars for prediction
- `--epochs 30`: Training epochs (adjust based on your needs)

**Expected Output:**
- Model: `models/XAUUSD_H1_model.onnx`
- Scaler: `models/XAUUSD_H1_scaler.pkl`

**Training Time:** 5-15 minutes depending on your hardware and data availability.

## Step 3: Run Backtest

After training, backtest the model:

```bash
python run_xauusd_backtest.py
```

Or use the combined script:

```bash
python train_and_backtest_xauusd.py
```

## Step 4: Review Results

The backtest will generate:
- Performance summary in console
- Equity curve chart
- Drawdown chart
- Monthly returns chart
- Trades CSV file

All files are saved in `onnx_xauusd_backtest/` directory.

## Model Configuration

The trained model uses:
- **Input**: 60 bars × 12 features
- **Features**: OHLC, volume, RSI, EMA, ATR, price changes, ratios
- **Output**: Predicted next close price
- **Architecture**: LSTM(128) → LSTM(64) → LSTM(32) → Dense layers

## Backtest Strategy Parameters

Default backtest parameters:
- **Prediction Threshold**: 0.01% (minimum price change to trade)
- **Min Confidence**: 30%
- **Lot Size**: 0.1
- **Stop Loss**: 50 pips
- **Take Profit**: 100 pips

You can adjust these in `run_xauusd_backtest.py`.

## Troubleshooting

### "Model not found"
- Make sure you've trained the model first
- Check that the model file exists in `models/` directory

### "MT5 initialization failed"
- Ensure MetaTrader 5 is running
- Log into your account
- Check that XAUUSD symbol is available

### "Insufficient data"
- Make sure you have historical data downloaded in MT5
- Check the date range in the backtest script
- Verify symbol name is correct

## Next Steps

After successful backtesting:
1. Review performance metrics
2. Optimize prediction threshold and confidence levels
3. Adjust stop loss/take profit if needed
4. Test on demo account before live trading
5. Consider using the model in `ONNX_EA.mq5` for live trading

## Files Created

- `models/XAUUSD_H1_model.onnx`: Trained ONNX model
- `models/XAUUSD_H1_scaler.pkl`: Feature scaler for normalization
- `onnx_xauusd_backtest/`: Backtest results directory
