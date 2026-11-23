// Static resource composition; this does not execute Swift or XCTest.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "9036622e301ac95b6f8fe4b4364444d532286974";
const app = path.join(root, "apps/ios/GalaxySSI"), assets = path.join(app, "Assets.xcassets");
const show = (ref, file) => cp.execFileSync("git", ["show", ref + ":" + file], { cwd: root, maxBuffer: 32000000 });
const read = (file) => JSON.parse(fs.readFileSync(file));
const pack = (name) => read(path.join(assets, name + ".dataset/content.json"));
const extended = pack("HealthAtlasExtendedCells");
const reproductivePath = "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasReproductiveCells.dataset/content.json";
const reproductive = read(path.join(root, reproductivePath));
let atlas = read(path.join(app, "body-atlas/body-atlas.json"));
function revise(delta) {
  const entries = new Map(delta.entries.map((entry) => [entry.id, entry]));
  const models = new Map(delta.mechanisms.map((model) => [model.id, model]));
  const existing = new Set(atlas.mechanisms.map((model) => model.id));
  atlas = { schema: atlas.schema,
    entries: atlas.entries.flatMap((entry) => [entries.get(entry.id) ?? entry,
      ...delta.entries.filter((added) => delta.insertAfter?.[added.id] === entry.id)]),
    mechanisms: [...atlas.mechanisms.map((model) => models.get(model.id) ?? model),
      ...delta.mechanisms.filter((model) => !existing.has(model.id))] };
}
revise(reproductive);
const organs = pack("HealthAtlasOrganPlates");
atlas.entries = atlas.entries.flatMap((entry) => [{ ...entry,
  related: [...(organs.relatedAdditions[entry.id] ?? []).filter((id) => !entry.related.includes(id)), ...entry.related] },
  ...organs.entries.filter((added) => organs.insertAfter[added.id] === entry.id)]);
revise(pack("HealthAtlasRenal"));
const cells = pack("HealthAtlasCellProcesses");
atlas.entries = atlas.entries.map((entry) => ({ ...entry, mechanism: cells.entryMechanisms[entry.id] ?? entry.mechanism }));
atlas.mechanisms.push(...cells.mechanisms);
revise(pack("HealthAtlasRespiration"));
revise(extended);
assert.equal(extended.schema, 1); assert.equal(extended.source.mergeCommit, sha);
assert.equal(extended.entries.length, 52); assert.equal(extended.mechanisms.length, 52);
const android = JSON.parse(show(sha, "apps/android/app/src/main/assets/health/body-atlas.json"));
assert.deepEqual(atlas.entries, android.entries);
const sorted = (models) => [...models].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(atlas.mechanisms), sorted(android.mechanisms));
assert.equal(atlas.entries.length, 287); assert.equal(atlas.mechanisms.length, 127);
const models = new Map(atlas.mechanisms.map((model) => [model.id, model]));
const microscopic = atlas.entries.filter((entry) => ["cell", "fragment"].includes(entry.kind));
assert.equal(microscopic.length, 106);
const keys = [];
for (const entry of microscopic) {
  const model = models.get(entry.id);
  assert.equal(entry.mechanism, entry.id); assert.equal(model.kind, entry.kind);
  assert.equal(model.stages.length, 4); keys.push(model.title, ...model.stages);
}
assert.equal(new Set(keys).size, 530);
console.log("Complete composition equals Android #4337: 287 entries / 127 mechanisms; 106 exclusive microscopic owners.");
