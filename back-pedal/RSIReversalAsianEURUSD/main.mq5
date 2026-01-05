//+------------------------------------------------------------------+
//|                                      SimpleRSIReversalAUDUSD.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include trade class
#include <Trade\Trade.mqh>

// Input parameters
input int    RSIPeriod = 28;          // RSI period
input double OverboughtLevel = 60;    // Overbought level
input double OversoldLevel = 8;      // Oversold level
input int    TakeProfitPips = 175;     // Take profit in pips
input int    StopLossPips = 5;       // Stop loss in pips
input double MaxLotSize = 0.1;        // Maximum lot size
input int    MaxSpread = 1000;           // Maximum allowed spread in pips
input int    MaxDuration = 270;         // Maximum trade duration in hours
input bool   UseStopLoss = false;      // Use stop loss
input bool   UseTakeProfit = false;    // Use take profit
input bool   UseRSIExit = true;       // Use RSI for exit
input double RSIExitLevel = 55;       // RSI level to exit (50 = neutral)
input bool   CloseOutsideSession = false; // Close trades outside Asian session
input color  PanelBackground = clrBlack; // Panel background color
input color  PanelText = clrWhite;    // Panel text color
input int    PanelX = 10;            // Panel X position
input int    PanelY = 20;            // Panel Y position

// Global variables
CTrade trade;
int rsiHandle;
bool isPositionOpen = false;
double positionOpenPrice = 0;
datetime positionOpenTime = 0;
ENUM_POSITION_TYPE lastPositionType = POSITION_TYPE_BUY;
bool sessionCloseAttempted = false;  // Track if we've attempted to close positions for current session

// RSI crossover variables
double rsiCurrent = 0;
double rsiPrevious = 0;
double rsiPrevious2 = 0;
bool rsiCrossedOverbought = false;
bool rsiCrossedOversold = false;
bool rsiCrossedExitLevel = false;

// Panel objects
string panelName = "RSIPanel";
int panelWidth = 200;
int panelHeight = 200;
int labelHeight = 20;
int labelSpacing = 5;

// Session times (UTC)
const int AsianSessionStart = 0;    // 00:00 UTC
const int AsianSessionEnd = 8;      // 08:00 UTC

//+------------------------------------------------------------------+
//| Create panel                                                      |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // Create panel background
    ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, PanelX);
    ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, PanelY);
    ObjectSetInteger(0, panelName, OBJPROP_XSIZE, panelWidth);
    ObjectSetInteger(0, panelName, OBJPROP_YSIZE, panelHeight);
    ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, PanelBackground);
    ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, panelName, OBJPROP_COLOR, PanelText);
    ObjectSetInteger(0, panelName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, panelName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, panelName, OBJPROP_BACK, false);
    ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, panelName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, panelName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, panelName, OBJPROP_ZORDER, 0);
    
    // Create title label
    ObjectCreate(0, panelName + "Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, panelName + "Title", OBJPROP_XDISTANCE, PanelX + 5);
    ObjectSetInteger(0, panelName + "Title", OBJPROP_YDISTANCE, PanelY + 5);
    ObjectSetInteger(0, panelName + "Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, panelName + "Title", OBJPROP_TEXT, "RSI Reversal");
    ObjectSetInteger(0, panelName + "Title", OBJPROP_COLOR, PanelText);
    ObjectSetInteger(0, panelName + "Title", OBJPROP_FONTSIZE, 10);
    
    // Create score labels
    CreateScoreLabel("RSI", "RSI: ", 0);
    CreateScoreLabel("Position", "Position: ", 1);
    CreateScoreLabel("Spread", "Spread: ", 2);
    CreateScoreLabel("Session", "Session: ", 3);
    CreateScoreLabel("SL", "Stop Loss: ", 4);
    CreateScoreLabel("TP", "Take Profit: ", 5);
    CreateScoreLabel("Cross", "Cross: ", 6);
}

//+------------------------------------------------------------------+
//| Create score label                                                |
//+------------------------------------------------------------------+
void CreateScoreLabel(string name, string text, int index)
{
    ObjectCreate(0, panelName + name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, panelName + name, OBJPROP_XDISTANCE, PanelX + 5);
    ObjectSetInteger(0, panelName + name, OBJPROP_YDISTANCE, PanelY + 30 + index * (labelHeight + labelSpacing));
    ObjectSetInteger(0, panelName + name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, panelName + name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, panelName + name, OBJPROP_COLOR, PanelText);
    ObjectSetInteger(0, panelName + name, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| Update panel values                                               |
//+------------------------------------------------------------------+
void UpdatePanel(double rsi, string position, int spread, string session, double sl, double tp, string crossInfo)
{
    ObjectSetString(0, panelName + "RSI", OBJPROP_TEXT, "RSI: " + DoubleToString(rsi, 2));
    ObjectSetString(0, panelName + "Position", OBJPROP_TEXT, "Position: " + position);
    ObjectSetString(0, panelName + "Spread", OBJPROP_TEXT, "Spread: " + IntegerToString(spread) + " pips");
    ObjectSetString(0, panelName + "Session", OBJPROP_TEXT, "Session: " + session);
    ObjectSetString(0, panelName + "SL", OBJPROP_TEXT, "Stop Loss: " + IntegerToString(StopLossPips) + " pips");
    ObjectSetString(0, panelName + "TP", OBJPROP_TEXT, "Take Profit: " + IntegerToString(TakeProfitPips) + " pips");
    ObjectSetString(0, panelName + "Cross", OBJPROP_TEXT, "Cross: " + crossInfo);
}

//+------------------------------------------------------------------+
//| Check if current time is in Asian session                         |
//+------------------------------------------------------------------+
bool IsAsianSession()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    
    return (timeStruct.hour >= AsianSessionStart && timeStruct.hour < AsianSessionEnd);
}

//+------------------------------------------------------------------+
//| Get current session name                                          |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    
    if(timeStruct.hour >= AsianSessionStart && timeStruct.hour < AsianSessionEnd)
        return "Asian";
    else if(timeStruct.hour >= 8 && timeStruct.hour < 16)
        return "London";
    else if(timeStruct.hour >= 13 && timeStruct.hour < 21)
        return "New York";
    else
        return "Other";
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                       |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    // Check if market is open
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
    {
        return false;
    }
    
    // Check if we have enough money
    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) <= 0)
    {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check RSI crossover conditions                                    |
//+------------------------------------------------------------------+
void CheckRSICrossover()
{
    // Reset crossover flags
    rsiCrossedOverbought = false;
    rsiCrossedOversold = false;
    rsiCrossedExitLevel = false;
    
    // Check for overbought crossover (RSI crosses above overbought level)
    if(rsiPrevious < OverboughtLevel && rsiCurrent >= OverboughtLevel)
    {
        rsiCrossedOverbought = true;
    }
    
    // Check for oversold crossover (RSI crosses below oversold level)
    if(rsiPrevious > OversoldLevel && rsiCurrent <= OversoldLevel)
    {
        rsiCrossedOversold = true;
    }
    
    // Check for exit level crossover
    if(rsiPrevious < RSIExitLevel && rsiCurrent >= RSIExitLevel)
    {
        rsiCrossedExitLevel = true;
    }
    else if(rsiPrevious > RSIExitLevel && rsiCurrent <= RSIExitLevel)
    {
        rsiCrossedExitLevel = true;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicator
    rsiHandle = iRSI(_Symbol, PERIOD_M15, RSIPeriod, PRICE_CLOSE);
    
    if(rsiHandle == INVALID_HANDLE)
    {
        return(INIT_FAILED);
    }
    
    // Wait a bit for the indicator to be ready
    Sleep(100);
    
    // Initialize RSI values with retry logic
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    int retryCount = 0;
    bool rsiInitialized = false;
    
    while(retryCount < 10 && !rsiInitialized)
    {
        int copied = CopyBuffer(rsiHandle, 0, 0, 3, rsi);
        if(copied >= 3)
        {
            rsiCurrent = rsi[0];
            rsiPrevious = rsi[1];
            rsiPrevious2 = rsi[2];
            rsiInitialized = true;
        }
        else
        {
            retryCount++;
            Sleep(100);
        }
    }
    
    if(!rsiInitialized)
    {
        // Don't fail initialization, just set default values
        rsiCurrent = 50.0;
        rsiPrevious = 50.0;
        rsiPrevious2 = 50.0;
    }
    
    // Create panel
    CreatePanel();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(rsiHandle);
    
    // Remove panel objects
    ObjectsDeleteAll(0, panelName);
}

//+------------------------------------------------------------------+
//| Close all trades for the current symbol                           |
//+------------------------------------------------------------------+
bool CloseAllTrades(string reason = "")
{
    bool allClosed = true;
    int totalPositions = PositionsTotal();
    
    if(totalPositions == 0)
        return true;
    
    // Check if there are any positions with our magic number
    bool hasOurPositions = false;
    for(int i = 0; i < totalPositions; i++)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == 123456)
        {
            hasOurPositions = true;
            break;
        }
    }

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            // Try to close position with retry logic
            int retryCount = 0;
            bool positionClosed = false;
            
            while(retryCount < 3 && !positionClosed)
            {
                if(trade.PositionClose(_Symbol))
                {
                    isPositionOpen = false;
                    positionClosed = true;
                }
                else
                {
                    int error = GetLastError();
                    
                    // If error is 4756 (Trade disabled), wait longer before retry
                    if(error == 4756)
                    {
                        Sleep(5000); // Wait 5 seconds before retry
                        retryCount++;
                    }
                    else
                    {
                        // For other errors, break the loop
                        break;
                    }
                }
            }
            
            if(!positionClosed)
            {
                allClosed = false;
            }
        }
    }
    
    return allClosed;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if trading is allowed
    if(!IsTradingAllowed())
    {
        return;
    }
    
    // Check if we're in Asian session
    if(!IsAsianSession())
    {
        // Close all positions if outside Asian session and CloseOutsideSession is true
        if(CloseOutsideSession && !sessionCloseAttempted)
        {
            CloseAllTrades("Outside Asian session");
            sessionCloseAttempted = true;
        }
        return;
    }
    else
    {
        // Reset the session close attempt flag when we enter Asian session
        sessionCloseAttempted = false;
    }
    
    // Get current spread
    double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int spreadInPips = (int)(spread / _Point);
    
    // Check if spread is too high
    if(spreadInPips > MaxSpread)
    {
        return;
    }
    
    // Get RSI values from bar data
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    int copied = CopyBuffer(rsiHandle, 0, 0, 3, rsi);
    if(copied < 3)
    {
        return;
    }
    
    // Update RSI values
    rsiPrevious2 = rsiPrevious;
    rsiPrevious = rsiCurrent;
    rsiCurrent = rsi[0];
    
    // Validate RSI values
    if(rsiCurrent == 0 || rsiPrevious == 0)
    {
        return;
    }
    
    // Check for RSI crossovers
    CheckRSICrossover();
    
    // Get current prices
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Get position status
    string positionStatus = "None";
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            positionStatus = (posType == POSITION_TYPE_BUY) ? "Long" : "Short";
            break;
        }
    }
    
    // Calculate stop loss and take profit levels
    double sl = 0;
    double tp = 0;
    
    // Prepare crossover info for panel
    string crossInfo = "None";
    if(rsiCrossedOverbought) crossInfo = "Overbought";
    else if(rsiCrossedOversold) crossInfo = "Oversold";
    else if(rsiCrossedExitLevel) crossInfo = "Exit";
    
    // Update panel
    UpdatePanel(rsiCurrent, positionStatus, spreadInPips, GetCurrentSession(), sl, tp, crossInfo);
    
    // Check for open position
    bool hasOpenPosition = false;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            hasOpenPosition = true;
            
            // Get position details
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            double positionVolume = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Check for RSI exit if enabled
            if(UseRSIExit && rsiCrossedExitLevel)
            {
                bool shouldExit = false;
                
                // For long positions, exit when RSI crosses above exit level
                if(posType == POSITION_TYPE_BUY && rsiCurrent >= RSIExitLevel && rsiPrevious < RSIExitLevel)
                {
                    shouldExit = true;
                }
                // For short positions, exit when RSI crosses below exit level
                else if(posType == POSITION_TYPE_SELL && rsiCurrent <= RSIExitLevel && rsiPrevious > RSIExitLevel)
                {
                    shouldExit = true;
                }
                
                if(shouldExit)
                {
                    CloseAllTrades("RSI Exit Crossover");
                    return;
                }
            }
            
            // Check for timeout
            if(TimeCurrent() - positionOpenTime > MaxDuration * 3600)
            {
                CloseAllTrades("Timeout");
                return;
            }
            
            break;
        }
    }
    
    // If no position is open, look for entry signals based on RSI crossover
    if(!hasOpenPosition)
    {
        // Place buy order if RSI crosses below oversold level (oversold crossover)
        if(rsiCrossedOversold)
        {
            double sl = UseStopLoss ? currentBid - StopLossPips * _Point : 0;
            double tp = UseTakeProfit ? currentBid + TakeProfitPips * _Point : 0;
            
            if(UseStopLoss && sl >= currentBid)
                return;
            if(UseTakeProfit && tp <= currentBid)
                return;
                
            // Set trade parameters
            trade.SetDeviationInPoints(3);
            trade.SetTypeFilling(ORDER_FILLING_IOC);
            trade.SetExpertMagicNumber(123456);
            
            // Place buy order using CTrade
            if(trade.Buy(MaxLotSize, _Symbol, currentAsk, sl, tp, "RSI Oversold Crossover Buy"))
            {
                isPositionOpen = true;
                positionOpenPrice = currentAsk;
                positionOpenTime = TimeCurrent();
                lastPositionType = POSITION_TYPE_BUY;
            }
        }
        // Place sell order if RSI crosses above overbought level (overbought crossover)
        else if(rsiCrossedOverbought)
        {
            double sl = UseStopLoss ? currentAsk + StopLossPips * _Point : 0;
            double tp = UseTakeProfit ? currentAsk - TakeProfitPips * _Point : 0;
            
            if(UseStopLoss && sl <= currentAsk)
                return;
            if(UseTakeProfit && tp >= currentAsk)
                return;
                
            // Set trade parameters
            trade.SetDeviationInPoints(3);
            trade.SetTypeFilling(ORDER_FILLING_IOC);
            trade.SetExpertMagicNumber(123456);
            
            // Place sell order using CTrade
            if(trade.Sell(MaxLotSize, _Symbol, currentBid, sl, tp, "RSI Overbought Crossover Sell"))
            {
                isPositionOpen = true;
                positionOpenPrice = currentBid;
                positionOpenTime = TimeCurrent();
                lastPositionType = POSITION_TYPE_SELL;
            }
        }
    }
}