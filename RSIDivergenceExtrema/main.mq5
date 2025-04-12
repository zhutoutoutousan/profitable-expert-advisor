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
input int      RSI_Overbought = 70;       // RSI Overbought Level
input int      RSI_Oversold = 30;         // RSI Oversold Level
input double   BaseLotSize = 0.01;        // Base Lot Size
input ENUM_TIMEFRAMES BarTimeFrame = PERIOD_H1;  // Timeframe for bar updates
input double   ExitBuyRSIThreshold = 60;  // RSI level to exit buy positions
input double   ExitSellRSIThreshold = 40; // RSI level to exit sell positions

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
   trade.SetExpertMagicNumber(123456);
   
   Print("RSI Divergence Rebound Strategy Initialized");
   Print("RSI Period: ", RSI_Period);
   Print("Overbought Level: ", RSI_Overbought);
   Print("Oversold Level: ", RSI_Oversold);
   
   // Clean up any existing extrema objects
   CleanupExtremaObjects();
   
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
      // First extrema (must be overbought/oversold)
      if(!hasFirstExtrema)
      {
         if((isMaxima && RSILastTwo >= RSI_Overbought) || (!isMaxima && RSILastTwo <= RSI_Oversold))
         {
            hasFirstExtrema = true;
            isOverboughtExtrema = isMaxima;
            priceFirstExtrema = iClose(_Symbol, BarTimeFrame, 1);
            rsiFirstExtrema = RSILastTwo;
            firstExtremaTime = iTime(_Symbol, BarTimeFrame, 1);
            
            // Draw first extrema
            string firstExtremaName = extremaPrefix + "First_" + TimeToString(firstExtremaTime);
            DrawExtremaPoint(firstExtremaName, firstExtremaTime, priceFirstExtrema, 
                           isMaxima ? clrRed : clrGreen, 234, "1st " + (isMaxima ? "OB" : "OS"));
            
            Print("First extrema detected - Type: ", isMaxima ? "Overbought" : "Oversold",
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
            }
            else
            {
               if(!trade.Buy(BaseLotSize, _Symbol, 0, 0, 0, "RSI Divergence Buy"))
               {
                  Print("Failed to execute buy order - resetting extrema");
                  ResetExtrema();
               }
            }
         }
      }
   }
   
   // Check for exit conditions
   if(PositionSelect(_Symbol))
   {
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY && RSILast >= ExitBuyRSIThreshold)
      {
         trade.PositionClose(_Symbol);
         ResetExtrema();
      }
      else if(posType == POSITION_TYPE_SELL && RSILast <= ExitSellRSIThreshold)
      {
         trade.PositionClose(_Symbol);
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
}
//+------------------------------------------------------------------+
