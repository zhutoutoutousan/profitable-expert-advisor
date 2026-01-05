"""
Test script to verify MT5 connection and setup

Run this script first to ensure everything is configured correctly.
"""

import MetaTrader5 as mt5
from datetime import datetime, timedelta


def test_mt5_connection():
    """Test MT5 connection and basic functionality"""
    print("Testing MetaTrader5 Connection...")
    print("="*60)
    
    # Initialize MT5
    if not mt5.initialize():
        print(f"ERROR: MT5 initialization failed")
        print(f"Error code: {mt5.last_error()}")
        print("\nTroubleshooting:")
        print("1. Make sure MetaTrader5 is installed")
        print("2. Make sure MT5 is running")
        print("3. Try logging into MT5 manually first")
        return False
    
    print("✓ MT5 initialized successfully")
    
    # Get account info
    account_info = mt5.account_info()
    if account_info is None:
        print("WARNING: Could not get account info")
    else:
        print(f"✓ Account: {account_info.login}")
        print(f"  Server: {account_info.server}")
        print(f"  Balance: ${account_info.balance:.2f}")
    
    # Test symbol access
    test_symbols = ['XAUUSD', 'EURUSD', 'BTCUSD']
    print("\nTesting symbol access...")
    
    for symbol in test_symbols:
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            print(f"✗ {symbol}: Not available")
        else:
            print(f"✓ {symbol}: Available")
            print(f"  Bid: {symbol_info.bid:.5f}, Ask: {symbol_info.ask:.5f}")
            print(f"  Spread: {symbol_info.spread} points")
    
    # Test historical data
    print("\nTesting historical data retrieval...")
    symbol = 'XAUUSD'
    timeframe = mt5.TIMEFRAME_H1
    end_date = datetime.now()
    start_date = end_date - timedelta(days=7)
    
    rates = mt5.copy_rates_range(symbol, timeframe, start_date, end_date)
    if rates is None or len(rates) == 0:
        print(f"✗ Could not retrieve historical data for {symbol}")
        print("  Make sure you have historical data in MT5")
    else:
        print(f"✓ Retrieved {len(rates)} bars for {symbol}")
        print(f"  Date range: {datetime.fromtimestamp(rates[0]['time'])} to {datetime.fromtimestamp(rates[-1]['time'])}")
    
    # Test indicator creation
    print("\nTesting indicator creation...")
    rsi_handle = mt5.iRSI(symbol, timeframe, 14, mt5.PRICE_CLOSE)
    if rsi_handle == mt5.INVALID_HANDLE:
        print("✗ Failed to create RSI indicator")
    else:
        print("✓ RSI indicator created successfully")
        # Get RSI values
        rsi_values = mt5.copy_buffer(rsi_handle, 0, 0, 10)
        if rsi_values is not None:
            print(f"  Latest RSI values: {rsi_values[-3:]}")
        mt5.indicator_release(rsi_handle)
    
    ema_handle = mt5.iMA(symbol, timeframe, 50, 0, mt5.MODE_EMA, mt5.PRICE_CLOSE)
    if ema_handle == mt5.INVALID_HANDLE:
        print("✗ Failed to create EMA indicator")
    else:
        print("✓ EMA indicator created successfully")
        mt5.indicator_release(ema_handle)
    
    # Cleanup
    mt5.shutdown()
    
    print("\n" + "="*60)
    print("Setup test completed!")
    print("="*60)
    
    return True


if __name__ == '__main__':
    success = test_mt5_connection()
    if not success:
        exit(1)
