// Source contracts only. No Swift compile, native network, SwiftUI render or XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '13917b93ccad3e3dd8511229dc0cac1a86c514df', app = 'apps/ios/GalaxySSI/';
const syncedMain = 'c1e1529ed1160a34564eb57606dfd209fc7a61ba';
const read = file => require('./check-mqtt-network-metrics-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const old = (file, ref = base) => cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(file, s) {
  s = require('./check-mqtt-network-metrics-scope.cjs').retained(file, s);
  if (file === app + 'GalaxySSIMqttClient.swift' && s.includes('  func diagnosticSnapshot()')) return s
    .replace('  private var connectionAttempts: Int64 = 0\n', '')
    .replace(section(s, '  func diagnosticSnapshot()', '  func disconnect()'), '')
    .replace('    if connectionAttempts < Int64.max { connectionAttempts += 1 }\n', '');
  if (file === app + 'GalaxySSIMqttBrokerPool.swift' && s.includes('  func diagnostics(now:'))
    return s.replace(section(s, '  func diagnostics(now:', '  func wakeForTraffic()'), '');
  if (file === app + 'MqttBrokerPath.swift' && s.includes('struct MqttBrokerPathDiagnostics:')) return s
    .replace('  func diagnosticSnapshot() async -> MqttBrokerPathDiagnostics?\n', '')
    .replace('  func diagnosticSnapshot() async -> MqttBrokerPathDiagnostics? { nil }\n', '')
    .replace(section(s, 'struct MqttBrokerPathDiagnostics:', '// Unknown is permitted'), '');
  if (file === app + 'MqttBusinessTransportRuntime.swift' && s.includes('  func transportDiagnostics()'))
    return s.replace(section(s, '  func transportDiagnostics()', '  func enqueue(_ requests:'), '');
  if (file === app + 'GalaxySSIServices.swift' && s.includes('  func mqttTransportDiagnostics()'))
    return s.replace(section(s, '  func mqttTransportDiagnostics()', '  let attachmentTransferStore:'), '');
  if (file.endsWith('MqttBrokerPoolTests.swift') && s.includes('// Observational diagnostic fixtures;')) return s
    .slice(0, s.indexOf('// Observational diagnostic fixtures;')).trimEnd().concat('\n')
    .replace('  var diagnosticsValue: MqttBrokerPathDiagnostics?\n  var diagnosticsRead: (() async -> MqttBrokerPathDiagnostics?)?\n', '')
    .replace(section(s, '  func diagnosticSnapshot()', '  func disconnect()'), '');
  if (file === app + 'GalaxySSILinkDiagnosticsView.swift' && s.includes('  private func mqttPathRow(')) return s
    .replace('  @Environment(\\.scenePhase) private var scenePhase\n  @EnvironmentObject private var coordinator: MessageCoordinator\n', '')
    .replace('  @State private var transport = MqttTransportDiagnostics.unavailable\n', '')
    .replace(section(s, '      Section(header: Text(t("mqtt_diagnostics_paths"', '      Section(header: Text(t("protocol_transport_summary"'), '')
    .replace(section(s, '    .task(id: scenePhase)', '  private func mqttPathRow('), '  }\n\n')
    .replace(section(s, '  private func mqttPathRow(', '  private func refresh()'), '');
  if (file.endsWith('zh-Hans.lproj/Localizable.strings') && s.includes('"mqtt_diagnostics_paths"'))
    return s.slice(0, s.indexOf('"mqtt_diagnostics_paths"')).trimEnd() + '\n';
  return s;
}
function includes(s, values) { for (const value of values) assert(s.includes(value), value); }
function validate() {
  for (const name of ['GalaxySSIMqttClient', 'GalaxySSIMqttBrokerPool', 'MqttBrokerPath', 'MqttBusinessTransportRuntime',
    'GalaxySSIServices', 'GalaxySSILinkDiagnosticsView']) {
    const file = app + name + '.swift';
    const expected = old(file, name === 'GalaxySSIServices' ? syncedMain : base);
    assert.equal(retained(file, read(file)), expected, 'Only declared observational diagnostic hooks: ' + name);
    assert.equal(retained(file, retained(file, read(file))), expected, 'Idempotent retained normalization: ' + name);
  }
  const client = read(app + 'GalaxySSIMqttClient.swift');
  const capture = section(client, '  func diagnosticSnapshot()', '  func disconnect()');
  includes(capture, ['queue.async', 'Set(self.subscriptions)', 'self.pendingSubscriptions.values.reduce(into: Set<String>())',
    'self.intentionallyDisconnected || self.networkMonitor == nil', 'networkAvailable: self.networkAvailability.permitsConnection',
    'connecting: self.connection != nil && !self.connected', '!desired.isEmpty && self.activeSubscriptions.isSuperset(of: desired)',
    'self.reconnectWorkItem != nil || self.transportRecoveryInProgress', 'self.endpoint.id', 'self.configurationID',
    'max(0, self.connectionAttempts - 1)', 'self.pendingPacketPublishes.count', 'self.inFlightPublishes.count']);
  assert(!/wakeForTraffic|sendFrame|start\(|connect\(|checkTransportOnDemand|Date\(|print\(/.test(capture));
  const start = section(client, '  private func start()', '  private func sendConnect()');
  assert(start.indexOf('networkAvailability.permitsConnection') < start.indexOf('connectionAttempts += 1'));
  assert(start.indexOf('connectionAttempts += 1') < start.indexOf('NWConnection('));
  includes(start, ['if connectionAttempts < Int64.max']);
  const pool = read(app + 'GalaxySSIMqttBrokerPool.swift');
  const query = section(pool, '  func diagnostics(now:', '  func wakeForTraffic()');
  includes(query, ['self.running ? (self.configurationID, self.paths) : nil', 'for endpoint in MqttBrokerEndpoint.catalog',
    'guard !Task.isCancelled else { return .unavailable }', 'await path.diagnosticSnapshot()', 'value.brokerID == endpoint.id',
    'value.configurationID == configuration', 'self.configurationID == configuration', 'self.policy.diagnostics(now: now).verifiedDelivery',
    'return Task.isCancelled ? .unavailable : result']);
  assert(!/publish\(|configurePath|onPathState\?\(|synchronize\(|setNetwork\(/.test(query));
  const runtime = section(read(app + 'MqttBusinessTransportRuntime.swift'), '  func transportDiagnostics()', '  func enqueue(_ requests:');
  includes(runtime, ['guard started, !stopped', 'await pool.diagnostics(now: monotonic())', 'return started && !stopped ? snapshot : .unavailable']);
  const owner = section(read(app + 'GalaxySSIServices.swift'), '  func mqttTransportDiagnostics()', '  let attachmentTransferStore:');
  includes(owner, ['if let runtime = journalMqttRuntime', 'await runtime.transportDiagnostics()', 'journalMqttRuntime === runtime',
    'guard usesLegacyMqtt', 'await mqttClient.diagnosticSnapshot()', 'journalMqttRuntime == nil', 'verifiedDelivery: [:]']);
  const view = read(app + 'GalaxySSILinkDiagnosticsView.swift');
  includes(view, ['ForEach(MqttBrokerEndpoint.catalog, id: \\.id)', 'path?.state ?? .unknown', '.task(id: scenePhase)',
    'guard scenePhase == .active', 'await coordinator.mqttTransportDiagnostics()', 'guard !Task.isCancelled',
    'Task.sleep(nanoseconds: 1_000_000_000)', 'stats.samples > 0', 'stats.samples >= 30, let value = stats.p95',
    'path.pendingSubscriptions', 'path.queuedPublishes', 'path.inflightPublishes', '.fixedSize(horizontal: false, vertical: true)']);
  const stringsFile = app + 'zh-Hans.lproj/Localizable.strings', strings = read(stringsFile);
  assert.equal(retained(stringsFile, strings), old(stringsFile, syncedMain), 'Append only diagnostic resource keys');
  const keys = [...view.matchAll(/t\("(mqtt_diagnostics_[^"]+)"/g)].map(m => m[1]);
  assert.equal(new Set(keys).size, 14);
  for (const key of new Set(keys)) assert.equal(strings.split('"' + key + '" =').length, 2, key);
  const testFile = 'apps/ios/GalaxySSITests/MqttBrokerPoolTests.swift', tests = read(testFile);
  assert.equal(retained(testFile, tests), old(testFile), 'Retain earlier network and broker fixtures');
  const added = tests.slice(tests.indexOf('// Observational diagnostic fixtures;'));
  assert.equal((added.match(/func test/g) || []).length, 9);
  includes(added, ['testDiagnosticStateSeparatesStoppedOfflineConnectingAndReceiveReadiness',
    'testUnstartedNativeClientDiagnosticsDoNotInventConnectionOrActivity', 'testPoolDiagnosticsAreUnavailableUntilStarted',
    'testPoolDiagnosticsPreserveObservedCountsWithoutPublishingOrReadinessChanges', 'testUnobservedPathsStayAbsentInsteadOfReceivingSyntheticStates',
    'testDiagnosticSamplesRejectWrongBrokerAndConfiguration', 'testReconfigurationDuringDiagnosticReadDiscardsEntireOldOwnerSnapshot',
    'testDisconnectDuringDiagnosticReadDoesNotPublishStaleReadyState', 'testCancelledDiagnosticReadDoesNotReturnReadyState']);
  for (const name of ['MqttMultipathPolicy', 'MqttBusinessInbox', 'MqttBusinessOutbox', 'MqttSignalStateJournal',
    'MqttDurableChunks', 'MqttPeerRoutes', 'MqttPeerRouteSession', 'MqttDeliveryDispatch', 'MqttBusinessReceipts'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), 'Unchanged scheduling/receipt/durable kernel: ' + name);
  const normalizer = "require('./check-mqtt-path-diagnostics-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'))";
  const rawRead = "fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')";
  for (const name of ['check-mqtt-network-lifecycle-scope.cjs', 'check-active-native-observation-scope.cjs']) {
    const file = 'apps/ios/tools/' + name;
    let expected = old(file, name.includes('active-native') ? syncedMain : base).replace('const read = file => ' + rawRead + ';', 'const read = file => ' + normalizer + ';');
    if (name.includes('network-lifecycle')) expected = expected
      .replace("const old = file => cp.execFileSync('git', ['show', base + ':' + file]", "const old = (file, ref = base) => cp.execFileSync('git', ['show', ref + ':' + file]")
      .replace("old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), 'No deployment, source registration or version churn'", "old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'c1e1529ed1160a34564eb57606dfd209fc7a61ba'), 'Retain latest main deployment, source registration and version'");
    if (name.includes('active-native')) expected = expected.replace('function retained(file, source) {\n',
      "function retained(file, source) {\n  source = require('./check-mqtt-path-diagnostics-scope.cjs').retained(file, source);\n");
    assert.equal(read(file), expected, 'Retain earlier checks beyond declared diagnostics: ' + name);
  }
  assert.equal(read('apps/ios/tools/check-desktop-probe-owner-scope.cjs'), old('apps/ios/tools/check-desktop-probe-owner-scope.cjs', syncedMain));
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj', syncedMain));
  console.log('Actual owner-fenced per-path MQTT diagnostics, localized foreground presentation, unchanged delivery kernels and nine authored-only observational fixtures passed source checks; no native/UI acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
