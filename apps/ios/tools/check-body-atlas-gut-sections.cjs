// Pinned Android resource parity only; this does not compile or execute Swift.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '../GalaxySSI'), assets = path.join(root, 'Assets.xcassets');
const read = name => JSON.parse(fs.readFileSync(path.join(assets, name + '.dataset/content.json')));
const pack = read('HealthAtlasGutSections'), sha = 'eb17db473412f018fe6b67eb364bdbe482210b5b';
const source = file => execFileSync('git', ['show', sha + ':' + file], {encoding: 'utf8', maxBuffer: 4_000_000});
assert.equal(pack.schema, 1); assert.equal(pack.source.androidPR, 4353); assert.equal(pack.source.mergeCommit, sha);
assert.deepEqual(pack.functionArtworkSource, {androidPR: 4384, mergeCommit: 'ab78711d467c013444883dbaeca23c39a601c875'});
execFileSync(process.execPath, [path.join(__dirname, 'check-body-atlas-sensory-sections.cjs'), '--function-gut-structures'], {stdio: 'inherit'});
const kotlin = source('apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGutSections.kt');
const latestSha = 'ab78711d467c013444883dbaeca23c39a601c875';
execFileSync(process.execPath, [path.join(__dirname, 'check-atlas-function-gut-plates.cjs')], {stdio: 'inherit'});
const latest = execFileSync('git', ['show', latestSha + ':apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGutSections.kt'], {encoding: 'utf8'});
const blocks = [...kotlin.matchAll(/section\("([^"]+)", R.drawable.(\w+), R.string.(\w+), (\w+),([\s\S]*?)(?=\n        section|\n    \)\.associateBy)/g)];
const latestBlocks = [...latest.matchAll(/section\("([^"]+)", R.drawable.(\w+), R.string.(\w+), (\w+),([\s\S]*?)(?=\n        section|\n    \)\.associateBy)/g)];
const book = 'https://openstax.org/books/anatomy-and-physiology-2e/pages/';
const chapters = {UPPER: '23-3-the-mouth-pharynx-and-esophagus', STOMACH: '23-4-the-stomach', INTESTINES: '23-5-the-small-and-large-intestines'};
assert.equal(blocks.length, 14); assert.equal(pack.plates.length, 14);
let features = 0, markers = 0, paths = 0, tracks = 0;
const routes = {};
for (const [index, plate] of pack.plates.entries()) {
  const painted = ['teeth', 'jejunum'].includes(plate.owner);
  const b = (painted ? latestBlocks : blocks)[index], body = b[5];
  const width = painted ? 1254 : 360, height = painted ? 1254 : 280;
  assert.equal(plate.id, b[1]); assert.equal(plate.owner, b[1]); assert.equal(plate.viewLabel, b[3]);
  assert.equal(plate.source, book + chapters[b[4]]); assert.equal(plate.aspectRatio, painted ? 1 : 360 / 280);
  const local = [...body.matchAll(/(?:feature|paintedFeature)\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(f => ({
    marker: {id: f[1], x: Number(f[2]) / width, y: Number(f[3]) / height}, title: f[4], explanation: f[5]
  }));
  const anatomy = [...body.matchAll(/(?:marker|paintedMarker)\("([^"]+)", (\d+), (\d+)\)/g)].map(m => ({
    id: m[1], x: Number(m[2]) / width, y: Number(m[3]) / height
  }));
  assert.deepEqual(plate.features, local); assert.deepEqual(plate.markers, anatomy);
  assert.deepEqual(plate.entryIDs, [plate.owner, ...anatomy.map(m => m.id)]);
  assert.deepEqual(pack.stageFeatures[plate.owner], body.match(/listOf\(([\d, ]+)\)/)[1].split(',').map(Number));
  const motion = [...body.matchAll(/atlasSectionTrack\(([\d.]+)f, ([\d.]+)f\) \{([^}]+)\}/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])},
    commands: [...m[3].matchAll(/(lineTo|cubicTo|quadTo)\(([^)]+)\)/g)].map(c => {
      const numbers = c[2].split(',').map(n => Number(n.trim().replace(/f$/, '')));
      return {kind: {lineTo: 'line', cubicTo: 'cubic', quadTo: 'quad'}[c[1]],
        points: numbers.reduce((result, n, i) => { if (i % 2 === 0) result.push({x: n, y: numbers[i + 1]}); return result; }, [])};
    })
  }));
  if (motion.length) { assert.equal(motion.length, 4); routes[plate.owner] = motion; tracks += motion.length; }
  const notes = ['health_atlas_gut_section_' + (motion.length ? 'motion_scope' : 'regional_scope'),
    ...[...body.matchAll(/note = R.string.(\w+)/g)].map(m => m[1])];
  assert.deepEqual(pack.notes[plate.owner], notes);
  features += local.length; markers += anatomy.length;
  if (painted) {
    assert.equal(plate.drawable, 'apps/android/app/src/main/res/drawable-nodpi/' + b[2] + '.png');
    // The dedicated #4384 audit verifies original PNG bytes, anchors and square lesson fitting.
  } else {
    assert.equal(plate.drawable, 'apps/android/app/src/main/res/drawable/' + b[2] + '.xml');
    paths += (source(plate.drawable).match(/<path\b/g) || []).length;
    const dir = path.join(assets, plate.asset + '.imageset'), metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
    assert.equal(metadata.properties['preserves-vector-representation'], true);
    assert.equal(fs.readFileSync(path.join(dir, metadata.images[0].filename)).subarray(0, 5).toString(), '%PDF-');
  }
}
assert.equal(features, 47); assert.equal(markers, 29); const replacedPaths = ['tooth', 'jejunum'].reduce((n, slug) => n + (source('apps/android/app/src/main/res/drawable/health_atlas_gut_' + slug + '.xml').match(/<path\b/g) || []).length, 0);
assert.equal(paths, 99 - replacedPaths); assert.equal(tracks, 24);
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
apply(read('HealthAtlasLymphOrgans'));
apply(pack);
for (const m of pack.mechanisms) entries.set(m.id, {...entries.get(m.id), mechanism: m.id});
const android = JSON.parse(source('apps/android/app/src/main/assets/health/body-atlas.json'));
const sorted = list => [...list].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(entries.values()), sorted(android.entries));
assert.deepEqual(sorted(models.values()), sorted(android.mechanisms));
assert.equal(entries.size, 313); assert.equal(models.size, 192);

const xmljs = require('xml-js');
for (const [language, directory] of [['en', 'values'], ['zh-Hans', 'values-zh']]) {
  const xml = xmljs.xml2js(source('apps/android/app/src/main/res/' + directory + '/health_atlas_gut_sections.xml'), {compact: true});
  const localized = new Map();
  for (const line of fs.readFileSync(path.join(root, language + '.lproj/BodyAtlas.strings'), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^"([^"]+)" = (".*");$/); if (!m) continue;
    assert(!localized.has(m[1]), 'Duplicate key: ' + m[1]); localized.set(m[1], JSON.parse(m[2]));
  }
  assert.equal(xml.resources.string.length, 192);
  for (const item of xml.resources.string) {
    const value = String(item._text ?? '').replace(/\\'/g, "'").replace(/%([0-9]+)\$s/g, '%$1$@').replace(/%([0-9]+)\$d/g, '%$1$lld');
    assert.equal(localized.get(item._attributes.name), value, language + ':' + item._attributes.name);
  }
}

console.log('Alimentary checkpoint: 14 sections / 47 features / 29 links; 12 #4384 shaded vector plates plus two #4384 painted replacements, 24 exact motion tracks / 384 localized values; graph 313 entries and 192 mechanisms. No native rendering executed.');
