// Preserve the pinned Android paths and gradients as PDF vector/shading operations.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const {PDFDocument, PDFName, PDFDict, PDFOperator, PDFOperatorNames, drawSvgPath, clip, endPath,
  rgb, setLineJoin, LineJoinStyle, LineCapStyle, pushGraphicsState, popGraphicsState, concatTransformationMatrix} = require("pdf-lib");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const retinal = process.argv.includes("--retinal-cells");
const systems = process.argv.includes("--system-overviews");
const tissues = process.argv.includes("--tissues"), lymph = process.argv.includes("--lymph");
const functionArt = require("./body-atlas-function-artwork.cjs");
const batch = tissues || lymph;
const revision = functionArt ? (functionArt.androidPR ?? 4384) : batch ? 4363 : systems ? 4362 : retinal ? 4359 : 4358;
const sha = functionArt ? (functionArt.sha ?? "ab78711d467c013444883dbaeca23c39a601c875") : batch ? "b8fbf1191367153af2824506df99bbc5c5bae56e" : systems ? "5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2" : retinal ? "b513fe5023b8699e4e64e1f914f09be98ddeeacb" : "7e5841c21c313fd2ecee924e6805385e96a564a1";
const batchFrames = [];
for (const [enabled, name, filename] of [[tissues, "HealthAtlasTissues", "tissue.pdf"], [lymph, "HealthAtlasLymphOrgans", "cell.pdf"]]) {
  if (!enabled) continue;
  const pack = JSON.parse(fs.readFileSync(path.join(assets, name + ".dataset/content.json")));
  for (const plate of pack.plates) batchFrames.push([path.basename(plate.drawable, ".xml").replace("health_atlas_", ""), plate.asset, filename]);
}
const frames = functionArt ? functionArt.frames : batch ? batchFrames : systems ? [
  ["system_cardio", "HealthAtlasOverviewCardio", "overview.pdf", 0],
  ["system_testicular", "HealthAtlasOverviewTesticular", "overview.pdf", 3],
  ["system_ovarian", "HealthAtlasOverviewOvarian", "overview.pdf", 9]
] : retinal ? [
  ["sensory_aii", "HealthAtlasSensoryAii", "cell.pdf", 0], ["sensory_bipolar", "HealthAtlasSensoryBipolar", "cell.pdf", 3],
  ["sensory_ganglion", "HealthAtlasSensoryGanglion", "cell.pdf", 8], ["sensory_rpe", "HealthAtlasSensoryRpe", "cell.pdf", 13]
] : [
  ["sensory_retina_section", "HealthAtlasSensoryRetinaSection", "cell.pdf"]
];
// Keep retained #4358 PDF resource IDs stable when earlier ear, eye and sensory-cell gradients retire.
const gradientOffset = functionArt || batch || systems || retinal ? 0 : 9;
function components(value) {
  if (!/^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i.test(value)) throw Error("Unsupported colour " + value);
  const colour = value.length === 9 ? "#" + value.slice(3) : value;
  return [1, 3, 5].map(i => parseInt(colour.slice(i, i + 2), 16) / 255);
}
const alpha = value => value?.length === 9 ? parseInt(value.slice(1,3),16) / 255 : 1;
(async () => {
  let paths = 0, gradients = gradientOffset, gradientCount = 0;
  for (const [slug, asset, filename, firstGradient] of frames) {
    if (firstGradient !== undefined) gradients = firstGradient;
    const raw = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/res/drawable/health_atlas_" + slug + ".xml"],
      {cwd: root, encoding: "utf8"});
    const vector = xml.xml2js(raw, {compact: true}).vector;
    if (vector.group) {
      if (!functionArt?.groups) throw Error("Unsupported vector groups");
      vector.path = require("./body-atlas-ordered-vector.cjs")(raw, {affine: !!functionArt.affineGroups, clips: !!functionArt.clips});
    }
    if (!Array.isArray(vector.path)) throw Error("Unsupported vector structure");
    if (functionArt?.normalizeQuadratics) for (const item of vector.path) {
      item._attributes["android:pathData"] = require("./body-atlas-quadratic-path.cjs")(item._attributes["android:pathData"]);
    }
    const pdf = await PDFDocument.create(), height = Number(vector._attributes["android:viewportHeight"]);
    pdf.setTitle("GalaxySSI " + slug + " - Android #" + revision + " vector paths and gradients");
    pdf.setCreationDate(new Date("2026-11-24T00:00:00Z")); pdf.setModificationDate(new Date("2026-11-24T00:00:00Z"));
    const page = pdf.addPage([Number(vector._attributes["android:viewportWidth"]), height]);
    page.node.normalize();
    const resources = page.node.Resources(), shadings = pdf.context.obj({});
    resources.set(PDFName.of("Shading"), shadings);
    for (const item of vector.path) {
      if (item._atlasClips) {
        page.pushOperators(pushGraphicsState());
        for (const clip of item._atlasClips) page.pushOperators(...require("./body-atlas-vector-clips.cjs")(clip, height));
      }
      if (item._atlasTransform) page.pushOperators(pushGraphicsState(),
        concatTransformationMatrix(...require("./body-atlas-vector-transform.cjs").pdf(item._atlasTransform,height)));
      else if (item._atlasMirrorX) page.pushOperators(pushGraphicsState(),concatTransformationMatrix(-1,0,0,1,360,0));
      const a = item._attributes, nested = item["aapt:attr"];
      const options = {x: 0, y: height};
      if (a["android:fillColor"]) options.color = rgb(...components(a["android:fillColor"]));
      if (a["android:fillColor"] || a["android:fillAlpha"]) options.opacity = alpha(a["android:fillColor"]) * Number(a["android:fillAlpha"] ?? 1);
      if (a["android:strokeColor"]) {
        options.borderColor = rgb(...components(a["android:strokeColor"]));
        options.borderWidth = Number(a["android:strokeWidth"] || 0);
        options.borderOpacity = alpha(a["android:strokeColor"]) * Number(a["android:strokeAlpha"] ?? 1);
        if (a["android:strokeLineCap"] === "round") options.borderLineCap = LineCapStyle.Round;
      }
      page.pushOperators(setLineJoin(a["android:strokeLineJoin"] === "round" ? LineJoinStyle.Round : LineJoinStyle.Miter));
      if (nested) {
        const strokeGradient = nested._attributes.name === "android:strokeColor";
        if ((!strokeGradient && nested._attributes.name !== "android:fillColor") || !nested.gradient) throw Error("Unsupported nested path attribute");
        const g = nested.gradient._attributes;
        if (g["android:tileMode"]) throw Error("Unsupported gradient mode");
        const items = nested.gradient.item;
        const stops = items ? (Array.isArray(items) ? items : [items]).map(item => ({
          offset:Number(item._attributes["android:offset"]), color:item._attributes["android:color"]
        })) : [g["android:startColor"], ...(g["android:centerColor"] ? [g["android:centerColor"]] : []), g["android:endColor"]]
          .map((color, i, all) => ({color, offset:i/(all.length-1)}));
        if (stops.length < 2 || stops.length > 8 || stops[0].offset !== 0 || stops.at(-1).offset !== 1 ||
          stops.some((s,i) => !Number.isFinite(s.offset) || (i > 0 && s.offset <= stops[i-1].offset))) throw Error("Invalid gradient stops");
        if (stops.some(s=>alpha(s.color)!==1)) throw Error("Alpha gradient stops require explicit soft-mask support");
        const values = stops.map(s => components(s.color));
        const functions = values.slice(1).map((c, i) => pdf.context.register(pdf.context.obj({
          FunctionType: 2, Domain: [0, 1], C0: values[i], C1: c, N: 1
        })));
        const fn = functions.length === 1 ? functions[0] : pdf.context.register(pdf.context.obj({
          FunctionType: 3, Domain: [0, 1], Functions: functions, Bounds: stops.slice(1,-1).map(s => s.offset), Encode: functions.flatMap(() => [0,1])
        }));
        const radial = g["android:type"] === "radial";
        if (g["android:type"] && !radial && g["android:type"] !== "linear") throw Error("Unsupported gradient type");
        // Android GradientColor initializes omitted axis coordinates to zero.
        const coordinates = radial ? [g["android:centerX"] ?? 0, g["android:centerY"] ?? 0, 0, g["android:centerX"] ?? 0, g["android:centerY"] ?? 0, g["android:gradientRadius"]].map(Number) :
          ["startX", "startY", "endX", "endY"].map(key => Number(g["android:" + key] ?? 0));
        if (!coordinates.every(Number.isFinite)) throw Error("Invalid gradient coordinates");
        const name = PDFName.of("AtlasGradient" + gradients++); gradientCount++;
        const shading = pdf.context.register(pdf.context.obj({
          ShadingType: radial ? 3 : 2, ColorSpace: "DeviceRGB", Coords: coordinates, Function: fn, Extend: [true, true]
        }));
        shadings.set(name, shading);
        if (strokeGradient) {
          // PDF shading patterns retain the original stroked path, width, caps and joins.
          let patterns = resources.lookupMaybe(PDFName.of("Pattern"), PDFDict);
          if (!patterns) { patterns = pdf.context.obj({}); resources.set(PDFName.of("Pattern"), patterns); }
          patterns.set(name, pdf.context.register(pdf.context.obj({
            Type:"Pattern", PatternType:2, Shading:shading, Matrix:[1,0,0,-1,0,height]
          })));
          const operators = drawSvgPath(a["android:pathData"], {x:0,y:height,borderColor:rgb(0,0,0),
            borderWidth:Number(a["android:strokeWidth"]),borderOpacity:Number(a["android:strokeAlpha"]??1),borderLineCap:a["android:strokeLineCap"]==="round"?LineCapStyle.Round:LineCapStyle.Butt});
          const colour = operators.findIndex(op => op.toString().endsWith(" RG"));
          if (colour < 0) throw Error("Missing stroke colour operator");
          operators.splice(colour,1,PDFOperator.of("CS",[PDFName.of("Pattern")]),PDFOperator.of("SCN",[name]));
          page.pushOperators(...operators);
          if (item._atlasMirrorX || item._atlasTransform) page.pushOperators(popGraphicsState());
          if (item._atlasClips) page.pushOperators(popGraphicsState());
          paths++; continue;
        }
        // pdf-lib parses the original SVG path; replace painting with clipping plus PDF shading.
        const operators = drawSvgPath(a["android:pathData"], {x: 0, y: height, color: rgb(0, 0, 0), opacity: options.opacity});
        if (operators[operators.length - 2].toString() !== "f") throw Error("Unexpected pdf-lib path operator layout");
        operators.splice(operators.length - 2, 1, clip(), endPath(), PDFOperator.of(PDFOperatorNames.ShadingFill, [name]));
        page.pushOperators(...operators);
        if (options.borderColor) page.drawSvgPath(a["android:pathData"], {...options, color: undefined});
      } else if (functionArt?.preserveFillRules && a["android:fillType"] === "evenOdd") {
        // This opaque source cohort needs PDF's odd-even painting, not nonzero winding.
        if ((options.opacity ?? 1) !== 1 || (options.borderOpacity ?? 1) !== 1) throw Error("Unsupported translucent odd-even source");
        const operators = drawSvgPath(a["android:pathData"], options);
        page.pushOperators(...operators.map(op => ["f", "B", "b"].includes(op.name) ? PDFOperator.of(op.name + "*", op.args) : op));
      } else page.drawSvgPath(a["android:pathData"], options);
      if (item._atlasMirrorX || item._atlasTransform) page.pushOperators(popGraphicsState());
      if (item._atlasClips) page.pushOperators(popGraphicsState());
      paths++;
    }
    const directory = path.join(assets, asset + ".imageset");
    if (functionArt) {
      fs.mkdirSync(directory, {recursive: true});
      fs.writeFileSync(path.join(directory, "Contents.json"), JSON.stringify({
        images: [{filename, idiom: "universal"}], info: {author: "xcode", version: 1},
        properties: {"preserves-vector-representation": true}
      }, null, 2) + "\n");
    }
    fs.writeFileSync(path.join(directory, filename), await pdf.save());
  }
  const expectedPaths = functionArt ? functionArt.paths : batch ? (tissues ? 546 : 0) + (lymph ? 100 : 0) : systems ? 39 : retinal ? 35 : 24;
  const expectedGradients = functionArt ? functionArt.gradients : batch ? (tissues ? 150 : 0) + (lymph ? 60 : 0) : systems ? 18 : retinal ? 11 : 2;
  if (paths !== expectedPaths || gradientCount !== expectedGradients) throw Error("Unexpected source geometry: " + paths + "/" + gradients);
  console.log("Imported Android #" + revision + ": " + paths + " original paths and " + gradientCount + " native gradients across " + frames.length + " retained vector assets.");
})().catch(error => { console.error(error); process.exitCode = 1; });
