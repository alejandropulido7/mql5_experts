//+------------------------------------------------------------------+
//|                      Indicador de señales basado en EMA y Engulfing |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 clrBlue   // Señal de Compra
#property indicator_color2 clrRed    // Señal de Venta

#property strict

// Buffers de señales
double BuyBuffer[];
double SellBuffer[];

input int EMA10_Period = 10;
input int EMA50_Period = 50;
input int LookbackBars = 15;
input int EngulfingBufferPips = 10;
int TimeframeAOI = PERIOD_H4;
int MinTouches = 3;
int MaxAOIs = 3;
int StructuresAvailables[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15};
color StructureColors[] = {clrBlue, clrGreen, clrDarkRed, clrDarkSlateGray};
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
   color colorStruc;
};
Structure StructuresArray[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer);
   SetIndexStyle(0, DRAW_ARROW);
   SetIndexArrow(0, 233);  // Flecha hacia arriba

   SetIndexBuffer(1, SellBuffer);
   SetIndexStyle(1, DRAW_ARROW);
   SetIndexArrow(1, 234);  // Flecha hacia abajo

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if (rates_total < EMA50_Period + 2)
      return 0;
      
      
      
   for (int i = 0; i < rates_total - 1; i++) {
      
      IdentifyStructures();
      DetectAOIs();
      //DrawAOIs();
   
      BuyBuffer[i] = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;

      double ema10 = iMA(NULL, 0, EMA10_Period, 0, MODE_EMA, PRICE_CLOSE, i);
      double ema50 = iMA(NULL, 0, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE, i);
      double ema50_prev = iMA(NULL, 0, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE, i+1);

      // Determinar dirección de tendencia con EMA10
      bool isBullishStructure = close[i] > ema10;
      bool isBearishStructure = close[i] < ema10;
      

      // Detectar vela envolvente
      double open1  = open[i];
      double close1 = close[i];
      double open0  = open[i + 1];
      double close0 = close[i + 1];

      bool isBullishEngulfing = (close0 < open0) && (close1 > open1) && (open1 < close0 && close1 > open0);
      bool isBearishEngulfing = (close0 > open0) && (close1 < open1) && (open1 > close0 && close1 < open0);

      // Señal de COMPRA
      if (isBullishStructure && close[i] > ema50 && isBullishEngulfing) {
         BuyBuffer[i] = low[i] - EngulfingBufferPips * Point;
      }

      // Señal de VENTA
      if (isBearishStructure && close[i] < ema50 && isBearishEngulfing) {
         SellBuffer[i] = high[i] + EngulfingBufferPips * Point;
      }
   }
   return rates_total;
  }
//+------------------------------------------------------------------+

void MarcarPuntoMasAltoYBajo(
   int tf,
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
      double close = iClose(Symbol(), tf, i);

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

void IdentifyStructures(){
   double maxClose;
   double minClose;
   int highIndex;
   int lowIndex;
   ArrayResize(StructuresArray, ArraySize(StructuresAvailables));
   for(int i=0;i<ArraySize(StructuresAvailables);i++)
     {
      MarcarPuntoMasAltoYBajo(StructuresAvailables[i],
         15,
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
      StructuresArray[i].colorStruc = StructureColors[i];
      if(highIndex < lowIndex)
        {
         Print( "- "+StructuresAvailables[i]+": "+"BULLISH \n");
         StructuresArray[i].direction = 1;
        } 
        else
         {
          Print( "- "+StructuresAvailables[i]+": "+"BEARISH \n");
          StructuresArray[i].direction = 0;
         }
      
     }
   
}

//=== DETECTAR NUEVAS AOIs DESDE VELAS ===
void DetectAOIs() {
   int totalBars = iBars(Symbol(), TimeframeAOI);
   int maxBars = MathMin(totalBars - 1, LookbackBars);
   //int maxBars = totalBars;
   if (maxBars <= 0) return;

   double closes[];
   ArrayResize(closes, maxBars);

   for (int i = 0; i < maxBars; i++)
      closes[i] = iClose(Symbol(), TimeframeAOI, i);

   int volume = (int)MathCeil(CalcularTamanioPromedioVelaEnPips(PERIOD_H4,LookbackBars)/2);
   double range = volume * Point;

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
         
         // Validar que la AOI esté dentro del rango de cierres estructurales de D1
         if (maxZ > StructuresArray[0].highestPoint || minZ < StructuresArray[0].lowestPoint)
            continue;

         // Validar que no esté muy cerca de otra zona
         bool alreadyExists = false;
         double buffer = (volume*2) * Point;
         for (int k = 0; k < ArraySize(AOIs); k++) {
            if (
               (minZ >= AOIs[k].minPrice - buffer && minZ <= AOIs[k].maxPrice + buffer) ||
               (maxZ >= AOIs[k].minPrice - buffer && maxZ <= AOIs[k].maxPrice + buffer) ||
               (AOIs[k].minPrice >= minZ - buffer && AOIs[k].minPrice <= maxZ + buffer)
            ) {
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

            // Si ya alcanzamos el máximo permitido, salimos
            if (ArraySize(AOIs) >= MaxAOIs)
               return;
         }
      }
   }
}

int CalcularTamanioPromedioVelaEnPips(int timeframe, int barras) {
   if (barras <= 0) return 0;

   double sumaRangos = 0;
   int total = barras;
   Print("total: "+total);

   for (int i = 0; i < total; i++) {
      double high = iHigh(Symbol(), timeframe, i);
      double low = iLow(Symbol(), timeframe, i);
      double rango = high - low;
      sumaRangos += rango;
   }

   double promedio = sumaRangos / total;

   // Convertir a pips
   double pipSize = (Digits == 5 || Digits == 3) ? Point * 10 : Point;
   double promedioPips = promedio / pipSize;

   // Redondear a 1 decimal
   return (int)MathCeil(promedioPips);
}

//=== DIBUJAR LAS ZONAS AOI EN EL GRÁFICO ===
void DrawAOIs() {
   if (ArraySize(AOIs) == 0) return;

   datetime t1 = iTime(NULL, 0, LookbackBars - 1);
   datetime t2 = Time[0];

   for (int i = 0; i < ArraySize(AOIs); i++) {
      string name = "AOI_RECT_" + IntegerToString(i);
      ObjectDelete(name);
      ObjectCreate(name, OBJ_RECTANGLE, 0, t1, AOIs[i].minPrice, t2, AOIs[i].maxPrice);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrAliceBlue);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}