// Reproduce Android #4340 vector paths as a transparent iOS PDF asset.
// Run with pdf-lib and xml-js available through NODE_PATH.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const { PDFDocument, rgb, LineCapStyle } = require("pdf-lib");
const xml = require("xml-js");
const root = path.resolve(__dirname, "../../..");
const source = "apps/android/app/src/main/res/drawable/health_atlas_eye_section.xml";
const sha = "24f22b76db1d7bb3764987ceb6354b16e1ab0679";
const vector = xml.xml2js(cp.execFileSync("git", ["show", sha + ":" + source],
  { cwd: root, encoding: "utf8" }), { compact: true }).vector;
const attributes = vector._attributes;
const color = (hex) => rgb(...[1, 3, 5].map((index) => parseInt(hex.slice(index, index + 2), 16) / 255));
(async () => {
  const pdf = await PDFDocument.create();
  pdf.setTitle("GalaxySSI eye cross-section - Android #4340 paths");
  pdf.setCreationDate(new Date("2026-11-23T00:00:00Z"));
  pdf.setModificationDate(new Date("2026-11-23T00:00:00Z"));
  const height = Number(attributes["android:viewportHeight"]);
  const page = pdf.addPage([Number(attributes["android:viewportWidth"]), height]);
  for (const item of vector.path) {
    const a = item._attributes, options = { x: 0, y: height };
    if (a["android:fillColor"]) options.color = color(a["android:fillColor"]);
    if (a["android:strokeColor"]) {
      options.borderColor = color(a["android:strokeColor"]);
      options.borderWidth = Number(a["android:strokeWidth"] ?? 0);
      if (a["android:strokeLineCap"] === "round") options.borderLineCap = LineCapStyle.Round;
    }
    page.drawSvgPath(a["android:pathData"], options);
  }
  const output = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasEyeSection.imageset/eye.pdf");
  fs.writeFileSync(output, await pdf.save());
  console.log("Imported " + vector.path.length + " original paths into " + output);
})().catch((error) => { console.error(error); process.exitCode = 1; });
