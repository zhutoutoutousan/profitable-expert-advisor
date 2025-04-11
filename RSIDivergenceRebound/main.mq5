//+------------------------------------------------------------------+
//|                                         RSIDivergenceRebound.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Input Parameters
input int      RSI_Period = 14;           // RSI Period
input int      RSI_Overbought = 70;       // RSI Overbought Level
input int      RSI_Oversold = 30;         // RSI Oversold Level
input double   BaseLotSize = 0.01;        // Base Lot Size
input int      ATR_Period = 14;           // ATR Period
input double   ATR_SL_Multiplier = 3.0;   // ATR Stop Loss Multiplier
input double   ATR_TP_Multiplier = 10.0;   // ATR Take Profit Multiplier
input int      MaxSpread = 50;            // Maximum Spread in Points
input int      DivergenceLookback = 9;    // Number of bars to look back for divergence
input int      MinTradeInterval = 30;     // Minimum minutes between trades
input double   MaxRiskPercent = 2.0;      // Maximum risk per trade (% of balance)
input double   MaxDrawdownPercent = 10.0; // Maximum drawdown before reset (% of balance)
input int      MaxConsecutiveLosses = 3;  // Maximum consecutive losses before reset
input double   MaxLotSize = 0.1;          // Maximum allowed lot size
input bool     UseRegularDivergence = true; // Use regular divergence for reversals
input bool     UseHiddenDivergence = true;  // Use hidden divergence for continuations
input int      RSI_ConfirmationBars = 19;  // Number of bars to confirm RSI pattern

// Global Variables
int rsiHandle;                            // RSI indicator handle
int atrHandle;                            // ATR indicator handle
datetime lastTradeTime = 0;               // Last trade time
datetime lastDebugTime = 0;               // Last debug message time
double currentLotSize = 0;                // Current lot size
bool lastTradeWasWin = false;             // Flag for last trade result
int consecutiveLosses = 0;                // Count of consecutive losses
double initialBalance = 0;                // Initial account balance
double maxBalance = 0;                    // Maximum balance reached

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   rsiHandle = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_H1, ATR_Period);
   
   if(rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   // Initialize variables
   currentLotSize = BaseLotSize;
   lastTradeWasWin = false;
   lastTradeTime = 0;
   consecutiveLosses = 0;
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxBalance = initialBalance;
   
   Print("RSI Divergence Rebound Strategy Initialized");
   Print("Base Lot Size: ", BaseLotSize);
   Print("RSI Period: ", RSI_Period, ", ATR Period: ", ATR_Period);
   Print("Max Risk per Trade: ", MaxRiskPercent, "%");
   Print("Max Drawdown: ", MaxDrawdownPercent, "%");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Get ATR value for stop loss and take profit calculations         |
//+------------------------------------------------------------------+
double GetATRValue()
{
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1)
   {
      Print("Error copying ATR buffer");
      return 0;
   }
   
   return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Check for RSI divergence patterns                                |
//+------------------------------------------------------------------+
int CheckRSIDivergence()
{
   double rsiBuffer[];
   double highBuffer[];
   double lowBuffer[];
   
   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(highBuffer, true);
   ArraySetAsSeries(lowBuffer, true);
   
   if(CopyBuffer(rsiHandle, 0, 0, DivergenceLookback + 1, rsiBuffer) != DivergenceLookback + 1 ||
      CopyHigh(_Symbol, PERIOD_H1, 0, DivergenceLookback + 1, highBuffer) != DivergenceLookback + 1 ||
      CopyLow(_Symbol, PERIOD_H1, 0, DivergenceLookback + 1, lowBuffer) != DivergenceLookback + 1)
   {
      Print("Error copying data for divergence check");
      return 0;
   }
   
   // Check for regular bullish divergence (price makes lower low, RSI makes higher low)
   if(UseRegularDivergence)
   {
      for(int i = 1; i < DivergenceLookback; i++)
      {
         if(lowBuffer[i] < lowBuffer[i+1] && rsiBuffer[i] > rsiBuffer[i+1] &&
            rsiBuffer[i] > RSI_Oversold && rsiBuffer[i] < RSI_Overbought)
         {
            // Confirm RSI is making higher lows
            if(rsiBuffer[0] > rsiBuffer[1] && rsiBuffer[1] > rsiBuffer[2])
            {
               Print("Regular bullish divergence detected");
               return 1;  // Bullish signal
            }
         }
      }
      
      // Check for regular bearish divergence (price makes higher high, RSI makes lower high)
      for(int i = 1; i < DivergenceLookback; i++)
      {
         if(highBuffer[i] > highBuffer[i+1] && rsiBuffer[i] < rsiBuffer[i+1] &&
            rsiBuffer[i] > RSI_Oversold && rsiBuffer[i] < RSI_Overbought)
         {
            // Confirm RSI is making lower highs
            if(rsiBuffer[0] < rsiBuffer[1] && rsiBuffer[1] < rsiBuffer[2])
            {
               Print("Regular bearish divergence detected");
               return -1;  // Bearish signal
            }
         }
      }
   }
   
   // Check for hidden bullish divergence (price makes higher low, RSI makes lower low)
   if(UseHiddenDivergence)
   {
      for(int i = 1; i < DivergenceLookback; i++)
      {
         if(lowBuffer[i] > lowBuffer[i+1] && rsiBuffer[i] < rsiBuffer[i+1] &&
            rsiBuffer[i] > RSI_Oversold && rsiBuffer[i] < RSI_Overbought)
         {
            // Confirm RSI is making higher lows
            if(rsiBuffer[0] > rsiBuffer[1] && rsiBuffer[1] > rsiBuffer[2])
            {
               Print("Hidden bullish divergence detected");
               return 1;  // Bullish signal
            }
         }
      }
      
      // Check for hidden bearish divergence (price makes lower high, RSI makes higher high)
      for(int i = 1; i < DivergenceLookback; i++)
      {
         if(highBuffer[i] < highBuffer[i+1] && rsiBuffer[i] > rsiBuffer[i+1] &&
            rsiBuffer[i] > RSI_Oversold && rsiBuffer[i] < RSI_Overbought)
         {
            // Confirm RSI is making lower highs
            if(rsiBuffer[0] < rsiBuffer[1] && rsiBuffer[1] < rsiBuffer[2])
            {
               Print("Hidden bearish divergence detected");
               return -1;  // Bearish signal
            }
         }
      }
   }
   
   return 0;  // No signal
}

//+------------------------------------------------------------------+
//| Check if we can open a new position                              |
//+------------------------------------------------------------------+
bool CanOpenPosition()
{
   // Check spread
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > MaxSpread)
   {
      Print("Spread too high: ", currentSpread);
      return false;
   }
   
   // Check minimum time between trades
   datetime currentTime = TimeCurrent();
   if(currentTime - lastTradeTime < MinTradeInterval * 60)
   {
      Print("Minimum time between trades not reached - Time since last trade: ", 
            (currentTime - lastTradeTime) / 60, " minutes");
      return false;
   }
   
   // Check for existing positions
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            Print("Position already exists - Ticket: ", ticket);
            return false;
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open new position                                                |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_POSITION_TYPE posType)
{
   // Validate lot size before attempting to open position
   double maxLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double minLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if(currentLotSize > maxLotSize || currentLotSize < minLotSize)
   {
      currentLotSize = BaseLotSize;
      Print("Lot size out of limits - Resetting to base: ", currentLotSize);
   }
   
   // Calculate required margin for the position
   double marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * currentLotSize;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // If not enough margin, reduce lot size
   while(marginRequired > freeMargin && currentLotSize > minLotSize)
   {
      currentLotSize = NormalizeDouble(currentLotSize * 0.5, 2);
      marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * currentLotSize;
      Print("Insufficient margin - Reducing lot size to: ", currentLotSize);
   }
   
   // If still not enough margin, reset to base lot size
   if(marginRequired > freeMargin)
   {
      currentLotSize = BaseLotSize;
      marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL) * currentLotSize;
      Print("Still insufficient margin - Resetting to base lot size: ", currentLotSize);
   }
   
   // Get current ATR value
   double atrValue = GetATRValue();
   if(atrValue == 0)
   {
      Print("Error getting ATR value");
      return false;
   }
   
   double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = (posType == POSITION_TYPE_BUY) 
               ? price - (atrValue * ATR_SL_Multiplier)
               : price + (atrValue * ATR_SL_Multiplier);
   
   double tp = (posType == POSITION_TYPE_BUY) 
               ? price + (atrValue * ATR_TP_Multiplier)
               : price - (atrValue * ATR_TP_Multiplier);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = currentLotSize;
   request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 123456;
   
   // Set filling mode for XAUUSD
   request.type_filling = ORDER_FILLING_FOK;  // Fill or Kill
   
   // If FOK fails, try IOC
   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_IOC;  // Immediate or Cancel
      if(!OrderSend(request, result))
      {
         Print("Failed to open position. Error: ", GetLastError());
         return false;
      }
   }
   
   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Order failed. Return code: ", result.retcode);
      return false;
   }
   
   lastTradeTime = TimeCurrent();
   Print("Position opened successfully - Lot size: ", currentLotSize,
         ", ATR: ", atrValue,
         ", SL: ", sl,
         ", TP: ", tp);
   return true;
}

//+------------------------------------------------------------------+
//| Check if we need to reset due to drawdown or consecutive losses   |
//+------------------------------------------------------------------+
bool NeedToReset()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update maximum balance
   if(currentBalance > maxBalance)
      maxBalance = currentBalance;
   
   // Calculate current drawdown
   double drawdownPercent = ((maxBalance - currentEquity) / maxBalance) * 100.0;
   
   // Check if we've hit maximum drawdown
   if(drawdownPercent >= MaxDrawdownPercent)
   {
      Print("Maximum drawdown reached - Drawdown: ", drawdownPercent, "%");
      return true;
   }
   
   // Check if we've hit maximum consecutive losses
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("Maximum consecutive losses reached - Losses: ", consecutiveLosses);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for closed positions and update lot size                    |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
   static int lastTotal = 0;
   int currentTotal = PositionsTotal();
   
   // If we have fewer positions than before, a position was closed
   if(currentTotal < lastTotal)
   {
      // Check history for the last closed position
      HistorySelect(TimeCurrent() - 3600, TimeCurrent());
      int historyTotal = HistoryDealsTotal();
      
      if(historyTotal > 0)
      {
         ulong dealTicket = HistoryDealGetTicket(historyTotal - 1);
         if(dealTicket > 0)
         {
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            bool isWin = (dealProfit > 0);
            
            Print("Position closed - Profit: ", dealProfit, 
                  ", Win: ", isWin ? "Yes" : "No");
            
            if(isWin)
            {
               lastTradeWasWin = true;
               consecutiveLosses = 0;
            }
            else
            {
               lastTradeWasWin = false;
               consecutiveLosses++;
               
               // Check if we need to reset due to drawdown or consecutive losses
               if(NeedToReset())
               {
                  consecutiveLosses = 0;
                  Print("Reset triggered");
               }
            }
         }
      }
   }
   
   lastTotal = currentTotal;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentTime = TimeCurrent();
   
   // Print debug info every minute
   if(currentTime - lastDebugTime >= 60)
   {
      lastDebugTime = currentTime;
      Print("Current lot size: ", currentLotSize, 
            ", Last trade was win: ", lastTradeWasWin ? "Yes" : "No");
   }
   
   // Check for closed positions and update lot size
   CheckClosedPositions();
   
   // Check for entry signals
   if(CanOpenPosition())
   {
      int signal = CheckRSIDivergence();
      
      if(signal == 1)  // Bullish signal
      {
         Print("Opening buy position with lot size: ", currentLotSize);
         OpenPosition(POSITION_TYPE_BUY);
      }
      else if(signal == -1)  // Bearish signal
      {
         Print("Opening sell position with lot size: ", currentLotSize);
         OpenPosition(POSITION_TYPE_SELL);
      }
   }
}
