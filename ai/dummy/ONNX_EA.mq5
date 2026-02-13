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
input double InpPredictionThreshold = 0.00005;               // Min Prediction Change (0.005% as decimal, e.g., 0.00005 = 0.005%)
input bool   InpUseConfidence = true;                         // Use Confidence Filter
input double InpMinConfidence = 0.1;                         // Minimum Confidence (0.1 = 10%)

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
    
    // Model now predicts price change percentage directly (e.g., -0.003 = -0.3%)
    double predicted_change_pct = output_data[0];
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check if prediction is percentage (between -1 and 1) or absolute price (old format)
    double price_change_pct;
    double predicted_price;
    
    if(MathAbs(predicted_change_pct) < 1.0)
    {
        // New format: percentage (e.g., -0.003 = -0.3%)
        price_change_pct = predicted_change_pct * 100.0; // Convert to percentage
        predicted_price = current_price * (1.0 + predicted_change_pct); // Calculate predicted price
    }
    else
    {
        // Old format: absolute price
        predicted_price = predicted_change_pct;
        double price_change = predicted_price - current_price;
        price_change_pct = (price_change / current_price) * 100.0;
    }
    
    // Calculate confidence (for percentage predictions: 0.001 = 0.1% = 10% confidence)
    double confidence;
    if(MathAbs(price_change_pct) < 1.0)
    {
        // It's a decimal percentage (e.g., 0.001 = 0.1%)
        confidence = MathMin(MathAbs(predicted_change_pct) / 0.01, 1.0); // 0.01 = 1% = 100% confidence
    }
    else
    {
        // It's already in percentage form
        confidence = MathMin(MathAbs(price_change_pct) / 1.0, 1.0);
    }
    
    last_prediction = predicted_price;
    last_confidence = confidence;
    
    // Log prediction
    Print("Prediction: Current=", current_price, 
          " Predicted Change=", price_change_pct, "%",
          " Predicted Price=", predicted_price,
          " Confidence=", confidence);
    
    // Check if we should trade
    if(!InpUseConfidence || confidence >= InpMinConfidence)
    {
        // Check if prediction is significant
        // price_change_pct is now in percentage (e.g., 0.1 = 0.1%), so compare with threshold * 100
        // OR: if model outputs decimal (0.001), compare directly
        double abs_change_decimal = MathAbs(predicted_change_pct); // Use raw prediction for threshold check
        if(abs_change_decimal >= InpPredictionThreshold)
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
                // Use raw prediction (decimal format) for threshold comparison
                if(predicted_change_pct > InpPredictionThreshold)
                {
                    OpenBuyPosition();
                }
                else if(predicted_change_pct < -InpPredictionThreshold)
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
    int features = 13; // OHLC(4) + volume(1) + RSI(1) + EMA20(1) + EMA50(1) + ATR(1) + price_change(1) + high_low_ratio(1) + volume_ma(1) + volume_ratio(1) = 13
    
    ArrayResize(input_array, lookback * features);
    ArrayInitialize(input_array, 0.0);
    
    // Get historical data
    double open[], high[], low[], close[];
    long volume[];  // CopyTickVolume requires long[] not double[]
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
    
    // Calculate volume MA for normalization
    double volume_ma[];
    ArraySetAsSeries(volume_ma, true);
    ArrayResize(volume_ma, lookback);
    ArrayInitialize(volume_ma, 0.0);
    
    // Calculate volume MA (20-period rolling average)
    for(int j = 0; j < lookback; j++)
    {
        double sum = 0.0;
        int count = 0;
        for(int k = j; k < j + 20 && k < ArraySize(volume); k++)
        {
            sum += (double)volume[k];  // Convert long to double
            count++;
        }
        volume_ma[j] = count > 0 ? sum / count : (double)volume[j];  // Convert long to double
    }
    
    // Prepare features - MUST match Python training exactly (13 features)
    // IMPORTANT: This uses simplified normalization. For best results, implement MinMaxScaler from training.
    // The scaler is saved as models/XAUUSD_H1_scaler.pkl - you may need to export scaler parameters to MQL5
    int idx = 0;
    for(int i = 0; i < lookback; i++)
    {
        // Feature 1-4: OHLC (raw values, will be normalized by scaler)
        input_array[idx++] = (float)open[i];
        input_array[idx++] = (float)high[i];
        input_array[idx++] = (float)low[i];
        input_array[idx++] = (float)close[i];
        
        // Feature 5: Volume (normalized by 1,000,000)
        input_array[idx++] = (float)((double)volume[i] / 1000000.0);  // Convert long to double first
        
        // Feature 6: RSI (normalized by 100)
        input_array[idx++] = (float)(rsi[i] / 100.0);
        
        // Feature 7: EMA20 normalized difference
        input_array[idx++] = (float)((ema20[i] - close[i]) / close[i]);
        
        // Feature 8: EMA50 normalized difference
        input_array[idx++] = (float)((ema50[i] - close[i]) / close[i]);
        
        // Feature 9: ATR normalized
        input_array[idx++] = (float)(atr[i] / close[i]);
        
        // Feature 10: Price change (percentage)
        double price_change = i > 0 ? (close[i] - close[i+1]) / close[i+1] : 0.0;
        input_array[idx++] = (float)price_change;
        
        // Feature 11: High/Low ratio
        input_array[idx++] = (float)(high[i] / low[i]);
        
        // Feature 12: Volume MA (normalized by 1,000,000)
        input_array[idx++] = (float)(volume_ma[i] / 1000000.0);
        
        // Feature 13: Volume ratio
        double vol_ratio = volume_ma[i] > 0 ? (double)volume[i] / volume_ma[i] : 1.0;  // Convert long to double
        input_array[idx++] = (float)vol_ratio;
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
    long input_shape[] = {1, InpLookback, 13}; // 13 features
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
