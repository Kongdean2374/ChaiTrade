# ChaiTrade engineering constraints

- Follow docs/REQUIREMENTS.md. Preserve the full requested scope and honest status tracking.
- Never add actual exchange orders, transfers, trading credentials, or telemetry.
- B must not create a transport or read Keychain credentials.
- Use Amount for financial values; Double is confined to simulation generation and chart/indicator presentation.
- All mutations pass through TradingEngine and one SQLite transaction. Validate account and epoch.
- Run `swift test` in Packages/ChaiTradeCore after financial/core edits; run Xcode UI and device build for UI edits.
- Update docs/IMPLEMENTATION_STATUS.md and TEST_REPORT.md with actual evidence. Do not count unexecuted checks as passed.
- Rebuild the committed project with scripts/generate_project.py after adding app Swift files.
- Keep chart code local and dependency checksums fixed. No remote fonts or chart CDN.
