# Android Collaboration Groups

## Scope

This increment implements the persistent digital-person roster and the approved
member-picker, collaboration-settings, per-member execution and result views.
It uses the existing Android composer, rich output, encrypted transcript, team
runtime, connector delivery and task completion paths. It does not simulate
human membership or imply that a contact grants access to another device.

Entry points are the conversation list's new-conversation menu and the settings
footer in the existing `@` picker. A group retains its member roster, stable
instance identities, coordinator, roles, provider/model choice, participation
settings and independent-review preference.

## Identity And Resources

- A member UUID is independent of the provider ID, name and model ID.
- Multiple members may use one provider without sharing a member Run identity.
- Changing a provider keeps the member UUID and role. Existing task snapshots
  preserve the provider and name used by that task.
- The packaged catalog contains 1,024 unique English names. The initial surname
  inspiration is the public Codex agent-name catalog at
  <https://github.com/openai/codex/blob/main/codex-rs/core/assets/agent/agent_names.txt>;
  additional English name combinations complete the pool. Names are labels,
  not impersonations or claims of affiliation.
- A roster supports 1,024 members; this is not a concurrency claim. The current
  host accepts at most 12 selected members in an execution batch and validates
  provider capacity. Larger selections are rejected visibly, never truncated.
- Automatic execution includes members following sent group messages whose
  participation is not mention-only. Explicit mentions select stable members.
  Draft text is never dispatched before the existing send action.

## Execution And Transcript

The compiler retains each selected member's identity, role and model. The
coordinator synthesizes after specialist dependencies terminate. The existing
single completion receipt still determines whether the parent task has ended.
Host-managed member dispatch prioritizes the compiled assignment prompt over the
shared user goal, preserving member identity and dependency evidence for both
cloud models and remote connectors. Ordinary chat prompt selection is unchanged.
The group-created persistence marker is excluded from process rendering, so
configuring a roster does not start a processing timer.

Opt-in collaboration groups additionally project public member lifecycle and
result events into encrypted PROCESS transcript rows with typed metadata.
These rows bypass ordinary process collapsing and cannot complete the parent
task. Results use content-addressed keys: retries deduplicate, while corrected
results append rather than replace earlier evidence. The rich-output renderer
is reused for member result text. When a member result duplicates the canonical
coordinator answer, presentation retains the canonical answer's identity and rich
deliverables and adds the member header. Files, images and structured tables remain
visible, and existing reply actions retain their original response identity.

Projection is event-driven and cached. No per-member timer or background model
polling is introduced. UI projection failures do not block the final delivery
path. Existing non-group teams retain their background-only presentation.

### Separate Conversation Pages

Collaboration and ordinary Agent conversations now have separate RecyclerViews,
adapters and presentation policies. They share the composer, rich result widgets
and execution runtime, not the ordinary conversation's process aggregation.
The collaboration page has no global elapsed-time or search-summary row. Member
headers and result content use the full output width. A successful member has no
standalone completed-status row; its public activity and sources remain available
under the result's expandable process entry. Failure and approval messages remain
visible. Switching back to an ordinary conversation restores its existing page.

Before member dispatch, the host persists an exact source/conversation/turn to
member/run binding. Authenticated Desktop events and cloud tool events use that
binding for transcript activity and per-member research traces. Two members using
one provider cannot overwrite one another's search. Duplicate progress updates
are deduplicated locally; this does not add transport polling or control messages.

### Ambiguity And Goal Boundaries

Explicit group roles take precedence over provider-inferred software roles.
Specialists receive differentiated contribution scopes. They must choose and state
reversible low-risk assumptions, define verifiable acceptance criteria, and perform
useful work instead of stopping at a clarification questionnaire. The coordinator
owns unresolved assumptions and evidence gaps and may continue researching and
checking within its existing model/tool run.

This policy is not a new unbounded autonomous replanning scheduler. A successful
provider response is not proof that a physical or long-term goal is achieved.
Missing authorization, equipment, experimental evidence or other real resources
must be reported as concrete blockers, never invented. Existing cancellation,
permissions, resource budgets and terminal failure handling remain effective.

## Messages And Review Boundaries

Committed member results may be delivered through the existing `team.v1`
mailbox to opted-in active peers. Deterministic message IDs deduplicate replay.
The coordinator already receives dependency evidence, so it is excluded from
duplicate peer-result fanout. Independent reviewers do not receive peer answers
during their first assignment. Current membership/settings are rechecked before
new peer delivery; deleted groups cannot be resurrected by transcript projection.

Running group follow-ups use the existing reliable team-message path instead of
cancelling the team. Receipts distinguish queued and delivered updates. Delivery
does not imply that a model has acted on the update. Providers without in-flight
steering retain pending messages; this does not guarantee a subsequent checkpoint
will exist. Attachments and explicit control commands retain the existing paths.

## Explicitly Not Claimed

- Cross-device human membership, invitations and revocable group permissions.
- 1,024 concurrently executing models or automatic thousand-member batching.
- Separate long-term private memory, knowledge and Skill libraries per person.
- Autonomous post-completion debate, unrestricted self-triggered conversations,
  or a model-independent pause/resume guarantee for every provider.
- Real laboratory validation of the protein-research example in the design.

These require further protocol, scheduler and permission work. The interface
does not create simulated people or successful invitations for those features.

## Deep Research Workflow

Group settings offer Auto, Parallel and Deep Research. Auto keeps ordinary
questions on the existing lightweight path; research/design requests with at
least a coordinator and two researchers use a host-owned dependency graph:

Brief -> independent exploration -> cross-challenge -> proposal revision ->
combine alternatives -> parallel validation -> repair -> recheck -> delivery.

Researchers receive distinct exploration paths, not just different names. Initial
exploration depends only on the common brief. Cross-review names a different
researcher's artifact and requires a concrete objection, repair and test. The
coordinator may preserve up to three alternatives; validators are assigned by
candidate, and the final answer compares surviving options rather than forcing
a single winner. Model-reported checks are not host-certified experimental facts.

Six researchers plus one coordinator produce 34 execution nodes, while live
model concurrency remains at the existing three-worker limit. This release
supports 3-12 people in the deep workflow and at most 64 graph nodes. It performs
one bounded repair/recheck cycle, not an endless autonomous research process.
Existing cancellation, reliable delivery and provider failure rules still apply.
Failed branches remain visible to subsequent review and final delivery.

Structured artifacts contain public summaries, candidates, findings, unresolved
questions, targeted requests and important memory items. Originals are preserved
before bounded handoffs. Unstructured responses are explicitly marked unverified,
not silently converted into successful checks. Member rows render public summaries,
not the artifact JSON or hidden reasoning.

### Directed Discussion

A member may address up to three specific peers per request using stable member
IDs. Requests travel through the existing durable team mailbox with deterministic
deduplication. They remain visible under the sender's contribution but wake no
unbounded conversation loop. Recipients consume them at later stage checkpoints,
after independent exploration. Queued/delivered does not prove a model has
answered; requests after the last useful checkpoint can remain unresolved.

### Long-Lived Group Evidence

Completed worker results and assignment contexts are appended to a group-scoped,
encrypted knowledge database. Content-derived IDs make replay idempotent without
overwriting earlier versions. Records retain the full raw output, author, provider,
model, stage, goal, dependency IDs and delivered inbox. They are not pruned by
prompt compression. The existing keyed full-text index supports retrieval without
opening all historical bodies on every model request.

The working prompt contains a bounded relevant subset, including model-reported
constraints, decisions, rejected routes and open questions. Superseding references
preserve the earlier record; they are claims to review, not automatic destructive
updates. Search never claims to cover all history.

The read-only native tool `galaxyssi.phone.collaboration.recall` supports:

- Ranked search of this group's historical records.
- Paged history-directory browsing, including records outside search's top results.
- Full-original reads in 8,000-character pages with an explicit next offset.

The caller's host-bound conversation and turn determine access, not a model-supplied
group ID. Other groups and personal memories are unavailable. Current-turn
proposals remain isolated from this recall channel; they are shared by explicit
graph dependencies and directed messages. Deleting the group deletes this derived
archive as well. There is no additional network polling.

This is not a claim of perfect recall or a months-long endurance result. Historical
conversations are not backfilled automatically, and raw tool logs/attachment bytes
are still governed by their existing stores. Retrieval can miss evidence; members
must state missing context and recover originals before relying on an old decision.
External backups and export coverage need separate acceptance before users rely on
this store as their only durable research archive.

The design draws on [Anthropic's research architecture](https://www.anthropic.com/engineering/multi-agent-research-system),
[explicit group speaker selection](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/selector-group-chat.html),
and [task-dependent multi-agent scaling evidence](https://arxiv.org/abs/2512.08296v3).
Synergy must be evaluated against a single agent at equal total budget; adding
stages or people alone is not evidence of a quality improvement.

## Verification

`CollaborationGroupTest`, `AgentTeamPlanBridgeTest`,
`AgentCollaborationRuntimeTest` and `AgentTranscriptRenderPolicyTest` cover names,
stable identity, settings round-trip, scope, independent review, deduplication,
task compilation, state updates and existing runtime regressions.

`CollaborationGroupDeviceTest` checks the Android member picker, settings,
historical restoration and member rows. Its real Codex/DeepSeek test is opt-in:
pass instrumentation argument `collaborationReal=true`. It creates and removes
only a dedicated acceptance conversation; screenshots and a content-free status
report remain in the device's external app files for inspection.

### Local Acceptance, 2026-10-01

- Android 1.4.5 (1090): source, built APK and S26U installed version agree;
  70 focused JVM tests passed.
- Two S26U instrumentation tests passed in a combined 51.75 seconds: member
  picker with the keyboard open, settings save, collapsed progress, roster
  restoration after Activity recreation, and real Codex/DeepSeek execution.
- Both real members returned the correct arithmetic result and their own member
  names. Curie delivered an independent contribution; Turing synthesized it.
  The test waited for the canonical final answer, not just member completion.
  Stable screenshots were inspected; existing reply actions remained available.
- Earlier real execution on 1.4.2 continued to completion when the phone locked.
  This is background continuity evidence, not a process-death recovery test.
- Initial UI attempts were invalidated by lock screen/startup timing. The test
  now waits for hydration and the actual foreground page, and captures screenshots
  after transitions settle. These earlier attempts are not counted as passes.
- Repository-wide `npm run check` encounters existing i18n-policy violations.
  The focused policy scan found 354 violations, none in this change's files.
  Kotlin source-size validation and `git diff --check` passed.

Generated screenshots, device reports, credentials and APKs are not repository
artifacts. The acceptance fixture removes only its own conversation.

### Separate-Page Acceptance, 2026-10-01

- Android 1.4.6 (1091): 80 focused JVM tests passed, including nine dedicated
  page-projection cases. Debug app and instrumentation APK builds passed.
- Three S26U device tests passed in 61.798 seconds: picker/settings/history,
  same-provider member search isolation and page switching, and real Codex/DeepSeek
  execution. The isolation fixture also verifies duplicate event suppression,
  rejected cross-turn events, retained search history after completion and Activity
  recreation, removal of completed-status rows, and distinct page adapters.
- Actual member/result screenshots were inspected for full-width left alignment
  and absence of a global timer. The real arithmetic run returned both members'
  correct contributions and the canonical coordinator result.
- Opt-in `collaborationResearch=true` runs a separate real official-documentation
  research task with unspecified business details. Its report contains only that
  dedicated fixture's outputs; it is never committed to the repository.

### Research and Archive Acceptance, 2026-10-01

- Android 1.4.8 (1093): source, built APK and S26U installed version agree.
  App and instrumentation builds succeeded; 139 focused JVM tests passed with
  no failures or skips. They include graph construction, blind exploration,
  separate candidate validation, directed message scope and deduplication,
  malformed artifact handling, native tool registration and parent recovery.
- Four device regressions passed on 1.4.8 in 29.883 seconds: member settings and
  history, page/search attribution, full-original recall, and versioned history.
  The three opt-in real-model tests were skipped in this regression invocation;
  the runner's `OK (7 tests)` must not be reported as seven executed passes.
- The archive fixture verifies a marker outside the short summary in an original
  over 18,000 characters, exact reconstruction through paged native-tool reads,
  current-turn isolation and cross-group denial. A second fixture preserves 65
  versions, including superseded claims, and reaches records beyond the ranked
  search window through history pagination. This is not a months-long test or
  a measurement of real-model semantic recall quality.
- A prior real Codex/DeepSeek official-documentation task passed in 117.435
  seconds on 1.4.6. It retained member-attributed sources and distinguished
  proposed tests from tests actually run.
- The first deep-workflow attempt on 1.4.7 exposed a routing defect: a negated
  phone-operation phrase selected the ordinary supervised-phone path. Version
  1.4.8 adds a group-bound routing seed without changing genuine phone-control
  requests. The rerun created the intended 14-node graph.
- The real 1.4.8 run completed the brief, both independent explorations, both
  cross-challenges, both revisions, combination and one verification. A second
  verification was running when the 600-second graph acceptance window expired;
  repair, recheck and final delivery were not accepted. The fixture cancelled
  only its own team and removed its dedicated conversation.
- Desktop confirmed that combination finished in 276.984 seconds with two
  distinct, valid arithmetic partitions. The incomplete acceptance is therefore
  not evidence of a lost combination reply, but it remains a failed full-flow
  test. No end-to-end performance or equal-budget synergy claim is made.
- Kotlin source-size policy passed. The i18n policy still reports 354 pre-existing
  violations and none in this change's files; the repository-wide gate is not
  green. No unrelated policy exceptions were added.

### Remaining Long-Term Acceptance

Group visibility means permission to retrieve shared records, not that every
request includes the complete transcript. Prompt summaries are replaceable views;
the archive originals and their references are the durable evidence. Neither a
model-authored memory item nor a superseding claim proves that a fact is correct.

Before claiming reliable months-long team memory, add acceptance for historical
chat backfill, attachment/tool-evidence retention, encrypted export and restore,
critical-constraint coverage, contradictory dated decisions, and real-model
cross-turn recall through both cloud and remote Agent paths. Test missing recall
explicitly: a member must report unavailable evidence instead of inventing the
contents of an old discussion. The current archive does not replace these checks.
