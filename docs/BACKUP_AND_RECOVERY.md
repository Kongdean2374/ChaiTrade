# Backup, restore and recovery

Settings exports the active account or both separate accounts through the system file exporter. The format is bounded JSON/base64, not an extracted archive; it has no filesystem paths or decompression surface. Each payload includes its account/mode/schema and a SHA-256 checksum. Licensed online quotes/depth are omitted. Keychain credentials never enter account state or backups.

Optional encryption uses AES-256-GCM, random 16-byte salt and 12-byte nonce, PBKDF2-HMAC-SHA256 with 600,000 iterations. Apple uses CryptoKit/CommonCrypto; Linux tests use the system OpenSSL implementation. Wrong password/tag/checksum, oversized data, schema mismatch and A/B mismatch fail before replacement.

Import validates every account in a dual bundle, then selects only the current mode. The confirmation says it replaces this account. The previous account is exported to its protected local snapshots directory before a single SQLite replacement transaction. The other mode remains unchanged. A single-account reset also creates a recovery point and requires typing RESET plus confirmation.

Plain backups provide corruption checks, not secrecy or tamper-proof financial proof. Keep passwords and backups yourself. The current 50 MB single-container / 32 MB payload limits mean very large archives need additional work; do not delete or reset an account until its exported backup has been validated.

When changing signing Team/Bundle ID, data container and Keychain access can change. Back up first, retain the old app until restoration has been confirmed, and expect to enter market credentials again. Current database schema is 1; unknown higher schemas are refused. Nontrivial interrupted migration acceptance remains outstanding.
