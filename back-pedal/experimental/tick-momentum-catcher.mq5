//+------------------------------------------------------------------+
//|                                          tick-momentum-catcher.mq5 |
//|                                  Tick-Level Momentum Catcher for BTCUSD |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Tick Momentum Catcher"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input string TradingSymbol = "BTCUSD"; // Trading Symbol
input double LotSize = 0.01; // Lot Size
input int MagicNumber = 88010; // Magic Number
input int Slippage = 3; // Slippage

input group "=== Tick Momentum Settings ==="
input int TickWindow = 20; // Tick Window for Momentum Calculation
input double MinTickMomentum = 0.05; // Min Tick Momentum % (0.05 = 0.05%)
input double VolumeSpikeMultiplier = 2.0; // Volume Spike Multiplier
input int MinTicksForSignal = 3; // Min Consecutive Ticks for Signal
input double OrderFlowImbalance = 1.5; // Order Flow Imbalance Ratio (1.5 = 50% more)

input group "=== Entry Settings ==="
input double EntryMomentumThreshold = 0.1; // Entry Momentum Threshold %
input int MaxBarsHold = 5; // Max Bars to Hold Position (1 minute bars)
input double MaxLossPercent = 0.3; // Max Loss % to Force Close
input double TakeProfitPercent = 0.15; // Take Profit % (0.15 = 0.15%)
input double StopLossPercent = 0.1; // Stop Loss % (0.1 = 0.1%)

input group "=== Self-Optimization ==="
input bool EnableAutoOptimization = true; // Enable Auto Optimization
input int OptimizationIntervalBars = 100; // Bars Between Optimizations
input int OptimizationPeriodMinutes = 30; // Backtesting Period (Minutes)

//+------------------------------------------------------------------+
//| Tick Data Structure                                              |
//+------------------------------------------------------------------+
struct TickData
{
   double price;
   ulong volume; // Match MqlTick.volume type (ulong)
   datetime time;
   bool is_buy; // true if price moved up, false if down
   double momentum; // Price change percentage
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
TickData tick_buffer[];
int tick_buffer_size = 1000;
int last_optimization_bar = 0;
int bars_since_optimization = 0;

// Current momentum tracking
double current_momentum = 0.0;
int consecutive_buy_ticks = 0;
int consecutive_sell_ticks = 0;
double buy_volume_sum = 0.0;
double sell_volume_sum = 0.0;

// Position tracking
datetime position_entry_time = 0;
double position_entry_price = 0.0;
ENUM_POSITION_TYPE position_type = WRONG_VALUE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(tick_buffer, tick_buffer_size);
   ArraySetAsSeries(tick_buffer, false); // New ticks at end
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   Print("=== Tick Momentum Catcher Initialized ===");
   Print("Symbol: ", TradingSymbol);
   Print("Tick Window: ", TickWindow);
   Print("Min Momentum: ", MinTickMomentum, "%");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ArrayFree(tick_buffer);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Get current tick
   MqlTick tick;
   if(!SymbolInfoTick(TradingSymbol, tick))
   {
      return;
   }
   
   // Process tick
   ProcessTick(tick);
   
   // Check for optimization
   if(EnableAutoOptimization)
   {
      int current_bar = iBars(TradingSymbol, PERIOD_M1);
      if(current_bar > last_optimization_bar)
      {
         bars_since_optimization++;
         if(bars_since_optimization >= OptimizationIntervalBars)
         {
            OptimizeParameters();
            bars_since_optimization = 0;
         }
      }
      last_optimization_bar = current_bar;
   }
   
   // Check existing position
   CheckPosition();
   
   // Look for entry signals
   if(!PositionSelect(TradingSymbol))
   {
      CheckEntrySignals();
   }
}

//+------------------------------------------------------------------+
//| Process Tick Data                                                |
//+------------------------------------------------------------------+
void ProcessTick(MqlTick &tick)
{
   static double last_price = 0.0;
   static datetime last_time = 0;
   
   if(last_price == 0.0)
   {
      last_price = tick.last;
      last_time = tick.time;
      return;
   }
   
   // Calculate momentum
   double price_change = tick.last - last_price;
   double momentum_pct = 0.0;
   if(last_price > 0)
   {
      momentum_pct = (price_change / last_price) * 100.0;
   }
   
   // Determine if buy or sell tick
   bool is_buy = (price_change > 0);
   
   // Add to buffer (circular buffer)
   static int tick_index = 0;
   tick_buffer[tick_index].price = tick.last;
   tick_buffer[tick_index].volume = tick.volume; // ulong type matches
   tick_buffer[tick_index].time = tick.time;
   tick_buffer[tick_index].is_buy = is_buy;
   tick_buffer[tick_index].momentum = momentum_pct;
   
   tick_index++;
   if(tick_index >= tick_buffer_size) tick_index = 0;
   
   // Update momentum tracking
   UpdateMomentumTracking(is_buy, momentum_pct, (double)(long)tick.volume); // Convert ulong to double via long
   
   last_price = tick.last;
   last_time = tick.time;
}

//+------------------------------------------------------------------+
//| Update Momentum Tracking                                         |
//+------------------------------------------------------------------+
void UpdateMomentumTracking(bool is_buy, double momentum, double volume)
{
   // Track consecutive ticks
   if(is_buy)
   {
      consecutive_buy_ticks++;
      consecutive_sell_ticks = 0;
      buy_volume_sum += volume;
   }
   else
   {
      consecutive_sell_ticks++;
      consecutive_buy_ticks = 0;
      sell_volume_sum += volume;
   }
   
   // Calculate current momentum from recent ticks
   int recent_ticks = MathMin(TickWindow, tick_buffer_size);
   double momentum_sum = 0.0;
   int count = 0;
   
   for(int i = tick_buffer_size - 1; i >= 0 && count < recent_ticks; i--)
   {
      if(tick_buffer[i].price > 0)
      {
         momentum_sum += MathAbs(tick_buffer[i].momentum);
         count++;
      }
   }
   
   if(count > 0)
   {
      current_momentum = momentum_sum / count;
   }
}

//+------------------------------------------------------------------+
//| Check Entry Signals                                              |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   // Get current price
   double ask = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
   
   // Calculate order flow imbalance
   double order_flow_ratio = 0.0;
   if(sell_volume_sum > 0)
   {
      order_flow_ratio = buy_volume_sum / sell_volume_sum;
   }
   else if(buy_volume_sum > 0)
   {
      order_flow_ratio = 999.0; // All buy volume
   }
   
   // Check for violent momentum (use optimized value if available)
   double momentum_threshold = (optimized_min_tick_momentum > 0.0) ? optimized_min_tick_momentum : MinTickMomentum;
   bool violent_momentum = (current_momentum >= momentum_threshold);
   
   // Check for consecutive ticks in same direction
   bool strong_buy_signal = (consecutive_buy_ticks >= MinTicksForSignal);
   bool strong_sell_signal = (consecutive_sell_ticks >= MinTicksForSignal);
   
   // Check order flow imbalance (use optimized value if available)
   double imbalance_threshold = (optimized_order_flow_imbalance > 0.0) ? optimized_order_flow_imbalance : OrderFlowImbalance;
   bool buy_imbalance = (order_flow_ratio >= imbalance_threshold);
   bool sell_imbalance = (order_flow_ratio <= (1.0 / imbalance_threshold));
   
   // Entry conditions
   // BUY: Violent momentum + consecutive buy ticks + buy volume dominance
   if(violent_momentum && strong_buy_signal && buy_imbalance)
   {
      double entry_momentum = CalculateEntryMomentum(true);
      if(entry_momentum >= EntryMomentumThreshold)
      {
         OpenBuyPosition(ask);
      }
   }
   // SELL: Violent momentum + consecutive sell ticks + sell volume dominance
   else if(violent_momentum && strong_sell_signal && sell_imbalance)
   {
      double entry_momentum = CalculateEntryMomentum(false);
      if(entry_momentum >= EntryMomentumThreshold)
      {
         OpenSellPosition(bid);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Entry Momentum                                         |
//+------------------------------------------------------------------+
double CalculateEntryMomentum(bool is_buy)
{
   double momentum_sum = 0.0;
   int count = 0;
   int lookback = MathMin(MinTicksForSignal, tick_buffer_size);
   
   for(int i = tick_buffer_size - 1; i >= 0 && count < lookback; i--)
   {
      if(tick_buffer[i].price > 0)
      {
         if(is_buy && tick_buffer[i].is_buy)
         {
            momentum_sum += tick_buffer[i].momentum;
            count++;
         }
         else if(!is_buy && !tick_buffer[i].is_buy)
         {
            momentum_sum += MathAbs(tick_buffer[i].momentum);
            count++;
         }
      }
   }
   
   if(count > 0)
   {
      return MathAbs(momentum_sum / count);
   }
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Normalize Stops According to Broker Requirements                |
//+------------------------------------------------------------------+
void NormalizeStops(double price, double &sl, double &tp, bool is_buy)
{
   double point = SymbolInfoDouble(TradingSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(TradingSymbol, SYMBOL_DIGITS);
   int stops_level = (int)SymbolInfoInteger(TradingSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   // Calculate minimum distance in points
   double min_stop_distance = stops_level * point;
   if(min_stop_distance == 0) min_stop_distance = point * 10; // Default to 10 points if not specified
   
   // Normalize to required digits
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   // Ensure stops meet minimum distance requirement
   if(is_buy)
   {
      // For buy: SL below price, TP above price
      double sl_distance = price - sl;
      double tp_distance = tp - price;
      
      if(sl_distance < min_stop_distance)
      {
         sl = NormalizeDouble(price - min_stop_distance, digits);
      }
      
      if(tp_distance < min_stop_distance)
      {
         tp = NormalizeDouble(price + min_stop_distance, digits);
      }
   }
   else
   {
      // For sell: SL above price, TP below price
      double sl_distance = sl - price;
      double tp_distance = price - tp;
      
      if(sl_distance < min_stop_distance)
      {
         sl = NormalizeDouble(price + min_stop_distance, digits);
      }
      
      if(tp_distance < min_stop_distance)
      {
         tp = NormalizeDouble(price - min_stop_distance, digits);
      }
   }
}

//+------------------------------------------------------------------+
//| Open Buy Position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition(double price)
{
   double sl = price * (1.0 - StopLossPercent / 100.0);
   double tp = price * (1.0 + TakeProfitPercent / 100.0);
   
   // Normalize stops according to broker requirements
   NormalizeStops(price, sl, tp, true);
   
   if(trade.Buy(LotSize, TradingSymbol, price, sl, tp, "Tick Momentum Buy"))
   {
      position_entry_time = TimeCurrent();
      position_entry_price = price;
      position_type = POSITION_TYPE_BUY;
      
      double order_flow_display = (sell_volume_sum > 0) ? (buy_volume_sum / sell_volume_sum) : 999.0;
      Print("BUY opened: Price=", price, " Momentum=", DoubleToString(current_momentum, 3), 
            "% Consecutive=", consecutive_buy_ticks, " OrderFlow=", DoubleToString(order_flow_display, 2));
      
      // Reset tracking
      consecutive_buy_ticks = 0;
      consecutive_sell_ticks = 0;
      buy_volume_sum = 0.0;
      sell_volume_sum = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Open Sell Position                                              |
//+------------------------------------------------------------------+
void OpenSellPosition(double price)
{
   double sl = price * (1.0 + StopLossPercent / 100.0);
   double tp = price * (1.0 - TakeProfitPercent / 100.0);
   
   // Normalize stops according to broker requirements
   NormalizeStops(price, sl, tp, false);
   
   if(trade.Sell(LotSize, TradingSymbol, price, sl, tp, "Tick Momentum Sell"))
   {
      position_entry_time = TimeCurrent();
      position_entry_price = price;
      position_type = POSITION_TYPE_SELL;
      
      double order_flow_display = (buy_volume_sum > 0) ? (sell_volume_sum / buy_volume_sum) : 999.0;
      Print("SELL opened: Price=", price, " Momentum=", DoubleToString(current_momentum, 3), 
            "% Consecutive=", consecutive_sell_ticks, " OrderFlow=", DoubleToString(order_flow_display, 2));
      
      // Reset tracking
      consecutive_buy_ticks = 0;
      consecutive_sell_ticks = 0;
      buy_volume_sum = 0.0;
      sell_volume_sum = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Check Position                                                   |
//+------------------------------------------------------------------+
void CheckPosition()
{
   if(!PositionSelect(TradingSymbol)) return;
   
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) return;
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
   
   // Get current price
   double current_price = (pos_type == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(TradingSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
   
   // Calculate profit percentage
   double profit_pct = 0.0;
   if(pos_type == POSITION_TYPE_BUY)
      profit_pct = ((current_price - open_price) / open_price) * 100.0;
   else
      profit_pct = ((open_price - current_price) / open_price) * 100.0;
   
   // Check max loss
   if(profit_pct < -MaxLossPercent)
   {
      trade.PositionClose(ticket);
      Print("Position closed: Max loss reached ", DoubleToString(profit_pct, 2), "%");
      return;
   }
   
   // Check time-based exit (1 minute bars)
   int bars_held = (int)((TimeCurrent() - open_time) / 60); // Convert to minutes
   if(bars_held >= MaxBarsHold)
   {
      trade.PositionClose(ticket);
      Print("Position closed: Max bars held ", bars_held);
      return;
   }
   
   // Check for momentum reversal (exit if momentum reverses)
   if(pos_type == POSITION_TYPE_BUY)
   {
      // Exit if strong sell momentum develops
      if(consecutive_sell_ticks >= MinTicksForSignal && current_momentum >= MinTickMomentum)
      {
         double reversal_momentum = CalculateEntryMomentum(false);
         if(reversal_momentum >= EntryMomentumThreshold)
         {
            trade.PositionClose(ticket);
            Print("Position closed: Momentum reversal detected");
            return;
         }
      }
   }
   else // SELL
   {
      // Exit if strong buy momentum develops
      if(consecutive_buy_ticks >= MinTicksForSignal && current_momentum >= MinTickMomentum)
      {
         double reversal_momentum = CalculateEntryMomentum(true);
         if(reversal_momentum >= EntryMomentumThreshold)
         {
            trade.PositionClose(ticket);
            Print("Position closed: Momentum reversal detected");
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Global Variables for Optimization                               |
//+------------------------------------------------------------------+
double optimized_min_tick_momentum = 0.0;
double optimized_order_flow_imbalance = 0.0;

//+------------------------------------------------------------------+
//| Optimize Parameters                                              |
//+------------------------------------------------------------------+
void OptimizeParameters()
{
   Print("=== Optimizing Tick Momentum Parameters ===");
   
   // Initialize optimized values if not set
   if(optimized_min_tick_momentum == 0.0)
   {
      optimized_min_tick_momentum = MinTickMomentum;
   }
   if(optimized_order_flow_imbalance == 0.0)
   {
      optimized_order_flow_imbalance = OrderFlowImbalance;
   }
   
   // Simple optimization: test different thresholds
   double best_profit = CalculateCurrentProfitability();
   double best_momentum = optimized_min_tick_momentum;
   double best_imbalance = optimized_order_flow_imbalance;
   
   // Test momentum thresholds
   for(double test_momentum = 0.03; test_momentum <= 0.15; test_momentum += 0.02)
   {
      optimized_min_tick_momentum = test_momentum;
      
      double profit = BacktestParameters(OptimizationPeriodMinutes);
      
      if(profit > best_profit)
      {
         best_profit = profit;
         best_momentum = test_momentum;
      }
   }
   
   // Test imbalance thresholds
   for(double test_imbalance = 1.2; test_imbalance <= 2.5; test_imbalance += 0.2)
   {
      optimized_order_flow_imbalance = test_imbalance;
      
      double profit = BacktestParameters(OptimizationPeriodMinutes);
      
      if(profit > best_profit)
      {
         best_profit = profit;
         best_imbalance = test_imbalance;
      }
   }
   
   // Update if better found
   if(best_profit > CalculateCurrentProfitability() * 1.1) // 10% improvement
   {
      optimized_min_tick_momentum = best_momentum;
      optimized_order_flow_imbalance = best_imbalance;
      Print("Parameters optimized: Momentum=", best_momentum, " Imbalance=", best_imbalance);
   }
   else
   {
      Print("Keeping current parameters. Profit: ", DoubleToString(best_profit, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Calculate Current Profitability                                 |
//+------------------------------------------------------------------+
double CalculateCurrentProfitability()
{
   double total_profit = 0.0;
   
   // Check open positions
   if(PositionSelect(TradingSymbol))
   {
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                               SymbolInfoDouble(TradingSymbol, SYMBOL_BID) :
                               SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            total_profit = ((current_price - open_price) / open_price) * 100.0;
         else
            total_profit = ((open_price - current_price) / open_price) * 100.0;
      }
   }
   
   // Check historical deals (last hour)
   datetime end_time = TimeCurrent();
   datetime start_time = end_time - 3600;
   
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
               double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
               
               if(price > 0 && volume > 0)
               {
                  total_profit += (profit / (price * volume)) * 100.0;
               }
            }
         }
      }
   }
   
   return total_profit;
}

//+------------------------------------------------------------------+
//| Backtest Parameters                                              |
//+------------------------------------------------------------------+
double BacktestParameters(int minutes)
{
   // Simplified backtest - would need historical tick data
   // For now, return current profitability as approximation
   return CalculateCurrentProfitability();
}
//+------------------------------------------------------------------+
