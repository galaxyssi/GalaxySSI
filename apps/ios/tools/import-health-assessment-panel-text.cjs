const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),xml=require('xml-js'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../..'),sha='239692d36820daf678c74226ae7be67c622fc1e8';
const read=(revision,file)=>new Map(xml.xml2js(cp.execFileSync('git',['show',revision+':'+file],{cwd:root,encoding:'utf8'}),{compact:false}).elements.find(x=>x.name==='resources').elements.filter(x=>x.name==='string').map(x=>[x.attributes.name,(x.elements||[]).map(e=>e.text||e.cdata||'').join('')]));
const references=['health_care_comparison_values','health_care_comparison_correction','health_care_comparison_history','health_care_bp_title'];
for(const[dir,locale]of[['values','en'],['values-zh','zh-Hans']]){
 const file='apps/android/app/src/main/res/'+dir+'/strings_health_agent.xml',current=read(sha,file),before=read(sha+'^1',file);
 const delta=[...current].filter(([key,text])=>text!==before.get(key));assert.deepEqual(delta.map(([key])=>key).sort(),['health_agent_collapse','health_agent_expand','health_agent_open_record']);
 const care=read(sha,'apps/android/app/src/main/res/'+dir+'/strings_health_care.xml');
 const priority=read(sha,'apps/android/app/src/main/res/'+dir+'/strings_health_priority.xml');
 for(const key of references){const table=key==='health_care_bp_title'?priority:care;assert(table.has(key));delta.push([key,table.get(key)]);}
 const content=delta.sort(([a],[b])=>a.localeCompare(b)).map(([key,text])=>JSON.stringify(key)+' = '+JSON.stringify(text.replace(/%([0-9]+)\$s/g,'%$1$@'))+';').join('\n')+'\n';
 const target=path.join(root,'apps/ios/GalaxySSI',locale+'.lproj/HealthAssessmentPanel.strings');
 if(process.argv.includes('--check'))assert.equal(fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n'),content);else fs.writeFileSync(target,content);
 console.log(locale+': three Android #4278 changed labels plus four unchanged comparison/priority references.');
}
