//+------------------------------------------------------------------+
//|                                          simple-rsi-reversal.mq5 |
//|                                  Simple RSI Reversal Self-Optimizer |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Simple RSI Reversal Self-Optimizer"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Optimization Method Enum                                        |
//+------------------------------------------------------------------+
enum ENUM_OPTIMIZATION_METHOD
{
   OPT_GRID_SEARCH,      // Exhaustive grid search
   OPT_RANDOM_WALK,      // Random walk exploration
   OPT_UCB,              // Upper Confidence Bound (Multi-Armed Bandit)
   OPT_THOMPSON_SAMPLING // Thompson Sampling (Bayesian)
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input string TradingSymbol = "BTCUSD"; // Trading Symbol
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1; // Timeframe
input double LotSize = 0.01; // Lot Size
input int MagicNumber = 88000; // Magic Number
input int Slippage = 3; // Slippage

input group "=== Self-Optimization Settings ==="
input int OptimizationPeriodHours = 2; // Backtesting Period (Hours)
input int OptimizationPeriodMinutes = 0; // Additional Minutes (0-59)
input int OptimizationIntervalBars = 50; // Bars Between Optimizations
input int MinTradesForOptimization = 2; // Min Trades for Optimization
input bool EnableAutoOptimization = true; // Enable Auto Optimization
input double MinProfitabilityForKeep = 0.1; // Min Profitability % to Keep Parameters
input ENUM_OPTIMIZATION_METHOD OptimizationMethod = OPT_UCB; // Optimization Method
input double UCB_ExplorationFactor = 2.0; // UCB Exploration Factor (c)
input int MaxParameterArms = 50; // Max Parameter Arms to Track

input group "=== RSI Parameters (Initial/Range) ==="
input int RSI_Period_Start = 7; // RSI Period (Start)
input int RSI_Period_End = 21; // RSI Period (End)
input double RSI_Oversold_Start = 25.0; // RSI Oversold (Start)
input double RSI_Oversold_End = 35.0; // RSI Oversold (End)
input double RSI_Overbought_Start = 65.0; // RSI Overbought (Start)
input double RSI_Overbought_End = 75.0; // RSI Overbought (End)

input group "=== Exit Settings ==="
input int MaxBarsInTrade = 30; // Max Bars in Trade
input int MinBarsBeforeExit = 3; // Min Bars Before Exit
input bool ExitOnReversal = false; // Exit on Signal Reversal
input double MaxLossPercent = 0.5; // Max Loss % to Force Close
input double AdverseMoveThreshold = 0.15; // Adverse Move % to Trigger Exit

//+------------------------------------------------------------------+
//| Strategy Parameters Structure                                    |
//+------------------------------------------------------------------+
struct StrategyParams
{
   int rsi_period;
   double rsi_oversold;
   double rsi_overbought;
   double profitability;
};

//+------------------------------------------------------------------+
//| Parameter Arm Structure (for Multi-Armed Bandit)               |
//+------------------------------------------------------------------+
struct ParameterArm
{
   StrategyParams params;
   int pulls;              // Number of times this arm was tested
   double total_reward;    // Cumulative reward
   double mean_reward;     // Average reward
   double ucb_score;       // UCB score for selection
   datetime last_tested;   // Last time this arm was tested
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
StrategyParams current_params;
int rsi_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int last_optimization_bar = 0;
int bars_since_optimization = 0;

// Multi-Armed Bandit variables
ParameterArm parameter_arms[];
int total_arm_pulls = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize parameters
   current_params.rsi_period = RSI_Period_Start;
   current_params.rsi_oversold = RSI_Oversold_Start;
   current_params.rsi_overbought = RSI_Overbought_Start;
   current_params.profitability = 0.0;
   
   // Create indicators
   rsi_handle = iRSI(TradingSymbol, TimeFrame, current_params.rsi_period, PRICE_CLOSE);
   atr_handle = iATR(TradingSymbol, TimeFrame, 14);
   
   if(rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators");
      return INIT_FAILED;
   }
   
   // Set magic number
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Perform initial optimization
   if(EnableAutoOptimization)
   {
      OptimizeStrategy();
   }
   
   Print("=== Simple RSI Reversal Strategy Initialized ===");
   Print("RSI Period: ", current_params.rsi_period, 
         " Oversold: ", DoubleToString(current_params.rsi_oversold, 1),
         " Overbought: ", DoubleToString(current_params.rsi_overbought, 1));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we need to optimize
   if(EnableAutoOptimization)
   {
      int current_bar = iBars(TradingSymbol, TimeFrame);
      if(current_bar > last_optimization_bar)
      {
         bars_since_optimization++;
         if(bars_since_optimization >= OptimizationIntervalBars)
         {
            OptimizeStrategy();
            bars_since_optimization = 0;
         }
      }
      last_optimization_bar = current_bar;
   }
   
   // Run the strategy
   RunStrategy();
}

//+------------------------------------------------------------------+
//| Optimize Strategy                                                |
//+------------------------------------------------------------------+
void OptimizeStrategy()
{
   Print("=== Starting Self-Optimization ===");
   
   // Calculate backtesting period
   datetime end_time = TimeCurrent();
   int total_minutes = OptimizationPeriodHours * 60 + OptimizationPeriodMinutes;
   datetime start_time = end_time - (total_minutes * 60);
   
   Print("Backtesting period: Last ", OptimizationPeriodHours, " hour(s) (", total_minutes, " minutes total)");
   Print("Period: ", TimeToString(start_time), " to ", TimeToString(end_time));
   
   // Update current live profitability
   current_params.profitability = CalculateStrategyProfitability();
   Print("Current Live Profitability: ", DoubleToString(current_params.profitability, 2), "%");
   
   // Test parameter combinations based on optimization method
   StrategyParams best_params = current_params;
   double best_profitability = current_params.profitability;
   int tests_run = 0;
   
   if(OptimizationMethod == OPT_GRID_SEARCH)
   {
      // Exhaustive grid search
      best_params = OptimizeGridSearch(start_time, end_time, tests_run);
      best_profitability = best_params.profitability;
   }
   else if(OptimizationMethod == OPT_RANDOM_WALK)
   {
      // Random walk exploration
      best_params = OptimizeRandomWalk(start_time, end_time, tests_run);
      best_profitability = best_params.profitability;
   }
   else if(OptimizationMethod == OPT_UCB)
   {
      // Upper Confidence Bound (Multi-Armed Bandit)
      best_params = OptimizeUCB(start_time, end_time, tests_run);
      best_profitability = best_params.profitability;
   }
   else if(OptimizationMethod == OPT_THOMPSON_SAMPLING)
   {
      // Thompson Sampling (Bayesian Multi-Armed Bandit)
      best_params = OptimizeThompsonSampling(start_time, end_time, tests_run);
      best_profitability = best_params.profitability;
   }
   
   Print("Optimization Results: Tests Run=", tests_run, " Current=", 
         DoubleToString(current_params.profitability, 2), "% Best Found=", 
         DoubleToString(best_profitability, 2), "%");
   
   // Update parameters if better ones found
   if(best_profitability > current_params.profitability + MinProfitabilityForKeep)
   {
      Print("Updating parameters to better set");
      current_params = best_params;
      
      // Recreate RSI indicator with new period
      if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
      rsi_handle = iRSI(TradingSymbol, TimeFrame, current_params.rsi_period, PRICE_CLOSE);
      
      if(rsi_handle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to recreate RSI indicator");
      }
      else
      {
         Print("Strategy Updated - RSI Period: ", current_params.rsi_period, 
               " Oversold: ", DoubleToString(current_params.rsi_oversold, 1),
               " Overbought: ", DoubleToString(current_params.rsi_overbought, 1),
               " Expected Profit: ", DoubleToString(best_profitability, 2), "%");
      }
   }
   else
   {
      Print("Keeping current parameters. Current Profit: ", 
            DoubleToString(current_params.profitability, 2), "% Best Found: ", 
            DoubleToString(best_profitability, 2), "%");
   }
   
   Print("=== Self-Optimization Complete ===");
}

//+------------------------------------------------------------------+
//| Grid Search Optimization                                        |
//+------------------------------------------------------------------+
StrategyParams OptimizeGridSearch(datetime start_time, datetime end_time, int &tests_run)
{
   Print("Using GRID SEARCH optimization method");
   StrategyParams best_params = current_params;
   double best_profitability = current_params.profitability;
   
   // Exhaustive grid search
   for(int rsi_period = RSI_Period_Start; rsi_period <= RSI_Period_End; rsi_period += 2)
   {
      for(double oversold = RSI_Oversold_Start; oversold <= RSI_Oversold_End; oversold += 2.5)
      {
         for(double overbought = RSI_Overbought_Start; overbought <= RSI_Overbought_End; overbought += 2.5)
         {
            if(oversold >= overbought) continue;
            
            StrategyParams test_params;
            test_params.rsi_period = rsi_period;
            test_params.rsi_oversold = oversold;
            test_params.rsi_overbought = overbought;
            
            double profitability = BacktestStrategy(test_params, start_time, end_time);
            tests_run++;
            
            if(profitability > best_profitability)
            {
               best_profitability = profitability;
               best_params = test_params;
               best_params.profitability = profitability;
            }
         }
      }
   }
   
   return best_params;
}

//+------------------------------------------------------------------+
//| Random Walk Optimization                                        |
//+------------------------------------------------------------------+
StrategyParams OptimizeRandomWalk(datetime start_time, datetime end_time, int &tests_run)
{
   Print("Using RANDOM WALK optimization method");
   StrategyParams best_params = current_params;
   double best_profitability = current_params.profitability;
   
   // Start from current parameters
   StrategyParams current = current_params;
   int max_steps = 30; // Number of random steps
   
   for(int step = 0; step < max_steps; step++)
   {
      // Random walk: small random changes to current parameters
      StrategyParams test_params = current;
      
      // Random walk in parameter space
      int period_change = (MathRand() % 5) - 2; // -2 to +2
      test_params.rsi_period = (int)MathMax(RSI_Period_Start, 
                                            MathMin(RSI_Period_End, current.rsi_period + period_change));
      
      double oversold_change = (MathRand() % 11 - 5) * 0.5; // -2.5 to +2.5
      test_params.rsi_oversold = MathMax(RSI_Oversold_Start, 
                                        MathMin(RSI_Oversold_End, current.rsi_oversold + oversold_change));
      
      double overbought_change = (MathRand() % 11 - 5) * 0.5; // -2.5 to +2.5
      test_params.rsi_overbought = MathMax(RSI_Overbought_Start, 
                                           MathMin(RSI_Overbought_End, current.rsi_overbought + overbought_change));
      
      if(test_params.rsi_oversold >= test_params.rsi_overbought) continue;
      
      double profitability = BacktestStrategy(test_params, start_time, end_time);
      tests_run++;
      
      // Accept if better, or with probability if worse (simulated annealing)
      if(profitability > best_profitability)
      {
         best_profitability = profitability;
         best_params = test_params;
         best_params.profitability = profitability;
         current = test_params; // Move to better position
      }
      else if(profitability > current.profitability)
      {
         current = test_params; // Accept improvement
      }
      // With small probability, accept worse (exploration)
      else if(MathRand() % 100 < 10) // 10% chance
      {
         current = test_params; // Random exploration
      }
   }
   
   return best_params;
}

//+------------------------------------------------------------------+
//| UCB (Upper Confidence Bound) Multi-Armed Bandit                 |
//+------------------------------------------------------------------+
StrategyParams OptimizeUCB(datetime start_time, datetime end_time, int &tests_run)
{
   Print("Using UCB (Multi-Armed Bandit) optimization method");
   
   // Initialize or update parameter arms
   if(ArraySize(parameter_arms) == 0)
   {
      // First time: create initial arms from grid
      InitializeParameterArms();
   }
   
   // Select arms to test using UCB
   int arms_to_test = MathMin(20, ArraySize(parameter_arms)); // Test top 20 arms
   
   for(int i = 0; i < arms_to_test; i++)
   {
      // Select arm with highest UCB score
      int selected_arm = SelectUCBArm();
      
      if(selected_arm < 0 || selected_arm >= ArraySize(parameter_arms)) break;
      
      // Test this arm
      double profitability = BacktestStrategy(parameter_arms[selected_arm].params, start_time, end_time);
      tests_run++;
      
      // Update arm statistics
      parameter_arms[selected_arm].pulls++;
      parameter_arms[selected_arm].total_reward += profitability;
      parameter_arms[selected_arm].mean_reward = parameter_arms[selected_arm].total_reward / 
                                                 parameter_arms[selected_arm].pulls;
      parameter_arms[selected_arm].last_tested = TimeCurrent();
      total_arm_pulls++;
      
      // Update UCB score
      UpdateUCBScores();
      
      // Add new random arm occasionally (exploration)
      if(MathRand() % 100 < 15 && ArraySize(parameter_arms) < MaxParameterArms) // 15% chance
      {
         AddRandomArm();
      }
   }
   
   // Find best arm based on mean reward
   int best_arm = 0;
   double best_reward = parameter_arms[0].mean_reward;
   for(int i = 1; i < ArraySize(parameter_arms); i++)
   {
      if(parameter_arms[i].pulls > 0 && parameter_arms[i].mean_reward > best_reward)
      {
         best_reward = parameter_arms[i].mean_reward;
         best_arm = i;
      }
   }
   
   StrategyParams result = parameter_arms[best_arm].params;
   result.profitability = parameter_arms[best_arm].mean_reward;
   
   return result;
}

//+------------------------------------------------------------------+
//| Thompson Sampling (Bayesian Multi-Armed Bandit)                 |
//+------------------------------------------------------------------+
StrategyParams OptimizeThompsonSampling(datetime start_time, datetime end_time, int &tests_run)
{
   Print("Using THOMPSON SAMPLING (Bayesian) optimization method");
   
   // Initialize arms if needed
   if(ArraySize(parameter_arms) == 0)
   {
      InitializeParameterArms();
   }
   
   int arms_to_test = MathMin(20, ArraySize(parameter_arms));
   
   for(int i = 0; i < arms_to_test; i++)
   {
      // Select arm using Thompson Sampling
      int selected_arm = SelectThompsonSamplingArm();
      
      if(selected_arm < 0 || selected_arm >= ArraySize(parameter_arms)) break;
      
      // Test this arm
      double profitability = BacktestStrategy(parameter_arms[selected_arm].params, start_time, end_time);
      tests_run++;
      
      // Update Bayesian parameters (alpha, beta for Beta distribution)
      // Normalize profitability to [0, 1] for Beta distribution
      double normalized_reward = (profitability + 100.0) / 200.0; // Assume range [-100, 100]
      normalized_reward = MathMax(0.0, MathMin(1.0, normalized_reward));
      
      // Update arm statistics
      parameter_arms[selected_arm].pulls++;
      parameter_arms[selected_arm].total_reward += profitability;
      parameter_arms[selected_arm].mean_reward = parameter_arms[selected_arm].total_reward / 
                                                 parameter_arms[selected_arm].pulls;
      parameter_arms[selected_arm].last_tested = TimeCurrent();
      total_arm_pulls++;
      
      // Add new random arm occasionally
      if(MathRand() % 100 < 15 && ArraySize(parameter_arms) < MaxParameterArms)
      {
         AddRandomArm();
      }
   }
   
   // Find best arm
   int best_arm = 0;
   double best_reward = parameter_arms[0].mean_reward;
   for(int i = 1; i < ArraySize(parameter_arms); i++)
   {
      if(parameter_arms[i].pulls > 0 && parameter_arms[i].mean_reward > best_reward)
      {
         best_reward = parameter_arms[i].mean_reward;
         best_arm = i;
      }
   }
   
   StrategyParams result = parameter_arms[best_arm].params;
   result.profitability = parameter_arms[best_arm].mean_reward;
   
   return result;
}

//+------------------------------------------------------------------+
//| Initialize Parameter Arms                                        |
//+------------------------------------------------------------------+
void InitializeParameterArms()
{
   ArrayResize(parameter_arms, 0);
   
   // Create initial arms from grid (sparse sampling)
   for(int rsi_period = RSI_Period_Start; rsi_period <= RSI_Period_End; rsi_period += 3)
   {
      for(double oversold = RSI_Oversold_Start; oversold <= RSI_Oversold_End; oversold += 5.0)
      {
         for(double overbought = RSI_Overbought_Start; overbought <= RSI_Overbought_End; overbought += 5.0)
         {
            if(oversold >= overbought) continue;
            
            ParameterArm arm;
            arm.params.rsi_period = rsi_period;
            arm.params.rsi_oversold = oversold;
            arm.params.rsi_overbought = overbought;
            arm.params.profitability = 0.0;
            arm.pulls = 0;
            arm.total_reward = 0.0;
            arm.mean_reward = 0.0;
            arm.ucb_score = 999999.0; // High initial score for exploration
            arm.last_tested = 0;
            
            ArrayResize(parameter_arms, ArraySize(parameter_arms) + 1);
            parameter_arms[ArraySize(parameter_arms) - 1] = arm;
            
            if(ArraySize(parameter_arms) >= MaxParameterArms) break;
         }
         if(ArraySize(parameter_arms) >= MaxParameterArms) break;
      }
      if(ArraySize(parameter_arms) >= MaxParameterArms) break;
   }
   
   Print("Initialized ", ArraySize(parameter_arms), " parameter arms");
}

//+------------------------------------------------------------------+
//| Select Arm Using UCB                                             |
//+------------------------------------------------------------------+
int SelectUCBArm()
{
   if(ArraySize(parameter_arms) == 0) return -1;
   
   int best_arm = 0;
   double best_ucb = -999999.0;
   
   for(int i = 0; i < ArraySize(parameter_arms); i++)
   {
      UpdateUCBScore(i);
      if(parameter_arms[i].ucb_score > best_ucb)
      {
         best_ucb = parameter_arms[i].ucb_score;
         best_arm = i;
      }
   }
   
   return best_arm;
}

//+------------------------------------------------------------------+
//| Update UCB Score for Single Arm                                  |
//+------------------------------------------------------------------+
void UpdateUCBScore(int arm_index)
{
   if(arm_index < 0 || arm_index >= ArraySize(parameter_arms)) return;
   
   if(parameter_arms[arm_index].pulls == 0)
   {
      parameter_arms[arm_index].ucb_score = 999999.0; // Never pulled, high priority
   }
   else
   {
      // UCB formula: mean_reward + c * sqrt(ln(total_pulls) / pulls)
      double exploration = UCB_ExplorationFactor * MathSqrt(MathLog(total_arm_pulls) / parameter_arms[arm_index].pulls);
      parameter_arms[arm_index].ucb_score = parameter_arms[arm_index].mean_reward + exploration;
   }
}

//+------------------------------------------------------------------+
//| Update All UCB Scores                                            |
//+------------------------------------------------------------------+
void UpdateUCBScores()
{
   for(int i = 0; i < ArraySize(parameter_arms); i++)
   {
      UpdateUCBScore(i);
   }
}

//+------------------------------------------------------------------+
//| Select Arm Using Thompson Sampling                               |
//+------------------------------------------------------------------+
int SelectThompsonSamplingArm()
{
   if(ArraySize(parameter_arms) == 0) return -1;
   
   int best_arm = 0;
   double best_sample = -999999.0;
   
   for(int i = 0; i < ArraySize(parameter_arms); i++)
   {
      // Sample from Beta distribution (approximation)
      // Beta(alpha, beta) where alpha = wins + 1, beta = losses + 1
      double mean = parameter_arms[i].mean_reward;
      double pulls = parameter_arms[i].pulls;
      
      // Normalize mean to [0, 1]
      double normalized_mean = (mean + 100.0) / 200.0;
      normalized_mean = MathMax(0.01, MathMin(0.99, normalized_mean));
      
      // Estimate alpha and beta
      double alpha = normalized_mean * pulls + 1.0;
      double beta = (1.0 - normalized_mean) * pulls + 1.0;
      
      // Sample from Beta (simplified: use normal approximation)
      double sample = normalized_mean + (MathRand() / 32767.0 - 0.5) * 0.2;
      sample = MathMax(0.0, MathMin(1.0, sample));
      
      // Convert back to profitability scale
      sample = sample * 200.0 - 100.0;
      
      if(sample > best_sample)
      {
         best_sample = sample;
         best_arm = i;
      }
   }
   
   return best_arm;
}

//+------------------------------------------------------------------+
//| Add Random Parameter Arm                                         |
//+------------------------------------------------------------------+
void AddRandomArm()
{
   ParameterArm arm;
   arm.params.rsi_period = (int)(RSI_Period_Start + MathRand() % (RSI_Period_End - RSI_Period_Start + 1));
   arm.params.rsi_oversold = RSI_Oversold_Start + 
                            (MathRand() % (int)((RSI_Oversold_End - RSI_Oversold_Start) * 10 + 1)) / 10.0;
   arm.params.rsi_overbought = RSI_Overbought_Start + 
                              (MathRand() % (int)((RSI_Overbought_End - RSI_Overbought_Start) * 10 + 1)) / 10.0;
   
   if(arm.params.rsi_oversold >= arm.params.rsi_overbought) return;
   
   arm.params.profitability = 0.0;
   arm.pulls = 0;
   arm.total_reward = 0.0;
   arm.mean_reward = 0.0;
   arm.ucb_score = 999999.0;
   arm.last_tested = 0;
   
   ArrayResize(parameter_arms, ArraySize(parameter_arms) + 1);
   parameter_arms[ArraySize(parameter_arms) - 1] = arm;
}

//+------------------------------------------------------------------+
//| Backtest Strategy                                                |
//+------------------------------------------------------------------+
double BacktestStrategy(StrategyParams &params, datetime start_time, datetime end_time)
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
   
   // Calculate how many bars we need
   int period_seconds = PeriodSeconds(TimeFrame);
   int bars_needed = (int)((end_time - start_time) / period_seconds) + 20;
   
   // Get bars from end_time going backwards
   int end_bar = iBarShift(TradingSymbol, TimeFrame, end_time, false);
   if(end_bar < 0) end_bar = 0;
   
   int start_bar = end_bar + bars_needed;
   int max_bars = Bars(TradingSymbol, TimeFrame);
   if(start_bar >= max_bars) 
   {
      start_bar = max_bars - 1;
      bars_needed = start_bar - end_bar;
   }
   
   int bars_to_test = start_bar - end_bar;
   
   if(bars_to_test < 5)
   {
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
   
   // Copy data
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
   
   // Iterate through historical bars (from oldest to newest)
   for(int i = bars_to_test - 1; i >= 1; i--)
   {
      datetime bar_time = time_buffer[i];
      double current_rsi = rsi_buffer[i];
      double prev_rsi = rsi_buffer[i-1];
      double current_price = close_buffer[i];
      
      // Check existing virtual position
      if(virtual_position > 0)
      {
         // Check exit conditions
         int bars_held = (int)((bar_time - virtual_entry_time) / period_seconds);
         
         // Time-based exit
         if(bars_held >= MaxBarsInTrade)
         {
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
         // Signal reversal exit
         else if(ExitOnReversal && bars_held >= MinBarsBeforeExit)
         {
            bool should_exit = false;
            if(virtual_position_type == POSITION_TYPE_BUY && current_rsi > params.rsi_overbought)
               should_exit = true;
            else if(virtual_position_type == POSITION_TYPE_SELL && current_rsi < params.rsi_oversold)
               should_exit = true;
            
            if(should_exit)
            {
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
         }
         // RSI extreme exit (if in profit)
         else if(bars_held >= MinBarsBeforeExit)
         {
            double profit_pct = 0;
            if(virtual_position_type == POSITION_TYPE_BUY)
               profit_pct = ((current_price - virtual_entry) / virtual_entry) * 100.0;
            else
               profit_pct = ((virtual_entry - current_price) / virtual_entry) * 100.0;
            
            // Exit if RSI reaches opposite extreme and we're in profit
            if(profit_pct > 0.05)
            {
               bool should_exit = false;
               if(virtual_position_type == POSITION_TYPE_BUY && current_rsi > params.rsi_overbought)
                  should_exit = true;
               else if(virtual_position_type == POSITION_TYPE_SELL && current_rsi < params.rsi_oversold)
                  should_exit = true;
               
               if(should_exit)
               {
                  double profit = profit_pct / 100.0;
                  total_profit += profit;
                  total_trades++;
                  winning_trades++;
                  virtual_position = 0;
               }
            }
         }
      }
      
      // Check for new entry signals (only if no position)
      if(virtual_position == 0)
      {
         // Buy signal: RSI crosses above oversold
         if(prev_rsi < params.rsi_oversold && current_rsi >= params.rsi_oversold)
         {
            virtual_position = 1;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_BUY;
         }
         // Sell signal: RSI crosses below overbought
         else if(prev_rsi > params.rsi_overbought && current_rsi <= params.rsi_overbought)
         {
            virtual_position = 1;
            virtual_entry = current_price;
            virtual_entry_time = bar_time;
            virtual_position_type = POSITION_TYPE_SELL;
         }
      }
   }
   
   // Close any remaining position at end
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
   
   // Check if we have enough trades
   if(total_trades < MinTradesForOptimization)
   {
      if(total_trades > 0)
      {
         // Return scaled negative value if some trades but not enough
         return (total_profit * 100.0) - (MinTradesForOptimization - total_trades) * 10.0;
      }
      return -999999.0;
   }
   
   // Return profitability percentage
   return total_profit * 100.0;
}

//+------------------------------------------------------------------+
//| Run Strategy                                                     |
//+------------------------------------------------------------------+
void RunStrategy()
{
   // Check if indicators are ready
   if(rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE) return;
   
   double rsi_buffer[];
   double close_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   ArraySetAsSeries(close_buffer, true);
   
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) < 3) return;
   if(CopyClose(TradingSymbol, TimeFrame, 0, 3, close_buffer) < 3) return;
   
   double current_rsi = rsi_buffer[0];
   double prev_rsi = rsi_buffer[1];
   double current_price = close_buffer[0];
   
   // Check existing positions
   if(PositionSelect(TradingSymbol))
   {
      ulong pos_ticket = PositionGetInteger(POSITION_TICKET);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         // Get position details
         double pos_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         datetime pos_open_time = (datetime)PositionGetInteger(POSITION_TIME);
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Calculate bars held
         datetime current_time = TimeCurrent();
         int period_seconds = PeriodSeconds(TimeFrame);
         int bars_held = (int)((current_time - pos_open_time) / period_seconds);
         
         // Loss protection
         double profit_pct = 0;
         if(pos_type == POSITION_TYPE_BUY)
            profit_pct = ((current_price - pos_open_price) / pos_open_price) * 100.0;
         else
            profit_pct = ((pos_open_price - current_price) / pos_open_price) * 100.0;
         
         // Max loss exit
         if(profit_pct < -MaxLossPercent)
         {
            trade.PositionClose(pos_ticket);
            Print("Position closed due to max loss: ", DoubleToString(profit_pct, 2), "%");
            return;
         }
         
         // Adverse move detection with ATR
         double atr_buffer[];
         ArraySetAsSeries(atr_buffer, true);
         if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) >= 1)
         {
            double atr_value = atr_buffer[0];
            double adverse_move = (atr_value / current_price) * 100.0;
            
            if(profit_pct < -AdverseMoveThreshold && adverse_move > AdverseMoveThreshold)
            {
               trade.PositionClose(pos_ticket);
               Print("Position closed due to adverse move: ", DoubleToString(profit_pct, 2), "%");
               return;
            }
         }
         
         // Time-based exit
         if(bars_held >= MaxBarsInTrade)
         {
            trade.PositionClose(pos_ticket);
            Print("Position closed due to max bars: ", bars_held);
            return;
         }
         
         // Signal reversal exit
         if(ExitOnReversal && bars_held >= MinBarsBeforeExit)
         {
            bool should_exit = false;
            if(pos_type == POSITION_TYPE_BUY && current_rsi > current_params.rsi_overbought)
               should_exit = true;
            else if(pos_type == POSITION_TYPE_SELL && current_rsi < current_params.rsi_oversold)
               should_exit = true;
            
            if(should_exit)
            {
               trade.PositionClose(pos_ticket);
               Print("Position closed due to signal reversal");
               return;
            }
         }
         
         // RSI extreme exit (if in profit)
         if(bars_held >= MinBarsBeforeExit && profit_pct > 0.05)
         {
            bool should_exit = false;
            if(pos_type == POSITION_TYPE_BUY && current_rsi > current_params.rsi_overbought)
               should_exit = true;
            else if(pos_type == POSITION_TYPE_SELL && current_rsi < current_params.rsi_oversold)
               should_exit = true;
            
            if(should_exit)
            {
               trade.PositionClose(pos_ticket);
               Print("Position closed due to RSI extreme: ", DoubleToString(profit_pct, 2), "%");
               return;
            }
         }
         
         return; // Position exists, don't open new one
      }
   }
   
   // Check for new entry signals
   // Buy signal: RSI crosses above oversold
   if(prev_rsi < current_params.rsi_oversold && current_rsi >= current_params.rsi_oversold)
   {
      double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
      if(trade.Buy(LotSize, TradingSymbol, ask, 0, 0, "RSI Reversal Buy"))
      {
         Print("Buy order opened: RSI=", DoubleToString(current_rsi, 2), 
               " Oversold=", DoubleToString(current_params.rsi_oversold, 1));
      }
   }
   // Sell signal: RSI crosses below overbought
   else if(prev_rsi > current_params.rsi_overbought && current_rsi <= current_params.rsi_overbought)
   {
      double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
      if(trade.Sell(LotSize, TradingSymbol, bid, 0, 0, "RSI Reversal Sell"))
      {
         Print("Sell order opened: RSI=", DoubleToString(current_rsi, 2), 
               " Overbought=", DoubleToString(current_params.rsi_overbought, 1));
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Strategy Profitability                                |
//+------------------------------------------------------------------+
double CalculateStrategyProfitability()
{
   double total_profit = 0.0;
   
   // Check open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == TradingSymbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                                  SymbolInfoDouble(TradingSymbol, SYMBOL_BID) :
                                  SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
            
            double profit = 0;
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               profit = (current_price - open_price) / open_price;
            else
               profit = (open_price - current_price) / open_price;
            
            total_profit += profit * PositionGetDouble(POSITION_VOLUME) / LotSize;
         }
      }
   }
   
   // Check historical deals (last 24 hours)
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - 86400; // 24 hours
   
   if(HistorySelect(start_time, end_time))
   {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) == TradingSymbol &&
               HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
            {
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
               double open_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
               
               if(open_price > 0)
               {
                  double profit_pct = (profit / (open_price * volume)) * 100.0;
                  total_profit += profit_pct / 100.0;
               }
            }
         }
      }
   }
   
   return total_profit * 100.0; // Return as percentage
}
//+------------------------------------------------------------------+
