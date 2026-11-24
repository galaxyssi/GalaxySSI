const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),xml=require('xml-js'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../..'),sha='6071f168d789cc0657306042b9735a512bd04e64';
const read=(revision,file)=>new Map(xml.xml2js(cp.execFileSync('git',['show',revision+':'+file],{cwd:root,encoding:'utf8'}),{compact:false}).elements.find(x=>x.name==='resources').elements.filter(x=>x.name==='string').map(x=>[x.attributes.name,(x.elements||[]).map(e=>e.text||e.cdata||'').join('')]));
for(const[dir,locale]of[['values','en'],['values-zh','zh-Hans']]){
 const file='apps/android/app/src/main/res/'+dir+'/health_comparison_strings.xml',current=read(sha,file),before=read(sha+'^1',file);
 const delta=[...current].filter(([key,text])=>text!==before.get(key));assert.deepEqual(delta.map(([key])=>key),['health_activity_day_unrecorded']);
 const content=delta.map(([key,text])=>JSON.stringify(key)+' = '+JSON.stringify(text)+';').join('\n')+'\n';
 const target=path.join(root,'apps/ios/GalaxySSI',locale+'.lproj/HealthActivityScrubbing.strings');
 if(process.argv.includes('--check'))assert.equal(fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n'),content);else fs.writeFileSync(target,content);
 console.log(locale+': exact Android #4497 no-record resource pair.');
}
