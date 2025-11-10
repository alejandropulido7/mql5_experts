//+------------------------------------------------------------------+
//|                                                     PrimerEA.mq4 |
//|                                  Modificado para SL/TP dinámico  |
//+------------------------------------------------------------------+
#property strict

extern string indicatorName = "IndicatorTest";
extern double lotSize = 0.1;
extern double slippage = 3;
extern int magicNumber = 123456;

double buySignal, sellSignal;

int OnInit()
{
   Print("EA cargado con éxito.");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if (OrdersTotal() > 0) return;

   buySignal = iCustom(Symbol(), 0, indicatorName, 0, 1);
   sellSignal = iCustom(Symbol(), 0, indicatorName, 1, 1);

   double ask = NormalizeDouble(MarketInfo(Symbol(), MODE_ASK), Digits);
   double bid = NormalizeDouble(MarketInfo(Symbol(), MODE_BID), Digits);
   double pip = Point * 10;

   // Señal de Compra
   if (buySignal != EMPTY_VALUE)
   {
      double entryLow = iLow(Symbol(), 0, 1);
      double sl = NormalizeDouble(entryLow - 5 * pip, Digits);
      double tp = NormalizeDouble(ask + 2 * (ask - sl), Digits);

      int buyTicket = OrderSend(Symbol(), OP_BUY, lotSize, ask, slippage, sl, tp, "Buy by Indicator", magicNumber, 0, clrBlue);
      if (buyTicket < 0)
         Print("Error al abrir compra: ", GetLastError());
      else
         Print("Compra abierta: ", buyTicket);
   }

   // Señal de Venta
   if (sellSignal != EMPTY_VALUE)
   {
      double entryHigh = iHigh(Symbol(), 0, 1);
      double sl = NormalizeDouble(entryHigh + 5 * pip, Digits);
      double tp = NormalizeDouble(bid - 2 * (sl - bid), Digits);

      int sellTicket = OrderSend(Symbol(), OP_SELL, lotSize, bid, slippage, sl, tp, "Sell by Indicator", magicNumber, 0, clrRed);
      if (sellTicket < 0)
         Print("Error al abrir venta: ", GetLastError());
      else
         Print("Venta abierta: ", sellTicket);
   }
}
