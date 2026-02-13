"""
Retrain XAUUSD ONNX Model with Improved Settings

This script retrains the model with:
- Price change percentage prediction (instead of absolute price)
- More training epochs
- Better model architecture
- Improved data preprocessing
"""

import os
import sys
from datetime import datetime
import MetaTrader5 as mt5

# Add paths
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from train_onnx_model import ONNXModelTrainer


def main():
    """Retrain XAUUSD model with improved settings."""
    print("="*60)
    print("Retraining XAUUSD ONNX Model (Improved)")
    print("="*60)
    
    symbol = 'XAUUSD'
    timeframe_str = 'H1'
    lookback = 60
    epochs = 50  # More epochs for better training
    
    # Convert timeframe
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1
    }
    timeframe = timeframe_map[timeframe_str]
    
    # Create models directory
    models_dir = 'models'
    os.makedirs(models_dir, exist_ok=True)
    
    print(f"\nConfiguration:")
    print(f"  Symbol: {symbol}")
    print(f"  Timeframe: {timeframe_str}")
    print(f"  Lookback: {lookback} bars")
    print(f"  Epochs: {epochs}")
    print(f"  Prediction: Price change percentage (improved)")
    print("\nThis will take 10-20 minutes...\n")
    
    trainer = ONNXModelTrainer(
        symbol=symbol,
        timeframe=timeframe,
        lookback=lookback
    )
    
    try:
        # Train model
        trainer.train(epochs=epochs, batch_size=32, verbose=1)
        
        # Export model
        model_name = f"{symbol}_{timeframe_str}_model.onnx"
        model_path = os.path.join(models_dir, model_name)
        
        print(f"\nExporting model to ONNX format...")
        trainer.export_to_onnx(model_path)
        
        # Save scaler
        scaler_name = f"{symbol}_{timeframe_str}_scaler.pkl"
        scaler_path = os.path.join(models_dir, scaler_name)
        import pickle
        with open(scaler_path, 'wb') as f:
            pickle.dump(trainer.scaler, f)
        print(f"Scaler saved to: {scaler_path}")
        
        print(f"\n{'='*60}")
        print("Retraining Completed Successfully!")
        print(f"{'='*60}")
        print(f"\nModel: {model_path}")
        print(f"Scaler: {scaler_path}")
        print("\nNext steps:")
        print("  1. Run: python quick_backtest.py")
        print("  2. Or: python optimize_onnx_params.py 2 30")
        
    except Exception as e:
        print(f"\nERROR: Training failed: {e}")
        import traceback
        traceback.print_exc()
        trainer.cleanup()
        return
    
    finally:
        trainer.cleanup()


if __name__ == '__main__':
    # Check MT5 connection
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        print("Make sure MetaTrader 5 is running and you're logged in.")
        sys.exit(1)
    
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user")
    finally:
        mt5.shutdown()
