// Source contracts only, not native extraction, inference, provider delivery or cancellation acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = 'fee71d95ce8b6d5c5d62863dd55e1bf93c866078';
const read = file => require('./check-managed-raw-attachments-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const show = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  source = require('./check-managed-raw-attachments-scope.cjs').retained(file, source);
  if (file.endsWith('check-pre-shadow-routing-scope.cjs')) return source.replace(
    "  require('./check-connector-document-input-scope.cjs').retained(file,\n    fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')));",
    "  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace("  source = require('./check-connector-document-input-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentConnectorDocumentInputTests.swift')).join('\n');
  if (file.endsWith('AgentIOSConnectorDispatch.swift') && source.includes('\nenum AgentConnectorDocumentInput {'))
    return source.slice(0, source.indexOf('\nenum AgentConnectorDocumentInput {'));
  if (file.endsWith('AgentAttachmentKnowledgeImporter.swift') && source.includes('  static func transientDocumentText('))
    return source.replace(section(source, '  static func transientDocumentText(', '  private static func extractText('), '');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('documentInput.section')) {
    const begin = '  private func dispatchQueuedNativeConnector(', end = '  private func nativeConnectorResponseOutbox(';
    return source.replace(section(source, begin, end), section(show(file), begin, end));
  }
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'AgentIOSConnectorDispatch.swift',
    app + 'AgentAttachmentKnowledgeImporter.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'])
    assert.equal(retained(file, read(file)), show(file), file);
  const service = section(read(app + 'GalaxySSIServices.swift'),
    '  private func dispatchQueuedNativeConnector(', '  private func nativeConnectorResponseOutbox(');
  const prior = section(show(app + 'GalaxySSIServices.swift'),
    '  private func dispatchQueuedNativeConnector(', '  private func nativeConnectorResponseOutbox(');
  assert.equal(section(service, '      let targets =', '      if dispatch.contactId == "local-llm" {'),
    section(prior, '      let targets =', '      let blocks ='), 'Original live provider/privacy/budget admission is unchanged');
  const paired = '        guard attachments.isEmpty, let contact =';
  assert.equal(service.slice(service.indexOf(paired)), prior.slice(prior.indexOf(paired)), 'Paired wire, disclosure, ownership and unknown-outcome handling retained');
  for (const token of ['matchExactIDs: true', 'Task.detached(priority: .utility)', 'withTaskCancellationHandler(', 'extraction.cancel()',
    'context.outgoing.content == original.outgoing.content', 'context.outgoing.richOutputJson == original.outgoing.richOutputJson',
    '(dispatch.executionPrompt + documentInput.section).utf8.count <= 256 * 1_024',
    'userPrompt: dispatch.prompt + documentInput.section', 'content: dispatch.executionPrompt + documentInput.section',
    'AgentUntrustedEvidenceBoundary.enforceSystemPrompt(', 'CloudImagePayloadFactory.prepare(attachments.filter(\\.isImage)',
    'guard completed, !text.isBlank']) assert(service.includes(token), token);
  assert(service.indexOf('extraction.value') < service.indexOf('guard let context = queuedNativeConnectorContext(dispatch)'));
  assert(service.indexOf('guard let context = queuedNativeConnectorContext(dispatch)') < service.indexOf('let targets ='));
  assert(service.indexOf('let budget =') < service.indexOf('started = true'));
  const dispatch = read(app + 'AgentIOSConnectorDispatch.swift');
  const policy = dispatch.slice(dispatch.indexOf('\nenum AgentConnectorDocumentInput {'));
  for (const token of ['attachments.count <= 10', 'Set(attachments.map(\\.id)).count == attachments.count',
    '$0.historicalSourceTurnId == nil', 'maximumSourceBytes - totalBytes', 'maximumDocumentCharacters = 12_000',
    'maximumTotalCharacters = 24_000', 'maximumEnvelopeBytes = 128 * 1_024', 'maximumTotalCharacters - totalCharacters',
    'section.utf8.count <= maximumEnvelopeBytes', 'AgentAttachmentKnowledgeImporter.transientDocumentText',
    'AgentMcpJSONCodec.stringify(.object(', 'AgentUntrustedEvidenceBoundary.wrapText(', 'Task.checkCancellation()']) assert(policy.includes(token), token);
  for (const token of ['replaceAgentKnowledgeSource', 'UserDefaults', 'URLSession', 'apiKey', 'store.']) assert(!policy.includes(token), token);
  const importer = section(read(app + 'AgentAttachmentKnowledgeImporter.swift'),
    '  static func transientDocumentText(', '  private static func extractText(');
  assert(importer.includes('return extractText(from: attachment)'));
  assert(importer.includes('!mime.hasPrefix("audio/")') && importer.includes('!mime.hasPrefix("video/")'));
  for (const name of ['GalaxySSIAttachments', 'AgentUntrustedEvidenceBoundary', 'AgentOfficeDocumentExtractor',
    'LocalModelInferenceRuntime', 'CloudConversationStreamEngine', 'CloudImagePayload', 'AgentConnectorResponseResolver',
    'MqttBusinessTransportRuntime', 'MqttDesktopConnectorProjection']) {
    const file = app + name + '.swift';
    assert.equal(read(file), show(file), name);
  }
  const tests = read('apps/ios/GalaxySSITests/AgentConnectorDocumentInputTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 10);
  for (const token of ['testProductionTextDecoderIncludesActualBodyAndExactAttachmentIdentity',
    'testProductionHTMLDecoderReusesReadableDocumentExtraction', 'testHostileNamesAndDocumentInstructionsRemainInsideVerifiedUntrustedEnvelope',
    'testAggregateSourceByteBoundIsCheckedBeforeAnyParserRuns', 'testDocumentAndAggregateTextCapsRejectRatherThanTruncate',
    'testEncodedByteBoundRejectsLargeSingleGraphemePayloads', 'testImageBytesStayOnExistingVisionPathAndAreNotDecodedAsDocuments',
    'testOneUnreadableDocumentCannotYieldPartialSuccessfulContext']) assert(tests.includes(token), token);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes('AgentConnectorDocumentInputTests.swift')).length, 4);
  const priorScope = 'apps/ios/tools/check-pre-shadow-routing-scope.cjs';
  assert.equal(retained(priorScope, read(priorScope)), show(priorScope));
  const statusScope = 'apps/ios/tools/check-native-status-observation-scope.cjs';
  assert.equal(read(statusScope).replace("const read = file => require('./check-connector-document-input-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
    "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');"), show(statusScope));
  console.log('Scoped transient document input, post-extraction admission, untrusted envelopes and unchanged paired transport source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
