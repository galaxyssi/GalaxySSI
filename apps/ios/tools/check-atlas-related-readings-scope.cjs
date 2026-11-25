// Pinned source wiring, not Swift execution, permission/device testing or UI acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "115d6adeb661fd4357fea57517ca92d02ffe1f51";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 6);
const inventory = {schema: 1, source: {androidPR: 4418, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const readings = source("Readings"), row = source("RelatedReadings"), detail = source("Detail");
const view = read("apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift"), records = read("apps/ios/GalaxySSI/GalaxySSIHealthRecords.swift");
const latest = readings.split("  static func latest(")[1].split("  static func snapshot(")[0];
for (const token of ["Set(GalaxySSIHealthAtlasMetrics.forEntry(entryID))", "metrics.contains(reading.metric)", "!reading.deleted", "reading.isValid", "reading.measuredAt <= now",
  "(previous.measuredAt, previous.id.uuidString) >= (reading.measuredAt, reading.id.uuidString)"]) assert(latest.includes(token), token);
assert(!latest.includes("spec.")); assert(!latest.includes("interval"));
for (const token of ["let window = spec.interval", "let mapped = GalaxySSIHealthAtlasMetrics.forEntry(entryID).contains(spec.metric)",
  "latest: latest(current, entryID: entryID, now: now)", "trend: mapped ? current.filter", "$0.metric == spec.metric", "$0.measuredAt >= window.start", "$0.measuredAt < window.end", "$0.measuredAt <= min(now, spec.through)"])
  assert(readings.includes(token), token);
const access = readings.split("  func atlasMeasurements(")[1];
for (const token of ["metrics.contains(spec.metric)", "(1...366).contains(spec.days)", "spec.through <= now", "let permitted = archive.derivesOverview == true",
  "permitted ? .started : .blocked", "purpose: .overview, metrics: metrics", "purpose: .trend, metrics: [spec.metric]",
  "from: nil, through: now", "from: spec.interval.start", "spec.calendar.timeZone.identifier", "Array(audit.suffix(200))",
  "guard permitted else { throw Failure.permission }", "try persistAtlasReadAudit(archive)", "outcome = .complete"]) assert(access.includes(token), token);
assert(access.indexOf("try persistAtlasReadAudit(archive)") < access.indexOf("archive.current"));
assert(access.indexOf("guard permitted else") < access.indexOf("archive.current"));
assert.equal((access.match(/try persistAtlasReadAudit\(archive\)/g) || []).length, 2);
const audit = readings.split("  struct Audit:")[1].split("  struct Snapshot")[0];
assert(!audit.includes("GalaxySSIHealthReading")); assert(!audit.includes("value:")); assert(audit.includes("let consentEvent: UUID?"));
const priorRecords = git(["show", "6ca6b7b3e590c39ce7ef45476b2160fe2598f377:apps/ios/GalaxySSI/GalaxySSIHealthRecords.swift"]).toString();
assert.equal(records.replace("    var atlasReadAudit: [GalaxySSIHealthAtlasReadings.Audit]?\n", "")
  .replace("  func persistAtlasReadAudit(_ archive: Archive) throws { try persist(archive, notify: false) }\n\n", ""), priorRecords);
assert(records.includes("AES.GCM.seal(payload")); assert(records.includes(".completeFileProtection"));
assert(!detail.includes('Picker(t("measurements")'));
assert.equal((detail.match(/atlasEntryID: entry.id, atlasMetricSelection: \$selection.metric/g) || []).length, 2);
assert(detail.includes('entry.id + ":" + (selection.metric ?? first).rawValue + ":" + selection.window.rawValue'));
for (const token of ['"atlas-related-metrics"', '"atlas-metric-reading-" + metric.rawValue', '"atlas-metric-" + metric.rawValue',
  'ForEach(GalaxySSIHealthAtlasMetrics.forEntry(entryID))', 'if let readings {', 'GalaxySSIHealthOverviewHistoryView.amount',
  'GalaxySSIHealthOverviewMetricRow.origin', 'date.timeZone = zone', 'date.locale = GalaxySSILocalization.interfaceLocale',
  '.accessibilityAddTraits(selected == metric ? .isSelected : [])']) assert(row.includes(token), token);
for (const token of ['GalaxySSIHealthAtlasRelatedReadings(entryID: atlasEntryID', 'readings: atlasLatestReadings',
  'select: selectAtlasMetric', '"atlas-personal-trend-title"', 'records.atlasMeasurements(entryID: atlasEntryID, spec: trendSpec, now: now)',
  'current = result.trend', 'atlasLatestReadings = result.latest', 'catch GalaxySSIHealthRecords.Failure.permission',
  'allowed = false; error = false; atlasLatestReadings = nil', 'atlasMetricSelection.wrappedValue = candidate',
  'if let revealAtlasTrend { revealAtlasTrend.wrappedValue = true }', 'GalaxySSIHealthAtlasMetrics.forEntry(atlasEntryID).contains(candidate)',
  'atlasAnalysisIdentity = nil; explanation = nil; trend = nil; trendVersions = []',
  'NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)']) assert(view.includes(token), token);
for (const marker of ['.onDisappear {', 'else { trend = nil;', 'protectedDataBlocked = true', 'private func invalidate()', 'private func reload()']) {
  const part = view.slice(view.indexOf(marker), view.indexOf(marker) + 340); assert(part.includes("atlasLatestReadings = nil"), marker);
}
const beforeView = git(["show", "6ca6b7b3e590c39ce7ef45476b2160fe2598f377:apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift"]).toString();
const identity = text => text.split("  private var currentAtlasIdentity:")[1].split("  private func chart(")[0];
assert.equal(identity(view), identity(beforeView), "Selected metric/period/revisions/permissions still gate the Agent action");
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasRelatedReadings.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), new Set(["health_atlas_related_metrics", "health_atlas_metric_trend_title", "health_atlas_reading_source", "health_atlas_no_reading"]));
  assert.equal((table.get("health_atlas_reading_source").match(/%\d+\$@/g) || []).length, 2);
}
const privacy = read("apps/ios/GalaxySSI/GalaxySSIHealthCenterView.swift"), chinese = read("apps/ios/GalaxySSI/zh-Hans.lproj/Localizable.strings");
assert(privacy.includes("if let uses = archive.atlasReadAudit"));
for (const key of ["atlas_history", "atlas_overview", "atlas_trend", "access_blocked", "access_started", "access_complete"]) {
  assert(privacy.includes('"privacy.' + key + '"')); assert(chinese.includes('"galaxyssi.health.privacy.' + key + '"'));
}
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ["GalaxySSIHealthAtlasReadings.swift in Sources", "GalaxySSIHealthAtlasRelatedReadings.swift in Sources", "GalaxySSIHealthAtlasReadingsTests.swift in Sources", "AtlasRelatedReadings.strings in Resources"]) assert(pbx.includes(token));
const test = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasReadingsTests.swift");
for (const token of ['days: 366', 'month.trend.isEmpty', 'month.latest[.ldl]', 'XCTAssertNil(month.latest[.alt])', 'XCTAssertEqual(year.trend, [ldl])',
  'setPrivacy(.overview, enabled: false)', 'audit[1].metrics, [.ldl]', '$0.outcome == .blocked', 'spec: spec(.alt)', 'measuredAt: now.addingTimeInterval(1)']) assert(test.includes(token));
const files = inventory.files.map(file => {
  let kind, ios, note;
  if (file.path.endsWith("HealthAtlasMeasurements.kt")) {
    kind = "related-readings-and-scoped-encrypted-access"; ios = [swift("Readings"), swift("RelatedReadings"), swift("Detail"), "apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift", "apps/ios/GalaxySSI/GalaxySSIHealthRecords.swift", "apps/ios/GalaxySSI/GalaxySSIHealthCenterView.swift"];
    note = "Replace picker with mapped latest confirmed values/date/source. Latest list is independent of selected period; chart/Agent use selected metric/window only. Permission-gated projection logs bounded overview and single-metric trend scopes in encrypted archive before returning values; expose audit history. Clear decrypted display state on denial, invalidation, background and protected-data loss. No teaching-value fallback. Native access/scroll behavior unverified.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasRelatedReadings.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasRelatedReadings.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/Localizable.strings"];
    note = "Four exact original English/Chinese pairs, plus six iOS-native privacy audit labels using existing English fallback/Chinese resource conventions. All registered in Xcode.";
  } else if (file.path.includes("/androidTest/")) {
    kind = "android-device-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasReadingsTests.swift"];
    note = "Source fixtures for concurrent mapped latest values, older reading outside month but inside year, empty metric isolation, future/deleted/invalid exclusion, provenance, numeric/qualitative display, encrypted audit reopen and denied/unrelated reads. Source fixtures and wiring retain Agent identity gating. No Android/XCTest/device/screenshot execution.";
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts"); kind = "android-version-only"; ios = []; note = "No iOS version bump or IPA.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)));
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const name = "apps/ios/ANDROID_4418_" + suffix + ".json", text = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, name), text); else assert.equal(read(name), text);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --related-readings-4418 --check", "check-atlas-whole-actions-scope.cjs --checks"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4418: six pinned source files, four original bilingual pairs, related-latest/scoped-trend/audit/lifecycle source wiring. Not native execution or acceptance.");
