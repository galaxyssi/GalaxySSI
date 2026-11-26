// Source contracts only, not URLSession/model cancellation, XCTest or runtime acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '56d58c29a0a8a6f7ef29ad016fda0c58929fac6f';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, 'One declared tool failure hook: ' + from);
  return source.replace(from, to);
}
function retainedFailureMedia(source) {
  const hook = '    if let urlError = error as? URLError, urlError.code == .timedOut {\n      throw AgentIOSURLSessionWebError.timeout\n    }\n';
  return source.includes(hook) ? once(source, hook, '') : source;
}
function retainedToolFailureFile(file, source) {
  if (!file.endsWith('/CloudWebGrounding.swift') || !source.includes('CloudWebToolFailurePolicy.failure(')) return source;
  source = once(source, '      return boundedModelJson(CloudWebToolFailurePolicy.failure(tool: name, error: error))',
    '      return boundedModelJson([\n        "status": .string("failed"),\n        "tool": .string(String(name.prefix(80))),\n        "error": .string(String(error.localizedDescription.prefix(300)))\n      ])');
  return once(source, '    return CloudWebToolFailurePolicy.applying(to: payload, status: result.status, code: result.error?.code)', '    return payload');
}
function validateWebToolFailure() {
  const grounding = read(app + 'CloudWebGrounding.swift'), media = read(app + 'AgentIOSURLSessionWebMediaProvider.swift');
  assert.equal(retainedToolFailureFile(app + 'CloudWebGrounding.swift', grounding), show(base, app + 'CloudWebGrounding.swift'),
    'Only thrown/structured failure projections change; evidence formatting, successful/static output, scopes, prompts, localization and tool declarations retained');
  assert.equal(retainedFailureMedia(media), show(base, app + 'AgentIOSURLSessionWebMediaProvider.swift'),
    'Only typed URLSession timeout classification changes; headers, credentials, redirects, bytes, DNS and rendering retained');
  const helper = read(app + 'CloudWebToolFailurePolicy.swift');
  for (const token of ['guard status != .succeeded else { return payload }', 'status == .cancelled', 'status == .timedOut',
    '"web_source_timeout"', '"web_execution_stopped"', '"renderer_unavailable"', '"invalid_engine"',
    'output["retryable"] = .bool(false)', 'output["native_status"]', 'output["next_action"]',
    'as AgentNativeToolInvocationError', 'as AgentIOSURLSessionWebError', 'as AgentIOSDynamicWebRenderError',
    'String(tool.prefix(80))', 'error.localizedDescription.prefix(300)']) assert(helper.includes(token), token);
  assert(!/localizedCaseInsensitiveContains|localizedDescription\.contains|URLSession\(|UserDefaults|grantedPermissions/.test(helper));
  assert(!helper.includes('output["error"] =') && !helper.includes('output["output"] ='), 'Preserve original structured errors/evidence');
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/CloudWebGrounding.kt');
  for (const token of ['put("error_code", "web_source_timeout")', 'put("error_code", "web_execution_stopped")',
    'put("error_code", "renderer_unavailable")', 'put("error_code", "invalid_engine")', 'put("retryable", false)',
    'Do not fetch the same URL again', 'only if the user did not require a specific source']) assert(reference.includes(token), token);
  for (const name of ['CloudConversationStreamToolRounds', 'CloudResearchRuntimeBudget', 'CloudConversationStreamEngine',
    'CloudConversationNonStreamingToolEngine', 'AgentIOSURLSessionWebIntelligenceProvider', 'AgentNativeToolExecutionModels'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  const rounds = read(app + 'CloudConversationStreamToolRounds.swift');
  assert(rounds.includes('["web_source_timeout", "renderer_unavailable"].contains(root["error_code"]?.stringValue ?? "")'));
  const tests = read('apps/ios/GalaxySSITests/CloudWebToolFailurePolicyTests.swift');
  for (const name of ['StructuredTimeoutCodesAndStatusSupplyNonRetryableGuidance', 'StoppedRendererAndEngineFailuresHaveDistinctActions',
    'SuccessfulStaticEvidenceAndUnrelatedFailuresRemainUnchanged', 'TypedThrownFailuresAreClassifiedWithoutMessageGuessingAndStayBounded',
    'ActualNativeTimeoutGetsRootClassificationAndCrossReadReuse', 'ActualURLSessionTimeoutIsNotFlattenedIntoGenericTransportFailure',
    'RegistryInvalidEngineDoesNotSilentlySearchAlternativeSources']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['CloudWebToolFailurePolicy', 'CloudWebToolFailurePolicyTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedFailureMedia, retainedToolFailureFile, validateWebToolFailure};
if (require.main === module) {
  validateWebToolFailure();
  console.log('iOS structured web failure hints, typed URLSession timeout and existing same-resource reuse source contracts passed; no native acceptance');
}
