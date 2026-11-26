// Static ownership/call-path checks only; not native execution or socket evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '1a9f176ca540b177d756ccac5be4685c5cfc9295';
const client = 'apps/ios/GalaxySSI/URLSessionCloudModelStreamClient.swift';
const fixture = 'apps/ios/GalaxySSITests/URLSessionCloudModelStreamClientTests.swift';
const read = f => require('./check-mqtt-inbound-timing-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  s = require('./check-mqtt-inbound-timing-scope.cjs').retained(f, s);
  if (f === client && s.includes('final class CloudModelStreamSessionPool {')) return s
    .replace(section(s, '// Retire only owned, completely idle sessions', 'private extension String {'), '')
    .replace('  private let sessions: CloudModelStreamSessionPool', '  private let session: URLSession')
    .replace('    sessions = CloudModelStreamSessionPool(session: session, now: elapsedMillis)', '    self.session = session ?? URLSession(configuration: Self.mobileStreamingConfiguration())')
    .replace('      let sessionLease = sessions.acquire()\n      defer { sessionLease.end() }\n      let (bytes, response) = try await sessionLease.session.bytes(for: urlRequest,', '      let (bytes, response) = try await session.bytes(for: urlRequest,');
  if (f === fixture && s.includes('  func testIdleSessionReusedBeforeMinuteAndReplacedAtTheBoundary()')) return s.replace(section(s,
    '  func testIdleSessionReusedBeforeMinuteAndReplacedAtTheBoundary()', '  func testSSEFrameAccumulatorCombinesEventAndMultilineData()'), '');
  return s;
}
function validate() {
  for (const f of [client, fixture]) assert.equal(retained(f, read(f)), old(f), f);
  const source = read(client), pool = section(source, '// Retire only owned, completely idle sessions', 'private extension String {');
  for (const token of ['private let lock = NSLock()', 'private var active = Set<UUID>()', 'owned = session == nil',
    'if owned, active.isEmpty, let idleSince, time >= idleSince', 'time.subtractingReportingOverflow(idleSince)',
    'overflow || elapsed >= 60_000', 'let session = current ?? make()', 'active.insert(id)',
    'active.remove(id) != nil', 'if active.isEmpty { idleSince = now() }', 'release = nil', 'deinit { end() }',
    '$0.finishTasksAndInvalidate()', 'return Lease(session: session) { self.finish(id) }']) assert(pool.includes(token), token);
  for (const forbidden of ['invalidateAndCancel', 'Thread.sleep', 'Task.sleep', 'httpAdditionalHeaders', 'Connection', 'retry']) assert(!pool.includes(forbidden), forbidden);
  assert(pool.indexOf('lock.unlock()\n    if let previous { retire(previous) }') > 0);
  const trial = section(source, '      if let sha256 = request.singleHTTPAdmissionSHA256', '      let sessionLease = sessions.acquire()');
  assert(trial.includes('CloudTrialHTTPTransport.send')); assert(trial.includes('return\n'));
  assert(source.includes('defer { sessionLease.end() }\n      let (bytes, response) = try await sessionLease.session.bytes'));
  assert.equal(section(source, '  static func mobileStreamingConfiguration()', '  func stream('), section(old(client), '  static func mobileStreamingConfiguration()', '  func stream('));
  const added = section(read(fixture), '  func testIdleSessionReusedBeforeMinuteAndReplacedAtTheBoundary()', '  func testSSEFrameAccumulatorCombinesEventAndMultilineData()');
  assert.equal((added.match(/func test/g) || []).length, 4);
  for (const token of ['59_999', '119_999', '1_800_000', 'first.end(); first.end()', 'XCTAssertEqual(retirements, 0)',
    'testInjectedSessionRemainsCallerOwnedAcrossIdleAndPoolDisposal', 'Int64.min', 'Int64.max']) assert(added.includes(token), token);
  const guard = 'apps/ios/tools/check-image-request-count-scope.cjs';
  assert.equal(read(guard), old(guard).replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
    "const read = f => require('./check-mobile-stream-session-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, s) {\n', "function retained(f, s) {\n  s = require('./check-mobile-stream-session-scope.cjs').retained(f, s);\n"));
  console.log('Owned idle-only session rotation, full-body leases, preserved active/trial/injected transport and four authored-only fixture contracts passed source checks; no socket/native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
