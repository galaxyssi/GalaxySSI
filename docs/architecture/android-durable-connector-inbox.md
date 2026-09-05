# Android durable connector reply inbox

## Scope

Android 1.0.6 replaces the pending **final Agent reply** preference array with
an encrypted SQLite inbox. This is not the contact message database, MQTT ACK
queue, managed Specialist ledger, or streaming transcript. Desktop/iOS code,
wire formats, model selection, ASR, and QNN runtimes are unchanged.

The previous array kept only the last 30 replies, discarded replies older than
24 hours, and truncated each plain-text answer to 24,000 characters. These
policies could discard results before the originating conversation consumed
them. Removing by source/contact alone could also acknowledge another turn.

## Storage and receipts

- Persist each response before notifying ordinary reply listeners.
- Identity is the SHA-256 of a structured tuple: source message, originating
  contact, conversation, turn, and task. A resolved failover provider is data,
  not a change to the originating identity.
- Encrypt the complete response with the existing Keystore-backed storage
  cipher. Bind ciphertext to the database name and identity through GCM AAD.
  Only opaque identity/turn hashes, sequence, and handled state are indexed.
- Duplicate pending deliveries cannot overwrite the first durable payload.
  An acknowledgement nulls the body and retains an opaque receipt, so a later
  duplicate cannot resurrect the result. There is no automatic receipt pruning.
- Pending bodies have no age/count eviction. Disk-full and encryption failures
  are failures to persist, not successful empty responses.
- Preserve existing explicit superseded/terminal-turn handling. A user-stopped
  task is not automatically restarted by keeping its reply durable.

## Bounded recovery

Recovery runs on the existing background recovery executor. It captures a
pending sequence high-water mark, reads indexed keyset pages of at most 32
responses, and re-enqueues between pages. New arrivals use the live listener.
Page bodies normally stay within 2 MiB of encoded text; one larger result is
allowed intact. SQLite reads ciphertext in 256 KiB substrings to avoid putting
a multi-megabyte answer into one CursorWindow row. This does not make decoding
an individual large response constant-memory.

`AgentConnectorResponseStore.pending()` now returns one bounded page, not all
recoverable responses. Recovery must use `pendingPage()` and its cursor; startup
checks a turn using the indexed `containsTurn()` operation.

Unreadable individual rows remain pending and do not prevent reading later
rows. Diagnostics contain a count/error class, not message bodies. This phase
does not implement automatic repair of corrupted ciphertext.

## Legacy migration

Import every valid legacy row and a migration marker in one transaction. Do
not delete the legacy preference until that transaction commits. A malformed
legacy entry rolls back the entire import and retains the source; it is not
silently dropped. A committed marker prevents stale preferences from restoring
already-acknowledged replies after a restart.

## Validation

Host checks: 13 focused JVM tests and Android/debug-test APK builds pass. The
final APK passes the 72-library 16 KiB ELF/ZIP audit and the 24-library QNN
package audit. Repository checks and `git diff --check` pass.

Device suites use isolated test database/preference names, not the user's
production inbox. The four regression cases can run against either installed
version using the same test APK: 128 pending replies, a three-day-old reply,
96,000-character text, and a mismatched-conversation acknowledgement.

Twelve additional device cases cover paging/index selection, concurrent
duplicates, large Unicode results, AAD/ciphertext corruption, migration rollback,
stale migration files, and turn isolation. A separate two-phase test persists
129 replies, acknowledges seven, and checks the remaining 122 after an external
`am force-stop`. Run its methods separately with the same `inboxRecoveryId`
matching `inbox-test-[a-z0-9-]{1,60}`; without this argument they are skipped.

## S26U results (2026-09-05)

Device: SM-S9480. Before the test, `MemAvailable` was 3,786,884 KiB and `/data`
had 178,649,536 KiB available. The production database directory was 6,608 KiB.
Only this phone was operated; the separately connected tablet was not touched.

| Validation | Installed version | Observed result |
| --- | --- | --- |
| Four regression cases, unchanged test APK | 1.0.5 (851) | 4/4 fail |
| Same regression cases | 1.0.6 (852) | 4/4 pass |
| Additional SQLite/Keystore cases | 1.0.6 (852) | 12/12 pass |
| Persist before external force-stop | 1.0.6 (852) | 129 stored, seven acknowledged |
| Separate recovery invocation after force-stop | 1.0.6 (852) | All 122 pending restored; acknowledged duplicates rejected |

The baseline specifically restored only 24,000 of 96,000 text characters.
The fixed 16-case run completed in 5.547 seconds. The two process-test phases
took 0.502/0.528 seconds inside instrumentation; these are test durations, not
end-to-end UI recovery latency measurements. Process 12159 was present before
the explicit force-stop; `pidof` confirmed no App process before recovery.

Installation used `adb -s <S26U> install -r`, not uninstall/data-clear. The
original installation timestamp stayed `2026-09-05 10:48:56`. The independent
test APK was removed afterward; production conversations, pairing and models
were retained.

Artifact SHA-256:

- App: `acba4010eddb3aff5d377c95d7f77b0371c7b3182aa3dfe5224cb0d21c851a83`
- Same baseline/retest APK: `88f22a64d0367d498912e65cf4eb344e6420ffffe45f15b8a7c3bb02f6a3f689`

A follow-up live request asking to "call Codex Agent" was interpreted as
installing/calling a CLI in phone Linux. Desktop returned a structured plan and
the phone consumed successive observations, rather than losing the responses.
That test was explicitly stopped using the App's normal stop command. It is
not a successful ordinary-chat latency sample; the intent/planning issue is a
separate follow-up and is not fixed by this inbox change.

A second, ordinary Chinese knowledge question was routed by Auto to Hermes.
The Desktop task failed with `hermes ACP prompt timed out after 60 seconds`,
77,000 ms total task duration and zero result characters. The phone test was
stopped; this is also not an end-to-end chat pass. Provider readiness/failover
and terminal failure delivery need separate investigation. No under-10-second
reply claim is made from these tests; the earlier accepted 13.49-second sample
was from a different successful request.

This phase does not claim that every Run Kernel ID mapping, end-to-end
final-render trace, routing policy, or recovery SLO is complete.
