"""
Enhanced ONNX Strategy for Backtesting with Historical Data Buffer

This version maintains a buffer of historical bars for proper ONNX predictions.
"""

from datetime import datetime
from typing import Dict, Any, Optional, List
import numpy as np
import MetaTrader5 as mt5
import onnxruntime as ort
import pickle
import os
from base_strategy import BaseStrategy


class ONNXBacktestStrategy(BaseStrategy):
    """
    ONNX strategy with historical data buffer for backtesting.
    """
    
    def __init__(self, symbol: str, timeframe: int, model_path: str, 
                 scaler_path: Optional[str] = None, initial_balance: float = 10000.0,
                 prediction_threshold: float = 0.0001, min_confidence: float = 0.0,
                 lot_size: float = 0.1, stop_loss_pips: int = 50, take_profit_pips: int = 100):
        """
        Initialize the ONNX backtest strategy.
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
        
        # Determine lookback
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
        
        # Historical data buffer
        self.historical_bars: List[Dict[str, Any]] = []
        
    def get_required_indicators(self) -> Dict[str, Dict[str, Any]]:
        """Required indicators for feature preparation."""
        # MT5 uses PRICE_CLOSE constant, but if not available, use 0 (close price)
        price_close = getattr(mt5, 'PRICE_CLOSE', 0)
        return {
            'rsi': {'period': 14, 'applied_price': price_close},
            'ema': {'period': 50, 'applied_price': price_close},
            'atr': {'period': 14}
        }
    
    def prepare_features(self) -> np.ndarray:
        """Prepare features from historical buffer - must match training features (13 total)."""
        if len(self.historical_bars) < self.lookback:
            return None
        
        features = []
        bars_to_use = self.historical_bars[-self.lookback:]
        
        # Calculate EMA20 and volume MA for all bars first
        closes = [bar['close'] for bar in bars_to_use]
        volumes = [bar.get('tick_volume', 0) for bar in bars_to_use]
        
        # Calculate EMA20 (using pandas-like ewm)
        import pandas as pd
        closes_series = pd.Series(closes)
        ema20_values = closes_series.ewm(span=20, adjust=False).mean().tolist()
        
        # Calculate volume MA
        volumes_series = pd.Series(volumes)
        volume_ma_values = volumes_series.rolling(window=20, min_periods=1).mean().tolist()
        
        for i, bar in enumerate(bars_to_use):
            feature_row = []
            
            # OHLC (4 features)
            feature_row.append(bar['open'])
            feature_row.append(bar['high'])
            feature_row.append(bar['low'])
            feature_row.append(bar['close'])
            
            # Volume (1 feature)
            volume = bar.get('tick_volume', 0)
            feature_row.append(volume / 1000000.0)
            
            # RSI (1 feature)
            rsi = bar.get('rsi', 50.0)
            feature_row.append(rsi / 100.0)
            
            # EMA20 (1 feature) - normalized difference
            ema20 = ema20_values[i] if i < len(ema20_values) else bar['close']
            feature_row.append((ema20 - bar['close']) / bar['close'] if bar['close'] > 0 else 0.0)
            
            # EMA50 (1 feature) - normalized difference
            ema50 = bar.get('ema', bar['close'])
            feature_row.append((ema50 - bar['close']) / bar['close'] if bar['close'] > 0 else 0.0)
            
            # ATR (1 feature)
            atr = bar.get('atr', 0.0)
            feature_row.append(atr / bar['close'] if bar['close'] > 0 else 0.0)
            
            # Price change (1 feature)
            if i > 0:
                prev_close = bars_to_use[i-1]['close']
                price_change = (bar['close'] - prev_close) / prev_close if prev_close > 0 else 0.0
            else:
                price_change = 0.0
            feature_row.append(price_change)
            
            # High/Low ratio (1 feature)
            feature_row.append(bar['high'] / bar['low'] if bar['low'] > 0 else 1.0)
            
            # Volume MA and ratio (2 features)
            volume_ma = volume_ma_values[i] if i < len(volume_ma_values) else max(volume, 1)
            volume_ratio = volume / max(volume_ma, 1) if volume_ma > 0 else 1.0
            feature_row.append(volume_ma / 1000000.0)  # Normalized volume MA
            feature_row.append(volume_ratio)
            
            features.append(feature_row)
        
        features = np.array(features, dtype=np.float32)
        
        # Normalize
        if self.scaler is not None:
            original_shape = features.shape
            features_flat = features.reshape(-1, features.shape[-1])
            features_scaled = self.scaler.transform(features_flat)
            features = features_scaled.reshape(original_shape)
        else:
            # Simple normalization
            mean = features.mean(axis=0)
            std = features.std(axis=0) + 1e-8
            features = (features - mean) / std
        
        # Reshape for model: (1, lookback, features)
        features = features.reshape(1, self.lookback, -1)
        
        return features
    
    def predict_price(self) -> Optional[float]:
        """Make prediction using ONNX model."""
        if len(self.historical_bars) < self.lookback:
            return None
        
        input_data = self.prepare_features()
        if input_data is None:
            return None
        
        try:
            outputs = self.session.run([self.output_name], {self.input_name: input_data})
            prediction = outputs[0][0][0]
            
            # Model now predicts price change percentage (e.g., -0.003 = -0.3%)
            # These values should be between -1 and 1 (or slightly outside for extreme cases)
            # Don't filter based on absolute price range anymore
            
            return float(prediction)
        except Exception as e:
            print(f"Prediction error: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def on_bar(self, bar_data: Dict[str, Any]) -> None:
        """Trading logic based on ONNX predictions."""
        # Add current bar to historical buffer
        self.historical_bars.append(bar_data.copy())
        
        # Keep only necessary history
        if len(self.historical_bars) > self.lookback + 50:
            self.historical_bars = self.historical_bars[-(self.lookback + 50):]
        
        # Check if we have enough data
        if len(self.historical_bars) < self.lookback:
            return
        
        current_price = bar_data['close']
        
        # Check existing position
        if self.position is not None:
            self.check_stop_loss_take_profit(current_price)
            return
        
        # Make prediction
        # Model now predicts price change percentage directly (e.g., 0.001 = 0.1%)
        predicted_change_pct = self.predict_price()
        if predicted_change_pct is None:
            return
        
        # Model predicts price change percentage directly
        # Check if it's a percentage (between -1 and 1) or absolute price
        if abs(predicted_change_pct) < 1.0:
            # It's already a percentage (e.g., 0.001 = 0.1%)
            price_change_pct = predicted_change_pct
        else:
            # It's an absolute price (old model format), convert to percentage
            predicted_price = predicted_change_pct
            if predicted_price <= 0 or predicted_price > 10000:
                return  # Invalid prediction
            price_change = predicted_price - current_price
            price_change_pct = (price_change / current_price) if current_price > 0 else 0.0
        
        # Calculate confidence (simple heuristic)
        # For percentage predictions (0.001 = 0.1%), normalize to 0-1
        # If price_change_pct is already a percentage (e.g., 0.001), use it directly
        # If it's a large number, it's already in percentage form
        if abs(price_change_pct) < 1.0:
            # It's a decimal percentage (e.g., 0.001 = 0.1%)
            confidence = min(abs(price_change_pct) / 0.01, 1.0)  # Normalize: 0.01 = 1% = 100% confidence
        else:
            # It's already in percentage form (e.g., 0.1 = 0.1%)
            confidence = min(abs(price_change_pct) / 1.0, 1.0)  # Normalize: 1% = 100% confidence
        
        # Debug: Print first few predictions (only for debugging)
        if len(self.historical_bars) % 100 == 0:
            predicted_price_val = current_price * (1 + price_change_pct) if abs(price_change_pct) < 1.0 else current_price * (1 + price_change_pct / 100)
            print(f"  Debug - Bar {len(self.historical_bars)}, Price: {current_price:.2f}, "
                  f"Predicted Change: {price_change_pct*100:.4f}%, Abs: {abs(price_change_pct):.6f}, "
                  f"Confidence: {confidence:.3f}, Threshold: {self.prediction_threshold:.6f}, "
                  f"MinConf: {self.min_confidence:.2f}, WillTrade: {abs(price_change_pct) >= self.prediction_threshold and confidence >= self.min_confidence}")
        
        # Check if we should trade
        if confidence < self.min_confidence:
            return
        
        if abs(price_change_pct) < self.prediction_threshold:
            return
        
        # Open position based on prediction
        if price_change_pct > self.prediction_threshold:
            # Bullish prediction
            sl = current_price - (self.stop_loss_pips / 10000) if self.stop_loss_pips > 0 else None
            tp = current_price + (self.take_profit_pips / 10000) if self.take_profit_pips > 0 else None
            self.open_position('BUY', self.lot_size, current_price, sl, tp, 'ONNX Buy')
        
        elif price_change_pct < -self.prediction_threshold:
            # Bearish prediction
            sl = current_price + (self.stop_loss_pips / 10000) if self.stop_loss_pips > 0 else None
            tp = current_price - (self.take_profit_pips / 10000) if self.take_profit_pips > 0 else None
            self.open_position('SELL', self.lot_size, current_price, sl, tp, 'ONNX Sell')
    
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
