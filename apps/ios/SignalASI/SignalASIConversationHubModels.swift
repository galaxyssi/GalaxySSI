import Foundation

enum SignalASIConversationHubTab: String, CaseIterable, Identifiable {
  case conversations
  case contacts
  case groups

  var id: String { rawValue }
}

struct SignalASIConversationHubSections {
  var pinned: [AgentConversation]
  var recent: [AgentConversation]
}

enum SignalASIConversationHubModels {
  static func conversations(
    _ source: [AgentConversation],
    query: String,
    archived: Bool
  ) -> SignalASIConversationHubSections {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matching = source
      .filter { $0.status == (archived ? .archived : .active) }
      .filter { conversation in
        cleanQuery.isEmpty || [
          conversation.title,
          conversation.summary,
          conversation.selectedModelOrAgent,
          conversation.id
        ].contains { $0.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
      }
      .sorted { $0.updatedAt > $1.updatedAt }
    return archived
      ? SignalASIConversationHubSections(pinned: [], recent: matching)
      : SignalASIConversationHubSections(
        pinned: matching.filter(\.pinned),
        recent: matching.filter { !$0.pinned }
      )
  }

  static func contacts(_ source: [SignalASIContact], query: String) -> [SignalASIContact] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return source
      .filter { contact in
        cleanQuery.isEmpty || [contact.displayName, contact.id].contains {
          $0.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
      .sorted {
        let leftSection = contactSection($0.displayName)
        let rightSection = contactSection($1.displayName)
        if leftSection != rightSection {
          if leftSection == "#" { return false }
          if rightSection == "#" { return true }
          return leftSection < rightSection
        }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
  }

  static func contactSection(_ name: String) -> String {
    guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
      return "#"
    }
    return first.isASCII && first.isLetter ? String(first).uppercased() : "#"
  }
}
