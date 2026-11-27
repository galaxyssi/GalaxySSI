# Conversational Temporary Teams (Android #4640)

Port baseline: Android PR #4640, merge `27f2e834720486e4e09a75734eb4f53ce0209961`.
Only iOS implementation, resource, project registration, test source and focused
source-check tooling are changed. This is not a port of later final-editor or
final-audit Android changes.

## User Flow

- `/team <objective>` and English/Chinese requests for temporary teams or
  independent review open a native confirmation panel. Quoted instructions,
  negation and explanatory questions are not delegation consent.
- The complete submitted objective (4000 UTF-16 units maximum), selected model,
  destination, scope and call allowance are displayed before authorization.
- An input mutation invalidates the consent epoch even if the original text is
  subsequently retyped. Attachment changes, owner/chat changes, backgrounding,
  protected-data loss and plaintext clearing also invalidate confirmation.
- Only active ordinary conversations without attachments or Agent mentions are
  accepted. Personal-health objectives are refused without echoing source text;
  private Health workflows remain separate.
- Manual model selection filters routes to that target/model. Unavailable pinned
  providers do not fall back to another model, Desktop or tool execution.
- `/team help` opens help/status; `/team stop` cancels the current conversation's
  run and prevents late publication. Chinese aliases are localization resources.

## Bounded Execution

Planning accepts 0-10 worker/reviewer/dissent roles, with at most three incoming
and outgoing dependencies. All IDs, edges and cycles are validated before any
role dispatch. The shared Skill topology validator is reused only as a graph
validator, never as a Skill executor.

At most three roles execute concurrently. Each receives only its direct parents'
public reports. Ready dependents do not wait for unrelated slow roots. Planning,
roles and synthesis share a hard 12-call budget, without automatic retries, and
120-second cooperative request deadlines. Independent dissent is appended even
if synthesis omits it. UI progress contains typed stage/index/count metadata,
not assignments, reports, objectives or raw provider errors.

The existing isolated text transport is shared with conversation goals. Team
JSON is supplied verbatim after provider request preparation, with one explicit
user payload and no history/tools. Provider credentials, endpoint fingerprints,
disclosure rules, usage budgets and local-model readiness are revalidated.
Biomedical prompts distinguish hypotheses from evidence and prohibit operational
drug engineering. Model agreement is not experimental or clinical validation.

## Persistence and Lifecycle

Jobs are encrypted with owner-scoped key material and hashed conversation keys.
Queued-to-running claims and each call reservation are persisted by compare-and-
swap before requests. Concurrent siblings bind immutable job identity, objective
and route rather than requiring an unchanged revision counter.

An uncertain running job after process/grant interruption finishes with a
generic interrupted receipt; it is never restarted automatically. Finished text
is saved before publication. Transcript publication commits synchronously through
the existing encrypted transport-incoming database API under a stable job remote
ID; only then can the terminal job retire. Publication failure keeps the saved
answer for idempotent recovery. Stopped/replaced/deleted rows reject stale results.
Conversation deletion tombstones rows; private-data reset removes job material.

iOS BGProcessing registration, foreground grace and grant-specific expiry use
the existing lifecycle pattern. Cold restoration requires a valid encrypted app
state. An old grant's expiry cannot cancel a newer foreground run. iOS scheduling
does not promise continuous execution or Android WorkManager timing.

## Verification Scope

- Focused JS source-contract checks cover command/protocol constraints,
  registration, localized resources, consent, worker authority, persistence order,
  lifecycle, deletion and reset hooks.
- 34 synthetic XCTest methods are authored across protocol (8), engine (7),
  command (8), job (5) and encrypted store (6). One shared inference test also
  covers exact team JSON payload preservation.
- Native XCTest, Swift compilation, simulator/device execution, background grant
  behavior, live providers and IPA generation have **not** been executed or
  certified. Source checks are not evidence that these runtime checks pass.
