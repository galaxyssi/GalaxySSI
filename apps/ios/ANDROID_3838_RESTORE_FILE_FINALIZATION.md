# Android #3838: committed restore versus original-file completion

Reference: `bbaf3337a479b98eadae272bb797d37d417e37f7`.
The existing iOS account-scoped restore lease and authenticated staging/receipt
implementation already protects recovery across interruption. This follow-up
does not replace that port or claim Android process-kill testing was executed.

The iOS backup API previously ignored errors promoting committed staged originals,
then the real backup view displayed a full success message. The archive commit
was durable, but original files could still be unavailable or fail authentication.

## Change

- Return an owner/receipt/exact-original-metadata result with originalsReady false
  until post-commit recovery and destination reads succeed. Keep existing callers
  source-compatible through discardable return; the real UI consumes the result.
- Distinguish committed measurements with pending original files from complete
  restore. Clear the consumed restore input/preview/password and expose a dedicated
  file-recovery retry. A retry failure retains the pending result and does not
  claim the committed measurements were rolled back or reimported.
- Retry acquires the existing restore lease, verifies owner and dataset identity,
  checks the committed receipt and every exact indexed original before recovery,
  then reads/authenticates the resulting destinations. It never stages a backup,
  reapplies conflicts, appends revisions, creates receipts or replays restoreWork.
- Respect explicit original removal/index changes instead of resurrecting files.
  Existing archive/source/index/removal crypto, input validation, pre-commit error
  propagation and interrupted staging retention remain unchanged.
- Notify index/record consumers only after successful retry. Existing record/trend
  publication after initial commit remains, even when files are pending. Scene
  reset clears UI tokens; durable receipt/index/staging recovery remains in the
  existing store and can still run on later original-file access.
- Add four Chinese resources with English fallbacks for truthful pending/retry
  states. No new permissions, network/model work, Android/Desktop or version edits.

## Validation Limits

Four Swift fixture methods are authored for corrupt committed staging and repair,
idempotent retry without revision/receipt changes, foreign/uncommitted/changed
tokens, explicit removal and successful API completion. They are NOT executed.
The initial post-commit failure-to-pending UI branch is source-checked, not a native
fault-injection or rendered UI result.

The focused JS guard checks approved deltas, unchanged codec/planning/source
mapping, no restore writes in the retry wrapper, four resources, retained fixture
source and 17 negative source mutations. This is not Swift typechecking or actual
filesystem, crash, process, disk, performance, SceneStorage or device acceptance.
Destination verification reads files sequentially in the existing main-actor
restore operation; no nonblocking or large-backup performance guarantee is made.
No native build/XCTest, CI inspection, live data, IPA or automatic merge.
