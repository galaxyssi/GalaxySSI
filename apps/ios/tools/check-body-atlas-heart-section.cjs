// Static Android/iOS resource comparison, not Swift or XCTest execution.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict"), root = path.resolve(__dirname, "../../..");
const assetRoot = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const read = (ref) => JSON.parse(cp.execFileSync("git", ["show",
  ref + ":apps/android/app/src/main/assets/health/body-atlas.json"], { cwd: root, maxBuffer: 4_000_000 }));
const current = read("fcd784640f7e01f12767fdedfb4cc75be09f9d74"), previous = read("fcd78464^1");
const pack = JSON.parse(fs.readFileSync(path.join(assetRoot, "HealthAtlasHeartSectionPack.dataset/content.json")));
const changed = (field) => current[field].filter((entry) =>
  JSON.stringify(entry) !== JSON.stringify(previous[field].find((old) => old.id === entry.id)));
assert.equal(pack.schema, 1);
assert.deepEqual(pack.entries, changed("entries"));
assert.deepEqual(pack.mechanisms, changed("mechanisms"));
assert.equal(pack.entries.length, 17); assert.equal(pack.mechanisms.length, 11);
assert.equal(pack.entries.filter((entry) => !previous.entries.some((old) => old.id === entry.id)).length, 10);
const cardiacTissue = pack.entries.find((entry) => entry.id === "tissue-cardiac-muscle");
const cardiomyocyte = pack.entries.find((entry) => entry.id === "cell-cardiomyocyte");
for (const id of ["left-atrium", "right-atrium", "left-ventricle", "right-ventricle"]) {
  assert.ok(cardiacTissue.locatedIn.includes(id)); assert.ok(cardiomyocyte.related.includes(id));
}
const image = path.join(assetRoot, "HealthAtlasHeartSection.imageset");
assert.equal(fs.readFileSync(path.join(image, "heart.png")).subarray(1, 4).toString(), "PNG");
const metadata = JSON.parse(fs.readFileSync(path.join(image, "Contents.json")));
assert(metadata.images.some(i => i.filename === "heart.png"));
assert(!metadata.properties?.["preserves-vector-representation"]);
assert(!fs.existsSync(path.join(image, "heart.pdf")));
console.log("Heart delta matches Android #4343: 10 new structures, 11 mechanisms and exact tissue/cell links.");
