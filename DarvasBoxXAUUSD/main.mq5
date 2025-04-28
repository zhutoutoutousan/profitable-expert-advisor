//+------------------------------------------------------------------+
//|                                                    DarvasBox.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Indicators\Trend.mqh>
#include <Indicators\Volumes.mqh>

// Input parameters
input int    BoxPeriod = 165;        // Period for Darvas Box calculation
input double BoxDeviation = 25140;    // Box deviation in points
input int    VolumeThreshold = 938; // Minimum volume for confirmation
input double StopLoss = 1665;        // Stop loss in points (increased for BTCUSD)
input double TakeProfit = 3685;      // Take profit in points (increased for BTCUSD)
input bool   EnableLogging = false;  // Enable detailed logging
input color  BoxColor = clrBlue;    // Color for Darvas Box
input int    BoxWidth = 1;          // Width of box lines

// Trend confirmation parameters
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H2;  // Timeframe for trend analysis
input int    MA_Period = 125;        // Moving Average period for trend
input ENUM_MA_METHOD MA_Method = MODE_EMA;  // Moving Average method
input ENUM_APPLIED_PRICE MA_Price = PRICE_WEIGHTED;  // Price type for MA
input double TrendThreshold = 4.94;   // Trend strength threshold

// Volume analysis parameters
input int    VolumeMA_Period = 110;   // Period for Volume MA
input double VolumeThresholdMultiplier = 1.5;  // Volume spike threshold

// Global variables
double boxHigh = 0;
double boxLow = 0;
bool boxFormed = false;
datetime lastBoxTime = 0;
string boxName = "DarvasBox_";
double minStopLevel = 0;
double point = 0;
CTrade trade;
ulong magicNumber = 135790;

// Indicator handles
int maHandle;
int volumeHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators and variables
   boxHigh = 0;
   boxLow = 0;
   boxFormed = false;
   lastBoxTime = 0;
   
   // Get symbol properties
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   
   // Initialize indicators
   maHandle = iMA(_Symbol, TrendTimeframe, MA_Period, 0, MA_Method, MA_Price);
   volumeHandle = iVolumes(_Symbol, PERIOD_CURRENT, VOLUME_TICK);
   
   if(maHandle == INVALID_HANDLE || volumeHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   // Configure trade object
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);
   trade.SetExpertMagicNumber(magicNumber);
   
   if(EnableLogging)
   {
      Print("Darvas Box Expert Advisor initialized");
      Print("Symbol: ", _Symbol);
      Print("Point: ", point);
      Print("Minimum Stop Level: ", minStopLevel);
   }
   
   // Delete any existing box objects
   ObjectsDeleteAll(0, boxName);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Draw Darvas Box on chart                                         |
//+------------------------------------------------------------------+
void DrawDarvasBox()
{
   if(!boxFormed) return;
   
   datetime time1 = iTime(_Symbol, PERIOD_H1, BoxPeriod);
   datetime time2 = iTime(_Symbol, PERIOD_H1, 0);
   
   // Delete old box
   ObjectsDeleteAll(0, boxName);
   
   // Draw box
   ObjectCreate(0, boxName + "Top", OBJ_TREND, 0, time1, boxHigh, time2, boxHigh);
   ObjectCreate(0, boxName + "Bottom", OBJ_TREND, 0, time1, boxLow, time2, boxLow);
   
   // Set box properties
   ObjectSetInteger(0, boxName + "Top", OBJPROP_COLOR, BoxColor);
   ObjectSetInteger(0, boxName + "Bottom", OBJPROP_COLOR, BoxColor);
   ObjectSetInteger(0, boxName + "Top", OBJPROP_WIDTH, BoxWidth);
   ObjectSetInteger(0, boxName + "Bottom", OBJPROP_WIDTH, BoxWidth);
   ObjectSetInteger(0, boxName + "Top", OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, boxName + "Bottom", OBJPROP_RAY_RIGHT, true);
}

//+------------------------------------------------------------------+
//| Calculate Darvas Box levels                                      |
//+------------------------------------------------------------------+
void CalculateDarvasBox()
{
   double high = 0;
   double low = DBL_MAX;
   
   // Find highest high and lowest low in the period
   for(int i = 0; i < BoxPeriod; i++)
   {
      high = MathMax(high, iHigh(_Symbol, PERIOD_H1, i));
      low = MathMin(low, iLow(_Symbol, PERIOD_H1, i));
   }
   
   double range = high - low;
   double allowedRange = BoxDeviation * _Point;
   
   if(EnableLogging)
   {
      Print("Box Calculation - High: ", high, " Low: ", low, " Range: ", range, " Allowed Range: ", allowedRange);
   }
   
   // Check if box is formed
   if(range <= allowedRange)
   {
      boxHigh = high;
      boxLow = low;
      boxFormed = true;
      lastBoxTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      // Draw the box
      DrawDarvasBox();
      
      if(EnableLogging)
         Print("Box Formed - High: ", boxHigh, " Low: ", boxLow, " Time: ", lastBoxTime);
   }
   else
   {
      boxFormed = false;
      // Delete box if it exists
      ObjectsDeleteAll(0, boxName);
   }
}

//+------------------------------------------------------------------+
//| Validate and adjust stop levels                                  |
//+------------------------------------------------------------------+
bool ValidateStopLevels(double price, double &sl, double &tp, ENUM_ORDER_TYPE orderType)
{
   double minSlDistance = MathMax(minStopLevel, StopLoss * point);
   double minTpDistance = MathMax(minStopLevel, TakeProfit * point);
   
   if(EnableLogging)
   {
      Print("Minimum SL Distance: ", minSlDistance);
      Print("Minimum TP Distance: ", minTpDistance);
   }
   
   // Adjust stop loss
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - minSlDistance;
      tp = price + minTpDistance;
      
      if(EnableLogging)
      {
         Print("Buy Order Levels:");
         Print("Entry: ", price);
         Print("Stop Loss: ", sl);
         Print("Take Profit: ", tp);
      }
   }
   else // ORDER_TYPE_SELL
   {
      sl = price + minSlDistance;
      tp = price - minTpDistance;
      
      if(EnableLogging)
      {
         Print("Sell Order Levels:");
         Print("Entry: ", price);
         Print("Stop Loss: ", sl);
         Print("Take Profit: ", tp);
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trend direction and strength                               |
//+------------------------------------------------------------------+
bool IsTrendFavorable(ENUM_ORDER_TYPE orderType)
{
   double ma[];
   ArraySetAsSeries(ma, true);
   
   if(CopyBuffer(maHandle, 0, 0, 2, ma) <= 0)
      return false;
      
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trendStrength = MathAbs(currentPrice - ma[0]) / point;
   
   if(EnableLogging)
      Print("Trend Strength: ", trendStrength);
   
   if(orderType == ORDER_TYPE_BUY)
      return (currentPrice > ma[0] && trendStrength > TrendThreshold);
   else
      return (currentPrice < ma[0] && trendStrength > TrendThreshold);
}

//+------------------------------------------------------------------+
//| Check volume conditions                                          |
//+------------------------------------------------------------------+
bool CheckVolumeConditions()
{
   double volumes[];
   ArraySetAsSeries(volumes, true);
   
   if(CopyBuffer(volumeHandle, 0, 0, VolumeMA_Period + 1, volumes) <= 0)
      return false;
      
   double volumeMA = 0;
   for(int i = 1; i <= VolumeMA_Period; i++)
      volumeMA += volumes[i];
   volumeMA /= VolumeMA_Period;
   
   double currentVolume = volumes[0];
   double volumeRatio = currentVolume / volumeMA;
   
   if(EnableLogging)
      Print("Volume Ratio: ", volumeRatio);
   
   return (volumeRatio > VolumeThresholdMultiplier);
}

//+------------------------------------------------------------------+
//| Place trade order                                                |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp)
{
   // Validate and adjust stop levels
   if(!ValidateStopLevels(price, sl, tp, orderType))
   {
      if(EnableLogging)
         Print("Invalid stop levels after adjustment");
      return false;
   }
   
   // Check trend and volume conditions
   if(!IsTrendFavorable(orderType))
   {
      if(EnableLogging)
         Print("Trend not favorable for trade");
      return false;
   }
   
   if(!CheckVolumeConditions())
   {
      if(EnableLogging)
         Print("Volume conditions not met");
      return false;
   }
   
   if(EnableLogging)
   {
      Print("Order Details:");
      Print("Type: ", EnumToString(orderType));
      Print("Price: ", price);
      Print("Stop Loss: ", sl);
      Print("Take Profit: ", tp);
   }
   
   bool result = false;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      result = trade.Buy(0.01, _Symbol, price, sl, tp, "Darvas Box Breakout");
   }
   else
   {
      result = trade.Sell(0.01, _Symbol, price, sl, tp, "Darvas Box Breakdown");
   }
   
   if(EnableLogging)
   {
      if(result)
         Print((orderType == ORDER_TYPE_BUY ? "Buy" : "Sell"), " Order Placed Successfully");
      else
         Print((orderType == ORDER_TYPE_BUY ? "Buy" : "Sell"), " Order Failed - Error: ", trade.ResultRetcode(), " Description: ", trade.ResultRetcodeDescription());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Calculate new box levels
   CalculateDarvasBox();
   
   // Check for trading signals
   if(boxFormed)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentVolume = iVolume(_Symbol, PERIOD_CURRENT, 0);
      
      if(EnableLogging)
      {
         Print("Current Price: ", currentPrice, " Box High: ", boxHigh, " Box Low: ", boxLow);
         Print("Current Volume: ", currentVolume, " Volume Threshold: ", VolumeThreshold);
      }
      
      // Check for breakout above box
      if(currentPrice > boxHigh && currentVolume > VolumeThreshold)
      {
         if(EnableLogging)
            Print("Breakout Signal Detected - Price above box high");
            
         // Buy signal
         if(PositionsTotal() == 0) // No existing positions
         {
            double sl = currentPrice - StopLoss * _Point;
            double tp = currentPrice + TakeProfit * _Point;
            
            if(EnableLogging)
               Print("Preparing Buy Order - Price: ", currentPrice, " SL: ", sl, " TP: ", tp);
            
            PlaceOrder(ORDER_TYPE_BUY, currentPrice, sl, tp);
         }
         else if(EnableLogging)
            Print("Skipping Buy Signal - Position already exists");
      }
      
      // Check for breakdown below box
      if(currentPrice < boxLow && currentVolume > VolumeThreshold)
      {
         if(EnableLogging)
            Print("Breakdown Signal Detected - Price below box low");
            
         // Sell signal
         if(PositionsTotal() == 0) // No existing positions
         {
            double sl = currentPrice + StopLoss * _Point;
            double tp = currentPrice - TakeProfit * _Point;
            
            if(EnableLogging)
               Print("Preparing Sell Order - Price: ", currentPrice, " SL: ", sl, " TP: ", tp);
            
            PlaceOrder(ORDER_TYPE_SELL, currentPrice, sl, tp);
         }
         else if(EnableLogging)
            Print("Skipping Sell Signal - Position already exists");
      }
   }
   else if(EnableLogging)
      Print("No Box Formed - Waiting for consolidation");
}

//+------------------------------------------------------------------+
//| Get last error description                                       |
//+------------------------------------------------------------------+
string GetLastErrorDescription()
{
   string errorDescription;
   switch(GetLastError())
   {
      case 0: errorDescription = "No error"; break;
      case 1: errorDescription = "No error, but result unknown"; break;
      case 2: errorDescription = "Common error"; break;
      case 3: errorDescription = "Invalid trade parameters"; break;
      case 4: errorDescription = "Trade server is busy"; break;
      case 5: errorDescription = "Old version of the client terminal"; break;
      case 6: errorDescription = "No connection with trade server"; break;
      case 7: errorDescription = "Not enough rights"; break;
      case 8: errorDescription = "Too frequent requests"; break;
      case 9: errorDescription = "Malfunctional trade operation"; break;
      case 64: errorDescription = "Account disabled"; break;
      case 65: errorDescription = "Invalid account"; break;
      case 128: errorDescription = "Trade timeout"; break;
      case 129: errorDescription = "Invalid price"; break;
      case 130: errorDescription = "Invalid stops"; break;
      case 131: errorDescription = "Invalid trade volume"; break;
      case 132: errorDescription = "Market is closed"; break;
      case 133: errorDescription = "Trade is disabled"; break;
      case 134: errorDescription = "Not enough money"; break;
      case 135: errorDescription = "Price changed"; break;
      case 136: errorDescription = "Off quotes"; break;
      case 137: errorDescription = "Broker is busy"; break;
      case 138: errorDescription = "Requote"; break;
      case 139: errorDescription = "Order is locked"; break;
      case 140: errorDescription = "Long positions only allowed"; break;
      case 141: errorDescription = "Too many requests"; break;
      case 145: errorDescription = "Modification denied because order is too close to market"; break;
      case 146: errorDescription = "Trade context is busy"; break;
      case 147: errorDescription = "Expirations are denied by broker"; break;
      case 148: errorDescription = "Amount of open and pending orders has reached the limit"; break;
      case 149: errorDescription = "Hedging is prohibited"; break;
      case 150: errorDescription = "Prohibited by FIFO rules"; break;
      default: errorDescription = "Unknown error"; break;
   }
   return errorDescription;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete all box objects
   ObjectsDeleteAll(0, boxName);
   
   if(EnableLogging)
      Print("Expert Advisor deinitialized - Reason: ", reason);
}
