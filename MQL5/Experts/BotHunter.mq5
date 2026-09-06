#property strict
#property version   "1.00"
#property description "BOT-HUNTER MQL5 starter Expert Advisor."

input int HeartbeatSeconds = 60;
input string StreamUser = "@fxboslink";

datetime lastHeartbeat = 0;
bool wasConnected = false;

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
   bool isConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!isConnected)
   {
      if(wasConnected)
         Print("BOT-HUNTER MQL5 heartbeat paused: terminal is disconnected.");

      wasConnected = false;
      return;
   }

   if(!wasConnected)
   {
      Print("BOT-HUNTER MQL5 heartbeat resumed: terminal is connected.");
      lastHeartbeat = 0;
   }

   wasConnected = true;

   if(TimeCurrent() - lastHeartbeat < HeartbeatSeconds)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Unable to retrieve the latest tick. Error: ", GetLastError());
      return;
   }

   lastHeartbeat = TimeCurrent();
   Print("BOT-HUNTER MQL5 stream for ", StreamUser, ". Bid: ", tick.bid, ", Ask: ", tick.ask);
}

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(transaction.type != TRADE_TRANSACTION_DEAL_ADD ||
      !HistoryDealSelect(transaction.deal))
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal, DEAL_ENTRY);
   if((entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) ||
      HistoryDealGetString(transaction.deal, DEAL_SYMBOL) != _Symbol)
      return;

   double netProfit = HistoryDealGetDouble(transaction.deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(transaction.deal, DEAL_SWAP) +
                      HistoryDealGetDouble(transaction.deal, DEAL_COMMISSION);
   Print("BOT-HUNTER MQL5 trade result for ", StreamUser,
         ". Deal: ", transaction.deal,
         ", Net profit: ", DoubleToString(netProfit, 2),
         ", Close price: ", DoubleToString(HistoryDealGetDouble(transaction.deal, DEAL_PRICE), _Digits));
}
