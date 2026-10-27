# Implementation status

Date: 2026-10-27. Work is in progress against the entire REQUIREMENTS.md; this is not a completed acceptance declaration.

| Area | Source / evidence | Current state |
|---|---|---|
| R01 A real market data / local trading | MarketData.swift, TradingEngine.swift | REST adapters implemented; credentialed live verification blocked by missing user entitlements |
| R02 B offline market | Simulation.swift, ChartWeb | 120 tradable + 5 indices; deterministic paths, five-second events; core tests passed |
| R03 A/B isolation | Persistence.swift, AccountContext, CoreTests | Separate database files and epoch validation tested |
| R04 cold-launch switching | AppModel.boot, AppSettings | Implemented; pending-state unit test and terminate/relaunch UI smoke passed; full A/B switch acceptance pending |
| R05 funding | cashFlow/exchange, CashView | Exact values, cash reservations, external-flow separation tested |
| R06 full scope | REQUIREMENTS.md and this table | Not yet fully accepted; missing behaviors tracked in KNOWN_LIMITATIONS |
| R07 order types and markets | TradingEngine, RulePack, OrderForm | Market/limit/stop/trailing/OCO/bracket, FOK/IOC/post/reduce; core tests passed for covered cases |
| R08 native UI and charts | Features/, ChartView, ChartWeb | Implemented; Simulator compilation and both offline UI flows passed on 3a4f3379 (full run 40451960851) |
| R09 public repository | Kongdean2374/ChaiTrade | Public read/write and independent clone/download verified |
| R10 unsigned IPA | workflows/, scripts/ | Workflow and artifact validators implemented; Unsigned IPA artifact produced by successful run 40451960851; user signing/device verification still required |
| R11 no actual assets | NetworkPolicy | Only allowlisted market-data GET requests; policy tests passed |
| R12 maintenance and verification | CoreTests, backups, docs, scripts | 65 ordinary core functions; Release T45 includes analytics, concurrent consistent backup, full CSV equality and backup restore. Local gates passed; this feature batch awaits Apple CI and device acceptance |

Technical choice: native SQLite C binding replaces GRDB so the same persistence code can be compiled and executed on Linux and iOS without conditional database engines. Transactions, WAL, schema versioning and account validation remain explicit. This choice does not remove the required behavior; full normalized event reconstruction, query performance and migrations still require further validation.

This iteration adds calendar-correct week/month bars, exact optimized synthetic OHLC, real backwards provider paging, bounded chart caches, persisted chart preferences, journal PNG attachments and local notification dispatch. Trading-cycle statistics use exact fee allocation and exclude the additional cash flows listed in their policy. These new native flows require the new Apple run; they are not covered by the older IPA's UI evidence. See REMAINING_WORK.md for unimplemented requirements and unexecuted acceptance.

B now supports configurable signed side-specific carry schedules, exchange-timezone daily settlement and automatic final expiry. New accounts use state schema 2; existing schema-1 worlds keep their persisted rules until explicitly changed. Exact checkpoint/restart tests pass. Funding debits consume free funds before isolated margin, and cross risk excludes another currency's isolated collateral. This does not add official A event synchronization or hedge positions.

Equity history is now normalized under database schema 4. The strengthened T45 includes 100,001 equity points as well as 100,000 fills; full restore and prefix return/drawdown checks pass. Same-time fills retain their fee impact in the curve, and initial B funding uses simulation time. New native equity paging and the screenshot journal's scrolling path await Apple UI verification.

Offline intraday history now counts valid trading bars and skips closures/weekends when paging backwards. The full local Release run executes all 67 tests (stress and production Coinbase enabled) with zero skipped. The final screenshot UI case explicitly checks switch activation and a valid preview before saving, while retaining saved-image/export assertions. Apple rerun remains required.
