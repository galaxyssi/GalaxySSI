'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const prefix = 'apps/ios/GalaxySSI/';
const baseline = 'b4678ce594b5e6b57712ab74c5b7caed7aaffcb2';

function once(source, before, after = '') {
  assert.equal(source.split(before).length - 1, 1, 'Unique declared checkpoint hook');
  return source.replace(before, after);
}

function retainedScopedReadTransport(input) {
  let source = clean(input);
  const resume = source.indexOf('\n  static func resume(');
  assert.ok(resume > 0, 'Explicit scoped-round recovery entry exists');
  source = source.slice(0, resume) + '}\n';
  source = once(source, `    var checkpoint = try records.savedCareDiscussionRound(review)
    if let saved = checkpoint {
      guard saved.phase == .received, let response = saved.response,
            review.model?.apiStyle == style else { throw GalaxySSIHealthRecords.Failure.stale }
      request = try saved.request(using: request, approval: review)
      bytes = response
      history = saved.history
      relatedHistory = saved.relatedHistory
      relatedEntries = saved.relatedEntries
      questionCursor = saved.questionCursor
      feedbackCursor = saved.feedbackCursor
      historyRemaining = saved.historyRemaining
      questionRemaining = saved.questionRemaining
      feedbackRemaining = saved.feedbackRemaining
    }
`);
  source = once(source, `      if let saved = checkpoint {
        guard let body = request.httpBody else { throw GalaxySSIHealthRecords.Failure.invalid }
        var next = saved
        next.index += 1
        next.phase = .prepared
        next.requestBody = body
        next.response = nil
        next.history = history
        next.relatedHistory = relatedHistory
        next.relatedEntries = relatedEntries
        next.questionCursor = questionCursor
        next.feedbackCursor = feedbackCursor
        next.historyRemaining = historyRemaining
        next.questionRemaining = questionRemaining
        next.feedbackRemaining = feedbackRemaining
        try records.prepareNextCareDiscussionRound(review, expected: saved, next: next)
        checkpoint = next
      }
`);
  source = once(source, '      var received = false\n');
  source = once(source, '        if let saved = checkpoint { try records.dispatchCareDiscussionRound(review, expected: saved, request: request) }\n');
  source = once(source, '        received = true\n');
  source = once(source, `        if let saved = checkpoint {
          try records.retainCareDiscussionRound(review, index: saved.index, request: request, response: bytes)
          checkpoint = try records.savedCareDiscussionRound(review)
        }
`);
  source = once(source, `AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: received ? .sent : .failed,
          failureReason: received ? "" : "health_scoped_read_not_completed")`,
    `AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .failed,
          failureReason: "health_scoped_read_not_completed")`);
  return source;
}

module.exports = { retainedScopedReadTransport };

if (require.main === module) {
  const file = prefix + 'GalaxySSIHealthScopedReadTransport.swift';
  const transport = read(file);
  const original = clean(cp.execFileSync('git', ['show', `${baseline}:${file}`], { cwd: root, encoding: 'utf8' }));
  assert.equal(retainedScopedReadTransport(transport), original, 'Legacy scoped reads and research mutations retained outside declared checkpoint hooks');
  const rounds = read(prefix + 'GalaxySSIHealthCareDiscussionRounds.swift');
  assert.match(rounds, /phase == \.received \|\| phase == \.prepared/);
  assert.match(rounds, /template\.httpMethod == "POST", template\.url == approval\.endpoint/);
  assert.match(rounds, /execution\.rounds == expected/);
  assert.match(rounds, /costs\.allSatisfy\(\{ \(0\.\.\.1\)\.contains\(\$0\) \}\), costs\.reduce\(0, \+\) == 1/);
  assert.match(rounds, /state\.request\(using: request, approval: approval\)\.httpBody == request\.httpBody/);
  assert.match(rounds, /state\.phase == \.dispatched/);
  assert.match(rounds, /state\.response == response/);
  assert.match(rounds, /validateLocalCareDiscussionTurn\(approval, now: now\)/);
  assert.doesNotMatch(rounds, /allHTTPHeaderFields|Authorization|x-api-key|x-goog-api-key/);
  assert.match(transport, /saved\.canResume/);
  assert.match(transport, /currentDestination\(\) == contact/);
  assert.match(transport, /saved\.index == 0 \{ try records\.dispatchLocalCareDiscussionTurn\(review\) \}/);
  assert.match(transport, /dispatchCareDiscussionRound[\s\S]*?bytes = try await send\(request\)/);
  assert.match(transport, /received \? \.sent : \.failed/);
  const runtime = read(prefix + 'GalaxySSIHealthCareTaskRuntime.swift');
  assert.match(runtime, /current\.state == \.prepared \|\| current\.state == \.dispatched/);
  assert.match(runtime, /current\.rounds\?\.canResume == true, mayApply\(\), let resumeRound/);
  const fixtures = read('apps/ios/GalaxySSITests/GalaxySSIHealthCareDiscussionRoundsTests.swift');
  assert.equal((fixtures.match(/func test/g) || []).length, 8);
  console.log('Health discussion round source scope passed (not native execution or typechecking).');
}
