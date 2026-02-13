//+------------------------------------------------------------------+
//|                                         RSIDivergence_EA.mq5     |
//|                                  RSI Divergence ONNX EA for MT5  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "RSI Divergence ONNX EA"
#property link      ""
#property version   "1.00"
#property description "Expert Advisor using ONNX model to identify genuine RSI divergences"
#property description "Based on: https://www.mql5.com/en/docs/onnx/onnx_prepare"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== ONNX Model Settings ==="
input string InpModelPath = "models\\BTCUSD_H1_rsi_divergence_model.onnx";  // ONNX Model Path
input string InpScalerPath = "models\\BTCUSD_H1_rsi_divergence_scaler.pkl";  // Scaler Path (not used in MQL5, for reference)
input string InpFeaturesPath = "models\\BTCUSD_H1_rsi_divergence_features.pkl";  // Features Path (not used in MQL5, for reference)
input int    InpLookback = 60;                              // Lookback Period (bars)
input double InpMinConfidence = 0.7;                        // Minimum Confidence (0-1)

input group "=== Trading Settings ==="
input double InpLotSize = 0.01;                            // Lot Size
input int    InpMagicNumber = 88001;                      // Magic Number
input int    InpSlippage = 3;                             // Slippage (points)
input int    InpStopLoss = 100;                            // Stop Loss (pips, 0 = disabled)
input int    InpTakeProfit = 200;                          // Take Profit (pips, 0 = disabled)
input int    InpMaxBarsInTrade = 20;                       // Max Bars in Trade (0 = disabled)

input group "=== Divergence Filter ==="
input bool   InpUseRegularBullish = true;                  // Trade Regular Bullish Divergence
input bool   InpUseRegularBearish = true;                  // Trade Regular Bearish Divergence
input bool   InpUseHiddenBullish = true;                   // Trade Hidden Bullish Divergence
input bool   InpUseHiddenBearish = true;                    // Trade Hidden Bearish Divergence

input group "=== Risk Management ==="
input bool   InpUseTrailingStop = false;                    // Use Trailing Stop
input int    InpTrailingStopPips = 50;                      // Trailing Stop (pips)
input int    InpTrailingStepPips = 10;                     // Trailing Step (pips)

//--- Global variables
CTrade trade;
long onnx_handle = INVALID_HANDLE;
datetime last_bar_time = 0;

// Divergence type constants (must match Python model)
#define DIV_NONE 0
#define DIV_REGULAR_BULLISH 1
#define DIV_REGULAR_BEARISH 2
#define DIV_HIDDEN_BULLISH 3
#define DIV_HIDDEN_BEARISH 4

// Feature calculation buffers
double rsi_buffer[];
double ema20_buffer[];
double ema50_buffer[];
double atr_buffer[];
double sma20_buffer[];
double sma50_buffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Load ONNX model
    string model_path = InpModelPath;
    
    // Convert relative path to full path
    if(StringFind(model_path, "\\") == 0 || StringFind(model_path, "/") == 0)
    {
        // Already absolute path
    }
    else
    {
        // Relative path - prepend terminal data folder
        model_path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + model_path;
    }
    
    // Replace forward slashes with backslashes for Windows
    StringReplace(model_path, "/", "\\");
    
    Print("Loading ONNX model from: ", model_path);
    
    onnx_handle = OnnxCreate(model_path, ONNX_DEFAULT);
    
    if(onnx_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to load ONNX model. Error: ", GetLastError());
        Print("Make sure the model file exists at: ", model_path);
        Print("Model file should be in: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\models\\");
        return(INIT_FAILED);
    }
    
    // Get model info
    long input_count = OnnxGetInputCount(onnx_handle);
    long output_count = OnnxGetOutputCount(onnx_handle);
    
    Print("ONNX Model loaded successfully");
    Print("  Inputs: ", input_count);
    Print("  Outputs: ", output_count);
    
    if(input_count > 0)
    {
        string input_name = OnnxGetInputName(onnx_handle, 0);
        Print("  Input name: ", input_name);
    }
    
    if(output_count > 0)
    {
        string output_name = OnnxGetOutputName(onnx_handle, 0);
        Print("  Output name: ", output_name);
    }
    
    // Initialize indicator buffers
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(ema20_buffer, true);
    ArraySetAsSeries(ema50_buffer, true);
    ArraySetAsSeries(atr_buffer, true);
    ArraySetAsSeries(sma20_buffer, true);
    ArraySetAsSeries(sma50_buffer, true);
    
    Print("RSI Divergence EA initialized successfully");
    Print("  Symbol: ", _Symbol);
    Print("  Timeframe: ", EnumToString(PERIOD_CURRENT));
    Print("  Lookback: ", InpLookback);
    Print("  Min Confidence: ", InpMinConfidence);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release ONNX model
    if(onnx_handle != INVALID_HANDLE)
    {
        OnnxRelease(onnx_handle);
        Print("ONNX model released");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar
    datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(current_bar_time == last_bar_time)
    {
        // Check trailing stop on current bar
        if(InpUseTrailingStop)
        {
            ApplyTrailingStop();
        }
        return; // Still the same bar
    }
    last_bar_time = current_bar_time;
    
    // Close positions that have been open too long
    if(InpMaxBarsInTrade > 0)
    {
        CloseOldPositions();
    }
    
    // Prepare input data
    float input_data[];
    if(!PrepareInputData(input_data))
    {
        Print("ERROR: Failed to prepare input data");
        return;
    }
    
    // Run ONNX model
    float output_data[];
    if(!RunONNXModel(input_data, output_data))
    {
        Print("ERROR: Failed to run ONNX model");
        return;
    }
    
    // Get prediction
    if(ArraySize(output_data) < 5)
    {
        Print("ERROR: Invalid output from ONNX model");
        return;
    }
    
    // Get predicted class and confidence
    int predicted_class = 0;
    double max_prob = 0.0;
    
    for(int i = 0; i < 5; i++)
    {
        if(output_data[i] > max_prob)
        {
            max_prob = output_data[i];
            predicted_class = i;
        }
    }
    
    double confidence = max_prob;
    
    // Check if confidence meets threshold
    if(confidence < InpMinConfidence)
    {
        return; // Not confident enough
    }
    
    // Check if we should trade this divergence type
    bool should_trade = false;
    int signal_type = 0; // 1 = BUY, -1 = SELL
    
    if(predicted_class == DIV_REGULAR_BULLISH && InpUseRegularBullish)
    {
        should_trade = true;
        signal_type = 1; // BUY
    }
    else if(predicted_class == DIV_REGULAR_BEARISH && InpUseRegularBearish)
    {
        should_trade = true;
        signal_type = -1; // SELL
    }
    else if(predicted_class == DIV_HIDDEN_BULLISH && InpUseHiddenBullish)
    {
        should_trade = true;
        signal_type = 1; // BUY
    }
    else if(predicted_class == DIV_HIDDEN_BEARISH && InpUseHiddenBearish)
    {
        should_trade = true;
        signal_type = -1; // SELL
    }
    
    if(!should_trade)
    {
        return; // Divergence type not enabled
    }
    
    // Check if we already have a position
    if(PositionSelect(_Symbol))
    {
        return; // Already in a position
    }
    
    // Execute trade
    double price = (signal_type == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = 0, tp = 0;
    
    // Calculate stop loss and take profit
    if(InpStopLoss > 0)
    {
        sl = (signal_type == 1) ? price - InpStopLoss * _Point * 10 : price + InpStopLoss * _Point * 10;
    }
    
    if(InpTakeProfit > 0)
    {
        tp = (signal_type == 1) ? price + InpTakeProfit * _Point * 10 : price - InpTakeProfit * _Point * 10;
    }
    
    // Open position
    string divergence_name = "";
    if(predicted_class == DIV_REGULAR_BULLISH) divergence_name = "Regular Bullish";
    else if(predicted_class == DIV_REGULAR_BEARISH) divergence_name = "Regular Bearish";
    else if(predicted_class == DIV_HIDDEN_BULLISH) divergence_name = "Hidden Bullish";
    else if(predicted_class == DIV_HIDDEN_BEARISH) divergence_name = "Hidden Bearish";
    
    if(signal_type == 1)
    {
        if(trade.Buy(InpLotSize, _Symbol, price, sl, tp, divergence_name + " Divergence (Conf: " + DoubleToString(confidence, 2) + ")"))
        {
            Print("BUY order opened: ", divergence_name, " Divergence, Confidence: ", confidence);
        }
        else
        {
            Print("ERROR: Failed to open BUY order: ", trade.ResultRetcodeDescription());
        }
    }
    else
    {
        if(trade.Sell(InpLotSize, _Symbol, price, sl, tp, divergence_name + " Divergence (Conf: " + DoubleToString(confidence, 2) + ")"))
        {
            Print("SELL order opened: ", divergence_name, " Divergence, Confidence: ", confidence);
        }
        else
        {
            Print("ERROR: Failed to open SELL order: ", trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| Prepare input data for ONNX model                                |
//+------------------------------------------------------------------+
bool PrepareInputData(float &input_data[])
{
    // We need to prepare features in the same order as training
    // This should match the feature_cols from the Python training script
    
    int lookback = InpLookback;
    int num_features = 20; // Adjust based on your actual feature count
    
    // Resize input array: (1, lookback, num_features)
    ArrayResize(input_data, lookback * num_features);
    ArrayInitialize(input_data, 0.0);
    
    // Get price data
    double close[], open[], high[], low[], volume[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(volume, true);
    
    CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
    CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
    CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
    CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
    CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, lookback, volume);
    
    // Calculate technical indicators
    int rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    int ema20_handle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ema50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
    int sma20_handle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    int sma50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
    
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(ema20_buffer, true);
    ArraySetAsSeries(ema50_buffer, true);
    ArraySetAsSeries(sma20_buffer, true);
    ArraySetAsSeries(sma50_buffer, true);
    ArraySetAsSeries(atr_buffer, true);
    
    if(CopyBuffer(rsi_handle, 0, 0, lookback, rsi_buffer) <= 0) return false;
    if(CopyBuffer(ema20_handle, 0, 0, lookback, ema20_buffer) <= 0) return false;
    if(CopyBuffer(ema50_handle, 0, 0, lookback, ema50_buffer) <= 0) return false;
    if(CopyBuffer(sma20_handle, 0, 0, lookback, sma20_buffer) <= 0) return false;
    if(CopyBuffer(sma50_handle, 0, 0, lookback, sma50_buffer) <= 0) return false;
    if(CopyBuffer(atr_handle, 0, 0, lookback, atr_buffer) <= 0) return false;
    
    // Release indicator handles
    IndicatorRelease(rsi_handle);
    IndicatorRelease(ema20_handle);
    IndicatorRelease(ema50_handle);
    IndicatorRelease(sma20_handle);
    IndicatorRelease(sma50_handle);
    IndicatorRelease(atr_handle);
    
    // Prepare features (must match Python feature order)
    // Note: Features need to be normalized - this is a simplified version
    // In production, you should use the same scaler from Python
    
    for(int i = 0; i < lookback; i++)
    {
        int idx = i * num_features;
        int bar_idx = lookback - 1 - i; // Reverse for time series
        
        // Basic OHLCV (normalized)
        input_data[idx + 0] = (float)(close[bar_idx] / close[0] - 1.0); // Normalized close
        input_data[idx + 1] = (float)(open[bar_idx] / close[0] - 1.0);   // Normalized open
        input_data[idx + 2] = (float)(high[bar_idx] / close[0] - 1.0);   // Normalized high
        input_data[idx + 3] = (float)(low[bar_idx] / close[0] - 1.0);    // Normalized low
        input_data[idx + 4] = (float)(volume[bar_idx] / 1000000.0);      // Normalized volume
        
        // Returns
        if(bar_idx < lookback - 1)
        {
            input_data[idx + 5] = (float)((close[bar_idx] - close[bar_idx + 1]) / close[bar_idx + 1]);
        }
        
        // Ratios
        input_data[idx + 6] = (float)(high[bar_idx] / (low[bar_idx] + 1e-10));
        input_data[idx + 7] = (float)(close[bar_idx] / (open[bar_idx] + 1e-10));
        
        // Moving averages (normalized)
        input_data[idx + 8] = (float)(sma20_buffer[bar_idx] / close[0] - 1.0);
        input_data[idx + 9] = (float)(sma50_buffer[bar_idx] / close[0] - 1.0);
        input_data[idx + 10] = (float)(ema20_buffer[bar_idx] / close[0] - 1.0);
        input_data[idx + 11] = (float)(ema50_buffer[bar_idx] / close[0] - 1.0);
        
        // ATR
        input_data[idx + 12] = (float)(atr_buffer[bar_idx] / close[0]);
        
        // RSI (normalized to 0-1)
        input_data[idx + 13] = (float)(rsi_buffer[bar_idx] / 100.0);
        
        // Volume features
        double volume_ma = 0;
        for(int j = 0; j < 20 && (bar_idx + j) < lookback; j++)
        {
            volume_ma += volume[bar_idx + j];
        }
        volume_ma /= 20.0;
        input_data[idx + 14] = (float)(volume[bar_idx] / (volume_ma + 1e-10));
        
        // Price position (simplified)
        double min_low = low[bar_idx];
        double max_high = high[bar_idx];
        for(int j = 0; j < 20 && (bar_idx + j) < lookback; j++)
        {
            if(low[bar_idx + j] < min_low) min_low = low[bar_idx + j];
            if(high[bar_idx + j] > max_high) max_high = high[bar_idx + j];
        }
        input_data[idx + 15] = (float)((close[bar_idx] - min_low) / (max_high - min_low + 1e-10));
        
        // Additional features (pad with zeros if needed)
        for(int j = 16; j < num_features; j++)
        {
            input_data[idx + j] = 0.0;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Run ONNX model                                                   |
//+------------------------------------------------------------------+
bool RunONNXModel(float &input_data[], float &output_data[])
{
    if(onnx_handle == INVALID_HANDLE)
    {
        return false;
    }
    
    // Get input/output names
    string input_name = OnnxGetInputName(onnx_handle, 0);
    string output_name = OnnxGetOutputName(onnx_handle, 0);
    
    // Prepare input shape: (1, lookback, num_features)
    long input_shape[] = {1, InpLookback, 20}; // Adjust num_features as needed
    long output_shape[] = {1, 5}; // 5 classes
    
    // Run model
    if(!OnnxRun(onnx_handle, ONNX_NO_CONVERSION, input_data, input_shape, 3, 
                output_data, output_shape))
    {
        Print("ERROR: OnnxRun failed. Error: ", GetLastError());
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
    if(!PositionSelect(_Symbol))
    {
        return;
    }
    
    if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
    {
        return;
    }
    
    double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double position_sl = PositionGetDouble(POSITION_SL);
    double position_tp = PositionGetDouble(POSITION_TP);
    long position_type = PositionGetInteger(POSITION_TYPE);
    
    double current_price = (position_type == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double trailing_distance = InpTrailingStopPips * _Point * 10;
    double trailing_step = InpTrailingStepPips * _Point * 10;
    
    if(position_type == POSITION_TYPE_BUY)
    {
        double new_sl = current_price - trailing_distance;
        
        if(new_sl > position_open_price && 
           (position_sl == 0 || new_sl > position_sl + trailing_step))
        {
            trade.PositionModify(_Symbol, new_sl, position_tp);
        }
    }
    else if(position_type == POSITION_TYPE_SELL)
    {
        double new_sl = current_price + trailing_distance;
        
        if(new_sl < position_open_price && 
           (position_sl == 0 || new_sl < position_sl - trailing_step))
        {
            trade.PositionModify(_Symbol, new_sl, position_tp);
        }
    }
}

//+------------------------------------------------------------------+
//| Close positions that have been open too long                    |
//+------------------------------------------------------------------+
void CloseOldPositions()
{
    if(!PositionSelect(_Symbol))
    {
        return;
    }
    
    if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
    {
        return;
    }
    
    datetime position_open_time = (datetime)PositionGetInteger(POSITION_TIME);
    datetime current_time = TimeCurrent();
    
    int bars_open = Bars(_Symbol, PERIOD_CURRENT, position_open_time, current_time);
    
    if(bars_open >= InpMaxBarsInTrade)
    {
        trade.PositionClose(_Symbol);
        Print("Position closed: Max bars in trade reached (", bars_open, " bars)");
    }
}

//+------------------------------------------------------------------+
