# Quick Start Guide - ONNX with MetaTrader 5

Get started with ONNX machine learning models in MT5 in 5 minutes!

## Prerequisites

1. **MetaTrader 5** installed and running
2. **Python 3.8+** installed
3. **MT5 account** (demo or live) with access to historical data

## Step 1: Install Dependencies

```bash
cd ai
pip install -r requirements.txt
```

This installs:
- TensorFlow/Keras for model training
- ONNX runtime for model inference
- MetaTrader5 Python module
- Other required libraries

## Step 2: Verify MT5 Connection

Make sure MT5 is running and you're logged in. The scripts will automatically connect to MT5.

## Step 3: Train Your First Model

Train a price prediction model for Gold (XAUUSD):

```bash
python train_onnx_model.py --symbol XAUUSD --timeframe H1 --epochs 30
```

This will:
- Download 2 years of historical data
- Train an LSTM neural network
- Save the model as `models/XAUUSD_H1_model.onnx`

**Expected time**: 5-15 minutes depending on your hardware.

## Step 4: Test the Model

Make a prediction with your trained model:

```bash
python predict_with_onnx.py --model models/XAUUSD_H1_model.onnx --symbol XAUUSD
```

You should see output like:
```
Current XAUUSD price: 2650.12345
Making 1 prediction(s)...

Predicted next price: 2652.54321
Expected change: 2.41976 (0.09%)
```

## Step 5: Use in MetaTrader 5

### Option A: Copy Model to MT5

1. Copy your ONNX model to MT5's Files folder:
   ```
   <MT5 Data Folder>\MQL5\Files\models\XAUUSD_H1_model.onnx
   ```
   
   Default locations:
   - Windows: `C:\Users\<YourName>\AppData\Roaming\MetaQuotes\Terminal\<TerminalID>\MQL5\Files\`
   - Or find it: MT5 → File → Open Data Folder → MQL5 → Files

2. Open `ONNX_EA.mq5` in MetaEditor

3. Compile (F7)

4. Attach to chart:
   - Model path: `models\XAUUSD_H1_model.onnx`
   - Lookback: `60` (must match training)
   - Set your trading parameters

### Option B: Run from MetaEditor

If you have Python integration enabled in MetaEditor:

1. Open `train_onnx_model.py` in MetaEditor
2. Press F7 (Compile) to run
3. The model will be saved to the project folder

## Common Commands

### Train for Different Symbols

```bash
# EUR/USD on 15-minute charts
python train_onnx_model.py --symbol EURUSD --timeframe M15

# Bitcoin on 4-hour charts
python train_onnx_model.py --symbol BTCUSD --timeframe H4
```

### Custom Training Parameters

```bash
python train_onnx_model.py \
    --symbol XAUUSD \
    --timeframe H1 \
    --lookback 100 \
    --epochs 100 \
    --batch-size 64
```

### Multiple Predictions

```bash
python predict_with_onnx.py \
    --model models/XAUUSD_H1_model.onnx \
    --symbol XAUUSD \
    --predictions 5
```

## Troubleshooting

### "MT5 initialization failed"
- ✅ Make sure MT5 is running
- ✅ Log into your account in MT5
- ✅ Check that the symbol exists (e.g., XAUUSD, not GOLD)

### "No data available"
- ✅ Ensure you have historical data downloaded in MT5
- ✅ Check the date range (script uses last 2 years)
- ✅ Verify symbol name is correct

### "Failed to load ONNX model" in EA
- ✅ Check the file path is correct
- ✅ Ensure model is in MT5's Files folder
- ✅ Verify the model file exists and is not corrupted

### Model predictions seem wrong
- ✅ Ensure `InpLookback` in EA matches training `--lookback`
- ✅ Check that you're using the same symbol/timeframe
- ✅ Verify feature normalization matches training

## Next Steps

1. **Experiment with different models**:
   - Try different lookback periods
   - Adjust network architecture
   - Add more features

2. **Optimize trading parameters**:
   - Test different prediction thresholds
   - Tune stop loss/take profit
   - Adjust confidence levels

3. **Backtest thoroughly**:
   - Use MT5 Strategy Tester
   - Test on different time periods
   - Analyze performance metrics

4. **Monitor and improve**:
   - Track prediction accuracy
   - Retrain models periodically
   - Adjust based on market conditions

## Example Workflow

```bash
# 1. Train model
python train_onnx_model.py --symbol XAUUSD --timeframe H1 --epochs 50

# 2. Test predictions
python predict_with_onnx.py --model models/XAUUSD_H1_model.onnx --symbol XAUUSD

# 3. Copy model to MT5 Files folder
# (Manual step)

# 4. Compile and attach ONNX_EA.mq5 to chart

# 5. Monitor and adjust parameters
```

## Tips

- 🎯 Start with longer timeframes (H1, H4) for more stable predictions
- 📊 Use multiple models for different market conditions
- 🔄 Retrain models periodically (weekly/monthly)
- ⚠️ Always test on demo account first
- 📈 Monitor model performance and adjust parameters

## Need Help?

- Check the main [README.md](README.md) for detailed documentation
- Review the MQL5 ONNX documentation: https://www.mql5.com/en/docs/onnx/onnx_prepare
- Examine the code comments for implementation details

Happy trading! 🚀
