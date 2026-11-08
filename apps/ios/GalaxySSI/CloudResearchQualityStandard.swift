import Foundation

struct CloudResearchQualityStandard {
  struct Report: Equatable {
    let contract: String
    let risks: [String]
    let researchObserved: Bool
    let semanticVerification = "not_independently_verified"

    var status: String {
      if !researchObserved { return "not_applicable" }
      return risks.isEmpty ? "no_structural_risk_detected" : "needs_review"
    }
  }

  private struct Contract: Decodable {
    struct Rule: Decodable {
      let id: String
      let pattern: String
    }

    let version: String
    let rules: [String]
    let repair: String
    let risk_rules: [Rule]
  }

  static let bundled: Self? = {
    guard let url = Bundle.main.url(forResource: "research-quality", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? Self(data: data)
  }()

  private let contract: Contract
  private let patterns: [(String, NSRegularExpression)]

  init(data: Data) throws {
    let decoded = try JSONDecoder().decode(Contract.self, from: data)
    contract = decoded
    patterns = try decoded.risk_rules.map { ($0.id, try NSRegularExpression(pattern: $0.pattern)) }
  }

  var prompt: String {
    "GalaxySSI research quality (\(contract.version)):\n" +
      contract.rules.map { "- \($0)" }.joined(separator: "\n")
  }

  func assess(_ answer: String, researchObserved: Bool) -> Report {
    guard researchObserved else { return Report(contract: contract.version, risks: [], researchObserved: false) }
    let prose = Self.prose(answer)
    let range = NSRange(prose.startIndex..., in: prose)
    let risks = patterns.compactMap { id, regex in
      regex.firstMatch(in: prose, range: range) == nil ? nil : id
    }
    return Report(contract: contract.version, risks: risks, researchObserved: true)
  }

  func repairPrompt(_ report: Report) -> String {
    "Research structural risk review: \(report.risks.joined(separator: ", ")). \(contract.repair)"
  }

  static func repairIfNeeded(_ draft: String, evidence: [(String, String)]) -> String? {
    guard let bundled, CloudResearchRuntimeBudget.hasCitableEvidence(evidence) else { return nil }
    let report = bundled.assess(draft, researchObserved: true)
    return report.risks.isEmpty ? nil : bundled.repairPrompt(report)
  }

  private static func prose(_ text: String) -> String {
    var fence: (marker: Character, count: Int)?
    var lines: [String] = []
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      let trimmed = line.drop(while: { $0.isWhitespace })
      if let marker = trimmed.first, marker == "`" || marker == "~" {
        let count = trimmed.prefix(while: { $0 == marker }).count
        if count >= 3 {
          if let active = fence {
            if active.marker == marker, count >= active.count,
               trimmed.dropFirst(count).allSatisfy(\.isWhitespace) { fence = nil }
          } else { fence = (marker, count) }
          continue
        }
      }
      guard fence == nil, trimmed.first != ">",
            line.prefix(while: { $0 == " " }).count < 4, line.first != "\t" else { continue }
      lines.append(String(line))
    }
    return lines.joined(separator: "\n").replacingOccurrences(
      of: #"(?<!`)(`+)(?!`)[^\n]*?(?<!`)\1(?!`)"#, with: "", options: .regularExpression
    )
  }
}
