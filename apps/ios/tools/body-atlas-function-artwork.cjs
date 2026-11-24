// Dedicated #4384 course art, shared by the importer and PDF/source audit.
const batches = {
  "--complete-load-transfer": {name: "load transfer", androidPR: 4388,
    sha: "6581110ec5c048edebf63821dee839b4818fe663", paths: 23, gradients: 0,
    groups: true, affineGroups: true, clips: true, normalizeQuadratics: true, preserveFillRules: true,
    frames: [["pelvic_ring", "HealthAtlasCompletePelvicRing", "art.pdf", 0],
      ["subcutaneous_section", "HealthAtlasCompleteSubcutaneousSection", "art.pdf", 0]]},
  "--function-gut-lymphoid": {name:"gut lymphoid", paths:26, gradients:8, frames:[
    ["gut_lymphoid_locator","HealthAtlasFunctionGutLymphoidLocator","art.pdf"],
    ["gut_lymphoid_comparison","HealthAtlasFunctionGutLymphoidComparison","art.pdf"]]},
  "--function-erector": {name:"erector", paths:19, gradients:8, groups:true,
    frames:[["erector_spinae_plate","HealthAtlasFunctionErector","art.pdf"]]},
  "--function-placenta": {name:"placenta", paths:19, gradients:5,
    frames:[["placenta_plate","HealthAtlasFunctionPlacenta","art.pdf"]]},
  "--function-ligaments": {name:"ligaments", paths:27, gradients:5,
    frames:[["ligaments_plate","HealthAtlasFunctionLigaments","art.pdf"]]},
  "--function-pineal": {name:"pineal", paths:32, gradients:5,
    frames:[["pineal_plate","HealthAtlasFunctionPineal","art.pdf"]]},
  "--function-digestion": {name:"digestive", paths:35, gradients:21, frames:
    ["mouth","esophagus","stomach","duodenum","large","rectum"].map(slug =>
      ["gut_"+slug,"HealthAtlasFunctionGut"+slug[0].toUpperCase()+slug.slice(1),"art.pdf"])},
  "--function-insulin": {name:"insulin", paths:18, gradients:16,
    frames:[["digestive_islet","HealthAtlasFunctionIslet","art.pdf"]]},
  "--function-homeostasis": {name:"homeostasis", paths:12, gradients:7,
    frames:[["digestive_alpha","HealthAtlasFunctionAlpha","art.pdf"],
      ["cell_sweat_gland_section","HealthAtlasFunctionSweatGland","art.pdf"]]},
  "--function-signal": {name:"signal", paths:34, gradients:0,
    frames:[["endocrine_pituitary_section","HealthAtlasFunctionPituitary","art.pdf"],
      ["endocrine_thyroid_section","HealthAtlasFunctionThyroid","art.pdf"]]}
};
if (process.argv.includes("--regional-4385")) {
  const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
  const root = path.resolve(__dirname, "../../..");
  const inventory = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/ANDROID_4385_SOURCE_INVENTORY.json")));
  if (inventory.source.androidPR !== 4385 || inventory.source.mergeCommit !== "a81aa85a1c81e41ff19a032eabea1eddcd2371dc") throw Error("Regional artwork source mismatch");
  const files = inventory.files.filter(f => f.path.includes("/res/drawable/") && f.path.endsWith(".xml"));
  if (files.length !== 23 || files.some(f => !["A", "M"].includes(f.status))) throw Error("Regional artwork inventory mismatch");
  let paths = 0, gradients = 0;
  const frames = files.map(file => {
    const raw = cp.execFileSync("git", ["show", inventory.source.mergeCommit + ":" + file.path], {cwd: root, encoding: "utf8"});
    const items = require("./body-atlas-ordered-vector.cjs")(raw, {affine: true, clips: true});
    paths += items.length; gradients += items.filter(p => p["aapt:attr"]).length;
    const slug = path.basename(file.path, ".xml").replace(/^health_atlas_/, "");
    const asset = "HealthAtlasRegional" + slug.split("_").map(part => part[0].toUpperCase() + part.slice(1)).join("");
    return [slug, asset, "art.pdf", 0];
  });
  batches["--regional-4385"] = {name: "regional", androidPR: 4385, sha: inventory.source.mergeCommit,
    paths, gradients, frames, groups: true, affineGroups: true, clips: true, normalizeQuadratics: true};
}
if (process.argv.includes("--regional-structures-4385")) {
  const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
  const root = path.resolve(__dirname, "../../..");
  const pack = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasRegionalStructures.dataset/content.json")));
  if (pack.source.androidPR !== 4385 || pack.source.mergeCommit !== "a81aa85a1c81e41ff19a032eabea1eddcd2371dc" || pack.plates.length !== 73) throw Error("Regional structure artwork source mismatch");
  let paths = 0, gradients = 0;
  const frames = pack.plates.map(plate => {
    const raw = cp.execFileSync("git", ["show", pack.source.mergeCommit + ":" + plate.drawable], {cwd: root, encoding: "utf8"});
    const items = require("./body-atlas-ordered-vector.cjs")(raw, {affine: true, clips: true});
    paths += items.length; gradients += items.filter(p => p["aapt:attr"]).length;
    return [path.basename(plate.drawable, ".xml").replace(/^health_atlas_/, ""), plate.asset, "art.pdf", 0];
  });
  if (new Set(frames.map(f => f[1])).size !== 73) throw Error("Regional structure asset collision");
  batches["--regional-structures-4385"] = {name: "complete regional structures", androidPR: 4385,
    sha: pack.source.mergeCommit, paths, gradients, frames, groups: true, affineGroups: true, clips: true, normalizeQuadratics: true};
}
if (process.argv.includes("--function-structures")) {
  const fs = require("node:fs"), path = require("node:path");
  const pack = JSON.parse(fs.readFileSync(path.join(__dirname,"../GalaxySSI/Assets.xcassets/HealthAtlasFunctionStructures.dataset/content.json")));
  batches["--function-structures"] = {name:"structure catalogue",paths:685,gradients:96,groups:true,affineGroups:true,
    frames:pack.plates.filter(p=>p.asset.startsWith("HealthAtlasStructure")).map(p=>[
      path.basename(p.drawable,".xml").replace("health_atlas_",""),p.asset,"art.pdf"])};
}
for (const [flag,dataset,paths,gradients] of [
  ["--function-digestive-structures","HealthAtlasDigestiveCells",104,93],
  ["--function-gut-structures","HealthAtlasGutSections",87,56]
]) if (process.argv.includes(flag)) {
  const fs = require("node:fs"), path = require("node:path");
  const pack = JSON.parse(fs.readFileSync(path.join(__dirname,"../GalaxySSI/Assets.xcassets",dataset+".dataset/content.json")));
  batches[flag] = {name:dataset,paths,gradients,groups:true,affineGroups:true,
    frames:pack.plates.filter(p=>p.drawable.endsWith(".xml")).map(p=>[
      path.basename(p.drawable,".xml").replace("health_atlas_",""),p.asset,"cell.pdf"])};
}
if (process.argv.includes("--detail-4389") || process.argv.includes("--expanded-4391") || process.argv.includes("--anatomy-4396")) {
  const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
  const anatomy = process.argv.includes("--anatomy-4396"), expanded = process.argv.includes("--expanded-4391"), revision = anatomy ? 4396 : expanded ? 4391 : 4389;
  const root = path.resolve(__dirname, "../../.."), sha = anatomy ? "dbd32a65c73e10d710372c44a7ffa8d1518d1f2c" : expanded ? "165809fc9606ac1ff6b0df6eb9bee73286b415ea" : "9508d49277cf33ab7f85e65722e7c470930fff7e";
  const pack = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/" + (anatomy ? "HealthAtlasAnatomyStructures" : expanded ? "HealthAtlasExpandedDetailStructures" : "HealthAtlasDetailStructures") + ".dataset/content.json")));
  if (pack.source.androidPR !== revision || pack.source.mergeCommit !== sha || pack.plates.length !== (anatomy ? 88 : expanded ? 61 : 26)) throw Error("Detail source mismatch");
  let paths = 0, gradients = 0;
  const frames = pack.plates.filter(p => anatomy ? p.asset.startsWith("HealthAtlasAnatomy") : !expanded || p.asset.startsWith("HealthAtlasExpanded")).map(plate => {
    const raw = cp.execFileSync("git", ["show", sha + ":" + plate.drawable], {cwd: root, encoding: "utf8"});
    const items = require("./body-atlas-ordered-vector.cjs")(raw, {affine: true, clips: true});
    paths += items.length; gradients += items.filter(p => p["aapt:attr"]).length;
    return [path.basename(plate.drawable, ".xml").replace(/^health_atlas_/, ""), plate.asset, "art.pdf", 0];
  });
  if (frames.length !== (anatomy ? 27 : expanded ? 35 : 26)) throw Error("Unexpected detail artwork count");
  batches[anatomy ? "--anatomy-4396" : expanded ? "--expanded-4391" : "--detail-4389"] = {name: "dedicated anatomy cutaways", androidPR: revision, sha, paths, gradients,
    groups: true, affineGroups: true, clips: true, normalizeQuadratics: true, preserveFillRules: true, frames};
}
const selected = Object.keys(batches).filter(flag=>process.argv.includes(flag));
if(selected.length>1)throw Error("Select one Function artwork batch at a time");
module.exports = selected.length ? batches[selected[0]] : null;
