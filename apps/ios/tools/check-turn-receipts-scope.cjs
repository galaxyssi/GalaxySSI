// Wiring/retention contracts, not native rendering, provider or timing execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '60529d22ae941e0ef20a27c8c4b386fc681fc13a';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function has(name, tokens) { const s = read(app + name + '.swift'); for (const token of tokens) assert(s.includes(token), name + ': ' + token); return s; }
function validate() {
  has('AgentTurnReceipt', ['range.lowerBound == text.startIndex, range.upperBound == text.endIndex',
    'AgentDesktopReplyRecovery.integer(value, minimum: minimum)', 'prefix(128)', 'prefix(256)',
    'integer($0["generation"], minimum: 1) == generation', 'provider:\\(task):\\(attempt - 1)',
    'integer(meta["execution_generation"] ?? NSNumber(value: 1), minimum: 1) == generation',
    'attempt >= Int64(best)', 'identifier(replay["provider"])']);
  const store = has('AgentTurnReceiptStore', ['NSRecursiveLock()', 'keyMaterialKey: Self.materialKey',
    'data.count <= 16_384', 'key.prefix + "deleted"', 'guard var row = read(key)',
    '!GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key.row)',
    'uptime >= observation.started', '(uptime - observation.started) / 1_000_000', 'order.count >= 256',
    '$0.taskSHA == AgentTurnReceiptEvidence.hash(task)', 'evidence.generation > ($0.generation ?? 0)',
    '$0.generation == evidence.generation', '$0.cloudAttempt == attempt',
    'result.receipt.status == result.status, !result.receipt.replayed',
    'result.provenance.toolId == tool, result.receipt.invocationId == context.invocationId',
    'live[key] != nil', 'GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.materialKey']);
  for (const token of ['headers', 'bodyJson', 'providerReasoning', 'request.messages', 'inputSha256', 'result.output']) assert(!store.includes(token), token + ' must not be stored');
  has('GalaxySSIStore', ['turnReceiptStore.invalidateLive()', 'turnReceiptStore.clear()',
    'turnReceiptStore.begin(key, choice: AgentModelSelectionSettings.selection(', 'uptime: receiptUptime']);
  has('GalaxySSIStoreSessions', ['turnReceiptStore.delete(owner: profile.identityFingerprint, conversation: id)']);
  has('GalaxySSIServices', ['runtime.registry.resultObserver = { tool, context, result in',
    'context: context, tool: tool, result: result)',
    'store.turnReceiptStore.outbound(key, task: taskIdentity.taskId, model: invocation.string("model_id")',
    'object.string("scheme") == "signal", taskIdentityStore.matchesRegistered(payload: appPayload)',
    'store.turnReceiptStore.authenticated(key, payload: appPayload)',
    'store.turnReceiptStore.localModel(key, profile: result.profileId)',
    'store.turnReceiptStore.localModel(key, profile: actual)']);
  const registryFile = app + 'AgentNativeToolExecutionModels.swift';
  const registry = read(registryFile).replace('  var resultObserver: ((String, AgentNativeToolInvocationContext, AgentNativeToolResult) -> Void)?\n', '')
    .replace('      resultObserver?(id, effectiveContext, result)\n', '');
  assert.equal(registry, old(registryFile), 'Registry authority/replay/verification logic retained exactly');
  has('AgentTurnReceiptModelObservation', ['store.cloudStarted(key, model:', 'completed.requestId == request.requestId',
    'capture.response(attempt, model: completed.reportedModel)', 'for try await event in base.stream(request)',
    'await base.cancel(requestId: requestId, reason: reason)']);
  has('CloudConversationStreamEngine', ['AgentTurnReceiptStreamClient(base: streamClient, capture: receiptCapture)', 'observedClient.stream(roundRequest)']);
  has('CloudConversationNonStreamingToolEngine', ['receiptCapture?.started(roundRequest)',
    'model: response.reportedModel, effort: response.reportedEffort', 'object["modelVersion"] as? String']);
  has('CloudModelNativeToolAdapter', ['modelRequest.conversationId, turn: modelRequest.turnId',
    'capture?.response(attempt, model: object["model"] as? String', 'effort: object["reasoning_effort"] as? String']);
  has('CloudModelAgentPlanningProvider', ['AgentTurnReceiptStreamClient(base: URLSessionCloudModelStreamClient(), capture: capture)',
    'repairCapture.store.cloudStarted(repairCapture.key, model: repairCapture.requestedModel)']);
  has('LocalModelAgentPlanningProvider', ['receiptStore?.localModel(', 'profile: result.profileId)']);
  assert.equal((read(app + 'AgentModelPlannerContactResolver.swift').match(/receiptStore: store.turnReceiptStore, receiptOwner: store.profile.identityFingerprint/g) || []).length, 4);
  const probe = has('AgentTurnReceiptVisibilityProbe', ['override func draw(', 'frame.timestamp > drawnAt',
    'frame.timestamp > visibleAt', 'window.isKeyWindow', '.foregroundActive', 'current.clipsToBounds',
    'visible.width > 1, visible.height > 1', 'painted?(); stop()', 'view.stop(); view.observe = nil',
    '!CloudSupervisedResearch.isTranscriptControlReply(message)', 'agent-stream-preview-']);
  assert(!probe.includes('.onAppear'));
  has('GalaxySSIAgentTranscriptMessagesView', ['.sheet(item: $receiptTarget)', 'store.turnReceiptStore.shouldObserve(key)',
    'painted: { store.turnReceiptStore.visible(key) }', 'completedAt: progress.status == .completed ? progress.updatedAt : nil']);
  has('GalaxySSIAgentExecutionFooterView', ['Button(action: onReceipt) { processingLabel }', 'ios.agent.turn-receipt.open']);
  has('GalaxySSITurnReceiptView', ['row("desktop_actual", "Actual Desktop provider model", missing)',
    'receipt = store.turnReceiptStore.read(target.key)', 'store.profile.identityFingerprint == target.key.owner',
    '.galaxySSIRuntimePlaintextWillClear', 'clock(target.completedAt)']);
  for (const name of ['GalaxySSIEncryptedUserDefaultsStore', 'AgentNativeToolCore', 'AgentDesktopReplyRecovery',
    'CloudModelStreaming', 'URLSessionCloudModelStreamClient', 'AgentIOSLocalModelWebToolAdapter']) {
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ' retained');
  }
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentTurnReceipt', 'AgentTurnReceiptStore', 'AgentTurnReceiptModelObservation',
    'AgentTurnReceiptVisibilityProbe', 'GalaxySSITurnReceiptView', 'AgentTurnReceiptTests']) {
    assert.equal((project.match(new RegExp(name + '\\.swift in Sources \\*\\/', 'g')) || []).length, 2);
    assert.equal((project.match(new RegExp('path = ' + name + '\\.swift;', 'g')) || []).length, 1);
  }
  assert.equal((read('apps/ios/GalaxySSITests/AgentTurnReceiptTests.swift').match(/func test/g) || []).length, 11);
  assert.equal((read(app + 'zh-Hans.lproj/Localizable.strings').match(/^"turn_receipt_/gm) || []).length, 22);
  console.log('Turn receipt source wiring checked: encrypted owner/turn scope, monotonic visible-body observations, authenticated task/generation evidence, distinct model provenance and eleven authored-only fixtures; no native acceptance.');
}
module.exports = {validate};
if (require.main === module) validate();
