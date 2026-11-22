// Static bundled-resource/composition audit. Does not execute the app or XCTest.
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const app = "apps/ios/GalaxySSI/", assets = app + "Assets.xcassets/";
const read = (name) => fs.readFileSync(path.join(root, name));
const json = (name) => JSON.parse(read(name));
const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0) return null;
  assert.ok(process.argv[index + 1], "Missing argument for " + name);
  return process.argv[index + 1];
};
const gitRead = (ref, file) => cp.execFileSync("git", ["show", ref + ":" + file], { cwd: root, maxBuffer: 32 * 1024 * 1024 });
const baseRef = argument("--base-ref"), organRef = argument("--organ-ref"), androidRef = argument("--android-ref");
const pack = json(assets + "HealthAtlasCellProcesses.dataset/content.json");
const info = json(assets + "HealthAtlasCellProcesses.dataset/Contents.json");
assert.equal(info.data[0].filename, "content.json");
assert.equal(info.data[0].idiom, "universal");
assert.equal(info.data[0]["universal-type-identifier"], "public.json");
assert.equal(pack.schema, 1); assert.equal(pack.source.androidPR, 4326);
assert.equal(pack.mechanisms.length, 30);
assert.equal(new Set(pack.mechanisms.map((model) => model.id)).size, 30);
assert.equal(Object.keys(pack.english).length, 152);
assert.equal(Object.keys(pack.entryMechanisms).length, 30);
const chinese = new Map();
for (const line of read(app + "zh-Hans.lproj/Localizable.strings").toString().split(/\r?\n/)) {
  if (!line.startsWith('"health_atlas_')) continue;
  const match = line.match(/^("[^"\\]+") = ("(?:[^"\\]|\\.)*");$/);
  assert.ok(match, "Malformed string: " + line);
  const key = JSON.parse(match[1]);
  assert.ok(!chinese.has(key), "Duplicate translation: " + key);
  chinese.set(key, JSON.parse(match[2]));
}
for (const model of pack.mechanisms) {
  assert.match(model.id, /^cell-[a-z0-9]+(?:-[a-z0-9]+)*$/);
  assert.equal(model.kind, "cell");
  assert.equal(pack.entryMechanisms[model.id], model.id);
  assert.match(model.chapter, /^[a-z0-9-]+$/);
  assert.equal(model.stages.length, 4);
  for (const key of [model.title, ...model.stages]) {
    assert.ok(pack.english[key]?.trim(), "Missing English text: " + key);
    assert.ok(chinese.get(key)?.trim(), "Missing Chinese text: " + key);
  }
}
for (const [key, value] of Object.entries(pack.english)) {
  assert.ok(key.startsWith("health_atlas_process_") || key.startsWith("health_atlas_view_"));
  assert.ok(value && chinese.has(key), "Incomplete resource: " + key);
}
assert.deepEqual(pack.plates.map((plate) => plate.owner), ["cell-erythrocyte", "cell-neuron"]);
for (const plate of pack.plates) {
  assert.deepEqual(plate.entryIDs, [plate.owner]); assert.equal(plate.markers.length, 0);
  assert.ok(pack.english[plate.viewLabel]);
  const directory = assets + plate.asset + ".imageset/";
  const contents = json(directory + "Contents.json"), png = read(directory + contents.images[0].filename);
  assert.equal(png.subarray(1, 4).toString(), "PNG"); assert.equal(png[25], 6);
  assert.equal(plate.aspectRatio, png.readUInt32BE(16) / png.readUInt32BE(20));
  if (androidRef) {
    const original = gitRead(androidRef, "apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + plate.id + ".png");
    assert.ok(png.equals(original), "Image differs from Android: " + plate.id);
  }
}
const basePath = app + "body-atlas/body-atlas.json", organPath = assets + "HealthAtlasOrganPlates.dataset/content.json";
const base = baseRef ? JSON.parse(gitRead(baseRef, basePath)) : fs.existsSync(path.join(root, basePath)) ? json(basePath) : null;
const organ = organRef ? JSON.parse(gitRead(organRef, organPath)) : fs.existsSync(path.join(root, organPath)) ? json(organPath) : null;
if (base) {
  const entries = organ ? base.entries.flatMap((entry) => [
    { ...entry, related: [...(organ.relatedAdditions[entry.id] || []), ...entry.related] },
    ...organ.entries.filter((extra) => organ.insertAfter[extra.id] === entry.id)
  ]) : base.entries;
  const combined = { ...base, entries: entries.map((entry) => ({ ...entry, mechanism: pack.entryMechanisms[entry.id] || entry.mechanism })),
    mechanisms: [...base.mechanisms, ...pack.mechanisms] };
  assert.equal(combined.mechanisms.length, 50);
  const models = new Map(combined.mechanisms.map((model) => [model.id, model]));
  const index = new Map(combined.entries.map((entry) => [entry.id, entry]));
  for (const entry of combined.entries) {
    assert.ok(models.has(entry.mechanism));
    if (models.get(entry.mechanism).kind === "cell") assert.equal(entry.mechanism, entry.id);
    for (const id of entry.related) assert.ok(index.has(id));
  }
  for (const model of combined.mechanisms.filter((model) => model.kind === "cell")) {
    assert.equal(index.get(model.id)?.kind, "cell"); assert.equal(index.get(model.id)?.mechanism, model.id);
  }
  if (androidRef) {
    const original = JSON.parse(gitRead(androidRef, "apps/android/app/src/main/assets/health/body-atlas.json"));
    assert.deepEqual(combined, original, "Composed catalogue differs from Android #4326; include --organ-ref for full composition.");
  }
  console.log("Composed graph: " + combined.entries.length + " entries, 50 processes, 30 correctly owned cell processes" +
    (androidRef ? "; exact Android #4326 equality, including PNG blobs." : "."));
} else {
  console.log("Resource-only branch: supply --base-ref and --organ-ref for complete composition audit.");
}
console.log("iOS cell pack resource audit passed: 30 processes, 120 stages, 152 bilingual strings, 2 owner-scoped plates.");
