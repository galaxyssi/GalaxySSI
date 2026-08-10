import Foundation

struct VoiceWhisperTimedSegment: Codable, Equatable {
  var startMillis: Int64
  var endMillis: Int64
  var text: String
  var averageLogProbability: Float?
  var noSpeechProbability: Float?
}

struct VoiceWhisperDecodedWindow: Codable, Equatable {
  var requestId: String
  var windowStartMillis: Int64
  var windowEndMillis: Int64
  var text: String
  var segments: [VoiceWhisperTimedSegment]
  var realTimeFactor: Double
  var final: Bool
}

struct VoiceWhisperStabilizedTranscript: Codable, Equatable {
  var stableText: String
  var unstableText: String
  var revision: Int
  var final: Bool

  var displayText: String {
    VoiceWhisperTranscriptText.join(stableText, unstableText)
  }
}

enum VoiceWhisperSegmentDecoder {
  static func decode(
    requestId: String,
    windowStartSample: Int64,
    windowEndSampleExclusive: Int64,
    sampleRateHz: Int = 16_000,
    result: VoiceNativeWhisperResult,
    final: Bool
  ) -> VoiceWhisperDecodedWindow {
    let safeSampleRate = max(sampleRateHz, 1)
    let windowStartMillis = max(0, windowStartSample) * 1_000 / Int64(safeSampleRate)
    let windowEndMillis = max(windowStartSample, windowEndSampleExclusive) * 1_000 / Int64(safeSampleRate)
    return VoiceWhisperDecodedWindow(
      requestId: requestId.trimmingCharacters(in: .whitespacesAndNewlines),
      windowStartMillis: windowStartMillis,
      windowEndMillis: windowEndMillis,
      text: VoiceWhisperTranscriptText.normalize(result.text),
      segments: result.segments.map { segment in
        VoiceWhisperTimedSegment(
          startMillis: windowStartMillis + max(0, segment.startMillis),
          endMillis: windowStartMillis + max(0, segment.endMillis),
          text: VoiceWhisperTranscriptText.normalize(segment.text),
          averageLogProbability: segment.averageLogProbability.isNaN ? nil : segment.averageLogProbability,
          noSpeechProbability: segment.noSpeechProbability.isNaN ? nil : segment.noSpeechProbability
        )
      },
      realTimeFactor: result.timings.realTimeFactor,
      final: final
    )
  }
}

final class VoiceWhisperTextStabilizer {
  private let stabilityLagMillis: Int64
  private let minimumAverageLogProbability: Float
  private let maximumNoSpeechProbability: Float
  private var stable = ""
  private var previousCandidate = ""
  private var revision = 0

  init(
    stabilityLagMillis: Int64 = 500,
    minimumAverageLogProbability: Float = -1.5,
    maximumNoSpeechProbability: Float = 0.60
  ) {
    self.stabilityLagMillis = max(0, stabilityLagMillis)
    self.minimumAverageLogProbability = minimumAverageLogProbability
    self.maximumNoSpeechProbability = maximumNoSpeechProbability
  }

  func accept(_ window: VoiceWhisperDecodedWindow) -> VoiceWhisperStabilizedTranscript {
    revision += 1
    if window.final {
      let finalText = VoiceWhisperTranscriptText.normalize(window.text)
      if !finalText.isEmpty {
        stable = collapseRepeatedFinalPrefix(finalText)
      }
      previousCandidate = stable
      return VoiceWhisperStabilizedTranscript(
        stableText: stable,
        unstableText: "",
        revision: revision,
        final: true
      )
    }

    let candidate = VoiceWhisperTranscriptText.mergeOverlap(prefix: stable, incoming: window.text)
    let common = commonPrefix(previousCandidate, candidate)
    let safeText = stableEligibleText(window)
    let safeCandidate = VoiceWhisperTranscriptText.mergeOverlap(prefix: stable, incoming: safeText)
    let promotionLimit = min(common.count, safeCandidate.count)
    if promotionLimit > stable.count, candidate.hasPrefix(stable) {
      let boundary = stableBoundary(candidate, limit: promotionLimit)
      if boundary > stable.count {
        stable = VoiceWhisperTranscriptText.trimEnd(String(candidate.prefix(boundary)))
      }
    }
    previousCandidate = candidate
    let unstable = candidate.hasPrefix(stable)
      ? String(candidate.dropFirst(stable.count)).trimmingCharacters(in: .whitespacesAndNewlines)
      : candidate
    return VoiceWhisperStabilizedTranscript(
      stableText: stable,
      unstableText: unstable,
      revision: revision,
      final: false
    )
  }

  func reset() {
    stable = ""
    previousCandidate = ""
    revision = 0
  }

  private func collapseRepeatedFinalPrefix(_ value: String) -> String {
    let evidence = stable.ifBlank(previousCandidate)
    let evidenceKey = canonicalEvidence(evidence)
    guard evidenceKey.count >= Self.minimumDuplicateEvidenceCharacters else {
      return value
    }

    let characters = Array(value)
    let maximumUnitEnd = characters.count / 2
    guard maximumUnitEnd >= Self.minimumDuplicateEvidenceCharacters else {
      return value
    }

    for unitEnd in stride(
      from: maximumUnitEnd,
      through: Self.minimumDuplicateEvidenceCharacters,
      by: -1
    ) {
      let first = String(characters.prefix(unitEnd)).trimmingCharacters(in: .whitespacesAndNewlines)
      let canonicalFirst = canonicalEvidence(first)
      guard canonicalFirst.count >= Self.minimumDuplicateEvidenceCharacters else {
        continue
      }

      var secondStart = unitEnd
      while secondStart < characters.count && characters[secondStart].isWhitespace {
        secondStart += 1
      }
      guard secondStart + Array(first).count <= characters.count else {
        continue
      }
      let second = String(characters.dropFirst(secondStart))
      guard second.hasPrefix(first) else {
        continue
      }

      let comparableLength = min(canonicalFirst.count, evidenceKey.count)
      var commonLength = 0
      for pair in zip(canonicalFirst, evidenceKey).prefix(comparableLength) {
        guard pair.0 == pair.1 else { break }
        commonLength += 1
      }
      guard commonLength >= Self.minimumDuplicateEvidenceCharacters,
            commonLength * 100 >= comparableLength * Self.minimumEvidenceMatchPercent else {
        continue
      }
      return second.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return value
  }

  private func canonicalEvidence(_ value: String) -> String {
    value.reduce(into: "") { result, character in
      if character.isLetter || character.isNumber || isCJK(character) {
        result.append(contentsOf: character.lowercased())
      }
    }
  }

  private func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
  }

  private func stableEligibleText(_ window: VoiceWhisperDecodedWindow) -> String {
    let latestStableEnd = window.windowEndMillis - stabilityLagMillis
    let combined = window.segments
      .filter { $0.endMillis <= latestStableEnd }
      .filter { ($0.averageLogProbability ?? 0) >= minimumAverageLogProbability }
      .filter { ($0.noSpeechProbability ?? 0) <= maximumNoSpeechProbability }
      .map(\.text)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .reduce("") { VoiceWhisperTranscriptText.join($0, $1) }
    return VoiceWhisperTranscriptText.normalize(combined)
  }

  private func stableBoundary(_ value: String, limit: Int) -> Int {
    guard limit > 0 else { return 0 }
    let characters = Array(value)
    let safe = min(limit, characters.count)
    if safe == characters.count {
      return safe
    }
    let next = characters[safe]
    if Self.isBoundary(next) {
      return safe
    }
    for index in stride(from: safe, through: 1, by: -1) {
      if Self.isBoundary(characters[index - 1]) {
        return index
      }
    }
    return 0
  }

  private func commonPrefix(_ first: String, _ second: String) -> String {
    let firstCharacters = Array(first)
    let secondCharacters = Array(second)
    var index = 0
    while index < min(firstCharacters.count, secondCharacters.count),
          firstCharacters[index] == secondCharacters[index] {
      index += 1
    }
    return String(firstCharacters.prefix(index))
  }

  private static func isBoundary(_ character: Character) -> Bool {
    character.isWhitespace || stablePunctuation.contains(character) || isCJK(character)
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
  }

  private static let stablePunctuation: Set<Character> = [
    ".", ",", "!", "?", ";", ":",
    "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1b}", "\u{ff1a}",
  ]
  private static let minimumDuplicateEvidenceCharacters = 6
  private static let minimumEvidenceMatchPercent = 70
}

enum VoiceWhisperTranscriptText {
  static func normalize(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .voiceReplacing(pattern: "\\s+", with: " ")
  }

  static func mergeOverlap(prefix: String, incoming: String) -> String {
    let left = normalize(prefix)
    let right = normalize(incoming)
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    if right.hasPrefix(left) { return right }
    if left.hasSuffix(right) { return left }
    let leftCharacters = Array(left)
    let rightCharacters = Array(right)
    let maximum = min(leftCharacters.count, rightCharacters.count)
    var overlap = 0
    for size in 1...maximum {
      if Array(leftCharacters.suffix(size)) == Array(rightCharacters.prefix(size)) {
        overlap = size
      }
    }
    return join(left, String(rightCharacters.dropFirst(overlap)))
  }

  static func join(_ first: String, _ second: String) -> String {
    let left = first.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = second.trimmingCharacters(in: .whitespacesAndNewlines)
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    let leftLast = left[left.index(before: left.endIndex)]
    let rightFirst = right[right.startIndex]
    let needsSpace = isLetterOrNumber(leftLast) &&
      isLetterOrNumber(rightFirst) &&
      !isCJK(leftLast) &&
      !isCJK(rightFirst)
    return needsSpace ? "\(trimEnd(left)) \(right)" : trimEnd(left) + right
  }

  static func trimEnd(_ value: String) -> String {
    var result = value
    while let last = result.unicodeScalars.last,
          CharacterSet.whitespacesAndNewlines.contains(last) {
      result.removeLast()
    }
    return result
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
  }

  private static func isLetterOrNumber(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
  }
}
