import Foundation

enum AgentResponseSectionKind: String, Codable, CaseIterable, Identifiable {
  case plan = "PLAN"
  case executionLog = "EXECUTION_LOG"
  case finalAnswer = "FINAL_ANSWER"
  case evidence = "EVIDENCE"

  var id: String { rawValue }
}

struct AgentResponseSection: Codable, Equatable, Identifiable {
  var kind: AgentResponseSectionKind
  var blocks: [AgentRichBlock]
  var expandedByDefault: Bool

  var id: String { kind.rawValue }
}

struct AgentResponseSectionLayout: Codable, Equatable {
  var collapsible: Bool
  var sections: [AgentResponseSection]
}

final class AgentResponseSectionExpansionStore {
  static let shared = AgentResponseSectionExpansionStore()

  private let defaults: UserDefaults
  private let key: String
  private var states: [String: Bool]

  init(defaults: UserDefaults = .standard, key: String = "galaxyssi.agent.response.section.expansion") {
    self.defaults = defaults
    self.key = key
    if let data = defaults.data(forKey: key),
       let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
      states = decoded
    } else {
      states = [:]
    }
  }

  func state(for storageKey: String) -> Bool? {
    guard !storageKey.isEmpty else { return nil }
    return states[storageKey]
  }

  func set(_ expanded: Bool, for storageKey: String) {
    guard !storageKey.isEmpty else { return }
    states[storageKey] = expanded
    while states.count > Self.maximumEntries, let firstKey = states.keys.first {
      states.removeValue(forKey: firstKey)
    }
    guard let data = try? JSONEncoder().encode(states) else { return }
    defaults.set(data, forKey: key)
  }

  private static let defaultKey = "galaxyssi.agent.response.section.expansion"
  private static let maximumEntries = 512
}

enum AgentResponseSectionOrganizer {
  static func organize(
    _ blocks: [AgentRichBlock],
    expandStructuredDetails: Bool = false
  ) -> AgentResponseSectionLayout {
    guard !blocks.isEmpty else {
      return AgentResponseSectionLayout(collapsible: false, sections: [])
    }

    var grouped: [AgentResponseSectionKind: [AgentRichBlock]] = [:]
    var activeKind: AgentResponseSectionKind?
    var structured = false

    for block in blocks {
      if let heading = headingKind(block) {
        activeKind = heading
        structured = true
        continue
      }

      let explicit = explicitKind(block)
      if explicit != nil {
        structured = true
      }

      let kind = explicit ?? typeKind(block) ?? activeKind ?? .finalAnswer
      grouped[kind, default: []].append(block)
    }

    var sections = orderedKinds.compactMap { kind -> AgentResponseSection? in
      guard let sectionBlocks = grouped[kind], !sectionBlocks.isEmpty else {
        return nil
      }
      return AgentResponseSection(
        kind: kind,
        blocks: sectionBlocks,
        expandedByDefault: kind == .finalAnswer || expandStructuredDetails
      )
    }

    if !sections.contains(where: \.expandedByDefault), !sections.isEmpty {
      sections[0].expandedByDefault = true
    }

    let contentSize = blocks.reduce(0) { $0 + contentCharacters($1) }
    let longResponse = contentSize >= longResponseCharacters || blocks.count >= longResponseBlocks
    return AgentResponseSectionLayout(
      collapsible: !sections.isEmpty && (longResponse || structured),
      sections: sections
    )
  }

  private static func explicitKind(_ block: AgentRichBlock) -> AgentResponseSectionKind? {
    let value = explicitMetadataKeys
      .compactMap { block.metadata[$0] }
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard let value else { return nil }
    return parseKind(value)
  }

  private static func headingKind(_ block: AgentRichBlock) -> AgentResponseSectionKind? {
    guard block.type == .heading else { return nil }
    let value = block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? block.title : block.text
    return parseKind(value)
  }

  private static func typeKind(_ block: AgentRichBlock) -> AgentResponseSectionKind? {
    switch block.type {
    case .status, .progress, .tool, .timeline:
      return .executionLog
    case .citation:
      return .evidence
    case .actions, .approval, .form:
      return .finalAnswer
    default:
      return block.metadata["evidence"] == "true" ? .evidence : nil
    }
  }

  private static func parseKind(_ value: String) -> AgentResponseSectionKind? {
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    switch normalized {
    case "plan", "approach", "steps",
      "\u{8ba1}\u{5212}", "\u{65b9}\u{6848}", "\u{6267}\u{884c}\u{8ba1}\u{5212}":
      return .plan
    case "log", "execution log", "tool log", "activity", "progress",
      "\u{65e5}\u{5fd7}", "\u{6267}\u{884c}\u{65e5}\u{5fd7}", "\u{5de5}\u{5177}\u{65e5}\u{5fd7}",
      "\u{6267}\u{884c}\u{8fc7}\u{7a0b}":
      return .executionLog
    case "final", "final answer", "answer", "result", "summary",
      "\u{6700}\u{7ec8}\u{7b54}\u{6848}", "\u{7b54}\u{6848}", "\u{7ed3}\u{679c}", "\u{603b}\u{7ed3}":
      return .finalAnswer
    case "evidence", "source", "sources", "citation", "citations", "references",
      "\u{8bc1}\u{636e}", "\u{6765}\u{6e90}", "\u{5f15}\u{7528}", "\u{53c2}\u{8003}":
      return .evidence
    default:
      return nil
    }
  }

  private static func contentCharacters(_ block: AgentRichBlock) -> Int {
    block.title.utf16.count +
      block.text.utf16.count +
      block.fallbackText.utf16.count +
      block.rows.reduce(0) { total, row in
        total + row.reduce(0) { $0 + $1.utf16.count }
      }
  }

  private static let longResponseCharacters = 1_200
  private static let longResponseBlocks = 6
  private static let explicitMetadataKeys = ["section", "response_section", "role"]
  private static let orderedKinds: [AgentResponseSectionKind] = [
    .plan,
    .executionLog,
    .finalAnswer,
    .evidence
  ]
}
