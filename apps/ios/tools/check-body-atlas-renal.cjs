// Static Android/source parity audit. Does not execute Swift or XCTest.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "8ecbef31cfcc6c4fb8fdf9b9aeea006cc56562d9";
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const show = (ref, file) => cp.execFileSync("git", ["show", ref + ":" + file], { cwd: root, maxBuffer: 32000000 });
const source = "apps/android/app/src/main/";
const before = JSON.parse(show(sha + "^1", source + "assets/health/body-atlas.json"));
const after = JSON.parse(show(sha, source + "assets/health/body-atlas.json"));
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasRenal.dataset/content.json")));
assert.equal(pack.schema, 1); assert.equal(pack.source.mergeCommit, sha);
const replacements = new Map(pack.entries.map((entry) => [entry.id, entry]));
const combined = { schema: before.schema,
  entries: before.entries.flatMap((entry) => [replacements.get(entry.id) ?? entry,
    ...pack.entries.filter((added) => pack.insertAfter[added.id] === entry.id)]),
  mechanisms: [...before.mechanisms, ...pack.mechanisms] };
assert.deepEqual(combined, after);
assert.equal(after.entries.length, 285); assert.equal(after.mechanisms.length, 57);
assert.equal(pack.mechanisms.length, 7);
for (const model of pack.mechanisms) {
  assert.equal(model.kind, "cell"); assert.equal(replacements.get(model.id).mechanism, model.id);
  assert.equal(model.stages.length, 4);
}
const plate = pack.plate, kotlin = show(sha, source + "java/com/galaxyssi/chat/HealthAtlasPlates.kt").toString();
const block = kotlin.slice(kotlin.indexOf("private val nephron ="), kotlin.indexOf("    val all"));
const markers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)",\s*([.\d]+)f,\s*([.\d]+)f\)/g)]
  .map((m) => ({ id: m[1], x: Number(m[2]), y: Number(m[3]) }));
assert.deepEqual(plate.markers, markers);
assert.ok(block.includes(plate.source));
const line = kotlin.split("\n").findIndex((line) => line.includes('"nephron", "glomerulus", "bowmans-capsule"'));
const routing = kotlin.split("\n").slice(line, line + 2).join("");
assert.deepEqual(plate.entryIDs, [...routing.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
const png = fs.readFileSync(path.join(assets, "HealthAtlasNephron.imageset/nephron.png"));
assert.deepEqual(png, show(sha, source + "res/drawable-nodpi/health_atlas_nephron.png"));
assert.equal(png.readUInt32BE(16) / png.readUInt32BE(20), plate.aspectRatio);
console.log("Renal resources equal Android #4330: 285 entries, 57 mechanisms, 6 markers, 8 routes, original PNG.");
