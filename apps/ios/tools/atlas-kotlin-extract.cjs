// Shared, pinned Kotlin declaration extraction. This is not an Android or native app build.
const fs=require("node:fs"),path=require("node:path"),os=require("node:os"),cp=require("node:child_process");
module.exports=function extract({files,temporary,mainClass,cwd}){
 function jars(directory){
  if(!fs.existsSync(directory))return [];
  return fs.readdirSync(directory,{withFileTypes:true}).flatMap(e=>e.isDirectory()?jars(path.join(directory,e.name)):e.name.endsWith(".jar")?[path.join(directory,e.name)]:[]);
 }
 const cache=path.join(os.homedir(),".gradle/caches/modules-2/files-2.1");
 const one=relative=>{const found=jars(path.join(cache,relative));if(found.length!==1)throw Error("Set up pinned Kotlin extraction dependency "+relative);return found[0];};
 const stdlib=one("org.jetbrains.kotlin/kotlin-stdlib/2.0.21");
 const compiler=[one("org.jetbrains.kotlin/kotlin-compiler-embeddable/2.0.21"),stdlib,
  one("org.jetbrains.kotlin/kotlin-script-runtime/2.0.21"),one("org.jetbrains.kotlin/kotlin-reflect/2.0.21"),
  one("org.jetbrains.kotlin/kotlin-daemon-embeddable/2.0.21"),one("org.jetbrains.intellij.deps/trove4j/1.0.20200330"),
  one("org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.9.0"),one("org.jetbrains/annotations/23.0.0")].join(path.delimiter);
 const output=path.join(temporary,"classes");
 try{cp.execFileSync("java",["-cp",compiler,"org.jetbrains.kotlin.cli.jvm.K2JVMCompiler","-no-stdlib","-no-reflect","-classpath",stdlib,"-d",output,...files],{cwd,stdio:["ignore","pipe","pipe"],maxBuffer:8_000_000});}
 catch(error){process.stderr.write(error.stderr||"");throw error;}
 return JSON.parse(cp.execFileSync("java",["-cp",output+path.delimiter+stdlib,mainClass],{cwd,encoding:"utf8",maxBuffer:16_000_000}));
};
