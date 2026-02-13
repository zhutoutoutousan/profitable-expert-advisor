"""
Train ONNX Model for XAUUSD and Backtest

This script:
1. Trains an ONNX model for XAUUSD
2. Runs backtest using the trained model
3. Generates performance report
"""

import os
import sys
from datetime import datetime, timedelta
import MetaTrader5 as mt5

# Add paths
current_dir = os.path.dirname(os.path.abspath(__file__))
backtest_dir = os.path.join(os.path.dirname(current_dir), 'backtesting', 'MT5')
sys.path.insert(0, current_dir)
sys.path.insert(0, backtest_dir)

from train_onnx_model import ONNXModelTrainer
from backtest_engine import BacktestEngine
from onnx_backtest_strategy import ONNXBacktestStrategy
from performance_analyzer import PerformanceAnalyzer


def main():
    """Main function to train model and run backtest."""
    print("="*60)
    print("XAUUSD ONNX Model Training and Backtesting")
    print("="*60)
    
    # Configuration
    symbol = 'XAUUSD'
    timeframe_str = 'H1'
    lookback = 60
    epochs = 30  # Reduced for faster training
    initial_balance = 10000.0
    
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
        
        # Save scaler
        scaler_name = f"{symbol}_{timeframe_str}_scaler.pkl"
        scaler_path = os.path.join(models_dir, scaler_name)
        import pickle
        with open(scaler_path, 'wb') as f:
            pickle.dump(trainer.scaler, f)
        print(f"✓ Scaler saved to: {scaler_path}")
        
        print(f"\n✓ Model saved to: {model_path}")
        
    except Exception as e:
        print(f"\n✗ Training failed: {e}")
        import traceback
        traceback.print_exc()
        trainer.cleanup()
        return
    
    finally:
        trainer.cleanup()
    
    # Step 2: Run Backtest
    print("\n" + "="*60)
    print("STEP 2: Running Backtest")
    print("="*60)
    
    # Backtest date range (last 6 months for testing)
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)
    
    # Create strategy
    strategy = ONNXBacktestStrategy(
        symbol=symbol,
        timeframe=timeframe,
        model_path=model_path,
        scaler_path=scaler_path,
        initial_balance=initial_balance,
        prediction_threshold=0.0001,  # 0.01% minimum change
        min_confidence=0.3,  # 30% minimum confidence
        lot_size=0.1,
        stop_loss_pips=50,
        take_profit_pips=100
    )
    
    # Run backtest
    try:
        print(f"\nRunning backtest from {start_date.date()} to {end_date.date()}...")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        
        # Analyze results
        print("\n" + "="*60)
        print("STEP 3: Performance Analysis")
        print("="*60)
        
        analyzer = PerformanceAnalyzer(results)
        analyzer.generate_report('onnx_backtest_results')
        
        print("\n" + "="*60)
        print("Training and Backtesting Completed!")
        print("="*60)
        print(f"\nModel: {model_path}")
        print(f"Scaler: {scaler_path}")
        print(f"Results: onnx_backtest_results/")
        
    except Exception as e:
        print(f"\n✗ Backtest failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    # Check MT5 connection
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
