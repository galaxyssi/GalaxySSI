// Pinned geometry/timing/resource checks only; no native compilation or mastication validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasToothMasticationStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","AnatomyData","View","ArchDrawing","ProfileDrawing","FrontDrawing","BiteDrawing","GrindingDrawing","CargoDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasTooth" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];assert.equal(shapes.length,23);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
for(const [name,variable] of [["tongue","frontTongue"],["tongueMidline","tongueMidline"]]){
  const from=source.match(new RegExp(variable+"\\.rewind\\(\\)([\\s\\S]*?)(?:area\\(c, "+variable+"|stroke\\(c, "+variable+")"))[1];
  const to=files[1].match(new RegExp("static func "+name+"\\([\\s\\S]*?var p = Path\\(\\)([\\s\\S]*?)return p"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
assert(files[2].includes("enum Kind: Int { case incisor, canine, premolar, molar }"),"source tooth ordinal order");
for(const [name,kind] of [["halfArch","ArchTooth"],["profile","ProfileTooth"]]){
  const expected=[...source.matchAll(new RegExp(kind+"\\(Tooth.(\\w+), ([^)]+)\\)","g"))].map(m=>[m[1].toLowerCase(),...m[2].split(",").map(s=>Number(norm(s)))]);
  const block=files[2].match(new RegExp("static let "+name+": \\["+kind+"\\] = \\[([\\s\\S]*?)\\n  \\]"))[1];
  const actual=[...block.matchAll(/\.init\(kind: \.(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(s=>Number(s.replace(/\w+: /,"")))]);
  assert.equal(expected.length,7);assert.deepEqual(actual,expected,name+" geometry table");
}
const expectedCrumbs=[...source.match(/private val crumbs = listOf\(([\s\S]*?)\n    \)/)[1].matchAll(/([-\d.]+)f to ([-\d.]+)f/g)].map(m=>m.slice(1).map(Number));
const nativeCrumbs=[...files[2].matchAll(/\(x: ([-\d.]+), y: ([-\d.]+)\)/g)].map(m=>m.slice(1).map(Number));
assert.equal(expectedCrumbs.length,6);assert.deepEqual(nativeCrumbs,expectedCrumbs,"crumb offsets");
const centers=source.match(/frontMolarCenters = floatArrayOf\(([^)]+)\)/)[1].split(",").map(s=>Number(norm(s)));
assert.deepEqual(files[2].match(/frontMolarCenters = \[([^\]]+)\]/)[1].split(",").map(Number),centers);
const strip=s=>norm(s.replaceAll("frame.",""));
const labels=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(strip)]);
const nativeLabels=[...all.matchAll(/toothCallout\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(strip)]);
assert.equal(labels.length,11);assert.deepEqual(nativeLabels.sort(),labels.sort(),"static and moving callout anchors");
for(const [key] of labels)for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["x * x * (3 - 2 * x)","x * x * (3f - 2f * x)"],
  ["ease(t, 0.18, 0.52)","ease(t, .18f, .52f)"],["ease(t, 0.60, 0.93)","ease(t, .60f, .93f)"],
  ["-9 + 8.4 * close - 5 * release","-9f + 8.4f * close - 5f * release"],
  ["ease(t, 0.52, 0.92)","ease(t, .52f, .92f)"],
  ["ease(t, 0.08, 0.31)","ease(t, .08f, .31f)"],["ease(t, 0.31, 0.87)","ease(t, .31f, .87f)"],
  ["-6.8 + 6.1 * close - 3.3 * ease(t, 0.66, 0.96)","-6.8f + 6.1f * close - 3.3f * ease(t, .66f, .96f)"],
  ["(1.65 * t).truncatingRemainder(dividingBy: 1)","(1.65f * t) % 1f"],
  ["ease(cycle, 0.11, 0.46) - ease(cycle, 0.70, 1)","ease(cycle, .11f, .46f) - ease(cycle, .70f, 1f)"],
  ["ease(cycle, 0.28, 0.69) - ease(cycle, 0.75, 1)","ease(cycle, .28f, .69f) - ease(cycle, .75f, 1f)"],
  ["jawX: 10 * shear, jawY: 17 - 16 * close","val jawY = 17f - 16f * close"],
  ["ease(t, 0.24, 0.68)","ease(t, .24f, .68f)"],
  ["ease(t, 0.03, 0.48) - 0.46 * ease(t, 0.79, 1)","ease(t, .03f, .48f) - .46f * ease(t, .79f, 1f)"],
  ["ease(t, 0.19, 0.87)","ease(t, .19f, .87f)"],["ease(t, 0.30, 0.80)","ease(t, .30f, .80f)"],
  ["jawX = 5 * opening, jawY = 12 + 17 * opening","val jawY = 12f + 17f * open"],
  ["x: 198 + 65 * place, y: 202 - 12 * place + jawY * 0.38","202f - 12f * place + jawY * .38f"],
  ["180 + side * (180 - tooth.x)","180f + side * (180f - tooth.x)"],
  ["-side * tooth.angle","-side * tooth.angle"],
  ["Double(tooth.kind.rawValue)","tooth.kind.ordinal"],
  ["Int(160 * strength)","(160f * strength).toLong()"],
  ["Double(alpha + 64) / 255","alpha + 64L"],
  ["local.translateBy(x: 307, y: 136)","c.rotate(angle, 307f, 136f)"],
  ["tooth.x + 4, 211, tooth.w - 2, -tooth.h + 3","tooth.x + 4f, 211f, tooth.w - 2f, -tooth.h + 3f"],
  ["1 - 0.55 * frame.close","1f - .55f * close"],
  ["-11 * frame.separation, 7 * frame.separation","-11f * separation, 7f * separation"],
  ["17 * frame.separation, 3 * frame.separation","17f * separation, 3f * separation"],
  ["-22 * frame.pull, dy = 7 * frame.pull","val dx = -22f * pull"],
  ["t < 0.53 + 0.05 * Double(i + 1)","t < .53f + .05f * (i + 1)"],
  ["274 + frame.jawX * 0.52, y: 176 + frame.jawY * 0.48","274f + jawX * .52f, 176f + jawY * .48f"],
  ["offset.x * (0.57 + 0.48 * frame.breakUp) + (i % 2 == 0 ? frame.shear * 4 : 0)","offset.first * (.57f + .48f * breakUp) + if (i % 2 == 0) shear * 4f else 0f"],
  ["offset.y * (1 - 0.74 * frame.close)","offset.second * (1f - .74f * close)"],
  ["5.8 - 2.1 * frame.breakUp, 5 - 3 * frame.close","5.8f - 2.1f * breakUp, 5f - 3f * close"],
  ["offset.x * (1 - 0.55 * frame.wet), dy = offset.y * (1 - 0.15 * frame.wet)","offset.first * (1f - .55f * wet)"],
  ["local.translateBy(x: 0, y: -0.42 * dy)","c.translate(0f, -.42f * dy)"],
  ["tip = 227 + 34 * reach, lift = 8 * reach","val tip = 227f + 34f * reach"],
  ["edge = 24 - 8 * frame.wet","edge = 24f - 8f * wet"],
  ["Double(Int(frame.wet * 255)) / 255","(wet * 255f).toLong()"],
  ["startAngle: .degrees(197), endAngle: .degrees(197 + 146 * frame.wet)","197f, 146f * wet"],
  ["d: 10.5, tx: frame.x, ty: frame.y - 0.5","x - edge, y - 11f, x + edge, y + 10f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "Double(alpha) / 255","copy(wash).fill(crown, 0x88C8BB)","copy(border).stroke(crown, 0x3B8175, 0.105)",
  "if strength > 0","if t <= 0.52","if t < 0.30","if frame.wet > 0","copy(local).stroke(ellipse, 0x527E8F, 1.8)",
  "focus ? 0xF4FAF1 : 0xFFFCF4","focus ? 0x52676A : 0x8E8073",
  "toothCrown(.molar, x, 150, 54, 24","toothCrown(.molar, x + dx, 210 + dy, 52, -34",
  "toothIncisorBite(t)","toothCanineTear(t)","toothGrindingStroke(t)","toothGatherBolus(t)",
  "atlas-function-tooth-mastication-art"
])assert(all.includes(token),token);
// Source-matched formula checks only; no Swift/native evaluation.
const ease=(t,a,b)=>{const x=Math.min(1,Math.max(0,(t-a)/(b-a)));return x*x*(3-2*x);};
for(let i=0;i<=1000;i++){const t=i/1000,c=(1.65*t)%1,close=ease(c,.11,.46)-ease(c,.70,1),shear=ease(c,.28,.69)-ease(c,.75,1);assert(close>=0&&close<=1&&shear>=0&&shear<=1);assert(17-16*close>=1);const wet=ease(t,.30,.80);assert(24-8*wet>=16);}
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(!/\d+f\b/.test(all),"no Kotlin numeric suffix in Swift");
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "TOOTH_MASTICATION": GalaxySSIHealthAtlasToothView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 tooth source audit: twenty-three exact outlines/two tongue paths, fourteen tooth specs/six crumb offsets, source bite/tear/grind/bolus timing, separate alpha channels, fixed jaw pivot, constant-width saliva ellipse and eleven bilingual anchors. No native compilation/pixels verified.");
