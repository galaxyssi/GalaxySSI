// Static bundled-resource audit only; this does not execute Swift or XCTest.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasTissues.dataset/content.json")));
const android = JSON.parse(cp.execFileSync("git", ["show",
  "1ab5e34eb81502f725d0070c47482677ea5ce8fd:apps/android/app/src/main/assets/health/body-atlas.json"],
  { cwd: root, maxBuffer: 4_000_000 }));
assert.equal(pack.schema, 1);
assert.equal(pack.source.mergeCommit, "1ab5e34eb81502f725d0070c47482677ea5ce8fd");
assert.deepEqual(pack.entries, android.entries.filter((entry) => entry.kind === "tissue"));
assert.deepEqual(pack.mechanisms, android.mechanisms.filter((model) => model.kind === "tissue"));
assert.equal(pack.entries.length, 14); assert.equal(pack.plates.length, 14);
assert.equal(new Set(pack.entries.flatMap((entry) => entry.locatedIn)).size, 53);
assert.equal(new Set(pack.entries.flatMap((entry) => entry.related)).size, 26);
assert.equal(pack.plates.flatMap((plate) => plate.markers).length, 17);
const graph = new Map(android.entries.map((entry) => [entry.id, entry]));
for (const plate of pack.plates) {
  const entry = graph.get(plate.owner);
  assert.equal(plate.id, entry.id); assert.deepEqual(plate.entryIDs, [entry.id]);
  for (const marker of plate.markers) {
    assert.ok(entry.related.includes(marker.id)); assert.equal(graph.get(marker.id).kind, "cell");
    assert.ok(marker.x >= 0 && marker.x <= 1 && marker.y >= 0 && marker.y <= 1);
  }
  const directory = path.join(assets, plate.asset + ".imageset");
  const contents = JSON.parse(fs.readFileSync(path.join(directory, "Contents.json")));
  assert.equal(contents.properties["preserves-vector-representation"], true);
  assert.equal(fs.readFileSync(path.join(directory, "tissue.pdf")).subarray(0, 5).toString(), "%PDF-");
}
console.log("Tissue delta equals Android #4342: 14 entries/mechanisms, 53 locations, 26 cells, 14 vectors and 17 hotspots.");
