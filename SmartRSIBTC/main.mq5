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
input int RSI_Period = 89;                // RSI Period
input ENUM_APPLIED_PRICE RSI_Price = PRICE_TYPICAL; // RSI Applied Price

// Strategy Selection
input group "Strategy Selection"
input bool UseTrendFollowing = true;      // Use Trend Following Strategy
input bool UseReversal = false;            // Use Reversal Strategy

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
input ENUM_RSI_CONDITION Trend_Exit_Condition = RSI_ABOVE_MIDPOINT;  // Trend Exit Condition
input ENUM_RSI_CONDITION Rev_Entry_Condition = RSI_BELOW_OVERSOLD;   // Reversal Entry Condition
input ENUM_RSI_CONDITION Rev_Exit_Condition = RSI_ABOVE_MIDPOINT;    // Reversal Exit Condition

// Trend Following Strategy Parameters
input group "Trend Following Strategy"
input double Trend_Overbought = 51;       // Overbought level for trend following
input double Trend_Oversold = 30;         // Oversold level for trend following
input double Trend_Exit_Long = 50;        // Exit level for long positions
input double Trend_Exit_Short = 50;       // Exit level for short positions
input double Trend_LotSize = 0.1;         // Lot size for trend following
input int Trend_Magic = 12345;            // Magic number for trend following
input bool Trend_CloseOpposite = true;    // Close opposite trades on profit
input double Trend_ProfitToClose = 15;    // Profit in points to close opposite trades
input int Trend_TimeToClose = 9;          // Bars to wait before closing opposite trades

// Reversal Strategy Parameters
input group "Reversal Strategy"
input double Rev_Overbought = 70;         // Overbought level for reversal
input double Rev_Oversold = 30;           // Oversold level for reversal
input double Rev_Exit_Long = 50;          // Exit level for long positions
input double Rev_Exit_Short = 50;         // Exit level for short positions
input double Rev_LotSize = 0.1;           // Lot size for reversal
input int Rev_Magic = 54321;              // Magic number for reversal
input bool Rev_CloseOpposite = true;      // Close opposite trades on profit
input double Rev_ProfitToClose = 50;      // Profit in points to close opposite trades
input int Rev_TimeToClose = 5;            // Bars to wait before closing opposite trades



// Indicator buffers
double rsi_buffer[];
int rsi_handle;
CTrade trade;
datetime last_bar_time;
datetime trend_long_entry_time = 0;
datetime trend_short_entry_time = 0;
datetime rev_long_entry_time = 0;
datetime rev_short_entry_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicator
    rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, RSI_Price);
    if(rsi_handle == INVALID_HANDLE)
    {
        Print("Failed to create RSI indicator");
        return INIT_FAILED;
    }
    
    // Set buffer size and series
    ArraySetAsSeries(rsi_buffer, true);
    
    // Initialize trade object
    trade.SetExpertMagicNumber(Trend_Magic);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(10);
    
    // Initialize last bar time
    last_bar_time = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(rsi_handle != INVALID_HANDLE)
        IndicatorRelease(rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    // Check if new bar has formed
    if(current_time != last_bar_time)
    {
        last_bar_time = current_time;
        
        // Update RSI values
        if(CopyBuffer(rsi_handle, 0, 0, 2, rsi_buffer) <= 0)
        {
            Print("Failed to copy RSI buffer");
            return;
        }
            
        // Run strategies if enabled
        if(UseTrendFollowing)
            CheckTrendFollowing();
            
        if(UseReversal)
            CheckReversal();
    }
}

//+------------------------------------------------------------------+
//| Check RSI Condition                                              |
//+------------------------------------------------------------------+
bool CheckRSICondition(ENUM_RSI_CONDITION condition, double level)
{
    switch(condition)
    {
        case RSI_BELOW_OVERSOLD:
            return rsi_buffer[0] < level;
        case RSI_ABOVE_OVERBOUGHT:
            return rsi_buffer[0] > level;
        case RSI_BELOW_MIDPOINT:
            return rsi_buffer[0] < 50;
        case RSI_ABOVE_MIDPOINT:
            return rsi_buffer[0] > 50;
        case RSI_CROSS_OVERSOLD:
            return rsi_buffer[0] < level && rsi_buffer[1] >= level;
        case RSI_CROSS_OVERBOUGHT:
            return rsi_buffer[0] > level && rsi_buffer[1] <= level;
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
        if(CheckRSICondition(Trend_Entry_Condition, Trend_Oversold))
        {
            // Open short position
            trade.SetExpertMagicNumber(Trend_Magic);
            trade.Sell(Trend_LotSize, _Symbol, 0, 0, 0, "SmartRSI Trend");
            trend_short_entry_time = TimeCurrent();
        }
        else if(CheckRSICondition(Trend_Entry_Condition, Trend_Overbought))
        {
            // Open long position
            trade.SetExpertMagicNumber(Trend_Magic);
            trade.Buy(Trend_LotSize, _Symbol, 0, 0, 0, "SmartRSI Trend");
            trend_long_entry_time = TimeCurrent();
        }
    }
    
    // Exit logic
    if(hasLong && CheckRSICondition(Trend_Exit_Condition, Trend_Exit_Long))
    {
        trade.SetExpertMagicNumber(Trend_Magic);
        trade.PositionClose(_Symbol);
    }
    else if(hasShort && CheckRSICondition(Trend_Exit_Condition, Trend_Exit_Short))
    {
        trade.SetExpertMagicNumber(Trend_Magic);
        trade.PositionClose(_Symbol);
    }
    
    // Check for opposite trade closing
    if(Trend_CloseOpposite)
    {
        if(hasLong && (TimeCurrent() - trend_long_entry_time) >= Trend_TimeToClose * PeriodSeconds(PERIOD_CURRENT))
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
        else if(hasShort && (TimeCurrent() - trend_short_entry_time) >= Trend_TimeToClose * PeriodSeconds(PERIOD_CURRENT))
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
        if(CheckRSICondition(Rev_Entry_Condition, Rev_Oversold))
        {
            // Open long position
            trade.SetExpertMagicNumber(Rev_Magic);
            trade.Buy(Rev_LotSize, _Symbol, 0, 0, 0, "SmartRSI Reversal");
            rev_long_entry_time = TimeCurrent();
        }
        else if(CheckRSICondition(Rev_Entry_Condition, Rev_Overbought))
        {
            // Open short position
            trade.SetExpertMagicNumber(Rev_Magic);
            trade.Sell(Rev_LotSize, _Symbol, 0, 0, 0, "SmartRSI Reversal");
            rev_short_entry_time = TimeCurrent();
        }
    }
    
    // Exit logic
    if(hasLong && CheckRSICondition(Rev_Exit_Condition, Rev_Exit_Long))
    {
        trade.SetExpertMagicNumber(Rev_Magic);
        trade.PositionClose(_Symbol);
    }
    else if(hasShort && CheckRSICondition(Rev_Exit_Condition, Rev_Exit_Short))
    {
        trade.SetExpertMagicNumber(Rev_Magic);
        trade.PositionClose(_Symbol);
    }
    
    // Check for opposite trade closing
    if(Rev_CloseOpposite)
    {
        if(hasLong && (TimeCurrent() - rev_long_entry_time) >= Rev_TimeToClose * PeriodSeconds(PERIOD_CURRENT))
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
        else if(hasShort && (TimeCurrent() - rev_short_entry_time) >= Rev_TimeToClose * PeriodSeconds(PERIOD_CURRENT))
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
