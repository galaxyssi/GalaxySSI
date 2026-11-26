import Foundation

enum AgentIOSWebPageDiff {
  struct Report: Equatable {
    var text: String
    var removedLines: Int
    var addedLines: Int
    var truncated: Bool
  }
  private struct Lines {
    var ordered: [String] = []
    var keys: Set<[UInt16]> = []
  }

  // Match the reference ordered set difference, not a positional/edit-distance diff.
  static func summarize(previous: String, current: String, checkpoint: () throws -> Void = {}) throws -> Report {
    let before = try lines(previous, checkpoint: checkpoint), after = try lines(current, checkpoint: checkpoint)
    let removed = before.ordered.filter { !after.keys.contains(Array($0.utf16)) }
    let added = after.ordered.filter { !before.keys.contains(Array($0.utf16)) }
    var output: [String] = [], truncated = removed.count > 40 || added.count > 40
    for (prefix, values) in [("- ", removed), ("+ ", added)] {
      for line in values.prefix(40) {
        try checkpoint()
        if line.utf16.count > 300 { truncated = true }
        output.append(prefix + bounded(line, length: 300))
      }
    }
    let text = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    try checkpoint()
    return Report(text: bounded(text, length: 32_768), removedLines: removed.count, addedLines: added.count,
      truncated: truncated || text.utf16.count > 32_768)
  }

  private static func lines(_ content: String, checkpoint: () throws -> Void) throws -> Lines {
    try checkpoint()
    var result = Lines()
    for raw in content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
      try checkpoint()
      let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty && result.keys.insert(Array(value.utf16)).inserted { result.ordered.append(value) }
    }
    return result
  }
  private static func bounded(_ value: String, length: Int) -> String {
    var units = Array(value.utf16.prefix(length))
    if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
    return String(decoding: units, as: UTF16.self)
  }
}
