"""
Complete Example Workflow for ONNX + MT5

This script demonstrates the complete workflow:
1. Train an ONNX model
2. Test predictions
3. Show how to use in MT5

Run this to see the full process in action.
"""

import os
import sys
from datetime import datetime
import MetaTrader5 as mt5

# Import our modules
from train_onnx_model import ONNXModelTrainer
from predict_with_onnx import ONNXPredictor


def main():
    """Complete workflow example."""
    print("="*60)
    print("ONNX + MetaTrader 5 - Complete Workflow Example")
    print("="*60)
    
    # Configuration
    symbol = 'XAUUSD'
    timeframe_str = 'H1'
    lookback = 60
    epochs = 20  # Reduced for quick demo
    
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
    
    # Create output directory
    models_dir = 'models'
    os.makedirs(models_dir, exist_ok=True)
    
    # Step 1: Train Model
    print("\n" + "="*60)
    print("STEP 1: Training ONNX Model")
    print("="*60)
    
    trainer = ONNXModelTrainer(
        symbol=symbol,
        timeframe=timeframe,
        lookback=lookback
    )
    
    try:
        print(f"\nTraining model for {symbol} on {timeframe_str} timeframe...")
        print(f"Lookback: {lookback} bars")
        print(f"Epochs: {epochs}")
        print("\nThis may take several minutes...\n")
        
        trainer.train(epochs=epochs, batch_size=32, verbose=1)
        
        # Export model
        model_name = f"{symbol}_{timeframe_str}_model.onnx"
        model_path = os.path.join(models_dir, model_name)
        
        print(f"\nExporting model to ONNX format...")
        trainer.export_to_onnx(model_path)
        
        print(f"\n✓ Model saved to: {model_path}")
        
    except Exception as e:
        print(f"\n✗ Training failed: {e}")
        import traceback
        traceback.print_exc()
        trainer.cleanup()
        return
    
    finally:
        trainer.cleanup()
    
    # Step 2: Test Predictions
    print("\n" + "="*60)
    print("STEP 2: Testing Predictions")
    print("="*60)
    
    predictor = ONNXPredictor(model_path)
    
    try:
        # Get current price
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info:
            current_price = symbol_info.bid
            print(f"\nCurrent {symbol} price: {current_price:.5f}")
        else:
            print(f"\nWarning: Could not get current price for {symbol}")
            current_price = 0
        
        # Make predictions
        print(f"\nMaking predictions...")
        predictions = predictor.predict_batch(symbol, timeframe, n_predictions=3)
        
        print("\nPredictions:")
        for i, pred in enumerate(predictions, 1):
            if current_price > 0:
                change = pred - current_price
                change_pct = (change / current_price) * 100
                print(f"  {i}. {pred:.5f} (change: {change:+.5f}, {change_pct:+.2f}%)")
            else:
                print(f"  {i}. {pred:.5f}")
        
    except Exception as e:
        print(f"\n✗ Prediction failed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        predictor.cleanup()
    
    # Step 3: Instructions for MT5
    print("\n" + "="*60)
    print("STEP 3: Using in MetaTrader 5")
    print("="*60)
    
    print(f"\nTo use this model in MetaTrader 5:")
    print(f"\n1. Copy the model file to MT5's Files folder:")
    print(f"   {model_path}")
    print(f"   → <MT5 Data Folder>\\MQL5\\Files\\models\\{os.path.basename(model_path)}")
    print(f"\n2. Open ONNX_EA.mq5 in MetaEditor")
    print(f"\n3. Set EA parameters:")
    print(f"   - Model Path: models\\{os.path.basename(model_path)}")
    print(f"   - Lookback: {lookback}")
    print(f"   - Your trading parameters")
    print(f"\n4. Compile and attach to chart")
    print(f"\n5. Monitor performance")
    
    print("\n" + "="*60)
    print("Workflow completed!")
    print("="*60 + "\n")


if __name__ == '__main__':
    # Check MT5 connection first
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        print("Make sure MetaTrader 5 is running and you're logged in.")
        sys.exit(1)
    
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    finally:
        mt5.shutdown()
