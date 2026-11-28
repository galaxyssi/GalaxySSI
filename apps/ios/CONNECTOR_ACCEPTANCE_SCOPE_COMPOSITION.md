# Connector Observation Scope Composition

This tools-only correction addresses a historical source-check failure, not an
iOS application feature, Swift compiler fix or Android runtime acceptance.
Reviewed source baseline: c6bad3465c673dfb2dcecb23b095185c129c7447.

The acceptance checker compared the Desktop probe checker against its pre-hook
version at 8a794e82ebe8f09790e41139295ffb7ac1ee9701. Later merged changes added
knowledge-primary and MQTT timing normalizers around the acceptance normalizer.
Those exact calls are legitimate composition, not removal of the probe-owner
gate. Further merged file-recovery and related coordinator work also made the
old whole-file comparisons stale. Suppressing the first assertion alone would
leave these failures and provide no proof of the current acceptance boundary.

The checker now projects both current source and its immutable reviewed snapshot
through the same existing normalizers. The compatibility expected value applies
the same feature inversion as the actual value. It never reads a mutable branch
as the baseline, copies a live expected file, removes assertions or accepts an
arbitrary diff. Exact optional normalizers recognize the separately pinned
pending iOS changes; malformed or unrelated changes still fail their contracts.

In addition to every existing acceptance assertion and four authored Swift
fixtures, compare the complete projected producer, native status recorder,
fixture files and Desktop probe checker to the reviewed snapshot BEFORE removing
the acceptance feature. This preserves the real code under the old retention
check, rather than checking only a historical or reconstructed example. Local
queue preparation still cannot fabricate remote acceptance, authenticated status
cannot reset its first acceptance clock, and source/generation/sequence/time and
terminal ownership gates remain required.

Thirteen Node test cases run only JavaScript source contracts. Twelve synthetic
mutations cover fabricated queue acceptance/completion, action/source/generation,
clock/sequence regression, terminal reactivation, probe ownership/readiness and
fixture removal. They do not execute Swift or simulate a real socket, encrypted
database, task lifecycle or device. No private reports or test evidence are stored.

## Native Status Observation Follow-up

The native-status checker had the same stale historical whole-file baseline.
Its original status-generation, sequence, observation time, task/session/profile
ownership and checked commit assertions remain. Complete projected coordinator,
status recorder, fixture and dependency sources now compare against the same
immutable reviewed snapshot. A shared helper removes duplication in the two
checkers; each checker retains its own distinct legacy projection policy.

Project and translation checks compare the exact four owned XCTest registration
lines and the single localized observation message, including their counts and
values. They no longer reject unrelated reviewed tool registrations or strings.
The repository's project structure check remains responsible for global Xcode
structure. This is not a relaxation of the owned registration or translation.

Seventeen more Node source cases exercise the actual status validator, fifteen
negative profile/journal/task/privacy/action/commit/generation/clock/effect/
fixture/registration/translation mutations, and unrelated entry coexistence.
They execute no Swift, persistence, Signal or device behavior.

## Active Observation Follow-up

The active-wake validator now uses the same immutable baseline, but retains its
own MQTT diagnostic projection and every foreground, protected-data, execution,
permission, cancellation, current task/source/generation, capacity, stage-clock
and probe-throttle assertion. Its full coordinator, timing model and fixture
source checks run before the original feature inversion. Exact pending catalog
readiness/workspace and pinned-projection normalizers apply only to their owned
files; they do not grant tools or fabricate provider readiness.

Nineteen additional Node source cases execute the active validator and reject
eighteen synthetic changes to those boundaries, including a duplicate compatibility
declaration. They never start a timer,
execute Swift or query a provider. Existing eight authored Swift wake fixtures
remain source-only, not runtime acceptance. Status-reader compatibility belongs
to this repair PR, rather than being duplicated by the deadline feature PR.

## Observation Timing Follow-up

The timing checker retains the pinned Android reference, exact 15/45/60-second
interactive and 60/90/180-second attachment windows, stage-specific anchors,
positive/nonfuture clock checks, overflow handling and four informational output
keys. Complete reviewed models, coordinator, fixture and dependency source are
checked before legacy policy/hook inversion. Existing six authored timing Swift
fixtures remain unexecuted source, not native clock acceptance.

When #4687 is present, the real timing projection lives in its separate expiry
helper. Verify that complete helper against its explicitly approved immutable
source and verify the timing call there; the pending coordinator transformation
remains separately exact. Do not claim that checking only a restored historical
coordinator proves the current helper is intact.

Eighteen further Node source cases validate the actual composed timing contract
and reject seventeen synthetic anchor/window/clock/status/output/hook/fixture
changes. The hook mutation targets the actual current helper when installed and
the original coordinator otherwise. No clock, Swift or task execution occurs.

## Native Delivery Follow-up

The native-delivery validator preserves original event/peer/topic/route/message,
managed task/source/generation, privacy and cancellation gates. It still checks
that the owned task write succeeds before completion consumption and that replay
does not refresh acceptance or overwrite newer remote progress. Complete owned
coordinator, projection, policy, fixture and transport dependency sources compare
against the immutable reviewed projection before feature inversion.

Compatibility exports in parent checker tools remain exact, while their separate
standalone validator implementations can evolve. This replaces inappropriate
whole-tool-file freezes, not the owned application or compatibility-kernel check.
Anchors include actual declaration line boundaries so source literals cannot be
mistaken for the exported function being compared.

Twenty-one Node source cases validate current delivery wiring and reject twenty
synthetic event/identity/route/task/clock/write/consume/fixture/export changes.
These are not native delivery, encrypted storage or replay acceptance tests.

All five historical validators discussed here now have explicit reviewed-source
checks. Other repository validators still require their own audits; passing
these five checks is not a full repository, native runtime or Android parity
claim. No app code, platform version, CI policy, IPA, approval or remote merge
changes are included.

## Isolated File-Read Composition

When #4704's source guard is installed, the shared projection also applies its
exact inverse for the complete reviewed single-file read entry point. Missing
guard files leave the source unchanged; unknown edits to that entry point are
rejected rather than hidden. This adds no file-reading or routing app code to
this tooling PR and makes no provider-execution claim.
