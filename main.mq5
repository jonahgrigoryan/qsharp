//+------------------------------------------------------------------+
//|                                       MT5-IntradaySwingEA.mq5 |
//|                              FundingPips Evaluation Strategy |
//|                                                              |
//+------------------------------------------------------------------+
#property copyright "MT5 Intraday Swing EA"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input double RiskPercent = 0.5;        // Risk per trade (%) - KEEP
input int    RSI_Period = 14;          // RSI Period - KEEP
input int    EMA_Fast = 50;            // Fast EMA Period - KEEP
input int    EMA_Slow = 200;           // Slow EMA Period - KEEP
input double SL_ATR_Multiplier = 1.5;  // Stop Loss ATR Multiplier - KEEP
input double TP_ATR_Multiplier = 3.5;  // Take Profit ATR Multiplier - KEEP (Good R:R)
input bool   UseEngulfingFilter = true; // Use Engulfing Pattern Filter - RESTORE TO TRUE (CRITICAL FOR LONGS & SHORTS)
input double MaxDailyDrawdown = 3.0;   // Maximum Daily Drawdown (%) - KEEP (Proven effective)
input int    MaxConcurrentTrades = 1;  // Maximum concurrent trades - KEEP
input bool   AllowNeutralTrend = true; // Allow trades in neutral H1 trend - KEEP
input double MinATRPips = 7.5;         // Minimum ATR in pips - RESTORE TO 7.5 (from Golden Long settings)
input bool   UseH4TrendFilter = true;  // Use H4 trend for additional confirmation - KEEP
input int    MaxTradesPerDay = 3;      // Maximum trades per day - RESTORE TO 3 (from Golden Long settings)

//--- Global variables
int emaFastH1Handle;
int emaSlowH1Handle;
int emaFastH4Handle;
int emaSlowH4Handle;
int emaFastM15Handle;
int rsiM15Handle;
int atrM15Handle;

// Daily drawdown tracking
double dailyStartingBalance = 0.0;
int currentDay = -1;

// Daily trade tracking
int dailyTradeCount = 0;
int lastTradeDay = -1;

// Trade management objects
CTrade trade;
CPositionInfo positionInfo;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   emaFastH1Handle = iMA(_Symbol, PERIOD_H1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowH1Handle = iMA(_Symbol, PERIOD_H1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   emaFastH4Handle = iMA(_Symbol, PERIOD_H4, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowH4Handle = iMA(_Symbol, PERIOD_H4, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   emaFastM15Handle = iMA(_Symbol, PERIOD_M15, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   rsiM15Handle = iRSI(_Symbol, PERIOD_M15, RSI_Period, PRICE_CLOSE);
   atrM15Handle = iATR(_Symbol, PERIOD_M15, 14);

   // Check if indicators were created successfully
   if(emaFastH1Handle == INVALID_HANDLE || emaSlowH1Handle == INVALID_HANDLE ||
      emaFastH4Handle == INVALID_HANDLE || emaSlowH4Handle == INVALID_HANDLE ||
      emaFastM15Handle == INVALID_HANDLE || rsiM15Handle == INVALID_HANDLE ||
      atrM15Handle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }

   Print("MT5 Intraday Swing EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(emaFastH1Handle);
   IndicatorRelease(emaSlowH1Handle);
   IndicatorRelease(emaFastH4Handle);
   IndicatorRelease(emaSlowH4Handle);
   IndicatorRelease(emaFastM15Handle);
   IndicatorRelease(rsiM15Handle);
   IndicatorRelease(atrM15Handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Test MODULE 5 - Trading Session Filter
   bool withinHours = IsWithinTradingHours();
   static bool lastWithinHours = true;
   static datetime lastHourCheck = 0;

   // Print session status every hour or when status changes
   if(withinHours != lastWithinHours || TimeCurrent() - lastHourCheck >= 3600)
   {
      MqlDateTime timeStruct;
      TimeToStruct(TimeCurrent(), timeStruct);
//      Print("Trading Session: ", withinHours ? "ACTIVE" : "CLOSED", 
//            " | Server Time: ", IntegerToString(timeStruct.hour, 2, '0'), ":", IntegerToString(timeStruct.min, 2, '0'));
      lastWithinHours = withinHours;
      lastHourCheck = TimeCurrent();
   }

   // Only proceed with signal detection during trading hours
   if(!withinHours)
   {
      return;  // Exit early if outside trading hours
   }

   // Test MODULE 6 - Daily Drawdown Guard
   bool drawdownHit = IsDailyDrawdownLimitHit();
   static bool lastDrawdownHit = false;

   if(drawdownHit != lastDrawdownHit)
   {
      if(drawdownHit)
      {
         Print("TRADING HALTED: Daily drawdown limit exceeded (", MaxDailyDrawdown, "%)");
      }
      else
      {
         Print("TRADING RESUMED: Daily drawdown back within limits");
      }
      lastDrawdownHit = drawdownHit;
   }

   // Block trading if daily drawdown limit is hit
   if(drawdownHit)
   {
      return;  // Exit early if drawdown limit exceeded
   }

   // Check daily trade limit
   MqlDateTime timeCurrent;
   TimeToStruct(TimeCurrent(), timeCurrent);
   int todayDay = timeCurrent.day;
   
   // Reset daily trade counter for new day
   if(todayDay != lastTradeDay)
   {
      dailyTradeCount = 0;
      lastTradeDay = todayDay;
   }
   
   // Block trading if daily trade limit reached
   if(dailyTradeCount >= MaxTradesPerDay)
   {
      static datetime lastTradeLimitPrint = 0;
      if(TimeCurrent() - lastTradeLimitPrint >= 3600) // Print once per hour
      {
         Print("🚫 TRADING LIMIT: Maximum trades per day reached (", dailyTradeCount, "/", MaxTradesPerDay, ") - Quality over quantity");
         lastTradeLimitPrint = TimeCurrent();
      }
      return;  // Exit early if trade limit reached
   }

   // Check ATR filter - avoid low volatility periods
   if(!IsVolatilityAcceptable())
   {
      return;  // Skip if market is too quiet
   }

   // Test MODULE 1 - H1 Trend Filter
   string trend = GetTrendDirection();
   string h4Trend = UseH4TrendFilter ? GetH4TrendDirection() : trend;
   static string lastTrend = "";

   // Only print when trend changes to avoid spam
   if(trend != lastTrend)
   {
      //Print("H1 Trend Direction: ", trend);
      lastTrend = trend;
   }

   // Test MODULE 2 - M15 Entry Signals
   static bool lastBuySignal = false;
   static bool lastSellSignal = false;

   bool buySignal  = IsEntrySignal(true);
   bool sellSignal = IsEntrySignal(false);

   if(buySignal && !lastBuySignal)
   {
      Print("BUY Entry Signal detected!");
      
      // Check if we already have open positions
      int currentPositions = CountOpenPositions();
      if(currentPositions >= MaxConcurrentTrades)
      {
         Print("BUY signal ignored - Maximum concurrent trades reached (", currentPositions, ")");
      }
      else
      {
         // Test MODULE 3 - ATR-Based SL/TP Calculation
         double sl, tp;
         double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         GetSLTP(entryPrice, true, sl, tp);
         Print("BUY - Entry: ", entryPrice, " | SL: ", sl, " | TP: ", tp, " | Risk:Reward = 1:", DoubleToString((tp-entryPrice)/(entryPrice-sl), 2));
         
         // Test MODULE 4 - Risk-Based Position Sizing
         double slPips = (entryPrice - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double lotSize = CalculateLotSize(slPips);
         Print("BUY - SL Distance: ", DoubleToString(slPips, 1), " pips | Lot Size: ", DoubleToString(lotSize, 2), " | Risk: 0.5% of account");
         
         // EXECUTE BUY TRADE - Balanced trend confirmation
         bool trendAligned = (trend == "bullish" || (AllowNeutralTrend && trend == "neutral"));
         bool h4Aligned = !UseH4TrendFilter || (h4Trend == "bullish" || (AllowNeutralTrend && h4Trend == "neutral"));
         
         if(trendAligned && h4Aligned)
         {
            trade.SetExpertMagicNumber(123456);
            trade.SetDeviationInPoints(10);
            
            if(trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, "IntradaySwing BUY"))
            {
               if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
               {
                  Print("✅ BUY order executed successfully! Ticket: ", trade.ResultOrder());
                  dailyTradeCount++; // Increment daily trade counter
                  Print("📊 Daily Trade Count: ", dailyTradeCount, "/", MaxTradesPerDay);
               }
               else
               {
                  Print("❌ BUY order failed! Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
            }
         }
         else
         {
            string reason = !trendAligned ? "H1 trend not aligned" : "H4 trend not aligned";
            Print("BUY signal ignored - ", reason, " (H1: ", trend, ", H4: ", h4Trend, ")");
         }
      }
   }
   if(sellSignal && !lastSellSignal)
   {
      Print("SELL Entry Signal detected!");
      
      // Check if we already have open positions
      int currentPositions = CountOpenPositions();
      if(currentPositions >= MaxConcurrentTrades)
      {
         Print("SELL signal ignored - Maximum concurrent trades reached (", currentPositions, ")");
      }
      else
      {
         // Test MODULE 3 - ATR-Based SL/TP Calculation
         double sl, tp;
         double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         GetSLTP(entryPrice, false, sl, tp);
         Print("SELL - Entry: ", entryPrice, " | SL: ", sl, " | TP: ", tp, " | Risk:Reward = 1:", DoubleToString((entryPrice-tp)/(sl-entryPrice), 2));
         
         // Test MODULE 4 - Risk-Based Position Sizing
         double slPips = (sl - entryPrice) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double lotSize = CalculateLotSize(slPips);
         Print("SELL - SL Distance: ", DoubleToString(slPips, 1), " pips | Lot Size: ", DoubleToString(lotSize, 2), " | Risk: 0.5% of account");
         
         // EXECUTE SELL TRADE - Balanced trend confirmation
         bool trendAligned = (trend == "bearish" || (AllowNeutralTrend && trend == "neutral"));
         bool h4Aligned = !UseH4TrendFilter || (h4Trend == "bearish" || (AllowNeutralTrend && h4Trend == "neutral"));
         
         if(trendAligned && h4Aligned)
         {
            trade.SetExpertMagicNumber(123456);
            trade.SetDeviationInPoints(10);
            
            if(trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, "IntradaySwing SELL"))
            {
               if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
               {
                  Print("✅ SELL order executed successfully! Ticket: ", trade.ResultOrder());
                  dailyTradeCount++; // Increment daily trade counter
                  Print("📊 Daily Trade Count: ", dailyTradeCount, "/", MaxTradesPerDay);
               }
               else
               {
                  Print("❌ SELL order failed! Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
            }
         }
         else
         {
            string reason = !trendAligned ? "H1 trend not aligned" : "H4 trend not aligned";
            Print("SELL signal ignored - ", reason, " (H1: ", trend, ", H4: ", h4Trend, ")");
         }
      }
   }

   lastBuySignal  = buySignal;
   lastSellSignal = sellSignal;

   //Module 8
   CloseOnFriday();

   // Test MODULE 7 - Trailing Stop Management
   ManageTrailingStop();
}


//+------------------------------------------------------------------+
//| MODULE 1 - H1 Trend Filter                                      |
//| Returns: "bullish", "bearish", or "neutral"                     |
//+------------------------------------------------------------------+
string GetTrendDirection()
{
   double emaFast[1];
   double emaSlow[1];
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get EMA values from H1 timeframe
   if(CopyBuffer(emaFastH1Handle, 0, 0, 1, emaFast) != 1 ||
      CopyBuffer(emaSlowH1Handle, 0, 0, 1, emaSlow) != 1)
   {
      Print("Error getting EMA values");
      return "neutral";
   }

   // Check trend conditions
   if(currentPrice > emaFast[0] && currentPrice > emaSlow[0])
   {
      return "bullish";
   }
   else if(currentPrice < emaFast[0] && currentPrice < emaSlow[0])
   {
      return "bearish";
   }
   else
   {
      return "neutral";
   }
}

//+------------------------------------------------------------------+
//| Get H4 Trend Direction for stronger bias                        |
//+------------------------------------------------------------------+
string GetH4TrendDirection()
{
   double emaFast[1];
   double emaSlow[1];
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get EMA values from H4 timeframe
   if(CopyBuffer(emaFastH4Handle, 0, 0, 1, emaFast) != 1 ||
      CopyBuffer(emaSlowH4Handle, 0, 0, 1, emaSlow) != 1)
   {
      return "neutral";
   }

   // Check trend conditions
   if(currentPrice > emaFast[0] && currentPrice > emaSlow[0])
   {
      return "bullish";
   }
   else if(currentPrice < emaFast[0] && currentPrice < emaSlow[0])
   {
      return "bearish";
   }
   else
   {
      return "neutral";
   }
}

//+------------------------------------------------------------------+
//| MODULE 2 - M15 Entry Signal (RESTORE & REFINE ASYMMETRIC)     |
//| ULTRA-TIGHT LONG conditions, LOOSENED SHORTS w/ MANDATORY ENGULF |
//+------------------------------------------------------------------+
bool IsEntrySignal(bool isBuy)
{
   double rsi[4];        // Need 4 bars for momentum confirmation
   double ema[4];        // Need 4 bars for trend analysis
   double high[4], low[4], open[4], close[4];  // OHLC for pattern check
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(CopyBuffer(rsiM15Handle, 0, 0, 4, rsi) != 4 ||
      CopyBuffer(emaFastM15Handle, 0, 0, 4, ema) != 4 ||
      CopyHigh(_Symbol, PERIOD_M15, 0, 4, high) != 4 ||
      CopyLow(_Symbol, PERIOD_M15, 0, 4, low) != 4 ||
      CopyOpen(_Symbol, PERIOD_M15, 0, 4, open) != 4 ||
      CopyClose(_Symbol, PERIOD_M15, 0, 4, close) != 4)
   {
      return false;
   }

   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double emaDistance = MathAbs(currentPrice - ema[0]) / point;
   
   if(isBuy) // --- BUY CONDITIONS (EXACT RESTORE OF 75% WIN RATE LOGIC) ---
   {
      bool rsiCond = false;
      // 1. Strong Oversold Bounce: RSI[2] deeply oversold, strong kick upwards
      if(rsi[2] <= 25.0 && rsi[1] <= 30.0 && rsi[0] > 38.0 && rsi[0] > rsi[1] + 4.5) { rsiCond = true; }
      // 2. RSI Upward Momentum (mid-range): Clear consecutive rises from mid-zone
      else if(rsi[0] > 45.0 && rsi[0] < 65.0 && rsi[0] > rsi[1] + 2.5 && rsi[1] > rsi[2] + 2.0) { rsiCond = true; }
      // 3. RSI Crossing 50 (Bullish): Strong cross above 50
      else if(rsi[0] > 53.0 && rsi[1] <= 50.0 && rsi[0] > rsi[1] + 3.5) { rsiCond = true; }
      // 4. Sustained Upward Momentum: Clear multi-bar bullish RSI trend
      else if(rsi[0] > 50.0 && rsi[0] < 70.0 && rsi[0] > rsi[1] + 2.0 && rsi[1] > rsi[2] + 1.0 && rsi[2] > rsi[3]) { rsiCond = true; }

      bool emaCond = false;
      // 1. Precise EMA Touch & Bounce: Price touches near EMA & bounces with bullish candle
      if(emaDistance <= 8.0 && currentPrice > ema[0] && low[1] <= ema[1] + (5.0 * point) && close[0] > open[0]) { emaCond = true; }
      // 2. Clear EMA Rejection & Momentum: Price rejects EMA and moves up with conviction
      else if(low[1] < ema[1] && close[1] > ema[1] && close[0] > ema[0] && close[0] > close[1] + point) { emaCond = true; }
      // 3. Price Above EMA & Strong Bullish Candle: Price holding above EMA with strong candle
      else if(emaDistance <= 15.0 && currentPrice > ema[0] && close[0] > close[1] && (close[0] - open[0]) > (high[0] - low[0]) * 0.5) { emaCond = true; }

      bool paCond = false;
      // 1. Very Strong Bullish Candle: Dominant bullish candle body
      if(close[0] > open[0] && (close[0] - open[0]) > (high[0] - low[0]) * 0.65) { paCond = true; }
      // 2. Convincing Hammer Pattern: Strong lower wick rejection, bullish close
      else if((close[0] - low[0]) > (high[0] - close[0]) * 2.2 && close[0] > open[0] && close[0] > (high[0]+low[0])/2) { paCond = true; }
      
      if(!(rsiCond && emaCond && paCond)) return false;
      // Engulfing filter is active due to global UseEngulfingFilter = true
      if(!IsBullishEngulfing(open, high, low, close)) return false;
      return true;
   }
   else // --- SELL CONDITIONS (RECENT LOOSENED LOGIC + MANDATORY ENGULFING) ---
   {
      bool rsiCond = false;
      // 1. Overbought Bounce (slightly more relaxed threshold from previous iteration)
      if(rsi[2] >= 70.0 && rsi[1] >= 65.0 && rsi[0] < 63.0 && rsi[0] < rsi[1] - 3.0) { rsiCond = true; }
      // 2. RSI Downward Momentum (mid-range, slightly more relaxed momentum from previous iteration)
      else if(rsi[0] < 60.0 && rsi[0] > 35.0 && rsi[0] < rsi[1] - 1.5 && rsi[1] < rsi[2] - 1.0) { rsiCond = true; }
      // 3. RSI Crossing 50 (Bearish, slightly more relaxed threshold from previous iteration)
      else if(rsi[0] < 47.0 && rsi[1] >= 50.0 && rsi[0] < rsi[1] - 2.5) { rsiCond = true; }
      // 4. Sustained Downward Momentum (broader range, slightly relaxed momentum from previous iteration)
      else if(rsi[0] < 58.0 && rsi[0] > 30.0 && rsi[0] < rsi[1] - 1.0 && rsi[1] < rsi[2] && rsi[2] < rsi[3]) { rsiCond = true; }

      bool emaCond = false;
      // 1. EMA Touch & Bounce (more tolerant distance from previous iteration)
      if(emaDistance <= 12.0 && currentPrice < ema[0] && high[1] >= ema[1] - (10.0 * point) && close[0] < open[0]) { emaCond = true; }
      // 2. Clear EMA Rejection & Momentum (momentum check slightly less strict from previous iteration)
      else if(high[1] > ema[1] && close[1] < ema[1] && close[0] < ema[0] && close[0] < close[1]) { emaCond = true; }
      // 3. Price Below EMA & Bearish Candle (candle check slightly more tolerant distance & body from previous iteration)
      else if(emaDistance <= 20.0 && currentPrice < ema[0] && close[0] < close[1] && (open[0] - close[0]) > (high[0] - low[0]) * 0.35) { emaCond = true; }

      bool paCond = false;
      // 1. Decent Bearish Candle (body >55% from previous iteration)
      if(close[0] < open[0] && (open[0] - close[0]) > (high[0] - low[0]) * 0.55) { paCond = true; }
      // 2. Shooting Star Pattern (more inclusive from previous iteration)
      else if((high[0] - close[0]) > (close[0] - low[0]) * 1.8 && close[0] < open[0] && close[0] < (high[0]+low[0])/2) { paCond = true; }

      if(!(rsiCond && emaCond && paCond)) return false;
      // Engulfing filter is active due to global UseEngulfingFilter = true, making it mandatory here
      if(!IsBearishEngulfing(open, high, low, close)) return false;
      return true;
   }
}

//+------------------------------------------------------------------+
//| Helper: Check for Bullish Engulfing Pattern                     |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(double &open[], double &high[], double &low[], double &close[])
{
   // Previous candle: bearish (red)
   bool prevBearish = close[1] < open[1];

   // Current candle: bullish (green) and engulfs previous
   bool currBullish = close[0] > open[0];
   bool engulfs = (open[0] < close[1]) && (close[0] > open[1]);

   return prevBearish && currBullish && engulfs;
}

//+------------------------------------------------------------------+
//| Helper: Check for Bearish Engulfing Pattern                     |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(double &open[], double &high[], double &low[], double &close[])
{
   // Previous candle: bullish (green)
   bool prevBullish = close[1] > open[1];

   // Current candle: bearish (red) and engulfs previous
   bool currBearish = close[0] < open[0];
   bool engulfs = (open[0] > close[1]) && (close[0] < open[1]);

   return prevBullish && currBearish && engulfs;
}

//+------------------------------------------------------------------+
//| MODULE 3 - ATR-Based SL/TP Calculation with Logs                |
//| Uses ATR(14) on M15: SL = 1.5x ATR, TP = 3.5x ATR               |
//+------------------------------------------------------------------+
void GetSLTP(double entryPrice, bool isBuy, double &sl, double &tp)
{
   double atr[1];

   // Get current ATR(14) value from M15 timeframe
   if(CopyBuffer(atrM15Handle, 0, 0, 1, atr) != 1)
   {
      Print("❌ [SLTP] Failed to retrieve ATR buffer");
      sl = 0;
      tp = 0;
      return;
   }

   double atrValue = atr[0];
   double slDistance = atrValue * SL_ATR_Multiplier;
   double tpDistance = atrValue * TP_ATR_Multiplier;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Debug: Raw ATR and distances
   PrintFormat("📦 [SLTP] ATR: %.5f | SL_Dist: %.5f | TP_Dist: %.5f", atrValue, slDistance, tpDistance);

   // Calculate initial SL/TP
   if(isBuy)
   {
      sl = NormalizeDouble(entryPrice - slDistance, digits);
      tp = NormalizeDouble(entryPrice + tpDistance, digits);
   }
   else
   {
      sl = NormalizeDouble(entryPrice + slDistance, digits);
      tp = NormalizeDouble(entryPrice - tpDistance, digits);
   }

   // Debug: Before min distance adjustment
   PrintFormat("📍 [SLTP] Raw SL: %.5f | Raw TP: %.5f | Entry: %.5f", sl, tp, entryPrice);

   // Enforce broker minimum distance
   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   bool slAdjusted = false;
   bool tpAdjusted = false;

   if(isBuy)
   {
      if(entryPrice - sl < minStopLevel)
      {
         sl = NormalizeDouble(entryPrice - minStopLevel, digits);
         slAdjusted = true;
      }
      if(tp - entryPrice < minStopLevel)
      {
         tp = NormalizeDouble(entryPrice + minStopLevel, digits);
         tpAdjusted = true;
      }
   }
   else
   {
      if(sl - entryPrice < minStopLevel)
      {
         sl = NormalizeDouble(entryPrice + minStopLevel, digits);
         slAdjusted = true;
      }
      if(entryPrice - tp < minStopLevel)
      {
         tp = NormalizeDouble(entryPrice - minStopLevel, digits);
         tpAdjusted = true;
      }
   }

   // Debug: Final values after adjustment
   PrintFormat("✅ [SLTP] Final SL: %.5f (%s) | TP: %.5f (%s) | MinStop: %.5f",
               sl, slAdjusted ? "adjusted" : "ok",
               tp, tpAdjusted ? "adjusted" : "ok",
               minStopLevel);
}

//+------------------------------------------------------------------+
//| MODULE 4 - Risk-Based Position Sizing (IMPROVED)                |
//| Calculate lot size with better margin management                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   // Account information
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Symbol information
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Enhanced margin calculation
   double marginRate = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Determine pip value
   double pipValue;
   if(contractSize == 100000.0)  // Standard Forex pair
   {
      pipValue = (tickSize / point) * tickValue;
   }
   else
   {
      pipValue = tickValue * (tickSize / point);
   }
   
   // Calculate monetary risk per pip
   double riskPerPip = slPips * pipValue;
   
   // Avoid division by zero or negative pip value
   if(riskPerPip <= 0)
   {
      Print("❌ [LOT] Invalid pip calculation. Using minimum lot size.");
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   // Calculate lot size based on risk
   double riskBasedLotSize = riskAmount / riskPerPip;
   
   // Calculate maximum lot size based on available margin (use only 50% of free margin)
   double maxMarginLotSize = (freeMargin * 0.5) / (marginRate * currentPrice);
   
   // Use the smaller of the two
   double lotSize = MathMin(riskBasedLotSize, maxMarginLotSize);
   
   // Broker lot size constraints
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize to broker step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Ensure within min/max
   if(lotSize < minLot)
   {
      lotSize = minLot;
   }
   else if(lotSize > maxLot)
   {
      lotSize = maxLot;
   }
   
   // Final margin safety check
   double requiredMargin = lotSize * marginRate * currentPrice;
   if(requiredMargin > freeMargin * 0.8)  // Use max 80% of free margin
   {
      lotSize = (freeMargin * 0.8) / (marginRate * currentPrice);
      lotSize = MathFloor(lotSize / lotStep) * lotStep;
      
      if(lotSize < minLot)
      {
         Print("❌ [LOT] Insufficient margin for minimum lot size");
         return 0;  // Don't trade if can't meet minimum
      }
      
      Print("⚠️ [LOT] Lot size reduced due to margin constraints: ", lotSize);
   }
   
   // Debug output
   PrintFormat("💰 [LOT] Risk: $%.2f | RiskLot: %.2f | MarginLot: %.2f | Final: %.2f", 
               riskAmount, riskBasedLotSize, maxMarginLotSize, lotSize);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| MODULE 5 - Trading Session Filter                                |
//| Allow trading only between 6:00–17:00 server time                |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   int currentHour = timeStruct.hour;

   // Trading allowed between 06:00 and 17:00 (5:00 PM) server time
   // This covers major trading sessions: London and New York overlap
   if(currentHour >= 6 && currentHour < 17)
   {
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| MODULE 6 - Daily Drawdown Guard                                 |
//| Block trading if equity drawdown exceeds 4.5% of daily balance  |
//+------------------------------------------------------------------+
bool IsDailyDrawdownLimitHit()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int today = timeStruct.day;

   // Check if it's a new trading day
   if(today != currentDay)
   {
       // New day - reset daily starting balance
       dailyStartingBalance = AccountInfoDouble(ACCOUNT_EQUITY);
       currentDay = today;

//       Print("New Trading Day: Daily starting balance = $", DoubleToString(dailyStartingBalance, 2));
   }

   // Get current equity
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Calculate drawdown percentage
   double drawdownAmount = dailyStartingBalance - currentEquity;
   double drawdownPercent = (drawdownAmount / dailyStartingBalance) * 100.0;

   // Debug output (only print every 10 minutes to avoid spam)
   static datetime lastDrawdownPrint = 0;
   if(TimeCurrent() - lastDrawdownPrint >= 600) // 10 minutes
   {
//       Print("Daily Drawdown Status: Starting=$", DoubleToString(dailyStartingBalance, 2), 
//             " | Current=$", DoubleToString(currentEquity, 2), 
//             " | Drawdown=", DoubleToString(drawdownPercent, 2), "%");
       lastDrawdownPrint = TimeCurrent();
   }

   // Check if drawdown limit is exceeded
   if(drawdownPercent > MaxDailyDrawdown)
   {
       return true;  // Drawdown limit hit
   }

   return false;  // Within acceptable drawdown limits
}  

//+------------------------------------------------------------------+
//| MODULE 7 - Trailing Stop Logic                                  |
//| Move SL to breakeven at +1R, then trail by 0.5R increments     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Loop through all open positions for this symbol
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i))
         continue;

      // Only manage positions for current symbol
      if(positionInfo.Symbol() != _Symbol)
         continue;

      string positionSymbol = positionInfo.Symbol();
      ulong ticket = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();
      double entryPrice = positionInfo.PriceOpen();
      double currentSL = positionInfo.StopLoss();
      double currentTP = positionInfo.TakeProfit();
      double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(positionSymbol, SYMBOL_BID) : SymbolInfoDouble(positionSymbol, SYMBOL_ASK);

      // Calculate R (risk) value - distance from entry to original SL
      double riskDistance;
      if(posType == POSITION_TYPE_BUY)
      {
         riskDistance = entryPrice - currentSL;
      }
      else
      {
         riskDistance = currentSL - entryPrice;
      }

      // Skip if risk distance is invalid
      if(riskDistance <= 0)
         continue;

      // Calculate current profit in R multiples
      double currentProfitDistance;
      if(posType == POSITION_TYPE_BUY)
      {
         currentProfitDistance = currentPrice - entryPrice;
      }
      else
      {
         currentProfitDistance = entryPrice - currentPrice;
      }

      double currentRMultiple = currentProfitDistance / riskDistance;

      // Get symbol digits for price normalization
      int digits = (int)SymbolInfoInteger(positionSymbol, SYMBOL_DIGITS);
      double newSL = currentSL;
      bool shouldModify = false;

      if(currentRMultiple >= 1.0)  // At +1R or better
      {
         // Move SL to breakeven if not already there
         if(posType == POSITION_TYPE_BUY)
         {
            double breakEvenSL = NormalizeDouble(entryPrice, digits);
            if(currentSL < breakEvenSL)
            {
               newSL = breakEvenSL;
               shouldModify = true;
               Print("Moving BUY position #", ticket, " SL to breakeven at ", newSL);
            }
         }
         else  // SELL position
         {
            double breakEvenSL = NormalizeDouble(entryPrice, digits);
            if(currentSL > breakEvenSL)
            {
               newSL = breakEvenSL;
               shouldModify = true;
               Print("Moving SELL position #", ticket, " SL to breakeven at ", newSL);
            }
         }
      }

      if(currentRMultiple >= 1.5)  // At +1.5R or better - start trailing by 0.5R increments
      {
         double trailLevel = MathFloor(currentRMultiple / 0.5) * 0.5;  // Round down to nearest 0.5R
         double trailDistance = (trailLevel - 1.0) * riskDistance;     // Distance to trail from breakeven

         if(posType == POSITION_TYPE_BUY)
         {
            double trailSL = NormalizeDouble(entryPrice + trailDistance, digits);
            if(trailSL > currentSL)
            {
               newSL = trailSL;
               shouldModify = true;
               Print("Trailing BUY position #", ticket, " SL to ", newSL, " (", DoubleToString(trailLevel, 1), "R level)");
            }
         }
         else  // SELL position
         {
            double trailSL = NormalizeDouble(entryPrice - trailDistance, digits);
            if(trailSL < currentSL)
            {
               newSL = trailSL;
               shouldModify = true;
               Print("Trailing SELL position #", ticket, " SL to ", newSL, " (", DoubleToString(trailLevel, 1), "R level)");
            }
         }
      }

      // Execute the stop loss modification
      if(shouldModify)
      {
         if(!trade.PositionModify(ticket, newSL, currentTP))
         {
            Print("Error modifying position #", ticket, ": ", trade.ResultRetcodeDescription());
         }
         else
         {
            Print("Successfully modified position #", ticket, " - New SL: ", newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 8 - Friday Trade Exit                                    |
//| Close all trades at 15:00 server time on Friday                 |
//+------------------------------------------------------------------+
void CloseOnFriday()
{
   // Static variables declared at function level for proper scope
   static bool fridayCloseExecuted = false;
   static int lastFridayClose = -1;
   static bool flagReset = false;

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   // Check if it's Friday (day 5) and 15:00 (hour 15)
   if(timeStruct.day_of_week == 5 && timeStruct.hour == 15)
   {
      // Only execute once per Friday at 15:00 (prevent multiple executions in same hour)
      if(!fridayCloseExecuted || timeStruct.day != lastFridayClose)
      {
//         Print("=== FRIDAY 15:00 - EXECUTING WEEKEND CLOSE PROCEDURE ===");

         int totalPositions = 0;
         int closedPositions = 0;
         int failedCloses = 0;

         // Loop through all positions for this symbol
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!positionInfo.SelectByIndex(i))
               continue;

            // Only close positions for current symbol
            if(positionInfo.Symbol() != _Symbol)
               continue;

            totalPositions++;
            ulong ticket = positionInfo.Ticket();
            double volume = positionInfo.Volume();
            ENUM_POSITION_TYPE posType = positionInfo.PositionType();
            double entryPrice = positionInfo.PriceOpen();
            double currentPrice = positionInfo.PriceCurrent();
            double profit = positionInfo.Profit();

            string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";

            Print("Closing ", posTypeStr, " position #", ticket, 
                  " | Volume: ", volume, 
                  " | Entry: ", entryPrice, 
                  " | Current: ", currentPrice, 
                  " | P&L: $", DoubleToString(profit, 2));

            // Close the position
            if(trade.PositionClose(ticket))
            {
               closedPositions++;
               Print("Successfully closed position #", ticket);
            }
            else
            {
               failedCloses++;
               Print("ERROR: Failed to close position #", ticket, " - ", trade.ResultRetcodeDescription());
            }

            // Small delay to avoid overwhelming the server
            Sleep(100);
         }

         // Summary report
         if(totalPositions > 0)
         {
            Print("=== FRIDAY CLOSE SUMMARY ===");
            Print("Total positions found: ", totalPositions);
            Print("Successfully closed: ", closedPositions);
            Print("Failed to close: ", failedCloses);
            Print("Weekend hold protection: ACTIVE");
         }
         else
         {
//            Print("No open positions found - Weekend protection complete");
         }

         fridayCloseExecuted = true;
         lastFridayClose = timeStruct.day;

//         Print("=== WEEKEND CLOSE PROCEDURE COMPLETED ===");
      }
   }
   else
   {
      // Reset the flag when it's not Friday 15:00
      if(timeStruct.day_of_week != 5 || timeStruct.hour != 15)
      {
         if(!flagReset)
         {
            fridayCloseExecuted = false;
            flagReset = true;
         }
      }
      else
      {
         flagReset = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Count open positions for this symbol                     |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 123456)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if volatility is acceptable for trading                   |
//+------------------------------------------------------------------+
bool IsVolatilityAcceptable()
{
   double atr[1];
   
   if(CopyBuffer(atrM15Handle, 0, 0, 1, atr) != 1)
   {
      return false;
   }
   
   double atrPips = atr[0] / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Skip if ATR is too low (choppy market)
   if(atrPips < MinATRPips)
   {
      static datetime lastVolPrint = 0;
      if(TimeCurrent() - lastVolPrint >= 3600) // Print once per hour
      {
         PrintFormat("⚠️ [VOL] Low volatility detected. ATR: %.1f pips (min: %.1f)", atrPips, MinATRPips);
         lastVolPrint = TimeCurrent();
      }
      return false;
   }
   
   return true;
} 