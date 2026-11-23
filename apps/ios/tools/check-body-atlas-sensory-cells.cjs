// Static source/resource composition, not Swift execution or a native UI test.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const read = name => JSON.parse(fs.readFileSync(path.join(assets, name + '.dataset/content.json')));
const pack = read('HealthAtlasSensoryCells'), sha = 'e533b182cc41df22e2e1a6291f7751e4848f8bb4';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8', maxBuffer: 4_000_000});
assert.equal(pack.source.mergeCommit, sha); assert.equal(pack.source.androidPR, 4350); assert.equal(pack.schema, 1);
const artworkSHA = 'ac7ab99df542b67a7a0ea6a28999a7334b79aada';
const visualSource = file => execFileSync('git', ['show', artworkSHA + ':' + file], {maxBuffer: 16_000_000});
const portraits = new Set(['cell-rod-photoreceptor', 'cell-cone-photoreceptor', 'cell-inner-ear-hair-cell']);
assert.deepEqual(pack.artworkSource, {androidPR: 4361, mergeCommit: artworkSHA});
const kotlin = visualSource('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensoryPlates.kt').toString();
const blocks = [...kotlin.matchAll(/plate\("([^"]+)", R.drawable.(\w+),\s*"([^"]+)",\s*R.string.(\w+),([\s\S]*?)(?=\n        plate|\n    \))/g)];
assert.equal(blocks.length, 16); assert.equal(pack.plates.length, 16);
const resources = ['en', 'zh-Hans'].map(lang => {
  const map = new Map();
  for (const line of fs.readFileSync(path.join(root, lang + '.lproj/BodyAtlas.strings'), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^"([^"]+)" = (".*");$/); if (!m) continue;
    assert(!map.has(m[1]), 'Duplicate key ' + lang + ':' + m[1]); map.set(m[1], JSON.parse(m[2]));
  }
  return map;
});
let features = 0, markers = 0, paths = 0;
for (const [index, plate] of pack.plates.entries()) {
  const block = blocks[index];
  assert.equal(plate.owner, block[1]); assert.equal(plate.id, plate.owner);
  assert.equal(plate.viewKey, block[5].match(/viewKey = "([^"]+)"/)?.[1]);
  assert.equal(plate.selectorLabel, block[5].match(/selector = R.string.(\w+)/)?.[1]);
  assert.equal(plate.source, block[3]); assert.equal(plate.viewLabel, block[4]); assert.equal(plate.aspectRatio, portraits.has(plate.owner) ? 2 / 3 : 360 / 280);
  const local = [...block[5].matchAll(/feature\("([^"]+)", ([\d.]+f?), ([\d.]+f?), R.string.(\w+), R.string.(\w+)\)/g)].map(f => ({
    marker: {id: f[1], x: Number(f[2].replace(/f$/, '')) / (f[2].endsWith('f') ? 1 : 360),
      y: Number(f[3].replace(/f$/, '')) / (f[3].endsWith('f') ? 1 : 280)}, title: f[4], explanation: f[5]
  }));
  const anatomy = [...block[5].matchAll(/HealthAtlasMarker\("([^"]+)", (\d+) \/ 360f, (\d+) \/ 280f\)/g)].map(f => ({
    id: f[1], x: Number(f[2]) / 360, y: Number(f[3]) / 280
  }));
  assert.deepEqual(plate.features, local); assert.deepEqual(plate.markers, anatomy);
  assert.deepEqual(plate.entryIDs, [plate.owner, ...anatomy.map(m => m.id)]);
  assert.equal(new Set([...local.map(f => f.marker.id), ...anatomy.map(m => m.id)]).size, local.length + anatomy.length);
  for (const f of local) for (const map of resources) for (const key of [f.title, f.explanation]) assert(map.get(key));
  features += local.length; markers += anatomy.length;
  const painted = portraits.has(plate.owner);
  assert.equal(plate.drawable, 'apps/android/app/src/main/res/' + (painted ? 'drawable-nodpi/' : 'drawable/') + block[2] + (painted ? '.png' : '.xml'));
  const dir = path.join(assets, plate.asset + '.imageset'), metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  const bytes = fs.readFileSync(path.join(dir, metadata.images[0].filename));
  if (painted) {
    assert(bytes.equals(visualSource(plate.drawable))); assert.equal(bytes.subarray(1,4).toString(), 'PNG');
    assert(!metadata.properties?.['preserves-vector-representation']);
  } else {
    paths += (visualSource(plate.drawable).toString().match(/<path\b/g) || []).length;
    assert.equal(metadata.properties['preserves-vector-representation'], true);
    assert.equal(bytes.subarray(0, 5).toString(), '%PDF-');
  }
}
assert.equal(features, 34); assert.equal(markers, 3); assert.equal(paths, 151);
const routeSource = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasRetinaPath.kt');
const destinationBlock = routeSource.match(/private val destinations = listOf\(([\s\S]*?)\n    \)\.map/)[1];
const destinations = [...destinationBlock.matchAll(/listOf\(([^)]*)\)/g)].map(m => JSON.parse('[' + m[1] + ']'));
const native = fs.readFileSync(path.join(root, 'GalaxySSIHealthAtlasRetinaPath.swift'), 'utf8');
const nativeLinks = JSON.parse('[' + native.match(/private static let links = \[([\s\S]*?)\n  \]/)[1] + ']');
assert.deepEqual(nativeLinks, destinations); assert.equal(destinations.length, 4);
const base = JSON.parse(fs.readFileSync(path.join(root, 'body-atlas/body-atlas.json')));
const entries = new Map(base.entries.map(e => [e.id, e])), models = new Map(base.mechanisms.map(m => [m.id, m]));
function apply(delta, appendRelated = false) {
  for (const e of delta.entries || []) entries.set(e.id, e);
  for (const m of delta.mechanisms || []) models.set(m.id, m);
  for (const [id, additions] of Object.entries(delta.relatedAdditions || {})) {
    const e = entries.get(id), fresh = additions.filter(a => !e.related.includes(a));
    entries.set(id, {...e, related: appendRelated ? [...e.related, ...fresh] : [...fresh, ...e.related]});
  }
}
for (const name of ['HealthAtlasReproductiveCells', 'HealthAtlasOrganPlates', 'HealthAtlasRenal']) apply(read(name));
const cells = read('HealthAtlasCellProcesses'); apply(cells);
for (const [id, mechanism] of Object.entries(cells.entryMechanisms)) entries.set(id, {...entries.get(id), mechanism});
for (const name of ['HealthAtlasRespiration', 'HealthAtlasExtendedCells', 'HealthAtlasEar', 'HealthAtlasTissues', 'HealthAtlasHeartSectionPack']) apply(read(name));
apply(read('HealthAtlasSystemOverviews'), true);
for (const name of ['HealthAtlasDigestiveCells', 'HealthAtlasEndocrineCells']) {
  const previous = read(name); apply(previous);
  for (const m of previous.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
}
apply(pack);
for (const m of pack.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
const android = JSON.parse(source('apps/android/app/src/main/assets/health/body-atlas.json'));
assert.equal(pack.entries.length, 2);
assert.deepEqual(pack.entries, android.entries.filter(e => ['cell-retinal-bipolar-cell', 'cell-retinal-aii-amacrine-cell'].includes(e.id)));
const sorted = list => [...list].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(entries.values()), sorted(android.entries));
assert.deepEqual(sorted(models.values()), sorted(android.mechanisms));
assert.equal(entries.size, 313); assert.equal(models.size, 167);
console.log('Android #4361 visual parity / frozen #4350 graph: 16 plates / 34 features / 3 cell links / 151 retained vector paths / 3 portraits; exact relay actions; historical graph 313 entries and 167 mechanisms.');
