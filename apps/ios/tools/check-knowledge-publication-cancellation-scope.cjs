// Static publication-path contracts only, not native race/database acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
const file = app + 'AgentKnowledgeHybridSearch.swift', source = read(file), previous = old(file);
let retained = source.replace('  private let embedQuery: (String) async throws -> [Float]\n  private let beforePublication: () -> Void', '  private let runtime: GalaxySSIEmbeddingRuntime');
retained = retained.replace(section(retained, '  convenience init(database:', '  func search(query:'), section(previous, '  init(database:', '  func search(query:'))
  .replace('    guard limit > 0 else { return [] }\n    try Task.checkCancellation()', '    guard limit > 0 else { return [] }')
  .replace('      let results = try await freshLexical(lexicalHits, limit: limit, token: token)\n      try Task.checkCancellation()\n      try active(token)\n      return results', '      return try await freshLexical(lexicalHits, limit: limit, token: token)')
  .replace('    let results: [AgentKnowledgeHit] = try await withTaskCancellationHandler', '    return try await withTaskCancellationHandler')
  .replace('try await embedQuery(query)', 'try await runtime.embed(query)')
  .replaceAll('            beforePublication()\n', '').replaceAll('          beforePublication()\n', '')
  .replace('    }, onCancel: { self.cancelRequest(requestId) })\n    try Task.checkCancellation()\n    try active(token)\n    return results', '    }, onCancel: { self.cancelRequest(requestId) })');
assert.equal(retained, previous, 'Retain ranking, snapshot validation, queue ownership, cancellation/native cleanup and admission effects outside declared publication checks/fixtures');
for (const token of ['      embedQuery: { try await runtime.embed($0) })', 'factory: nativeFactory',
  'let results = try await freshLexical(lexicalHits, limit: limit, token: token)\n      try Task.checkCancellation()\n      try active(token)\n      return results',
  '}, onCancel: { self.cancelRequest(requestId) })\n    try Task.checkCancellation()\n    try active(token)\n    return results']) assert(source.includes(token), token);
assert.equal((source.match(/beforePublication\(\)/g) || []).length, 2);
for (const name of ['AgentKnowledgeDatabase', 'AgentKnowledgeNativeIndex', 'AgentKnowledgeNativeFiles', 'AgentKnowledgeSemanticModel']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'));
const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
assert.equal(read(project).split('\n').filter(l => !l.includes('AgentKnowledgePublicationCancellationTests.swift')).join('\n'), old(project));
assert.equal((read(project).match(/AgentKnowledgePublicationCancellationTests.swift in Sources \*\//g) || []).length, 2);
const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgePublicationCancellationTests.swift');
assert.equal((fixture.match(/func test/g) || []).length, 6);
for (const token of ['testCancelledBusyFallbackCannotPublishAfterSQLiteValidation', 'testCancelledHybridCannotPublishAfterSQLiteValidation',
  'testLifecycleInvalidationWithholdsBothPublicationPaths', 'testAlreadyCancelledFallbackDoesNotStartValidationOrEmbedding',
  'testSuccessfulHybridRetainsRankingAndReleasesAdmission', 'request.cancel(); release.signal()',
  'XCTAssertEqual(f.database.nativeFiles.activeToken(), token)']) assert(fixture.includes(token), token);
assert.equal(read('apps/ios/GalaxySSITests/AgentKnowledgeHybridSearchTests.swift'), old('apps/ios/GalaxySSITests/AgentKnowledgeHybridSearchTests.swift'));
console.log('Caller-task cancellation/lifecycle publication checks, unchanged retrieval kernels and six authored deterministic boundary fixture contracts passed source checks; no native execution.');
