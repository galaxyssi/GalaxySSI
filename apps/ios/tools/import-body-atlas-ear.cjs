// Convert Android #4341 original paths to a transparent, vector-preserving iOS asset.
// Requires pdf-lib and xml-js through NODE_PATH.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const { PDFDocument, rgb, LineCapStyle, LineJoinStyle, setLineJoin } = require("pdf-lib");
const xml = require("xml-js"), root = path.resolve(__dirname, "../../..");
const source = "apps/android/app/src/main/res/drawable/health_atlas_ear_section.xml";
const vector = xml.xml2js(cp.execFileSync("git", ["show",
  "29ca9c01d6e1ef8a156b77650448168a0ed09298:" + source],
  { cwd: root, encoding: "utf8" }), { compact: true }).vector;
const color = (hex) => rgb(...[1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255));
(async () => {
  const pdf = await PDFDocument.create(), a = vector._attributes;
  pdf.setTitle("GalaxySSI ear cross-section - Android #4341 paths");
  pdf.setCreationDate(new Date("2026-11-23T00:00:00Z"));
  pdf.setModificationDate(new Date("2026-11-23T00:00:00Z"));
  const height = Number(a["android:viewportHeight"]);
  const page = pdf.addPage([Number(a["android:viewportWidth"]), height]);
  for (const { _attributes: item } of vector.path) {
    const options = { x: 0, y: height };
    if (item["android:fillColor"]) options.color = color(item["android:fillColor"]);
    if (item["android:strokeColor"]) {
      options.borderColor = color(item["android:strokeColor"]);
      options.borderWidth = Number(item["android:strokeWidth"] ?? 0);
      if (item["android:strokeLineCap"] === "round") options.borderLineCap = LineCapStyle.Round;
    }
    page.pushOperators(setLineJoin(item["android:strokeLineJoin"] === "round" ? LineJoinStyle.Round : LineJoinStyle.Miter));
    page.drawSvgPath(item["android:pathData"], options);
  }
  fs.writeFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasEarSection.imageset/ear.pdf"), await pdf.save());
  console.log("Imported " + vector.path.length + " original ear paths.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
