# Known limitations and remaining acceptance work

The complete implementation and external verification gaps are maintained in [REMAINING_WORK.md](REMAINING_WORK.md). They remain part of the requested scope. This product is not fully accepted against all 48 plan cases.

T45 uses 100,000 fills/orders, 200,002 ledger entries and 100,001 equity points. All rows remain in the database and complete backups; only the normal screen projection is bounded. The existing automated storage gates (3 s hot repository load, 300 ms page p95, 150 ms local order-write p95) and added 3 s CSV/analytics gates remain enforced. These measurements do not establish the plan's **2 s normal B cold launch**, physical-device frame rate, memory or battery targets. Full import/integrity/backup operations remain multi-second explicit background work.

The latest successful Apple build, UI cases and IPA source are recorded in TEST_EVIDENCE.json and TEST_REPORT.md. Failures do not publish an IPA. Signed iPhone installation, locked-device notifications, credentialed market feeds and full acceptance still require the unavailable device/entitlements listed in REMAINING_WORK.md.
