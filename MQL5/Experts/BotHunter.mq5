#property strict
#property version   "1.00"
#property description "BOT-HUNTER MQL5 starter Expert Advisor."

input int HeartbeatSeconds = 60;

datetime lastHeartbeat = 0;

int OnInit()
{
   Print("BOT-HUNTER MQL5 initialized on ", _Symbol, " / ", EnumToString(_Period));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("BOT-HUNTER MQL5 stopped. Reason: ", reason);
}

void OnTick()
{
   if(TimeCurrent() - lastHeartbeat < HeartbeatSeconds)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Unable to retrieve the latest tick. Error: ", GetLastError());
      return;
   }

   lastHeartbeat = TimeCurrent();
   Print("BOT-HUNTER MQL5 heartbeat. Bid: ", tick.bid, ", Ask: ", tick.ask);
}
