// Pinned geometry/timing/resource checks only; no native compilation or Club cell validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasClubCellStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","OverviewDrawing","WallDrawing","SecretionDrawing","RenewalDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasClub" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const edge=source.match(/private fun filmEdge\(p: Path\) = with\(p\) \{([^}]+)\}/)[1];
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,12);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block.replaceAll("filmEdge(this)",edge)),name);
}
const renewal=source.match(/renewal.rewind\(\)([\s\S]*?)ink\(cream\)/)[1];
const nativeRenewal=files[1].match(/static func renewal[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(nativeRenewal),fromCommands(renewal),"dynamic renewal outline");
const cilium=source.match(/private fun cilium[\s\S]*?ciliaStroke.rewind\(\)([\s\S]*?)stroke\(c, ciliaStroke/)[1];
const nativeCilium=files[5].match(/func clubCilium[\s\S]*?var p = Path\(\)([\s\S]*?)stroke\(p/)[1];
assert.deepEqual(toCommands(nativeCilium),fromCommands(cilium),"shared cilium curve");
const expectedRoutes=[...source.matchAll(/track\(Path\(\).apply \{([^}]+)\}/g)].map(m=>fromCommands(m[1]));
const nativeRoutes=[...files[2].matchAll(/Route\(start: ([\s\S]*?)\n    \]\)/g)].map(m=>{
  const start=m[1].match(/\.init\(x: ([^,]+), y: ([^)]+)\)/);
  const cmds=[...m[1].matchAll(/\.init\(kind: \.(line|quad|cubic), points: \[([^\]]+)\]/g)].map(c=>[{line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[c[1]],...[...c[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  return [["moveTo",...start.slice(1).map(norm)],...cmds];
});
assert.equal(expectedRoutes.length,5);assert.deepEqual(nativeRoutes,expectedRoutes,"indexed release/spread routes");
for(const m of source.matchAll(/fun (\w+)\(t: Float(?:, index: Int)?\) = (ease\([^\n]+\))/g)){
  const indexed=m[0].includes("index: Int");
  const native=files[0].match(new RegExp("static func "+m[1]+"\\(_ t: Double"+(indexed?", _ index: Int":"")+"\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(native.replaceAll("Double(index)","index")),norm(m[2]),m[1]+" timing");
}
const flags=s=>{
  const values=s.split(",").map(v=>norm(v.replace("belowText: ","")));
  if(!["true","false"].includes(values.at(-1)))values.push("false");
  return values;
};
const leaders=[...source.matchAll(/leader\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...flags(m[2])]);
const nativeLeaders=[...all.matchAll(/clubLeader\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...flags(m[2])]);
assert.equal(leaders.length,17);assert.deepEqual(nativeLeaders,leaders,"leader polarity and anchors");
const labels=[...source.matchAll(/label\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(labels.length,1);assert.deepEqual(nativeLabels,labels,"mouse-specific lineage label");
for(const [key] of [...leaders,...labels])for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
const cells=[...source.matchAll(/drawCiliatedCell\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm)).sort();
const nativeCells=[...all.matchAll(/clubCiliatedCell\(([^_][^)]+)\)/g)].map(m=>m[1].replace(/(?:width|phase): /g,"").split(",").map(norm)).sort();
assert.equal(cells.length,4);assert.deepEqual(nativeCells,cells,"human/mouse neighbor dimensions and cilia phase");
const positions=source.match(/clubPositions = setOf\(([^)]+)\)/)[1].split(",").map(Number);
assert.deepEqual(files[1].match(/clubPositions: Set<Int> = \[([^\]]+)\]/)[1].split(",").map(Number),positions);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["local.translateBy(x: 150, y: 184)","c.translate(150f, 184f)"],
  ["local.scaleBy(x: 1, y: 0.92)","c.scale(1f, .92f)"],
  ["Double(i) * 22.5","i * 22.5f"],
  ["166 - 91 * scan","166f - 91f * scan"],
  ["endAngle: .degrees(166 - 91 * scan + 30)","166f - 91f * scan, 30f"],
  ["10 * wave(phase + offset * 0.025) + 2","10f * wave(phase + offset * .025f) + 2f"],
  ["offset * 6.3, 189 + offset * offset * 0.045","offset * 6.3f, 189f + offset * offset * .045f"],
  ["length: 16 - Double(i % 3)","16f - i % 3"],
  ["if dock < 0.98","if (dock < .98f)"],
  ["182 - 6 * dock, 193 - 35 * dock, 6.5","182f - 6f * dock, 193f - 35f * dock, 6.5f"],
  ["dock >= 0.98 && exported < 0.94","dock >= .98f && exported < .94f"],
  ["if progress > 0","if (progress > 0f)"],
  ["0.04 + 0.10 * Double(i / 2) + (0.45 + 0.06 * Double(i)) * travel",".04f + .10f * (i / 2) + (.45f + .06f * i) * travel"],
  ["Double(i / 2 - 1) * 3","(i / 2 - 1) * 3f"],
  ["187 + 52 * expansion, joinY = 171 + 20 * mature, shoulderY = 159 + 32 * mature","val right = 187f + 52f * expansion"],
  ["joinY + (253 - joinY) * division","joinY + (253f - joinY) * division"],
  ["Double(Int(255 * mature)) / 255","(255f * mature).toInt()"],
  ["right - 161, height: 254 - top","right + 2f, 254f"],
  ["min(joinY, shoulderY)","minOf(joinY, shoulderY)"],
  ["171 + Double(i) * 6.4, y = 191 - (191 - shoulderY) * 0.64","191f - (191f - shoulderY) * .64f"],
  ["length: 16 * mature, bend: 3 + 3 * mature","16f * mature, 3f + 3f * mature"],
  ["nucleusX = 142 - 17 * division","nucleusX = 142f - 17f * division"],
  ["143 + (right - 162) * 0.75 * division, r = 12 * division","143f + (right - 162f) * .75f * division"],
  ["baseline + (belowText ? 5 : -11)","baseline + if (belowText) 5f else -11f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "for i in 0...15","Geometry.clubPositions.contains(i)","clubHumanWall(GalaxySSIHealthAtlasClubMotion.cilia(t))",
  "clubHumanWall(0.3)","clubHumanWall(0.44)","clubProtein(176, 141)","for i in 0...5",
  "local.clip(to: renewal)","CGRect(x: 163, y: top, width: right - 161, height: 254 - top)",
  "line(163, 253, 163, boundary","line(163, 253, 163, joinY","for i in 0...9",
  "clubGranule(125, 178, 4)","clubGranule(133, 191, 3.5)","clubRenew(t)","atlas-function-club-cell-airway-art"
])assert(all.includes(token),token);
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CLUB_CELL_AIRWAY": GalaxySSIHealthAtlasClubView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 Club source audit: twelve exact outlines/dynamic renewal/cilium, five ordered routes, eight timing windows, sixteen-cell rim identity, pore gating and indexed spread, clipped lineage differentiation and retained mouse-specific bilingual label. No native compilation/pixels verified.");
