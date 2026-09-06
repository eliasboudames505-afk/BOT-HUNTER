#property strict
#property version   "1.00"
#property description "BOT-HUNTER MQL4 starter Expert Advisor."

input int HeartbeatSeconds = 60;
input string StreamUser = "@fxboslink";

datetime lastHeartbeat = 0;
datetime lastReportedCloseTime = 0;
int lastReportedTicket = 0;
bool wasConnected = false;

int OnInit()
{
   lastReportedCloseTime = TimeCurrent();
   Print("BOT-HUNTER MQL4 initialized on ", Symbol(), " / ", Period());
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("BOT-HUNTER MQL4 stopped. Reason: ", reason);
}

void OnTick()
{
   bool isConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!isConnected)
   {
      if(wasConnected)
         Print("BOT-HUNTER MQL4 heartbeat paused: terminal is disconnected.");

      wasConnected = false;
      return;
   }

   if(!wasConnected)
   {
      Print("BOT-HUNTER MQL4 heartbeat resumed: terminal is connected.");
      lastHeartbeat = 0;
   }

   wasConnected = true;
   ReportClosedTrades();

   if(TimeCurrent() - lastHeartbeat < HeartbeatSeconds)
      return;

   lastHeartbeat = TimeCurrent();
   Print("BOT-HUNTER MQL4 stream for ", StreamUser, ". Bid: ", Bid, ", Ask: ", Ask);
}

void ReportClosedTrades()
{
   for(int index = OrdersHistoryTotal() - 1; index >= 0; index--)
   {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderType() > OP_SELL)
         continue;

      datetime closeTime = OrderCloseTime();
      int ticket = OrderTicket();
      if(closeTime < lastReportedCloseTime ||
         (closeTime == lastReportedCloseTime && ticket <= lastReportedTicket))
         continue;

      double netProfit = OrderProfit() + OrderSwap() + OrderCommission();
      Print("BOT-HUNTER MQL4 trade result for ", StreamUser,
            ". Ticket: ", ticket,
            ", Net profit: ", DoubleToString(netProfit, 2),
            ", Close price: ", DoubleToString(OrderClosePrice(), Digits));

      lastReportedCloseTime = closeTime;
      lastReportedTicket = ticket;
   }
}
