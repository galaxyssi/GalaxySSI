# Assessment draft preflight

The collaboration tool accepts `mode=validate_assessment` and an `artifact`
containing the exact goal-assessment JSON string. This is a diagnostic operation,
not a publication, planning commit or evidence endorsement.

## Contract

- Android runs `CollaborationAssessmentValidation.inspect`, the same field and
  qualified-validator parser used at final admission. There is no weaker duplicate
  validator in Desktop.
- Valid tool execution returns `success=true` independently of `schema_valid`.
  Invalid drafts include syntax state and the exact failing field, reason and
  expected constraint. The response hashes the original draft without rewriting it.
- A valid draft still requires preserved-contract, dependency graph, permission,
  evidence and goal-acceptance checks during actual admission. These unchecked
  dimensions are explicitly named in the response.
- The call does not write workspace rows, enroll a publication, finish an
  assignment, accept a goal or schedule model work. An active coordinator can
  inspect a draft without gaining interim-publication authority.
- Existing assignment identity, execution generation, expiry, pause, membership
  and retirement guards remain in force. The model cannot select another member.
- The existing 128 KiB tool envelope bound remains. Transport failure means the
  check was unavailable, not that a plan was submitted or accepted.

The existing executable-case contract now explicitly advertises its requirement
for at least one target and one regression case; edge cases do not replace a
regression case. The requirement itself is unchanged.

## Verification

`CollaborationAssessmentPreflightTest` checks same-turn repair, canonical validator
parity, syntax versus field errors, zero workspace mutation, no authority grant,
pause/revocation, strict arguments and the existing envelope bound.
`CollaborationMilestoneProtocolTest` checks the authenticated request envelope and
tool advertisement across supported cloud providers. Desktop bridge tests check
exact draft forwarding, scoped replies, failure guidance and nonterminal progress.

`CollaborationAssessmentPreflightDeviceTest` exercises the production Context
handler with a dedicated temporary group and no model or network call. It checks
repair, repeated results, reopened workspace state, pause/resume and membership
revocation, then removes its own data. This is not a process-restart or live model
collaboration acceptance test.

Engineering tests alone do not establish fewer model calls, better methods,
peer-driven revision, transfer or retained capability. Those require separately
recorded real-model acceptance and independent outcome evaluation.

## Local verification on 2026-10-11

- Android: 54 focused unit tests, zero failures/errors/skips; debug and test APKs built.
- S20U SM-G9880: Android 1.4.143 / 1228 installed and read back; the new preflight
  device test and the existing exchange-replay device test passed (2 tests).
  Both use local synthetic records, not a live broker or model.
- Desktop: 55 bridge/recovery tests passed. The first structure suite run had one
  VM timeout during Android compilation (67/68); the unchanged suite passed 68/68
  after compilation, without increasing a timeout or weakening checks.
- Repository structure, text and Kotlin source-size gates passed.

No new real-model trial was run to validate this increment. Earlier failed
collaboration outcomes remain failed; this diagnostic change does not rewrite them.
