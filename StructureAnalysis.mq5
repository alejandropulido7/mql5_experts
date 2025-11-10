//+------------------------------------------------------------------+
//|                                            StructureAnalisys.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window

input int amountPreviousCandleStructure = 2;

struct Structure {
   ENUM_TIMEFRAMES period;
   double highestPoint;
   double lowestPoint;
   int highestIndex;
   int lowestIndex;
   int direction; //1: bullish, 0: bearish, -1: consolidate
};
Structure StructuresArray[];
datetime lastProcessedTime = 0;
int highIndexes[];
int lowIndexes[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- indicator buffers mapping
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int32_t rates_total,
                const int32_t prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int32_t &spread[])
  {
//---
   
//--- return value of prev_calculated for next call
   if (time[0] == lastProcessedTime)
      return(rates_total);  // aún no se ha cerrado una nueva vela

   lastProcessedTime = time[0];

   ClearObjets();
   //DetectarEstructura(PERIOD_H4, 300);
   //DrawStructure();
   MarcarEstructura(PERIOD_H4);
   return(rates_total);
  }
  
  void ClearObjets() {
   int total = ObjectsTotal(0);  // 0 = gráfico actual
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      ObjectDelete(0, name);
   }
   }
  


bool isBullish(ENUM_TIMEFRAMES tf, int i){
   double openCurrent = iOpen(Symbol(), tf, i);
   double closeCurrent = iClose(Symbol(), tf, i);
   
   return openCurrent < closeCurrent;
}

bool validateStructureByPreviousCandles(int candleIndex, ENUM_TIMEFRAMES tf){
   double openCurrent = iOpen(Symbol(), tf, candleIndex);
   double closeCurrent = iClose(Symbol(), tf, candleIndex);
   
   int index = candleIndex+1;
   bool bullish = openCurrent < closeCurrent;
   int countCandles = 0;
   
   while(index <= amountPreviousCandleStructure+candleIndex)
     {
      double open = iOpen(Symbol(), tf, index);
      double close = iClose(Symbol(), tf, index);
      bool bullishPreviousCandle = open < close;
      if(bullish == bullishPreviousCandle){
         countCandles++;
      }
      index++;
     }
   if(countCandles == amountPreviousCandleStructure){
      return true;
   }
   return false;
}

void DrawStructure(){
   Print(ArraySize(StructuresArray));

   for (int i = 0; i < ArraySize(StructuresArray); i++) {
   
      Print(i+": High("+StructuresArray[i].highestIndex+") Low("+StructuresArray[i].lowestIndex+")");
      string highLineName = "STRUCT_HIGH_" + IntegerToString(i);
      string lowLineName = "STRUCT_LOW_" + IntegerToString(i);
      
      datetime lowerTime = iTime(_Symbol, StructuresArray[i].period, StructuresArray[i].lowestIndex);
      ObjectCreate(0, lowLineName, OBJ_ARROW, 0, lowerTime, StructuresArray[i].lowestPoint);
      ObjectSetInteger(0, lowLineName, OBJPROP_ARROWCODE, 233);
      ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);
      
      datetime higherTime = iTime(_Symbol, StructuresArray[i].period, StructuresArray[i].highestIndex);
      ObjectCreate(0, highLineName, OBJ_ARROW, 0, higherTime, StructuresArray[i].highestPoint);
      ObjectSetInteger(0, highLineName, OBJPROP_ARROWCODE, 234);
      ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);
     }
}

// Marca estructura: swing high y swing low con flechas
void MarcarEstructura(ENUM_TIMEFRAMES tf, int lookback = 300) {
   ArrayResize(lowIndexes, lookback);
   ArrayResize(highIndexes, lookback);
   for (int i = 1; i < lookback; i++) {
      //--- Datos vela actual y previas
      double open_i     = iOpen(_Symbol, tf, i);
      double close_i    = iClose(_Symbol, tf, i);
      double low_i      = iLow(_Symbol, tf, i);
      double high_i     = iHigh(_Symbol, tf, i);

      double close_ip1  = iClose(_Symbol, tf, i+1);
      double open_ip1   = iOpen(_Symbol, tf, i+1);
      double close_ip2  = iClose(_Symbol, tf, i+2);
      double open_ip2   = iOpen(_Symbol, tf, i+2);
      
      double close_ia1  = iClose(_Symbol, tf, i-1);
      double open_ia1   = iOpen(_Symbol, tf, i-1);
      double close_ia2  = iClose(_Symbol, tf, i-2);
      double open_ia2   = iOpen(_Symbol, tf, i-2);


      //--- Swing Low: 2 bajistas previas, actual alcista
      bool prev1_bearish = (close_ip1 < open_ip1);
      bool prev2_bearish = (close_ip2 < open_ip2);
      bool after1_bullish = (close_ia1 > open_ia1);
      bool after2_bullish = (close_ia2 > open_ia2);
      bool curr_bullish  = (close_i > open_i);
      
      //--- Swing High: 2 alcistas previas, actual bajista
      bool prev1_bullish = (close_ip1 > open_ip1);
      bool prev2_bullish = (close_ip2 > open_ip2);
      bool after1_bearish = (close_ia1 < open_ia1);
      bool after2_bearish = (close_ia2 < open_ia2);
      bool curr_bearish  = (close_i < open_i);
      
      bool isBullishEngulfingAfter = (open_i < close_ia1) && (curr_bearish && prev1_bearish && after1_bullish);
      bool isBearishEngulfingAfter = (open_i < close_ia1) && (curr_bullish && prev1_bullish && after1_bearish);
      
      if (
            //(curr_bullish && prev1_bearish && prev2_bearish && after1_bullish) || 
            (curr_bullish && prev1_bearish && after1_bullish && after2_bullish) || 
            isBullishEngulfingAfter) {
         string name = "SWING_LOW_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, tf, i), low_i - 5 * _Point);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233); // Flecha arriba
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
         
         lowIndexes[i] = i; 
      }

      if (
            //(curr_bearish && prev1_bullish && prev2_bullish && after1_bearish) || 
            (curr_bearish && prev1_bullish && after1_bearish && after2_bearish) ||
            isBearishEngulfingAfter) {
         string name = "SWING_HIGH_" + IntegerToString(i);
         ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, tf, i), high_i + 5 * _Point);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234); // Flecha abajo
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
         
         highIndexes[i] = i;
      }
   }
   //Recorrer los lowIndexes y validar si entre i y i+1 hay mas de un highIndex, si lo hay, dejar el mas high y borrar el otro
}

