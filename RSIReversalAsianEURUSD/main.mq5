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
input int    RSIPeriod = 14;          // RSI period
input double OverboughtLevel = 78;    // Overbought level
input double OversoldLevel = 20;      // Oversold level
input int    TakeProfitPips = 635;     // Take profit in pips
input int    StopLossPips = 290;       // Stop loss in pips
input double MaxLotSize = 0.1;        // Maximum lot size
input int    MaxSpread = 1000;           // Maximum allowed spread in pips
input int    MaxDuration = 22;         // Maximum trade duration in hours
input bool   UseStopLoss = true;      // Use stop loss
input bool   UseTakeProfit = false;    // Use take profit
input bool   UseRSIExit = true;       // Use RSI for exit
input double RSIExitLevel = 57;       // RSI level to exit (50 = neutral)
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
void UpdatePanel(double rsi, string position, int spread, string session, double sl, double tp)
{
    ObjectSetString(0, panelName + "RSI", OBJPROP_TEXT, "RSI: " + DoubleToString(rsi, 2));
    ObjectSetString(0, panelName + "Position", OBJPROP_TEXT, "Position: " + position);
    ObjectSetString(0, panelName + "Spread", OBJPROP_TEXT, "Spread: " + IntegerToString(spread) + " pips");
    ObjectSetString(0, panelName + "Session", OBJPROP_TEXT, "Session: " + session);
    ObjectSetString(0, panelName + "SL", OBJPROP_TEXT, "Stop Loss: " + IntegerToString(StopLossPips) + " pips");
    ObjectSetString(0, panelName + "TP", OBJPROP_TEXT, "Take Profit: " + IntegerToString(TakeProfitPips) + " pips");
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
        Print("Trading is not allowed for ", _Symbol);
        return false;
    }
    
    // Check if we have enough money
    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) <= 0)
    {
        Print("Not enough free margin");
        return false;
    }
    
    return true;
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
        Print("Failed to create RSI indicator handle");
        return(INIT_FAILED);
    }
    
    // Create panel
    CreatePanel();
    
    Print("Expert Advisor initialized successfully");
    Print("Trading symbol: ", _Symbol);
    Print("Account balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Account leverage: ", AccountInfoInteger(ACCOUNT_LEVERAGE));
    
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
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == 123457)
        {
            hasOurPositions = true;
            break;
        }
    }
    
    // Return if no positions with our magic number
    if(!hasOurPositions)
        return true;

    Print("Attempting to close all positions", (reason != "" ? " - " + reason : ""));
    
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
                    Print("Position closed successfully");
                    isPositionOpen = false;
                    positionClosed = true;
                }
                else
                {
                    int error = GetLastError();
                    Print("Failed to close position. Error: ", error, " Retry: ", retryCount + 1);
                    
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
                Print("Failed to close position after all retries");
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
        Print("Trading is not allowed at the moment");
        return;
    }
    
    // Check if we're in Asian session
    if(!IsAsianSession())
    {
        Print("Not in Asian session");
        
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
        Print("Spread too high: ", spreadInPips, " pips");
        return;
    }
    
    // Get RSI value
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) != 1)
        return;
        
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
    
    // Update panel
    UpdatePanel(rsi[0], positionStatus, spreadInPips, GetCurrentSession(), sl, tp);
    
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
            if(UseRSIExit)
            {
                bool shouldExit = false;
                
                // For long positions, exit when RSI reaches or exceeds exit level
                if(posType == POSITION_TYPE_BUY && rsi[0] >= RSIExitLevel)
                {
                    Print("Closing long position due to RSI exit. RSI: ", rsi[0], " Exit Level: ", RSIExitLevel);
                    shouldExit = true;
                }
                // For short positions, exit when RSI reaches or falls below exit level
                else if(posType == POSITION_TYPE_SELL && rsi[0] <= RSIExitLevel)
                {
                    Print("Closing short position due to RSI exit. RSI: ", rsi[0], " Exit Level: ", RSIExitLevel);
                    shouldExit = true;
                }
                
                if(shouldExit)
                {
                    CloseAllTrades("RSI Exit");
                    return;
                }
            }
            
            // Check for timeout
            if(TimeCurrent() - positionOpenTime > MaxDuration * 3600)
            {
                Print("Closing position due to timeout");
                CloseAllTrades("Timeout");
                return;
            }
            
            break;
        }
    }
    
    // If no position is open, look for entry signals
    if(!hasOpenPosition)
    {
        // Place buy order if RSI is oversold
        if(rsi[0] <= OversoldLevel)
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
            trade.SetExpertMagicNumber(123457);
            
            // Place buy order using CTrade
            if(!trade.Buy(MaxLotSize, _Symbol, currentAsk, sl, tp, "RSI Buy"))
            {
                Print("Buy order failed. Error code: ", GetLastError());
            }
            else
            {
                Print("Buy order placed. RSI: ", rsi[0]);
                isPositionOpen = true;
                positionOpenPrice = currentAsk;
                positionOpenTime = TimeCurrent();
                lastPositionType = POSITION_TYPE_BUY;
            }
        }
        // Place sell order if RSI is overbought
        else if(rsi[0] >= OverboughtLevel)
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
            trade.SetExpertMagicNumber(123457);
            
            // Place sell order using CTrade
            if(!trade.Sell(MaxLotSize, _Symbol, currentBid, sl, tp, "RSI Sell"))
            {
                Print("Sell order failed. Error code: ", GetLastError());
            }
            else
            {
                Print("Sell order placed. RSI: ", rsi[0]);
                isPositionOpen = true;
                positionOpenPrice = currentBid;
                positionOpenTime = TimeCurrent();
                lastPositionType = POSITION_TYPE_SELL;
            }
        }
    }
}
