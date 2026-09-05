#property strict
#property version   "1.00"
#property description "Broker-aware BTCUSD EMA and RSI Expert Advisor"

#include <Trade/Trade.mqh>

input string InpSymbol="";
input ENUM_TIMEFRAMES InpSignalTimeframe=PERIOD_M15;
input long InpMagicNumber=26090502;
input double InpRiskPercent=0.50;
input double InpMaxDailyLossPercent=3.00;
input double InpMaxSpreadPrice=0.0;
input double InpStopLossPrice=0.0;
input double InpTakeProfitPrice=0.0;
input double InpTrailStartPrice=0.0;
input double InpTrailDistancePrice=0.0;
input int InpFastEMA=21;
input int InpSlowEMA=55;
input int InpRSIPeriod=14;
input int InpRSIBuyMinimum=52;
input int InpRSISellMaximum=48;
input int InpTradeStartHour=0;
input int InpTradeEndHour=23;
input int InpDeviationPoints=30;
input bool InpEnableTrailingStop=true;
input bool InpShowPanel=true;
input int InpChartZoom=2;
input ENUM_BASE_CORNER InpPanelCorner=CORNER_RIGHT_UPPER;
input int InpPanelMargin=12;

CTrade g_trade;
string g_symbol;
datetime g_lastBar=0;
double g_dayStartEquity=0.0;
int g_dayKey=0;
int g_fastHandle=INVALID_HANDLE, g_slowHandle=INVALID_HANDLE, g_rsiHandle=INVALID_HANDLE;

string PanelName(const string suffix) { return("BAEA5BTC_"+IntegerToString((int)InpMagicNumber)+"_"+suffix); }
int CurrentDayKey()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   return(now.year*10000+now.mon*100+now.day);
  }
string DayEquityKey() { return("BAEA5_BTC_DAY_EQUITY_"+IntegerToString((int)InpMagicNumber)+"_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))); }
void RefreshDayGuard()
  {
   int day=CurrentDayKey();
   if(day!=g_dayKey)
     {
      g_dayKey=day;
      g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(DayEquityKey(),g_dayStartEquity);
     }
  }
bool DailyLossLimitReached()
  {
   RefreshDayGuard();
   return(InpMaxDailyLossPercent>0.0 && g_dayStartEquity>0.0 &&
          AccountInfoDouble(ACCOUNT_EQUITY)<=g_dayStartEquity*(1.0-InpMaxDailyLossPercent/100.0));
  }
double MaxSpreadPrice() { return(InpMaxSpreadPrice>0.0 ? InpMaxSpreadPrice : 4.0); }
double StopLossPrice() { return(InpStopLossPrice>0.0 ? InpStopLossPrice : 500.0); }
double TakeProfitPrice() { return(InpTakeProfitPrice>0.0 ? InpTakeProfitPrice : 1000.0); }
double TrailStartPrice() { return(InpTrailStartPrice>0.0 ? InpTrailStartPrice : 400.0); }
double TrailDistancePrice() { return(InpTrailDistancePrice>0.0 ? InpTrailDistancePrice : 250.0); }
int SymbolDigits() { return((int)SymbolInfoInteger(g_symbol,SYMBOL_DIGITS)); }
double NormalizePrice(const double value) { return(NormalizeDouble(value,SymbolDigits())); }
double MinimumStopDistance() { return((double)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(g_symbol,SYMBOL_POINT)); }
bool IsTradingHour()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(InpTradeStartHour<=InpTradeEndHour) return(now.hour>=InpTradeStartHour && now.hour<=InpTradeEndHour);
   return(now.hour>=InpTradeStartHour || now.hour<=InpTradeEndHour);
  }
bool HasOurPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL)==g_symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) return(true);
     }
   return(false);
  }
double CalculateLots(const double stopDistance)
  {
   double tickSize=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue<=0.0) tickValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   double minimum=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN), maximum=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(tickSize<=0.0 || tickValue<=0.0 || stopDistance<=0.0 || step<=0.0)
     {
      Print("Invalid broker contract specification for ",g_symbol);
      return(0.0);
     }
   double lots=MathFloor((AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0/((stopDistance/tickSize)*tickValue))/step)*step;
   lots=MathMin(maximum,lots);
   if(lots<minimum)
     {
      Print("Risk amount is below the broker minimum volume for ",g_symbol);
      return(0.0);
     }
   return(NormalizeDouble(lots,2));
  }
bool IsNewSignalBar()
  {
   datetime bar=iTime(g_symbol,InpSignalTimeframe,0);
   if(bar==0 || bar==g_lastBar) return(false);
   g_lastBar=bar;
   return(true);
  }
int SignalDirection()
  {
   if(Bars(g_symbol,InpSignalTimeframe)<InpSlowEMA+5) return(0);
   double fast[1],slow[1],rsi[1];
   if(CopyBuffer(g_fastHandle,0,1,1,fast)!=1 || CopyBuffer(g_slowHandle,0,1,1,slow)!=1 || CopyBuffer(g_rsiHandle,0,1,1,rsi)!=1) return(0);
   if(fast[0]>slow[0] && rsi[0]>=InpRSIBuyMinimum) return(1);
   if(fast[0]<slow[0] && rsi[0]<=InpRSISellMaximum) return(-1);
   return(0);
  }
bool CanOpen(const double spread)
  {
   return(IsTradingHour() && !DailyLossLimitReached() && !HasOurPosition() &&
          spread<=MaxSpreadPrice() && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED));
  }
void OpenTrade(const int direction)
  {
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol,tick)) { Print("No executable quote for ",g_symbol); return; }
   double minStop=MinimumStopDistance(), stopDistance=MathMax(StopLossPrice(),minStop);
   double takeDistance=MathMax(TakeProfitPrice(),minStop), lots=CalculateLots(stopDistance);
   if(lots<=0.0) return;
   double price=(direction>0 ? tick.ask : tick.bid);
   double sl=(direction>0 ? price-stopDistance : price+stopDistance);
   double tp=(direction>0 ? price+takeDistance : price-takeDistance);
   bool sent=(direction>0 ? g_trade.Buy(lots,g_symbol,price,NormalizePrice(sl),NormalizePrice(tp),"BrokerAware BTC") :
                              g_trade.Sell(lots,g_symbol,price,NormalizePrice(sl),NormalizePrice(tp),"BrokerAware BTC"));
   if(!sent) Print("Entry failed for ",g_symbol,": ",g_trade.ResultRetcode()," ",g_trade.ResultRetcodeDescription());
  }
void ManageTrailingStop()
  {
   if(!InpEnableTrailingStop) return;
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol,tick)) return;
   double distance=MathMax(TrailDistancePrice(),MinimumStopDistance());
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=g_symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN), currentSL=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP), newSL=0.0;
      if(type==POSITION_TYPE_BUY && tick.bid-openPrice>=TrailStartPrice()) newSL=NormalizePrice(tick.bid-distance);
      if(type==POSITION_TYPE_SELL && openPrice-tick.ask>=TrailStartPrice()) newSL=NormalizePrice(tick.ask+distance);
      if(newSL>0.0 && ((type==POSITION_TYPE_BUY && (currentSL==0.0 || newSL>currentSL)) ||
                       (type==POSITION_TYPE_SELL && (currentSL==0.0 || newSL<currentSL))) &&
         !g_trade.PositionModify(g_symbol,newSL,tp))
         Print("Trailing-stop update failed: ",g_trade.ResultRetcode()," ",g_trade.ResultRetcodeDescription());
     }
  }
void SetPanelLine(const string id,const int row,const string text,const color textColor)
  {
   string name=PanelName(id);
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpPanelMargin+18);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpPanelMargin+18+row*20);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(row==0 ? 13 : 10));
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
     }
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,textColor);
  }
void SetPanelBackground()
  {
   string name=PanelName("background");
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpPanelMargin);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpPanelMargin);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,450);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,244);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }
void UpdatePanel()
  {
   if(!InpShowPanel) return;
   SetPanelBackground();
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol,tick)) return;
   double spread=tick.ask-tick.bid;
   int trend=SignalDirection();
   bool spreadAllowed=(spread<=MaxSpreadPrice());
   bool tradingEnabled=TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   string entryState=!tradingEnabled ? "AUTO TRADING: OFF" :
                     DailyLossLimitReached() ? "HALTED: DAILY LOSS LIMIT" :
                     !spreadAllowed ? "ENTRY BLOCKED: SPREAD" :
                     HasOurPosition() ? "POSITION MANAGED" :
                     trend>0 ? "BUY READY" : trend<0 ? "SELL READY" : "WAITING FOR TREND";
   color entryColor=(trend==0 || !spreadAllowed || DailyLossLimitReached() || !tradingEnabled ? clrTomato : clrLimeGreen);
   SetPanelLine("title",0," BTCUSD | BROKER-AWARE EA ",clrWhite);
   SetPanelLine("market",1,StringFormat("MARKET  %s   %s",g_symbol,EnumToString(InpSignalTimeframe)),clrSilver);
   SetPanelLine("quote",2,StringFormat("BID  %.2f     ASK  %.2f",tick.bid,tick.ask),clrGainsboro);
   SetPanelLine("spread",3,StringFormat("SPREAD  $%.2f / $%.2f",spread,MaxSpreadPrice()),spreadAllowed ? clrLimeGreen : clrTomato);
   SetPanelLine("trend",4,"TREND SIGNAL  "+(trend>0 ? "BUY" : trend<0 ? "SELL" : "NEUTRAL"),clrAqua);
   SetPanelLine("risk",5,StringFormat("RISK  %.2f%%    STOP  %.2f    TARGET  %.2f",InpRiskPercent,StopLossPrice(),TakeProfitPrice()),clrGainsboro);
   SetPanelLine("guard",6,StringFormat("DAILY GUARD  %.2f%%",InpMaxDailyLossPercent),clrGainsboro);
   SetPanelLine("position",7,HasOurPosition() ? "POSITION  OPEN - TRAILING MANAGED" : "POSITION  NONE",clrGainsboro);
   SetPanelLine("execution",8,"EXECUTION  BUY AT ASK | SELL AT BID",clrSilver);
   SetPanelLine("status",9,entryState,entryColor);
  }
int OnInit()
  {
   g_symbol=(StringLen(InpSymbol)>0 ? InpSymbol : _Symbol);
   if(!SymbolSelect(g_symbol,true)) { Print("Cannot select symbol ",g_symbol); return(INIT_FAILED); }
   g_fastHandle=iMA(g_symbol,InpSignalTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(g_symbol,InpSignalTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle=iRSI(g_symbol,InpSignalTimeframe,InpRSIPeriod,PRICE_CLOSE);
   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE || g_rsiHandle==INVALID_HANDLE) return(INIT_FAILED);
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_dayKey=CurrentDayKey();
   if(GlobalVariableCheck(DayEquityKey()))
      g_dayStartEquity=GlobalVariableGet(DayEquityKey());
   else
     {
      g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(DayEquityKey(),g_dayStartEquity);
     }
   ChartSetInteger(0,CHART_SCALE,InpChartZoom);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_rsiHandle!=INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   string ids[10]={"title","market","quote","spread","trend","risk","guard","position","execution","status"};
   for(int i=0;i<10;i++) ObjectDelete(0,PanelName(ids[i]));
   ObjectDelete(0,PanelName("background"));
  }
void OnTick()
  {
   RefreshDayGuard();
   ManageTrailingStop();
   MqlTick tick;
   if(SymbolInfoTick(g_symbol,tick) && CanOpen(tick.ask-tick.bid))
     {
      int direction=SignalDirection();
      if(direction!=0) OpenTrade(direction);
     }
   UpdatePanel();
  }
