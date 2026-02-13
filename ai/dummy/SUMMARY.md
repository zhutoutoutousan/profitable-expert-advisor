# XAUUSD ONNX Model Training and Backtesting Summary

## Status: ✅ Model Trained, ⚠️ Predictions Need Investigation

### Completed
1. ✅ **Model Training**: Successfully trained XAUUSD H1 ONNX model
   - Model: `models/XAUUSD_H1_model.onnx`
   - Scaler: `models/XAUUSD_H1_scaler.pkl`
   - Training Loss: 177939.59, MAE: 349.43
   - Validation Loss: 1749893.25, MAE: 1280.39

2. ✅ **Backtest Framework**: Working correctly
   - Processes 2888 bars successfully
   - No errors in execution

3. ✅ **Parameter Optimization Tools**: Created
   - Grid search and random search support
   - Can test multiple parameter combinations

### Issue Identified
⚠️ **Model Predictions Are Unrealistic**
- Model predicts prices around **2669** when current price is **3800+**
- This suggests a **-31% price change**, which is unrealistic
- All parameter combinations result in **0 trades**

### Possible Causes
1. **Model Training Issue**: 
   - High validation MAE (1280) suggests model may not be learning well
   - Model might be predicting from wrong data range

2. **Feature Mismatch**: 
   - Features used in backtesting might not match training features exactly
   - Normalization might be inconsistent

3. **Model Architecture**: 
   - LSTM might need more training or different architecture
   - Current model might be underfitting

### Recommendations

#### Immediate Actions
1. **Check Model Predictions**:
   ```bash
   python inspect_predictions.py
   ```
   This shows actual prediction values and statistics

2. **Retrain with Better Settings**:
   - Increase training epochs (try 50-100)
   - Use more recent data
   - Consider predicting price changes instead of absolute prices
   - Add more regularization to prevent overfitting

3. **Alternative Approach**:
   - Train model to predict **price change percentage** instead of absolute price
   - This would be more stable and easier to interpret

#### Next Steps
1. Investigate why predictions are so far off
2. Consider retraining with:
   - Price change prediction instead of absolute price
   - Better feature engineering
   - More training data
   - Different model architecture

### Files Created
- `ai/train_onnx_model.py` - Model training script
- `ai/quick_backtest.py` - Quick backtest script
- `ai/optimize_onnx_params.py` - Parameter optimization
- `ai/debug_onnx_predictions.py` - Debug predictions
- `ai/inspect_predictions.py` - Detailed prediction inspection
- `ai/test_very_low_threshold.py` - Test with very low thresholds
- `backtesting/MT5/onnx_backtest_strategy.py` - ONNX strategy class
- `backtesting/MT5/indicator_utils.py` - Indicator calculation utilities

### Usage
```bash
# Quick backtest
cd ai
python quick_backtest.py

# Optimize parameters
python optimize_onnx_params.py 2 30

# Inspect predictions
python inspect_predictions.py
```

### Model Details
- **Symbol**: XAUUSD
- **Timeframe**: H1
- **Lookback**: 60 bars
- **Features**: 13 (OHLC + volume + RSI + EMA20 + EMA50 + ATR + price_change + high_low_ratio + volume_ma + volume_ratio)
- **Architecture**: LSTM(128) → LSTM(64) → LSTM(32) → Dense(16) → Dense(1)
