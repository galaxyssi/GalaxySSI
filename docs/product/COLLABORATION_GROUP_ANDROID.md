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
