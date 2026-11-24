// Pinned geometry/timing/resource checks only; no native compilation or secretion validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSebaceousStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Geometry","Motion","View","SkinDrawing","LobuleDrawing","CellDrawing"].map(n => "GalaxySSIHealthAtlasSebaceous" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
for (const name of ["skin","skinSurface","skinEdge","follicleWall","shaft","locatorGland","canal","lobule","duct"]) {
  const from = source.match(new RegExp("private val " + name + " = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to = files[0].match(new RegExp("static let " + name + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to), fromCommands(from), name);
  if (["canal","duct"].includes(name)) {
    const block = files[0].match(new RegExp("static let "+name+"Track = ([\\s\\S]*?)\\n  \\]\\)"))[1];
    const start = block.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
    const cmds = [...block.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m => [m[1]==="quad"?"quadTo":"cubicTo", ...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
    assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...cmds],fromCommands(from),name+" particle track");
  }
}
for (const [name,count] of [["locatorCells",3],["basal",14],["mature",11],["lipidLocations",6]]) {
  const marker = "private val "+name+" = listOf(";
  const start = source.indexOf(marker) + marker.length;
  assert(start >= marker.length, name);
  let end = start, depth = 1;
  for (; end < source.length && depth; end++) {
    if (source[end] === "(") depth++;
    if (source[end] === ")") depth--;
  }
  assert.equal(depth, 0, name+" balanced point list");
  const block = source.slice(start, end - 1);
  const expected = [...block.matchAll(/Point\(([-.\d]+)f, ([-.\d]+)f\)/g)].map(m=>m.slice(1).map(Number));
  const local = files[0].match(new RegExp("static let "+name+": \\[CGPoint\\] = \\[([\\s\\S]*?)\\n  \\]"))[1];
  const actual = [...local.matchAll(/CGPoint\(x: ([-.\d]+), y: ([-.\d]+)\)/g)].map(m=>m.slice(1).map(Number));
  assert.equal(expected.length,count,name+" source count");assert.deepEqual(actual,expected,name);
}
for (const kind of ["label","leader"]) {
  const expected = [...source.matchAll(new RegExp(kind+"\\(c, R.string.health_atlas_(\\w+), ([^)]+)\\)","g"))].map(m=>[m[1],...m[2].split(",").map(norm)]);
  const actual = [...all.matchAll(new RegExp((kind==="leader"?"sebaceousLeader":"label")+'\\("([^"]+)", ([^)]+)\\)',"g"))].map(m=>[m[1],...m[2].split(",").map(norm)]);
  assert.deepEqual(actual.sort(),expected.sort(),kind+" anchors");
  for (const [key] of expected) for (const language of ["en","zh-Hans"]) assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for (const [swift,kotlin] of [
  ["t * t * (3 - 2 * t)","t * t * (3f - 2f * t)"],
  ["(t + Double(index) * 0.24).truncatingRemainder(dividingBy: 1) * 0.93 + 0.02","((t + i * .24f) % 1f) * .93f + .02f"],
  ["min(0.95, eased(t) * 0.74 + Double(index) * 0.072)","(open * .74f + index * .072f).coerceAtMost(.95f)"],
  ["(t * 0.78 + Double(index) / 4).truncatingRemainder(dividingBy: 1) * 0.93 + 0.03","((t * .78f + i / 4f) % 1f) * .93f + .03f"],
  ["min(1, max(0, stored * 1.32 - Double(index) * 0.12))","(stored * 1.32f - index * .12f).coerceIn(0f, 1f)"],
  ["step == 1 && index == 3","step == 1 && index == 3"],
  ["(2...3).contains(step) && index == 9","step in 2..3 && index == 9"],
  ["8.1 + Double(index % 3), 0.36 + Double(index % 4) * 0.14","8.1f + index % 3, .36f + index % 4 * .14f"],
  ["1.2 + 6 * t","1.2f + 6f * t"],
  ["266 - spread, 94, 4.3, 0, 1","266f - spread, 94f, 4.3f, 0f, 1f"],
  ["266 + spread, 96 + 7 * t, 4.3 + t, 0.18 * t, 1","266f + spread, 96f + 7f * t, 4.3f + t, .18f * t, 1f"],
  ["266 + 6 * focus, 129 + 31 * focus, 7.4 + 6 * focus, focus, 1","266f + 6f * focus, 129f + 31f * focus, 7.4f + 6f * focus, focus, 1f"],
  ["261 - 13 * open, y = 151 + 23 * open","val x = 261f - 13f * open"],
  ["sebaceousCell(x, y, 13.2, 0.92, 1 - open)","cell(c, x, y, 13.2f, .92f, 1f - open)"],
  ["2.4 + Double(index % 2) * 0.7","2.4f + (index % 2) * .7f"],
  ["Double(Int(255 * intact)) / 255","(255f * intact).toLong()"],
  ["radius * (0.31 - 0.16 * stored)","radius * (.31f - .16f * stored)"],
  ["radius * (0.05 + 0.16 * volume)","radius * (.05f + .16f * volume)"],
  ["baseline + (targetY > baseline ? 6 : -16)","baseline + if (targetY > baseline) 6f else -16f"],
  ["18 + 12 * t","18f + 12f * t"],
  ["startAngle: .degrees(-100)","-100f"],
  ["endAngle: .degrees(-100 + 130 + t * 220)","130f + t * 220f"],
  ["width: 31 + t * 4, height: 24 + t * 2","251f - t * 2f, 84f, 282f + t * 2f, 108f + t * 2f"]
]) {assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for (const color of ["F7D9CA","ECC2BB","F1BAB0","CF8994","FFEAD0","E2B99E","99696B","668181","875344","D69742","9B651E","9773A0","C29390","EDAAA6","CF999C","D39389","AE7858","FFE4AE","CF9C62","E6BB7F","EED39E","D7A8B6","F6D6AD","C0843F"]) {
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for (const token of ["clipped.clip(to: Geometry.skin)","guard intact > 0 else { return }","if step == 4 {","for i in 0...3","atlas-function-sebaceous-art","Motion.release(t, index)","Motion.duct(t, i)"]) assert(all.includes(token),token);
assert.equal((all.match(/for i in 0\.\.\.3/g)||[]).length,2);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SEBUM_RELEASE": GalaxySSIHealthAtlasSebaceousView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names) assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 sebaceous source audit: nine exact paths/two particle tracks, all 34 cell/lipid positions, five-stage cell replacement/maturation/holocrine fade and transport, clipped locator, arc/oval cues and bilingual anchors. No native compilation/pixels verified.");
