# Backup, restore and recovery

Settings exports the active account or both separate accounts through the system file exporter. The format is bounded JSON/base64, not an extracted archive; it has no extracted filesystem paths. Large payloads use zlib with a declared expanded size and bounded output; malformed sizes/streams fail before replacement. Each payload includes its account/mode/schema and a SHA-256 checksum. Licensed online quotes/depth are omitted. Keychain credentials never enter account state or backups.

Optional encryption uses AES-256-GCM, random 16-byte salt and 12-byte nonce, PBKDF2-HMAC-SHA256 with 600,000 iterations. Apple uses CryptoKit/CommonCrypto; Linux tests use the system OpenSSL implementation. Wrong password/tag/checksum, oversized data, schema mismatch and A/B mismatch fail before replacement.

Import validates every account in a dual bundle, then selects only the current mode. The confirmation says it replaces this account. The previous account is exported to its protected local snapshots directory before a single SQLite replacement transaction. The other mode remains unchanged. A single-account reset also creates a recovery point and requires typing RESET plus confirmation.

Plain backups provide corruption checks, not secrecy or tamper-proof financial proof. Keep passwords and backups yourself. The bounds are 50 MB per single-account envelope, 32 MB compressed payload, 512 MB expanded payload, and 100 MB per dual-account bundle. The 100,000-fill round trip is tested. Larger histories and device peak memory still need validation; do not delete or reset an account until its exported backup has been validated.

When changing signing Team/Bundle ID, data container and Keychain access can change. Back up first, retain the old app until restoration has been confirmed, and expect to enter market credentials again. Current database schema is 4; unknown higher schemas are refused. Injected migration failures from schemas 1, 2 and 3 preserve the original account and support retry. Physical-device termination/power-loss migration acceptance remains outstanding.
