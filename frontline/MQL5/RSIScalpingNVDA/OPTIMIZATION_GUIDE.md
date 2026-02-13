# Genetic Algorithm Optimization Guide for RSIScalpingNVDA

## Recommended Optimization Strategy

### Phase 1: Core RSI Parameters (Primary Focus)
These parameters directly control entry/exit signals and should be optimized first.

#### **RSI_Period** (Y - Optimize)
- **Current**: 14
- **Recommended Range**: 7-21
- **Step**: 1
- **Rationale**: Standard RSI periods. Shorter = more sensitive, longer = smoother signals

#### **RSI_Overbought** (Y - Optimize)
- **Current**: 19.0 (unusually low - verify if this is correct)
- **Standard Range**: 60.0-85.0
- **Step**: 2.0
- **Alternative Range** (if current is intentional): 15.0-30.0
- **Rationale**: Level where RSI indicates overbought condition for sell entries

#### **RSI_Oversold** (Y - Optimize)
- **Current**: 50.0 (unusually high - verify if this is correct)
- **Standard Range**: 15.0-40.0
- **Step**: 2.0
- **Alternative Range** (if current is intentional): 40.0-60.0
- **Rationale**: Level where RSI indicates oversold condition for buy entries

#### **RSI_Target_Buy** (Y - Optimize)
- **Current**: 71.0
- **Recommended Range**: 65.0-90.0
- **Step**: 2.0
- **Rationale**: Exit target for long positions. Must be > RSI_Oversold

#### **RSI_Target_Sell** (Y - Optimize)
- **Current**: 70.0
- **Recommended Range**: 10.0-35.0
- **Step**: 2.0
- **Rationale**: Exit target for short positions. Must be < RSI_Overbought

### Phase 2: Risk Management Parameters

#### **BarsToWait** (Y - Optimize)
- **Current**: 1
- **Recommended Range**: 1-8
- **Step**: 1
- **Rationale**: Bars to wait before closing when RSI goes against position. Higher = more patience

#### **TimeFrame** (Y - Optimize)
- **Current**: 16387 (M5)
- **Recommended**: Test M1, M5, M15, H1
- **Values**: 
  - M1 = 16385
  - M5 = 16387
  - M15 = 16388
  - H1 = 16390
- **Rationale**: Different timeframes can significantly affect scalping performance

### Phase 3: Position Sizing (Optimize with Caution)

#### **LotSize** (Y - Optimize with Fixed Risk)
- **Current**: 50.0
- **Recommended Range**: 10.0-100.0
- **Step**: 5.0
- **Note**: Consider using fixed risk % instead of fixed lot size
- **Rationale**: Position sizing affects profitability but also risk

### Fixed Parameters (Do NOT Optimize)

#### **RSI_Applied_Price** (N)
- **Value**: 1 (PRICE_CLOSE)
- **Rationale**: Standard choice, changing may not improve results significantly

#### **MagicNumber** (N)
- **Value**: 12345
- **Rationale**: Identifier only, no impact on performance

#### **Slippage** (N)
- **Value**: 3
- **Rationale**: Broker-specific, should match your actual slippage

## Genetic Algorithm Settings

### Recommended GA Settings:
- **Optimization Criterion**: Balance (or Custom: Profit Factor * Total Net Profit)
- **Population Size**: 50-100
- **Mutation Probability**: 0.1-0.2
- **Crossover Probability**: 0.7-0.9
- **Optimization Passes**: 3-5
- **Forward Testing**: Always use out-of-sample data

### Optimization Phases:

1. **Broad Search** (First Pass):
   - Optimize: RSI_Period, RSI_Overbought, RSI_Oversold, RSI_Target_Buy, RSI_Target_Sell
   - Fix: BarsToWait=1, TimeFrame=M5, LotSize=50

2. **Refinement** (Second Pass):
   - Use best results from Phase 1
   - Optimize: BarsToWait, TimeFrame
   - Narrow ranges around Phase 1 winners

3. **Fine-Tuning** (Third Pass):
   - Optimize: LotSize (if needed)
   - Very narrow ranges around Phase 2 winners

## Important Notes

⚠️ **Current Parameter Anomaly**: 
- RSI_Overbought=19 and RSI_Oversold=50 are unusual
- Standard RSI ranges: Overbought 70-80, Oversold 20-30
- **Verify** if these are intentional or if there's a scaling issue

✅ **Validation Checklist**:
- Ensure RSI_Target_Buy > RSI_Oversold
- Ensure RSI_Target_Sell < RSI_Overbought
- Test on sufficient historical data (at least 6-12 months)
- Use forward testing on unseen data
- Check for overfitting (too many parameters optimized)

## Example .set File Structure

```
RSI_Period=14||1||7||21||Y
RSI_Overbought=70.0||2.0||60.0||85.0||Y
RSI_Oversold=30.0||2.0||15.0||40.0||Y
RSI_Target_Buy=75.0||2.0||65.0||90.0||Y
RSI_Target_Sell=25.0||2.0||10.0||35.0||Y
BarsToWait=2||1||1||8||Y
TimeFrame=16387||0||16385||16390||Y
LotSize=50.0||5.0||10.0||100.0||Y
RSI_Applied_Price=1||0||1||1||N
MagicNumber=12345||0||12345||12345||N
Slippage=3||0||3||3||N
```
