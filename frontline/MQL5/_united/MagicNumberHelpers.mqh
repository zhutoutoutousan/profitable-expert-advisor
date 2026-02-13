//+------------------------------------------------------------------+
//|                                          MagicNumberHelpers.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Select position by symbol and magic number                       |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(string symbol, ulong magic_number)
{
   // First try to find position by symbol
   if(!PositionSelect(symbol))
      return false;
   
   // Check if the selected position has the correct magic number
   if(PositionGetInteger(POSITION_MAGIC) != magic_number)
   {
      // Position exists but wrong magic number, search all positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) > 0)
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == magic_number)
            {
               return true;
            }
         }
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Select position by ticket and verify magic number and symbol     |
//+------------------------------------------------------------------+
bool PositionSelectByTicketAndMagic(ulong ticket, ulong magic_number)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   return (PositionGetInteger(POSITION_MAGIC) == magic_number);
}

//+------------------------------------------------------------------+
//| Select position by ticket and verify symbol, magic number        |
//+------------------------------------------------------------------+
bool PositionSelectByTicketSymbolAndMagic(ulong ticket, string symbol, ulong magic_number)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   return (PositionGetString(POSITION_SYMBOL) == symbol && 
           PositionGetInteger(POSITION_MAGIC) == magic_number);
}

//+------------------------------------------------------------------+
//| Check if position exists with correct magic number               |
//+------------------------------------------------------------------+
bool PositionExistsByMagic(string symbol, ulong magic_number)
{
   return PositionSelectByMagic(symbol, magic_number);
}

//+------------------------------------------------------------------+
//| Get position ticket by symbol and magic number                   |
//+------------------------------------------------------------------+
ulong GetPositionTicketByMagic(string symbol, ulong magic_number)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic_number)
         {
            return ticket;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Close position by symbol and magic number                        |
//+------------------------------------------------------------------+
bool ClosePositionByMagic(CTrade &trade_obj, string symbol, ulong magic_number)
{
   ulong ticket = GetPositionTicketByMagic(symbol, magic_number);
   if(ticket == 0)
      return false;
   
   return trade_obj.PositionClose(ticket);
}

//+------------------------------------------------------------------+
//| Modify position by symbol and magic number                        |
//+------------------------------------------------------------------+
bool ModifyPositionByMagic(CTrade &trade_obj, string symbol, ulong magic_number, 
                         double sl, double tp)
{
   ulong ticket = GetPositionTicketByMagic(symbol, magic_number);
   if(ticket == 0)
      return false;
   
   return trade_obj.PositionModify(ticket, sl, tp);
}

//+------------------------------------------------------------------+
//| Get position profit by symbol and magic number                   |
//+------------------------------------------------------------------+
double GetPositionProfitByMagic(string symbol, ulong magic_number)
{
   if(!PositionSelectByMagic(symbol, magic_number))
      return 0.0;
   
   return PositionGetDouble(POSITION_PROFIT);
}

//+------------------------------------------------------------------+
//| Get position type by symbol and magic number                     |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetPositionTypeByMagic(string symbol, ulong magic_number)
{
   if(!PositionSelectByMagic(symbol, magic_number))
      return WRONG_VALUE;
   
   return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
}

//+------------------------------------------------------------------+
//| Count positions by symbol and magic number                       |
//+------------------------------------------------------------------+
int CountPositionsByMagic(string symbol, ulong magic_number)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic_number)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
