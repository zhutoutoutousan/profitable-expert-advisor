"""
Data Collection Script for BTCUSD RSI Divergence Training
Fetches BTCUSD data from MetaTrader 5 and labels it with RSI divergence signals.
"""

import argparse
import os
import sys
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
import MetaTrader5 as mt5
from rsi_divergence_detector import RSIDivergenceDetector, DivergenceType
import pickle
from tqdm import tqdm


def fetch_mt5_data(symbol: str, timeframe: int, start_date: datetime, end_date: datetime) -> pd.DataFrame:
    """
    Fetch historical data from MetaTrader 5.
    
    Args:
        symbol: Trading symbol (e.g., 'BTCUSD')
        timeframe: MT5 timeframe constant
        start_date: Start date for data
        end_date: End date for data
    
    Returns:
        DataFrame with OHLCV data
    """
    print(f"Fetching {symbol} data from {start_date} to {end_date}...")
    
    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialization failed: {mt5.last_error()}")
    
    try:
        rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)
        
        if rates is None or len(rates) == 0:
            raise ValueError(f"No data available for {symbol} in the specified date range")
        
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)
        
        # Rename columns to lowercase
        df.columns = [col.lower() for col in df.columns]
        
        print(f"Fetched {len(df)} bars")
        return df
    
    finally:
        mt5.shutdown()


def prepare_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Prepare additional features for training.
    
    Args:
        df: DataFrame with OHLCV data
    
    Returns:
        DataFrame with additional features
    """
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
    
    return feature_df


def create_sequences(df: pd.DataFrame, lookback: int = 60, prediction_horizon: int = 5) -> tuple:
    """
    Create sequences for training.
    
    Args:
        df: Labeled DataFrame
        lookback: Number of bars to look back
        prediction_horizon: Number of bars ahead to predict
    
    Returns:
        Tuple of (X, y) where X is features and y is labels
    """
    # Feature columns (exclude labels and time-based columns)
    exclude_cols = ['divergence_type', 'divergence_confidence', 'divergence_strength', 'time']
    feature_cols = [col for col in df.columns if col not in exclude_cols]
    
    X, y = [], []
    
    for i in range(lookback, len(df) - prediction_horizon):
        # Get feature sequence
        X.append(df[feature_cols].iloc[i - lookback:i].values)
        
        # Get label (divergence type at current bar)
        y.append(df['divergence_type'].iloc[i])
    
    return np.array(X), np.array(y)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Collect and label BTCUSD data for RSI divergence training')
    parser.add_argument('--symbol', type=str, default='BTCUSD', help='Trading symbol')
    parser.add_argument('--timeframe', type=str, default='H1', 
                       choices=['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'],
                       help='Timeframe')
    parser.add_argument('--days', type=int, default=365, help='Number of days of historical data')
    parser.add_argument('--rsi-period', type=int, default=14, help='RSI period')
    parser.add_argument('--output', type=str, default='data', help='Output directory')
    parser.add_argument('--min-strength', type=float, default=0.15, 
                       help='Minimum divergence strength (0-1)')
    
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
    
    # Fetch data
    end_date = datetime.now()
    start_date = end_date - timedelta(days=args.days)
    
    print(f"\n{'='*60}")
    print("BTCUSD RSI Divergence Data Collection")
    print(f"{'='*60}\n")
    
    df = fetch_mt5_data(args.symbol, timeframe, start_date, end_date)
    
    # Prepare features
    print("\nPreparing features...")
    df = prepare_features(df)
    
    # Detect and label divergences
    print("\nDetecting RSI divergences...")
    detector = RSIDivergenceDetector(
        rsi_period=args.rsi_period,
        min_divergence_strength=args.min_strength
    )
    
    df = detector.label_data(df)
    
    # Statistics
    total_bars = len(df)
    labeled_bars = len(df[df['divergence_type'] != DivergenceType.NONE.value])
    
    print(f"\n{'='*60}")
    print("Labeling Statistics:")
    print(f"{'='*60}")
    print(f"Total bars: {total_bars}")
    print(f"Bars with divergence: {labeled_bars} ({labeled_bars/total_bars*100:.2f}%)")
    
    for div_type in DivergenceType:
        if div_type == DivergenceType.NONE:
            continue
        count = len(df[df['divergence_type'] == div_type.value])
        print(f"  {div_type.name}: {count} ({count/total_bars*100:.2f}%)")
    
    # Save labeled data
    output_file = os.path.join(args.output, f"{args.symbol}_{args.timeframe}_labeled.csv")
    df.to_csv(output_file)
    print(f"\nLabeled data saved to: {output_file}")
    
    # Save detector parameters
    detector_params = {
        'rsi_period': args.rsi_period,
        'min_swing_bars': detector.min_swing_bars,
        'max_swing_bars': detector.max_swing_bars,
        'min_divergence_strength': args.min_strength
    }
    
    params_file = os.path.join(args.output, f"{args.symbol}_{args.timeframe}_detector_params.pkl")
    with open(params_file, 'wb') as f:
        pickle.dump(detector_params, f)
    print(f"Detector parameters saved to: {params_file}")
    
    print(f"\n{'='*60}")
    print("Data collection completed!")
    print(f"{'='*60}\n")


if __name__ == '__main__':
    main()
