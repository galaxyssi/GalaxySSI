const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const memo = read('AgentKnowledgeIndexKeyMemo.swift');
for (const value of ['capacity: Int = 64', '(1...256).contains(capacity)', 'SymmetricKey(size: .bits256)',
  'HMAC<SHA256>.authenticationCode(for: Data(input.utf8)', 'values[token]', 'recency.removeFirst()',
  'try calculate()', 'guard self.tokenKey != nil', 'keepingCapacity: false', 'tokenKey = nil',
  'digits[Int($0 >> 4)]', 'digits[Int($0 & 15)]']) assert.ok(memo.includes(value), value);
assert.doesNotMatch(memo, /UserDefaults|Keychain|secrets\.|values\[input\]|recency\.append\(input\)/);
const database = read('AgentKnowledgeDatabase.swift');
const hashing = database.slice(database.indexOf('  private func keyedHash('), database.indexOf('  private func indexKey('));
for (const value of ['if lock.try()', 'defer { lock.unlock() }', 'if indexOperationDepth > 0',
  'indexMemo = try? AgentKnowledgeIndexKeyMemo()', 'memo.key(value, calculate:',
  'return calculateIndexKey(value)', 'AgentKnowledgeIndexKeyMemo.hex(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: indexKey()))']) {
  assert.ok(hashing.includes(value), value);
}
assert.doesNotMatch(hashing, /lock\.lock\(\)|String\(format:|lowercased\(\)|normalized/);
const scope = database.slice(database.indexOf('  private func locked<T>'));
assert.ok(scope.includes('indexOperationDepth += 1'));
assert.ok(scope.includes('indexOperationDepth -= 1'));
assert.ok(scope.includes('if indexOperationDepth == 0 { indexMemo?.close(); indexMemo = nil }'));
assert.ok(scope.indexOf('indexMemo?.close()') < scope.indexOf('lock.unlock()'));
assert.match(database, /agent\.knowledge\.index\.hmac256\.v1/);
assert.match(database, /agent\.knowledge\.row\.aes256\.v1/);
// Existing canonical encryption/authentication remains in place; the memo is
// never a replacement for ciphertext or plaintext body authentication.
assert.match(database, /cipher\.encrypt\(plaintext, purpose: purpose\(itemHash\)\)/);
assert.match(database, /cipher\.decrypt\(encrypted, expectedPurpose: purpose\(itemHash\)\)/);
const cipher = read('GalaxySSIAttachmentAtRestCipher.swift');
assert.match(cipher, /private var cachedKey: SymmetricKey\?/);
assert.match(cipher, /AES\.GCM\.seal\(/);
assert.match(cipher, /AES\.GCM\.open\(/);
assert.match(cipher, /authenticating: parsed\.authenticatedPrefix/);
assert.match(cipher, /sha256\(plaintext\) == parsed\.header\.plaintextSHA256/);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeIndexKeyMemoTests.swift'), 'utf8');
for (const name of ['RepeatedInputCalculatesOnceWithinMemo', 'LRUEvictsLeastRecentlyUsedEntryAndNeverExceedsCapacity',
  'RawUTF8InputsDoNotAliasCanonicalEquivalentStringsOrNulBoundaries', 'FailedCalculationIsNotCachedAndCanRetry',
  'CloseIsIdempotentClearsValuesAndRejectsReuse', 'CloseDuringCalculationCannotResurrectEntries',
  'CapacityBoundsAndIndependentOperationLifetimes', 'HexFormattingPreservesLeadingZerosAndAllByteValues',
  'DatabaseSharesHashWithinOperationButReleasesItBeforeNextOperation', 'DatabaseThrowingDecodeDoesNotLeakOperationMemo',
  'PersistentIndexHMACAndReopenRemainCompatible', 'SnapshotHashDoesNotWaitForOrBorrowHeldOperationMemo']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
console.log('iOS operation-owned index memo source checks passed (not native execution)');
