import Foundation

enum AgentAttachmentPublishOrder {
  struct Step {
    let attachment: AgentPreparedOutboundAttachment
    let chunkIndex: Int?

    var type: String {
      chunkIndex == nil ? "input_attachment_manifest" : "input_attachment_chunk"
    }

    func payload() throws -> [String: Any] {
      if let chunkIndex {
        return try attachment.chunkPayload(index: chunkIndex)
      }
      return attachment.manifestPayload(resume: false)
    }
  }

  static func steps(_ attachments: [AgentPreparedOutboundAttachment]) -> [Step] {
    var result: [Step] = []
    for attachment in attachments {
      result.append(Step(attachment: attachment, chunkIndex: nil))
      result.append(contentsOf: (0..<attachment.chunkCount).map { index in
        Step(attachment: attachment, chunkIndex: index)
      })
    }
    return result
  }
}
