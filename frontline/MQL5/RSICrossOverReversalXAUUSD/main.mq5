// Input Parameters
#include <Trade\Trade.mqh>
#include "../_united/MagicNumberHelpers.mqh"

input group "Trade Management"
input int MagicNumber = 7;
input int rsiPeriod = 19;           // RSI period
input int overboughtLevel = 93;     // Overbought level (RSI > 70 for sell)
input int oversoldLevel = 22;       // Oversold level (RSI < 30 for buy)
input double entryRSIBuySpread = 0;
input double entryRSISellSpread = 0;
input double lotSize = 0.01;        // Trade lot size
input int slippage = 3;            // Slippage for orders
input int cooldownSeconds = 209;   // Cooldown period in seconds
input ENUM_TIMEFRAMES TimeFrame1 = PERIOD_M1; // RSI Timeframe
input ENUM_TIMEFRAMES TimeFrame2 = PERIOD_M1; // EMA Timeframe
input ENUM_TIMEFRAMES BarTimeFrame = PERIOD_M12; // EMA Timeframe
input int emaPeriod = 140;           // EMA period
input double emaSlopeThreshold = 105; // EMA slope threshold for trend strength
input double exitBuyRSI = 86;
input double exitSellRSI = 10;
input double TrailingStop  = 295;
input double emaDistanceThreshold = 165;
input int tradingHourOneBegin = 24;
input int tradingHourOneEnd = 22;
input int tradingHourTwoBegin = 6;
input int tradingHourTwoEnd = 19;
datetime bartime;
// RSI Handle
int rsiHandle;

input bool Sunday   =false; // Sunday
input bool Monday   =false; // Monday
input bool Tuesday  =true; // Tuesday 
input bool Wednesday=true; // Wednesday
input bool Thursday =true; // Thursday
input bool Friday   =false; // Friday
input bool Saturday =false; // Saturday

bool WeekDays[7];

void WeekDays_Init()
  {
   WeekDays[0]=Sunday;
   WeekDays[1]=Monday;
   WeekDays[2]=Tuesday;
   WeekDays[3]=Wednesday;
   WeekDays[4]=Thursday;
   WeekDays[5]=Friday;
   WeekDays[6]=Saturday;
  }
  
bool WeekDays_Check(datetime aTime)
  {
   MqlDateTime stm;
   TimeToStruct(aTime,stm);
   return(WeekDays[stm.day_of_week]);
  }


// EMA Handle
int emaHandle;
double previousRSIDef = 0;
// Create CTrade object for executing trades
CTrade trade;

// Track the last trade time
datetime lastTradeTime = 0;

void OnInit() {
    WeekDays_Init();     

    // Create RSI handle
    rsiHandle = iRSI(_Symbol, TimeFrame1, rsiPeriod, PRICE_CLOSE);
    if (rsiHandle == INVALID_HANDLE) {
        Print("Error creating RSI handle: ", GetLastError());
        return;
    }

    // Create EMA handle
    emaHandle = iMA(_Symbol, TimeFrame2, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if (emaHandle == INVALID_HANDLE) {
        Print("Error creating EMA handle: ", GetLastError());
        return;
    }

    // Initialization successful
    Print("RSI and EMA Reversal Strategy Initialized.");
}

void OnTick() {
    if(bartime==iTime(_Symbol,BarTimeFrame,0))return;
    bartime=iTime(_Symbol,BarTimeFrame,0);

    // Check if RSI data is available
    double rsi[];
    if (CopyBuffer(rsiHandle, 0, 0, 2, rsi) <= 0) {
        Print("Error copying RSI data: ", GetLastError());
        return;
    }

    // Check if EMA data is available
    double ema[];
    if (CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0) {
        Print("Error copying EMA data: ", GetLastError());
        return;
    }

    // Get the current time
    datetime currentTime = TimeCurrent();
    

   int currentHour = TimeHour(TimeCurrent());
   
   if(!WeekDays_Check(TimeTradeServer())) {
      Close_Position_MN(MagicNumber);   
      return;
   }
   
   if (!(currentHour < tradingHourOneEnd && currentHour > tradingHourOneBegin || currentHour < tradingHourTwoEnd && currentHour > tradingHourTwoBegin))
   {

      Close_Position_MN(MagicNumber);
      return; // Prevent further trading during this time
   }


    // Ensure there is at least one position
    bool hasPosition = PositionExistsByMagic(_Symbol, MagicNumber);

    

    // Get the current and previous RSI values
    double currentRSI = rsi[0];
    double previousRSI = rsi[1];

    if(previousRSIDef == 0) {
      previousRSIDef = currentRSI;
      return;
    }

    // Get the current and previous EMA values
    double currentEMA = ema[0];
    double previousEMA = ema[1];

    // Calculate the EMA slope (difference between current and previous EMA values)
    double emaSlope = (currentEMA - previousEMA) * 100;
    Print(emaSlope);
    
    double closeCurr = iClose(Symbol(), Period(), 0);  // Close of current bar
            // ** NEW CODE: Calculate distance to EMA and adjust score **
    double priceToEmaDistance = (closeCurr - currentEMA) * 10;  // Distance between the current price and the EMA
    Print("priceToEmaDistance");
    Print(priceToEmaDistance);
    
    
    // Determine if there are existing buy or sell positions
    bool isBuyPosition = false;
    bool isSellPosition = false;
    if (hasPosition) {
        if (PositionSelectByMagic(_Symbol, MagicNumber)) {
            int positionType = PositionGetInteger(POSITION_TYPE);
            if (positionType == POSITION_TYPE_BUY) {
                isBuyPosition = true;
            } else if (positionType == POSITION_TYPE_SELL) {
                isSellPosition = true;
            }
        }
    }

    ApplyTrailingStop();

    // Check if the cooldown period has elapsed since the last trade
    bool cooldownPassed = (currentTime - lastTradeTime) >= cooldownSeconds;

    // Check if EMA slope is above the threshold (indicating strong trend)
    bool isTrendStrong = MathAbs(emaSlope) > emaSlopeThreshold || MathAbs(priceToEmaDistance) > emaDistanceThreshold;

    // Close trade logic when RSI crosses 50
    if (isBuyPosition && currentRSI > exitBuyRSI) {
        // Close buy position
        Close_Position_MN(MagicNumber);
        lastTradeTime = currentTime;  // Update last trade time
    }

    if (isSellPosition && currentRSI < exitSellRSI) {
        Close_Position_MN(MagicNumber);
        lastTradeTime = currentTime;  // Update last trade time

    }


    // If the EMA slope is strong, do not place new trades
    if (isTrendStrong) {
        Close_Position_MN(MagicNumber);
        lastTradeTime = currentTime;  // Update last trade time
        Print("Strong trend detected (EMA slope), skipping new trade.");
        return;
    }

    // SELL logic (RSI crosses over the overbought level)
    if (currentRSI < overboughtLevel - entryRSISellSpread && previousRSIDef >= overboughtLevel && !isSellPosition && !hasPosition && cooldownPassed) {
        trade.SetExpertMagicNumber(MagicNumber);
        if (trade.Sell(lotSize, _Symbol, 0, 0, "Sell Order")) {
            Print("Sell order placed.");
            lastTradeTime = currentTime;  // Update last trade time
        } else {
            Print("Error placing sell order: ", GetLastError());
        }
    }

    // BUY logic (RSI crosses below the oversold level)
    if (currentRSI > oversoldLevel + entryRSIBuySpread && previousRSIDef <= oversoldLevel && !isBuyPosition && !hasPosition && cooldownPassed) {
        trade.SetExpertMagicNumber(MagicNumber);
        if (trade.Buy(lotSize, _Symbol, 0, 0, "Buy Order")) {
            Print("Buy order placed.");
            lastTradeTime = currentTime;  // Update last trade time
        } else {
            Print("Error placing buy order: ", GetLastError());
        }
    }
    
    previousRSIDef = currentRSI;
}

void OnDeinit(const int reason) {
    // Release RSI and EMA handles on deinitialization
    if (rsiHandle != INVALID_HANDLE) {
        IndicatorRelease(rsiHandle);
        Print("RSI handle released.");
    }
    if (emaHandle != INVALID_HANDLE) {
        IndicatorRelease(emaHandle);
        Print("EMA handle released.");
    }
}


void Close_Position_MN(ulong magicNumber)
{  
    // Use helper function to close position by magic number
    ClosePositionByMagic(trade, _Symbol, (int)magicNumber);
}

void ApplyTrailingStop()
{
      Print("Scanning for trailing stop");
      
      // Check if position exists with our magic number
      if(!PositionSelectByMagic(_Symbol, MagicNumber))
      {
         return; // No position with our magic number
      }
      
      ulong PositionTicket = PositionGetInteger(POSITION_TICKET);
      long trade_type = PositionGetInteger(POSITION_TYPE);
      string symbol = _Symbol;
            
      double POINT  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    DIGIT  = (int) SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
      if(trade_type == POSITION_TYPE_BUY)
      {    
         double Bid = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_BID), DIGIT);
                                  
         if(Bid - PositionGetDouble(POSITION_PRICE_OPEN) > NormalizeDouble(POINT * TrailingStop, DIGIT))
         {
            if(PositionGetDouble(POSITION_SL) < NormalizeDouble(Bid - POINT * TrailingStop, DIGIT))
            {
               ModifyPositionByMagic(trade, symbol, MagicNumber, 
                                    NormalizeDouble(Bid - POINT * TrailingStop, DIGIT), 
                                    PositionGetDouble(POSITION_TP));
            }
         }
      }
      else if(trade_type == POSITION_TYPE_SELL)
      {  
         double Ask = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_ASK), DIGIT);
               
         if((PositionGetDouble(POSITION_PRICE_OPEN) - Ask) > NormalizeDouble(POINT * TrailingStop, DIGIT))
         {
            if((PositionGetDouble(POSITION_SL) > NormalizeDouble(Ask + POINT * TrailingStop, DIGIT)) || 
               (PositionGetDouble(POSITION_SL) == 0))
            {
               ModifyPositionByMagic(trade, symbol, MagicNumber, 
                                   NormalizeDouble(Ask + POINT * TrailingStop, DIGIT), 
                                   PositionGetDouble(POSITION_TP));
            }
         }
      }
}

int TimeHour(datetime when=0){ if(when == 0) when = TimeCurrent();
   return when / 3600 % 24;
}