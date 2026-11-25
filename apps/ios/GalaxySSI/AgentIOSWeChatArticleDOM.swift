import Foundation
import WebKit

enum AgentIOSWeChatArticleDOM {
  struct State: Decodable {
    let phase: String
    let signature: String?
    let article: AgentIOSWeChatArticleDocument?
    var address: String? = nil
  }
  @MainActor
  static func parse(html: String, url: URL) async throws -> AgentIOSWeChatArticleDocument {
    guard html.utf8.count <= AgentIOSWeChatArticleLimits.htmlBytes else { throw AgentIOSWeChatArticleFailure.tooLarge }
    let parser = PublicScienceDOM()
    let state: State
    do {
      state = try await parser.decode(html: html, script: script,
        arguments: ["page": url.absoluteString, "live": false, "expected": NSNull()],
        maximumHTMLBytes: AgentIOSWeChatArticleLimits.htmlBytes, maximumJSONBytes: AgentIOSWeChatArticleLimits.htmlBytes)
    } catch {
      if case PublicScienceError.tooLarge = error { throw AgentIOSWeChatArticleFailure.tooLarge }
      throw error
    }
    if state.phase == "verify" { throw AgentIOSWeChatArticleFailure.verificationRequired }
    if state.phase == "oversize" { throw AgentIOSWeChatArticleFailure.tooLarge }
    guard let article = state.article else { throw AgentIOSWeChatArticleFailure.bodyUnavailable }
    try article.validate()
    return article
  }
  // Read and clone in one isolated-world call. Publisher markup is inert data.
  static let script = #"""
    if (live && location.href !== page) return JSON.stringify({phase:'changed'});
    let tree;
    if (live) tree = document;
    else {
      const inert = document.createElement('template');
      inert.innerHTML = html;
      tree = inert.content;
    }
    const body = tree.querySelector('#js_content');
    const address = new URL(page);
    if (address.pathname.includes('/secitptpage/verify') || (!body && tree.querySelector('#js_verify')))
      return JSON.stringify({phase:'verify'});
    const title = tree.querySelector('#activity-name')?.textContent?.trim()
      || tree.querySelector('meta[property="og:title"]')?.getAttribute('content')?.trim();
    if (!body || !title || (live && document.readyState === 'loading')) return JSON.stringify({phase:'loading'});
    const markup = body.innerHTML;
    if (markup.length > 8388608) return JSON.stringify({phase:'oversize'});
    if (!body.textContent.trim() && !body.querySelector('img')) return JSON.stringify({phase:'loading'});
    let hash = 0;
    for (let i = 0; i < markup.length; i++) hash = ((hash << 5) - hash + markup.charCodeAt(i)) | 0;
    const signature = title + ':' + markup.length + ':' + hash;
    if (live && expected == null) return JSON.stringify({phase:'ready',signature});
    if (live && expected !== signature) return JSON.stringify({phase:'changed'});
    if (live && document.documentElement.outerHTML.length > 8388608) return JSON.stringify({phase:'oversize'});
    const content = body.cloneNode(true);
    content.querySelectorAll('script,style,link,iframe,object,embed,svg,canvas,template,noscript,input,button,select,textarea,video,audio,picture source').forEach(node => node.remove());
    const hasBodyText = content.textContent.trim().length > 0;
    const blocks = [];
    let text = '';
    const flush = () => {
      const value = text.replace(/[ \t]+/g,' ').replace(/ *\n */g,'\n').replace(/\n{3,}/g,'\n\n').trim();
      if (value) blocks.push({kind:'text',text:value});
      text = '';
    };
    const blockTags = new Set(['ARTICLE','BLOCKQUOTE','BR','DIV','H1','H2','H3','H4','H5','H6','LI','OL','P','PRE','SECTION','TABLE','TD','TH','TR','UL']);
    let visited = 0, exceeded = false;
    const visit = (node, depth) => {
      if (exceeded) return;
      if (++visited > 100000 || depth > 256 || blocks.length > 32768) { exceeded = true; return; }
      if (node.nodeType === 3) { text += node.nodeValue; return; }
      if (node.nodeType !== 1) return;
      if (node.tagName === 'IMG') {
        flush();
        const raw = ['data-src','data-original','data-lazy-src','src'].map(key => node.getAttribute(key)?.trim()).find(Boolean);
        let source = null;
        try {
          if (raw?.toLowerCase().startsWith('data:image/')) source = raw;
          else if (raw) {
            const image = new URL(raw, page);
            if (image.protocol === 'https:' && !image.username && !image.password) source = image.href;
          }
        } catch (_) {}
        blocks.push({kind:'image',source});
        return;
      }
      if (blockTags.has(node.tagName)) text += '\n';
      for (const child of node.childNodes) visit(child, depth + 1);
      if (blockTags.has(node.tagName)) text += '\n';
    };
    visit(content, 0);
    if (exceeded) return JSON.stringify({phase:'oversize'});
    flush();
    return JSON.stringify({phase:'ready',signature,address:page,article:{title,hasBodyText,blocks}});
    """#
}
