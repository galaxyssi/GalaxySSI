import Foundation
import SwiftSoup

enum AgentIOSArxivSearchAdapter {
  static let entry = AgentIOSJSONWebSearchAdapter.Entry(id: "arxiv", title: "arXiv", vertical: .academic,
    template: "https://export.arxiv.org/api/query?max_results={limit}&search_query=all:{query}", authority: 0.9)

  static func parse(_ data: Data, limit: Int, isCancelled: @escaping () -> Bool = { false }) throws -> [AgentIOSPublicSearchParser.Hit] {
    guard limit > 0 else { return [] }
    guard data.count <= 2_097_152, let text = String(data: data, encoding: .utf8),
      text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    let delegate = AtomDelegate(limit: min(limit, 100), isCancelled: isCancelled)
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    let valid = parser.parse()
    if delegate.cancelled { throw AgentIOSURLSessionWebError.cancelled }
    guard valid, delegate.isFeed, !delegate.invalid else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    return delegate.hits
  }

  private final class AtomDelegate: NSObject, XMLParserDelegate {
    let limit: Int
    let isCancelled: () -> Bool
    var hits: [AgentIOSPublicSearchParser.Hit] = []
    var seen = Set<String>()
    var isFeed = false
    var invalid = false
    var cancelled = false
    var depth = 0
    var inEntry = false
    var fields: [String: String] = [:]
    var field: String?
    var fieldDepth = 0
    init(limit: Int, isCancelled: @escaping () -> Bool) { self.limit = limit; self.isCancelled = isCancelled }

    private func checkpoint(_ parser: XMLParser) -> Bool {
      if isCancelled() { cancelled = true; parser.abortParsing(); return false }
      return !invalid
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
      guard checkpoint(parser) else { return }
      depth += 1
      guard depth <= 32 else { invalid = true; parser.abortParsing(); return }
      let atom = namespaceURI == nil || namespaceURI == "" || namespaceURI == "http://www.w3.org/2005/Atom"
      if depth == 1 {
        isFeed = elementName == "feed" && atom
        if !isFeed { invalid = true; parser.abortParsing() }
      } else if depth == 2, atom, elementName == "entry" {
        inEntry = true; fields = [:]; field = nil
      } else if inEntry, depth == 3, atom {
        if ["title", "summary", "id"].contains(elementName) { field = elementName; fieldDepth = depth }
        if elementName == "link", ["", "alternate"].contains(attributeDict["rel"] ?? ""), let href = attributeDict["href"] {
          fields["link"] = String(href.prefix(4097))
        }
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard checkpoint(parser), inEntry, let field else { return }
      let value = (fields[field] ?? "") + string
      guard value.utf8.count <= 32_768 else { invalid = true; parser.abortParsing(); return }
      fields[field] = value
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
      guard let text = String(data: CDATABlock, encoding: .utf8) else { invalid = true; parser.abortParsing(); return }
      self.parser(parser, foundCharacters: text)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
      guard checkpoint(parser) else { return }
      if fieldDepth == depth { field = nil }
      if depth == 2, inEntry, elementName == "entry" {
        defer { inEntry = false; fields = [:] }
        if hits.count < limit {
          let link = (fields["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          let raw = link.isEmpty ? (fields["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : link
          if raw.hasPrefix("https://") || raw.hasPrefix("http://"),
            let url = AgentIOSPublicSearchParser.destination(raw, baseURL: "https://export.arxiv.org/"),
            let host = URL(string: url)?.host?.lowercased(), AgentIOSWebSourceLearningPolicy.validHost(host) {
            do {
              let title = String(try SwiftSoup.parse(fields["title"] ?? "").text().prefix(2048))
              if !title.isEmpty, seen.insert(url).inserted {
                hits.append(.init(title: title, url: url,
                  excerpt: String(try SwiftSoup.parse(fields["summary"] ?? "").text().prefix(2048))))
              }
            } catch { invalid = true; parser.abortParsing() }
          }
        }
      }
      depth -= 1
    }

    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
      invalid = true; parser.abortParsing(); return nil
    }
  }
}
