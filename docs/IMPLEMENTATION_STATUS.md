# Implementation status

Date: 2026-10-27. Work is in progress against the entire REQUIREMENTS.md; this is not a completed acceptance declaration.

| Area | Source / evidence | Current state |
|---|---|---|
| R01 A real market data / local trading | MarketData.swift, TradingEngine.swift | REST adapters implemented; credentialed live verification blocked by missing user entitlements |
| R02 B offline market | Simulation.swift, ChartWeb | 120 tradable + 5 indices; deterministic paths, five-second events; core tests passed |
| R03 A/B isolation | Persistence.swift, AccountContext, CoreTests | Separate database files and epoch validation tested |
| R04 cold-launch switching | AppModel.boot, AppSettings | Implemented; pending-state unit test passed; UI relaunch validation pending |
| R05 funding | cashFlow/exchange, CashView | Exact values, cash reservations, external-flow separation tested |
| R06 full scope | REQUIREMENTS.md and this table | Not yet fully accepted; missing behaviors tracked in KNOWN_LIMITATIONS |
| R07 order types and markets | TradingEngine, RulePack, OrderForm | Market/limit/stop/trailing/OCO/bracket, FOK/IOC/post/reduce; core tests passed for covered cases |
| R08 native UI and charts | Features/, ChartView, ChartWeb | Implemented; Simulator compilation passed in earlier runs; app launch smoke currently failed and is under investigation |
| R09 public repository | Kongdean2374/ChaiTrade | Public read/write verified with README round trip |
| R10 unsigned IPA | workflows/, scripts/ | Workflow and artifact validators implemented; main workflow executing; no IPA success claimed yet |
| R11 no actual assets | NetworkPolicy | Only allowlisted market-data GET requests; policy tests passed |
| R12 maintenance and verification | CoreTests, backups, docs, scripts | 39 ordinary Linux Swift test functions passed; 1 stress test separately passed; stress/device/migration acceptance incomplete |

Technical choice: native SQLite C binding replaces GRDB so the same persistence code can be compiled and executed on Linux and iOS without conditional database engines. Transactions, WAL, schema versioning and account validation remain explicit. This choice does not remove the required behavior; full normalized event reconstruction, query performance and migrations still require further validation.
