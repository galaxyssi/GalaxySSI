// Declaration and source inventory audit, not native execution or acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const read = file => fs.readFileSync(path.join(root, "apps/ios", file), "utf8");
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 32_000_000});
const inventory = JSON.parse(read("ANDROID_4388_SOURCE_INVENTORY.json"));
assert.deepEqual(inventory.source, {androidPR: 4388, mergeCommit: sha});
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(s => s.split("\t"));
assert.equal(changed.length, 67); assert.equal(inventory.files.length, changed.length);
for (const [index, [status, file]] of changed.entries()) {
  const bytes = git(["show", (status === "D" ? sha + "^1" : sha) + ":" + file]);
  assert.deepEqual(inventory.files[index], {path: file, status, sha256: crypto.createHash("sha256").update(bytes).digest("hex")});
}
const pack = JSON.parse(read("GalaxySSI/Assets.xcassets/HealthAtlasCompleteStories.dataset/content.json"));
assert.deepEqual(pack.source, inventory.source);
assert.equal(pack.stories.length, 138); assert.equal(Object.keys(pack.routes).length, 313);
assert.equal(pack.stories.reduce((n, s) => n + s.chapters.length, 0), 643);
assert.equal(pack.stories.reduce((n, s) => n + s.references.length, 0), 320);
assert.equal(pack.stories.reduce((n, s) => n + s.related.length, 0), 151);
const graph = JSON.parse(git(["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"]));
const owners = new Set(graph.entries.map(e => e.id)), stories = new Map(pack.stories.map(s => [s.id, s]));
assert.equal(stories.size, 138);
const swift = read("GalaxySSI/GalaxySSIHealthAtlasFunctionCatalogue.swift");
for (const [owner, choices] of Object.entries(pack.routes)) {
  assert.ok(owners.has(owner), owner); assert.ok(choices.length > 0 && choices.length <= 6);
  assert.deepEqual(Object.keys(pack.entryPhases[owner]).sort(), [...choices].sort());
  for (const choice of choices) {
    // choicesForId also routes teaching aliases, not only each story's direct owners.
    assert.ok(stories.has(choice), owner + ":" + choice);
    assert.ok(Number.isFinite(pack.entryPhases[owner][choice]) && pack.entryPhases[owner][choice] >= 0 && pack.entryPhases[owner][choice] <= 1);
  }
}
const translations = new Map(["en", "zh-Hans"].map(locale => [locale,
  ["BodyAtlas", "AtlasFunction", "AtlasRegional", "AtlasComplete"].map(t => read("GalaxySSI/" + locale + ".lproj/" + t + ".strings")).join("\n")]));
for (const story of pack.stories) {
  for (const related of story.related) assert.ok(pack.routes[related.entryID]?.includes(related.storyID));
  for (const reference of story.references) {
    const url = new URL(reference.url);
    assert.equal(url.protocol, "https:"); assert.equal(url.username + url.password + url.port, "");
    assert.ok(swift.includes(JSON.stringify(url.hostname)), url.hostname);
  }
  const keys = [story.title, story.choiceTitle, story.scope, ...story.chapters.flatMap(c => [c.title, c.caption]), ...story.references.map(r => r.title)];
  for (const [locale, resources] of translations) {
    for (const key of keys) assert.ok(resources.includes(JSON.stringify(key) + " = "), locale + ":" + key);
  }
}
const previous = JSON.parse(read("GalaxySSI/Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json"));
const old = new Set(previous.stories.map(s => s.id)), added = pack.stories.filter(s => !old.has(s.id));
assert.equal(added.length, 24);
const artwork = read("GalaxySSI/GalaxySSIHealthAtlasFunctionArtwork.swift");
const connected = added.filter(s => artwork.includes('case "' + s.id + '":'));
assert.deepEqual(connected.map(s => s.id), added.map(s => s.id));
assert.equal(connected.length, 24);
assert.ok(swift.includes("revision: Int = 4385"), "Runtime activation still awaits full integration audit");
console.log("Verified 67 source hashes; 138 courses / 313 routes / 151 related links / bilingual keys. All 24 new dispatches connected; default activation/full integration audit remain. No native execution.");
