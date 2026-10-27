# Architecture and decisions

SwiftUI → MainActor AppModel → immutable AccountContext → TradingEngine actor → AccountRepository. Charts receive presentation-only data and emit bounded, account/epoch/instrument-validated intents. A chart drag opens a confirmation; it cannot write the ledger.

Each account has its own SQLite file under `accounts/account-online` or `accounts/account-offline`. State projection, audit events and fill indexes commit in one `BEGIN IMMEDIATE` transaction. An exception leaves the actor's previous value and database unchanged. Full ledger validation checks each event/currency and reconstructs cash from its postings. Account and epoch are validated before writes.

Technical deviation from the planned GRDB dependency: a small native SQLite binding is used so exactly the same repository can execute under Linux and Apple CI without swapping persistence implementations. SQLite WAL, FULL synchronization, schema versioning, unique event/fill IDs and indexed pagination are explicit. No SPM remote dependencies are needed.

This does not claim every desired normalized table has been implemented. The current full account projection remains a serialization and cold-load bottleneck at 100,000 fills. Measured evidence and remaining work are recorded in TEST_REPORT and KNOWN_LIMITATIONS.

Cold launch verifies the target repository before committing pendingMode. Foreground resume keeps the current context. Switching to A excludes that interval from B catch-up. Simulation time, ledger and corresponding wall-clock anchor are checkpointed atomically. Long or reversed wall-clock changes require a visible choice.

Provider transports are constructed only for A. HTTPS GET hosts/routes and the public Coinbase market-data WebSocket are allowlisted; redirects are rejected. No exchange trading SDK, order endpoint, transfer, telemetry or remote chart resource exists.
