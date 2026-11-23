// Pinned binary/anchor checks, not XCTest or native UI execution.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const cp = require("node:child_process"), sharp = require("sharp");
const root = path.resolve(__dirname, "../../.."), assets = path.join(root, "apps/ios/GalaxySSI/Assets.xcassets");
const sha = "5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2";
(async () => {
  cp.execFileSync(process.execPath, [path.join(__dirname, "check-body-atlas-final-overviews.cjs")], {cwd:root,stdio:"inherit"});
  cp.execFileSync(process.execPath, [path.join(__dirname, "check-body-atlas-sensory-sections.cjs"), "--system-overviews"], {cwd:root,stdio:"inherit"});
  const pack = JSON.parse(fs.readFileSync(path.join(assets, "HealthAtlasSystemOverviews.dataset/content.json")));
  const plate = pack.plates.find(p => p.id === "nervous"), directory = path.join(assets, plate.asset + ".imageset");
  assert.equal(plate.aspectRatio, 2/3); assert.equal(plate.markers.length, 5);
  assert(!plate.entryIDs.includes("brain"), "Keep dedicated brain illustration precedence");
  const metadata = JSON.parse(fs.readFileSync(path.join(directory, "Contents.json")));
  assert(metadata.images.some(i => i.filename === "overview.png")); assert(!metadata.properties?.["preserves-vector-representation"]);
  assert(!fs.existsSync(path.join(directory, "overview.pdf")));
  const png = fs.readFileSync(path.join(directory, "overview.png"));
  const original = cp.execFileSync("git", ["show", sha + ":" + plate.drawable], {cwd:root,maxBuffer:16_000_000});
  assert(png.equals(original));
  const image = sharp(png), info = await image.metadata();
  assert.equal(info.width, 1024); assert.equal(info.height, 1536); assert(info.hasAlpha);
  const rgba = await image.ensureAlpha().raw().toBuffer(), at = (x,y) => Array.from(rgba.subarray((y*info.width+x)*4,(y*info.width+x)*4+4));
  for (const x of [0,1023]) for (const y of [0,1535]) assert(at(x,y)[3] <= 4);
  for (const marker of plate.markers) {
    const x = Math.floor(marker.x*info.width), y = Math.floor(marker.y*info.height);
    assert(at(x,y)[3] >= 200, marker.id);
    let matches = false;
    for(let dx=-1;dx<=1;dx++) for(let dy=-1;dy<=1;dy++) {
      const [r,g,b,a] = at(x+dx,y+dy);
      matches ||= a>200 && (marker.id==="brain" ? b>r+10 : r>b+45 && g>b+30);
    }
    assert(matches, marker.id + " must hit the brain/nerve artwork");
  }
  console.log("Android #4362: byte-identical posterior nervous portrait, transparency and five calibrated brain/nerve anchors.");
})().catch(error => {console.error(error); process.exitCode=1;});
