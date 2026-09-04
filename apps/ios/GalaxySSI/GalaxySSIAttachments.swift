import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct GalaxySSIDraftAttachment: Identifiable, Equatable {
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
    mimeType.lowercased().hasPrefix("image/")
  }

  var isAudio: Bool {
    mimeType.lowercased().hasPrefix("audio/")
  }

  var humanSize: String {
    GalaxySSIAttachmentPayloadBuilder.humanSize(sizeBytes)
  }

  var label: String {
    "[\(displayName)]"
  }

  mutating func wipeSensitive() {
    data.wipeSensitive()
    sourceDescription.removeAll(keepingCapacity: false)
  }
}

extension Array where Element == GalaxySSIDraftAttachment {
  mutating func removeAndWipe(id: String) {
    guard let index = firstIndex(where: { $0.id == id }) else { return }
    var removed = remove(at: index)
    removed.wipeSensitive()
  }

  mutating func wipeSensitive() {
    for index in indices {
      self[index].wipeSensitive()
    }
    removeAll(keepingCapacity: false)
  }
}

struct AgentStagedAttachment: Codable, Equatable {
  var name: String
  var relativePath: String
  var mimeType: String
  var sizeBytes: Int64
  var sha256: String

  enum CodingKeys: String, CodingKey {
    case name
    case relativePath = "relative_path"
    case mimeType = "mime_type"
    case sizeBytes = "size_bytes"
    case sha256
  }
}

struct AgentRestoredAttachment: Equatable {
  var attachment: GalaxySSIDraftAttachment
  var staged: AgentStagedAttachment
}

enum AgentAttachmentWorkspaceStagingError: LocalizedError, Equatable {
  case invalidTurnId
  case unsafePath
  case limitExceeded
  case unavailable
  case commitFailed

  var errorDescription: String? {
    switch self {
    case .invalidTurnId:
      return "Attachment turn ID is invalid."
    case .unsafePath:
      return "Attachment workspace path is unsafe."
    case .limitExceeded:
      return "Attachment input exceeds the workspace limit."
    case .unavailable:
      return "Attachment workspace is unavailable."
    case .commitFailed:
      return "Attachment could not be committed."
    }
  }
}

enum AgentWorkspaceScope {
  static func id(conversationId: String, sessionId: String = "") -> String {
    let owner = conversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(sessionId.trimmingCharacters(in: .whitespacesAndNewlines))
      .ifBlank("default")
    return nameBasedUUID("galaxyssi-workspace:\(owner)")
  }

  static func bindToolInput(
    toolId: String,
    input: [String: Any],
    workspaceId: String
  ) -> [String: Any] {
    guard toolId.hasPrefix(workspaceToolPrefix) else {
      return input
    }
    var output = input
    output["workspace_id"] = workspaceId
    return output
  }

  static func withLock<T>(workspaceId: String, _ body: () throws -> T) rethrows -> T {
    let lock = lock(for: workspaceId)
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static func lock(for workspaceId: String) -> NSLock {
    stateLock.lock()
    defer { stateLock.unlock() }
    if let existing = locks[workspaceId] {
      return existing
    }
    let created = NSLock()
    locks[workspaceId] = created
    return created
  }

  private static func nameBasedUUID(_ value: String) -> String {
    var bytes = Array(Insecure.MD5.hash(data: Data(value.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    )).uuidString.lowercased()
  }

  private static let workspaceToolPrefix = "galaxyssi.workspace."
  private static let stateLock = NSLock()
  private static var locks: [String: NSLock] = [:]
}

enum AgentAttachmentWorkspaceStager {
  static let maximumAttachmentBytes: Int64 = 256 * 1024 * 1024
  static let maximumTurnBytes: Int64 = 10 * 64 * 1024 * 1024

  private struct AttachmentManifest: Codable {
    var version: Int
    var attachments: [AttachmentManifestRecord]
  }

  private struct AttachmentManifestRecord: Codable {
    var attachmentId: String
    var name: String
    var relativePath: String
    var mimeType: String
    var sizeBytes: Int64
    var sha256: String

    enum CodingKeys: String, CodingKey {
      case attachmentId = "attachment_id"
      case name
      case relativePath = "relative_path"
      case mimeType = "mime_type"
      case sizeBytes = "size_bytes"
      case sha256
    }
  }

  static func stage(
    conversationId: String,
    turnId: String,
    attachments: [GalaxySSIDraftAttachment],
    projectRoot: URL? = nil,
    fileManager: FileManager = .default
  ) throws -> [AgentStagedAttachment] {
    guard turnId.range(of: safeIdPattern, options: .regularExpression) != nil else {
      throw AgentAttachmentWorkspaceStagingError.invalidTurnId
    }
    let workspaceId = AgentWorkspaceScope.id(conversationId: conversationId)
    return try AgentWorkspaceScope.withLock(workspaceId: workspaceId) {
      let root = try (projectRoot ?? defaultProjectRoot(fileManager: fileManager))
      let workspace = root.appendingPathComponent(workspaceId, isDirectory: true).standardizedFileURL
      let inputDirectory = workspace
        .appendingPathComponent("inputs", isDirectory: true)
        .appendingPathComponent(turnId, isDirectory: true)
        .standardizedFileURL
      guard inputDirectory.path.hasPrefix(workspace.path + pathSeparator) else {
        throw AgentAttachmentWorkspaceStagingError.unsafePath
      }
      try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)

      var totalBytes: Int64 = 0
      var staged: [AgentStagedAttachment] = []
      for (index, attachment) in attachments.enumerated() {
        let safeName = uniqueName(
          directory: inputDirectory,
          baseName: sanitizeName(attachment.displayName),
          index: index,
          fileManager: fileManager
        )
        let target = inputDirectory.appendingPathComponent(safeName, isDirectory: false)
        let temporary = inputDirectory.appendingPathComponent(".\(safeName).part", isDirectory: false)
        let size = Int64(attachment.data.count)
        totalBytes += size
        guard size <= maximumAttachmentBytes && totalBytes <= maximumTurnBytes else {
          try? fileManager.removeItem(at: temporary)
          throw AgentAttachmentWorkspaceStagingError.limitExceeded
        }
        do {
          try attachment.data.write(to: temporary, options: [.atomic])
          if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
          }
          try fileManager.moveItem(at: temporary, to: target)
          protectFile(at: target, fileManager: fileManager)
        } catch {
          try? fileManager.removeItem(at: temporary)
          throw AgentAttachmentWorkspaceStagingError.commitFailed
        }
        staged.append(
          AgentStagedAttachment(
            name: attachment.displayName,
            relativePath: "inputs/\(turnId)/\(safeName)",
            mimeType: attachment.mimeType,
            sizeBytes: size,
            sha256: GalaxySSIAttachmentPayloadBuilder.sha256(attachment.data)
          )
        )
      }
      try writeManifest(
        directory: inputDirectory,
        attachments: attachments,
        staged: staged,
        fileManager: fileManager
      )
      return staged
    }
  }

  static func restore(
    conversationId: String,
    turnId: String,
    blocks: [AgentRichBlock],
    projectRoot: URL? = nil,
    fileManager: FileManager = .default
  ) -> [AgentRestoredAttachment] {
    guard turnId.range(of: safeIdPattern, options: .regularExpression) != nil,
          !blocks.isEmpty else {
      return []
    }
    let workspaceId = AgentWorkspaceScope.id(conversationId: conversationId)
    return AgentWorkspaceScope.withLock(workspaceId: workspaceId) {
      guard let root = try? (projectRoot ?? defaultProjectRoot(fileManager: fileManager)) else {
        return []
      }
      let workspace = root.appendingPathComponent(workspaceId, isDirectory: true).standardizedFileURL
      let inputDirectory = workspace
        .appendingPathComponent("inputs", isDirectory: true)
        .appendingPathComponent(turnId, isDirectory: true)
        .standardizedFileURL
      var isDirectory: ObjCBool = false
      guard inputDirectory.path.hasPrefix(workspace.path + pathSeparator),
            fileManager.fileExists(atPath: inputDirectory.path, isDirectory: &isDirectory),
            isDirectory.boolValue else {
        return []
      }
      var unused = readManifest(directory: inputDirectory, fileManager: fileManager)
      guard !unused.isEmpty else { return [] }
      return blocks
        .filter { attachmentTypes.contains($0.type) && $0.metadata["source"] == "user_attachment" }
        .prefix(maximumRestoredAttachments)
        .compactMap { block in
          let recordIndex = unused.firstIndex { record in
            !block.id.isEmpty && record.attachmentId == block.id
          } ?? unused.firstIndex { record in
            record.name.caseInsensitiveCompare(block.title) == .orderedSame
          }
          guard let recordIndex else { return nil }
          let record = unused.remove(at: recordIndex)
          let expectedPrefix = "inputs/\(turnId)/"
          guard record.attachmentId.count <= 256,
                record.relativePath.hasPrefix(expectedPrefix),
                record.relativePath.range(of: "^inputs/[A-Za-z0-9][A-Za-z0-9._-]{0,127}/[^/]+$", options: .regularExpression) != nil,
                record.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                record.sizeBytes > 0,
                record.sizeBytes <= maximumAttachmentBytes else {
            return nil
          }
          let source = workspace.appendingPathComponent(record.relativePath, isDirectory: false).standardizedFileURL
          guard source.path.hasPrefix(inputDirectory.path + pathSeparator),
                fileManager.fileExists(atPath: source.path),
                let data = try? Data(contentsOf: source, options: [.mappedIfSafe]),
                Int64(data.count) == record.sizeBytes,
                GalaxySSIAttachmentPayloadBuilder.sha256(data) == record.sha256 else {
            return nil
          }
          let attachmentID = block.id.ifBlank(record.attachmentId)
          guard !attachmentID.isEmpty else { return nil }
          let attachment = GalaxySSIDraftAttachment(
            id: attachmentID,
            displayName: record.name,
            mimeType: record.mimeType.ifBlank(block.mimeType),
            data: data,
            sourceDescription: source.absoluteString
          )
          return AgentRestoredAttachment(
            attachment: attachment,
            staged: AgentStagedAttachment(
              name: record.name,
              relativePath: record.relativePath,
              mimeType: record.mimeType,
              sizeBytes: record.sizeBytes,
              sha256: record.sha256
            )
          )
        }
    }
  }

  static func sanitizeName(_ value: String) -> String {
    GalaxySSIAttachmentPayloadBuilder.sanitizeName(value)
  }

  private static func writeManifest(
    directory: URL,
    attachments: [GalaxySSIDraftAttachment],
    staged: [AgentStagedAttachment],
    fileManager: FileManager
  ) throws {
    guard attachments.count == staged.count else {
      throw AgentAttachmentWorkspaceStagingError.commitFailed
    }
    let records = zip(attachments, staged).map { attachment, staged in
      AttachmentManifestRecord(
        attachmentId: String(attachment.id.prefix(256)),
        name: staged.name,
        relativePath: staged.relativePath,
        mimeType: staged.mimeType,
        sizeBytes: staged.sizeBytes,
        sha256: staged.sha256
      )
    }
    let target = directory.appendingPathComponent(manifestFile, isDirectory: false)
    let temporary = directory.appendingPathComponent("\(manifestFile).tmp", isDirectory: false)
    defer { try? fileManager.removeItem(at: temporary) }
    do {
      try JSONEncoder().encode(AttachmentManifest(version: 1, attachments: records))
        .write(to: temporary, options: [.atomic])
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
      try fileManager.moveItem(at: temporary, to: target)
      protectFile(at: target, fileManager: fileManager)
    } catch {
      throw AgentAttachmentWorkspaceStagingError.commitFailed
    }
  }

  private static func readManifest(directory: URL, fileManager: FileManager) -> [AttachmentManifestRecord] {
    let target = directory.appendingPathComponent(manifestFile, isDirectory: false)
    guard fileManager.fileExists(atPath: target.path),
          let data = try? Data(contentsOf: target),
          let manifest = try? JSONDecoder().decode(AttachmentManifest.self, from: data),
          manifest.version == 1 else {
      return []
    }
    return Array(manifest.attachments.prefix(maximumRestoredAttachments))
  }

  private static func defaultProjectRoot(fileManager: FileManager) throws -> URL {
    guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw AgentAttachmentWorkspaceStagingError.unavailable
    }
    return root.appendingPathComponent("agent-native-workspaces", isDirectory: true)
  }

  private static func protectFile(at url: URL, fileManager: FileManager) {
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }

  private static func uniqueName(
    directory: URL,
    baseName: String,
    index: Int,
    fileManager: FileManager
  ) -> String {
    if !fileManager.fileExists(atPath: directory.appendingPathComponent(baseName).path) {
      return baseName
    }
    let extensionValue = (baseName.split(separator: ".").last.map(String.init) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasExtension = !extensionValue.isEmpty && baseName.contains(".")
    let stem = hasExtension ? String(baseName.dropLast(extensionValue.count + 1)) : baseName
    var suffix = index + 1
    while true {
      let candidate = "\(stem)-\(suffix)\(hasExtension ? ".\(extensionValue)" : "")"
      if !fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
        return candidate
      }
      suffix += 1
    }
  }

  private static let safeIdPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#
  private static let pathSeparator = "/"
  private static let manifestFile = ".galaxyssi-attachments.json"
  private static let maximumRestoredAttachments = 10
  private static let attachmentTypes: Set<AgentRichBlockType> = [.image, .file, .video, .audio]
}

struct AgentAnimatedImageFrames {
  var images: [UIImage]
  var duration: TimeInterval
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

  static func frames(from source: Data) -> AgentAnimatedImageFrames? {
    let data = normalizeZeroFrameDelays(source)
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(imageSource)
    guard count > 1 else { return nil }

    var images: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<count {
      guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else { continue }
      images.append(UIImage(cgImage: image))
      duration += frameDelay(imageSource: imageSource, index: index)
    }
    guard images.count > 1 else { return nil }
    return AgentAnimatedImageFrames(
      images: images,
      duration: max(gifDelaySeconds * Double(images.count), duration)
    )
  }

  static func staticImage(from source: Data) -> UIImage? {
    UIImage(data: normalizeZeroFrameDelays(source))
  }

  private static func frameDelay(imageSource: CGImageSource, index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
          let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
      return gifDelaySeconds
    }
    let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let clamped = (gif[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let delay = unclamped > 0 ? unclamped : clamped
    return delay > 0 ? min(delay, 5) : gifDelaySeconds
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

  private static let gifDelaySeconds: TimeInterval = 0.08
}

enum GalaxySSIAttachmentPayloadBuilder {
  static let maximumAttachmentCount = 10
  static let maximumAttachmentBytes = 64 * 1024 * 1024
  static let maximumInlineBytes = 320 * 1024

  static func accepted(_ attachment: GalaxySSIDraftAttachment, existing: [GalaxySSIDraftAttachment]) -> Bool {
    guard existing.count < maximumAttachmentCount else { return false }
    guard attachment.sizeBytes <= maximumAttachmentBytes else { return false }
    return true
  }

  static func messageLabel(for attachments: [GalaxySSIDraftAttachment]) -> String {
    switch attachments.count {
    case 0:
      return ""
    case 1:
      return attachments[0].label
    default:
      return "\(attachments.count) attachments"
    }
  }

  static func descriptors(
    for attachments: [GalaxySSIDraftAttachment],
    mediaProfile: AgentMediaDeliveryProfile? = nil
  ) -> [[String: Any]] {
    var remaining = maximumInlineBytes
    return attachments.prefix(maximumAttachmentCount).map { attachment in
      var item: [String: Any] = [
        "id": attachment.id,
        "name": attachment.displayName,
        "mime_type": attachment.mimeType,
        "size": attachment.sizeBytes,
        "sha256": sha256(attachment.data)
      ]
      if let mediaProfile {
        item["transport_profile"] = mediaProfile.id
      }
      if let inline = AgentMediaAttachmentTransportEncoder.inlinePayload(
        for: attachment,
        profile: mediaProfile,
        remainingBytes: remaining
      ) {
        item["data_b64"] = inline.data.base64EncodedString()
        item["transport_size"] = inline.data.count
        item["transport_lossless"] = inline.lossless
        if inline.mimeType != attachment.mimeType {
          item["transport_mime_type"] = inline.mimeType
        }
        if inline.displayName != attachment.displayName {
          item["transport_name"] = inline.displayName
        }
        remaining -= inline.data.count
      } else {
        item["inline_status"] = "metadata_only"
      }
      return item
    }
  }

  static func promptSuffix(for attachments: [GalaxySSIDraftAttachment]) -> String {
    guard !attachments.isEmpty else { return "" }
    let lines = attachments.map { attachment in
      "- \(attachment.displayName) (\(attachment.mimeType), \(attachment.humanSize), sha256 \(sha256(attachment.data).prefix(12)))"
    }
    return "Attachments:\n" + lines.joined(separator: "\n")
  }

  static func makeAttachment(from url: URL) throws -> GalaxySSIDraftAttachment {
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
    return GalaxySSIDraftAttachment(
      displayName: sanitizeName(name),
      mimeType: type,
      data: data,
      sourceDescription: url.absoluteString
    )
  }

  static func makePhotoAttachment(
    data: Data,
    suggestedName: String = "photo.jpg",
    sourceDescription: String = "photo-library"
  ) -> GalaxySSIDraftAttachment {
    let normalizedData = AgentAnimatedImageTiming.normalizeZeroFrameDelays(data)
    let type = imageMimeType(for: normalizedData) ?? "image/jpeg"
    return GalaxySSIDraftAttachment(
      displayName: sanitizeName(suggestedName),
      mimeType: type,
      data: normalizedData,
      sourceDescription: sourceDescription
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
