# Table of Contents

- [Table of Contents](#table-of-contents)
- [Profitable Expert Advisors (EAs)](#profitable-expert-advisors-eas)
  - [Available EAs](#available-eas)
    - [1. RSI Reversal Asian AUD/USD](#1-rsi-reversal-asian-audusd)
    - [2. RSI MidPoint Hijack XAU/USD](#2-rsi-midpoint-hijack-xauusd)
    - [3. RSI Reversal Asian EUR/USD](#3-rsi-reversal-asian-eurusd)
    - [4. RSI CrossOver Reversal XAU/USD](#4-rsi-crossover-reversal-xauusd)
  - [Strategy Rationale](#strategy-rationale)
    - [RSI Reversal Strategy](#rsi-reversal-strategy)
    - [RSI MidPoint Hijack Strategy](#rsi-midpoint-hijack-strategy)
  - [Profitability Factors](#profitability-factors)
  - [Usage](#usage)
  - [Disclaimer](#disclaimer)


# Profitable Expert Advisors (EAs)

This repository contains a collection of profitable Expert Advisors (EAs) designed for MetaTrader 5. Each EA implements different trading strategies optimized for specific currency pairs and market conditions.

## Available EAs

### 1. RSI Reversal Asian AUD/USD
- **Strategy**: RSI-based reversal trading during Asian session
- **Key Features**:
  - Uses RSI (Relative Strength Index) for entry and exit signals
  - Specifically optimized for AUD/USD pair during Asian session (00:00-08:00 UTC)
  - Implements strict risk management with configurable stop loss and take profit
  - Includes spread monitoring to avoid trading during high spread conditions
  - Features a visual panel showing real-time trading metrics

**Core Parameters:**
```mql5
// RSI Settings
RSIPeriod = 28;          // RSI period
OverboughtLevel = 64;    // Overbought level
OversoldLevel = 13;      // Oversold level

// Risk Management
TakeProfitPips = 175;    // Take profit in pips
StopLossPips = 5;        // Stop loss in pips
MaxLotSize = 0.1;        // Maximum lot size
MaxSpread = 1000;        // Maximum allowed spread in pips
MaxDuration = 140;       // Maximum trade duration in hours
```

**Test Balance Results:**
<div align="center">
  <img src="RSIReversalAsianAUDUSD/test-balance.jpg" alt="RSI Reversal Asian AUD/USD Test Balance" width="600"/>
</div>

### 2. RSI MidPoint Hijack XAU/USD
- **Strategy**: Multi-strategy approach combining RSI and EMA crossovers
- **Key Features**:
  - Implements three distinct strategies:
    1. RSI Follow Strategy
    2. RSI Reverse Strategy
    3. EMA Cross Strategy
  - Optimized for Gold (XAU/USD) trading
  - Includes strategy locking mechanism to protect profits
  - Features cooldown periods after losses
  - Time-based trading windows for each strategy

**Core Parameters:**
```mql5
// RSI Follow Strategy
InpRSIPeriod = 87;              // RSI Period
InpRSIOverbought = 72;          // RSI Overbought Level
InpRSIOversold = 50;            // RSI Oversold Level

// RSI Reverse Strategy
InpRSIReversePeriod = 59;       // RSI Period
InpRSIReverseOverbought = 51;   // RSI Overbought Level
InpRSIReverseOversold = 49;     // RSI Oversold Level

// Strategy Management
InpEnableStrategyLock = false;   // Enable Strategy Lock
InpLockProfitThreshold = 0.0;   // Lock Profit Threshold (pips)
```

**Test Balance Results:**
<div align="center">
  <img src="RSIMidPointHijackXAUUSD/test-balance.jpg" alt="RSI MidPoint Hijack XAU/USD Test Balance" width="600"/>
</div>

### 3. RSI Reversal Asian EUR/USD
- **Strategy**: Similar to AUD/USD version but optimized for EUR/USD
- **Key Features**:
  - RSI-based reversal strategy during Asian session
  - Customized parameters for EUR/USD pair
  - Risk management features
  - Session-based trading

**Core Parameters:**
```mql5
// RSI Settings
RSIPeriod = 14;          // RSI period
OverboughtLevel = 78;    // Overbought level
OversoldLevel = 20;      // Oversold level

// Risk Management
TakeProfitPips = 635;    // Take profit in pips
StopLossPips = 290;      // Stop loss in pips
MaxLotSize = 0.1;        // Maximum lot size
MaxDuration = 22;        // Maximum trade duration in hours
RSIExitLevel = 57;       // RSI level to exit
```

**Test Balance Results:**
<div align="center">
  <img src="RSIReversalAsianEURUSD/test-balance.jpg" alt="RSI Reversal Asian EUR/USD Test Balance" width="600"/>
</div>

### 4. RSI CrossOver Reversal XAU/USD
- **Strategy**: RSI crossover strategy for Gold trading
- **Key Features**:
  - Uses RSI crossovers for entry and exit signals
  - Optimized for Gold market conditions
  - Includes multiple timeframe analysis
  - Risk management features

**Core Parameters:**
```mql5
// RSI Settings
rsiPeriod = 19;           // RSI period
overboughtLevel = 93;     // Overbought level
oversoldLevel = 22;       // Oversold level

// EMA Settings
emaPeriod = 140;          // EMA period
emaSlopeThreshold = 105;  // EMA slope threshold
emaDistanceThreshold = 165; // EMA distance threshold

// Risk Management
TrailingStop = 295;       // Trailing stop in pips
```

**Test Balance Results:**
<div align="center">
  <img src="RSICrossOverReversalXAUUSD/test-balance.jpg" alt="RSI CrossOver Reversal XAU/USD Test Balance" width="600"/>
</div>

## Strategy Rationale

### RSI Reversal Strategy
The RSI Reversal strategy is based on the principle that markets tend to revert to their mean after reaching extreme conditions. The strategy:
- Enters trades when RSI reaches overbought/oversold levels
- Uses Asian session timing to capitalize on specific market conditions
- Implements strict risk management to protect capital
- Takes advantage of mean reversion tendencies in currency pairs

### RSI MidPoint Hijack Strategy
This advanced strategy combines multiple approaches:
- RSI Follow: Capitalizes on strong trends
- RSI Reverse: Takes advantage of market reversals
- EMA Cross: Provides additional confirmation signals
- Strategy locking: Protects profits during favorable conditions
- Cooldown periods: Prevents over-trading after losses

## Profitability Factors

These EAs are designed to be profitable in the long run due to:

1. **Risk Management**
   - Strict stop loss implementation
   - Take profit targets
   - Spread monitoring
   - Position sizing control

2. **Market Timing**
   - Session-based trading
   - Time-specific entry and exit rules
   - Avoidance of high volatility periods

3. **Strategy Diversification**
   - Multiple entry and exit conditions
   - Different timeframes
   - Various technical indicators

4. **Adaptive Features**
   - Strategy locking during profitable periods
   - Cooldown periods after losses
   - Spread-based trade filtering

## Usage

Each EA comes with configurable parameters that can be adjusted based on:
- Market conditions
- Risk tolerance
- Trading style
- Account size

Please refer to the individual EA files for specific parameter descriptions and recommended settings.

## Disclaimer

Trading involves substantial risk of loss. These EAs are provided for educational purposes only. Always test thoroughly on a demo account before using with real money. Past performance does not guarantee future results.
