const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const build = read('tools/build-knowledge-native.cjs');
assert.match(build, /process.platform !== 'darwin'/);
assert.match(build, /aarch64-apple-ios-sim/);
assert.match(build, /x86_64-apple-ios/);
assert.match(build, /const toolchain = '1.97.1'/);
assert.match(build, /'--locked', '--release', '--target'/);
assert.match(build, /IPHONEOS_DEPLOYMENT_TARGET = '15.0'/);
assert.match(build, /-install_name,@rpath\/GalaxySSIMemory.framework\/GalaxySSIMemory/);
assert.match(build, /-exported_symbols_list/);
assert.match(build, /'dyld_info', '-exports'/);
assert.match(build, /Bundled SQLite symbols escaped/);
const exportedNames = read('memory-native/exports.txt').trim().split(/\r?\n/);
assert.equal(exportedNames.length, 8);
assert.equal(new Set(exportedNames).size, 8);
for (const symbol of exportedNames) assert.match(symbol, /^_gs_memory_[a-z_]+$/);
assert.match(read('memory-native/include/module.modulemap'), /framework module GalaxySSIMemory/);
assert.match(read('memory-native/Info.plist'), /MinimumOSVersion<\/key><string>15.0<\/string>/);
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
assert.match(project, /ATTRIBUTES = \(CodeSignOnCopy, RemoveHeadersOnCopy,/);
assert.match(project, /dstSubfolderSpec = 10/);
assert.match(project, /node.*build-knowledge-native.cjs/);
for (const name of ['AgentKnowledgeNativeWire.swift', 'AgentKnowledgeNativeBridge.swift']) {
  assert.ok(project.includes(`${name} in Sources`), name);
  assert.ok(project.includes(`path = ${name};`), name);
}
const native = read('GalaxySSI/AgentKnowledgeNativeBridge.swift');
assert.match(native, /import GalaxySSIMemory/);
assert.doesNotMatch(native, /canImport\(GalaxySSIMemory\)/);
assert.match(native, /deinit \{ close\(\) \}/);
assert.match(native, /handle = 0/);
assert.match(native, /data.wipeSensitive\(\)/);
assert.match(native, /addingReportingOverflow/);
assert.match(native, /checkpoint.provenance == page.checkpoints\[0\].provenance/);
assert.doesNotMatch(native, /\bawait\b/);
const wire = read('GalaxySSI/AgentKnowledgeNativeWire.swift');
for (const magic of ['GSE1', 'GSC1', 'GSM1', 'GSN1']) assert.ok(wire.includes(`"${magic}"`));
assert.match(wire, /count <= 256/);
assert.match(wire, /value <= UInt64\(Int64.max\)/);
assert.match(wire, /pending.next < pending.event.chunks/);
assert.match(wire, /index == bytes.count/);
const tests = read('GalaxySSITests/AgentKnowledgeDatabaseTests.swift');
for (const name of ['NativeEventUsesExactRustLittleEndianRecord', 'NativeCheckpointDecodesCommittedAndPendingProgress',
  'NativeCheckpointRejectsInvalidFlagsAndRemovedPendingEvents', 'NativeMatchesValidateCountsBoundsAndFiniteScores']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
console.log('iOS native memory framework/Swift source checks passed; not an Xcode build or runtime result');
