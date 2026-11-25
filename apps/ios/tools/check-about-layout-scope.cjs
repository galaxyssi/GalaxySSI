// Source contracts only; not a SwiftUI layout or accessibility execution.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ee17e7cac043350e3f65c10ba025ecf55cde10c7';
const android = '16bdaa3e06a5126a5c7b77d1bcdb579cba2633a4';
const normalize = text => text.replace(/\r\n/g, '\n');
const read = file => normalize(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => normalize(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const section = (text, start, end) => {
  const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return text.slice(first, last);
};
const file = app + 'GalaxySSIAboutView.swift', view = read(file), previous = show(base, file);
assert.equal(section(view, '  private var versionName:', '  var body:'), section(previous, '  private var versionName:', '  var body:'));
assert.equal(section(view, '      GalaxySSISecurityNavigationRow(', 'private struct GalaxySSIAboutVersionRow:'),
  section(previous, '      GalaxySSISecurityNavigationRow(', 'private struct GalaxySSIAboutHeroView:'));
assert(!view.includes('GalaxySSIAboutHeroView') && !view.includes('about_product_subtitle'));
assert.equal(view.split('"v\\(versionName)"').length, 2, 'Installed version displayed once');
for (const token of ['GalaxySSIAboutVersionRow(', 'if dynamicTypeSize.isAccessibilitySize',
  '.lineLimit(nil)', '.fixedSize(horizontal: false, vertical: true)', '.font(.body)',
  '.accessibilityElement(children: .combine)', '.textSelection(.enabled)']) assert(view.includes(token), token);
const row = view.slice(view.indexOf('private struct GalaxySSIAboutVersionRow:'));
for (const forbidden of ['Button(', 'NavigationLink', '.lineLimit(1)', '.minimumScaleFactor', 'ViewThatFits']) assert(!row.includes(forbidden), forbidden);
assert.equal(read(app + 'GalaxySSISecurityCenterComponents.swift'), show(base, app + 'GalaxySSISecurityCenterComponents.swift'));
assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), show(base, 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'));
const androidSource = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityDataAndMedia.kt');
const androidAbout = section(androidSource, 'internal fun MainActivity.showAboutGalaxySSIPage()', 'internal fun MainActivity.', );
assert(!androidAbout.includes('featureHeroCard('));
assert(androidAbout.includes('featureValueRow(') && androidAbout.includes('valueMaxLines = 3'));
const androidTests = show(android, 'apps/android/app/src/androidTest/java/com/galaxyssi/chat/AboutPageUiDeviceTest.kt');
for (const name of ['productSectionStartsPageWithoutDuplicateHero', 'installedVersionIsCompleteAndNotAnAction',
  'narrowLayoutWithLargeTextKeepsEveryVersionCharacterVisible', 'protocolAndSecurityActionsRemainAvailable']) assert(androidTests.includes(name));
console.log('About layout/source scope passed: no duplicate hero, installed value wraps, accessibility branch and existing actions retained. No SwiftUI/device acceptance.');
