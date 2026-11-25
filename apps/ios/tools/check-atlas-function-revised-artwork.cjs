// Source/PDF audit entry point; not XCTest or native rendering.
const cp=require("node:child_process"),path=require("node:path");
cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-function-revised-artwork.cjs"),"--check"],{stdio:"inherit"});
