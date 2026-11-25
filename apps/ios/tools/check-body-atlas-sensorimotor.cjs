// Pinned geometry/timing/resource checks only; no native compilation or sensorimotor validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCerebralSensorimotorStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","AnatomyDrawing","ArmDrawing","SignalDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasSensorimotor" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const pathNames = [...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(pathNames.length,17);
for (const [,name,block] of pathNames) {
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
for (const name of ["centralSulcus","plansAcross","plansBack","touchPath","commandPath"]) {
  const from=fromCommands(pathNames.find(m=>m[1]===name)[2]);
  const block=files[2].match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const start=block.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[m[1]==="quad"?"quadTo":"cubicTo",...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],from,name+" cached track");
}
const dynamic=source.match(/positionPath.moveTo\(([\s\S]*?)positionTrack.setPath/)[1];
const expected=[["moveTo","x","y"],...fromCommands(dynamic)];
const block=files[2].slice(files[2].indexOf("static func position"));
const start=block.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
const commands=[...block.matchAll(/\.init\(kind: \.cubic, points: \[([^\]]+)\]/g)].map(m=>["cubicTo",...[...m[1].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
const normalized=expected.map(c=>c.map(v=>v.replace("positionPath.","")));
assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],normalized,"dynamic proprioceptive track");
for (const name of ["tissueTrace","touch","position","planning","reply","preview","command","ongoingInput","ongoingOutput"]) {
  const sourceBody=source.match(new RegExp("fun "+name+"\\(t: Float\\) = ([^\\n]+)"))[1];
  const nativeBody=files[0].match(new RegExp("static func "+name+"\\(_ t: Double\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(nativeBody),norm(sourceBody),name+" window");
}
for (const [swift,kotlin] of [
  ["midReach = 0.52","MID_REACH = .52f"],
  ["midReach * ease(window(t, 0.19, 1))","MID_REACH * ease(window(t, .19f, 1f))"],
  ["midReach + (1 - midReach) * ease(window(t, 0, 0.94))","MID_REACH + (1f - MID_REACH) * ease(window(t, 0f, .94f))"],
  ["218 + 56 * reach","218f + 56f * reach"],
  ["277 - 2 * reach - 22 * sin(.pi * reach)","277f - 2f * reach - 22f * sin(PI * reach)"],
  ["(safe(t) - from) / (to - from)","(HealthAtlasFunctionStory.safePhase(t) - from) / (to - from)"],
  ["max(0, safe(t) - delay).truncatingRemainder(dividingBy: period) / period","((HealthAtlasFunctionStory.safePhase(t) - delay).coerceAtLeast(0f) % period) / period"],
  ["t * t * (3 - 2 * t)","t * t * (3f - 2f * t)"],
  ["sx = 41.0, sy = 266.0, upper = 88.0, lower = 151.0","val upper = 88f"],
  ["(distance * distance + upper * upper - lower * lower) / (2 * distance)","(distance * distance + upper * upper - lower * lower) / (2f * distance)"],
  ["sqrt(max(0, upper * upper - along * along))","sqrt((upper * upper - along * along).coerceAtLeast(0f))"],
  ["sx + (dx * along - dy * bend) / distance","sx + (dx * along - dy * bend) / distance"],
  ["sy + (dy * along + dx * bend) / distance","sy + (dy * along + dx * bend) / distance"],
  ["sx + (ex - sx) * 0.69","sx + (ex - sx) * .69f"],
  ["sy + (ey - sy) * 0.69","sy + (ey - sy) * .69f"],
  ["for i in 1...20","for (i in 1..20)"],
  ["progress * Double(i) / 20","progress * i / 20f"],
  ["lineWidth: dashed ? 1.7 : 1.25","if (dashed) 1.7f else 1.25f"],
  ["dash: [3.5, 3.5], dashPhase: 0","DashPathEffect(floatArrayOf(3.5f, 3.5f), 0f)"],
  ["max(0, 1 - 7 / length)","(1f - 7f / measure.length).coerceAtLeast(0f)"],
  ["4.6 * min(1, min(progress * 9, (1 - progress) * 9))","4.6f * minOf(1f, progress * 9f, (1f - progress) * 9f)"],
  ["radius >= 0.6","radius >= .6f"],
  ["frame.reach > 0.96","reach > .96f"],
  ["y + (kneeY >= y ? 4 : -14)","y + if (kneeY >= y) 4f else -14f"]
]) {assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
const sourceLabels=[...source.matchAll(/leader\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/sensorimotorLeader\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(sourceLabels.length,11);assert.deepEqual(nativeLabels.sort(),sourceLabels.sort(),"stage/anatomy label anchors");
for(const [key] of sourceLabels) for(const language of ["en","zh-Hans"]) assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of ["65747B","8A5968","9B4945","386C8B","A3723C","4D796A","5A688E","FFDECA","E3AB94","FFE6D9","E3ADB5","E6EFDC","AFC5A4","B9D6D1","80A8A2","CAD2C8","EBC99B","BBD6BF","DB9A8E","B0CAD9","B47F85","BDC8B7","B7C4B6","CBDAC0","EFF2DC","C5D3B3","8CA189","C18476"]) {
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const token of [
  "guard progress.isFinite, progress > 0, progress < 1 else { return }",
  "GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360)",
  "upper.rotate(by: .radians(frame.upperAngle))","lower.rotate(by: .radians(frame.lowerAngle))",
  "upperAngle = atan2(ey - sy, ex - sx)","lowerAngle = atan2(finger.y - ey, finger.x - ex)",
  "sensorimotorPulse(Routes.centralSulcus, Motion.tissueTrace(t), 0x8A5968)",
  "sensorimotorInput(frame.position.x, frame.position.y, Motion.position(t))",
  "sensorimotorSignal(Routes.touchPath, Motion.touch(t), 0x386C8B)",
  "sensorimotorSignal(Routes.plansAcross, Motion.planning(t), 0x4D796A)",
  "sensorimotorSignal(Routes.plansBack, Motion.reply(t), 0xA3723C)",
  "sensorimotorSignal(Routes.commandPath, Motion.command(t), 0x9B4945)",
  "sensorimotorInput(frame.position.x, frame.position.y, Motion.ongoingInput(t))",
  "sensorimotorSignal(Routes.commandPath, Motion.ongoingOutput(t), 0x9B4945)",
  "sensorimotorReach(Motion.preview(t), dashed: true)","sensorimotorReach(frame.reach, dashed: false)",
  "atlas-function-cerebral-sensorimotor-art"
]) assert(all.includes(token),token);
// Numeric checks cover the matched source formulas, not execution of Swift or native Path.
const ease=t=>t*t*(3-2*t),window=(t,a,b)=>Math.min(1,Math.max(0,(t-a)/(b-a)));
const reach=(chapter,t)=>chapter===3?.52*ease(window(t,.19,1)):chapter===4?.52+.48*ease(window(t,0,.94)):0;
assert.equal(reach(3,1),reach(4,0));assert.equal(reach(4,1),1);
for(let i=0;i<=1000;i++){
  const r=i/1000,x=218+56*r,y=277-2*r-22*Math.sin(Math.PI*r),dx=x-41,dy=y-266,d=Math.hypot(dx,dy);
  const along=(d*d+88*88-151*151)/(2*d),bend=Math.sqrt(Math.max(0,88*88-along*along));
  const ex=41+(dx*along-dy*bend)/d,ey=266+(dy*along+dx*bend)/d;
  assert(Math.abs(Math.hypot(ex-41,ey-266)-88)<1e-8);
  assert(Math.abs(Math.hypot(x-ex,y-ey)-151)<1e-8);
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CEREBRAL_SENSORIMOTOR": GalaxySSIHealthAtlasSensorimotorView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names) assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 sensorimotor source audit: seventeen exact paths, five cached/dynamic position tracks, nine timing windows, continuous two-stage reach, fixed-length arm formulas, dashed direction arrows/pulse gates and eleven bilingual anchors. No native compilation/pixels verified.");
