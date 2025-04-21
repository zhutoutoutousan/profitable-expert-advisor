//+------------------------------------------------------------------+
//|                                         RSIDivergenceRebound.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>                // Include CTrade class

// Input Parameters
input int      RSI_Period = 14;           // RSI Period
input int      RSI_Overbought = 71;       // RSI Overbought Level
input int      RSI_Oversold = 33;         // RSI Oversold Level
input double   BaseLotSize = 0.01;        // Base Lot Size
input ENUM_TIMEFRAMES BarTimeFrame = PERIOD_H6;  // Timeframe for bar updates
input double   ExitBuyRSIThreshold = 60;  // RSI level to exit buy positions
input double   ExitSellRSIThreshold = 40; // RSI level to exit sell positions
input int      ExtremaExpiryBars = 45;    // Number of bars before extrema expire
input int      StuckTradeBars = 6;        // Number of bars before considering trade stuck
input double   HedgeLotMultiplier = 6.0;  // Multiplier for hedge position lot size

// Global Variables
int rsiHandle;                            // RSI indicator handle
CTrade trade;                             // Trade object
datetime lastBarTime = 0;                 // Last bar time
double RSILastThree = 0;                  // Third last RSI value
double RSILastTwo = 0;                    // Second last RSI value
double RSILast = 0;                       // Last RSI value
bool hasFirstExtrema = false;             // Flag for first extrema
bool hasSecondExtrema = false;            // Flag for second extrema
bool hasThirdExtrema = false;             // Flag for third extrema
bool isOverboughtExtrema = false;         // Flag for extrema type
double priceFirstExtrema = 0;             // Price at first extrema
double rsiFirstExtrema = 0;               // RSI at first extrema
double priceSecondExtrema = 0;            // Price at second extrema
double rsiSecondExtrema = 0;              // RSI at second extrema
double priceThirdExtrema = 0;             // Price at third extrema
double rsiThirdExtrema = 0;               // RSI at third extrema
string extremaPrefix = "Ext_";            // Prefix for extrema objects
datetime firstExtremaTime = 0;            // Time of first extrema
datetime secondExtremaTime = 0;           // Time of second extrema
datetime thirdExtremaTime = 0;            // Time of third extrema
datetime extremaStartTime = 0;            // Time when first extrema was detected
datetime positionOpenTime = 0;            // Time when position was opened
bool isHedged = false;                    // Flag for hedge position

//+------------------------------------------------------------------+
//| Draw extrema point                                               |
//+------------------------------------------------------------------+
void DrawExtremaPoint(string name, datetime time, double price, color clr, int shape, string label)
{
   // Create the point
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, shape);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   
   // Add label
   string labelName = name + "_Label";
   ObjectCreate(0, labelName, OBJ_TEXT, 0, time, price);
   ObjectSetString(0, labelName, OBJPROP_TEXT, label);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, labelName, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Clean up extrema objects                                         |
//+------------------------------------------------------------------+
void CleanupExtremaObjects()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, extremaPrefix) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trade is stuck                                          |
//+------------------------------------------------------------------+
bool IsTradeStuck()
{
   if(!PositionSelect(_Symbol))
   {
      Print("No position selected - cannot check if trade is stuck");
      return false;
   }
   
   if(positionOpenTime == 0)
   {
      Print("Position open time not set - cannot check if trade is stuck");
      return false;
   }
   
   datetime currentTime = iTime(_Symbol, BarTimeFrame, 0);
   int barsPassed = (int)((currentTime - positionOpenTime) / PeriodSeconds(BarTimeFrame));
   
   Print("Trade Stuck Check - Current Time: ", TimeToString(currentTime),
         ", Position Open Time: ", TimeToString(positionOpenTime),
         ", Bars Passed: ", barsPassed,
         ", Stuck Trade Bars: ", StuckTradeBars);
   
   return barsPassed >= StuckTradeBars;
}

//+------------------------------------------------------------------+
//| Place hedge trade                                                |
//+------------------------------------------------------------------+
void PlaceHedgeTrade()
{
   if(isHedged)
   {
      Print("Hedge position already exists - skipping");
      return;
   }
   
   if(!PositionSelect(_Symbol))
   {
      Print("No position selected - cannot place hedge");
      return;
   }
      
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentLot = PositionGetDouble(POSITION_VOLUME);
   double hedgeLot = currentLot * HedgeLotMultiplier;
   
   Print("Placing hedge trade - Current Position: ", EnumToString(posType),
         ", Current Lot: ", currentLot,
         ", Hedge Lot: ", hedgeLot);
   
   // Set different magic number for hedge positions
   trade.SetExpertMagicNumber(654321);
   
   if(posType == POSITION_TYPE_BUY)
   {
      if(trade.Sell(hedgeLot, _Symbol, 0, 0, 0, "RSI Hedge Sell"))
      {
         isHedged = true;
         Print("Hedge sell position opened with lot size: ", hedgeLot);
      }
      else
      {
         Print("Failed to open hedge sell position");
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(trade.Buy(hedgeLot, _Symbol, 0, 0, 0, "RSI Hedge Buy"))
      {
         isHedged = true;
         Print("Hedge buy position opened with lot size: ", hedgeLot);
      }
      else
      {
         Print("Failed to open hedge buy position");
      }
   }
   
   // Reset magic number back to original
   trade.SetExpertMagicNumber(123456);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   Print("Starting to close all positions");
   
   // Close all positions for the symbol
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         Print("Failed to get position ticket for index ", i);
         continue;
      }
      
      if(!PositionSelectByTicket(ticket))
      {
         Print("Failed to select position with ticket ", ticket);
         continue;
      }
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      {
         Print("Position ", ticket, " is not for symbol ", _Symbol);
         continue;
      }
      
      Print("Closing position - Ticket: ", ticket,
            ", Magic: ", PositionGetInteger(POSITION_MAGIC),
            ", Type: ", EnumToString((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)));
      
      if(!trade.PositionClose(ticket))
      {
         Print("Failed to close position with ticket ", ticket);
      }
      else
      {
         Print("Successfully closed position with ticket ", ticket);
      }
   }
   
   isHedged = false;
   positionOpenTime = 0;
   Print("All positions closed");
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize RSI indicator
   rsiHandle = iRSI(_Symbol, BarTimeFrame, RSI_Period, PRICE_CLOSE);
   
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(123457);
   
   Print("RSI Divergence Rebound Strategy Initialized");
   Print("RSI Period: ", RSI_Period);
   Print("Overbought Level: ", RSI_Overbought);
   Print("Oversold Level: ", RSI_Oversold);
   
   // Clean up any existing extrema objects
   CleanupExtremaObjects();
   
   positionOpenTime = 0;
   isHedged = false;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up extrema objects
   CleanupExtremaObjects();
   
   IndicatorRelease(rsiHandle);
   
   CloseAllPositions();
}

//+------------------------------------------------------------------+
//| Check for local extrema in RSI                                   |
//+------------------------------------------------------------------+
bool IsLocalExtrema(double rsi1, double rsi2, double rsi3, bool& isMaxima)
{
   if(rsi2 > rsi1 && rsi2 > rsi3)
   {
      isMaxima = true;
      return true;
   }
   else if(rsi2 < rsi1 && rsi2 < rsi3)
   {
      isMaxima = false;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for divergence patterns                                    |
//+------------------------------------------------------------------+
bool CheckDivergence(double price1, double rsi1, double price2, double rsi2, bool isOverbought)
{
   if(isOverbought)
   {
      // Bearish divergence (price makes higher high, RSI makes lower high)
      if(price2 > price1 && rsi2 < rsi1)
         return true;
      // Hidden bearish divergence (price makes lower high, RSI makes higher high)
      if(price2 < price1 && rsi2 > rsi1)
         return true;
   }
   else
   {
      // Bullish divergence (price makes lower low, RSI makes higher low)
      if(price2 < price1 && rsi2 > rsi1)
         return true;
      // Hidden bullish divergence (price makes higher low, RSI makes lower low)
      if(price2 > price1 && rsi2 < rsi1)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if market is open                                          |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Check if it's a weekend
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;
      
   // Check if it's within trading hours (assuming 24/5 market)
   // You can modify these hours based on your broker's trading hours
   int hour = dt.hour;
   int minute = dt.min;
   
   // Market is open 24/5 except weekends
   return true;
}

//+------------------------------------------------------------------+
//| Check if extrema has expired                                     |
//+------------------------------------------------------------------+
bool HasExtremaExpired()
{
   if(extremaStartTime == 0)
      return false;
      
   datetime currentTime = iTime(_Symbol, BarTimeFrame, 0);
   int barsPassed = (int)((currentTime - extremaStartTime) / PeriodSeconds(BarTimeFrame));
   
   return barsPassed >= ExtremaExpiryBars;
}

//+------------------------------------------------------------------+
//| Check if loss is resolved after hedging                          |
//+------------------------------------------------------------------+
bool IsLossResolved()
{
   if(!isHedged)
   {
      Print("Loss Resolution Check - No hedge position exists");
      return false;
   }
      
   double originalProfit = 0;
   double hedgeProfit = 0;
   bool foundOriginal = false;
   bool foundHedge = false;
   
   Print("Loss Resolution Check - Starting position scan");
   
   // Calculate total profit from all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         Print("Loss Resolution Check - Failed to get position ticket for index ", i);
         continue;
      }
      
      if(!PositionSelectByTicket(ticket))
      {
         Print("Loss Resolution Check - Failed to select position with ticket ", ticket);
         continue;
      }
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      {
         Print("Loss Resolution Check - Position ", ticket, " is not for symbol ", _Symbol);
         continue;
      }
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      
      Print("Loss Resolution Check - Position ", ticket, 
            ", Magic: ", magic,
            ", Profit: ", profit);
      
      if(magic == 123456) // Original position
      {
         originalProfit = profit;
         foundOriginal = true;
         Print("Loss Resolution Check - Found original position with profit: ", profit);
      }
      else if(magic == 654321) // Hedge position
      {
         hedgeProfit = profit;
         foundHedge = true;
         Print("Loss Resolution Check - Found hedge position with profit: ", profit);
      }
   }
   
   if(!foundOriginal)
      Print("Loss Resolution Check - Warning: Original position not found");
   if(!foundHedge)
      Print("Loss Resolution Check - Warning: Hedge position not found");
   
   double totalProfit = originalProfit + hedgeProfit;
   Print("Loss Resolution Check - Final Calculation -",
         "\nOriginal Profit: ", originalProfit,
         "\nHedge Profit: ", hedgeProfit,
         "\nTotal Profit: ", totalProfit,
         "\nIs Resolved: ", totalProfit >= 0);
         
   return totalProfit >= 0;
}

//+------------------------------------------------------------------+
//| Check if main trade is in loss                                   |
//+------------------------------------------------------------------+
bool IsMainTradeInLoss()
{
   if(!PositionSelect(_Symbol))
   {
      Print("No position selected - cannot check for loss");
      return false;
   }
   
   if(PositionGetInteger(POSITION_MAGIC) != 123456)
   {
      Print("Not a main trade position - cannot check for loss");
      return false;
   }
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   Print("Main Trade Profit Check - Profit: ", profit);
   
   return profit < 0;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if market is open
   if(!IsMarketOpen())
   {
      Print("Market is closed - resetting extrema");
      ResetExtrema();
      return;
   }
   
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, BarTimeFrame, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   // Get current RSI value
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) != 1)
   {
      Print("Error copying RSI buffer");
      return;
   }
   
   // Update RSI queue
   RSILastThree = RSILastTwo;
   RSILastTwo = RSILast;
   RSILast = rsiBuffer[0];
   
   // Check if we have enough RSI values
   if(RSILastThree == 0 || RSILastTwo == 0)
      return;
   
   // Check for local extrema
   bool isMaxima;
   if(IsLocalExtrema(RSILastThree, RSILastTwo, RSILast, isMaxima))
   {
      
      if(!hasFirstExtrema)
      {
         // For overbought condition, we need a maxima
         if(isMaxima && RSILastTwo >= RSI_Overbought)
         {
            hasFirstExtrema = true;
            isOverboughtExtrema = true;
            priceFirstExtrema = iClose(_Symbol, BarTimeFrame, 1);
            rsiFirstExtrema = RSILastTwo;
            firstExtremaTime = iTime(_Symbol, BarTimeFrame, 1);
            extremaStartTime = firstExtremaTime;
            
            // Draw first extrema
            string firstExtremaName = extremaPrefix + "First_" + TimeToString(firstExtremaTime);
            DrawExtremaPoint(firstExtremaName, firstExtremaTime, priceFirstExtrema, 
                           clrRed, 234, "1st OB");
            
            Print("First extrema detected - Type: Overbought",
                  ", RSI: ", rsiFirstExtrema, ", Price: ", priceFirstExtrema);
         }
         // For oversold condition, we need a minima
         else if(!isMaxima && RSILastTwo <= RSI_Oversold)
         {
            hasFirstExtrema = true;
            isOverboughtExtrema = false;
            priceFirstExtrema = iClose(_Symbol, BarTimeFrame, 1);
            rsiFirstExtrema = RSILastTwo;
            firstExtremaTime = iTime(_Symbol, BarTimeFrame, 1);
            extremaStartTime = firstExtremaTime;
            
            // Draw first extrema
            string firstExtremaName = extremaPrefix + "First_" + TimeToString(firstExtremaTime);
            DrawExtremaPoint(firstExtremaName, firstExtremaTime, priceFirstExtrema, 
                           clrGreen, 234, "1st OS");
            
            Print("First extrema detected - Type: Oversold",
                  ", RSI: ", rsiFirstExtrema, ", Price: ", priceFirstExtrema);
         }
      }
      // Second extrema (check for divergence)
      else if(!hasSecondExtrema)
      {
         priceSecondExtrema = iClose(_Symbol, BarTimeFrame, 1);
         rsiSecondExtrema = RSILastTwo;
         secondExtremaTime = iTime(_Symbol, BarTimeFrame, 1);
         
         if(CheckDivergence(priceFirstExtrema, rsiFirstExtrema, priceSecondExtrema, rsiSecondExtrema, isOverboughtExtrema))
         {
            hasSecondExtrema = true;
            
            // Draw second extrema
            string secondExtremaName = extremaPrefix + "Second_" + TimeToString(secondExtremaTime);
            DrawExtremaPoint(secondExtremaName, secondExtremaTime, priceSecondExtrema, 
                           clrBlue, 233, "2nd Div");
            
            Print("Second extrema detected - Divergence found",
                  ", RSI: ", rsiSecondExtrema, ", Price: ", priceSecondExtrema);
         }
      }
      // Third extrema (must be between overbought/oversold levels)
      else if(!hasThirdExtrema)
      {
         if(RSILastTwo > RSI_Oversold && RSILastTwo < RSI_Overbought)
         {
            hasThirdExtrema = true;
            priceThirdExtrema = iClose(_Symbol, BarTimeFrame, 1);
            rsiThirdExtrema = RSILastTwo;
            thirdExtremaTime = iTime(_Symbol, BarTimeFrame, 1);
            
            // Draw third extrema
            string thirdExtremaName = extremaPrefix + "Third_" + TimeToString(thirdExtremaTime);
            DrawExtremaPoint(thirdExtremaName, thirdExtremaTime, priceThirdExtrema, 
                           clrMagenta, 232, "3rd Entry");
            
            Print("Third extrema detected - Trade signal",
                  ", RSI: ", rsiThirdExtrema, ", Price: ", priceThirdExtrema);
            
            // Enter trade
            if(isOverboughtExtrema)
            {
               if(!trade.Sell(BaseLotSize, _Symbol, 0, 0, 0, "RSI Divergence Sell"))
               {
                  Print("Failed to execute sell order - resetting extrema");
                  ResetExtrema();
               }
               else
               {
                  positionOpenTime = iTime(_Symbol, BarTimeFrame, 0);
                  Print("Sell position opened at: ", TimeToString(positionOpenTime));
               }
            }
            else
            {
               if(!trade.Buy(BaseLotSize, _Symbol, 0, 0, 0, "RSI Divergence Buy"))
               {
                  Print("Failed to execute buy order - resetting extrema");
                  ResetExtrema();
               }
               else
               {
                  positionOpenTime = iTime(_Symbol, BarTimeFrame, 0);
                  Print("Buy position opened at: ", TimeToString(positionOpenTime));
               }
            }
         }
      }
   }
   
   // Check for exit conditions and hedge
   if(PositionSelect(_Symbol))
   {
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Check if trade is stuck and in loss
      if(IsTradeStuck() && IsMainTradeInLoss())
      {
         Print("Trade is stuck and in loss - placing hedge");
         PlaceHedgeTrade();
      }
      
      // Check if loss is resolved after hedging
      if(isHedged && IsLossResolved())
      {
         Print("Loss resolved - closing all positions");
         CloseAllPositions();
         ResetExtrema();
         return;
      }
      
      // Check RSI exit conditions
      if(posType == POSITION_TYPE_BUY && RSILast >= ExitBuyRSIThreshold)
      {
         CloseAllPositions();
         ResetExtrema();
      }
      else if(posType == POSITION_TYPE_SELL && RSILast <= ExitSellRSIThreshold)
      {
         CloseAllPositions();
         ResetExtrema();
      }
   }
}

//+------------------------------------------------------------------+
//| Reset extrema flags and values                                   |
//+------------------------------------------------------------------+
void ResetExtrema()
{
   // Clean up existing objects
   CleanupExtremaObjects();
   
   hasFirstExtrema = false;
   hasSecondExtrema = false;
   hasThirdExtrema = false;
   isOverboughtExtrema = false;
   priceFirstExtrema = 0;
   rsiFirstExtrema = 0;
   priceSecondExtrema = 0;
   rsiSecondExtrema = 0;
   priceThirdExtrema = 0;
   rsiThirdExtrema = 0;
   firstExtremaTime = 0;
   secondExtremaTime = 0;
   thirdExtremaTime = 0;
   extremaStartTime = 0;
   positionOpenTime = 0;
   isHedged = false;
}
//+------------------------------------------------------------------+
