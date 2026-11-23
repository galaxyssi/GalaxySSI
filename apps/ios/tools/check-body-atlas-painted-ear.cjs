// Byte/geometry/pixel audit only; not a native iOS test.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process"), sharp = require("sharp");
const {svgPathProperties} = require("svg-path-properties");
const root = path.resolve(__dirname, "../GalaxySSI"), dir = path.join(root, "Assets.xcassets/HealthAtlasEarSection.imageset");
const sha = "b513fe5023b8699e4e64e1f914f09be98ddeeacb";
const source = file => execFileSync("git", ["show", sha + ":" + file], {maxBuffer: 16_000_000});
(async () => {
  const metadata = JSON.parse(fs.readFileSync(path.join(dir, "Contents.json")));
  assert(metadata.images.some(i => i.filename === "ear.png")); assert(!metadata.properties?.["preserves-vector-representation"]);
  assert(!fs.existsSync(path.join(dir, "ear.pdf")), "Retired ear PDF must not remain bundled");
  const png = fs.readFileSync(path.join(dir, "ear.png"));
  assert(png.equals(source("apps/android/app/src/main/res/drawable-nodpi/health_atlas_ear_section.png")));
  const image = sharp(png), dimensions = await image.metadata();
  assert.equal(dimensions.width, 1536); assert.equal(dimensions.height, 1024); assert.equal(dimensions.width / dimensions.height, 3 / 2);
  const {data, info} = await image.resize(420, 280).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  const pixel = (x, y) => { const offset = (Math.floor(y) * info.width + Math.floor(x)) * info.channels; return data.subarray(offset, offset + 4); };
  for (const x of [0,419]) for (const y of [0,279]) assert(pixel(x,y)[3] <= 4);
  const plates = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPlates.kt").toString();
  const start = plates.indexOf('private val ear ='), block = plates.slice(start, plates.indexOf("\n    val all", start));
  const expectedMarkers = [...block.matchAll(/HealthAtlasMarker\("([^"]+)", ([\d.]+)f, ([\d.]+)f\)/g)].map(m => ({id:m[1], x:Number(m[2]), y:Number(m[3])}));
  const native = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasMiddleEar.swift"), "utf8");
  const actualMarkers = [...native.matchAll(/\.init\(id: "([^"]+)", x: ([\d.]+), y: ([\d.]+)\)/g)].map(m => ({id:m[1], x:Number(m[2]), y:Number(m[3])}));
  assert.equal(expectedMarkers.length, 5); assert.deepEqual(actualMarkers, expectedMarkers);
  assert(native.includes("aspectRatio: 3.0 / 2"));
  for (const marker of actualMarkers) assert(pixel(marker.x * 420, marker.y * 280)[3] > 200, marker.id);
  const kotlin = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensorySections.kt").toString();
  const factory = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasSensorySections.swift"), "utf8");
  assert(factory.includes("x: x / 420")); assert(factory.includes("artWidth: 420"));
  const features = [...kotlin.matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)];
  assert.equal(features.length, 4);
  for (const f of features) assert(pixel(Number(f[2]), Number(f[3]))[3] > 200, f[1]);
  const tracks = [...kotlin.matchAll(/atlasSectionTrack\(([\d.]+)f, ([\d.]+)f\) \{([\s\S]*?)\}/g)];
  assert.equal(tracks.length, 4);
  let count = 0, endpoint;
  for (const [stage, track] of tracks.entries()) {
    let svg = "M" + track[1] + "," + track[2];
    for (const command of track[3].matchAll(/(lineTo|quadTo|cubicTo)\(([^)]+)\)/g))
      svg += " " + ({lineTo:"L", quadTo:"Q", cubicTo:"C"}[command[1]]) + command[2].replace(/f/g,"");
    const curve = new svgPathProperties(svg), length = curve.getTotalLength();
    for (let i=0; i<=12; i++) {
      endpoint = curve.getPointAtLength(length * i / 12);
      assert(pixel(endpoint.x, endpoint.y)[3] > 200, "Off-plate route: stage " + stage + ", point " + i); count++;
    }
  }
  assert.equal(count, 52); assert(Math.abs(endpoint.x - 411) < 1e-6); assert(Math.abs(endpoint.y - 135) < 1e-6);
  const output = pixel(endpoint.x, endpoint.y); assert(output[0] > output[2] + 45, "Output must end on ochre auditory nerve, not the tube");
  console.log("Android #4359 painted-ear parity: original 1536x1024 PNG, 3:2 canvas, five exact opaque navigation points, four features, 52 on-plate arc-length samples and nerve endpoint colour. Not native UI execution.");
})().catch(error => { console.error(error); process.exit(1); });
