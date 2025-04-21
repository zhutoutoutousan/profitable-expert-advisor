//+------------------------------------------------------------------+
//|                                             RSIReverseFollow.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input parameters
input group "Timeframe Settings"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M3; // Trading Timeframe

input group "RSI Settings"
input int    InpRSIPeriod = 48;          // RSI Period
input double InpRSIOverbought = 68;      // RSI Overbought Level
input double InpRSIOversold = 12;        // RSI Oversold Level
input double InpRSI50Distance = 4.0;     // Distance from 50 to consider as near

input group "Strategy 1 - RSI 50 Touch"
input bool   InpEnableStrategy1 = true;  // Enable Strategy 1
input int    InpMagicNumber1 = 123456;   // Magic Number for Strategy 1
input double InpLotSize1 = 0.01;         // Lot Size for Strategy 1
input bool   InpEnableRSIExit1 = true;   // Enable RSI-based exit for Strategy 1
input bool   InpUseSLTPWithRSI1 = false;  // Use SL/TP alongside RSI exits
input int    InpStopLoss1 = 188;          // Stop Loss in pips
input int    InpTakeProfit1 = 547;       // Take Profit in pips
input double InpRSIExitBuy1 = 97.0;      // RSI level to exit buy trades
input double InpRSIExitSell1 = 20.0;     // RSI level to exit sell trades
input int    InpTrailingStop1 = 125;      // Trailing Stop in pips
input int    InpTrailingStep1 = 400;      // Trailing Step in pips
input int    InpMaxTradeDuration1 = 22;  // Maximum trade duration (hours)
input double InpLossThreshold1 = 7.1;   // Minimum loss threshold to close trade

input group "Strategy 2 - RSI Reversal"
input bool   InpEnableStrategy2 = true;  // Enable Strategy 2
input int    InpMagicNumber2 = 123457;   // Magic Number for Strategy 2
input double InpLotSize2 = 0.01;         // Lot Size for Strategy 2
input bool   InpEnableRSIExit2 = false;   // Enable RSI-based exit for Strategy 2
input bool   InpUseSLTPWithRSI2 = true;  // Use SL/TP alongside RSI exits
input int    InpStopLoss2 = 245;          // Stop Loss in pips
input int    InpTakeProfit2 = 410;       // Take Profit in pips
input double InpRSIExitBuy2 = 70.0;      // RSI level to exit buy trades
input double InpRSIExitSell2 = 5.0;     // RSI level to exit sell trades
input int    InpTrailingStop2 = 185;      // Trailing Stop in pips
input int    InpTrailingStep2 = 30;      // Trailing Step in pips
input int    InpMaxTradeDuration2 = 6;  // Maximum trade duration (hours)
input double InpLossThreshold2 = 9.3;   // Minimum loss threshold to close trade

input group "Trading Hours"
input int    InpStartHour = 16;           // Trading Session Start Hour
input int    InpEndHour = 19;            // Trading Session End Hour
input bool   InpCloseOutsideHours = true;// Close trades outside trading hours

// Global variables
CTrade trade;
int rsiHandle;
double lastRSI[];
bool wasOverbought = false;
bool wasOversold = false;
datetime lastBarTime = 0;
bool debugMode = true; // Enable detailed logging

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize RSI indicator
   rsiHandle = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return INIT_FAILED;
   }
   
   // Initialize trade settings
   trade.SetExpertMagicNumber(InpMagicNumber1);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   
   // Initialize RSI array
   ArraySetAsSeries(lastRSI, true);
   ArrayResize(lastRSI, 3);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
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
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   return (timeStruct.hour >= InpStartHour && timeStruct.hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Check for RSI signals                                            |
//+------------------------------------------------------------------+
void CheckRSISignals()
{
   // Get RSI values for current and previous bars
   if(CopyBuffer(rsiHandle, 0, 0, 3, lastRSI) <= 0)
   {
      Print("Error getting RSI values");
      return;
   }
      
   // Check for RSI extremes
   if(lastRSI[0] >= InpRSIOverbought)
   {
      wasOverbought = true;
   }
   
   if(lastRSI[0] <= InpRSIOversold)
   {
      wasOversold = true;
   }
}

//+------------------------------------------------------------------+
//| Check for trailing stop                                          |
//+------------------------------------------------------------------+
void CheckTrailingStop(int magic, int trailingStop, int trailingStep)
{
   if(!PositionSelectByTicket(magic))
      return;
      
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double stopLoss = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double newStopLoss = 0;
   double trailingStopPoints = trailingStop * _Point;
   double trailingStepPoints = trailingStep * _Point;
   
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentPrice - openPrice > trailingStopPoints)
      {
         newStopLoss = currentPrice - trailingStopPoints;
         if(newStopLoss > stopLoss + trailingStepPoints)
         {
            trade.PositionModify(magic, newStopLoss, PositionGetDouble(POSITION_TP));
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(openPrice - currentPrice > trailingStopPoints)
      {
         newStopLoss = currentPrice + trailingStopPoints;
         if(newStopLoss < stopLoss - trailingStepPoints || stopLoss == 0)
         {
            trade.PositionModify(magic, newStopLoss, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for time-based exits                                       |
//+------------------------------------------------------------------+
void CheckTimeBasedExits(int magic, int maxDuration, double lossThreshold)
{
   datetime currentTime = TimeCurrent();
   
   if(PositionSelectByTicket(magic))
   {
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      double totalLoss = profit + swap;
      
      if(currentTime - openTime >= maxDuration * 3600)
      {
         if(totalLoss < -lossThreshold)
         {
            trade.PositionClose(magic);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for trading hours exits                                    |
//+------------------------------------------------------------------+
void CheckTradingHoursExits()
{
   if(!InpCloseOutsideHours)
      return;
      
   if(!IsWithinTradingHours())
   {
      // Close Strategy 1 positions
      if(PositionSelectByTicket(InpMagicNumber1))
      {
         trade.PositionClose(InpMagicNumber1);
      }
      
      // Close Strategy 2 positions
      if(PositionSelectByTicket(InpMagicNumber2))
      {
         trade.PositionClose(InpMagicNumber2);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for RSI-based exits                                        |
//+------------------------------------------------------------------+
void CheckRSIExits(int magic, bool enableRSIExit, double exitBuyLevel, double exitSellLevel)
{
   if(!enableRSIExit)
      return;
      
   // Try to find position by magic number
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double currentRSI = lastRSI[0];
            
            if(posType == POSITION_TYPE_BUY && currentRSI <= exitBuyLevel)
            {
               ulong ticket = PositionGetTicket(i);
               if(trade.PositionClose(ticket))
               {
                  Print("Strategy ", magic == InpMagicNumber1 ? "1" : "2", " Buy position closed due to RSI exit level",
                        "\nTicket: ", ticket,
                        "\nRSI: ", DoubleToString(currentRSI, 2),
                        "\nExit Level: ", DoubleToString(exitBuyLevel, 2));
               }
               else
               {
                  Print("Failed to close Strategy ", magic == InpMagicNumber1 ? "1" : "2", " Buy position",
                        "\nTicket: ", ticket,
                        "\nRSI: ", DoubleToString(currentRSI, 2),
                        "\nExit Level: ", DoubleToString(exitBuyLevel, 2),
                        "\nError: ", GetLastError());
               }
            }
            else if(posType == POSITION_TYPE_SELL && currentRSI >= exitSellLevel)
            {
               ulong ticket = PositionGetTicket(i);
               if(trade.PositionClose(ticket))
               {
                  Print("Strategy ", magic == InpMagicNumber1 ? "1" : "2", " Sell position closed due to RSI exit level",
                        "\nTicket: ", ticket,
                        "\nRSI: ", DoubleToString(currentRSI, 2),
                        "\nExit Level: ", DoubleToString(exitSellLevel, 2));
               }
               else
               {
                  Print("Failed to close Strategy ", magic == InpMagicNumber1 ? "1" : "2", " Sell position",
                        "\nTicket: ", ticket,
                        "\nRSI: ", DoubleToString(currentRSI, 2),
                        "\nExit Level: ", DoubleToString(exitSellLevel, 2),
                        "\nError: ", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check trading hours exits
   CheckTradingHoursExits();
   
   // Only process on new bar
   if(!IsNewBar())
   {
      // Check trailing stops and time-based exits every tick
      if(InpEnableStrategy1)
      {
         CheckTrailingStop(InpMagicNumber1, InpTrailingStop1, InpTrailingStep1);
         CheckTimeBasedExits(InpMagicNumber1, InpMaxTradeDuration1, InpLossThreshold1);
      }
      
      if(InpEnableStrategy2)
      {
         CheckTrailingStop(InpMagicNumber2, InpTrailingStop2, InpTrailingStep2);
         CheckTimeBasedExits(InpMagicNumber2, InpMaxTradeDuration2, InpLossThreshold2);
      }
      return;
   }
   
   // Check for RSI signals
   CheckRSISignals();
   
   // Get current price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = 0;
   double takeProfit = 0;
   
   // Strategy 1: Enter on RSI 50 touch after oversold/overbought
   if(InpEnableStrategy1)
   {
      if(!IsWithinTradingHours())
      {
         MqlDateTime timeStruct;
         TimeToStruct(TimeCurrent(), timeStruct);
         Print("Strategy 1: Outside trading hours",
               "\nCurrent Hour: ", timeStruct.hour,
               "\nTrading Hours: ", InpStartHour, ":00 - ", InpEndHour, ":00");
         return;
      }
      
      // Check for RSI-based exits for Strategy 1
      if(InpEnableRSIExit1)
      {
         CheckRSIExits(InpMagicNumber1, true, InpRSIExitBuy1, InpRSIExitSell1);
      }
      
      // Log current RSI state
      Print("Strategy 1 Current State:",
            "\nRSI: ", DoubleToString(lastRSI[0], 2),
            "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2),
            "\nWas Oversold: ", wasOversold ? "Yes" : "No",
            "\nWas Overbought: ", wasOverbought ? "Yes" : "No",
            "\nPosition Exists: ", PositionSelectByTicket(InpMagicNumber1) ? "Yes" : "No");
      
      // Buy signal: RSI was oversold and now is near 50
      if(wasOversold && MathAbs(lastRSI[0] - 50) <= InpRSI50Distance)
      {
         if(!PositionSelectByTicket(InpMagicNumber1))
         {
            stopLoss = InpEnableRSIExit1 && !InpUseSLTPWithRSI1 ? 0 : currentPrice - InpStopLoss1 * _Point;
            takeProfit = InpEnableRSIExit1 && !InpUseSLTPWithRSI1 ? 0 : currentPrice + InpTakeProfit1 * _Point;
            
            trade.SetExpertMagicNumber(InpMagicNumber1);
            if(trade.Buy(InpLotSize1, _Symbol, 0, stopLoss, takeProfit, "RSI 50 Touch Buy"))
            {
               Print("Strategy 1 Buy trade executed: RSI was oversold and now near 50",
                     "\nRSI: ", DoubleToString(lastRSI[0], 2),
                     "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2),
                     "\nEntry Price: ", DoubleToString(currentPrice, _Digits),
                     "\nStop Loss: ", stopLoss == 0 ? "None" : DoubleToString(stopLoss, _Digits),
                     "\nTake Profit: ", takeProfit == 0 ? "None" : DoubleToString(takeProfit, _Digits));
               wasOversold = false;
            }
            else
            {
               Print("Failed to execute Strategy 1 Buy trade",
                     "\nRSI: ", DoubleToString(lastRSI[0], 2),
                     "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2),
                     "\nError: ", GetLastError());
            }
         }
         else
         {
            Print("Strategy 1 Buy signal detected but position already exists",
                  "\nRSI: ", DoubleToString(lastRSI[0], 2),
                  "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2));
         }
      }
      
      // Sell signal: RSI was overbought and now is near 50
      if(wasOverbought && MathAbs(lastRSI[0] - 50) <= InpRSI50Distance)
      {
         if(!PositionSelectByTicket(InpMagicNumber1))
         {
            stopLoss = InpEnableRSIExit1 && !InpUseSLTPWithRSI1 ? 0 : currentPrice + InpStopLoss1 * _Point;
            takeProfit = InpEnableRSIExit1 && !InpUseSLTPWithRSI1 ? 0 : currentPrice - InpTakeProfit1 * _Point;
            
            trade.SetExpertMagicNumber(InpMagicNumber1);
            if(trade.Sell(InpLotSize1, _Symbol, 0, stopLoss, takeProfit, "RSI 50 Touch Sell"))
            {
               Print("Strategy 1 Sell trade executed: RSI was overbought and now near 50",
                     "\nRSI: ", DoubleToString(lastRSI[0], 2),
                     "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2),
                     "\nEntry Price: ", DoubleToString(currentPrice, _Digits),
                     "\nStop Loss: ", stopLoss == 0 ? "None" : DoubleToString(stopLoss, _Digits),
                     "\nTake Profit: ", takeProfit == 0 ? "None" : DoubleToString(takeProfit, _Digits));
               wasOverbought = false;
            }
            else
            {
               Print("Failed to execute Strategy 1 Sell trade",
                     "\nRSI: ", DoubleToString(lastRSI[0], 2),
                     "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2),
                     "\nError: ", GetLastError());
            }
         }
         else
         {
            Print("Strategy 1 Sell signal detected but position already exists",
                  "\nRSI: ", DoubleToString(lastRSI[0], 2),
                  "\nDistance from 50: ", DoubleToString(MathAbs(lastRSI[0] - 50), 2));
         }
      }
   }
   
   // Strategy 2: Enter on RSI reversal from extremes
   if(InpEnableStrategy2 && IsWithinTradingHours())
   {
      // Check for RSI-based exits for Strategy 2
      if(InpEnableRSIExit2)
      {
         CheckRSIExits(InpMagicNumber2, true, InpRSIExitBuy2, InpRSIExitSell2);
      }
      
      // Sell signal: RSI was overbought and now is moving down
      if(wasOverbought && lastRSI[0] < lastRSI[1] && !PositionSelectByTicket(InpMagicNumber2))
      {
         stopLoss = InpEnableRSIExit2 && !InpUseSLTPWithRSI2 ? 0 : currentPrice + InpStopLoss2 * _Point;
         takeProfit = InpEnableRSIExit2 && !InpUseSLTPWithRSI2 ? 0 : currentPrice - InpTakeProfit2 * _Point;
         
         trade.SetExpertMagicNumber(InpMagicNumber2);
         trade.Sell(InpLotSize2, _Symbol, 0, stopLoss, takeProfit, "RSI Reversal Sell");
      }
      
      // Buy signal: RSI was oversold and now is moving up
      if(wasOversold && lastRSI[0] > lastRSI[1] && !PositionSelectByTicket(InpMagicNumber2))
      {
         stopLoss = InpEnableRSIExit2 && !InpUseSLTPWithRSI2 ? 0 : currentPrice - InpStopLoss2 * _Point;
         takeProfit = InpEnableRSIExit2 && !InpUseSLTPWithRSI2 ? 0 : currentPrice + InpTakeProfit2 * _Point;
         
         trade.SetExpertMagicNumber(InpMagicNumber2);
         trade.Buy(InpLotSize2, _Symbol, 0, stopLoss, takeProfit, "RSI Reversal Buy");
      }
   }
   
   // Check trailing stops and time-based exits
   if(InpEnableStrategy1)
   {
      CheckTrailingStop(InpMagicNumber1, InpTrailingStop1, InpTrailingStep1);
      CheckTimeBasedExits(InpMagicNumber1, InpMaxTradeDuration1, InpLossThreshold1);
   }
   
   if(InpEnableStrategy2)
   {
      CheckTrailingStop(InpMagicNumber2, InpTrailingStop2, InpTrailingStep2);
      CheckTimeBasedExits(InpMagicNumber2, InpMaxTradeDuration2, InpLossThreshold2);
   }
}
