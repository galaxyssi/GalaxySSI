import CryptoKit
import Foundation

enum PublicNewsArticleBodyError: Error {
  case unsupportedSource, incompleteSource, modelUnavailable, invalidTranslation, changedSource
}

struct PublicNewsOriginalBody: Codable, Equatable {
  let title: String
  let paragraphs: [String]

  var fingerprint: String {
    var sha = SHA256()
    for value in [title] + paragraphs {
      sha.update(data: Data(value.utf8))
      sha.update(data: Data([0]))
    }
    return sha.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

enum PublicNewsArticleBody {
  private static let supportedHosts: Set<String> = [
    "www.ithome.com", "github.blog", "www.chinanews.com.cn", "www.federalreserve.gov",
    "news.mit.edu", "journals.plos.org", "www.404media.co", "404media.co", "9to5google.com",
    "www.aboutamazon.com", "www.seangoedecke.com", "seangoedecke.com", "simonwillison.net"
  ]

  static func supports(_ url: URL) -> Bool {
    PublicScienceSource.safe(url) && url.absoluteString.utf8.count <= 2_048 && url.fragment == nil &&
      url.host.map { supportedHosts.contains($0.lowercased()) } == true && url.path.count > 1
  }

  @MainActor
  static func load(_ url: URL) async throws -> PublicNewsOriginalBody {
    guard supports(url) else { throw PublicNewsArticleBodyError.unsupportedSource }
    let data = try await PublicScienceTransport.fetch(url, limit: 3_000_000)
    guard let html = String(data: data, encoding: .utf8) else { throw PublicNewsArticleBodyError.incompleteSource }
    return try await extract(html)
  }

  @MainActor
  static func extract(_ html: String) async throws -> PublicNewsOriginalBody {
    let body: PublicNewsOriginalBody = try await PublicScienceDOM().decode(html: html, script: script)
    let count = body.paragraphs.reduce(0) { $0 + $1.count }
    guard !body.title.isEmpty, body.paragraphs.count >= 2, (240...80_000).contains(count) else {
      throw PublicNewsArticleBodyError.incompleteSource
    }
    return body
  }

  static let script = #"""
    const template = document.createElement("template");
    template.innerHTML = html;
    const tree = template.content;
    const clean = (text) => (text || "").replace(/\s+/g, " ").trim();
    if (tree.querySelector("[itemprop='isAccessibleForFree'][content='false'],[data-paywall='true']")) {
      return null;
    }
    const selector = "[itemprop='articleBody'],#article-body,#article_content,article .article-body,article .entry-content," +
      "#artibody,.article-text,.article-content,.article__content,.article-text-content";
    const region = tree.querySelector(selector) ||
      (tree.querySelectorAll("main article").length === 1 ? tree.querySelector("main article") : null) ||
      (tree.querySelectorAll("article").length === 1 ? tree.querySelector("article") : null);
    if (!region) return null;
    region.querySelectorAll("script,style,nav,aside,footer,form,iframe,.related,.advertisement,[role='navigation']")
      .forEach(node => node.remove());
    const title = clean(tree.querySelector("meta[property='og:title']")?.getAttribute("content") ||
      region.querySelector("h1")?.textContent || tree.querySelector("main h1")?.textContent ||
      tree.querySelector("title")?.textContent).slice(0, 500);
    const paragraphs = [];
    let total = 0;
    for (const item of region.querySelectorAll("p,h2,h3,h4,li,blockquote,tr")) {
      if (item.closest("figure,figcaption") || (item.tagName !== "P" && item.querySelector("p"))) continue;
      if (item.tagName !== "TR" && item.closest("table")) continue;
      const value = item.tagName === "TR" ?
        Array.from(item.cells).map(cell => clean(cell.textContent)).join(" | ") : clean(item.textContent);
      if (!value) continue;
      total += value.length;
      if (total > 80000 || paragraphs.length === 350) return null;
      paragraphs.push(value);
    }
    return JSON.stringify({title, paragraphs});
    """#
}
