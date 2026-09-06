# BOT-HUNTER

Starter MetaTrader Expert Advisors and GitHub reporting automation.

## Sources

- `MQL4/Experts/BotHunter.mq4` is the MQL4 starter Expert Advisor.
- `MQL5/Experts/BotHunter.mq5` is the MQL5 starter Expert Advisor.
- `.vscode/` recommends MQL Tools and associates MQ4/MQ5 source files with an editor mode.

The starter EAs only log a periodic heartbeat. They do not open, modify, or close trades.

## Live automation reports

`.github/workflows/mql-report.yml` runs on pushes, pull requests, manual dispatches,
and every six hours. It validates MQL source structure, writes a GitHub Actions
summary, and retains JSON and Markdown reports as workflow artifacts for 30 days.
Scheduled runs update one `automation` / `mql-report` GitHub issue with the current
result and run link.

To also send each completed report to Slack, Discord, or a compatible endpoint, add
the repository secret `REPORT_WEBHOOK_URL`. The workflow sends a small JSON payload
containing the result and GitHub Actions run URL. Do not commit webhook URLs or
trading credentials.

## MetaEditor compilation

GitHub-hosted runners do not include MetaTrader's proprietary MetaEditor compiler.
Open the appropriate source under the MQL4 or MQL5 data folder in MetaEditor and
compile it there before attaching an EA to a chart or enabling automated trading.