// Static metadata composition and Android parity, not Swift/XCTest execution.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "94154bdf32590ff7909469aeac2767c521138162";
const app = path.join(root, "apps/ios/GalaxySSI"), assets = path.join(app, "Assets.xcassets");
const read = (file) => JSON.parse(fs.readFileSync(file));
const pack = (name) => read(path.join(assets, name + ".dataset/content.json"));
const reproductive = pack("HealthAtlasReproductiveCells");
assert.equal(reproductive.schema, 1); assert.equal(reproductive.source.mergeCommit, sha);
assert.equal(reproductive.entries.length, 12); assert.equal(reproductive.mechanisms.length, 15);
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
const android = JSON.parse(cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"],
  { cwd: root, maxBuffer: 32000000 }));
assert.deepEqual(atlas.entries, android.entries);
const sorted = (models) => [...models].sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(sorted(atlas.mechanisms), sorted(android.mechanisms));
assert.equal(atlas.entries.length, 287); assert.equal(atlas.mechanisms.length, 75);
for (const model of reproductive.mechanisms.filter((model) => model.kind === "cell")) {
  assert.equal(atlas.entries.find((entry) => entry.id === model.id)?.mechanism, model.id);
  assert.equal(model.stages.length, 4);
}
console.log("Actual bundled-pack composition matches Android #4336: 287 entries / 75 mechanisms, 12 owned new cell processes.");
