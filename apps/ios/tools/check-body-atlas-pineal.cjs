// Pinned geometry/timing/resource checks only; no native compilation or pineal validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPinealStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["GalaxySSIHealthAtlasPinealGeometry.swift","GalaxySSIHealthAtlasPinealRoutes.swift","GalaxySSIHealthAtlasPinealMotion.swift","GalaxySSIHealthAtlasPinealView.swift","GalaxySSIHealthAtlasPinealGlyphDrawing.swift","GalaxySSIHealthAtlasPinealInputDrawing.swift","GalaxySSIHealthAtlasPinealRelayDrawing.swift","GalaxySSIHealthAtlasPinealProduceDrawing.swift","GalaxySSIHealthAtlasPinealRhythmDrawing.swift","GalaxySSIHealthAtlasPinealLabelsDrawing.swift"];
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});


const geometry=local("GalaxySSIHealthAtlasPinealGeometry.swift"),routeFile=local("GalaxySSIHealthAtlasPinealRoutes.swift");
const shapes=[...source.matchAll(/private val (\w+) = path \{([^}]+)\}/g)].filter(m=>m[1]!=="curve");
assert.equal(shapes.length,10);
for(const [,name,body] of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
const relays=[...source.match(/private val relays = listOf\(([\s\S]*?)\n    \)/)[1].matchAll(/path \{([^}]+)\}/g)].map(m=>m[1]);
assert.equal(relays.length,4);
const rays=[-1,0,1].map(i=>"moveTo(15f, "+(170+i*7)+"f); lineTo(51f, "+(170+i*6)+"f); lineTo("+(i===1?128:132)+"f, "+(166-i*9)+"f)");
assert(source.includes("170f + i * 7f")&&source.includes("170f + i * 6f")&&source.includes("166f - i * 9f")&&source.includes("if (i == 1) 128f else 132f"));
const routes=[["retinaTrack",shapes.find(m=>m[1]==="retinaFiber")[2]],
 ...rays.map((b,i)=>["ray"+i,b]),...relays.map((b,i)=>["relay"+i,b]),
 ["outgoing",source.match(/private val outgoing = track\(path \{([^}]+)\}/)[1]]];
for(const [name,body] of routes){
 const native=routeFile.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
 const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
 const cmds=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind: \.(line|quad|cubic), points: \[([^\n]+)\]/g)].map(m=>[
 {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))])];
 assert.deepEqual(cmds,fromCommands(body),name);
}
for(const [swift,kotlin] of [
 ["0.22+0.11*Double(i), 0.55+0.12*Double(i)",".22f + .11f * index, .55f + .12f * index"],
 ["0.03+0.22*Double(i), 0.24+0.22*Double(i)",".03f + .22f * index, .24f + .22f * index"],
 ["0.025+0.04*Double(i), 0.23+0.04*Double(i)",".025f + .04f * index, .23f + .04f * index"],
 ["0.29+0.21*Double(i), 0.49+0.21*Double(i)",".29f + .21f * index, .49f + .21f * index"],
 ["0.71+0.052*Double(i), 0.89+0.052*Double(i)",".71f + .052f * index, .89f + .052f * index"],
 ["0.08+0.82*ease(t, 0.29, 0.45)*(1-ease(t, 0.64, 0.81))",".08f + .82f * ease(t, .29f, .45f) * (1f - ease(t, .64f, .81f))"],
 ["f*f*(3-2*f)","f * f * (3f - 2f * f)"],
 ["0.91+0.57*zoom",".91f + .57f * zoom"], ["242-32*zoom-249*size","242f - 32f * zoom - 249f * size"],
 ["180-146*size","180f - 146f * size"], ["min(1, t*2.55)","(t * 2.55f).coerceAtMost(1f)"],
 ["4.7+2.1*arrival","4.7f + 2.1f * arrival"], ["191-Double(i)*2.1+Double(i*i)*0.23","191f - i * 2.1f + i * i * .23f"],
 ["0.63+8/track.length",".63f + 8f / route.length"], ["if f > 0 && f < 1","if (f > 0f && f < 1f)"],
 ["f*(1-0.10*Double(i))","f * (1f - .10f * i)"], ["first >= 0.98","first >= .98f"], ["second >= 0.98","second >= .98f"],
 ["x-Double(i)*(1-f)","x - i * (1f - f)"], ["34+292*t","34f + 292f * t"], ["269-145*GalaxySSIHealthAtlasPinealMotion.melatonin(t)","269f - 145f * HealthAtlasPinealMotion.melatonin(t)"]
]) {assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 "let length: Double", "GalaxySSIHealthAtlasCurveLength.route(route", "min(0.94, 0.63+8/track.length)",
 "for i in 0...110", "Double(i)/110", "p.addLine(to: CGPoint(x: 326, y: 269))",
 "p.addLine(to: CGPoint(x: 34, y: 269))", "for y in stride(from: 151.0, through: 241, by: 30)",
 "CGRect(x: 12, y: 45, width: 336, height: 248)", 'Image("HealthAtlasFunctionPineal")',
 "width: 360, height: 280", "startAngle: .degrees(168), endAngle: .degrees(300), clockwise: false",
 "CGAffineTransform(a: 7.5, b: 0, c: 0, d: 8, tx: 89.5, ty: 154)",
 "0xF0F1F9 : 0xF8FBFC", "0xE7F1F3 : 0xE7F1F1",
 'accessibilityIdentifier("atlas-function-pineal-dark-signal-art")'
])assert(all.includes(token),token);
const labels=local("GalaxySSIHealthAtlasPinealLabelsDrawing.swift");
const calls=[...source.matchAll(/(leader|label)\(c, R.string.health_atlas_(\w+),([\s\S]*?)\)/g)];
assert.equal(calls.length,25);
for(const [,fn,key,args]of calls){
 const values=args.replace(/(\d)f\b/g,"$1").replace(/\bsX\b/g,"108").replace(/\bnX\b/g,"159").replace(/\bmX\b/g,"210");
 assert(norm(labels).includes(norm((fn==="leader"?"pinealLeader":"label")+'("'+key+'",'+values+')')),key);
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),lang+":"+key);
}
const ease=(t,a,b)=>{const f=Math.min(1,Math.max(0,(t-a)/(b-a)));return f*f*(3-2*f);};
const mel=t=>.08+.82*ease(t,.29,.45)*(1-ease(t,.64,.81));
assert.equal(mel(0),.08);assert.equal(mel(1),.08);assert(Math.abs(mel(.5)-.9)<1e-12);
const windows=[[.22,.11,.55,.12,3],[.03,.22,.24,.22,4],[.025,.04,.23,.04,3],[.29,.21,.49,.21,2],[.71,.052,.89,.052,3]];
for(const[a,da,b,db,n]of windows)for(let i=0;i<n;i++){
 const start=a+da*i,end=b+db*i;
 assert.equal(ease(start,start,end),0);assert.equal(ease(end,start,end),1);
 assert(Math.abs(ease((start+end)/2,start,end)-.5)<1e-12);
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"));
const story=data.stories.find(s=>s.id==="PINEAL_DARK_SIGNAL");assert.equal(story.durationMs,20000);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["orient","retina","relay","production","rhythm"]);
assert.equal(story.references.length,6);
assert.deepEqual(story.owners,["pineal-gland","cell-pinealocyte"]);assert.equal(data.entryPhases["cell-pinealocyte"].PINEAL_DARK_SIGNAL,.6);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PINEAL_DARK_SIGNAL": GalaxySSIHealthAtlasPinealView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){
 assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);
 assert(Buffer.byteLength(local(name))<16000,name);
}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-pineal"],{cwd:root,stdio:"inherit"});
console.log("Android #4384 pineal: 10 exact fixed paths, 9 ordered cached tracks, 25 bilingual placements, relative rhythm/source timing and original vector plate checked; no native compilation/pixels verified.");
