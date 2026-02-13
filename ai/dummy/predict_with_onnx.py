"""
ONNX Model Prediction Script

This script loads a trained ONNX model and makes predictions using MT5 data.
Can be run from MetaEditor or directly in Python.

Usage:
    python predict_with_onnx.py --model models/XAUUSD_H1_model.onnx --symbol XAUUSD
"""

import argparse
import numpy as np
import pandas as pd
import MetaTrader5 as mt5
import onnxruntime as ort
from datetime import datetime
from sklearn.preprocessing import MinMaxScaler
import pickle
import os


class ONNXPredictor:
    """
    Predictor class for using ONNX models with MT5 data.
    """
    
    def __init__(self, model_path: str, scaler_path: str = None):
        """
        Initialize the predictor.
        
        Args:
            model_path: Path to ONNX model file
            scaler_path: Path to saved scaler (optional, will create if not provided)
        """
        self.model_path = model_path
        self.scaler_path = scaler_path
        
        # Load ONNX model
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"ONNX model not found: {model_path}")
        
        self.session = ort.InferenceSession(model_path)
        
        # Get input/output info
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name
        self.input_shape = self.session.get_inputs()[0].shape
        
        print(f"Loaded ONNX model: {model_path}")
        print(f"Input shape: {self.input_shape}")
        print(f"Input name: {self.input_name}")
        print(f"Output name: {self.output_name}")
        
        # Load or create scaler
        if scaler_path and os.path.exists(scaler_path):
            with open(scaler_path, 'rb') as f:
                self.scaler = pickle.load(f)
            print(f"Loaded scaler from: {scaler_path}")
        else:
            self.scaler = MinMaxScaler()
            print("Using default scaler (will need to fit)")
        
        # Initialize MT5
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialization failed: {mt5.last_error()}")
    
    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features from raw OHLCV data (same as training).
        
        Args:
            df: Raw OHLCV data
        
        Returns:
            DataFrame with features
        """
        features = ['open', 'high', 'low', 'close', 'tick_volume']
        feature_df = df[features].copy()
        
        # Add technical indicators
        feature_df['rsi'] = self._calculate_rsi(df['close'], period=14)
        feature_df['ema_20'] = df['close'].ewm(span=20).mean()
        feature_df['ema_50'] = df['close'].ewm(span=50).mean()
        feature_df['atr'] = self._calculate_atr(df, period=14)
        feature_df['price_change'] = df['close'].pct_change()
        feature_df['high_low_ratio'] = df['high'] / df['low']
        feature_df['volume_ma'] = df['tick_volume'].rolling(window=20).mean()
        feature_df['volume_ratio'] = df['tick_volume'] / feature_df['volume_ma']
        
        feature_df = feature_df.dropna()
        return feature_df
    
    def _calculate_rsi(self, prices: pd.Series, period: int = 14) -> pd.Series:
        """Calculate RSI indicator."""
        delta = prices.diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))
        return rsi
    
    def _calculate_atr(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate ATR indicator."""
        high_low = df['high'] - df['low']
        high_close = np.abs(df['high'] - df['close'].shift())
        low_close = np.abs(df['low'] - df['close'].shift())
        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        atr = tr.rolling(window=period).mean()
        return atr
    
    def get_latest_data(self, symbol: str, timeframe: int, lookback: int) -> np.ndarray:
        """
        Get latest data from MT5 and prepare for prediction.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe
            lookback: Number of bars needed
        
        Returns:
            Prepared feature array ready for model input
        """
        # Fetch data
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, lookback + 50)
        
        if rates is None or len(rates) < lookback:
            raise ValueError(f"Insufficient data for {symbol}")
        
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        
        # Prepare features
        feature_df = self.prepare_features(df)
        
        # Get last lookback bars
        feature_data = feature_df.values[-lookback:]
        
        # Scale features
        if hasattr(self.scaler, 'scale_'):
            feature_data_scaled = self.scaler.transform(feature_data)
        else:
            # Fit scaler if not already fitted
            print("Warning: Scaler not fitted, fitting on current data...")
            feature_data_scaled = self.scaler.fit_transform(feature_data)
        
        # Reshape for model input: (1, lookback, features)
        feature_data_scaled = feature_data_scaled.reshape(1, lookback, -1)
        
        return feature_data_scaled.astype(np.float32)
    
    def predict(self, symbol: str, timeframe: int, lookback: int = None) -> float:
        """
        Make a prediction for the next price.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe
            lookback: Number of bars to use (default: from model input shape)
        
        Returns:
            Predicted price
        """
        if lookback is None:
            lookback = self.input_shape[1] if self.input_shape[1] else 60
        
        # Get and prepare data
        input_data = self.get_latest_data(symbol, timeframe, lookback)
        
        # Make prediction
        outputs = self.session.run([self.output_name], {self.input_name: input_data})
        prediction = outputs[0][0][0]
        
        return float(prediction)
    
    def predict_batch(self, symbol: str, timeframe: int, n_predictions: int = 5) -> list:
        """
        Make multiple predictions.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe
            n_predictions: Number of predictions to make
        
        Returns:
            List of predictions
        """
        predictions = []
        for _ in range(n_predictions):
            pred = self.predict(symbol, timeframe)
            predictions.append(pred)
        return predictions
    
    def cleanup(self):
        """Clean up MT5 connection."""
        mt5.shutdown()


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Make predictions using ONNX model')
    parser.add_argument('--model', type=str, required=True, 
                       help='Path to ONNX model file')
    parser.add_argument('--symbol', type=str, default='XAUUSD', 
                       help='Trading symbol')
    parser.add_argument('--timeframe', type=str, default='H1',
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Timeframe')
    parser.add_argument('--scaler', type=str, default=None,
                       help='Path to saved scaler (optional)')
    parser.add_argument('--predictions', type=int, default=1,
                       help='Number of predictions to make')
    
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
    
    # Create predictor
    predictor = ONNXPredictor(args.model, args.scaler)
    
    try:
        # Get current price
        symbol_info = mt5.symbol_info(args.symbol)
        current_price = symbol_info.bid if symbol_info else 0
        
        print(f"\nCurrent {args.symbol} price: {current_price:.5f}")
        print(f"Making {args.predictions} prediction(s)...\n")
        
        # Make predictions
        if args.predictions == 1:
            prediction = predictor.predict(args.symbol, timeframe)
            print(f"Predicted next price: {prediction:.5f}")
            print(f"Expected change: {(prediction - current_price):.5f} "
                  f"({((prediction - current_price) / current_price * 100):.2f}%)")
        else:
            predictions = predictor.predict_batch(args.symbol, timeframe, args.predictions)
            print("Predictions:")
            for i, pred in enumerate(predictions, 1):
                change = pred - current_price
                change_pct = (change / current_price * 100) if current_price > 0 else 0
                print(f"  {i}. {pred:.5f} (change: {change:+.5f}, {change_pct:+.2f}%)")
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
    finally:
        predictor.cleanup()


if __name__ == '__main__':
    main()
