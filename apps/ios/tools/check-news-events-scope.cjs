'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const base = 'f6bc5f522b65be056071b56b8b17bd6c54eb4f56';
const app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {
  cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024
}).replace(/\r\n/g, '\n');
const has = (source, tokens) => tokens.forEach(token => assert.ok(source.includes(token), `Missing source wiring: ${token}`));
const events = read(app + 'PublicNewsEvents.swift');
has(events, ['window: TimeInterval = 36 * 3_600', '(12...512).contains(original.utf16.count)',
  'let title = headline(article.title)', 'let date = article.publishedAt', 'metadata.interests.isDisjoint(with: enabled)',
  'shared.intersection(topics)', 'timeIntervalSince(first.sortDate) > window', 'Set(reports.map(\\.source)).count > 1',
  'period.reversed()', 'seen.insert($0.id).inserted', 'readReports.compactMap { $0.article.readAt }.max()',
  '!report.article.read && report.article.discoveredAt > lastRead', 'guard !previous.isEmpty else { return nil }',
  'report.source, text', 'article.summary.prefix(900)', 'options: .bySentences', '(12...220).contains(line.utf16.count)',
  'result.count == 4', 'Task.checkCancellation()', 'if let first = period.first']);
assert.ok(!events.includes('article.displayTitle'), 'Translations must not become grouping keys');
assert.ok(!/URLSession|CloudModel|generateAsync|Task\.sleep/.test(events));
const view = read(app + 'GalaxySSIPublicNewsEventView.swift');
has(view, ['List(event.reports)', 'GalaxySSIPublicNewsCachedReportView(archive: archive, report: report)',
  'await archive.articleBodies.load(report.id)', 'checkpoint.source.paragraphs.joined',
  'guard !Task.isCancelled, retained', 'checkpoint.articleID == report.id', '!checkpoint.source.paragraphs.isEmpty',
  'archive.markRead(report.id)', 'scenePhase == .active', '.onAppear { markDisplayed() }',
  'if showsExcerpt, let excerpt = event.newExcerpt', 'event.newCount > 0', 'public_news_event_no_body', 'public_news_event_removed']);
assert.ok(!/PublicNewsArticleBody\.load|PublicNewsTranslation\.run|URLSession|CloudModel|\.refresh\(/.test(view));
assert.equal((view.match(/archive\.markRead\(/g) || []).length, 1, 'Only one exact report read mutation');
const archive = read(app + 'PublicNewsArchive.swift');
has(archive, ['markRead(Set([id]))', 'where !next[index].read && ids.contains(next[index].id)',
  'next[index].readAt = now', 'article.readAt = previous.readAt', 'article.discoveredAt = previous.discoveredAt']);
const feed = read(app + 'PublicNewsFeed.swift');
assert.equal(feed, old(app + 'PublicNewsFeed.swift').replace('  var sourceReview: PublicNewsSourceReview?\n',
  '  var sourceReview: PublicNewsSourceReview?\n  var readAt: Date?\n'), 'Preserve all/saved timelines, decoders and dwell logic');
const highlights = read(app + 'GalaxySSIPublicNewsHighlightsView.swift');
has(highlights, ['PublicNewsEvents.group(archiveSnapshot, enabled: enabled)',
  'PublicNewsEvents.representatives(archiveSnapshot, events: grouped)', 'deduplicateHeadlines: false',
  'GalaxySSIPublicNewsEventButton(event: event)', '.sheet(item: $selectedEvent)', 'events = grouped',
  'articles: archive.eligibleArticles']);
const timeline = read(app + 'GalaxySSIPublicNewsView.swift');
has(timeline, ['selected == nil && selectedEvent == nil', '.sheet(item: $selectedEvent)',
  'PublicNewsEvents.Request(articles: archive.eligibleArticles, mask: interestMask)',
  'GalaxySSIPublicNewsEventButton(event: event, showsExcerpt: !expanded)', 'archive.markRead(ready)',
  'withTaskCancellationHandler', 'worker.cancel()']);
for (const name of ['PublicNewsRowArchive.swift', 'PublicNewsTranslation.swift', 'PublicNewsArticleBody.swift',
  'PublicNewsSourceReview.swift', 'PublicNewsBacklogWorker.swift']) {
  assert.equal(read(app + name), old(app + name), `Do not alter existing storage/fetch/model policy: ${name}`);
}
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['PublicNewsEvents.swift', 'GalaxySSIPublicNewsEventView.swift', 'PublicNewsEventsTests.swift']) {
  assert.equal(project.split(`/* ${name} in Sources */`).length - 1, 2, `${name} build and source membership`);
  assert.equal(project.split(`path = ${name};`).length - 1, 1, `${name} file reference`);
}
const tests = read('apps/ios/GalaxySSITests/PublicNewsEventsTests.swift');
assert.equal((tests.match(/  func test\w+\(/g) || []).length, 10);
has(tests, ['testNewSourcesRequireAnActualRecordedReadNotAVisitOrLegacyReadFlag',
  'testReadingOneArchivedSourceDoesNotMarkTheOtherAndPersistsOnlyItsTimestamp',
  'testOnlyOriginalHeadlinesGroupWithoutMergingVersionsNegationOrTranslatedCollisions']);
const strings = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const key of ['reports', 'new_count', 'new', 'sources', 'removed', 'no_body']) {
  assert.equal(strings.split(`"public_news_event_${key}" =`).length - 1, 1);
}
console.log('News-event source wiring checked: conservative grouping, actual read baselines, individual cached sources and unchanged fetch/storage policy. Ten authored Swift methods are not runtime acceptance.');
