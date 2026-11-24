const xml = require("xml-js");

// The #4384 posterior plate has identity groups and one x-reflection about x=180.
// Keep document order and apply the reflection to geometry and shading together.
module.exports = function orderedVectorPaths(text, options = {}) {
  const transforms = require("./body-atlas-vector-transform.cjs");
  const vector = xml.xml2js(text, {compact:false}).elements.find(e=>e.name==="vector");
  if (!vector) throw Error("Missing vector root");
  const result=[];
  function visit(nodes, mirror=false, matrix=transforms.identity) {
    for (const node of nodes || []) {
      if (node.type!=="element") continue;
      if (node.name==="path") {
        const path=xml.xml2js(xml.js2xml({elements:[node]}),{compact:true}).path;
        if (mirror) path._atlasMirrorX=true;
        if (options.affine && matrix.some((n,i)=>n!==transforms.identity[i])) path._atlasTransform=matrix;
        result.push(path);
      } else if (node.name==="group") {
        const a=node.attributes || {}, keys=Object.keys(a).filter(k=>k!=="android:name");
        if (options.affine) {
          visit(node.elements,false,transforms.multiply(matrix,transforms.group(a)));
          continue;
        }
        let reflected=false;
        if (keys.length) {
          if (keys.length!==2 || a["android:pivotX"]!=="180" || a["android:scaleX"]!=="-1")
            throw Error("Unsupported atlas group transform");
          reflected=true;
        }
        visit(node.elements,mirror!==reflected);
      } else throw Error("Unsupported atlas vector element "+node.name);
    }
  }
  visit(vector.elements);
  return result;
};
