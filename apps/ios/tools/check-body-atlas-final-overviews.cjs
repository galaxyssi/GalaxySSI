// Static resource/source comparison; this does not execute Swift or XCTest.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict"), root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2", prefix = "apps/android/app/src/main/";
const show = (file) => cp.execFileSync("git", ["show", sha + ":" + file], { cwd: root, maxBuffer: 4_000_000 });
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSystemOverviews.dataset/content.json")));
const source = show(prefix + "java/com/galaxyssi/chat/HealthAtlasSystemPlates.kt").toString();
const graph = JSON.parse(show(prefix + "assets/health/body-atlas.json"));
const entries = new Map(graph.entries.map((entry) => [entry.id, entry]));
assert.equal(pack.extensionSource.androidPR, 4344);
assert.deepEqual(pack.finalArtworkSource, {androidPR:4362,mergeCommit:sha});
const added = pack.plates.filter((plate) => plate.drawable);
assert.equal(added.length, 4);
assert.equal(added.flatMap((plate) => plate.markers).length, 23);
const routed = pack.plates.flatMap((plate) => plate.entryIDs);
assert.equal(routed.length, 54); assert.equal(new Set(routed).size, 54);
for (const plate of added) {
  const name = plate.viewLabel.replace("health_atlas_view_system_", "");
  const start = source.indexOf("private val " + name + " =");
  const next = source.indexOf("    private val ", start + 1);
  const block = source.slice(start, next < 0 ? source.indexOf("    val all") : next);
  assert.ok(start >= 0 && block.includes('"' + plate.owner + '"'));
  assert.ok(block.includes("R.string." + plate.viewLabel));
  assert.ok(block.includes('"' + plate.source.split("/pages/")[1] + '"'));
  let markers = [...block.matchAll(/marker\("([^"]+)",\s*(\d+),\s*(\d+)(?:,\s*(\d+))?\)/g)]
    .map((m) => ({ id: m[1], x: Number(m[2]) / 420, y: Number(m[3]) / Number(m[4] ?? 560) }));
  if (plate.id === "nervous") markers = [...block.matchAll(/Marker\("([^"]+)",\s*([\d.]+)f,\s*([\d.]+)f\)/g)]
    .map(m => ({id:m[1],x:Number(m[2]),y:Number(m[3])}));
  assert.deepEqual(plate.markers, markers);
  const route = source.split("\n").find((line) => line.trim().endsWith("-> " + name));
  assert.deepEqual(plate.entryIDs, [...route.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
  assert.equal(entries.get(plate.owner).kind, "system");
  for (const marker of markers) assert.equal(entries.get(marker.id).kind, "organ");
  const directory = path.join(assets, plate.asset + ".imageset");
  if (plate.id !== "nervous") {
    assert.equal(fs.readFileSync(path.join(directory, "overview.pdf")).subarray(0, 5).toString(), "%PDF-");
    assert.equal(JSON.parse(fs.readFileSync(path.join(directory, "Contents.json"))).properties["preserves-vector-representation"], true);
  }
}
assert.deepEqual(pack.relatedAdditions.cardio, entries.get("cardio").related.slice(-3));
console.log("Android #4362 parity: 23 calibrated system markers, 54 unchanged routes and exact cardiovascular additions.");
