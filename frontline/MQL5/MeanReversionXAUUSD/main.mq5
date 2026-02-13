//+------------------------------------------------------------------+
//|                                                 EMACrossOver.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property link      "https://www.mql5.com"
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property version   "1.00"
#include <Trade\Trade.mqh>
#include "../_united/MagicNumberHelpers.mqh"
//--- Eingabeparameter (Input Parameters) - Optimized Profitable Parameters
input int    EMA_Periode = 46;           // EMA Periode
input double PreisSchwelle = 600.0;       // Preisbewegung Schwelle in Pips
input double SteigungSchwelle = 80.0;     // EMA Steigung Schwelle in Pips
input int    ÜberwachungTimeout = 800;   // Überwachungszeit in Sekunden
input double TrailingStop = 260.0;        // Gleitender Stop in Pips
input double LotGröße = 0.03;             // Handelsvolumen
input int    MagicNumber = 12351;        // Magic Number für Trades
input bool   UseSpreadAdjustment = true; // Spread-Anpassung verwenden
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1; // Zeitraum für Analyse
input bool   UseBarData = true;          // Bar-Daten statt Tick-Daten verwenden
input int    MaxTradesPerCrossover = 9;  // Maximale Trades pro Crossover-Ereignis
input int    ProfitCheckBars = 12;       // Bars bis zur Profit-Prüfung
input bool   CloseUnprofitableTrades = true; // Unprofitable Trades nach X Bars schließen

//--- Globale Variablen (Global Variables)
int ema_handle;                          // EMA Indicator Handle
double ema_array[];                      // Array für EMA
datetime letzte_überwachung_zeit;        // Zeit der letzten Überwachung
bool überwachung_aktiv = false;          // Überwachungsstatus
bool preis_trigger_aktiv = false;        // Preis-Trigger Status
bool steigung_trigger_aktiv = false;     // Steigungs-Trigger Status
int ticket = 0;                          // Trade Ticket
CTrade trade;                            // CTrade Objekt
int trades_in_current_crossover = 0;     // Anzahl Trades im aktuellen Crossover
bool crossover_detected = false;          // Crossover erkannt
datetime trade_open_time = 0;            // Zeitpunkt des Trade-Öffnens

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
   
   //--- Arrays initialisieren (Initialize arrays)
   ArraySetAsSeries(ema_array, true);
   
   //--- Arrays mit aktuellen Werten füllen (Fill arrays with current values)
   BerechneEMA();
   
   Print("EMA EA initialisiert - Periode: ", EMA_Periode, " Timeframe: ", EnumToString(Timeframe), " Handle: ", ema_handle);
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
      Print("Position offen: ", PositionExistsByMagic(_Symbol, MagicNumber));
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
      
      if(bullish_signal && !PositionExistsByMagic(_Symbol, MagicNumber))
      {
         Print("TRACE: Versuche KAUF-Trade zu platzieren (Trade #", trades_in_current_crossover + 1, ")");
         if(PlatziereTrade(ORDER_TYPE_BUY))
         {
            trades_in_current_crossover++;
         }
      }
      else if(bearish_signal && !PositionExistsByMagic(_Symbol, MagicNumber))
      {
         Print("TRACE: Versuche VERKAUF-Trade zu platzieren (Trade #", trades_in_current_crossover + 1, ")");
         if(PlatziereTrade(ORDER_TYPE_SELL))
         {
            trades_in_current_crossover++;
         }
      }
      else if(PositionExistsByMagic(_Symbol, MagicNumber))
      {
         Print("TRACE: Position bereits offen - kein neuer Trade");
      }
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
   if(!PositionSelectByMagic(_Symbol, MagicNumber))
      return;
   
   double position_profit = PositionGetDouble(POSITION_PROFIT);
   double position_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
   double trailing_stop_pips = TrailingStop;
   
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
   if(CloseUnprofitableTrades && trade_open_time != 0 && PositionExistsByMagic(_Symbol, MagicNumber))
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
   if(!PositionSelectByMagic(_Symbol, MagicNumber))
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
   
   bool success = ModifyPositionByMagic(trade, _Symbol, MagicNumber, new_stop_loss, PositionGetDouble(POSITION_TP));
   
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
   
   bool success = ClosePositionByMagic(trade, _Symbol, MagicNumber);
   
   if(success)
   {
      Print("TRACE: Position erfolgreich geschlossen - Grund: ", reason);
   }
   else
   {
      Print("TRACE: Fehler beim Schließen der Position - Retcode: ", trade.ResultRetcode());
      Print("TRACE: Fehlerbeschreibung: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
