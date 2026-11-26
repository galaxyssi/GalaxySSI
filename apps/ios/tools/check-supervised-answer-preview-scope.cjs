// Source contracts only: not native compilation, UI, privacy, lifecycle or authenticated network acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '3e950c5fb1d9e577d7f2f245dd5822a80271bcb2';
const read = file => require('./check-resumed-planner-route-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const cache = new Map();
function old(file) { if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n')); return cache.get(file); }
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  source = require('./check-resumed-planner-route-scope.cjs').retained(file, source);
  if (file.endsWith('check-interactive-request-hedge-scope.cjs')) return source
    .replace("const read = file => require('./check-supervised-answer-preview-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-supervised-answer-preview-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line =>
    !['AgentSupervisedAnswerPreview.swift', 'AgentSupervisedAnswerPreviewTests.swift'].some(name => line.includes(name))).join('\n');
  if (file.endsWith('MqttDesktopConnectorProjection.swift')) return source
    .replace('  var receiveAnswerPreview: (([String: Any], String, String) -> Void)? = nil\n', '')
    .replace('      if AgentSupervisedAnswerPreview.claims(payload) {\n        receiveAnswerPreview?(payload, target.peer.remoteSignalName, target.routeId)\n        return\n      }\n', '');
  if (file.endsWith('GalaxySSIAgentHomeSessionLifecycle.swift')) return source.replace('    coordinator.clearSupervisedAnswerPreviews()\n', '');
  if (file.endsWith('GalaxySSIAgentHomeOutputView.swift')) return source
    .replace('              answerPreviews: coordinator.visibleSupervisedAnswerPreviews(conversationId: store.activeAgentConversationId),\n', '')
    .replace('              turnStartMillis: transcriptWindow.snapshot.turnStartMillis,\n', '')
    .replace('              messages: messages,\n', '              messages: messages,\n              turnStartMillis: transcriptWindow.snapshot.turnStartMillis,\n');
  if (file.endsWith('GalaxySSIAgentTranscriptMessagesView.swift') && source.includes('ForEach(answerPreviews.filter')) return source
    .replace('  var answerPreviews: [AgentSupervisedAnswerPreview] = []\n', '')
    .replace(section(source, '      if message.isMine {\n        ForEach(answerPreviews.filter', '    }\n    .onAppear { observeLatestReply(latest) }'), '');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('supervisedAnswerPreviewScopes:')) {
    source = source.replace(section(source, '  @Published private(set) var supervisedAnswerPreviews:', '  @Published private(set) var pendingPeerSendContactIds:'), '');
    source = source.replace(section(source, '    answerPreviewProfileObserver = store.$profile', '    nativeConnectorResponseToken ='), '');
    source = source.replace(section(source, '    answerPreviewLifecycleObservers = [UIApplication.willResignActiveNotification,', '    foregroundRecoveryObserver ='), '');
    source = source.replace('    answerPreviewLifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }\n', '');
    source = source.replace(section(source, '  func clearSupervisedAnswerPreviews(', '  private func requestPairedPhonePlan('), '');
    source = source.replace(section(source, '    let previewScope = AgentSupervisedAnswerPreview.Scope(', '    try managedDesktopReplyLedger.register(record)'), '');
    source = source.replace('      }, receiveAnswerPreview: { [weak self] payload, desktop, route in\n        self?.receiveSupervisedAnswerPreview(payload, desktopId: desktop, routeId: route)\n', '');
    source = source.replace(section(source, '    if AgentSupervisedAnswerPreview.claims(appPayload) {', '    if object.string("scheme") == "signal", let link, handleDesktopGoalWorkReply'), '');
  }
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'MqttDesktopConnectorProjection.swift', app + 'GalaxySSIAgentHomeOutputView.swift',
    app + 'GalaxySSIAgentTranscriptMessagesView.swift', app + 'GalaxySSIAgentHomeSessionLifecycle.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/tools/check-interactive-request-hedge-scope.cjs'])
    assert.equal(retained(file, read(file)), old(file), file);
  const model = read(app + 'AgentSupervisedAnswerPreview.swift');
  for (const token of ['supervised_answer_preview_v1', 'scope.route.clientRouteId == scope.identity.clientRouteId',
    'payload.string("agent_id") == "codex"', 'Self.source(payload) == scope.source', '== scope.generation',
    'CFGetTypeID(visible) == CFBooleanGetTypeID()', 'String(source) == text', 'sequence > prior.sequence',
    'scope == prior.scope', 'CloudSupervisedResearch.hasUnexecutedMarkup', 'String(text.prefix(64_000))']) assert(model.includes(token), token);
  for (const token of ['Codable', 'UserDefaults', 'FileManager', 'URLSession', 'appendIncoming', 'register(']) assert(!model.includes(token), token);
  const service = read(app + 'GalaxySSIServices.swift');
  const current = section(service, '  private func answerPreviewScopeIsCurrent(', '  func visibleSupervisedAnswerPreviews(');
  for (const token of ['scope.profile == store.profile.identityFingerprint', 'store.canReadAgentTranscript',
    'UIApplication.shared.isProtectedDataAvailable', 'UIApplication.shared.applicationState == .active',
    'task.phase == .planning', '!PhoneExecutionAuthority.isCancelled', 'session.status == .active', '!session.privateMode',
    '!session.trackingPaused', 'session.mergedIntoConversationId.isBlank', 'concernID(session) == nil',
    'pairedPhonePlannerLink(scope.route) != nil', 'record.state == .pending', 'record.response == nil',
    'record.executionGeneration == scope.generation', 'sourceMessageId: String(scope.source)) == scope.identity']) assert(current.includes(token), token);
  const receive = section(service, '  private func receiveSupervisedAnswerPreview(', '  private func requestPairedPhonePlan(');
  for (const token of ['scopes.count == 1', 'answerPreviewScopeIsCurrent(scope)', 'taskIdentityStore.matchesRegistered(payload: payload)', 'preview.advances(']) assert(receive.includes(token), token);
  for (const token of ['appendIncoming', 'connectorResponseBus.publish', '.complete(', '.register(', 'onIncomingMessage']) assert(!receive.includes(token), token);
  assert(service.includes('supervisedAnswerPreviewScopes.count >= 32'));
  assert(service.includes('if supervisedAnswerPreviewScopes[dispatch.owner] == previewScope'));
  assert(service.indexOf('if AgentSupervisedAnswerPreview.claims(appPayload)') < service.indexOf('if object.string("scheme") == "signal", let link, handleDesktopGoalWorkReply'));
  const projection = read(app + 'MqttDesktopConnectorProjection.swift');
  assert(projection.indexOf('if AgentSupervisedAnswerPreview.claims(payload)') > projection.indexOf('let contact = try contact(payload, target: target)', projection.indexOf('  func project(')));
  const view = read(app + 'GalaxySSIAgentTranscriptMessagesView.swift');
  const display = section(view, '      if message.isMine {\n        ForEach(answerPreviews.filter', '    }\n    .onAppear { observeLatestReply(latest) }');
  for (const token of ['identity.conversationId == message.conversationId', 'identity.turnId == message.turnId', 'Text(verbatim: preview.text)']) assert(display.includes(token), token);
  assert(!display.includes('onMessageVisible') && !display.includes('playCompletedReply'));
  const output = read(app + 'GalaxySSIAgentHomeOutputView.swift');
  assert(!section(output, 'return GalaxySSIAgentHomeTranscriptView(', '    ) {\n      LazyVStack').includes('turnStartMillis:'));
  assert(section(output, '            GalaxySSIAgentTranscriptMessagesView(', '            ForEach(unboundWaitingTurnIDs').includes('turnStartMillis: transcriptWindow.snapshot.turnStartMillis'));
  for (const name of ['AgentPlannerModelSnapshot', 'GuardedModelAgentPlanner', 'AgentModelPlanningPrompt', 'AgentNativeToolCore',
    'AgentNativeToolExecutionModels', 'AgentConnectorStreamUpdate', 'MqttBusinessTransportRuntime', 'MqttSignalStateJournal',
    'MqttBusinessOutbox', 'MqttBusinessInbox', 'GalaxySSIChatHistoryDatabase']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/AgentSupervisedAnswerPreviewTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const name of ['AgentSupervisedAnswerPreview.swift', 'AgentSupervisedAnswerPreviewTests.swift'])
    assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes(name)).length, 4);
  console.log('Exact active planner preview scope, ephemeral original-turn UI, lifecycle cleanup and unchanged final/transport kernels source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
