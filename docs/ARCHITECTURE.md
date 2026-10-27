# Architecture and decisions

SwiftUI → MainActor AppModel → immutable AccountContext → TradingEngine actor → AccountRepository. Charts receive presentation-only data and emit bounded, account/epoch/instrument-validated intents. A chart drag opens a confirmation; it cannot write the ledger.

Each account has its own SQLite file under `accounts/account-online` or `accounts/account-offline`. State projection, audit events and fill indexes commit in one `BEGIN IMMEDIATE` transaction. An exception leaves the actor's previous value and database unchanged. Full ledger validation checks each event/currency and reconstructs cash from its postings. Account and epoch are validated before writes.

Technical deviation from the planned GRDB dependency: a small native SQLite binding is used so exactly the same repository can execute under Linux and Apple CI without swapping persistence implementations. SQLite WAL, FULL synchronization, schema versioning, unique event/fill IDs and indexed pagination are explicit. No SPM remote dependencies are needed.

Database schema 3 stores immutable fills/events/ledger and indexed orders separately from a bounded hot projection (100 recent fills/events and terminal orders, plus active protection relationships). Prefix ledger balances preserve cash reconstruction without loading archived history into a screen. Prepared batches append immutable rows and reject conflicting IDs. Exact CSV cells, cumulative analytics and periodic open-cycle checkpoints commit with the same transaction. Equal-time order paging uses a time/ID cursor. Stale projections and mismatched history counts roll back.

Full backups use an independent read-only connection and one SQLite read transaction, so the WAL writer can continue. Restore/reset acquires an engine maintenance token before its recovery snapshot and blocks new account mutations until replacement or explicit release. Production online order matching checks its injected wall clock at actual actor execution, so a queued request cannot make an old quote fresh. Bulk full-integrity reconstruction remains a multi-second background operation. Measured evidence and remaining work are recorded in TEST_REPORT and KNOWN_LIMITATIONS.

Cold launch verifies the target repository before committing pendingMode. Foreground resume keeps the current context. Switching to A excludes that interval from B catch-up. Simulation time, ledger and corresponding wall-clock anchor are checkpointed atomically. Long or reversed wall-clock changes require a visible choice.

Provider transports are constructed only for A. HTTPS GET hosts/routes and the public Coinbase market-data WebSocket are allowlisted; redirects are rejected. No exchange trading SDK, order endpoint, transfer, telemetry or remote chart resource exists.
