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
input ENUM_TIMEFRAMES      TimeFrame = PERIOD_H1; // Timeframe for Analysis
input int                  RSI_Period = 14;           // RSI Period
input ENUM_APPLIED_PRICE   RSI_Applied_Price = PRICE_CLOSE; // RSI Applied Price
input double              RSI_Overbought = 90;        // RSI Overbought Level
input double              RSI_Oversold = 73;          // RSI Oversold Level
input double              RSI_Target_Buy = 88;         // RSI Target for Buy Exit
input double              RSI_Target_Sell = 48;        // RSI Target for Sell Exit
input int                 BarsToWait = 6;             // Bars to wait when RSI goes against position
input double              LotSize = 0.1;              // Lot Size
input int                 MagicNumber = 123459123;        // Magic Number
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
      return(INIT_FAILED);
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Allocate arrays
   ArraySetAsSeries(rsi_buffer, true);
   
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
      return;
   }
      
   // Check if this is a new bar
   datetime current_bar_time = iTime(_Symbol, TimeFrame, 0);
   if(current_bar_time == last_bar_time)
   {
      return;  // Still the same bar, don't process
   }
      
   last_bar_time = current_bar_time;
   
   // Update RSI values
   if(!UpdateRSI())
   {
      return;
   }
   
   // Check for existing position
   CheckExistingPosition();
   
   // Check for new entry signals
   if(!position_open)
   {
      CheckEntrySignals();
   }
}

//+------------------------------------------------------------------+
//| Update RSI values                                                |
//+------------------------------------------------------------------+
bool UpdateRSI()
{
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) < 3)
   {
      return false;
   }
   
   rsi_current = rsi_buffer[0];  // Current bar
   rsi_prev = rsi_buffer[1];     // Previous bar
   rsi_two_bars_ago = rsi_buffer[2];  // Two bars ago
   
   return true;
}

//+------------------------------------------------------------------+
//| Check existing position for exit conditions                     |
//+------------------------------------------------------------------+
void CheckExistingPosition()
{
   if(!position_open)
   {
      return;
   }
   
   // Check if position still exists
   if(!PositionSelectByTicket(position_ticket))
   {
      position_open = false;
      position_ticket = 0;
      rsi_against_position = false;
      bars_against_count = 0;
      return;
   }
   
   // Exit conditions based on RSI target
   if(current_position_type == POSITION_TYPE_BUY)
   {
      // Check if RSI is against the position (below oversold)
      if(rsi_current < RSI_Oversold)
      {
         if(!rsi_against_position)
         {
            rsi_against_position = true;
            bars_against_count = 1;
         }
         else
         {
            bars_against_count++;
         }
         
         // Close position if RSI has been against for Y bars
         if(bars_against_count >= BarsToWait)
         {
            ClosePosition();
            return;
         }
      }
      else
      {
         // RSI is no longer against the position, reset counter
         if(rsi_against_position)
         {
            rsi_against_position = false;
            bars_against_count = 0;
         }
         
         // Exit long position when RSI reaches buy target
         if(rsi_current >= RSI_Target_Buy)
         {
            ClosePosition();
         }
      }
   }
   else if(current_position_type == POSITION_TYPE_SELL)
   {
      // Check if RSI is against the position (above overbought)
      if(rsi_current > RSI_Overbought)
      {
         if(!rsi_against_position)
         {
            rsi_against_position = true;
            bars_against_count = 1;
         }
         else
         {
            bars_against_count++;
         }
         
         // Close position if RSI has been against for Y bars
         if(bars_against_count >= BarsToWait)
         {
            ClosePosition();
            return;
         }
      }
      else
      {
         // RSI is no longer against the position, reset counter
         if(rsi_against_position)
         {
            rsi_against_position = false;
            bars_against_count = 0;
         }
         
         // Exit short position when RSI reaches sell target
         if(rsi_current <= RSI_Target_Sell)
         {
            ClosePosition();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   // Buy signal: RSI crosses from oversold to above oversold (checking the actual crossover)
   if(rsi_two_bars_ago <= RSI_Oversold && rsi_prev > RSI_Oversold)
   {
      OpenBuyPosition();
   }
   
   // Sell signal: RSI crosses from overbought to below overbought (checking the actual crossover)
   if(rsi_two_bars_ago >= RSI_Overbought && rsi_prev < RSI_Overbought)
   {
      OpenSellPosition();
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(trade.Buy(LotSize, _Symbol, ask, 0, 0, "RSI Scalping Buy"))
   {
      position_ticket = trade.ResultOrder();
      position_open = true;
      current_position_type = POSITION_TYPE_BUY;
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(trade.Sell(LotSize, _Symbol, bid, 0, 0, "RSI Scalping Sell"))
   {
      position_ticket = trade.ResultOrder();
      position_open = true;
      current_position_type = POSITION_TYPE_SELL;
   }
}

//+------------------------------------------------------------------+
//| Close current position                                           |
//+------------------------------------------------------------------+
void ClosePosition()
{
   if(trade.PositionClose(position_ticket))
   {
      position_open = false;
      position_ticket = 0;
      rsi_against_position = false;
      bars_against_count = 0;
   }
}
