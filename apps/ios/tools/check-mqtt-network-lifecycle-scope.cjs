// Source contracts only. Does not run Swift, NWPathMonitor, timers, sockets or XCTest.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701', app = 'apps/ios/GalaxySSI/';
const read = file => require('./check-mqtt-path-diagnostics-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function includes(source, values) { for (const value of values) assert(source.includes(value), value); }
const clientFile = app + 'GalaxySSIMqttClient.swift', client = read(clientFile);
const network = section(client, '  private func applyNetworkAvailability(', '  private func checkTransportOnDemand(');
includes(network, ['switch networkAvailability.update(available)', 'case .none:', 'case .lost:',
  'reconnectWorkItem?.cancel()', 'reconnectWorkItem = nil',
  'if let connection { handleTransportFailure(for: connection) }', 'else { setConnected(false) }',
  'case .restored:', 'checkTransportOnDemand(networkRecovered: true)']);
assert(network.indexOf('reconnectWorkItem?.cancel()') < network.indexOf('handleTransportFailure'));
assert(!/outbox|inbox|journal|Signal|clear\(/.test(network.replace(/\/\/[^\n]*/g, '')));
for (const [start, end] of [
  ['  private func start()', '  private func sendConnect()'],
  ['  private func hasLiveTransport()', '  func wakeForTraffic()'],
  ['  private func checkTransportOnDemand(', '  private func scheduleSubscriptionWatchdog()'],
  ['  private func scheduleReconnect()', '\n}\n']
]) includes(section(client, start, end), ['networkAvailability.permitsConnection']);
const monitor = section(client, '  private func monitorNetwork()', '  private func applyNetworkAvailability(');
includes(monitor, ['self.networkMonitor === monitor', 'self.applyNetworkAvailability(path.status == .satisfied)', 'monitor.start(queue: queue)']);
assert(monitor.indexOf('self.networkMonitor === monitor') < monitor.indexOf('self.applyNetworkAvailability'));
const stopped = section(client, '  private func stopTransport()', '  private var pathSnapshot:');
includes(stopped, ['intentionallyDisconnected = true', 'networkMonitor?.cancel()', 'networkMonitor = nil', 'networkAvailability.reset()']);
const failure = section(client, '  private func handleTransportFailure(', '  private func resetOutboundInflightForReconnect()');
includes(failure, ['guard connection === failedConnection', 'connection = nil', 'failedConnection.cancel()',
  'resetOutboundInflightForReconnect()', 'setConnected(false)', 'scheduleReconnect()']);
const reset = section(client, '  private func setConnected(', '  private func scheduleBrokerAckWatchdog()');
includes(reset, ['activeSubscriptions.removeAll()', 'pendingSubscriptions.removeAll()', 'subscriptionSentAt.removeAll()', 'onPathState?(pathSnapshot)']);
assert(reset.indexOf('activeSubscriptions.removeAll()') < reset.indexOf('onPathState?(pathSnapshot)'));
const retainedClient = client
  .replace('  private var networkAvailability = MqttNetworkAvailability()', '  private var networkWasAvailable: Bool?')
  .replace('    networkAvailability.reset()', '    networkWasAvailable = nil')
  .replace('guard connection == nil, !intentionallyDisconnected, networkAvailability.permitsConnection else', 'guard connection == nil, !intentionallyDisconnected else')
  .replace('guard networkAvailability.permitsConnection, connected else', 'guard connected else')
  .replace('      self.applyNetworkAvailability(path.status == .satisfied)',
    '      let available = path.status == .satisfied\n      let recovered = available && self.networkWasAvailable == false\n      self.networkWasAvailable = available\n      if recovered { self.checkTransportOnDemand(networkRecovered: true) }')
  .replace(network, '')
  .replace('guard !intentionallyDisconnected, !transportRecoveryInProgress, networkMonitor != nil,\n          networkAvailability.permitsConnection else',
    'guard !intentionallyDisconnected, !transportRecoveryInProgress, networkMonitor != nil else')
  .replace('guard connection == nil, networkAvailability.permitsConnection,', 'guard connection == nil, networkWasAvailable != false,')
  .replace('guard connection == nil, !intentionallyDisconnected, !transportRecoveryInProgress,\n          networkAvailability.permitsConnection, reconnectWorkItem == nil else',
    'guard connection == nil, !intentionallyDisconnected, !transportRecoveryInProgress, reconnectWorkItem == nil else');
assert.equal(retainedClient, old(clientFile), 'Retain all TLS, parser, wire, Signal, queue, retry, fragment and PUBACK behavior outside network gate');
const pathFile = app + 'MqttBrokerPath.swift', paths = read(pathFile);
const state = section(paths, '// Unknown is permitted', 'struct MqttConnectionLiveness {');
includes(state, ['struct MqttNetworkAvailability', 'private(set) var available: Bool?',
  'var permitsConnection: Bool { available != false }', 'let previous = available', 'available = value',
  'guard previous != value else { return .none }', 'if !value { return .lost }',
  'return previous == false ? .restored : .none', 'mutating func reset() { available = nil }']);
assert.equal(paths.replace(state, ''), old(pathFile), 'Retain broker catalog, subscription, generation, authorization and keepalive policies');
const testFile = 'apps/ios/GalaxySSITests/MqttBrokerPoolTests.swift', tests = read(testFile);
const marker = '// Synthetic policy/pool fixtures; no NWConnection or live broker is exercised.';
const added = tests.slice(tests.indexOf(marker));
assert.equal(tests.slice(0, tests.indexOf(marker)).trimEnd(), old(testFile).trimEnd(), 'Retain all existing broker fixtures and fake path');
assert.equal((added.match(/func test/g) || []).length, 10);
includes(added, ['testNetworkUnknownAllowsInitialConnectionWithoutInventingRecovery',
  'testInitialOfflineObservationWithdrawsAndBlocksConnection', 'testRepeatedNetworkCallbacksDoNotRepeatRecoveryOrWithdrawal',
  'testEachOfflineIntervalRequiresANewRestoration', 'testStoppedMonitorStateDoesNotLeakIntoItsReplacement',
  'testNetworkObservationsRemainPathLocal', 'testOfflineSnapshotWithdrawsReadyGenerationAndRefusesOldPublication',
  'testRestorationRequiresFreshGenerationAndAllSubscriptionAcknowledgements',
  'testOfflineAndOldGenerationIngressAreNotDeliveredAfterRecovery', 'testOneOfflineBrokerDoesNotWithdrawAnotherReadyPath',
  'XCTAssertEqual(result, .failed)', 'XCTAssertEqual(stale, .failed)', 'XCTAssertEqual(accepted, .queued)',
  'XCTAssertTrue(partial.isEmpty)', 'XCTAssertEqual(recorder.count, 1)', 'XCTAssertEqual(remaining, ["hivemq": 1])']);
for (const name of ['GalaxySSIMqttBrokerPool', 'MqttBusinessTransportRuntime', 'MqttSignalStateJournal',
  'MqttBusinessInbox', 'MqttBusinessOutbox', 'MqttDurableChunks', 'MqttPeerRoutes', 'MqttPeerRouteSession',
  'MqttMultipathPolicy', 'MqttDeliveryEnvelope', 'MqttBusinessReceipts', 'MqttDeliveryDispatch'])
  assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), 'Unchanged business/protocol kernel: ' + name);
assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), 'No deployment, source registration or version churn');
console.log('MQTT offline withdrawal, all connection gates, exact retained protocol/durable behavior and ten authored-only policy/pool fixtures passed source checks; no native acceptance.');
