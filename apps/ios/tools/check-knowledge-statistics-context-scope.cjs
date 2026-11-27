// Static contracts only; no Swift/XCTest, database execution or UI/device acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'f6eb451d14caa820e2ba2328eb280e3799798120', app = 'apps/ios/GalaxySSI/';
const read = f => require('./check-knowledge-projection-scratch-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
const promptBlock = `      if let snapshot = request.knowledgeStats,
         let stats = AgentKnowledgeStatisticsContext.capture(for: request, read: { snapshot }) {
        let metadata = AgentKnowledgeStatisticsContext.parameters(stats).mapValues { AgentMcpJSONValue.string($0) }
        append(&context, "Knowledge statistics (metadata only; not retrieval evidence): " + AgentMcpJSONCodec.stringify(metadata) + "\\n")
      }
`;
function retained(f, s) {
  s = require('./check-knowledge-projection-scratch-scope.cjs').retained(f, s);
  if (f === app + 'AgentKnowledgeDatabase.swift') return s.replace(section(s, '  func knowledgeStats()', '  struct PrimaryMigrationPage:'),
    section(old(f), '  func knowledgeStats()', '  struct PrimaryMigrationPage:'));
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return s.split('\n').filter(l => !/AgentKnowledgeStatistics(?:Context|ReadAdmission)(?:Tests)?\.swift/.test(l)).join('\n');
  if (f === app + 'AgentKnowledgeModels.swift') return s.replace('  var countsUnavailable: Bool\n', '')
    .replace('    countsComplete: Bool = true,\n    countsUnavailable: Bool = false', '    countsComplete: Bool = true')
    .replace('    self.countsComplete = countsComplete && !countsUnavailable\n    self.countsUnavailable = countsUnavailable', '    self.countsComplete = countsComplete')
    .replace('    case countsUnavailable = "counts_unavailable"\n', '')
    .replace('      countsComplete: try container.decodeIfPresent(Bool.self, forKey: .countsComplete) ?? true,\n      countsUnavailable: try container.decodeIfPresent(Bool.self, forKey: .countsUnavailable) ?? false', '      countsComplete: try container.decodeIfPresent(Bool.self, forKey: .countsComplete) ?? true');
  if (f === app + 'GalaxySSIStoreKnowledge.swift') return s.replace(section(s, '  var agentKnowledgeStats:', '  func agentKnowledgeSourceGroups('), section(old(f), '  var agentKnowledgeStats:', '  func agentKnowledgeSourceGroups('));
  if (f === app + 'AgentPersonalDataCommandRouter.swift') return s.replace('    var parameters: [String: String] = [:]\n', '')
    .replace(section(s, '  private static func knowledgeOverview(', '  private static func saveMemory('), section(old(f), '  private static func knowledgeOverview(', '  private static func saveMemory('));
  if (f === app + 'AgentModelPlanningPromptModels.swift') return s
    .replace('  var knowledgeStats: AgentKnowledgeStats? = nil\n', '')
    .replace('    case knowledgeStats = "knowledge_stats"\n', '')
    .replace('    knowledgeStats = try container.decodeIfPresent(AgentKnowledgeStats.self, forKey: .knowledgeStats)\n', '');
  if (f === app + 'AgentModelPlanningPrompt.swift') return s.replace(promptBlock, '');
  if (f === app + 'GalaxySSIServices.swift') return s
    .replace('          detail: commandResult.parameters.isEmpty ? "Local personal data command" :\n            commandResult.parameters.sorted { $0.key < $1.key }.map { "\\($0.key)=\\($0.value)" }.joined(separator: "; "),', '          detail: "Local personal data command",')
    .replace('    planningRequest.knowledgeStats = AgentKnowledgeStatisticsContext.capture(for: planningRequest, read: { store.agentKnowledgeStats })\n', '');
  if (f === app + 'zh-Hans.lproj/Localizable.strings') return s.split('\n').filter(l => !l.startsWith('"knowledge_stats_')).join('\n');
  return s;
}
function validate() {
  for (const f of ['AgentKnowledgeModels.swift', 'GalaxySSIStoreKnowledge.swift', 'AgentPersonalDataCommandRouter.swift',
    'AgentModelPlanningPromptModels.swift', 'AgentModelPlanningPrompt.swift', 'GalaxySSIServices.swift', 'zh-Hans.lproj/Localizable.strings'])
    assert.equal(retained(app + f, read(app + f)), old(app + f), f);
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(retained(project, read(project)), old(project));
  const guard = 'apps/ios/tools/check-knowledge-primary-metadata-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-statistics-context-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-statistics-context-scope.cjs').retained(f, source);\n"));
  const context = read(app + 'AgentKnowledgeStatisticsContext.swift');
  for (const text of ['AgentKnowledgeStats(countsComplete: false, countsUnavailable: true)',
    '!request.conversationContext.privateMode, request.requirements.capabilities.contains(.knowledgeSearch)',
    'stats.countsUnavailable ? "unavailable"', '"partial_indexing"', 'if !stats.countsUnavailable',
    'String(stats.itemCount)', 'String(stats.sourceCount)', 'Int64(stats.itemCount), Int64(stats.sourceCount)',
    'knowledge_stats_partial', 'knowledge_stats_unavailable']) assert(context.includes(text), text);
  for (const forbidden of ['agentKnowledgeItems', 'Double(', 'JSONEncoder().encode(item)']) assert(!context.includes(forbidden), forbidden);
  const store = section(read(app + 'GalaxySSIStoreKnowledge.swift'), '  var agentKnowledgeStats:', '  func agentKnowledgeSourceGroups(');
  assert(store.includes('resolve(try? agentKnowledgeDatabase.knowledgeStats())')); assert(!store.includes('agentKnowledgeItems'));
  const overview = section(read(app + 'AgentPersonalDataCommandRouter.swift'), '  private static func knowledgeOverview(', '  private static func saveMemory(');
  for (const text of ['agentKnowledgeSourcePage(limit: 10)', 'summary(stats, language: language)', 'stats.countsUnavailable || !page.preparationError.isEmpty',
    '!stats.countsComplete || page.preparing || stats.itemCount > 0', 'parameters: AgentKnowledgeStatisticsContext.parameters(stats)']) assert(overview.includes(text), text);
  assert(!overview.includes('agentKnowledgeSourceGroups()'));
  assert(read(app + 'AgentModelPlanningPrompt.swift').includes(promptBlock));
  assert(read(app + 'GalaxySSIServices.swift').includes('planningRequest.knowledgeStats = AgentKnowledgeStatisticsContext.capture'));
  assert(read(app + 'GalaxySSIServices.swift').includes('commandResult.parameters.sorted'));
  const database = read(app + 'AgentKnowledgeDatabase.swift');
  assert.equal(retained(app + 'AgentKnowledgeDatabase.swift', database), old(app + 'AgentKnowledgeDatabase.swift'), 'Outside the declared statistics read admission, schema, crypto and mutations remain unchanged');
  const stats = section(database, '  func knowledgeStats()', '  struct PrimaryMigrationPage:');
  for (const text of ['FROM knowledge_item_count_state i', 'JOIN knowledge_source_directory_state d',
    'ORDER BY updated_at DESC, item_hash ASC LIMIT 1', 'sqlite3_column_int64(statement, 0)', 'itemComplete == 1 && directoryComplete == 1',
    'let view = try committedReadView()', 'defer { view.close() }', 'return try view.read { connection in',
    'on: connection', 'sqlite3_column_type(statement, Int32($0)) == SQLITE_INTEGER',
    'Int(exactly: items)', 'Int(exactly: sources)', 'sqlite3_step(statement) == SQLITE_DONE']) assert(stats.includes(text), text);
  for (const text of ['sqlite3_column_int64(statement, 2)', 'sqlite3_column_int64(statement, 4)']) assert(stats.includes(text), text);
  for (const forbidden of ['COUNT(*)', 'MAX(updated_at)', 'decode(', '.all()', 'try locked', 'sourceDirectoryState()',
    'requestIndexRetry(', 'try readCommitted']) assert(!stats.includes(forbidden), forbidden);
  const translations = read(app + 'zh-Hans.lproj/Localizable.strings').split('\n').filter(l => l.startsWith('"knowledge_stats_'));
  assert.equal(translations.length, 5);
  for (const key of ['complete', 'partial']) assert.equal((translations.find(l => l.startsWith('"knowledge_stats_' + key + '"')).match(/%lld/g) || []).length, 2);
  const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgeStatisticsContextTests.swift');
  assert.equal((fixture.match(/func test/g) || []).length, 14);
  for (const text of ['testUnavailableReadDoesNotReportExactZeroOrIndexingProgress', 'testPrivateOrNonKnowledgePlanningNeverReadsStatistics',
    'testPromptBuilderRechecksPrivacyForRestoredRequests', 'testOverviewUsesBoundedIndexedSourcesInsteadOfEmptyUICache',
    'testPartialDirectoryDoesNotClaimKnowledgeIsEmpty', 'testUnavailableCountersDoNotFallBackToCachedExactTotals',
    '9007199254740993', 'EXPLAIN QUERY PLAN', 'COVERING']) assert(fixture.includes(text), text);
  const admission = read('apps/ios/GalaxySSITests/AgentKnowledgeStatisticsReadAdmissionTests.swift');
  assert.equal((admission.match(/func test/g) || []).length, 5);
  for (const name of ['StatisticsCompleteUnderHeldUncommittedWriterUsingPreviousCommittedCounters',
    'ReentrantStatisticsNeverReadTheirOwnUncommittedWriter',
    'MalformedCounterTypesAndWideFlagsBecomeUnavailableInsteadOfTruncatedTotals',
    'SingleViewRetainsPartialFlagsAndExactWideIntegerMetadata', 'MetadataStatisticsDoNotRequestKnownLexicalRepair']) assert(admission.includes('func test' + name + '('), name);
  console.log('Committed indexed/64-bit metadata-only producer, truthful overview/planner privacy, localization and 14 context plus 5 admission authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
