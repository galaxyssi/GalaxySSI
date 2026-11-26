// Source contracts only; no native timing, multipath, receipt, restart or capacity acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '3b86319460c7bdc9ea73f037c8d6817262f458de';
const read = file => require('./check-supervised-answer-preview-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const cache = new Map();
function old(file) { if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n')); return cache.get(file); }
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  source = require('./check-supervised-answer-preview-scope.cjs').retained(file, source);
  if (file.endsWith('check-progressive-tool-catalog-scope.cjs')) return source
    .replace("const read = file => require('./check-interactive-request-hedge-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-interactive-request-hedge-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('MqttMultipathPolicy.swift') && source.includes('interactiveFinal: Bool')) return source
    .replace('eligible: [String: Int64]? = nil,\n            interactiveFinal: Bool = false)', 'eligible: [String: Int64]? = nil)')
    .replace(section(source, '      if interactiveFinal, [Traffic.message, .final].contains(traffic),', '      if wireBytes <= 65_536,'), '');
  if (file.endsWith('MqttDeliveryDispatch.swift')) return source.replace('    var interactiveFinal = false\n', '')
    .replace('eligible: eligible,\n                       interactiveFinal: delivery.interactiveFinal)', 'eligible: eligible)');
  if (file.endsWith('MqttBusinessSendDrain.swift')) return source
    .replace('             interactiveFinal: @Sendable (MqttBusinessOutbox.Entry) async throws -> Bool = { _ in false },\n', '')
    .replace('          var interactive = false\n', '').replace('            interactive = try await interactiveFinal(item)\n', '')
    .replace('guard var direct = try routes.prepareDelivery', 'guard let direct = try routes.prepareDelivery')
    .replace('              direct.interactiveFinal = interactive\n', '');
  if (file.endsWith('MqttBusinessTransportRuntime.swift') && source.includes('  private func isInteractiveConnectorRequest(')) return source
    .replace('    let outbound = try await sends.drain(identities: identities, validatedNetwork: validatedNetwork,\n      interactiveFinal: { [weak self] entry in try await self?.isInteractiveConnectorRequest(entry) ?? false }) { [weak self] entry in',
      '    let outbound = try await sends.drain(identities: identities, validatedNetwork: validatedNetwork) { [weak self] entry in')
    .replace(section(source, '  private func isInteractiveConnectorRequest(', '  private func authorizeConnectorSend('), '');
  if (file.endsWith('MqttMultipathPolicyTests.swift') && source.includes('  func testInteractiveDesktopRequestsHedge')) return source
    .replace(section(source, '  func testInteractiveDesktopRequestsHedge', '  private let brokers ='), '');
  if (file.endsWith('MqttDeliveryDispatchTests.swift') && source.includes('  func testInteractiveRequestCopiesShare')) return source
    .replace(section(source, '  func testInteractiveRequestCopiesShare', '  func testCommittedReceiptStopsCopies'), '');
  return source;
}
function validate() {
  for (const file of [app + 'MqttMultipathPolicy.swift', app + 'MqttDeliveryDispatch.swift', app + 'MqttBusinessSendDrain.swift',
    app + 'MqttBusinessTransportRuntime.swift', 'apps/ios/tools/check-progressive-tool-catalog-scope.cjs',
    'apps/ios/GalaxySSITests/MqttMultipathPolicyTests.swift', 'apps/ios/GalaxySSITests/MqttDeliveryDispatchTests.swift'])
    assert.equal(retained(file, read(file)), old(file), file);
  const policy = read(app + 'MqttMultipathPolicy.swift');
  const branch = section(policy, '      if interactiveFinal,', '      if wireBytes <= 65_536,');
  for (const token of ['[Traffic.message, .final].contains(traffic)', 'wireBytes <= 256 * 1024', 'candidates.dropFirst()',
    'delayMillis: 250 * Int64(index + 1)', 'generation: paths[broker]!.generation']) assert(branch.includes(token), token);
  assert(policy.indexOf('eligible.map { $0[broker] == path.generation }') < policy.indexOf('      if interactiveFinal,'));
  const runtime = read(app + 'MqttBusinessTransportRuntime.swift');
  const marker = section(runtime, '  private func isInteractiveConnectorRequest(', '  private func authorizeConnectorSend(');
  for (const token of ['currentDestination(entry.identity)', 'target.desktop', 'target.contactId != entry.message.contactId',
    'contact.trustState == .verified', 'identity.isComplete', 'identity.clientRouteId == target.routeId',
    'return try authorizeConnectorSend(entry)', 'entry.message.attachmentTransferId.isEmpty']) assert(marker.includes(token), token);
  const drain = read(app + 'MqttBusinessSendDrain.swift');
  assert(drain.indexOf('guard try await authorize(item)') < drain.indexOf('interactive = try await interactiveFinal(item)'));
  assert(drain.includes('direct.interactiveFinal = interactive'));
  const dispatch = read(app + 'MqttDeliveryDispatch.swift');
  assert(dispatch.includes('interactiveFinal: delivery.interactiveFinal'));
  for (const name of ['MqttPeerRoutes', 'MqttSealedPathPublication', 'MqttSignalSendRequest', 'MqttDeliveryEnvelope',
    'MqttBusinessOutbox', 'MqttDeliveryCompletions', 'MqttSignalStateJournal'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/MqttMultipathPolicyTests.swift') + read('apps/ios/GalaxySSITests/MqttDeliveryDispatchTests.swift');
  assert.equal((tests.match(/  func testInteractive/g) || []).length, 6);
  for (const token of ['[0, 250]', '256 * 1024 + 1', 'interactiveFinal: interactive', 'fixture.time = 249',
    'fixture.dispatch.acceptVerifiedReceipt', 'fixture.authorized = false', 'throw DispatchFixture.Fault.commit']) assert(tests.includes(token), token);
  console.log('Interactive Desktop classification, bounded authorized fast copies, unchanged wire/receipt kernels and six authored fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
