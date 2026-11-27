const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'e6bd822b0d1f08d6dd445839b87179a72f42da3c';
const raw = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const read = name => raw(app + name);
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  if (file === app + 'AgentKnowledgeDatabase.swift' && source.includes('  private let indexMemoScope')) return source
    .replace('  private let indexMemoScope = AgentKnowledgeIndexOperationScope()\n', '')
    .replace('primarySnapshotLease: primarySnapshotLease,\n      indexMemoScope: indexMemoScope)', 'primarySnapshotLease: primarySnapshotLease)')
    .replace(section(source, '  private func keyedHash(', '  private func indexKey('),
      section(old(file), '  private func keyedHash(', '  private func indexKey('))
    .replace('return try indexMemoScope.withOperation(body)', 'return try body()');
  if (file === app + 'AgentKnowledgeCommittedReadView.swift' && source.includes('  private let indexMemoScope')) return source
    .replace('  private let indexMemoScope: AgentKnowledgeIndexOperationScope?\n', '')
    .replace('    indexMemoScope: AgentKnowledgeIndexOperationScope? = nil,\n', '')
    .replace('    self.indexMemoScope = indexMemoScope\n', '')
    .replace(section(source, '  func read<T>', '  private func readWithinOperation<T>'), '')
    .replace('  private func readWithinOperation<T>', '  func read<T>');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !/AgentKnowledgeIndexKeyMemo(?:Tests)?\.swift/.test(line)).join('\n');
  return source;
}
function validate() {
const memo = read('AgentKnowledgeIndexKeyMemo.swift');
for (const value of ['capacity: Int = 64', '(1...256).contains(capacity)', 'SymmetricKey(size: .bits256)',
  'HMAC<SHA256>.authenticationCode(for: Data(input.utf8)', 'values[token]', 'recency.removeFirst()',
  'try calculate()', 'guard self.tokenKey != nil', 'keepingCapacity: false', 'tokenKey = nil',
  'digits[Int($0 >> 4)]', 'digits[Int($0 & 15)]']) assert.ok(memo.includes(value), value);
assert.doesNotMatch(memo, /UserDefaults|Keychain|secrets\.|values\[input\]|recency\.append\(input\)/);
const database = read('AgentKnowledgeDatabase.swift');
const hashing = database.slice(database.indexOf('  private func keyedHash('), database.indexOf('  private func indexKey('));
for (const value of ['indexMemoScope.key(value, calculate: { calculateIndexKey(value) })',
  'AgentKnowledgeIndexKeyMemo.hex(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: indexKey()))']) {
  assert.ok(hashing.includes(value), value);
}
assert.doesNotMatch(hashing, /lock\.lock\(\)|lock\.try\(\)|String\(format:|lowercased\(\)|normalized/);
const scope = database.slice(database.indexOf('  private func locked<T>'));
assert.ok(scope.includes('defer { lock.unlock() }'));
assert.ok(scope.includes('return try indexMemoScope.withOperation(body)'));
assert.ok(database.includes('primarySnapshotLease: primarySnapshotLease,\n      indexMemoScope: indexMemoScope)'));
const view = read('AgentKnowledgeCommittedReadView.swift');
assert.ok(view.includes('return try indexMemoScope.withOperation { try readWithinOperation(body) }'));
for (const value of ['Thread.current.threadDictionary', 'UUID().uuidString', 'if dictionary[slot] is Operation',
  'dictionary[slot] = operation', 'defer {', 'dictionary.removeObject(forKey: slot)', 'operation.memo?.close()',
  'Thread.current.threadDictionary[slot] as? Operation', 'operation.memo = try? AgentKnowledgeIndexKeyMemo()']) assert.ok(memo.includes(value), value);
assert.match(database, /agent\.knowledge\.index\.hmac256\.v1/);
assert.match(database, /agent\.knowledge\.row\.aes256\.v1/);
// Existing canonical encryption/authentication remains in place; the memo is
// never a replacement for ciphertext or plaintext body authentication.
assert.ok(database.includes('primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database)'));
assert.match(read('AgentKnowledgePrimaryPartitions.swift'), /cipher\.encrypt\(encoded, purpose: framePurpose\(/);
assert.match(database, /cipher\.decrypt\(encrypted, expectedPurpose: purpose\(itemHash\)\)/);
const cipher = read('GalaxySSIAttachmentAtRestCipher.swift');
assert.match(cipher, /private var cachedKey: SymmetricKey\?/);
assert.match(cipher, /AES\.GCM\.seal\(/);
assert.match(cipher, /AES\.GCM\.open\(/);
assert.match(cipher, /authenticating: parsed\.authenticatedPrefix/);
assert.match(cipher, /sha256\(plaintext\) == parsed\.header\.plaintextSHA256/);
const tests = raw('apps/ios/GalaxySSITests/AgentKnowledgeIndexKeyMemoTests.swift');
for (const name of ['RepeatedInputCalculatesOnceWithinMemo', 'LRUEvictsLeastRecentlyUsedEntryAndNeverExceedsCapacity',
  'RawUTF8InputsDoNotAliasCanonicalEquivalentStringsOrNulBoundaries', 'FailedCalculationIsNotCachedAndCanRetry',
  'CloseIsIdempotentClearsValuesAndRejectsReuse', 'CloseDuringCalculationCannotResurrectEntries',
  'CapacityBoundsAndIndependentOperationLifetimes', 'HexFormattingPreservesLeadingZerosAndAllByteValues',
  'DatabaseSharesHashWithinOperationButReleasesItBeforeNextOperation', 'DatabaseThrowingDecodeDoesNotLeakOperationMemo',
  'PersistentIndexHMACAndReopenRemainCompatible', 'SnapshotHashDoesNotWaitForOrBorrowHeldOperationMemo',
  'NestedScopeSharesOnlyItsOuterOperationAndDropsOnReturn', 'ThrowingScopeClearsMemoAndUnscopedHashesAreNeverRetained',
  'DifferentDatabaseScopesNeverBorrowEachOthersEntryOnOneThread', 'ConcurrentReadersOwnSeparateEntriesWithoutBlockingEachOther',
  'CommittedViewBracketsMemoAndDropsItAfterThrowingRead', 'ClosingViewInsideReadCannotRetainAnOperationMemo']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
assert.equal((tests.match(/func test/g) || []).length, 18);
for (const file of [app + 'AgentKnowledgeDatabase.swift', app + 'AgentKnowledgeCommittedReadView.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) {
  assert.equal(retained(file, raw(file)), old(file), 'Retain complete main outside operation hooks: ' + file);
  assert.equal(retained(file, retained(file, raw(file))), old(file), 'Idempotent older-check view');
}
const memoFile = app + 'AgentKnowledgeIndexKeyMemo.swift';
const priorMemo = cp.execFileSync('git', ['show', '5c21d5994a898360781a2ed836f66a5c0ea9815c:' + memoFile], {cwd: root, encoding: 'utf8'}).replace(/\r\n/g, '\n');
assert.equal(memo.slice(0, memo.indexOf('// All bodies are synchronous.')).trimEnd(), priorMemo.trimEnd(), 'Original LRU/UTF8/close kernel unchanged');
const guard = 'apps/ios/tools/check-knowledge-read-connections-scope.cjs';
assert.equal(raw(guard), old(guard)
  .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
    "const read = f => require('./check-knowledge-index-memo-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
  .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-index-memo-scope.cjs').retained(f, source);\n"));
console.log('iOS thread/operation-owned write and committed-read memo, exact retained main/crypto kernels and eighteen authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
