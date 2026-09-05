# Broker-Aware XAUUSD Expert Advisors

This repository contains equivalent MetaTrader 4 and MetaTrader 5 Expert Advisors:

- `MQL4/BrokerAwareXAUUSDEA.mq4`
- `MQL5/BrokerAwareXAUUSDEA.mq5`
- `MQL5/BrokerAwareBTCUSDEA.mq5`

The XAUUSD and BTCUSD advisors trade a trend-continuation setup: the fast EMA must be above/below the slow EMA and RSI must confirm the direction. The setup is evaluated on completed signal bars and can open immediately after attachment when the current confirmed trend meets all risk gates. They deliberately do not use hard-coded broker symbol names. Set `InpSymbol` to the exact Market Watch name (for example, `XAUUSDm`, `GOLD`, or `BTCUSD.a`) when the chart symbol is not right.

## Safeguards

- Entry orders use the executable side of the quote: **Ask** for buys and **Bid** for sells.
- The BTCUSD current spread must be at or below `InpMaxSpreadPrice` before entering; its default is **$4.00**. The XAUUSD advisors use `InpMaxSpreadPoints`, whose default is **40 broker points** and is normalized from the symbol's reported point size.
- Stop-loss and take-profit are calculated from price distances and raised to the broker's stop-level requirement where necessary.
- Risk-based lot sizing uses the broker-reported tick size and tick value, then aligns the result to the broker's minimum, maximum, and volume step.
- One position per symbol/magic number, a maximum daily loss guard, trading-hour window, slippage/deviation limit, and optional trailing stop are enabled by default.
- The panel shows the symbol, profile, live bid/ask/spread, trend state, position state, and whether new entries are permitted.

## Installation

1. Open MetaEditor from the target terminal.
2. Copy the appropriate file into `MQL4\Experts` or `MQL5\Experts`.
3. Compile the file, attach it to the signal chart, and enable Algo Trading/AutoTrading.
4. Configure the exact symbol, position risk, spread limit, and stop/take-profit distances for that broker.
5. Run it on a **demo account** first and confirm that the panel reports `READY` only at spreads you consider acceptable.

`InpStopLossPrice`, `InpTakeProfitPrice`, `InpTrailStartPrice`, and `InpTrailDistancePrice` are price units, not pips. For example, an XAUUSD stop loss of `8.0` means $8.00 in gold price. The XAUUSD defaults apply when their inputs are left at zero.

The BTCUSD MT5 EA has its own defaults: a maximum spread of `4.0`, stop loss of `500.0`, take profit of `1000.0`, trailing-start distance of `400.0`, and trailing distance of `250.0`.

No trading strategy can guarantee profit. The broker's contract specifications, leverage, execution rules, swaps, and spread behavior remain decisive; validate every configuration in the intended terminal before using a live account.