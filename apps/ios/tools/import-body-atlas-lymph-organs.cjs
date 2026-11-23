// Regenerate current Android #4363 artwork with the shared native-gradient converter.
const cp = require("node:child_process"), path = require("node:path");
cp.execFileSync(process.execPath, [path.join(__dirname, "import-body-atlas-sensory-gradients.cjs"), "--lymph"],
  {cwd:path.resolve(__dirname,"../../.."),stdio:"inherit"});
