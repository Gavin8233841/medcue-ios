# Persistent store recovery boundary (#13)

If the primary SwiftData store cannot open, the app shows a recovery-only page.
The in-memory fallback supplies a scene container but is never shown as a normal
medication workspace; external dose intents return a save failure. Retry calls
the same primary `MedicationAdherenceModelContainer.make()` path and opens the
existing store. It does not move, delete, or recreate the store.

The diagnostic export is a JSON object with exactly six fields:
`appVersion`, `build`, `systemVersion`, `failureStage`, `errorCategory`, and
`generatedAt`. Stage and category are fixed enums. Raw framework errors,
record contents, identifiers, credentials, and sandbox paths are excluded.

The sensitive export reads the store URL reported by the existing SwiftData
configuration and any present `-wal`, `-shm`, and `-journal` companions. It
copies bytes to an opaque, app-owned Application Support directory with complete
file protection, then compares source-before, source-after, and copy sizes and
SHA-256 hashes. An incomplete generated directory is removed on failure; the
originals are never opened for writing. On a physical device, failure to verify
complete file protection stops export. Simulator file-protection attributes do
not provide equivalent evidence.

The copy contains complete private medication data. The app has no tested
import/restore path, so neither the UI nor this document describes it as a
recoverable backup. A user-initiated share may place a copy under another
app's protection policy. “Start fresh” is unavailable until a restore path is
implemented and tested; startup, retry, export cancellation, or export failure
never rebuild the store.
