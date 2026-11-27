import Foundation

enum GalaxySSIHealthAtlasDiscussion {
  static let storageKey = "galaxyssi.atlas.educational-conversations"
  static let maximumQuestionUTF16 = 500

  static func topic(_ itemID: String) -> String? {
    guard itemID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,59}$"#, options: .regularExpression) != nil else { return nil }
    return "body-atlas:" + itemID
  }

  static func reusable(_ session: AgentConversation, topic: String) -> Bool {
    session.globalTopicKey == topic && topic.hasPrefix("body-atlas:") &&
      self.topic(String(topic.dropFirst("body-atlas:".count))) == topic && session.createdByAgent &&
      session.status == .active && !session.privateMode && !session.trackingPaused && session.mergedIntoConversationId.isBlank
  }

  static func limitQuestion(_ text: String) -> String {
    var result = "", count = 0
    for character in text {
      let width = String(character).utf16.count
      guard count + width <= maximumQuestionUTF16 else { break }
      result.append(character); count += width
    }
    return result
  }

  static func request(context: String, question: String, language: String) -> String? {
    let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !context.isBlank, clean.utf16.count <= maximumQuestionUTF16 else { return nil }
    let result = clean.isEmpty ? context : context + "\n\n" + String(format:
      GalaxySSIHealthAtlasText.get("health_atlas_user_question", language), clean)
    guard result.utf16.count <= 9_000, result.utf8.count <= 32_000 else { return nil }
    return result
  }

  static func structureContext(atlas: GalaxySSIHealthAtlas, entry: GalaxySSIHealthAtlas.Entry?,
                               selection: GalaxySSIHealthAtlasState.Selection, position: Int?, language: String) -> String {
    guard let position, let plate = atlas.plate(for: entry?.id, viewKey: selection.artworkView), plate.hasLabels else { return "" }
    let landmarks = GalaxySSIHealthAtlasLandmarks.list(plate, atlas: atlas)
    let step = min(landmarks.count, max(0, position))
    func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
    let title = step == 0 ? atlas.caption(plate, selected: entry, language: language)
      : GalaxySSIHealthAtlasText.get(landmarks[step - 1].title, language)
    let label = step == 0 ? t("step_overview") : String(format: t("step_position"), Int64(step), Int64(landmarks.count))
    return [label, title].joined(separator: " \u{00B7} ")
  }

  private struct Index: Codable {
    let owner: String
    var topics: [String: String]
  }

  @MainActor
  static func conversation(store: GalaxySSIStore, itemID: String, title: String) -> AgentConversation? {
    guard store.canReadAgentTranscript, !store.profile.identityFingerprint.isBlank,
          let topic = topic(itemID) else { return nil }
    let owner = store.profile.identityFingerprint
    var index = Index(owner: owner, topics: [:])
    if GalaxySSIEncryptedUserDefaultsStore.contains(defaults: store.defaults, key: storageKey) {
      guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: store.defaults, key: storageKey, secrets: store.secrets),
            data.count <= 512_000, let saved = try? JSONDecoder().decode(Index.self, from: data), saved.topics.count <= 2_048 else { return nil }
      if saved.owner == owner { index = saved }
    }
    if let id = index.topics[topic], let session = store.agentConversationDatabase.read(id), reusable(session, topic: topic) {
      return session
    }
    guard index.topics[topic] != nil || index.topics.count < 2_048 else { return nil }
    let session = store.createAgentConversation(title: title, globalTopicKey: topic)
    guard let saved = store.agentConversationDatabase.read(session.id), reusable(saved, topic: topic) else { return nil }
    index.topics[topic] = saved.id
    guard let data = try? JSONEncoder().encode(index),
          GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: store.defaults, key: storageKey, secrets: store.secrets) else {
      _ = store.deleteAgentSession(id: saved.id)
      return nil
    }
    return saved
  }
}
