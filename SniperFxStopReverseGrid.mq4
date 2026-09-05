#property strict
#property version   "1.00"
#property description "Fixed-lot stop-and-reverse basket grid EA."

input int    MagicNumber                 = 5052026;
input double Lots                        = 0.01;
input int    InitialDirection            = 1;     // 1 = buy, -1 = sell
input int    GridStepPoints              = 100;   // Broker points, not displayed price units
input int    MaxBasketOrders             = 5;
input int    BasketLockPoints            = 50;    // Locks profit relative to weighted entry
input int    ReverseOffsetPoints         = 10;    // Distance between basket stop and reverse stop
input int    ReverseStopLossPoints       = 100;
input int    ReverseTakeProfitPoints     = 1200;
input int    MaxSpreadPoints             = 50;
input int    Slippage                    = 10;

int OnInit()
{
   if(Lots <= 0 || GridStepPoints <= 0 || MaxBasketOrders < 1 ||
      ReverseStopLossPoints <= 0 || ReverseTakeProfitPoints <= 0)
   {
      Print("Invalid EA inputs.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!CanTrade())
      return;

   int direction = BasketDirection();
   if(direction == 0)
   {
      DeleteManagedPendingOrders();
      OpenInitialOrder();
      return;
   }

   ManageBasket(direction);
}

bool CanTrade()
{
   RefreshRates();
   if(!IsTradeAllowed())
      return(false);
   if((Ask - Bid) / Point > MaxSpreadPoints)
      return(false);
   return(true);
}

int BasketDirection()
{
   int buys = 0;
   int sells = 0;

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsManagedOrder())
         continue;

      if(OrderType() == OP_BUY)
         buys++;
      else if(OrderType() == OP_SELL)
         sells++;
   }

   if(buys > 0 && sells == 0)
      return(1);
   if(sells > 0 && buys == 0)
      return(-1);

   if(buys > 0 && sells > 0)
      Print("Both buy and sell orders are open. EA will not manage a hedged basket.");
   return(0);
}

void OpenInitialOrder()
{
   int orderType = InitialDirection >= 0 ? OP_BUY : OP_SELL;
   double price = orderType == OP_BUY ? Ask : Bid;
   int ticket = OrderSend(Symbol(), orderType, NormalizedLots(), price, Slippage,
                          0, 0, "SniperFx initial", MagicNumber, 0, clrBlue);
   if(ticket < 0)
      Print("Initial order failed. Error=", GetLastError());
}

void ManageBasket(int direction)
{
   int count;
   double weightedEntry;
   double extremeEntry;
   GetBasketStats(direction, count, weightedEntry, extremeEntry);

   if(count < MaxBasketOrders && ShouldAddGridOrder(direction, extremeEntry))
      OpenGridOrder(direction);

   // Refresh statistics after a new grid order is filled.
   GetBasketStats(direction, count, weightedEntry, extremeEntry);

   double basketStop = BasketStop(direction, weightedEntry);
   ApplyBasketStop(direction, basketStop);
   EnsureReverseStop(direction, basketStop);
}

void GetBasketStats(int direction, int &count, double &weightedEntry, double &extremeEntry)
{
   count = 0;
   double lotsTotal = 0;
   weightedEntry = 0;
   extremeEntry = direction > 0 ? -DBL_MAX : DBL_MAX;

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsManagedOrder())
         continue;
      if((direction > 0 && OrderType() != OP_BUY) ||
         (direction < 0 && OrderType() != OP_SELL))
         continue;

      count++;
      lotsTotal += OrderLots();
      weightedEntry += OrderOpenPrice() * OrderLots();
      if(direction > 0)
         extremeEntry = MathMax(extremeEntry, OrderOpenPrice());
      else
         extremeEntry = MathMin(extremeEntry, OrderOpenPrice());
   }

   if(lotsTotal > 0)
      weightedEntry /= lotsTotal;
}

bool ShouldAddGridOrder(int direction, double extremeEntry)
{
   if(direction > 0)
      return(Bid >= extremeEntry + GridStepPoints * Point);
   return(Ask <= extremeEntry - GridStepPoints * Point);
}

void OpenGridOrder(int direction)
{
   int orderType = direction > 0 ? OP_BUY : OP_SELL;
   double price = orderType == OP_BUY ? Ask : Bid;
   int ticket = OrderSend(Symbol(), orderType, NormalizedLots(), price, Slippage,
                          0, 0, "SniperFx grid", MagicNumber, 0, clrBlue);
   if(ticket < 0)
      Print("Grid order failed. Error=", GetLastError());
}

double BasketStop(int direction, double weightedEntry)
{
   double candidate = direction > 0
                      ? weightedEntry + BasketLockPoints * Point
                      : weightedEntry - BasketLockPoints * Point;
   double minimumDistance = BrokerStopDistance();

   if(direction > 0)
   {
      if(candidate >= Bid - minimumDistance)
         return(0);
   }
   else if(candidate <= Ask + minimumDistance)
      return(0);

   return(NormalizeDouble(candidate, Digits));
}

void ApplyBasketStop(int direction, double basketStop)
{
   if(basketStop <= 0)
      return;

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsManagedOrder())
         continue;
      if((direction > 0 && OrderType() != OP_BUY) ||
         (direction < 0 && OrderType() != OP_SELL))
         continue;

      bool improvesStop = direction > 0
                          ? OrderStopLoss() == 0 || basketStop > OrderStopLoss()
                          : OrderStopLoss() == 0 || basketStop < OrderStopLoss();
      if(improvesStop && !OrderModify(OrderTicket(), OrderOpenPrice(), basketStop,
                                      0, 0, clrNONE))
         Print("Basket stop update failed for #", OrderTicket(), ". Error=", GetLastError());
   }
}

void EnsureReverseStop(int direction, double basketStop)
{
   if(basketStop <= 0)
      return;

   int wantedType = direction > 0 ? OP_SELLSTOP : OP_BUYSTOP;
   double entry = direction > 0
                  ? basketStop - ReverseOffsetPoints * Point
                  : basketStop + ReverseOffsetPoints * Point;
   double stopLoss = direction > 0
                     ? entry + ReverseStopLossPoints * Point
                     : entry - ReverseStopLossPoints * Point;
   double takeProfit = direction > 0
                       ? entry - ReverseTakeProfitPoints * Point
                       : entry + ReverseTakeProfitPoints * Point;

   entry = NormalizeDouble(entry, Digits);
   stopLoss = NormalizeDouble(stopLoss, Digits);
   takeProfit = NormalizeDouble(takeProfit, Digits);
   if(!IsValidPendingPrice(wantedType, entry))
      return;

   int ticket = FindPendingOrder(wantedType);
   if(ticket > 0)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return;
      if(MathAbs(OrderOpenPrice() - entry) < Point &&
         MathAbs(OrderStopLoss() - stopLoss) < Point &&
         MathAbs(OrderTakeProfit() - takeProfit) < Point)
         return;

      if(!OrderModify(ticket, entry, stopLoss, takeProfit, 0, clrRed))
         Print("Reverse stop update failed for #", ticket, ". Error=", GetLastError());
      return;
   }

   ticket = OrderSend(Symbol(), wantedType, NormalizedLots(), entry, Slippage, stopLoss,
                      takeProfit, "SniperFx reverse", MagicNumber, 0, clrRed);
   if(ticket < 0)
      Print("Reverse stop placement failed. Error=", GetLastError());
}

bool IsValidPendingPrice(int orderType, double price)
{
   double minimumDistance = BrokerStopDistance();
   if(orderType == OP_BUYSTOP)
      return(price >= Ask + minimumDistance);
   if(orderType == OP_SELLSTOP)
      return(price <= Bid - minimumDistance);
   return(false);
}

double BrokerStopDistance()
{
   return(MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL),
                  MarketInfo(Symbol(), MODE_FREEZELEVEL)) * Point);
}

double NormalizedLots()
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double lots = MathMax(minLot, MathMin(maxLot, Lots));
   return(NormalizeDouble(MathFloor(lots / lotStep) * lotStep, 2));
}

int FindPendingOrder(int orderType)
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderSelect(index, SELECT_BY_POS, MODE_TRADES) && IsManagedOrder() &&
         OrderType() == orderType)
         return(OrderTicket());
   }
   return(-1);
}

void DeleteManagedPendingOrders()
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(!OrderSelect(index, SELECT_BY_POS, MODE_TRADES) || !IsManagedOrder())
         continue;
      if(OrderType() != OP_BUYSTOP && OrderType() != OP_SELLSTOP)
         continue;
      if(!OrderDelete(OrderTicket()))
         Print("Pending order deletion failed for #", OrderTicket(), ". Error=", GetLastError());
   }
}

bool IsManagedOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}
