// Metadata/resource source audit only; not native view or navigation execution.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict"), cp = require("node:child_process");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI"), assets = path.join(app, "Assets.xcassets");
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasRegionalStructures.dataset/content.json")));
assert.deepEqual(pack.source, {androidPR: 4385, mergeCommit: "a81aa85a1c81e41ff19a032eabea1eddcd2371dc"});
assert.equal(pack.schema, 1); assert.equal(pack.plates.length, 73);
assert.equal(new Set(pack.plates.map(p => p.id)).size, 73); assert.equal(new Set(pack.plates.map(p => p.owner)).size, 72);
assert.equal(pack.plates.flatMap(p => p.features).length, 252); assert.equal(pack.plates.flatMap(p => p.markers).length, 36);
const graph = JSON.parse(cp.execFileSync("git", ["show", pack.source.mergeCommit + ":apps/android/app/src/main/assets/health/body-atlas.json"], {cwd: root, encoding: "utf8", maxBuffer: 16_000_000}));
const ids = new Set(graph.entries.map(e => e.id));
const tables = language => {
  const values = new Map();
  for (const file of ["BodyAtlas", "AtlasFunction", "AtlasRegional"]) {
    for (const line of fs.readFileSync(path.join(app, language + ".lproj/" + file + ".strings"), "utf8").split(/\r?\n/)) {
      const match = line.match(/^"([^"]+)" = (".*");$/); if (match) values.set(match[1], JSON.parse(match[2]));
    }
  }
  return values;
};
const languages = [tables("en"), tables("zh-Hans")];
for (const p of pack.plates) {
  assert(ids.has(p.owner)); assert.equal(p.id, p.viewKey); assert(p.id.length > 0);
  assert.deepEqual(p.entryIDs, [p.owner, ...p.markers.map(m => m.id)]); assert.equal(p.aspectRatio, 360 / 280);
  assert.equal(new Set([...p.markers.map(m => m.id), ...p.features.map(f => f.marker.id)]).size, p.markers.length + p.features.length);
  for (const marker of [...p.markers, ...p.features.map(f => f.marker)]) assert(Number.isFinite(marker.x) && Number.isFinite(marker.y) && marker.x >= 0 && marker.x <= 1 && marker.y >= 0 && marker.y <= 1);
  for (const marker of p.markers) assert(ids.has(marker.id));
  for (const feature of p.features) assert(!ids.has(feature.marker.id));
  for (const key of [p.viewLabel, p.selectorLabel, ...p.features.flatMap(f => [f.title, f.explanation])].filter(Boolean)) {
    assert(key.startsWith("health_atlas_")); for (const language of languages) assert(language.get(key), key);
  }
  const source = new URL(p.source); assert.equal(source.protocol, "https:"); assert(!source.username && !source.password && !source.port);
  const metadata = JSON.parse(fs.readFileSync(path.join(assets, p.asset + ".imageset/Contents.json")));
  assert(metadata.properties["preserves-vector-representation"]);
  for (const image of metadata.images) if (image.filename) assert(fs.statSync(path.join(assets, p.asset + ".imageset", image.filename)).size > 0);
}
const tenocyte = pack.plates.filter(p => p.owner === "cell-tenocyte");
assert.deepEqual(tenocyte.map(p => p.viewKey), ["atlas-detail-cell-tenocyte", "tenocyte-tendon-longitudinal"]);
assert.equal(tenocyte[1].asset, "HealthAtlasRegionalTenocyteTendonMatrixLongitudinal");
const pore = pack.plates.find(p => p.owner === "taste-buds").features.find(f => f.marker.id === "taste-pore").marker;
assert(Math.abs(pore.x - 183 / 360) < 1e-7 && Math.abs(pore.y - 70 / 280) < 1e-7);
for (const [owner, asset] of [["cell-microglia", "MicrogliaPlate"], ["cell-ependymal-cell", "EpendymalPlate"], ["ribs", "RibsAttachmentsPlate"]]) assert.equal(pack.plates.find(p => p.owner === owner).asset, "HealthAtlasRegional" + asset);
assert.equal(pack.plates.filter(p => p.asset.startsWith("HealthAtlasRegional")).length, 22);
if (process.argv.includes("--reextract")) cp.execFileSync(process.execPath, [path.join(__dirname, "import-body-atlas-function-structures.cjs"), "--regional", "--check"], {cwd: root, stdio: "inherit"});
console.log("Android #4385 structures: 73 unique view identities / 72 owners / 252 annotations / 36 links, bilingual keys, resource availability, revised plates, taste-pore correction and two tenocyte views. Runtime integration pending; no native execution.");
