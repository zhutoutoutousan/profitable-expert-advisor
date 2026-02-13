"""
Backtest XAUUSD ONNX Model

This script backtests a trained ONNX model for XAUUSD.
Make sure you have trained the model first using train_onnx_model.py
"""

import sys
import os
from datetime import datetime, timedelta
import MetaTrader5 as mt5

# Add paths
current_dir = os.path.dirname(os.path.abspath(__file__))
backtest_dir = os.path.join(os.path.dirname(current_dir), 'backtesting', 'MT5')
sys.path.insert(0, backtest_dir)

from backtest_engine import BacktestEngine
from onnx_backtest_strategy import ONNXBacktestStrategy
from performance_analyzer import PerformanceAnalyzer


def main():
    """Run backtest for XAUUSD ONNX model."""
    print("="*60)
    print("XAUUSD ONNX Model Backtest")
    print("="*60)
    
    # Configuration
    symbol = 'XAUUSD'
    timeframe = mt5.TIMEFRAME_H1
    model_path = 'models/XAUUSD_H1_model.onnx'
    scaler_path = 'models/XAUUSD_H1_scaler.pkl'
    initial_balance = 10000.0
    
    # Check if model exists
    if not os.path.exists(model_path):
        print(f"\nERROR: Model not found: {model_path}")
        print("Please train the model first using:")
        print("  python train_onnx_model.py --symbol XAUUSD --timeframe H1")
        return
    
    if not os.path.exists(scaler_path):
        print(f"\nWARNING: Scaler not found: {scaler_path}")
        print("Will use default normalization (may affect accuracy)")
        scaler_path = None
    
    # Backtest date range
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)  # Last 6 months
    
    print(f"\nModel: {model_path}")
    print(f"Symbol: {symbol}")
    print(f"Timeframe: H1")
    print(f"Date Range: {start_date.date()} to {end_date.date()}")
    print(f"Initial Balance: ${initial_balance:,.2f}\n")
    
    # Create strategy
    try:
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
    except Exception as e:
        print(f"ERROR: Failed to create strategy: {e}")
        import traceback
        traceback.print_exc()
        return
    
    # Initialize MT5
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        print("Make sure MetaTrader 5 is running and you're logged in.")
        return
    
    try:
        # Run backtest
        print("Running backtest...\n")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        
        # Analyze results
        print("\n" + "="*60)
        print("Performance Analysis")
        print("="*60)
        
        analyzer = PerformanceAnalyzer(results)
        analyzer.generate_report('onnx_xauusd_backtest')
        
        print("\n" + "="*60)
        print("Backtest Completed!")
        print("="*60)
        print(f"\nResults saved to: onnx_xauusd_backtest/")
        
    except Exception as e:
        print(f"\nERROR: Backtest failed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
