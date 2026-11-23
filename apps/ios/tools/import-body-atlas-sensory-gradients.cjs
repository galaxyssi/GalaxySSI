// Preserve the pinned Android paths and gradients as PDF vector/shading operations.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const {PDFDocument, PDFName, PDFDict, PDFOperator, PDFOperatorNames, drawSvgPath, clip, endPath,
  rgb, setLineJoin, LineJoinStyle, LineCapStyle} = require("pdf-lib");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const retinal = process.argv.includes("--retinal-cells");
const sha = retinal ? "b513fe5023b8699e4e64e1f914f09be98ddeeacb" : "7e5841c21c313fd2ecee924e6805385e96a564a1";
const frames = retinal ? [
  ["sensory_aii", "HealthAtlasSensoryAii", "cell.pdf"], ["sensory_bipolar", "HealthAtlasSensoryBipolar", "cell.pdf"],
  ["sensory_cone", "HealthAtlasSensoryCone", "cell.pdf"], ["sensory_ganglion", "HealthAtlasSensoryGanglion", "cell.pdf"],
  ["sensory_rod", "HealthAtlasSensoryRod", "cell.pdf"], ["sensory_rpe", "HealthAtlasSensoryRpe", "cell.pdf"]
] : [
  ["eye_section", "HealthAtlasEyeSection", "eye.pdf"],
  ["sensory_cochlear_hair", "HealthAtlasSensoryCochlearHair", "cell.pdf"],
  ["sensory_retina_section", "HealthAtlasSensoryRetinaSection", "cell.pdf"]
];
// Keep retained #4358 PDF resource IDs stable after retiring the ear's four gradients.
const gradientOffset = retinal ? 0 : 4;
function components(value) {
  if (!/^#[0-9a-f]{6}$/i.test(value)) throw Error("Unsupported colour " + value);
  return [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16) / 255);
}
(async () => {
  let paths = 0, gradients = gradientOffset;
  for (const [slug, asset, filename] of frames) {
    const vector = xml.xml2js(cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable/health_atlas_" + slug + ".xml"],
      {cwd: root, encoding: "utf8"}), {compact: true}).vector;
    if (vector.group || !Array.isArray(vector.path)) throw Error("Unsupported vector structure");
    const pdf = await PDFDocument.create(), height = Number(vector._attributes["android:viewportHeight"]);
    pdf.setTitle("GalaxySSI " + slug + " - Android #" + (retinal ? 4359 : 4358) + " vector paths and gradients");
    pdf.setCreationDate(new Date("2026-11-24T00:00:00Z")); pdf.setModificationDate(new Date("2026-11-24T00:00:00Z"));
    const page = pdf.addPage([Number(vector._attributes["android:viewportWidth"]), height]);
    page.node.normalize();
    const resources = page.node.Resources(), shadings = pdf.context.obj({});
    resources.set(PDFName.of("Shading"), shadings);
    for (const item of vector.path) {
      const a = item._attributes, nested = item["aapt:attr"];
      const options = {x: 0, y: height};
      if (a["android:fillColor"]) options.color = rgb(...components(a["android:fillColor"]));
      if (a["android:fillAlpha"]) options.opacity = Number(a["android:fillAlpha"]);
      if (a["android:strokeColor"]) {
        options.borderColor = rgb(...components(a["android:strokeColor"]));
        options.borderWidth = Number(a["android:strokeWidth"] || 0);
        options.borderOpacity = 1;
        if (a["android:strokeLineCap"] === "round") options.borderLineCap = LineCapStyle.Round;
      }
      page.pushOperators(setLineJoin(a["android:strokeLineJoin"] === "round" ? LineJoinStyle.Round : LineJoinStyle.Miter));
      if (nested) {
        if (nested._attributes.name !== "android:fillColor" || !nested.gradient) throw Error("Unsupported nested path attribute");
        const g = nested.gradient._attributes;
        if (nested.gradient.item || g["android:tileMode"]) throw Error("Unsupported gradient stops/mode");
        const values = [g["android:startColor"], ...(g["android:centerColor"] ? [g["android:centerColor"]] : []), g["android:endColor"]].map(components);
        const functions = values.slice(1).map((c, i) => pdf.context.register(pdf.context.obj({
          FunctionType: 2, Domain: [0, 1], C0: values[i], C1: c, N: 1
        })));
        const fn = functions.length === 1 ? functions[0] : pdf.context.register(pdf.context.obj({
          FunctionType: 3, Domain: [0, 1], Functions: functions, Bounds: [0.5], Encode: [0, 1, 0, 1]
        }));
        const radial = g["android:type"] === "radial";
        if (g["android:type"] && !radial && g["android:type"] !== "linear") throw Error("Unsupported gradient type");
        const coordinates = radial ? [g["android:centerX"], g["android:centerY"], 0, g["android:centerX"], g["android:centerY"], g["android:gradientRadius"]].map(Number) :
          ["startX", "startY", "endX", "endY"].map(key => Number(g["android:" + key]));
        if (!coordinates.every(Number.isFinite)) throw Error("Invalid gradient coordinates");
        const name = PDFName.of("AtlasGradient" + gradients++);
        shadings.set(name, pdf.context.register(pdf.context.obj({
          ShadingType: radial ? 3 : 2, ColorSpace: "DeviceRGB", Coords: coordinates, Function: fn, Extend: [true, true]
        })));
        // pdf-lib parses the original SVG path; replace painting with clipping plus PDF shading.
        const operators = drawSvgPath(a["android:pathData"], {x: 0, y: height, color: rgb(0, 0, 0)});
        if (operators[operators.length - 2].toString() !== "f") throw Error("Unexpected pdf-lib path operator layout");
        operators.splice(operators.length - 2, 1, clip(), endPath(), PDFOperator.of(PDFOperatorNames.ShadingFill, [name]));
        page.pushOperators(...operators);
        if (options.borderColor) page.drawSvgPath(a["android:pathData"], {...options, color: undefined});
      } else page.drawSvgPath(a["android:pathData"], options);
      paths++;
    }
    fs.writeFileSync(path.join(assets, asset + ".imageset", filename), await pdf.save());
  }
  if (paths !== (retinal ? 49 : 46) || gradients - gradientOffset !== (retinal ? 17 : 7)) throw Error("Unexpected source geometry: " + paths + "/" + gradients);
  console.log("Imported Android #" + (retinal ? 4359 : 4358) + ": " + paths + " original paths and " + (gradients - gradientOffset) + " native gradients across " + frames.length + " retained vector assets.");
})().catch(error => { console.error(error); process.exitCode = 1; });
