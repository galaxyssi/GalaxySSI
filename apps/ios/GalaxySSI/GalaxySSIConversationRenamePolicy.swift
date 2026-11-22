import Foundation

enum GalaxySSIConversationRenamePolicy {
  static let maximumCharacters = 72
  static func normalize(_ raw: String) -> String? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.utf16.count <= maximumCharacters,
          !name.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) || [0x2028, 0x2029].contains($0.value) }) else { return nil }
    return name
  }
}

struct GalaxySSIConversationRenameTarget: Identifiable {
  let id = UUID()
  let rowID: String
  let kind: GalaxySSIConversationHubItemKind
  let owner: String
  let title: String
  let initialName: String
  var contactFingerprint: String? = nil
}

extension GalaxySSIConversationHubModels {
  static func filteredRows(_ source: GalaxySSIConversationHubSections, query: String) -> GalaxySSIConversationHubSections {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    func matches(_ item: GalaxySSIConversationHubItem) -> Bool {
      query.isEmpty || [item.title, item.subtitle, item.preview, item.searchableMetadata]
        .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
    return .init(pinned: source.pinned.filter(matches), recent: source.recent.filter(matches))
  }
  static func renamedRows(_ source: GalaxySSIConversationHubSections, kind: GalaxySSIConversationHubItemKind,
                          id: String, title: String, query: String) -> GalaxySSIConversationHubSections {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    func update(_ rows: [GalaxySSIConversationHubItem]) -> [GalaxySSIConversationHubItem] {
      rows.compactMap { item in
        guard item.id == id && item.kind == kind else { return item }
        var changed = item; changed.title = title
        guard query.isEmpty || [changed.title, changed.subtitle, changed.preview, changed.searchableMetadata]
          .contains(where: { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) else { return nil }
        return changed
      }
    }
    return .init(pinned: update(source.pinned), recent: update(source.recent))
  }
}
