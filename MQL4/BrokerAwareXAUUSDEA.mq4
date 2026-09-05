#property strict
#property version   "1.00"
#property description "Broker-aware XAUUSD EMA and RSI Expert Advisor"

input string InpSymbol="";
input ENUM_TIMEFRAMES InpSignalTimeframe=PERIOD_M15;
input int InpMagicNumber=26090501;
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
input int InpSlippagePoints=30;
input bool InpEnableTrailingStop=true;
input bool InpShowPanel=true;
input int InpChartZoom=2;

string g_symbol;
datetime g_lastBar=0;
double g_dayStartEquity=0.0;
int g_dayKey=0;

string PanelName(const string suffix) { return("BAEA4_"+IntegerToString(InpMagicNumber)+"_"+suffix); }
int CurrentDayKey()
  {
   datetime now=TimeCurrent();
   return(TimeYear(now)*10000+TimeMonth(now)*100+TimeDay(now));
  }
string DayEquityKey() { return("BAEA4_DAY_EQUITY_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(AccountNumber())); }
void RefreshDayGuard()
  {
   int day=CurrentDayKey();
   if(day!=g_dayKey)
     {
      g_dayKey=day;
      g_dayStartEquity=AccountEquity();
      GlobalVariableSet(DayEquityKey(),g_dayStartEquity);
     }
  }
bool DailyLossLimitReached()
  {
   RefreshDayGuard();
   return(InpMaxDailyLossPercent>0.0 && g_dayStartEquity>0.0 &&
          AccountEquity()<=g_dayStartEquity*(1.0-InpMaxDailyLossPercent/100.0));
  }
double MaxSpreadPrice() { return(InpMaxSpreadPrice>0.0 ? InpMaxSpreadPrice : 0.80); }
double StopLossPrice() { return(InpStopLossPrice>0.0 ? InpStopLossPrice : 8.0); }
double TakeProfitPrice() { return(InpTakeProfitPrice>0.0 ? InpTakeProfitPrice : 16.0); }
double TrailStartPrice() { return(InpTrailStartPrice>0.0 ? InpTrailStartPrice : 6.0); }
double TrailDistancePrice() { return(InpTrailDistancePrice>0.0 ? InpTrailDistancePrice : 3.0); }
double PointSize() { return(MarketInfo(g_symbol,MODE_POINT)); }
int SymbolDigits() { return((int)MarketInfo(g_symbol,MODE_DIGITS)); }
double NormalizePrice(const double value) { return(NormalizeDouble(value,SymbolDigits())); }
double MinimumStopDistance() { return(MarketInfo(g_symbol,MODE_STOPLEVEL)*PointSize()); }
bool IsTradingHour()
  {
   int hour=TimeHour(TimeCurrent());
   if(InpTradeStartHour<=InpTradeEndHour)
      return(hour>=InpTradeStartHour && hour<=InpTradeEndHour);
   return(hour>=InpTradeStartHour || hour<=InpTradeEndHour);
  }
bool HasOurPosition()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==g_symbol &&
         OrderMagicNumber()==InpMagicNumber && (OrderType()==OP_BUY || OrderType()==OP_SELL))
         return(true);
   return(false);
  }
double CalculateLots(const double stopDistance)
  {
   double tickSize=MarketInfo(g_symbol,MODE_TICKSIZE), tickValue=MarketInfo(g_symbol,MODE_TICKVALUE);
   double minimum=MarketInfo(g_symbol,MODE_MINLOT), maximum=MarketInfo(g_symbol,MODE_MAXLOT);
   double step=MarketInfo(g_symbol,MODE_LOTSTEP);
   if(tickSize<=0.0 || tickValue<=0.0 || stopDistance<=0.0 || step<=0.0)
     {
      Print("Invalid broker contract specification for ",g_symbol);
      return(0.0);
     }
   double lots=MathFloor((AccountEquity()*InpRiskPercent/100.0/((stopDistance/tickSize)*tickValue))/step)*step;
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
   if(iBars(g_symbol,InpSignalTimeframe)<InpSlowEMA+5) return(0);
   double fastOne=iMA(g_symbol,InpSignalTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double fastTwo=iMA(g_symbol,InpSignalTimeframe,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double slowOne=iMA(g_symbol,InpSignalTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double slowTwo=iMA(g_symbol,InpSignalTimeframe,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double rsi=iRSI(g_symbol,InpSignalTimeframe,InpRSIPeriod,PRICE_CLOSE,1);
   if(fastOne>slowOne && fastTwo<=slowTwo && rsi>=InpRSIBuyMinimum) return(1);
   if(fastOne<slowOne && fastTwo>=slowTwo && rsi<=InpRSISellMaximum) return(-1);
   return(0);
  }
bool CanOpen(const double spread)
  {
   return(IsTradingHour() && !DailyLossLimitReached() && !HasOurPosition() &&
          spread<=MaxSpreadPrice() && IsTradeAllowed());
  }
void OpenTrade(const int direction)
  {
   double bid=MarketInfo(g_symbol,MODE_BID), ask=MarketInfo(g_symbol,MODE_ASK);
   double minStop=MinimumStopDistance(), stopDistance=MathMax(StopLossPrice(),minStop);
   double takeDistance=MathMax(TakeProfitPrice(),minStop), lots=CalculateLots(stopDistance);
   if(lots<=0.0) return;
   int type=(direction>0 ? OP_BUY : OP_SELL);
   double price=(direction>0 ? ask : bid);
   color arrow=(direction>0 ? clrDodgerBlue : clrTomato);
   int ticket=OrderSend(g_symbol,type,lots,price,InpSlippagePoints,0,0,"BrokerAware",InpMagicNumber,0,arrow);
   if(ticket<0) { Print("OrderSend failed for ",g_symbol,": ",GetLastError()); return; }
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) { Print("Unable to select new ticket ",ticket,": ",GetLastError()); return; }
   double sl=(direction>0 ? OrderOpenPrice()-stopDistance : OrderOpenPrice()+stopDistance);
   double tp=(direction>0 ? OrderOpenPrice()+takeDistance : OrderOpenPrice()-takeDistance);
   if(!OrderModify(ticket,OrderOpenPrice(),NormalizePrice(sl),NormalizePrice(tp),0,arrow))
      Print("OrderModify protection failed for ticket ",ticket,": ",GetLastError());
  }
void ManageTrailingStop()
  {
   if(!InpEnableTrailingStop) return;
   double bid=MarketInfo(g_symbol,MODE_BID), ask=MarketInfo(g_symbol,MODE_ASK);
   double distance=MathMax(TrailDistancePrice(),MinimumStopDistance());
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderSymbol()!=g_symbol || OrderMagicNumber()!=InpMagicNumber) continue;
      if(OrderType()==OP_BUY && bid-OrderOpenPrice()>=TrailStartPrice())
        {
         double newSL=NormalizePrice(bid-distance);
         if((OrderStopLoss()==0.0 || newSL>OrderStopLoss()) && !OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrDodgerBlue))
            Print("Buy trailing-stop update failed: ",GetLastError());
        }
      if(OrderType()==OP_SELL && OrderOpenPrice()-ask>=TrailStartPrice())
        {
         double newSL=NormalizePrice(ask+distance);
         if((OrderStopLoss()==0.0 || newSL<OrderStopLoss()) && !OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrTomato))
            Print("Sell trailing-stop update failed: ",GetLastError());
        }
     }
  }
void SetPanelLine(const string id,const int row,const string text,const color textColor)
  {
   string name=PanelName(id);
   if(ObjectFind(0,name)<0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,18);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,18+row*19);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(row==0 ? 11 : 9));
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
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,330);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,128);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }
void UpdatePanel()
  {
   if(!InpShowPanel) return;
   SetPanelBackground();
   double bid=MarketInfo(g_symbol,MODE_BID), ask=MarketInfo(g_symbol,MODE_ASK), spread=ask-bid;
   bool ready=CanOpen(spread);
   int trend=SignalDirection();
   SetPanelLine("title",0," BROKER-AWARE XAUUSD EA ",clrWhite);
   SetPanelLine("quote",1,StringFormat("%s  Bid %.2f  Ask %.2f",g_symbol,bid,ask),clrGainsboro);
   SetPanelLine("spread",2,StringFormat("Spread %.2f / max %.2f",spread,MaxSpreadPrice()),spread<=MaxSpreadPrice() ? clrLimeGreen : clrTomato);
   SetPanelLine("trend",3,"Signal "+(trend>0 ? "BUY" : trend<0 ? "SELL" : "WAIT"),clrAqua);
   SetPanelLine("position",4,HasOurPosition() ? "Position OPEN" : "Position NONE",clrGainsboro);
   SetPanelLine("status",5,DailyLossLimitReached() ? "HALTED: DAILY LOSS LIMIT" : (ready ? "READY: NEW ENTRIES ENABLED" : "BLOCKED: CHECK CONDITIONS"),ready ? clrLimeGreen : clrTomato);
  }
int OnInit()
  {
   g_symbol=(StringLen(InpSymbol)>0 ? InpSymbol : Symbol());
   if(!SymbolSelect(g_symbol,true)) { Print("Cannot select symbol ",g_symbol); return(INIT_FAILED); }
   g_dayKey=CurrentDayKey();
   if(GlobalVariableCheck(DayEquityKey()))
      g_dayStartEquity=GlobalVariableGet(DayEquityKey());
   else
     {
      g_dayStartEquity=AccountEquity();
      GlobalVariableSet(DayEquityKey(),g_dayStartEquity);
     }
   ChartSetInteger(0,CHART_SCALE,InpChartZoom);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   string ids[6]={"title","quote","spread","trend","position","status"};
   for(int i=0;i<6;i++) ObjectDelete(0,PanelName(ids[i]));
   ObjectDelete(0,PanelName("background"));
  }
void OnTick()
  {
   RefreshDayGuard();
   ManageTrailingStop();
   double spread=MarketInfo(g_symbol,MODE_ASK)-MarketInfo(g_symbol,MODE_BID);
   if(IsNewSignalBar() && CanOpen(spread))
     {
      int direction=SignalDirection();
      if(direction!=0) OpenTrade(direction);
     }
   UpdatePanel();
  }
