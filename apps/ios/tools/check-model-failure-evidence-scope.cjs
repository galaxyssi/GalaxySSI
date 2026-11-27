// Source contracts only; no Swift, streams, tools, transport or native fixtures executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c1e1529ed1160a34564eb57606dfd209fc7a61ba';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const names = ['AgentConnectorModelFailureEvidence.swift', 'AgentConnectorModelFailureEvidenceTests.swift'];
const signature = '  func streamConversation(\n' +
  '    contact: GalaxySSIContact, store: GalaxySSIStore, turns: [ChatMessage], images: [CloudImagePayload],\n' +
  '    requestId: String, connectorFailureEvidence: AgentConnectorModelFailureEvidence\n' +
  '  ) -> AsyncThrowingStream<ModelStreamEvent, Error>';
const opaque = signature + ' {\n    connectorFailureEvidence.markPossibleEffects()\n' +
  '    return streamConversation(contact: contact, store: store, turns: turns, images: images, requestId: requestId)\n  }\n';
const observed = signature + ' {\n' +
  '    streamConversation(contact: contact, store: store, turns: turns, images: images,\n' +
  '      requestId: requestId, collaborationEvidence: nil, connectorFailureEvidence: connectorFailureEvidence)\n  }\n';
function retained(file, source) {
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line => !names.some(name => line.includes(name))).join('\n');
  if (file.endsWith('GalaxySSIServices.swift')) return source
    .replace('    let failureEvidence = AgentConnectorModelFailureEvidence(owner: dispatch.owner)\n', '')
    .replace('        failureEvidence.beginPhoneInference()\n', '')
    .replace('        failureEvidence.beginCloudInference()\n', '')
    .replace('requestId: dispatch.owner, connectorFailureEvidence: failureEvidence)', 'requestId: dispatch.owner)')
    .replace('          case .failed(let failure):\n            failureEvidence.recordStreamFailure(code: failure.error.code, requestId: dispatch.owner)\n            throw GalaxySSIError.invalidPayload(failure.error.message)',
      '          case .failed(let failure): throw GalaxySSIError.invalidPayload(failure.error.message)')
    .replace('if started && !failureEvidence.permitsKnownFailure(requestId: dispatch.owner, error: error, taskCancelled: Task.isCancelled)', 'if started')
    .replace('      if started && queuedNativeConnectorContext(dispatch, requireExecution: false) == nil { return }\n', '');
  if (file.endsWith('CloudConversationStreamEngine.swift')) return source
    .replace(signature + '\n', '')
    .replace('\n' + opaque, '')
    .replace(observed + '\n', '')
    .replace('    peerWorkPublish: GoalWorkHandler? = nil,\n    connectorFailureEvidence: AgentConnectorModelFailureEvidence? = nil', '    peerWorkPublish: GoalWorkHandler? = nil')
    .replace('    connectorFailureEvidence?.installCloudObserver(requestId: conversationRequestId)\n', '')
    .replace('          connectorFailureEvidence: connectorFailureEvidence,\n', '')
    .replace('    connectorFailureEvidence: AgentConnectorModelFailureEvidence?,\n', '')
    .replace('              connectorFailureEvidence?.markPossibleEffects()\n', '')
    .replace('          collaborationPublish: publish,\n          connectorFailureEvidence: connectorFailureEvidence', '          collaborationPublish: publish')
    .replace('    collaborationPublish: ((AgentMcpJSONObject) async -> AgentMcpJSONObject?)? = nil,\n    connectorFailureEvidence: AgentConnectorModelFailureEvidence? = nil',
      '    collaborationPublish: ((AgentMcpJSONObject) async -> AgentMcpJSONObject?)? = nil')
    .replace('    connectorFailureEvidence?.markPossibleEffects()\n', '');
  if (file.endsWith('check-knowledge-primary-partitions-scope.cjs')) return source
    .replace("const read = file => require('./check-model-failure-evidence-scope.cjs').retained(file,\n  require('./check-connector-acceptance-evidence-scope.cjs').retained(file,\n    fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')));",
      "const read = file => require('./check-connector-acceptance-evidence-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace("  source = require('./check-model-failure-evidence-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'CloudConversationStreamEngine.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/tools/check-knowledge-primary-partitions-scope.cjs'])
    assert.equal(retained(file, read(file)), old(file), file);
  const service = section(read(app + 'GalaxySSIServices.swift'), '  private func dispatchQueuedNativeConnector(', '  private func nativeConnectorResponseOutbox(');
  for (const token of ['failureEvidence.beginPhoneInference()', 'failureEvidence.beginCloudInference()',
    'connectorFailureEvidence: failureEvidence', 'failureEvidence.recordStreamFailure(code: failure.error.code',
    '!failureEvidence.permitsKnownFailure(requestId: dispatch.owner, error: error, taskCancelled: Task.isCancelled)',
    'if started && queuedNativeConnectorContext(dispatch, requireExecution: false) == nil { return }',
    'markQueuedConnectorUnknown(dispatch)', 'publishNativeConnectorResponse(dispatch.response(error.localizedDescription, success: false)']) assert(service.includes(token), token);
  assert(service.indexOf('failureEvidence.beginPhoneInference()') < service.indexOf('LocalModelInferenceRuntime.shared.generateAsync('));
  assert(service.indexOf('failureEvidence.beginCloudInference()') < service.indexOf('for try await event in cloudStreamEngine.streamConversation('));
  const stream = read(app + 'CloudConversationStreamEngine.swift');
  assert(stream.includes(opaque) && stream.includes(observed));
  assert(stream.includes('connectorFailureEvidence?.markPossibleEffects()\n              await emitLegacyConversation('));
  assert(stream.includes('guard !calls.isEmpty else { return [] }\n    connectorFailureEvidence?.markPossibleEffects()'));
  const tools = section(stream, '  private func executeToolCalls(', '  static func cloudEvidenceOutput(');
  assert(tools.indexOf('connectorFailureEvidence?.markPossibleEffects()') < tools.indexOf('group.addTask'));
  const policy = read(app + names[0]);
  for (const token of ['private let lock = NSLock()', 'requestId == owner', 'backend == .cloud', 'cloudObserved = true',
    'effectsPossible = true', '!effectsPossible, !streamCancelled', 'NSURLErrorCancelled', 'error is CancellationError',
    'case .some(.phone): return true', 'case .some(.cloud): return cloudObserved']) assert(policy.includes(token), token);
  assert.equal((policy.match(/effectsPossible = false/g) || []).length, 1);
  const tests = read('apps/ios/GalaxySSITests/' + names[1]);
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const name of names) assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes(name)).length, 4, name);
  for (const name of ['AgentIOSConnectorDispatch', 'AgentConnectorResponseResolver', 'AgentControlPlaneActionExecutorModels',
    'AgentNetworkRoutingModels', 'AgentManagedResponseModels', 'CloudConversationStreamToolRounds'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  console.log('Owned phone/observed-cloud model failure settlement, tool/opaque/cancellation boundaries, retained stream/recovery kernels and eight authored fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
