//+------------------------------------------------------------------+
//|                                                 EMACrossOver.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property link      "https://www.mql5.com"
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property version   "1.00"
#include <Trade\Trade.mqh>
//--- Eingabeparameter (Input Parameters) - Optimized Profitable Parameters
input int    EMA_Periode = 51;           // EMA Periode
input double PreisSchwelle = 300.0;       // Preisbewegung Schwelle in Pips
input double SteigungSchwelle = 40.0;     // EMA Steigung Schwelle in Pips
input int    ÜberwachungTimeout = 1600;   // Überwachungszeit in Sekunden
input double TrailingStop = 100.0;        // Gleitender Stop in Pips
input double LotGröße = 0.03;             // Handelsvolumen
input int    MagicNumber = 12350;        // Magic Number für Trades
input bool   UseSpreadAdjustment = true; // Spread-Anpassung verwenden
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1; // Zeitraum für Analyse
input bool   UseBarData = true;          // Bar-Daten statt Tick-Daten verwenden
input int    MaxTradesPerCrossover = 6;  // Maximale Trades pro Crossover-Ereignis
input int    ProfitCheckBars = 11;       // Bars bis zur Profit-Prüfung
input bool   CloseUnprofitableTrades = true; // Unprofitable Trades nach X Bars schließen
//--- V-Shape Reversal Protection Parameters
input bool   UseRSIFilter = true;        // RSI Filter verwenden (vermeidet Extreme)
input int    RSIPeriod = 14;             // RSI Periode
input double RSIOverbought = 71.0;       // RSI Überkauft Level
input double RSIOversold = 31.0;         // RSI Überverkauft Level
input bool   UseMomentumConfirmation = true; // Momentum-Bestätigung verwenden
input int    MomentumBars = 5;           // Bars für Momentum-Prüfung
input bool   UsePullbackConfirmation = true; // Pullback-Bestätigung verwenden
input double PullbackThreshold = 0.5;    // Pullback-Schwelle (50% der Bewegung)
input bool   UseEarlyReversalDetection = true; // Frühe Reversal-Erkennung
input double ReversalThreshold = 0.5;    // Reversal-Schwelle (50% Rückgang)
input bool   UseMAEProtection = true;     // Maximum Adverse Excursion Schutz
input double MAEThreshold = 150.0;        // MAE Schwelle in Pips
input int    MAECheckBars = 5;           // Bars für MAE-Prüfung
//--- V-Shape Reversal Trading Parameters
input bool   UseVShapeReversalTrading = true; // V-Shape Reversal Trading aktivieren
input double VShapeReversalStopLoss = 100.0;  // Stop Loss für V-Shape Reversal Trades (Pips)
input double VShapeReversalLotSize = 0.01;    // Lot-Größe für V-Shape Trades (konservativer)
input bool   UseRSI50Crossover = false;        // RSI 50 Crossover für Haupt-Trades verwenden
input int    RSICrossBars = 4;                 // Bars für RSI Crossover Bestätigung

//--- Globale Variablen (Global Variables)
int ema_handle;                          // EMA Indicator Handle
int rsi_handle;                          // RSI Indicator Handle
double ema_array[];                      // Array für EMA
double rsi_array[];                      // Array für RSI
datetime letzte_überwachung_zeit;        // Zeit der letzten Überwachung
bool überwachung_aktiv = false;          // Überwachungsstatus
bool preis_trigger_aktiv = false;        // Preis-Trigger Status
bool steigung_trigger_aktiv = false;     // Steigungs-Trigger Status
int ticket = 0;                          // Trade Ticket
CTrade trade;                            // CTrade Objekt
int trades_in_current_crossover = 0;     // Anzahl Trades im aktuellen Crossover
bool crossover_detected = false;          // Crossover erkannt
datetime trade_open_time = 0;            // Zeitpunkt des Trade-Öffnens
double entry_price = 0;                  // Einstiegspreis für MAE-Prüfung
double max_favorable_excursion = 0;      // Maximale günstige Bewegung
double max_adverse_excursion = 0;        // Maximale ungünstige Bewegung
double trigger_price = 0;                // Preis beim Trigger für Pullback-Prüfung
bool is_vshape_trade = false;            // Ist aktueller Trade ein V-Shape Reversal Trade
double last_rsi = 50.0;                  // Letzter RSI-Wert für Crossover-Erkennung
bool rsi_crossed_above_50 = false;       // RSI über 50 gekreuzt
bool rsi_crossed_below_50 = false;       // RSI unter 50 gekreuzt

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- CTrade konfigurieren (Configure CTrade)
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- EMA Indicator Handle erstellen (Create EMA indicator handle)
   ema_handle = iMA(_Symbol, Timeframe, EMA_Periode, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema_handle == INVALID_HANDLE)
   {
      Print("Fehler beim Erstellen des EMA Indicators");
      return(INIT_FAILED);
   }
   
   //--- RSI Indicator Handle erstellen (Create RSI indicator handle)
   if(UseRSIFilter || UseVShapeReversalTrading || UseRSI50Crossover)
   {
      rsi_handle = iRSI(_Symbol, Timeframe, RSIPeriod, PRICE_CLOSE);
      
      if(rsi_handle == INVALID_HANDLE)
      {
         Print("Fehler beim Erstellen des RSI Indicators");
         return(INIT_FAILED);
      }
      
      ArraySetAsSeries(rsi_array, true);
      
      // Initialisiere RSI Tracking (Initialize RSI tracking)
      if(UseRSI50Crossover)
      {
         BerechneRSI();
         if(ArraySize(rsi_array) > 0)
         {
            last_rsi = rsi_array[0];
            rsi_crossed_above_50 = (last_rsi > 50.0);
            rsi_crossed_below_50 = (last_rsi < 50.0);
         }
      }
   }
   
   //--- Arrays initialisieren (Initialize arrays)
   ArraySetAsSeries(ema_array, true);
   
   //--- Arrays mit aktuellen Werten füllen (Fill arrays with current values)
   BerechneEMA();
   if(UseRSIFilter)
   {
      BerechneRSI();
   }
   
   Print("EMA EA initialisiert - Periode: ", EMA_Periode, " Timeframe: ", EnumToString(Timeframe), " Handle: ", ema_handle);
   if(UseRSIFilter)
   {
      Print("RSI Filter aktiviert - Periode: ", RSIPeriod);
   }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Indicator Handle freigeben (Release indicator handle)
   if(ema_handle != INVALID_HANDLE)
   {
      IndicatorRelease(ema_handle);
   }
   
   if((UseRSIFilter || UseVShapeReversalTrading || UseRSI50Crossover) && rsi_handle != INVALID_HANDLE)
   {
      IndicatorRelease(rsi_handle);
   }
   
   Print("EA beendet - Grund: ", reason);
}
   
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Bar-Daten oder Tick-Daten verwenden (Use bar data or tick data)
   if(UseBarData)
   {
      //--- Nur bei neuen Bars ausführen (Only execute on new bars)
      static datetime last_bar_time = 0;
      datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
      
      if(current_bar_time == last_bar_time)
      {
         return; // Kein neuer Bar, nichts tun
      }
      
      last_bar_time = current_bar_time;
   }
   
   //--- EMA Werte berechnen (Calculate EMA values)
   BerechneEMA();
   
   //--- RSI Werte berechnen (Calculate RSI values)
   if(UseRSIFilter || UseVShapeReversalTrading || UseRSI50Crossover)
   {
      BerechneRSI();
      
      //--- RSI Crossover Tracking für Haupt-Trades (RSI Crossover tracking for main trades)
      if(UseRSI50Crossover && ArraySize(rsi_array) >= 2)
      {
         double current_rsi = rsi_array[0];
         double previous_rsi = rsi_array[1];
         
         // Prüfe RSI Crossover über 50 (Check RSI crossover above 50)
         if(previous_rsi <= 50.0 && current_rsi > 50.0)
         {
            rsi_crossed_above_50 = true;
            rsi_crossed_below_50 = false;
            Print("TRACE: RSI über 50 gekreuzt - Vorher: ", previous_rsi, " Jetzt: ", current_rsi);
         }
         // Prüfe RSI Crossover unter 50 (Check RSI crossover below 50)
         else if(previous_rsi >= 50.0 && current_rsi < 50.0)
         {
            rsi_crossed_below_50 = true;
            rsi_crossed_above_50 = false;
            Print("TRACE: RSI unter 50 gekreuzt - Vorher: ", previous_rsi, " Jetzt: ", current_rsi);
         }
         
         last_rsi = current_rsi;
      }
   }
   
   //--- Debug: Aktuelle Werte ausgeben (Debug: Output current values)
   if(ArraySize(ema_array) > 0)
   {
      double aktueller_close = iClose(_Symbol, Timeframe, 0);
      double ema_aktuell = ema_array[0];
      double ema_vorher = ema_array[1];
      double preis_abstand = MathAbs(aktueller_close - ema_aktuell) / _Point;
      double steigung = (ema_aktuell - ema_vorher) / _Point;
      
      if(UseBarData)
      {
         Print("=== DEBUG INFO (Neuer Bar) ===");
         Print("Bar Zeit: ", TimeToString(iTime(_Symbol, Timeframe, 0)));
      }
      else
      {
         Print("=== DEBUG INFO (Tick) ===");
      }
      
      Print("Aktueller Close: ", aktueller_close);
      Print("EMA: ", ema_aktuell);
      Print("Preis-Abstand: ", preis_abstand, " Pips");
      Print("EMA Steigung: ", steigung, " Pips");
      Print("Differenz Close-EMA: ", aktueller_close - ema_aktuell);
      Print("Preis-Trigger: ", preis_trigger_aktiv, " Steigungs-Trigger: ", steigung_trigger_aktiv);
      Print("Überwachung aktiv: ", überwachung_aktiv);
      Print("Position offen: ", PositionSelect(_Symbol));
         Print("Trades im aktuellen Crossover: ", trades_in_current_crossover, "/", MaxTradesPerCrossover);
   Print("==================");
   }
   
   //--- Überwachung prüfen (Check monitoring)
   if(überwachung_aktiv)
   {
      if(UseBarData)
      {
         // Bar-basierte Überwachungszeit
         int bars_since_monitoring = iBarShift(_Symbol, Timeframe, letzte_überwachung_zeit);
         int timeout_bars = (int)(ÜberwachungTimeout / PeriodSeconds(Timeframe));
         
         if(bars_since_monitoring > timeout_bars)
         {
            überwachung_aktiv = false;
            preis_trigger_aktiv = false;
            steigung_trigger_aktiv = false;
            Print("Überwachung beendet - Bar-basierte Zeitüberschreitung (", bars_since_monitoring, " Bars)");
         }
      }
      else
      {
         // Tick-basierte Überwachungszeit
         if(TimeCurrent() - letzte_überwachung_zeit > ÜberwachungTimeout)
         {
            überwachung_aktiv = false;
            preis_trigger_aktiv = false;
            steigung_trigger_aktiv = false;
            Print("Überwachung beendet - Tick-basierte Zeitüberschreitung");
         }
      }
   }
   
   //--- Trigger-Bedingungen prüfen (Check trigger conditions)
   PrüfeTrigger();
   
   //--- Trade Management (Trade management)
   VerwalteTrades();
   
   //--- MAE Protection prüfen (Check MAE protection)
   if(UseMAEProtection && PositionSelect(_Symbol))
   {
      PrüfeMAE();
   }
}

//+------------------------------------------------------------------+
//| EMA Berechnung (EMA Calculation)                                |
//+------------------------------------------------------------------+
void BerechneEMA()
{
   //--- EMA Werte vom Indicator kopieren (Copy EMA values from indicator)
   int copied = CopyBuffer(ema_handle, 0, 0, 3, ema_array);
   
   if(copied <= 0)
   {
      Print("TRACE: Fehler beim Kopieren der EMA Werte - Copied: ", copied);
      return;
   }
   
   Print("TRACE: EMA Werte kopiert: ", copied, " Bars");
   Print("TRACE: EMA [0]: ", ema_array[0], " [1]: ", ema_array[1], " [2]: ", ema_array[2]);
}

//+------------------------------------------------------------------+
//| RSI Berechnung (RSI Calculation)                                |
//+------------------------------------------------------------------+
void BerechneRSI()
{
   if(!UseRSIFilter || rsi_handle == INVALID_HANDLE)
      return;
   
   //--- RSI Werte vom Indicator kopieren (Copy RSI values from indicator)
   int copied = CopyBuffer(rsi_handle, 0, 0, 3, rsi_array);
   
   if(copied <= 0)
   {
      Print("TRACE: Fehler beim Kopieren der RSI Werte - Copied: ", copied);
      return;
   }
   
   Print("TRACE: RSI Werte kopiert: ", copied, " Bars");
   Print("TRACE: RSI [0]: ", rsi_array[0], " [1]: ", rsi_array[1], " [2]: ", rsi_array[2]);
}

//+------------------------------------------------------------------+
//| Trigger-Bedingungen prüfen (Check trigger conditions)           |
//+------------------------------------------------------------------+
void PrüfeTrigger()
{
   if(ArraySize(ema_array) < 2)
   {
      Print("TRACE: Array zu klein - Größe: ", ArraySize(ema_array));
      return;
   }
   
   //--- Aktuelle Werte (Current values)
   double aktueller_preis = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double aktueller_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double aktueller_close = iClose(_Symbol, Timeframe, 0);
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   
   //--- EMA Werte in Variablen (EMA values in variables)
   double ema_aktuell = ema_array[0];
   double ema_vorher = ema_array[1];
   
   //--- EMA Crossover Erkennung (EMA Crossover Detection)
   // Prüfe ob Preis die EMA kreuzt (Check if price crosses EMA)
   static double last_close = 0;
   static double last_ema = 0;
   
   if(last_close != 0 && last_ema != 0)
   {
      bool crossover_bullish = (last_close <= last_ema) && (aktueller_close > ema_aktuell);
      bool crossover_bearish = (last_close >= last_ema) && (aktueller_close < ema_aktuell);
      
      //--- Neues Crossover-Ereignis erkannt (New crossover event detected)
      if(crossover_bullish || crossover_bearish)
      {
         trades_in_current_crossover = 0; // Reset trade counter
         Print("TRACE: EMA Crossover erkannt - ", (crossover_bullish ? "BULLISH" : "BEARISH"), " - Trade-Counter zurückgesetzt");
         Print("TRACE: Vorher: Close=", last_close, " EMA=", last_ema, " Jetzt: Close=", aktueller_close, " EMA=", ema_aktuell);
      }
   }
   
   //--- Aktuelle Werte für nächsten Vergleich speichern (Save current values for next comparison)
   last_close = aktueller_close;
   last_ema = ema_aktuell;
   
   //--- Preisbewegung zur EMA prüfen (Check price action to EMA)
   double preis_abstand = MathAbs(aktueller_close - ema_aktuell) / _Point / pips_multiplier;
   
   Print("TRACE: Preis-Abstand: ", preis_abstand, " Pips (Schwelle: ", PreisSchwelle, ")");
   Print("TRACE: Close: ", aktueller_close, " EMA: ", ema_aktuell);
   Print("TRACE: Trades im aktuellen Crossover: ", trades_in_current_crossover, "/", MaxTradesPerCrossover);
   
   if(preis_abstand > PreisSchwelle && !preis_trigger_aktiv)
   {
      preis_trigger_aktiv = true;
      Print("TRACE: Preis-Trigger aktiviert: ", preis_abstand, " Pips");
   }
   
   //--- EMA Steigung prüfen (Check EMA slope)
   double steigung = (ema_aktuell - ema_vorher) / _Point / pips_multiplier;
   
   Print("TRACE: EMA Steigung: ", steigung, " Pips (Schwelle: ", SteigungSchwelle, ")");
   
   if(MathAbs(steigung) > SteigungSchwelle && !steigung_trigger_aktiv)
   {
      steigung_trigger_aktiv = true;
      Print("TRACE: Steigungs-Trigger aktiviert: ", steigung, " Pips");
   }
   
   //--- Überwachung starten wenn beide Trigger aktiv sind (Start monitoring when both triggers are active)
   if(preis_trigger_aktiv && steigung_trigger_aktiv && !überwachung_aktiv)
   {
      überwachung_aktiv = true;
      trigger_price = aktueller_close; // Preis beim Trigger speichern für Pullback-Prüfung
      
      if(UseBarData)
      {
         letzte_überwachung_zeit = iTime(_Symbol, Timeframe, 0); // Aktuelle Bar-Zeit
         Print("TRACE: Überwachung gestartet - Beide Trigger aktiv (Bar: ", TimeToString(letzte_überwachung_zeit), ")");
      }
      else
      {
         letzte_überwachung_zeit = TimeCurrent(); // Aktuelle Tick-Zeit
         Print("TRACE: Überwachung gestartet - Beide Trigger aktiv (Tick)");
      }
   }
   
   //--- Trade platzieren wenn Überwachung aktiv und Preis über/unter EMA (Place trade when monitoring active and price above/below EMA)
   if(überwachung_aktiv)
   {
      bool bullish_signal = aktueller_close > ema_aktuell;
      bool bearish_signal = aktueller_close < ema_aktuell;
      
      Print("TRACE: Signal Check - Bullish: ", bullish_signal, " Bearish: ", bearish_signal);
      Print("TRACE: Close: ", aktueller_close, " EMA: ", ema_aktuell);
      Print("TRACE: Differenz: ", aktueller_close - ema_aktuell);
      
      //--- Trade-Limit prüfen (Check trade limit)
      if(trades_in_current_crossover >= MaxTradesPerCrossover)
      {
         Print("TRACE: Trade-Limit erreicht (", MaxTradesPerCrossover, ") - Kein neuer Trade");
         return;
      }
      
      //--- Neue Strategie: V-Shape Reversal Trading + RSI 50 Crossover für Haupt-Trades
      if(!PositionSelect(_Symbol))
      {
         //--- 1. Prüfe auf V-Shape Reversal Pattern (Check for V-Shape Reversal Pattern)
         if(UseVShapeReversalTrading)
         {
            ENUM_ORDER_TYPE vshape_direction = PrüfeVShapePattern(aktueller_close, ema_aktuell);
            
            if(vshape_direction == ORDER_TYPE_BUY)
            {
               // V-Shape erkannt: Preis war hoch, jetzt fallend -> REVERSE TRADE (SELL)
               Print("TRACE: V-SHAPE REVERSAL erkannt - REVERSE TRADE: VERKAUF");
               if(PlatziereVShapeTrade(ORDER_TYPE_SELL, aktueller_close, ema_aktuell))
               {
                  trades_in_current_crossover++;
                  entry_price = aktueller_close;
                  max_favorable_excursion = 0;
                  max_adverse_excursion = 0;
                  is_vshape_trade = true;
               }
               return; // V-Shape Trade platziert, keine weiteren Trades
            }
            else if(vshape_direction == ORDER_TYPE_SELL)
            {
               // V-Shape erkannt: Preis war niedrig, jetzt steigend -> REVERSE TRADE (BUY)
               Print("TRACE: V-SHAPE REVERSAL erkannt - REVERSE TRADE: KAUF");
               if(PlatziereVShapeTrade(ORDER_TYPE_BUY, aktueller_close, ema_aktuell))
               {
                  trades_in_current_crossover++;
                  entry_price = aktueller_close;
                  max_favorable_excursion = 0;
                  max_adverse_excursion = 0;
                  is_vshape_trade = true;
               }
               return; // V-Shape Trade platziert, keine weiteren Trades
            }
         }
         
         //--- 2. Haupt-Trend Trade: Warte auf RSI 50 Crossover (Main Trend Trade: Wait for RSI 50 Crossover)
         if(bullish_signal)
         {
            // Prüfe RSI 50 Crossover für KAUF (Check RSI 50 crossover for BUY)
            bool rsi_ready = true;
            if(UseRSI50Crossover)
            {
               rsi_ready = rsi_crossed_above_50 && (ArraySize(rsi_array) > 0 && rsi_array[0] > 50.0);
               if(!rsi_ready)
               {
                  Print("TRACE: KAUF-Signal wartet auf RSI 50 Crossover - RSI: ", (ArraySize(rsi_array) > 0 ? rsi_array[0] : 0));
               }
            }
            
            if(rsi_ready)
            {
               Print("TRACE: Versuche KAUF-Trade zu platzieren (Trade #", trades_in_current_crossover + 1, ")");
               if(PlatziereTrade(ORDER_TYPE_BUY))
               {
                  trades_in_current_crossover++;
                  entry_price = aktueller_close;
                  max_favorable_excursion = 0;
                  max_adverse_excursion = 0;
                  is_vshape_trade = false;
                  rsi_crossed_above_50 = false; // Reset nach Trade
               }
            }
         }
         else if(bearish_signal)
         {
            // Prüfe RSI 50 Crossover für VERKAUF (Check RSI 50 crossover for SELL)
            bool rsi_ready = true;
            if(UseRSI50Crossover)
            {
               rsi_ready = rsi_crossed_below_50 && (ArraySize(rsi_array) > 0 && rsi_array[0] < 50.0);
               if(!rsi_ready)
               {
                  Print("TRACE: VERKAUF-Signal wartet auf RSI 50 Crossover - RSI: ", (ArraySize(rsi_array) > 0 ? rsi_array[0] : 0));
               }
            }
            
            if(rsi_ready)
            {
               Print("TRACE: Versuche VERKAUF-Trade zu platzieren (Trade #", trades_in_current_crossover + 1, ")");
               if(PlatziereTrade(ORDER_TYPE_SELL))
               {
                  trades_in_current_crossover++;
                  entry_price = aktueller_close;
                  max_favorable_excursion = 0;
                  max_adverse_excursion = 0;
                  is_vshape_trade = false;
                  rsi_crossed_below_50 = false; // Reset nach Trade
               }
            }
         }
      }
      else if(PositionSelect(_Symbol))
      {
         Print("TRACE: Position bereits offen - kein neuer Trade");
      }
   }
}

//+------------------------------------------------------------------+
//| V-Shape Pattern Detection                                        |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE PrüfeVShapePattern(double aktueller_preis, double ema_aktuell)
{
   if(!UseVShapeReversalTrading || ArraySize(rsi_array) < 3)
      return WRONG_VALUE;
   
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double current_rsi = rsi_array[0];
   double previous_rsi = rsi_array[1];
   double rsi_before = rsi_array[2];
   
   //--- Hole Preis-Historie für V-Shape Erkennung (Get price history for V-Shape detection)
   double close_0 = iClose(_Symbol, Timeframe, 0);
   double close_1 = iClose(_Symbol, Timeframe, 1);
   double close_2 = iClose(_Symbol, Timeframe, 2);
   double close_3 = iClose(_Symbol, Timeframe, 3);
   
   if(close_1 == 0 || close_2 == 0 || close_3 == 0)
      return WRONG_VALUE;
   
   //--- V-Shape Top Pattern: Preis war hoch (RSI überkauft), jetzt fallend (V-Shape Top Pattern)
   // Pattern: Preis steigt -> erreicht Hoch -> fällt (RSI: hoch -> fällt)
   bool vshape_top = false;
   if(current_rsi < previous_rsi && previous_rsi > RSIOverbought)
   {
      // RSI war überkauft und fällt jetzt
      if(close_0 < close_1 && close_1 < close_2)
      {
         // Preis fällt kontinuierlich
         double price_drop = (close_2 - close_0) / _Point / pips_multiplier;
         if(price_drop > 100.0) // Mindest-Fall von 100 Pips
         {
            vshape_top = true;
            Print("TRACE: V-SHAPE TOP erkannt - RSI fällt von ", previous_rsi, " zu ", current_rsi);
            Print("TRACE: Preis fällt von ", close_2, " zu ", close_0, " (", price_drop, " Pips)");
         }
      }
   }
   
   //--- V-Shape Bottom Pattern: Preis war niedrig (RSI überverkauft), jetzt steigend (V-Shape Bottom Pattern)
   // Pattern: Preis fällt -> erreicht Tief -> steigt (RSI: niedrig -> steigt)
   bool vshape_bottom = false;
   if(current_rsi > previous_rsi && previous_rsi < RSIOversold)
   {
      // RSI war überverkauft und steigt jetzt
      if(close_0 > close_1 && close_1 > close_2)
      {
         // Preis steigt kontinuierlich
         double price_rise = (close_0 - close_2) / _Point / pips_multiplier;
         if(price_rise > 100.0) // Mindest-Anstieg von 100 Pips
         {
            vshape_bottom = true;
            Print("TRACE: V-SHAPE BOTTOM erkannt - RSI steigt von ", previous_rsi, " zu ", current_rsi);
            Print("TRACE: Preis steigt von ", close_2, " zu ", close_0, " (", price_rise, " Pips)");
         }
      }
   }
   
   if(vshape_top)
      return ORDER_TYPE_SELL; // Reverse Trade: Verkauf bei V-Shape Top
   else if(vshape_bottom)
      return ORDER_TYPE_BUY;  // Reverse Trade: Kauf bei V-Shape Bottom
   
   return WRONG_VALUE; // Kein V-Shape erkannt
}

//+------------------------------------------------------------------+
//| V-Shape Reversal Trade platzieren (Place V-Shape Reversal Trade)|
//+------------------------------------------------------------------+
bool PlatziereVShapeTrade(ENUM_ORDER_TYPE order_type, double aktueller_preis, double ema_aktuell)
{
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double stop_loss_pips = VShapeReversalStopLoss;
   double stop_loss_price = 0;
   
   Print("TRACE: Versuche V-SHAPE REVERSAL Trade zu platzieren - Typ: ", (order_type == ORDER_TYPE_BUY) ? "KAUF" : "VERKAUF");
   Print("TRACE: Lot: ", VShapeReversalLotSize, " Stop Loss: ", stop_loss_pips, " Pips");
   
   //--- Berechne Stop Loss (Calculate Stop Loss)
   if(order_type == ORDER_TYPE_BUY)
   {
      stop_loss_price = aktueller_preis - (stop_loss_pips * _Point * pips_multiplier);
   }
   else
   {
      stop_loss_price = aktueller_preis + (stop_loss_pips * _Point * pips_multiplier);
   }
   
   bool success = false;
   
   if(order_type == ORDER_TYPE_BUY)
   {
      success = trade.Buy(VShapeReversalLotSize, _Symbol, 0, stop_loss_price, 0, "V-Shape Reversal Trade");
   }
   else
   {
      success = trade.Sell(VShapeReversalLotSize, _Symbol, 0, stop_loss_price, 0, "V-Shape Reversal Trade");
   }
   
   if(success)
   {
      ticket = (int)trade.ResultOrder();
      Print("TRACE: V-SHAPE Trade erfolgreich platziert: ", (order_type == ORDER_TYPE_BUY) ? "KAUF" : "VERKAUF", " Ticket: ", ticket);
      Print("TRACE: Stop Loss: ", stop_loss_price);
      
      //--- Trade-Öffnungszeit speichern (Save trade opening time)
      trade_open_time = iTime(_Symbol, Timeframe, 0);
      Print("TRACE: Trade-Öffnungszeit: ", TimeToString(trade_open_time));
      
      //--- Überwachung zurücksetzen (Reset monitoring)
      überwachung_aktiv = false;
      preis_trigger_aktiv = false;
      steigung_trigger_aktiv = false;
      
      return true;
   }
   else
   {
      Print("TRACE: Fehler beim Platzieren des V-SHAPE Trades - Retcode: ", trade.ResultRetcode());
      Print("TRACE: Fehlerbeschreibung: ", trade.ResultRetcodeDescription());
      
      return false;
   }
}

//+------------------------------------------------------------------+
//| Trade platzieren (Place trade)                                  |
//+------------------------------------------------------------------+
bool PlatziereTrade(ENUM_ORDER_TYPE order_type)
{
   Print("TRACE: Versuche Trade zu platzieren - Typ: ", (order_type == ORDER_TYPE_BUY) ? "KAUF" : "VERKAUF");
   Print("TRACE: Lot: ", LotGröße);
   
   bool success = false;
   
   if(order_type == ORDER_TYPE_BUY)
   {
      success = trade.Buy(LotGröße, _Symbol, 0, 0, 0, "EMA Crossover Trade");
   }
   else
   {
      success = trade.Sell(LotGröße, _Symbol, 0, 0, 0, "EMA Crossover Trade");
   }
   
   if(success)
   {
      ticket = (int)trade.ResultOrder();
      Print("TRACE: Trade erfolgreich platziert: ", (order_type == ORDER_TYPE_BUY) ? "KAUF" : "VERKAUF", " Ticket: ", ticket);
      
      //--- Trade-Öffnungszeit speichern (Save trade opening time)
      trade_open_time = iTime(_Symbol, Timeframe, 0);
      Print("TRACE: Trade-Öffnungszeit: ", TimeToString(trade_open_time));
      
      //--- Überwachung zurücksetzen (Reset monitoring)
      überwachung_aktiv = false;
      preis_trigger_aktiv = false;
      steigung_trigger_aktiv = false;
      
      return true;
   }
   else
   {
      Print("TRACE: Fehler beim Platzieren des Trades - Retcode: ", trade.ResultRetcode());
      Print("TRACE: Fehlerbeschreibung: ", trade.ResultRetcodeDescription());
      
      return false;
   }
}

//+------------------------------------------------------------------+
//| Trades verwalten (Manage trades)                                |
//+------------------------------------------------------------------+
void VerwalteTrades()
{
   if(!PositionSelect(_Symbol))
      return;
   
   double position_profit = PositionGetDouble(POSITION_PROFIT);
   double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double trailing_stop_pips = TrailingStop;
   
   //--- Für V-Shape Trades: Tighter Trailing Stop (For V-Shape trades: Tighter trailing stop)
   if(is_vshape_trade)
   {
      trailing_stop_pips = VShapeReversalStopLoss * 0.5; // 50% des Stop Loss als Trailing
      Print("TRACE: V-Shape Trade - Verwendeter Trailing Stop: ", trailing_stop_pips, " Pips");
   }
   
   //--- Gleitender Stop (Trailing Stop) - nur wenn Position im Profit ist
   if(position_profit > 0) // Only apply trailing stop when in profit
   {
      if(position_type == POSITION_TYPE_BUY)
      {
         double new_stop_loss = current_price - (trailing_stop_pips * _Point * pips_multiplier);
         double current_stop_loss = PositionGetDouble(POSITION_SL);
         
         // Only move stop loss if new stop is higher than current stop
         if(new_stop_loss > current_stop_loss)
         {
            ÄndereStopLoss(new_stop_loss);
         }
      }
      else if(position_type == POSITION_TYPE_SELL)
      {
         double new_stop_loss = current_price + (trailing_stop_pips * _Point * pips_multiplier);
         double current_stop_loss = PositionGetDouble(POSITION_SL);
         
         // Only move stop loss if new stop is lower than current stop
         if(new_stop_loss < current_stop_loss || current_stop_loss == 0)
         {
            ÄndereStopLoss(new_stop_loss);
         }
      }
   }
   
   //--- Ausstieg bei Preis unter/über EMA (Exit when price below/above EMA)
   if(ArraySize(ema_array) >= 1)
   {
      double aktueller_close = iClose(_Symbol, Timeframe, 0);
      double ema_aktuell = ema_array[0];
      bool exit_bullish = (position_type == POSITION_TYPE_SELL && aktueller_close > ema_aktuell);
      bool exit_bearish = (position_type == POSITION_TYPE_BUY && aktueller_close < ema_aktuell);
      
      if(exit_bullish || exit_bearish)
      {
         Print("TRACE: Ausstiegssignal - Close: ", aktueller_close, " EMA: ", ema_aktuell);
         SchließePosition("EMA Crossover Exit");
         
         Print("TRACE: Position geschlossen - Trade-Counter bleibt bei ", trades_in_current_crossover);
      }
   }
   
   //--- Profit-Prüfung nach X Bars (Profit check after X bars)
   if(CloseUnprofitableTrades && trade_open_time != 0 && PositionSelect(_Symbol))
   {
      Print("TRACE: Profit-Prüfung aktiviert - CloseUnprofitableTrades: ", CloseUnprofitableTrades);
      PrüfeProfitNachBars();
   }
   else if(!CloseUnprofitableTrades)
   {
      Print("TRACE: Profit-Prüfung deaktiviert - CloseUnprofitableTrades: ", CloseUnprofitableTrades);
   }
}

//+------------------------------------------------------------------+
//| Profit-Prüfung nach X Bars (Profit check after X bars)           |
//+------------------------------------------------------------------+
void PrüfeProfitNachBars()
{
   if(!PositionSelect(_Symbol))
   {
      return; // Keine Position offen
   }
   
   datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
   int bars_since_trade_open = iBarShift(_Symbol, Timeframe, trade_open_time);
   
   Print("TRACE: Bars seit Trade-Öffnung: ", bars_since_trade_open, "/", ProfitCheckBars);
   
   //--- Prüfe ob genügend Bars vergangen sind (Check if enough bars have passed)
   if(bars_since_trade_open >= ProfitCheckBars)
   {
      double position_profit = PositionGetDouble(POSITION_PROFIT);
      double position_volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      Print("TRACE: Profit-Prüfung nach ", ProfitCheckBars, " Bars");
      Print("TRACE: Position Profit: ", position_profit, " USD");
      
      //--- Schließe Position wenn nicht im Profit (Close position if not in profit)
      if(position_profit <= 0)
      {
         Print("TRACE: Position nicht im Profit - Schließe Position");
         SchließePosition("Profit Check - Unprofitable");
         
         //--- Trade-Öffnungszeit zurücksetzen (Reset trade opening time)
         trade_open_time = 0;
         Print("TRACE: Trade-Öffnungszeit zurückgesetzt");
      }
      else
      {
         Print("TRACE: Position im Profit - Behalte Position");
         //--- Trade-Öffnungszeit zurücksetzen um weitere Prüfungen zu vermeiden (Reset to avoid further checks)
         trade_open_time = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Stop Loss ändern (Modify Stop Loss)                             |
//+------------------------------------------------------------------+
void ÄndereStopLoss(double new_stop_loss)
{
   Print("TRACE: Versuche Stop Loss zu ändern auf: ", new_stop_loss);
   
   bool success = trade.PositionModify(_Symbol, new_stop_loss, PositionGetDouble(POSITION_TP));
   
   if(success)
   {
      Print("TRACE: Stop Loss erfolgreich geändert auf: ", new_stop_loss);
   }
   else
   {
      Print("TRACE: Fehler beim Ändern des Stop Loss - Retcode: ", trade.ResultRetcode());
      Print("TRACE: Fehlerbeschreibung: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Position schließen (Close position)                             |
//+------------------------------------------------------------------+
void SchließePosition(string reason = "Unbekannt")
{
   Print("TRACE: Versuche Position zu schließen - Grund: ", reason);
   
   bool success = trade.PositionClose(_Symbol);
   
   if(success)
   {
      Print("TRACE: Position erfolgreich geschlossen - Grund: ", reason);
      //--- Reset MAE tracking (Reset MAE tracking)
      entry_price = 0;
      max_favorable_excursion = 0;
      max_adverse_excursion = 0;
      is_vshape_trade = false;
   }
   else
   {
      Print("TRACE: Fehler beim Schließen der Position - Retcode: ", trade.ResultRetcode());
      Print("TRACE: Fehlerbeschreibung: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| V-Shape Reversal Protection Check                                |
//+------------------------------------------------------------------+
bool PrüfeVShapeSchutz(ENUM_ORDER_TYPE order_type, double aktueller_preis, double ema_aktuell)
{
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   
   //--- 1. RSI Filter: Vermeide Einstieg bei extremen RSI-Werten (RSI Filter: Avoid entry at extreme RSI values)
   if(UseRSIFilter)
   {
      if(ArraySize(rsi_array) < 1)
      {
         Print("TRACE: RSI Array zu klein für Filter");
         return false;
      }
      
      double current_rsi = rsi_array[0];
      
      if(order_type == ORDER_TYPE_BUY)
      {
         // Vermeide Einstieg wenn RSI überkauft (Avoid entry when RSI overbought)
         if(current_rsi > RSIOverbought)
         {
            Print("TRACE: RSI Filter blockiert KAUF - RSI: ", current_rsi, " > ", RSIOverbought);
            return false;
         }
      }
      else if(order_type == ORDER_TYPE_SELL)
      {
         // Vermeide Einstieg wenn RSI überverkauft (Avoid entry when RSI oversold)
         if(current_rsi < RSIOversold)
         {
            Print("TRACE: RSI Filter blockiert VERKAUF - RSI: ", current_rsi, " < ", RSIOversold);
            return false;
         }
      }
      
      Print("TRACE: RSI Filter bestanden - RSI: ", current_rsi);
   }
   
   //--- 2. Momentum Confirmation: Prüfe ob Momentum in Richtung des Trades zeigt (Momentum Confirmation)
   if(UseMomentumConfirmation)
   {
      if(!PrüfeMomentum(order_type))
      {
         Print("TRACE: Momentum-Bestätigung fehlgeschlagen");
         return false;
      }
      Print("TRACE: Momentum-Bestätigung erfolgreich");
   }
   
   //--- 3. Pullback Confirmation: Warte auf Pullback statt Einstieg am Extrem (Pullback Confirmation)
   if(UsePullbackConfirmation && trigger_price != 0)
   {
      double price_movement = MathAbs(aktueller_preis - trigger_price) / _Point / pips_multiplier;
      double distance_to_ema = MathAbs(aktueller_preis - ema_aktuell) / _Point / pips_multiplier;
      double initial_distance = MathAbs(trigger_price - ema_aktuell) / _Point / pips_multiplier;
      
      if(initial_distance > 0)
      {
         double pullback_ratio = distance_to_ema / initial_distance;
         
         // Erlaube Einstieg nur wenn Preis zurück zur EMA gezogen ist (Allow entry only if price pulled back toward EMA)
         if(pullback_ratio > (1.0 - PullbackThreshold))
         {
            Print("TRACE: Pullback-Bestätigung fehlgeschlagen - Ratio: ", pullback_ratio, " (benötigt < ", (1.0 - PullbackThreshold), ")");
            return false;
         }
         Print("TRACE: Pullback-Bestätigung erfolgreich - Ratio: ", pullback_ratio);
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Momentum Confirmation Check                                     |
//+------------------------------------------------------------------+
bool PrüfeMomentum(ENUM_ORDER_TYPE order_type)
{
   if(MomentumBars < 1)
      return true;
   
   //--- Prüfe ob die letzten Bars Momentum in Richtung des Trades zeigen (Check if recent bars show momentum in trade direction)
   double close_0 = iClose(_Symbol, Timeframe, 0);
   double close_n = iClose(_Symbol, Timeframe, MomentumBars);
   
   if(close_n == 0)
      return true; // Nicht genug Daten (Not enough data)
   
   if(order_type == ORDER_TYPE_BUY)
   {
      // Für KAUF: Preis sollte höher sein als vor N Bars (For BUY: Price should be higher than N bars ago)
      if(close_0 <= close_n)
      {
         Print("TRACE: Momentum fehlt für KAUF - Close[0]: ", close_0, " Close[", MomentumBars, "]: ", close_n);
         return false;
      }
   }
   else if(order_type == ORDER_TYPE_SELL)
   {
      // Für VERKAUF: Preis sollte niedriger sein als vor N Bars (For SELL: Price should be lower than N bars ago)
      if(close_0 >= close_n)
      {
         Print("TRACE: Momentum fehlt für VERKAUF - Close[0]: ", close_0, " Close[", MomentumBars, "]: ", close_n);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Maximum Adverse Excursion Check                                 |
//+------------------------------------------------------------------+
void PrüfeMAE()
{
   if(!PositionSelect(_Symbol) || entry_price == 0)
      return;
   
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   
   double current_excursion = 0;
   
   if(position_type == POSITION_TYPE_BUY)
   {
      current_excursion = (current_price - entry_price) / _Point / pips_multiplier;
   }
   else if(position_type == POSITION_TYPE_SELL)
   {
      current_excursion = (entry_price - current_price) / _Point / pips_multiplier;
   }
   
   //--- Update maximale Bewegungen (Update maximum movements)
   if(current_excursion > max_favorable_excursion)
   {
      max_favorable_excursion = current_excursion;
   }
   
   if(current_excursion < -max_adverse_excursion)
   {
      max_adverse_excursion = -current_excursion;
   }
   
   //--- Prüfe ob MAE-Schwelle überschritten wurde (Check if MAE threshold exceeded)
   if(max_adverse_excursion > MAEThreshold)
   {
      // Prüfe ob genug Bars vergangen sind (Check if enough bars have passed)
      datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
      int bars_since_entry = iBarShift(_Symbol, Timeframe, trade_open_time);
      
      if(bars_since_entry >= MAECheckBars)
      {
         double position_profit = PositionGetDouble(POSITION_PROFIT);
         
         // Schließe nur wenn Position nicht im Profit ist (Close only if position not in profit)
         if(position_profit <= 0)
         {
            Print("TRACE: MAE-Schwelle überschritten - MAE: ", max_adverse_excursion, " Pips (Schwelle: ", MAEThreshold, ")");
            Print("TRACE: Position Profit: ", position_profit, " - Schließe Position");
            SchließePosition("MAE Protection - Excessive Adverse Excursion");
         }
         else
         {
            Print("TRACE: MAE-Schwelle überschritten aber Position im Profit - MAE: ", max_adverse_excursion, " Profit: ", position_profit);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Early Reversal Detection                                        |
//+------------------------------------------------------------------+
bool PrüfeFrüheReversal(ENUM_POSITION_TYPE position_type, double aktueller_preis, double ema_aktuell)
{
   if(!UseEarlyReversalDetection || entry_price == 0)
      return false;
   
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double price_to_ema = MathAbs(aktueller_preis - ema_aktuell) / _Point / pips_multiplier;
   double entry_to_ema = MathAbs(entry_price - ema_aktuell) / _Point / pips_multiplier;
   
   if(entry_to_ema == 0)
      return false;
   
   //--- Prüfe ob Preis sich zu weit zurück zur EMA bewegt hat (Check if price moved too far back toward EMA)
   double reversal_ratio = price_to_ema / entry_to_ema;
   
   if(reversal_ratio < ReversalThreshold)
   {
      // Preis hat sich mehr als X% zurück zur EMA bewegt - mögliche Reversal (Price moved more than X% back toward EMA - possible reversal)
      Print("TRACE: Frühe Reversal erkannt - Ratio: ", reversal_ratio, " (Schwelle: ", ReversalThreshold, ")");
      
      // Prüfe ob Position im Verlust ist (Check if position is in loss)
      if(PositionSelect(_Symbol))
      {
         double position_profit = PositionGetDouble(POSITION_PROFIT);
         if(position_profit <= 0)
         {
            Print("TRACE: Reversal erkannt und Position im Verlust - Schließe Position");
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+