// Static Android/source parity, not app or XCTest execution.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "80d46ca59dd3db25e3e7d266c70f082232f4788b";
const prefix = "apps/android/app/src/main/", assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const show = (file) => cp.execFileSync("git", ["show", sha + ":" + file], { cwd: root, maxBuffer: 32000000 });
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasMusculoskeletal.dataset/content.json")));
const kotlin = show(prefix + "java/com/galaxyssi/chat/HealthAtlasMusculoskeletalPlates.kt").toString();
const graph = JSON.parse(show(prefix + "assets/health/body-atlas.json"));
const entries = new Map(graph.entries.map((entry) => [entry.id, entry]));
assert.equal(pack.schema, 1); assert.equal(pack.source.mergeCommit, sha); assert.equal(pack.plates.length, 4);
assert.deepEqual(pack.plates.map((p) => p.viewKey), ["skeletal-anterior", "skeletal-posterior", "muscle-anterior", "muscle-posterior"]);
for (const plate of pack.plates) {
  const start = kotlin.indexOf("HealthAtlasPlate(R.drawable." + plate.viewLabel);
  const next = kotlin.indexOf("HealthAtlasPlate(", start + 1);
  const block = kotlin.slice(start, next < 0 ? kotlin.indexOf("\n    )", start) : next);
  assert.ok(start >= 0 && block.includes('"' + plate.owner + '"') && block.includes('"' + plate.viewKey + '"'));
  const markers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)",\s*([.\d]+)f,\s*([.\d]+)f\)/g)]
    .map((m) => ({ id: m[1], x: Number(m[2]), y: Number(m[3]) }));
  assert.deepEqual(plate.markers, markers);
  assert.deepEqual(plate.entryIDs, [plate.owner, ...markers.map((m) => m.id)]);
  for (const marker of markers) assert.equal(entries.get(marker.id)?.kind, "organ");
  const source = plate.owner === "skeletal" ? "7-1-divisions-of-the-skeletal-system" : "11-2-naming-skeletal-muscles";
  assert.equal(plate.source, "https://openstax.org/books/anatomy-and-physiology-2e/pages/" + source);
  const png = fs.readFileSync(path.join(assets, plate.asset + ".imageset/artwork.png"));
  assert.deepEqual(png, show(prefix + "res/drawable-nodpi/" + plate.viewLabel + ".png"));
  assert.equal(png.readUInt32BE(16) / png.readUInt32BE(20), plate.aspectRatio);
}
assert.equal(pack.plates.flatMap((plate) => plate.markers).length, 28);
console.log("Android #4334 parity: 4 original PNGs, 28 visible hotspots, 4 bounded view keys and exact references.");
