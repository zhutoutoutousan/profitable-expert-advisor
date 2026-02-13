"""
Inspect ONNX Model Predictions in Detail

This script directly tests the model and shows what it's predicting.
"""

import os
import sys
from datetime import datetime, timedelta
import MetaTrader5 as mt5
import numpy as np
import pandas as pd
import onnxruntime as ort
import pickle

# Add paths
current_dir = os.path.dirname(os.path.abspath(__file__))
backtest_dir = os.path.join(os.path.dirname(current_dir), 'backtesting', 'MT5')
sys.path.insert(0, backtest_dir)

from indicator_utils import calculate_rsi, calculate_ema, calculate_atr


def main():
    """Inspect model predictions."""
    print("="*60)
    print("ONNX Model Prediction Inspection")
    print("="*60)
    
    model_path = 'models/XAUUSD_H1_model.onnx'
    scaler_path = 'models/XAUUSD_H1_scaler.pkl'
    
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found: {model_path}")
        return
    
    # Load model
    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name
    input_shape = session.get_inputs()[0].shape
    lookback = int(input_shape[1]) if input_shape[1] else 60
    
    print(f"Model Input Shape: {input_shape}")
    print(f"Lookback: {lookback}")
    
    # Load scaler
    with open(scaler_path, 'rb') as f:
        scaler = pickle.load(f)
    
    print(f"Scaler Feature Count: {scaler.n_features_in_}")
    
    # Initialize MT5
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        return
    
    try:
        # Get data
        symbol = 'XAUUSD'
        timeframe = mt5.TIMEFRAME_H1
        end_date = datetime.now()
        start_date = end_date - timedelta(days=100)  # Get more data
        
        rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)
        if rates is None or len(rates) == 0:
            print("ERROR: No data")
            return
        
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)
        
        print(f"\nLoaded {len(df)} bars")
        
        # Calculate indicators (same as training)
        df['rsi'] = calculate_rsi(df['close'], period=14)
        df['ema_20'] = calculate_ema(df['close'], period=20)
        df['ema_50'] = calculate_ema(df['close'], period=50)
        df['atr'] = calculate_atr(df, period=14)
        df['price_change'] = df['close'].pct_change()
        df['high_low_ratio'] = df['high'] / df['low']
        df['volume_ma'] = df['tick_volume'].rolling(window=20).mean()
        df['volume_ratio'] = df['tick_volume'] / df['volume_ma']
        
        # Drop NaN
        df = df.dropna()
        
        print(f"After indicator calculation: {len(df)} bars")
        print(f"Features: {len(['open', 'high', 'low', 'close', 'tick_volume', 'rsi', 'ema_20', 'ema_50', 'atr', 'price_change', 'high_low_ratio', 'volume_ma', 'volume_ratio'])}")
        
        # Test predictions
        print("\n" + "="*60)
        print("Testing Predictions")
        print("="*60)
        
        predictions = []
        
        for i in range(lookback, min(lookback + 50, len(df))):
            # Prepare features (same as training)
            feature_rows = []
            
            for j in range(i - lookback, i):
                bar = df.iloc[j]
                feature_row = [
                    bar['open'],
                    bar['high'],
                    bar['low'],
                    bar['close'],
                    bar['tick_volume'] / 1000000.0,
                    bar['rsi'] / 100.0,
                    (bar['ema_20'] - bar['close']) / bar['close'] if bar['close'] > 0 else 0.0,
                    (bar['ema_50'] - bar['close']) / bar['close'] if bar['close'] > 0 else 0.0,
                    bar['atr'] / bar['close'] if bar['close'] > 0 else 0.0,
                    bar['price_change'],
                    bar['high_low_ratio'],
                    bar['volume_ma'] / 1000000.0,
                    bar['volume_ratio']
                ]
                feature_rows.append(feature_row)
            
            features = np.array(feature_rows, dtype=np.float32)
            
            # Scale
            original_shape = features.shape
            features_flat = features.reshape(-1, features.shape[-1])
            features_scaled = scaler.transform(features_flat)
            features = features_scaled.reshape(original_shape)
            
            # Reshape for model
            input_data = features.reshape(1, lookback, -1)
            
            # Predict
            outputs = session.run([output_name], {input_name: input_data})
            predicted_change_pct = float(outputs[0][0][0])
            
            current_price = df.iloc[i]['close']
            
            # Model predicts price change percentage directly
            # If it's between -1 and 1, it's already a percentage
            if abs(predicted_change_pct) < 1.0:
                price_change_pct = predicted_change_pct * 100  # Convert to percentage (e.g., 0.001 -> 0.1%)
                predicted_price = current_price * (1 + predicted_change_pct / 100)  # Calculate predicted price
                price_change = predicted_price - current_price
            else:
                # Old format: absolute price
                predicted_price = predicted_change_pct
                price_change = predicted_price - current_price
                price_change_pct = (price_change / current_price) * 100 if current_price > 0 else 0.0
            
            predictions.append({
                'time': df.index[i],
                'current_price': current_price,
                'predicted_price': predicted_price,
                'price_change': price_change,
                'price_change_pct': price_change_pct,
                'abs_change_pct': abs(price_change_pct)
            })
        
        if predictions:
            pred_df = pd.DataFrame(predictions)
            
            print(f"\nAnalyzed {len(pred_df)} predictions:")
            print(f"\nPrice Change Statistics:")
            print(f"  Mean: {pred_df['price_change_pct'].mean():.6f}%")
            print(f"  Std: {pred_df['price_change_pct'].std():.6f}%")
            print(f"  Min: {pred_df['price_change_pct'].min():.6f}%")
            print(f"  Max: {pred_df['price_change_pct'].max():.6f}%")
            print(f"  Median: {pred_df['price_change_pct'].median():.6f}%")
            
            print(f"\nAbsolute Price Change Statistics:")
            print(f"  Mean: {pred_df['abs_change_pct'].mean():.6f}%")
            print(f"  Min: {pred_df['abs_change_pct'].min():.6f}%")
            print(f"  Max: {pred_df['abs_change_pct'].max():.6f}%")
            print(f"  Median: {pred_df['abs_change_pct'].median():.6f}%")
            
            print(f"\nSample Predictions (first 10):")
            print(pred_df[['time', 'current_price', 'predicted_price', 'price_change_pct']].head(10).to_string(index=False))
            
            # Check thresholds
            threshold_0001 = (pred_df['abs_change_pct'] >= 0.01).sum()
            threshold_00005 = (pred_df['abs_change_pct'] >= 0.005).sum()
            threshold_00001 = (pred_df['abs_change_pct'] >= 0.001).sum()
            
            print(f"\nPredictions meeting thresholds:")
            print(f"  >= 0.01% (0.0001): {threshold_0001}/{len(pred_df)}")
            print(f"  >= 0.005% (0.00005): {threshold_00005}/{len(pred_df)}")
            print(f"  >= 0.001% (0.00001): {threshold_00001}/{len(pred_df)}")
            
            if threshold_00001 == 0:
                print("\n" + "="*60)
                print("ISSUE DETECTED!")
                print("="*60)
                print("Even with 0.001% threshold, no predictions qualify.")
                print("The model may be predicting prices that are too close to current prices.")
                print("\nPossible solutions:")
                print("  1. Retrain model to predict price changes instead of absolute prices")
                print("  2. Use a different prediction target (e.g., next bar high/low)")
                print("  3. Adjust the model architecture")
        else:
            print("No predictions generated")
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
