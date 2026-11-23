// Static source/resource audit only; not XCTest or native app execution.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "c3b829446f44109b585b55a37a13e1d683d96919";
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets"), prefix = "apps/android/app/src/main/";
const show = (ref, file) => cp.execFileSync("git", ["show", ref + ":" + file], { cwd: root, maxBuffer: 32000000 });
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasRespiration.dataset/content.json")));
const before = JSON.parse(show(sha + "^1", prefix + "assets/health/body-atlas.json"));
const after = JSON.parse(show(sha, prefix + "assets/health/body-atlas.json"));
const revisions = new Map(pack.entries.map((entry) => [entry.id, entry]));
assert.equal(pack.schema, 1); assert.equal(pack.source.mergeCommit, sha);
assert.deepEqual({ schema: before.schema, entries: before.entries.flatMap((entry) =>
  [revisions.get(entry.id) ?? entry, ...pack.entries.filter((added) => pack.insertAfter[added.id] === entry.id)]),
  mechanisms: [...before.mechanisms, ...pack.mechanisms] }, after);
assert.equal(after.entries.length, 287); assert.equal(after.mechanisms.length, 63);
for (const mechanism of pack.mechanisms) {
  if (mechanism.reference) assert.match(mechanism.reference, /^https:\/\/pubmed\.ncbi\.nlm\.nih\.gov\/[1-9][0-9]*\/$/);
}
const plate = pack.plate, kotlin = show(sha, prefix + "java/com/galaxyssi/chat/HealthAtlasPlates.kt").toString();
const block = kotlin.slice(kotlin.indexOf("private val alveolus ="), kotlin.indexOf("    val all"));
const markers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)",\s*([.\d]+)f,\s*([.\d]+)f\)/g)]
  .map((m) => ({ id: m[1], x: Number(m[2]), y: Number(m[3]) }));
assert.deepEqual(plate.markers, markers);
const route = kotlin.split("\n").find((line) => line.trim().endsWith("-> alveolus"));
assert.deepEqual(plate.entryIDs, [...route.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
const png = fs.readFileSync(path.join(assets, "HealthAtlasAlveolus.imageset/alveolus.png"));
assert.deepEqual(png, show(sha, prefix + "res/drawable-nodpi/health_atlas_alveolus.png"));
assert.equal(png.readUInt32BE(16) / png.readUInt32BE(20), plate.aspectRatio);
console.log("Respiration matches Android #4331: 287 entries, 63 mechanisms, 3 markers/routes, original PNG.");
