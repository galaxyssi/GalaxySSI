import Foundation

@MainActor
final class AgentIOSDownloadCompletionCoordinator {
  private let store: GalaxySSIStore
  private let reporter: AgentIOSDownloadCompletionReporting
  private var deliveryInFlight: Set<Int64> = []

  init(
    store: GalaxySSIStore,
    reporter: AgentIOSDownloadCompletionReporting = AgentIOSDefaultDownloadProvider.shared
  ) {
    self.store = store
    self.reporter = reporter
    reporter.setCompletionHandler { [weak self] completion in
      Task { @MainActor in
        self?.deliver(completion)
      }
    }
    deliverPendingCompletions()
  }

  func deliverPendingCompletions() {
    reporter.pendingCompletions().forEach(deliver)
  }

  private func deliver(_ completion: AgentIOSDownloadCompletion) {
    guard deliveryInFlight.insert(completion.id).inserted else { return }
    defer { deliveryInFlight.remove(completion.id) }

    guard let contactId = contactId(for: completion) else {
      notify(completion)
      reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
      return
    }

    let remoteMessageId = "ios-download:\(completion.id)"
    if store.messages(for: contactId).contains(where: { $0.remoteMessageId == remoteMessageId }) {
      reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
      return
    }

    let language = languageTag(for: completion)
    let name = completion.title.ifBlank(completion.localFileURL?.lastPathComponent ?? "Download")
    let succeeded = completion.succeeded
    let content: String
    let fileName = completion.localFileURL?.lastPathComponent ?? name
    let relativePath = AgentIOSDownloadFilePolicy.relativePath(for: fileName)
    let richOutput: String
    if succeeded {
      content = String(
        format: localized(
          "galaxyssi.agent.download.complete",
          "Download complete: %@\nSaved in Download/GalaxySSI.",
          language: language
        ),
        name
      )
      richOutput = AgentRichContentCodec.encode([
        fileBlock(for: completion, name: name, relativePath: relativePath)
      ])
    } else {
      let reason = completion.reason == 0 ? "" : " (\(completion.reason))"
      content = String(
        format: localized(
          "galaxyssi.agent.download.failed",
          "Download failed: %@%@",
          language: language
        ),
        name,
        reason
      )
      richOutput = ""
    }

    _ = store.appendIncoming(
      content,
      from: contactId,
      remoteMessageId: remoteMessageId,
      status: succeeded ? .delivered : .failed,
      traceStage: succeeded ? "ios_download_completed" : "ios_download_failed",
      conversationId: conversationId(for: completion),
      turnId: completion.turnId,
      richOutputJson: richOutput
    )
    notify(completion)
    reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
  }

  private func notify(_ completion: AgentIOSDownloadCompletion) {
    let zh = languageTag(for: completion).hasPrefix("zh")
    let name = completion.title.ifBlank(completion.localFileURL?.lastPathComponent ?? "Download")
    let title = completion.succeeded
      ? (zh ? "\u{4E0B}\u{8F7D}\u{5B8C}\u{6210}" : "Download complete")
      : (zh ? "\u{4E0B}\u{8F7D}\u{5931}\u{8D25}" : "Download failed")
    let reason = completion.reason == 0 ? "" : " (\(completion.reason))"
    let body = completion.succeeded
      ? (zh
        ? "\(name) \u{5DF2}\u{4FDD}\u{5B58}\u{5230} Download/GalaxySSI\u{3002}"
        : "\(name) was saved to Download/GalaxySSI.")
      : (zh
        ? "\(name) \u{4E0B}\u{8F7D}\u{5931}\u{8D25}\(reason)\u{3002}"
        : "\(name) failed to download\(reason).")
    NotificationService.notify(
      title: title,
      body: body,
      userInfo: [
        "galaxyssi_notification_type": "agent_download",
        "download_id": String(completion.id),
        "contact_id": completion.contactId,
        "conversation_id": completion.conversationId,
        "turn_id": completion.turnId,
        "succeeded": completion.succeeded
      ]
    )
  }

  private func contactId(for completion: AgentIOSDownloadCompletion) -> String? {
    if !completion.contactId.isEmpty,
       let contact = store.contact(id: completion.contactId),
       !contact.deleted {
      return completion.contactId
    }
    if let matched = store.contacts.first(where: { contact in
      !contact.deleted && store.messages(for: contact.id).contains {
        $0.conversationId == completion.conversationId
      }
    }) {
      return matched.id
    }
    if let hermes = store.contact(id: "hermes"), !hermes.deleted {
      return hermes.id
    }
    return store.contacts.first { contact in
      !contact.deleted && (contact.type == "agent" || contact.deliveryMode == .cloudAPI)
    }?.id
  }

  private func conversationId(for completion: AgentIOSDownloadCompletion) -> String {
    let requested = completion.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    if let session = store.agentSession(id: requested) {
      return session.id
    }
    return store.activeAgentConversationId
  }

  private func languageTag(for completion: AgentIOSDownloadCompletion) -> String {
    let recorded = completion.languageTag.trimmingCharacters(in: .whitespacesAndNewlines)
    return recorded.isEmpty ? LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage) : recorded
  }

  private func localized(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }

  private func fileBlock(
    for completion: AgentIOSDownloadCompletion,
    name: String,
    relativePath: String
  ) -> AgentRichBlock {
    let fileURL = completion.localFileURL
    return AgentRichBlock(
      id: "ios-download:\(completion.id)",
      type: .file,
      title: name,
      text: relativePath,
      uri: fileURL?.absoluteString ?? "",
      mimeType: completion.mediaType,
      fallbackText: name,
      metadata: [
        "download_id": String(completion.id),
        "local_download": "true",
        "relative_path": relativePath,
        "size": humanSize(completion.bytesDownloaded),
        "saved_to_downloads": "true",
        "size_bytes": String(max(0, completion.bytesDownloaded)),
        "source": "ios_system_download",
        "total_bytes": String(max(0, completion.totalBytes))
      ]
    )
  }

  private func humanSize(_ bytes: Int64) -> String {
    let value = max(0, bytes)
    if value < 1_024 { return "\(value) B" }
    if value < 1_024 * 1_024 { return String(format: "%.1f KB", Double(value) / 1_024) }
    if value < 1_024 * 1_024 * 1_024 { return String(format: "%.1f MB", Double(value) / (1_024 * 1_024)) }
    return String(format: "%.1f GB", Double(value) / (1_024 * 1_024 * 1_024))
  }

  private func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}
