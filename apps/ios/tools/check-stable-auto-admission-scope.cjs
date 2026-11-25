const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const base = 'ddcb2a69acd02ea12d20fb469e779d4d87b85a4f';
const android = 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const native = 'apps/ios/GalaxySSI/AgentNetworkRoutingModels.swift';
const source = read(native);
const insertion = '    let admittedTargetIds = decision.map { Set($0.orderedTargetIds) }\n';
const predicate = '      (admittedTargetIds?.contains($0.id) ?? true) &&\n';
assert.equal(source.split(insertion).length, 2);
assert.equal(source.split(predicate).length, 2);
assert(source.indexOf(insertion) < source.indexOf('let reasoningTargets = targets.filter'));
assert(source.indexOf(predicate) < source.indexOf('var eligible = reasoningTargets.filter'));
const shortCircuit = `    if preserveHealthyPrimary, decision == nil,
       let preferredTarget, preferredTarget.status == .available {
      let primaryDecision = routingGoal.isBlank ? nil : AgentQualityRoutingService.baselineDecision(
        goal: routingGoal, targets: [preferredTarget], primaryTargetId: preferredTarget.id,
        requirements: requirements)
      return AgentConnectorRouteSelection(target: preferredTarget, decision: primaryDecision)
    }
`;
assert(source.includes(shortCircuit));
const recoveryStart = source.indexOf('  static func mergingRoutingMetadata(');
const recoveryEnd = source.indexOf('  static func resultMetadata(', recoveryStart);
assert(recoveryStart > 0 && recoveryEnd > recoveryStart);
const autoMetadata = '      "auto_reroute_on_failure": String(action.parameters["auto_reroute_on_failure"] == "true" &&\n        action.parameters["manual_target_locked"] != "true"),\n';
const refreshStart = source.indexOf('enum AgentAutomaticConnectorRoutePolicy {');
const refreshEnd = source.indexOf('enum AgentConnectorFallbackAction {');
assert(refreshStart > 0 && refreshEnd > refreshStart);
const refreshBlock = source.slice(refreshStart, refreshEnd);
assert(refreshBlock.includes('var routed = action'));
assert(refreshBlock.includes('!AgentConnectorFallbackAction.hasActiveTrail(action)'));
assert(refreshBlock.includes('AgentPlanFactory.unavailableReasoningConnectorId'));
const normalizedRecovery = (source.slice(0, recoveryStart) + source.slice(recoveryEnd))
  .replace(refreshBlock, '').replace(autoMetadata, '');
const normalizedNetwork = normalizedRecovery.replace(insertion, '').replace(predicate, '').replace(shortCircuit, '')
  .replace('    goal: String = "",\n    preserveHealthyPrimary: Bool = false', '    goal: String = ""');
assert.equal(normalizedNetwork, git('show', `${base}:${native}`));
module.exports = { normalizedNetwork };
assert(source.includes('let preferredTarget = preferredTargetId.isEmpty ? nil : eligibleById[preferredTargetId]'));
assert(source.includes('let routedTarget = calibratedCandidates.compactMap { eligibleById[$0.resource.targetId] }.first'));
const tests = read('apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift');
for (const name of [
  'testConnectorPreferenceCannotResurrectCatalogOnlyTarget',
  'testUnavailableAdmittedTargetDoesNotFallBackToExcludedHealthyTarget',
  'testAdmittedRecoveringTargetIsNotHiddenByExcludedAvailableTarget',
  'testToolOnlyDecisionDoesNotFabricateReasoningCandidateFromCatalog',
  'testAgentConnectorRouteSelectorHonorsExplicitConnectorPreference',
  'testAgentConnectorRouteSelectorSelectsCodexWhenPhoneToolIsTopScoredResource',
  'testAgentConnectorRouteSelectorRecoversReasoningTargetDuringHeartbeat',
  'testFreshAutoFallbackIgnoresOldOrderAndPreservesAttemptAndScopeIdentity',
  'testFreshAutoFallbackRejectsUnknownAwaitingManualAndUnobservedRemoteOutcomes',
  'testFreshAutoFallbackCannotReviveExcludedDeferredTarget',
  'testAutomaticRouteRefreshKeepsRoutedParametersWhenContextIsAppended',
]) assert(tests.includes(`func ${name}(`), name);
for (const file of [
  'AgentQualityRouting.swift', 'AgentPlanRunModels.swift',
  'GalaxySSIAgentModelSelectionView.swift',
]) {
  const target = `apps/ios/GalaxySSI/${file}`;
  assert.equal(read(target), git('show', `${base}:${target}`), file);
}
const services = read('apps/ios/GalaxySSI/GalaxySSIServices.swift');
assert(services.includes('store.beginAgentAutoRouteTurn(for: message'));
assert(services.includes('preserveHealthyPrimary: true'));
assert.equal((services.match(/automaticTargetId: automaticTargetId/g) || []).length, 6);
assert.equal((services.match(/try recordAutomaticDispatch\(targetId:/g) || []).length, 7);
assert(services.includes('code: "auto_route_turn_not_committed"'));
assert(services.includes('code: "auto_route_dispatch_not_committed"'));
assert(services.includes('rememberedId: session.stableAutoRoute?.targetId ?? ""'));
assert(services.includes('return AgentConnectorFallbackAction.freshFallback(action: action, failure: failedResult,'));
assert(services.includes('recordAutomaticConnectorTarget(fallbackAction, outgoing: outgoing)'));
assert(services.includes('recordAutomaticConnectorTarget(executionAction, result: result, outgoing: outgoing)'));
assert(services.includes('connectorId: executionAction.parameters["connector_id"] ?? ""'));
assert(services.includes('let alternatives = AgentCodexSilenceRecoveryPolicy.rankedAlternatives('));
assert(services.includes('eligibleIds: eligibleIds, goal: source.content'));
assert(services.includes('if status == .queued || status == .sent { recordRecoveredAutoTarget(record) }'));
const recovered = services.slice(services.indexOf('  private func recordRecoveredAutoTarget('),
  services.indexOf('  private func scheduleCodexReplay('));
for (const token of ['binding.teamSource == nil', 'binding.managedSource == nil', '!record.isManualTargetLocked',
  'currentDesktopReplySource(binding)', 'target.trustState == .verified', 'target.connectorAgentId == binding.agentId',
  '$0.routes.clientRouteId == binding.identity.clientRouteId', 'turnId: binding.identity.turnId']) assert(recovered.includes(token));
const accepted = services.slice(services.indexOf('  private func completeAcceptedDesktopReply('),
  services.indexOf('  private func receiveJournalBackedDesktopRecovery('));
assert(accepted.indexOf('store.commitAcceptedDesktopTask(') < accepted.indexOf('recordRecoveredAutoTarget(record)'));
const remoteFile = 'apps/ios/GalaxySSI/AgentRemoteTaskStatusPolicy.swift';
const remote = read(remoteFile);
const rankStart = remote.indexOf('  static func rankedAlternatives('), rankEnd = remote.indexOf('  static func isCodex(', rankStart);
assert(rankStart > 0 && rankEnd > rankStart);
assert.equal(remote.slice(0, rankStart) + remote.slice(rankEnd), git('show', `${base}:${remoteFile}`));
assert(remote.includes('eligibleIds.contains($0.id) && $0.kind == .agent'));
assert(read('apps/ios/GalaxySSITests/AgentConnectorResponseTests.swift')
  .includes('func testCodexRecoveryRanksOnlyCurrentlyEligibleDesktopAgents()'));
assert(services.includes('let routed = refreshAutomaticConnectorAction(action, outgoing: outgoing, goal: task.goal)'));
assert(services.includes('return preparedLocalNativeAction(routed, outgoing: outgoing, task: task)'));
const prepared = services.slice(services.indexOf('  private func preparedLocalNativeAction('),
  services.indexOf('  private func recordLocalNativeBatchSummary('));
assert(prepared.includes('scopedLocalNativeExecutionAction(action, outgoing: outgoing, task: task)'));
assert(!prepared.includes('var executionAction = action'));
assert(source.includes('rememberedResourceIds: [],'));
assert(source.includes('allowed.contains($0) && permits($0)'));
assert(source.includes('failure.actionId == action.id'));
assert(source.includes('failure.metadata["plan_node_outcome_unknown"] != "true"'));
assert(source.includes('AgentConnectorHandoffRecovery.requiresRemoteObservation(metadata: failure.metadata'));
for (const file of ['AgentNativeToolActionExecutor.swift', 'AgentControlPlaneActionExecutorModels.swift']) {
  assert(read('apps/ios/GalaxySSI/' + file).includes('AgentConnectorFallbackAction.mergingRoutingMetadata('));
}
for (const file of ['AgentActionEffectExecutor.swift', 'AgentConnectorTimeoutResolver.swift']) {
  const target = 'apps/ios/GalaxySSI/' + file;
  assert.equal(read(target), git('show', `${base}:${target}`), file + ' effect/timeout kernel unchanged');
}
const sessions = read('apps/ios/GalaxySSI/GalaxySSIStoreSessions.swift');
const persistence = sessions.slice(sessions.indexOf('  private func persistAgentAutoRoute('), sessions.indexOf('  func updateAgentSessionSummary('));
assert(persistence.indexOf('guard persisted else { return false }') < persistence.indexOf('cacheAgentConversation(session)'));
assert(persistence.includes('agentConversationDatabase.saveDraft(session)'));
assert(persistence.includes('agentConversationDatabase.upsert(session)'));
assert(sessions.includes('startedAt > current.turnStartedAt'));
assert(sessions.includes('defaults: defaults).mode == .automatic'));
assert(sessions.includes('AgentStableAutoRoutePolicy.acceptsUpdate(state: session.stableAutoRoute, turnId: turnId)'));
const models = read('apps/ios/GalaxySSI/AgentConversationModels.swift');
assert(models.includes('case stableAutoRoute = "stable_auto_route"'));
assert(models.includes('try container.decodeIfPresent(AgentStableAutoRouteState.self, forKey: .stableAutoRoute)'));
const header = read('apps/ios/GalaxySSI/GalaxySSIAgentHomeHeaderPresentation.swift');
assert(header.includes('return automaticTarget?.title.ifBlank(automaticLabel) ?? automaticLabel'));
assert(!header.includes('? "Codex"'));
assert(!header.includes('return liveExecutionTargetLabel'));
assert(read('apps/ios/GalaxySSI/GalaxySSIAndroidParityUI.swift').includes(
  'automaticTarget: coordinator.displayedAutoRouteTarget(conversationId: store.activeAgentConversationId)'));
const runtimeTests = read('apps/ios/GalaxySSITests/AgentConversationRuntimeTests.swift');
const scheduled = services.slice(services.indexOf('  private func executeConversationSchedule('),
  services.indexOf('  private func reconcileConversationScheduleRuns('));
assert(scheduled.includes('guard store.beginAgentAutoRouteTurn(for: outgoing'));
assert(scheduled.indexOf('auto_route_turn_not_committed') < scheduled.indexOf('let automaticTargetId'));
assert.equal((scheduled.match(/automaticRouteSelection\(for: contact/g) || []).length, 1);
assert.equal((scheduled.match(/automaticTargetId: automaticTargetId/g) || []).length, 3);
assert.equal((scheduled.match(/try recordAutomaticDispatch\(targetId:/g) || []).length, 4);
assert(scheduled.includes('AgentConversationScheduleProvenance.verified(current), current.revision == task.revision'));
assert(scheduled.indexOf('guard ticket.allowed') < scheduled.lastIndexOf('try recordAutomaticDispatch'));
assert(scheduled.includes('AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .failed)'));
assert(runtimeTests.includes('func testStableAutoRoutePersistsExactConversationAndRejectsOldTurnsAndManualUpdates'));
assert(runtimeTests.includes('func testAutoHeaderUsesExactTargetNotOldSessionOrLiveDisplayLabels'));
assert(runtimeTests.includes('func testMessageSubmissionScopeRejectsOtherConversationOwnerAndBlankIdentity'));
const submit = read('apps/ios/GalaxySSI/GalaxySSIAgentHomeMessageSubmission.swift');
assert(submit.includes('requiredAgentConversationID: submittingConversation'));
assert(submit.includes('to: submittingContact'));
assert.equal((submit.match(/guard submissionScope.matches/g) || []).length, 3);
assert(submit.includes('guard composerSubmissionID == submissionID'));
assert(submit.includes('if draft.isEmpty, !draftForRecovery.isEmpty'));
assert(submit.includes('voicePendingAttachments.removeAndWipe(id: id)'));
assert(!submit.includes('voicePendingAttachments.wipeSensitive()'));
assert(!submit.includes('restoreAgentVoiceAttachments(sensitiveAttachments)'));
const attachmentFile = 'apps/ios/GalaxySSI/AgentConversationAttachmentContinuity.swift';
const attachment = read(attachmentFile);
const scopeStart = attachment.indexOf('struct AgentMessageSubmissionScope:');
const scopeEnd = attachment.indexOf('struct AgentAttachmentContinuityReuse {');
assert(scopeStart > 0 && scopeEnd > scopeStart);
assert.equal(attachment.slice(0, scopeStart) + attachment.slice(scopeEnd), git('show', `${base}:${attachmentFile}`));
assert(attachment.includes('owner == currentOwner && conversationId == currentConversation'));
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n');
assert.equal(files.length, 17);
const disposition = file => {
  if (file.endsWith('build.gradle.kts')) return 'Android-only version bump excluded';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Android evidence inventoried; new native admission regression source added but not executed; no live acceptance claim';
  if (file.endsWith('AgentStableAutoRoute.kt')) return 'Candidate admission, exact target ID, begin-turn and stale update guards adapted using encrypted native session payload, not a new plaintext preference store';
  if (file.endsWith('MainActivityAgentExecution.kt')) return 'Native header uses the same exact target identity as dispatch, not stale display labels or a fabricated Codex fallback';
  if (file.endsWith('AgentResourceRouter.kt')) return 'Healthy eligible displayed primary short-circuits quality/alternative ranking in native selector; existing capability admission retained, no new full capacity/privacy/budget router claimed';
  if (file.endsWith('MobileNativeAgentExecution.kt')) return 'Primary branch snapshot and parallel/synchronous pre-dispatch route refresh preserve updated action parameters and exact outgoing context; asynchronous recovery specifics still incomplete';
  if (file.endsWith('MainActivityAgentPage.kt')) return 'Composer captures owner/contact/conversation, requires that conversation at send, and rejects stale UI restoration; attachment staging/routing uses outgoing identity; no live navigation acceptance';
  if (file.endsWith('AgentConnectorFallbackAction.kt')) return 'Auto-reroute metadata propagated through actual native/control-plane executor results; manual/explicit false flags dominate; synchronous fallback uses current admitted ranking and owned attempt trail';
  if (file.endsWith('AgentConnectorHandoffRecovery.kt')) return 'Native synchronous fallback refuses unobserved remote timeout outcomes; actual pre-timeout observer/deferred asynchronous discovery remains incomplete';
  if (file.endsWith('MobileNativeAgent.kt')) return 'Existing real Desktop recovery recomputes alternative rankings within paired/verified same-Desktop eligibility and retains original retry budget. Generic timeout observer/candidate callback remains unwired; journal transport does not gain Codex replay';
  if (file.endsWith('MobileNativeAgentRuntimeTiming.kt')) return 'Native synchronous connector execution records exact selected/fallback/result target for the current conversation turn; full async/parallel/resume timing path still incomplete';
  return 'Inspected reference for broader primary identity, fresh fallback ranking, deferred recovery, attachment scope and parallel routing; not implemented or claimed by this admission increment';
};
const inventory = { androidPR: 3119, androidCommit: android, incrementalBase: base,
  scope: 'Admission, encrypted Auto identity, primary/synchronous/parallel preparation, attachment UI scope and bounded existing Desktop recovery ranking/header updates; generic connector/timeout and broader resume parity incomplete',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'), disposition: disposition(file) })) };
const report = path.join(root, 'apps/ios/ANDROID_3119_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3119: scoped Auto dispatch and bounded Desktop recovery contracts; generic connector/timeout wiring remains incomplete. Source checks only.');
