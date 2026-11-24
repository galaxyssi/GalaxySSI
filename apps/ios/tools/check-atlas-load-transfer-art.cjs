// Source/resource audit only; does not execute Swift, Metal, Android or XCTest.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), xml = require("xml-js");
const {PDFDocument, PDFRawStream, decodePDFRawStream} = require("pdf-lib");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = file => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/" + file], {cwd: root, encoding: "utf8"});
const read = file => fs.readFileSync(path.join(root, "apps/ios", file), "utf8");
(async () => {
  let paths = 0, holes = 0;
  for (const [slug, asset] of [["pelvic_ring", "PelvicRing"], ["subcutaneous_section", "SubcutaneousSection"]]) {
    const vector = xml.xml2js(source("res/drawable/health_atlas_" + slug + ".xml"), {compact: true}).vector;
    assert.equal(vector._attributes["android:viewportWidth"], "360");
    assert.equal(vector._attributes["android:viewportHeight"], "280");
    paths += vector.path.length;
    const expectedHoles = vector.path.filter(p => p._attributes["android:fillType"] === "evenOdd").length;
    const directory = "GalaxySSI/Assets.xcassets/HealthAtlasComplete" + asset + ".imageset/";
    assert.equal(JSON.parse(read(directory + "Contents.json")).properties["preserves-vector-representation"], true);
    const pdf = await PDFDocument.load(fs.readFileSync(path.join(root, "apps/ios", directory, "art.pdf")));
    assert.deepEqual(pdf.getPages()[0].getSize(), {width: 360, height: 280});
    const text = pdf.context.enumerateIndirectObjects().filter(([, obj]) => obj instanceof PDFRawStream)
      .map(([, obj]) => Buffer.from(decodePDFRawStream(obj).decode()).toString()).join("\n");
    assert.equal((text.match(/^(?:B|b|f)\*$/gm) || []).length, expectedHoles);
    holes += expectedHoles;
  }
  assert.equal(paths, 23); assert.equal(holes, 2);
  const view = read("GalaxySSI/GalaxySSIHealthAtlasLoadTransferStoryView.swift");
  for (const token of ["columns: 24, rows: 20", "Double(column) * 360 / 24", "Double(row) * 280 / 20",
    "15 * compression * relative * across * bulge", "42 + y + 28 * compression * across * depth"]) assert.ok(view.includes(token), token);
  const original = source("java/com/galaxyssi/chat/HealthAtlasSubcutaneousStoryView.kt");
  for (const token of ["const val COLUMNS = 24", "const val ROWS = 20", "15f * compression * relative * across * bulge",
    "42f + y + 28f * compression * across * depth"]) assert.ok(original.includes(token), token);
  const drawing = read("GalaxySSI/GalaxySSIHealthAtlasLoadTransferStoryDrawing.swift");
  for (const token of ["0.8 * smooth", "0.8 * (1 - smooth)", "0.5 + shift / 2", "(t - 0.24) / 0.76",
    "180 + shift * 97", "subcutaneous_force_spread", "subcutaneous_reference_surface"]) assert.ok(drawing.includes(token), token);
  const pbx = read("GalaxySSI.xcodeproj/project.pbxproj");
  for (const name of ["LoadTransferStoryView", "LoadTransferStoryDrawing"]) assert.ok(pbx.includes("GalaxySSIHealthAtlas" + name + ".swift in Sources"));
  console.log("Source-only load-transfer audit: 23 vector paths, two odd-even holes, original mesh formulas and course stage/trace contracts. No native rendering or runtime dispatch acceptance.");
})().catch(error => { console.error(error); process.exitCode = 1; });
