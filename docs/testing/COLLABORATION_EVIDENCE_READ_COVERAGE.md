# Original evidence page coverage

## Scope

Android 1.4.26 adds host-owned page coverage to the existing scoped evidence
recall path used by cloud members and remote/native members. A citation alone
is not evidence that a reviewer received the original tool observation.

The encrypted evidence ledger retains merged half-open character intervals for
each exact `(group, run, turn, round, node, person, evidence ID, evidence hash)`.
Intervals refer to the immutable serialized source, with its own content hash.
Duplicate/overlapping reads do not accumulate per-call history. A direct lookup
is used for each citation, not a scan of the group's discussion history.

The returned `host_read_coverage` reports the number of characters served and
the first missing offset. Callers still follow `next_offset` to read all pages.
An index, a source ID, a final-page-only read or an empty end-of-document read
does not establish complete coverage. Invalid offsets fail without writing
coverage; page boundaries do not split a Unicode surrogate pair.

## Publication and acceptance

When publishing a workspace revision, the host resolves exact original
observations and freezes its own coverage snapshot in `host_observations`.
Member-supplied coverage fields are ignored. Formal goal acceptance checks the
snapshot on each original observation cited by the selected independent review:

- The reader identity must match the saved review's dispatch, not just its name
  or model provider.
- Source ID, digest, complete serialized length and content digest must match.
- Another member's read or a different dispatch by the same member cannot be
  substituted.
- Reading missing pages after publication does not update an old review. The
  member must publish a new review after receiving the missing source material.
- A tool observation produced in the reviewer's own exact dispatch is separately
  labeled `same_dispatch_execution`; it is not misrepresented as paginated recall.
- Existing source-type requirements, negative-review handling, contributor
  independence, version checks and semantic coverage remain in force.

Coverage can survive reopening the encrypted stores. Group removal deletes it
with the existing group-prefixed evidence records. Nothing is sent periodically;
updates occur only when an authorized recall serves an original page. There are
no new UI elements and no changes to ordinary chat, routing or model limits.
Existing unbound history recall remains readable but is labeled `unattributed`;
it does not create a member's read-coverage record or certify a review.

## Meaning and limitations

Coverage proves that the host produced complete source pages for that member's
scoped tool context before publication. It does **not** prove that a provider
received every network byte, attended to every token, understood the source,
verified the claim, or performed a scientific experiment. A direct execution
receipt likewise records an operation, not scientific truth.

Historical published reviews without coverage are not retroactively certified.
They remain preserved, and previously completed research is not automatically
restarted. New formal acceptance of such material requires fresh review.

## Validation

Automated cases cover missing middle pages, duplicate/out-of-order/overlapping
reads, exact identity and source binding, immutable publication snapshots,
reopening stores, invalid offsets, tampering, revocation, and Unicode boundaries.
The device fixture exercises cloud and native recall with a multi-page original.
The opt-in real-provider fixture is `CollaborationLiveEvidenceDeviceTest` with
`collaborationLiveEvidence=true`; it uses only a synthetic read-only arithmetic
document and independent documentary review, not the user's research.

## Results: 2026-10-03

- Android main and instrumentation APKs compiled successfully. S26U was upgraded
  in place to **1.4.26 (1111)**; existing data was retained.
- **724 JVM tests across 55 suites** passed, with no failures, errors or skips
  (`Collaboration*` and `Mqtt*`). The new coverage tests include a 10,000-unrelated-
  record fixture that checks a citation needs two direct row reads, not a history
  scan. This is a lookup-complexity check, not a measured p95 latency result.
- **32 on-device tests passed in 4.08 seconds**: scoped cloud/native recall,
  encrypted evidence reopening, five goal-acceptance cases, and 25 atomic-inbox
  cases. These use dedicated local fixtures and make no real provider calls.
- The 153,600-byte Kotlin source-size policy and `git diff --check` passed.

The first regression exposed JSON integer/long identity normalization and the
need to preserve unbound history reads without attesting to a member. Both were
corrected. An existing positive ancestry fixture was also updated to actually
fetch its cited source before publishing; its independent-author checks were not
weakened. The final full regression is the passing result above.

S26U returned to the secure lock screen during compilation. No new real-provider
attempt was started while waiting for unlock. The updated strict Codex + DeepSeek
fixture therefore remains **pending**, not passed. Existing Desktop 1.4.2 was
not restarted or replaced. Prior real-provider passes in
`COLLABORATION_LIVE_EVIDENCE.md` do not validate this new gate and are not counted
as new samples. Scientific validation and equal-budget team superiority are also
not established by these tests.
