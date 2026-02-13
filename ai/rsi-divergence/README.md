# RSI Divergence ONNX Trading System for BTCUSD

A complete AI-powered trading system that uses machine learning to identify genuine RSI (Relative Strength Index) divergences and execute trades on MetaTrader 5.

## Overview

This system trains a neural network to classify RSI divergences into 5 categories:
- **NONE** (0): No divergence detected
- **REGULAR_BULLISH** (1): Price makes lower low, RSI makes higher low (reversal signal)
- **REGULAR_BEARISH** (2): Price makes higher high, RSI makes lower high (reversal signal)
- **HIDDEN_BULLISH** (3): Price makes higher low, RSI makes lower low (continuation signal)
- **HIDDEN_BEARISH** (4): Price makes lower high, RSI makes higher high (continuation signal)

The trained model is exported to ONNX format and used in a MetaTrader 5 Expert Advisor for live trading.

## Features

- **Advanced Divergence Detection**: Identifies both regular and hidden RSI divergences
- **Machine Learning Classification**: Uses LSTM neural network to learn genuine divergence patterns
- **ONNX Integration**: Model runs efficiently in MetaTrader 5 using ONNX Runtime
- **Comprehensive Backtesting**: Test model performance on historical data
- **Risk Management**: Built-in stop loss, take profit, trailing stop, and position time limits

## Project Structure

```
ai/rsi-divergence/
├── rsi_divergence_detector.py    # Core divergence detection module
├── collect_btcusd_data.py        # Data collection and labeling script
├── train_onnx_model.py           # Model training script
├── backtest_model.py              # Backtesting script
├── RSIDivergence_EA.mq5          # MetaTrader 5 Expert Advisor
├── requirements.txt               # Python dependencies
└── README.md                      # This file
```

## Installation

### 1. Install Python Dependencies

```bash
cd ai/rsi-divergence
pip install -r requirements.txt
```

### 2. Setup MetaTrader 5

1. Install MetaTrader 5
2. Enable automated trading in MT5 settings
3. Copy `RSIDivergence_EA.mq5` to `MT5_Data_Folder/MQL5/Experts/`
4. Compile the EA in MetaEditor

## Usage

### Step 1: Collect and Label Data

Collect BTCUSD historical data and label it with RSI divergence signals:

```bash
python collect_btcusd_data.py \
    --symbol BTCUSD \
    --timeframe H1 \
    --days 365 \
    --rsi-period 14 \
    --output data \
    --min-strength 0.15
```

This will:
- Fetch BTCUSD data from MetaTrader 5
- Calculate RSI and other technical indicators
- Detect and label RSI divergences
- Save labeled data to `data/BTCUSD_H1_labeled.csv`

### Step 2: Train the Model

Train the neural network to classify divergences:

```bash
python train_onnx_model.py \
    --data data/BTCUSD_H1_labeled.csv \
    --lookback 60 \
    --epochs 50 \
    --batch-size 32 \
    --output models
```

This will:
- Load labeled data
- Train an LSTM-based classification model
- Export model to ONNX format
- Save scaler and feature list for inference

Output files:
- `models/BTCUSD_H1_rsi_divergence_model.onnx` - ONNX model
- `models/BTCUSD_H1_rsi_divergence_scaler.pkl` - Feature scaler
- `models/BTCUSD_H1_rsi_divergence_features.pkl` - Feature list

### Step 3: Backtest the Model

Test the trained model on historical data:

```bash
python backtest_model.py \
    --model models/BTCUSD_H1_rsi_divergence_model.onnx \
    --scaler models/BTCUSD_H1_rsi_divergence_scaler.pkl \
    --features models/BTCUSD_H1_rsi_divergence_features.pkl \
    --symbol BTCUSD \
    --timeframe H1 \
    --days 90 \
    --balance 10000 \
    --lot-size 0.01 \
    --min-confidence 0.7
```

This will:
- Load the trained model
- Run backtest on historical data
- Generate performance metrics
- Save trade history to CSV

### Step 4: Deploy to MetaTrader 5

1. **Copy Model Files**:
   - Copy `BTCUSD_H1_rsi_divergence_model.onnx` to `MT5_Data_Folder/MQL5/Files/models/`
   - Create the `models` folder if it doesn't exist

2. **Attach EA to Chart**:
   - Open BTCUSD chart in MT5
   - Drag `RSIDivergence_EA` from Navigator to chart
   - Configure parameters:
     - `InpModelPath`: Path to ONNX model (e.g., `models\\BTCUSD_H1_rsi_divergence_model.onnx`)
     - `InpMinConfidence`: Minimum confidence threshold (0.7 recommended)
     - `InpLotSize`: Position size
     - `InpStopLoss`: Stop loss in pips
     - `InpTakeProfit`: Take profit in pips

3. **Enable AutoTrading**:
   - Click "AutoTrading" button in MT5 toolbar
   - EA will start analyzing and trading automatically

## Parameters

### Data Collection Parameters

- `--symbol`: Trading symbol (default: BTCUSD)
- `--timeframe`: Timeframe (M1, M5, M15, M30, H1, H4, D1)
- `--days`: Number of days of historical data
- `--rsi-period`: RSI calculation period (default: 14)
- `--min-strength`: Minimum divergence strength (0-1)

### Training Parameters

- `--data`: Path to labeled CSV file
- `--lookback`: Number of bars to look back (default: 60)
- `--epochs`: Training epochs (default: 50)
- `--batch-size`: Batch size (default: 32)

### EA Parameters

**ONNX Model Settings**:
- `InpModelPath`: Path to ONNX model file
- `InpLookback`: Lookback period (must match training)
- `InpMinConfidence`: Minimum confidence to trade (0-1)

**Trading Settings**:
- `InpLotSize`: Position size
- `InpMagicNumber`: Unique identifier for EA trades
- `InpStopLoss`: Stop loss in pips (0 = disabled)
- `InpTakeProfit`: Take profit in pips (0 = disabled)
- `InpMaxBarsInTrade`: Maximum bars to hold position (0 = disabled)

**Divergence Filter**:
- `InpUseRegularBullish`: Enable regular bullish divergence trades
- `InpUseRegularBearish`: Enable regular bearish divergence trades
- `InpUseHiddenBullish`: Enable hidden bullish divergence trades
- `InpUseHiddenBearish`: Enable hidden bearish divergence trades

**Risk Management**:
- `InpUseTrailingStop`: Enable trailing stop
- `InpTrailingStopPips`: Trailing stop distance in pips
- `InpTrailingStepPips`: Trailing stop step in pips

## Understanding RSI Divergences

### Regular Divergences (Reversal Signals)

- **Bullish**: Price makes lower low, RSI makes higher low → Potential upward reversal
- **Bearish**: Price makes higher high, RSI makes lower high → Potential downward reversal

### Hidden Divergences (Continuation Signals)

- **Bullish**: Price makes higher low, RSI makes lower low → Trend continuation upward
- **Bearish**: Price makes lower high, RSI makes higher high → Trend continuation downward

## Performance Optimization

1. **Data Quality**: Use more historical data (1-2 years) for better training
2. **Feature Engineering**: Experiment with additional technical indicators
3. **Model Tuning**: Adjust LSTM architecture, dropout rates, learning rate
4. **Confidence Threshold**: Higher threshold = fewer but higher quality trades
5. **Risk Management**: Always use stop loss and position sizing

## Troubleshooting

### Model Not Loading in MT5

- Check model file path is correct
- Ensure model file is in `MQL5/Files/models/` folder
- Verify ONNX model version compatibility (opset 13)

### No Trades Executed

- Check confidence threshold (try lowering `InpMinConfidence`)
- Verify divergence types are enabled
- Check that sufficient historical data is available

### Poor Backtest Results

- Collect more training data
- Adjust divergence detection parameters
- Retrain with different model architecture
- Test on different timeframes

## Notes

- **Model Compatibility**: ONNX model uses opset 13 for MT5 compatibility
- **Feature Normalization**: Features are normalized using MinMaxScaler - ensure same normalization in EA
- **Timeframe**: Model trained on H1 timeframe - retrain for other timeframes
- **Symbol**: Model trained on BTCUSD - retrain for other symbols

## License

This project is provided as-is for educational and research purposes.

## References

- [MetaTrader 5 ONNX Documentation](https://www.mql5.com/en/docs/onnx/onnx_prepare)
- [RSI Divergence Trading Strategies](https://www.investopedia.com/trading/using-relative-strength-index-rsi/)
- [ONNX Runtime](https://onnxruntime.ai/)
