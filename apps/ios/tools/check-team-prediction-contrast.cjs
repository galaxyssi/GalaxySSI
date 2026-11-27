// Source contracts, not Swift execution, model judgment or scientific validation.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '747ca81e60cd4cbf26d48b558dcfa683e0907122';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const helper = read(app + 'AgentTeamPredictionContrast.swift');
const keys = ['purpose', 'input', 'input_direction', 'readout', 'expected_direction', 'alternative', 'gap'];
const reference = cp.execFileSync('git', ['show', '0e7c2990d1a1012e2c71b2689229c4698e7ef1e6:apps/android/app/src/main/java/com/galaxyssi/chat/TeamPredictionContrast.kt'],
  {cwd: root, encoding: 'utf8'});
const declaredFields = reference.match(/private val fields = setOf\(([^\n]+)\)/);
assert(declaredFields, 'Pinned Android contrast contract');
assert.deepEqual([...declaredFields[1].matchAll(/"([^"]+)"/g)].map(match => match[1]), keys);
for (const token of ['Input and readout must differ', 'not an experimental or clinical conclusion', 'missing, invalid or uninterpretable measurement would not']) assert(reference.includes(token), token);
assert(helper.includes('Set(object.keys) == fields'));
for (const key of keys) assert(helper.includes('"' + key + '"'), key);
for (const token of ['(1...8_000).contains(objective.utf16.count)', 'regex.stringByReplacingMatches',
  '!matches(clause, excluded)', '!matches(clause, resource("excluded"))', 'resource("request")',
  'precomposedStringWithCompatibilityMapping.lowercased()', 'CharacterSet.letters.contains',
  'normalized(input) != normalized(readout)', 'case .string("higher")', 'case .string("lower")',
  'field("input", limit: 120)', 'field("purpose", limit: 400)', 'field("alternative", limit: 400)',
  'expected ? text.higher : text.lower, expected ? text.lower : text.higher',
  'AgentTeamDraftAudit.object(raw)', 'Set(object.keys) == ["answer"]', 'if object["answer"] == nil',
  'return Draft(answer: try AgentConversationalTeamProtocol.synthesis(raw), claim: nil)',
  'a missing, invalid or uninterpretable measurement would not', 'not an experimental or clinical conclusion']) assert(helper.includes(token), token);
const engine = read(app + 'AgentConversationalTeamEngine.swift');
for (const token of ['editor != nil && worksheet == nil && AgentTeamPredictionContrast.requested(objective)',
  'text: labels.contrast', 'synthesis.claim == nil ? AgentTeamDraftAudit.system : AgentTeamPredictionContrast.auditor',
  'reviewed.requiresHandback || (synthesis.claim != nil && reviewed.correction != nil)',
  'rewriteFields["original_claim"]', 'JSONEncoder().encode(claim)',
  'synthesis.claim == nil ? AgentTeamDraftAudit.rewriteSystem : AgentTeamPredictionContrast.writer',
  'AgentTeamPredictionContrast.render(AgentTeamDraftAudit.object(rawRewrite), text: labels.contrast)',
  'guard !candidate.isBlank, !AgentTeamDraftAudit.sameDraft(candidate, draft)', 'guard calls + 2 <= Contract.maximumCalls']) assert(engine.includes(token), token);
let retained = engine;
const hooks = [
  ['      let offerContrast = editor != nil && worksheet == nil && AgentTeamPredictionContrast.requested(objective)\n      let synthesis = try AgentTeamPredictionContrast.synthesis(\n        await call(offerContrast ? AgentTeamPredictionContrast.writer : Contract.synthesizer, input: payload, limit: 16_064, ask: ask),\n        offered: offerContrast, text: labels.contrast)\n      let draft = synthesis.answer',
    '      let draft = try Contract.synthesis(await call(Contract.synthesizer, input: payload, limit: 16_064, ask: ask))'],
  ['        let auditSystem = worksheet != nil ? AgentTeamDraftAudit.tableSystem :\n          (synthesis.claim == nil ? AgentTeamDraftAudit.system : AgentTeamPredictionContrast.auditor)\n        let raw = try await call(auditSystem,',
    '        let raw = try await call(worksheet == nil ? AgentTeamDraftAudit.system : AgentTeamDraftAudit.tableSystem,'],
  ['if reviewed.requiresHandback || (synthesis.claim != nil && reviewed.correction != nil)', 'if reviewed.requiresHandback'],
  ['var rewriteFields: [String: Any]', 'let rewriteFields: [String: Any]'],
  ['            if let claim = synthesis.claim { rewriteFields["original_claim"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(claim)) }\n', ''],
  ['call(synthesis.claim == nil ? AgentTeamDraftAudit.rewriteSystem : AgentTeamPredictionContrast.writer,', 'call(AgentTeamDraftAudit.rewriteSystem,'],
  ['            let candidate: String\n            if synthesis.claim == nil { candidate = try AgentTeamDraftAudit.replacement(rawRewrite, rejected: draft) }\n            else { candidate = try AgentTeamPredictionContrast.render(AgentTeamDraftAudit.object(rawRewrite), text: labels.contrast) }\n            guard !candidate.isBlank, !AgentTeamDraftAudit.sameDraft(candidate, draft), candidate.utf16.count <= 8_000 else { throw AgentTeamDraftAudit.Failure.invalid }',
    '            let candidate = try AgentTeamDraftAudit.replacement(rawRewrite, rejected: draft)']
];
for (const [from, to] of hooks) { assert.equal(retained.split(from).length, 2, 'Exactly one contrast hook'); retained = retained.replace(from, to); }
assert.equal(retained, old(app + 'AgentConversationalTeamEngine.swift'), 'All other scheduling, budget, role/report and rejection behavior unchanged');
const audit = read(app + 'AgentTeamDraftAudit.swift');
assert.equal(audit.replace('    var contrast = AgentTeamPredictionContrast.Text.english\n', '').replace('  static func object(', '  private static func object('),
  old(app + 'AgentTeamDraftAudit.swift'), 'Only shared strict decoder visibility and labels added');
for (const file of ['AgentConversationalTeamProtocol', 'AgentTeamPlanWire', 'AgentTeamPlanJSONPreflight', 'AgentConversationalTeamJob', 'AgentConversationalTeamStore'])
  assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file);
const tests = read('apps/ios/GalaxySSITests/AgentTeamPredictionContrastTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 10);
for (const token of ['"approve", "return", "replace", "bypass", "reject", "qualitative"', 'for workers in [1, 8]',
  'SyntheticDirectionalWire("cancel")', '"original_claim"', 'recheck[key], audit[key]',
  'mode == "bypass"', 'Never checked.', 'contrast_sample_request', 'contrast_sample_excluded',
  '\\u{ff36}', '\\r\\n']) {
  assert(tests.includes(token), token);
}
assert(!/\p{Script=Han}/u.test(helper + tests));
const strings = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const key of ['format', 'higher', 'lower', 'excluded', 'request', 'placeholders', 'sample_request', 'sample_excluded'])
  assert.equal(strings.split(`"galaxyssi.conversation_team.contrast_${key}" =`).length - 1, 1, key);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentTeamPredictionContrast', 'AgentTeamPredictionContrastTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
  assert.equal(project.split('path = ' + name + '.swift;').length - 1, 1);
}
console.log('Matched directional claims, exact localized draft review and bounded structured handback source contracts passed; ten native test methods authored, not executed.');
