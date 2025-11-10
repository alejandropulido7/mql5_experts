//=== EXPERT ADVISOR BASADO EN ZONAS AOI Y ESTRUCTURAS (MT5) ===
#include <Trade\Trade.mqh>
CTrade trade;

input double LotSize = 0.1;
input int EMA_Period = 50;
input int EngulfingBufferPips = 5;
input double RiskRewardRatio = 2.0;
input int FixedStopLossPips = 20;
input int LookbackBarsStructure = 20;
input int LookbackBars = 500;
input int MinTouches = 3;
input double OscillationPips = 40;
input int MaxAOIs = 3;

struct AOIZona {
   double minPrice;
   double maxPrice;
   int count;
};
AOIZona AOIs[];

struct Structure {
   int direction;
   double highestPoint;
   double lowestPoint;
};
Structure StructuresArray[1];

int EsEngulfing(ENUM_TIMEFRAMES tf, int i) {
   if (i < 1) return 0;
   double open1 = iOpen(_Symbol, tf, i);
   double close1 = iClose(_Symbol, tf, i);
   double open0 = iOpen(_Symbol, tf, i - 1);
   double close0 = iClose(_Symbol, tf, i - 1);
   bool esBullish = (close0 < open0) && (close1 > open1) && (open1 < close0 && close1 > open0);
   bool esBearish = (close0 > open0) && (close1 < open1) && (open1 > close0 && close1 < open0);
   if (esBullish) return 1;
   if (esBearish) return -1;
   return 0;
}

bool TocaEMA(ENUM_TIMEFRAMES tf, int i, int periodEMA) {
   int handle = iMA(_Symbol, tf, periodEMA, 0, MODE_EMA, PRICE_CLOSE);
   if (handle == INVALID_HANDLE) return false;
   double ema[];
   ArraySetAsSeries(ema, true);
   if (CopyBuffer(handle, 0, i, 1, ema) <= 0) return false;
   double high = iHigh(_Symbol, tf, i);
   double low = iLow(_Symbol, tf, i);
   return (high >= ema[0] && low <= ema[0]);
}

int CierreRespectoEMA(ENUM_TIMEFRAMES tf, int i, int periodEMA) {
   double close = iClose(_Symbol, tf, i);
   int handle = iMA(_Symbol, tf, periodEMA, 0, MODE_EMA, PRICE_CLOSE);
   if (handle == INVALID_HANDLE) return false;
   double ema[];
   ArraySetAsSeries(ema, true);
   if (CopyBuffer(handle, 0, i, 1, ema) <= 0) return false;
   if (close > ema[0]) return 1;
   if (close < ema[0]) return -1;
   return 0;
}

bool TocaAOI(AOIZona &zonas[], ENUM_TIMEFRAMES tf, int i) {
   double high = iHigh(_Symbol, tf, i);
   double low = iLow(_Symbol, tf, i);
   for (int j = 0; j < ArraySize(zonas); j++) {
      if (high >= zonas[j].minPrice && low <= zonas[j].maxPrice)
         return true;
   }
   return false;
}

void DetectAOIs() {
   int totalBars = iBars(_Symbol, PERIOD_H4);
   int maxBars = MathMin(totalBars - 1, LookbackBars);
   if (maxBars <= 0) return;
   double closes[];
   ArrayResize(closes, maxBars);
   for (int i = 0; i < maxBars; i++)
      closes[i] = iClose(_Symbol, PERIOD_H4, i);
   double range = OscillationPips * _Point;
   for (int i = 0; i < maxBars; i++) {
      double base = closes[i];
      double minZ = base - range / 2.0;
      double maxZ = base + range / 2.0;
      int hits = 0;
      for (int j = 0; j < maxBars; j++) {
         if (closes[j] >= minZ && closes[j] <= maxZ)
            hits++;
      }
      if (hits >= MinTouches) {
         bool alreadyExists = false;
         double buffer = (OscillationPips * 2) * _Point;
         for (int k = 0; k < ArraySize(AOIs); k++) {
            if ((minZ >= AOIs[k].minPrice - buffer && minZ <= AOIs[k].maxPrice + buffer) ||
                (maxZ >= AOIs[k].minPrice - buffer && maxZ <= AOIs[k].maxPrice + buffer) ||
                (AOIs[k].minPrice >= minZ - buffer && AOIs[k].minPrice <= maxZ + buffer)) {
               alreadyExists = true;
               break;
            }
         }
         if (!alreadyExists) {
            int idx = ArraySize(AOIs);
            ArrayResize(AOIs, idx + 1);
            AOIs[idx].minPrice = minZ;
            AOIs[idx].maxPrice = maxZ;
            AOIs[idx].count = hits;
            if (ArraySize(AOIs) >= MaxAOIs)
               return;
         }
      }
   }
}

void IdentifyStructures() {
   int total = LookbackBarsStructure;
   double maxClose = -DBL_MAX;
   double minClose = DBL_MAX;
   int highIndex = -1;
   int lowIndex = -1;
   for (int i = 0; i < total; i++) {
      double close = iClose(_Symbol, PERIOD_D1, i);
      if (close > maxClose) {
         maxClose = close;
         highIndex = i;
      }
      if (close < minClose) {
         minClose = close;
         lowIndex = i;
      }
   }
   StructuresArray[0].highestPoint = maxClose;
   StructuresArray[0].lowestPoint = minClose;
   StructuresArray[0].direction = (highIndex < lowIndex) ? 1 : 0;
}

bool HayOperacionAbierta() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (PositionGetTicket(i)) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if (symbol == _Symbol)
            return true;
      }
   }
   return false;
}

void GestionarEntrada(ENUM_TIMEFRAMES tf, int i, bool esCompra) {
   double price = SymbolInfoDouble(_Symbol, esCompra ? SYMBOL_ASK : SYMBOL_BID);
   double slPips = FixedStopLossPips * _Point;
   double sl, tp;

   if (esCompra) {
      sl = price - slPips;
      tp = price + slPips * RiskRewardRatio;
      trade.Buy(LotSize, _Symbol, price, sl, tp);
   } else {
      sl = price + slPips;
      tp = price - slPips * RiskRewardRatio;
      trade.Sell(LotSize, _Symbol, price, sl, tp);
   }
}

void DrawAOIs() {
   if (ArraySize(AOIs) == 0) return;

   datetime times[];
   if (CopyTime(_Symbol, PERIOD_CURRENT, LookbackBars - 1, 1, times) != 1)
      return;

   datetime t1 = times[0];
   datetime t2 = TimeCurrent();

   for (int i = 0; i < ArraySize(AOIs); i++) {
      string name = "AOI_RECT_" + IntegerToString(i);
      ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, AOIs[i].minPrice, t2, AOIs[i].maxPrice);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}

datetime lastBarTime = 0;

void OnTick() {
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if (currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   ArrayFree(AOIs);
   ArrayFree(StructuresArray);

   IdentifyStructures();
   DetectAOIs();
   DrawAOIs();

   int i = 1;
   if (HayOperacionAbierta()) return;

   int ema10Trend = CierreRespectoEMA(PERIOD_M15, i, 10);
   if (!TocaAOI(AOIs, PERIOD_M15, i)) return;
   if (!TocaEMA(PERIOD_M15, i, EMA_Period)) return;
   int cierre = CierreRespectoEMA(PERIOD_M15, i, EMA_Period);
   int engul = EsEngulfing(PERIOD_M15, i);

   if (ema10Trend == 1 && cierre == 1 && engul == 1) {
      GestionarEntrada(PERIOD_M15, i, true);
   }
   if (ema10Trend == -1 && cierre == -1 && engul == -1) {
      GestionarEntrada(PERIOD_M15, i, false);
   }
}
