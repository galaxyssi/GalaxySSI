import Foundation

enum AgentDeliveredAttachmentRecovery {
  static let maximumFileBytes: Int64 = 64 * 1_024 * 1_024
  static let maximumTotalBytes: Int64 = 128 * 1_024 * 1_024

  struct PageResult {
    var attachments: [GalaxySSIDraftAttachment] = []
    var consumedBytes: Int64 = 0
  }

  static func restore(messages: [ChatMessage], conversationId: String, desktopId: String,
                      requestedIDs: [String], artifactStore: AgentDesktopArtifactStore,
                      remainingBytes: Int64) -> PageResult {
    guard !conversationId.isBlank, !desktopId.isBlank, remainingBytes > 0 else { return PageResult() }
    var missing = Set(requestedIDs.filter { !$0.isBlank && $0.count <= 120 }.prefix(10))
    var result = PageResult()
    for message in messages.reversed()
      where message.conversationId == conversationId && !message.isSystem {
      for block in AgentRichContentCodec.decode(message.richOutputJson)
        where missing.contains(block.id) && [.file, .image, .audio, .video].contains(block.type) {
        guard result.consumedBytes < remainingBytes else { return result }
        let attachment: GalaxySSIDraftAttachment?
        if message.isMine {
          // Never substitute a same-name input for a requested attachment identity.
          attachment = AgentAttachmentWorkspaceStager.restore(conversationId: conversationId,
            turnId: message.turnId, blocks: [block], matchExactIDs: true).first?.attachment
          if let attachment { result.consumedBytes += Int64(attachment.data.count) }
        } else {
          guard [ChatDeliveryStatus.delivered, .read].contains(message.deliveryStatus),
                block.metadata["desktop_id"] == desktopId,
                let expected = block.metadata["sha256"],
                expected.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                AgentDesktopArtifactStore.isGalaxySSIArtifactURI(
                  (block.metadata["artifact_source_uri"] ?? "").ifBlank(block.uri)) else { continue }
          let resolved = artifactStore.resolveBlock(block)
          guard let size = Int64(resolved.metadata["size_bytes"] ?? ""), size > 0,
                size <= maximumFileBytes, size <= remainingBytes - result.consumedBytes,
                resolved.metadata["sha256"] == expected else { continue }
          result.consumedBytes += size
          guard let file = artifactStore.localFile(for: block),
                let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                Int64(data.count) == size,
                GalaxySSIAttachmentPayloadBuilder.sha256(data) == expected else { continue }
          attachment = GalaxySSIDraftAttachment(id: block.id,
            displayName: (resolved.metadata["artifact_name"] ?? "").ifBlank(block.title),
            mimeType: resolved.mimeType, data: data, sourceDescription: file.absoluteString)
        }
        guard result.consumedBytes <= remainingBytes else { return result }
        guard let attachment, !attachment.data.isEmpty,
              Int64(attachment.data.count) <= maximumFileBytes else { continue }
        result.attachments.append(attachment)
        missing.remove(block.id)
        if missing.isEmpty { return result }
      }
    }
    return result
  }
}
