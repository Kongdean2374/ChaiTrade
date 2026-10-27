# Known limitations and remaining acceptance work

This file records gaps honestly; none are removed from the requested complete product scope.

- iOS compilation, UI automation and unsigned IPA packaging must run on GitHub macOS. iPhone 17 Pro signing and device validation require the user's device and valid signing setup.
- Provider REST adapters require fixture coverage for every schema and live verification with user entitlements. Coinbase's public endpoint returned HTTP 403 from the cloud environment, so live success has not been claimed. Coinbase public level2 lifecycle and dynamic source catalogs are implemented with fixtures; complete lifecycle/recovery for the other sources and failover remain unaccepted.
- Market calendars, Taiwan odd-lot/full-lot sessions, price tiers, settlement and fees have not been verified against current official rule packs. Current UI clearly calls these custom simulation rules.
- Derivatives currently use net one-way positions and a disclosed mark-settlement liquidation model. Hedge position mode, tiered collateral, detailed forced-order fills and funding scheduling require additional implementation/validation.
- Custom business-day receivables/payables settlement, manual corporate actions, carry events and futures settlement are implemented and tested. Official calendar/rule packs, automatic reliable event synchronization and complete replay acceptance remain outstanding.
- 100,000-fill persistence/report measurements are recorded in STRESS_REPORT.json: indexed 100-row queries are fast, but full saves/loads miss the intended latency. Dual-account backups are implemented. Journal screenshots/attachments, system notifications and complete period/cycle statistics remain unaccepted.
- The committed UI exposes only working implemented paths; the status file must continue to track requested behaviors not yet exposed. No placeholder or fake online quotes are used.

Do not label this product as fully conforming to all 48 acceptance cases until evidence is recorded.
