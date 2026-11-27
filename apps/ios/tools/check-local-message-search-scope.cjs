'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const app = 'apps/ios/GalaxySSI/';
const base = 'eb970a6ac3ac5883f011991957bb776d40b0ab48';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', `${base}:${f}`], { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).replace(/\r\n/g, '\n');
const has = (s, tokens) => tokens.forEach(t => assert.ok(s.includes(t), `Missing source wiring: ${t}`));
const policy = read(app + 'GalaxySSILocalMessageSearch.swift');
has(policy, ['clean.utf16.count <= 256', '!conversation.privateMode && !conversation.trackingPaused',
  'conversation.globalTopicKey.isBlank', 'conversation.mergedIntoConversationId.isBlank',
  'contact.isDesktopHistoryOnly == archived', 'contact.type.lowercased() == "person"', 'contact.isDesktopDeviceContact',
  'message.sourceConversationId.isBlank', 'message.conversationId == source.id', 'message.contactId == source.id',
  'containsUnexecutedControlReply', 'agent-stream-preview-', 'AgentPeerChatTransport.migrateStoredHistory',
  '[.file, .image, .audio, .video]', 'map(\\.title)', 'text.range(of: query, options: .caseInsensitive)']);
const scanner = read(app + 'GalaxySSILocalMessageSearchScanner.swift');
has(scanner, ['actor GalaxySSILocalMessageSearchScanner', 'Task.checkCancellation()',
  'conversations.localSearchPage(', 'messages.localSearchPage(', 'conversations.read(current.id)',
  'Search.ordinary(live)', 'saved.nextCursor != cursor', 'messages.message(id: hit.message)',
  'GalaxySSIChatHistoryCursor(exact) == hit.cursor', 'Search.hit(exact', 'static func allowed(_ source: Source',
  'store.canReadAgentTranscript, store.canRestoreMessageViewport']);
const db = read(app + 'GalaxySSIChatHistoryDatabase.swift');
let normal = db.replace(/  \/\/ Search remains an on-demand encrypted read[\s\S]*?(?=  private func turnTimingKey)/, '');
normal = normal.replace('payloadColumn: Int32, cache: Bool = true)', 'payloadColumn: Int32)')
  .replace('guard cache, rowCachingEnabled, let database', 'guard rowCachingEnabled, let database');
assert.equal(normal, old(app + 'GalaxySSIChatHistoryDatabase.swift'), 'Existing history writes/ownership/cipher unchanged; only add uncached strict reads');
has(db, ['rowCachingEnabled, database != nil', 'cache: false', 'row.id.uuidString == id',
  'contactId.map({ row.contactId == $0 })', 'conversationId.map({ row.conversationId == $0 })',
  'kept.filter(admitsAgentTurn)', 'step == SQLITE_DONE, rowCachingEnabled', 'min(max(1, pageSize), 32)']);
const sessions = read(app + 'GalaxySSIStoreSessions.swift');
normal = sessions.replace(/  func localSearchPage\([\s\S]*?(?=  @discardableResult\n  func delete\()/, '');
assert.equal(normal, old(app + 'GalaxySSIStoreSessions.swift'), 'Do not change session lifecycle or metadata authority');
const view = read(app + 'GalaxySSILocalMessageSearchView.swift');
has(view, ['220_000_000', 'hits.count + 24', 'hits.isEmpty ? 1 : min(6', 'scannerOwner == owner',
  '$0.owner == owner && Search.allowed', '.task(id: request)', 'model.prune(store: store)',
  '.sheet(item: $selected)', 'GalaxySSILocalMessageReader', 'galaxySSIRuntimePlaintextWillClear', 'model.stop()']);
const reader = read(app + 'GalaxySSILocalMessageReader.swift');
has(reader, ['mounted && scene == .active', 'store.profile.identityFingerprint == hit.owner', 'Search.allowed(hit.source',
  'Task.detached', 'withTaskCancellationHandler', 'viewportEpoch.accepts(epoch)',
  'glyphRange(forCharacterRange: range', 'y - scroll.bounds.height / 3', 'query, options: .caseInsensitive',
  'view.position = nil; view.attributedText = nil', 'scroll.adjustTop(by: -retained.top)',
  'job.older != nil ? page.lines + lines : lines + page.lines', '.navigationTitle(canRead ? hit.source.title : "")']);
for (const source of [policy, scanner, view, reader]) {
  assert.ok(!/URLSession|UserDefaults|AppStorage|switchAgentSession|restoreAgentSession|markContactRead|upsert\(/.test(source));
}
has(read(app + 'GalaxySSIConversationHubView.swift'), ['GalaxySSILocalMessageSearchView(query: searchText, archived: showingArchived',
  'closeSearch(); suspendHubContentForBackground()']);
for (const name of ['GalaxySSIServices.swift', 'GalaxySSIConversationComposer.swift', 'AgentPeerChatTransport.swift',
  'GalaxySSIAttachmentAtRestCipher.swift', 'GalaxySSIHealthRecords.swift']) assert.equal(read(app + name), old(app + name));
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const f of ['GalaxySSILocalMessageSearch.swift', 'GalaxySSILocalMessageSearchScanner.swift',
  'GalaxySSILocalMessageSearchView.swift', 'GalaxySSILocalMessageReader.swift', 'GalaxySSILocalMessageSearchTests.swift']) {
  assert.equal(project.split(`/* ${f} in Sources */`).length - 1, 2);
  assert.equal(project.split(`path = ${f};`).length - 1, 1);
}
assert.equal((read('apps/ios/GalaxySSITests/GalaxySSILocalMessageSearchTests.swift').match(/  func test\w+\(/g) || []).length, 12);
const strings = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const key of ['heading', 'attachment', 'query_limit', 'empty', 'failed', 'retry', 'more', 'gone', 'earlier', 'later', 'back']) {
  assert.equal(strings.split(`"galaxyssi.chat_search.${key}" =`).length - 1, 1);
}
console.log('Local-message search source wiring checked: uncached encrypted pages, ordinary-history fences, transient cancellable batches and exact read-only context. Twelve authored Swift methods are not native acceptance.');
