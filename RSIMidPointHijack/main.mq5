//+------------------------------------------------------------------+
//|                                 RSIFollowReverseEMACrossOver.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Input Parameters
input group "General Settings"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT;  // Trading Timeframe
input double InpLotSize = 0.01;               // Lot Size
input int    InpMagicNumberRSIFollow = 1001; // Magic Number RSI Follow
input int    InpMagicNumberRSIReverse = 1002;// Magic Number RSI Reverse
input int    InpMagicNumberEMACross = 1003;  // Magic Number EMA Cross

input group "Strategy Switches"
input bool   InpEnableRSIFollow = false;      // Enable RSI Follow Strategy
input bool   InpEnableRSIReverse = true;     // Enable RSI Reverse Strategy
input bool   InpEnableEMACross = false;       // Enable EMA Cross Strategy
input bool   InpEnableStrategyLock = false;   // Enable Strategy Lock
input double InpLockProfitThreshold = 0.0;   // Lock Profit Threshold (pips)
input bool   InpCloseOppositeTrades = false;  // Close Opposite Trades When Profiting

input group "RSI Follow Strategy"
input int    InpRSIPeriod = 14;              // RSI Period
input int    InpRSIOverbought = 70;          // RSI Overbought Level
input int    InpRSIOversold = 30;            // RSI Oversold Level
input int    InpRSIExitLevel = 50;           // RSI Exit Level
input int    InpRSIFollowStartHour = 0;      // RSI Follow Start Hour (0-23)
input int    InpRSIFollowEndHour = 23;       // RSI Follow End Hour (0-23)
input bool   InpRSIFollowCloseOutsideHours = true; // Close trades outside trading hours

input group "RSI Reverse Strategy"
input int    InpRSIReversePeriod = 59;       // RSI Period
input int    InpRSIReverseOverbought = 51;   // RSI Overbought Level
input int    InpRSIReverseOversold = 49;     // RSI Oversold Level
input int    InpRSIReverseCrossLevel = 53;   // RSI Cross Level
input int    InpRSIReverseExitLevel = 48;    // RSI Exit Level
input int    InpRSIReverseStartHour = 7;     // RSI Reverse Start Hour (0-23)
input int    InpRSIReverseEndHour = 13;      // RSI Reverse End Hour (0-23)
input bool   InpRSIReverseCloseOutsideHours = false; // Close trades outside trading hours
input int    InpRSIReverseCooldownBars = 15;  // RSI Reverse Cooldown (bars)
input bool   InpRSIReverseCooldownOnLoss = true; // Apply cooldown only on loss

input group "EMA Cross Strategy"
input int    InpEMAPeriod = 20;              // EMA Period
input int    InpEMACrossStartHour = 0;       // EMA Cross Start Hour (0-23)
input int    InpEMACrossEndHour = 23;        // EMA Cross End Hour (0-23)
input bool   InpEMACrossCloseOutsideHours = true; // Close trades outside trading hours
input bool   InpUseEMADistanceEntry = false; // Use EMA Distance Entry
input double InpEMADistancePips = 10.0;      // EMA Distance Threshold (pips)
input int    InpEMADistancePeriod = 3;       // EMA Distance Period (bars)

// Global Variables
int rsiHandle;
int rsiReverseHandle;
int emaHandle;
bool rsiOverbought = false;
bool rsiOversold = false;
bool rsiReverseOverbought = false;
bool rsiReverseOversold = false;
CTrade trade;
CPositionInfo positionInfo;
bool emaCrossBuySignal = false;
bool emaCrossSellSignal = false;
int emaCrossSignalBar = 0;
datetime lastBarTime = 0;
datetime rsiReverseLastCloseTime = 0;
bool rsiReverseInCooldown = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    rsiHandle = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
    rsiReverseHandle = iRSI(_Symbol, InpTimeframe, InpRSIReversePeriod, PRICE_CLOSE);
    emaHandle = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    
    if(rsiHandle == INVALID_HANDLE || rsiReverseHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Initialize trade settings
    trade.SetExpertMagicNumber(InpMagicNumberRSIFollow);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(10);
    
    // Initialize last bar time
    datetime time[];
    if(CopyTime(_Symbol, InpTimeframe, 0, 1, time) > 0)
    {
        lastBarTime = time[0];
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime time[];
    if(CopyTime(_Symbol, InpTimeframe, 0, 1, time) > 0)
    {
        if(time[0] != lastBarTime)
        {
            lastBarTime = time[0];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(rsiHandle);
    IndicatorRelease(rsiReverseHandle);
    IndicatorRelease(emaHandle);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours(int startHour, int endHour)
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);
    
    if(startHour <= endHour)
    {
        return (currentTime.hour >= startHour && currentTime.hour < endHour);
    }
    else
    {
        return (currentTime.hour >= startHour || currentTime.hour < endHour);
    }
}

//+------------------------------------------------------------------+
//| Check if position exists for given magic number                   |
//+------------------------------------------------------------------+
bool HasPosition(int magic)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == magic)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if any strategy has profitable position                     |
//+------------------------------------------------------------------+
bool HasProfitablePosition(int excludeMagic)
{
    bool hasProfitable = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() != excludeMagic)
            {
                double profit = positionInfo.Profit();
                if(profit > InpLockProfitThreshold * _Point)
                {
                    hasProfitable = true;
                    // If enabled, close opposite trades
                    if(InpCloseOppositeTrades)
                    {
                        // Check if this is an opposite trade to the excluded magic number
                        if((excludeMagic == InpMagicNumberRSIFollow && positionInfo.Magic() == InpMagicNumberRSIReverse) ||
                           (excludeMagic == InpMagicNumberRSIReverse && positionInfo.Magic() == InpMagicNumberRSIFollow) ||
                           (excludeMagic == InpMagicNumberEMACross && (positionInfo.Magic() == InpMagicNumberRSIReverse || positionInfo.Magic() == InpMagicNumberRSIFollow)) ||
                           ((excludeMagic == InpMagicNumberRSIFollow || excludeMagic == InpMagicNumberRSIReverse) && positionInfo.Magic() == InpMagicNumberEMACross))
                        {
                            ClosePosition(positionInfo.Magic());
                        }
                    }
                }
            }
        }
    }
    return hasProfitable;
}

//+------------------------------------------------------------------+
//| Check for RSI Follow Strategy signals                            |
//+------------------------------------------------------------------+
void CheckRSIFollowStrategy()
{
    // Check if within trading hours
    if(!IsWithinTradingHours(InpRSIFollowStartHour, InpRSIFollowEndHour))
    {
        if(InpRSIFollowCloseOutsideHours)
        {
            if(HasPosition(InpMagicNumberRSIFollow))
            {
                ClosePosition(InpMagicNumberRSIFollow);
            }
        }
        return;
    }
    
    // Check strategy lock
    if(InpEnableStrategyLock && HasProfitablePosition(InpMagicNumberRSIFollow))
        return;
    
    double rsi[];
    ArraySetAsSeries(rsi, true);
    CopyBuffer(rsiHandle, 0, 0, 3, rsi);
    
    if(ArraySize(rsi) < 3) return;
    
    // Check for overbought condition
    if(rsi[1] > InpRSIOverbought)
        rsiOverbought = true;
    else if(rsi[1] < InpRSIOversold)
        rsiOversold = true;
    
    // Check for entry signals
    if(rsiOverbought && rsi[1] < rsi[0] && rsi[1] < InpRSIExitLevel)
    {
        // Sell signal
        if(!HasPosition(InpMagicNumberRSIFollow))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIFollow);
            trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "RSI Follow");
        }
        rsiOverbought = false;
    }
    else if(rsiOversold && rsi[1] > rsi[0] && rsi[1] > InpRSIExitLevel)
    {
        // Buy signal
        if(!HasPosition(InpMagicNumberRSIFollow))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIFollow);
            trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "RSI Follow");
        }
        rsiOversold = false;
    }
}

//+------------------------------------------------------------------+
//| Check if RSI Reverse is in cooldown                              |
//+------------------------------------------------------------------+
bool IsRSIReverseInCooldown()
{
    if(InpRSIReverseCooldownBars <= 0)
        return false;
        
    if(!rsiReverseInCooldown)
        return false;
        
    datetime time[];
    if(CopyTime(_Symbol, InpTimeframe, 0, 1, time) > 0)
    {
        datetime currentBarTime = time[0];
        datetime cooldownEndTime = rsiReverseLastCloseTime + InpRSIReverseCooldownBars * PeriodSeconds(InpTimeframe);
        
        if(currentBarTime >= cooldownEndTime)
        {
            rsiReverseInCooldown = false;
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for RSI Reverse Strategy signals                           |
//+------------------------------------------------------------------+
void CheckRSIReverseStrategy()
{
    // Check if within trading hours
    if(!IsWithinTradingHours(InpRSIReverseStartHour, InpRSIReverseEndHour))
    {
        if(InpRSIReverseCloseOutsideHours)
        {
            if(HasPosition(InpMagicNumberRSIReverse))
            {
                ClosePosition(InpMagicNumberRSIReverse);
            }
        }
        return;
    }
    
    // Check strategy lock
    if(InpEnableStrategyLock && HasProfitablePosition(InpMagicNumberRSIReverse))
        return;
        
    // Check cooldown
    if(IsRSIReverseInCooldown())
        return;
    
    double rsi[];
    ArraySetAsSeries(rsi, true);
    CopyBuffer(rsiReverseHandle, 0, 0, 3, rsi);
    
    if(ArraySize(rsi) < 3) return;
    
    // Check for overbought/oversold conditions
    if(rsi[1] > InpRSIReverseOverbought)
        rsiReverseOverbought = true;
    else if(rsi[1] < InpRSIReverseOversold)
        rsiReverseOversold = true;
    
    // Check for entry signals
    if(rsiReverseOverbought && rsi[1] < InpRSIReverseCrossLevel)
    {
        // Sell signal
        if(!HasPosition(InpMagicNumberRSIReverse))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIReverse);
            trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "RSI Reverse");
        }
        rsiReverseOverbought = false;
    }
    else if(rsiReverseOversold && rsi[1] > InpRSIReverseCrossLevel)
    {
        // Buy signal
        if(!HasPosition(InpMagicNumberRSIReverse))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIReverse);
            trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "RSI Reverse");
        }
        rsiReverseOversold = false;
    }
}

//+------------------------------------------------------------------+
//| Check for EMA Cross Strategy signals                             |
//+------------------------------------------------------------------+
void CheckEMACrossStrategy()
{
    // Check if within trading hours
    if(!IsWithinTradingHours(InpEMACrossStartHour, InpEMACrossEndHour))
    {
        if(InpEMACrossCloseOutsideHours)
        {
            if(HasPosition(InpMagicNumberEMACross))
            {
                ClosePosition(InpMagicNumberEMACross);
            }
        }
        return;
    }
    
    // Check strategy lock
    if(InpEnableStrategyLock && HasProfitablePosition(InpMagicNumberEMACross))
        return;
    
    double ema[], close[];
    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(close, true);
    
    CopyBuffer(emaHandle, 0, 0, InpEMADistancePeriod + 2, ema);
    CopyClose(_Symbol, InpTimeframe, 0, InpEMADistancePeriod + 2, close);
    
    if(ArraySize(ema) < InpEMADistancePeriod + 2 || ArraySize(close) < InpEMADistancePeriod + 2) return;
    
    // Check for cross signals
    if(ema[1] < close[1] && ema[0] > close[0])
    {
        // Buy cross signal
        emaCrossBuySignal = true;
        emaCrossSellSignal = false;
        emaCrossSignalBar = 0;
    }
    else if(ema[1] > close[1] && ema[0] < close[0])
    {
        // Sell cross signal
        emaCrossSellSignal = true;
        emaCrossBuySignal = false;
        emaCrossSignalBar = 0;
    }
    
    // Check for distance entry conditions
    if(InpUseEMADistanceEntry)
    {
        if(emaCrossBuySignal)
        {
            // Check if price has moved above EMA by the required distance for the required period
            bool distanceConditionMet = true;
            for(int i = 0; i < InpEMADistancePeriod; i++)
            {
                double distance = (close[i] - ema[i]) / _Point;
                if(distance < InpEMADistancePips)
                {
                    distanceConditionMet = false;
                    break;
                }
            }
            
            if(distanceConditionMet && !HasPosition(InpMagicNumberEMACross))
            {
                trade.SetExpertMagicNumber(InpMagicNumberEMACross);
                trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "EMA Cross Distance");
                emaCrossBuySignal = false;
            }
        }
        else if(emaCrossSellSignal)
        {
            // Check if price has moved below EMA by the required distance for the required period
            bool distanceConditionMet = true;
            for(int i = 0; i < InpEMADistancePeriod; i++)
            {
                double distance = (ema[i] - close[i]) / _Point;
                if(distance < InpEMADistancePips)
                {
                    distanceConditionMet = false;
                    break;
                }
            }
            
            if(distanceConditionMet && !HasPosition(InpMagicNumberEMACross))
            {
                trade.SetExpertMagicNumber(InpMagicNumberEMACross);
                trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "EMA Cross Distance");
                emaCrossSellSignal = false;
            }
        }
    }
    else
    {
        // Original cross entry logic
        if(ema[1] < close[1] && ema[0] > close[0])
        {
            // Buy signal
            if(!HasPosition(InpMagicNumberEMACross))
            {
                trade.SetExpertMagicNumber(InpMagicNumberEMACross);
                trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "EMA Cross");
            }
        }
        else if(ema[1] > close[1] && ema[0] < close[0])
        {
            // Sell signal
            if(!HasPosition(InpMagicNumberEMACross))
            {
                trade.SetExpertMagicNumber(InpMagicNumberEMACross);
                trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "EMA Cross");
            }
        }
    }
    
    // Increment signal bar counter
    if(emaCrossBuySignal || emaCrossSellSignal)
    {
        emaCrossSignalBar++;
        // Reset signals if they're too old (optional, can be removed if not needed)
        if(emaCrossSignalBar > InpEMADistancePeriod * 2)
        {
            emaCrossBuySignal = false;
            emaCrossSellSignal = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Only process on new bar
    if(!IsNewBar())
        return;
        
    // Check for new signals
    if(InpEnableRSIFollow)
        CheckRSIFollowStrategy();
    if(InpEnableRSIReverse)
        CheckRSIReverseStrategy();
    if(InpEnableEMACross)
        CheckEMACrossStrategy();
    
    // Check for exit conditions
    CheckExitConditions();
}

//+------------------------------------------------------------------+
//| Check exit conditions for all strategies                         |
//+------------------------------------------------------------------+
void CheckExitConditions()
{
    double rsi[], rsiReverse[], ema[], close[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(rsiReverse, true);
    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(close, true);
    
    if(InpEnableRSIFollow)
    {
        CopyBuffer(rsiHandle, 0, 0, 1, rsi);
        // Check RSI Follow exit conditions
        if(HasPosition(InpMagicNumberRSIFollow))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && rsi[0] < InpRSIExitLevel) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && rsi[0] > InpRSIExitLevel))
            {
                ClosePosition(InpMagicNumberRSIFollow);
            }
        }
    }
    
    if(InpEnableRSIReverse)
    {
        CopyBuffer(rsiReverseHandle, 0, 0, 1, rsiReverse);
        // Check RSI Reverse exit conditions
        if(HasPosition(InpMagicNumberRSIReverse))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && rsiReverse[0] < InpRSIReverseExitLevel) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && rsiReverse[0] > InpRSIReverseExitLevel))
            {
                ClosePosition(InpMagicNumberRSIReverse);
            }
        }
    }
    
    if(InpEnableEMACross)
    {
        CopyBuffer(emaHandle, 0, 0, 2, ema);
        CopyClose(_Symbol, InpTimeframe, 0, 2, close);
        // Check EMA Cross exit conditions
        if(HasPosition(InpMagicNumberEMACross))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && ema[0] > close[0]) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && ema[0] < close[0]))
            {
                ClosePosition(InpMagicNumberEMACross);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close position by magic number                                   |
//+------------------------------------------------------------------+
void ClosePosition(int magic)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == magic)
            {
                // Check if this is RSI Reverse position and update cooldown
                if(magic == InpMagicNumberRSIReverse)
                {
                    datetime time[];
                    if(CopyTime(_Symbol, InpTimeframe, 0, 1, time) > 0)
                    {
                        rsiReverseLastCloseTime = time[0];
                        // Only enter cooldown if it's a loss or if cooldown on loss is disabled
                        if(!InpRSIReverseCooldownOnLoss || positionInfo.Profit() < 0)
                        {
                            rsiReverseInCooldown = true;
                        }
                    }
                }
                
                trade.PositionClose(positionInfo.Ticket());
                break;
            }
        }
    }
}
