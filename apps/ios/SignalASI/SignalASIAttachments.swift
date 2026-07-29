import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct SignalASIDraftAttachment: Identifiable, Equatable {
  var id: String
  var displayName: String
  var mimeType: String
  var data: Data
  var sourceDescription: String

  init(
    id: String = UUID().uuidString,
    displayName: String,
    mimeType: String,
    data: Data,
    sourceDescription: String = ""
  ) {
    self.id = id
    self.displayName = displayName.ifBlank("attachment")
    self.mimeType = mimeType.ifBlank("application/octet-stream")
    self.data = data
    self.sourceDescription = sourceDescription
  }

  var sizeBytes: Int {
    data.count
  }

  var isImage: Bool {
    mimeType.localizedCaseInsensitiveHasPrefix("image/")
  }

  var humanSize: String {
    SignalASIAttachmentPayloadBuilder.humanSize(sizeBytes)
  }

  var label: String {
    "[\(displayName)]"
  }
}

enum AgentAnimatedImageTiming {
  private static let gifDelayCentiseconds: UInt8 = 8

  static func normalizeZeroFrameDelays(_ source: Data) -> Data {
    guard isGif(source) else { return source }
    var output: Data?
    var index = 0
    while index + 7 < source.count {
      let isGraphicControlExtension = source[index] == 0x21 &&
        source[index + 1] == 0xf9 &&
        source[index + 2] == 0x04
      if !isGraphicControlExtension {
        index += 1
        continue
      }
      let delay = Int(source[index + 4]) | (Int(source[index + 5]) << 8)
      if delay == 0 {
        var normalized = output ?? source
        normalized[index + 4] = gifDelayCentiseconds
        normalized[index + 5] = 0
        output = normalized
      }
      index += 8
    }
    return output ?? source
  }

  private static func isGif(_ data: Data) -> Bool {
    data.count >= 6 &&
      data[0] == 0x47 &&
      data[1] == 0x49 &&
      data[2] == 0x46 &&
      data[3] == 0x38 &&
      (data[4] == 0x37 || data[4] == 0x39) &&
      data[5] == 0x61
  }
}

enum SignalASIAttachmentPayloadBuilder {
  static let maximumAttachmentCount = 10
  static let maximumAttachmentBytes = 20 * 1024 * 1024
  static let maximumInlineBytes = 320 * 1024

  static func accepted(_ attachment: SignalASIDraftAttachment, existing: [SignalASIDraftAttachment]) -> Bool {
    guard existing.count < maximumAttachmentCount else { return false }
    guard attachment.sizeBytes <= maximumAttachmentBytes else { return false }
    return true
  }

  static func messageLabel(for attachments: [SignalASIDraftAttachment]) -> String {
    switch attachments.count {
    case 0:
      return ""
    case 1:
      return attachments[0].label
    default:
      return "\(attachments.count) attachments"
    }
  }

  static func descriptors(for attachments: [SignalASIDraftAttachment]) -> [[String: Any]] {
    var remaining = maximumInlineBytes
    return attachments.prefix(maximumAttachmentCount).map { attachment in
      var item: [String: Any] = [
        "id": attachment.id,
        "name": attachment.displayName,
        "mime_type": attachment.mimeType,
        "size": attachment.sizeBytes,
        "sha256": sha256(attachment.data)
      ]
      if attachment.sizeBytes > 0, attachment.sizeBytes <= remaining {
        item["data_b64"] = attachment.data.base64EncodedString()
        item["transport_size"] = attachment.sizeBytes
        item["transport_lossless"] = true
        remaining -= attachment.sizeBytes
      } else {
        item["inline_status"] = "metadata_only"
      }
      return item
    }
  }

  static func promptSuffix(for attachments: [SignalASIDraftAttachment]) -> String {
    guard !attachments.isEmpty else { return "" }
    let lines = attachments.map { attachment in
      "- \(attachment.displayName) (\(attachment.mimeType), \(attachment.humanSize), sha256 \(sha256(attachment.data).prefix(12)))"
    }
    return "Attachments:\n" + lines.joined(separator: "\n")
  }

  static func makeAttachment(from url: URL) throws -> SignalASIDraftAttachment {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    let data = AgentAnimatedImageTiming.normalizeZeroFrameDelays(
      try Data(contentsOf: url, options: [.mappedIfSafe])
    )
    let values = try? url.resourceValues(forKeys: [.nameKey, .contentTypeKey, .fileSizeKey])
    let name = values?.name ?? url.lastPathComponent.ifBlank("attachment")
    let type = values?.contentType?.preferredMIMEType ??
      UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ??
      "application/octet-stream"
    return SignalASIDraftAttachment(
      displayName: sanitizeName(name),
      mimeType: type,
      data: data,
      sourceDescription: url.absoluteString
    )
  }

  static func makePhotoAttachment(data: Data, suggestedName: String = "photo.jpg") -> SignalASIDraftAttachment {
    let normalizedData = AgentAnimatedImageTiming.normalizeZeroFrameDelays(data)
    let type = imageMimeType(for: normalizedData) ?? "image/jpeg"
    return SignalASIDraftAttachment(
      displayName: sanitizeName(suggestedName),
      mimeType: type,
      data: normalizedData,
      sourceDescription: "photo-library"
    )
  }

  static func humanSize(_ bytes: Int) -> String {
    if bytes < 1024 {
      return "\(bytes) B"
    }
    if bytes < 1024 * 1024 {
      return String(format: "%.1f KB", Double(bytes) / 1024)
    }
    return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
  }

  static func sanitizeName(_ value: String) -> String {
    let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
    let replacedScalars = value.unicodeScalars.map { scalar in
      forbidden.contains(scalar) ? "_" : String(scalar)
    }
    let cleaned = replacedScalars.joined()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    return String(cleaned.prefix(120)).ifBlank("attachment")
  }

  static func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }

  private static func imageMimeType(for data: Data) -> String? {
    guard let first = data.first else { return nil }
    if first == 0xff { return "image/jpeg" }
    if data.starts(with: Data([0x89, 0x50, 0x4e, 0x47])) { return "image/png" }
    if data.starts(with: Data([0x47, 0x49, 0x46])) { return "image/gif" }
    if data.starts(with: Data([0x52, 0x49, 0x46, 0x46])) { return "image/webp" }
    return nil
  }
}
