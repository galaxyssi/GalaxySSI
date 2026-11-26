// Source contracts only; not native localization, model/transport or XCTest acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'fee8008f9b268ee1b7f8e342773ad8e48e5cfc3f', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(source.split(first).length, 2, first);
  return source.slice(start, end);
}
function replace(source, from, to, count = 1) {
  assert.equal(source.split(from).length - 1, count, 'Declared fallback hook: ' + from);
  return source.replaceAll(from, to);
}
function retainedFallbackFile(file, source) {
  if (file.endsWith('/CloudWebGrounding.swift')) {
    if (!source.includes('"cloud_web_fallback_sources"')) return source;
    const prior = show(base, app + 'CloudWebGrounding.swift');
    for (const [first, last] of [['  static func inlineEvidenceMessage(', '  static func citationRepairPrompt('],
      ['  private static func collectSources(', '  private static func boundValue(']])
      source = source.replace(section(source, first, last), section(prior, first, last));
    return source;
  }
  if (!file.endsWith('/CloudConversationStreamEngine.swift') && !file.endsWith('/CloudConversationNonStreamingToolEngine.swift')) return source;
  const hook = '    let fallbackLanguage = await MainActor.run { store.languagePolicy.interfaceLanguage }\n';
  if (!source.includes(hook)) return source;
  source = replace(source, hook, '');
  if (file.endsWith('/CloudConversationNonStreamingToolEngine.swift'))
    return replace(source, 'evidenceFallback(results: evidence, language: fallbackLanguage)', 'evidenceFallback(results: evidence)', 4);
  source = replace(source, 'evidenceFallback(results: evidenceResults, language: fallbackLanguage)', 'evidenceFallback(results: evidenceResults)', 2);
  source = replace(source, 'evidenceFallback(results: evidence, language: language)', 'evidenceFallback(results: evidence)');
  source = replace(source, 'ticket: ticket, language: fallbackLanguage, continuation: continuation)', 'ticket: ticket, continuation: continuation)', 2);
  return replace(source, 'ticket: AgentDisclosureTicket, language: String, continuation:', 'ticket: AgentDisclosureTicket, continuation:');
}
function validateWebFallback() {
  for (const name of ['CloudWebGrounding', 'CloudConversationStreamEngine', 'CloudConversationNonStreamingToolEngine']) {
    const file = app + name + '.swift';
    assert.equal(retainedFallbackFile(file, read(file)), show(base, file), name + ': only fallback presentation/guidance/language hooks change');
  }
  const grounding = read(app + 'CloudWebGrounding.swift');
  const collect = section(grounding, '  private static func collectSources(', '  private static func boundValue(');
  for (const token of ['url.utf16.count <= 4_096', 'seen.insert(url)', 'sources.append((url,',
    'where key != "images" && key != "image"', 'depth > 6 || sources.count >= 12']) assert(collect.includes(token), token);
  assert(!collect.includes('url.prefix('), 'Never invent a different URL by truncation');
  const fallback = section(grounding, '  static func evidenceFallback(', '  static func citationRepairPrompt(');
  for (const token of ['emptyMessage: String? = nil', 'sourcesMessage: String? = nil', 'language: String = LanguagePolicySettings.auto',
    'GalaxySSILocalization.string("cloud_web_fallback_empty"', 'GalaxySSILocalization.string("cloud_web_fallback_sources"',
    'language: language', 'sources.prefix(6)']) assert(fallback.includes(token), token);
  const english = ['These sources were retrieved, but a reliable synthesis is not complete:', 'No reliable web evidence is available yet. Try again later or narrow the query.'];
  const zh = read(app + 'zh-Hans.lproj/Localizable.strings');
  const androidEN = show(android, 'apps/android/app/src/main/res/values/strings.xml');
  const androidZH = show(android, 'apps/android/app/src/main/res/values-zh-rCN/strings.xml');
  for (const [i, key] of ['cloud_web_fallback_sources', 'cloud_web_fallback_empty'].entries()) {
    assert(grounding.includes('fallback: "' + english[i] + '"'));
    assert(androidEN.includes('<string name="' + key + '">' + english[i] + '</string>'));
    const row = zh.split('\n').filter(line => line.startsWith('"' + key + '" = '));
    assert.equal(row.length, 1, key);
    const translated = JSON.parse(row[0].slice(row[0].indexOf(' = ') + 3).replace(/;$/, ''));
    assert(androidZH.includes('<string name="' + key + '">' + translated + '</string>'), key);
  }
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/CloudWebGrounding.kt');
  for (const token of ['if (url.length <= 4_096) sources.putIfAbsent(url, title)', 'if (key != "images") collectSources',
    'Discard off-topic results', 'without duplicating Markdown images']) assert(reference.includes(token), token);
  for (const name of ['AgentIOSWebEvidenceVerification', 'AgentIOSWebEvidencePack', 'LanguagePolicySettings', 'GalaxySSILocalization', 'AgentModelToolLoop'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/CloudWebFallbackTests.swift');
  for (const name of ['FallbackKeepsCompleteSourceURLsThroughReferenceLengthBoundary', 'FallbackRejectsOversizedURLsRatherThanInventingTruncatedSources',
    'FallbackDoesNotPromotePluralOrSingularImageObjectsToSourcePages', 'FallbackRetainsDedupSixSourceBoundHTTPSAndMessageOverrides',
    'FallbackUsesIncompleteSynthesisCopyAndConfiguredInterfaceLanguage', 'InlineEvidenceGuidanceStaysRequestFocusedAndUntrusted']) assert(tests.includes('func test' + name + '('), name);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('CloudWebFallbackTests.swift in Sources */').length, 3);
}
module.exports = {retainedFallbackFile, validateWebFallback};
if (require.main === module) {
  validateWebFallback();
  console.log('iOS complete fallback source URLs, image exclusion, truthful localized synthesis and actual engine language hooks source contracts passed; no native acceptance');
}
