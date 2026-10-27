# Data and numeric contracts

Amount is a checked Decimal wrapper. User input is a strict decimal string, at most 12 fractional digits and magnitude 10¹⁵. Exact Decimal intermediate precision is retained in persistent strings; decoding verifies a lossless canonical round trip instead of silently truncating it. Add/subtract/multiply reject overflow or loss of precision. Recurring division explicitly rounds at 12 decimals. SQLite stores financial values inside JSON strings/text, never REAL; numeric sorting is performed by Amount or indexed integer time/cursors.

Each account snapshot includes instruments/rules, balances/external flows, orders, positions, fills, double-entry ledger, audit events, alerts, journal, drawings, equity and optional lifecycle (settlements, corporate actions, carry, FX rates). Optional additive fields preserve earlier schema-1 decoding. Future incompatible schema versions are rejected; errors never reset balances.

`account_state` stores the canonical sorted JSON projection. `events` has unique ID and sequence. `fills` has unique ID and indexes by time/order; rowid supports stable backwards pagination. The projection and both indexes are committed atomically. A/B account IDs are checked in ledger, orders and fills.

Available cash = settled cash − grouped order reservations − margin − pending settlement payables. OCO shares a reservation group. Filled cash changes are distinct from reservations. Fees accrue cumulatively per order, so partial fills do not each re-charge the minimum.

Lifecycle events carry stable IDs and source descriptions. Receivables/payables are valued once and settle once. Futures settlement resets basis; dividends accrue then pay; a split preserves total cost. Read the known limitations before interpreting these custom simulation rules as official market conventions.
