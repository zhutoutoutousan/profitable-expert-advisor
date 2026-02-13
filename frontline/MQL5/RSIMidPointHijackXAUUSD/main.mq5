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
#include "../_united/MagicNumberHelpers.mqh"

// Input Parameters
input group "General Settings"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;  // Trading Timeframe
input double InpLotSize = 0.02;               // Lot Size
input int    InpMagicNumberRSIFollow = 1001; // Magic Number RSI Follow
input int    InpMagicNumberRSIReverse = 1002;// Magic Number RSI Reverse
input int    InpMagicNumberEMACross = 1003;  // Magic Number EMA Cross

input group "Strategy Switches"
input bool   InpEnableRSIFollow = true;      // Enable RSI Follow Strategy
input bool   InpEnableRSIReverse = true;     // Enable RSI Reverse Strategy
input bool   InpEnableEMACross = true;       // Enable EMA Cross Strategy
input bool   InpEnableStrategyLock = false;   // Enable Strategy Lock
input double InpLockProfitThreshold = 0.0;   // Lock Profit Threshold (pips)
input bool   InpCloseOppositeTrades = false;  // Close Opposite Trades When Profiting

input group "RSI Follow Strategy"
input int    InpRSIPeriod = 32;              // RSI Period
input int    InpRSIOverbought = 78;          // RSI Overbought Level
input int    InpRSIOversold = 46;            // RSI Oversold Level
input int    InpRSIExitLevel = 44;           // RSI Exit Level
input int    InpRSIFollowStartHour = 23;      // RSI Follow Start Hour (0-23)
input int    InpRSIFollowEndHour = 8;       // RSI Follow End Hour (0-23)
input bool   InpRSIFollowCloseOutsideHours = false; // Close trades outside trading hours

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
input int    InpEMAPeriod = 120;              // EMA Period
input int    InpEMACrossStartHour = 8;       // EMA Cross Start Hour (0-23)
input int    InpEMACrossEndHour = 14;        // EMA Cross End Hour (0-23)
input bool   InpEMACrossCloseOutsideHours = true; // Close trades outside trading hours
input bool   InpUseEMADistanceEntry = true; // Use EMA Distance Entry
input double InpEMADistancePips = 160.0;      // EMA Distance Threshold (pips)
input int    InpEMADistancePeriod = 26;       // EMA Distance Period (bars)

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
double lastBarRSI = 0;  // Store last bar's RSI value
double lastBarRSIReverse = 0;  // Store last bar's RSI Reverse value
double lastBarEMA = 0;  // Store last bar's EMA value
double lastBarClose = 0;  // Store last bar's close value
double lastBarEMAPrev = 0;  // Store previous bar's EMA value
double lastBarClosePrev = 0;  // Store previous bar's close value

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
//| Check if position exists for given magic number AND symbol       |
//+------------------------------------------------------------------+
bool HasPosition(int magic)
{
    // Use helper function that verifies BOTH symbol AND magic number for THIS EA
    return PositionExistsByMagic(_Symbol, magic);
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
    
    // Use lastBarRSI instead of copying buffer
    if(lastBarRSI > InpRSIOverbought)
        rsiOverbought = true;
    else if(lastBarRSI < InpRSIOversold)
        rsiOversold = true;
    
    // Check for entry signals
    if(rsiOverbought && lastBarRSI < InpRSIExitLevel)
    {
        // Sell signal
        if(!HasPosition(InpMagicNumberRSIFollow))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIFollow);
            trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "RSI Follow");
        }
        rsiOverbought = false;
    }
    else if(rsiOversold && lastBarRSI > InpRSIExitLevel)
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
    
    // Use lastBarRSIReverse instead of copying buffer
    if(lastBarRSIReverse > InpRSIReverseOverbought)
        rsiReverseOverbought = true;
    else if(lastBarRSIReverse < InpRSIReverseOversold)
        rsiReverseOversold = true;
    
    // Check for entry signals
    if(rsiReverseOverbought && lastBarRSIReverse < InpRSIReverseCrossLevel)
    {
        // Sell signal
        if(!HasPosition(InpMagicNumberRSIReverse))
        {
            trade.SetExpertMagicNumber(InpMagicNumberRSIReverse);
            trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "RSI Reverse");
        }
        rsiReverseOverbought = false;
    }
    else if(rsiReverseOversold && lastBarRSIReverse > InpRSIReverseCrossLevel)
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
    
    // Check for cross signals using stored values
    if(lastBarEMAPrev < lastBarClosePrev && lastBarEMA > lastBarClose)
    {
        // Buy cross signal
        emaCrossBuySignal = true;
        emaCrossSellSignal = false;
        emaCrossSignalBar = 0;
    }
    else if(lastBarEMAPrev > lastBarClosePrev && lastBarEMA < lastBarClose)
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
            double emaHistory[], closeHistory[];
            ArraySetAsSeries(emaHistory, true);
            ArraySetAsSeries(closeHistory, true);
            
            if(CopyBuffer(emaHandle, 0, 0, InpEMADistancePeriod, emaHistory) > 0 &&
               CopyClose(_Symbol, InpTimeframe, 0, InpEMADistancePeriod, closeHistory) > 0)
            {
                for(int i = 0; i < InpEMADistancePeriod; i++)
                {
                    double distance = (closeHistory[i] - emaHistory[i]) / _Point;
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
        }
        else if(emaCrossSellSignal)
        {
            // Check if price has moved below EMA by the required distance for the required period
            bool distanceConditionMet = true;
            double emaHistory[], closeHistory[];
            ArraySetAsSeries(emaHistory, true);
            ArraySetAsSeries(closeHistory, true);
            
            if(CopyBuffer(emaHandle, 0, 0, InpEMADistancePeriod, emaHistory) > 0 &&
               CopyClose(_Symbol, InpTimeframe, 0, InpEMADistancePeriod, closeHistory) > 0)
            {
                for(int i = 0; i < InpEMADistancePeriod; i++)
                {
                    double distance = (emaHistory[i] - closeHistory[i]) / _Point;
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
    }
    else
    {
        // Original cross entry logic using stored values
        if(lastBarEMAPrev < lastBarClosePrev && lastBarEMA > lastBarClose)
        {
            // Buy signal
            if(!HasPosition(InpMagicNumberEMACross))
            {
                trade.SetExpertMagicNumber(InpMagicNumberEMACross);
                trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "EMA Cross");
            }
        }
        else if(lastBarEMAPrev > lastBarClosePrev && lastBarEMA < lastBarClose)
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
        
    // Get indicator values for the new bar
    double rsi[], rsiReverse[], ema[], close[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(rsiReverse, true);
    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(close, true);
    
    // Store previous values
    lastBarEMAPrev = lastBarEMA;
    lastBarClosePrev = lastBarClose;
    
    // Get new values
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) > 0)
        lastBarRSI = rsi[0];
        
    if(CopyBuffer(rsiReverseHandle, 0, 0, 1, rsiReverse) > 0)
        lastBarRSIReverse = rsiReverse[0];
        
    if(CopyBuffer(emaHandle, 0, 0, 1, ema) > 0)
        lastBarEMA = ema[0];
        
    if(CopyClose(_Symbol, InpTimeframe, 0, 1, close) > 0)
        lastBarClose = close[0];
        
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
    if(InpEnableRSIFollow)
    {
        // Check RSI Follow exit conditions
        if(HasPosition(InpMagicNumberRSIFollow))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && lastBarRSI < InpRSIExitLevel) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && lastBarRSI > InpRSIExitLevel))
            {
                ClosePosition(InpMagicNumberRSIFollow);
            }
        }
    }
    
    if(InpEnableRSIReverse)
    {
        // Check RSI Reverse exit conditions
        if(HasPosition(InpMagicNumberRSIReverse))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && lastBarRSIReverse < InpRSIReverseExitLevel) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && lastBarRSIReverse > InpRSIReverseExitLevel))
            {
                ClosePosition(InpMagicNumberRSIReverse);
            }
        }
    }
    
    if(InpEnableEMACross)
    {
        // Check EMA Cross exit conditions using stored values
        if(HasPosition(InpMagicNumberEMACross))
        {
            if((positionInfo.PositionType() == POSITION_TYPE_BUY && lastBarEMA > lastBarClose) ||
               (positionInfo.PositionType() == POSITION_TYPE_SELL && lastBarEMA < lastBarClose))
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
    // Close position using helper that verifies symbol AND magic number for THIS EA
    // First check if position exists for this EA on this symbol
    if(!PositionExistsByMagic(_Symbol, magic))
    {
        return; // No position for this EA on this symbol
    }
    
    // Get the position ticket for this EA on this symbol
    ulong ticket = GetPositionTicketByMagic(_Symbol, magic);
    if(ticket == 0)
    {
        return; // No valid ticket found
    }
    
    // Check if this is RSI Reverse position and update cooldown
    if(magic == InpMagicNumberRSIReverse)
    {
        if(PositionSelectByTicketSymbolAndMagic(ticket, _Symbol, magic))
        {
            datetime time[];
            if(CopyTime(_Symbol, InpTimeframe, 0, 1, time) > 0)
            {
                rsiReverseLastCloseTime = time[0];
                // Only enter cooldown if it's a loss or if cooldown on loss is disabled
                double profit = PositionGetDouble(POSITION_PROFIT);
                if(!InpRSIReverseCooldownOnLoss || profit < 0)
                {
                    rsiReverseInCooldown = true;
                }
            }
        }
    }
    
    // Close the position using helper function
    ClosePositionByMagic(trade, _Symbol, magic);
}
