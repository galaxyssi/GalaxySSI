// Current runtime source/data wiring audit, not execution of Swift, navigation or pixels.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI"), assets = path.join(app, "Assets.xcassets");
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const data = name => JSON.parse(fs.readFileSync(path.join(assets, name + ".dataset/content.json")));
const catalogue = data("HealthAtlasRegionalStories"), baseline = data("HealthAtlasFunctionStories"), structures = data("HealthAtlasRegionalStructures");
assert.deepEqual(catalogue.source, {androidPR: 4385, mergeCommit: "a81aa85a1c81e41ff19a032eabea1eddcd2371dc"});
assert.equal(catalogue.stories.length, 114); assert.equal(catalogue.stories.flatMap(s => s.chapters).length, 544);
assert.equal(catalogue.stories.flatMap(s => s.references).length, 261); assert.equal(Object.keys(catalogue.routes).length, 289);
const rendering = local("FunctionArtwork"), swift = local("FunctionCatalogue"), atlas = local("");
const ids = key => [...rendering.match(new RegExp("static let " + key + ": Set<String> = \\[([^\\]]+)\\]"))[1].matchAll(/"([^"]+)"/g)].map(m => m[1]);
const oldIDs = ids("baseline"), newIDs = ids("regional"), all = [...oldIDs, ...newIDs];
assert.equal(oldIDs.length, 101); assert.equal(newIDs.length, 13); assert.equal(new Set(all).size, 114);
assert.deepEqual(new Set(oldIDs), new Set(baseline.stories.map(s => s.id)));
assert.deepEqual(new Set(all), new Set(catalogue.stories.map(s => s.id)));
assert(rendering.includes("static let implemented = baseline.union(regional)"));
const cases = [...rendering.matchAll(/case ((?:"[A-Z_]+"(?:,\s*)?)+):/g)].flatMap(m => [...m[1].matchAll(/"([A-Z_]+)"/g)].map(s => s[1]));
assert.equal(cases.length, 114); assert.deepEqual(new Set(cases), new Set(all));
const native = {ANKLE_MORTISE: "Ankle", VULVAR_PROTECTIVE_FOLDS: "Vulvar", ACCESSORY_GLAND_ROUTING: "AccessoryGland",
  UTEROCERVICAL_CONTINUITY: "Uterocervical", PENILE_URINARY_ROUTE: "PenileUrinary", SCROTAL_HEAT_EXCHANGE: "ScrotalHeat",
  SKULL_PROTECTION: "Skull", VERTEBRAL_MOTION: "Vertebral", CLITORAL_SENSORY_PATH: "ClitoralSensory",
  VESTIBULAR_GLAND_SECRETION: "VestibularGland", TENOCYTE_TENDON_MATRIX: "TenocyteTendon",
  PECTORAL_HORIZONTAL_ADDUCTION: "Pectoral", LATISSIMUS_EXTENSION_ADDUCTION: "Latissimus"};
for (const [id, name] of Object.entries(native)) {
  assert(rendering.includes('case "' + id + '": GalaxySSIHealthAtlas' + name + 'View(story: story, phase: phase, language: language)'));
  assert(local(name + "View").includes("story.chapter(phase), story.fraction(phase)"));
}
for (const token of ["revision: Int = 4385", 'revision == 4384 ? "HealthAtlasFunctionStories" : "HealthAtlasRegionalStories"', "value.source.androidPR == revision", "source.androidPR == 4385", catalogue.source.mergeCommit, "stories.count == 114", "== 544", "routes.count == 289", "== 261", "baseline || regional"]) assert(swift.includes(token), token);
const allowedHosts = new Set([...swift.slice(swift.indexOf("let hosts: Set<String>")).matchAll(/"([a-z0-9.-]+)"/g)].map(m => m[1]));
let links = 0;
for (const story of catalogue.stories) {
  for (const ref of story.references) { const url = new URL(ref.url); assert.equal(url.protocol, "https:"); assert(allowedHosts.has(url.hostname), url.hostname); assert(!url.username && !url.password && !url.port); }
  for (const related of story.related) { assert(catalogue.routes[related.entryID]?.includes(related.storyID)); links++; }
}
for (const [owner, choices] of Object.entries(catalogue.routes)) {
  assert.deepEqual(new Set(Object.keys(catalogue.entryPhases[owner])), new Set(choices));
  for (const phase of Object.values(catalogue.entryPhases[owner])) assert(Number.isFinite(phase) && phase >= 0 && phase <= 1);
}
assert.deepEqual(catalogue.routes.tibia, ["KNEE_ARTICULATION", "ANKLE_MORTISE"]);
assert(catalogue.stories.find(s => s.id === "SCAPULAR_ROTATION").owners.includes("clavicle"));
const pack = local("RegionalStructures");
assert.deepEqual(JSON.parse(pack.match(/static let owners = (\[[^\n]+\])/)[1]), structures.plates.map(p => p.owner));
for (const token of ['NSDataAsset(name: "HealthAtlasRegionalStructures"', "source.androidPR == 4385", catalogue.source.mergeCommit,
  "plates.count == 73", "== 252", "== 36", "plate.id == plate.viewKey", "pack.plates.filter { $0.owner == id }", "static let sources = FunctionStructurePack.sources.union"]) assert(pack.includes(token), token);
const oldSources = local("FunctionStructures"), sourceURLs = new Set([...pack.matchAll(/"(https:[^"]+)"/g), ...oldSources.matchAll(/"(https:[^"]+)"/g)].map(m => m[1]));
for (const plate of structures.plates) assert(sourceURLs.has(plate.source));
assert(atlas.includes("if let pack = try RegionalStructurePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }"));
assert(atlas.includes('if id == "cell-tenocyte" {\n      let views = RegionalStructurePack.views(for: id)'.replace(/\n/g, "\r\n")) || atlas.includes('if id == "cell-tenocyte" {\n      let views = RegionalStructurePack.views(for: id)'));
assert(atlas.indexOf("if let plate = RegionalStructurePack.plate(for: id) { return plate }") < atlas.indexOf("if let plate = FunctionStructurePack.plate(for: id) { return plate }"));
assert(atlas.includes("RegionalStructurePack.plate(for: id) ?? FunctionStructurePack.plate(for: id)"));
assert(atlas.includes("RegionalStructurePack.sources.contains(source)"));
assert(atlas.includes("available.first(where: { $0.viewKey == viewKey }) ?? available.first"));
const tenocyte = structures.plates.filter(p => p.owner === "cell-tenocyte");
assert.deepEqual(tenocyte.map(p => p.viewKey), ["atlas-detail-cell-tenocyte", "tenocyte-tendon-longitudinal"]);
assert.equal(new Set(tenocyte.map(p => p.id)).size, 2);
const pineal = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasRegionalPinealPlate.imageset/Contents.json")));
assert(pineal.properties["preserves-vector-representation"]); assert(local("PinealGlyphDrawing").includes('Image("HealthAtlasRegionalPinealPlate")'));
for (const [name, asset] of [["ErectorPosteriorDrawing", "ErectorSpinaePlate"], ["LigamentDrawing", "LigamentsPlate"], ["PlacentalAnatomyDrawing", "PlacentaPlate"]]) assert(local(name).includes('Image("HealthAtlasRegional' + asset + '")'));
for (const plate of structures.plates) assert(plate.asset.startsWith("HealthAtlasRegional"));
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
assert.equal(pbx.split("path = GalaxySSIHealthAtlasRegionalStructures.swift;").length - 1, 1);
console.log("Android #4385 runtime source: 114 explicit course dispatches, all 289 owner routes/entry phases, " + links + " related links, pinned revision/host guards, 73 structure views and two tenocyte selectors. Pineal retains preserved-vector PDF rendering. No Swift/native execution, zoom/rewind or UI acceptance.");
