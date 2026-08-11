import Foundation

/// Keeps inline model tool protocols out of user-visible streaming text.
final class InlineToolProtocolStreamGuard {
  private static let maximumPendingTagCharacters = 1_024

  private var raw = ""
  private var pendingTag = ""
  private var suppressProtocol = false

  func append(_ fragment: String) -> String {
    guard !fragment.isEmpty else { return "" }
    raw.append(fragment)
    guard !suppressProtocol else { return "" }

    var visible = ""
    for character in fragment {
      guard !suppressProtocol else { break }
      if pendingTag.isEmpty {
        if character == "<" {
          pendingTag.append(character)
        } else {
          visible.append(character)
        }
        continue
      }

      pendingTag.append(character)
      if looksLikeInternalProtocol(pendingTag) {
        suppressProtocol = true
        pendingTag = ""
      } else if character == ">" || pendingTag.count >= Self.maximumPendingTagCharacters {
        visible.append(contentsOf: pendingTag)
        pendingTag = ""
      }
    }
    return visible
  }

  func finishVisibleText() -> String {
    guard !suppressProtocol, !pendingTag.isEmpty else { return "" }
    defer { pendingTag = "" }
    return CloudWebGrounding.containsInternalToolProtocol(raw) ? "" : pendingTag
  }

  func rawText() -> String {
    raw
  }

  private func looksLikeInternalProtocol(_ candidate: String) -> Bool {
    let lower = candidate.lowercased()
    return lower.contains("dsml") || lower.contains("tool_calls") ||
      (candidate.hasSuffix(">") && CloudWebGrounding.containsInternalToolProtocol(candidate))
  }
}
