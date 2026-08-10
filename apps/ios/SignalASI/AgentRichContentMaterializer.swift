import CryptoKit
import Foundation

/// Stores inline rich-output payloads in app-private storage before they enter the transcript.
final class AgentRichContentMaterializer {
  static let defaultDirectoryName = "agent-rich-output"
  static let maximumMaterializedBytes = 4 * 1024 * 1024

  private let directoryURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()

  init(directoryURL: URL, fileManager: FileManager = .default) {
    self.directoryURL = directoryURL.standardizedFileURL
    self.fileManager = fileManager
  }

  convenience init(
    applicationSupportDirectory: URL,
    fileManager: FileManager = .default
  ) {
    self.init(
      directoryURL: applicationSupportDirectory
        .appendingPathComponent(Self.defaultDirectoryName, isDirectory: true),
      fileManager: fileManager
    )
  }

  func materialize(_ raw: String) -> String {
    locked {
      let normalized = AgentRichContentCodec.normalize(raw)
      guard !normalized.isEmpty else { return "" }
      let blocks = AgentRichContentCodec.decode(normalized)
      guard blocks.contains(where: { !$0.dataB64.isEmpty }) else { return normalized }

      let materialized = blocks.map { block in
        materializeBlock(block) ?? block
      }
      return AgentRichContentCodec.encode(materialized)
    }
  }

  private func materializeBlock(_ block: AgentRichBlock) -> AgentRichBlock? {
    guard !block.dataB64.isEmpty,
          let data = Data(base64Encoded: block.dataB64, options: [.ignoreUnknownCharacters]),
          !data.isEmpty,
          data.count <= Self.maximumMaterializedBytes else {
      return nil
    }

    let digest = SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
    let target = directoryURL.appendingPathComponent(
      "\(digest).\(extensionFor(block))",
      isDirectory: false
    )

    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let attributes = try? fileManager.attributesOfItem(atPath: target.path)
      let existingBytes = (attributes?[.size] as? NSNumber)?.intValue
      if existingBytes != data.count {
        let temporary = directoryURL.appendingPathComponent("\(digest).tmp", isDirectory: false)
        try data.write(to: temporary, options: [.atomic])
        if fileManager.fileExists(atPath: target.path) {
          try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: temporary, to: target)
      }
    } catch {
      return nil
    }

    return AgentRichBlock(
      id: block.id,
      type: block.type,
      title: block.title,
      text: block.text,
      uri: target.absoluteString,
      dataB64: "",
      mimeType: block.mimeType,
      language: block.language,
      columns: block.columns,
      rows: block.rows,
      value: block.value,
      maximum: block.maximum,
      fallbackText: block.fallbackText,
      actions: block.actions,
      fields: block.fields,
      metadata: block.metadata.merging([
        "size_bytes": String(data.count),
        "sha256": digest,
        "storage": "app_private"
      ]) { _, new in new }
    )
  }

  private func extensionFor(_ block: AgentRichBlock) -> String {
    switch block.mimeType.lowercased() {
    case "image/jpeg": return "jpg"
    case "image/png": return "png"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    case "image/heic", "image/heif": return "heic"
    case "audio/mpeg": return "mp3"
    case "audio/mp4", "audio/x-m4a": return "m4a"
    case "audio/wav", "audio/x-wav": return "wav"
    case "video/mp4": return "mp4"
    case "application/pdf": return "pdf"
    case "application/zip": return "zip"
    case "text/plain": return "txt"
    default:
      switch block.type {
      case .image, .gallery: return "img"
      case .audio: return "audio"
      case .video: return "video"
      default: return "bin"
      }
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
