//+------------------------------------------------------------------+
//|                                                      UnitedEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "United EA - Runs multiple strategies on multiple instruments with instrument-specific parameters"

#include <Trade\Trade.mqh>
#include "MagicNumberHelpers.mqh"

//--- Strategy Selection
input bool EnableRSIScalping = true;          // Enable RSI Scalping Strategy
input bool EnableMeanReversion = true;         // Enable Mean Reversion Strategy
input bool EnableDarvasBox = true;             // Enable Darvas Box Strategy
input bool EnableRSICrossOver = true;          // Enable RSI Crossover Strategy
input bool EnableRSIMidPoint = true;           // Enable RSI Midpoint Strategy

//--- Instrument Selection for RSI Scalping (each with its own parameters)
input bool EnableRSI_XAUUSD = true;           // Enable RSI Scalping on XAUUSD
input bool EnableRSI_APPL = true;             // Enable RSI Scalping on APPL
input bool EnableRSI_BTCUSD = true;             // Enable RSI Scalping on BTCUSD
input bool EnableRSI_MSFT = true;             // Enable RSI Scalping on MSFT
input bool EnableRSI_NVDA = true;             // Enable RSI Scalping on NVDA
input bool EnableRSI_TSLA = true;             // Enable RSI Scalping on TSLA

//--- Magic Numbers for RSI Scalping (one per instrument)
input int MagicNumber_RSI_XAUUSD = 129102315;     // Magic Number for RSI Scalping XAUUSD
input int MagicNumber_RSI_APPL = 123457;           // Magic Number for RSI Scalping APPL
input int MagicNumber_RSI_BTCUSD = 123459123;     // Magic Number for RSI Scalping BTCUSD
input int MagicNumber_RSI_MSFT = 123456;           // Magic Number for RSI Scalping MSFT
input int MagicNumber_RSI_NVDA = 12345;           // Magic Number for RSI Scalping NVDA
input int MagicNumber_RSI_TSLA = 125421321;       // Magic Number for RSI Scalping TSLA

//--- Magic Numbers for Other Strategies
input int MagicNumber_MeanReversion = 12351;       // Magic Number for Mean Reversion
input int MagicNumber_DarvasBox = 135790;          // Magic Number for Darvas Box
input int MagicNumber_RSICrossOver = 123456;       // Magic Number for RSI Crossover
input int MagicNumber_RSIMidPoint = 123457;        // Magic Number for RSI Midpoint

//--- RSI Scalping Parameters: XAUUSD
input ENUM_TIMEFRAMES RSI_XAUUSD_TimeFrame = PERIOD_H1;
input int RSI_XAUUSD_Period = 14;
input double RSI_XAUUSD_Overbought = 71;
input double RSI_XAUUSD_Oversold = 57;
input double RSI_XAUUSD_Target_Buy = 80;
input double RSI_XAUUSD_Target_Sell = 57;
input int RSI_XAUUSD_BarsToWait = 4;
input double RSI_XAUUSD_LotSize = 0.1;

//--- RSI Scalping Parameters: APPL
input ENUM_TIMEFRAMES RSI_APPL_TimeFrame = PERIOD_M10;
input int RSI_APPL_Period = 14;
input double RSI_APPL_Overbought = 80;
input double RSI_APPL_Oversold = 78;
input double RSI_APPL_Target_Buy = 94;
input double RSI_APPL_Target_Sell = 44;
input int RSI_APPL_BarsToWait = 7;
input double RSI_APPL_LotSize = 25;

//--- RSI Scalping Parameters: BTCUSD
input ENUM_TIMEFRAMES RSI_BTCUSD_TimeFrame = PERIOD_H1;
input int RSI_BTCUSD_Period = 14;
input double RSI_BTCUSD_Overbought = 90;
input double RSI_BTCUSD_Oversold = 73;
input double RSI_BTCUSD_Target_Buy = 88;
input double RSI_BTCUSD_Target_Sell = 48;
input int RSI_BTCUSD_BarsToWait = 6;
input double RSI_BTCUSD_LotSize = 0.1;

//--- RSI Scalping Parameters: MSFT
input ENUM_TIMEFRAMES RSI_MSFT_TimeFrame = PERIOD_H3;
input int RSI_MSFT_Period = 14;
input double RSI_MSFT_Overbought = 19;
input double RSI_MSFT_Oversold = 50;
input double RSI_MSFT_Target_Buy = 71;
input double RSI_MSFT_Target_Sell = 70;
input int RSI_MSFT_BarsToWait = 1;
input double RSI_MSFT_LotSize = 50;

//--- RSI Scalping Parameters: NVDA
input ENUM_TIMEFRAMES RSI_NVDA_TimeFrame = PERIOD_M15;
input int RSI_NVDA_Period = 8;
input double RSI_NVDA_Overbought = 36;
input double RSI_NVDA_Oversold = 38;
input double RSI_NVDA_Target_Buy = 90;
input double RSI_NVDA_Target_Sell = 70;
input int RSI_NVDA_BarsToWait = 5;
input double RSI_NVDA_LotSize = 50;

//--- RSI Scalping Parameters: TSLA
input ENUM_TIMEFRAMES RSI_TSLA_TimeFrame = PERIOD_H1;
input int RSI_TSLA_Period = 14;
input double RSI_TSLA_Overbought = 54;
input double RSI_TSLA_Oversold = 73;
input double RSI_TSLA_Target_Buy = 87;
input double RSI_TSLA_Target_Sell = 33;
input int RSI_TSLA_BarsToWait = 1;
input double RSI_TSLA_LotSize = 50;

//--- Mean Reversion Parameters
input int EMA_Periode = 46;
input double PreisSchwelle = 600.0;
input double SteigungSchwelle = 80.0;
input int ÜberwachungTimeout = 800;
input double TrailingStop = 260.0;
input double MeanRev_LotSize = 0.03;
input ENUM_TIMEFRAMES MeanRev_Timeframe = PERIOD_H1;

//--- Structure for RSI Scalping Strategy Instance
struct RSIScalpingStrategy
{
   string symbol;
   int magic_number;
   ENUM_TIMEFRAMES timeframe;
   int period;
   double overbought;
   double oversold;
   double target_buy;
   double target_sell;
   int bars_to_wait;
   double lot_size;
   int rsi_handle;
   double rsi_buffer[];
   ulong position_ticket;
   bool position_open;
   bool buy_position_open;
   bool sell_position_open;
   datetime last_bar_time;
   bool rsi_against_position;
   int bars_against_count;
   ENUM_POSITION_TYPE current_position_type;
};

//--- Global variables
CTrade trade;
RSIScalpingStrategy rsi_strategies[6];  // Array for 6 instruments
int rsi_strategy_count = 0;

int ema_handle_meanrev = INVALID_HANDLE;
double ema_array[];
ulong meanrev_ticket = 0;
bool meanrev_position_open = false;
datetime last_bar_time_meanrev = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Initialize RSI Scalping strategies for each enabled instrument
   if(EnableRSIScalping)
   {
      if(EnableRSI_XAUUSD)
      {
         InitializeRSIStrategy("XAUUSD", MagicNumber_RSI_XAUUSD, 
                               RSI_XAUUSD_TimeFrame, RSI_XAUUSD_Period,
                               RSI_XAUUSD_Overbought, RSI_XAUUSD_Oversold,
                               RSI_XAUUSD_Target_Buy, RSI_XAUUSD_Target_Sell,
                               RSI_XAUUSD_BarsToWait, RSI_XAUUSD_LotSize);
      }
      
      if(EnableRSI_APPL)
      {
         // Try different symbol variations for Apple (Pepperstone typically uses AAPL without suffix)
         // Try: AAPL, AAPL.US, APPL (in case of typo in broker)
         string appl_symbol = GetValidSymbol("AAPL", "AAPL.US");
         if(appl_symbol != "")
         {
            InitializeRSIStrategy(appl_symbol, MagicNumber_RSI_APPL,
                                  RSI_APPL_TimeFrame, RSI_APPL_Period,
                                  RSI_APPL_Overbought, RSI_APPL_Oversold,
                                  RSI_APPL_Target_Buy, RSI_APPL_Target_Sell,
                                  RSI_APPL_BarsToWait, RSI_APPL_LotSize);
         }
         else
         {
            Print("Skipping AAPL strategy - symbol not available");
         }
      }
      
      if(EnableRSI_BTCUSD)
      {
         InitializeRSIStrategy("BTCUSD", MagicNumber_RSI_BTCUSD,
                               RSI_BTCUSD_TimeFrame, RSI_BTCUSD_Period,
                               RSI_BTCUSD_Overbought, RSI_BTCUSD_Oversold,
                               RSI_BTCUSD_Target_Buy, RSI_BTCUSD_Target_Sell,
                               RSI_BTCUSD_BarsToWait, RSI_BTCUSD_LotSize);
      }
      
      if(EnableRSI_MSFT)
      {
         // Pepperstone typically uses MSFT without suffix
         string msft_symbol = GetValidSymbol("MSFT", "MSFT.US");
         if(msft_symbol != "")
         {
            InitializeRSIStrategy(msft_symbol, MagicNumber_RSI_MSFT,
                                  RSI_MSFT_TimeFrame, RSI_MSFT_Period,
                                  RSI_MSFT_Overbought, RSI_MSFT_Oversold,
                                  RSI_MSFT_Target_Buy, RSI_MSFT_Target_Sell,
                                  RSI_MSFT_BarsToWait, RSI_MSFT_LotSize);
         }
         else
         {
            Print("Skipping MSFT strategy - symbol not available");
         }
      }
      
      if(EnableRSI_NVDA)
      {
         // Pepperstone typically uses NVDA without suffix
         string nvda_symbol = GetValidSymbol("NVDA", "NVDA.US");
         if(nvda_symbol != "")
         {
            InitializeRSIStrategy(nvda_symbol, MagicNumber_RSI_NVDA,
                                  RSI_NVDA_TimeFrame, RSI_NVDA_Period,
                                  RSI_NVDA_Overbought, RSI_NVDA_Oversold,
                                  RSI_NVDA_Target_Buy, RSI_NVDA_Target_Sell,
                                  RSI_NVDA_BarsToWait, RSI_NVDA_LotSize);
         }
         else
         {
            Print("Skipping NVDA strategy - symbol not available");
         }
      }
      
      if(EnableRSI_TSLA)
      {
         // Pepperstone typically uses TSLA without suffix
         string tsla_symbol = GetValidSymbol("TSLA", "TSLA.US");
         if(tsla_symbol != "")
         {
            InitializeRSIStrategy(tsla_symbol, MagicNumber_RSI_TSLA,
                                  RSI_TSLA_TimeFrame, RSI_TSLA_Period,
                                  RSI_TSLA_Overbought, RSI_TSLA_Oversold,
                                  RSI_TSLA_Target_Buy, RSI_TSLA_Target_Sell,
                                  RSI_TSLA_BarsToWait, RSI_TSLA_LotSize);
         }
         else
         {
            Print("Skipping TSLA strategy - symbol not available");
         }
      }
   }
   
   // Initialize Mean Reversion indicator
   if(EnableMeanReversion)
   {
      ema_handle_meanrev = iMA(_Symbol, MeanRev_Timeframe, EMA_Periode, 0, MODE_EMA, PRICE_CLOSE);
      if(ema_handle_meanrev == INVALID_HANDLE)
      {
         Print("Error: Failed to create EMA indicator for Mean Reversion");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(ema_array, true);
      trade.SetExpertMagicNumber(MagicNumber_MeanReversion);
      Print("Mean Reversion Strategy initialized with Magic: ", MagicNumber_MeanReversion);
   }
   
   Print("United EA initialized successfully");
   Print("Active RSI Scalping Strategies: ", rsi_strategy_count);
   for(int i = 0; i < rsi_strategy_count; i++)
   {
      Print("  - ", rsi_strategies[i].symbol, " (Magic: ", rsi_strategies[i].magic_number, 
            ", TF: ", EnumToString(rsi_strategies[i].timeframe), ")");
   }
   if(EnableMeanReversion) Print("  - Mean Reversion (Magic: ", MagicNumber_MeanReversion, ")");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get valid symbol name (try variations)                            |
//+------------------------------------------------------------------+
string GetValidSymbol(string preferred, string fallback)
{
   string symbols_to_try[];
   ArrayResize(symbols_to_try, 0);
   
   // Build list of symbols to try
   ArrayResize(symbols_to_try, 1);
   symbols_to_try[0] = preferred;
   
   if(fallback != preferred)
   {
      ArrayResize(symbols_to_try, 2);
      symbols_to_try[1] = fallback;
   }
   
   // If preferred has .US, also try without it
   if(StringFind(preferred, ".US") >= 0)
   {
      string without_suffix = preferred;
      StringReplace(without_suffix, ".US", "");
      if(without_suffix != fallback)
      {
         int size = ArraySize(symbols_to_try);
         ArrayResize(symbols_to_try, size + 1);
         symbols_to_try[size] = without_suffix;
      }
   }
   
   // Try each symbol variation
   for(int i = 0; i < ArraySize(symbols_to_try); i++)
   {
      string test_symbol = symbols_to_try[i];
      
      // Try to select the symbol
      if(!SymbolSelect(test_symbol, true))
      {
         // Symbol might already be selected, check if it exists
         if(!SymbolInfoInteger(test_symbol, SYMBOL_SELECT))
         {
            continue; // Symbol doesn't exist, try next
         }
      }
      
      // Verify symbol is visible
      if(SymbolInfoInteger(test_symbol, SYMBOL_VISIBLE))
      {
         // Check if we can get price data (symbol is really available)
         // During initialization, prices might be 0 if symbol is still synchronizing
         // So we'll be lenient and accept the symbol if it's visible
         double bid = SymbolInfoDouble(test_symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(test_symbol, SYMBOL_ASK);
         
         // Accept symbol if it has valid prices OR if it's visible (might be syncing)
         if((bid > 0 && ask > 0) || SymbolInfoInteger(test_symbol, SYMBOL_VISIBLE))
         {
            if(bid > 0 && ask > 0)
            {
               Print("Using symbol: ", test_symbol, " (Bid: ", bid, ", Ask: ", ask, ")");
            }
            else
            {
               Print("Using symbol: ", test_symbol, " (synchronizing, prices not yet available)");
            }
            return test_symbol;
         }
      }
   }
   
   Print("Error: Could not find valid symbol for ", preferred, " or ", fallback);
   Print("Tried ", ArraySize(symbols_to_try), " symbol variations:");
   for(int i = 0; i < ArraySize(symbols_to_try); i++)
   {
      Print("  ", (i+1), ". ", symbols_to_try[i]);
   }
   Print("These symbols may not be available in your broker's symbol list.");
   Print("Please add the symbol to Market Watch or disable this strategy.");
   
   return ""; // Return empty string to indicate failure
}

//+------------------------------------------------------------------+
//| Initialize RSI Scalping Strategy for an instrument               |
//+------------------------------------------------------------------+
void InitializeRSIStrategy(string symbol, int magic, ENUM_TIMEFRAMES tf, int period,
                          double overbought, double oversold, double target_buy, 
                          double target_sell, int bars_wait, double lot_size)
{
   if(rsi_strategy_count >= 6)
   {
      Print("Error: Maximum 6 RSI strategies allowed");
      return;
   }
   
   // Work directly with array element (no reference)
   rsi_strategies[rsi_strategy_count].symbol = symbol;
   rsi_strategies[rsi_strategy_count].magic_number = magic;
   rsi_strategies[rsi_strategy_count].timeframe = tf;
   rsi_strategies[rsi_strategy_count].period = period;
   rsi_strategies[rsi_strategy_count].overbought = overbought;
   rsi_strategies[rsi_strategy_count].oversold = oversold;
   rsi_strategies[rsi_strategy_count].target_buy = target_buy;
   rsi_strategies[rsi_strategy_count].target_sell = target_sell;
   rsi_strategies[rsi_strategy_count].bars_to_wait = bars_wait;
   rsi_strategies[rsi_strategy_count].lot_size = lot_size;
   rsi_strategies[rsi_strategy_count].position_ticket = 0;
   rsi_strategies[rsi_strategy_count].position_open = false;
   rsi_strategies[rsi_strategy_count].buy_position_open = false;
   rsi_strategies[rsi_strategy_count].sell_position_open = false;
   rsi_strategies[rsi_strategy_count].last_bar_time = 0;
   rsi_strategies[rsi_strategy_count].rsi_against_position = false;
   rsi_strategies[rsi_strategy_count].bars_against_count = 0;
   rsi_strategies[rsi_strategy_count].current_position_type = WRONG_VALUE;
   
   // Ensure symbol is selected before creating indicator
   if(!SymbolSelect(symbol, true))
   {
      // Symbol might already be selected, check if it exists
      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
      {
         Print("Error: Failed to select symbol ", symbol, " for RSI indicator");
         Print("Please ensure the symbol exists in Market Watch or add it manually");
         return;
      }
   }
   
   // Verify symbol is visible (prices might be 0 during synchronization)
   if(!SymbolInfoInteger(symbol, SYMBOL_VISIBLE))
   {
      Print("Error: Symbol ", symbol, " is not visible");
      Print("Please add the symbol to Market Watch");
      return;
   }
   
   // Check prices (but don't fail if they're 0 - symbol might be syncing)
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0)
   {
      Print("Warning: Symbol ", symbol, " has no prices yet (Bid: ", bid, ", Ask: ", ask, ")");
      Print("Symbol may be synchronizing. Will attempt to create indicator anyway...");
   }
   
   // Create RSI indicator for this symbol
   rsi_strategies[rsi_strategy_count].rsi_handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(rsi_strategies[rsi_strategy_count].rsi_handle == INVALID_HANDLE)
   {
      int error = GetLastError();
      Print("Error: Failed to create RSI indicator for ", symbol, " (Error: ", error, ")");
      Print("Symbol: ", symbol, ", Timeframe: ", EnumToString(tf), ", Period: ", period);
      Print("Please check if the symbol is available in your broker's symbol list");
      return;
   }
   
   ArraySetAsSeries(rsi_strategies[rsi_strategy_count].rsi_buffer, true);
   rsi_strategy_count++;
   
   Print("RSI Scalping Strategy initialized for ", symbol, 
         " (Magic: ", magic, ", TF: ", EnumToString(tf), ")");
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release all RSI indicators
   for(int i = 0; i < rsi_strategy_count; i++)
   {
      if(rsi_strategies[i].rsi_handle != INVALID_HANDLE)
         IndicatorRelease(rsi_strategies[i].rsi_handle);
   }
   
   if(ema_handle_meanrev != INVALID_HANDLE)
      IndicatorRelease(ema_handle_meanrev);
   
   Print("United EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Run RSI Scalping Strategies for all enabled instruments
   if(EnableRSIScalping)
   {
      for(int i = 0; i < rsi_strategy_count; i++)
      {
         RunRSIScalpingStrategy(i);
      }
   }
   
   // Run Mean Reversion Strategy
   if(EnableMeanReversion)
   {
      RunMeanReversionStrategy();
   }
}

//+------------------------------------------------------------------+
//| RSI Scalping Strategy for a specific instrument (by index)      |
//+------------------------------------------------------------------+
void RunRSIScalpingStrategy(int strategy_index)
{
   // Access strategy by index (no reference needed)
   // Check if we have enough bars
   if(Bars(rsi_strategies[strategy_index].symbol, rsi_strategies[strategy_index].timeframe) < 
      rsi_strategies[strategy_index].period + 2)
      return;
   
   // Check if this is a new bar
   datetime current_bar_time = iTime(rsi_strategies[strategy_index].symbol, 
                                     rsi_strategies[strategy_index].timeframe, 0);
   if(current_bar_time == rsi_strategies[strategy_index].last_bar_time)
      return;
   
   rsi_strategies[strategy_index].last_bar_time = current_bar_time;
   
   // Update RSI values
   if(CopyBuffer(rsi_strategies[strategy_index].rsi_handle, 0, 0, 3, 
                 rsi_strategies[strategy_index].rsi_buffer) < 3)
      return;
   
   double rsi_current = rsi_strategies[strategy_index].rsi_buffer[0];
   double rsi_prev = rsi_strategies[strategy_index].rsi_buffer[1];
   double rsi_two_bars_ago = rsi_strategies[strategy_index].rsi_buffer[2];
   
   // Set magic number for this strategy
   trade.SetExpertMagicNumber(rsi_strategies[strategy_index].magic_number);
   
   // Check if position exists (regardless of flag state - handles EA restart)
   bool position_exists = PositionExistsByMagic(rsi_strategies[strategy_index].symbol, 
                                               rsi_strategies[strategy_index].magic_number);
   
   if(position_exists)
   {
      // Get actual position type and ticket
      ulong ticket = GetPositionTicketByMagic(rsi_strategies[strategy_index].symbol, 
                                              rsi_strategies[strategy_index].magic_number);
      ENUM_POSITION_TYPE pos_type = GetPositionTypeByMagic(rsi_strategies[strategy_index].symbol, 
                                                          rsi_strategies[strategy_index].magic_number);
      
      if(ticket == 0 || pos_type == WRONG_VALUE)
      {
         // Position doesn't exist or invalid
         rsi_strategies[strategy_index].position_open = false;
         rsi_strategies[strategy_index].buy_position_open = false;
         rsi_strategies[strategy_index].sell_position_open = false;
         rsi_strategies[strategy_index].position_ticket = 0;
         rsi_strategies[strategy_index].rsi_against_position = false;
         rsi_strategies[strategy_index].bars_against_count = 0;
         return;
      }
      
      // Update position tracking with fine-grained flags
      rsi_strategies[strategy_index].position_ticket = ticket;
      rsi_strategies[strategy_index].position_open = true;
      rsi_strategies[strategy_index].current_position_type = pos_type;
      
      if(pos_type == POSITION_TYPE_BUY)
      {
         rsi_strategies[strategy_index].buy_position_open = true;
         rsi_strategies[strategy_index].sell_position_open = false;
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         rsi_strategies[strategy_index].buy_position_open = false;
         rsi_strategies[strategy_index].sell_position_open = true;
      }
      
      // Verify position still exists with correct ticket, symbol, and magic number
      if(!PositionSelectByTicketSymbolAndMagic(rsi_strategies[strategy_index].position_ticket,
                                               rsi_strategies[strategy_index].symbol,
                                               rsi_strategies[strategy_index].magic_number))
      {
         // Position was closed externally or doesn't match this instrument, reset tracking
         rsi_strategies[strategy_index].position_open = false;
         rsi_strategies[strategy_index].buy_position_open = false;
         rsi_strategies[strategy_index].sell_position_open = false;
         rsi_strategies[strategy_index].position_ticket = 0;
         rsi_strategies[strategy_index].rsi_against_position = false;
         rsi_strategies[strategy_index].bars_against_count = 0;
         return;
      }
      
      // Double-check position type matches our tracking (instrument-specific verification)
      ENUM_POSITION_TYPE actual_pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string actual_symbol = PositionGetString(POSITION_SYMBOL);
      
      if(actual_symbol != rsi_strategies[strategy_index].symbol)
      {
         Print("Warning: Position symbol mismatch for ", rsi_strategies[strategy_index].symbol, 
               " - Found: ", actual_symbol, ". Resetting tracking.");
         rsi_strategies[strategy_index].position_open = false;
         rsi_strategies[strategy_index].buy_position_open = false;
         rsi_strategies[strategy_index].sell_position_open = false;
         rsi_strategies[strategy_index].position_ticket = 0;
         rsi_strategies[strategy_index].rsi_against_position = false;
         rsi_strategies[strategy_index].bars_against_count = 0;
         return;
      }
      
      // Update position type if it changed (shouldn't happen, but safety check)
      if(actual_pos_type != pos_type)
      {
         Print("Warning: Position type changed for ", rsi_strategies[strategy_index].symbol, 
               " - Updating from ", EnumToString(pos_type), " to ", EnumToString(actual_pos_type));
         pos_type = actual_pos_type;
         rsi_strategies[strategy_index].current_position_type = pos_type;
         
         if(pos_type == POSITION_TYPE_BUY)
         {
            rsi_strategies[strategy_index].buy_position_open = true;
            rsi_strategies[strategy_index].sell_position_open = false;
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            rsi_strategies[strategy_index].buy_position_open = false;
            rsi_strategies[strategy_index].sell_position_open = true;
         }
      }
      
      if(pos_type == POSITION_TYPE_BUY)
      {
         // Check if RSI is against the position (below oversold)
         if(rsi_current < rsi_strategies[strategy_index].oversold)
         {
            if(!rsi_strategies[strategy_index].rsi_against_position)
            {
               rsi_strategies[strategy_index].rsi_against_position = true;
               rsi_strategies[strategy_index].bars_against_count = 1;
            }
            else
            {
               rsi_strategies[strategy_index].bars_against_count++;
            }
            
            // Close position if RSI has been against for Y bars
            if(rsi_strategies[strategy_index].bars_against_count >= 
               rsi_strategies[strategy_index].bars_to_wait)
            {
               if(ClosePositionByMagic(trade, rsi_strategies[strategy_index].symbol, 
                                      rsi_strategies[strategy_index].magic_number))
               {
                  rsi_strategies[strategy_index].position_open = false;
                  rsi_strategies[strategy_index].buy_position_open = false;
                  rsi_strategies[strategy_index].sell_position_open = false;
                  rsi_strategies[strategy_index].position_ticket = 0;
                  rsi_strategies[strategy_index].rsi_against_position = false;
                  rsi_strategies[strategy_index].bars_against_count = 0;
                  Print("Closed ", rsi_strategies[strategy_index].symbol, " BUY position - RSI against for ", 
                        rsi_strategies[strategy_index].bars_to_wait, " bars");
               }
               else
               {
                  Print("Failed to close ", rsi_strategies[strategy_index].symbol, " BUY position - will retry");
               }
               return;
            }
         }
         else
         {
            // RSI is no longer against the position, reset counter
            if(rsi_strategies[strategy_index].rsi_against_position)
            {
               rsi_strategies[strategy_index].rsi_against_position = false;
               rsi_strategies[strategy_index].bars_against_count = 0;
            }
            
            // Exit long position when RSI reaches buy target
            if(rsi_current >= rsi_strategies[strategy_index].target_buy)
            {
               if(ClosePositionByMagic(trade, rsi_strategies[strategy_index].symbol, 
                                      rsi_strategies[strategy_index].magic_number))
               {
                  rsi_strategies[strategy_index].position_open = false;
                  rsi_strategies[strategy_index].buy_position_open = false;
                  rsi_strategies[strategy_index].sell_position_open = false;
                  rsi_strategies[strategy_index].position_ticket = 0;
                  rsi_strategies[strategy_index].rsi_against_position = false;
                  rsi_strategies[strategy_index].bars_against_count = 0;
                  Print("Closed ", rsi_strategies[strategy_index].symbol, " BUY position - RSI reached target: ", 
                        rsi_strategies[strategy_index].target_buy);
               }
               else
               {
                  Print("Failed to close ", rsi_strategies[strategy_index].symbol, " BUY position - will retry");
               }
            }
         }
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         // Check if RSI is against the position (above overbought)
         if(rsi_current > rsi_strategies[strategy_index].overbought)
         {
            if(!rsi_strategies[strategy_index].rsi_against_position)
            {
               rsi_strategies[strategy_index].rsi_against_position = true;
               rsi_strategies[strategy_index].bars_against_count = 1;
            }
            else
            {
               rsi_strategies[strategy_index].bars_against_count++;
            }
            
            // Close position if RSI has been against for Y bars
            if(rsi_strategies[strategy_index].bars_against_count >= 
               rsi_strategies[strategy_index].bars_to_wait)
            {
               if(ClosePositionByMagic(trade, rsi_strategies[strategy_index].symbol, 
                                      rsi_strategies[strategy_index].magic_number))
               {
                  rsi_strategies[strategy_index].position_open = false;
                  rsi_strategies[strategy_index].buy_position_open = false;
                  rsi_strategies[strategy_index].sell_position_open = false;
                  rsi_strategies[strategy_index].position_ticket = 0;
                  rsi_strategies[strategy_index].rsi_against_position = false;
                  rsi_strategies[strategy_index].bars_against_count = 0;
                  Print("Closed ", rsi_strategies[strategy_index].symbol, " SELL position - RSI against for ", 
                        rsi_strategies[strategy_index].bars_to_wait, " bars");
               }
               else
               {
                  Print("Failed to close ", rsi_strategies[strategy_index].symbol, " SELL position - will retry");
               }
               return;
            }
         }
         else
         {
            // RSI is no longer against the position, reset counter
            if(rsi_strategies[strategy_index].rsi_against_position)
            {
               rsi_strategies[strategy_index].rsi_against_position = false;
               rsi_strategies[strategy_index].bars_against_count = 0;
            }
            
            // Exit short position when RSI reaches sell target
            if(rsi_current <= rsi_strategies[strategy_index].target_sell)
            {
               if(ClosePositionByMagic(trade, rsi_strategies[strategy_index].symbol, 
                                      rsi_strategies[strategy_index].magic_number))
               {
                  rsi_strategies[strategy_index].position_open = false;
                  rsi_strategies[strategy_index].buy_position_open = false;
                  rsi_strategies[strategy_index].sell_position_open = false;
                  rsi_strategies[strategy_index].position_ticket = 0;
                  rsi_strategies[strategy_index].rsi_against_position = false;
                  rsi_strategies[strategy_index].bars_against_count = 0;
                  Print("Closed ", rsi_strategies[strategy_index].symbol, " SELL position - RSI reached target: ", 
                        rsi_strategies[strategy_index].target_sell);
               }
               else
               {
                  Print("Failed to close ", rsi_strategies[strategy_index].symbol, " SELL position - will retry");
               }
            }
         }
      }
   }
   else
   {
      // No position exists - reset all tracking flags
      rsi_strategies[strategy_index].position_open = false;
      rsi_strategies[strategy_index].buy_position_open = false;
      rsi_strategies[strategy_index].sell_position_open = false;
      rsi_strategies[strategy_index].position_ticket = 0;
      rsi_strategies[strategy_index].rsi_against_position = false;
      rsi_strategies[strategy_index].bars_against_count = 0;
      
      // Check for new entry signals (only if no position exists)
      if(!PositionExistsByMagic(rsi_strategies[strategy_index].symbol, 
                               rsi_strategies[strategy_index].magic_number))
      {
         // Buy signal: RSI crosses from oversold to above oversold
         // Only enter if we don't already have a buy position for THIS EA (magic number) on THIS INSTRUMENT
         if(!rsi_strategies[strategy_index].buy_position_open)
         {
            if(rsi_two_bars_ago <= rsi_strategies[strategy_index].oversold && 
               rsi_prev > rsi_strategies[strategy_index].oversold)
            {
               double ask = SymbolInfoDouble(rsi_strategies[strategy_index].symbol, SYMBOL_ASK);
               if(trade.Buy(rsi_strategies[strategy_index].lot_size, 
                           rsi_strategies[strategy_index].symbol, ask, 0, 0, 
                           "RSI Scalping Buy " + rsi_strategies[strategy_index].symbol))
               {
                  ulong new_ticket = trade.ResultOrder();
                  if(new_ticket > 0)
                  {
                     // Verify the position was actually opened for THIS SPECIFIC INSTRUMENT
                     if(PositionSelectByTicketSymbolAndMagic(new_ticket,
                                                            rsi_strategies[strategy_index].symbol,
                                                            rsi_strategies[strategy_index].magic_number))
                     {
                        rsi_strategies[strategy_index].position_ticket = new_ticket;
                        rsi_strategies[strategy_index].position_open = true;
                        rsi_strategies[strategy_index].buy_position_open = true;
                        rsi_strategies[strategy_index].sell_position_open = false;
                        rsi_strategies[strategy_index].current_position_type = POSITION_TYPE_BUY;
                        Print("Opened BUY position for ", rsi_strategies[strategy_index].symbol, 
                              " (Ticket: ", rsi_strategies[strategy_index].position_ticket, 
                              ", Magic: ", rsi_strategies[strategy_index].magic_number, ")");
                     }
                     else
                     {
                        Print("Error: Position opened but doesn't match instrument ", 
                              rsi_strategies[strategy_index].symbol, " - resetting tracking");
                        rsi_strategies[strategy_index].position_ticket = 0;
                        rsi_strategies[strategy_index].position_open = false;
                        rsi_strategies[strategy_index].buy_position_open = false;
                     }
                  }
               }
            }
         }
         
         // Sell signal: RSI crosses from overbought to below overbought
         // Only enter if we don't already have a sell position for THIS EA (magic number) on THIS INSTRUMENT
         if(!rsi_strategies[strategy_index].sell_position_open)
         {
            if(rsi_two_bars_ago >= rsi_strategies[strategy_index].overbought && 
               rsi_prev < rsi_strategies[strategy_index].overbought)
            {
               double bid = SymbolInfoDouble(rsi_strategies[strategy_index].symbol, SYMBOL_BID);
               if(trade.Sell(rsi_strategies[strategy_index].lot_size, 
                            rsi_strategies[strategy_index].symbol, bid, 0, 0, 
                            "RSI Scalping Sell " + rsi_strategies[strategy_index].symbol))
               {
                  ulong new_ticket = trade.ResultOrder();
                  if(new_ticket > 0)
                  {
                     // Verify the position was actually opened for THIS SPECIFIC INSTRUMENT
                     if(PositionSelectByTicketSymbolAndMagic(new_ticket,
                                                            rsi_strategies[strategy_index].symbol,
                                                            rsi_strategies[strategy_index].magic_number))
                     {
                        rsi_strategies[strategy_index].position_ticket = new_ticket;
                        rsi_strategies[strategy_index].position_open = true;
                        rsi_strategies[strategy_index].buy_position_open = false;
                        rsi_strategies[strategy_index].sell_position_open = true;
                        rsi_strategies[strategy_index].current_position_type = POSITION_TYPE_SELL;
                        Print("Opened SELL position for ", rsi_strategies[strategy_index].symbol, 
                              " (Ticket: ", rsi_strategies[strategy_index].position_ticket, 
                              ", Magic: ", rsi_strategies[strategy_index].magic_number, ")");
                     }
                     else
                     {
                        Print("Error: Position opened but doesn't match instrument ", 
                              rsi_strategies[strategy_index].symbol, " - resetting tracking");
                        rsi_strategies[strategy_index].position_ticket = 0;
                        rsi_strategies[strategy_index].position_open = false;
                        rsi_strategies[strategy_index].sell_position_open = false;
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Mean Reversion Strategy                                          |
//+------------------------------------------------------------------+
void RunMeanReversionStrategy()
{
   // Check if this is a new bar
   datetime current_bar_time = iTime(_Symbol, MeanRev_Timeframe, 0);
   if(current_bar_time == last_bar_time_meanrev)
      return;
   
   last_bar_time_meanrev = current_bar_time;
   
   // Update EMA values
   if(CopyBuffer(ema_handle_meanrev, 0, 0, 3, ema_array) < 3)
      return;
   
   double ema_current = ema_array[0];
   double ema_prev = ema_array[1];
   double current_close = iClose(_Symbol, MeanRev_Timeframe, 0);
   
   // Set magic number for this strategy
   trade.SetExpertMagicNumber(MagicNumber_MeanReversion);
   
   // Check existing position
   if(PositionExistsByMagic(_Symbol, MagicNumber_MeanReversion))
   {
      // Manage existing position (trailing stop, exit conditions, etc.)
      ManageMeanReversionPosition(ema_current, current_close);
   }
   else
   {
      // Check for new entry signals
      CheckMeanReversionEntry(ema_current, ema_prev, current_close);
   }
}

//+------------------------------------------------------------------+
//| Manage Mean Reversion Position                                   |
//+------------------------------------------------------------------+
void ManageMeanReversionPosition(double ema_current, double current_close)
{
   if(!PositionSelectByMagic(_Symbol, MagicNumber_MeanReversion))
      return;
   
   double position_profit = PositionGetDouble(POSITION_PROFIT);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   
   // Trailing stop
   if(position_profit > 0)
   {
      if(position_type == POSITION_TYPE_BUY)
      {
         double new_stop_loss = current_price - (TrailingStop * _Point * pips_multiplier);
         double current_stop_loss = PositionGetDouble(POSITION_SL);
         if(new_stop_loss > current_stop_loss)
         {
            ModifyPositionByMagic(trade, _Symbol, MagicNumber_MeanReversion, 
                                new_stop_loss, PositionGetDouble(POSITION_TP));
         }
      }
      else if(position_type == POSITION_TYPE_SELL)
      {
         double new_stop_loss = current_price + (TrailingStop * _Point * pips_multiplier);
         double current_stop_loss = PositionGetDouble(POSITION_SL);
         if(new_stop_loss < current_stop_loss || current_stop_loss == 0)
         {
            ModifyPositionByMagic(trade, _Symbol, MagicNumber_MeanReversion, 
                                new_stop_loss, PositionGetDouble(POSITION_TP));
         }
      }
   }
   
   // Exit when price crosses EMA
   bool exit_bullish = (position_type == POSITION_TYPE_SELL && current_close > ema_current);
   bool exit_bearish = (position_type == POSITION_TYPE_BUY && current_close < ema_current);
   
   if(exit_bullish || exit_bearish)
   {
      ClosePositionByMagic(trade, _Symbol, MagicNumber_MeanReversion);
   }
}

//+------------------------------------------------------------------+
//| Check Mean Reversion Entry Signals                               |
//+------------------------------------------------------------------+
void CheckMeanReversionEntry(double ema_current, double ema_prev, double current_close)
{
   // Simplified entry logic - can be expanded
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double preis_abstand = MathAbs(current_close - ema_current) / _Point / pips_multiplier;
   double steigung = (ema_current - ema_prev) / _Point / pips_multiplier;
   
   // Entry conditions
   bool bullish_signal = (current_close > ema_current && preis_abstand > PreisSchwelle && 
                          MathAbs(steigung) > SteigungSchwelle);
   bool bearish_signal = (current_close < ema_current && preis_abstand > PreisSchwelle && 
                          MathAbs(steigung) > SteigungSchwelle);
   
   if(bullish_signal)
   {
      if(trade.Buy(MeanRev_LotSize, _Symbol, 0, 0, 0, "Mean Reversion Buy"))
      {
         meanrev_ticket = trade.ResultOrder();
         meanrev_position_open = true;
      }
   }
   else if(bearish_signal)
   {
      if(trade.Sell(MeanRev_LotSize, _Symbol, 0, 0, 0, "Mean Reversion Sell"))
      {
         meanrev_ticket = trade.ResultOrder();
         meanrev_position_open = true;
      }
   }
}

//+------------------------------------------------------------------+
