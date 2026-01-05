//+------------------------------------------------------------------+
//|                                                      ONNX_EA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor using ONNX model for price prediction"
#property description "Based on: https://www.mql5.com/en/docs/onnx/onnx_prepare"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "ONNX Model Settings"
input string InpModelPath = "models\\XAUUSD_H1_model.onnx";  // ONNX Model Path
input int    InpLookback = 60;                              // Lookback Period (bars)
input bool   InpUsePrediction = true;                        // Use Model Prediction

input group "Trading Settings"
input double InpLotSize = 0.01;                              // Lot Size
input int    InpMagicNumber = 123456;                        // Magic Number
input int    InpSlippage = 3;                                // Slippage (points)
input int    InpStopLoss = 50;                               // Stop Loss (pips)
input int    InpTakeProfit = 100;                            // Take Profit (pips)

input group "Prediction Settings"
input double InpPredictionThreshold = 0.0001;                // Min Prediction Change (0.01%)
input bool   InpUseConfidence = true;                         // Use Confidence Filter
input double InpMinConfidence = 0.6;                         // Minimum Confidence

//--- Global variables
CTrade trade;
long onnx_handle = INVALID_HANDLE;
datetime last_bar_time = 0;
double last_prediction = 0.0;
double last_confidence = 0.0;

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
        return(INIT_FAILED);
    }
    
    // Get model info
    int input_count = OnnxGetInputCount(onnx_handle);
    int output_count = OnnxGetOutputCount(onnx_handle);
    
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
        return; // Still the same bar
    }
    last_bar_time = current_bar_time;
    
    // Check if we should use prediction
    if(!InpUsePrediction)
    {
        return;
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
    if(ArraySize(output_data) == 0)
    {
        Print("ERROR: Empty output from ONNX model");
        return;
    }
    
    double predicted_price = output_data[0];
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate prediction change
    double price_change = predicted_price - current_price;
    double price_change_pct = (price_change / current_price) * 100.0;
    
    // Calculate confidence (simple heuristic based on prediction magnitude)
    double confidence = MathAbs(price_change_pct) / 1.0; // Normalize
    if(confidence > 1.0) confidence = 1.0;
    
    last_prediction = predicted_price;
    last_confidence = confidence;
    
    // Log prediction
    Print("Prediction: Current=", current_price, 
          " Predicted=", predicted_price, 
          " Change=", price_change_pct, "%",
          " Confidence=", confidence);
    
    // Check if we should trade
    if(!InpUseConfidence || confidence >= InpMinConfidence)
    {
        // Check if prediction is significant
        if(MathAbs(price_change_pct) >= InpPredictionThreshold)
        {
            // Check existing position
            if(PositionSelect(_Symbol))
            {
                // Manage existing position
                ManagePosition(predicted_price, price_change_pct);
            }
            else
            {
                // Open new position based on prediction
                if(price_change_pct > InpPredictionThreshold)
                {
                    OpenBuyPosition();
                }
                else if(price_change_pct < -InpPredictionThreshold)
                {
                    OpenSellPosition();
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Prepare input data for ONNX model                                |
//+------------------------------------------------------------------+
bool PrepareInputData(float &input_array[])
{
    // We need to prepare data similar to training
    // This is a simplified version - you may need to adjust based on your model
    
    int lookback = InpLookback;
    int features = 12; // Adjust based on your model (OHLC + volume + indicators)
    
    ArrayResize(input_array, lookback * features);
    ArrayInitialize(input_array, 0.0);
    
    // Get historical data
    double open[], high[], low[], close[], volume[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(volume, true);
    
    if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback + 50, open) < lookback)
        return false;
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback + 50, high) < lookback)
        return false;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback + 50, low) < lookback)
        return false;
    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback + 50, close) < lookback)
        return false;
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, lookback + 50, volume) < lookback)
        return false;
    
    // Calculate indicators (simplified - you may need to match training exactly)
    double rsi[], ema20[], ema50[], atr[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(atr, true);
    
    // Calculate RSI
    int rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    if(rsi_handle == INVALID_HANDLE) return false;
    if(CopyBuffer(rsi_handle, 0, 0, lookback + 50, rsi) < lookback)
    {
        IndicatorRelease(rsi_handle);
        return false;
    }
    IndicatorRelease(rsi_handle);
    
    // Calculate EMAs
    int ema20_handle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ema50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(ema20_handle == INVALID_HANDLE || ema50_handle == INVALID_HANDLE) return false;
    
    if(CopyBuffer(ema20_handle, 0, 0, lookback + 50, ema20) < lookback ||
       CopyBuffer(ema50_handle, 0, 0, lookback + 50, ema50) < lookback)
    {
        IndicatorRelease(ema20_handle);
        IndicatorRelease(ema50_handle);
        return false;
    }
    IndicatorRelease(ema20_handle);
    IndicatorRelease(ema50_handle);
    
    // Calculate ATR
    int atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(atr_handle == INVALID_HANDLE) return false;
    if(CopyBuffer(atr_handle, 0, 0, lookback + 50, atr) < lookback)
    {
        IndicatorRelease(atr_handle);
        return false;
    }
    IndicatorRelease(atr_handle);
    
    // Normalize and prepare data (simplified normalization)
    // IMPORTANT: This uses simplified normalization. For best results, you should:
    // 1. Save the scaler during training (train_onnx_model.py does this automatically)
    // 2. Implement the same normalization logic in MQL5, OR
    // 3. Pre-normalize data in Python and pass to MQL5 via files/global variables
    // The current implementation may not match training exactly, which can affect accuracy
    int idx = 0;
    for(int i = 0; i < lookback; i++)
    {
        // Normalize features (simplified - use proper scaler in production)
        input_array[idx++] = (float)((open[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)((high[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)((low[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)((close[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)(volume[i] / 1000000.0); // Normalize volume
        input_array[idx++] = (float)(rsi[i] / 100.0); // Normalize RSI
        input_array[idx++] = (float)((ema20[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)((ema50[i] - close[lookback-1]) / close[lookback-1]);
        input_array[idx++] = (float)(atr[i] / close[lookback-1]);
        input_array[idx++] = (float)((close[i] - close[i+1]) / close[i+1]); // Price change
        input_array[idx++] = (float)(high[i] / low[i]); // High/low ratio
        input_array[idx++] = (float)(volume[i] / (volume[i] + volume[i+1] + volume[i+2]) / 3.0); // Volume ratio
    }
    
    // Reshape for model: (1, lookback, features)
    // ONNX expects shape [1, lookback, features]
    float reshaped[];
    ArrayResize(reshaped, 1 * lookback * features);
    ArrayCopy(reshaped, input_array);
    
    ArrayCopy(input_array, reshaped);
    
    return true;
}

//+------------------------------------------------------------------+
//| Run ONNX model                                                   |
//+------------------------------------------------------------------+
bool RunONNXModel(float &input_data[], float &output_data[])
{
    if(onnx_handle == INVALID_HANDLE)
        return false;
    
    // Set input shape
    long input_shape[] = {1, InpLookback, 12}; // Adjust based on your model
    if(!OnnxSetInputShape(onnx_handle, 0, input_shape))
    {
        Print("ERROR: Failed to set input shape. Error: ", GetLastError());
        return false;
    }
    
    // Run model
    if(!OnnxRun(onnx_handle, ONNX_NO_CONVERSION, input_data, output_data))
    {
        Print("ERROR: Failed to run ONNX model. Error: ", GetLastError());
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = InpStopLoss > 0 ? price - InpStopLoss * _Point * 10 : 0;
    double tp = InpTakeProfit > 0 ? price + InpTakeProfit * _Point * 10 : 0;
    
    if(trade.Buy(InpLotSize, _Symbol, price, sl, tp, "ONNX Buy Signal"))
    {
        Print("Buy order opened. Ticket: ", trade.ResultOrder());
    }
    else
    {
        Print("Failed to open buy order. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = InpStopLoss > 0 ? price + InpStopLoss * _Point * 10 : 0;
    double tp = InpTakeProfit > 0 ? price - InpTakeProfit * _Point * 10 : 0;
    
    if(trade.Sell(InpLotSize, _Symbol, price, sl, tp, "ONNX Sell Signal"))
    {
        Print("Sell order opened. Ticket: ", trade.ResultOrder());
    }
    else
    {
        Print("Failed to open sell order. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Manage existing position                                          |
//+------------------------------------------------------------------+
void ManagePosition(double predicted_price, double price_change_pct)
{
    if(!PositionSelect(_Symbol))
        return;
    
    long position_type = PositionGetInteger(POSITION_TYPE);
    double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_profit = PositionGetDouble(POSITION_PROFIT);
    
    // Simple management: close if prediction reverses
    if(position_type == POSITION_TYPE_BUY && price_change_pct < -InpPredictionThreshold)
    {
        // Prediction turned bearish, close long
        if(trade.PositionClose(_Symbol))
        {
            Print("Closed long position due to bearish prediction");
        }
    }
    else if(position_type == POSITION_TYPE_SELL && price_change_pct > InpPredictionThreshold)
    {
        // Prediction turned bullish, close short
        if(trade.PositionClose(_Symbol))
        {
            Print("Closed short position due to bullish prediction");
        }
    }
}
