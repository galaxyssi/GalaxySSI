import UIKit

enum VoiceAppNativeTools {
  enum Operation: String, CaseIterable {
    case context, contacts, news, readArticle = "read_article", playback

    var id: String { "galaxyssi.app.\(rawValue)" }
    var changesPlayback: Bool { self == .playback }
  }

  static let playbackConsent = "voice_app.playback"
  static let contactsConsent = "voice_app.contacts.read"

  static func executables(
    invoke: @escaping (Operation, AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
  ) throws -> [AgentNativeToolExecutableDefinition] {
    try Operation.allCases.map { operation in
      let descriptor = try AgentNativeToolDescriptor(
        id: operation.id, version: AgentPhoneNativeToolCatalog.version, title: "GalaxySSI \(operation.rawValue)",
        description: description(operation), location: .application, inputSchema: schema(operation),
        outputSchema: AgentNativeToolDescriptor.objectSchema(),
        risk: operation == .contacts || operation.changesPlayback ? .medium : .low,
        capabilities: ["app_control", "voice_interaction"],
        requiredConsents: consents(operation),
        timeoutMillis: 15_000,
        idempotency: operation.changesPlayback ? .idempotencyKeyRequired : .idempotent,
        effect: operation.changesPlayback ? .mutation : .readOnly
      )
      return AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "ios.voice_app"),
        executor: { invocation in
          try invocation.checkpoint()
          return invoke(operation, invocation)
        }
      )
    }
  }

  private static func consents(_ operation: Operation) -> [AgentNativeConsentRequirement] {
    switch operation {
    case .contacts:
      return [AgentNativeConsentRequirement(id: contactsConsent, title: "Share paired contacts",
        description: "Allows the current Agent to read matching paired contact names and IDs.")]
    case .playback:
      return [AgentNativeConsentRequirement(id: playbackConsent, title: "Control news reading",
        description: "Allows this voice request to change public news playback.")]
    default: return []
    }
  }

  private static func description(_ operation: Operation) -> String {
    switch operation {
    case .context: return "Read the conversation, contact and article IDs captured for this voice turn, plus current news playback."
    case .contacts: return "Find verified paired contacts. Use the exact contact ID; clarify zero or ambiguous matches."
    case .news: return "List locally downloaded articles by title, publisher and date. Returns exact article IDs."
    case .readArticle: return "Read the cached original text of a downloaded article using an exact article ID."
    case .playback: return "Play ordered downloaded articles, pause, resume, skip, or stop news reading. Requires the original foreground voice owner."
    }
  }

  private static func schema(_ operation: Operation) -> AgentMcpJSONObject {
    let text: AgentMcpJSONValue = .object(["type": .string("string"), "maxLength": .int(256)])
    let identifier: AgentMcpJSONValue = .object(["type": .string("string"), "minLength": .int(64), "maxLength": .int(64)])
    let limit: AgentMcpJSONValue = .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(20)])
    var properties: AgentMcpJSONObject = [:]
    var required: [String] = []
    switch operation {
    case .context: break
    case .contacts: properties = ["query": text, "limit": limit]
    case .news:
      properties = ["query": text, "limit": limit,
        "since_epoch_ms": .object(["type": .string("integer"), "minimum": .int(0)])]
    case .readArticle:
      properties = ["article_id": identifier]
      required = ["article_id"]
    case .playback:
      properties = [
        "operation": .object(["type": .string("string"), "enum": .array(
          ["play_news", "pause", "resume", "next", "stop"].map(AgentMcpJSONValue.string)
        )]),
        "article_ids": .object(["type": .string("array"), "items": identifier, "maxItems": .int(20)])
      ]
      required = ["operation"]
    }
    return ["type": .string("object"), "properties": .object(properties),
      "required": .array(required.map(AgentMcpJSONValue.string)), "additionalProperties": .bool(false)]
  }
}

extension MessageCoordinator {
  func executeVoiceAppTool(
    _ operation: VoiceAppNativeTools.Operation, invocation: AgentNativeToolInvocation, store: GalaxySSIStore
  ) -> AgentNativeToolExecutionResult {
    let context = invocation.context
    guard UIApplication.shared.applicationState == .active, store.canReadVoiceReminderSnapshot,
          let anchor = voiceAppContexts.context(conversationID: context.conversationId, turnID: context.turnId),
          let session = store.agentSession(id: anchor.conversationID),
          session.status == .active, !session.privateMode, !session.trackingPaused else {
      return .failure(code: "voice_context_unavailable", message: "This invocation has no eligible bound voice context.")
    }
    let input = invocation.input
    let query = (input["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = Int(min(20, max(1, input["limit"]?.intValue ?? 10)))
    switch operation {
    case .context:
      return .success(output: [
        "voice_active": .bool(true), "foreground_owner": .bool(voiceAppContexts.isForegroundOwner(anchor)),
        "conversation_id": .string(anchor.conversationID), "contact_id": .string(anchor.contactID),
        "article_id": .string(anchor.articleID), "surface": .string(anchor.surface.rawValue),
        "playback_state": .string(anchor.playbackState), "playback": .object(voiceNewsPlaybackOutput())
      ])
    case .contacts:
      let matches = store.visibleContacts.filter { contact in
        contact.isCommunicable && ["person", "device"].contains(contact.type.lowercased()) &&
          (contact.opaquePhoneRoutes != nil || contact.isDesktopDeviceContact) &&
          (query.isEmpty || contact.displayName.localizedCaseInsensitiveContains(query))
      }
      let rows = matches.prefix(limit).map { contact in
        AgentMcpJSONValue.object(["contact_id": .string(contact.id),
          "display_name": .string(String(contact.displayName.prefix(160))), "type": .string(contact.type)])
      }
      return .success(output: ["contacts": .array(Array(rows)), "matched_count": .int(Int64(matches.count))])
    case .news:
      let since = input["since_epoch_ms"]?.intValue ?? 0
      var rows: [AgentMcpJSONValue] = []
      for article in voiceNewsArchive() {
        if rows.count == limit { break }
        let at = Int64(article.sortDate.timeIntervalSince1970 * 1_000)
        guard at >= since, query.isEmpty || article.displayTitle.localizedCaseInsensitiveContains(query) ||
                article.publisher.localizedCaseInsensitiveContains(query) else { continue }
        let item = voiceNewsItem(article)
        guard PublicNewsBodyStore.shared.speechDocument(for: item) != nil else { continue }
        rows.append(.object(["article_id": .string(item.articleKey), "title": .string(article.displayTitle),
          "publisher": .string(article.publisher), "at_epoch_ms": .int(at)]))
      }
      return .success(output: ["articles": .array(rows), "scope": .string("downloaded_public_news")])
    case .readArticle:
      let id = input["article_id"]?.stringValue ?? ""
      guard PublicNewsSpeechBookmark.isKey(id),
            let article = voiceNewsArchive().first(where: { voiceNewsItem($0).articleKey == id }),
            let document = PublicNewsBodyStore.shared.speechDocument(for: voiceNewsItem(article)) else {
        return .failure(code: "article_unavailable", message: "The requested original article is not available locally.")
      }
      var remaining = 24_000
      var truncated = false
      let paragraphs = document.paragraphs.compactMap { paragraph -> AgentMcpJSONValue? in
        guard remaining > 0 else { truncated = true; return nil }
        let bounded = String(paragraph.prefix(remaining))
        remaining -= bounded.count
        if bounded.count < paragraph.count { truncated = true }
        return .string(bounded)
      }
      return .success(output: ["article_id": .string(id), "title": .string(article.title),
        "paragraphs": .array(paragraphs), "truncated": .bool(truncated)])
    case .playback:
      guard voiceAppContexts.isForegroundOwner(anchor), store.activeAgentConversationId == anchor.conversationID else {
        return .failure(code: "stale_voice_owner", message: "The original voice surface is no longer active.")
      }
      return executeVoiceNewsPlayback(input, store: store)
    }
  }

  private func executeVoiceNewsPlayback(_ input: AgentMcpJSONObject, store: GalaxySSIStore) -> AgentNativeToolExecutionResult {
    let playback = PublicNewsSpeechPlayback.shared
    let command = input["operation"]?.stringValue ?? ""
    if !["pause", "stop"].contains(command), !store.voiceSettings.textToSpeechEnabled {
      return .failure(code: "tts_disabled", message: "Text-to-speech is disabled.")
    }
    switch command {
    case "play_news":
      let ids = input["article_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
      guard !ids.isEmpty, ids.count <= 20, Set(ids).count == ids.count else {
        return .failure(code: "article_ids_required", message: "Choose one or more distinct downloaded article IDs.")
      }
      let available = Set(voiceNewsArchive().map { voiceNewsItem($0).articleKey })
      let items = ids.map { PublicNewsSpeechBookmark.Item(articleKey: $0, edition: .original) }
      guard items.allSatisfy({ available.contains($0.articleKey) &&
        PublicNewsBodyStore.shared.speechDocument(for: $0) != nil }) else {
        return .failure(code: "article_unavailable", message: "One or more requested articles are not downloaded.")
      }
      playback.play(items, settings: store.voiceSettings, languagePolicy: store.languagePolicy)
    case "pause": playback.pause()
    case "resume":
      guard playback.queue.current != nil else {
        return .failure(code: "news_queue_empty", message: "No news queue is available to resume.")
      }
      playback.resume(settings: store.voiceSettings, languagePolicy: store.languagePolicy)
    case "next":
      guard playback.queue.current != nil else {
        return .failure(code: "news_queue_empty", message: "No news queue is available.")
      }
      playback.next()
    case "stop": playback.stop()
    default: return .failure(code: "invalid_playback_operation", message: "Unknown news playback operation.")
    }
    return .success(output: voiceNewsPlaybackOutput())
  }

  private func voiceNewsArchive() -> [PublicNewsArticle] {
    let archive = PublicNewsArchive()
    archive.load()
    return archive.eligibleArticles
  }

  private func voiceNewsItem(_ article: PublicNewsArticle) -> PublicNewsSpeechBookmark.Item {
    .init(articleKey: PublicNewsSpeechBookmark.key(for: article.id), edition: .original)
  }

  private func voiceNewsPlaybackOutput() -> AgentMcpJSONObject {
    let playback = PublicNewsSpeechPlayback.shared
    return ["state": .string(playback.appControlState),
      "article_id": .string(playback.queue.current?.articleKey ?? "")]
  }
}
