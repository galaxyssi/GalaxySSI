// Pinned geometry/timing/resource checks only; no native compilation or autonomic validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAutonomicRelayStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","AnatomyDrawing","FiberDrawing","StagesDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasAutonomic" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const constants={MEDULLA_X:"medullaX",MEDULLA_Y:"medullaY",SPINAL_X:"spinalX",SPINAL_Y:"spinalY",THORACIC_X:"thoracicX",THORACIC_Y:"thoracicY",CARDIAC_X:"cardiacX",CARDIAC_Y:"cardiacY",SA_X:"saX",SA_Y:"saY"};
const canonical=s=>norm(s).replace(/AutonomicLabelAnchors\./g,"").replace(/MEDULLA_X|MEDULLA_Y|SPINAL_X|SPINAL_Y|THORACIC_X|THORACIC_Y|CARDIAC_X|CARDIAC_Y|SA_X|SA_Y/g,s=>constants[s]);
const outlines=[...source.matchAll(/private val (\w+) = path \{([^}]+)\}/g)];
assert.equal(outlines.length,11);
for(const [,name,block] of outlines){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
const routes=[...source.matchAll(/private val (\w+) = route \{([^}]+)\}/g)];
assert.equal(routes.length,8);
for(const [,name,block] of routes){
  const expected=fromCommands(block).map(c=>c.map(canonical));
  const native=files[2].match(new RegExp("static let "+name+" = Fiber\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...native.matchAll(/\.init\(kind: \.(line|quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[{line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>canonical(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(canonical)],...commands],expected,name);
}
for(const [key,name] of Object.entries(constants)){
  const value=Number(source.match(new RegExp("const val "+key+" = ([\\d.]+)f"))[1]);
  assert(files[2].includes(name+" = "+value+".0"),key);
}
for(const name of ["sympatheticApproach","sympatheticHandoff","sympatheticExit","cardiacArrival","beatSpacing","vagalDescent","vagalHandoff","vagalExit"]){
  const from=source.match(new RegExp("fun "+name+"\\(t: Float\\) = ([^\\n]+)"))[1];
  const to=files[0].match(new RegExp("static func "+name+"\\(_ t: Double\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(to),norm(from),name);
}
for(const kind of ["callout","leader"]){
  const expected=[...source.matchAll(new RegExp(kind+"\\(c, string.health_atlas_(\\w+), ([^)]+)\\)","g"))].map(m=>[m[1],...m[2].split(",").map(canonical)]);
  const method=kind==="callout"?"autonomicCallout":"autonomicLeader";
  const actual=[...all.matchAll(new RegExp(method+'\\("([^"]+)", ([^)]+)\\)',"g"))].map(m=>[m[1],...m[2].split(",").map(canonical)]);
  assert.deepEqual(actual,expected,kind+" stage anchors");
}
const labels=[...source.matchAll(/label\(c, string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(canonical)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(canonical)]);
assert.equal(labels.length,3);assert.deepEqual(nativeLabels.sort(),labels.sort(),"comparison/beat labels");
for(const key of new Set([...source.matchAll(/string.health_atlas_(\w+)/g)].map(m=>m[1])))for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const [swift,kotlin] of [
  ["segment(t, 0.08, 0.95) * 0.64","segment(t, .08f, .95f) * .64f"],
  ["segment(t, 0.18, 0.9) * 0.86","segment(t, .18f, .9f) * .86f"],
  ["(safe(t) - start) / (end - start)","(HealthAtlasFunctionStory.safePhase(t) - start) / (end - start)"],
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["4 * f * (1 - f)","4f * f * (1f - f)"],
  ["0.83 * phase + 0.38","(.83f * it + .38f) % 1f"],
  ["1.10 * phase + 0.12","(1.10f * it + .12f) % 1f"],
  ["1 - abs(phase - split) / 0.08","1f - kotlin.math.abs(phase - split) / .08f"],
  ["phase / split : (phase - split) / (1 - split)","phase / split else (phase - split) / (1f - split)"],
  ["(arrival - 0.83) / 0.17","(arrival - .83f) / .17f"],
  ["(exit - 0.76) / 0.24","(exit - .76f) / .24f"],
  ["first ? 3.5 : 2.15","if (first) 3.5f else 2.15f"],
  ["width + 2.7","width + 2.7f"],
  ["max(0, fraction - 0.18)","(fraction - .18f).coerceAtLeast(0f)"],
  ["8 + 5 * activity","8f + 5f * activity"],
  ["2.25 + activity","2.25f + activity"],
  ["5.8 + 2.8 * activity","5.8f + 2.8f * activity"],
  ["(t * 2.4).truncatingRemainder(dividingBy: 1) * spacing","(t * 2.4f % 1f) * spacing"],
  ["x < left + 7 || x > right - 13","x < left + 7f || x > right - 13f"],
  ["width - 2.5","width - 2.5f"],
  ["ty > y ? y + 5 : y - 14","if (ty > y) y + 5f else y - 14f"],
  ["local.translateBy(x: 139, y: 140)","c.translate(139f, 140f)"],
  ["local.scaleBy(x: 1.37, y: 1.37)","c.scale(1.37f, 1.37f)"],
  ["local.translateBy(x: 271, y: 177)","c.translate(271f, 177f)"],
  ["local.scaleBy(x: 0.73, y: 0.73)","c.scale(.73f, .73f)"],
  ["split: 0.29","sympathetic, .29f"],
  ["split: 0.64","vagal, .64f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["596F73","98602F","367B73","9B778B","925E6E","795777","ECD1BF","D9B1AE","F5E8DC","EFE3D7","EFB8AC","CB8391","A2B7C6","DBA09E","C9B7A7","ECD4CB","E1C9B8","E7BFB7","D8AEAC","BE9470"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const token of [
  "guard fraction.isFinite, fraction > 0 else { return }","if fraction < 1 {",
  "mirror.translateBy(x: 360, y: 0); mirror.scaleBy(x: -1, y: 1)","for i in 0...5","for i in 0...8",
  "AutonomicCourseMotion.output(t, vagal: false)","AutonomicCourseMotion.output(t, vagal: true)",
  "AutonomicCourseMotion.sympatheticApproach(t)","AutonomicCourseMotion.sympatheticExit(t)","AutonomicCourseMotion.sympatheticHandoff(t)",
  "AutonomicCourseMotion.cardiacArrival(t)","AutonomicCourseMotion.beatSpacing(t)",
  "AutonomicCourseMotion.vagalDescent(t)","AutonomicCourseMotion.vagalExit(t)","AutonomicCourseMotion.vagalHandoff(t)",
  "AutonomicCourseMotion.ongoing(t, vagal: false)","AutonomicCourseMotion.ongoing(t, vagal: true)",
  "local.translateBy(x: -AutonomicCourseRoutes.saX, y: -AutonomicCourseRoutes.saY)",
  "at(handoff.onFirst ? first.route : second.route, handoff.fraction)","atlas-function-autonomic-relay-art"
])assert(all.includes(token),token);
// These exercise the matched source formulas, not Swift/native execution or physiological timing.
const segment=(t,a,b)=>{const f=Math.min(1,Math.max(0,(t-a)/(b-a)));return f*f*(3-2*f);};
assert.equal(49-17*segment(0,.38,.96),49);assert.equal(49-17*segment(1,.38,.96),32);
for(const split of [.29,.64])for(let i=0;i<=1000;i++){
  const phase=i/1000,f=phase<split?phase/split:(phase-split)/(1-split),handoff=Math.min(1,Math.max(0,1-Math.abs(phase-split)/.08));
  assert(f>=0&&f<=1&&handoff>=0&&handoff<=1);
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "AUTONOMIC_RELAY": GalaxySSIHealthAtlasAutonomicView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 autonomic source audit: eleven exact anatomy paths/eight fibers, ten source anchors, source timing/handoff/transport, separate simultaneous streams, cardiac transforms, beat spacing, finite tails and bilingual callouts. No native compilation/pixels verified.");
