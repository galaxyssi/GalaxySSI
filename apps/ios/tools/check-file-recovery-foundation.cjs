// Source contracts for the transport/receipt foundation, not complete UI parity or native execution.
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
  'AgentFileReceipt.originals(original).count >= 2', '"delivery_verified": .bool(false)']);
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
for (const name of ['GalaxySSISignalEngine', 'AgentNativeToolCore', 'AgentNativeToolExecutionModels',
  'GalaxySSIEncryptedUserDefaultsStore']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ' retained');
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentFileReceipt', 'AgentFileRetryPolicy', 'AgentFileRecoveryCoordinator', 'AgentAttachmentReadingTool', 'AgentFileReceiptTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' project registration');
}
for (const name of ['AgentFileReceipt', 'AgentFileRetryPolicy', 'AgentFileRecoveryCoordinator', 'AgentAttachmentReadingTool']) {
  assert(!/\p{Script=Han}/u.test(read(app + name + '.swift')), name + ': localized strings only in resources');
}
console.log('iOS file recovery foundation source contracts passed; UI/read-isolation integration is not asserted.');
