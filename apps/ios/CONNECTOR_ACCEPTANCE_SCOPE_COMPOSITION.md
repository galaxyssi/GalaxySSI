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

Other historical whole-file validators still require their own audits; passing
these two checks is not a full repository, native runtime or Android parity
claim. No app code, platform version, CI policy, IPA, approval or remote merge
changes are included.
