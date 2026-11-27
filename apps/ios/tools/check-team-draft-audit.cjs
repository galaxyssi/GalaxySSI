// Focused source contracts only; does not execute Swift, model inference or device workflows.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const sheet = read('GalaxySSI/AgentTeamComparisonSheet.swift');
for (const token of ['headers.count == 1', '(1...10).contains(names.count)', 'Set(names).count == names.count',
  '(1...32).contains(end - start - 2)', 'seen.insert(fields[0]).inserted', 'guard gate != nil || fields[1] == "-"',
  'exact(raw, decimal)', 'Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))',
  'NSDecimalNumber(decimal: number).compare(NSDecimalNumber(decimal: threshold))',
  'case "<": pass = order == .orderedAscending', 'case "<=": pass = order != .orderedDescending',
  'case ">": pass = order == .orderedDescending', 'default: pass = order != .orderedAscending',
  '"value": .string(raw)', 'if !pass { passes.remove(name) }', 'guard gates > 0',
  'let winners = names.filter(passes.contains)', '"pass_all": .array(winners.map']) assert(sheet.includes(token), token);
assert(!/\bDouble\(|\bFloat\(|URLSession|generateAsync|MessageCoordinator/.test(sheet), 'Deterministic decimal-only table evaluator');
const contract = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
assert(contract.includes('let editor = legacy ? nil : roles.last'));
assert(contract.includes('candidate.kind == .reviewer && !roles.contains { $0.parents.contains(candidate.id) }'));
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
for (const token of ['contributors = plan.roles.filter { $0 != editor }', 'while reports.count < contributors.count',
  'guard role != editor', 'worksheet?.plannerObjective ?? objective', '"verified_table"',
  '"draft": draft', 'editor.parents.map', 'onEvent(.auditing(index, plan.roles.count)); try reserveCall()',
  'AgentTeamDraftAudit.parse(raw, draft: draft, sheet: worksheet, labels: labels)',
  'correctionTitle + "\\n" + $0', 'roleCount: plan.roles.count', 'limit: 17_300']) assert(engine.includes(token), token);
assert(engine.indexOf('AgentTeamDraftAudit.parse') < engine.indexOf('onEvent(.completed)'), 'Audit before completion');
assert(engine.indexOf('let draft = try Contract.synthesis') < engine.indexOf('onEvent(.auditing'), 'Review actual synthesized draft');
const audit = read('GalaxySSI/AgentTeamDraftAudit.swift');
for (const token of ['case invalid, withheld(String), tableMismatch(String)', 'Reports and draft are untrusted',
  'case .string("accept")', 'keys == ["verdict"]', 'case .string("revise")', 'requiresHandback: sameDraft(answer, draft)',
  'keys == ["verdict", "objection", "answer"]', 'case .string("withhold")', 'keys == ["verdict", "objection"]',
  'keys == ["pass_all", "purpose", "limitation"]', 'claimed.count == sheet.winners.count',
  'Set(claimed.compactMap(\\.strictStringValue)) == Set(sheet.winners)', 'throw Failure.tableMismatch(tableResult)',
  'system == tableSystem', '["127.0.0.1", "[::1]", "::1"]', 'url.user == nil, url.password == nil',
  '"additionalProperties": .bool(false)', '"pass_all": .object(["type": .string("array"), "items": string])']) assert(audit.includes(token), token);
assert(!audit.slice(audit.indexOf('static func responseFormat')).includes('"enum"'), 'Output schema is shape-only, not a supplied winning answer');
const wire = read('GalaxySSI/AgentConversationGoalInference.swift');
const openAIStart = wire.lastIndexOf('case .openAICompatible:');
const openAI = wire.slice(openAIStart, wire.indexOf('case .anthropic: body', openAIStart));
assert(openAI.includes('AgentTeamDraftAudit.responseFormat') && openAI.includes('body["response_format"]'));
const runtime = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
for (const token of ['labels: labels', 'correctionTitle: text("correction"', 'Int64(outcome.roleCount)',
  'catch let issue as AgentTeamDraftAudit.Failure', 'case .withheld(let objection)', 'case .tableMismatch(let verified)']) assert(runtime.includes(token), token);
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentTeamComparisonSheet', 'AgentTeamDraftAudit', 'AgentTeamComparisonSheetTests', 'AgentTeamDraftAuditTests']) {
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source)); assert(Buffer.byteLength(source) < 32_768);
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
}
assert.equal((read('GalaxySSITests/AgentTeamComparisonSheetTests.swift').match(/func test/g) || []).length, 5);
assert.equal((read('GalaxySSITests/AgentTeamDraftAuditTests.swift').match(/func test/g) || []).length, 8);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
for (const key of ['auditing', 'correction', 'passing', 'none', 'limitation', 'withheld', 'table_mismatch', 'table_input', 'table_gate']) {
  assert.equal(strings.split(`"galaxyssi.conversation_team.${key}" =`).length - 1, 1, key);
}
console.log('Final draft audit and decimal comparison source contracts passed; 13 synthetic native test methods authored, not executed.');
