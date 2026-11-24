// Pinned source geometry/formulas only; not native compilation or perfusion validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCoronaryStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","Routes","View","StreamDrawing","HeartDrawing","WallDrawing","RootReturnDrawing"].map(n=>"GalaxySSIHealthAtlasCoronary"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1],routes=files[2];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["arch","venaCava","pulmonaryTrunk","heart","lvSurface","atrialGroove","rootCusp","rootSection","rootValve","posteriorHeart","posteriorAtrium","exposedRoot","wallSlice"]){
  const from=["exposedRoot","wallSlice"].includes(name)?source.match(new RegExp("private fun "+(name==="exposedRoot"?"drawHeart":"drawWall")+"[\\s\\S]*?detail.rewind\\(\\)([\\s\\S]*?)detail.close\\(\\)"))[1]+"close()":source.match(new RegExp("private val "+name+" = shape \\{([^}]+)\\}"))[1];
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const nativeTrack=block=>{
  const first=block.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))
  ]);
  return [["moveTo",norm(first[1]),norm(first[2])],...commands];
};
const named=["rightCoronary","rightBranch","leftMain","descending","circumflex","diagonal","anteriorVein","cardiacVein","tributary","coronarySinus","arteriole","venule"];
for(const name of [...named,"ostialFlows","capillaries"]){
  const from=named.includes(name)?source.match(new RegExp("private val "+name+" = route \\{([^}]+)\\}"))[1]:source.match(new RegExp("private val "+name+"[\\s\\S]*?route \\{([^}]+)\\}"))[1];
  const start=routes.indexOf("static let "+name),end=routes.indexOf("\n  static let ",start+1),block=routes.slice(start,end<0?routes.length:end);
  assert.deepEqual(nativeTrack(block),fromCommands(from),name);
}
const fiberSource=source.match(/val edge = mid \+ side[\s\S]*?detail.rewind\(\)([\s\S]*?)stroke\(c, detail/)[1];
const fiberNative=geometry.match(/static func wallFiber[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(fiberNative),fromCommands(fiberSource),"compressed muscle fibers");
const sourceLabels=[...source.matchAll(/label\(c, R\.string\.health_atlas_(\w+), ([\d.f, ]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeLabels=[...all.matchAll(/label\("([^"]+)",([\d.,]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.equal(sourceLabels.length,18);assert.deepEqual(nativeLabels,sourceLabels,"all label positions");
const sourceVessels=[...source.matchAll(/vessel\(c, (\w+), ([\d.]+)f, prominent\)/g)].map(m=>m.slice(1)).sort();
const nativeVessels=[...all.matchAll(/coronaryVessel\(CoronaryArteries\.(\w+),width: ([\d.]+),prominent: prominent\)/g)].map(m=>m.slice(1)).sort();
assert.deepEqual(nativeVessels,sourceVessels,"arterial branch widths");
const streamNorm=s=>norm(s.replace(/Coronary(?:Arteries|WallRoutes|Return)\./g,"").replace(/Double\(([^)]+)\)/g,"$1").replaceAll("Self.cream","cream").replace(/(?:time|speed|count|color|strength|span): /g,"").replace(/0xff([\da-f]{6})/gi,"0x$1"));
const sourceStreams=[...source.matchAll(/stream\(c, ([^\n]+?)\)/g)].map(m=>m[1].split(",").map(streamNorm)).sort();
const nativeStreams=[...all.matchAll(/coronaryStream\(((?:Coronary(?:Arteries|WallRoutes|Return)\.\w+|branch),[^\n]+)\)/g)].map(m=>m[1].split(",").map(streamNorm)).sort();
assert.equal(sourceStreams.length,16);assert.deepEqual(nativeStreams,sourceStreams,"stream time/speed/count/strength/span");
for(const [swift,kotlin] of [
  ["0.64 * t * t * t * (1 - 0.5 * t)",".64f * t * t * t * (1f - .5f * t)"],
  ["step == 2 ? 1 + t - delta","2 -> 1f + t - delta"],
  ["1.68 + 0.36 * t + delta","3 -> 1.68f + .36f * t + delta"],
  ["1 - 0.57 * squeeze","1f - .57f * squeeze"],["1 - 0.58 * squeeze","1f - .58f * squeeze"],
  ["travel - floor(travel)","travel - kotlin.math.floor(travel)"],
  ["position: u * span","val p = u * span"],
  ["min(5.8,length * 0.19)","minOf(5.8f, length * .19f)"],
  ["Int(255 * strength * min(1,min(8 * u,8 * (1 - u))))","(255f * strength * minOf(1f, 8f * u, 8f * (1f - u))).toInt()"],
  ["0.55 * size * dx + 0.36 * size * dy",".55f * size * dx + .36f * size * dy"],
  ["0.55 * size * dy - 0.36 * size * dx",".55f * size * dy - .36f * size * dx"],
  ["149 + Double(index) * 20 + 5 * u","149f + i * 20f + 5f * u"],
  ["290 + side * (8 * crowding + 19 * u)","mid + side * (8f * crowding + 19f * u)"],
  ["Int(255 * (1 - abs(2 * u - 1)) * crowding)","(255f * (1f - abs(2f * u - 1f)) * crowding).toInt()"],
  ["21 - 11 * squeeze + Double(row) * 9","21f - 11f * squeeze + row * 9f"],
  ["5 + 5 * crowding","5f + 5f * crowding"],["2 + 4 * crowding","2f + 4f * crowding"],
  ["1, y: crowding","c.scale(1f, crowding, 180f, mid)"],
  ["13 - 5 * squeeze","13f - 5f * squeeze"],["width * 0.58","width * .58f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["995F62","A1414F","E69B86","3E7188","95BDC9","786969","B67822","F7CBB3","CC777E","ECB09B","B86675","F7B5A0","C76B70","FFD9BD","E09082","DFEBEC","96B8C1","FFE4CD","E6A39B","F7D1BB","D58E90","789AA6","B67577","B9797A","FBE0C2","AC7073","DCA29A","8B5B60","F9BCA8","763345","BB827A","CD8C82","FBE0C9","A15D73","B76B79","905864"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(coronary_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["length = GalaxySSIHealthAtlasCurveLength.route(route,width: 360,height: 360)","guard let length = track.length","frame.alpha > 0","local.opacity *=",
  "branch.path.trimmedPath(from: 0.53,to: 1)","local.translateBy(x: 180, y: 290); local.scaleBy(x: 1, y: crowding); local.translateBy(x: -180, y: -290)","if step == 2","prominent = step != 4","oxygen.opacity *="
])assert(all.includes(token),token);
assert(!files[4].includes("CurveLength.route"),"route lengths must not be recomputed for every marker");
assert(routes.includes("ostialFlows: [Track] = [-1.0,1].map"));
assert(routes.includes("capillaries: [Track] = [-1.0,0,1].map"));
assert(source.includes("listOf(-1f, 1f).map"));
assert(source.includes("listOf(-1f, 0f, 1f).map"));
assert(all.includes("atlas-function-coronary-perfusion-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CORONARY_PERFUSION": GalaxySSIHealthAtlasCoronaryView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 coronary source audit: thirteen outlines/seventeen tracks, integrated left-flow timing, compressed capillaries, negative-time wrap, every stream signature/label position and bilingual resources. No native compilation/pixels verified.");
