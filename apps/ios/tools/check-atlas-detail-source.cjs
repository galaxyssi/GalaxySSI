// Source/data/PDF inspection only; no Swift type checking, native gestures or pixels.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const {PDFDocument, PDFRawStream, decodePDFRawStream, drawSvgPath, rgb, concatTransformationMatrix} = require("pdf-lib"), xml = require("xml-js");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI");
const read = name => fs.readFileSync(path.join(app, name), "utf8");
const expanded = process.argv.includes("--expanded-4391"), revision = expanded ? 4391 : 4389;
const inventory = require("../ANDROID_" + revision + "_SOURCE_INVENTORY.json");
const sha = expanded ? "165809fc9606ac1ff6b0df6eb9bee73286b415ea" : "9508d49277cf33ab7f85e65722e7c470930fff7e";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(s => s.split("\t"));
assert.deepEqual(inventory.source, {androidPR: revision, mergeCommit: sha});
assert.equal(changed.length, inventory.files.length);
for (const [index, [status, file]] of changed.entries()) assert.deepEqual(inventory.files[index],
  {path: file, status, sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")});
const pack = JSON.parse(read("Assets.xcassets/" + (expanded ? "HealthAtlasExpandedDetailStructures" : "HealthAtlasDetailStructures") + ".dataset/content.json"));
assert.deepEqual(pack.source, inventory.source); assert.equal(pack.plates.length, expanded ? 61 : 26);
assert.equal(new Set(pack.plates.map(p => p.owner)).size, pack.plates.length);
assert.equal(new Set(pack.plates.map(p => p.id)).size, pack.plates.length);
assert.equal(pack.plates.flatMap(p => p.features).length, expanded ? 279 : 139);
assert.equal(pack.plates.flatMap(p => p.markers).length, expanded ? 52 : 3);
if (expanded) {
  const previous = JSON.parse(read("Assets.xcassets/HealthAtlasDetailStructures.dataset/content.json"));
  assert.deepEqual(pack.plates.slice(0, 26), previous.plates);
  for (const plate of previous.plates) assert(git(["show", sha + ":" + plate.drawable]).equals(git(["show", previous.source.mergeCommit + ":" + plate.drawable])));
  const directory = "apps/android/app/src/main/java/com/galaxyssi/chat/";
  const changed = git(["diff", "--name-only", "6581110ec5c048edebf63821dee839b4818fe663", sha, "--",
    directory + "HealthAtlasFunctionStory.kt", directory + "HealthAtlas*Assignment*.kt", directory + "HealthAtlasPhysiology*.kt"]);
  assert.equal(changed.toString().trim(), "", "Course assignments or numerical bindings changed; re-extract instead of reusing catalogue");
  assert(read("GalaxySSIHealthAtlasDetailStructures.swift").includes("revision: Int = 4391"));
}
const graph = JSON.parse(git(["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"]));
const ids = new Set(graph.entries.map(e => e.id)), runtime = read("GalaxySSIHealthAtlasDetailStructures.swift");
const tables = ["en", "zh-Hans"].map(locale => new Map(["AtlasDetail", ...(expanded ? ["AtlasExpanded"] : [])].flatMap(table =>
  [...read(locale + ".lproj/" + table + ".strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]))));
assert.equal(tables[0].size, expanded ? 678 : 331); assert.deepEqual([...tables[0].keys()], [...tables[1].keys()]);
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
    if (expanded) {
      assert(plate.features.length >= 3); assert(plate.selectorLabel);
      assert.notEqual(tables[0].get(plate.selectorLabel), tables[1].get(plate.selectorLabel));
    }
    for (const p of points) assert(Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1);
    for (const key of [plate.viewLabel, plate.selectorLabel, ...plate.features.flatMap(f => [f.title, f.explanation])].filter(Boolean)) {
      for (const table of tables) assert(table.get(key), key);
    }
    const raw = git(["show", sha + ":" + plate.drawable]).toString();
    const vector = xml.xml2js(raw, {compact: true}).vector;
    const items = vector.group ? require("./body-atlas-ordered-vector.cjs")(raw, {affine: true, clips: true}) : vector.path;
    paths += items.length;
    const folder = path.join(app, "Assets.xcassets", plate.asset + ".imageset");
    const metadata = JSON.parse(fs.readFileSync(path.join(folder, "Contents.json")));
    assert(metadata.properties["preserves-vector-representation"]);
    const pdf = await PDFDocument.load(fs.readFileSync(path.join(folder, "art.pdf")));
    assert.equal(pdf.getPageCount(), 1); assert.deepEqual(pdf.getPages()[0].getSize(), {width: 360, height: 280});
    const expected = items.flatMap(item => [
      ...(item._atlasClips || []).flatMap(clip => require("./body-atlas-vector-clips.cjs")(clip, 280)),
      ...(item._atlasTransform ? [concatTransformationMatrix(...require("./body-atlas-vector-transform.cjs").pdf(item._atlasTransform, 280))] :
        item._atlasMirrorX ? [concatTransformationMatrix(-1, 0, 0, 1, 360, 0)] : []),
      ...drawSvgPath(require("./body-atlas-quadratic-path.cjs")(item._attributes["android:pathData"]), {x: 0, y: 280, color: rgb(0, 0, 0)})]
      .filter(op => ["m", "l", "c", "h", "cm"].includes(op.name)).map(op => op.toString()));
    const operators = pdf.context.enumerateIndirectObjects().filter(([, obj]) => obj instanceof PDFRawStream)
      .flatMap(([, obj]) => Buffer.from(decodePDFRawStream(obj).decode()).toString().split(/\r?\n/))
      .filter(line => /(?:^| )(?:m|l|c|h|cm)$/.test(line));
    assert.deepEqual(operators, expected, "PDF path mismatch: " + plate.asset);
    assert.equal(plate.aspectRatio, 360 / 280);
  }
  assert.equal(paths, expanded ? 1152 : 408);
  const atlas = read("GalaxySSIHealthAtlas.swift"), artwork = read("GalaxySSIHealthAtlasArtwork.swift");
  for (const token of ["let context = contextViews(for: id)", "DetailStructurePack.plate(for: id)", "return [detail] + context.map",
    '"anatomy-locator-"', '"health_atlas_locator_view"', 'table: "AtlasDetail"', "DetailStructurePack.sources.contains(source)"])
    assert(atlas.includes(token), token);
  for (const token of [".fullScreenCover(isPresented: $fullscreen)", "fullscreenLayers.toggle()", "fullscreenZoom = 1; fullscreenReset += 1",
    "canvas(art, full: true)", '"atlas-fullscreen-labels"', '"atlas-fullscreen-reset"', "depth < 32", "case .feature(let feature)"])
    assert(artwork.includes(token), token);
  for (const file of ["GalaxySSIHealthAtlasArtwork.swift", "GalaxySSIHealthAtlasLabeledArtwork.swift"]) {
    const source = read(file);
    assert(source.includes("override func touchesShouldCancel(in view: UIView) -> Bool"));
    assert(source.includes("view is UIButton || super.touchesShouldCancel(in: view)"));
  }
  console.log(`Android #${revision}: ${changed.length} source hashes, ${pack.plates.length} views / ${pack.plates.flatMap(p => p.features).length} features / ${pack.plates.flatMap(p => p.markers).length} links / ${paths} vector paths / ${tables[0].size} bilingual pairs. Native fullscreen/navigation/gesture/pixel acceptance remains outstanding.`);
})().catch(error => {console.error(error); process.exitCode = 1;});
