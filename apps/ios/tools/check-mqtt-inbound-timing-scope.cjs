// Source contracts only; no Signal/database/logging/native timing execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '2d6678d8aed5cd0d9bf9afff051efaca00c9c931';
const app = 'apps/ios/GalaxySSI/', fixture = 'apps/ios/GalaxySSITests/URLSessionCloudModelStreamClientTests.swift';
const read = f => require('./check-ordered-reply-images-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  s = require('./check-ordered-reply-images-scope.cjs').retained(f, s);
  if (f === app + 'MqttBusinessTransportRuntime.swift' && s.includes('enum MqttInboundDebugTiming {')) {
    s = s.slice(0, s.indexOf('\n// Stages are a fixed allowlist.'));
    return s.replace('import Foundation\nimport os\n\nprivate struct MqttTimedIngress {\n  let ingress: MqttAuthenticatedIngress\n  let queued = MqttInboundDebugTiming.start(.queue)\n}\n', 'import Foundation\n')
      .replaceAll('AsyncStream<MqttTimedIngress>', 'AsyncStream<MqttAuthenticatedIngress>')
      .replace('continuation.yield(MqttTimedIngress(ingress: ingress))', 'continuation.yield(ingress)')
      .replace('for await queued in ingressStream', 'for await ingress in ingressStream')
      .replace('        queued.queued.finish()\n        let ingress = queued.ingress\n', '')
      .replace('    let timing = MqttInboundDebugTiming.start(.handle)\n    defer { timing.finish() }\n', '')
      .replace('    let accepted = try MqttInboundDebugTiming.measure(.signalDecryptStore) {\n      try routes.decryptAndStore(packet, using: engine, remoteName: remoteName)\n    }', '    let accepted = try routes.decryptAndStore(packet, using: engine, remoteName: remoteName)')
      .replace('      let accepted = try MqttInboundDebugTiming.measure(.signalDecryptStore) {\n        try engine.decryptAndStore(wire, identity: identity, remoteName: remoteName,\n          ingressBroker: packet.ingress.brokerID)\n      }', '      let accepted = try engine.decryptAndStore(wire, identity: identity, remoteName: remoteName,\n        ingressBroker: packet.ingress.brokerID)')
      .replace('        let timing = MqttInboundDebugTiming.start(.inboxDispatch)\n        defer { timing.finish() }\n', '');
  }
  if (f === app + 'GalaxySSIMqttClient.swift') return s.replace('let payload = try? MqttInboundDebugTiming.measure(.wireOpen, {\n            try GalaxySSILinkProtocol.openWirePacket(opaquePayload, secret: secret)\n          })', 'let payload = try? GalaxySSILinkProtocol.openWirePacket(opaquePayload, secret: secret)');
  if (f === fixture && s.includes('  func testInboundDiagnosticStagesUseOnlyFixedNonidentifyingNames()')) return s.replace(section(s,
    '  func testInboundDiagnosticStagesUseOnlyFixedNonidentifyingNames()', '  func testSSEFrameAccumulatorCombinesEventAndMultilineData()'), '');
  return s;
}
function validate() {
  for (const f of [app + 'MqttBusinessTransportRuntime.swift', app + 'GalaxySSIMqttClient.swift', fixture]) assert.equal(retained(f, read(f)), old(f), f);
  const runtime = read(app + 'MqttBusinessTransportRuntime.swift');
  const helper = runtime.slice(runtime.indexOf('enum MqttInboundDebugTiming {'));
  for (const token of ['enum Stage: String, CaseIterable', 'case signalDecryptStore = "signal_decrypt_store"',
    'case inboxDispatch = "inbox_dispatch"', 'category: "mqtt-latency"', 'end >= start ? (end - start) / 1_000_000 : 0',
    'defer { span.finish() }', 'return try work()']) assert(helper.includes(token), token);
  const lines = helper.split('\n'); let debugDepth = 0;
  for (const line of lines) {
    if (line.trim() === '#if DEBUG') debugDepth++;
    if (/Logger\(|DispatchTime\.now|logger\.debug/.test(line)) assert(debugDepth > 0, line);
    if (line.trim() === '#endif') debugDepth--;
  }
  assert.equal(debugDepth, 0);
  assert.equal((helper.match(/logger\.debug/g) || []).length, 1);
  for (const forbidden of ['payload', 'topic', 'fingerprint', 'messageID', 'error.localizedDescription', 'Data(', 'UserDefaults', 'FileManager'])
    assert(!helper.includes(forbidden), forbidden);
  const start = section(runtime, '    var captured: AsyncStream<MqttTimedIngress>', '    started = true');
  assert(start.includes('.bufferingOldest(32)')); assert(start.includes('queued.queued.finish()'));
  assert.equal((runtime.match(/measure\(\.signalDecryptStore\)/g) || []).length, 2);
  assert(read(app + 'GalaxySSIMqttClient.swift').includes('try? MqttInboundDebugTiming.measure(.wireOpen'));
  const tests = section(read(fixture), '  func testInboundDiagnosticStagesUseOnlyFixedNonidentifyingNames()', '  func testSSEFrameAccumulatorCombinesEventAndMultilineData()');
  assert.equal((tests.match(/func test/g) || []).length, 3);
  for (const token of ['UInt64.max', 'XCTAssertEqual(calls, 2)', 'throw Failure.fixture']) assert(tests.includes(token), token);
  const poolGuard = 'apps/ios/tools/check-mobile-stream-session-scope.cjs';
  assert.equal(read(poolGuard), old(poolGuard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');", "const read = f => require('./check-mqtt-inbound-timing-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, s) {\n', "function retained(f, s) {\n  s = require('./check-mqtt-inbound-timing-scope.cjs').retained(f, s);\n"));
  const managed = 'apps/ios/tools/check-managed-raw-attachments-scope.cjs';
  assert.equal(read(managed), old(managed)
    .replace("  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));", "  require('./check-mqtt-inbound-timing-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-mqtt-inbound-timing-scope.cjs').retained(file, source);\n"));
  const probe = 'apps/ios/tools/check-desktop-probe-owner-scope.cjs';
  assert.equal(read(probe), old(probe)
    .replace("const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');", "const read = file => require('./check-mqtt-inbound-timing-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-mqtt-inbound-timing-scope.cjs').retained(file, source);\n"));
  for (const name of ['MqttSignalStateJournal', 'MqttPeerRoutes', 'MqttBusinessInbox', 'MqttDeliveryDispatch']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'));
  console.log('DEBUG-only fixed-stage MQTT clocks/logs, unchanged ingress bound/Signal/receipts/dispatch and three authored-only fixture contracts passed source checks; no native timing acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
