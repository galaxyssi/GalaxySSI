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
const admissionStart = source.indexOf('enum AgentAutomaticRouteAdmission {');
assert(admissionStart > 0 && admissionStart < refreshStart);
const admissionBlock = source.slice(admissionStart, refreshStart);
for (const token of ['registration?.agentId == resource.targetId', 'active >= capacity',
  'requirements.localOnly, location == .cloud', 'requirements.dataSensitivity == .restricted',
  'AgentCapabilityRoutingPolicy.missingRequired', 'AgentTaskBudgetPolicy.evaluate(',
  'connector_calls_disabled']) assert(admissionBlock.includes(token));
assert(refreshBlock.includes('var routed = action'));
assert(refreshBlock.includes('!AgentConnectorFallbackAction.hasActiveTrail(action)'));
assert(refreshBlock.includes('AgentPlanFactory.unavailableReasoningConnectorId'));
const normalizedRecovery = (source.slice(0, recoveryStart) + source.slice(recoveryEnd))
  .replace(refreshBlock, '').replace(admissionBlock, '').replace(autoMetadata, '');
const normalizedNetwork = normalizedRecovery.replace(insertion, '').replace(predicate, '').replace(shortCircuit, '')
  .replace('    goal: String = "",\n    preserveHealthyPrimary: Bool = false', '    goal: String = ""');
assert.equal(normalizedNetwork, git('show', `${base}:${native}`));
module.exports = { normalizedNetwork };
assert(source.includes('let preferredTarget = preferredTargetId.isEmpty ? nil : eligibleById[preferredTargetId]'));
assert(source.includes('let routedTarget = calibratedCandidates.compactMap { eligibleById[$0.resource.targetId] }.first'));
const tests = read('apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift');
for (const name of [
  'testAutoAdmissionRejectsFullPrimaryBeforeStablePreference',
  'testAutoAdmissionRetainsExplicitPrivacyNetworkAndProviderRestrictions',
  'testAutoAdmissionUsesExactRegistrationCapabilitiesAndTrust',
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
assert.equal((services.match(/let targets = automaticRoutingTargets\(goal: goal\)/g) || []).length, 3);
const primary = services.slice(services.indexOf('  private func automaticRouteSelection('),
  services.indexOf('  private func selectedLocalModel('));
assert(primary.includes('let preferredTargetId = (store.agentSession(id: conversationId)?.stableAutoRoute?.targetId ?? "")'));
assert(primary.includes('preferredTargetId: preferredTargetId, goal: goal, preserveHealthyPrimary: true'));
assert(!primary.includes('AgentStableAutoRoutePolicy.displayedTarget(targets: targets'));
const admissionCaller = services.slice(services.indexOf('  private func automaticRoutingTargets('),
  services.indexOf('  private func automaticRouteSelection('));
for (const token of ['AgentAutomaticRouteAdmission.targets(', 'registrations: callableAgentRegistrations(targets: targets)',
  'AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)', 'budget: store.agentTaskBudget',
  'probe.networkPresent && probe.internetCapable && probe.validated',
  'connectorCallsAllowed: store.agentSafetySettings.connectorCallsAllowed']) assert(admissionCaller.includes(token));
assert.equal((services.match(/automaticTargetId: automaticTargetId/g) || []).length, 9);
assert.equal((services.match(/try recordAutomaticDispatch\(targetId:/g) || []).length, 8);
assert(services.includes('code: "auto_route_turn_not_committed"'));
assert(services.includes('code: "auto_route_dispatch_not_committed"'));
assert(services.includes('rememberedId: session.stableAutoRoute?.targetId ?? ""'));
assert(services.includes('return AgentConnectorFallbackAction.freshFallback(action: action, failure: failedResult,'));
assert(services.includes('recordAutomaticConnectorTarget(fallbackAction, outgoing: outgoing)'));
assert(services.includes('recordAutomaticConnectorTarget(executionAction, result: result, outgoing: outgoing)'));
assert(services.includes('connectorId: executionAction.parameters["connector_id"] ?? ""'));
assert(services.includes('let alternatives = AgentCodexSilenceRecoveryPolicy.rankedAlternatives('));
assert(services.includes('eligibleIds: eligibleIds, goal: source.content'));
assert(services.includes('targets: automaticRoutingTargets(goal: source.content)'));
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
const providerFile = 'apps/ios/GalaxySSI/AgentControlPlaneActionExecutorModels.swift';
const providerText = read(providerFile);
const validationStart = providerText.indexOf('    if awaitingResponse {\n      let generation = Int64(');
const validationEnd = providerText.indexOf('    var waitingIdentity:', validationStart);
assert(validationStart > 0 && validationEnd > validationStart);
const waitValidation = providerText.slice(validationStart, validationEnd);
for (const token of ['sourceMessageId > 0, result.actionId == item.action.id',
  'AgentRemoteOutcomePolicy.validGeneration(generation)', 'invalid_connector_wait_receipt',
  'metadata["conversation_id"]', 'metadata["turn_id"]', 'metadata["task_id"]']) assert(waitValidation.includes(token));
const trackingStart = providerText.indexOf('      do {\n        try managedResponseLedger.register(');
const trackingCatch = `      } catch {
        return failUntrackedDispatch(result, actionId: item.action.id, request: request, registration: item.registration,
          code: "connector_response_tracking_unavailable")
      }
`;
const catchStart = providerText.indexOf(trackingCatch, trackingStart);
assert(trackingStart > 0 && catchStart > trackingStart);
const trackingBlock = providerText.slice(trackingStart, catchStart + trackingCatch.length);
const oldTracking = providerText.slice(trackingStart + '      do {\n'.length, catchStart)
  .split('\n').map(line => line.startsWith('  ') ? line.slice(2) : line).join('\n')
  .replace('      try managedResponseLedger.register(', '      try? managedResponseLedger.register(')
  .replace('      try AgentManagedConnectorResponseRegistry.shared.register(', '      try? AgentManagedConnectorResponseRegistry.shared.register(');
assert(oldTracking.indexOf('managedResponseLedger.register(') < oldTracking.indexOf('AgentManagedConnectorResponseRegistry.shared.register('));
const failureStart = providerText.indexOf('  private func failUntrackedDispatch(');
const failureEnd = providerText.indexOf('  private func terminalDelivery(', failureStart);
assert(failureStart > 0 && failureEnd > failureStart);
const trackingFailure = providerText.slice(failureStart, failureEnd);
for (const token of ['metadata["effect_outcome_unknown"] = "true"', 'metadata["non_retriable"] = "true"',
  'metadata["awaiting_response"] = "false"', 'metadata["completion_verified"] = "false"',
  'metadata["provider_failure_attribution"] = "local_transport"', 'activeByRunId.removeValue(forKey: request.runId)',
  'success: false', 'type: .runFailed']) assert(trackingFailure.includes(token));
for (const forbidden of ['globalRunSlots.release(', 'terminalDeliveryStore.mark(', 'managedResponseLedger.removeOwner('])
  assert(!trackingFailure.includes(forbidden));
const normalizedProvider = providerText.replace(waitValidation, '').replace(trackingBlock, oldTracking)
  .replace(trackingFailure, '');
assert.equal(normalizedProvider.replace('    var result = AgentConnectorFallbackAction.mergingRoutingMetadata(\n      delegate.execute(action: item.action, screen: item.screen), action: item.action)',
  '    var result = delegate.execute(action: item.action, screen: item.screen)'), git('show', `${base}:${providerFile}`));
module.exports.normalizedProvider = normalizedProvider;
const dispatchTests = read('apps/ios/GalaxySSITests/AgentControlPlaneActionExecutorTests.swift');
assert(dispatchTests.includes('func testConnectorTrackingFailureIsUnknownNonRetriableAndNotRedispatched('));
assert(dispatchTests.includes('func testMalformedQueuedConnectorReceiptCannotBecomeCompletedOrWaiting('));
for (const name of ['testNativeConnectorWaitRoundTripsAndOnlySettlesExactCommittedOwner',
  'testNativeConnectorQueueCannotProjectSuccessfulToolCompletion',
  'testNativeConnectorWaitRejectsMissingScopeAndUntrackedFailureCannotReroute']) assert(dispatchTests.includes('func ' + name + '('));
assert(source.includes('failure.metadata["effect_outcome_unknown"] != "true"'));
assert(source.includes('failure.metadata["non_retriable"] != "true"'));
for (const file of ['AgentActionEffectExecutor.swift', 'AgentConnectorTimeoutResolver.swift']) {
  const target = 'apps/ios/GalaxySSI/' + file;
  const current = file === 'AgentActionEffectExecutor.swift' ? read(target).replace(
    '    guard let claim = store.observe(key) else { return nil }',
    '    guard let claim = store.observe(key), claim.result != nil else { return nil }') : read(target);
  assert.equal(current, git('show', `${base}:${target}`), file + ' only read-only pending-claim observation changes; execution/timeout kernels unchanged');
}
const taskStore = read('apps/ios/GalaxySSI/GalaxySSIStore.swift');
assert.equal(taskStore.replace('    commitOwnedAgentTaskState(expected: expected, updated: updated)\n  }\n\n  func commitOwnedAgentTaskState(expected: AgentTaskRecord?, updated: AgentTaskRecord) -> Bool {\n', ''),
  git('show', `${base}:apps/ios/GalaxySSI/GalaxySSIStore.swift`), 'Existing guarded task snapshot save/rollback body and other Store code unchanged');
const resolverFile = 'apps/ios/GalaxySSI/AgentConnectorResponseResolver.swift';
const resolver = read(resolverFile);
const continuationStart = resolver.indexOf('enum AgentNativeConnectorContinuation {');
const continuationEnd = resolver.indexOf('struct AgentConnectorResponseSettlement:');
assert(continuationStart > 0 && continuationEnd > continuationStart);
assert.equal(resolver.slice(0, continuationStart) + resolver.slice(continuationEnd), git('show', `${base}:${resolverFile}`));
for (const token of ['record.matchesCommittedResult(response)', 'record.ownerRunId == pending.metadata["control_plane_run_id"]',
  'response.contactId == record.contactId', 'response.executionGeneration == record.executionGeneration',
  'AgentControlPlaneActionExecutor.stableRunId(', 'outgoing.contactId == "hermes"',
  'waiting.status = .waitingResponse']) assert(resolver.includes(token));
const waitHost = services.slice(services.indexOf('  private func retainWaitingNativeConnector('),
  services.indexOf('  private func finishLocalNativeAction('));
for (const token of ['store.commitOwnedAgentTaskState(expected: previous, updated: updated)',
  'managedDesktopReplyLedger.recoveryRecord(owner: run)', 'store.persistedMessage(id: sourceID, contactId: "hermes")',
  'store.commitOwnedAgentTaskState(expected: previous, updated: task)', 'AgentNativeConnectorContinuation.settle(',
  'PhoneExecutionAuthority.isCancelled', 'session.mergedIntoConversationId.isBlank']) assert(waitHost.includes(token));
assert(waitHost.indexOf('store.commitOwnedAgentTaskState(expected: previous, updated: task)') < waitHost.indexOf('finishLocalNativeAction('));
const finishHost = services.slice(services.indexOf('  private func finishLocalNativeAction('), services.indexOf('  private func updateActiveNativePlan('));
assert(finishHost.indexOf('result.metadata["awaiting_response"] == "true"') < finishHost.indexOf('updateActiveNativePlan('));
assert(services.includes('nativeConnectorResponseToken = AgentLateManagedResponseBus.shared.addListener'));
assert(services.includes('!AgentNativeConnectorContinuation.hasWaitingAction(task),'));
const dispatchHost = services.slice(services.indexOf('  private func executeLocalNativeAction('),
  services.indexOf('  private func refreshAutomaticConnectorAction('));
assert(dispatchHost.indexOf('observedConnectorDispatch(action: original)') < dispatchHost.indexOf('refreshAutomaticConnectorAction('));
assert(dispatchHost.indexOf('checkpointNativeConnectorDispatch(executionAction') < dispatchHost.indexOf('runtime.actionExecutor.execute('));
assert(dispatchHost.indexOf('checkpointNativeConnectorDispatch(fallbackAction') < dispatchHost.indexOf('runtime.actionExecutor.execute(action: fallbackAction'));
const projectionFile = 'apps/ios/GalaxySSI/AgentRecordedExecutionEvidence.swift';
const projected = read(projectionFile);
assert.equal(projected.replace('    let awaiting = metadata["awaiting_response"] == "true"\n', '')
  .replace('} else if unknown || awaiting {', '} else if unknown {')
  .replace('receipt.success && !unknown && !awaiting', 'receipt.success && !unknown')
  .replace('    if awaiting { output["awaiting_response"] = .bool(true) }\n', ''), git('show', `${base}:${projectionFile}`));
assert.equal(read('apps/ios/GalaxySSI/AgentTaskBudgetModels.swift'),
  git('show', `${base}:apps/ios/GalaxySSI/AgentTaskBudgetModels.swift`),
  'Reuse current explicit network/provider policy; do not restore old telemetry counter cutoffs');
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
const review = services.slice(services.indexOf('  private func shortcutReviewPlanner('),
  services.indexOf('  private func continueObservedNativeOutcomeReview('));
assert(review.includes('let needsAutomaticRoute = task.plannerSnapshot == nil && contact.id == "hermes"'));
assert(review.includes('guard store.beginAgentAutoRouteTurn(for: outgoing'));
assert(review.includes('if let existing = task.plannerSnapshot {\n      snapshot = existing'));
assert.equal((review.match(/automaticRouteSelection\(for: contact/g) || []).length, 1);
assert.equal((review.match(/automaticTargetId: automaticTargetId/g) || []).length, 3);
assert(review.indexOf('AgentEffectRecoveryRecord.permitsReviewProvider(') < review.indexOf('try recordAutomaticDispatch('));
assert(review.includes('if needsAutomaticRoute {\n      guard let automaticTargetId, !automaticTargetId.isEmpty'));
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
  if (file.endsWith('AgentResourceRouter.kt')) return 'Live exact-ID registration/global-slot capacity, privacy/capability and explicit provider/network budget admission precedes stable primary selection and fresh synchronous fallback. Current telemetry-only counters retained; full scored/circuit-health/failure-domain router remains incomplete';
  if (file.endsWith('MobileNativeAgentExecution.kt')) return 'Primary branch snapshot and parallel/synchronous pre-dispatch route refresh preserve updated action parameters and exact outgoing context; asynchronous recovery specifics still incomplete';
  if (file.endsWith('MainActivityAgentPage.kt')) return 'Composer captures owner/contact/conversation, requires that conversation at send, and rejects stale UI restoration; attachment staging/routing uses outgoing identity; no live navigation acceptance';
  if (file.endsWith('AgentConnectorFallbackAction.kt')) return 'Auto-reroute metadata propagated through actual native/control-plane executor results; manual/explicit false flags dominate; synchronous fallback uses current admitted ranking and owned attempt trail';
  if (file.endsWith('AgentConnectorHandoffRecovery.kt')) return 'Native synchronous fallback refuses unobserved remote timeout outcomes; actual pre-timeout observer/deferred asynchronous discovery remains incomplete';
  if (file.endsWith('MobileNativeAgent.kt')) return 'Existing real Desktop recovery recomputes alternative rankings within paired/verified same-Desktop eligibility and retains original retry budget. Generic timeout observer/candidate callback remains unwired; journal transport does not gain Codex replay';
  if (file.endsWith('MobileNativeAgentRuntimeTiming.kt')) return 'Native synchronous connector execution records exact selected/fallback/result target for the current conversation turn; full async/parallel/resume timing path still incomplete';
  return 'Inspected reference for broader primary identity, fresh fallback ranking, deferred recovery, attachment scope and parallel routing; not implemented or claimed by this admission increment';
};
const inventory = { androidPR: 3119, androidCommit: android, incrementalBase: base,
  scope: 'Live admission and encrypted Auto identity; scoped primary/synchronous/parallel/scheduled preparation; native queued receipt tracking/committed-owner continuation and read-before-reroute recovery; attachment UI scope and bounded Desktop recovery; full scored router, generic app connector producer, asynchronous failover/timeout and broader resume parity incomplete',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'), disposition: disposition(file) })) };
const report = path.join(root, 'apps/ios/ANDROID_3119_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3119: scoped Auto dispatch and bounded Desktop recovery contracts; generic connector/timeout wiring remains incomplete. Source checks only.');
