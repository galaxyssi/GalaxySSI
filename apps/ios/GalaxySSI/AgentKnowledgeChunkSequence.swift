import Foundation

// Reiterable count pass, followed by one production input traversal. Retains
// the input string and one output chunk, not an array of paragraph bodies.
struct AgentKnowledgeChunkSequence: Sequence {
  let text: String
  let limit: Int
  init(_ content: String, limit: Int = 12_000) {
    text = content.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    self.limit = max(1, limit)
  }
  func makeIterator() -> Iterator { Iterator(text: text, limit: limit) }
  struct Iterator: IteratorProtocol {
    private let text: String, limit: Int
    private var position: String.Index
    private var current = "", longPart: Substring?
    private var finished = false
    private let single: Bool
    init(text: String, limit: Int) {
      self.text = text; self.limit = limit; position = text.startIndex
      let boundary = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex)
      single = boundary == nil || boundary == text.endIndex
    }
    mutating func next() -> String? {
      guard !finished else { return nil }
      if single { finished = true; return text.isEmpty ? nil : text }
      while true {
        if let part = longPart {
          let end = part.index(part.startIndex, offsetBy: limit, limitedBy: part.endIndex) ?? part.endIndex
          longPart = end == part.endIndex ? nil : part[end...]
          return String(part[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard position < text.endIndex else {
          finished = true
          return current.isEmpty ? nil : current
        }
        let separator = text.range(of: "\n\n", range: position..<text.endIndex)
        let end = separator?.lowerBound ?? text.endIndex
        let part = Self.trim(text[position..<end])
        position = separator?.upperBound ?? text.endIndex
        if part.isEmpty { continue }
        let boundary = part.index(part.startIndex, offsetBy: limit, limitedBy: part.endIndex)
        if let boundary, boundary != part.endIndex {
          longPart = part
          if !current.isEmpty { let result = current; current = ""; return result }
        } else if current.count + part.count + 2 > limit {
          let result = current; current = String(part)
          if !result.isEmpty { return result }
        } else { current = current.isEmpty ? String(part) : current + "\n\n" + String(part) }
      }
    }
    private static func trim(_ text: Substring) -> Substring {
      let scalars = text.unicodeScalars
      var start = scalars.startIndex, end = scalars.endIndex
      while start < end, CharacterSet.whitespacesAndNewlines.contains(scalars[start]) { start = scalars.index(after: start) }
      while start < end, CharacterSet.whitespacesAndNewlines.contains(scalars[scalars.index(before: end)]) { end = scalars.index(before: end) }
      return text[start..<end]
    }
  }
}
