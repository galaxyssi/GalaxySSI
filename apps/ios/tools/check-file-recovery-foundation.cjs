// Source contracts for file recovery and isolated reads; these do not execute Swift or prove runtime behavior.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'e60cd55e1';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function has(name, tokens) {
  const source = read(app + name + '.swift');
  for (const token of tokens) assert(source.includes(token), name + ': ' + token);
  return source;
}
has('AgentFileReceipt', ['case uploading, retrying, failed, stored, closed', 'case recognized, unreadable',
  'Set(blocks.map(\\.id)).count == blocks.count', 'self.generation == generation', 'generation == self.generation + 1',
  'peer == fingerprint', 'turn == (readTurn ?? original)', 'now - $0 >= 30_000']);
has('AgentTurnReceiptStore', ['entries.count < 10', 'guard body(&receipt)', 'guard write(row, key)',
  'keyMaterialKey: Self.materialKey', 'NSRecursiveLock()', 'source.digest, count: 64']);
has('AgentAttachmentReadingTool', ['galaxyssi.app.attachment_reading', '"result"', '"recognized"', '"unreadable"',
  'UIApplication.shared.applicationState == .active', 'parent.digest == AgentTurnReceiptEvidence.hash(block.id)',
  'AgentFileReceipt.originals(original).count >= 2', 'permitScopedRead: Bool = false', '"delivery_verified": .bool(false)']);
has('AgentFileRetryPolicy', ['CFGetTypeID(number) != CFBooleanGetTypeID()', 'generation(payload) == file.fileRetryGeneration',
  'file.fileRetryGeneration < 3', 'file.scope.attachmentRequestId == nil', 'AgentAttachmentDeliveryFailureContract.matches']);
has('AgentBlobProtocol', ['payload["file_retry_generation"] = attachment.fileRetryGeneration']);
has('AgentOutboundAttachmentTransfer', ['AgentFileRetryPolicy.generation(payload) == fileRetryGeneration',
  'func verifyOriginalChunks()', 'hash.update(data: try plaintextChunk(index: index))',
  'Data(hash.finalize()).hexString() == sha256']);
has('AgentBlobTransfer', ['jobs[index].retryReserved != true', 'expires > Date()', 'try attachment.verifyOriginalChunks()',
  'jobs[index].fileRetryGeneration = generation', 'jobs.firstIndex(of: reserved)',
  'try fileManager.removeItem(at: directory)', 'try await onExpiredRetry(file)',
  'guard job.active, job.heldUntil == nil', 'try loadJobs().contains(job)']);
has('MqttBusinessTransportRuntime', ['if incomingGeneration < currentGeneration { try complete(); return }',
  'let transfer = attempt', 'try await outgoingBlobs.holdRecoverable', 'projection.store.profile.identityFingerprint == key.owner',
  'state: .failed, generation: transfer.fileRetryGeneration', 'state: .stored, generation: transfer.fileRetryGeneration']);
const reliability = has('GalaxySSILinkReliability', ['status == Self.heldFile',
  'hasAttachmentDependency(source: item.clientSourceMessageId, transfer: item.attachmentTransferId)',
  'state.outbox[$0].clientSourceMessageId == source', 'state.outbox[$0].attachmentTransferId == transfer',
  'state.outbox[$0].status == PendingLinkMessage.heldFile', 'guard save() else { state = previous; return false }']);
const resume = reliability.slice(reliability.indexOf('  func resumeHeldFile('), reliability.indexOf('  func discardExhausted('));
assert(!resume.includes('releaseAttachmentDependency'), 'A click must not release the parent task');
const services = has('GalaxySSIServices', ['AgentAttachmentReadingTool.executable', 'queuedFileReceipts(outboundAttachments)',
  'receipt.wire == .failed', 'fileRecoveriesInFlight.insert(id).inserted',
  'blobOutgoingCoordinator.reserveFileRetry(file, link: link)', '$0.restart(transfer: id',
  'blobOutgoingCoordinator.activateFileRetry(id, generation: next)', 'deliveryStore.resumeHeldFile(source: messageID.uuidString']);
const start = services.indexOf('  func resumeAgentFile('), end = services.indexOf('  func expireFileRetry(', start);
const retry = services.slice(start, end);
assert(!retry.includes('await send('), 'Transport retry must not submit the original question');
assert(retry.indexOf('$0.restart(') < retry.indexOf('activateFileRetry('), 'Persist the receipt generation before activation');
has('MqttSignalStateJournal', ['func expireFileRetry(identity:', 'try MqttAttachmentBodyIdentity.matches(body, transfer: transfer, bodyID: bodyID)']);
const interpretation = services.slice(services.indexOf('  func readAgentFile('), services.indexOf('  func resumeAgentFile('));
for (const token of ['blocks: [block], matchExactIDs: true', 'bindFileRead(childKey', 'richOutputJson: outgoingAttachmentRichOutput([file]',
  'sourceTrace: AgentSingleFileRead.stage', 'AgentSingleFileRead.parse(raw)', 'store.reportAttachmentReading(',
  'AgentTurnReceiptEvidence.hash(current.richOutputJson) == sourceHash']) assert(interpretation.includes(token), token);
for (const token of ['await send(', 'original.content', 'recentLocalConversationContext(', 'conversationContext:']) {
  assert(!interpretation.includes(token), 'Single-file read must not use ' + token);
}
has('AgentSingleFileRead', ['turns: [only]', 'only.richOutputJson = ""', 'request = try isolatedRequest(prepared, system: system)',
  'Set(object.keys) == ["result", "reply"]', 'case .toolCallDelta: throw Failure.format',
  'messages.count == 2', 'contents.count == 1', 'body.removeValue(forKey: key)',
  'Text extraction only; original layout and non-text visual content are not supplied.',
  'AgentModelToolLoopCancellationSource()', 'onCancel: { cancellation.cancel() }']);
has('GalaxySSIStore', ['sourceTrace != AgentSingleFileRead.stage']);
has('AgentSingleFileDesktopIntent', ['Set(payload.keys) == fields', 'descriptors.count == 1',
  'Self.digest(descriptors) == descriptorsSHA', 'Self.digest(invocation) == invocationSHA',
  'fileReadOwners[identity.turnId] == store.profile.identityFingerprint', 'intent.originalRichSHA',
  'fileReadRegisteredIdentity(contact: item.contactId, source: item.clientSourceMessageId)',
  'guard let scope = item.fileReadScope else { return nil }', 'readTurn == identity.turnId',
  'session.globalTopicKey.isBlank', 'store.agentSafetySettings.connectorCallsAllowed']);
const desktopRead = services.slice(services.indexOf('  private func readSingleFileOnDesktop('), services.indexOf('  private func cancelFileReadDesktop('));
for (const token of ['attachments: [file]', 'preserveOriginalBytes: true', 'bindFileReadDesktop(key, intent: intent)',
  'fileReadScope: source.turnId', 'AgentTaskExecutionMode.planOnly.rawValue', 'intent.matches(payload)',
  'currentFileReadDesktopContext(', 'reply.executionGeneration == 1', 'reply.taskStatus == "completed"',
  'ProcessInfo.processInfo.systemUptime + 120', 'cancelFileReadDesktop(intent, link: link)',
  'defer { attachmentTransferStore.discard(prepared.map(\\.transferId)',
  'defer { managedDesktopReplyLedger.markApplied(ownerRunId: owner) }']) assert(desktopRead.includes(token), token);
for (const token of ['original.content', 'recentLocalConversationContext(', 'conversation_context', 'session_requirement',
  'await send(', 'resumeWaitingNativeConnectors(']) assert(!desktopRead.includes(token), 'Isolated Desktop read must not use ' + token);
assert(interpretation.includes('permitScopedRead: true'), 'Only the host reader may report an isolated child result');
has('GalaxySSILinkReliability', ['case fileReadScope = "file_read_scope"', '$0.fileReadScope == task.fileReadScope',
  'fileReadScope: request.fileReadScope']);
has('GalaxySSIServices+Outbox', ['if fileReadOutboxAllowed(item) == false']);
for (const token of ['if !planner && !fileRead', 'record.matchesCommittedResult(normalized)',
  'self.recordSingleFileDesktopFailure(payload, file: transfer)', 'current.intent.matches(payload)',
  'payload.string("sender") == self.store.profile.galaxySSIId']) assert(services.includes(token), token);
has('GalaxySSIAgentTranscriptMessagesView', ['.environment(\\.agentFileReceiptSource, message.isMine']);
has('GalaxySSIRichContentView', ['@Environment(\\.agentFileReceiptSource)', 'fileReceiptCaption', 'onlyItemID: block.id']);
has('GalaxySSIAgentFileReceiptsView', ['originals.filter { onlyItemID == nil || $0.id == onlyItemID }',
  'No file delivery receipt', 'Model reports: recognized', 'Model reports: unreadable',
  'coordinator.resumeAgentFile(messageID: message.id, itemID: block.id)',
  'coordinator.readAgentFile(messageID: message.id, itemID: block.id)',
  'work.values.forEach { $0.cancel() }', '.galaxySSIRuntimePlaintextWillClear']);
for (const name of ['GalaxySSISignalEngine', 'AgentNativeToolCore', 'AgentNativeToolExecutionModels',
  'GalaxySSIEncryptedUserDefaultsStore']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ' retained');
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentFileReceipt', 'AgentFileRetryPolicy', 'AgentFileRecoveryCoordinator', 'AgentAttachmentReadingTool', 'AgentFileReceiptTests',
  'AgentSingleFileRead', 'GalaxySSIAgentFileReceiptsView', 'AgentSingleFileReadTests',
  'AgentSingleFileDesktopIntent', 'AgentSingleFileDesktopIntentTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' project registration');
}
for (const name of ['AgentFileReceipt', 'AgentFileRetryPolicy', 'AgentFileRecoveryCoordinator', 'AgentAttachmentReadingTool',
  'AgentSingleFileRead', 'GalaxySSIAgentFileReceiptsView', 'AgentSingleFileDesktopIntent']) {
  assert(!/\p{Script=Han}/u.test(read(app + name + '.swift')), name + ': localized strings only in resources');
}
console.log('iOS file recovery and cloud/local/Desktop read source contracts passed; no Swift compilation or native execution.');
