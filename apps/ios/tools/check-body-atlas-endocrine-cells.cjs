// Static source/resource composition, not Swift execution or a native UI test.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const read = name => JSON.parse(fs.readFileSync(path.join(assets, name + '.dataset/content.json')));
const pack = read('HealthAtlasEndocrineCells'), sha = '7281138717425cc4a5fb905f65084de0c14141d5';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8', maxBuffer: 4_000_000});
assert.equal(pack.source.mergeCommit, sha); assert.equal(pack.source.androidPR, 4349); assert.equal(pack.schema, 1);
const kotlin = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasEndocrinePlates.kt');
const blocks = [...kotlin.matchAll(/plate\("([^"]+)", R.drawable.(\w+),\s*"([^"]+)",\s*R.string.(\w+),([\s\S]*?)(?=\n        plate|\n    \))/g)];
assert.equal(blocks.length, 18); assert.equal(pack.plates.length, 18);
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
assert.equal(features, 37); assert.equal(markers, 4); assert.equal(paths, 239);
const pathSource = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasEndocrinePath.kt');
const pathways = {};
for (const m of pathSource.matchAll(/"([^"]+)" to HealthAtlasEndocrinePath\(R.string.(\w+), (true|false), listOf\(([\s\S]*?)(?=\n            "|\n        \))/g)) {
  const steps = [...m[4].matchAll(/step\(R.string.(\w+)(?:, "([^"]+)")?\)/g)].map(f => ({
    label: f[1], ...(f[2] ? {destination: f[2]} : {})
  }));
  pathways[m[1]] = {scope: m[2], separateBranches: m[3] === 'true', steps};
}
assert.deepEqual(pack.paths, pathways); assert.equal(Object.keys(pathways).length, 4);
for (const p of Object.values(pathways)) {
  assert.equal(p.steps.length, 4);
  for (const map of resources) for (const key of [p.scope, ...p.steps.map(s => s.label)]) assert(map.get(key));
}
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
const digestive = read('HealthAtlasDigestiveCells'); apply(digestive);
for (const m of digestive.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
apply(pack);
for (const m of pack.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
const android = JSON.parse(source('apps/android/app/src/main/assets/health/body-atlas.json'));
const sorted = list => [...list].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(entries.values()), sorted(android.entries));
assert.deepEqual(sorted(models.values()), sorted(android.mechanisms));
assert.equal(entries.size, 311); assert.equal(models.size, 164);
console.log('Android #4349 parity: 18 plates / 37 features / 4 anatomy links / 239 paths / 4 signal pathways; full graph 311 entries and 164 mechanisms.');
