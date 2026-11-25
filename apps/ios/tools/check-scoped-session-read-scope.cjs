// Source contracts only, not native SQLite/cipher/UI acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = 'a66d7cfc13fdc8ce72fdb64b9215d56d969eae05';
const file = 'apps/ios/GalaxySSI/GalaxySSIStoreSessions.swift';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const previous = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const source = read(file), old = previous(file);
const section = (text, start, end) => {
  const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return text.slice(first, last);
};
const lookupStart = '  func agentSession(id conversationId: String)';
const lookupEnd = '  func agentSessionDestination(';
const lookup = section(source, lookupStart, lookupEnd);
assert(!lookup.includes('mergedAgentConversations()') && !lookup.includes('readAll()'));
assert(lookup.includes('isAgentSessionContact(contact) && defaultAgentConversationId(for: contact.id) == clean'));
assert(lookup.indexOf('agentConversationDatabase.read(clean)') < lookup.indexOf('agentConversationDatabase.readDraft(clean)'));
assert(lookup.indexOf('agentConversationDatabase.readDraft(clean)') < lookup.indexOf('legacyAgentConversation(for:'));
const metricsStart = '  func agentSessionMetrics(';
const metricsEnd = '  @discardableResult\n  private func mutateAgentConversation(';
const metrics = section(source, metricsStart, metricsEnd);
assert.equal((metrics.match(/agentSession\(id:/g) || []).length, 1, 'One metadata snapshot per metrics request');
assert.equal(metrics.replace('    let conversation = agentSession(id: conversationId)\n', '')
  .replaceAll('conversation?.', 'agentSession(id: conversationId)?.'), section(old, metricsStart, metricsEnd));
const helperStart = '  private func legacyAgentConversation(';
const helperEnd = '  private func isAgentSessionContact(';
const helper = section(source, helperStart, helperEnd);
const listStart = '    for contact in contacts where isAgentSessionContact(contact) {\n';
const listEnd = '    return Self.sortedAgentConversations(Array(byId.values))';
const newLoop = section(source, listStart, listEnd), oldLoop = section(old, listStart, listEnd);
const flattened = text => text.replace(/\s+/g, ' ').trim();
const helperBody = helper.slice(helper.indexOf('\n') + 1, helper.lastIndexOf('\n  }'))
  .replace('else { return nil }', 'else { continue }')
  .replace('var conversation = stored ??', 'var conversation = byId[conversationId] ??')
  .replace('    return conversation', '    byId[conversationId] = conversation');
const oldBody = oldLoop.slice(oldLoop.indexOf('\n') + 1, oldLoop.lastIndexOf('    }'));
assert.equal(flattened(helperBody), flattened(oldBody), 'Legacy synthesis is moved exactly, retaining timestamps, title/model fallback and dialogue activity');
assert(newLoop.includes('legacyAgentConversation(for: contact, stored: byId[conversationId])'));
assert.equal(source.replace(lookup, section(old, lookupStart, lookupEnd))
  .replace(metrics, section(old, metricsStart, metricsEnd)).replace(helper, '').replace(newLoop, oldLoop), old,
  'No other session/database, draft, list, merge, privacy, metric or persistence behavior changed');
for (const name of ['GalaxySSIServices', 'GalaxySSIChatHistoryDatabase', 'AgentTranscriptEntryStore', 'AgentConversationModels']) {
  const file = `apps/ios/GalaxySSI/${name}.swift`;
  let retained = read(file);
  const dispatchScope = path.join(__dirname, 'check-plan-node-dispatch-scope.cjs');
  if (name === 'GalaxySSIServices' && fs.existsSync(dispatchScope)) {
    retained = require(dispatchScope).retainedServices(retained);
  }
  assert.equal(retained, previous(file), name + ' retained outside separately checked dispatch hook');
}
const services = read('apps/ios/GalaxySSI/GalaxySSIServices.swift');
assert(section(services, '  private func initialPlanningConversation(', '  private func initialPlannerConfigurationSha256(')
  .includes('store.agentSession(id: outgoing.conversationId)'));
assert(section(services, '  private func recentLocalConversationContext(', '  private let localModelSystemPrompt')
  .includes('store.agentSessionMessages(conversationId)'));
const tests = read('apps/ios/GalaxySSITests/GalaxySSIStoreTests.swift');
const fixtures = section(tests, '  func testScopedSessionLookupRetainsArchivedAndDraftMetadata()', '  @MainActor');
assert.equal(tests.replace(fixtures, ''), previous('apps/ios/GalaxySSITests/GalaxySSIStoreTests.swift'),
  'Only the new fixture region changes; baseline test/parser issues are not silently rewritten');
for (const name of ['testScopedSessionLookupRetainsArchivedAndDraftMetadata',
  'testScopedLegacySessionLookupMatchesListSynthesisAndDialogueActivity',
  'testScopedUnknownSessionDoesNotBorrowActiveSessionMetadataOrHistory']) assert(tests.includes('func ' + name + '('));
console.log('Scoped session metadata/legacy lookup source contracts passed; no Swift type checking, native SQLite, latency or device acceptance.');
