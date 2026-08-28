import Foundation

enum AgentPeerChatTransport {
  struct StoredHistoryMigrationResult {
    var messages: [String: [ChatMessage]]
    var changed: Bool
  }

  struct DeliveryTraceEntry: Equatable {
    var stage: String
    var detail: String
  }

  static func conversationId(for link: ServerLink) -> String {
    "peer:\(link.routes.clientRouteId)"
  }

  static func turnId(for sourceMessageId: String) -> String {
    "peer-turn:\(sourceMessageId)"
  }

  static func taskId(for sourceMessageId: String) -> String {
    "peer:\(sourceMessageId)"
  }

  static func deliveryTrace(from payload: [String: Any]) -> [DeliveryTraceEntry] {
    let values: [[String: Any]]
    if let entries = payload["delivery_trace"] as? [[String: Any]] {
      values = entries
    } else if let entries = payload["delivery_trace"] as? [Any] {
      values = entries.compactMap { $0 as? [String: Any] }
    } else {
      return []
    }
    return values.compactMap { value in
      let stage = String(value.string("stage").prefix(80))
      guard !stage.isEmpty else { return nil }
      return DeliveryTraceEntry(
        stage: stage,
        detail: String(value.string("detail").prefix(240))
      )
    }
  }

  static func richOutput(
    for rawAttachments: [[String: Any]],
    context: [String: String] = [:]
  ) -> String {
    let blocks = rawAttachments.enumerated().compactMap { index, raw -> AgentRichBlock? in
      let name = raw.string("name")
        .ifBlank(raw.string("original_name"))
        .ifBlank("attachment")
      let mimeType = raw.string("mime_type").ifBlank("application/octet-stream")
      let type: AgentRichBlockType
      if mimeType.hasPrefix("image/") {
        type = .image
      } else if mimeType.hasPrefix("audio/") {
        type = .audio
      } else if mimeType.hasPrefix("video/") {
        type = .video
      } else {
        type = .file
      }
      let size = raw["size_bytes"] as? NSNumber
        ?? raw["size"] as? NSNumber
      let sizeText = size.map { ByteCountFormatter.string(fromByteCount: $0.int64Value, countStyle: .file) } ?? ""
      let artifactURI = raw.string("artifact_uri")
        .ifBlank(raw.string("artifact_source_uri"))
      let artifactID = raw.string("artifact_id")
      var metadata: [String: String] = context.filter { !$0.value.isEmpty }
      metadata.merge([
        "source": "peer_message",
        "size_bytes": String(size?.int64Value ?? 0)
      ]) { _, new in new }
      if !artifactURI.isEmpty {
        metadata["artifact_source_uri"] = artifactURI
      }
      if let transferId = raw["transfer_id"] as? String, !transferId.isEmpty {
        metadata["transfer_id"] = transferId
      }
      if let sha256 = raw["sha256"] as? String, !sha256.isEmpty {
        metadata["sha256"] = sha256
      }
      if let storage = raw["storage"] as? String, !storage.isEmpty {
        metadata["storage"] = storage
      }
      if let purpose = raw["encryption_purpose"] as? String, !purpose.isEmpty {
        metadata["encryption_purpose"] = purpose
      }
      if !artifactURI.isEmpty {
        metadata["artifact_source_uri"] = artifactURI
      }
      if !artifactID.isEmpty {
        metadata["artifact_id"] = artifactID
      }
      return AgentRichBlock(
        id: raw.string("id").ifBlank(raw.string("attachment_id")).ifBlank("peer-attachment-" + String(index)),
        type: type,
        title: name,
        text: sizeText,
        uri: artifactURI.ifBlank(raw.string("uri")),
        dataB64: raw.string("data_b64"),
        mimeType: mimeType,
        fallbackText: name,
        metadata: metadata
      )
    }
    return AgentRichContentCodec.encode(blocks)
  }

  static func migrateStoredHistory(
    _ messagesByContact: [String: [ChatMessage]]
  ) -> StoredHistoryMigrationResult {
    var migrated = messagesByContact
    var changed = false

    for (contactId, messages) in messagesByContact {
      let normalized = messages.map { message -> ChatMessage in
        let content = storedContent(message.content)
        let richOutput = message.richOutputJson.isEmpty
          ? storedRichOutput(message.content)
          : message.richOutputJson
        guard content != message.content || richOutput != message.richOutputJson else {
          return message
        }
        var updated = message
        updated.content = content
        updated.richOutputJson = richOutput
        changed = true
        return updated
      }
      migrated[contactId] = normalized
    }

    return StoredHistoryMigrationResult(messages: migrated, changed: changed)
  }

  static func incomingContent(from payload: [String: Any]) -> String {
    let content = payload.string("content")
      .ifBlank(payload.string("text"))
    guard payload.string("type") == "peer_message" else {
      return content
    }
    return normalizedPeerContent(content)
  }

  private static func storedContent(_ raw: String) -> String {
    normalizedPeerContent(raw)
  }

  private static func normalizedPeerContent(_ raw: String) -> String {
    var content = raw
    for _ in 0..<3 {
      guard let envelope = storedEnvelope(content),
            envelope.string("type") == "peer_message" else {
        break
      }
      let nested = envelope.string("content")
      guard !nested.isEmpty, nested != content else { break }
      content = nested
    }
    return content
  }

  private static func storedRichOutput(_ raw: String) -> String {
    guard let envelope = storedEnvelope(raw),
          envelope.string("type") == "peer_message",
          let attachments = envelope["attachments"] as? [[String: Any]],
          !attachments.isEmpty else {
      return ""
    }
    return richOutput(
      for: attachments,
      context: [
        "desktop_id": envelope.string("desktop_id").ifBlank(envelope.string("from")),
        "client_route_id": envelope.string("client_route_id"),
        "conversation_id": envelope.string("conversation_id"),
        "task_id": envelope.string("task_id"),
        "turn_id": envelope.string("turn_id").ifBlank(envelope.string("source_message_id")),
        "contact_id": envelope.string("contact_id")
      ]
    )
  }

  private static func storedEnvelope(_ raw: String) -> [String: Any]? {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return object
  }
}
