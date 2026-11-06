import CoreFoundation
import Foundation

enum AgentIOSWebTextDecoder {
  static let version: Int64 = 1

  struct Decoded {
    let text: String
    let charset: String
    let lossless: Bool
  }

  static func decode(_ body: Data, contentType: String) -> Decoded {
    if let marker = byteOrderMarks.first(where: { body.starts(with: $0.bytes) }) {
      let bytes = body.dropFirst(marker.bytes.count)
      let value = String(data: bytes, encoding: marker.encoding)
      return Decoded(text: value ?? String(decoding: bytes, as: UTF8.self),
        charset: marker.label, lossless: value != nil)
    }

    let prefix = String(decoding: body.prefix(8_192), as: UTF8.self)
    let html = isHTML(contentType: contentType, textPrefix: prefix)
    let labels = [charsetParameter(in: contentType), html ? metaCharset(in: prefix) : nil, "UTF-8"]
    for label in labels.compactMap({ $0 }) {
      let encoding = CFStringConvertIANACharSetNameToEncoding(label as CFString)
      guard encoding != kCFStringEncodingInvalidId,
            let text = String(data: body, encoding: String.Encoding(
              rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)
            )) else { continue }
      return Decoded(text: String(text.drop(while: { $0 == "\u{FEFF}" })),
        charset: label.uppercased(), lossless: true)
    }
    return Decoded(text: String(decoding: body, as: UTF8.self), charset: "UTF-8", lossless: false)
  }

  static func isHTML(contentType: String, textPrefix: String) -> Bool {
    if contentType.localizedCaseInsensitiveContains("html") { return true }
    let prefix = textPrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html")
  }

  static func reusable(content: String, metadata: [String: String]) -> Bool {
    if let status = metadata["text_decoding_lossless"] { return status == "true" }
    return !content.contains("\u{FFFD}")
  }

  private static func charsetParameter(in value: String) -> String? {
    firstCapture(in: value, pattern: #"(?i)(?:^|;)\s*charset\s*=\s*["']?([a-z0-9._:-]{1,40})(?=["'\s;]|$)"#)
  }

  private static func metaCharset(in prefix: String) -> String? {
    let scanned = prefix
      .replacingOccurrences(of: #"(?is)<!--.*?(?:-->|$)|<script\b[^>]*>.*?(?:</script\s*>|$)"#,
        with: "", options: .regularExpression)
    let end = scanned.range(of: "</head>", options: .caseInsensitive)?.lowerBound ?? scanned.endIndex
    let head = String(scanned[..<end])
    guard let pattern = try? NSRegularExpression(pattern: #"(?i)<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>"#) else { return nil }
    for match in pattern.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
      guard let range = Range(match.range, in: head) else { continue }
      let tag = String(head[range])
      let attributes = metaAttributes(tag)
      if let charset = attributes["charset"], validLabel(charset) { return charset }
      if attributes["http-equiv"]?.lowercased() == "content-type", let content = attributes["content"],
         let charset = charsetParameter(in: content) { return charset }
    }
    return nil
  }

  private static func metaAttributes(_ tag: String) -> [String: String] {
    guard let pattern = try? NSRegularExpression(
      pattern: #"(?i)\s+([a-z-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
    ) else { return [:] }
    return pattern.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)).reduce(into: [:]) { result, match in
      guard let key = Range(match.range(at: 1), in: tag),
            let value = (2...4).compactMap({ Range(match.range(at: $0), in: tag) }).first else { return }
      result[String(tag[key]).lowercased()] = String(tag[value]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func validLabel(_ value: String) -> Bool {
    value.range(of: #"^[a-zA-Z0-9._:-]{1,40}$"#, options: .regularExpression) != nil
  }

  private static func firstCapture(in value: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value) else { return nil }
    return String(value[range])
  }

  private static let byteOrderMarks: [(bytes: [UInt8], encoding: String.Encoding, label: String)] = [
    ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian, "UTF-32BE"),
    ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian, "UTF-32LE"),
    ([0xEF, 0xBB, 0xBF], .utf8, "UTF-8"),
    ([0xFE, 0xFF], .utf16BigEndian, "UTF-16BE"),
    ([0xFF, 0xFE], .utf16LittleEndian, "UTF-16LE")
  ]
}
