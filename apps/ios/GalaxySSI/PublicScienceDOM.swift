import Foundation
import WebKit

@MainActor
final class PublicScienceDOM: NSObject, WKNavigationDelegate {
  private let webView: WKWebView
  private var readiness: CheckedContinuation<Void, Error>?

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    webView.navigationDelegate = self
  }

  func catalog(html: String, source: PublicScienceSource) async throws -> [PublicScienceEntry] {
    let entries: [PublicScienceEntry] = try await extract(html: html, source: source, url: source.endpoint, catalog: true)
    var seen = Set<URL>()
    let valid = entries.filter {
      source.acceptsArticle($0.url) && !$0.title.isEmpty && seen.insert($0.url).inserted
    }
    guard !valid.isEmpty else { throw PublicScienceError.unreadable }
    return valid
  }

  func article(html: String, source: PublicScienceSource, url: URL) async throws -> PublicScienceDocument {
    guard source.acceptsArticle(url) else { throw PublicScienceError.invalidSource }
    let parsed: PublicScienceDocument = try await extract(html: html, source: source, url: url, catalog: false)
    guard !parsed.title.isEmpty, !parsed.sections.isEmpty else { throw PublicScienceError.unreadable }
    var seen = Set<URL>()
    let figures = parsed.figures.filter { source.acceptsImage($0.url) && seen.insert($0.url).inserted }
    let license = parsed.license.flatMap { url in
      PublicScienceSource.safe(url) && url.host == "creativecommons.org" ? url : nil
    }
    return .init(title: parsed.title, sections: parsed.sections, figures: figures,
                 attribution: parsed.attribution, license: license)
  }

  private func extract<T: Decodable>(html: String, source: PublicScienceSource, url: URL, catalog: Bool) async throws -> T {
    try await decode(html: html, script: Self.script, arguments: [
      "page": url.absoluteString, "bookSlug": source.rawValue,
      "isPDB": source == .molecule, "catalog": catalog
    ])
  }

  func decode<T: Decodable>(html: String, script: String, arguments: [String: Any] = [:]) async throws -> T {
    try Task.checkCancellation()
    guard html.utf8.count <= 5_000_000 else { throw PublicScienceError.tooLarge }
    let timeout = Task { @MainActor [weak self] in
      do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
      self?.finish(.failure(PublicScienceError.unavailable))
    }
    defer { timeout.cancel(); webView.stopLoading() }
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        readiness = continuation
        // Publisher markup is passed as data to an inert template, never loaded as a page.
        webView.loadHTMLString("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'\">",
                               baseURL: nil)
      }
    }, onCancel: { [weak self] in
      Task { @MainActor in self?.finish(.failure(CancellationError())) }
    })
    try Task.checkCancellation()
    var inputs = arguments
    inputs["html"] = html
    let value = try await webView.callAsyncJavaScript(script, arguments: inputs, in: nil, contentWorld: .defaultClient)
    try Task.checkCancellation()
    guard let json = value as? String, json.utf8.count <= 2_000_000 else { throw PublicScienceError.unreadable }
    return try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private func finish(_ result: Result<Void, Error>) {
    let current = readiness
    readiness = nil
    current?.resume(with: result)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(PublicScienceError.unavailable)) }

  static let script = #"""
    const inert = document.createElement("template");
    inert.innerHTML = html;
    const tree = inert.content;
    const clean = (text, limit) => (text || "").replace(/\s+/g, " ").trim().slice(0, limit);
    const plain = (text, limit) => {
      const label = document.createElement("template");
      label.innerHTML = typeof text === "string" ? text : "";
      return clean(label.content.textContent, limit);
    };
    const resolved = value => {
      if (!value) return null;
      try { return new URL(value, page); } catch (_) { return null; }
    };
    let book = null;
    if (!isPDB) {
      for (const script of tree.querySelectorAll("script:not([src])")) {
        const match = script.textContent.trim().match(/^window\.__PRELOADED_STATE__\s*=\s*/);
        if (!match) continue;
        try {
          const data = JSON.parse(script.textContent.trim().slice(match[0].length).replace(/;$/, ""));
          if (data.content?.book?.slug === bookSlug) { book = data.content.book; break; }
        } catch (_) {}
      }
    }
    if (catalog) {
      const entries = [];
      if (isPDB) {
        for (const link of tree.querySelectorAll("a[href]")) {
          const url = resolved(link.getAttribute("href"));
          const title = clean(link.textContent, 240);
          if (url?.origin === "https://pdb101.rcsb.org" && /^\/motm\/[0-9]{1,6}\/?$/.test(url.pathname) && title) {
            entries.push({url: url.href, title});
          }
          if (entries.length === 600) break;
        }
      } else {
        let visited = 0;
        const visit = (node, depth) => {
          if (!node || typeof node !== "object" || depth > 12 || ++visited > 4000) throw Error("invalid catalog");
          if (node.toc_target_type === "numbered-section" && /^[0-9]+-[0-9]+-[a-z0-9-]+$/.test(node.slug)) {
            const title = plain(node.title, 240);
            if (title && entries.length < 600) entries.push({url: new URL(node.slug, page).href, title});
          }
          if (Array.isArray(node.contents)) for (const child of node.contents) visit(child, depth + 1);
        };
        visit(book?.tree, 0);
      }
      return JSON.stringify(entries);
    }
    const regions = isPDB ? tree.querySelectorAll("[data-elastic-include]") :
      tree.querySelectorAll("#main-content [data-type='page']");
    if (regions.length !== 1) return null;
    const root = regions[0];
    root.querySelectorAll("script,style,nav,footer,[data-elastic-exclude],.nav-tabs,iframe,form").forEach(node => node.remove());
    const title = clean(root.querySelector("h1")?.textContent ||
      tree.querySelector("meta[property='og:title']")?.getAttribute("content") ||
      tree.querySelector("title")?.textContent, 500);
    const sections = [];
    let remaining = 250000;
    for (const node of root.querySelectorAll("h2,h3,h4,h5,h6,p,li,dt,dd")) {
      if (node.closest("figure,figcaption") || (node.tagName === "LI" && node.querySelector("p"))) continue;
      const text = clean(node.textContent, Math.min(remaining, 12000));
      if (!text) continue;
      sections.push({id: sections.length, heading: /^H[2-6]$/.test(node.tagName), text});
      remaining -= text.length;
      if (remaining <= 0 || sections.length === 350) break;
    }
    const figures = [];
    const seen = new Set();
    for (const img of root.querySelectorAll("img")) {
      const url = resolved(img.getAttribute("data-src") || img.getAttribute("src"));
      if (!url || url.protocol !== "https:" || seen.has(url.href)) continue;
      const container = img.closest("figure,[data-type='figure'],.motm-figure,.thumbnail");
      const caption = clean(container?.querySelector("figcaption,[data-type='caption'],.caption")?.textContent ||
        img.getAttribute("alt"), 1600);
      seen.add(url.href);
      figures.push({url: url.href, caption});
      if (figures.length === 60) break;
    }
    const attribution = [isPDB ? "RCSB PDB-101" : "OpenStax"];
    if (book?.title) attribution.push(plain(book.title, 240));
    if (Array.isArray(book?.authors)) {
      for (const author of book.authors.slice(0, 30)) {
        if (author?.value?.display_at_top && author.value.name) attribution.push(plain(author.value.name, 120));
      }
    }
    if (book?.license?.name) attribution.push(plain(book.license.name, 160));
    const license = typeof book?.license?.url === "string" ?
      book.license.url.replace(/^http:\/\/creativecommons\.org\//, "https://creativecommons.org/") : null;
    return JSON.stringify({title, sections, figures, attribution: attribution.filter(Boolean), license});
    """#
}
