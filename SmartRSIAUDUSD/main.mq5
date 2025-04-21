//+------------------------------------------------------------------+
//|                                                     SmartRSI.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input parameters for RSI
input group "RSI Settings"
input int RSI_Period = 125;                // RSI Period
input ENUM_APPLIED_PRICE RSI_Price = PRICE_MEDIAN; // RSI Applied Price

// Strategy Selection
input group "Strategy Selection"
input bool UseTrendFollowing = false;      // Use Trend Following Strategy
input bool UseReversal = true;            // Use Reversal Strategy

// Time Frames
input group "Time Frames"
input ENUM_TIMEFRAMES Trend_TimeFrame = PERIOD_H12; // Trend Following Time Frame
input ENUM_TIMEFRAMES Rev_TimeFrame = PERIOD_M6;   // Reversal Time Frame

// Enum for RSI conditions
enum ENUM_RSI_CONDITION
{
    RSI_BELOW_OVERSOLD,      // RSI below oversold level
    RSI_ABOVE_OVERBOUGHT,    // RSI above overbought level
    RSI_BELOW_MIDPOINT,      // RSI below midpoint
    RSI_ABOVE_MIDPOINT,      // RSI above midpoint
    RSI_CROSS_OVERSOLD,      // RSI crosses below oversold
    RSI_CROSS_OVERBOUGHT     // RSI crosses above overbought
};

// Entry/Exit Conditions
input group "Entry/Exit Conditions"
input ENUM_RSI_CONDITION Trend_Entry_Condition = RSI_BELOW_OVERSOLD; // Trend Entry Condition
input ENUM_RSI_CONDITION Trend_Exit_Condition = RSI_BELOW_MIDPOINT;  // Trend Exit Condition
input ENUM_RSI_CONDITION Rev_Entry_Condition = RSI_CROSS_OVERSOLD;   // Reversal Entry Condition
input ENUM_RSI_CONDITION Rev_Exit_Condition = RSI_BELOW_MIDPOINT;    // Reversal Exit Condition

// Trend Following Strategy Parameters
input group "Trend Following Strategy"
input double Trend_Overbought = 11;       // Overbought level for trend following
input double Trend_Oversold = 26;         // Oversold level for trend following
input double Trend_Exit_Long = 50;        // Exit level for long positions
input double Trend_Exit_Short = 50;       // Exit level for short positions
input double Trend_LotSize = 0.09;         // Lot size for trend following
input int Trend_Magic = 12345;            // Magic number for trend following
input bool Trend_CloseOpposite = false;    // Close opposite trades on profit
input double Trend_ProfitToClose = 180;    // Profit in points to close opposite trades
input int Trend_TimeToClose = 1;          // Bars to wait before closing opposite trades

// Reversal Strategy Parameters
input group "Reversal Strategy"
input double Rev_Overbought = 60;         // Overbought level for reversal
input double Rev_Oversold = 226;           // Oversold level for reversal
input double Rev_Exit_Long = 50;          // Exit level for long positions
input double Rev_Exit_Short = 50;         // Exit level for short positions
input double Rev_LotSize = 0.06;           // Lot size for reversal
input int Rev_Magic = 54321;              // Magic number for reversal
input bool Rev_CloseOpposite = true;      // Close opposite trades on profit
input double Rev_ProfitToClose = 105;      // Profit in points to close opposite trades
input int Rev_TimeToClose = 5;            // Bars to wait before closing opposite trades

// Indicator buffers
double trend_rsi_buffer[];
double rev_rsi_buffer[];
int trend_rsi_handle;
int rev_rsi_handle;
CTrade trade;
datetime last_trend_bar_time;
datetime last_rev_bar_time;
datetime trend_long_entry_time = 0;
datetime trend_short_entry_time = 0;
datetime rev_long_entry_time = 0;
datetime rev_short_entry_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicators
    trend_rsi_handle = iRSI(_Symbol, Trend_TimeFrame, RSI_Period, RSI_Price);
    rev_rsi_handle = iRSI(_Symbol, Rev_TimeFrame, RSI_Period, RSI_Price);
    
    if(trend_rsi_handle == INVALID_HANDLE || rev_rsi_handle == INVALID_HANDLE)
    {
        Print("Failed to create RSI indicators");
        return INIT_FAILED;
    }
    
    // Set buffer size and series
    ArraySetAsSeries(trend_rsi_buffer, true);
    ArraySetAsSeries(rev_rsi_buffer, true);
    
    // Initialize trade object
    trade.SetExpertMagicNumber(Trend_Magic);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(10);
    
    // Initialize last bar times
    last_trend_bar_time = 0;
    last_rev_bar_time = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(trend_rsi_handle != INVALID_HANDLE)
        IndicatorRelease(trend_rsi_handle);
    if(rev_rsi_handle != INVALID_HANDLE)
        IndicatorRelease(rev_rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime current_trend_time = iTime(_Symbol, Trend_TimeFrame, 0);
    datetime current_rev_time = iTime(_Symbol, Rev_TimeFrame, 0);
    
    // Check if new bar has formed for trend following
    if(current_trend_time != last_trend_bar_time)
    {
        last_trend_bar_time = current_trend_time;
        
        // Update RSI values for trend following
        if(CopyBuffer(trend_rsi_handle, 0, 0, 2, trend_rsi_buffer) <= 0)
        {
            Print("Failed to copy trend RSI buffer");
            return;
        }
            
        // Run trend following strategy if enabled
        if(UseTrendFollowing)
            CheckTrendFollowing();
    }
    
    // Check if new bar has formed for reversal
    if(current_rev_time != last_rev_bar_time)
    {
        last_rev_bar_time = current_rev_time;
        
        // Update RSI values for reversal
        if(CopyBuffer(rev_rsi_handle, 0, 0, 2, rev_rsi_buffer) <= 0)
        {
            Print("Failed to copy reversal RSI buffer");
            return;
        }
            
        // Run reversal strategy if enabled
        if(UseReversal)
            CheckReversal();
    }
}

//+------------------------------------------------------------------+
//| Check RSI Condition                                              |
//+------------------------------------------------------------------+
bool CheckRSICondition(ENUM_RSI_CONDITION condition, double level, double &buffer[])
{
    switch(condition)
    {
        case RSI_BELOW_OVERSOLD:
            return buffer[0] < level;
        case RSI_ABOVE_OVERBOUGHT:
            return buffer[0] > level;
        case RSI_BELOW_MIDPOINT:
            return buffer[0] < 50;
        case RSI_ABOVE_MIDPOINT:
            return buffer[0] > 50;
        case RSI_CROSS_OVERSOLD:
            return buffer[0] < level && buffer[1] >= level;
        case RSI_CROSS_OVERBOUGHT:
            return buffer[0] > level && buffer[1] <= level;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check Trend Following Strategy                                   |
//+------------------------------------------------------------------+
void CheckTrendFollowing()
{
    // Check for existing positions
    bool hasLong = PositionSelectByMagic(Trend_Magic, POSITION_TYPE_BUY);
    bool hasShort = PositionSelectByMagic(Trend_Magic, POSITION_TYPE_SELL);
    
    // Entry logic
    if(!hasLong && !hasShort)
    {
        if(CheckRSICondition(Trend_Entry_Condition, Trend_Oversold, trend_rsi_buffer))
        {
            // Open short position
            trade.SetExpertMagicNumber(Trend_Magic);
            trade.Sell(Trend_LotSize, _Symbol, 0, 0, 0, "SmartRSI Trend");
            trend_short_entry_time = TimeCurrent();
        }
        else if(CheckRSICondition(Trend_Entry_Condition, Trend_Overbought, trend_rsi_buffer))
        {
            // Open long position
            trade.SetExpertMagicNumber(Trend_Magic);
            trade.Buy(Trend_LotSize, _Symbol, 0, 0, 0, "SmartRSI Trend");
            trend_long_entry_time = TimeCurrent();
        }
    }
    
    // Exit logic
    if(hasLong && CheckRSICondition(Trend_Exit_Condition, Trend_Exit_Long, trend_rsi_buffer))
    {
        trade.SetExpertMagicNumber(Trend_Magic);
        trade.PositionClose(_Symbol);
    }
    else if(hasShort && CheckRSICondition(Trend_Exit_Condition, Trend_Exit_Short, trend_rsi_buffer))
    {
        trade.SetExpertMagicNumber(Trend_Magic);
        trade.PositionClose(_Symbol);
    }
    
    // Check for opposite trade closing
    if(Trend_CloseOpposite)
    {
        if(hasLong && (TimeCurrent() - trend_long_entry_time) >= Trend_TimeToClose * PeriodSeconds(Trend_TimeFrame))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= Trend_ProfitToClose * _Point)
            {
                // Close short position if exists
                if(PositionSelectByMagic(Trend_Magic, POSITION_TYPE_SELL))
                {
                    trade.SetExpertMagicNumber(Trend_Magic);
                    trade.PositionClose(_Symbol);
                }
            }
        }
        else if(hasShort && (TimeCurrent() - trend_short_entry_time) >= Trend_TimeToClose * PeriodSeconds(Trend_TimeFrame))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= Trend_ProfitToClose * _Point)
            {
                // Close long position if exists
                if(PositionSelectByMagic(Trend_Magic, POSITION_TYPE_BUY))
                {
                    trade.SetExpertMagicNumber(Trend_Magic);
                    trade.PositionClose(_Symbol);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Reversal Strategy                                          |
//+------------------------------------------------------------------+
void CheckReversal()
{
    // Check for existing positions
    bool hasLong = PositionSelectByMagic(Rev_Magic, POSITION_TYPE_BUY);
    bool hasShort = PositionSelectByMagic(Rev_Magic, POSITION_TYPE_SELL);
    
    // Entry logic
    if(!hasLong && !hasShort)
    {
        if(CheckRSICondition(Rev_Entry_Condition, Rev_Oversold, rev_rsi_buffer))
        {
            // Open long position
            trade.SetExpertMagicNumber(Rev_Magic);
            trade.Buy(Rev_LotSize, _Symbol, 0, 0, 0, "SmartRSI Reversal");
            rev_long_entry_time = TimeCurrent();
        }
        else if(CheckRSICondition(Rev_Entry_Condition, Rev_Overbought, rev_rsi_buffer))
        {
            // Open short position
            trade.SetExpertMagicNumber(Rev_Magic);
            trade.Sell(Rev_LotSize, _Symbol, 0, 0, 0, "SmartRSI Reversal");
            rev_short_entry_time = TimeCurrent();
        }
    }
    
    // Exit logic
    if(hasLong && CheckRSICondition(Rev_Exit_Condition, Rev_Exit_Long, rev_rsi_buffer))
    {
        trade.SetExpertMagicNumber(Rev_Magic);
        trade.PositionClose(_Symbol);
    }
    else if(hasShort && CheckRSICondition(Rev_Exit_Condition, Rev_Exit_Short, rev_rsi_buffer))
    {
        trade.SetExpertMagicNumber(Rev_Magic);
        trade.PositionClose(_Symbol);
    }
    
    // Check for opposite trade closing
    if(Rev_CloseOpposite)
    {
        if(hasLong && (TimeCurrent() - rev_long_entry_time) >= Rev_TimeToClose * PeriodSeconds(Rev_TimeFrame))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= Rev_ProfitToClose * _Point)
            {
                // Close short position if exists
                if(PositionSelectByMagic(Rev_Magic, POSITION_TYPE_SELL))
                {
                    trade.SetExpertMagicNumber(Rev_Magic);
                    trade.PositionClose(_Symbol);
                }
            }
        }
        else if(hasShort && (TimeCurrent() - rev_short_entry_time) >= Rev_TimeToClose * PeriodSeconds(Rev_TimeFrame))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= Rev_ProfitToClose * _Point)
            {
                // Close long position if exists
                if(PositionSelectByMagic(Rev_Magic, POSITION_TYPE_BUY))
                {
                    trade.SetExpertMagicNumber(Rev_Magic);
                    trade.PositionClose(_Symbol);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Position Select By Magic                                         |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(int magic, ENUM_POSITION_TYPE posType)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetInteger(POSITION_MAGIC) == magic && 
               PositionGetInteger(POSITION_TYPE) == posType)
            {
                return true;
            }
        }
    }
    return false;
}
