import Foundation
import SwiftSoup

struct AgentIOSOriginalPageAsset {
  var contentType: String
  var data: Data
  var finalURL: String
}

struct AgentIOSOriginalPageDocument {
  var data: Data
  var embeddedImages: Int
  var missingAssets: Int

  static let maximumSourceBytes = 8 * 1_024 * 1_024
  static let maximumAssetBytes = 24 * 1_024 * 1_024
  static let maximumOutputBytes = 48 * 1_024 * 1_024
  private static let imageTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif"]

  static func build(source: Data, url: String, language: String,
                    load: (String, Int) -> AgentIOSOriginalPageAsset?) throws -> Self {
    guard !source.isEmpty, source.count <= maximumSourceBytes,
          let base = publicURL(url, relativeTo: url) else { throw CocoaError(.fileReadCorruptFile) }
    let decoded = AgentIOSWebTextDecoder.decode(source, contentType: "text/html")
    guard decoded.lossless else { throw CocoaError(.fileReadInapplicableStringEncoding) }
    let document = try SwiftSoup.parse(decoded.text, base)
    guard let head = document.head(), let body = document.body() else { throw CocoaError(.fileReadCorruptFile) }
    // Parse only: publisher markup is never loaded into a browser or executed.
    try document.select("script,iframe,object,embed,svg,math,canvas,template,noscript,input,button,select,textarea,base,meta").remove()
    for form in try document.select("form").array() { _ = try form.unwrap() }
    var remaining = maximumAssetBytes, embedded = 0, missing = Set<String>()
    var encodedRemaining = maximumOutputBytes - source.count
    var assets: [String: AgentIOSOriginalPageAsset] = [:], attempted = Set<String>()
    func asset(_ address: String) -> AgentIOSOriginalPageAsset? {
      if let cached = assets[address] { return cached }
      guard attempted.count < 128, remaining > 0, attempted.insert(address).inserted,
            let item = load(address, min(8 * 1_024 * 1_024, remaining)),
            !item.data.isEmpty, item.data.count <= min(8 * 1_024 * 1_024, remaining),
            publicURL(item.finalURL, relativeTo: address) != nil else { return nil }
      remaining -= item.data.count
      assets[address] = item
      return item
    }
    func image(_ value: String, _ baseURL: String) -> String? {
      if value.lowercased().hasPrefix("data:") {
        guard let comma = value.firstIndex(of: ",") else { return nil }
        let header = String(value[..<comma]).lowercased()
        let type = String(header.dropFirst(5)).components(separatedBy: ";").first ?? ""
        guard imageTypes.contains(type), header == "data:\(type);base64",
              value.utf8.count <= 12 * 1_024 * 1_024,
              let bytes = Data(base64Encoded: String(value[value.index(after: comma)...])),
              !bytes.isEmpty, bytes.count <= min(8 * 1_024 * 1_024, remaining) else { return nil }
        guard bytes.count * 4 / 3 + 128 <= encodedRemaining else { return nil }
        encodedRemaining -= bytes.count * 4 / 3 + 128
        remaining -= bytes.count
        embedded += 1
        return "data:\(type);base64,\(bytes.base64EncodedString())"
      }
      guard let address = publicURL(value, relativeTo: baseURL), let item = asset(address),
            imageTypes.contains(item.contentType.lowercased()),
            item.data.count * 4 / 3 + 128 <= encodedRemaining else { return nil }
      encodedRemaining -= item.data.count * 4 / 3 + 128
      embedded += 1
      return "data:\(item.contentType.lowercased());base64,\(item.data.base64EncodedString())"
    }
    // Article images precede optional decoration requests in the shared byte budget.
    for img in try document.select("img").array() {
      let original = try ["data-src", "data-original", "data-lazy-src", "src"]
        .map { try img.attr($0) }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
      for key in ["srcset", "sizes", "loading", "data-src", "data-original", "data-lazy-src"] { try img.removeAttr(key) }
      if let local = image(original, base) { try img.attr("src", local) }
      else {
        missing.insert(publicURL(original, relativeTo: base) ?? original)
        try img.removeAttr("src")
        if try img.attr("alt").isEmpty { try img.attr("alt", copy("image", language: language)) }
      }
    }
    var decorations = 0
    func css(_ text: String, _ baseURL: String) throws -> String {
      let expression = try NSRegularExpression(pattern: #"(?is)url\(\s*(['"]?)(.*?)\1\s*\)"#)
      var output = text
      for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
        guard let valueRange = Range(match.range(at: 2), in: text), let range = Range(match.range, in: output) else { continue }
        let value = String(text[valueRange])
        let address = publicURL(value, relativeTo: baseURL)
        let mayLoad = value.lowercased().hasPrefix("data:") || address.map { assets[$0] != nil } == true || decorations < 8
        decorations += 1
        let local = mayLoad ? image(value, baseURL) : nil
        if local == nil { missing.insert(address ?? value) }
        output.replaceSubrange(range, with: "url(\"\(local ?? "")\")")
      }
      // CSP is the network boundary even for escaped/unsupported CSS syntax.
      return output.replacingOccurrences(of: #"(?is)@import\s+[^;]+;?"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: "</", with: "<\\/")
    }
    // Rewrite each stylesheet once, using its final redirected URL as the CSS base.
    for style in try document.select("style").array() {
      let rewritten = try css(style.data(), base)
      _ = style.empty()
      try style.appendChild(DataNode(rewritten, base))
    }
    for link in try document.select("link").array() {
      let href = try link.attr("href")
      if try link.attr("rel").lowercased() == "stylesheet",
         let address = publicURL(href, relativeTo: base), let item = asset(address),
         item.contentType.lowercased() == "text/css",
         item.data.count <= encodedRemaining,
         let text = String(data: item.data, encoding: .utf8) {
        let rewritten = try css(text, item.finalURL)
        guard rewritten.utf8.count <= encodedRemaining else {
          missing.insert(address)
          try link.remove()
          continue
        }
        encodedRemaining -= rewritten.utf8.count
        let style = Element(try Tag.valueOf("style"), base)
        try style.appendChild(DataNode(rewritten, base))
        try link.replaceWith(style)
      } else {
        missing.insert(publicURL(href, relativeTo: base) ?? href)
        try link.remove()
      }
    }
    for media in try document.select("picture source,video,audio").array() {
      missing.insert("media:\(media.tagName())")
      let placeholder = Element(try Tag.valueOf("span"), base)
      try placeholder.text(copy("media", language: language))
      try media.replaceWith(placeholder)
    }
    let attributes: Set<String> = ["id", "class", "style", "title", "lang", "dir", "role", "aria-label",
      "width", "height", "alt", "colspan", "rowspan", "align", "border", "cellspacing", "cellpadding"]
    for element in try document.getAllElements().array() {
      for attribute in element.getAttributes()?.asList() ?? [] {
        let key = attribute.getKey().lowercased()
        let imageSource = element.tagName() == "img" && key == "src"
        let anchor = element.tagName() == "a" && key == "href"
        if !attributes.contains(key) && !imageSource && !anchor { try element.removeAttr(attribute.getKey()) }
      }
      if element.hasAttr("style") { try element.attr("style", css(element.attr("style"), base)) }
      if element.tagName() == "a", element.hasAttr("href") {
        let href = try element.attr("href")
        if href.hasPrefix("#") { continue }
        if let address = publicURL(href, relativeTo: base) {
          try element.attr("href", address).attr("rel", "noopener noreferrer")
        } else { try element.removeAttr("href") }
      }
    }
    for content in try document.select("#js_content,.rich_media_content").array() {
      try content.attr("style", content.attr("style") + ";visibility:visible!important;opacity:1!important;")
    }
    try head.prependElement("meta").attr("charset", "utf-8")
    try head.prependElement("meta").attr("http-equiv", "Content-Security-Policy").attr("content",
      "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'")
    try head.appendElement("meta").attr("name", "referrer").attr("content", "no-referrer")
    try head.appendElement("meta").attr("name", "galaxyssi-archive-missing-assets").attr("content", String(missing.count))
    try body.appendElement("p").attr("style", "font:12px sans-serif;color:#666;white-space:normal")
      .text(String(format: copy("notice", language: language), Int64(missing.count), base))
    let data = Data(try document.outerHtml().utf8)
    guard data.count <= maximumOutputBytes else { throw CocoaError(.fileWriteOutOfSpace) }
    return Self(data: data, embeddedImages: embedded, missingAssets: missing.count)
  }

  private static func publicURL(_ value: String, relativeTo base: String) -> String? {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let parent = URL(string: base), let url = URL(string: value, relativeTo: parent)?.absoluteURL,
          url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
          !AgentIOSPublicAddressPolicy.blocksHost(host), url.user == nil, url.password == nil,
          url.port == nil || url.port == 443 else { return nil }
    return url.absoluteString
  }

  private static func copy(_ key: String, language: String) -> String {
    let locale = LanguagePolicySettings.resolveInterface(language).hasPrefix("zh") ? "zh-Hans" : "en"
    let bundle = Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return bundle.localizedString(forKey: "original_page_archive_" + key, value: nil, table: "WeChatArticleExportNative")
  }
}
