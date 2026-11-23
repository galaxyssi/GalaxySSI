// Convert Android #4350 sensory cell paths to transparent iOS vector PDFs.
// Requires pdf-lib and xml-js through NODE_PATH.
const fs = require("node:fs"), cp = require("node:child_process"), path = require("node:path");
const { PDFDocument, rgb, LineCapStyle, LineJoinStyle, setLineJoin } = require("pdf-lib");
const xml = require("xml-js"), root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSensoryCells.dataset/content.json")));
const color = (hex) => {
  if (!/^#[0-9a-f]{6}$/i.test(hex)) throw Error("Unsupported color " + hex);
  return rgb(...[1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255));
};
(async () => {
  let count = 0, diagrams = 0;
  const current = new Set(["HealthAtlasSensoryCochlearHair", "HealthAtlasSensoryRod", "HealthAtlasSensoryCone",
    "HealthAtlasSensoryAii", "HealthAtlasSensoryBipolar", "HealthAtlasSensoryGanglion", "HealthAtlasSensoryRpe", "HealthAtlasSensoryRetinaSection"]);
  for (const plate of pack.plates) {
    if (current.has(plate.asset)) continue;
    const vector = xml.xml2js(cp.execFileSync("git", ["show", pack.source.mergeCommit + ":" + plate.drawable],
      { cwd: root, encoding: "utf8" }), { compact: true }).vector;
    if (vector.group || !Array.isArray(vector.path)) throw Error("Unsupported vector structure " + plate.id);
    const pdf = await PDFDocument.create(), a = vector._attributes;
    pdf.setTitle("GalaxySSI " + plate.owner + " - Android #4350 paths");
    pdf.setCreationDate(new Date("2026-11-23T00:00:00Z")); pdf.setModificationDate(new Date("2026-11-23T00:00:00Z"));
    const height = Number(a["android:viewportHeight"]);
    const page = pdf.addPage([Number(a["android:viewportWidth"]), height]);
    for (const { _attributes: item } of vector.path) {
      const options = { x: 0, y: height };
      if (item["android:fillColor"]) options.color = color(item["android:fillColor"]);
      if (item["android:strokeColor"]) {
        options.borderColor = color(item["android:strokeColor"]); options.borderWidth = Number(item["android:strokeWidth"] ?? 0);
        if (item["android:strokeLineCap"] === "round") options.borderLineCap = LineCapStyle.Round;
      }
      page.pushOperators(setLineJoin(item["android:strokeLineJoin"] === "round" ? LineJoinStyle.Round : LineJoinStyle.Miter));
      page.drawSvgPath(item["android:pathData"], options);
    }
    fs.writeFileSync(path.join(assets, plate.asset + ".imageset/cell.pdf"), await pdf.save()); count += vector.path.length; diagrams++;
  }
  console.log("Imported " + diagrams + " unchanged sensory diagrams / " + count + " original paths.");
  for (const args of [["import-body-atlas-sensory-gradients.cjs"], ["import-body-atlas-sensory-gradients.cjs", "--retinal-cells"],
    ["import-body-atlas-portrait-cells.cjs"]]) {
    cp.execFileSync(process.execPath, [path.join(__dirname, args[0]), ...args.slice(1)], {stdio: "inherit"});
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
