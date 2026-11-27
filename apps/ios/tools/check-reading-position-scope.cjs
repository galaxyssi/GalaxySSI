'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const app = 'apps/ios/GalaxySSI/';
const base = '20bb51f10021351bd4ea62ae1fc37e9ed65e5752';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', `${base}:${f}`], {
  cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024
}).replace(/\r\n/g, '\n');
const has = (s, tokens) => tokens.forEach(t => assert.ok(s.includes(t), `Missing source wiring: ${t}`));
const policy = read(app + 'GalaxySSIReadingPosition.swift');
has(policy, ['previous.scope == current.scope', '!previous.entries.isEmpty', 'previous.entries.filter(\\.reply)',
  'previous.entries.filter(\\.request)', 'lastIndex { ids.contains($0.id) }', 'open.contains(row.turn)',
  'row.at > last', 'index > $0', '!message.isMine && !message.isSystem', 'message.deliveryStatus != .failed',
  'containsUnexecutedControlReply', 'agent-stream-preview-', 'dedupePrefix', 'abs($0 - index) < abs($1 - index)']);
const paragraph = read(app + 'GalaxySSIReadingParagraphAnchor.swift');
has(paragraph, ['holding?() == true', 'value.preferredFramesPerSecond = 30', 'weak var target',
  'window.isKeyWindow', 'foregroundActive', '!scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating',
  'abs(scroll.contentOffset.y - previousOffset) < 1', 'belongs(target, scroll: scroll)',
  'scroll.contentOffset.y + delta', 'checked < 2_048', 'view is AgentReplyParagraphTextView',
  'ios.reading.row-marker', 'if view is UIScrollView { continue }', 'dismantleUIView', 'view.holding = nil']);
assert.ok(!/addGestureRecognizer|selectedRange\s*=|becomeFirstResponder|URLSession/.test(paragraph));
const agent = read(app + 'GalaxySSIAgentTranscriptScrollView.swift');
has(agent, ['GalaxySSIReadingParagraphAnchor(', 'store.canReadAgentTranscript',
  'GalaxySSIReadingPosition.newReply(previous: replySnapshot, current: value)', 'Set(value.answerIDs)',
  '!answers.subtracting(previous).isEmpty', 'guard transcriptAutoFollow else { return }',
  'guard userScrolling else { return }', 'metrics.viewportHeight + 1', 'galaxySSIRuntimePlaintextWillClear',
  'private var readingScope: String { store.profile.identityFingerprint']);
assert.ok(!agent.includes('transcriptShowLatestButton = !messages.isEmpty'));
assert.equal((agent.match(/transcriptShowLatestButton = true/g) || []).length, 2, 'Only actual Agent/Health reply arrivals signal');
const peer = read(app + 'GalaxySSIViews.swift');
has(peer, ['if newPeerReply && !isSystemNoticeContact', 'peerReplySnapshot', 'GalaxySSIReadingPosition.newReply(',
  'frames[id].map { $0.maxY <= messageViewportHeight + 1 }', 'if userScrolling, let id',
  'GalaxySSIReadingParagraphAnchor(scope: peerReadingScope', 'store.canRestoreMessageViewport',
  'private var peerReadingScope: String { store.profile.identityFingerprint']);
const health = read(app + 'GalaxySSIHealthMetricReadingAnchor.swift');
has(health, ['GalaxySSIReadingPosition.nearestKeys', 'pending.oldY', 'pending.ticket == ticket',
  'allowed?() == true', 'expected.contains($0)', 'old.split(separator: ":"',
  'view.scroll() === scroll', 'isDecelerating', 'weak var anchor', 'layoutSubviews',
  'scroll.setContentOffset', 'func clear()']);
const overview = read(app + 'GalaxySSIHealthMeasurementOverviewView.swift');
has(overview, ['readingAnchor.capture(); abnormal = $0', 'readingAnchor.capture(); expanded.toggle()',
  'readingAnchor.restore(keys: keys)', 'readingAnchor.capture()\n    guard query.adopt(staged',
  'series.key.unit', 'series.key.condition', 'series.key.side', 'readingAnchor.clear()',
  'GalaxySSIHealthMetricReadingAnchor.Marker', 'galaxySSIRuntimePlaintextWillClear']);
for (const f of ['GalaxySSIConversationComposer.swift', 'GalaxySSIHealthRecords.swift', 'AgentRichSelectableParagraphs.swift',
  'GalaxySSIHealthMeasurementQuery.swift', 'GalaxySSIServices.swift']) {
  assert.equal(read(app + f), old(app + f), `Preserve unrelated composer/authority/text selection: ${f}`);
}
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const f of ['GalaxySSIReadingPosition.swift', 'GalaxySSIReadingParagraphAnchor.swift',
  'GalaxySSIHealthMetricReadingAnchor.swift', 'GalaxySSIReadingPositionTests.swift']) {
  assert.equal(project.split(`/* ${f} in Sources */`).length - 1, 2);
  assert.equal(project.split(`path = ${f};`).length - 1, 1);
}
assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIReadingPositionTests.swift').match(/  func test\w+\(/g) || []).length, 10);
console.log('Reading-position source wiring checked: genuine reply signals, idle paragraph/row anchors, nearest surviving metrics and unchanged composer/authority. Ten authored Swift methods are not native acceptance.');
