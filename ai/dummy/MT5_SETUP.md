# MetaTrader 5 ONNX EA Setup Guide

## Quick Start

1. **Copy Model Files to MT5**
   - Copy `models/XAUUSD_H1_model.onnx` to: `MT5_Data_Folder/MQL5/Files/models/`
   - The EA will look for the model at: `models\XAUUSD_H1_model.onnx`

2. **Compile the EA**
   - Open `ai/ONNX_EA.mq5` in MetaEditor
   - Press F7 to compile
   - Check for any errors

3. **Attach to Chart**
   - Open XAUUSD H1 chart in MT5
   - Drag `ONNX_EA.ex5` from Navigator to chart
   - Configure parameters (see below)

## Model Information

- **Model Type**: LSTM Neural Network
- **Input**: 60 bars × 13 features
- **Output**: Price change percentage (e.g., -0.003 = -0.3% decrease)
- **Features**: OHLC, volume, RSI, EMA20, EMA50, ATR, price_change, high_low_ratio, volume_ma, volume_ratio

## EA Parameters

### ONNX Model Settings
- **InpModelPath**: `models\\XAUUSD_H1_model.onnx` (path relative to MQL5/Files/)
- **InpLookback**: `60` (must match training)
- **InpUsePrediction**: `true` (enable/disable predictions)

### Trading Settings
- **InpLotSize**: `0.01` (start small for testing)
- **InpMagicNumber**: `123456` (unique identifier)
- **InpSlippage**: `3` (points)
- **InpStopLoss**: `50` (pips)
- **InpTakeProfit**: `100` (pips)

### Prediction Settings
- **InpPredictionThreshold**: `0.00005` (0.005% as decimal, minimum change to trade)
- **InpUseConfidence**: `true` (enable confidence filter)
- **InpMinConfidence**: `0.1` (10% minimum confidence)

## Important Notes

### Feature Normalization
⚠️ **The EA uses simplified normalization that may not exactly match training.**

For best results:
1. The training script saves a scaler (`XAUUSD_H1_scaler.pkl`)
2. You should implement the same MinMaxScaler logic in MQL5
3. Or export scaler parameters (min/max) from Python and use in MQL5

Current implementation uses:
- OHLC: Raw values (should be normalized by scaler)
- Volume: Divided by 1,000,000
- RSI: Divided by 100
- EMAs/ATR: Normalized differences
- Price change: Percentage
- Volume MA: Divided by 1,000,000

### Prediction Format
The new model predicts **price change percentage** directly:
- Example: `-0.003` = price will decrease by 0.3%
- Old format (absolute price) is also supported for backward compatibility

### Testing Recommendations

1. **Start with Strategy Tester**
   - Use Visual Mode to see predictions
   - Check Expert tab for prediction logs
   - Verify predictions make sense

2. **Monitor Logs**
   - Check "Experts" tab for prediction values
   - Verify confidence calculations
   - Watch for any errors

3. **Adjust Parameters**
   - If too many trades: Increase `InpPredictionThreshold` or `InpMinConfidence`
   - If no trades: Decrease thresholds
   - Adjust stop loss/take profit based on volatility

## Troubleshooting

### "Failed to load ONNX model"
- Check model path is correct
- Ensure model file exists in `MQL5/Files/models/`
- Check file permissions

### "Failed to prepare input data"
- Ensure enough historical data (need 60+ bars)
- Check indicator calculations
- Verify symbol is XAUUSD

### "Empty output from ONNX model"
- Check model input shape matches (1, 60, 13)
- Verify feature preparation matches training
- Check ONNX runtime version compatibility

### Predictions seem wrong
- Feature normalization may not match training
- Implement proper MinMaxScaler from training
- Check feature order matches training (13 features in correct order)

## Model Training Info

- **Training Date**: 2026-01-06
- **Training MAE**: 0.0013 (0.13%)
- **Validation MAE**: 0.0018 (0.18%)
- **Data Period**: Last 2 years
- **Timeframe**: H1

## Next Steps

1. Test in Strategy Tester first
2. Compare predictions with Python backtest
3. Adjust parameters based on results
4. Consider implementing proper scaler normalization
5. Test on demo account before live trading
