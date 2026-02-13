//+------------------------------------------------------------------+
//|                                    SelfOptimizingStrategy.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Self-Backtesting and Self-Optimizing Strategy"
#property description "Dynamically adjusts parameters based on last 3 days performance"
#property description "Two concurrent strategies: RSI Reversion and MA Crossover"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== General Settings ==="
input string TradingSymbol = "BTCUSD"; // Trading Symbol
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1; // Timeframe (1 minute)
input double LotSize = 0.01; // Lot Size
input int MagicNumberBase = 88001; // Magic Number Base
input int Slippage = 3; // Slippage

input group "=== Self-Optimization Settings ==="
input int OptimizationPeriodHours = 6; // Backtesting Period (Hours) - Use last N hours
input int OptimizationPeriodMinutes = 0; // Additional Minutes (0-59) - Adds to hours
input int OptimizationIntervalBars = 50; // Bars Between Optimizations (reduced for faster adaptation)
input int MinTradesForOptimization = 2; // Min Trades for Optimization (reduced for faster adaptation)
input bool EnableAutoOptimization = true; // Enable Auto Optimization
input double MinProfitabilityForKeep = 0.1; // Min Profitability % to Keep Parameters
input bool EnableRandomExploration = true; // Enable Random Parameter Exploration
input int ConsecutiveLossesToTrigger = 5; // Consecutive Losses to Trigger Random Mode
input double MinProfitabilityForRandom = -2.0; // Min Profitability % to Trigger Random Mode
input bool EnableForkSystem = true; // Enable Fork/Merge System
input int ForkTestBars = 200; // Bars to Test Fork Before Merge
input double ForkMinImprovement = 0.2; // Min Improvement % to Merge Fork
input double MaxLossPercent = 0.5; // Max Loss % Before Force Exit (Fork)
input double AdverseMoveThreshold = 0.15; // Adverse Move % to Trigger Exit (Fork)
input int ATR_Period = 14; // ATR Period for Volatility Stop

input group "=== Strategy 1: RSI Reversion ==="
input bool EnableStrategy1 = true; // Enable RSI Reversion
input int RSI_Period_Start = 7; // RSI Period (Start)
input int RSI_Period_End = 21; // RSI Period (End)
input double RSI_Oversold_Start = 25.0; // RSI Oversold (Start)
input double RSI_Oversold_End = 35.0; // RSI Oversold (End)
input double RSI_Overbought_Start = 65.0; // RSI Overbought (Start)
input double RSI_Overbought_End = 75.0; // RSI Overbought (End)
input int RSI_MaxBars = 30; // Max Bars in Trade
input int RSI_MinBars = 3; // Min Bars Before Exit
input bool RSI_ExitOnReversal = false; // Exit on Signal Reversal

input group "=== Strategy 2: MA Crossover ==="
input bool EnableStrategy2 = true; // Enable MA Crossover
input int MA_Fast_Start = 5; // Fast MA Period (Start)
input int MA_Fast_End = 15; // Fast MA Period (End)
input int MA_Slow_Start = 20; // Slow MA Period (Start)
input int MA_Slow_End = 50; // Slow MA Period (End)
input ENUM_MA_METHOD MA_Method = MODE_EMA; // MA Method
input int MA_MaxBars = 40; // Max Bars in Trade
input int MA_MinBars = 5; // Min Bars Before Exit
input bool MA_ExitOnReversal = false; // Exit on Signal Reversal

//--- Global variables
CTrade trade;

// Strategy 1: RSI Reversion
struct RSIStrategyParams
{
   int rsi_period;
   double rsi_oversold;
   double rsi_overbought;
   double trailing_stop_pips;
   double profit_target_percent;
   int max_bars;
   int min_bars;
   bool exit_on_reversal;
   double profitability;
   int total_trades;
   int winning_trades;
   double net_profit;
};

// Strategy 2: MA Crossover
struct MAStrategyParams
{
   int ma_fast;
   int ma_slow;
   ENUM_MA_METHOD ma_method;
   double trailing_stop_pips;
   double profit_target_percent;
   int max_bars;
   int min_bars;
   bool exit_on_reversal;
   double profitability;
   int total_trades;
   int winning_trades;
   double net_profit;
};

RSIStrategyParams s1_current_params;
MAStrategyParams s2_current_params;

// Fork system - parallel testing
RSIStrategyParams s1_fork_params;
MAStrategyParams s2_fork_params;
bool s1_fork_active = false;
bool s2_fork_active = false;
datetime s1_fork_start_time = 0;
datetime s2_fork_start_time = 0;
int s1_fork_start_bars = 0;
int s2_fork_start_bars = 0;
double s1_fork_start_profit = 0.0;
double s2_fork_start_profit = 0.0;
int s1_fork_magic = 0;
int s2_fork_magic = 0;

// Strategy handles
int s1_rsi_handle = INVALID_HANDLE;
int s1_fork_rsi_handle = INVALID_HANDLE;
int s2_ma_fast_handle = INVALID_HANDLE;
int s2_ma_slow_handle = INVALID_HANDLE;
int s2_fork_ma_fast_handle = INVALID_HANDLE;
int s2_fork_ma_slow_handle = INVALID_HANDLE;
int s1_fork_atr_handle = INVALID_HANDLE;
int s2_fork_atr_handle = INVALID_HANDLE;
double s1_fork_entry_price = 0.0;
double s2_fork_entry_price = 0.0;

// Position tracking
ulong s1_position_ticket = 0;
ulong s1_fork_position_ticket = 0;
ulong s2_position_ticket = 0;
ulong s2_fork_position_ticket = 0;
datetime s1_last_bar = 0;
datetime s1_fork_last_bar = 0;
datetime s2_last_bar = 0;
datetime s2_fork_last_bar = 0;
int s1_magic = 0;
int s2_magic = 0;

// Optimization tracking
int bars_since_optimization = 0;
datetime last_optimization_time = 0;

// Loss tracking for random exploration
int s1_consecutive_losses = 0;
int s2_consecutive_losses = 0;
double s1_last_profitability = 0.0;
double s2_last_profitability = 0.0;
bool s1_random_mode = false;
bool s2_random_mode = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize random seed
   MathSrand((uint)TimeCurrent());
   
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Set magic numbers for each strategy
   s1_magic = MagicNumberBase;
   s2_magic = MagicNumberBase + 1;
   s1_fork_magic = MagicNumberBase + 10; // Fork uses different magic
   s2_fork_magic = MagicNumberBase + 11;
   
   // Initialize default parameters
   s1_current_params.rsi_period = RSI_Period_Start;
   s1_current_params.rsi_oversold = RSI_Oversold_Start;
   s1_current_params.rsi_overbought = RSI_Overbought_Start;
   s1_current_params.trailing_stop_pips = 0; // Not used
   s1_current_params.profit_target_percent = 0; // Not used
   s1_current_params.max_bars = RSI_MaxBars;
   s1_current_params.min_bars = RSI_MinBars;
   s1_current_params.exit_on_reversal = RSI_ExitOnReversal;
   s1_current_params.profitability = 0.0;
   s1_current_params.total_trades = 0;
   s1_current_params.winning_trades = 0;
   s1_current_params.net_profit = 0.0;
   
   s2_current_params.ma_fast = MA_Fast_Start;
   s2_current_params.ma_slow = MA_Slow_Start;
   s2_current_params.ma_method = MA_Method;
   s2_current_params.trailing_stop_pips = 0; // Not used
   s2_current_params.profit_target_percent = 0; // Not used
   s2_current_params.max_bars = MA_MaxBars;
   s2_current_params.min_bars = MA_MinBars;
   s2_current_params.exit_on_reversal = MA_ExitOnReversal;
   s2_current_params.profitability = 0.0;
   s2_current_params.total_trades = 0;
   s2_current_params.winning_trades = 0;
   s2_current_params.net_profit = 0.0;
   
   // Create initial indicators
   if(EnableStrategy1)
   {
      s1_rsi_handle = iRSI(TradingSymbol, TimeFrame, s1_current_params.rsi_period, PRICE_CLOSE);
      if(s1_rsi_handle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create RSI indicator");
         return(INIT_FAILED);
      }
   }
   
   if(EnableStrategy2)
   {
      s2_ma_fast_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_fast, 0, s2_current_params.ma_method, PRICE_CLOSE);
      s2_ma_slow_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_slow, 0, s2_current_params.ma_method, PRICE_CLOSE);
      if(s2_ma_fast_handle == INVALID_HANDLE || s2_ma_slow_handle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create MA indicators");
         return(INIT_FAILED);
      }
   }
   
   // Perform initial optimization
   if(EnableAutoOptimization)
   {
      Print("=== Initial Self-Optimization Starting ===");
      OptimizeStrategies();
   }
   
   Print("Self-Optimizing Strategy initialized");
   Print("Strategy 1 (RSI Reversion): Period=", s1_current_params.rsi_period, 
         " Oversold=", s1_current_params.rsi_oversold, " Overbought=", s1_current_params.rsi_overbought);
   Print("Strategy 2 (MA Crossover): Fast=", s2_current_params.ma_fast, 
         " Slow=", s2_current_params.ma_slow, " Method=", EnumToString(s2_current_params.ma_method));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(s1_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_rsi_handle);
   if(s1_fork_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_rsi_handle);
   if(s1_fork_atr_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_atr_handle);
   if(s2_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_fast_handle);
   if(s2_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_slow_handle);
   if(s2_fork_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_fast_handle);
   if(s2_fork_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_slow_handle);
   if(s2_fork_atr_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if it's time to optimize
   bars_since_optimization++;
   if(EnableAutoOptimization && bars_since_optimization >= OptimizationIntervalBars)
   {
      Print("=== Self-Optimization Triggered ===");
      OptimizeStrategies();
      bars_since_optimization = 0;
   }
   
   // Run Strategy 1: RSI Reversion
   if(EnableStrategy1)
   {
      RunRSIStrategy();
      
      // Run fork if active
      if(EnableForkSystem && s1_fork_active)
      {
         RunRSIStrategyFork();
         CheckForkMerge(1); // Check if fork should be merged
      }
   }
   
   // Run Strategy 2: MA Crossover
   if(EnableStrategy2)
   {
      RunMAStrategy();
      
      // Run fork if active
      if(EnableForkSystem && s2_fork_active)
      {
         RunMAStrategyFork();
         CheckForkMerge(2); // Check if fork should be merged
      }
   }
}

//+------------------------------------------------------------------+
//| Optimize both strategies using backtesting                      |
//+------------------------------------------------------------------+
void OptimizeStrategies()
{
   Print("=== Starting Self-Optimization ===");
   
   // FIRST: Update current profitability from live trades
   if(EnableStrategy1)
   {
      double live_profit = CalculateStrategyProfitability(s1_magic);
      s1_current_params.profitability = live_profit;
      Print("Strategy 1 - Current Live Profitability: ", DoubleToString(live_profit, 2), "%");
   }
   
   if(EnableStrategy2)
   {
      double live_profit = CalculateStrategyProfitability(s2_magic);
      s2_current_params.profitability = live_profit;
      Print("Strategy 2 - Current Live Profitability: ", DoubleToString(live_profit, 2), "%");
   }
   
   int total_minutes = OptimizationPeriodHours * 60 + OptimizationPeriodMinutes;
   if(OptimizationPeriodMinutes > 0)
      Print("Backtesting period: Last ", OptimizationPeriodHours, " hour(s) ", OptimizationPeriodMinutes, " minute(s) (", total_minutes, " minutes total)");
   else
      Print("Backtesting period: Last ", OptimizationPeriodHours, " hour(s) (", total_minutes, " minutes total)");
   
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - (OptimizationPeriodHours * 3600 + OptimizationPeriodMinutes * 60); // Convert to seconds
   
   // Ensure we have enough historical data
   int total_bars = Bars(TradingSymbol, TimeFrame);
   if(total_bars > 0)
   {
      datetime oldest_bar = iTime(TradingSymbol, TimeFrame, total_bars - 1);
      if(start_time < oldest_bar)
      {
         Print("WARNING: Not enough historical data. Using available data from ", TimeToString(oldest_bar));
         start_time = oldest_bar;
      }
   }
   
   // Optimize Strategy 1: RSI Reversion
   if(EnableStrategy1)
   {
      Print("--- Optimizing Strategy 1: RSI Reversion ---");
      OptimizeRSIStrategy(start_time, end_time);
   }
   
   // Optimize Strategy 2: MA Crossover
   if(EnableStrategy2)
   {
      Print("--- Optimizing Strategy 2: MA Crossover ---");
      OptimizeMAStrategy(start_time, end_time);
   }
   
   // Check if we should trigger random exploration mode
   if(EnableRandomExploration)
   {
      // Check Strategy 1
      if(EnableStrategy1)
      {
         if(s1_current_params.profitability < MinProfitabilityForRandom || s1_consecutive_losses >= ConsecutiveLossesToTrigger)
         {
            if(!s1_random_mode)
            {
               Print("=== Strategy 1: Entering RANDOM EXPLORATION MODE ===");
               Print("Reason: Profitability=", DoubleToString(s1_current_params.profitability, 2), 
                     "% Consecutive Losses=", s1_consecutive_losses);
               s1_random_mode = true;
            }
         }
         else if(s1_current_params.profitability > 0.5 && s1_random_mode)
         {
            Print("=== Strategy 1: Exiting RANDOM EXPLORATION MODE ===");
            s1_random_mode = false;
            s1_consecutive_losses = 0;
         }
      }
      
      // Check Strategy 2
      if(EnableStrategy2)
      {
         if(s2_current_params.profitability < MinProfitabilityForRandom || s2_consecutive_losses >= ConsecutiveLossesToTrigger)
         {
            if(!s2_random_mode)
            {
               Print("=== Strategy 2: Entering RANDOM EXPLORATION MODE ===");
               Print("Reason: Profitability=", DoubleToString(s2_current_params.profitability, 2), 
                     "% Consecutive Losses=", s2_consecutive_losses);
               s2_random_mode = true;
            }
         }
         else if(s2_current_params.profitability > 0.5 && s2_random_mode)
         {
            Print("=== Strategy 2: Exiting RANDOM EXPLORATION MODE ===");
            s2_random_mode = false;
            s2_consecutive_losses = 0;
         }
      }
   }
   
   Print("=== Self-Optimization Complete ===");
   Print("Strategy 1 - RSI Period: ", s1_current_params.rsi_period, 
         " Oversold: ", s1_current_params.rsi_oversold, 
         " Overbought: ", s1_current_params.rsi_overbought,
         " Profitability: ", DoubleToString(s1_current_params.profitability, 2), "%",
         s1_random_mode ? " [RANDOM MODE]" : "");
   Print("Strategy 2 - Fast MA: ", s2_current_params.ma_fast, 
         " Slow MA: ", s2_current_params.ma_slow,
         " Profitability: ", DoubleToString(s2_current_params.profitability, 2), "%",
         s2_random_mode ? " [RANDOM MODE]" : "");
}

//+------------------------------------------------------------------+
//| Optimize RSI Reversion Strategy                                 |
//+------------------------------------------------------------------+
void OptimizeRSIStrategy(datetime start_time, datetime end_time)
{
   Print("RSI Optimization: Testing period from ", TimeToString(start_time), " to ", TimeToString(end_time));
   RSIStrategyParams best_params = s1_current_params;
   double best_profitability = s1_current_params.profitability;
   int tests_run = 0; // Track number of tests run
   
   if(s1_random_mode)
   {
      // Random exploration mode - test random parameter combinations
      Print("RSI Strategy: RANDOM EXPLORATION MODE - Testing random parameters");
      int random_tests = 20; // Test 20 random combinations
      
      for(int i = 0; i < random_tests; i++)
      {
         // Generate random parameters within ranges
         int rsi_period = (int)(RSI_Period_Start + MathRand() % (RSI_Period_End - RSI_Period_Start + 1));
         double oversold = RSI_Oversold_Start + (MathRand() % (int)((RSI_Oversold_End - RSI_Oversold_Start) * 10 + 1)) / 10.0;
         double overbought = RSI_Overbought_Start + (MathRand() % (int)((RSI_Overbought_End - RSI_Overbought_Start) * 10 + 1)) / 10.0;
         
         // Ensure valid range
         if(oversold >= overbought) continue;
         
         RSIStrategyParams test_params;
         test_params.rsi_period = rsi_period;
         test_params.rsi_oversold = oversold;
         test_params.rsi_overbought = overbought;
         test_params.trailing_stop_pips = s1_current_params.trailing_stop_pips;
         test_params.profit_target_percent = s1_current_params.profit_target_percent;
         test_params.max_bars = s1_current_params.max_bars;
         test_params.min_bars = s1_current_params.min_bars;
         test_params.exit_on_reversal = s1_current_params.exit_on_reversal;
         
         // Backtest this parameter set
         double profitability = BacktestRSIStrategy(test_params, start_time, end_time);
         tests_run++;
         
         if(i == 0 || i == random_tests - 1)
         {
            Print("RSI Random Test ", i+1, "/", random_tests, ": Period=", rsi_period, 
                  " Oversold=", DoubleToString(oversold, 1), " Overbought=", DoubleToString(overbought, 1),
                  " Profit=", DoubleToString(profitability, 2), "%");
         }
         
         if(profitability > best_profitability)
         {
            best_profitability = profitability;
            best_params = test_params;
            best_params.profitability = profitability;
            Print("RSI NEW BEST: Period=", rsi_period, " Oversold=", DoubleToString(oversold, 1), 
                  " Overbought=", DoubleToString(overbought, 1), " Profit=", DoubleToString(profitability, 2), "%");
         }
      }
   }
   else
   {
      // Normal grid search mode
      for(int rsi_period = RSI_Period_Start; rsi_period <= RSI_Period_End; rsi_period += 2)
      {
         for(double oversold = RSI_Oversold_Start; oversold <= RSI_Oversold_End; oversold += 2.5)
         {
            for(double overbought = RSI_Overbought_Start; overbought <= RSI_Overbought_End; overbought += 2.5)
            {
               if(oversold >= overbought) continue; // Skip invalid combinations
               
               RSIStrategyParams test_params;
               test_params.rsi_period = rsi_period;
               test_params.rsi_oversold = oversold;
               test_params.rsi_overbought = overbought;
               test_params.trailing_stop_pips = s1_current_params.trailing_stop_pips;
               test_params.profit_target_percent = s1_current_params.profit_target_percent;
               test_params.max_bars = s1_current_params.max_bars;
               test_params.min_bars = s1_current_params.min_bars;
               test_params.exit_on_reversal = s1_current_params.exit_on_reversal;
               
               // Backtest this parameter set
               double profitability = BacktestRSIStrategy(test_params, start_time, end_time);
               tests_run++;
               
               if(profitability > best_profitability)
               {
                  best_profitability = profitability;
                  best_params = test_params;
                  best_params.profitability = profitability;
                  Print("RSI Grid Search: NEW BEST Period=", rsi_period, " Oversold=", DoubleToString(oversold, 1), 
                        " Overbought=", DoubleToString(overbought, 1), " Profit=", DoubleToString(profitability, 2), "%");
               }
            }
         }
      }
   }
   
   // Update parameters if new ones are better
   // Be more aggressive when losing money
   bool should_update = false;
   bool is_losing = s1_current_params.profitability < -0.5; // Losing more than 0.5%
   
   Print("RSI Optimization Results: Tests Run=", tests_run, " Current=", DoubleToString(s1_current_params.profitability, 2), 
         "% Best Found=", DoubleToString(best_profitability, 2), "%");
   
   if(s1_random_mode)
   {
      // In random mode, accept if it's better OR if current is very bad
      should_update = (best_profitability > s1_current_params.profitability) || 
                      (best_profitability > -5.0 && s1_current_params.profitability < -10.0);
   }
   else if(is_losing)
   {
      // When losing, be more aggressive - accept any improvement or if backtest shows positive
      should_update = (best_profitability > s1_current_params.profitability) || 
                      (best_profitability > 0.1); // Accept if backtest shows any positive result
      Print("RSI Strategy: LOSING MODE - Accepting improvements more aggressively");
   }
   else
   {
      should_update = (best_profitability > s1_current_params.profitability + 0.1) || 
                      (best_profitability >= MinProfitabilityForKeep && s1_current_params.profitability < MinProfitabilityForKeep);
   }
   
   if(should_update)
   {
      if(EnableForkSystem && !s1_fork_active)
      {
         // Create fork instead of immediately updating
         Print("RSI Strategy: Creating FORK with new parameters. Current Profit: ", 
               DoubleToString(s1_current_params.profitability, 2), 
               "% Fork Profit (backtest): ", DoubleToString(best_profitability, 2), "%");
         
         s1_fork_params = best_params;
         s1_fork_active = true;
         s1_fork_start_time = TimeCurrent();
         s1_fork_start_bars = Bars(TradingSymbol, TimeFrame);
         s1_fork_start_profit = s1_current_params.profitability;
         
         // Create fork indicators
         s1_fork_rsi_handle = iRSI(TradingSymbol, TimeFrame, s1_fork_params.rsi_period, PRICE_CLOSE);
         s1_fork_atr_handle = iATR(TradingSymbol, TimeFrame, ATR_Period);
         if(s1_fork_rsi_handle == INVALID_HANDLE || s1_fork_atr_handle == INVALID_HANDLE)
         {
            Print("ERROR: Failed to create fork indicators");
            if(s1_fork_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_rsi_handle);
            if(s1_fork_atr_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_atr_handle);
            s1_fork_active = false;
         }
         else
         {
            Print("FORK CREATED: RSI Period=", s1_fork_params.rsi_period, 
                  " Oversold=", s1_fork_params.rsi_oversold, 
                  " Overbought=", s1_fork_params.rsi_overbought);
         }
      }
      else if(!EnableForkSystem)
      {
         // Direct update if fork system disabled
         Print("RSI Strategy: Updating parameters. Old Profit: ", DoubleToString(s1_current_params.profitability, 2), 
               "% New Profit: ", DoubleToString(best_profitability, 2), "%");
         
         s1_current_params = best_params;
         s1_consecutive_losses = 0; // Reset on improvement
         
         // Recreate indicator with new parameters
         if(s1_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_rsi_handle);
         s1_rsi_handle = iRSI(TradingSymbol, TimeFrame, s1_current_params.rsi_period, PRICE_CLOSE);
         
         if(s1_rsi_handle == INVALID_HANDLE)
         {
            Print("ERROR: Failed to recreate RSI indicator with new parameters");
         }
      }
      else
      {
         Print("RSI Strategy: Fork already active, skipping new fork creation");
      }
   }
   else
   {
      Print("RSI Strategy: Keeping current parameters. Current Profit: ", 
            DoubleToString(s1_current_params.profitability, 2), "% Best Found: ", 
            DoubleToString(best_profitability, 2), "%");
      
      // Track if we're still losing
      if(s1_current_params.profitability < 0)
         s1_consecutive_losses++;
      else
         s1_consecutive_losses = 0;
   }
   
   s1_last_profitability = s1_current_params.profitability;
}

//+------------------------------------------------------------------+
//| Backtest RSI Strategy                                            |
//+------------------------------------------------------------------+
double BacktestRSIStrategy(RSIStrategyParams &params, datetime start_time, datetime end_time)
{
   // Create temporary RSI indicator for backtesting
   int temp_rsi = iRSI(TradingSymbol, TimeFrame, params.rsi_period, PRICE_CLOSE);
   if(temp_rsi == INVALID_HANDLE) return -999999.0;
   
   double total_profit = 0.0;
   int total_trades = 0;
   int winning_trades = 0;
   ulong virtual_position = 0;
   double virtual_entry = 0;
   datetime virtual_entry_time = 0;
   ENUM_POSITION_TYPE virtual_position_type = WRONG_VALUE;
   
   // Calculate how many bars we need based on time period
   int period_seconds = PeriodSeconds(TimeFrame);
   int bars_needed = (int)((end_time - start_time) / period_seconds) + 20; // Add buffer for indicators
   
   // Get bars from end_time going backwards
   // end_bar should be 0 (current bar) or the bar at end_time
   int end_bar = iBarShift(TradingSymbol, TimeFrame, end_time, false);
   if(end_bar < 0) end_bar = 0; // Use current bar if not found
   
   // Calculate start_bar by going backwards from end_bar
   int start_bar = end_bar + bars_needed;
   int max_bars = Bars(TradingSymbol, TimeFrame);
   if(start_bar >= max_bars) 
   {
      start_bar = max_bars - 1;
      bars_needed = start_bar - end_bar; // Adjust to available bars
   }
   
   // Verify we have enough bars
   int bars_to_test = start_bar - end_bar;
   Print("RSI Backtest: Bars needed: ", bars_needed, " Bars available: ", bars_to_test, 
         " (start_bar=", start_bar, " end_bar=", end_bar, ") Period: ", 
         TimeToString(start_time), " to ", TimeToString(end_time));
   
   if(bars_to_test < 5) // Reduced minimum for shorter periods
   {
      Print("RSI Backtest: Not enough bars (need 5, have ", bars_to_test, ")");
      IndicatorRelease(temp_rsi);
      return -999999.0;
   }
   
   // Get data arrays
   double rsi_buffer[];
   double close_buffer[];
   datetime time_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   ArraySetAsSeries(close_buffer, true);
   ArraySetAsSeries(time_buffer, true);
   
   // Copy data from end_bar to start_bar (oldest to newest)
   // With ArraySetAsSeries(true), index 0 = most recent, higher index = older
   if(CopyBuffer(temp_rsi, 0, end_bar, bars_to_test, rsi_buffer) < bars_to_test) 
   {
      IndicatorRelease(temp_rsi);
      return -999999.0;
   }
   if(CopyClose(TradingSymbol, TimeFrame, end_bar, bars_to_test, close_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_rsi);
      return -999999.0;
   }
   if(CopyTime(TradingSymbol, TimeFrame, end_bar, bars_to_test, time_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_rsi);
      return -999999.0;
   }
   if(CopyTime(TradingSymbol, TimeFrame, end_bar, bars_to_test, time_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_rsi);
      return -999999.0;
   }
   
   double point = SymbolInfoDouble(TradingSymbol, SYMBOL_POINT);
   double pip = (SymbolInfoInteger(TradingSymbol, SYMBOL_DIGITS) == 3 || 
                SymbolInfoInteger(TradingSymbol, SYMBOL_DIGITS) == 5) ? point * 10 : point;
   
   // Iterate through historical bars (from oldest to newest)
   // With ArraySetAsSeries(true), index 0 = newest, higher index = older
   // So we iterate from highest index (oldest) down to 1 (newest)
   for(int i = bars_to_test - 1; i >= 1; i--) // Start from oldest, need previous bar
   {
      datetime bar_time = time_buffer[i];
      double current_rsi = rsi_buffer[i];
      double prev_rsi = rsi_buffer[i-1]; // i-1 is more recent than i
      double current_price = close_buffer[i];
      
      // Check existing virtual position
      if(virtual_position > 0)
      {
         // Check exit conditions
         int bars_held = (int)((bar_time - virtual_entry_time) / period_seconds);
         if(bars_held >= params.max_bars)
         {
            // Time-based exit
            double exit_price = current_price;
            double profit = 0;
            if(virtual_position_type == POSITION_TYPE_BUY)
               profit = (exit_price - virtual_entry) / virtual_entry;
            else
               profit = (virtual_entry - exit_price) / virtual_entry;
            
            total_profit += profit;
            total_trades++;
            if(profit > 0) winning_trades++;
            
            virtual_position = 0;
         }
         else
         {
            // Check profit target
            double profit_pct = 0;
            if(virtual_position_type == POSITION_TYPE_BUY)
               profit_pct = ((current_price - virtual_entry) / virtual_entry) * 100.0;
            else
               profit_pct = ((virtual_entry - current_price) / virtual_entry) * 100.0;
            
            // Profit target removed - using other exit conditions only
            if(false) // Disabled
            {
               double profit = profit_pct / 100.0;
               total_profit += profit;
               total_trades++;
               winning_trades++;
               virtual_position = 0;
               continue;
            }
            
            // Check RSI extreme exit
            if(virtual_position_type == POSITION_TYPE_BUY && current_rsi >= params.rsi_overbought)
            {
               double profit = (current_price - virtual_entry) / virtual_entry;
               total_profit += profit;
               total_trades++;
               if(profit > 0) winning_trades++;
               virtual_position = 0;
               continue;
            }
            else if(virtual_position_type == POSITION_TYPE_SELL && current_rsi <= params.rsi_oversold)
            {
               double profit = (virtual_entry - current_price) / virtual_entry;
               total_profit += profit;
               total_trades++;
               if(profit > 0) winning_trades++;
               virtual_position = 0;
               continue;
            }
         }
      }
      
      // Check for new entry signals
      if(virtual_position == 0)
      {
         // RSI Reversion: Buy when oversold, Sell when overbought
         if(current_rsi > params.rsi_oversold && prev_rsi <= params.rsi_oversold)
         {
            // RSI crossed above oversold - buy signal
            virtual_position = 1;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_BUY;
         }
         else if(current_rsi < params.rsi_overbought && prev_rsi >= params.rsi_overbought)
         {
            // RSI crossed below overbought - sell signal
            virtual_position = 2;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_SELL;
         }
      }
   }
   
   // Debug: Log signal detection
   if(total_trades == 0 && bars_to_test > 20)
   {
      // Check if we're even getting RSI signals
      int signal_count = 0;
      for(int i = 1; i < bars_to_test && i < 20; i++)
      {
         if(rsi_buffer[i] > params.rsi_oversold && rsi_buffer[i-1] <= params.rsi_oversold) signal_count++;
         if(rsi_buffer[i] < params.rsi_overbought && rsi_buffer[i-1] >= params.rsi_overbought) signal_count++;
      }
      Print("RSI Backtest Debug: First 20 bars - Signals detected: ", signal_count, 
            " RSI range: ", DoubleToString(rsi_buffer[0], 1), " to ", DoubleToString(rsi_buffer[MathMin(19, bars_to_test-1)], 1));
   }
   
   // Close any remaining position
   if(virtual_position > 0)
   {
      double exit_price = close_buffer[0];
      double profit = 0;
      if(virtual_position_type == POSITION_TYPE_BUY)
         profit = (exit_price - virtual_entry) / virtual_entry;
      else
         profit = (virtual_entry - exit_price) / virtual_entry;
      
      total_profit += profit;
      total_trades++;
      if(profit > 0) winning_trades++;
   }
   
   IndicatorRelease(temp_rsi);
   
   // Calculate profitability percentage
   if(total_trades >= MinTradesForOptimization)
   {
      params.total_trades = total_trades;
      params.winning_trades = winning_trades;
      params.net_profit = total_profit;
      double profitability = total_profit * 100.0;
      Print("RSI Backtest: Trades=", total_trades, " Wins=", winning_trades, 
            " Profit=", DoubleToString(profitability, 2), "%");
      // Return profitability as percentage (total_profit is already a ratio)
      return profitability;
   }
   
   // Return a very negative value if not enough trades
   if(total_trades > 0)
   {
      // Some trades found but not enough - return a scaled negative value
      Print("RSI Backtest: Only ", total_trades, " trades found (need ", MinTradesForOptimization, ")");
      return -1000.0 - (MinTradesForOptimization - total_trades);
   }
   
   Print("RSI Backtest: NO TRADES FOUND - Period=", params.rsi_period, 
         " Oversold=", DoubleToString(params.rsi_oversold, 1), 
         " Overbought=", DoubleToString(params.rsi_overbought, 1));
   return -999999.0; // No trades found
}

//+------------------------------------------------------------------+
//| Optimize MA Crossover Strategy                                  |
//+------------------------------------------------------------------+
void OptimizeMAStrategy(datetime start_time, datetime end_time)
{
   Print("MA Optimization: Testing period from ", TimeToString(start_time), " to ", TimeToString(end_time));
   MAStrategyParams best_params = s2_current_params;
   double best_profitability = s2_current_params.profitability;
   int tests_run = 0; // Track number of tests run
   
   if(s2_random_mode)
   {
      // Random exploration mode - test random parameter combinations
      Print("MA Strategy: RANDOM EXPLORATION MODE - Testing random parameters");
      int random_tests = 20; // Test 20 random combinations
      
      for(int i = 0; i < random_tests; i++)
      {
         // Generate random parameters within ranges
         int ma_fast = MA_Fast_Start + (MathRand() % (MA_Fast_End - MA_Fast_Start + 1));
         int ma_slow = MA_Slow_Start + (MathRand() % (MA_Slow_End - MA_Slow_Start + 1));
         
         // Ensure valid range (fast < slow)
         if(ma_fast >= ma_slow) continue;
         
         MAStrategyParams test_params;
         test_params.ma_fast = ma_fast;
         test_params.ma_slow = ma_slow;
         test_params.ma_method = MA_Method;
         test_params.trailing_stop_pips = s2_current_params.trailing_stop_pips;
         test_params.profit_target_percent = s2_current_params.profit_target_percent;
         test_params.max_bars = s2_current_params.max_bars;
         test_params.min_bars = s2_current_params.min_bars;
         test_params.exit_on_reversal = s2_current_params.exit_on_reversal;
         
         // Backtest this parameter set
         double profitability = BacktestMAStrategy(test_params, start_time, end_time);
         tests_run++;
         
         if(i == 0 || i == random_tests - 1)
         {
            Print("MA Random Test ", i+1, "/", random_tests, ": Fast=", ma_fast, 
                  " Slow=", ma_slow, " Profit=", DoubleToString(profitability, 2), "%");
         }
         
         if(profitability > best_profitability)
         {
            best_profitability = profitability;
            best_params = test_params;
            best_params.profitability = profitability;
            Print("MA NEW BEST: Fast=", ma_fast, " Slow=", ma_slow, 
                  " Profit=", DoubleToString(profitability, 2), "%");
         }
      }
   }
   else
   {
      // Normal grid search mode
      for(int ma_fast = MA_Fast_Start; ma_fast <= MA_Fast_End; ma_fast += 2)
      {
         for(int ma_slow = MA_Slow_Start; ma_slow <= MA_Slow_End; ma_slow += 5)
         {
            if(ma_fast >= ma_slow) continue; // Fast must be less than slow
            
            MAStrategyParams test_params;
            test_params.ma_fast = ma_fast;
            test_params.ma_slow = ma_slow;
            test_params.ma_method = MA_Method;
            test_params.trailing_stop_pips = s2_current_params.trailing_stop_pips;
            test_params.profit_target_percent = s2_current_params.profit_target_percent;
            test_params.max_bars = s2_current_params.max_bars;
            test_params.min_bars = s2_current_params.min_bars;
            test_params.exit_on_reversal = s2_current_params.exit_on_reversal;
            
            // Backtest this parameter set
            double profitability = BacktestMAStrategy(test_params, start_time, end_time);
            tests_run++;
            
            if(profitability > best_profitability)
            {
               best_profitability = profitability;
               best_params = test_params;
               best_params.profitability = profitability;
               Print("MA Grid Search: NEW BEST Fast=", ma_fast, " Slow=", ma_slow, 
                     " Profit=", DoubleToString(profitability, 2), "%");
            }
         }
      }
   }
   
   // Update parameters if new ones are better
   // Be more aggressive when losing money
   bool should_update = false;
   bool is_losing = s2_current_params.profitability < -0.5; // Losing more than 0.5%
   
   Print("MA Optimization Results: Tests Run=", tests_run, " Current=", DoubleToString(s2_current_params.profitability, 2), 
         "% Best Found=", DoubleToString(best_profitability, 2), "%");
   
   if(s2_random_mode)
   {
      // In random mode, accept if it's better OR if current is very bad
      should_update = (best_profitability > s2_current_params.profitability) || 
                      (best_profitability > -5.0 && s2_current_params.profitability < -10.0);
   }
   else if(is_losing)
   {
      // When losing, be more aggressive - accept any improvement or if backtest shows positive
      should_update = (best_profitability > s2_current_params.profitability) || 
                      (best_profitability > 0.1); // Accept if backtest shows any positive result
      Print("MA Strategy: LOSING MODE - Accepting improvements more aggressively");
   }
   else
   {
      should_update = (best_profitability > s2_current_params.profitability + 0.1) || 
                      (best_profitability >= MinProfitabilityForKeep && s2_current_params.profitability < MinProfitabilityForKeep);
   }
   
   if(should_update)
   {
      if(EnableForkSystem && !s2_fork_active)
      {
         // Create fork instead of immediately updating
         Print("MA Strategy: Creating FORK with new parameters. Current Profit: ", 
               DoubleToString(s2_current_params.profitability, 2), 
               "% Fork Profit (backtest): ", DoubleToString(best_profitability, 2), "%");
         
         s2_fork_params = best_params;
         s2_fork_active = true;
         s2_fork_start_time = TimeCurrent();
         s2_fork_start_bars = Bars(TradingSymbol, TimeFrame);
         s2_fork_start_profit = s2_current_params.profitability;
         
         // Create fork indicators
         s2_fork_ma_fast_handle = iMA(TradingSymbol, TimeFrame, s2_fork_params.ma_fast, 0, s2_fork_params.ma_method, PRICE_CLOSE);
         s2_fork_ma_slow_handle = iMA(TradingSymbol, TimeFrame, s2_fork_params.ma_slow, 0, s2_fork_params.ma_method, PRICE_CLOSE);
         s2_fork_atr_handle = iATR(TradingSymbol, TimeFrame, ATR_Period);
         if(s2_fork_ma_fast_handle == INVALID_HANDLE || s2_fork_ma_slow_handle == INVALID_HANDLE || s2_fork_atr_handle == INVALID_HANDLE)
         {
            Print("ERROR: Failed to create fork MA indicators");
            if(s2_fork_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_fast_handle);
            if(s2_fork_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_slow_handle);
            if(s2_fork_atr_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_atr_handle);
            s2_fork_active = false;
         }
         else
         {
            Print("FORK CREATED: Fast MA=", s2_fork_params.ma_fast, 
                  " Slow MA=", s2_fork_params.ma_slow);
         }
      }
      else if(!EnableForkSystem)
      {
         // Direct update if fork system disabled
         Print("MA Strategy: Updating parameters. Old Profit: ", DoubleToString(s2_current_params.profitability, 2), 
               "% New Profit: ", DoubleToString(best_profitability, 2), "%");
         
         s2_current_params = best_params;
         s2_consecutive_losses = 0; // Reset on improvement
         
         // Recreate indicators with new parameters
         if(s2_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_fast_handle);
         if(s2_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_slow_handle);
         
         s2_ma_fast_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_fast, 0, s2_current_params.ma_method, PRICE_CLOSE);
         s2_ma_slow_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_slow, 0, s2_current_params.ma_method, PRICE_CLOSE);
         
         if(s2_ma_fast_handle == INVALID_HANDLE || s2_ma_slow_handle == INVALID_HANDLE)
         {
            Print("ERROR: Failed to recreate MA indicators with new parameters");
         }
      }
      else
      {
         Print("MA Strategy: Fork already active, skipping new fork creation");
      }
   }
   else
   {
      Print("MA Strategy: Keeping current parameters. Current Profit: ", 
            DoubleToString(s2_current_params.profitability, 2), "% Best Found: ", 
            DoubleToString(best_profitability, 2), "%");
      
      // Track if we're still losing
      if(s2_current_params.profitability < 0)
         s2_consecutive_losses++;
      else
         s2_consecutive_losses = 0;
   }
   
   s2_last_profitability = s2_current_params.profitability;
}

//+------------------------------------------------------------------+
//| Backtest MA Crossover Strategy                                  |
//+------------------------------------------------------------------+
double BacktestMAStrategy(MAStrategyParams &params, datetime start_time, datetime end_time)
{
   // Create temporary MA indicators for backtesting
   int temp_ma_fast = iMA(TradingSymbol, TimeFrame, params.ma_fast, 0, params.ma_method, PRICE_CLOSE);
   int temp_ma_slow = iMA(TradingSymbol, TimeFrame, params.ma_slow, 0, params.ma_method, PRICE_CLOSE);
   
   if(temp_ma_fast == INVALID_HANDLE || temp_ma_slow == INVALID_HANDLE)
   {
      if(temp_ma_fast != INVALID_HANDLE) IndicatorRelease(temp_ma_fast);
      if(temp_ma_slow != INVALID_HANDLE) IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   
   double total_profit = 0.0;
   int total_trades = 0;
   int winning_trades = 0;
   ulong virtual_position = 0;
   double virtual_entry = 0;
   datetime virtual_entry_time = 0;
   ENUM_POSITION_TYPE virtual_position_type = WRONG_VALUE;
   
   // Calculate how many bars we need based on time period
   int period_seconds = PeriodSeconds(TimeFrame);
   int bars_needed = (int)((end_time - start_time) / period_seconds) + 20; // Add buffer for indicators
   
   // Get bars from end_time going backwards
   // end_bar should be 0 (current bar) or close to it
   int end_bar = iBarShift(TradingSymbol, TimeFrame, end_time, false);
   if(end_bar < 0) end_bar = 0; // Use current bar if not found
   
   // Calculate start_bar by going backwards from end_bar
   int start_bar = end_bar + bars_needed;
   int max_bars = Bars(TradingSymbol, TimeFrame);
   if(start_bar >= max_bars) 
   {
      start_bar = max_bars - 1;
      bars_needed = start_bar - end_bar; // Adjust to available bars
   }
   
   // Verify we have enough bars
   int bars_to_test = start_bar - end_bar;
   Print("MA Backtest: Bars needed: ", bars_needed, " Bars available: ", bars_to_test, 
         " (start_bar=", start_bar, " end_bar=", end_bar, ") Period: ", 
         TimeToString(start_time), " to ", TimeToString(end_time));
   
   if(bars_to_test < 5) // Reduced minimum for shorter periods
   {
      Print("MA Backtest: Not enough bars (need 5, have ", bars_to_test, ")");
      IndicatorRelease(temp_ma_fast);
      IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   
   // Get data arrays
   double ma_fast_buffer[];
   double ma_slow_buffer[];
   double close_buffer[];
   datetime time_buffer[];
   ArraySetAsSeries(ma_fast_buffer, true);
   ArraySetAsSeries(ma_slow_buffer, true);
   ArraySetAsSeries(close_buffer, true);
   ArraySetAsSeries(time_buffer, true);
   
   // Copy data from end_bar to start_bar (oldest to newest)
   // With ArraySetAsSeries(true), index 0 = most recent, higher index = older
   if(CopyBuffer(temp_ma_fast, 0, end_bar, bars_to_test, ma_fast_buffer) < bars_to_test) 
   {
      IndicatorRelease(temp_ma_fast);
      IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   if(CopyBuffer(temp_ma_slow, 0, end_bar, bars_to_test, ma_slow_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_ma_fast);
      IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   if(CopyClose(TradingSymbol, TimeFrame, end_bar, bars_to_test, close_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_ma_fast);
      IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   if(CopyTime(TradingSymbol, TimeFrame, end_bar, bars_to_test, time_buffer) < bars_to_test)
   {
      IndicatorRelease(temp_ma_fast);
      IndicatorRelease(temp_ma_slow);
      return -999999.0;
   }
   
   double point = SymbolInfoDouble(TradingSymbol, SYMBOL_POINT);
   double pip = (SymbolInfoInteger(TradingSymbol, SYMBOL_DIGITS) == 3 || 
                SymbolInfoInteger(TradingSymbol, SYMBOL_DIGITS) == 5) ? point * 10 : point;
   // period_seconds already declared above
   
   // Iterate through historical bars (from oldest to newest)
   // With ArraySetAsSeries(true), index 0 = newest, higher index = older
   // So we iterate from highest index (oldest) down to 1 (newest)
   for(int i = bars_to_test - 1; i >= 1; i--) // Start from oldest, need previous bar
   {
      datetime bar_time = time_buffer[i];
      double current_ma_fast = ma_fast_buffer[i];
      double prev_ma_fast = ma_fast_buffer[i-1]; // i-1 is more recent than i
      double current_ma_slow = ma_slow_buffer[i];
      double prev_ma_slow = ma_slow_buffer[i-1]; // i-1 is more recent than i
      double current_price = close_buffer[i];
      
      // Check existing virtual position
      if(virtual_position > 0)
      {
         // Check exit conditions
         int bars_held = (int)((bar_time - virtual_entry_time) / period_seconds);
         if(bars_held >= params.max_bars)
         {
            // Time-based exit
            double exit_price = current_price;
            double profit = 0;
            if(virtual_position_type == POSITION_TYPE_BUY)
               profit = (exit_price - virtual_entry) / virtual_entry;
            else
               profit = (virtual_entry - exit_price) / virtual_entry;
            
            total_profit += profit;
            total_trades++;
            if(profit > 0) winning_trades++;
            
            virtual_position = 0;
         }
         else
         {
            // Check profit target
            double profit_pct = 0;
            if(virtual_position_type == POSITION_TYPE_BUY)
               profit_pct = ((current_price - virtual_entry) / virtual_entry) * 100.0;
            else
               profit_pct = ((virtual_entry - current_price) / virtual_entry) * 100.0;
            
            // Profit target removed - using other exit conditions only
            if(false) // Disabled
            {
               double profit = profit_pct / 100.0;
               total_profit += profit;
               total_trades++;
               winning_trades++;
               virtual_position = 0;
               continue;
            }
            
            // Check price crosses back over MA (trend reversal)
            if(virtual_position_type == POSITION_TYPE_BUY && current_price < current_ma_slow)
            {
               double profit = (current_price - virtual_entry) / virtual_entry;
               total_profit += profit;
               total_trades++;
               if(profit > 0) winning_trades++;
               virtual_position = 0;
               continue;
            }
            else if(virtual_position_type == POSITION_TYPE_SELL && current_price > current_ma_slow)
            {
               double profit = (virtual_entry - current_price) / virtual_entry;
               total_profit += profit;
               total_trades++;
               if(profit > 0) winning_trades++;
               virtual_position = 0;
               continue;
            }
            
            // Check opposite crossover (signal reversal)
            if(params.exit_on_reversal)
            {
               bool bearish_cross = (current_ma_fast < current_ma_slow && prev_ma_fast >= prev_ma_slow);
               bool bullish_cross = (current_ma_fast > current_ma_slow && prev_ma_fast <= prev_ma_slow);
               
               if(virtual_position_type == POSITION_TYPE_BUY && bearish_cross)
               {
                  double profit = (current_price - virtual_entry) / virtual_entry;
                  total_profit += profit;
                  total_trades++;
                  if(profit > 0) winning_trades++;
                  virtual_position = 0;
                  continue;
               }
               else if(virtual_position_type == POSITION_TYPE_SELL && bullish_cross)
               {
                  double profit = (virtual_entry - current_price) / virtual_entry;
                  total_profit += profit;
                  total_trades++;
                  if(profit > 0) winning_trades++;
                  virtual_position = 0;
                  continue;
               }
            }
         }
      }
      
      // Check for new entry signals (MA Crossover)
      if(virtual_position == 0)
      {
         // Bullish crossover: Fast MA crosses above Slow MA
         bool bullish_cross = (current_ma_fast > current_ma_slow && prev_ma_fast <= prev_ma_slow);
         // Bearish crossover: Fast MA crosses below Slow MA
         bool bearish_cross = (current_ma_fast < current_ma_slow && prev_ma_fast >= prev_ma_slow);
         
         if(bullish_cross)
         {
            virtual_position = 1;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_BUY;
         }
         else if(bearish_cross)
         {
            virtual_position = 2;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_SELL;
         }
      }
   }
   
   // Close any remaining position
   if(virtual_position > 0)
   {
      double exit_price = close_buffer[0];
      double profit = 0;
      if(virtual_position_type == POSITION_TYPE_BUY)
         profit = (exit_price - virtual_entry) / virtual_entry;
      else
         profit = (virtual_entry - exit_price) / virtual_entry;
      
      total_profit += profit;
      total_trades++;
      if(profit > 0) winning_trades++;
   }
   
   IndicatorRelease(temp_ma_fast);
   IndicatorRelease(temp_ma_slow);
   
   // Calculate profitability percentage
   if(total_trades >= MinTradesForOptimization)
   {
      params.total_trades = total_trades;
      params.winning_trades = winning_trades;
      params.net_profit = total_profit;
      double profitability = total_profit * 100.0;
      Print("MA Backtest: Trades=", total_trades, " Wins=", winning_trades, 
            " Profit=", DoubleToString(profitability, 2), "%");
      // Return profitability as percentage (total_profit is already a ratio)
      return profitability;
   }
   
   // Return a very negative value if not enough trades
   if(total_trades > 0)
   {
      // Some trades found but not enough - return a scaled negative value
      Print("MA Backtest: Only ", total_trades, " trades found (need ", MinTradesForOptimization, ")");
      return -1000.0 - (MinTradesForOptimization - total_trades);
   }
   
   Print("MA Backtest: NO TRADES FOUND");
   return -999999.0; // No trades found
}

//+------------------------------------------------------------------+
//| Normalize Stop Loss and Take Profit levels                      |
//+------------------------------------------------------------------+
bool NormalizeStops(string symbol, double entry_price, ENUM_ORDER_TYPE order_type, double &sl, double &tp)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double pip = (digits == 3 || digits == 5) ? point * 10 : point;
   
   // Get minimum stop level from broker
   long min_stop_level = (long)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_distance = min_stop_level * point;
   
   // Calculate safe minimum distance (0.1% of price or 50 points, whichever is larger)
   double safe_min_distance = MathMax(entry_price * 0.001, 50 * point);
   double required_distance = MathMax(min_stop_distance, safe_min_distance);
   
   // Add a small buffer to prevent rounding issues
   double buffer = required_distance * 0.1;
   required_distance += buffer;
   
   // Normalize to correct number of digits
   required_distance = NormalizeDouble(required_distance, digits);
   
   // Adjust stop loss and take profit based on order type
   if(order_type == ORDER_TYPE_BUY)
   {
      // For buy: SL below entry, TP above entry
      if(sl > 0 && sl >= entry_price - required_distance)
         sl = NormalizeDouble(entry_price - required_distance, digits);
      
      if(tp > 0 && tp <= entry_price + required_distance)
         tp = NormalizeDouble(entry_price + required_distance, digits);
      
      // Validate SL is below entry and TP is above entry
      if(sl > 0 && sl >= entry_price) return false;
      if(tp > 0 && tp <= entry_price) return false;
      
      // Ensure SL and TP are far enough apart
      if(sl > 0 && tp > 0 && (tp - sl) < required_distance * 2) return false;
   }
   else // ORDER_TYPE_SELL
   {
      // For sell: SL above entry, TP below entry
      if(sl > 0 && sl <= entry_price + required_distance)
         sl = NormalizeDouble(entry_price + required_distance, digits);
      
      if(tp > 0 && tp >= entry_price - required_distance)
         tp = NormalizeDouble(entry_price - required_distance, digits);
      
      // Validate SL is above entry and TP is below entry
      if(sl > 0 && sl <= entry_price) return false;
      if(tp > 0 && tp >= entry_price) return false;
      
      // Ensure SL and TP are far enough apart
      if(sl > 0 && tp > 0 && (sl - tp) < required_distance * 2) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Run RSI Reversion Strategy                                       |
//+------------------------------------------------------------------+
void RunRSIStrategy()
{
   trade.SetExpertMagicNumber(s1_magic);
   
   datetime current_bar = iTime(TradingSymbol, TimeFrame, 0);
   if(current_bar == s1_last_bar) return;
   s1_last_bar = current_bar;
   
   // Get RSI data
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   if(CopyBuffer(s1_rsi_handle, 0, 0, 3, rsi_buffer) < 3) return;
   
   // Check existing position for smart exits
   if(s1_position_ticket > 0)
   {
      if(!PositionSelectByTicket(s1_position_ticket))
      {
         s1_position_ticket = 0;
      }
      else
      {
         // Get position details
         double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         double current_price = (position_type == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         
         // Calculate bars held
         int bars_held = (int)((current_bar - position_open_time) / PeriodSeconds(TimeFrame));
         
         // 1. Time-based exit (max bars)
         if(bars_held >= s1_current_params.max_bars)
         {
            trade.PositionClose(s1_position_ticket);
            s1_position_ticket = 0;
            return;
         }
         
         // Minimum hold time - don't exit too early
         if(bars_held < s1_current_params.min_bars)
         {
            return; // Don't check other exit conditions if minimum bars not reached
         }
         
         // 2. Signal reversal exit (if enabled)
         if(s1_current_params.exit_on_reversal)
         {
            if(position_type == POSITION_TYPE_BUY)
            {
               // Exit buy if RSI crosses below oversold (reversal signal)
               if(rsi_buffer[0] < s1_current_params.rsi_oversold && rsi_buffer[1] >= s1_current_params.rsi_oversold)
               {
                  trade.PositionClose(s1_position_ticket);
                  s1_position_ticket = 0;
                  return;
               }
            }
            else // SELL
            {
               // Exit sell if RSI crosses above overbought (reversal signal)
               if(rsi_buffer[0] > s1_current_params.rsi_overbought && rsi_buffer[1] <= s1_current_params.rsi_overbought)
               {
                  trade.PositionClose(s1_position_ticket);
                  s1_position_ticket = 0;
                  return;
               }
            }
         }
         
         // 3. RSI extreme exit (exit when RSI reaches opposite extreme)
         {
            if(position_type == POSITION_TYPE_BUY && rsi_buffer[0] >= s1_current_params.rsi_overbought)
            {
               // Bought from oversold, exit when reaches overbought
               trade.PositionClose(s1_position_ticket);
               s1_position_ticket = 0;
               return;
            }
            else if(position_type == POSITION_TYPE_SELL && rsi_buffer[0] <= s1_current_params.rsi_oversold)
            {
               // Sold from overbought, exit when reaches oversold
               trade.PositionClose(s1_position_ticket);
               s1_position_ticket = 0;
               return;
            }
         }
      }
   }
   
   // Check for new entry signals
   if(s1_position_ticket == 0)
   {
      // Buy signal: RSI crosses above oversold
      if(rsi_buffer[0] > s1_current_params.rsi_oversold && rsi_buffer[1] <= s1_current_params.rsi_oversold)
      {
         double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         if(trade.Buy(LotSize, TradingSymbol, 0, 0, 0, "S1: RSI Reversion"))
         {
            // Find the position ticket
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s1_magic)
                  {
                     s1_position_ticket = PositionGetInteger(POSITION_TICKET);
                     break;
                  }
               }
            }
         }
      }
      // Sell signal: RSI crosses below overbought
      else if(rsi_buffer[0] < s1_current_params.rsi_overbought && rsi_buffer[1] >= s1_current_params.rsi_overbought)
      {
         double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
         if(trade.Sell(LotSize, TradingSymbol, 0, 0, 0, "S1: RSI Reversion"))
         {
            // Find the position ticket
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s1_magic)
                  {
                     s1_position_ticket = PositionGetInteger(POSITION_TICKET);
                     break;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Run MA Crossover Strategy                                        |
//+------------------------------------------------------------------+
void RunMAStrategy()
{
   trade.SetExpertMagicNumber(s2_magic);
   
   datetime current_bar = iTime(TradingSymbol, TimeFrame, 0);
   if(current_bar == s2_last_bar) return;
   s2_last_bar = current_bar;
   
   // Get MA data
   double ma_fast_buffer[];
   double ma_slow_buffer[];
   ArraySetAsSeries(ma_fast_buffer, true);
   ArraySetAsSeries(ma_slow_buffer, true);
   if(CopyBuffer(s2_ma_fast_handle, 0, 0, 3, ma_fast_buffer) < 3) return;
   if(CopyBuffer(s2_ma_slow_handle, 0, 0, 3, ma_slow_buffer) < 3) return;
   
   // Check existing position for smart exits
   if(s2_position_ticket > 0)
   {
      if(!PositionSelectByTicket(s2_position_ticket))
      {
         s2_position_ticket = 0;
      }
      else
      {
         // Get position details
         double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         double current_price = (position_type == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         
         // Calculate bars held
         int bars_held = (int)((current_bar - position_open_time) / PeriodSeconds(TimeFrame));
         
         // 1. Time-based exit (max bars)
         if(bars_held >= s2_current_params.max_bars)
         {
            trade.PositionClose(s2_position_ticket);
            s2_position_ticket = 0;
            return;
         }
         
         // Minimum hold time - don't exit too early
         if(bars_held < s2_current_params.min_bars)
         {
            return; // Don't check other exit conditions if minimum bars not reached
         }
         
         // 2. Signal reversal exit (opposite crossover)
         if(s2_current_params.exit_on_reversal)
         {
            bool bearish_cross = (ma_fast_buffer[0] < ma_slow_buffer[0] && ma_fast_buffer[1] >= ma_slow_buffer[1]);
            bool bullish_cross = (ma_fast_buffer[0] > ma_slow_buffer[0] && ma_fast_buffer[1] <= ma_slow_buffer[1]);
            
            if(position_type == POSITION_TYPE_BUY && bearish_cross)
            {
               // Exit buy on bearish crossover
               trade.PositionClose(s2_position_ticket);
               s2_position_ticket = 0;
               return;
            }
            else if(position_type == POSITION_TYPE_SELL && bullish_cross)
            {
               // Exit sell on bullish crossover
               trade.PositionClose(s2_position_ticket);
               s2_position_ticket = 0;
               return;
            }
         }
         
         // 3. Price crosses back over MA (trend reversal)
         {
            if(position_type == POSITION_TYPE_BUY)
            {
               // Exit if price crosses below slow MA (trend reversal)
               if(current_price < ma_slow_buffer[0])
               {
                  trade.PositionClose(s2_position_ticket);
                  s2_position_ticket = 0;
                  return;
               }
            }
            else // SELL
            {
               // Exit if price crosses above slow MA (trend reversal)
               if(current_price > ma_slow_buffer[0])
               {
                  trade.PositionClose(s2_position_ticket);
                  s2_position_ticket = 0;
                  return;
               }
            }
         }
      }
   }
   
   // Check for new entry signals
   if(s2_position_ticket == 0)
   {
      // Bullish crossover: Fast MA crosses above Slow MA
      bool bullish_cross = (ma_fast_buffer[0] > ma_slow_buffer[0] && ma_fast_buffer[1] <= ma_slow_buffer[1]);
      // Bearish crossover: Fast MA crosses below Slow MA
      bool bearish_cross = (ma_fast_buffer[0] < ma_slow_buffer[0] && ma_fast_buffer[1] >= ma_slow_buffer[1]);
      
      if(bullish_cross)
      {
         double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         if(trade.Buy(LotSize, TradingSymbol, 0, 0, 0, "S2: MA Crossover"))
         {
            // Find the position ticket
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s2_magic)
                  {
                     s2_position_ticket = PositionGetInteger(POSITION_TICKET);
                     break;
                  }
               }
            }
         }
      }
      else if(bearish_cross)
      {
         double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
         if(trade.Sell(LotSize, TradingSymbol, 0, 0, 0, "S2: MA Crossover"))
         {
            // Find the position ticket
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s2_magic)
                  {
                     s2_position_ticket = PositionGetInteger(POSITION_TICKET);
                     break;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if fork should be merged                                   |
//+------------------------------------------------------------------+
void CheckForkMerge(int strategy_num)
{
   if(strategy_num == 1 && s1_fork_active)
   {
      int current_bars = Bars(TradingSymbol, TimeFrame);
      int bars_tested = current_bars - s1_fork_start_bars;
      
      if(bars_tested >= ForkTestBars)
      {
         // Calculate current profitability for both original and fork
         double original_profit = CalculateStrategyProfitability(s1_magic);
         double fork_profit = CalculateStrategyProfitability(s1_fork_magic);
         
         double improvement = fork_profit - s1_fork_start_profit;
         double original_change = original_profit - s1_fork_start_profit;
         
         Print("=== Strategy 1 Fork Evaluation ===");
         Print("Original: Start=", DoubleToString(s1_fork_start_profit, 2), 
               "% Current=", DoubleToString(original_profit, 2), 
               "% Change=", DoubleToString(original_change, 2), "%");
         Print("Fork: Start=", DoubleToString(s1_fork_start_profit, 2), 
               "% Current=", DoubleToString(fork_profit, 2), 
               "% Change=", DoubleToString(improvement, 2), "%");
         Print("Bars tested: ", bars_tested, " / ", ForkTestBars);
         
         // Merge if fork is better by minimum improvement threshold
         if(improvement > original_change + ForkMinImprovement)
         {
            Print("=== MERGING Strategy 1 Fork ===");
            Print("Fork improvement (", DoubleToString(improvement, 2), 
                  "%) exceeds original (", DoubleToString(original_change, 2), 
                  "%) by ", DoubleToString(improvement - original_change, 2), "%");
            
            // Close all fork positions
            CloseAllPositions(s1_fork_magic);
            
            // Switch to fork parameters
            s1_current_params = s1_fork_params;
            s1_current_params.profitability = fork_profit;
            
            // Recreate indicators with fork parameters
            if(s1_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_rsi_handle);
            s1_rsi_handle = iRSI(TradingSymbol, TimeFrame, s1_current_params.rsi_period, PRICE_CLOSE);
            
            // Clean up fork
            if(s1_fork_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_rsi_handle);
            s1_fork_active = false;
            s1_fork_rsi_handle = INVALID_HANDLE;
            s1_fork_position_ticket = 0;
            
            Print("MERGE COMPLETE: Now using fork parameters");
         }
         else
         {
            Print("=== DISCARDING Strategy 1 Fork ===");
            Print("Fork did not improve enough. Keeping original parameters.");
            
            // Close all fork positions
            CloseAllPositions(s1_fork_magic);
            
            // Clean up fork
            if(s1_fork_rsi_handle != INVALID_HANDLE) IndicatorRelease(s1_fork_rsi_handle);
            s1_fork_active = false;
            s1_fork_rsi_handle = INVALID_HANDLE;
            s1_fork_position_ticket = 0;
         }
      }
   }
   else if(strategy_num == 2 && s2_fork_active)
   {
      int current_bars = Bars(TradingSymbol, TimeFrame);
      int bars_tested = current_bars - s2_fork_start_bars;
      
      if(bars_tested >= ForkTestBars)
      {
         // Calculate current profitability for both original and fork
         double original_profit = CalculateStrategyProfitability(s2_magic);
         double fork_profit = CalculateStrategyProfitability(s2_fork_magic);
         
         double improvement = fork_profit - s2_fork_start_profit;
         double original_change = original_profit - s2_fork_start_profit;
         
         Print("=== Strategy 2 Fork Evaluation ===");
         Print("Original: Start=", DoubleToString(s2_fork_start_profit, 2), 
               "% Current=", DoubleToString(original_profit, 2), 
               "% Change=", DoubleToString(original_change, 2), "%");
         Print("Fork: Start=", DoubleToString(s2_fork_start_profit, 2), 
               "% Current=", DoubleToString(fork_profit, 2), 
               "% Change=", DoubleToString(improvement, 2), "%");
         Print("Bars tested: ", bars_tested, " / ", ForkTestBars);
         
         // Merge if fork is better by minimum improvement threshold
         if(improvement > original_change + ForkMinImprovement)
         {
            Print("=== MERGING Strategy 2 Fork ===");
            Print("Fork improvement (", DoubleToString(improvement, 2), 
                  "%) exceeds original (", DoubleToString(original_change, 2), 
                  "%) by ", DoubleToString(improvement - original_change, 2), "%");
            
            // Close all fork positions
            CloseAllPositions(s2_fork_magic);
            
            // Switch to fork parameters
            s2_current_params = s2_fork_params;
            s2_current_params.profitability = fork_profit;
            
            // Recreate indicators with fork parameters
            if(s2_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_fast_handle);
            if(s2_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_ma_slow_handle);
            
            s2_ma_fast_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_fast, 0, s2_current_params.ma_method, PRICE_CLOSE);
            s2_ma_slow_handle = iMA(TradingSymbol, TimeFrame, s2_current_params.ma_slow, 0, s2_current_params.ma_method, PRICE_CLOSE);
            
            // Clean up fork
            if(s2_fork_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_fast_handle);
            if(s2_fork_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_slow_handle);
            s2_fork_active = false;
            s2_fork_ma_fast_handle = INVALID_HANDLE;
            s2_fork_ma_slow_handle = INVALID_HANDLE;
            s2_fork_position_ticket = 0;
            
            Print("MERGE COMPLETE: Now using fork parameters");
         }
         else
         {
            Print("=== DISCARDING Strategy 2 Fork ===");
            Print("Fork did not improve enough. Keeping original parameters.");
            
            // Close all fork positions
            CloseAllPositions(s2_fork_magic);
            
            // Clean up fork
            if(s2_fork_ma_fast_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_fast_handle);
            if(s2_fork_ma_slow_handle != INVALID_HANDLE) IndicatorRelease(s2_fork_ma_slow_handle);
            s2_fork_active = false;
            s2_fork_ma_fast_handle = INVALID_HANDLE;
            s2_fork_ma_slow_handle = INVALID_HANDLE;
            s2_fork_position_ticket = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate strategy profitability from positions                  |
//+------------------------------------------------------------------+
double CalculateStrategyProfitability(int magic)
{
   double total_profit = 0.0;
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Get all positions for this magic number
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            total_profit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   
   // Also check closed deals (history)
   HistorySelect(TimeCurrent() - 86400, TimeCurrent()); // Last 24 hours
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == TradingSymbol &&
            HistoryDealGetInteger(ticket, DEAL_MAGIC) == magic)
         {
            total_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }
   }
   
   if(account_balance > 0)
      return (total_profit / account_balance) * 100.0;
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Close all positions for a magic number                          |
//+------------------------------------------------------------------+
void CloseAllPositions(int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Run RSI Strategy Fork (parallel testing)                        |
//+------------------------------------------------------------------+
void RunRSIStrategyFork()
{
   trade.SetExpertMagicNumber(s1_fork_magic);
   
   datetime current_bar = iTime(TradingSymbol, TimeFrame, 0);
   if(current_bar == s1_fork_last_bar) return;
   s1_fork_last_bar = current_bar;
   
   // Get RSI data
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   if(CopyBuffer(s1_fork_rsi_handle, 0, 0, 3, rsi_buffer) < 3) return;
   
   // Check existing fork position for smart exits (same logic as original)
   if(s1_fork_position_ticket > 0)
   {
      if(!PositionSelectByTicket(s1_fork_position_ticket))
      {
         s1_fork_position_ticket = 0;
      }
      else
      {
         // Same exit logic as RunRSIStrategy but using fork params
         double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         double current_price = (position_type == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         
         int bars_held = (int)((current_bar - position_open_time) / PeriodSeconds(TimeFrame));
         if(bars_held >= s1_fork_params.max_bars)
         {
            trade.PositionClose(s1_fork_position_ticket);
            s1_fork_position_ticket = 0;
            return;
         }
         
         if(bars_held < s1_fork_params.min_bars) return;
         
         // Calculate current profit/loss
         double profit_pct = 0;
         if(position_type == POSITION_TYPE_BUY)
            profit_pct = ((current_price - position_open_price) / position_open_price) * 100.0;
         else
            profit_pct = ((position_open_price - current_price) / position_open_price) * 100.0;
         
         // LOSS PROTECTION: Maximum loss threshold
         if(profit_pct <= -MaxLossPercent)
         {
            Print("FORK S1: Force exit - Max loss exceeded: ", DoubleToString(profit_pct, 2), "%");
            trade.PositionClose(s1_fork_position_ticket);
            s1_fork_position_ticket = 0;
            s1_fork_entry_price = 0.0;
            return;
         }
         
         // LOSS PROTECTION: Adverse move detection (strong move against position)
         if(profit_pct < 0)
         {
            double adverse_move = MathAbs(profit_pct);
            if(adverse_move >= AdverseMoveThreshold)
            {
               // Get ATR for volatility check
               double atr_buffer[];
               ArraySetAsSeries(atr_buffer, true);
               if(CopyBuffer(s1_fork_atr_handle, 0, 0, 2, atr_buffer) >= 2)
               {
                  double current_atr = atr_buffer[0];
                  double prev_atr = atr_buffer[1];
                  
                  // Exit if adverse move exceeds threshold AND volatility is increasing
                  if(adverse_move >= AdverseMoveThreshold && current_atr > prev_atr * 1.2)
                  {
                     Print("FORK S1: Force exit - Adverse move detected: ", DoubleToString(profit_pct, 2), 
                           "% | ATR increased: ", DoubleToString(prev_atr, 2), " -> ", DoubleToString(current_atr, 2));
                     trade.PositionClose(s1_fork_position_ticket);
                     s1_fork_position_ticket = 0;
                     s1_fork_entry_price = 0.0;
                     return;
                  }
               }
            }
         }
         
         if(s1_fork_params.exit_on_reversal)
         {
            if(position_type == POSITION_TYPE_BUY)
            {
               if(rsi_buffer[0] < s1_fork_params.rsi_oversold && rsi_buffer[1] >= s1_fork_params.rsi_oversold)
               {
                  trade.PositionClose(s1_fork_position_ticket);
                  s1_fork_position_ticket = 0;
                  return;
               }
            }
            else
            {
               if(rsi_buffer[0] > s1_fork_params.rsi_overbought && rsi_buffer[1] <= s1_fork_params.rsi_overbought)
               {
                  trade.PositionClose(s1_fork_position_ticket);
                  s1_fork_position_ticket = 0;
                  return;
               }
            }
         }
         
         // RSI extreme exit (no profit requirement for fork)
         if(position_type == POSITION_TYPE_BUY && rsi_buffer[0] >= s1_fork_params.rsi_overbought)
         {
            trade.PositionClose(s1_fork_position_ticket);
            s1_fork_position_ticket = 0;
            return;
         }
         else if(position_type == POSITION_TYPE_SELL && rsi_buffer[0] <= s1_fork_params.rsi_oversold)
         {
            trade.PositionClose(s1_fork_position_ticket);
            s1_fork_position_ticket = 0;
            return;
         }
      }
   }
   
   // Check for new entry signals (using fork params)
   if(s1_fork_position_ticket == 0)
   {
      if(rsi_buffer[0] > s1_fork_params.rsi_oversold && rsi_buffer[1] <= s1_fork_params.rsi_oversold)
      {
         double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         if(trade.Buy(LotSize, TradingSymbol, 0, 0, 0, "S1 Fork: RSI Reversion"))
         {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s1_fork_magic)
                  {
                     s1_fork_position_ticket = PositionGetInteger(POSITION_TICKET);
                     s1_fork_entry_price = ask;
                     break;
                  }
               }
            }
         }
      }
      else if(rsi_buffer[0] < s1_fork_params.rsi_overbought && rsi_buffer[1] >= s1_fork_params.rsi_overbought)
      {
         double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
         if(trade.Sell(LotSize, TradingSymbol, 0, 0, 0, "S1 Fork: RSI Reversion"))
         {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s1_fork_magic)
                  {
                     s1_fork_position_ticket = PositionGetInteger(POSITION_TICKET);
                     s1_fork_entry_price = bid;
                     break;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Run MA Strategy Fork (parallel testing)                         |
//+------------------------------------------------------------------+
void RunMAStrategyFork()
{
   trade.SetExpertMagicNumber(s2_fork_magic);
   
   datetime current_bar = iTime(TradingSymbol, TimeFrame, 0);
   if(current_bar == s2_fork_last_bar) return;
   s2_fork_last_bar = current_bar;
   
   // Get MA data
   double ma_fast_buffer[];
   double ma_slow_buffer[];
   ArraySetAsSeries(ma_fast_buffer, true);
   ArraySetAsSeries(ma_slow_buffer, true);
   if(CopyBuffer(s2_fork_ma_fast_handle, 0, 0, 3, ma_fast_buffer) < 3) return;
   if(CopyBuffer(s2_fork_ma_slow_handle, 0, 0, 3, ma_slow_buffer) < 3) return;
   
   // Check existing fork position for smart exits (same logic as original)
   if(s2_fork_position_ticket > 0)
   {
      if(!PositionSelectByTicket(s2_fork_position_ticket))
      {
         s2_fork_position_ticket = 0;
      }
      else
      {
         // Same exit logic as RunMAStrategy but using fork params
         double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         double current_price = (position_type == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         
         int bars_held = (int)((current_bar - position_open_time) / PeriodSeconds(TimeFrame));
         if(bars_held >= s2_fork_params.max_bars)
         {
            trade.PositionClose(s2_fork_position_ticket);
            s2_fork_position_ticket = 0;
            return;
         }
         
         if(bars_held < s2_fork_params.min_bars) return;
         
         // Calculate current profit/loss
         double profit_pct = 0;
         if(position_type == POSITION_TYPE_BUY)
            profit_pct = ((current_price - position_open_price) / position_open_price) * 100.0;
         else
            profit_pct = ((position_open_price - current_price) / position_open_price) * 100.0;
         
         // LOSS PROTECTION: Maximum loss threshold
         if(profit_pct <= -MaxLossPercent)
         {
            Print("FORK S2: Force exit - Max loss exceeded: ", DoubleToString(profit_pct, 2), "%");
            trade.PositionClose(s2_fork_position_ticket);
            s2_fork_position_ticket = 0;
            s2_fork_entry_price = 0.0;
            return;
         }
         
         // LOSS PROTECTION: Adverse move detection (strong move against position)
         if(profit_pct < 0)
         {
            double adverse_move = MathAbs(profit_pct);
            if(adverse_move >= AdverseMoveThreshold)
            {
               // Get ATR for volatility check
               double atr_buffer[];
               ArraySetAsSeries(atr_buffer, true);
               if(CopyBuffer(s2_fork_atr_handle, 0, 0, 2, atr_buffer) >= 2)
               {
                  double current_atr = atr_buffer[0];
                  double prev_atr = atr_buffer[1];
                  
                  // Exit if adverse move exceeds threshold AND volatility is increasing
                  if(adverse_move >= AdverseMoveThreshold && current_atr > prev_atr * 1.2)
                  {
                     Print("FORK S2: Force exit - Adverse move detected: ", DoubleToString(profit_pct, 2), 
                           "% | ATR increased: ", DoubleToString(prev_atr, 2), " -> ", DoubleToString(current_atr, 2));
                     trade.PositionClose(s2_fork_position_ticket);
                     s2_fork_position_ticket = 0;
                     s2_fork_entry_price = 0.0;
                     return;
                  }
               }
            }
         }
         
         if(s2_fork_params.exit_on_reversal)
         {
            bool bearish_cross = (ma_fast_buffer[0] < ma_slow_buffer[0] && ma_fast_buffer[1] >= ma_slow_buffer[1]);
            bool bullish_cross = (ma_fast_buffer[0] > ma_slow_buffer[0] && ma_fast_buffer[1] <= ma_slow_buffer[1]);
            
            if(position_type == POSITION_TYPE_BUY && bearish_cross)
            {
               trade.PositionClose(s2_fork_position_ticket);
               s2_fork_position_ticket = 0;
               return;
            }
            else if(position_type == POSITION_TYPE_SELL && bullish_cross)
            {
               trade.PositionClose(s2_fork_position_ticket);
               s2_fork_position_ticket = 0;
               return;
            }
         }
         
         // Price/MA reversal exit (no profit requirement for fork)
         if(position_type == POSITION_TYPE_BUY && current_price < ma_slow_buffer[0])
         {
            trade.PositionClose(s2_fork_position_ticket);
            s2_fork_position_ticket = 0;
            return;
         }
         else if(position_type == POSITION_TYPE_SELL && current_price > ma_slow_buffer[0])
         {
            trade.PositionClose(s2_fork_position_ticket);
            s2_fork_position_ticket = 0;
            return;
         }
      }
   }
   
   // Check for new entry signals (using fork params)
   if(s2_fork_position_ticket == 0)
   {
      bool bullish_cross = (ma_fast_buffer[0] > ma_slow_buffer[0] && ma_fast_buffer[1] <= ma_slow_buffer[1]);
      bool bearish_cross = (ma_fast_buffer[0] < ma_slow_buffer[0] && ma_fast_buffer[1] >= ma_slow_buffer[1]);
      
      if(bullish_cross)
      {
         double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         if(trade.Buy(LotSize, TradingSymbol, 0, 0, 0, "S2 Fork: MA Crossover"))
         {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s2_fork_magic)
                  {
                     s2_fork_position_ticket = PositionGetInteger(POSITION_TICKET);
                     s2_fork_entry_price = ask;
                     break;
                  }
               }
            }
         }
      }
      else if(bearish_cross)
      {
         double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
         if(trade.Sell(LotSize, TradingSymbol, 0, 0, 0, "S2 Fork: MA Crossover"))
         {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               if(PositionGetTicket(i) > 0)
               {
                  if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
                     PositionGetInteger(POSITION_MAGIC) == s2_fork_magic)
                  {
                     s2_fork_position_ticket = PositionGetInteger(POSITION_TICKET);
                     s2_fork_entry_price = bid;
                     break;
                  }
               }
            }
         }
      }
   }
}
