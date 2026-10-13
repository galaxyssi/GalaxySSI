# Collaboration context allocation and scoped recall

## Failure modes

The full Android CI run on main at 69ccd9f01 failed three collaboration checks:
the live-resource coordinator could not inline a 5,610-character original goal;
one tool revision was read twice within a capability page; and an older test
mistook candidate metadata recall for indexing source code or test answers.
These failures also appeared in the autonomous-loop foundation PR.

## Prompt allocation

Required assignments, response protocols, execution boundaries and resource
observations remain atomic. The dispatch limit stays at 32,000 characters.
Optional material is admitted in priority order without truncation. Each
allocation charges the omission references it will actually emit, including
changes to the first-eight reference window. References for admitted material
are not charged again. Earlier skipped sections are reconsidered after short
inline sections remove reference overhead; admission only grows, so this reaches
a fixed point without dropping already admitted text. If every section fits,
no omission directory is needed.

The context-availability footer now reserves the serialized size of its longest
possible record rather than a fixed 512 characters. The actual footer is checked
against that bound. This removes unused headroom without dropping status fields
or making a complete-inline claim for omitted material.

Length accounting uses Long arithmetic without constructing rendered copies of
large omitted bodies. Unfitting required context still fails explicitly before
model dispatch; it is not clipped or misreported as a model answer. Omitted
originals remain available through the existing pinned, encrypted goal contract.

## Capability page reuse

Directory and linked-source lookups share one page-local revision cache, keyed
by object ID, revision and digest. The first lookup still uses the existing
scoped read and integrity checks. A new page request or assignment starts a new
cache and revalidates the original; there is no global plaintext cache or
cross-assignment reuse.

The observer-concurrency regression now uses a bounded two-participant barrier
instead of hoping two tasks overlap within a 60 ms sleep. Serial execution still
fails: both observers must enter before either can finish. Production scheduling
and concurrency limits are unchanged.

Unreleased tool definitions remain discoverable as candidates, not callable
releases. Search excerpts contain allowed metadata only. Source code, test
cases and expected answers require separate original reads. Search does not
grant permissions, change lineage checks or release a candidate.

## Acceptance boundary

Regressions cover exact-fit allocation, complete Unicode goals, overflowing
reference directories, shifting reference windows, required-context overflow,
all research roles, first dispatch and restored dispatch, candidate metadata,
linked-source integrity, and page/assignment isolation.

Device fixtures exercise encrypted original-goal paging, cloud/native recall,
database reopening and separate-process recovery. Their injected decisions and
observations are not proof of autonomous real-provider dependency installation,
website login, or successful end-to-end problem solving. That broader goal
remains open.

## Verified increment

Android 1.4.187 (1272) built successfully. All 72 targeted tests passed. The final
full workspace run covered 6,516 tests across 813 suites: no failures or errors,
with five explicit environment skips. Four require the isolated Blob
cross-runtime runner; one requires Windows symbolic-link privileges. These
skips are not successful validations of those behaviors.

S20U / SM-G9880 was updated without clearing user data. All 65 local, browser,
collaboration and continuation checks passed. Separate seed/recover processes
also passed both phases, restoring a 51-page encrypted goal contract and
rejecting its deliberately damaged fixture. The cold Activity launch reported
TotalTime=673 ms and WaitTime=681 ms; MainActivity resumed and the crash buffer
was empty. These are Activity timings, not first-content or model latency.

Build/device tests used the current workspace, including separately developed
unstaged MQTT work. That work is excluded from this increment. Repository Guard
passed against the clean staged-source snapshot.

Evidence is retained under .local-artifacts/autonomous-problem-solving/:

- build-1.4.187-final.txt and jvm-1.4.187-four-suites.json
- jvm-1.4.187-full-final.txt, jvm-1.4.187-full-summary.json and jvm-1.4.187-skipped.json
- s20u-1.4.187-final-regression.txt and s20u-1.4.187-final-goal-{seed,recover}.txt
- s20u-1.4.187-{installed-package,cold-start,resumed-activity,crash-buffer}.txt
- pr-1.4.187-clean-repo-guard.txt and apk-1.4.187-hash.json
