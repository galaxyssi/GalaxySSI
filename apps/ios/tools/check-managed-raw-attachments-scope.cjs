// Source contracts only; not native delivery, cryptography, fault/restart or privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '4f4406c3bc2e8a58c0ef0e9be2ad2de9f214447e';
const read = file => require('./check-journal-codex-replay-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const originals = new Map();
const old = file => {
  if (!originals.has(file)) originals.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return originals.get(file);
};
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function restore(file, source, start, end) { return source.replace(section(source, start, end), section(old(file), start, end)); }
const fields = [
  '  var resolveManagedAttachmentOwner: (([String: Any], GalaxySSIContact, AgentTaskIdentity, MqttPeerChatProjection.Destination) throws -> TaskOwner?)? = nil\n',
  '  var recordManagedAttachmentFailure: (([String: Any], AgentPreparedOutboundAttachment) throws -> Void)? = nil\n',
  '  var managedAttachmentSourceIsCurrent: ((String, GalaxySSIContact, AgentTaskIdentity, MqttPeerChatProjection.Destination) -> Bool)? = nil\n'
];
function retained(file, source) {
  source = require('./check-journal-codex-replay-scope.cjs').retained(file, source);
  if (file.endsWith('check-native-status-observation-scope.cjs') || file.endsWith('check-connector-document-input-scope.cjs')) return source
    .replace("const read = file => require('./check-managed-raw-attachments-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-managed-raw-attachments-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('MqttManagedConnectorAttachmentTests.swift')).join('\n');
  if (file.endsWith('AgentConnectorResponseResolver.swift')) return source
    .replace('      metadata["provider_failure_attribution"] = "local_transport"\n      metadata["delivery_failure_reason"] = response.deliveryFailureCode\n', '');
  if (file.endsWith('MqttSignalSendRequest.swift') && source.includes('enum MqttAttachmentBodyIdentity {'))
    return source.replace(section(source, '// Local body lookup only.', '// Trusted local send intent.'), '');
  if (file.endsWith('MqttBusinessOutbox.swift')) return source.replace('try MqttAttachmentBodyIdentity.matches(request, bodyID: messageID)',
    'request.sourceMessageID == messageID || UUID(uuidString: request.sourceMessageID)?.uuidString == messageID');
  if (file.endsWith('MqttSignalStateJournal.swift') && source.includes('MqttAttachmentBodyIdentity.')) {
    source = restore(file, source, '  func consumeStoredAttachment(', '  func consumeFailedBlobAttachment(');
    return restore(file, source, '  func consumeFailedBlobAttachment(', '  // Compare the exact last committed snapshot');
  }
  if (file.endsWith('MqttDesktopConnectorProjection.swift') && source.includes('managedOwnerRunID')) {
    source = restore(file, source, '  struct TaskOwner {', '  let store: GalaxySSIStore');
    for (const field of fields) { assert(source.includes(field)); source = source.replace(field, ''); }
    source = restore(file, source, '  func outgoingRequests(', '  private func sourceMessage(');
    return restore(file, source, '  func attachmentOwner(', '  func isCurrentSendOwner(');
  }
  if (file.endsWith('MqttBusinessTransportRuntime.swift') && source.includes('MqttAttachmentBodyIdentity.')) {
    for (const [start, end] of [
      ['  func journalBlobDisposition(', '  func enqueueDesktopBlobOffer('],
      ['  private func queuedAttachmentOwner(', '  private func enqueueExactControl('],
      ['  private func authorizeConnectorSend(', '  func notifyDesktopRevocation('],
      ['  private func processOutgoingAttachmentReceipt(', '  private func projectDirectInbound(']
    ]) source = restore(file, source, start, end);
    return source;
  }
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func enqueueNativeConnectorAttachments(')) {
    source = restore(file, source, '  private func dispatchQueuedNativeConnector(', '  private func nativeConnectorResponseOutbox(');
    source = source.replace(section(source, '  private func enqueueNativeConnectorAttachments(', '  private func publishNativeConnectorResponse('), '');
    source = source.replace('    drainNativeConnectorAttachmentFailures()\n', '');
    return source.replace(section(source, '      }, resolveManagedAttachmentOwner:', '    return try MqttBusinessTransportRuntime('), '      })\n');
  }
  return source;
}
function validate() {
  for (const name of ['GalaxySSIServices', 'AgentConnectorResponseResolver', 'MqttSignalSendRequest', 'MqttBusinessOutbox',
    'MqttSignalStateJournal', 'MqttDesktopConnectorProjection', 'MqttBusinessTransportRuntime']) {
    const file = app + name + '.swift'; assert.equal(retained(file, read(file)), old(file), name);
  }
  const service = read(app + 'GalaxySSIServices.swift');
  const dispatch = section(service, '  private func dispatchQueuedNativeConnector(', '  private func nativeConnectorResponseOutbox(');
  for (const token of ['attachments: attachments.map { AgentDataDisclosureAttachment($0) }', 'preserveOriginalBytes: true',
    'persistNativeConnectorAttachmentIntent(dispatch, bodyID:', 'payload["message_id"] = bodyID.uuidString',
    'enqueueNativeConnectorAttachments(payload', 'String(dispatch.sourceMessageId)', 'markQueuedConnectorUnknown(dispatch)']) assert(dispatch.includes(token), token);
  assert(dispatch.indexOf('persistNativeConnectorAttachmentIntent(') < dispatch.indexOf('enqueueNativeConnectorAttachments('));
  const helpers = section(service, '  private func enqueueNativeConnectorAttachments(', '  private func publishNativeConnectorResponse(');
  for (const token of ['registerJournal(prepared', 'blobTransfers: blobs', 'enqueueDeferredAttachmentTask(',
    'store.commitOwnedAgentTaskState(expected: context.task, updated: task)', 'native_connector_attachment_manifest_json',
    'record.state == .pending', 'record.contactId == contact.id', 'matches.count == 1',
    'task.lastNativeActionResult?.actionId == pending.actionId', 'queuedNativeConnectorContext(dispatch)',
    'attachmentDeliveryFailureStore.observations()', 'AgentTaskBudgetPolicy.evaluate(',
    'descriptors.map({ $0.string("id") }) == expectedIDs', 'AgentInvocationRequestJsonCodec.encode(',
    'deliveryFailureCode: failure.errorCode']) assert(helpers.includes(token), token);
  assert(service.includes('    drainNativeConnectorAttachmentFailures()\n'));
  for (const name of ['resolveManagedAttachmentOwner:', 'recordManagedAttachmentFailure:', 'managedAttachmentSourceIsCurrent:']) assert(service.includes(name), name);
  const runtime = read(app + 'MqttBusinessTransportRuntime.swift');
  for (const token of ['isCurrentManagedAttachmentSource(', 'MqttAttachmentBodyIdentity.bodyID(source: source, taskID:',
    'MqttAttachmentBodyIdentity.matches(body, transfer: transfer, bodyID: bodyID)',
    'AgentAttachmentDeliveryFailureContract.matches(receipt: payload, attachment: transfer)', 'try record(payload, transfer)',
    'journal.consumeFailedBlobAttachment(item, bodyID: bodyID, transfer: transfer)']) assert(runtime.includes(token), token);
  const projection = read(app + 'MqttDesktopConnectorProjection.swift');
  for (const token of ['let owner = try managedAttachmentOwner(payload', 'owner.maySend', 'owner.managedOwnerRunID != nil',
    'matchesAttachment(attachment, payload:', 'contact.isCommunicable', 'managedAttachmentSourceIsCurrent?']) assert(projection.includes(token), token);
  const policy = section(read(app + 'MqttSignalSendRequest.swift'), '// Local body lookup only.', '// Trusted local send intent.');
  for (const token of ['String(numeric) == source', 'numeric <= 9_007_199_254_740_991', 'UUID(uuidString: taskID)',
    'request.sourceMessageID == transfer.scope.clientMessageId', 'request.remoteName == transfer.scope.desktopId',
    'request.contactID == transfer.scope.contactId', 'payload.string("turn_id") == transfer.scope.turnId']) assert(policy.includes(token), token);
  const journal = read(app + 'MqttSignalStateJournal.swift');
  assert.equal((journal.match(/MqttAttachmentBodyIdentity.matches\(body, transfer: transfer, bodyID: bodyID\)/g) || []).length, 2);
  assert(journal.includes('try database.withTransaction { token in'));
  for (const name of ['AgentIOSConnectorDispatch', 'AgentAttachmentDeliveryFailure', 'AgentOutboundAttachmentTransfer',
    'AgentBlobTransfer', 'AgentProviderHealth', 'AgentManagedResponseModels', 'AgentConnectorTimeoutResolver', 'GalaxySSIStore']) {
    const file = app + name + '.swift'; assert.equal(read(file), old(file), name);
  }
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'; assert.equal(retained(project, read(project)), old(project));
  assert.equal(read(project).split('\n').filter(line => line.includes('MqttManagedConnectorAttachmentTests.swift')).length, 4);
  const tests = read('apps/ios/GalaxySSITests/MqttManagedConnectorAttachmentTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 9);
  for (const token of ['testNumericReleaseAndInboxConsumptionRollBackTogether', 'testForeignNumericReceiptCannotReleaseOriginalBody',
    'testManagedNumericAttachmentsRequireAnExplicitCurrentOwnerAndExactOriginalBody', 'testAttachmentDeliveryFailureIsNotRecordedAsProviderFailure']) assert(tests.includes(token), token);
  for (const name of ['check-native-status-observation-scope.cjs', 'check-connector-document-input-scope.cjs']) {
    const file = 'apps/ios/tools/' + name; assert.equal(retained(file, read(file)), old(file));
  }
  console.log('Managed numeric raw attachments: owned intent, dependency/receipt/body binding and failure attribution source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
