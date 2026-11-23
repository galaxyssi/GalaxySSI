// Pinned geometry/source wiring only; no native compilation or pleural-mechanics validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPleuraStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasPleuraMotion.swift"),view=local("GalaxySSIHealthAtlasPleuraView.swift"),drawing=local("GalaxySSIHealthAtlasPleuraDrawing.swift"),all=motion+view+drawing;
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"");
const kotlin=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const swift=block=>[...block.matchAll(/(?:p|edge|path)\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))/g)].map(m=>{
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return m[1]==="addCurve"||m[1]==="addQuadCurve"?[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
});
const fromAirway=source.match(/private val airway = Path\(\).apply \{([^}]+)\}/)[1],toAirway=view.match(/static let airway = Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(swift(toAirway),kotlin(fromAirway));
const fromEdge=source.match(/edge\.rewind\(\)([\s\S]*?)stroke\(c, edge/)[1],toEdge=drawing.match(/var edge = Path\(\);([\s\S]*?)stroke\(edge/)[1];
assert.deepEqual(swift(toEdge),kotlin(fromEdge));
const fromBase=source.match(/private fun lungBase\([^}]+?\{([^}]+)\}/)[1],toBase=drawing.match(/private func pleuraLungBase\([^}]+?\{([^}]+)\}/)[1];
assert.deepEqual(swift(toBase),kotlin(fromBase));
for(const [native,android] of [
  ["(1 - cos(2 * .pi * t)) / 2","(1f - cos(2.0 * PI * t).toFloat()) / 2f"],
  ["case 0: breath = 0.28 * pulse","0 -> .28f * pulse"],["case 1: breath = 0.55 * t","1 -> .55f * t"],
  ["case 2: breath = 0.55 + 0.45 * t","2 -> .55f + .45f * t"],["case 3: breath = 1 - 0.72 * pulse","3 -> 1f - .72f * pulse"],
  ["default: breath = 1 - t","else -> 1f - t"],["1 + 0.11 * breath","1f + .11f * breath"],
  ["55 + Double(i) * 54 + 9 * breath","55f + i * 54f + 9f * breath"],
  ["55 + Double(i) * 54 + 35 * breath","55f + i * 54f + 35f * breath"],
  ["86 + 6 * Double(i) - 1.15 * Double(i * i)","86f + 6f * i - 1.15f * i * i"],
  ["81 + 19 * Double(i) - 3 * breath","81f + 19f * i - 3f * breath"],
  ["heartSide ? 12.0 : 0","if (heartSide) 12f else 0f"],["highlight ? 2.3 : 1.5","if (highlightLung) 2.3f else 1.5f"],
  ["171 + 17 * breath","171f + 17f * breath"],["171 + 20 * breath","171f + 20f * breath"],
  ["step == 1 ? 1.0 : -1","if (step == 1) 1f else -1f"]
]){assert(all.includes(native),native);assert(source.includes(android),android);}
for(const token of ["local.translateBy(x: 180, y: 0); local.scaleBy(x: side * widen, y: 1)","heartSide: side > 0, highlight: step == 2",
  "var lung = edge; pleuraLungBase(&lung, breath)","stroke(lung, PleuraInk.parietal, 7); stroke(lung, PleuraInk.fluid, 4.5)",
  "local.clip(to: lung)","diaphragm.translateBy(x: 0, y: 5)","if !heartSide", "if step == 1 || step == 4", "if step == 2", "sliding: step == 3",
  "CGRect(x: 24, y: 266, width: 312, height: 6)", "sliding ? PleuraInk.parietal : 0xAEACA0", "sliding ? PleuraInk.visceral : 0xC79A9F"])assert(all.includes(token),token);
for(const color of ["527F79","95576B","A6DBE3","516B72","FAE0D9","DBA0A9","AB8072","EED2BA","E4BAAC","F4DCD0","A86567","DFA495","F5DED2","F5C7C7"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(pleura_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-pleural-coupling-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PLEURAL_COUPLING": GalaxySSIHealthAtlasPleuraView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["PleuraMotion","PleuraView","PleuraDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 pleura source audit: source airway/costal/basal curves, shared layered contour, mirrored heart-side notch/fissures, diaphragm coupling, sheet-attached sliding marks and bilingual labels. No native compilation/pixels verified.");
