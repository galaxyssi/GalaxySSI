// Static bundled-resource audit; this does not execute the app or XCTest.
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../GalaxySSI");
const atlas = JSON.parse(fs.readFileSync(path.join(root, "body-atlas/body-atlas.json"), "utf8"));
assert.equal(atlas.schema, 1);
assert.equal(atlas.entries.length, 278);
assert.equal(atlas.mechanisms.length, 20);
const entries = new Map(atlas.entries.map((entry) => [entry.id, entry]));
const models = new Map(atlas.mechanisms.map((model) => [model.id, model]));
assert.equal(entries.size, 278);
assert.equal(models.size, 20);
for (const [kind, count] of Object.entries({ system: 14, organ: 158, cell: 105, fragment: 1 })) {
  assert.equal(atlas.entries.filter((entry) => entry.kind === kind).length, count);
}
const keys = [];
for (const entry of atlas.entries) {
  assert.match(entry.id, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
  assert.ok(entry.systems.length);
  for (const id of entry.systems) assert.equal(entries.get(id)?.kind, "system");
  for (const id of entry.related) { assert.ok(entries.has(id)); assert.notEqual(id, entry.id); }
  assert.ok(models.has(entry.mechanism));
  keys.push(entry.name, entry.description, entry.aliases);
}
for (const model of atlas.mechanisms) {
  assert.equal(model.stages.length, 4);
  assert.match(model.chapter, /^[a-z0-9-]+$/);
  keys.push(model.title, ...model.stages);
}
const tables = [];
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map();
  const lines = fs.readFileSync(path.join(root, locale + ".lproj/BodyAtlas.strings"), "utf8").split(/\r?\n/);
  for (const line of lines) {
    if (!line || line.startsWith("/*")) continue;
    const match = line.match(/^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$/);
    assert.ok(match, "Malformed strings line: " + line);
    const key = JSON.parse(match[1]), value = JSON.parse(match[2]);
    assert.ok(!table.has(key), "Duplicate key: " + key);
    assert.ok(!value.startsWith('"'), "Android quote delimiters leaked: " + key);
    assert.ok(!/%(?:\d+\$)?[sd]/.test(value), "Android format specifier leaked: " + key);
    table.set(key, value);
  }
  for (const key of keys) assert.ok(table.has(key), "Missing translation: " + key);
  tables.push(table);
}
assert.deepEqual([...tables[0].keys()].sort(), [...tables[1].keys()].sort());
for (const [key, english] of tables[0]) {
  const formats = (value) => (value.match(/%(?:\d+\$)?(?:lld|@)/g) || []).sort();
  assert.deepEqual(formats(english), formats(tables[1].get(key)), "Placeholder mismatch: " + key);
}
for (const name of ["HealthAtlasBody", "HealthAtlasHeart", "HealthAtlasBetaCell"]) {
  const directory = path.join(root, "Assets.xcassets", name + ".imageset");
  const contents = JSON.parse(fs.readFileSync(path.join(directory, "Contents.json"), "utf8"));
  for (const image of contents.images) {
    const png = fs.readFileSync(path.join(directory, image.filename));
    assert.equal(png.subarray(1, 4).toString(), "PNG");
    assert.ok(png.readUInt32BE(16) > 1000 && png.readUInt32BE(20) > 1000);
  }
}
console.log("iOS atlas resource audit passed: 278 entries, 20 processes, 2 x " + tables[0].size + " strings, 3 PNG assets.");
