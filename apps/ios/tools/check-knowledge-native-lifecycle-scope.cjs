const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const files = read('GalaxySSI/AgentKnowledgeNativeFiles.swift');
assert.match(files, /SymmetricKey\(size: .bits256\)/);
assert.match(files, /HKDF<SHA256>.deriveKey/);
assert.match(files, /HMAC<SHA256>.authenticationCode\(for: identity/);
assert.match(files, /secrets.setString\(key.base64EncodedString\(\), account: masterKeyAccount\)/);
assert.match(files, /secrets.delete\(account: masterKeyAccount\)/);
assert.match(files, /guard !FileManager.default.fileExists\(atPath: rootDirectory.path\)/);
assert.match(files, /\.protectionKey: FileProtectionType.complete/);
assert.match(files, /isExcludedFromBackup = true/);
assert.match(files, /generation == expected/);
assert.match(files, /bridge.cancel\(\); bridge.close\(\)/);
assert.match(files, /willResignActiveNotification/);
assert.match(files, /protectedDataWillBecomeUnavailableNotification/);
assert.match(files, /attributes\[.type\] as\? FileAttributeType == .typeDirectory/);
assert.match(files, /defer \{ key.wipeSensitive\(\) \}/);
assert.doesNotMatch(files, /write\(to:|\.all\(\)/);
const database = read('GalaxySSI/AgentKnowledgeDatabase.swift');
assert.match(database, /CREATE TABLE IF NOT EXISTS knowledge_vector_native_enrollment/);
assert.match(database, /\(1\.\.\.64\).contains\(pageSize\)/);
assert.match(database, /SELECT item_hash FROM knowledge_items WHERE item_hash > \? ORDER BY item_hash ASC LIMIT \?/);
assert.match(database, /UPDATE knowledge_vector_native_enrollment SET after_item_hash = \?, complete = \?/);
assert.match(database, /if let nativeContract/);
assert.match(database, /vectorProvenanceHash\(checkpoint.provenance\) == nativeContract/);
assert.match(database, /contract_hash != excluded.contract_hash/);
assert.match(database, /ordinalCount == Int64\(expectedCount\)/);
const controller = read('GalaxySSI/AgentKnowledgeSemanticModel.swift');
assert.match(controller, /database.maintainNativeVectorEnrollment/);
assert.match(controller, /if indexed == 0 && !enrollmentPending && nativeEnrollmentComplete/);
assert.match(controller, /database.nativeFiles.destroy\(\)/);
assert.match(controller, /database.nativeFiles.invalidate\(\)/);
const tests = read('GalaxySSITests/AgentKnowledgeDatabaseTests.swift');
for (const name of ['NativeEnrollmentResumesBoundedLegacyMigration',
  'LegacyVectorMigrationRequiresRealRangesAndPublishesReplacement', 'NativeEnrollmentSkipsCurrentRangesWithoutRepublishing',
  'NativeFileIdentityIsolatesDatabaseModelEpochAndInvalidatesTokens', 'NativeFileResetDeletesDerivedFilesAndMasterKey',
  'NativeFilesRejectMissingKeyAndSymlinkWithoutReplacingSecrets']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
assert.match(read('GalaxySSI.xcodeproj/project.pbxproj'), /AgentKnowledgeNativeFiles.swift in Sources/);
console.log('iOS native file lifecycle and legacy enrollment source checks passed; no native execution');
