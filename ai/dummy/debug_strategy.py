"""
Debug ONNX Strategy - Find out why no trades are generated
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


def main():
    """Debug strategy to find why no trades."""
    print("="*60)
    print("Debugging ONNX Strategy - Why No Trades?")
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
    start_date = end_date - timedelta(days=30)  # Shorter period for debugging
    
    print(f"\nModel: {model_path}")
    print(f"Date Range: {start_date.date()} to {end_date.date()}")
    print(f"Parameters:")
    print(f"  Prediction Threshold: 0.00005 (0.005%)")
    print(f"  Min Confidence: 0.1 (10%)")
    print("\n")
    
    if not mt5.initialize():
        print("ERROR: Failed to initialize MT5")
        return
    
    try:
        # Create strategy with debug enabled
        strategy = ONNXBacktestStrategy(
            symbol=symbol,
            timeframe=timeframe,
            model_path=model_path,
            scaler_path=scaler_path,
            initial_balance=initial_balance,
            prediction_threshold=0.00005,
            min_confidence=0.1,
            lot_size=0.1,
            stop_loss_pips=50,
            take_profit_pips=100
        )
        
        # Override on_bar to add detailed debugging
        original_on_bar = strategy.on_bar
        
        def debug_on_bar(bar_data):
            """Debug version of on_bar."""
            # Add current bar to historical buffer
            strategy.historical_bars.append(bar_data.copy())
            
            # Keep only necessary history
            if len(strategy.historical_bars) > strategy.lookback + 50:
                strategy.historical_bars = strategy.historical_bars[-(strategy.lookback + 50):]
            
            # Check if we have enough data
            if len(strategy.historical_bars) < strategy.lookback:
                if len(strategy.historical_bars) % 20 == 0:
                    print(f"  [Bar {len(strategy.historical_bars)}] Not enough data yet (need {strategy.lookback})")
                return
            
            current_price = bar_data['close']
            
            # Check existing position
            if strategy.position is not None:
                strategy.check_stop_loss_take_profit(current_price)
                return
            
            # Make prediction
            try:
                predicted_change_pct = strategy.predict_price()
                if predicted_change_pct is None:
                    if len(strategy.historical_bars) % 10 == 0:
                        print(f"  [Bar {len(strategy.historical_bars)}] Prediction returned None - checking why...")
                        # Try to debug why prediction is None
                        features = strategy.prepare_features()
                        if features is None:
                            print(f"    -> Features preparation returned None")
                        else:
                            print(f"    -> Features shape: {features.shape}")
                    return
            except Exception as e:
                print(f"  [Bar {len(strategy.historical_bars)}] Prediction exception: {e}")
                import traceback
                traceback.print_exc()
                return
            
            # Process prediction
            if abs(predicted_change_pct) < 1.0:
                price_change_pct = predicted_change_pct
            else:
                predicted_price = predicted_change_pct
                if predicted_price <= 0 or predicted_price > 10000:
                    if len(strategy.historical_bars) % 50 == 0:
                        print(f"  [Bar {len(strategy.historical_bars)}] Invalid prediction: {predicted_price}")
                    return
                price_change = predicted_price - current_price
                price_change_pct = (price_change / current_price) if current_price > 0 else 0.0
            
            # Calculate confidence
            if abs(price_change_pct) < 1.0:
                confidence = min(abs(price_change_pct) / 0.01, 1.0)
            else:
                confidence = min(abs(price_change_pct) / 1.0, 1.0)
            
            # Debug output for every 10th bar
            if len(strategy.historical_bars) % 10 == 0:
                print(f"\n  [Bar {len(strategy.historical_bars)}]")
                print(f"    Current Price: {current_price:.2f}")
                print(f"    Raw Prediction: {predicted_change_pct:.6f}")
                print(f"    Price Change %: {price_change_pct*100:.4f}%")
                print(f"    Abs Change: {abs(price_change_pct):.6f}")
                print(f"    Threshold: {strategy.prediction_threshold:.6f}")
                print(f"    Confidence: {confidence:.3f}")
                print(f"    Min Confidence: {strategy.min_confidence:.2f}")
                print(f"    Threshold Check: {abs(price_change_pct) >= strategy.prediction_threshold} (need True)")
                print(f"    Confidence Check: {confidence >= strategy.min_confidence} (need True)")
                
                if abs(price_change_pct) >= strategy.prediction_threshold and confidence >= strategy.min_confidence:
                    print(f"    -> WOULD TRADE! Direction: {'BUY' if price_change_pct > 0 else 'SELL'}")
                else:
                    if abs(price_change_pct) < strategy.prediction_threshold:
                        print(f"    -> BLOCKED: Abs change {abs(price_change_pct):.6f} < threshold {strategy.prediction_threshold:.6f}")
                    if confidence < strategy.min_confidence:
                        print(f"    -> BLOCKED: Confidence {confidence:.3f} < min {strategy.min_confidence:.2f}")
            
            # Check if we should trade
            if confidence < strategy.min_confidence:
                return
            
            if abs(price_change_pct) < strategy.prediction_threshold:
                return
            
            # Open position based on prediction
            if price_change_pct > strategy.prediction_threshold:
                # Bullish prediction
                sl = current_price - (strategy.stop_loss_pips / 10000) if strategy.stop_loss_pips > 0 else None
                tp = current_price + (strategy.take_profit_pips / 10000) if strategy.take_profit_pips > 0 else None
                print(f"\n  *** ATTEMPTING BUY POSITION at bar {len(strategy.historical_bars)} ***")
                print(f"    Price: {current_price:.2f}, Predicted Change: {price_change_pct*100:.4f}%")
                print(f"    SL: {sl:.2f}, TP: {tp:.2f}, Volume: {strategy.lot_size}")
                print(f"    Equity: {strategy.equity:.2f}, Current Position: {strategy.position}")
                # Check margin requirement manually
                contract_size = 100000
                margin_required = strategy.lot_size * contract_size * current_price * 0.01
                print(f"    Margin Required: {margin_required:.2f}, Available: {strategy.equity * 0.9:.2f}")
                result = strategy.open_position('BUY', strategy.lot_size, current_price, sl, tp, 'ONNX Buy')
                print(f"    Open Position Result: {result}")
                if result:
                    print(f"    -> Position opened! New position: {strategy.position}")
                else:
                    if strategy.position is not None:
                        print(f"    -> Position NOT opened! Reason: Already have position")
                    else:
                        print(f"    -> Position NOT opened! Reason: Margin insufficient or other validation failed")
            elif price_change_pct < -strategy.prediction_threshold:
                # Bearish prediction
                sl = current_price + (strategy.stop_loss_pips / 10000) if strategy.stop_loss_pips > 0 else None
                tp = current_price - (strategy.take_profit_pips / 10000) if strategy.take_profit_pips > 0 else None
                print(f"\n  *** ATTEMPTING SELL POSITION at bar {len(strategy.historical_bars)} ***")
                print(f"    Price: {current_price:.2f}, Predicted Change: {price_change_pct*100:.4f}%")
                print(f"    SL: {sl:.2f}, TP: {tp:.2f}, Volume: {strategy.lot_size}")
                print(f"    Equity: {strategy.equity:.2f}, Current Position: {strategy.position}")
                # Check margin requirement manually
                contract_size = 100000
                margin_required = strategy.lot_size * contract_size * current_price * 0.01
                print(f"    Margin Required: {margin_required:.2f}, Available: {strategy.equity * 0.9:.2f}")
                result = strategy.open_position('SELL', strategy.lot_size, current_price, sl, tp, 'ONNX Sell')
                print(f"    Open Position Result: {result}")
                if result:
                    print(f"    -> Position opened! New position: {strategy.position}")
                else:
                    if strategy.position is not None:
                        print(f"    -> Position NOT opened! Reason: Already have position")
                    else:
                        print(f"    -> Position NOT opened! Reason: Margin insufficient or other validation failed")
        
        strategy.on_bar = debug_on_bar
        
        print("Running backtest with detailed debugging...\n")
        engine = BacktestEngine(strategy, start_date, end_date)
        results = engine.run()
        
        print("\n" + "="*60)
        print("Backtest Complete")
        print("="*60)
        print(f"Total Trades: {len(strategy.closed_trades)}")
        print(f"Open Positions: {1 if strategy.position else 0}")
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
    finally:
        mt5.shutdown()


if __name__ == '__main__':
    main()
