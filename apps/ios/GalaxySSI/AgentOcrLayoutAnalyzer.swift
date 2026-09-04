import Foundation

enum AgentOcrScript: String, Codable, CaseIterable, Identifiable {
  case auto = "auto"
  case latin = "latin"
  case chinese = "chinese"
  case japanese = "japanese"
  case korean = "korean"
  case devanagari = "devanagari"

  var id: String { rawValue }

  var languageTag: String {
    switch self {
    case .auto:
      return "und"
    case .latin:
      return "Latn"
    case .chinese:
      return "zh"
    case .japanese:
      return "ja"
    case .korean:
      return "ko"
    case .devanagari:
      return "Deva"
    }
  }

  static func fromWireValue(_ value: String?) -> AgentOcrScript? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self)) ?? .auto
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentOcrLine: Codable, Equatable {
  var text: String
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int
  var languageTag: String
  var blockIndex: Int
  var lineIndex: Int

  init(
    text: String,
    left: Int = 0,
    top: Int = 0,
    right: Int = 0,
    bottom: Int = 0,
    languageTag: String = "",
    blockIndex: Int = 0,
    lineIndex: Int = 0
  ) {
    self.text = text
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
    self.languageTag = languageTag
    self.blockIndex = blockIndex
    self.lineIndex = lineIndex
  }

  enum CodingKeys: String, CodingKey {
    case text
    case left
    case top
    case right
    case bottom
    case languageTag = "language_tag"
    case blockIndex = "block_index"
    case lineIndex = "line_index"
  }
}

struct AgentOcrBlock: Codable, Equatable {
  var text: String
  var left: Int
  var top: Int
  var right: Int
  var bottom: Int
  var lineCount: Int

  enum CodingKeys: String, CodingKey {
    case text
    case left
    case top
    case right
    case bottom
    case lineCount = "line_count"
  }
}

struct AgentOcrCandidate: Equatable {
  var script: AgentOcrScript
  var fallbackText: String
  var lines: [AgentOcrLine]
}

struct AgentOcrMergedLayout: Equatable {
  var text: String
  var lines: [AgentOcrLine]
  var blocks: [AgentOcrBlock]
  var languageTags: [String]
  var layoutMode: String
  var qualityScore: Double
  var warnings: [String]
}

enum AgentOcrLayoutAnalyzer {
  static func merge(
    candidates: [AgentOcrCandidate],
    width: Int,
    height: Int
  ) -> AgentOcrMergedLayout {
    let usable = candidates.compactMap { candidate -> AgentOcrCandidate? in
      let lines = candidate.lines
        .map { line -> AgentOcrLine in
          var clean = line
          clean.text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
          return clean
        }
        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validBounds($0) }
      let fallbackText = candidate.fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !fallbackText.isEmpty || !lines.isEmpty else {
        return nil
      }
      return AgentOcrCandidate(script: candidate.script, fallbackText: fallbackText, lines: lines)
    }
    guard !usable.isEmpty else {
      return AgentOcrMergedLayout(
        text: "",
        lines: [],
        blocks: [],
        languageTags: [],
        layoutMode: "empty",
        qualityScore: 0.0,
        warnings: ["no_readable_text"]
      )
    }

    let ranked = usable.sorted { candidateScore($0) > candidateScore($1) }
    var merged: [AgentOcrLine] = []
    for candidate in ranked {
      for sourceLine in candidate.lines {
        var line = sourceLine
        if line.languageTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          line.languageTag = candidate.script.languageTag
        }
        if let duplicateIndex = merged.firstIndex(where: { duplicate($0, line) }) {
          let existing = merged[duplicateIndex]
          if lineScore(line, script: candidate.script) > lineScore(existing, script: scriptFor(existing)) {
            merged[duplicateIndex] = line
          }
        } else {
          merged.append(line)
        }
      }
    }

    let ordered = merged.sorted {
      if $0.top != $1.top { return $0.top < $1.top }
      if $0.left != $1.left { return $0.left < $1.left }
      if $0.blockIndex != $1.blockIndex { return $0.blockIndex < $1.blockIndex }
      return $0.lineIndex < $1.lineIndex
    }
    let structured = structureBlocks(ordered)
    let primary = ranked[0]
    let text = structured.lines.map(\.text).joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(primary.fallbackText)
    let tags = unique(
      structured.lines
        .map(\.languageTag)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    ).ifEmpty([primary.script.languageTag])
    let layout = layoutMode(blocks: structured.blocks, lines: structured.lines, width: width)
    let quality = qualityScore(text: text, lines: structured.lines)
    var warnings: [String] = []
    if min(width, height) >= 1 && min(width, height) <= lowResolutionEdge {
      warnings.append("low_resolution")
    }
    if quality < lowQualityThreshold {
      warnings.append("low_ocr_quality")
    }
    if tags.count > 1 {
      warnings.append("mixed_script")
    }
    if structured.lines.isEmpty {
      warnings.append("text_without_layout")
    }
    return AgentOcrMergedLayout(
      text: text,
      lines: structured.lines,
      blocks: structured.blocks,
      languageTags: tags,
      layoutMode: layout,
      qualityScore: quality,
      warnings: warnings
    )
  }

  private static func structureBlocks(_ lines: [AgentOcrLine]) -> (blocks: [AgentOcrBlock], lines: [AgentOcrLine]) {
    guard !lines.isEmpty else {
      return ([], [])
    }
    let grouped = Dictionary(grouping: lines) { line in
      "\(line.languageTag)\u{001f}\(line.blockIndex)"
    }
    let sourceGroups = grouped.values
      .map { group in
        group.sorted {
          if $0.top != $1.top { return $0.top < $1.top }
          return $0.left < $1.left
        }
      }
      .sorted {
        let leftTop = $0.map(\.top).min() ?? 0
        let rightTop = $1.map(\.top).min() ?? 0
        if leftTop != rightTop { return leftTop < rightTop }
        return ($0.map(\.left).min() ?? 0) < ($1.map(\.left).min() ?? 0)
      }
    var blocks: [AgentOcrBlock] = []
    var outputLines: [AgentOcrLine] = []
    for (blockIndex, group) in sourceGroups.enumerated() {
      let normalized = group.enumerated().map { lineIndex, line -> AgentOcrLine in
        var output = line
        output.blockIndex = blockIndex
        output.lineIndex = lineIndex
        return output
      }
      outputLines.append(contentsOf: normalized)
      blocks.append(
        AgentOcrBlock(
          text: normalized.map(\.text).joined(separator: "\n"),
          left: normalized.map(\.left).min() ?? 0,
          top: normalized.map(\.top).min() ?? 0,
          right: normalized.map(\.right).max() ?? 0,
          bottom: normalized.map(\.bottom).max() ?? 0,
          lineCount: normalized.count
        )
      )
    }
    return (blocks, outputLines)
  }

  private static func layoutMode(blocks: [AgentOcrBlock], lines: [AgentOcrLine], width: Int) -> String {
    guard !lines.isEmpty else {
      return "unknown"
    }
    if lines.count <= 2 {
      return "sparse"
    }
    guard width > 0, blocks.count >= 2 else {
      return "single_column"
    }
    let narrow = blocks.filter { block in
      Double(block.right - block.left) < Double(width) * 0.72
    }
    guard narrow.count >= 4 else {
      return "single_column"
    }
    let centers = narrow.map { ($0.left + $0.right) / 2 }.sorted()
    guard let gap = widestGap(centers) else {
      return "single_column"
    }
    let divider = (gap.0 + gap.1) / 2
    let left = narrow.filter { ($0.left + $0.right) / 2 < divider }
    let right = narrow.filter { ($0.left + $0.right) / 2 >= divider }
    guard left.count >= 2,
          right.count >= 2,
          Double(gap.1 - gap.0) >= Double(width) * columnGapRatio else {
      return "single_column"
    }
    let overlapTop = max(left.map(\.top).min() ?? 0, right.map(\.top).min() ?? 0)
    let overlapBottom = min(left.map(\.bottom).max() ?? 0, right.map(\.bottom).max() ?? 0)
    return overlapBottom > overlapTop ? "multi_column" : "single_column"
  }

  private static func duplicate(_ left: AgentOcrLine, _ right: AgentOcrLine) -> Bool {
    let leftText = normalized(left.text)
    let rightText = normalized(right.text)
    if leftText.isEmpty || rightText.isEmpty {
      return false
    }
    let textMatches = leftText == rightText ||
      (min(leftText.count, rightText.count) >= 4 &&
        (leftText.contains(rightText) || rightText.contains(leftText)))
    if left.right <= left.left ||
      left.bottom <= left.top ||
      right.right <= right.left ||
      right.bottom <= right.top {
      return textMatches
    }
    let intersectionWidth = max(min(left.right, right.right) - max(left.left, right.left), 0)
    let intersectionHeight = max(min(left.bottom, right.bottom) - max(left.top, right.top), 0)
    let intersection = Int64(intersectionWidth) * Int64(intersectionHeight)
    let smallerArea = max(
      min(
        Int64(left.right - left.left) * Int64(left.bottom - left.top),
        Int64(right.right - right.left) * Int64(right.bottom - right.top)
      ),
      1
    )
    let spatialDuplicate = Double(intersection) / Double(smallerArea) >= spatialDuplicateRatio
    let nearbyTextDuplicate = textMatches &&
      centerDistance(left, right) <= max(left.bottom - left.top, right.bottom - right.top) * 2
    return spatialDuplicate || nearbyTextDuplicate
  }

  private static func centerDistance(_ left: AgentOcrLine, _ right: AgentOcrLine) -> Int {
    let leftX = (left.left + left.right) / 2
    let leftY = (left.top + left.bottom) / 2
    let rightX = (right.left + right.right) / 2
    let rightY = (right.top + right.bottom) / 2
    return abs(leftX - rightX) + abs(leftY - rightY)
  }

  private static func candidateScore(_ candidate: AgentOcrCandidate) -> Double {
    candidate.lines.reduce(0.0) { $0 + lineScore($1, script: candidate.script) } +
      Double(letterDigitCount(candidate.fallbackText))
  }

  private static func lineScore(_ line: AgentOcrLine, script: AgentOcrScript) -> Double {
    let meaningful = letterDigitCount(line.text)
    let replacementPenalty = line.text.unicodeScalars.filter { $0.value == 0xFFFD }.count * 8
    let scriptBonus = line.text.unicodeScalars.filter { characterMatchesScript($0, script: script) }.count
    return Double(meaningful) * 2.0 + Double(scriptBonus) * 0.4 - Double(replacementPenalty)
  }

  private static func scriptFor(_ line: AgentOcrLine) -> AgentOcrScript {
    AgentOcrScript.allCases.first { $0.languageTag == line.languageTag } ?? .auto
  }

  private static func characterMatchesScript(_ value: Unicode.Scalar, script: AgentOcrScript) -> Bool {
    switch script {
    case .auto:
      return isLetterOrDigit(value)
    case .latin:
      return (0x0041...0x024F).contains(value.value)
    case .chinese:
      return (0x3400...0x9FFF).contains(value.value)
    case .japanese:
      return (0x3040...0x30FF).contains(value.value) ||
        (0x3400...0x9FFF).contains(value.value)
    case .korean:
      return (0x1100...0x11FF).contains(value.value) ||
        (0xAC00...0xD7AF).contains(value.value)
    case .devanagari:
      return (0x0900...0x097F).contains(value.value)
    }
  }

  private static func qualityScore(text: String, lines: [AgentOcrLine]) -> Double {
    let visible = max(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count, 1)
    let meaningful = letterDigitCount(text)
    let replacement = text.unicodeScalars.filter { $0.value == 0xFFFD }.count
    let characterQuality = Double(max(meaningful - replacement * 4, 0)) / Double(visible)
    let structureQuality = (Double(min(lines.count, 8)) / 8.0) * 0.18
    return min(max(characterQuality * 0.82 + structureQuality, 0.0), 1.0)
  }

  private static func normalized(_ value: String) -> String {
    var output = ""
    for scalar in value.lowercased().unicodeScalars where isLetterOrDigit(scalar) {
      output.unicodeScalars.append(scalar)
    }
    return output
  }

  private static func validBounds(_ line: AgentOcrLine) -> Bool {
    line.left >= 0 &&
      line.top >= 0 &&
      line.right >= line.left &&
      line.bottom >= line.top
  }

  private static func letterDigitCount(_ value: String) -> Int {
    value.unicodeScalars.filter(isLetterOrDigit).count
  }

  private static func isLetterOrDigit(_ value: Unicode.Scalar) -> Bool {
    CharacterSet.alphanumerics.contains(value)
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
      result.append(value)
    }
    return result
  }

  private static func widestGap(_ sortedCenters: [Int]) -> (Int, Int)? {
    guard sortedCenters.count >= 2 else {
      return nil
    }
    var best = (sortedCenters[0], sortedCenters[1])
    for index in 1..<(sortedCenters.count - 1) {
      let candidate = (sortedCenters[index], sortedCenters[index + 1])
      if candidate.1 - candidate.0 > best.1 - best.0 {
        best = candidate
      }
    }
    return best
  }

  private static let lowResolutionEdge = 640
  private static let lowQualityThreshold = 0.45
  private static let spatialDuplicateRatio = 0.58
  private static let columnGapRatio = 0.14
}

private extension Array {
  func ifEmpty(_ fallback: [Element]) -> [Element] {
    isEmpty ? fallback : self
  }
}
