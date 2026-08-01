import Foundation

struct VoiceTextPattern {
  private let regex: NSRegularExpression

  init(_ pattern: String, options: NSRegularExpression.Options = []) {
    self.regex = try! NSRegularExpression(pattern: pattern, options: options)
  }

  func containsMatch(in text: String) -> Bool {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, options: [], range: range) != nil
  }

  func matches(in text: String, group: Int = 0) -> [String] {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, options: [], range: range).compactMap { match in
      guard group < match.numberOfRanges,
            let swiftRange = Range(match.range(at: group), in: text) else {
        return nil
      }
      return String(text[swiftRange])
    }
  }
}

extension String {
  func voiceNormalizedTranscript() -> String {
    voiceNFKC()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .voiceReplacing(pattern: "[\\p{P}\\p{Z}\\s]+", with: "")
  }

  func voiceNormalizedForMatching() -> String {
    voiceNFKC()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .voiceReplacing(pattern: "\\s+", with: " ")
  }

  func voiceNormalizedEntityValue() -> String {
    voiceNFKC()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .voiceReplacing(pattern: "\\s+", with: "")
  }

  func voiceNFKC() -> String {
    (self as NSString).precomposedStringWithCompatibilityMapping
  }

  func voiceReplacing(pattern: String, with replacement: String) -> String {
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(startIndex..<endIndex, in: self)
    return regex.stringByReplacingMatches(
      in: self,
      options: [],
      range: range,
      withTemplate: replacement
    )
  }

  func voiceTrimEndPunctuation() -> String {
    var result = self.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = result.unicodeScalars.last,
          CharacterSet.whitespacesAndNewlines.contains(last) || Self.voiceEndPunctuation.contains(last) {
      result.removeLast()
    }
    return result
  }

  private static let voiceEndPunctuation = CharacterSet(charactersIn: ",.;:!?)]}>\u{ff0c}\u{3002}\u{ff1b}\u{ff1a}\u{ff01}\u{ff1f}\u{ff09}\u{3011}\u{300b}")
}
