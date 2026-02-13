"""
Debug ONNX Model Predictions

This script helps debug why the model isn't generating trades.
It shows actual predictions and checks if they meet trading criteria.
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

from backtest_engine import BacktestEngine
from onnx_backtest_strategy import ONNXBacktestStrategy


def main():
    """Debug ONNX predictions."""
    print("="*60)
    print("ONNX Model Prediction Debug")
    print("="*60)
    
    # Configuration
    symbol = 'XAUUSD'
    timeframe = mt5.TIMEFRAME_H1
    model_path = 'models/XAUUSD_H1_model.onnx'
    scaler_path = 'models/XAUUSD_H1_scaler.pkl'
    
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found: {model_path}")
        return
    
    # Initialize MT5
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        return
    
    try:
        # Load model and scaler
        session = ort.InferenceSession(model_path)
        input_name = session.get_inputs()[0].name
        output_name = session.get_outputs()[0].name
        
        with open(scaler_path, 'rb') as f:
            scaler = pickle.load(f)
        
        # Get recent data
        end_date = datetime.now()
        start_date = end_date - timedelta(days=10)
        
        rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)
        if rates is None or len(rates) == 0:
            print("ERROR: No data available")
            return
        
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        
        print(f"\nLoaded {len(df)} bars")
        print(f"Date range: {df['time'].min()} to {df['time'].max()}")
        
        # Create strategy to get features
        strategy = ONNXBacktestStrategy(
            symbol=symbol,
            timeframe=timeframe,
            model_path=model_path,
            scaler_path=scaler_path,
            initial_balance=10000.0,
            prediction_threshold=0.0001,
            min_confidence=0.3,
            lot_size=0.1,
            stop_loss_pips=50,
            take_profit_pips=100
        )
        
        # Simulate a few bars
        print("\n" + "="*60)
        print("Predictions Analysis")
        print("="*60)
        
        predictions_data = []
        
        for i in range(60, min(100, len(df))):  # Start from bar 60 (need lookback)
            bar = df.iloc[i]
            bar_time = bar['time'] if isinstance(bar['time'], datetime) else datetime.fromtimestamp(bar['time'])
            current_price = bar['close']
            
            # Build historical buffer
            bar_data = {
                'time': bar_time,
                'open': float(bar['open']),
                'high': float(bar['high']),
                'low': float(bar['low']),
                'close': float(bar['close']),
                'tick_volume': int(bar['tick_volume']),
                'rsi': 50.0,  # Simplified
                'ema': current_price,  # Simplified
                'atr': 0.0  # Simplified
            }
            
            strategy.historical_bars.append(bar_data)
            
            if len(strategy.historical_bars) >= strategy.lookback:
                # Get prediction
                features = strategy.prepare_features()
                if features is not None:
                    input_data = features.astype(np.float32)
                    outputs = session.run([output_name], {input_name: input_data})
                    predicted_price = float(outputs[0][0][0])
                    
                    # Calculate metrics
                    price_change = predicted_price - current_price
                    price_change_pct = (price_change / current_price) if current_price > 0 else 0.0
                    confidence = min(abs(price_change_pct) / 0.01, 1.0)
                    
                    predictions_data.append({
                        'time': bar_time,
                        'current_price': current_price,
                        'predicted_price': predicted_price,
                        'price_change': price_change,
                        'price_change_pct': price_change_pct * 100,
                        'confidence': confidence,
                        'meets_threshold': abs(price_change_pct) >= 0.0001,
                        'meets_confidence': confidence >= 0.3,
                        'would_trade': abs(price_change_pct) >= 0.0001 and confidence >= 0.3
                    })
        
        # Display results
        if predictions_data:
            pred_df = pd.DataFrame(predictions_data)
            print(f"\nAnalyzed {len(pred_df)} predictions")
            print(f"\nPrediction Statistics:")
            print(f"  Mean price change: {pred_df['price_change_pct'].mean():.4f}%")
            print(f"  Std price change: {pred_df['price_change_pct'].std():.4f}%")
            print(f"  Min price change: {pred_df['price_change_pct'].min():.4f}%")
            print(f"  Max price change: {pred_df['price_change_pct'].max():.4f}%")
            print(f"\n  Mean confidence: {pred_df['confidence'].mean():.4f}")
            print(f"  Predictions meeting threshold: {pred_df['meets_threshold'].sum()}/{len(pred_df)}")
            print(f"  Predictions meeting confidence: {pred_df['meets_confidence'].sum()}/{len(pred_df)}")
            print(f"  Predictions that would trade: {pred_df['would_trade'].sum()}/{len(pred_df)}")
            
            print(f"\nSample predictions (first 10):")
            print(pred_df[['time', 'current_price', 'predicted_price', 'price_change_pct', 'confidence', 'would_trade']].head(10).to_string(index=False))
            
            if pred_df['would_trade'].sum() == 0:
                print("\n" + "="*60)
                print("RECOMMENDATIONS:")
                print("="*60)
                print("No trades would be generated. Try:")
                print(f"  1. Lower prediction_threshold (current: 0.0001)")
                print(f"     Suggested: {pred_df['price_change_pct'].abs().quantile(0.1):.6f}")
                print(f"  2. Lower min_confidence (current: 0.3)")
                print(f"     Suggested: {pred_df['confidence'].quantile(0.1):.2f}")
                print(f"  3. Check if model predictions are reasonable")
        else:
            print("No predictions generated (need more historical data)")
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
