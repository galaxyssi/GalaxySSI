import Foundation

@MainActor
final class AgentIOSDownloadCompletionCoordinator {
  private let store: SignalASIStore
  private let reporter: AgentIOSDownloadCompletionReporting
  private var deliveryInFlight: Set<Int64> = []

  init(
    store: SignalASIStore,
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
      reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
      return
    }

    let remoteMessageId = "ios-download:\(completion.id)"
    if store.messages(for: contactId).contains(where: { $0.remoteMessageId == remoteMessageId }) {
      reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
      return
    }

    let zh = languageTag(for: completion).hasPrefix("zh")
    let name = completion.title.ifBlank(completion.localFileURL?.lastPathComponent ?? "Download")
    let succeeded = completion.succeeded
    let content: String
    let fileName = completion.localFileURL?.lastPathComponent ?? name
    let relativePath = "SignalASI Downloads/\(fileName)"
    let richOutput: String
    if succeeded {
      content = zh
        ? "\u{4e0b}\u{8f7d}\u{5b8c}\u{6210}\u{ff1a}\(name)\n\u{5df2}\u{4fdd}\u{5b58}\u{5230} SignalASI \u{4e0b}\u{8f7d}\u{3002}"
        : "Download complete: \(name)\nSaved in SignalASI Downloads."
      richOutput = AgentRichContentCodec.encode([
        fileBlock(for: completion, name: name, relativePath: relativePath)
      ])
    } else {
      let reason = completion.reason == 0 ? "" : " (\(completion.reason))"
      content = zh
        ? "\u{4e0b}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(name)\(reason)"
        : "Download failed: \(name)\(reason)"
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
    reporter.markCompletionDelivered(id: completion.id, nowMillis: nowMillis())
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
