"""
Backtesting Script for RSI Divergence ONNX Model
Tests the trained model on historical data and evaluates trading performance.
"""

import argparse
import os
import sys
import numpy as np
import pandas as pd
import MetaTrader5 as mt5
from datetime import datetime, timedelta
import onnxruntime as ort
import pickle
from tqdm import tqdm


class RSIDivergenceBacktester:
    """
    Backtests the RSI divergence ONNX model.
    """
    
    def __init__(self, model_path: str, scaler_path: str, features_path: str, lookback: int = 60):
        """
        Initialize the backtester.
        
        Args:
            model_path: Path to ONNX model file
            scaler_path: Path to scaler pickle file
            features_path: Path to features list pickle file
            lookback: Number of bars to look back
        """
        self.lookback = lookback
        
        # Load ONNX model
        print(f"Loading ONNX model from {model_path}...")
        self.session = ort.InferenceSession(model_path)
        print("ONNX model loaded successfully")
        
        # Load scaler
        print(f"Loading scaler from {scaler_path}...")
        with open(scaler_path, 'rb') as f:
            self.scaler = pickle.load(f)
        print("Scaler loaded successfully")
        
        # Load feature list
        print(f"Loading features from {features_path}...")
        with open(features_path, 'rb') as f:
            self.feature_cols = pickle.load(f)
        print(f"Using {len(self.feature_cols)} features")
        
        # Divergence type mapping
        self.divergence_types = {
            0: 'NONE',
            1: 'REGULAR_BULLISH',
            2: 'REGULAR_BEARISH',
            3: 'HIDDEN_BULLISH',
            4: 'HIDDEN_BEARISH'
        }
    
    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Prepare features from raw data (same as in collect_btcusd_data.py)."""
        feature_df = df.copy()
        
        # Price-based features
        feature_df['returns'] = feature_df['close'].pct_change()
        feature_df['high_low_ratio'] = feature_df['high'] / (feature_df['low'] + 1e-10)
        feature_df['close_open_ratio'] = feature_df['close'] / (feature_df['open'] + 1e-10)
        
        # Moving averages
        feature_df['sma_20'] = feature_df['close'].rolling(window=20).mean()
        feature_df['sma_50'] = feature_df['close'].rolling(window=50).mean()
        feature_df['ema_20'] = feature_df['close'].ewm(span=20).mean()
        feature_df['ema_50'] = feature_df['close'].ewm(span=50).mean()
        
        # ATR
        high_low = feature_df['high'] - feature_df['low']
        high_close = np.abs(feature_df['high'] - feature_df['close'].shift())
        low_close = np.abs(feature_df['low'] - feature_df['close'].shift())
        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        feature_df['atr'] = tr.rolling(window=14).mean()
        feature_df['atr_pct'] = feature_df['atr'] / (feature_df['close'] + 1e-10)
        
        # Volume features
        if 'tick_volume' in feature_df.columns:
            feature_df['volume_ma'] = feature_df['tick_volume'].rolling(window=20).mean()
            feature_df['volume_ratio'] = feature_df['tick_volume'] / (feature_df['volume_ma'] + 1e-10)
        
        # Price position relative to range
        feature_df['price_position'] = (feature_df['close'] - feature_df['low'].rolling(20).min()) / (
            feature_df['high'].rolling(20).max() - feature_df['low'].rolling(20).min() + 1e-10
        )
        
        # Calculate RSI
        from rsi_divergence_detector import RSIDivergenceDetector
        detector = RSIDivergenceDetector()
        feature_df['rsi'] = detector.calculate_rsi(feature_df['close'])
        
        return feature_df
    
    def predict(self, df: pd.DataFrame, index: int) -> tuple:
        """
        Make prediction at given index.
        
        Args:
            df: DataFrame with features
            index: Current bar index
        
        Returns:
            Tuple of (predicted_class, confidence)
        """
        if index < self.lookback:
            return 0, 0.0
        
        # Get feature sequence
        feature_data = df[self.feature_cols].iloc[index - self.lookback:index].values
        
        # Scale features
        feature_data_scaled = self.scaler.transform(feature_data)
        
        # Reshape for model input (1, lookback, features)
        feature_data_scaled = feature_data_scaled.reshape(1, self.lookback, -1)
        
        # Run ONNX model
        input_name = self.session.get_inputs()[0].name
        output_name = self.session.get_outputs()[0].name
        
        result = self.session.run([output_name], {input_name: feature_data_scaled.astype(np.float32)})
        
        # Get prediction
        probabilities = result[0][0]
        predicted_class = int(np.argmax(probabilities))
        confidence = float(np.max(probabilities))
        
        return predicted_class, confidence
    
    def backtest(self, symbol: str, timeframe: int, start_date: datetime, 
                 end_date: datetime, initial_balance: float = 10000.0,
                 lot_size: float = 0.01, min_confidence: float = 0.7) -> dict:
        """
        Run backtest on historical data.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe constant
            start_date: Start date
            end_date: End date
            initial_balance: Starting balance
            lot_size: Lot size per trade
            min_confidence: Minimum confidence to take a trade
        
        Returns:
            Dictionary with backtest results
        """
        print(f"\n{'='*60}")
        print("RSI Divergence Model Backtest")
        print(f"{'='*60}\n")
        
        # Fetch data
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialization failed: {mt5.last_error()}")
        
        try:
            print(f"Fetching {symbol} data from {start_date} to {end_date}...")
            rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)
            
            if rates is None or len(rates) == 0:
                raise ValueError(f"No data available for {symbol}")
            
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            df.set_index('time', inplace=True)
            df.columns = [col.lower() for col in df.columns]
            
            print(f"Fetched {len(df)} bars")
            
            # Prepare features
            print("Preparing features...")
            df = self.prepare_features(df)
            df = df.dropna()
            
            print(f"Data ready: {len(df)} bars after feature preparation")
            
            # Backtest simulation
            balance = initial_balance
            equity = initial_balance
            position = None  # (type: 'BUY' or 'SELL', entry_price, entry_index, size)
            trades = []
            equity_curve = [initial_balance]
            
            print("\nRunning backtest...")
            for i in tqdm(range(self.lookback, len(df))):
                current_price = df['close'].iloc[i]
                current_time = df.index[i]
                
                # Make prediction
                predicted_class, confidence = self.predict(df, i)
                divergence_type = self.divergence_types[predicted_class]
                
                # Close position if needed
                if position is not None:
                    # Simple exit: close after 10 bars or on opposite signal
                    bars_in_trade = i - position[2]
                    
                    if bars_in_trade >= 10:
                        # Close position
                        if position[0] == 'BUY':
                            pnl = (current_price - position[1]) * position[3]
                        else:
                            pnl = (position[1] - current_price) * position[3]
                        
                        balance += pnl
                        equity = balance
                        
                        trades.append({
                            'entry_time': df.index[position[2]],
                            'exit_time': current_time,
                            'type': position[0],
                            'entry_price': position[1],
                            'exit_price': current_price,
                            'size': position[3],
                            'pnl': pnl,
                            'bars_held': bars_in_trade
                        })
                        
                        position = None
                
                # Open new position based on prediction
                if position is None and confidence >= min_confidence:
                    if divergence_type == 'REGULAR_BULLISH' or divergence_type == 'HIDDEN_BULLISH':
                        # Buy signal
                        position = ('BUY', current_price, i, lot_size)
                    elif divergence_type == 'REGULAR_BEARISH' or divergence_type == 'HIDDEN_BEARISH':
                        # Sell signal
                        position = ('SELL', current_price, i, lot_size)
                
                # Update equity (with unrealized PnL)
                if position is not None:
                    if position[0] == 'BUY':
                        unrealized_pnl = (current_price - position[1]) * position[3]
                    else:
                        unrealized_pnl = (position[1] - current_price) * position[3]
                    equity = balance + unrealized_pnl
                else:
                    equity = balance
                
                equity_curve.append(equity)
            
            # Close any remaining position
            if position is not None:
                final_price = df['close'].iloc[-1]
                if position[0] == 'BUY':
                    pnl = (final_price - position[1]) * position[3]
                else:
                    pnl = (position[1] - final_price) * position[3]
                
                balance += pnl
                trades.append({
                    'entry_time': df.index[position[2]],
                    'exit_time': df.index[-1],
                    'type': position[0],
                    'entry_price': position[1],
                    'exit_price': final_price,
                    'size': position[3],
                    'pnl': pnl,
                    'bars_held': len(df) - position[2]
                })
            
            # Calculate metrics
            trades_df = pd.DataFrame(trades)
            
            if len(trades) > 0:
                total_trades = len(trades)
                winning_trades = len(trades_df[trades_df['pnl'] > 0])
                losing_trades = len(trades_df[trades_df['pnl'] <= 0])
                win_rate = winning_trades / total_trades * 100
                
                total_pnl = trades_df['pnl'].sum()
                avg_win = trades_df[trades_df['pnl'] > 0]['pnl'].mean() if winning_trades > 0 else 0
                avg_loss = trades_df[trades_df['pnl'] <= 0]['pnl'].mean() if losing_trades > 0 else 0
                
                profit_factor = abs(avg_win * winning_trades / (avg_loss * losing_trades)) if losing_trades > 0 and avg_loss != 0 else float('inf')
                
                final_balance = balance
                total_return = (final_balance - initial_balance) / initial_balance * 100
                
                # Drawdown
                equity_series = pd.Series(equity_curve)
                running_max = equity_series.expanding().max()
                drawdown = (equity_series - running_max) / running_max * 100
                max_drawdown = drawdown.min()
            else:
                total_trades = 0
                winning_trades = 0
                losing_trades = 0
                win_rate = 0
                total_pnl = 0
                avg_win = 0
                avg_loss = 0
                profit_factor = 0
                final_balance = initial_balance
                total_return = 0
                max_drawdown = 0
            
            results = {
                'initial_balance': initial_balance,
                'final_balance': final_balance,
                'total_return_pct': total_return,
                'total_trades': total_trades,
                'winning_trades': winning_trades,
                'losing_trades': losing_trades,
                'win_rate': win_rate,
                'total_pnl': total_pnl,
                'avg_win': avg_win,
                'avg_loss': avg_loss,
                'profit_factor': profit_factor,
                'max_drawdown_pct': max_drawdown,
                'trades': trades_df
            }
            
            return results
        
        finally:
            mt5.shutdown()


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Backtest RSI divergence ONNX model')
    parser.add_argument('--model', type=str, required=True, help='Path to ONNX model file')
    parser.add_argument('--scaler', type=str, required=True, help='Path to scaler pickle file')
    parser.add_argument('--features', type=str, required=True, help='Path to features list pickle file')
    parser.add_argument('--symbol', type=str, default='BTCUSD', help='Trading symbol')
    parser.add_argument('--timeframe', type=str, default='H1', 
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Timeframe')
    parser.add_argument('--days', type=int, default=90, help='Number of days to backtest')
    parser.add_argument('--balance', type=float, default=10000.0, help='Initial balance')
    parser.add_argument('--lot-size', type=float, default=0.01, help='Lot size per trade')
    parser.add_argument('--min-confidence', type=float, default=0.7, 
                       help='Minimum confidence to take a trade')
    
    args = parser.parse_args()
    
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
    timeframe = timeframe_map[args.timeframe]
    
    # Create backtester
    backtester = RSIDivergenceBacktester(
        args.model, args.scaler, args.features, lookback=60
    )
    
    # Run backtest
    end_date = datetime.now()
    start_date = end_date - timedelta(days=args.days)
    
    results = backtester.backtest(
        args.symbol, timeframe, start_date, end_date,
        initial_balance=args.balance,
        lot_size=args.lot_size,
        min_confidence=args.min_confidence
    )
    
    # Print results
    print(f"\n{'='*60}")
    print("Backtest Results")
    print(f"{'='*60}")
    print(f"Initial Balance: ${results['initial_balance']:,.2f}")
    print(f"Final Balance: ${results['final_balance']:,.2f}")
    print(f"Total Return: {results['total_return_pct']:.2f}%")
    print(f"Max Drawdown: {results['max_drawdown_pct']:.2f}%")
    print(f"\nTrades:")
    print(f"  Total: {results['total_trades']}")
    print(f"  Winning: {results['winning_trades']}")
    print(f"  Losing: {results['losing_trades']}")
    print(f"  Win Rate: {results['win_rate']:.2f}%")
    print(f"\nPerformance:")
    print(f"  Total P&L: ${results['total_pnl']:,.2f}")
    print(f"  Avg Win: ${results['avg_win']:,.2f}")
    print(f"  Avg Loss: ${results['avg_loss']:,.2f}")
    print(f"  Profit Factor: {results['profit_factor']:.2f}")
    print(f"{'='*60}\n")
    
    # Save trades to CSV
    if len(results['trades']) > 0:
        output_file = f"backtest_trades_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        results['trades'].to_csv(output_file, index=False)
        print(f"Trades saved to: {output_file}")


if __name__ == '__main__':
    main()
