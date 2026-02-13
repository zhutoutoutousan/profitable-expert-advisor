"""
Quick Backtest Script for ONNX Model

Simple script to quickly backtest the trained ONNX model with default parameters.
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
    """Run quick backtest."""
    print("="*60)
    print("XAUUSD ONNX Model Quick Backtest")
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
    
    # Backtest date range
    end_date = datetime.now()
    start_date = end_date - timedelta(days=180)  # Last 6 months
    
    print(f"\nModel: {model_path}")
    print(f"Symbol: {symbol}")
    print(f"Timeframe: H1")
    print(f"Date Range: {start_date.date()} to {end_date.date()}")
    print(f"Initial Balance: ${initial_balance:,.2f}\n")
    
    # Adjusted parameters (more relaxed to generate trades)
    print("Strategy Parameters (Adjusted for Testing):")
    print("  Prediction Threshold: 0.00005 (0.005%) - LOWERED")
    print("  Min Confidence: 0.1 (10%) - LOWERED")
    print("  Stop Loss: 50 pips")
    print("  Take Profit: 100 pips")
    print("  Lot Size: 0.1\n")
    
    # Initialize MT5
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        print("Make sure MetaTrader 5 is running and you're logged in.")
        return
    
    try:
        # Create strategy with relaxed parameters
        strategy = ONNXBacktestStrategy(
            symbol=symbol,
            timeframe=timeframe,
            model_path=model_path,
            scaler_path=scaler_path,
            initial_balance=initial_balance,
            prediction_threshold=0.00005,  # Lowered from 0.0001
            min_confidence=0.1,  # Lowered from 0.3
            lot_size=0.1,
            stop_loss_pips=50,
            take_profit_pips=100
        )
        
        # Run backtest
        print("Running backtest...\n")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        
        # Analyze results
        print("\n" + "="*60)
        print("Performance Summary")
        print("="*60)
        
        analyzer = PerformanceAnalyzer(results)
        metrics = analyzer.metrics
        
        print(f"\nTotal Return: {metrics.get('total_return_pct', 0):.2f}%")
        print(f"Max Drawdown: {metrics.get('max_drawdown_pct', 0):.2f}%")
        print(f"Profit Factor: {metrics.get('profit_factor', 0):.2f}")
        print(f"Win Rate: {metrics.get('win_rate_pct', 0):.2f}%")
        print(f"Total Trades: {metrics.get('total_trades', 0)}")
        print(f"Final Balance: ${metrics.get('final_balance', initial_balance):,.2f}")
        
        # Generate report
        analyzer.generate_report('onnx_xauusd_quick_backtest')
        
        print("\n" + "="*60)
        print("Backtest Completed!")
        print("="*60)
        print(f"\nResults saved to: onnx_xauusd_quick_backtest/")
        print("\nTo optimize parameters, run:")
        print("  python optimize_onnx_params.py")
        
    except Exception as e:
        print(f"\nERROR: Backtest failed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
