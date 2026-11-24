const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),xml=require('xml-js'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../..'),sha='c0be10a58c873cea52d3f60caf071cf36ec0a4af';
const git=args=>cp.execFileSync('git',args,{cwd:root,encoding:'utf8'});
const value=e=>(e.elements||[]).map(x=>x.text||x.cdata||'').join('');
const read=(revision,file)=>new Map(xml.xml2js(git(['show',revision+':'+file]),{compact:false}).elements.find(x=>x.name==='resources').elements.filter(x=>x.name==='string').map(x=>[x.attributes.name,value(x)]));
const references=['wechat_article_static','wechat_article_verification','wechat_article_continue','wechat_article_verify_continue_hint'];
const tables=[];
for(const[dir,locale]of[['values','en'],['values-zh-rCN','zh-Hans']]){
 const file='apps/android/app/src/main/res/'+dir+'/strings_wechat_article.xml',current=read(sha,file),prior=read(sha+'^1',file);
 const delta=[...current].filter(([key,text])=>text!==prior.get(key));assert.equal(delta.length,8);
 for(const key of references){assert(current.has(key));delta.push([key,current.get(key)]);}
 const normalize=s=>s.replace(/\\n/g,'\n').replace(/\\'/g,"'").replace(/%([0-9]+)\$s/g,'%$1$@').replace(/%([0-9]+)\$d/g,'%$1$lld');
 const content=delta.sort(([a],[b])=>a.localeCompare(b)).map(([key,text])=>JSON.stringify(key)+' = '+JSON.stringify(normalize(text))+';').join('\n')+'\n';
 const target=path.join(root,'apps/ios/GalaxySSI',locale+'.lproj/WeChatArticleExport.strings');
 if(process.argv.includes('--check'))assert.equal(fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n'),content);else fs.writeFileSync(target,content);
 tables.push(delta.map(([key])=>key).sort());console.log(locale+': eight exact Android #4461 delta pairs plus four unchanged reference labels; native platform adaptations have a separate table.');
}
assert.deepEqual(tables[0],tables[1]);
