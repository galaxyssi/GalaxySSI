import Foundation
import UIKit

struct CloudImagePayload: Equatable {
  static let maximumBytes = 100_000

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
    self.displayName = GalaxySSIAttachmentPayloadBuilder.sanitizeName(displayName)
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
  static func prepare(_ attachments: [GalaxySSIDraftAttachment]) throws -> [CloudImagePayload] {
    try attachments
      .filter(\.isImage)
      .map { attachment in
        guard let payload = payload(for: attachment) else {
          throw CloudImagePayloadError.preparationFailed(attachment.displayName)
        }
        return payload
      }
  }

  private static func payload(for attachment: GalaxySSIDraftAttachment) -> CloudImagePayload? {
    if attachment.data.count <= CloudImagePayload.maximumBytes {
      return try? CloudImagePayload(
        displayName: attachment.displayName,
        mimeType: attachment.mimeType,
        data: attachment.data
      )
    }
    guard let source = UIImage(data: attachment.data) else { return nil }
    var image = flattened(scaleToMaximumDimension(source, maximum: maximumDimension))
    for _ in 0..<maximumAttempts {
      if let data = bestJPEG(for: image, byteLimit: CloudImagePayload.maximumBytes) {
        return try? CloudImagePayload(
          displayName: jpegTransportName(for: attachment.displayName),
          mimeType: "image/jpeg",
          data: data
        )
      }
      guard max(image.size.width, image.size.height) > minimumDimension else { break }
      image = scaled(image, factor: 0.8)
    }
    guard let data = image.jpegData(compressionQuality: 0.25),
          data.count <= CloudImagePayload.maximumBytes else {
      return nil
    }
    return try? CloudImagePayload(
      displayName: jpegTransportName(for: attachment.displayName),
      mimeType: "image/jpeg",
      data: data
    )
  }

  private static func bestJPEG(for image: UIImage, byteLimit: Int) -> Data? {
    var low = minimumJPEGQuality
    var high = maximumJPEGQuality
    var best: Data?
    while low <= high {
      let quality = CGFloat(low + high) / 100
      guard let candidate = image.jpegData(compressionQuality: quality) else { return best }
      if candidate.count <= byteLimit {
        best = candidate
        low = Int(quality * 100) + 1
      } else {
        high = Int(quality * 100) - 1
      }
    }
    return best
  }

  private static func scaleToMaximumDimension(_ image: UIImage, maximum: CGFloat) -> UIImage {
    let largest = max(image.size.width, image.size.height)
    guard largest > maximum else { return image }
    return scaled(image, factor: maximum / largest)
  }

  private static func scaled(_ image: UIImage, factor: CGFloat) -> UIImage {
    let size = CGSize(
      width: max(1, (image.size.width * factor).rounded()),
      height: max(1, (image.size.height * factor).rounded())
    )
    guard size != image.size else { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private static func flattened(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: image.size))
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
  }

  private static func jpegTransportName(for name: String) -> String {
    let clean = GalaxySSIAttachmentPayloadBuilder.sanitizeName(name)
    let base = (clean as NSString).deletingPathExtension.ifBlank("image")
    return "\(base).jpg"
  }

  private static let maximumDimension: CGFloat = 2_400
  private static let minimumDimension: CGFloat = 240
  private static let minimumJPEGQuality = 35
  private static let maximumJPEGQuality = 95
  private static let maximumAttempts = 8
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
