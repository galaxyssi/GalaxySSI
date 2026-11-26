import Foundation

// Deterministic metadata hints from untrusted text, not semantic verification.
enum AgentIOSWebLocalExtraction {
  static func requestedFields(_ input: AgentMcpJSONValue?) -> [String] {
    var seen = Set<[UInt16]>(), result: [String] = []
    for value in input?.arrayValue ?? [] {
      guard let raw = value.stringValue else { continue }
      let clean = bounded(raw.trimmingCharacters(in: .whitespacesAndNewlines), limit: 128)
      guard !clean.isEmpty, seen.insert(Array(clean.utf16)).inserted else { continue }
      result.append(clean)
      if result.count == 100 { break }
    }
    return result
  }

  static func structured(title: String, url: String, content: String, links: [String], fields: [String],
    checkpoint: () throws -> Void = {}) throws -> AgentMcpJSONObject {
    try checkpoint()
    var headings: [String] = [], seen = Set<[UInt16]>()
    let lines = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    for raw in lines {
      try checkpoint()
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines), count = line.utf16.count
      guard (3...160).contains(count), line.hasPrefix("#") || (count < 100 && !line.contains(where: { ".!?;:".contains($0) })) else { continue }
      let units = line.utf16.drop(while: { $0 == 35 || $0 == 32 })
      let heading = String(decoding: units, as: UTF16.self)
      if seen.insert(Array(heading.utf16)).inserted { headings.append(heading) }
      if headings.count == 100 { break }
    }
    var result: AgentMcpJSONObject = ["title": .string(title), "url": .string(url),
      "headings": .array(headings.map(AgentMcpJSONValue.string)), "links": .array(links.prefix(100).map(AgentMcpJSONValue.string)),
      "language": .string(language(content))]
    if !fields.isEmpty {
      var requested: AgentMcpJSONObject = [:]
      for field in fields.prefix(100) {
        try checkpoint()
        let escaped = NSRegularExpression.escapedPattern(for: field.trimmingCharacters(in: .whitespacesAndNewlines))
        let regex = try NSRegularExpression(pattern: "^\\s*" + escaped + "\\s*[:=]\\s*(.{1,500})$",
          options: [.caseInsensitive, .anchorsMatchLines])
        let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content))
        let value = match.flatMap { Range($0.range(at: 1), in: content) }.map { String(content[$0]) } ?? ""
        requested[field] = .string(value)
      }
      result["requested"] = .object(requested)
    }
    try checkpoint()
    return result
  }

  static func language(_ content: String) -> String {
    if content.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) { return "zh" }
    if content.unicodeScalars.contains(where: { (0x3040...0x30ff).contains($0.value) }) { return "ja" }
    if content.unicodeScalars.contains(where: { (0xac00...0xd7af).contains($0.value) }) { return "ko" }
    return "en"
  }
  private static func bounded(_ value: String, limit: Int) -> String {
    var units = Array(value.utf16.prefix(limit))
    if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
    return String(decoding: units, as: UTF16.self)
  }
}
