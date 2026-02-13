"""
Test with very low thresholds to see if we can get any trades
"""

import os
import sys
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
    """Test with very low thresholds."""
    print("="*60)
    print("Testing with VERY LOW Thresholds")
    print("="*60)
    
    symbol = 'XAUUSD'
    timeframe = mt5.TIMEFRAME_H1
    model_path = 'models/XAUUSD_H1_model.onnx'
    scaler_path = 'models/XAUUSD_H1_scaler.pkl'
    initial_balance = 10000.0
    
    if not os.path.exists(model_path):
        print(f"ERROR: Model not found: {model_path}")
        return
    
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)
    
    print(f"\nModel: {model_path}")
    print(f"Date Range: {start_date.date()} to {end_date.date()}")
    print(f"\nVERY RELAXED Parameters:")
    print("  Prediction Threshold: 0.00001 (0.001%)")
    print("  Min Confidence: 0.05 (5%)")
    print("  Stop Loss: 50 pips")
    print("  Take Profit: 100 pips")
    print("  Lot Size: 0.1\n")
    
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        return
    
    try:
        # Create strategy with VERY low thresholds
        strategy = ONNXBacktestStrategy(
            symbol=symbol,
            timeframe=timeframe,
            model_path=model_path,
            scaler_path=scaler_path,
            initial_balance=initial_balance,
            prediction_threshold=0.00001,  # Very low: 0.001%
            min_confidence=0.05,  # Very low: 5%
            lot_size=0.1,
            stop_loss_pips=50,
            take_profit_pips=100
        )
        
        print("Running backtest...\n")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        
        analyzer = PerformanceAnalyzer(results)
        metrics = analyzer.metrics
        
        print("\n" + "="*60)
        print("Results")
        print("="*60)
        print(f"Total Trades: {metrics.get('total_trades', 0)}")
        print(f"Final Balance: ${metrics.get('final_balance', initial_balance):,.2f}")
        print(f"Total Return: {metrics.get('total_return_pct', 0):.2f}%")
        
        if metrics.get('total_trades', 0) == 0:
            print("\n" + "="*60)
            print("STILL NO TRADES!")
            print("="*60)
            print("This suggests the model predictions may be:")
            print("  1. Too small in magnitude")
            print("  2. Not meeting even very low thresholds")
            print("  3. Or there's an issue with the prediction logic")
            print("\nNext steps:")
            print("  - Check model predictions directly")
            print("  - Verify feature preparation matches training")
            print("  - Consider retraining with different architecture")
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
