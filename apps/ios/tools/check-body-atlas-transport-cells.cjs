// Static source/resource parity only; this does not compile or execute the iOS app.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const pack = JSON.parse(fs.readFileSync(path.join(assets, 'HealthAtlasTransportCells.dataset/content.json')));
const sha = 'ee54cfd25d31e05eb34bd97f1557a404ae337b10';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8'});
assert.equal(pack.source.mergeCommit, sha); assert.equal(pack.source.androidPR, 4347); assert.equal(pack.schema, 1);
const kotlin = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasTransportCellPlates.kt');
const blocks = [...kotlin.matchAll(/plate\("([^"]+)", R.drawable.(\w+), "([^"]+)",([\s\S]*?)(?=\n        plate|\n    \))/g)];
assert.equal(blocks.length, 12); assert.equal(pack.plates.length, 12);
const resources = ['en', 'zh-Hans'].map(lang => {
  const values = new Map();
  for (const line of fs.readFileSync(path.join(root, lang + '.lproj/BodyAtlas.strings'), 'utf8').split(/\r?\n/)) {
    const match = line.match(/^"([^"]+)" = (".*");$/);
    if (!match) continue;
    assert(!values.has(match[1]), 'Duplicate key ' + lang + ':' + match[1]);
    values.set(match[1], JSON.parse(match[2]));
  }
  return values;
});
let features = 0, paths = 0;
for (const [index, plate] of pack.plates.entries()) {
  const block = blocks[index];
  assert.equal(plate.owner, block[1]); assert.equal(plate.id, plate.owner);
  assert.deepEqual(plate.entryIDs, [plate.owner]); assert.deepEqual(plate.markers, []);
  assert.equal(plate.source, 'https://openstax.org/books/anatomy-and-physiology-2e/pages/' + block[3]);
  const caption = plate.owner === 'cell-collecting-duct-intercalated-cell' ? 'health_atlas_type_a_intercalated_view' : plate.owner === 'cell-urothelial-cell' ? 'health_atlas_umbrella_view' : 'health_atlas_cell_morphology';
  assert.equal(plate.viewLabel, caption); assert.equal(plate.aspectRatio, 360 / 280);
  const expected = [...block[4].matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(f => ({
    marker: {id: f[1], x: Number(f[2]) / 360, y: Number(f[3]) / 280}, title: f[4], explanation: f[5]
  }));
  assert.deepEqual(plate.features, expected);
  assert.equal(new Set(expected.map(f => f.marker.id)).size, expected.length);
  for (const feature of expected) {
    for (const localized of resources) for (const key of [feature.title, feature.explanation]) assert(localized.get(key));
    features++;
  }
  assert.equal(plate.drawable, 'apps/android/app/src/main/res/drawable/' + block[2] + '.xml');
  paths += (source(plate.drawable).match(/<path\b/g) || []).length;
  const dir = path.join(assets, plate.asset + '.imageset');
  const metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  assert.equal(metadata.properties['preserves-vector-representation'], true);
  assert.equal(fs.readFileSync(path.join(dir, metadata.images[0].filename)).subarray(0, 5).toString(), '%PDF-');
}
assert.equal(features, 25); assert.equal(paths, 88);
console.log('Transport cell parity: 12 plates, 25 features, 88 original paths; exact owners, subtype captions, chapters and coordinates.');
