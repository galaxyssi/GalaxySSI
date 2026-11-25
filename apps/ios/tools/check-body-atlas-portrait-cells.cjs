// Static source/resource audit, not native Canvas rendering or XCTest execution.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process"), sharp = require("sharp");
const root = path.resolve(__dirname, "../GalaxySSI"), assets = path.join(root, "Assets.xcassets");
const sha = "ac7ab99df542b67a7a0ea6a28999a7334b79aada";
const source = file => execFileSync("git", ["show", sha + ":" + file], {maxBuffer: 16_000_000});
(async () => {
  const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSensoryCells.dataset/content.json")));
  assert.deepEqual(pack.artworkSource, {androidPR:4361,mergeCommit:sha});
  const kotlin = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensoryPlates.kt").toString();
  const lessons = source("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensorySections.kt").toString();
  const native = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasSensorySections.swift"), "utf8");
  const resources = ["en","zh-Hans"].map(language => new Map(fs.readFileSync(path.join(root,language+".lproj/BodyAtlas.strings"),"utf8").split(/\r?\n/).flatMap(line=>{
    const m=line.match(/^"([^"]+)" = (".*");$/);return m?[[m[1],JSON.parse(m[2])]]:[];
  })));
  const fixtures = [
    ["cell-inner-ear-hair-cell","cochlear_hair","hairCell",[0,0,2,1]],
    ["cell-rod-photoreceptor","rod","rod",[0,0,0,1]],
    ["cell-cone-photoreceptor","cone","cone",[0,0,0,1]]
  ];
  let features=0;
  for (const [id,slug,name,stages] of fixtures) {
    const plate=pack.plates.find(p=>p.owner===id); assert(plate); assert.equal(plate.aspectRatio,2/3);
    const dir=path.join(assets,plate.asset+".imageset"),metadata=JSON.parse(fs.readFileSync(path.join(dir,"Contents.json")));
    assert(metadata.images.some(i=>i.filename==="cell.png")); assert(!metadata.properties?.["preserves-vector-representation"]);
    assert(!fs.existsSync(path.join(dir,"cell.pdf")));
    const original=source("apps/android/app/src/main/res/drawable-nodpi/health_atlas_sensory_"+slug+".png");
    const png=fs.readFileSync(path.join(dir,"cell.png"));assert(png.equals(original));
    const image=sharp(png),info=await image.metadata();assert.equal(info.width,1024);assert.equal(info.height,1536);
    const rgba=await image.ensureAlpha().raw().toBuffer();
    const alpha=(x,y)=>rgba[(Math.floor(y*info.height)*info.width+Math.floor(x*info.width))*4+3];
    for(const x of [0,info.width-1])for(const y of [0,info.height-1])assert(rgba[(y*info.width+x)*4+3]<=4);
    const start=kotlin.indexOf('plate("'+id+'"'), next=kotlin.indexOf('\n        plate(',start+1);
    const block=kotlin.slice(start,next<0?kotlin.length:next);
    const expected=[...block.matchAll(/feature\("([^"]+)", ([\d.]+)f, ([\d.]+)f, R.string.(\w+), R.string.(\w+)\)/g)].map(m=>({
      marker:{id:m[1],x:Number(m[2]),y:Number(m[3])},title:m[4],explanation:m[5]
    }));
    assert.equal(expected.length,2);assert.deepEqual(plate.features,expected);
    for(const feature of expected) {
      assert(alpha(feature.marker.x,feature.marker.y)>200,feature.marker.id); features++;
      for(const map of resources)for(const key of [feature.title,feature.explanation])assert(map.get(key),key);
    }
    if(name==="hairCell") {
      assert(alpha(0.431,0.574)>200);
      for(const map of resources)for(const key of ["health_atlas_cell_inner_ear_hair_cell_name","health_atlas_process_cell_inner_ear_hair_cell_2"])assert(map.get(key));
      assert(native.includes('id: "hair-cell-receptor-body", x: 0.431, y: 0.574'));
    }
    const actual=native.match(new RegExp("static let "+name+" = portrait\\(\""+id+"\", stages: \\[([\\d, ]+)\\]"));
    assert(actual);assert.deepEqual(actual[1].split(",").map(Number),stages);
    const from=lessons.indexOf("private val "+name+" by lazy"), body=lessons.slice(from,lessons.indexOf("\n    }",from));
    assert(body.includes("listOf("+stages.join(", ")+")"));
  }
  assert.equal(features,6);
  assert(lessons.includes("artWidth = 280, artHeight = 420"));
  assert(native.includes("artWidth: 280, artHeight: 420"));
  const view=fs.readFileSync(path.join(root,"GalaxySSIHealthAtlasSectionLessonView.swift"),"utf8");
  assert(view.includes("size.height / lesson.artHeight"));assert(view.includes("lesson.artWidth / lesson.artHeight"));
  assert(view.includes("lesson.artHeight > lesson.artWidth ? 280 : 226"));
  const simulation=fs.readFileSync(path.join(root,"GalaxySSIHealthAtlasSimulationPanel.swift"),"utf8");
  assert(simulation.includes("section != nil && entry.kind != .cell"));
  assert(simulation.includes("if !quantitativeAfterArt"));
  assert(simulation.includes("mechanismFirst || gasExchange || entry.id == \"pancreas\" || endocrine != nil || sweat || quantitativeAfterSection"));
  console.log("Android #4361 parity: three original 1024x1536 portraits, six calibrated features plus hair-cell body, exact stage maps, portrait dimensions and cell-quantitative ordering. No native UI execution.");
})().catch(error=>{console.error(error);process.exit(1);});
