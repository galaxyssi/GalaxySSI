// Source-only contracts; no Swift, live model, device or scientific acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const audit = read('GalaxySSI/AgentTeamDraftAudit.swift');
for (const token of ['case .string("revise"), .string("request_changes")',
  'let returnToWriter = review["verdict"] == .string("request_changes")',
  'returnToWriter ? ["verdict", "objection"] : ["verdict", "objection", "answer"]',
  'guard keys == expected', 'let reason = try objection(review, labels: labels)',
  'requiresHandback: returnToWriter || sameDraft(answer, draft)',
  'guard !isReviewPlaceholder(reason) else { throw Failure.withheld(labels.noReviewReason) }',
  'guard !isReviewPlaceholder(reason) else { throw Failure.invalid }',
  'value["verdict"] == .string("request_changes")', 'while normalized.hasSuffix(".")',
  '"brief error in draft", "brief reason", "what the writer must correct"',
  '"specific reason in the language of the objective"']) assert(audit.includes(token), token);
const protocol = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
assert.equal(protocol.split('\\(predictionCheck)').length - 1, 2);
assert.equal(audit.split('\\(AgentConversationalTeamProtocol.predictionCheck)').length - 1, 3);
for (const token of ['uninterpretable observation', 'SAME independent conditions',
  'Do not assume the predicted readout as a condition', 'never list such failure as',
  'plausible competing explanation', 'Do not invent data.']) assert(protocol.includes(token), token);
const runtime = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
assert(runtime.includes('noReviewReason: text("review_reason_missing"'));
assert(runtime.includes('catch let rejection as AgentTeamDraftAudit.Rejected'));
assert.equal(read('GalaxySSI/zh-Hans.lproj/Localizable.strings').split('"galaxyssi.conversation_team.review_reason_missing" =').length - 1, 1);
const tests = read('GalaxySSITests/AgentTeamHandbackTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 16);
for (const token of ['testExplicitRequestChangesUsesOneWriterAndSameEditorWithoutAnAnswerField',
  'testRequestChangesRejectsAnswerFieldsMissingReasonsAndWrongTypes',
  'testPlaceholderAuditReasonsUseLocalizedReceiptAndRetainContributorDissent',
  'testRecheckRequestChangesIsATerminalVetoAndPlaceholderFallsBackToOriginal',
  'testPlaceholderRecognitionDoesNotDiscardActualSpecificObjections',
  'testEveryJudgmentRoleGetsPredictionCheckWithoutChangingPlannerAuthority',
  'Localized missing reason', 'rejected.objections.count, 2']) assert(tests.includes(token), token);
assert(!/\p{Script=Han}/u.test(audit + tests));
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
assert(engine.includes('guard calls + 2 <= Contract.maximumCalls'));
assert.equal(engine.split('input("rewrite",').length - 1, 1);
assert.equal(engine.split('input("recheck",').length - 1, 1);
console.log('Explicit review changes, non-placeholder objections and shared prediction-check source contracts passed; six new native test methods authored, not executed.');
