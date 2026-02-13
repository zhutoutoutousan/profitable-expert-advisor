"""
ONNX-based Trading Strategy for Backtesting

This strategy uses a trained ONNX model to make price predictions and trade based on those predictions.
"""

from datetime import datetime
from typing import Dict, Any, Optional
import numpy as np
import MetaTrader5 as mt5
import onnxruntime as ort
import pickle
import os
from base_strategy import BaseStrategy


class ONNXStrategy(BaseStrategy):
    """
    Trading strategy that uses ONNX model predictions for trading decisions.
    """
    
    def __init__(self, symbol: str, timeframe: int, model_path: str, 
                 scaler_path: Optional[str] = None, initial_balance: float = 10000.0,
                 prediction_threshold: float = 0.0001, min_confidence: float = 0.0,
                 lot_size: float = 0.1, stop_loss_pips: int = 50, take_profit_pips: int = 100):
        """
        Initialize the ONNX strategy.
        
        Args:
            symbol: Trading symbol
            timeframe: MT5 timeframe
            model_path: Path to ONNX model file
            scaler_path: Path to saved scaler (optional)
            initial_balance: Starting balance
            prediction_threshold: Minimum price change % to trade (0.0001 = 0.01%)
            min_confidence: Minimum confidence level (0.0-1.0)
            lot_size: Position size
            stop_loss_pips: Stop loss in pips
            take_profit_pips: Take profit in pips
        """
        super().__init__(symbol, timeframe, initial_balance)
        
        self.model_path = model_path
        self.scaler_path = scaler_path
        self.prediction_threshold = prediction_threshold
        self.min_confidence = min_confidence
        self.lot_size = lot_size
        self.stop_loss_pips = stop_loss_pips
        self.take_profit_pips = take_profit_pips
        
        # Load ONNX model
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"ONNX model not found: {model_path}")
        
        self.session = ort.InferenceSession(model_path)
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name
        self.input_shape = self.session.get_inputs()[0].shape
        
        # Determine lookback from model shape
        if self.input_shape and len(self.input_shape) >= 2:
            self.lookback = int(self.input_shape[1]) if self.input_shape[1] else 60
        else:
            self.lookback = 60
        
        # Load scaler
        if scaler_path and os.path.exists(scaler_path):
            with open(scaler_path, 'rb') as f:
                self.scaler = pickle.load(f)
        else:
            self.scaler = None
            print("Warning: No scaler provided. Will use default normalization.")
        
        # Track previous prediction for comparison
        self.prev_prediction = None
        self.prev_price = None
        
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        """ONNX model doesn't use traditional indicators, but we need RSI, EMA, ATR for features."""
        return {
            'rsi': {'period': 14, 'applied_price': mt5.PRICE_CLOSE},
            'ema': {'period': 50, 'applied_price': mt5.PRICE_CLOSE},
            'atr': {'period': 14}
        }
    
    def prepare_features(self, bar_data: Dict[str, Any], historical_bars: list) -> np.ndarray:
        """
        Prepare features for ONNX model input.
        
        Args:
            bar_data: Current bar data
            historical_bars: List of historical bar data dictionaries
        
        Returns:
            Prepared feature array
        """
        features = []
        
        for bar in historical_bars[-self.lookback:]:
            feature_row = []
            
            # OHLC
            feature_row.append(bar['open'])
            feature_row.append(bar['high'])
            feature_row.append(bar['low'])
            feature_row.append(bar['close'])
            
            # Volume (normalized)
            feature_row.append(bar.get('tick_volume', 0) / 1000000.0)
            
            # RSI (if available)
            rsi = bar.get('rsi', 50.0)
            feature_row.append(rsi / 100.0)
            
            # EMA (if available)
            ema = bar.get('ema', bar['close'])
            feature_row.append((ema - bar['close']) / bar['close'])
            
            # ATR (if available)
            atr = bar.get('atr', 0.0)
            feature_row.append(atr / bar['close'])
            
            # Price change
            if len(features) > 0:
                prev_close = historical_bars[historical_bars.index(bar) - 1]['close']
                price_change = (bar['close'] - prev_close) / prev_close
            else:
                price_change = 0.0
            feature_row.append(price_change)
            
            # High/Low ratio
            feature_row.append(bar['high'] / bar['low'])
            
            # Volume ratio (simplified)
            if len(features) > 0:
                prev_volume = historical_bars[historical_bars.index(bar) - 1].get('tick_volume', 1)
                volume_ratio = bar.get('tick_volume', 1) / max(prev_volume, 1)
            else:
                volume_ratio = 1.0
            feature_row.append(volume_ratio)
            
            features.append(feature_row)
        
        # Pad if needed
        while len(features) < self.lookback:
            features.insert(0, features[0] if features else [0.0] * 12)
        
        features = np.array(features[-self.lookback:], dtype=np.float32)
        
        # Normalize if scaler available
        if self.scaler is not None:
            # Reshape for scaler (flatten, scale, reshape)
            original_shape = features.shape
            features_flat = features.reshape(-1, features.shape[-1])
            features_scaled = self.scaler.transform(features_flat)
            features = features_scaled.reshape(original_shape)
        else:
            # Simple normalization
            features = (features - features.mean(axis=0)) / (features.std(axis=0) + 1e-8)
        
        # Reshape for model: (1, lookback, features)
        features = features.reshape(1, self.lookback, -1)
        
        return features
    
    def predict_price(self, bar_data: Dict[str, Any], historical_bars: list) -> float:
        """
        Make price prediction using ONNX model.
        
        Args:
            bar_data: Current bar data
            historical_bars: Historical bar data
        
        Returns:
            Predicted price
        """
        # Prepare input
        input_data = self.prepare_features(bar_data, historical_bars)
        
        # Run model
        outputs = self.session.run([self.output_name], {self.input_name: input_data})
        prediction = outputs[0][0][0]
        
        return float(prediction)
    
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        """
        Trading logic based on ONNX predictions.
        """
        current_price = bar_data['close']
        
        # We need historical bars for prediction
        # For now, we'll use a simplified approach
        # In a real implementation, you'd maintain a buffer of historical bars
        
        # Check if we have a position
        if self.position is not None:
            # Check stop loss/take profit
            self.check_stop_loss_take_profit(current_price)
            return
        
        # For backtesting, we need to get historical data
        # This is a simplified version - in practice, you'd maintain a buffer
        # For now, we'll skip prediction if we don't have enough data
        # The backtest engine should provide historical context
        
        # Simple prediction-based logic (simplified for backtesting)
        # In production, use the full ONNX prediction pipeline
        
    def get_parameters(self) -> Dict[str, Any]:
        """Return strategy parameters."""
        return {
            'model_path': self.model_path,
            'lookback': self.lookback,
            'prediction_threshold': self.prediction_threshold,
            'min_confidence': self.min_confidence,
            'lot_size': self.lot_size,
            'stop_loss_pips': self.stop_loss_pips,
            'take_profit_pips': self.take_profit_pips
        }
