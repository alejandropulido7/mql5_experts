//=== EXPERT ADVISOR BASADO EN ZONAS AOI Y ESTRUCTURAS (MT5) ===
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input int EMA_Period = 20;
input int LookbackBarsStructure = 300;
input int LookbackBars = 100;
input int MinTouches = 3;
input int MaxAOIs = 3;
input double Risk_Percent = 30;
input double ratio = 3;
ENUM_TIMEFRAMES StructuresAvailables[] = {PERIOD_H4, PERIOD_H1, PERIOD_M15};
//SOLO FUNCIONA EN MT5 con USDCHF y USDCAD

struct AOIZona {
   double minPrice;
   double maxPrice;
   int count;
};
AOIZona AOIs[];

struct Structure {
   int period;
   double highestPoint;
   double lowestPoint;
   int highestIndex;
   int lowestIndex;
   int direction; //1: bullish, 0: bearish, -1: consolidate
};
Structure StructuresArray[];

int EsEngulfing(ENUM_TIMEFRAMES tf, int i) {
   if (i < 1) return 0;
   double open1 = iOpen(_Symbol, tf, i);
   double close1 = iClose(_Symbol, tf, i);
   double open0 = iOpen(_Symbol, tf, i - 1);
   double close0 = iClose(_Symbol, tf, i - 1);
   bool esBullish = (close0 < open0) && (close1 > open1) && (open1 < close0 && close1 > open0);
   bool esBearish = (close0 > open0) && (close1 < open1) && (open1 > close0 && close1 < open0);
   if (esBullish) return 1;
   if (esBearish) return 0;
   return -1;
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
   if (close < ema[0]) return 0;
   return -1;
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

int TocaAOIyDireccion(AOIZona &zonas[], ENUM_TIMEFRAMES tf, int i) {
   double high  = iHigh(_Symbol, tf, i);
   double low   = iLow(_Symbol, tf, i);
   double open  = iOpen(_Symbol, tf, i);
   double close = iClose(_Symbol, tf, i);

   for (int j = 0; j < ArraySize(zonas); j++) {
      if (high >= zonas[j].minPrice && low <= zonas[j].maxPrice) {
         if (close > zonas[j].maxPrice)
            return 1;  // Toca AOI y es vela alcista
         else if (close < zonas[j].minPrice)
            return 0;  // Toca AOI y es vela bajista
         else
            return -1; // Vela doji o sin dirección clara
      }
   }
   return -1; // No toca ninguna AOI
}

void DetectAOIs(ENUM_TIMEFRAMES tf) {
   int totalBars = iBars(_Symbol, tf);
   int maxBars = MathMin(totalBars - 1, LookbackBars);
   if (maxBars <= 0) return;
   double closes[];
   ArrayResize(closes, maxBars);
   for (int i = 0; i < maxBars; i++)
      closes[i] = iClose(_Symbol, tf, i);
      
   int volume = (int)MathCeil(CalcularTamanioPromedioVelaEnPips(tf,LookbackBarsStructure)/2);
   double range = volume * _Point;
      
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
         //if (maxZ > StructuresArray[0].highestPoint || minZ < StructuresArray[0].lowestPoint)
           // continue;
         bool alreadyExists = false;
         double buffer = (volume * 2) * _Point;
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

void IdentifyStructures(){
   double maxClose;
   double minClose;
   int highIndex;
   int lowIndex;
   ArrayResize(StructuresArray, ArraySize(StructuresAvailables));
   for(int i=0;i<ArraySize(StructuresAvailables);i++)
     {
      MarcarPuntoMasAltoYBajo(StructuresAvailables[i],
         LookbackBarsStructure,
         maxClose,
         minClose,
         highIndex,
         lowIndex
      );
      StructuresArray[i].period = StructuresAvailables[i];
      StructuresArray[i].highestPoint = maxClose;
      StructuresArray[i].lowestPoint = minClose;
      StructuresArray[i].highestIndex = highIndex;
      StructuresArray[i].lowestIndex = lowIndex;
      StructuresArray[i].direction = highIndex < lowIndex ? 1 : 0;
      
     }
   
}

void MarcarPuntoMasAltoYBajo(
   ENUM_TIMEFRAMES tf,
   int lookbackBars,
   double &maxCloseOut,
   double &minCloseOut,
   int &highIndexOut,
   int &lowIndexOut
) {
   
   double maxClose = -DBL_MAX;
   double minClose = DBL_MAX;
   int highIndex = -1;
   int lowIndex = -1;

   int total = lookbackBars;
   if (total <= 0) return;

   for (int i = 0; i < total; i++) {
      double close = iClose(_Symbol, tf, i);

      if (close > maxClose) {
         maxClose = close;
         highIndex = i;
      }

      if (close < minClose) {
         minClose = close;
         lowIndex = i;
      }
      
   }
   
   // Asignar salidas
   maxCloseOut = maxClose;
   minCloseOut = minClose;
   highIndexOut = highIndex;
   lowIndexOut = lowIndex;
}

int ValidarEstructura(){
   
   int bullishCount = 0;
   int bearishCount = 0;
   for(int i=0;i<ArraySize(StructuresArray);i++)
     {
      Print(StructuresArray[i].period +"-"+StructuresArray[i].direction);
      if(StructuresArray[i].direction == 1)
        {
         bullishCount ++;
        }
       if(StructuresArray[i].direction == 0)
        {
         bearishCount ++;
        }
     }
     
     if(bullishCount >= 2)
       {
        return 1;
       }
     if(bearishCount >= 2)
       {
        return 0;
       }
     return -1;
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

// Retorna:
//  1 → Estructura alcista
//  0 → Estructura bajista
// -1 → Indefinida (pocos datos o empate)
int DetectarEstructura(ENUM_TIMEFRAMES tf, int lookbackBars = 100) {
   double highestClose = -DBL_MAX;
   double lowestClose  = DBL_MAX;
   int highestIndex = -1;
   int lowestIndex  = -1;

   int total = iBars(_Symbol, tf);
   if (total < lookbackBars) lookbackBars = total - 1;

   for (int i = 0; i < lookbackBars; i++) {
      double close = iClose(_Symbol, tf, i);
      if (close > highestClose) {
         highestClose = close;
         highestIndex = i;
      }
      if (close < lowestClose) {
         lowestClose = close;
         lowestIndex = i;
      }
   }

   if (highestIndex < 0 || lowestIndex < 0) return -1;

   if (highestIndex < lowestIndex)
      return 1;  // Estructura alcista
   else if (highestIndex > lowestIndex)
      return 0;  // Estructura bajista
   else
      return -1; // Indefinida
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

// Retorna:
//  1 → Alcista (precio > EMA)
//  0 → Bajista (precio < EMA)
// -1 → Indefinida / error
int DetectarEstructuraPorEMA(ENUM_TIMEFRAMES tf, int emaPeriod = 50) {
   int handle = iMA(_Symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (handle == INVALID_HANDLE) {
      Print("Error al crear EMA");
      return -1;
   }

   double ema[], close;
   ArraySetAsSeries(ema, true);

   if (CopyBuffer(handle, 0, 0, 1, ema) <= 0) {
      Print("Error al copiar EMA");
      return -1;
   }

   close = iClose(_Symbol, tf, 1);

   if (close > ema[0])
      return 1;  // Alcista
   else if (close < ema[0])
      return 0;  // Bajista
   else
      return -1; // Igual o error
}


int CalcularTamanioPromedioVelaEnPips(ENUM_TIMEFRAMES timeframe, int barras) {
   if (barras <= 0) return 0;

   double sumaRangos = 0;
   int total = barras;

   for (int i = 0; i < total; i++) {
      double high = iHigh(Symbol(), timeframe, i);
      double low = iLow(Symbol(), timeframe, i);
      double rango = high - low;
      sumaRangos += rango;
   }

   double promedio = sumaRangos / total;

   // Convertir a pips
   double pipSize = (Digits() == 5 || Digits() == 3) ? _Point * 10 : _Point;
   double promedioPips = promedio / pipSize;

   // Redondear a 1 decimal
   return (int)MathCeil(promedioPips);
}

// Retorna:
//  1 → cruce alcista (de abajo hacia arriba)
//  0 → cruce bajista (de arriba hacia abajo)
// -1 → sin cruce
int CrucePrecioEMA(ENUM_TIMEFRAMES tf, int emaPeriod = 10) {
   ;
   int handle = iMA(_Symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (handle == INVALID_HANDLE) {
      Print("Error al crear EMA");
      return -1;
   }

   double ema[], close[], prevClose;
   ArraySetAsSeries(ema, true);

   if (CopyBuffer(handle, 0, 0, 2, ema) != 2) {
      Print("Error al copiar EMA");
      return -1;
   }

   double c0 = iClose(_Symbol, tf, 0); // cierre actual
   double c1 = iClose(_Symbol, tf, 1); // cierre previo

   double ema0 = ema[0]; // EMA actual
   double ema1 = ema[1]; // EMA anterior

   // Cruce alcista: antes debajo de la EMA, ahora por encima
   if (c1 < ema1 && c0 > ema0)
      return 1;

   // Cruce bajista: antes encima de la EMA, ahora por debajo
   if (c1 > ema1 && c0 < ema0)
      return 0;

   return -1; // sin cruce
}

// Devuelve true si el cierre de la vela está en la sesión de London o NY (ajustado a UTC+3)
bool IsInLondonOrNYSession(ENUM_TIMEFRAMES tf, int i, int utcOffset = 0) {
   datetime closeTime = iTime(_Symbol, tf, i);
   MqlDateTime dt;
   TimeToStruct(closeTime, dt);

   int hour = dt.hour;
   
   Print("Hour:"+hour);
   
   // Londres y NY: 06:00-17:00 UTC -> 9:00-20:00 UTC+3
   int sessionStart = 6 + utcOffset;
   int sessionEnd   = 14 + utcOffset;

   bool validSession = false;
   // Validar sesión de Londres
   validSession = (hour >= sessionStart && hour < sessionEnd);
   Print("validSession:"+validSession);

   return validSession;
}



datetime lastBarTime = 0;

void OnTick() {
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if (currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   int i = 1;
   
   bool validSession = IsInLondonOrNYSession(PERIOD_M15, i);
   
   if(!validSession){
      ArrayFree(AOIs);
      ArrayFree(StructuresArray);
      DetectAOIs(PERIOD_H4);
      DrawAOIs();
   }
   IdentifyStructures();
   

   
   if (HayOperacionAbierta()) return;

   int cierreXEMA = CierreRespectoEMA(PERIOD_H1, i, 20);
   int aoiDirection = TocaAOIyDireccion(AOIs, PERIOD_H1, i);
   int cruceEma = CrucePrecioEMA(PERIOD_H1, 50);
   
   double close = iClose(_Symbol, PERIOD_M15, 1);
   
   int engul = EsEngulfing(PERIOD_H1, i);
   int estructura = ValidarEstructura();
   int estructuraH4 = DetectarEstructuraPorEMA(PERIOD_H4, 20);
   int estructuraH1EMA = DetectarEstructuraPorEMA(PERIOD_H1, LookbackBarsStructure);
   int estructuraM15 = DetectarEstructura(PERIOD_M15, LookbackBarsStructure);
   int estructuraM15EMA = DetectarEstructuraPorEMA(PERIOD_M15, 50);
   int estructuraH1 = DetectarEstructura(PERIOD_M15, LookbackBarsStructure);
   bool velaGrande = CuerpoVelaMenorOIgual(1, PERIOD_M15, CalcularTamanioPromedioVelaEnPips(PERIOD_M15, 10));
   
   double sl, tp, lotSize, entry;
   
   double pip = (_Digits == 5 || _Digits == 3) ? 10 * _Point : _Point;
   double extraSL = 10 * pip;
   
   if(
      //SpreadValido()
      //!velaGrande
      validSession
   ){
   
      if (
         true
         && engul == 1 
         && aoiDirection == 1 
         && estructuraM15EMA == 1
         && estructuraM15 == 1
         && estructuraH1EMA == 1
         && estructuraH1 == 1
         //&& cruceEma == 0
         ) {
         double low = iLow(_Symbol, PERIOD_H1, 1);
         entry = (low + iHigh(_Symbol, PERIOD_H1, 1)) / 2;
         sl = low - extraSL;
         double riskPoints = entry - sl;
         tp = entry + (riskPoints * ratio);
         if (riskPoints < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) return;
         lotSize = LotsByRiskUsingPrices(entry, sl);
         trade.Buy(lotSize, _Symbol, entry, sl, tp, NULL);
      }
      if (
         true
         && engul == 0 
         && aoiDirection == 0 
         && estructuraM15EMA == 0
         && estructuraM15 == 0
         && estructuraH1EMA == 0
         && estructuraH1 == 0
         //&& cruceEma == 1
         ) {
         double high = iHigh(_Symbol, PERIOD_H1, 1);
         entry = (high + iLow(_Symbol, PERIOD_H1, 1)) / 2;
         sl = high + extraSL;
         double riskPoints = sl - entry;
         tp = entry - (riskPoints * ratio);
         if (riskPoints < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) return;
         lotSize = LotsByRiskUsingPrices(entry, sl);
         trade.Sell(lotSize, _Symbol, entry, sl, tp, NULL);
      }
   
   }

   CerrarOperacionesViejas(2);
   
}

double LotsByRiskUsingPrices(double entry_price, double sl_price, string symbol=NULL)
{
   if(symbol == NULL || symbol == "") symbol = _Symbol;
   if(Risk_Percent <= 0.0) return 0.0;

   // Monto a arriesgar
   double base = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = base * (Risk_Percent / 100.0);

   // Distancia al SL en puntos del símbolo
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0.0;
   double stop_points = MathAbs(entry_price - sl_price) / point;
   if(stop_points <= 0.0) return 0.0;

   // Valor monetario por punto y por lote
   double vpp = ValuePerPointPerLot(symbol);
   if(vpp <= 0.0) return 0.0;

   // Riesgo por 1 lote dada la distancia al SL
   double risk_per_lot = stop_points * vpp;
   if(risk_per_lot <= 0.0) return 0.0;

   // Lots teóricos
   double lots = risk_money / risk_per_lot;

   // Ajustar a step/min/max (redondeo hacia abajo para no exceder riesgo)
   return NormalizeVolumeToStep(symbol, lots);
}

double ValuePerPointPerLot(string symbol)
{
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE); // valor del "tick" (en divisa de la cuenta) para 1 lot
   double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);  // tamaño del tick en precio
   double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);            // tamaño del "point" (=_Point)
   if(tick_value <= 0.0 || tick_size <= 0.0 || point <= 0.0) return 0.0;
   // Si 1 tick mueve 'tick_value', entonces 1 point mueve:
   // value_per_point = tick_value * (point / tick_size)
   return tick_value * (point / tick_size);
}

double NormalizeVolumeToStep(string symbol, double vol)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;               // fallback típico
   // Se normaliza HACIA ABAJO para no exceder el riesgo
   double normalized = MathFloor(vol / step) * step;
   if(normalized < minv) normalized = 0.0;    // si no llega al mínimo, devuelve 0 (no tradear)
   if(normalized > maxv) normalized = maxv;
   return normalized;
}

// Retorna true si el cuerpo de la vela en la posición i es menor o igual a nPips
bool CuerpoVelaMenorOIgual(int i, ENUM_TIMEFRAMES tf, double nPips) {
   double open  = iOpen(_Symbol, tf, i);
   double close = iClose(_Symbol, tf, i);

   double cuerpo = MathAbs(close - open);

   // convertir nPips a precio
   double maxCuerpo = nPips * _Point;

   if (cuerpo <= maxCuerpo)
      return true;

   return false;
}


void CerrarOperacionesViejas(int maxHoras = 2) {
   datetime ahora = TimeCurrent();

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      // calcula cuánto tiempo lleva abierta en segundos
      int segundosAbierta = int(ahora - openTime);

      if (segundosAbierta >= maxHoras * 3600) {
         double volumen = PositionGetDouble(POSITION_VOLUME);
         int tipo = (int)PositionGetInteger(POSITION_TYPE);

         // cerramos según el tipo
         if (tipo == POSITION_TYPE_BUY)
            trade.PositionClose(ticket);
         else if (tipo == POSITION_TYPE_SELL)
            trade.PositionClose(ticket);
      }
   }
}



//=== FUNCIÓN PARA VALIDAR SPREAD MÁXIMO EN PIPS ===
bool SpreadValido(double maxPips = 5.0) {
   double spreadActual = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   // Detectar si el instrumento usa 5/3 dígitos (pips fraccionarios)
   double pipSize = (Digits() == 3 || Digits() == 5) ? 10.0 : 1.0;

   double spreadEnPips = spreadActual / pipSize;
   
   Print("Spread: ", spreadEnPips);

   return (spreadEnPips <= maxPips);
}


/*
//+------------------------------------------------------------------+
//| Cálculo del tamaño de lote basado en balance y riesgo           |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPoints)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (Risk_Percent / 100.0);

   double valuePerPoint = tickValue / tickSize;
   double lotSize = (riskMoney / (riskPoints / point * valuePerPoint));
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   Print("Balance:", balance,
      " RiskMoney:", riskMoney,
      " RiskPoints:", riskPoints,
      " minLot:", minLot,
      " lotStep:", lotStep,
      " LotSize:", lotSize);

   //lotSize = MathMax(minLot, NormalizeDouble(lotSize, 2));
   //lotSize = NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);
   //lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Ahora sí, compara con el mínimo
   //if (lotSize < minLot)   
     // lotSize = minLot;
   
   Print("Balance:", balance,
      " RiskMoney:", riskMoney,
      " RiskPoints:", riskPoints,
      " ValuePerPoint:", valuePerPoint,
      " LotSize:", lotSize);
   
   return 2;
  }
  */
  
double CalculateLotSize(double riskPoints)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (Risk_Percent / 100.0);

   double valuePerPoint = tickValue / tickSize;
   double lotSize = riskMoney / (MathAbs(riskPoints) / point * valuePerPoint);

   // Ajusta al lote mínimo y múltiplo de lotStep
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, lotSize);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = NormalizeDouble(lotSize, 2);

   return 4;
}
