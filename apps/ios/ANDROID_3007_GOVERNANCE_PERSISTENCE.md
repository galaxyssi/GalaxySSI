# Checked Governance Persistence

Independent iOS follow-up on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. This closes the governance read/write
error-reporting limitation recorded in ANDROID_3007_KNOWLEDGE_GAP_SOURCE_FOLLOWUP.md,
not a claim that Android #3007 introduced a different encrypted wire/storage format.

## Change

AgentCognitiveGovernanceStore previously treated decryption/decoding failure as
an empty state and ignored the encrypted writer's failure result. Reads now
distinguish an absent key from an unreadable encrypted record or unexpected
plaintext value. Mutations refuse unreadable state and return nil after encoding
or reported write failure. Stable diagnostic codes contain no stored prose, key
material or raw error text. A later successful read clears the diagnostic.
No new key, migration, plaintext fallback or removal is attempted after a failed
read. The shared encrypted store, key lookup/creation and AES-GCM format remain
unchanged. Its write Bool is the existing API acknowledgement, not an fsync or
durable-disk guarantee for UserDefaults.

Status updates hold the existing instance lock across read, mutation and checked
write and retain all other gap fields. Detector processing stops after an
unreadable family lookup rather than inventing a separate new gap from an empty
result. The bridge loads the current persisted gap by ID, not stale callback
prose or caller-supplied source membership; missing/unreadable gaps cannot queue.

Research queue persistence still precedes governance bookkeeping. After a failed
status or decision write, a later ordinary observation may reconcile only one
matching active queued/running/waiting/scheduled task with exact source event,
source set/primary, topic and bounded question. No new research task is created
or dispatched during this repair. Save status before appending a decision;
recognize prior queue decisions and use a stable gap-specific decision ID.
Current sources/settings and later research runtime gates remain authoritative.
Mismatched, ambiguous or terminal research records are not adopted as proof.

## Verification

Ten XCTest methods authored in the existing EvalOps fixture, NOT executed:
missing/corrupt state; authenticated invalid JSON/unknown plaintext; temporary
key unavailability without replacement; first-write failure; failed gap/status/
decision/outcome mutations retaining prior ciphertext; detector failure;
bridge missing/corrupt gap; status-write repair; decision-write repair; and
current saved-gap selection over stale caller prose. The secret-store fixture
uses locked deterministic failure counters. These are not native Keychain,
CryptoKit, UserDefaults fault, multi-process or actual research-execution tests.

The source guard pins exact approved sections to
`a72b0985904205a718c5bce4cd360d9ceb8233c6`, restores only those sections and
compares complete source/fixtures against main; synthetic weakening fails.
Encryption, evaluation storage, research model/policy and main runtime kernels
remain byte-identical. The older knowledge-gap checker retains every assertion
with exact-hook normalization. It still fails an old full GalaxySSIServices
dependency snapshot; substituting unchanged main Swift sources reproduces the
same failure. That command is not reported as passing or suppressed.

Dedicated source guard, JS syntax, iOS project structure and diff whitespace
checks pass. No Swift/native compilation, XCTest execution, full check, CI
watching, IPA, private evidence upload or device/privacy/fault acceptance.

## Limits

Research and governance writes remain separate; a queued research task can exist
while its governance status/decision is awaiting repair. Repair requires another
ordinary observation; no new timer/background entitlement is added. Decision
retention is still bounded, not a permanent global idempotency journal. Per-instance
locking is not a shared-file/process CAS or a cross-store transaction. UI error
presentation and other stores' persistence APIs are not redesigned. No retraction
of already dispatched work or inference of missing historical provenance.
Android #3007 and the overall parity backlog remain incomplete.
