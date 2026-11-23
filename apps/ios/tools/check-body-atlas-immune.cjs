// Static resource audit; does not execute Swift or replace native UI validation.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..', 'GalaxySSI');
const assets = path.join(root, 'Assets.xcassets');
const pack = JSON.parse(fs.readFileSync(path.join(assets, 'HealthAtlasImmuneCells.dataset/content.json')));
const sha = 'f32823ec6fce4a44760313b69f7a77caef57b65e';
assert.equal(pack.source.mergeCommit, sha);
assert.equal(pack.source.androidPR, 4345);
assert.equal(pack.schema, 1);
assert.equal(pack.plates.length, 12);
assert.equal(new Set(pack.plates.map(p => p.owner)).size, 12);
const source = execFileSync('git', ['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmunePlates.kt'], {encoding: 'utf8'});
let paths = 0, features = 0;
for (const plate of pack.plates) {
  assert(source.includes('"' + plate.owner + '"'));
  assert.equal(plate.id, plate.owner);
  assert.deepEqual(plate.entryIDs, [plate.owner]);
  const painted = ["cell-macrophage","cell-neutrophil","cell-eosinophil","cell-basophil"].includes(plate.owner);
  assert.equal(plate.aspectRatio, painted ? 1 : 360 / 280);
  assert.deepEqual(plate.markers, []);
  const ids = new Set();
  for (const feature of plate.features) {
    assert(!ids.has(feature.marker.id)); ids.add(feature.marker.id);
    assert(source.includes('"' + feature.marker.id + '"'));
    assert.equal(feature.explanation, feature.title + '_detail');
    for (const axis of ['x', 'y']) assert(Number.isFinite(feature.marker[axis]) && feature.marker[axis] >= 0 && feature.marker[axis] <= 1);
    for (const lang of ['en', 'zh-Hans']) {
      const resource = fs.readFileSync(path.join(root, lang + '.lproj/BodyAtlas.strings'), 'utf8');
      for (const key of [feature.title, feature.explanation]) assert(resource.includes('"' + key + '" = "'));
    }
    features++;
  }
  const dir = path.join(assets, plate.asset + '.imageset');
  const metadata = JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json')));
  if (painted) {
    assert(metadata.images.some(i=>i.filename==="cell.png"));
    assert(!metadata.properties?.["preserves-vector-representation"]);
    assert(!fs.existsSync(path.join(dir,"cell.pdf")));
    continue;
  }
  const original = execFileSync('git', ['show', sha + ':' + plate.drawable], {encoding: 'utf8'});
  paths += (original.match(/<path\b/g) || []).length;
  assert.equal(metadata.properties['preserves-vector-representation'], true);
  const pdf = fs.readFileSync(path.join(dir, metadata.images[0].filename));
  assert.equal(pdf.subarray(0, 5).toString(), '%PDF-');
}
assert.equal(features, 25);
assert.equal(paths, 30);
console.log('Immune resource audit: 12 plates, 25 local features, 30 retained vector paths and four painted cells; bilingual keys resolved.');
