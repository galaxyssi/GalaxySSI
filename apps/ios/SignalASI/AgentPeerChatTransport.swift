import Foundation

enum AgentPeerChatTransport {
  static func conversationId(for link: ServerLink) -> String {
    "peer:\(link.routes.clientRouteId)"
  }

  static func turnId(for sourceMessageId: String) -> String {
    "peer-turn:\(sourceMessageId)"
  }

  static func taskId(for sourceMessageId: String) -> String {
    "peer:\(sourceMessageId)"
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
      if let transferId = raw["transfer_id"] as? String, !transferId.isEmpty {
        metadata["transfer_id"] = transferId
      }
      if let sha256 = raw["sha256"] as? String, !sha256.isEmpty {
        metadata["sha256"] = sha256
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
}
