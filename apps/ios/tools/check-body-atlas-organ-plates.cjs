// Static resource/composition audit, not app execution or XCTest.
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const app = "apps/ios/GalaxySSI/";
const assets = app + "Assets.xcassets/";
const read = (file) => fs.readFileSync(path.join(root, file));
const json = (file) => JSON.parse(read(file));
const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0) return null;
  assert.ok(process.argv[index + 1], "Missing argument for " + name);
  return process.argv[index + 1];
};
const gitRead = (ref, file) => cp.execFileSync("git", ["show", ref + ":" + file], { cwd: root, maxBuffer: 32 * 1024 * 1024 });
const baseRef = argument("--base-ref"), androidRef = argument("--android-ref");
const pack = json(assets + "HealthAtlasOrganPlates.dataset/content.json");
const contents = json(assets + "HealthAtlasOrganPlates.dataset/Contents.json");
assert.equal(contents.data[0].filename, "content.json");
assert.equal(contents.data[0].idiom, "universal");
assert.equal(contents.data[0]["universal-type-identifier"], "public.json");
assert.equal(pack.schema, 1);
assert.equal(pack.source.androidPR, 4323);
assert.deepEqual(pack.entries.map((entry) => entry.id), ["renal-cortex", "renal-medulla", "renal-pelvis"]);
assert.equal(pack.plates.length, 7);
assert.equal(Object.keys(pack.english).length, 17);
assert.equal(new Set(pack.plates.flatMap((plate) => plate.entryIDs)).size, pack.plates.flatMap((plate) => plate.entryIDs).length);
for (const plate of pack.plates) {
  assert.ok(Number.isFinite(plate.aspectRatio) && plate.aspectRatio > 0);
  assert.ok(pack.english[plate.viewLabel]);
  for (const marker of plate.markers) {
    assert.ok(Number.isFinite(marker.x) && marker.x >= 0 && marker.x <= 1);
    assert.ok(Number.isFinite(marker.y) && marker.y >= 0 && marker.y <= 1);
  }
}
const chinese = new Map();
for (const line of read(app + "zh-Hans.lproj/Localizable.strings").toString().split(/\r?\n/)) {
  if (!line.startsWith('"health_atlas_')) continue;
  const match = line.match(/^("[^"\\]+") = ("(?:[^"\\]|\\.)*");$/);
  assert.ok(match, "Malformed atlas string: " + line);
  const key = JSON.parse(match[1]);
  assert.ok(!chinese.has(key), "Duplicate atlas translation: " + key);
  chinese.set(key, JSON.parse(match[2]));
}
for (const [key, english] of Object.entries(pack.english)) {
  assert.ok(chinese.has(key), "Missing Chinese translation: " + key);
  const formats = (text) => (text.match(/%(?:\d+\$)?(?:lld|@)/g) || []).sort();
  assert.deepEqual(formats(english), formats(chinese.get(key)), key);
}
for (const name of ["Brain", "Lungs", "Liver", "Kidney"]) {
  const directory = assets + "HealthAtlas" + name + ".imageset/";
  const info = json(directory + "Contents.json");
  const png = read(directory + info.images[0].filename);
  assert.equal(png.subarray(1, 4).toString(), "PNG");
  assert.equal(png.readUInt32BE(16), 1254); assert.equal(png.readUInt32BE(20), 1254);
  assert.equal(png[25], 6, "Transparent RGBA image expected: " + name);
  if (androidRef) {
    const original = gitRead(androidRef, "apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + name.toLowerCase() + ".png");
    assert.ok(png.equals(original), "Android image blob changed: " + name);
  }
}
const baseFile = app + "body-atlas/body-atlas.json";
const base = baseRef ? JSON.parse(gitRead(baseRef, baseFile)) : fs.existsSync(path.join(root, baseFile)) ? json(baseFile) : null;
if (base) {
  const combined = { ...base, entries: base.entries.flatMap((entry) => [
    { ...entry, related: [...(pack.relatedAdditions[entry.id] || []), ...entry.related] },
    ...pack.entries.filter((extra) => pack.insertAfter[extra.id] === entry.id)
  ]) };
  const ids = new Set(combined.entries.map((entry) => entry.id));
  assert.equal(ids.size, 281);
  for (const [kind, count] of Object.entries({ system: 14, organ: 161, cell: 105, fragment: 1 })) {
    assert.equal(combined.entries.filter((entry) => entry.kind === kind).length, count);
  }
  for (const entry of combined.entries) {
    for (const id of entry.related) assert.ok(ids.has(id), "Unresolved relationship: " + id);
  }
  for (const plate of pack.plates) {
    for (const id of plate.entryIDs) assert.ok(id === "" || ids.has(id));
    for (const marker of plate.markers) assert.ok(ids.has(marker.id));
    assert.ok(plate.owner == null || ids.has(plate.owner));
  }
  if (androidRef) {
    const original = JSON.parse(gitRead(androidRef, "apps/android/app/src/main/assets/health/body-atlas.json"));
    assert.deepEqual(combined, original, "Composed iOS catalogue differs from Android #4323");
  }
  console.log("Composed catalogue: 281 entries, graph and markers resolved" + (androidRef ? "; exact Android #4323 parity and PNG blob equality." : "."));
} else {
  console.log("Resource-only branch: atlas foundation is not present; use --base-ref for composition audit.");
}
console.log("iOS organ-plate resources valid: 4 transparent images, 7 plate definitions, 3 entries, 17 bilingual strings.");
