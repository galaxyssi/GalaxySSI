const xml = require("xml-js");

// The #4384 posterior plate has identity groups and one x-reflection about x=180.
// Keep document order and apply the reflection to geometry and shading together.
module.exports = function orderedVectorPaths(text, options = {}) {
  const transforms = require("./body-atlas-vector-transform.cjs");
  const vector = xml.xml2js(text, {compact:false}).elements.find(e=>e.name==="vector");
  if (!vector) throw Error("Missing vector root");
  const result=[];
  function visit(nodes, mirror=false, matrix=transforms.identity, clips=[]) {
    let activeClips = clips;
    for (const node of nodes || []) {
      if (node.type!=="element") continue;
      if (node.name==="path") {
        const path=xml.xml2js(xml.js2xml({elements:[node]}),{compact:true}).path;
        if (mirror) path._atlasMirrorX=true;
        if (options.affine && matrix.some((n,i)=>n!==transforms.identity[i])) path._atlasTransform=matrix;
        if (activeClips.length) path._atlasClips = activeClips;
        result.push(path);
      } else if (node.name==="group") {
        const a=node.attributes || {}, keys=Object.keys(a).filter(k=>k!=="android:name");
        if (options.affine) {
          visit(node.elements,false,transforms.multiply(matrix,transforms.group(a)),activeClips);
          continue;
        }
        let reflected=false;
        if (keys.length) {
          if (keys.length!==2 || a["android:pivotX"]!=="180" || a["android:scaleX"]!=="-1")
            throw Error("Unsupported atlas group transform");
          reflected=true;
        }
        visit(node.elements,mirror!==reflected,matrix,activeClips);
      } else if (node.name==="clip-path" && options.clips) {
        if (mirror || matrix.some((n,i)=>n!==transforms.identity[i])) throw Error("Transformed atlas clip requires explicit support");
        const a = node.attributes || {};
        if (!a["android:pathData"] || Object.keys(a).some(k=>!["android:name","android:pathData","android:fillType"].includes(k))) throw Error("Unsupported vector clip attributes");
        if (a["android:fillType"] && !["nonZero","evenOdd"].includes(a["android:fillType"])) throw Error("Unsupported vector clip fill type");
        activeClips = [...activeClips, {pathData:a["android:pathData"],evenOdd:a["android:fillType"]==="evenOdd"}];
      } else throw Error("Unsupported atlas vector element "+node.name);
    }
  }
  visit(vector.elements);
  return result;
};
