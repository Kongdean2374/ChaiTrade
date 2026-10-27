# Known limitations and remaining acceptance work

This file records gaps honestly; none are removed from the requested complete product scope.

- iOS compilation, UI automation and unsigned IPA packaging must run on GitHub macOS. iPhone 17 Pro signing and device validation require the user's device and valid signing setup.
- Provider REST adapters require fixture coverage for every schema and live verification with user entitlements. Coinbase's public endpoint returned HTTP 403 from the cloud environment, so live success has not been claimed. WebSocket lifecycle, source-specific incremental depth recovery, dynamic product discovery and provider failover remain to be completed/verified.
- Market calendars, Taiwan odd-lot/full-lot sessions, price tiers, settlement and fees have not been verified against current official rule packs. Current UI clearly calls these custom simulation rules.
- Derivatives currently use net one-way positions and a disclosed mark-settlement liquidation model. Hedge position mode, tiered collateral, detailed forced-order fills and funding scheduling require additional implementation/validation.
- Realistic receivables/payables settlement, complete corporate action timeline and related replay tests are not yet accepted.
- Full 100,000-fill performance measurements, journal attachments/screenshots, system notification permission flow, complete period-by-period performance statistics and multi-account backup container remain unaccepted.
- The committed UI exposes only working implemented paths; the status file must continue to track requested behaviors not yet exposed. No placeholder or fake online quotes are used.

Do not label this product as fully conforming to all 48 acceptance cases until evidence is recorded.
