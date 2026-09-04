import Foundation

enum AgentAttachmentPublishOrder {
  struct PeerMessagePlan {
    let transferSteps: [Step]
    let blockedTransferIds: [String]
  }

  struct Step {
    let attachment: AgentPreparedOutboundAttachment
    let chunkIndex: Int?
    let eagerChunks: Bool

    init(
      attachment: AgentPreparedOutboundAttachment,
      chunkIndex: Int?,
      eagerChunks: Bool = false
    ) {
      self.attachment = attachment
      self.chunkIndex = chunkIndex
      self.eagerChunks = eagerChunks
    }

    var type: String {
      chunkIndex == nil ? "input_attachment_manifest" : "input_attachment_chunk"
    }

    func payload() throws -> [String: Any] {
      if let chunkIndex {
        return try attachment.chunkPayload(index: chunkIndex)
      }
      return attachment.manifestPayload(resume: false, eagerChunks: eagerChunks)
    }
  }

  static func steps(_ attachments: [AgentPreparedOutboundAttachment]) -> [Step] {
    var result: [Step] = []
    for attachment in attachments {
      result.append(Step(attachment: attachment, chunkIndex: nil, eagerChunks: true))
      result.append(contentsOf: (0..<attachment.chunkCount).map { index in
        Step(attachment: attachment, chunkIndex: index, eagerChunks: true)
      })
    }
    return result
  }

  static func initialSteps(
    _ attachments: [AgentPreparedOutboundAttachment],
    allowEagerChunks: Bool = true,
    eagerAttachment: (AgentPreparedOutboundAttachment) -> Bool = { _ in true }
  ) -> [Step] {
    var result: [Step] = []
    for attachment in attachments {
      let eager = allowEagerChunks &&
        eagerAttachment(attachment) &&
        attachment.sizeBytes <= eagerTransferBytes
      result.append(Step(attachment: attachment, chunkIndex: nil, eagerChunks: eager))
      if eager {
        result.append(contentsOf: (0..<attachment.chunkCount).map { index in
          Step(attachment: attachment, chunkIndex: index, eagerChunks: true)
        })
      }
    }
    return result
  }

  static func peerMessagePlan(
    _ attachments: [AgentPreparedOutboundAttachment],
    eagerAttachment: (AgentPreparedOutboundAttachment) -> Bool
  ) -> PeerMessagePlan {
    PeerMessagePlan(
      transferSteps: initialSteps(attachments, eagerAttachment: eagerAttachment),
      blockedTransferIds: uniqueTransferIds(attachments)
    )
  }

  private static func uniqueTransferIds(
    _ attachments: [AgentPreparedOutboundAttachment]
  ) -> [String] {
    var seen = Set<String>()
    return attachments.compactMap { attachment in
      seen.insert(attachment.transferId).inserted ? attachment.transferId : nil
    }
  }

  private static let eagerTransferBytes: Int64 = 1_024 * 1_024
}
