// Static pinned-resource/PDF/source audit. No native Swift or UI execution.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process"), xml = require("xml-js");
const {PDFDocument, PDFName, PDFDict, PDFArray, decodePDFRawStream} = require("pdf-lib");
const root = path.resolve(__dirname, "../GalaxySSI"), assets = path.join(root, "Assets.xcassets");
const retinal = process.argv.includes("--retinal-cells");
const sha = retinal ? "b513fe5023b8699e4e64e1f914f09be98ddeeacb" : "7e5841c21c313fd2ecee924e6805385e96a564a1";
const source = file => execFileSync("git", ["show", sha + ":" + file], {encoding: "utf8", maxBuffer: 4_000_000});
const frames = retinal ? [
  ["sensory_aii", "HealthAtlasSensoryAii", "cell.pdf", 0], ["sensory_bipolar", "HealthAtlasSensoryBipolar", "cell.pdf", 3],
  ["sensory_ganglion", "HealthAtlasSensoryGanglion", "cell.pdf", 8], ["sensory_rpe", "HealthAtlasSensoryRpe", "cell.pdf", 13]
] : [
  ["sensory_retina_section", "HealthAtlasSensoryRetinaSection", "cell.pdf"]
];
const gradientOffset = retinal ? 0 : 9;
const array = (dict, key) => dict.lookup(PDFName.of(key), PDFArray).asArray().map(n => n.asNumber());
const colour = value => [1,3,5].map(i => parseInt(value.slice(i, i + 2), 16) / 255);
(async () => {
  let paths = 0, gradients = gradientOffset, gradientCount = 0;
  for (const [slug, asset, filename, firstGradient] of frames) {
    if (firstGradient !== undefined) gradients = firstGradient;
    const vector = xml.xml2js(source("apps/android/app/src/main/res/drawable/health_atlas_" + slug + ".xml"), {compact: true}).vector;
    const dir = path.join(assets, asset + ".imageset"), metadata = JSON.parse(fs.readFileSync(path.join(dir, "Contents.json")));
    assert(metadata.properties["preserves-vector-representation"]); assert(metadata.images.some(i => i.filename === filename));
    const pdf = await PDFDocument.load(fs.readFileSync(path.join(dir, filename)));
    assert.equal(pdf.getPageCount(), 1);
    const page = pdf.getPage(0), box = page.getSize();
    assert.equal(box.width, Number(vector._attributes["android:viewportWidth"]));
    assert.equal(box.height, Number(vector._attributes["android:viewportHeight"]));
    const resources = page.node.Resources(), shades = resources.lookup(PDFName.of("Shading"), PDFDict);
    const expected = vector.path.filter(p => p["aapt:attr"]); gradientCount += expected.length;
    assert.equal(shades.keys().length, expected.length);
    const images = resources.lookupMaybe(PDFName.of("XObject"), PDFDict);
    assert(!images || images.keys().length === 0, "Gradient/path PDF must not be rasterized");
    const contents = page.node.Contents().asArray().map(ref =>
      Buffer.from(decodePDFRawStream(pdf.context.lookup(ref)).decode()).toString()).join("\n");
    assert.equal((contents.match(/\/AtlasGradient\d+ sh/g) || []).length, expected.length);
    for (const item of expected) {
      const g = item["aapt:attr"].gradient._attributes, shade = shades.lookup(PDFName.of("AtlasGradient" + gradients++), PDFDict);
      const radial = g["android:type"] === "radial";
      assert.equal(shade.lookup(PDFName.of("ShadingType")).asNumber(), radial ? 3 : 2);
      const coords = radial ? [g["android:centerX"], g["android:centerY"], 0, g["android:centerX"], g["android:centerY"], g["android:gradientRadius"]].map(Number) :
        ["startX","startY","endX","endY"].map(k => Number(g["android:" + k]));
      assert.deepEqual(array(shade, "Coords"), coords);
      const fn = shade.lookup(PDFName.of("Function"), PDFDict);
      const colours = [g["android:startColor"], ...(g["android:centerColor"] ? [g["android:centerColor"]] : []), g["android:endColor"]].map(colour);
      const functions = fn.lookup(PDFName.of("FunctionType")).asNumber() === 3 ?
        fn.lookup(PDFName.of("Functions"), PDFArray).asArray().map(ref => pdf.context.lookup(ref, PDFDict)) : [fn];
      assert.equal(functions.length, colours.length - 1);
      for (const [index, f] of functions.entries()) {
        assert.deepEqual(array(f, "C0"), colours[index]); assert.deepEqual(array(f, "C1"), colours[index + 1]);
      }
    }
    paths += vector.path.length;
  }
  assert.equal(paths, retinal ? 35 : 24); assert.equal(gradientCount, retinal ? 11 : 2);
  const kotlin = execFileSync("git", ["show", "b513fe5023b8699e4e64e1f914f09be98ddeeacb:apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensorySections.kt"], {encoding: "utf8"});
  const swift = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasSensorySections.swift"), "utf8");
  const expectedRoutes = [...kotlin.matchAll(/atlasSectionTrack\(([\d.]+)f, ([\d.]+)f\) \{([^}]+)\}/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])}, commands: [...m[3].matchAll(/(lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(c => {
      const n = c[2].split(",").map(x => Number(x.trim().replace(/f$/, "")));
      return {kind: {lineTo: "line", quadTo: "quad", cubicTo: "cubic"}[c[1]],
        points: n.reduce((r, x, i) => { if (i % 2 === 0) r.push({x, y: n[i+1]}); return r; }, [])};
    })
  }));
  const actualRoutes = [...swift.matchAll(/\.init\(start: \.init\(x: ([\d.]+), y: ([\d.]+)\), commands: \[([\s\S]*?)(?=\n      \.init\(start:|\n    \])/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])}, commands: [...m[3].matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(c => ({
      kind: c[1], points: [...c[2].matchAll(/\.init\(x: ([\d.]+), y: ([\d.]+)\)/g)].map(p => ({x: Number(p[1]), y: Number(p[2])}))
    }))
  }));
  assert.equal(expectedRoutes.length, 4); assert.deepEqual(actualRoutes, expectedRoutes);
  const expectedFeatures = [...kotlin.matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(m => [m[1], Number(m[2]), Number(m[3]), m[4], m[5]]);
  const actualFeatures = [...swift.matchAll(/feature\("([^"]+)", (\d+), (\d+), "([^"]+)", (\d+)\)/g)].map(m =>
    [m[1], Number(m[2]), Number(m[3]), "health_atlas_" + m[4], "health_atlas_hearing_ear_" + m[5]]);
  assert.equal(expectedFeatures.length, 4); assert.deepEqual(actualFeatures, expectedFeatures);
  for (const language of ["en", "zh-Hans"]) {
    const directory = language === "en" ? "values" : "values-zh";
    const resource = xml.xml2js(source("apps/android/app/src/main/res/" + directory + "/health_atlas_hearing.xml"), {compact:true}).resources.string;
    const values = new Map(fs.readFileSync(path.join(root, language + ".lproj/BodyAtlas.strings"), "utf8").split(/\r?\n/).flatMap(line => {
      const m = line.match(/^"([^"]+)" = (".*");$/); return m ? [[m[1], JSON.parse(m[2])]] : [];
    }));
    for (const key of ["health_atlas_hearing_eardrum", "health_atlas_hearing_ossicles", "health_atlas_hearing_route_scope"])
      assert.equal(values.get(key), resource.find(r => r._attributes.name === key)._text);
  }
  console.log("Sensory parity: " + frames.length + " retained vector PDFs / " + paths + " source paths / " + gradientCount + " exact native gradients; Android #4359 ear routes/features and six inherited localized values. No native UI execution.");
})().catch(error => { console.error(error); process.exit(1); });
