import Foundation

enum AgentInlineStyle: String, Codable, CaseIterable, Identifiable {
  case normal = "NORMAL"
  case bold = "BOLD"
  case italic = "ITALIC"
  case strike = "STRIKE"
  case code = "CODE"
  case link = "LINK"

  var id: String { rawValue }
}

struct AgentInlineSegment: Codable, Equatable {
  var text: String
  var style: AgentInlineStyle
  var url: String

  init(
    text: String,
    style: AgentInlineStyle = .normal,
    url: String = ""
  ) {
    self.text = text
    self.style = style
    self.url = url
  }
}

enum AgentInlineMarkdown {
  static func parse(_ value: String) -> [AgentInlineSegment] {
    guard !value.isEmpty else { return [] }
    var result: [AgentInlineSegment] = []
    var cursor = value.startIndex
    while cursor < value.endIndex {
      let candidates = tokens.compactMap { token in
        firstMatch(pattern: token.pattern, style: token.style, in: value, from: cursor)
      }
      guard let next = candidates.min(by: { $0.range.lowerBound < $1.range.lowerBound }) else {
        result.append(AgentInlineSegment(text: String(value[cursor...])))
        break
      }
      if next.range.lowerBound > cursor {
        result.append(AgentInlineSegment(text: String(value[cursor..<next.range.lowerBound])))
      }
      if next.style == .link, next.groups.count >= 2 {
        result.append(AgentInlineSegment(text: next.groups[0], style: next.style, url: next.groups[1]))
      } else {
        result.append(AgentInlineSegment(text: next.groups.first ?? "", style: next.style))
      }
      cursor = next.range.upperBound
    }
    return result.filter { !$0.text.isEmpty }
  }

  private static func firstMatch(
    pattern: String,
    style: AgentInlineStyle,
    in value: String,
    from cursor: String.Index
  ) -> MatchCandidate? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let searchRange = NSRange(cursor..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, options: [], range: searchRange),
          let range = Range(match.range, in: value) else {
      return nil
    }
    var groups: [String] = []
    for index in 1..<match.numberOfRanges {
      if let groupRange = Range(match.range(at: index), in: value) {
        groups.append(String(value[groupRange]))
      } else {
        groups.append("")
      }
    }
    return MatchCandidate(style: style, range: range, groups: groups)
  }

  private struct Token {
    var style: AgentInlineStyle
    var pattern: String
  }

  private struct MatchCandidate {
    var style: AgentInlineStyle
    var range: Range<String.Index>
    var groups: [String]
  }

  private static let tokens = [
    Token(style: .bold, pattern: #"\*\*([^*\n]+)\*\*"#),
    Token(style: .strike, pattern: #"~~([^~\n]+)~~"#),
    Token(style: .link, pattern: #"\[([^\]\n]+)\]\((https?://[^\)\s]+)\)"#),
    Token(style: .code, pattern: #"`([^`\n]+)`"#),
    Token(style: .italic, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
  ]
}
