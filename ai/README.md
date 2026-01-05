# ONNX Models with MetaTrader 5

A complete framework for training and using ONNX machine learning models in MetaTrader 5 for algorithmic trading.

Based on the [MQL5 ONNX documentation](https://www.mql5.com/en/docs/onnx/onnx_prepare).

## Overview

This framework allows you to:
1. **Train neural network models** in Python using MetaTrader 5 historical data
2. **Export models to ONNX format** for use in MQL5
3. **Use ONNX models in Expert Advisors** for real-time trading predictions
4. **Test predictions** using Python scripts

## Features

- 🧠 **LSTM Neural Networks** for price prediction
- 📊 **Technical Indicators** as features (RSI, EMA, ATR, etc.)
- 🔄 **ONNX Export** for MQL5 integration
- 📈 **Real-time Prediction** in Expert Advisors
- 🎯 **Flexible Configuration** for different symbols and timeframes

## Installation

### 1. Install Python Dependencies

```bash
cd ai
pip install -r requirements.txt
```

### 2. Install MetaTrader 5

- Download and install [MetaTrader 5](https://www.metatrader5.com/en/download)
- Create a demo or live account
- Enable Python integration in MT5 settings:
  - Tools → Options → Expert Advisors
  - Check "Allow DLL imports"
  - Check "Integration with Python" (if available)

### 3. Configure MetaEditor (Optional)

If you want to run Python scripts from MetaEditor:
- MetaEditor → Tools → Options → Compiler
- Set Python executable path
- Or click "Install" to download Python

## Quick Start

### Step 1: Train an ONNX Model

Train a model for price prediction:

```bash
python train_onnx_model.py --symbol XAUUSD --timeframe H1 --lookback 60 --epochs 50
```

This will:
- Fetch 2 years of historical data from MT5
- Prepare features (OHLCV + technical indicators)
- Train an LSTM neural network
- Export the model to `models/XAUUSD_H1_model.onnx`

### Step 2: Test the Model

Make predictions using the trained model:

```bash
python predict_with_onnx.py --model models/XAUUSD_H1_model.onnx --symbol XAUUSD --timeframe H1
```

### Step 3: Use in Expert Advisor

1. Copy the ONNX model to MT5's Files folder:
   ```
   <MT5 Data Folder>\MQL5\Files\models\XAUUSD_H1_model.onnx
   ```

2. Compile `ONNX_EA.mq5` in MetaEditor

3. Attach the EA to a chart with:
   - Model path: `models\XAUUSD_H1_model.onnx`
   - Your trading parameters

## Detailed Usage

### Training Models

#### Basic Training

```bash
python train_onnx_model.py \
    --symbol XAUUSD \
    --timeframe H1 \
    --lookback 60 \
    --epochs 50 \
    --batch-size 32
```

#### Advanced Options

```bash
python train_onnx_model.py \
    --symbol EURUSD \
    --timeframe M15 \
    --lookback 100 \
    --epochs 100 \
    --batch-size 64 \
    --output custom_models
```

**Parameters:**
- `--symbol`: Trading symbol (XAUUSD, EURUSD, BTCUSD, etc.)
- `--timeframe`: M1, M5, M15, M30, H1, H4, D1
- `--lookback`: Number of bars to use for prediction (default: 60)
- `--epochs`: Training epochs (default: 50)
- `--batch-size`: Batch size (default: 32)
- `--output`: Output directory (default: models)

### Making Predictions

#### Single Prediction

```bash
python predict_with_onnx.py \
    --model models/XAUUSD_H1_model.onnx \
    --symbol XAUUSD \
    --timeframe H1
```

#### Multiple Predictions

```bash
python predict_with_onnx.py \
    --model models/XAUUSD_H1_model.onnx \
    --symbol XAUUSD \
    --timeframe H1 \
    --predictions 5
```

### Expert Advisor Configuration

The `ONNX_EA.mq5` Expert Advisor includes:

**ONNX Model Settings:**
- `InpModelPath`: Path to ONNX model file
- `InpLookback`: Lookback period (must match training)
- `InpUsePrediction`: Enable/disable model predictions

**Trading Settings:**
- `InpLotSize`: Position size
- `InpMagicNumber`: Magic number for trades
- `InpStopLoss`: Stop loss in pips
- `InpTakeProfit`: Take profit in pips

**Prediction Settings:**
- `InpPredictionThreshold`: Minimum prediction change to trade (0.01% = 0.0001)
- `InpUseConfidence`: Enable confidence filtering
- `InpMinConfidence`: Minimum confidence level (0.0-1.0)

## Model Architecture

The default model uses:
- **Input**: 60 bars × 12 features
- **Architecture**: 
  - LSTM(128) → Dropout(0.2)
  - LSTM(64) → Dropout(0.2)
  - LSTM(32) → Dropout(0.2)
  - Dense(16, ReLU)
  - Dense(1) - Price prediction
- **Features**:
  - OHLC prices
  - Tick volume
  - RSI (14)
  - EMA(20), EMA(50)
  - ATR(14)
  - Price changes
  - High/Low ratio
  - Volume ratios

## Customization

### Modify Features

Edit `train_onnx_model.py` to add/remove features:

```python
def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
    feature_df = df[['open', 'high', 'low', 'close', 'tick_volume']].copy()
    
    # Add your custom indicators
    feature_df['custom_indicator'] = your_calculation(df)
    
    return feature_df
```

### Change Model Architecture

Modify `build_model()` in `train_onnx_model.py`:

```python
def build_model(self, input_shape: tuple) -> keras.Model:
    model = keras.Sequential([
        layers.LSTM(256, return_sequences=True, input_shape=input_shape),
        # Add your layers here
        layers.Dense(1)
    ])
    return model
```

### Adjust Expert Advisor Logic

Edit `ONNX_EA.mq5` to customize trading logic:
- Entry conditions
- Exit conditions
- Position management
- Risk management

## File Structure

```
ai/
├── requirements.txt           # Python dependencies
├── train_onnx_model.py       # Model training script
├── predict_with_onnx.py       # Prediction testing script
├── ONNX_EA.mq5               # MQL5 Expert Advisor
├── README.md                 # This file
└── models/                   # Trained ONNX models (created after training)
```

## Troubleshooting

### MT5 Connection Issues

**Error**: "MT5 initialization failed"
- Ensure MetaTrader 5 is installed and running
- Log into a demo or live account
- Check that the symbol exists in MT5

### Model Loading Issues

**Error**: "Failed to load ONNX model"
- Verify the model file path is correct
- Ensure the model file is in MT5's Files folder
- Check that the model was exported correctly

### Prediction Issues

**Error**: "Failed to prepare input data"
- Ensure enough historical data is available
- Check that lookback period matches training
- Verify indicators can be calculated

### Shape Mismatch Errors

If you get shape mismatch errors:
1. Check that `InpLookback` in EA matches training `--lookback`
2. Verify feature count matches (default: 12 features)
3. Ensure input normalization matches training

## Best Practices

1. **Data Quality**: Use high-quality historical data
2. **Feature Engineering**: Experiment with different indicators
3. **Model Validation**: Always validate on out-of-sample data
4. **Risk Management**: Use stop loss and position sizing
5. **Backtesting**: Test thoroughly before live trading
6. **Monitoring**: Monitor model performance regularly

## Example Workflow

1. **Train Model**:
   ```bash
   python train_onnx_model.py --symbol XAUUSD --timeframe H1
   ```

2. **Test Predictions**:
   ```bash
   python predict_with_onnx.py --model models/XAUUSD_H1_model.onnx --symbol XAUUSD
   ```

3. **Backtest in MT5**:
   - Use Strategy Tester with `ONNX_EA.mq5`
   - Test on historical data
   - Analyze results

4. **Optimize Parameters**:
   - Adjust prediction threshold
   - Tune confidence levels
   - Optimize stop loss/take profit

5. **Deploy**:
   - Start with small position sizes
   - Monitor performance
   - Adjust as needed

## References

- [MQL5 ONNX Documentation](https://www.mql5.com/en/docs/onnx/onnx_prepare)
- [ONNX Model Zoo](https://github.com/onnx/models)
- [MetaTrader 5 Python Module](https://pypi.org/project/MetaTrader5/)
- [TensorFlow to ONNX](https://github.com/onnx/tensorflow-onnx)

## Disclaimer

Trading involves substantial risk of loss. This framework is provided for educational purposes only. Always test thoroughly on a demo account before using with real money. Past performance does not guarantee future results.

## License

This framework is provided for educational and research purposes.
