"""
RSI Divergence Detection Module
Detects regular and hidden RSI divergences in price action.

Regular Divergence:
- Bullish: Price makes lower low, RSI makes higher low (reversal signal)
- Bearish: Price makes higher high, RSI makes lower high (reversal signal)

Hidden Divergence:
- Bullish: Price makes higher low, RSI makes lower low (continuation signal)
- Bearish: Price makes lower high, RSI makes higher high (continuation signal)
"""

import numpy as np
import pandas as pd
from typing import Tuple, Optional, List, Dict
from dataclasses import dataclass
from enum import Enum


class DivergenceType(Enum):
    """Types of RSI divergences"""
    NONE = 0
    REGULAR_BULLISH = 1  # Price lower low, RSI higher low
    REGULAR_BEARISH = 2  # Price higher high, RSI lower high
    HIDDEN_BULLISH = 3   # Price higher low, RSI lower low
    HIDDEN_BEARISH = 4   # Price lower high, RSI higher high


@dataclass
class DivergenceSignal:
    """Represents a detected divergence signal"""
    type: DivergenceType
    price_swing_start: int  # Index of price swing start
    price_swing_end: int    # Index of price swing end
    rsi_swing_start: int   # Index of RSI swing start
    rsi_swing_end: int      # Index of RSI swing end
    price_start: float      # Price at swing start
    price_end: float        # Price at swing end
    rsi_start: float        # RSI at swing start
    rsi_end: float          # RSI at swing end
    strength: float         # Divergence strength (0-1)
    confidence: float       # Confidence score (0-1)
    timestamp: pd.Timestamp


class RSIDivergenceDetector:
    """
    Detects RSI divergences in price data.
    """
    
    def __init__(self, rsi_period: int = 14, min_swing_bars: int = 5, 
                 max_swing_bars: int = 50, min_divergence_strength: float = 0.1):
        """
        Initialize the RSI divergence detector.
        
        Args:
            rsi_period: Period for RSI calculation
            min_swing_bars: Minimum bars for a valid swing
            max_swing_bars: Maximum bars to look back for swings
            min_divergence_strength: Minimum strength for valid divergence
        """
        self.rsi_period = rsi_period
        self.min_swing_bars = min_swing_bars
        self.max_swing_bars = max_swing_bars
        self.min_divergence_strength = min_divergence_strength
    
    def calculate_rsi(self, prices: pd.Series, period: int = None) -> pd.Series:
        """
        Calculate RSI indicator.
        
        Args:
            prices: Price series (typically close prices)
            period: RSI period (defaults to self.rsi_period)
        
        Returns:
            RSI values
        """
        if period is None:
            period = self.rsi_period
        
        delta = prices.diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        
        # Avoid division by zero
        rs = gain / (loss + 1e-10)
        rsi = 100 - (100 / (1 + rs))
        
        return rsi
    
    def find_swings(self, data: pd.Series, lookback: int = None) -> Tuple[List[int], List[int]]:
        """
        Find swing highs and lows in the data.
        
        Args:
            data: Series to find swings in (price or RSI)
            lookback: Number of bars to look back (defaults to max_swing_bars)
        
        Returns:
            Tuple of (swing_highs, swing_lows) - lists of indices
        """
        if lookback is None:
            lookback = self.max_swing_bars
        
        swing_highs = []
        swing_lows = []
        
        for i in range(lookback, len(data) - lookback):
            # Check for swing high
            is_swing_high = True
            for j in range(i - lookback, i + lookback + 1):
                if j != i and data.iloc[j] >= data.iloc[i]:
                    is_swing_high = False
                    break
            
            if is_swing_high:
                swing_highs.append(i)
            
            # Check for swing low
            is_swing_low = True
            for j in range(i - lookback, i + lookback + 1):
                if j != i and data.iloc[j] <= data.iloc[i]:
                    is_swing_low = False
                    break
            
            if is_swing_low:
                swing_lows.append(i)
        
        return swing_highs, swing_lows
    
    def detect_divergence(self, df: pd.DataFrame, current_index: int) -> Optional[DivergenceSignal]:
        """
        Detect divergence at the current index.
        
        Args:
            df: DataFrame with 'close' and 'rsi' columns
            current_index: Current bar index to check for divergence
        
        Returns:
            DivergenceSignal if found, None otherwise
        """
        if current_index < self.max_swing_bars * 2:
            return None
        
        # Get price and RSI data up to current index
        price_data = df['close'].iloc[:current_index + 1]
        rsi_data = df['rsi'].iloc[:current_index + 1]
        
        # Find recent swings
        price_highs, price_lows = self.find_swings(price_data, self.max_swing_bars)
        rsi_highs, rsi_lows = self.find_swings(rsi_data, self.max_swing_bars)
        
        if len(price_highs) < 2 or len(price_lows) < 2:
            return None
        if len(rsi_highs) < 2 or len(rsi_lows) < 2:
            return None
        
        # Get the two most recent swings
        current_price = price_data.iloc[current_index]
        current_rsi = rsi_data.iloc[current_index]
        
        # Check for regular bearish divergence (price higher high, RSI lower high)
        if len(price_highs) >= 2 and len(rsi_highs) >= 2:
            price_high_1_idx = price_highs[-1]
            price_high_2_idx = price_highs[-2] if len(price_highs) >= 2 else price_highs[-1]
            
            rsi_high_1_idx = rsi_highs[-1]
            rsi_high_2_idx = rsi_highs[-2] if len(rsi_highs) >= 2 else rsi_highs[-1]
            
            # Regular bearish: price higher high, RSI lower high
            if (price_high_1_idx == current_index or abs(price_high_1_idx - current_index) <= 3):
                if price_data.iloc[price_high_1_idx] > price_data.iloc[price_high_2_idx]:
                    if rsi_data.iloc[rsi_high_1_idx] < rsi_data.iloc[rsi_high_2_idx]:
                        strength = self._calculate_strength(
                            price_data.iloc[price_high_2_idx], price_data.iloc[price_high_1_idx],
                            rsi_data.iloc[rsi_high_2_idx], rsi_data.iloc[rsi_high_1_idx]
                        )
                        if strength >= self.min_divergence_strength:
                            return DivergenceSignal(
                                type=DivergenceType.REGULAR_BEARISH,
                                price_swing_start=price_high_2_idx,
                                price_swing_end=price_high_1_idx,
                                rsi_swing_start=rsi_high_2_idx,
                                rsi_swing_end=rsi_high_1_idx,
                                price_start=price_data.iloc[price_high_2_idx],
                                price_end=price_data.iloc[price_high_1_idx],
                                rsi_start=rsi_data.iloc[rsi_high_2_idx],
                                rsi_end=rsi_data.iloc[rsi_high_1_idx],
                                strength=strength,
                                confidence=self._calculate_confidence(df, price_high_1_idx, DivergenceType.REGULAR_BEARISH),
                                timestamp=df.index[current_index]
                            )
        
        # Check for regular bullish divergence (price lower low, RSI higher low)
        if len(price_lows) >= 2 and len(rsi_lows) >= 2:
            price_low_1_idx = price_lows[-1]
            price_low_2_idx = price_lows[-2] if len(price_lows) >= 2 else price_lows[-1]
            
            rsi_low_1_idx = rsi_lows[-1]
            rsi_low_2_idx = rsi_lows[-2] if len(rsi_lows) >= 2 else rsi_lows[-1]
            
            # Regular bullish: price lower low, RSI higher low
            if (price_low_1_idx == current_index or abs(price_low_1_idx - current_index) <= 3):
                if price_data.iloc[price_low_1_idx] < price_data.iloc[price_low_2_idx]:
                    if rsi_data.iloc[rsi_low_1_idx] > rsi_data.iloc[rsi_low_2_idx]:
                        strength = self._calculate_strength(
                            price_data.iloc[price_low_2_idx], price_data.iloc[price_low_1_idx],
                            rsi_data.iloc[rsi_low_2_idx], rsi_data.iloc[rsi_low_1_idx],
                            reverse=True
                        )
                        if strength >= self.min_divergence_strength:
                            return DivergenceSignal(
                                type=DivergenceType.REGULAR_BULLISH,
                                price_swing_start=price_low_2_idx,
                                price_swing_end=price_low_1_idx,
                                rsi_swing_start=rsi_low_2_idx,
                                rsi_swing_end=rsi_low_1_idx,
                                price_start=price_data.iloc[price_low_2_idx],
                                price_end=price_data.iloc[price_low_1_idx],
                                rsi_start=rsi_data.iloc[rsi_low_2_idx],
                                rsi_end=rsi_data.iloc[rsi_low_1_idx],
                                strength=strength,
                                confidence=self._calculate_confidence(df, price_low_1_idx, DivergenceType.REGULAR_BULLISH),
                                timestamp=df.index[current_index]
                            )
        
        # Check for hidden bearish divergence (price lower high, RSI higher high)
        if len(price_highs) >= 2 and len(rsi_highs) >= 2:
            price_high_1_idx = price_highs[-1]
            price_high_2_idx = price_highs[-2] if len(price_highs) >= 2 else price_highs[-1]
            
            rsi_high_1_idx = rsi_highs[-1]
            rsi_high_2_idx = rsi_highs[-2] if len(rsi_highs) >= 2 else rsi_highs[-1]
            
            # Hidden bearish: price lower high, RSI higher high
            if (price_high_1_idx == current_index or abs(price_high_1_idx - current_index) <= 3):
                if price_data.iloc[price_high_1_idx] < price_data.iloc[price_high_2_idx]:
                    if rsi_data.iloc[rsi_high_1_idx] > rsi_data.iloc[rsi_high_2_idx]:
                        strength = self._calculate_strength(
                            price_data.iloc[price_high_2_idx], price_data.iloc[price_high_1_idx],
                            rsi_data.iloc[rsi_high_2_idx], rsi_data.iloc[rsi_high_1_idx]
                        )
                        if strength >= self.min_divergence_strength:
                            return DivergenceSignal(
                                type=DivergenceType.HIDDEN_BEARISH,
                                price_swing_start=price_high_2_idx,
                                price_swing_end=price_high_1_idx,
                                rsi_swing_start=rsi_high_2_idx,
                                rsi_swing_end=rsi_high_1_idx,
                                price_start=price_data.iloc[price_high_2_idx],
                                price_end=price_data.iloc[price_high_1_idx],
                                rsi_start=rsi_data.iloc[rsi_high_2_idx],
                                rsi_end=rsi_data.iloc[rsi_high_1_idx],
                                strength=strength,
                                confidence=self._calculate_confidence(df, price_high_1_idx, DivergenceType.HIDDEN_BEARISH),
                                timestamp=df.index[current_index]
                            )
        
        # Check for hidden bullish divergence (price higher low, RSI lower low)
        if len(price_lows) >= 2 and len(rsi_lows) >= 2:
            price_low_1_idx = price_lows[-1]
            price_low_2_idx = price_lows[-2] if len(price_lows) >= 2 else price_lows[-1]
            
            rsi_low_1_idx = rsi_lows[-1]
            rsi_low_2_idx = rsi_lows[-2] if len(rsi_lows) >= 2 else rsi_lows[-1]
            
            # Hidden bullish: price higher low, RSI lower low
            if (price_low_1_idx == current_index or abs(price_low_1_idx - current_index) <= 3):
                if price_data.iloc[price_low_1_idx] > price_data.iloc[price_low_2_idx]:
                    if rsi_data.iloc[rsi_low_1_idx] < rsi_data.iloc[rsi_low_2_idx]:
                        strength = self._calculate_strength(
                            price_data.iloc[price_low_2_idx], price_data.iloc[price_low_1_idx],
                            rsi_data.iloc[rsi_low_2_idx], rsi_data.iloc[rsi_low_1_idx],
                            reverse=True
                        )
                        if strength >= self.min_divergence_strength:
                            return DivergenceSignal(
                                type=DivergenceType.HIDDEN_BULLISH,
                                price_swing_start=price_low_2_idx,
                                price_swing_end=price_low_1_idx,
                                rsi_swing_start=rsi_low_2_idx,
                                rsi_swing_end=rsi_low_1_idx,
                                price_start=price_data.iloc[price_low_2_idx],
                                price_end=price_data.iloc[price_low_1_idx],
                                rsi_start=rsi_data.iloc[rsi_low_2_idx],
                                rsi_end=rsi_data.iloc[rsi_low_1_idx],
                                strength=strength,
                                confidence=self._calculate_confidence(df, price_low_1_idx, DivergenceType.HIDDEN_BULLISH),
                                timestamp=df.index[current_index]
                            )
        
        return None
    
    def _calculate_strength(self, price1: float, price2: float, 
                           rsi1: float, rsi2: float, reverse: bool = False) -> float:
        """
        Calculate divergence strength (0-1).
        
        Args:
            price1: First price value
            price2: Second price value
            rsi1: First RSI value
            rsi2: Second RSI value
            reverse: If True, reverse the calculation for bullish divergences
        
        Returns:
            Strength score (0-1)
        """
        if price1 == 0 or price2 == 0:
            return 0.0
        
        price_change_pct = abs((price2 - price1) / price1)
        rsi_change = abs(rsi2 - rsi1)
        
        # Normalize to 0-1 range
        price_strength = min(price_change_pct * 10, 1.0)  # Scale price change
        rsi_strength = min(rsi_change / 20.0, 1.0)  # Scale RSI change (max ~20 points)
        
        # Combined strength
        strength = (price_strength + rsi_strength) / 2.0
        
        return min(max(strength, 0.0), 1.0)
    
    def _calculate_confidence(self, df: pd.DataFrame, signal_index: int, 
                              divergence_type: DivergenceType) -> float:
        """
        Calculate confidence score for a divergence signal.
        
        Args:
            df: DataFrame with market data
            signal_index: Index where divergence was detected
            divergence_type: Type of divergence
        
        Returns:
            Confidence score (0-1)
        """
        confidence = 0.5  # Base confidence
        
        # Check RSI extremes
        if signal_index < len(df):
            rsi = df['rsi'].iloc[signal_index]
            
            # Higher confidence if RSI is in extreme zones
            if divergence_type in [DivergenceType.REGULAR_BULLISH, DivergenceType.HIDDEN_BULLISH]:
                if rsi < 30:
                    confidence += 0.2
                elif rsi < 40:
                    confidence += 0.1
            elif divergence_type in [DivergenceType.REGULAR_BEARISH, DivergenceType.HIDDEN_BEARISH]:
                if rsi > 70:
                    confidence += 0.2
                elif rsi > 60:
                    confidence += 0.1
        
        # Check volume (if available)
        if 'tick_volume' in df.columns and signal_index < len(df):
            volume = df['tick_volume'].iloc[signal_index]
            avg_volume = df['tick_volume'].rolling(20).mean().iloc[signal_index] if signal_index >= 20 else volume
            
            if avg_volume > 0:
                volume_ratio = volume / avg_volume
                if volume_ratio > 1.2:  # Higher volume increases confidence
                    confidence += 0.1
        
        return min(max(confidence, 0.0), 1.0)
    
    def label_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Label entire dataset with divergence signals.
        
        Args:
            df: DataFrame with 'close' column and datetime index
        
        Returns:
            DataFrame with 'divergence_type' and 'divergence_confidence' columns
        """
        # Calculate RSI
        if 'rsi' not in df.columns:
            df['rsi'] = self.calculate_rsi(df['close'], self.rsi_period)
        
        # Initialize labels
        df['divergence_type'] = DivergenceType.NONE.value
        df['divergence_confidence'] = 0.0
        df['divergence_strength'] = 0.0
        
        # Detect divergences at each point
        for i in range(self.max_swing_bars * 2, len(df)):
            signal = self.detect_divergence(df, i)
            
            if signal:
                df.loc[df.index[i], 'divergence_type'] = signal.type.value
                df.loc[df.index[i], 'divergence_confidence'] = signal.confidence
                df.loc[df.index[i], 'divergence_strength'] = signal.strength
        
        return df
