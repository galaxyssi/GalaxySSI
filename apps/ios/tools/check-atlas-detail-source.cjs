// Source/data/PDF inspection only; no Swift type checking, native gestures or pixels.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const {PDFDocument} = require("pdf-lib"), xml = require("xml-js");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI");
const read = name => fs.readFileSync(path.join(app, name), "utf8");
const inventory = require("../ANDROID_4389_SOURCE_INVENTORY.json"), sha = "9508d49277cf33ab7f85e65722e7c470930fff7e";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(s => s.split("\t"));
assert.deepEqual(inventory.source, {androidPR: 4389, mergeCommit: sha});
assert.equal(changed.length, inventory.files.length);
for (const [index, [status, file]] of changed.entries()) assert.deepEqual(inventory.files[index],
  {path: file, status, sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")});
const pack = JSON.parse(read("Assets.xcassets/HealthAtlasDetailStructures.dataset/content.json"));
assert.deepEqual(pack.source, inventory.source); assert.equal(pack.plates.length, 26);
assert.equal(new Set(pack.plates.map(p => p.owner)).size, 26);
assert.equal(new Set(pack.plates.map(p => p.id)).size, 26);
assert.equal(pack.plates.flatMap(p => p.features).length, 139); assert.equal(pack.plates.flatMap(p => p.markers).length, 3);
const graph = JSON.parse(git(["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"]));
const ids = new Set(graph.entries.map(e => e.id)), runtime = read("GalaxySSIHealthAtlasDetailStructures.swift");
const tables = ["en", "zh-Hans"].map(locale => new Map([...read(locale + ".lproj/AtlasDetail.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])])));
assert.equal(tables[0].size, 331); assert.deepEqual([...tables[0].keys()], [...tables[1].keys()]);
(async () => {
  let paths = 0;
  for (const plate of pack.plates) {
    assert(ids.has(plate.owner)); assert.equal(plate.id, plate.viewKey);
    assert.deepEqual(plate.entryIDs, [plate.owner, ...plate.markers.map(m => m.id)]);
    assert(runtime.includes(JSON.stringify(plate.owner))); assert(runtime.includes(JSON.stringify(plate.source)));
    for (const marker of plate.markers) assert(ids.has(marker.id));
    for (const feature of plate.features) assert(!ids.has(feature.marker.id));
    const points = [...plate.markers, ...plate.features.map(f => f.marker)];
    assert.equal(new Set(points.map(p => p.id)).size, points.length);
    for (const p of points) assert(Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1);
    for (const key of [plate.viewLabel, plate.selectorLabel, ...plate.features.flatMap(f => [f.title, f.explanation])].filter(Boolean)) {
      for (const table of tables) assert(table.get(key), key);
    }
    const vector = xml.xml2js(git(["show", sha + ":" + plate.drawable]).toString(), {compact: true}).vector;
    paths += vector.path.length;
    const folder = path.join(app, "Assets.xcassets", plate.asset + ".imageset");
    const metadata = JSON.parse(fs.readFileSync(path.join(folder, "Contents.json")));
    assert(metadata.properties["preserves-vector-representation"]);
    const pdf = await PDFDocument.load(fs.readFileSync(path.join(folder, "art.pdf")));
    assert.equal(pdf.getPageCount(), 1); assert.deepEqual(pdf.getPages()[0].getSize(), {width: 360, height: 280});
    assert.equal(plate.aspectRatio, 360 / 280);
  }
  assert.equal(paths, 408);
  const atlas = read("GalaxySSIHealthAtlas.swift"), artwork = read("GalaxySSIHealthAtlasArtwork.swift");
  for (const token of ["let context = contextViews(for: id)", "DetailStructurePack.plate(for: id)", "return [detail] + context.map",
    '"anatomy-locator-"', '"health_atlas_locator_view"', 'table: "AtlasDetail"', "DetailStructurePack.sources.contains(source)"])
    assert(atlas.includes(token), token);
  for (const token of [".fullScreenCover(isPresented: $fullscreen)", "fullscreenLayers.toggle()", "fullscreenZoom = 1; fullscreenReset += 1",
    "canvas(art, full: true)", '"atlas-fullscreen-labels"', '"atlas-fullscreen-reset"', "depth < 32", "case .feature(let feature)"])
    assert(artwork.includes(token), token);
  console.log(`Android #4389: ${changed.length} source hashes, 26 views / 139 features / 3 links / 408 vector paths / 331 bilingual pairs. Native fullscreen/navigation/gesture/pixel acceptance remains outstanding.`);
})().catch(error => {console.error(error); process.exitCode = 1;});
