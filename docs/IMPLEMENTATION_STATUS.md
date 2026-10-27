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
| R08 native UI and charts | Features/, ChartView, ChartWeb | Implemented; Latest native compilation and nine UI cases x2 plus focused order x2 passed (40517887202); complete device/UI acceptance remains separate |
| R09 public repository | Kongdean2374/ChaiTrade | Public read/write and independent clone/download verified |
| R10 unsigned IPA | workflows/, scripts/ | Workflow and artifact validators implemented; Latest unsigned IPA produced by successful run 40517887202; user signing/device verification still required |
| R11 no actual assets | NetworkPolicy | Only allowlisted market-data GET requests; policy tests passed |
| R12 maintenance and verification | CoreTests, backups, docs, scripts | 69 ordinary core functions; Release T45 includes analytics, concurrent consistent backup, full CSV equality and backup restore. Local full Release and Apple required gates passed (40517887202); complete device acceptance pending |

Technical choice: native SQLite C bindings keep persistence identical on Linux and iOS. WAL, atomic financial transactions, migration rollback/retry and bounded indexed history are tested. This is not a waiver of full plan acceptance.

This iteration implements:

- Database schema 4: complete immutable fill/order/ledger/equity history, bounded hot state, indexed paging/search, exact CSV cache, atomic performance checkpoints, independent consistent backup reads and guarded restore/reset.
- Exact calendar week/month bars and optimized deterministic OHLC; backwards provider history paging; stock history across market closures; bounded chart caches and account/instrument preferences.
- Watermarked local chart PNGs, journal associations and export; native local notifications with stable event identities and outbox acknowledgement.
- Day/week/month fill-cycle reports, partial/flip cost allocation, NAV/drawdown prefix state and equity history paging. The UI/policy disclose the cash-flow and historical multiplier gaps in REMAINING_WORK.md.
- B fixed-clock signed long/short carry, timezone-aware daily/final settlement, stable event replay and canonical set encoding. New state schema 2; older worlds retain their saved rules. Isolated fee handling and cross-currency collateral accounting corrected.

Latest local full Release: all 71 tests executed and passed with CHAI_STRESS=1 and CHAI_LIVE=1, zero skipped. Apple run 40517887202 passed core/live, unchanged required T45, unsigned device compilation and all 20 isolated UI executions. Source, IPA and evidence are in TEST_REPORT.md / TEST_EVIDENCE.json.

[REMAINING_WORK.md](REMAINING_WORK.md) lists the incomplete product behaviors and unavailable external checks. The plan's 2 s normal B cold launch and other physical-device performance targets remain unverified.

Interaction fixes: stable journal draft identity / synchronous save guard, fixed request identity / submit guard, atomic engine favorites, catchup mutation blocking with usable sheet dismissal, fixed pause/resume locations, and order tab change after sheet dismissal. All adversarial assertions and test allowances remain; historical failed runs are retained in INTERACTION_VALIDATION.md. Older iOS18.x two-round interaction and signed-device acceptance remain unverified.


## Product completion development — 2026-10-27 (not final acceptance)

The complete original plan remains authoritative. Product work is on `product-experience-20261027`; the main-branch IPA described above predates this redesign. The current native app separates market browsing from cold A/B account switching, offers rich real-name identities, market home/list/news, chart-first details and market-specific order language, compact portfolio summaries, settings groups and data tools. Local order/accounting paths remain in TradingEngine and SQLite transactions.

Core additions include independent hedge positions, progressive risk tiers, collateral ratios, liquidation estimates and explicit estimated liquidation fills; immutable financial-flow history and full economic cycles with fixed fill multipliers/notional; deterministic offline news/events/corporate actions; distinct participant refill pools and archived own-trade impact replay; bounded visible quote requests and typed source status; official public US listing metadata search. Additive identity migration retains old holdings/history and old A trading rules until explicit flat upgrade.

Evidence: full Release100 passed with live and stress enabled, zero skipped, in `.reports/product-full-release-sixth.log`. Original T45 writep95=51.769125ms, 100,000 fills and100,001 equity points, unchanged thresholds. Real HTTP BTC/ETH quotes/stats/history/recovery, official RSS and official US directory passed. This is Linux storage evidence, not signed iPhone startup or feedback performance. Minor later corrections require a final full rerun.

Apple run40559942622 passed native device/simulator and core/T45. New product UI: stock→order→holding→journal, fresh A missing-key + multiple public quotes, and settings/bottom reachability passed; landscape selector, crypto news navigation/keyboard and post-restart market switch failed. Failure artifact12762820764 has SHA256 f127115bb836dc2c5ac9eaaba567c630c84647dde95da1056173ca69f293a716; screenshots and independent databases were inspected before fixes. Old crypto query ETH remained in SQLite; UI navigation must be verified separately. Original20 interaction executions completed:19passed and1failed on swipe-dismiss after keyboard input. The suite remains failed; all allowances and assertions are retained for full rerun.

Remaining feasible implementation includes complete calendar/session/source-unit rules, FX validity, percentage and pre-liquidation alerts/deep links, streaming archives beyond existing safe limits, visual matrix and complete original/new interaction acceptance, plus the final walkthrough, screenshots, documentation and unsigned IPA. Credentials, regional restrictions and physical-device measurements remain explicit external blockers; they do not excuse the feasible code work.
