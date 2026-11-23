// Static source/resource comparison, not app or XCTest execution.
const fs = require("node:fs");
const cp = require("node:child_process");
const path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSystemPlates.dataset/content.json")));
const sha = "dd6e7c26e3d89736ee65a05dab45223c0db2538e";
const android = "apps/android/app/src/main/";
function show(file) { return cp.execFileSync("git", ["show", sha + ":" + file], { cwd: root, maxBuffer: 32000000 }); }
const kotlin = show(android + "java/com/galaxyssi/chat/HealthAtlasPlates.kt").toString();
const chinese = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/zh-Hans.lproj/Localizable.strings"), "utf8");
assert.equal(pack.schema, 1); assert.equal(pack.source.mergeCommit, sha);
assert.equal(pack.plates.length, 3); assert.equal(Object.keys(pack.english).length, 4);
const routes = new Map();
for (const plate of pack.plates) {
  const start = kotlin.indexOf("private val " + plate.id + " = HealthAtlasPlate(");
  const end = kotlin.indexOf("\n    private val ", start + 1);
  const block = kotlin.slice(start, end < 0 ? kotlin.indexOf("\n    val all", start) : end);
  assert.ok(start >= 0 && block.includes(plate.source));
  assert.ok(block.includes('"' + plate.owner + '"'));
  assert.ok(block.includes("R.string." + plate.viewLabel));
  const markers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)",\s*([.\d]+)f,\s*([.\d]+)f\)/g)]
    .map((m) => ({ id: m[1], x: Number(m[2]), y: Number(m[3]) }));
  assert.deepEqual(plate.markers, markers);
  const line = kotlin.split("\n").find((line) => line.trim().endsWith("-> " + plate.id));
  assert.ok(line);
  assert.deepEqual(plate.entryIDs, [...line.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
  for (const id of plate.entryIDs) { assert.ok(!routes.has(id)); routes.set(id, plate.id); }
  const png = fs.readFileSync(path.join(assets, plate.asset + ".imageset", plate.id + ".png"));
  assert.deepEqual(png, show(android + "res/drawable-nodpi/health_atlas_" + plate.id + ".png"));
  assert.equal(png.readUInt32BE(16) / png.readUInt32BE(20), plate.aspectRatio);
  assert.equal(png[25], 6); // RGBA PNG; bitmap alpha inspected separately.
  const url = new URL(plate.source);
  assert.equal(url.protocol, "https:"); assert.equal(url.hostname, "openstax.org");
  assert.ok(chinese.includes('"' + plate.viewLabel + '" = '));
}
assert.equal(routes.get("ureters"), "urinary"); assert.ok(!routes.has("kidneys"));
assert.equal(routes.get("pancreatic-duct"), "pancreas");
for (const id of ["pancreatic-islets", "pancreatic-acini", "cell-pancreatic-beta-cell", "cell-pancreatic-acinar-cell"]) {
  assert.ok(!routes.has(id));
}
assert.ok(chinese.includes('"health_atlas_plate_source" = '));
console.log("System plates match Android #4328: 3 original PNGs, 13 markers, 14 explicit routes and 3 references.");
