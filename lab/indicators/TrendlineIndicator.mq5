//+------------------------------------------------------------------+
//|                                           TrendlineIndicator.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property description "Automatically draws trendlines connecting swing highs and lows"
#property description "Adjustable parameters for swing detection and line appearance"
#property description "Can execute actual trades when enabled"
#property description "NOTE: For Strategy Tester, use as Expert Advisor (EA) instead"

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Swing Point Detection ==="
input int    InpSwingPeriod = 5;              // Swing Period (bars to look back/forward)
input int    InpMinBarsBetween = 10;          // Minimum Bars Between Swing Points
input int    InpMaxSwingPoints = 20;          // Maximum Swing Points to Track
input int    InpLookbackBars = 500;           // Lookback Bars (0 = all available)

input group "=== Trendline Appearance ==="
input color  InpResistanceColor = clrRed;     // Resistance Line Color
input color  InpSupportColor = clrBlue;        // Support Line Color
input int    InpLineWidth = 1;                 // Line Width
input ENUM_LINE_STYLE InpLineStyle = STYLE_SOLID; // Line Style
input bool   InpExtendLines = true;            // Extend Lines to Right Edge
input int    InpExtensionBars = 50;            // Extension Bars (if ExtendLines = false)

input group "=== Display Options ==="
input bool   InpShowSupportLines = true;      // Show Support Lines
input bool   InpShowResistanceLines = true;   // Show Resistance Lines
input bool   InpShowRay = false;               // Show Ray (infinite extension)
input bool   InpShowLabels = false;            // Show Price Labels

input group "=== Trading Strategy ==="
input bool   InpEnableTrading = true;         // Enable Trading Signals
input bool   InpExecuteRealTrades = false;   // Execute Real Trades (WARNING: Uses Real Money!)
input double InpLotSize = 0.01;              // Lot Size for Real Trades
input int    InpMagicNumber = 123456;       // Magic Number for Trades
input int    InpSlippage = 10;               // Slippage in Points
input double InpMinRiskRewardRatio = 2.0;     // Minimum Risk/Reward Ratio Required
input double InpMaxRiskRewardRatio = 10.0;   // Maximum Risk/Reward Ratio (sanity check)
input bool   InpIgnoreRRRejection = false;    // Ignore R/R Ratio Rejection (Accept All Signals)
input bool   InpUseNearestLevels = true;     // Use Nearest Support/Resistance for SL/TP
input double InpLevelTolerancePips = 5.0;    // Tolerance for finding levels (pips)
input bool   InpShowTradeLevels = true;       // Show Entry/SL/TP on Chart
input color  InpBuyColor = clrLime;           // Buy Signal Color
input color  InpSellColor = clrOrange;        // Sell Signal Color

input group "=== Debug & Feedback ==="
input bool   InpShowDebugInfo = true;         // Show Debug Information
input bool   InpShowDetailedStats = false;   // Show Detailed Statistics

//--- Global Variables
struct SwingPoint
{
   datetime time;
   double   price;
   bool     isHigh;
   int      barIndex;
};

SwingPoint swingPoints[];
string      trendlineNames[];
int         trendlineCount = 0;

//--- Trading structures
struct TrendlineInfo
{
   string name;
   double point1Price;
   double point2Price;
   datetime point1Time;
   datetime point2Time;
   bool isResistance;
   double slope;
   double intercept;
};

struct TradeSignal
{
   bool active;
   ENUM_ORDER_TYPE type;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   datetime entryTime;
   string trendlineName;
   string entryObjectName;
   string slObjectName;
   string tpObjectName;
};

TrendlineInfo trendlines[];
TradeSignal currentSignal;
int atrHandle = INVALID_HANDLE;
CTrade trade;                                 // Trade object for real trading
ulong currentTradeTicket = 0;                // Current trade ticket
static int uniqueObjectCounter = 0;          // Unique counter for object names

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set indicator short name
   IndicatorSetString(INDICATOR_SHORTNAME, "Trendline Indicator");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   //--- Initialize arrays
   ArrayResize(swingPoints, 0);
   ArrayResize(trendlineNames, 0);
   
   //--- Initialize trade signal
   currentSignal.active = false;
   currentTradeTicket = 0;
   
   //--- Initialize trade object if real trading is enabled
   if(InpExecuteRealTrades)
   {
      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetDeviationInPoints(InpSlippage);
      trade.SetAsyncMode(false);
      
      //--- Set filling mode based on broker capabilities
      ENUM_ORDER_TYPE_FILLING filling = (ENUM_ORDER_TYPE_FILLING)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if(filling == 0)
         filling = ORDER_FILLING_FOK; // Default if not specified
      trade.SetTypeFilling(filling);
   }
   
   if(InpShowDebugInfo)
   {
      Print("=== TRENDLINE INDICATOR INITIALIZED ===");
      Print("Symbol: ", _Symbol, " | Period: ", EnumToString(_Period));
      Print("Settings: SwingPeriod=", InpSwingPeriod, " MinBars=", InpMinBarsBetween, " MaxPoints=", InpMaxSwingPoints, " Lookback=", InpLookbackBars);
      Print("Colors: Resistance=", ColorToString(InpResistanceColor), " Support=", ColorToString(InpSupportColor));
      Print("Display: Resistance=", InpShowResistanceLines, " Support=", InpShowSupportLines, " Ray=", InpShowRay);
      if(InpEnableTrading)
      {
         Print("Trading: ENABLED | Min R/R=", InpMinRiskRewardRatio, " | Max R/R=", InpMaxRiskRewardRatio, " | Use Nearest Levels=", InpUseNearestLevels);
         Print("Ignore R/R Rejection: ", InpIgnoreRRRejection, " (", (InpIgnoreRRRejection ? "All signals accepted" : "R/R validation active"), ")");
         if(InpExecuteRealTrades)
         {
            Print("*** REAL TRADING ENABLED *** - Trades will be executed with real money!");
            Print("Lot Size: ", InpLotSize, " | Magic: ", InpMagicNumber);
         }
         else
         {
            Print("Real Trading: DISABLED (Simulation only)");
         }
      }
   }
   else
   {
      Print("Trendline Indicator initialized");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete all trendline objects
   DeleteAllTrendlines();
   
   //--- Delete trade signal objects
   DeleteTradeSignalObjects();
   
   Print("Trendline Indicator deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpSwingPeriod * 2 + 1)
      return(0);
   
   //--- Always recalculate to update trendlines as new data comes in
   //--- Only skip if we're on the exact same bar (same rates_total and same last bar time)
   static int lastRatesTotal = 0;
   static datetime lastBarTime = 0;
   
   if(prev_calculated > 0)
   {
      datetime currentBarTime = time[rates_total - 1];
      // Only skip if it's the exact same calculation (same bar count and same time)
      if(rates_total == lastRatesTotal && currentBarTime == lastBarTime)
      {
         return(rates_total); // Same bar, skip recalculation
      }
      lastBarTime = currentBarTime;
   }
   lastRatesTotal = rates_total;
   
   //--- Don't set arrays as series - we'll work with normal indexing
   //--- Copy arrays to work with them
   datetime timeArray[];
   double highArray[];
   double lowArray[];
   double closeArray[];
   
   ArraySetAsSeries(timeArray, false);
   ArraySetAsSeries(highArray, false);
   ArraySetAsSeries(lowArray, false);
   ArraySetAsSeries(closeArray, false);
   
   int timeCopied = CopyTime(_Symbol, _Period, 0, rates_total, timeArray);
   int highCopied = CopyHigh(_Symbol, _Period, 0, rates_total, highArray);
   int lowCopied = CopyLow(_Symbol, _Period, 0, rates_total, lowArray);
   int closeCopied = CopyClose(_Symbol, _Period, 0, rates_total, closeArray);
   
   //--- Data validation
   if(timeCopied <= 0 || highCopied <= 0 || lowCopied <= 0 || closeCopied <= 0)
   {
      if(InpShowDebugInfo)
         Print("ERROR: Failed to copy data - Time: ", timeCopied, " High: ", highCopied, " Low: ", lowCopied, " Close: ", closeCopied);
      return(0);
   }
   
   //--- Validate data sanity
   if(InpShowDebugInfo && prev_calculated == 0)
   {
      Print("=== DATA VALIDATION ===");
      Print("Symbol: ", _Symbol, " Period: ", EnumToString(_Period));
      Print("Total bars: ", rates_total, " | Time copied: ", timeCopied, " | High copied: ", highCopied, " | Low copied: ", lowCopied);
      Print("Data range: ", TimeToString(timeArray[0]), " to ", TimeToString(timeArray[ArraySize(timeArray)-1]));
      Print("Price range: High=", highArray[ArrayMaximum(highArray, 0, rates_total)], " Low=", lowArray[ArrayMinimum(lowArray, 0, rates_total)]);
      Print("Swing Period: ", InpSwingPeriod, " | Min Bars Between: ", InpMinBarsBetween, " | Max Points: ", InpMaxSwingPoints);
   }
   
   //--- Find swing points
   FindSwingPoints(rates_total, timeArray, highArray, lowArray);
   
   //--- Draw trendlines
   DrawTrendlines(rates_total, timeArray, prev_calculated);
   
   //--- Check for trading signals if enabled
   if(InpEnableTrading)
   {
      CheckTradingSignals(rates_total, timeArray, highArray, lowArray, closeArray);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Find swing highs and lows                                        |
//+------------------------------------------------------------------+
void FindSwingPoints(const int rates_total,
                     const datetime &time[],
                     const double &high[],
                     const double &low[])
{
   ArrayResize(swingPoints, 0);
   
   //--- Arrays are in normal order: index 0 = oldest, index (rates_total-1) = newest
   //--- Focus on recent data if lookback is specified
   int lookbackStart = 0;
   if(InpLookbackBars > 0 && rates_total > InpLookbackBars)
   {
      lookbackStart = rates_total - InpLookbackBars;
   }
   
   int start = MathMax(InpSwingPeriod, lookbackStart);  // Start from older bars (but respect lookback)
   int end = rates_total - InpSwingPeriod - 1;          // End at newer bars
   
   //--- Find swing highs
   if(InpShowResistanceLines)
   {
      SwingPoint highPoints[];
      ArrayResize(highPoints, 0);
      
      for(int i = start; i <= end; i++)
      {
         bool isSwingHigh = true;
         double currentHigh = high[i];
         
         //--- Check if current high is higher than surrounding bars
         for(int j = 1; j <= InpSwingPeriod; j++)
         {
            if(high[i - j] >= currentHigh || high[i + j] >= currentHigh)
            {
               isSwingHigh = false;
               break;
            }
         }
         
         if(isSwingHigh)
         {
            SwingPoint point;
            point.time = time[i];
            point.price = currentHigh;
            point.isHigh = true;
            point.barIndex = i;
            
            //--- Check minimum distance from previous swing high
            bool canAdd = true;
            if(ArraySize(highPoints) > 0)
            {
               int lastIndex = ArraySize(highPoints) - 1;
               int barsBetween = MathAbs(highPoints[lastIndex].barIndex - point.barIndex);
               
               if(barsBetween < InpMinBarsBetween)
                  canAdd = false;
            }
            
            if(canAdd)
            {
               ArrayResize(highPoints, ArraySize(highPoints) + 1);
               highPoints[ArraySize(highPoints) - 1] = point;
            }
            
            //--- Limit number of swing points
            if(ArraySize(highPoints) >= InpMaxSwingPoints / 2)
               break;
         }
      }
      
      //--- Add high points to main array
      for(int i = 0; i < ArraySize(highPoints); i++)
      {
         ArrayResize(swingPoints, ArraySize(swingPoints) + 1);
         swingPoints[ArraySize(swingPoints) - 1] = highPoints[i];
      }
      
      if(InpShowDebugInfo && InpShowDetailedStats)
      {
         Print("Swing Highs Found: ", ArraySize(highPoints));
         for(int i = 0; i < ArraySize(highPoints) && i < 5; i++)
         {
            Print("  High[", i, "]: Bar=", highPoints[i].barIndex, " Time=", TimeToString(highPoints[i].time), " Price=", DoubleToString(highPoints[i].price, _Digits));
         }
      }
   }
   
   //--- Find swing lows
   if(InpShowSupportLines)
   {
      SwingPoint lowPoints[];
      ArrayResize(lowPoints, 0);
      
      for(int i = start; i <= end; i++)
      {
         bool isSwingLow = true;
         double currentLow = low[i];
         
         //--- Check if current low is lower than surrounding bars
         for(int j = 1; j <= InpSwingPeriod; j++)
         {
            if(low[i - j] <= currentLow || low[i + j] <= currentLow)
            {
               isSwingLow = false;
               break;
            }
         }
         
         if(isSwingLow)
         {
            SwingPoint point;
            point.time = time[i];
            point.price = currentLow;
            point.isHigh = false;
            point.barIndex = i;
            
            //--- Check minimum distance from previous swing low
            bool canAdd = true;
            if(ArraySize(lowPoints) > 0)
            {
               int lastIndex = ArraySize(lowPoints) - 1;
               int barsBetween = MathAbs(lowPoints[lastIndex].barIndex - point.barIndex);
               
               if(barsBetween < InpMinBarsBetween)
                  canAdd = false;
            }
            
            if(canAdd)
            {
               ArrayResize(lowPoints, ArraySize(lowPoints) + 1);
               lowPoints[ArraySize(lowPoints) - 1] = point;
            }
            
            //--- Limit number of swing points
            if(ArraySize(lowPoints) >= InpMaxSwingPoints / 2)
               break;
         }
      }
      
      //--- Add low points to main array
      for(int i = 0; i < ArraySize(lowPoints); i++)
      {
         ArrayResize(swingPoints, ArraySize(swingPoints) + 1);
         swingPoints[ArraySize(swingPoints) - 1] = lowPoints[i];
      }
      
      if(InpShowDebugInfo && InpShowDetailedStats)
      {
         Print("Swing Lows Found: ", ArraySize(lowPoints));
         for(int i = 0; i < ArraySize(lowPoints) && i < 5; i++)
         {
            Print("  Low[", i, "]: Bar=", lowPoints[i].barIndex, " Time=", TimeToString(lowPoints[i].time), " Price=", DoubleToString(lowPoints[i].price, _Digits));
         }
      }
   }
   
   //--- Sort swing points by bar index (oldest first)
   SortSwingPoints();
   
   //--- Summary feedback
   if(InpShowDebugInfo)
   {
      int totalHighs = 0, totalLows = 0;
      for(int i = 0; i < ArraySize(swingPoints); i++)
      {
         if(swingPoints[i].isHigh) totalHighs++;
         else totalLows++;
      }
      static int lastTotal = -1;
      static datetime lastSummaryTime = 0;
      datetime currentTime = TimeCurrent();
      
      // Show summary when swing points change OR every 100 bars to show it's updating
      if(ArraySize(swingPoints) != lastTotal || (currentTime - lastSummaryTime) > 3600)
      {
         Print("=== SWING POINTS SUMMARY ===");
         Print("Current bar time: ", TimeToString(time[rates_total - 1]));
         Print("Total swing points: ", ArraySize(swingPoints), " (Highs: ", totalHighs, " | Lows: ", totalLows, ")");
         lastTotal = ArraySize(swingPoints);
         lastSummaryTime = currentTime;
      }
   }
}

//+------------------------------------------------------------------+
//| Sort swing points by bar index                                  |
//+------------------------------------------------------------------+
void SortSwingPoints()
{
   int size = ArraySize(swingPoints);
   for(int i = 0; i < size - 1; i++)
   {
      for(int j = i + 1; j < size; j++)
      {
         if(swingPoints[i].barIndex > swingPoints[j].barIndex)
         {
            SwingPoint temp = swingPoints[i];
            swingPoints[i] = swingPoints[j];
            swingPoints[j] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw trendlines connecting swing points                         |
//+------------------------------------------------------------------+
void DrawTrendlines(const int rates_total, const datetime &time[], const int prev_calculated)
{
   //--- Delete existing trendlines first
   DeleteAllTrendlines();
   
   int swingCount = ArraySize(swingPoints);
   if(swingCount < 2)
   {
      if(InpShowDebugInfo)
         Print("WARNING: Not enough swing points to draw trendlines: ", swingCount, " (need at least 2)");
      return;
   }
   
   trendlineCount = 0;
   ArrayResize(trendlineNames, 0);
   
   int resistanceLines = 0;
   int supportLines = 0;
   
   //--- Focus on most recent swing points (prioritize recent trendlines)
   //--- Only use swing points from the most recent portion of data
   int recentStartIndex = 0;
   if(InpLookbackBars > 0)
   {
      // Find the first swing point that's within our lookback window
      int lookbackBarIndex = (rates_total > InpLookbackBars) ? (rates_total - InpLookbackBars) : 0;
      for(int i = 0; i < swingCount; i++)
      {
         if(swingPoints[i].barIndex >= lookbackBarIndex)
         {
            recentStartIndex = i;
            break;
         }
      }
   }
   
   //--- Draw trendlines for swing highs (resistance) - connect recent highs
   if(InpShowResistanceLines)
   {
      for(int i = recentStartIndex; i < swingCount; i++)
      {
         if(!swingPoints[i].isHigh)
            continue;
         
         //--- Find next high
         for(int j = i + 1; j < swingCount; j++)
         {
            if(!swingPoints[j].isHigh)
               continue;
            
            //--- Check if both points are valid
            if(swingPoints[i].barIndex >= rates_total || swingPoints[j].barIndex >= rates_total)
               continue;
            
            DrawTrendline(swingPoints[i], swingPoints[j], rates_total, time, true);
            resistanceLines++;
            break; // Only connect to the next high
         }
      }
   }
   
   //--- Draw trendlines for swing lows (support) - connect recent lows
   if(InpShowSupportLines)
   {
      for(int i = recentStartIndex; i < swingCount; i++)
      {
         if(swingPoints[i].isHigh)
            continue;
         
         //--- Find next low
         for(int j = i + 1; j < swingCount; j++)
         {
            if(swingPoints[j].isHigh)
               continue;
            
            //--- Check if both points are valid
            if(swingPoints[i].barIndex >= rates_total || swingPoints[j].barIndex >= rates_total)
               continue;
            
            DrawTrendline(swingPoints[i], swingPoints[j], rates_total, time, false);
            supportLines++;
            break; // Only connect to the next low
         }
      }
   }
   
   //--- Feedback summary
   static int lastResistance = -1, lastSupport = -1;
   static datetime lastSummaryTime = 0;
   datetime currentTime = TimeCurrent();
   
   // Show summary when counts change OR periodically to show updates
   bool shouldShow = (resistanceLines != lastResistance || supportLines != lastSupport || prev_calculated == 0);
   bool periodicUpdate = (currentTime - lastSummaryTime) > 3600; // Every hour
   
   if(InpShowDebugInfo && (shouldShow || periodicUpdate))
   {
      Print("=== TRENDLINE SUMMARY ===");
      Print("Current time: ", TimeToString(time[rates_total - 1]), " | Bars: ", rates_total);
      Print("Resistance lines: ", resistanceLines, " | Support lines: ", supportLines, " | Total: ", (resistanceLines + supportLines));
      Print("Objects created: ", trendlineCount);
      
      //--- Verify objects exist
      int actualObjects = 0;
      int total = ObjectsTotal(0, 0, -1);
      string prefix = "TrendlineIndicator_TL_";
      for(int i = 0; i < total; i++)
      {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, prefix) == 0)
            actualObjects++;
      }
      Print("Objects on chart: ", actualObjects, " (expected: ", trendlineCount, ")");
      
      if(actualObjects != trendlineCount && actualObjects > 0)
         Print("WARNING: Object count mismatch - some objects may not be visible");
      
      if(shouldShow)
      {
         Print("TRENDLINES UPDATED - New swing points detected!");
      }
      
      lastResistance = resistanceLines;
      lastSupport = supportLines;
      lastSummaryTime = currentTime;
   }
   
   //--- Redraw chart to show objects
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw a single trendline                                          |
//+------------------------------------------------------------------+
void DrawTrendline(SwingPoint &point1, SwingPoint &point2,
                   const int rates_total, const datetime &time[],
                   const bool isResistance)
{
   //--- Create unique name with indicator prefix
   uniqueObjectCounter++;
   string prefix = "TrendlineIndicator_TL_";
   //--- Use point times and counter for better uniqueness
   long timeHash = (long)point1.time + (long)point2.time;
   string name = prefix + IntegerToString(trendlineCount) + "_" + IntegerToString(uniqueObjectCounter) + "_" + IntegerToString(timeHash) + "_" + IntegerToString(GetTickCount64());
   
   //--- Delete object if it already exists (with retry)
   int attempts = 0;
   while(ObjectFind(0, name) >= 0 && attempts < 10)
   {
      ObjectDelete(0, name);
      Sleep(50);
      ChartRedraw(0);
      attempts++;
      //--- Generate new name if still exists
      uniqueObjectCounter++;
      timeHash = (long)point1.time + (long)point2.time + uniqueObjectCounter;
      name = prefix + IntegerToString(trendlineCount) + "_" + IntegerToString(uniqueObjectCounter) + "_" + IntegerToString(timeHash) + "_" + IntegerToString(GetTickCount64());
   }
   
   if(attempts >= 10)
   {
      if(InpShowDebugInfo)
         Print("WARNING: Could not create unique name after ", attempts, " attempts. Using: ", name);
   }
   
   //--- Calculate end time
   datetime endTime;
   if(InpExtendLines)
   {
      //--- Extend to right edge of chart (use most recent bar time)
      datetime latestTime = time[rates_total - 1];
      endTime = latestTime + PeriodSeconds(_Period) * InpExtensionBars;
   }
   else
   {
      //--- Use extension bars
      int extensionBars = MathMax(InpExtensionBars, rates_total - point2.barIndex);
      endTime = point2.time + PeriodSeconds(_Period) * extensionBars;
   }
   
   //--- Calculate end price using linear extrapolation
   double priceDiff = point2.price - point1.price;
   datetime timeDiff = point2.time - point1.time;
   double slope = 0.0;
   
   if(timeDiff > 0)
   {
      slope = priceDiff / (double)timeDiff;
   }
   
   double endPrice = point2.price + slope * (endTime - point2.time);
   
   //--- Create trendline object (use 0 for current chart)
   bool created = false;
   if(InpShowRay)
   {
      //--- Create ray (infinite extension)
      created = ObjectCreate(0, name, OBJ_TREND, 0, point1.time, point1.price, point2.time, point2.price);
      if(created)
      {
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, name, OBJPROP_COLOR, isResistance ? InpResistanceColor : InpSupportColor);
         ObjectSetInteger(0, name, OBJPROP_STYLE, InpLineStyle);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      }
   }
   else
   {
      //--- Create regular trendline
      created = ObjectCreate(0, name, OBJ_TREND, 0, point1.time, point1.price, endTime, endPrice);
      if(created)
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, isResistance ? InpResistanceColor : InpSupportColor);
         ObjectSetInteger(0, name, OBJPROP_STYLE, InpLineStyle);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      }
   }
   
   if(!created)
   {
      int error = GetLastError();
      ResetLastError();
      if(InpShowDebugInfo)
      {
         Print("ERROR: Failed to create trendline: ", name);
         Print("  Error code: ", error);
         Print("  Point1: Bar=", point1.barIndex, " Time=", TimeToString(point1.time), " Price=", DoubleToString(point1.price, _Digits));
         Print("  Point2: Bar=", point2.barIndex, " Time=", TimeToString(point2.time), " Price=", DoubleToString(point2.price, _Digits));
         Print("  EndTime: ", TimeToString(endTime), " EndPrice: ", DoubleToString(endPrice, _Digits));
         
         //--- Data validation
         if(point1.time <= 0 || point2.time <= 0)
            Print("  VALIDATION ERROR: Invalid time values");
         if(point1.price <= 0 || point2.price <= 0)
            Print("  VALIDATION ERROR: Invalid price values");
         if(endTime <= point2.time)
            Print("  VALIDATION ERROR: End time must be after point2 time");
      }
   }
   else if(InpShowDebugInfo && InpShowDetailedStats)
   {
      Print("Created: ", name, " | Type: ", (isResistance ? "Resistance" : "Support"), " | Points: ", TimeToString(point1.time), " -> ", TimeToString(point2.time));
   }
   
   //--- Add price label if enabled
   if(InpShowLabels && created)
   {
      string labelName = name + "_Label";
      if(ObjectFind(0, labelName) >= 0)
      {
         ObjectDelete(0, labelName);
      }
      
      string labelText = DoubleToString(point2.price, _Digits);
      
      if(ObjectCreate(0, labelName, OBJ_TEXT, 0, point2.time, point2.price))
      {
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, isResistance ? InpResistanceColor : InpSupportColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
      }
   }
   
   //--- Store trendline name and info only if created successfully
   if(created)
   {
      //--- Store trendline info for trading signals
      if(InpEnableTrading)
      {
         ArrayResize(trendlines, trendlineCount + 1);
         trendlines[trendlineCount].name = name;
         trendlines[trendlineCount].point1Price = point1.price;
         trendlines[trendlineCount].point2Price = point2.price;
         trendlines[trendlineCount].point1Time = point1.time;
         trendlines[trendlineCount].point2Time = point2.time;
         trendlines[trendlineCount].isResistance = isResistance;
         trendlines[trendlineCount].slope = slope;
         // Calculate intercept: price = slope * time + intercept
         trendlines[trendlineCount].intercept = point1.price - slope * (double)point1.time;
      }
      
      ArrayResize(trendlineNames, trendlineCount + 1);
      trendlineNames[trendlineCount] = name;
      if(InpShowLabels)
      {
         ArrayResize(trendlineNames, trendlineCount + 2);
         trendlineNames[trendlineCount + 1] = name + "_Label";
      }
      trendlineCount++;
      if(InpShowLabels) trendlineCount++;
   }
}

//+------------------------------------------------------------------+
//| Delete all trendline objects                                     |
//+------------------------------------------------------------------+
void DeleteAllTrendlines()
{
   //--- Delete stored trendlines
   for(int i = 0; i < ArraySize(trendlineNames); i++)
   {
      if(ObjectFind(0, trendlineNames[i]) >= 0)
      {
         ObjectDelete(0, trendlineNames[i]);
      }
   }
   
   //--- Also delete any remaining trendlines with our prefix
   string prefix = "TrendlineIndicator_TL_";
   int total = ObjectsTotal(0, 0, -1);
   int deleted = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
      {
         if(ObjectDelete(0, name))
            deleted++;
      }
   }
   
   if(deleted > 0)
   {
      ChartRedraw(0);
      Sleep(100); // Give time for deletion to complete
   }
   
   ArrayResize(trendlineNames, 0);
   trendlineCount = 0;
   ArrayResize(trendlines, 0);
}

//+------------------------------------------------------------------+
//| Check for trading signals based on trendline breaks            |
//+------------------------------------------------------------------+
void CheckTradingSignals(const int rates_total,
                        datetime &time[],
                        double &high[],
                        double &low[],
                        double &close[])
{
   if(ArraySize(trendlines) == 0)
      return;
   
   //--- Get current price data
   double currentClose = close[rates_total - 1];
   double currentHigh = high[rates_total - 1];
   double currentLow = low[rates_total - 1];
   datetime currentTime = time[rates_total - 1];
   
   //--- Check if we already have an active signal
   if(currentSignal.active)
   {
      CheckTradeStatus(currentTime, currentClose, currentHigh, currentLow);
      
      //--- Check real trade status if enabled
      if(InpExecuteRealTrades && currentTradeTicket > 0)
      {
         CheckRealTradeStatus();
      }
      return;
   }
   
   //--- Check each trendline for breaks
   for(int i = 0; i < ArraySize(trendlines); i++)
   {
      double trendlinePrice = CalculateTrendlinePrice(trendlines[i], currentTime);
      
      if(trendlinePrice <= 0)
         continue;
      
      //--- Check for resistance break (bullish signal)
      if(trendlines[i].isResistance && currentClose > trendlinePrice && currentHigh > trendlinePrice)
      {
         // Price broke above resistance - BUY signal
         if(CreateBuySignal(trendlines[i], currentTime, currentClose, rates_total, time))
            break;
      }
      //--- Check for support break (bearish signal)
      else if(!trendlines[i].isResistance && currentClose < trendlinePrice && currentLow < trendlinePrice)
      {
         // Price broke below support - SELL signal
         if(CreateSellSignal(trendlines[i], currentTime, currentClose, rates_total, time))
            break;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate price on trendline at given time                      |
//+------------------------------------------------------------------+
double CalculateTrendlinePrice(TrendlineInfo &tl, datetime time)
{
   // Price = slope * time + intercept
   double price = tl.slope * (double)time + tl.intercept;
   
   //--- Validate: price should be between point1 and point2 prices (or extended)
   if(time >= tl.point1Time && time <= tl.point2Time)
   {
      return price;
   }
   //--- Allow extension beyond point2 for future prediction
   else if(time > tl.point2Time)
   {
      return price; // Extended forward
   }
   
   return 0; // Invalid
}

//+------------------------------------------------------------------+
//| Create buy signal                                                |
//+------------------------------------------------------------------+
bool CreateBuySignal(TrendlineInfo &tl, datetime entryTime, double entryPrice, const int rates_total, datetime &time[])
{
   //--- Find nearest support level (for SL) and next resistance (for TP)
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(InpUseNearestLevels)
   {
      stopLoss = FindNearestSupport(entryPrice, rates_total, time);
      takeProfit = FindNextResistance(entryPrice, rates_total, time);
   }
   
   //--- Validate levels found
   if(stopLoss <= 0 || takeProfit <= 0 || stopLoss >= entryPrice || takeProfit <= entryPrice)
   {
      if(InpShowDebugInfo)
         Print("BUY Signal rejected: Invalid support/resistance levels - SL: ", stopLoss, " TP: ", takeProfit);
      return false;
   }
   
   //--- Calculate Risk/Reward ratio
   double risk = entryPrice - stopLoss;
   double reward = takeProfit - entryPrice;
   
   if(risk <= 0 || reward <= 0)
   {
      if(InpShowDebugInfo)
         Print("BUY Signal rejected: Invalid risk/reward calculation");
      return false;
   }
   
   double riskRewardRatio = reward / risk;
   
   //--- Check if R/R meets minimum requirement
   if(!InpIgnoreRRRejection && riskRewardRatio < InpMinRiskRewardRatio)
   {
      if(InpShowDebugInfo)
         Print("BUY Signal rejected: R/R ratio ", DoubleToString(riskRewardRatio, 2), " below minimum ", InpMinRiskRewardRatio);
      return false;
   }
   
   //--- Sanity check for maximum R/R
   if(!InpIgnoreRRRejection && riskRewardRatio > InpMaxRiskRewardRatio)
   {
      if(InpShowDebugInfo)
         Print("BUY Signal rejected: R/R ratio ", DoubleToString(riskRewardRatio, 2), " exceeds maximum ", InpMaxRiskRewardRatio);
      return false;
   }
   
   //--- Warn if R/R is outside recommended range but still allow if ignore is enabled
   if(InpIgnoreRRRejection)
   {
      if(riskRewardRatio < InpMinRiskRewardRatio)
      {
         if(InpShowDebugInfo)
            Print("BUY Signal WARNING: R/R ratio ", DoubleToString(riskRewardRatio, 2), " below recommended minimum ", InpMinRiskRewardRatio, " (Accepted due to IgnoreRRRejection)");
      }
      else if(riskRewardRatio > InpMaxRiskRewardRatio)
      {
         if(InpShowDebugInfo)
            Print("BUY Signal WARNING: R/R ratio ", DoubleToString(riskRewardRatio, 2), " exceeds recommended maximum ", InpMaxRiskRewardRatio, " (Accepted due to IgnoreRRRejection)");
      }
   }
   
   //--- Create the signal
   currentSignal.active = true;
   currentSignal.type = ORDER_TYPE_BUY;
   currentSignal.entryPrice = entryPrice;
   currentSignal.entryTime = entryTime;
   currentSignal.trendlineName = tl.name;
   currentSignal.stopLoss = stopLoss;
   currentSignal.takeProfit = takeProfit;
   
   //--- Execute real trade if enabled
   if(InpExecuteRealTrades)
   {
      //--- Check if we already have an open position with our magic number
      bool hasPosition = false;
      for(int pos = PositionsTotal() - 1; pos >= 0; pos--)
      {
         ulong ticket = PositionGetTicket(pos);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               hasPosition = true;
               if(InpShowDebugInfo)
                  Print("BUY Signal: Position already exists (Ticket: ", ticket, "), skipping trade execution");
               break;
            }
         }
      }
      
      if(!hasPosition)
      {
         if(InpShowDebugInfo)
            Print("Attempting to execute BUY trade - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit);
         
         if(ExecuteBuyTrade(entryPrice, stopLoss, takeProfit))
         {
            currentTradeTicket = trade.ResultOrder();
            if(InpShowDebugInfo)
               Print("Real BUY trade executed - Ticket: ", currentTradeTicket);
         }
         else
         {
            if(InpShowDebugInfo)
            {
               Print("Failed to execute real BUY trade - Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               Print("  Symbol: ", _Symbol, " Lot: ", InpLotSize, " Magic: ", InpMagicNumber);
            }
            // Still create signal for visualization even if trade fails
         }
      }
   }
   else
   {
      //--- Real trading is disabled - only showing signal for visualization
      if(InpShowDebugInfo)
         Print("BUY Signal created (Visualization only) - Real Trading is DISABLED. Set InpExecuteRealTrades=true to execute trades.");
   }
   
   //--- Draw trade levels on chart
   if(InpShowTradeLevels)
   {
      DrawTradeLevels();
   }
   
   if(InpShowDebugInfo)
   {
      Print("=== BUY SIGNAL GENERATED ===");
      Print("Entry: ", DoubleToString(entryPrice, _Digits));
      Print("SL (Support): ", DoubleToString(stopLoss, _Digits), " | Risk: ", DoubleToString(risk, _Digits));
      Print("TP (Resistance): ", DoubleToString(takeProfit, _Digits), " | Reward: ", DoubleToString(reward, _Digits));
      Print("Risk/Reward Ratio: ", DoubleToString(riskRewardRatio, 2), ":1");
      Print("Trendline: ", tl.name);
      if(InpExecuteRealTrades && currentTradeTicket > 0)
         Print("Real Trade Ticket: ", currentTradeTicket);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Create sell signal                                               |
//+------------------------------------------------------------------+
bool CreateSellSignal(TrendlineInfo &tl, datetime entryTime, double entryPrice, const int rates_total, datetime &time[])
{
   //--- Find nearest resistance level (for SL) and next support (for TP)
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(InpUseNearestLevels)
   {
      stopLoss = FindNearestResistance(entryPrice, rates_total, time);
      takeProfit = FindNextSupport(entryPrice, rates_total, time);
   }
   
   //--- Validate levels found
   if(stopLoss <= 0 || takeProfit <= 0 || stopLoss <= entryPrice || takeProfit >= entryPrice)
   {
      if(InpShowDebugInfo)
         Print("SELL Signal rejected: Invalid support/resistance levels - SL: ", stopLoss, " TP: ", takeProfit);
      return false;
   }
   
   //--- Calculate Risk/Reward ratio
   double risk = stopLoss - entryPrice;
   double reward = entryPrice - takeProfit;
   
   if(risk <= 0 || reward <= 0)
   {
      if(InpShowDebugInfo)
         Print("SELL Signal rejected: Invalid risk/reward calculation");
      return false;
   }
   
   double riskRewardRatio = reward / risk;
   
   //--- Check if R/R meets minimum requirement
   if(!InpIgnoreRRRejection && riskRewardRatio < InpMinRiskRewardRatio)
   {
      if(InpShowDebugInfo)
         Print("SELL Signal rejected: R/R ratio ", DoubleToString(riskRewardRatio, 2), " below minimum ", InpMinRiskRewardRatio);
      return false;
   }
   
   //--- Sanity check for maximum R/R
   if(!InpIgnoreRRRejection && riskRewardRatio > InpMaxRiskRewardRatio)
   {
      if(InpShowDebugInfo)
         Print("SELL Signal rejected: R/R ratio ", DoubleToString(riskRewardRatio, 2), " exceeds maximum ", InpMaxRiskRewardRatio);
      return false;
   }
   
   //--- Warn if R/R is outside recommended range but still allow if ignore is enabled
   if(InpIgnoreRRRejection)
   {
      if(riskRewardRatio < InpMinRiskRewardRatio)
      {
         if(InpShowDebugInfo)
            Print("SELL Signal WARNING: R/R ratio ", DoubleToString(riskRewardRatio, 2), " below recommended minimum ", InpMinRiskRewardRatio, " (Accepted due to IgnoreRRRejection)");
      }
      else if(riskRewardRatio > InpMaxRiskRewardRatio)
      {
         if(InpShowDebugInfo)
            Print("SELL Signal WARNING: R/R ratio ", DoubleToString(riskRewardRatio, 2), " exceeds recommended maximum ", InpMaxRiskRewardRatio, " (Accepted due to IgnoreRRRejection)");
      }
   }
   
   //--- Create the signal
   currentSignal.active = true;
   currentSignal.type = ORDER_TYPE_SELL;
   currentSignal.entryPrice = entryPrice;
   currentSignal.entryTime = entryTime;
   currentSignal.trendlineName = tl.name;
   currentSignal.stopLoss = stopLoss;
   currentSignal.takeProfit = takeProfit;
   
   //--- Execute real trade if enabled
   if(InpExecuteRealTrades)
   {
      //--- Check if we already have an open position with our magic number
      bool hasPosition = false;
      for(int pos = PositionsTotal() - 1; pos >= 0; pos--)
      {
         ulong ticket = PositionGetTicket(pos);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               hasPosition = true;
               if(InpShowDebugInfo)
                  Print("SELL Signal: Position already exists (Ticket: ", ticket, "), skipping trade execution");
               break;
            }
         }
      }
      
      if(!hasPosition)
      {
         if(InpShowDebugInfo)
            Print("Attempting to execute SELL trade - Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit);
         
         if(ExecuteSellTrade(entryPrice, stopLoss, takeProfit))
         {
            currentTradeTicket = trade.ResultOrder();
            if(InpShowDebugInfo)
               Print("Real SELL trade executed - Ticket: ", currentTradeTicket);
         }
         else
         {
            if(InpShowDebugInfo)
            {
               Print("Failed to execute real SELL trade - Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               Print("  Symbol: ", _Symbol, " Lot: ", InpLotSize, " Magic: ", InpMagicNumber);
            }
            // Still create signal for visualization even if trade fails
         }
      }
   }
   else
   {
      //--- Real trading is disabled - only showing signal for visualization
      if(InpShowDebugInfo)
         Print("SELL Signal created (Visualization only) - Real Trading is DISABLED. Set InpExecuteRealTrades=true to execute trades.");
   }
   
   //--- Draw trade levels on chart
   if(InpShowTradeLevels)
   {
      DrawTradeLevels();
   }
   
   if(InpShowDebugInfo)
   {
      Print("=== SELL SIGNAL GENERATED ===");
      Print("Entry: ", DoubleToString(entryPrice, _Digits));
      Print("SL (Resistance): ", DoubleToString(stopLoss, _Digits), " | Risk: ", DoubleToString(risk, _Digits));
      Print("TP (Support): ", DoubleToString(takeProfit, _Digits), " | Reward: ", DoubleToString(reward, _Digits));
      Print("Risk/Reward Ratio: ", DoubleToString(riskRewardRatio, 2), ":1");
      Print("Trendline: ", tl.name);
      if(InpExecuteRealTrades && currentTradeTicket > 0)
         Print("Real Trade Ticket: ", currentTradeTicket);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Draw trade levels (Entry, SL, TP) on chart                      |
//+------------------------------------------------------------------+
void DrawTradeLevels()
{
   string prefix = "TrendlineIndicator_Trade_";
   
   //--- Entry line
   currentSignal.entryObjectName = prefix + "Entry";
   if(ObjectFind(0, currentSignal.entryObjectName) >= 0)
      ObjectDelete(0, currentSignal.entryObjectName);
   
   if(ObjectCreate(0, currentSignal.entryObjectName, OBJ_HLINE, 0, 0, currentSignal.entryPrice))
   {
      ObjectSetInteger(0, currentSignal.entryObjectName, OBJPROP_COLOR, (currentSignal.type == ORDER_TYPE_BUY) ? InpBuyColor : InpSellColor);
      ObjectSetInteger(0, currentSignal.entryObjectName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, currentSignal.entryObjectName, OBJPROP_WIDTH, 2);
      ObjectSetString(0, currentSignal.entryObjectName, OBJPROP_TEXT, "Entry: " + DoubleToString(currentSignal.entryPrice, _Digits));
   }
   
   //--- Stop Loss line
   currentSignal.slObjectName = prefix + "SL";
   if(ObjectFind(0, currentSignal.slObjectName) >= 0)
      ObjectDelete(0, currentSignal.slObjectName);
   
   if(ObjectCreate(0, currentSignal.slObjectName, OBJ_HLINE, 0, 0, currentSignal.stopLoss))
   {
      ObjectSetInteger(0, currentSignal.slObjectName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, currentSignal.slObjectName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, currentSignal.slObjectName, OBJPROP_WIDTH, 2);
      ObjectSetString(0, currentSignal.slObjectName, OBJPROP_TEXT, "SL: " + DoubleToString(currentSignal.stopLoss, _Digits));
   }
   
   //--- Take Profit line
   currentSignal.tpObjectName = prefix + "TP";
   if(ObjectFind(0, currentSignal.tpObjectName) >= 0)
      ObjectDelete(0, currentSignal.tpObjectName);
   
   if(ObjectCreate(0, currentSignal.tpObjectName, OBJ_HLINE, 0, 0, currentSignal.takeProfit))
   {
      ObjectSetInteger(0, currentSignal.tpObjectName, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, currentSignal.tpObjectName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, currentSignal.tpObjectName, OBJPROP_WIDTH, 2);
      ObjectSetString(0, currentSignal.tpObjectName, OBJPROP_TEXT, "TP: " + DoubleToString(currentSignal.takeProfit, _Digits));
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Check if trade hit SL or TP                                     |
//+------------------------------------------------------------------+
void CheckTradeStatus(datetime currentTime, double currentClose, double currentHigh, double currentLow)
{
   bool tradeClosed = false;
   string reason = "";
   
   if(currentSignal.type == ORDER_TYPE_BUY)
   {
      //--- Check for TP hit
      if(currentHigh >= currentSignal.takeProfit)
      {
         tradeClosed = true;
         reason = "TP HIT";
      }
      //--- Check for SL hit
      else if(currentLow <= currentSignal.stopLoss)
      {
         tradeClosed = true;
         reason = "SL HIT";
      }
   }
   else // SELL
   {
      //--- Check for TP hit
      if(currentLow <= currentSignal.takeProfit)
      {
         tradeClosed = true;
         reason = "TP HIT";
      }
      //--- Check for SL hit
      else if(currentHigh >= currentSignal.stopLoss)
      {
         tradeClosed = true;
         reason = "SL HIT";
      }
   }
   
   if(tradeClosed)
   {
      double profit = 0;
      if(currentSignal.type == ORDER_TYPE_BUY)
      {
         if(reason == "TP HIT")
            profit = currentSignal.takeProfit - currentSignal.entryPrice;
         else
            profit = currentSignal.stopLoss - currentSignal.entryPrice;
      }
      else
      {
         if(reason == "TP HIT")
            profit = currentSignal.entryPrice - currentSignal.takeProfit;
         else
            profit = currentSignal.entryPrice - currentSignal.stopLoss;
      }
      
      if(InpShowDebugInfo)
      {
         Print("=== TRADE CLOSED: ", reason, " ===");
         Print("Entry: ", DoubleToString(currentSignal.entryPrice, _Digits), " | Close: ", DoubleToString(currentClose, _Digits));
         Print("Profit/Loss: ", DoubleToString(profit, _Digits), " (", (profit > 0 ? "WIN" : "LOSS"), ")");
      }
      
      //--- Close real trade if enabled
      if(InpExecuteRealTrades && currentTradeTicket > 0)
      {
         CloseRealTrade();
      }
      
      //--- Delete trade level objects
      DeleteTradeSignalObjects();
      
      //--- Reset signal
      currentSignal.active = false;
      currentTradeTicket = 0;
   }
}

//+------------------------------------------------------------------+
//| Delete trade signal objects                                     |
//+------------------------------------------------------------------+
void DeleteTradeSignalObjects()
{
   string prefix = "TrendlineIndicator_Trade_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| Find nearest support level below entry price                    |
//+------------------------------------------------------------------+
double FindNearestSupport(double entryPrice, const int rates_total, datetime &time[])
{
   double nearestSupport = 0;
   double minDistance = DBL_MAX;
   double pipsMultiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double tolerance = InpLevelTolerancePips * _Point * pipsMultiplier;
   
   datetime currentTime = time[rates_total - 1];
   int supportLinesChecked = 0;
   int validSupportLines = 0;
   
   for(int i = 0; i < ArraySize(trendlines); i++)
   {
      if(trendlines[i].isResistance)
         continue; // Skip resistance lines
      
      supportLinesChecked++;
      
      // Get the price level of this support trendline at current time
      double supportPrice = CalculateTrendlinePrice(trendlines[i], currentTime);
      
      if(supportPrice <= 0)
      {
         if(InpShowDebugInfo && supportLinesChecked <= 3) // Only log first few to avoid spam
            Print("FindNearestSupport: Invalid price for trendline ", i, " - Price: ", supportPrice);
         continue;
      }
      
      // Support must be below entry price
      if(supportPrice >= entryPrice - tolerance)
      {
         if(InpShowDebugInfo && supportLinesChecked <= 3)
            Print("FindNearestSupport: Support too close/above entry - Support: ", supportPrice, " Entry: ", entryPrice);
         continue;
      }
      
      validSupportLines++;
      double distance = entryPrice - supportPrice;
      
      // Find the closest support below entry
      if(distance < minDistance && distance > 0)
      {
         minDistance = distance;
         nearestSupport = supportPrice;
      }
   }
   
   if(InpShowDebugInfo && nearestSupport == 0)
      Print("FindNearestSupport: No valid support found - Checked: ", supportLinesChecked, " Valid: ", validSupportLines, " Entry: ", entryPrice);
   
   return nearestSupport;
}

//+------------------------------------------------------------------+
//| Find next resistance level above entry price                    |
//+------------------------------------------------------------------+
double FindNextResistance(double entryPrice, const int rates_total, datetime &time[])
{
   double nextResistance = 0;
   double minDistance = DBL_MAX;
   double pipsMultiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double tolerance = InpLevelTolerancePips * _Point * pipsMultiplier;
   
   datetime currentTime = time[rates_total - 1];
   int resistanceLinesChecked = 0;
   int validResistanceLines = 0;
   
   for(int i = 0; i < ArraySize(trendlines); i++)
   {
      if(!trendlines[i].isResistance)
         continue; // Skip support lines
      
      resistanceLinesChecked++;
      
      // Get the price level of this resistance trendline at current time
      double resistancePrice = CalculateTrendlinePrice(trendlines[i], currentTime);
      
      if(resistancePrice <= 0)
      {
         if(InpShowDebugInfo && resistanceLinesChecked <= 3) // Only log first few to avoid spam
            Print("FindNextResistance: Invalid price for trendline ", i, " - Price: ", resistancePrice);
         continue;
      }
      
      // Resistance must be above entry price
      if(resistancePrice <= entryPrice + tolerance)
      {
         if(InpShowDebugInfo && resistanceLinesChecked <= 3)
            Print("FindNextResistance: Resistance too close/below entry - Resistance: ", resistancePrice, " Entry: ", entryPrice);
         continue;
      }
      
      validResistanceLines++;
      double distance = resistancePrice - entryPrice;
      
      // Find the closest resistance above entry
      if(distance < minDistance && distance > 0)
      {
         minDistance = distance;
         nextResistance = resistancePrice;
      }
   }
   
   if(InpShowDebugInfo && nextResistance == 0)
      Print("FindNextResistance: No valid resistance found - Checked: ", resistanceLinesChecked, " Valid: ", validResistanceLines, " Entry: ", entryPrice);
   
   return nextResistance;
}

//+------------------------------------------------------------------+
//| Find nearest resistance level above entry price                 |
//+------------------------------------------------------------------+
double FindNearestResistance(double entryPrice, const int rates_total, datetime &time[])
{
   double nearestResistance = 0;
   double minDistance = DBL_MAX;
   double pipsMultiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double tolerance = InpLevelTolerancePips * _Point * pipsMultiplier;
   
   for(int i = 0; i < ArraySize(trendlines); i++)
   {
      if(!trendlines[i].isResistance)
         continue; // Skip support lines
      
      // Get the price level of this resistance trendline at current time
      datetime currentTime = time[rates_total - 1];
      double resistancePrice = CalculateTrendlinePrice(trendlines[i], currentTime);
      
      if(resistancePrice <= 0)
         continue;
      
      // Resistance must be above entry price
      if(resistancePrice <= entryPrice + tolerance)
         continue;
      
      double distance = resistancePrice - entryPrice;
      
      // Find the closest resistance above entry
      if(distance < minDistance && distance > 0)
      {
         minDistance = distance;
         nearestResistance = resistancePrice;
      }
   }
   
   return nearestResistance;
}

//+------------------------------------------------------------------+
//| Find next support level below entry price                       |
//+------------------------------------------------------------------+
double FindNextSupport(double entryPrice, const int rates_total, datetime &time[])
{
   double nextSupport = 0;
   double minDistance = DBL_MAX;
   double pipsMultiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double tolerance = InpLevelTolerancePips * _Point * pipsMultiplier;
   
   for(int i = 0; i < ArraySize(trendlines); i++)
   {
      if(trendlines[i].isResistance)
         continue; // Skip resistance lines
      
      // Get the price level of this support trendline at current time
      datetime currentTime = time[rates_total - 1];
      double supportPrice = CalculateTrendlinePrice(trendlines[i], currentTime);
      
      if(supportPrice <= 0)
         continue;
      
      // Support must be below entry price
      if(supportPrice >= entryPrice - tolerance)
         continue;
      
      double distance = entryPrice - supportPrice;
      
      // Find the closest support below entry
      if(distance < minDistance && distance > 0)
      {
         minDistance = distance;
         nextSupport = supportPrice;
      }
   }
   
   return nextSupport;
}

//+------------------------------------------------------------------+
//| Execute real BUY trade                                           |
//+------------------------------------------------------------------+
bool ExecuteBuyTrade(double entryPrice, double stopLoss, double takeProfit)
{
   //--- Get symbol info
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   
   //--- Normalize prices properly
   double normalizedSL = NormalizeDouble(stopLoss, digits);
   double normalizedTP = NormalizeDouble(takeProfit, digits);
   
   //--- Validate SL/TP distances from current price
   if(normalizedSL >= ask - minStopLevel)
   {
      normalizedSL = NormalizeDouble(ask - minStopLevel - point, digits);
      if(InpShowDebugInfo)
         Print("BUY Trade: Adjusted SL to minimum stop level: ", normalizedSL);
   }
   
   if(normalizedTP <= ask + minStopLevel)
   {
      normalizedTP = NormalizeDouble(ask + minStopLevel + point, digits);
      if(InpShowDebugInfo)
         Print("BUY Trade: Adjusted TP to minimum stop level: ", normalizedTP);
   }
   
   //--- Final validation
   if(normalizedSL >= ask || normalizedTP <= ask)
   {
      if(InpShowDebugInfo)
         Print("BUY Trade: Invalid SL/TP after normalization - Ask: ", ask, " SL: ", normalizedSL, " TP: ", normalizedTP);
      return false;
   }
   
   //--- Execute buy order
   bool result = trade.Buy(InpLotSize, _Symbol, 0, normalizedSL, normalizedTP, "Trendline Breakout BUY");
   
   //--- Wait a bit for order processing
   Sleep(100);
   
   //--- Check result
   if(!result)
   {
      uint retcode = trade.ResultRetcode();
      if(InpShowDebugInfo)
      {
         Print("BUY Trade Error: ", retcode, " - ", trade.ResultRetcodeDescription());
         Print("  Entry: ", DoubleToString(entryPrice, digits), " SL: ", DoubleToString(normalizedSL, digits), " TP: ", DoubleToString(normalizedTP, digits), " Lot: ", InpLotSize);
         Print("  Ask: ", DoubleToString(ask, digits), " Symbol: ", _Symbol, " Digits: ", digits);
         Print("  Min Stop Level: ", minStopLevel, " points");
      }
      
      //--- Retcode 0 might mean pending - check if order was actually placed
      if(retcode == 0)
      {
         // Check if we have a pending order
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong ticket = OrderGetTicket(i);
            if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            {
               if(InpShowDebugInfo)
                  Print("BUY Order found as pending - Ticket: ", ticket);
               return true; // Order exists, consider it successful
            }
         }
      }
   }
   else
   {
      if(InpShowDebugInfo)
      {
         ulong orderTicket = trade.ResultOrder();
         ulong dealTicket = trade.ResultDeal();
         Print("BUY Trade SUCCESS - Order: ", orderTicket, " Deal: ", dealTicket);
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Execute real SELL trade                                          |
//+------------------------------------------------------------------+
bool ExecuteSellTrade(double entryPrice, double stopLoss, double takeProfit)
{
   //--- Get symbol info
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   
   //--- Normalize prices properly
   double normalizedSL = NormalizeDouble(stopLoss, digits);
   double normalizedTP = NormalizeDouble(takeProfit, digits);
   
   //--- Validate SL/TP distances from current price
   if(normalizedSL <= bid + minStopLevel)
   {
      normalizedSL = NormalizeDouble(bid + minStopLevel + point, digits);
      if(InpShowDebugInfo)
         Print("SELL Trade: Adjusted SL to minimum stop level: ", normalizedSL);
   }
   
   if(normalizedTP >= bid - minStopLevel)
   {
      normalizedTP = NormalizeDouble(bid - minStopLevel - point, digits);
      if(InpShowDebugInfo)
         Print("SELL Trade: Adjusted TP to minimum stop level: ", normalizedTP);
   }
   
   //--- Final validation
   if(normalizedSL <= bid || normalizedTP >= bid)
   {
      if(InpShowDebugInfo)
         Print("SELL Trade: Invalid SL/TP after normalization - Bid: ", bid, " SL: ", normalizedSL, " TP: ", normalizedTP);
      return false;
   }
   
   //--- Execute sell order
   bool result = trade.Sell(InpLotSize, _Symbol, 0, normalizedSL, normalizedTP, "Trendline Breakout SELL");
   
   //--- Wait a bit for order processing
   Sleep(100);
   
   //--- Check result
   if(!result)
   {
      uint retcode = trade.ResultRetcode();
      if(InpShowDebugInfo)
      {
         Print("SELL Trade Error: ", retcode, " - ", trade.ResultRetcodeDescription());
         Print("  Entry: ", DoubleToString(entryPrice, digits), " SL: ", DoubleToString(normalizedSL, digits), " TP: ", DoubleToString(normalizedTP, digits), " Lot: ", InpLotSize);
         Print("  Bid: ", DoubleToString(bid, digits), " Symbol: ", _Symbol, " Digits: ", digits);
         Print("  Min Stop Level: ", minStopLevel, " points");
      }
      
      //--- Retcode 0 might mean pending - check if order was actually placed
      if(retcode == 0)
      {
         // Check if we have a pending order
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong ticket = OrderGetTicket(i);
            if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            {
               if(InpShowDebugInfo)
                  Print("SELL Order found as pending - Ticket: ", ticket);
               return true; // Order exists, consider it successful
            }
         }
      }
   }
   else
   {
      if(InpShowDebugInfo)
      {
         ulong orderTicket = trade.ResultOrder();
         ulong dealTicket = trade.ResultDeal();
         Print("SELL Trade SUCCESS - Order: ", orderTicket, " Deal: ", dealTicket);
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Check real trade status                                          |
//+------------------------------------------------------------------+
void CheckRealTradeStatus()
{
   if(currentTradeTicket == 0)
      return;
   
   //--- Check if position still exists
   if(!PositionSelectByTicket(currentTradeTicket))
   {
      //--- Position was closed (SL/TP hit or manually closed)
      if(InpShowDebugInfo)
      {
         Print("Real trade closed - Ticket: ", currentTradeTicket);
      }
      
      currentTradeTicket = 0;
      currentSignal.active = false;
      DeleteTradeSignalObjects();
      return;
   }
   
   //--- Position still open - check if we need to update SL/TP
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   
   //--- Update SL/TP if they differ from signal levels (trailing stop logic could go here)
   // For now, we just monitor - could add trailing stop logic later
}

//+------------------------------------------------------------------+
//| Close real trade                                                 |
//+------------------------------------------------------------------+
void CloseRealTrade()
{
   if(currentTradeTicket == 0)
      return;
   
   if(PositionSelectByTicket(currentTradeTicket))
   {
      bool result = trade.PositionClose(currentTradeTicket);
      
      if(result)
      {
         if(InpShowDebugInfo)
         {
            Print("Real trade closed successfully - Ticket: ", currentTradeTicket);
         }
      }
      else
      {
         if(InpShowDebugInfo)
         {
            Print("Failed to close real trade - Ticket: ", currentTradeTicket, " Error: ", trade.ResultRetcode());
         }
      }
   }
   
   currentTradeTicket = 0;
}

//+------------------------------------------------------------------+