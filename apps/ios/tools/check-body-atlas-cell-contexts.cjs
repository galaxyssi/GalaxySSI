// Static source/resource composition, not Swift execution or a native UI test.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const read = name => JSON.parse(fs.readFileSync(path.join(assets, name + '.dataset/content.json')));
const pack = read('HealthAtlasCellContexts'), sha = '3db9c86a0fdb74f52ffbba29dd87c652dddb6587';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8', maxBuffer: 4_000_000});
assert.equal(pack.source.mergeCommit, sha); assert.equal(pack.source.androidPR, 4351); assert.equal(pack.schema, 1);
const kotlin = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasTissueContextPlates.kt');
const blocks = [...kotlin.matchAll(/plate\("([^"]+)", R.drawable.(\w+),\s*"([^"]+)",\s*R.string.(\w+),([\s\S]*?)(?=\n        plate|\n    \))/g)];
assert.equal(blocks.length, 23); assert.equal(pack.plates.length, 23);
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
  assert.equal(plate.source, block[3]); assert.equal(plate.viewLabel, block[4]); assert.equal(plate.aspectRatio, 360 / 280);
  const local = [...block[5].matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(f => ({
    marker: {id: f[1], x: Number(f[2]) / 360, y: Number(f[3]) / 280}, title: f[4], explanation: f[5]
  }));
  const anatomy = [...block[5].matchAll(/HealthAtlasMarker\("([^"]+)", (\d+) \/ 360f, (\d+) \/ 280f\)/g)].map(f => ({
    id: f[1], x: Number(f[2]) / 360, y: Number(f[3]) / 280
  }));
  assert.deepEqual(plate.features, local); assert.deepEqual(plate.markers, anatomy);
  assert.deepEqual(plate.entryIDs, [plate.owner, ...anatomy.map(m => m.id)]);
  assert.equal(new Set([...local.map(f => f.marker.id), ...anatomy.map(m => m.id)]).size, local.length + anatomy.length);
  for (const f of local) for (const map of resources) for (const key of [f.title, f.explanation]) assert(map.get(key));
  features += local.length; markers += anatomy.length;
  assert.equal(plate.drawable, 'apps/android/app/src/main/res/drawable/' + block[2] + '.xml');
  paths += (source(plate.drawable).match(/<path\b/g) || []).length;
  const dir = path.join(assets, plate.asset + '.imageset'), metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  assert.equal(metadata.properties['preserves-vector-representation'], true);
  assert.equal(fs.readFileSync(path.join(dir, metadata.images[0].filename)).subarray(0, 5).toString(), '%PDF-');
}
assert.equal(features, 46); assert.equal(markers, 2); assert.equal(paths, 168);
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
for (const name of ['HealthAtlasDigestiveCells', 'HealthAtlasEndocrineCells', 'HealthAtlasSensoryCells']) {
  const previous = read(name); apply(previous);
  for (const m of previous.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
}
apply(pack);
for (const m of pack.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
const android = JSON.parse(source('apps/android/app/src/main/assets/health/body-atlas.json'));
const sorted = list => [...list].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(entries.values()), sorted(android.entries));
assert.deepEqual(sorted(models.values()), sorted(android.mechanisms));
assert.equal(entries.size, 313); assert.equal(models.size, 169);
const microscopic = [...entries.values()].filter(e => ['cell', 'fragment'].includes(e.kind));
const pictures = new Map([['cell-pancreatic-beta-cell', 'HealthAtlasBetaCell']]);
for (const name of ['HealthAtlasCellProcesses', 'HealthAtlasTransportCells', 'HealthAtlasCoreCells', 'HealthAtlasImmuneCells',
  'HealthAtlasDigestiveCells', 'HealthAtlasEndocrineCells', 'HealthAtlasSensoryCells', 'HealthAtlasCellContexts']) {
  for (const p of read(name).plates) if (microscopic.some(e => e.id === p.owner)) pictures.set(p.owner, p.asset);
}
assert.equal(microscopic.length, 108);
assert.equal(pictures.size, 108); assert.equal(new Set(pictures.values()).size, 108);
assert.deepEqual([...pictures.keys()].sort(), microscopic.map(e => e.id).sort());
for (const asset of pictures.values()) {
  const dir = path.join(assets, asset + '.imageset'), metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  assert(metadata.images.some(i => i.filename && fs.existsSync(path.join(dir, i.filename))));
}
for (const p of read('HealthAtlasMusculoskeletal').plates) assert(!p.entryIDs.some(id => pictures.has(id)));
const original = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSweatView.kt');
const duct = original.match(/PathMeasure\(Path\(\)\.apply \{([\s\S]*?)\}, false\)/)[1];
const expected = [...duct.matchAll(/(moveTo|lineTo|quadTo)\(([^)]+)\)/g)].map(m => [
  m[1], m[2].split(',').map(n => Number(n.trim().replace(/f$/, '')))
]);
const native = fs.readFileSync(path.join(root, 'GalaxySSIHealthAtlasSweatView.swift'), 'utf8');
const actual = [...native.matchAll(/path\.(move|addLine)\(to: CGPoint\(x: ([\d.-]+), y: ([\d.-]+)\)\)|path\.addQuadCurve\(to: CGPoint\(x: ([\d.-]+), y: ([\d.-]+)\), control: CGPoint\(x: ([\d.-]+), y: ([\d.-]+)\)\)/g)]
  .map(m => m[1] ? [m[1] === 'move' ? 'moveTo' : 'lineTo', [Number(m[2]), Number(m[3])]] :
    ['quadTo', [Number(m[6]), Number(m[7]), Number(m[4]), Number(m[5])]]);
assert.deepEqual(actual, expected);
console.log('Android #4351 parity: 23 plates / 46 features / 2 cell links / 168 paths; 108 distinct microscopic pictures; exact sweat duct; full graph 313 entries and 169 mechanisms.');
