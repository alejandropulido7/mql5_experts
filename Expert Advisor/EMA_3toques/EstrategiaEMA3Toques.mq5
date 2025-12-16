//+------------------------------------------------------------------+
//|                                      EstrategiaEMA3050.mq5    |
//|                        Copyright 2025, Expert Advisor Development|
//|                                                 Gemini Assistant |
//+------------------------------------------------------------------+
#property copyright "Gemini AI"
#property version   "4.00"
#include <Trade\Trade.mqh>

//--- INPUTS DEL USUARIO
input group "--- Configuración de EMAs ---"
input int      InpEMA_Fast_Period = 30;   
input int      InpEMA_Mid_Period  = 50;   
input int      InpEMA_Slow_Period = 100;  

input group "--- Gestión de Riesgo (Stop Loss Real) ---"
input double   InpRiskPercent     = 1.0;  // Porcentaje de Riesgo por operación
input double   InpRiskRewardRatio = 2.0;  // Ratio Beneficio (ej. 1:2)
input int      InpSLBufferPips    = 10;   // Pips de margen sobre la EMA 50 para el SL

input group "--- Otros ---"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; 

//--- VARIABLES GLOBALES
CTrade         trade;
int            handleEMA30, handleEMA50, handleEMA100;
double         bufferEMA30[], bufferEMA50[], bufferEMA100[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   handleEMA30  = iMA(_Symbol, InpTimeframe, InpEMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA50  = iMA(_Symbol, InpTimeframe, InpEMA_Mid_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA100 = iMA(_Symbol, InpTimeframe, InpEMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleEMA30 == INVALID_HANDLE || handleEMA50 == INVALID_HANDLE || handleEMA100 == INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(bufferEMA30, true);
   ArraySetAsSeries(bufferEMA50, true);
   ArraySetAsSeries(bufferEMA100, true);
   
   trade.SetExpertMagicNumber(998877); // Magic Number único

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleEMA30);
   IndicatorRelease(handleEMA50);
   IndicatorRelease(handleEMA100);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(CopyBuffer(handleEMA30, 0, 0, 100, bufferEMA30) < 0) return;
   if(CopyBuffer(handleEMA50, 0, 0, 100, bufferEMA50) < 0) return;
   if(CopyBuffer(handleEMA100, 0, 0, 100, bufferEMA100) < 0) return;

   // Si ya hay una posición abierta, NO hacemos nada. Dejamos que toque TP o SL.
   if(PositionsTotal() > 0) return;

   CheckEntryLogic();
  }

//+------------------------------------------------------------------+
//| Lógica Principal de Entrada                                      |
//+------------------------------------------------------------------+
void CheckEntryLogic()
  {
   // 1. Definir Tendencia
   bool isUptrend = (bufferEMA30[1] > bufferEMA50[1] && bufferEMA50[1] > bufferEMA100[1]);
   bool isDowntrend = (bufferEMA30[1] < bufferEMA50[1] && bufferEMA50[1] < bufferEMA100[1]);

   if(!isUptrend && !isDowntrend) return;

   // 2. Escanear Toques Históricos
   int touches = 0;
   int lookbackBars = 100; 
   bool patternValid = true;
   bool currentlyTouching = false;

   for(int i = 1; i < lookbackBars; i++)
     {
      double high = iHigh(_Symbol, InpTimeframe, i);
      double low  = iLow(_Symbol, InpTimeframe, i);
      double ema30 = bufferEMA30[i];
      double ema50 = bufferEMA50[i];

      if(isUptrend) {
         // Si en algún momento el precio rompió la EMA 50, reiniciamos conteo/invalidamos
         if(low < ema50) { patternValid = false; break; }
         
         // Toque válido a la EMA 30
         if(low <= ema30 && high > ema30) {
            if(!currentlyTouching) { touches++; currentlyTouching = true; }
         } else currentlyTouching = false;
      }
      else if(isDowntrend) {
         if(high > ema50) { patternValid = false; break; }
         
         if(high >= ema30 && low < ema30) {
             if(!currentlyTouching) { touches++; currentlyTouching = true; }
         } else currentlyTouching = false;
      }
     }

   // 3. Ejecución al 4to toque (3 históricos + actual)
   if(patternValid && touches == 3)
     {
      double currentLow = iLow(_Symbol, InpTimeframe, 0);
      double currentHigh = iHigh(_Symbol, InpTimeframe, 0);
      
      // COMPRA
      if(isUptrend && currentLow <= bufferEMA30[0] && currentLow > bufferEMA50[0])
        {
         OpenTrade(ORDER_TYPE_BUY);
        }
      // VENTA
      else if(isDowntrend && currentHigh >= bufferEMA30[0] && currentHigh < bufferEMA50[0])
        {
         OpenTrade(ORDER_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Abrir Operación con SL REAL y Dinámico                           |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ema50Val = bufferEMA50[0];
   double bufferPoints = InpSLBufferPips * 10 * _Point; // Convertir pips a puntos (para divisas de 5 digitos)
   
   double sl = 0;
   double tp = 0;
   double slDistancePoints = 0;

   // --- CÁLCULO DE NIVELES ---
   if(type == ORDER_TYPE_BUY)
     {
      // SL = EMA50 - Buffer
      sl = ema50Val - bufferPoints;
      
      // Protección: Si el SL calculado está por encima del precio de entrada (imposible), abortar o ajustar.
      if(sl >= price) return; 

      slDistancePoints = price - sl;
      tp = price + (slDistancePoints * InpRiskRewardRatio);
     }
   else // SELL
     {
      // SL = EMA50 + Buffer
      sl = ema50Val + bufferPoints;
      
      if(sl <= price) return;

      slDistancePoints = sl - price;
      tp = price - (slDistancePoints * InpRiskRewardRatio);
     }

   // Protección de SL mínimo (evitar error por SL muy pegado)
   double minStopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDistancePoints < minStopLevel) return; // No operar si el SL está demasiado cerca

   // --- CÁLCULO DE LOTAJE ---
   double lotSize = CalculateLotSize(slDistancePoints);
   if(lotSize <= 0) return;

   // --- ENVIAR ORDEN ---
   trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, "EMA Strategy Hard SL");
  }

//+------------------------------------------------------------------+
//| Calcular Lotaje según Riesgo Monetario                           |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePoints)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0) return 0.01;

   // Fórmula universal para Forex/Indices en MT5
   // Lotes = Dinero_Riesgo / (Distancia_Puntos * Valor_del_Punto)
   
   // Convertir distancia en puntos a "pasos de tick" para mayor precisión
   double lossPerLot = (slDistancePoints / tickSize) * tickValue;
   
   if(lossPerLot == 0) return 0.01;
   
   double lotSize = riskMoney / lossPerLot;
   
   // Normalizar al paso del broker
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = 0; // Si el riesgo es tan bajo que no llega al lote mínimo, no operar
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
  }
//+------------------------------------------------------------------+