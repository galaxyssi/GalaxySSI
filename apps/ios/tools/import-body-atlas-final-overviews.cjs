// Import the four Android #4344 overview vectors, retaining original paths.
// Requires pdf-lib and xml-js through NODE_PATH.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const { PDFDocument, rgb, LineCapStyle, LineJoinStyle, setLineJoin } = require("pdf-lib");
const xml = require("xml-js"), root = path.resolve(__dirname, "../../..");
const assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSystemOverviews.dataset/content.json")));
const color = (hex) => {
  if (!/^#[0-9a-f]{6}$/i.test(hex)) throw Error("Unsupported color " + hex);
  return rgb(...[1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255));
};
(async () => {
  let count = 0;
  for (const plate of pack.plates.filter((plate) => plate.drawable)) {
    const vector = xml.xml2js(cp.execFileSync("git", ["show", pack.extensionSource.mergeCommit + ":" + plate.drawable],
      { cwd: root, encoding: "utf8" }), { compact: true }).vector;
    if (vector.group || !Array.isArray(vector.path)) throw Error("Unsupported vector structure " + plate.id);
    const pdf = await PDFDocument.create(), a = vector._attributes;
    pdf.setTitle("GalaxySSI " + plate.id + " overview - Android #4344 paths");
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
    fs.writeFileSync(path.join(assets, plate.asset + ".imageset/overview.pdf"), await pdf.save());
    count += vector.path.length;
  }
  console.log("Imported 4 system overviews / " + count + " original paths.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
