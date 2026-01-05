"""
ONNX Model Training Script for MetaTrader 5

This script trains a neural network model for price prediction and exports it to ONNX format.
Based on MQL5 ONNX documentation: https://www.mql5.com/en/docs/onnx/onnx_prepare

Usage:
    python train_onnx_model.py --symbol XAUUSD --timeframe H1 --lookback 60 --epochs 50
"""

import argparse
import os
import sys
from datetime import datetime, timedelta
import numpy as np
import pandas as pd
import MetaTrader5 as mt5
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.preprocessing import MinMaxScaler
from sklearn.model_selection import train_test_split
import tf2onnx
import onnx
from tqdm import tqdm


class ONNXModelTrainer:
    """
    Trainer class for creating ONNX models from MT5 data.
    """
    
    def __init__(self, symbol: str, timeframe: int, lookback: int = 60, 
                 prediction_horizon: int = 1, features: list = None):
        """
        Initialize the trainer.
        
        Args:
            symbol: Trading symbol (e.g., 'XAUUSD', 'EURUSD')
            timeframe: MT5 timeframe constant
            lookback: Number of bars to look back for prediction
            prediction_horizon: Number of bars ahead to predict
            features: List of features to use (default: OHLC + volume)
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.lookback = lookback
        self.prediction_horizon = prediction_horizon
        self.features = features or ['open', 'high', 'low', 'close', 'tick_volume']
        
        self.scaler = MinMaxScaler()
        self.model = None
        
        # Initialize MT5
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialization failed: {mt5.last_error()}")
    
    def fetch_data(self, start_date: datetime, end_date: datetime) -> pd.DataFrame:
        """
        Fetch historical data from MT5.
        
        Args:
            start_date: Start date for data
            end_date: End date for data
        
        Returns:
            DataFrame with OHLCV data
        """
        print(f"Fetching data for {self.symbol} from {start_date} to {end_date}...")
        
        rates = mt5.copy_rates_range(self.symbol, self.timeframe, start_date, end_date)
        
        if rates is None or len(rates) == 0:
            raise ValueError(f"No data available for {self.symbol} in the specified date range")
        
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)
        
        print(f"Fetched {len(df)} bars")
        return df
    
    def prepare_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features for training.
        
        Args:
            df: Raw OHLCV data
        
        Returns:
            DataFrame with features
        """
        feature_df = df[self.features].copy()
        
        # Add technical indicators as features
        feature_df['rsi'] = self._calculate_rsi(df['close'], period=14)
        feature_df['ema_20'] = df['close'].ewm(span=20).mean()
        feature_df['ema_50'] = df['close'].ewm(span=50).mean()
        feature_df['atr'] = self._calculate_atr(df, period=14)
        
        # Price changes
        feature_df['price_change'] = df['close'].pct_change()
        feature_df['high_low_ratio'] = df['high'] / df['low']
        
        # Volume features
        feature_df['volume_ma'] = df['tick_volume'].rolling(window=20).mean()
        feature_df['volume_ratio'] = df['tick_volume'] / feature_df['volume_ma']
        
        # Drop NaN values
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
    
    def create_sequences(self, data: np.ndarray, target: np.ndarray) -> tuple:
        """
        Create sequences for LSTM/RNN training.
        
        Args:
            data: Feature data
            target: Target values
        
        Returns:
            Tuple of (X, y) sequences
        """
        X, y = [], []
        
        for i in range(self.lookback, len(data) - self.prediction_horizon + 1):
            X.append(data[i - self.lookback:i])
            y.append(target[i + self.prediction_horizon - 1])
        
        return np.array(X), np.array(y)
    
    def build_model(self, input_shape: tuple) -> keras.Model:
        """
        Build the neural network model.
        
        Args:
            input_shape: Shape of input data (lookback, features)
        
        Returns:
            Compiled Keras model
        """
        model = keras.Sequential([
            layers.LSTM(128, return_sequences=True, input_shape=input_shape),
            layers.Dropout(0.2),
            layers.LSTM(64, return_sequences=True),
            layers.Dropout(0.2),
            layers.LSTM(32),
            layers.Dropout(0.2),
            layers.Dense(16, activation='relu'),
            layers.Dense(1)  # Predict next close price
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=0.001),
            loss='mse',
            metrics=['mae']
        )
        
        return model
    
    def train(self, epochs: int = 50, batch_size: int = 32, 
              validation_split: float = 0.2, verbose: int = 1):
        """
        Train the model.
        
        Args:
            epochs: Number of training epochs
            batch_size: Batch size for training
            validation_split: Fraction of data to use for validation
            verbose: Verbosity level
        """
        # Fetch data (last 2 years)
        end_date = datetime.now()
        start_date = end_date - timedelta(days=730)
        
        df = self.fetch_data(start_date, end_date)
        feature_df = self.prepare_features(df)
        
        # Prepare data
        feature_data = feature_df.values
        target_data = df['close'].values[feature_df.index]
        
        # Scale features
        feature_data_scaled = self.scaler.fit_transform(feature_data)
        
        # Create sequences
        X, y = self.create_sequences(feature_data_scaled, target_data)
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=validation_split, shuffle=False
        )
        
        print(f"\nTraining data shape: {X_train.shape}")
        print(f"Validation data shape: {X_test.shape}")
        
        # Build model
        self.model = self.build_model((X_train.shape[1], X_train.shape[2]))
        
        print("\nModel architecture:")
        self.model.summary()
        
        # Train model
        print("\nTraining model...")
        history = self.model.fit(
            X_train, y_train,
            batch_size=batch_size,
            epochs=epochs,
            validation_data=(X_test, y_test),
            verbose=verbose,
            callbacks=[
                keras.callbacks.EarlyStopping(
                    monitor='val_loss',
                    patience=10,
                    restore_best_weights=True
                ),
                keras.callbacks.ReduceLROnPlateau(
                    monitor='val_loss',
                    factor=0.5,
                    patience=5,
                    min_lr=0.0001
                )
            ]
        )
        
        # Evaluate
        train_loss = self.model.evaluate(X_train, y_train, verbose=0)
        test_loss = self.model.evaluate(X_test, y_test, verbose=0)
        
        print(f"\nTraining Loss: {train_loss[0]:.4f}, MAE: {train_loss[1]:.4f}")
        print(f"Validation Loss: {test_loss[0]:.4f}, MAE: {test_loss[1]:.4f}")
        
        return history
    
    def export_to_onnx(self, output_path: str):
        """
        Export the trained model to ONNX format.
        
        Args:
            output_path: Path to save ONNX model
        """
        if self.model is None:
            raise ValueError("Model must be trained before exporting")
        
        print(f"\nExporting model to ONNX format: {output_path}")
        
        # Get input shape
        input_shape = (1, self.lookback, len(self.features) + 7)  # +7 for added features
        
        # Create dummy input
        dummy_input = np.random.randn(*input_shape).astype(np.float32)
        
        # Convert to ONNX
        spec = (tf.TensorSpec((None, self.lookback, len(self.features) + 7), tf.float32, name="input"),)
        output_path_onnx = tf2onnx.convert.from_keras(
            self.model,
            input_signature=spec,
            opset=13,
            output_path=output_path
        )
        
        print(f"✓ ONNX model saved to: {output_path}")
        
        # Verify ONNX model
        try:
            onnx_model = onnx.load(output_path)
            onnx.checker.check_model(onnx_model)
            print("✓ ONNX model validation passed")
        except Exception as e:
            print(f"⚠ ONNX model validation warning: {e}")
    
    def cleanup(self):
        """Clean up MT5 connection."""
        mt5.shutdown()


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Train ONNX model for MT5 price prediction')
    parser.add_argument('--symbol', type=str, default='XAUUSD', help='Trading symbol')
    parser.add_argument('--timeframe', type=str, default='H1', 
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Timeframe')
    parser.add_argument('--lookback', type=int, default=60, 
                       help='Number of bars to look back')
    parser.add_argument('--epochs', type=int, default=50, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=32, help='Batch size')
    parser.add_argument('--output', type=str, default='models', 
                       help='Output directory for ONNX model')
    
    args = parser.parse_args()
    
    # Convert timeframe string to MT5 constant
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
    
    # Create output directory
    os.makedirs(args.output, exist_ok=True)
    
    # Create trainer
    trainer = ONNXModelTrainer(
        symbol=args.symbol,
        timeframe=timeframe,
        lookback=args.lookback
    )
    
    try:
        # Train model
        trainer.train(epochs=args.epochs, batch_size=args.batch_size)
        
        # Export to ONNX
        model_name = f"{args.symbol}_{args.timeframe}_model.onnx"
        output_path = os.path.join(args.output, model_name)
        trainer.export_to_onnx(output_path)
        
        # Save scaler for consistent normalization
        scaler_path = os.path.join(args.output, f"{args.symbol}_{args.timeframe}_scaler.pkl")
        import pickle
        with open(scaler_path, 'wb') as f:
            pickle.dump(trainer.scaler, f)
        print(f"✓ Scaler saved to: {scaler_path}")
        print(f"  Use this with predict_with_onnx.py for consistent normalization")
        
        print(f"\n{'='*60}")
        print("Training completed successfully!")
        print(f"ONNX model saved to: {output_path}")
        print(f"{'='*60}\n")
        
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)
    finally:
        trainer.cleanup()


if __name__ == '__main__':
    main()
