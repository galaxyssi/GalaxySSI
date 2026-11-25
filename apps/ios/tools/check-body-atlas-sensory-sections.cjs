// Static pinned-resource/PDF/source audit. No native Swift or UI execution.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process"), xml = require("xml-js");
const {PDFDocument, PDFName, PDFDict, PDFArray, PDFNumber, decodePDFRawStream, drawSvgPath, rgb} = require("pdf-lib");
const root = path.resolve(__dirname, "../GalaxySSI"), assets = path.join(root, "Assets.xcassets");
const retinal = process.argv.includes("--retinal-cells");
const systems = process.argv.includes("--system-overviews");
const batch = process.argv.includes("--tissue-lymph");
const functionArt = require("./body-atlas-function-artwork.cjs");
const sha = functionArt ? (functionArt.sha ?? "ab78711d467c013444883dbaeca23c39a601c875") : batch ? "b8fbf1191367153af2824506df99bbc5c5bae56e" : systems ? "5ca99f3dde521cd65ca0f0f84b5550a31da5b9f2" : retinal ? "b513fe5023b8699e4e64e1f914f09be98ddeeacb" : "7e5841c21c313fd2ecee924e6805385e96a564a1";
const source = file => execFileSync("git", ["show", sha + ":" + file], {encoding: "utf8", maxBuffer: 4_000_000});
const batchFrames = [];
if (batch) for (const [name, filename] of [["HealthAtlasTissues","tissue.pdf"],["HealthAtlasLymphOrgans","cell.pdf"]]) {
  const pack = JSON.parse(fs.readFileSync(path.join(assets,name+".dataset/content.json")));
  assert.deepEqual(pack.artworkSource,{androidPR:4363,mergeCommit:sha});
  for (const plate of pack.plates) batchFrames.push([path.basename(plate.drawable,".xml").replace("health_atlas_",""),plate.asset,filename]);
}
const frames = functionArt ? functionArt.frames : batch ? batchFrames : systems ? [
  ["system_cardio", "HealthAtlasOverviewCardio", "overview.pdf", 0],
  ["system_testicular", "HealthAtlasOverviewTesticular", "overview.pdf", 3],
  ["system_ovarian", "HealthAtlasOverviewOvarian", "overview.pdf", 9]
] : retinal ? [
  ["sensory_aii", "HealthAtlasSensoryAii", "cell.pdf", 0], ["sensory_bipolar", "HealthAtlasSensoryBipolar", "cell.pdf", 3],
  ["sensory_ganglion", "HealthAtlasSensoryGanglion", "cell.pdf", 8], ["sensory_rpe", "HealthAtlasSensoryRpe", "cell.pdf", 13]
] : [
  ["sensory_retina_section", "HealthAtlasSensoryRetinaSection", "cell.pdf"]
];
const gradientOffset = functionArt || batch || systems || retinal ? 0 : 9;
const array = (dict, key) => dict.lookup(PDFName.of(key), PDFArray).asArray().map(n => n.asNumber());
const colour = value => [1,3,5].map(i => parseInt(value.slice(i, i + 2), 16) / 255);
(async () => {
  let paths = 0, gradients = gradientOffset, gradientCount = 0;
  for (const [slug, asset, filename, firstGradient] of frames) {
    if (firstGradient !== undefined) gradients = firstGradient;
    const raw = source("apps/android/app/src/main/res/drawable/health_atlas_" + slug + ".xml");
    const vector = xml.xml2js(raw, {compact: true}).vector;
    if (vector.group) {
      assert(functionArt?.groups,"Unexpected grouped source");
      vector.path=require("./body-atlas-ordered-vector.cjs")(raw, {affine: !!functionArt.affineGroups, clips: !!functionArt.clips});
    }
    const dir = path.join(assets, asset + ".imageset"), metadata = JSON.parse(fs.readFileSync(path.join(dir, "Contents.json")));
    if (functionArt?.normalizeQuadratics) for (const item of vector.path) {
      item._attributes["android:pathData"] = require("./body-atlas-quadratic-path.cjs")(item._attributes["android:pathData"]);
    }
    assert(metadata.properties["preserves-vector-representation"]); assert(metadata.images.some(i => i.filename === filename));
    const pdf = await PDFDocument.load(fs.readFileSync(path.join(dir, filename)));
    assert.equal(pdf.getPageCount(), 1);
    const page = pdf.getPage(0), box = page.getSize();
    assert.equal(box.width, Number(vector._attributes["android:viewportWidth"]));
    assert.equal(box.height, Number(vector._attributes["android:viewportHeight"]));
    const resources = page.node.Resources(), shades = resources.lookup(PDFName.of("Shading"), PDFDict);
    const expected = vector.path.filter(p => p["aapt:attr"]); gradientCount += expected.length;
    assert.equal(shades.keys().length, expected.length);
    const images = resources.lookupMaybe(PDFName.of("XObject"), PDFDict);
    assert(!images || images.keys().length === 0, "Gradient/path PDF must not be rasterized");
    const contents = page.node.Contents().asArray().map(ref =>
      Buffer.from(decodePDFRawStream(pdf.context.lookup(ref)).decode()).toString()).join("\n");
    let orderedCursor=0;
    if (functionArt) for (const item of vector.path) {
      const geometry = drawSvgPath(item._attributes["android:pathData"], {x:0,y:box.height,color:rgb(0,0,0)})
        .map(op=>op.toString()).filter(op=>/(?:^|\s)(?:m|l|c|v|y|h)$/.test(op)).join("\n");
      assert(geometry.length > 0 && contents.includes(geometry), "Missing original geometry " + slug);
      if (item._atlasClips) {
        let cursor = orderedCursor;
        for (const clip of item._atlasClips) {
          const signature = require("./body-atlas-vector-clips.cjs")(clip, box.height).map(op=>op.toString()).join("\n");
          const at = contents.indexOf(signature, cursor);
          assert(at >= cursor, "Missing source clip " + slug);
          cursor = at + signature.length;
        }
        assert(contents.indexOf(geometry, cursor) >= cursor, "Source clip must precede its painted geometry " + slug);
      }
      if (functionArt.groups && !functionArt.affineGroups) {
        const at=contents.indexOf(geometry,orderedCursor);
        assert(at>=orderedCursor,"Source path order "+slug);
        let mirror=false; const stack=[];
        for (const line of contents.slice(0,at).trim().split(/\r?\n/)) {
          if (line==="q") stack.push(mirror);
          if (line==="Q") { assert(stack.length); mirror=stack.pop(); }
          if (line==="-1 0 0 1 360 0 cm") mirror=!mirror;
        }
        assert.equal(mirror,!!item._atlasMirrorX,"Source group reflection "+slug);
        orderedCursor=at+geometry.length;
      }
      if (functionArt.affineGroups) {
        const at=contents.indexOf(geometry,orderedCursor);
        assert(at>=orderedCursor,"Source affine path order "+slug);
        const transform=require("./body-atlas-vector-transform.cjs");
        let state={matrix:transform.identity,fill:1,stroke:1,fillRGB:null,strokeRGB:null};const stack=[];
        const ext=resources.lookupMaybe(PDFName.of("ExtGState"),PDFDict);
        for(const line of contents.slice(0,at).trim().split(/\r?\n/)){
          if(line==="q")stack.push({...state});
          else if(line==="Q"){assert(stack.length);state=stack.pop();}
          else if(line.endsWith(" cm")){
            const numbers=line.slice(0,-3).trim().split(/\s+/).map(Number);
            assert(numbers.length===6&&numbers.every(Number.isFinite));state.matrix=transform.multiply(state.matrix,numbers);
          } else if(line.endsWith(" rg"))state.fillRGB=line.slice(0,-3).trim().split(/\s+/).map(Number);
          else if(line.endsWith(" RG"))state.strokeRGB=line.slice(0,-3).trim().split(/\s+/).map(Number);
          else if(line.endsWith(" gs")){
            const dictionary=ext.lookup(PDFName.of(line.slice(1,-3).trim()),PDFDict);
            const fill=dictionary.lookupMaybe(PDFName.of("ca"),PDFNumber),stroke=dictionary.lookupMaybe(PDFName.of("CA"),PDFNumber);
            if(fill)state.fill=fill.asNumber();if(stroke)state.stroke=stroke.asNumber();
          }
        }
        const expected=transform.multiply(transform.pdf(item._atlasTransform||transform.identity,box.height),[1,0,0,-1,0,box.height]);
        expected.forEach((number,i)=>assert(Math.abs(state.matrix[i]-number)<1e-8,"Source affine matrix "+slug));
        const a=item._attributes,alpha=colour=>colour?.length===9?parseInt(colour.slice(1,3),16)/255:1;
        if(a["android:fillColor"])assert(Math.abs(state.fill-alpha(a["android:fillColor"])*Number(a["android:fillAlpha"]??1))<1e-9,"Source fill opacity "+slug);
        if(a["android:strokeColor"])assert(Math.abs(state.stroke-alpha(a["android:strokeColor"])*Number(a["android:strokeAlpha"]??1))<1e-9,"Source stroke opacity "+slug);
        for(const [attribute,key] of [["android:fillColor","fillRGB"],["android:strokeColor","strokeRGB"]]){
          if(!a[attribute]||item["aapt:attr"])continue;
          const hex=a[attribute].slice(-6),rgb=[0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255);
          assert(state[key]?.length===3,"Missing source RGB "+slug);
          rgb.forEach((component,i)=>assert(Math.abs(state[key][i]-component)<1e-9,"Source RGB "+slug));
        }
        orderedCursor=at+geometry.length;
      }
    }
    if (functionArt?.groups) {
      if (!functionArt.affineGroups) assert.equal((contents.match(/-1 0 0 1 360 0 cm/g)||[]).length,vector.path.filter(p=>p._atlasMirrorX).length);
      let depth=0;
      for(const line of contents.trim().split(/\r?\n/)){if(line==="q")depth++;if(line==="Q")depth--;assert(depth>=0);}
      assert.equal(depth,0,"Balanced PDF drawing groups");
    }
    const strokeGradients = expected.filter(p => p["aapt:attr"]._attributes.name === "android:strokeColor");
    assert.equal((contents.match(/\/AtlasGradient\d+ sh/g) || []).length, expected.length - strokeGradients.length);
    assert.equal((contents.match(/\/AtlasGradient\d+ SCN/g) || []).length, strokeGradients.length);
    for (const item of expected) {
      const g = item["aapt:attr"].gradient._attributes, shade = shades.lookup(PDFName.of("AtlasGradient" + gradients++), PDFDict);
      const radial = g["android:type"] === "radial";
      if (item["aapt:attr"]._attributes.name === "android:strokeColor") {
        const patterns = resources.lookup(PDFName.of("Pattern"),PDFDict);
        const pattern = patterns.lookup(PDFName.of("AtlasGradient"+(gradients-1)),PDFDict);
        assert.equal(pattern.lookup(PDFName.of("PatternType")).asNumber(),2);
        assert.deepEqual(array(pattern,"Matrix"),[1,0,0,-1,0,box.height]);
        assert.equal(pattern.lookup(PDFName.of("Shading"),PDFDict),shade);
      }
      assert.equal(shade.lookup(PDFName.of("ShadingType")).asNumber(), radial ? 3 : 2);
      const coords = radial ? [g["android:centerX"], g["android:centerY"], 0, g["android:centerX"], g["android:centerY"], g["android:gradientRadius"]].map(Number) :
        ["startX","startY","endX","endY"].map(k => Number(g["android:" + k] ?? 0));
      assert.deepEqual(array(shade, "Coords"), coords);
      const fn = shade.lookup(PDFName.of("Function"), PDFDict);
      const rawStops = item["aapt:attr"].gradient.item;
      const stops = rawStops ? (Array.isArray(rawStops)?rawStops:[rawStops]).map(s=>({color:s._attributes["android:color"],offset:Number(s._attributes["android:offset"])})) :
        [g["android:startColor"], ...(g["android:centerColor"] ? [g["android:centerColor"]] : []), g["android:endColor"]].map((color,i,all)=>({color,offset:i/(all.length-1)}));
      const colours = stops.map(s=>colour(s.color));
      const functions = fn.lookup(PDFName.of("FunctionType")).asNumber() === 3 ?
        fn.lookup(PDFName.of("Functions"), PDFArray).asArray().map(ref => pdf.context.lookup(ref, PDFDict)) : [fn];
      assert.equal(functions.length, colours.length - 1);
      if (functions.length > 1) {
        assert.deepEqual(array(fn,"Bounds"),stops.slice(1,-1).map(s=>s.offset));
        assert.deepEqual(array(fn,"Encode"),functions.flatMap(()=>[0,1]));
      }
      for (const [index, f] of functions.entries()) {
        assert.deepEqual(array(f, "C0"), colours[index]); assert.deepEqual(array(f, "C1"), colours[index + 1]);
      }
    }
    paths += vector.path.length;
  }
  assert.equal(paths, functionArt ? functionArt.paths : batch ? 646 : systems ? 39 : retinal ? 35 : 24); assert.equal(gradientCount, functionArt ? functionArt.gradients : batch ? 210 : systems ? 18 : retinal ? 11 : 2);
  if (functionArt) {
    console.log("Android #" + (functionArt.androidPR ?? 4384) + " " + functionArt.name + " Function artwork: " + frames.length + " vector PDFs, " + paths + " exact path geometries and " + gradientCount + " native gradients; no native pixel verification.");
    return;
  }
  if (batch) {
    console.log("Android #4363: 23 vector PDFs, 646 paths, 210 exact gradients including native stroked shading patterns; no raster flattening.");
    return;
  }
  if (systems) {
    console.log("Android #4362: three vector PDFs, 39 paths, 18 exact native gradients and unchanged viewports; no raster flattening.");
    return;
  }
  const kotlin = execFileSync("git", ["show", "b513fe5023b8699e4e64e1f914f09be98ddeeacb:apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSensorySections.kt"], {encoding: "utf8"});
  const swift = fs.readFileSync(path.join(root, "GalaxySSIHealthAtlasSensorySections.swift"), "utf8");
  const expectedRoutes = [...kotlin.matchAll(/atlasSectionTrack\(([\d.]+)f, ([\d.]+)f\) \{([^}]+)\}/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])}, commands: [...m[3].matchAll(/(lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(c => {
      const n = c[2].split(",").map(x => Number(x.trim().replace(/f$/, "")));
      return {kind: {lineTo: "line", quadTo: "quad", cubicTo: "cubic"}[c[1]],
        points: n.reduce((r, x, i) => { if (i % 2 === 0) r.push({x, y: n[i+1]}); return r; }, [])};
    })
  }));
  const actualRoutes = [...swift.matchAll(/\.init\(start: \.init\(x: ([\d.]+), y: ([\d.]+)\), commands: \[([\s\S]*?)(?=\n      \.init\(start:|\n    \])/g)].map(m => ({
    start: {x: Number(m[1]), y: Number(m[2])}, commands: [...m[3].matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(c => ({
      kind: c[1], points: [...c[2].matchAll(/\.init\(x: ([\d.]+), y: ([\d.]+)\)/g)].map(p => ({x: Number(p[1]), y: Number(p[2])}))
    }))
  }));
  assert.equal(expectedRoutes.length, 4); assert.deepEqual(actualRoutes, expectedRoutes);
  const expectedFeatures = [...kotlin.matchAll(/feature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)].map(m => [m[1], Number(m[2]), Number(m[3]), m[4], m[5]]);
  const actualFeatures = [...swift.matchAll(/feature\("([^"]+)", (\d+), (\d+), "([^"]+)", (\d+)\)/g)].map(m =>
    [m[1], Number(m[2]), Number(m[3]), "health_atlas_" + m[4], "health_atlas_hearing_ear_" + m[5]]);
  assert.equal(expectedFeatures.length, 4); assert.deepEqual(actualFeatures, expectedFeatures);
  for (const language of ["en", "zh-Hans"]) {
    const directory = language === "en" ? "values" : "values-zh";
    const resource = xml.xml2js(source("apps/android/app/src/main/res/" + directory + "/health_atlas_hearing.xml"), {compact:true}).resources.string;
    const values = new Map(fs.readFileSync(path.join(root, language + ".lproj/BodyAtlas.strings"), "utf8").split(/\r?\n/).flatMap(line => {
      const m = line.match(/^"([^"]+)" = (".*");$/); return m ? [[m[1], JSON.parse(m[2])]] : [];
    }));
    for (const key of ["health_atlas_hearing_eardrum", "health_atlas_hearing_ossicles", "health_atlas_hearing_route_scope"])
      assert.equal(values.get(key), resource.find(r => r._attributes.name === key)._text);
  }
  console.log("Sensory parity: " + frames.length + " retained vector PDFs / " + paths + " source paths / " + gradientCount + " exact native gradients; Android #4359 ear routes/features and six inherited localized values. No native UI execution.");
})().catch(error => { console.error(error); process.exit(1); });
