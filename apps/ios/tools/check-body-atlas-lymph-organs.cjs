// Pinned Android resource parity only; this does not compile or execute Swift.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const read = name => JSON.parse(fs.readFileSync(path.join(assets, name + '.dataset/content.json')));
const pack = read('HealthAtlasLymphOrgans'), sha = '108afffd1545f2ba10633e754ba907dc38495132';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8', maxBuffer: 4_000_000});
assert.equal(pack.schema, 1); assert.equal(pack.source.androidPR, 4352); assert.equal(pack.source.mergeCommit, sha);
const kotlin = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLymphOrgans.kt');
const blocks = [...kotlin.matchAll(/lesson\("([^"]+)", R.drawable.(\w+), R.string.(\w+),([\s\S]*?)(?=\n        lesson|\n    \)\.associateBy)/g)];
assert.equal(blocks.length, 9); assert.equal(pack.plates.length, 9);
let features = 0, markers = 0, paths = 0;
for (const [index, plate] of pack.plates.entries()) {
  const block = blocks[index];
  assert.equal(plate.id, block[1]); assert.equal(plate.owner, block[1]); assert.equal(plate.viewLabel, block[3]);
  assert.equal(plate.aspectRatio, 360 / 280);
  const local = [...block[4].matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(f => ({
    marker: {id: f[1], x: Number(f[2]) / 360, y: Number(f[3]) / 280}, title: f[4], explanation: f[5]
  }));
  const anatomy = [...block[4].matchAll(/marker\("([^"]+)", (\d+), (\d+)\)/g)].map(m => ({
    id: m[1], x: Number(m[2]) / 360, y: Number(m[3]) / 280
  }));
  assert.deepEqual(plate.features, local); assert.deepEqual(plate.markers, anatomy);
  assert.deepEqual(plate.entryIDs, [plate.owner, ...anatomy.map(m => m.id)]);
  const stages = block[4].match(/intArrayOf\(([^)]+)\)/)[1].split(',').map(Number);
  assert.deepEqual(pack.stageFeatures[plate.owner], stages);
  features += local.length; markers += anatomy.length;
  assert.equal(plate.drawable, 'apps/android/app/src/main/res/drawable/' + block[2] + '.xml');
  paths += (source(plate.drawable).match(/<path\b/g) || []).length;
  const dir = path.join(assets, plate.asset + '.imageset'), metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  assert.equal(metadata.properties['preserves-vector-representation'], true);
  assert.equal(fs.readFileSync(path.join(dir, metadata.images[0].filename)).subarray(0, 5).toString(), '%PDF-');
}
assert.equal(features, 30); assert.equal(markers, 12); assert.equal(paths, 100);
const lesson = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLymphLessonView.kt');
const routes = {};
for (const block of lesson.matchAll(/"([^"]+)" -> listOf\(([\s\S]*?)\n        \)/g)) {
  routes[block[1]] = [...block[2].matchAll(/path\(([\d.]+)f, ([\d.]+)f\) \{([^}]+)\}/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])},
    commands: [...m[3].matchAll(/(cubicTo|quadTo)\(([^)]+)\)/g)].map(command => {
      const numbers = command[2].split(',').map(n => Number(n.trim().replace(/f$/, '')));
      return {kind: command[1] === 'quadTo' ? 'quad' : 'cubic',
        points: numbers.reduce((result, n, i) => { if (i % 2 === 0) result.push({x: n, y: numbers[i + 1]}); return result; }, [])};
    })
  }));
}
assert.deepEqual(pack.routes, routes);
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
for (const name of ['HealthAtlasDigestiveCells', 'HealthAtlasEndocrineCells', 'HealthAtlasSensoryCells', 'HealthAtlasCellContexts']) {
  const previous = read(name); apply(previous);
  for (const m of previous.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
}
apply(pack);
for (const m of pack.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
const android = JSON.parse(source('apps/android/app/src/main/assets/health/body-atlas.json'));
const sorted = list => [...list].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(entries.values()), sorted(android.entries));
assert.deepEqual(sorted(models.values()), sorted(android.mechanisms));
assert.equal(entries.size, 313); assert.equal(models.size, 178);

const xmljs = require('xml-js');
for (const [language, directory] of [['en', 'values'], ['zh-Hans', 'values-zh']]) {
  const xml = xmljs.xml2js(source('apps/android/app/src/main/res/' + directory + '/health_atlas_lymph_organs.xml'), {compact: true});
  const localized = new Map();
  for (const line of fs.readFileSync(path.join(root, language + '.lproj/BodyAtlas.strings'), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^"([^"]+)" = (".*");$/); if (!m) continue;
    assert(!localized.has(m[1]), 'Duplicate key: ' + m[1]); localized.set(m[1], JSON.parse(m[2]));
  }
  assert.equal(xml.resources.string.length, 124);
  for (const item of xml.resources.string) {
    const value = String(item._text ?? '').replace(/\\'/g, "'").replace(/%([0-9]+)\$s/g, '%$1$@');
    assert.equal(localized.get(item._attributes.name), value, language + ':' + item._attributes.name);
  }
}
console.log('Android #4352 parity: 9 organ lessons / 30 features / 12 canonical links / 100 paths; 8 exact transport routes; 248 localized strings; graph 313 entries / 178 mechanisms.');
