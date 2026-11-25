// Execute the production extraction script against inert synthetic DOMs, not WebKit or PDFs.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {JSDOM}=require(path.join(process.env.GALAXYSSI_DOM_NODE_MODULES||path.join(os.tmpdir(),'galaxyssi-ios-dom-audit/node_modules'),'jsdom'));
const root=path.resolve(__dirname,'../../..'),swift=fs.readFileSync(path.join(root,'apps/ios/GalaxySSI/AgentIOSWeChatArticleDOM.swift'),'utf8');
const script=swift.match(/static let script = #"""([\s\S]*?)"""#/)[1];
const page='https://mp.weixin.qq.com/s/fixture';
function fixture(html,url=page){
 const dom=new JSDOM(html,{url,runScripts:'outside-only'});
 Object.defineProperty(dom.window.document,'readyState',{value:'interactive',configurable:true});
 const run=dom.window.Function('html','page','live','expected',script);
 return{dom,live:(expected=null)=>JSON.parse(run('',url,true,expected)),inert:()=>JSON.parse(run(html,url,false,null))};
}
const source='<h1 id="activity-name">Fixture \u4e2d\u6587</h1><div id="js_content">'+
 '<p>FIRST</p><img data-lazy-src="https://mmbiz.qpic.cn/good.png"><img src="about:blank">'+
 '<p>MIDDLE</p><img src="data:image/png;base64,YmFk"><p>LAST \u7ed3\u5c3e</p>'+
 '<script>window.didRun=true</script><style>decoration</style><iframe>not body</iframe>'+
 '<video>not static</video><textarea>not article</textarea></div>';
let f=fixture(source);
const ready=f.live();assert.equal(ready.phase,'ready');assert(ready.signature);assert.equal(ready.article,undefined);
assert.equal(f.dom.window.document.querySelector('img').naturalWidth,0,'Readiness must not require decoded images');
const saved=f.live(ready.signature),inert=f.inert();
assert.equal(saved.phase,'ready');assert.deepEqual(saved.article,inert.article);
assert.equal(saved.address,page);
f.dom.window.history.replaceState(null,'','/s/other-article');
assert.equal(f.live(ready.signature).phase,'changed');
f.dom.window.history.replaceState(null,'','/s/fixture');
assert.deepEqual(saved.article.blocks.map(x=>x.kind),['text','image','image','text','image','text']);
assert.equal(saved.article.blocks[1].source,'https://mmbiz.qpic.cn/good.png');assert.equal(saved.article.blocks[2].source,null);
assert(saved.article.blocks.at(-1).text.includes('LAST'));assert(saved.article.hasBodyText);
assert(!JSON.stringify(saved.article).includes('not body'));assert(!JSON.stringify(saved.article).includes('not static'));
assert.equal(f.dom.window.didRun,undefined);assert.equal(f.dom.window.document.querySelector('img').hasAttribute('loading'),false);
f.dom.window.document.querySelector('#js_content').append('CHANGED');
assert.equal(f.live(ready.signature).phase,'changed');f.dom.window.close();
f=fixture('<h1 id="activity-name">Image only</h1><div id="js_content"><img src="data:image/png;base64,YmFk"></div>');
assert.equal(f.inert().article.hasBodyText,false);assert.equal(f.inert().article.blocks[0].kind,'image');f.dom.window.close();
f=fixture('<h1>Not an article</h1><p>Server placeholder</p>');assert.equal(f.live().phase,'loading');f.dom.window.close();
f=fixture('<div id="js_verify">Verification</div>');assert.equal(f.live().phase,'verify');f.dom.window.close();
f=fixture(source,'https://mp.weixin.qq.com/secitptpage/verify');assert.equal(f.live().phase,'verify');f.dom.window.close();
f=fixture('<meta property="og:title" content="Fallback"><div id="js_content"><p>Body</p><img src="/asset"><img src="file:///private/a"><img src="javascript:void(0)"></div>');
assert.equal(f.inert().article.title,'Fallback');
assert.deepEqual(f.inert().article.blocks.filter(x=>x.kind==='image').map(x=>x.source),['https://mp.weixin.qq.com/asset',null,null]);f.dom.window.close();
f=fixture('<h1 id="activity-name">Empty media</h1><div id="js_content"><video>fallback</video><script>ignored</script></div>');
assert.equal(f.inert().article.hasBodyText,false);assert.deepEqual(f.inert().article.blocks,[]);f.dom.window.close();
console.log('Android #4461 production JS: interactive DOM readiness with broken images, matching-signature snapshot, ordered lazy/invalid images and trailing prose, inert active-content exclusion, explicit verification and image-only flags. Synthetic DOM execution, not WKWebView, native PDF or device acceptance.');
