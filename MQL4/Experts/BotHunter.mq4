#property strict
#property version   "1.00"
#property description "BOT-HUNTER MQL4 starter Expert Advisor."

input int HeartbeatSeconds = 60;

datetime lastHeartbeat = 0;

int OnInit()
{
   Print("BOT-HUNTER MQL4 initialized on ", Symbol(), " / ", Period());
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("BOT-HUNTER MQL4 stopped. Reason: ", reason);
}

void OnTick()
{
   if(TimeCurrent() - lastHeartbeat < HeartbeatSeconds)
      return;

   lastHeartbeat = TimeCurrent();
   Print("BOT-HUNTER MQL4 heartbeat. Bid: ", Bid, ", Ask: ", Ask);
}
