// Focused structural checks, not Swift execution or device/peer acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const baseline = 'fe0940f0cc538bfc6659a49588b066ea560917b8';
const approved = 'c1a85545b107b89f353fe73c7003008cbf5629ed';
const show = (ref, name) => cp.execFileSync('git', ['show', ref + ':apps/ios/GalaxySSI/' + name + '.swift'],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function revocation(source) {
  const first = '  @discardableResult\n  func revokeDesktopPairing(', last = '  @discardableResult\n  private func removeDesktopPairingState(';
  const begin = source.indexOf(first), end = source.indexOf(last, begin);
  assert(begin >= 0 && end > begin); assert.equal(source.split(first).length, 2);
  return source.slice(begin, end);
}
function retainedPairingServices(source) {
  const desktopTeam = path.join(__dirname, 'check-pinned-desktop-team.cjs');
  if (fs.existsSync(desktopTeam)) source = require(desktopTeam).retainedServices(source);
  const planning = path.join(__dirname, 'check-planning-recovery-ownership.cjs');
  if (fs.existsSync(planning)) source = require(planning).retainedServices(source);
  const parallel = path.join(__dirname, 'check-parallel-native-dispatch-ownership.cjs');
  if (fs.existsSync(parallel)) source = require(parallel).retainedServices(source);
  const query = path.join(__dirname, 'check-native-recovery-query-ownership.cjs');
  if (fs.existsSync(query)) source = require(query).retainedServices(source);
  const expiry = path.join(__dirname, 'check-native-observation-expiry-scope.cjs');
  if (fs.existsSync(expiry)) source = require(expiry).retainedServices(source);
  const observation = path.join(__dirname, 'check-observation-job-lifecycle-scope.cjs');
  if (fs.existsSync(observation)) source = require(observation).retainedServices(source);
  const learning = path.join(__dirname, 'check-learning-outbox-scope.cjs');
  if (fs.existsSync(learning)) source = require(learning).retainedServices(source);
  if (!source.includes('func revokeDesktopPairing(desktopId: String) async -> Bool')) return source;
  const exact = revocation(show(approved, 'GalaxySSIServices'));
  assert.equal(source.split(exact).length, 2, 'Only the pinned approved revocation implementation may normalize');
  source = source.replace(exact, revocation(show(baseline, 'GalaxySSIServices')));
  const defaults = '  private func removeDesktopPairingState(\n    desktopId: String,\n    deleteMessages: Bool = false,\n    preserveHistory: Bool = true\n';
  assert.equal(source.split(defaults).length, 2);
  return source.replace(defaults, defaults.replace('deleteMessages: Bool = false', 'deleteMessages: Bool = true').replace('preserveHistory: Bool = true', 'preserveHistory: Bool = false'));
}
function retainedPairingStore(source) {
  const pin = path.join(__dirname, 'check-pinned-desktop-capability.cjs');
  if (fs.existsSync(pin)) source = require(pin).retainedStore(source);
  const cloud = path.join(__dirname, 'check-cloud-tool-invocation-journal.cjs');
  if (fs.existsSync(cloud)) source = require(cloud).retainedStore(source);
  return source === show(approved, 'GalaxySSIStore') ? show(baseline, 'GalaxySSIStore') : source;
}
module.exports = {retainedPairingServices, retainedPairingStore, validatePairingHistory};
function validatePairingHistory() {
  const store = read('GalaxySSI/GalaxySSIStore.swift');
  assert.equal(retainedPairingStore(store), show(baseline, 'GalaxySSIStore'), 'All Store changes must match the exact approved pairing-history version');
  const lifecycle = read('GalaxySSI/GalaxySSIPairingLifecycle.swift');
  for (const source of [store, lifecycle, read('GalaxySSI/GalaxySSIServices.swift')]) {
    assert(source.includes('deleteMessages: Bool = false,\n    preserveHistory: Bool = true'));
  }
  for (const token of ['guard contact.isDesktopHistoryOnly else { return true }',
    'MqttRouteProtocol.hex(pairedFingerprint.lowercased(), count: 64)',
    'MqttRouteProtocol.hex(contact.identityFingerprint.lowercased(), count: 64)',
    'contact.identityFingerprint.caseInsensitiveCompare(pairedFingerprint) == .orderedSame']) assert(lifecycle.includes(token), token);
  for (const token of ['preserveHistory: !deleteMessages',
    'GalaxySSIPairingLifecycle.canRestoreHistory(contacts[contactIndex]',
    'GalaxySSIPairingLifecycle.canRestoreHistory(existingContact',
    'GalaxySSIPairingLifecycle.canRestoreHistory(contact', 'link == nil || (link?.desktopId == desktopId && link?.routes == current.routes)',
    'link?.desktopId == desktopId, current.routes == link?.routes']) assert(store.includes(token), token);
  const clear = store.slice(store.indexOf('func clearPairedDesktopLocalHistory'), store.indexOf('func updateDesktopAgentContacts'));
  for (const token of ['!runtimePlaintextCleared', 'profile.identityFingerprint == owner', 'current.routes == expected.routes',
    'GalaxySSIPairingLifecycle.canRestoreHistory($0', '$0.id != "hermes" && $0.id != "system"',
    'try chatHistoryDatabase.deleteContactHistories(ids)', 'suppressMessageDatabaseSync = true',
    'deletePrivateAttachmentCopies(in: messages)', 'agentReplyUnreadStore.remove(message)']) assert(clear.includes(token), token);
  assert(clear.indexOf('try chatHistoryDatabase.deleteContactHistories') < clear.indexOf('messagesByContact.removeValue'));
  assert(!/publish|removeDesktopPairing|serverLinks\.(remove|append)/.test(clear), 'Local deletion cannot unpair or send');
  const db = read('GalaxySSI/GalaxySSIChatHistoryDatabase.swift');
  const deletion = db.slice(db.indexOf('func deleteContactHistories'), db.indexOf('func deleteConversation('));
  for (const token of ['try locked', 'contactIds.count <= 10_000', '!contactIds.contains(where: \\.isBlank)',
    'BEGIN IMMEDIATE TRANSACTION', 'ROLLBACK', 'INSERT OR IGNORE INTO chat_message_deletions',
    'SELECT contact_id, message_id, remote_message_id, is_mine FROM chat_messages WHERE contact_id = ?',
    'DELETE FROM chat_messages WHERE contact_id = ?', 'guard execute("COMMIT")', 'committed = true; rowCache.clear()']) assert(deletion.includes(token), token);
  const services = read('GalaxySSI/GalaxySSIServices.swift');
  assert(services.includes('func revokeDesktopPairing(desktopId: String) async -> Bool'));
  assert(!services.includes('func revokeDesktopPairing(desktopId: String, deleteMessages:'));
  assert(services.includes('notifyDesktopRevocation(link)') && services.includes('finishDesktopRevocation(link)'));
  const screen = read('GalaxySSI/GalaxySSISecurityCenterView.swift');
  assert(screen.includes('"galaxyssi.desktop_history.scan", "Scan to reconnect"'));
  assert(screen.includes('GalaxySSIDesktopHistoryDeletionView(link: link)'));
  for (const text of ['Local chats are kept.', 'Update Desktop first', 'Update each Desktop first']) assert(screen.includes(text));
  const view = read('GalaxySSI/GalaxySSIDesktopHistoryDeletionView.swift');
  assert(view.includes('confirmation = link') && view.includes('owner = store.profile.identityFingerprint'));
  assert(view.includes('.destructive') && view.includes('.cancel()'));
  assert(view.includes('store.clearPairedDesktopLocalHistory(captured, owner: owner)'));
  assert(!view.includes('coordinator') && !view.includes('publish'));
  assert.equal(read('GalaxySSI.xcodeproj/project.pbxproj').split('GalaxySSIDesktopHistoryDeletionView.swift in Sources').length - 1, 2);
  const tests = read('GalaxySSITests/GalaxySSIDesktopDisconnectTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 10);
  assert(!tests.includes('store.upsert('), 'Private Store API is not a test seam');
  for (const token of ['store.approveFriendRequest(id: request.id)', 'testDifferentFingerprintCannotRestoreArchivedDeviceOrAgentWithSameIdOrName',
    'testDatabaseLocalDeletionIsScopedAndRejectsInvalidTargetsBeforeAnyMutation', 'owner: "wrong owner"',
    'XCTAssertFalse(reopened.upsert(replay))', 'XCTAssertEqual(store.serverLinks.first, link)']) assert(tests.includes(token), token);
  const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
  for (const key of ['scan', 'delete', 'confirmation', 'deleted', 'failed']) {
    assert.equal(strings.split(`"galaxyssi.desktop_history.${key}" =`).length - 1, 1);
  }
  assert(!/\p{Script=Han}/u.test(view)); assert(!/\p{Script=Han}/u.test(tests));
  console.log('Pairing history retention, identity restoration and confirmed local deletion source contracts passed; six new native tests authored, not executed.');
}
if (require.main === module) validatePairingHistory();
