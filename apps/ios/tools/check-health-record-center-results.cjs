// Source contracts only; no Swift compilation or UI/locale execution.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const displayApproved = '5f5a2f7b4a8808fa037bb5a5523a4baea4efccbb';
const tilesApproved = 'cf2fa04780024bb2beec3822550ef9ec5c8343d4';
const approved = '795d64ab0cfb0040dc180ced65275383f75a0fb9';
const file = app + 'GalaxySSIHealthRecordCenterView.swift';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function validate(source) { assert.equal(source, show(approved, file), 'Exact typed results, adaptive entries and mixed review ordering'); }
function between(s, start, end) {
  assert.equal(s.split(start).length, 2, start);
  const offset = s.indexOf(start), finish = s.indexOf(end, offset + start.length);
  assert(finish > offset, end); return s.slice(offset, finish);
}
function withoutReviews(source) {
  validate(source);
  source = once(source, between(show(approved, file), 'struct GalaxySSIHealthRecordCenterSnapshot {\n', '@MainActor\n'),
    between(show(tilesApproved, file), 'struct GalaxySSIHealthRecordCenterSnapshot {\n', '@MainActor\n'));
  const start = '            if snapshot.reviews.isEmpty, snapshot.draft == nil {\n';
  const end = '            NavigationLink {\n              GalaxySSIHealthTableImportView(records: records)\n';
  source = once(source, between(show(approved, file), start, end),
    between(show(tilesApproved, file), start.replace('reviews', 'pending'), end));
  source = once(source, between(show(approved, file), '  @ViewBuilder\n  private func reviewRow(', '  private var entries:'), '');
  assert.equal(source, show(tilesApproved, file), 'Only review projection, mixed pagination and exact resume row changed');
  return source;
}
function withoutTiles(source) {
  source = withoutReviews(source);
  source = once(source, '  @ScaledMetric(relativeTo: .body) private var entryMinimumWidth: CGFloat = 325\n', '');
  source = once(source, '  @State private var entryWidth: CGFloat = 0\n', '');
  const section = '        Section(t("record_center.entry", "Record health data")) {\n';
  source = once(source, between(show(tilesApproved, file), section, '        if failed {'),
    between(show(displayApproved, file), section, '        if failed {'));
  source = once(source, between(show(tilesApproved, file), '  private var entries: some View {\n',
    '  private func summary('), '');
  assert.equal(source, show(displayApproved, file), 'Only entry tiles, scaled width and measured width changed');
  return source;
}
function retainedView(source) {
  if (source === show(base, file)) return source;
  validate(source); return show(base, file);
}
const fixture = 'apps/ios/GalaxySSITests/GalaxySSIHealthRecordsTests.swift';
const fixtureStart = '  func testRecordCenterMergesTableAndReportReviewsByJobCreationBeforePagination() {\n';
const fixtureEnd = '  func testIndividualTargetRequiresCurrentRecordAndRevokesWithoutErasingHistory() throws {\n';
function retainedTests(source) {
  if (!source.includes(fixtureStart)) return source;
  const block = between(show(approved, fixture), fixtureStart, fixtureEnd);
  assert.equal(between(source, fixtureStart, fixtureEnd), block, 'Exact owned mixed-review fixtures');
  return once(source, block, '');
}
function retentionNormalize(file, source) {
  const tool = path.join(__dirname, 'check-photo-original-retention.cjs');
  if (fs.existsSync(tool)) source = require(tool).retained(file, source);
  const restore = path.join(__dirname, 'check-restore-file-finalization.cjs');
  if (file === fixture && fs.existsSync(restore)) source = require(restore).retainedFixtures(source);
  return source;
}
module.exports = {retainedView, retainedTests};
if (require.main === module) {
  const source = read(file); validate(source);
  const helper = '  private func summary(_ reading: GalaxySSIHealthReading) -> String {\n' +
    '    let value = reading.reported?.raw ?? reading.value?.formatted(.number.locale(locale)) ?? ""\n' +
    '    let lower = reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) } ?? ""\n' +
    '    return value + lower + (reading.unit.isEmpty ? "" : " " + reading.unit)\n  }\n\n';
  let expected = once(show(base, file), '  @Environment(\\.galaxySSIInterfaceLanguage) private var language\n',
    '  @Environment(\\.galaxySSIInterfaceLanguage) private var language\n  @Environment(\\.locale) private var locale\n');
  expected = once(expected, 'Text((reading.value?.formatted() ?? "") + " " + reading.unit)', 'Text(summary(reading))');
  expected = once(expected, '  private func reload() {', helper + '  private func reload() {');
  assert.equal(withoutTiles(source), expected, 'All review/recent navigation, draft guards, grouping, reload and lifecycle retained');
  const unindent = s => s.split('\n').map(line => line.trimStart()).join('\n');
  assert(unindent(read(app + 'GalaxySSIHealthMetricCatalogView.swift')).includes(unindent(helper)), 'Reuse catalog result semantics');
  const reference = show('7c98635fab8b5c0e27ec0f19c95b94acf0432a61',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthRecordCenterView.kt');
  assert(reference.includes('healthDisplayValue(record.draft)'));
  assert(reference.includes('configuration.screenWidthDp / configuration.fontScale.coerceAtLeast(1f) < 325f'));
  const androidStore = show('7c98635fab8b5c0e27ec0f19c95b94acf0432a61',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthOriginalStore.kt');
  assert(androidStore.includes('ORDER BY created_at DESC,id DESC'));
  const androidReviews = show('7c98635fab8b5c0e27ec0f19c95b94acf0432a61',
    'apps/android/app/src/main/java/com/galaxyssi/chat/HealthOverviewRepository.kt');
  for (const token of ['HealthOverviewReviewKind.TABLE', 'HealthOverviewReviewKind.OCR', 'job.createdAt'])
    assert(androidReviews.includes(token), token);
  const normalizedTests = retentionNormalize(fixture, read(fixture));
  assert.equal(normalizedTests, show(approved, fixture), 'Exact authored mixed review fixture source, not executed');
  assert.equal(retainedTests(normalizedTests),
    show(base, fixture), 'All preexisting fixtures retained');
  const translations = app + 'zh-Hans.lproj/Localizable.strings';
  const keys = ['scan', 'manual', 'devices', 'photo_note', 'manual_note', 'import_note', 'sources_note'];
  for (const key of keys) {
    const prefix = '"galaxyssi.health.record_center.' + key + '" = ';
    const lines = s => s.split('\n').filter(line => line.startsWith(prefix));
    assert.equal(lines(read(translations)).length, 1, key + ': unique translation');
    assert.deepEqual(lines(read(translations)), lines(show(approved, translations)), key + ': approved translation');
    assert(source.includes('t("record_center.' + key + '"'), key + ': actual tile uses resource');
  }
  for (const name of ['GalaxySSIHealthRecords', 'GalaxySSIHealthMetricCatalog', 'GalaxySSIHealthReportReview']) {
    const file = app + name + '.swift';
    const source = name === 'GalaxySSIHealthRecords' ? retentionNormalize(file, read(file)) : read(file);
    assert.equal(source, show(base, file), name + ': unchanged data boundary outside exact photo retention');
  }
  const mutations = [
    ['reading.reported?.raw ?? ', ''],
    ['reading.value?.formatted(.number.locale(locale))', 'reading.value?.formatted()'],
    ['reading.diastolic.map { "/" + $0.formatted(.number.locale(locale)) }', 'reading.pulse.map { "/" + $0.formatted(.number.locale(locale)) }'],
    ['return value + lower +', 'return value +'],
    ['reading.unit.isEmpty ? "" : " " + reading.unit', '" " + reading.metric.unit'],
    ['Text(summary(reading))', 'Text(reading.value?.formatted() ?? "")'],
    ['.disabled(snapshot.draft != nil)', '.disabled(false)'],
    ['guard scene == .active else { return }', 'guard true else { return }'],
    ['count: entryWidth < entryMinimumWidth ? 1 : 2', 'count: 2'],
    ['@ScaledMetric(relativeTo: .body)', '@State'],
    ['.onChange(of: geometry.size.width) { entryWidth = $0 }', ''],
    ['.buttonStyle(.plain)', '.buttonStyle(.automatic)'],
    ['initialAction: .files', 'initialAction: .none'],
    ['Button { addManual(nil) }', 'Button {}'],
    ['NavigationLink(destination: devices)', 'NavigationLink(destination: EmptyView())'],
    ['.accessibilityHidden(true)', '.accessibilityHidden(false)'],
    ['pending.map(Review.report) + (archive.tableReviews ?? []).map(Review.table)', 'pending.map(Review.report)'],
    ['snapshot.reviews.isEmpty', 'snapshot.pending.isEmpty'],
    ['ForEach(snapshot.reviews.prefix(pendingLimit))', 'ForEach(snapshot.reviews)'],
    ['if snapshot.reviews.count > pendingLimit', 'if snapshot.pending.count > pendingLimit'],
    ['($0.at, $0.id) > ($1.at, $1.id)', '($0.at, $0.id) < ($1.at, $1.id)'],
    ['$0.original.id == source.original && $0.original.sha256 == source.sha256', '$0.original.id == source.original'],
    ['let addedAt = jobDate ?? originalDate.flatMap', 'let addedAt = stagedDate ?? originalDate.flatMap'],
    ['?? stagedDate ?? .distantPast', '?? items.first?.reading.measuredAt ?? .distantPast'],
    ['resumeReviewID: draft.id, resumeReviewVersion: draft.version', 'resumeReviewID: draft.id'],
    ['"table:" + table.id.uuidString + ":" + table.version.uuidString', 'table.id.uuidString'],
    ['.map(\\.addedAt).filter { $0.timeIntervalSinceReferenceDate.isFinite }.max()', '.map(\\.addedAt).max()'],
    ['}.sorted { ($0.addedAt, $0.id) > ($1.addedAt, $1.id) }', '}']
  ];
  for (const [from, to] of mutations) {
    assert(source.includes(from), from);
    assert.throws(() => validate(source.replace(from, to)));
    assert.throws(() => retainedView(source.replace(from, to)));
  }
  console.log('Record center result/tile/review contracts, seven resources and 28 negative source mutations passed; Swift fixtures not executed.');
}
