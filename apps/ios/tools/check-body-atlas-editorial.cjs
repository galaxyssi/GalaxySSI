// Static byte/pixel/source parity only; this does not run SwiftUI or XCTest.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process"), sharp = require("sharp");
const root = path.resolve(__dirname, "../GalaxySSI"), assets = path.join(root, "Assets.xcassets");
const sha = "b4ed9ae74fa6989da5addbfdd8bf9d35dd960855";
const source = file => execFileSync("git", ["show", sha + ":" + file], {maxBuffer: 32_000_000});
const kotlin = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPlates.kt").toString();
const blocks = new Map([...kotlin.matchAll(/(?:private )?val (whole|heart|brain|lungs|liver|kidney|gut) = HealthAtlasPlate\(([\s\S]*?)(?=\n    (?:private )?val|\n    \/\*\*)/g)].map(m => [m[1], m[2]]));
const raw = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlas.swift"), "utf8");
const wholeStart = raw.indexOf('return Plate(id: "whole"');
const whole = raw.slice(wholeStart, raw.indexOf('if ["heart"', wholeStart));
const heart = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasHeartSection.swift"), "utf8");
const parseSwift = value => [...value.matchAll(/(?:Marker|\.init)\(id: "([^"]+)", x: ([\d.]+), y: ([\d.]+)\)/g)].map(m => ({id: m[1], x: Number(m[2]), y: Number(m[3])}));
const packs = ["HealthAtlasOrganPlates", "HealthAtlasSystemPlates"].flatMap(name =>
  JSON.parse(fs.readFileSync(path.join(assets, name + ".dataset/content.json"))).plates);
const frames = [
  ["Body", "body", "whole", "atlas.png", 1024, 1536],
  ["Heart", "heart", "heart", "atlas.png", 1086, 1448],
  ["Lungs", "lungs", "lungs", "atlas.png", 1254, 1254],
  ["Liver", "liver", "liver", "atlas.png", 1254, 1254],
  ["Kidney", "kidney", "kidney", "atlas.png", 1254, 1254],
  ["Brain", "brain", "brain", "atlas.png", 1254, 1254],
  ["Gut", "gut", "gut", "gut.png", 1024, 1536]
];
(async () => {
  let count = 0;
  for (const [name, slug, key, filename, width, height] of frames) {
    const original = source("apps/android/app/src/main/res/drawable-nodpi/health_atlas_" + slug + ".png");
    const dir = path.join(assets, "HealthAtlas" + name + ".imageset");
    const metadata = JSON.parse(fs.readFileSync(path.join(dir, "Contents.json")));
    assert(metadata.images.some(i => i.filename === filename));
    const png = fs.readFileSync(path.join(dir, filename)); assert(png.equals(original), "Byte mismatch " + name);
    const image = sharp(png), info = await image.metadata(); assert.equal(info.width, width); assert.equal(info.height, height); assert(info.hasAlpha);
    const raw = await image.ensureAlpha().raw().toBuffer();
    for (const x of [0, width - 1]) for (const y of [0, height - 1]) assert.equal(raw[(y * width + x) * 4 + 3], 0);
    const expected = [...blocks.get(key).matchAll(/HealthAtlasMarker\("([^"]+)", ([\d.]+)f, ([\d.]+)f\)/g)].map(m => ({id: m[1], x: Number(m[2]), y: Number(m[3])}));
    const actual = key === "whole" ? parseSwift(whole) : key === "heart" ?
      parseSwift(heart.slice(heart.indexOf("static let exterior"), heart.indexOf("static let section"))) :
      packs.find(p => p.asset === "HealthAtlas" + name).markers;
    assert.equal(actual.length, expected.length, key + " marker count");
    // Whole-body marker display order does not change their canonical coordinates.
    assert.deepEqual([...actual].sort((a,b) => a.id.localeCompare(b.id)), [...expected].sort((a,b) => a.id.localeCompare(b.id)));
    for (const marker of actual) {
      const x = Math.floor(marker.x * width), y = Math.floor(marker.y * height);
      assert(raw[(y * width + x) * 4 + 3] >= 200, "Transparent hotspot " + key + ":" + marker.id); count++;
    }
  }
  assert.equal(count, 26);
  const androidFlow = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSectionLessonView.kt").toString();
  const swift = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasSectionLessonView.swift"), "utf8");
  for (const value of ["6.5", "5.5", "4.3", "5.6", "2.7", "2.6"]) {
    assert(androidFlow.includes(value + "f")); assert(swift.includes(value), "Missing source dimension " + value);
  }
  console.log("Android #4354 parity: seven byte-identical PNGs, original dimensions, transparent corners, 26 exact opaque hotspots and source arrow dimensions. Native flow rendering not executed.");
})().catch(error => { console.error(error); process.exit(1); });
