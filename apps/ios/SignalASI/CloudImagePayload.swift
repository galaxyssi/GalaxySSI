import Foundation

struct CloudImagePayload: Equatable {
  static let maximumBytes = 64 * 1_024 * 1_024

  var displayName: String
  var mimeType: String
  var data: Data

  init(displayName: String, mimeType: String, data: Data) throws {
    let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !data.isEmpty,
          data.count <= Self.maximumBytes,
          normalizedMimeType.hasPrefix("image/") else {
      throw CloudImagePayloadError.invalidPayload(displayName)
    }
    self.displayName = SignalASIAttachmentPayloadBuilder.sanitizeName(displayName)
    self.mimeType = normalizedMimeType
    self.data = data
  }

  var base64: String {
    data.base64EncodedString()
  }
}

enum CloudImagePayloadError: LocalizedError, Equatable {
  case invalidPayload(String)
  case preparationFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidPayload(let name):
      return "Cloud image payload is invalid: \(name)"
    case .preparationFailed(let name):
      return "Cloud image could not be prepared: \(name)"
    }
  }
}

enum CloudImagePayloadFactory {
  static func prepare(_ attachments: [SignalASIDraftAttachment]) throws -> [CloudImagePayload] {
    try attachments
      .filter(\.isImage)
      .map { attachment in
        guard let encoded = AgentMediaAttachmentTransportEncoder.inlinePayload(
          for: attachment,
          profile: nil,
          remainingBytes: CloudImagePayload.maximumBytes
        ) else {
          throw CloudImagePayloadError.preparationFailed(attachment.displayName)
        }
        return try CloudImagePayload(
          displayName: encoded.displayName,
          mimeType: encoded.mimeType,
          data: encoded.data
        )
      }
  }
}

enum CloudVisionPayloadEncoder {
  static func attachOpenAI(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    for image in images {
      content.append([
        "type": "image_url",
        "image_url": [
          "url": "data:\(image.mimeType);base64,\(image.base64)",
          "detail": "auto"
        ]
      ])
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachAnthropic(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    for image in images {
      content.append([
        "type": "image",
        "source": [
          "type": "base64",
          "media_type": image.mimeType,
          "data": image.base64
        ]
      ])
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachGemini(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "parts": [[String: Any]]()])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var parts = message["parts"] as? [[String: Any]] ?? []
    for image in images {
      parts.append([
        "inline_data": [
          "mime_type": image.mimeType,
          "data": image.base64
        ]
      ])
    }
    message["parts"] = parts
    conversation[index] = message
  }

  private static func latestUserIndex(in conversation: [[String: Any]]) -> Int? {
    conversation.indices.reversed().first { conversation[$0]["role"] as? String == "user" }
  }

  private static func contentParts(_ value: Any?, textType: String) -> [[String: Any]] {
    if let content = value as? [[String: Any]] {
      return content
    }
    if let content = value as? [[Any]] {
      return content.compactMap { $0 as? [String: Any] }
    }
    guard let text = value as? String, !text.isEmpty else { return [] }
    return [["type": textType, "text": text]]
  }
}
