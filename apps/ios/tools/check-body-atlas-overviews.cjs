// Static Android resource comparison; not native execution.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "96b3f950e85c839173e473ddb2435fe88f1acb75";
const prefix = "apps/android/app/src/main/", assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const show = (file) => cp.execFileSync("git", ["show", sha + ":" + file], { cwd: root, maxBuffer: 32000000 });
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSystemOverviews.dataset/content.json")));
const kotlin = show(prefix + "java/com/galaxyssi/chat/HealthAtlasSystemPlates.kt").toString();
const graph = JSON.parse(show(prefix + "assets/health/body-atlas.json"));
const entries = new Map(graph.entries.map((entry) => [entry.id, entry]));
assert.equal(pack.schema, 1); assert.equal(pack.source.mergeCommit, "9401329c48ea31a4c3e06e7e48b1e73ca5433eff");
assert.equal(pack.artworkSource.androidPR, 4357); assert.equal(pack.artworkSource.mergeCommit, sha); assert.equal(pack.plates.length, 10);
const original = pack.plates.filter((plate) => !plate.drawable);
assert.equal(original.length, 6);
const seen = new Set();
for (const plate of original) {
  const start = kotlin.indexOf("private val " + plate.id + " =");
  const next = kotlin.indexOf("    private val ", start + 1);
  const block = kotlin.slice(start, next < 0 ? kotlin.indexOf("    val all") : next);
  assert.ok(start >= 0 && block.includes('"' + plate.owner + '"'));
  assert.ok(block.includes("R.string." + plate.viewLabel));
  assert.ok(block.includes('"' + plate.source.split("/pages/")[1] + '"'));
  const markers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)",\s*([.\d]+)f,\s*([.\d]+)f\)/g)]
    .map((m) => ({ id: m[1], x: Number(m[2]), y: Number(m[3]) }));
  assert.deepEqual(plate.markers, markers);
  const lines = kotlin.split("\n"), index = lines.findIndex((line) => line.trim().endsWith("-> " + plate.id));
  let route = lines[index];
  if (plate.id === "skin") route = lines[index - 1] + route;
  assert.deepEqual(plate.entryIDs, [...route.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
  for (const id of plate.entryIDs) {
    assert.ok(!seen.has(id)); seen.add(id);
    assert.ok(["system", "organ"].includes(entries.get(id)?.kind));
  }
  const png = fs.readFileSync(path.join(assets, plate.asset + ".imageset/overview.png"));
  assert.deepEqual(png, show(prefix + "res/drawable-nodpi/health_atlas_system_" + plate.id + ".png"));
  assert.equal(png.readUInt32BE(16) / png.readUInt32BE(20), plate.aspectRatio);
}
assert.equal(seen.size, 32);
for (const dedicated of ["lungs", "trachea", "liver", "gallbladder", "pancreas", "cell-neuron"]) assert.ok(!seen.has(dedicated));
assert.equal(original.flatMap((p) => p.markers).length, 30);
console.log("Android #4357 visual parity / #4332 routing: 6 original PNGs, 32 non-cell routes, 30 calibrated markers, dedicated-organ precedence retained.");
