// Static source contracts only; no Swift execution or decoder acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '14acae50dbb4a0ef3cef1e8332ed3c82e3c89c05';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const android = cp.execFileSync('git', ['show', '9cab75e19de460f75e7c83a82033acc02b4dd288:apps/android/app/src/main/java/com/galaxyssi/chat/TeamWriterFormatSession.kt'], {cwd: root, encoding: 'utf8'});
const helper = read(app + 'AgentTeamWriterFormatSession.swift');
for (const field of ['purpose', 'input', 'input_direction', 'readout', 'expected_direction', 'alternative', 'gap']) {
  assert(android.includes(`"${field}"`)); assert(helper.includes(`"${field}"`));
}
for (const token of ['AgentTeamPlanWire.canonicalEndpoint(value)', 'source == destination', 'product.utf8.count <= 128',
  '^llama\\.cpp(?:/[A-Za-z0-9._-]+)?$', 'known == Endpoint(endpoint)', 'system == AgentTeamPredictionContrast.writer',
  '["synthesis", "rewrite"].contains(stage)', '"higher", "lower"', '"additionalProperties": .bool(false)',
  'stage == "rewrite" ? claim', 'record(["answer": text])', 'request.provider == .openAICompatible',
  'body["response_format"]', 'lock.lock()', 'confirmed = source != nil']) assert(helper.includes(token), token);
const observer = read(app + 'CloudTextServerObservation.swift');
for (const token of ['redirected = true', 'completionHandler(request)', 'guard !redirected, (200...299).contains(response.statusCode)',
  'response.value(forHTTPHeaderField: "Server")']) assert(observer.includes(token), token);
const inference = read(app + 'AgentConversationGoalInference.swift');
assert(inference.indexOf('if route.kind == .local') < inference.indexOf('writerSession.apply(to:'));
assert(inference.indexOf('let decoded = try wire?.decode(body) ?? body') < inference.indexOf('writerSession?.observe('));
for (const token of ['if wire == nil, let writerSession', 'if wire != nil, let advertisement',
  'observesTextServer: wire != nil && writerSession != nil', 'textServerAdvertisement(requestId: requestID)',
  'writerSession: AgentTeamWriterFormatSession? = nil']) assert(inference.includes(token), token);
const runtime = read(app + 'AgentConversationalTeamRuntime.swift');
assert.equal(runtime.split('let writerSession = AgentTeamWriterFormatSession()').length - 1, 1);
assert(runtime.indexOf('let writerSession = AgentTeamWriterFormatSession()') < runtime.indexOf('let outcome = try await AgentConversationalTeamEngine.run'));
assert(runtime.includes('writerSession: writerSession, store: store'));
let stream = read(app + 'URLSessionCloudModelStreamClient.swift');
const changes = [
  ['  private let observesTextServer: Bool\n  private var lastTextServerAdvertisement: (requestId: String, value: CloudTextServerAdvertisement)?\n', ''],
  ['URLSessionCloudModelStreamClient.defaultElapsedMillis,\n    observesTextServer: Bool = false', 'URLSessionCloudModelStreamClient.defaultElapsedMillis'],
  ['    self.observesTextServer = observesTextServer\n', ''],
  ['  func textServerAdvertisement(requestId: String) -> CloudTextServerAdvertisement? {\n    locked { lastTextServerAdvertisement?.requestId == requestId ? lastTextServerAdvertisement?.value : nil }\n  }\n\n', ''],
  ['    if observesTextServer { locked { lastTextServerAdvertisement = nil } }\n', ''],
  ['      let textServerObserver = observesTextServer && !privateContinuation && request.provider == .openAICompatible &&\n        request.transport == .completeJSON ? CloudTextServerObservation() : nil\n      let delegate: URLSessionTaskDelegate? = privateContinuation ? NoPrivateContinuationRedirects() : textServerObserver\n', ''],
  ['        delegate: delegate)', '        delegate: privateContinuation ? NoPrivateContinuationRedirects() : nil)'],
  ['      if let advertisement = textServerObserver?.advertisement(response: http) {\n        locked { lastTextServerAdvertisement = (request.requestId, advertisement) }\n      }\n', '']
];
for (const [from, to] of changes) { assert.equal(stream.split(from).length, 2, from); stream = stream.replace(from, to); }
assert.equal(stream, old(app + 'URLSessionCloudModelStreamClient.swift'), 'All shared transport behavior outside the explicit opt-in hooks retained');
for (const file of ['AgentConversationalTeamEngine', 'AgentConversationalTeamProtocol', 'AgentTeamPlanWire', 'AgentTeamPlanJSONPreflight',
  'AgentTeamPredictionContrast', 'AgentTeamDraftAudit', 'AgentConversationalTeamJob', 'AgentConversationalTeamStore', 'CloudModelStreaming']) {
  assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file);
}
const tests = read('apps/ios/GalaxySSITests/AgentTeamWriterFormatSessionTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 6);
for (const name of ['AgentTeamWriterFormatSession', 'CloudTextServerObservation', 'AgentTeamWriterFormatSessionTests']) {
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name);
}
assert(!/\p{Script=Han}/u.test(helper + observer + tests));
console.log('Android #4669 writer-schema source contracts passed; six XCTest methods authored, not executed.');
