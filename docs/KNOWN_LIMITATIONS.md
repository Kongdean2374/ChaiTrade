# Known limitations and remaining acceptance work

This file records gaps honestly; none are removed from the requested complete product scope.

- iOS compilation, two UI flows and unsigned IPA packaging passed on GitHub macOS (run 40450662963). iPhone 17 Pro signing and device validation require the user's device and valid signing setup.
- Provider REST adapters require fixture coverage for every schema and live verification with user entitlements. Coinbase succeeded with the app User-Agent and the production Swift adapter passed live ticker/book/candle reads; Binance returned HTTP 451. Coinbase public level2 lifecycle and dynamic source catalogs are implemented with fixtures; complete lifecycle/recovery for the other sources and failover remain unaccepted.
- Market calendars, Taiwan odd-lot/full-lot sessions, price tiers, settlement and fees have not been verified against current official rule packs. Current UI clearly calls these custom simulation rules.
- Derivatives currently use net one-way positions and a disclosed mark-settlement liquidation model. Hedge position mode, tiered collateral, detailed forced-order fills and funding scheduling require additional implementation/validation.
- Custom business-day receivables/payables settlement, manual corporate actions, carry events and futures settlement are implemented and tested. Official calendar/rule packs, automatic reliable event synchronization and complete replay acceptance remain outstanding.
- T45 Release benchmark now passes locally: bounded hot state, indexed paging/search, exact CSV cache, 30-sample order-write p95, full-history reconciliation and 100,000-fill compressed backup restore. Apple CI and signed-device acceptance remain separate. Bulk import/full integrity reconstruction remain multi-second explicit background operations; screens never load the entire history. Journal screenshots/attachments, system notifications and complete period/cycle statistics remain outstanding.
- The committed UI exposes only working implemented paths; the status file must continue to track requested behaviors not yet exposed. No placeholder or fake online quotes are used.

Do not label this product as fully conforming to all 48 acceptance cases until evidence is recorded.
