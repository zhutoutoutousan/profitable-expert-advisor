//+------------------------------------------------------------------+
//|                                                  RSIScalping.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input ENUM_TIMEFRAMES      TimeFrame = PERIOD_M30; // Timeframe for Analysis
input int                  RSI_Period = 14;           // RSI Period
input ENUM_APPLIED_PRICE   RSI_Applied_Price = PRICE_CLOSE; // RSI Applied Price
input double              RSI_Overbought = 77;        // RSI Overbought Level
input double              RSI_Oversold = 10;          // RSI Oversold Level
input double              RSI_Target_Buy = 27;         // RSI Target for Buy Exit
input double              RSI_Target_Sell = 43;        // RSI Target for Sell Exit
input int                 BarsToWait = 14;             // Bars to wait when RSI goes against position
input double              LotSize = 0.1;              // Lot Size
input int                 MagicNumber = 12345;        // Magic Number
input int                 Slippage = 3;               // Slippage in points

//--- Global variables
CTrade trade;
int rsi_handle;
double rsi_buffer[];
double rsi_prev, rsi_current, rsi_two_bars_ago;
bool position_open = false;
int position_ticket = 0;
ENUM_POSITION_TYPE current_position_type = POSITION_TYPE_BUY;
datetime last_bar_time = 0;
bool rsi_against_position = false;
int bars_against_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize RSI indicator
   rsi_handle = iRSI(_Symbol, TimeFrame, RSI_Period, RSI_Applied_Price);
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Allocate arrays
   ArraySetAsSeries(rsi_buffer, true);
   
   Print("RSI Scalping EA initialized successfully on timeframe: ", EnumToString(TimeFrame));
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
   // Check if we have enough bars
   if(Bars(_Symbol, TimeFrame) < RSI_Period + 2)
   {
      Print("TRACE: Not enough bars. Bars=", Bars(_Symbol, TimeFrame), " RSI_Period+2=", RSI_Period+2);
      return;
   }
      
   // Check if this is a new bar
   datetime current_bar_time = iTime(_Symbol, TimeFrame, 0);
   if(current_bar_time == last_bar_time)
   {
      Print("TRACE: Same bar, skipping. current_bar_time=", current_bar_time, " last_bar_time=", last_bar_time);
      return;  // Still the same bar, don't process
   }
      
   Print("TRACE: New bar detected. current_bar_time=", current_bar_time, " last_bar_time=", last_bar_time);
   last_bar_time = current_bar_time;
   
   // Update RSI values
   if(!UpdateRSI())
   {
      Print("TRACE: Failed to update RSI values");
      return;
   }
   
   Print("TRACE: RSI values - Current=", rsi_current, " Previous=", rsi_prev);
   
   // Check for existing position
   CheckExistingPosition();
   
   // Check for new entry signals
   if(!position_open)
   {
      Print("TRACE: No position open, checking entry signals");
      CheckEntrySignals();
   }
   else
   {
      Print("TRACE: Position already open, skipping entry signals");
   }
}

//+------------------------------------------------------------------+
//| Update RSI values                                                |
//+------------------------------------------------------------------+
bool UpdateRSI()
{
   Print("TRACE: Updating RSI values...");
   
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) < 3)
   {
      Print("TRACE: Error copying RSI data. Copied=", CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer));
      return false;
   }
   
   rsi_current = rsi_buffer[0];  // Current bar
   rsi_prev = rsi_buffer[1];     // Previous bar
   rsi_two_bars_ago = rsi_buffer[2];  // Two bars ago
   
   Print("TRACE: RSI buffer values - [0]=", rsi_buffer[0], " [1]=", rsi_buffer[1], " [2]=", rsi_buffer[2]);
   
   return true;
}

//+------------------------------------------------------------------+
//| Check existing position for exit conditions                     |
//+------------------------------------------------------------------+
void CheckExistingPosition()
{
   if(!position_open)
   {
      Print("TRACE: No position open, skipping position check");
      return;
   }
      
   Print("TRACE: Checking existing position. Ticket=", position_ticket, " Type=", (current_position_type == POSITION_TYPE_BUY ? "BUY" : "SELL"));
   
   // Check if position still exists
   if(!PositionSelectByTicket(position_ticket))
   {
      Print("TRACE: Position no longer exists, resetting state");
      position_open = false;
      position_ticket = 0;
      rsi_against_position = false;
      bars_against_count = 0;
      return;
   }
   
   // Exit conditions based on RSI target
   if(current_position_type == POSITION_TYPE_BUY)
   {
      Print("TRACE: Checking BUY position exit - rsi_current=", rsi_current, " RSI_Target_Buy=", RSI_Target_Buy, " RSI_Oversold=", RSI_Oversold);
      
      // Check if RSI is against the position (below oversold)
      if(rsi_current < RSI_Oversold)
      {
         if(!rsi_against_position)
         {
            Print("TRACE: RSI went against BUY position (below oversold), starting counter");
            rsi_against_position = true;
            bars_against_count = 1;
         }
         else
         {
            bars_against_count++;
            Print("TRACE: RSI still against BUY position. Bars against: ", bars_against_count, "/", BarsToWait);
         }
         
         // Close position if RSI has been against for Y bars
         if(bars_against_count >= BarsToWait)
         {
            Print("TRACE: RSI against BUY position for ", BarsToWait, " bars, closing position!");
            ClosePosition();
            return;
         }
      }
      else
      {
         // RSI is no longer against the position, reset counter
         if(rsi_against_position)
         {
            Print("TRACE: RSI no longer against BUY position, resetting counter");
            rsi_against_position = false;
            bars_against_count = 0;
         }
         
         // Exit long position when RSI reaches buy target
         if(rsi_current >= RSI_Target_Buy)
         {
            Print("TRACE: BUY position target reached!");
            ClosePosition();
         }
         else
         {
            Print("TRACE: BUY position exit condition not met");
         }
      }
   }
   else if(current_position_type == POSITION_TYPE_SELL)
   {
      Print("TRACE: Checking SELL position exit - rsi_current=", rsi_current, " RSI_Target_Sell=", RSI_Target_Sell, " RSI_Overbought=", RSI_Overbought);
      
      // Check if RSI is against the position (above overbought)
      if(rsi_current > RSI_Overbought)
      {
         if(!rsi_against_position)
         {
            Print("TRACE: RSI went against SELL position (above overbought), starting counter");
            rsi_against_position = true;
            bars_against_count = 1;
         }
         else
         {
            bars_against_count++;
            Print("TRACE: RSI still against SELL position. Bars against: ", bars_against_count, "/", BarsToWait);
         }
         
         // Close position if RSI has been against for Y bars
         if(bars_against_count >= BarsToWait)
         {
            Print("TRACE: RSI against SELL position for ", BarsToWait, " bars, closing position!");
            ClosePosition();
            return;
         }
      }
      else
      {
         // RSI is no longer against the position, reset counter
         if(rsi_against_position)
         {
            Print("TRACE: RSI no longer against SELL position, resetting counter");
            rsi_against_position = false;
            bars_against_count = 0;
         }
         
         // Exit short position when RSI reaches sell target
         if(rsi_current <= RSI_Target_Sell)
         {
            Print("TRACE: SELL position target reached!");
            ClosePosition();
         }
         else
         {
            Print("TRACE: SELL position exit condition not met");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   Print("TRACE: Checking entry signals...");
   Print("TRACE: Buy condition - rsi_two_bars_ago <= RSI_Oversold && rsi_prev > RSI_Oversold");
   Print("TRACE: Buy condition values - rsi_two_bars_ago=", rsi_two_bars_ago, " <= ", RSI_Oversold, " && rsi_prev=", rsi_prev, " > ", RSI_Oversold);
   
   // Buy signal: RSI crosses from oversold to above oversold (checking the actual crossover)
   if(rsi_two_bars_ago <= RSI_Oversold && rsi_prev > RSI_Oversold)
   {
      Print("TRACE: Buy signal detected!");
      OpenBuyPosition();
   }
   else
   {
      Print("TRACE: Buy signal condition not met");
   }
   
   Print("TRACE: Sell condition - rsi_two_bars_ago >= RSI_Overbought && rsi_prev < RSI_Overbought");
   Print("TRACE: Sell condition values - rsi_two_bars_ago=", rsi_two_bars_ago, " >= ", RSI_Overbought, " && rsi_prev=", rsi_prev, " < ", RSI_Overbought);
   
   // Sell signal: RSI crosses from overbought to below overbought (checking the actual crossover)
   if(rsi_two_bars_ago >= RSI_Overbought && rsi_prev < RSI_Overbought)
   {
      Print("TRACE: Sell signal detected!");
      OpenSellPosition();
   }
   else
   {
      Print("TRACE: Sell signal condition not met");
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   Print("TRACE: Attempting to open buy position...");
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   Print("TRACE: Current ask price=", ask, " LotSize=", LotSize);
   
   if(trade.Buy(LotSize, _Symbol, ask, 0, 0, "RSI Scalping Buy"))
   {
      position_ticket = trade.ResultOrder();
      position_open = true;
      current_position_type = POSITION_TYPE_BUY;
      Print("TRACE: Buy position opened successfully! Ticket=", position_ticket, " Price=", ask);
   }
   else
   {
      Print("TRACE: Error opening buy position. Retcode=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   Print("TRACE: Attempting to open sell position...");
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("TRACE: Current bid price=", bid, " LotSize=", LotSize);
   
   if(trade.Sell(LotSize, _Symbol, bid, 0, 0, "RSI Scalping Sell"))
   {
      position_ticket = trade.ResultOrder();
      position_open = true;
      current_position_type = POSITION_TYPE_SELL;
      Print("TRACE: Sell position opened successfully! Ticket=", position_ticket, " Price=", bid);
   }
   else
   {
      Print("TRACE: Error opening sell position. Retcode=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close current position                                           |
//+------------------------------------------------------------------+
void ClosePosition()
{
   Print("TRACE: Attempting to close position. Ticket=", position_ticket);
   
   if(trade.PositionClose(position_ticket))
   {
      Print("TRACE: Position closed successfully! Ticket=", position_ticket);
      position_open = false;
      position_ticket = 0;
      rsi_against_position = false;
      bars_against_count = 0;
   }
   else
   {
      Print("TRACE: Error closing position. Retcode=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
   }
}
