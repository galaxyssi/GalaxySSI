// Pinned formula/geometry wiring only; not native Path execution or physiological acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasUrineRouteStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasUrineMotion.swift"),view=local("GalaxySSIHealthAtlasUrineView.swift"),channel=local("GalaxySSIHealthAtlasUrineChannelDrawing.swift"),overview=local("GalaxySSIHealthAtlasUrineOverviewDrawing.swift"),flow=local("GalaxySSIHealthAtlasUrineFlowDrawing.swift"),all=motion+view+channel+overview+flow;
const arc=source.match(/fun Path\.arcFromPelvis\(\) \{([^}]+)\}/)[1];
for(const name of ["overviewUreter","pelvisRoute","ureter","tunnel","junctionExit","inlet","outlet"]){
  const block=source.match(new RegExp("private val "+name+" = (?:Channel\\(|track\\()?Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].replace("arcFromPelvis()",arc).matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const c=JSON.parse("["+motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"))[1]+"]");
  assert.deepEqual([[c[0],c[1]],...c.slice(2)],expected,name);
}
for(const name of ["kidney","medulla","calyces","junctionWall"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"||m[1]==="addQuadCurve"?[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["0.23 + 0.73 * safe(t)",".23f + .73f * t"],["pinch = front - 0.16","pinch = front - .16f"],
  ["11 + 5 * bump(fraction - front, span: 0.13) - 8 * bump(fraction - pinch, span: 0.12)","11f + 5f * bump(f - front, .13f) - 8f * bump(f - pinch, .12f)"],
  ["0.10 + 1.06 * ease(t)",".10f + 1.06f * ease(t)"],
  ["8 - 6 * ease((fraction - 0.4) / 0.55) * (1 - bump(fraction - junctionFront(time) + 0.06, span: 0.19))","8f - 6f * ease((f - .4f) / .55f) * (1f - bump(f - front + .06f, .19f))"],
  ["ease(t / 0.22) * (1 - GalaxySSIHealthAtlasUrineMotion.ease((t - 0.89) / 0.11))","ease(t / .22f) * (1f - ease((t - .89f) / .11f))"],
  ["ease((t - 0.14) / 0.80)","ease((t - .14f) / .80f)"],
  ["79 + 34 * size","79f + 34f * size"],["134 - 62 * size","134f - 62f * size"],
  ["111 + 149 * drain : 196 - 85 * size","111f + 149f * drain else 196f - 85f * size"],
  ["(relaxed - 0.35) * (1 - open)","(relaxed - .35f) * (1f - open)"],
  ["bump(f - 0.43, span: 0.32)","bump(f - .43f, .32f)"],
  ["max(from, front - length)","maxOf(from, front - length)"],["end = min(1, front)","minOf(1f, front)"],
  ["Int((pinch * 64).rounded())","(pinch * SAMPLES).roundToInt()"],
  ["x: 180 - half, y: (top + base) / 2","180f - half, (top + base) / 2f"],
  ["x: 180 + half, y: (top + base) / 2","180f + half, (top + base) / 2f"],
  ["front: (front - 1) * 5.4","(front - 1f) * 5.4f"],["width * 0.61","width * .61f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["for i in 0...64", "position: Double(i) / 64", "let radii = (0...64).map", "i = side < 0 ? j : 64 - j",
  "Double(sample.point.x) - r * Double(sample.direction.dy)","Double(sample.point.y) + r * Double(sample.direction.dx)",
  "(9, 0xE9B0AB, Self.coral)","(3.5, 0xF7D7C2, 0xC68B87)","(0, Self.cream, 0xBC8680)","start < end ? (start, end) : nil",
  "case 0: art.urineOverview(t)","case 1: art.urinePeristalsis(t)","case 2: art.urineJunction(t)","emptying: step == 4",
  "liquid.clip(to: lumen)","if emptying && frame.open > 0.8 && frame.drain < 1", "width: 6 * frame.open, from: 0.13",
  "if !emptying", "local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1)"])assert(all.includes(token),token);
const bladder=view.match(/static func bladder[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert(!bladder.includes("closeSubpath"),"Source bladder neck stays open");assert.equal((bladder.match(/addCurve/g)||[]).length,4);
for(const color of ["F8D2CB","D58C9E","F8DDD4","DEA1A9","FFE7A7","E7B568","E9B0AB","F7D7C2","C68B87","BC8680","B37532","F3C56C","776C72"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(urine_route_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-urine-route-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "URINE_ROUTE": GalaxySSIHealthAtlasUrineView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["UrineMotion","UrineView","UrineChannelDrawing","UrineOverviewDrawing","UrineFlowDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 urine source audit: seven tracks/four source outlines, 65-sample deforming channels, peristaltic pinch/tunnel gating, reservoir/outlet timing, clipped pulse intervals, mirrored lower inlets and bilingual labels. No native compilation/pixels verified.");
