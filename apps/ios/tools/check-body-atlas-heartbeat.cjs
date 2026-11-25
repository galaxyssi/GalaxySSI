// Pinned source, topology and integration checks; no Metal/Swift/native renderer execution.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict"),cp=require("node:child_process");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:16_000_000});
const kotlin=show("java/com/galaxyssi/chat/HealthAtlasHeartbeatView.kt").toString();
const stageSource=show("java/com/galaxyssi/chat/HealthAtlasBeatStage.kt").toString();
const view=local("GalaxySSIHealthAtlasHeartbeatView.swift"),motion=local("GalaxySSIHealthAtlasBeatMotion.swift");
const mesh=local("GalaxySSIHealthAtlasImageMesh.swift"),native=local("GalaxySSIHealthAtlasMeshImage.swift"),metal=local("GalaxySSIHealthAtlasMesh.metal");
for(const name of ["rightFill","leftFill","rightOut","leftOutFront","leftOutArch","shortToRight","shortToLeft"]){
  const source=kotlin.match(new RegExp("private val "+name+" = path \\{([\\s\\S]*?)\\n    \\}"));assert(source,name);
  const expected=[...source[1].matchAll(/(?:moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(x=>Number(x.trim().replace(/f$/,""))));
  const target=view.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]"),actual=[[parsed[0],parsed[1]],...parsed.slice(2)];
  assert.deepEqual(actual,expected,name);
}
const pairs=[["1 - 0.84 * Self.ease(f)","1f - .84f * ease(fraction)"],
  ["0.16 * (1 - Self.ease(f))",".16f * (1f - ease(fraction))"],["f / 0.14","fraction / .14f"],
  ["(1 - f) / 0.14","(1f - fraction) / .14f"]];
for(const [swift,android] of pairs){assert(motion.includes(swift),swift);assert(stageSource.includes(android),android);}
for(const [swift,android] of [["(y - 662) / 390","(y - 662f) / 390f"],["(720 - x) * weight(y) * contraction * 0.19","(720f - x) * weight(y) * amount * .19f"],
  ["weight(y) * contraction * 64","weight(y) * amount * 64f"],["(y - 527) / 132","(y - 527f) / 132f"],
  ["atrialSqueeze * 0.55","atrialSqueeze * .55f"],["progress * 1.56 - Double($0) * 0.137","progress * 1.56f - i * .137f"]]){
  assert(motion.includes(swift),swift);assert(kotlin.includes(android),android);
}
assert(motion.includes("divisions = 24"));assert(kotlin.includes("MESH = 24"));assert(kotlin.includes("ART_SIZE = 1254f"));
assert(mesh.includes("[i, i + step, i + step + 1, i, i + step + 1, i + 1]"));
assert(native.includes("makeDefaultLibrary(bundle:"));assert(native.includes("drawIndexedPrimitives(type: .triangle"));
assert(native.includes("GalaxySSIHealthAtlasImageMesh.transform(source: src, destination: dst)"));
assert(native.includes("image.draw(in: CGRect(origin: .zero, size: logicalSize))"));
assert(native.includes("MemoryLayout<Vertex>.stride"));assert(native.includes("CGImageAlphaInfo.premultipliedLast"));
assert(native.includes("pixelFormat: .rgba8Unorm"));assert(native.includes("texture.replace(region:"));
assert(native.includes("context.scaleBy(x: 1, y: -1)"));
assert(native.includes("color.sourceRGBBlendFactor = .one"));assert(native.includes("view.isPaused = true"));
assert(!native.includes("Timer")&&!view.includes("Timer"));
for(const token of ["float2 position; float2 uv","galaxyssiAtlasMeshVertex","galaxyssiAtlasMeshFragment","filter::linear","address::clamp_to_edge"])assert(metal.includes(token),token);
assert(view.includes("valve.marker.x * 1254"));assert(view.includes("(motion.fraction - 0.45) / 0.55"));
assert(view.includes("width: 1254, height: 1254"));assert(view.includes("atlas-function-heartbeat-art"));
const original=show("res/drawable-nodpi/health_atlas_heart_section.png");
assert(original.equals(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasHeartSection.imageset/heart.png"))));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
assert.equal((project.match(/GalaxySSIHealthAtlasMesh\.metal in Sources/g)||[]).length,2);
assert(project.includes("sourcecode.metal"));
const registry=local("GalaxySSIHealthAtlasFunctionArtwork.swift");assert(registry.includes('"HEARTBEAT": GalaxySSIHealthAtlasHeartbeatView'));
console.log("Android #4384 heartbeat source parity: five stage rules, seven exact cubic routes, shared valve anchors, 24x24 mesh topology, Metal/CoreGraphics paths and original heart PNG. Native shader compilation/pixels remain unverified.");
