// Dedicated #4384 course art, shared by the importer and PDF/source audit.
const batches = {
  "--function-digestion": {name:"digestive", paths:35, gradients:21, frames:
    ["mouth","esophagus","stomach","duodenum","large","rectum"].map(slug =>
      ["gut_"+slug,"HealthAtlasFunctionGut"+slug[0].toUpperCase()+slug.slice(1),"art.pdf"])},
  "--function-insulin": {name:"insulin", paths:18, gradients:16,
    frames:[["digestive_islet","HealthAtlasFunctionIslet","art.pdf"]]},
  "--function-homeostasis": {name:"homeostasis", paths:12, gradients:7,
    frames:[["digestive_alpha","HealthAtlasFunctionAlpha","art.pdf"],
      ["cell_sweat_gland_section","HealthAtlasFunctionSweatGland","art.pdf"]]},
  "--function-signal": {name:"signal", paths:34, gradients:0,
    frames:[["endocrine_pituitary_section","HealthAtlasFunctionPituitary","art.pdf"],
      ["endocrine_thyroid_section","HealthAtlasFunctionThyroid","art.pdf"]]}
};
const selected = Object.keys(batches).filter(flag=>process.argv.includes(flag));
if(selected.length>1)throw Error("Select one Function artwork batch at a time");
module.exports = selected.length ? batches[selected[0]] : null;
