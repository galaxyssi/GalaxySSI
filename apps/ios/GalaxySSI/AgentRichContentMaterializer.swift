import CryptoKit
import Foundation

enum AgentVisualOutputPolicy {
  static let maximumHTMLCharacters = 32_000
  static let maximumHTMLBytes = 128_000
  static let localHTMLPrefix = "galaxyssi-artifact://local-html/"

  static func isCompleteHTML(_ html: String) -> Bool {
    guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          html.count <= maximumHTMLCharacters, html.utf8.count <= maximumHTMLBytes else { return false }
    let fullDocument = isDocumentSource(html) ||
      html.range(of: #"<html(?:\s|>)"#, options: [.caseInsensitive, .regularExpression]) != nil
    return (!fullDocument || html.range(of: #"</html\s*>"#, options: [.caseInsensitive, .regularExpression]) != nil) &&
      count(#"<script(?:\s|>)"#, in: html) == count(#"</script\s*>"#, in: html)
  }

  static func isDocumentSource(_ html: String) -> Bool {
    html.range(of: #"^\s*(?:<!doctype\s+html(?:\s|>)|<html(?:\s|>))"#,
               options: [.caseInsensitive, .regularExpression]) != nil
  }

  private static func count(_ pattern: String, in text: String) -> Int {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
    return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
  }
}

/// Stores inline rich-output payloads in app-private storage before they enter the transcript.
final class AgentRichContentMaterializer {
  static let defaultDirectoryName = "agent-rich-output-v2"
  static let maximumMaterializedBytes = 4 * 1024 * 1024

  private let directoryURL: URL
  private let fileManager: FileManager
  private let cipher: any GalaxySSILocalAttachmentStoring
  private let lock = NSLock()

  init(
    directoryURL: URL,
    fileManager: FileManager = .default,
    cipher: any GalaxySSILocalAttachmentStoring = GalaxySSILocalAttachmentStore.shared
  ) {
    self.directoryURL = directoryURL.standardizedFileURL
    self.fileManager = fileManager
    self.cipher = cipher
  }

  convenience init(
    applicationSupportDirectory: URL,
    fileManager: FileManager = .default,
    cipher: any GalaxySSILocalAttachmentStoring = GalaxySSILocalAttachmentStore.shared
  ) {
    self.init(
      directoryURL: applicationSupportDirectory
        .appendingPathComponent(Self.defaultDirectoryName, isDirectory: true),
      fileManager: fileManager,
      cipher: cipher
    )
  }

  func materialize(_ raw: String) -> String {
    locked {
      let normalized = AgentRichContentCodec.normalize(raw)
      guard !normalized.isEmpty else { return "" }
      let blocks = AgentRichContentCodec.decode(normalized)
      guard blocks.contains(where: { !$0.dataB64.isEmpty || $0.type == .html }) else { return normalized }

      let materialized = blocks.map { block in
        if block.type == .html { return materializeHTMLBlock(block) ?? block }
        return materializeBlock(block) ?? block
      }
      return AgentRichContentCodec.encode(materialized)
    }
  }

  func storeDeclaredHTML(_ block: AgentRichBlock) -> AgentRichBlock? {
    locked { materializeHTMLBlock(block) }
  }

  func loadDeclaredHTML(_ block: AgentRichBlock) -> String? {
    locked { readDeclaredHTML(block) }
  }

  private func materializeHTMLBlock(_ block: AgentRichBlock) -> AgentRichBlock? {
    guard block.type == .html else { return nil }
    if block.text.isEmpty { return readDeclaredHTML(block) == nil ? nil : block }
    guard AgentVisualOutputPolicy.isCompleteHTML(block.text) else { return nil }
    let data = Data(block.text.utf8)
    let digest = Self.sha256(data)
    let target = htmlURL(digest)
    let purpose = "rich-html:\(digest)"
    var artifact = block
    artifact.text = ""
    artifact.dataB64 = ""
    artifact.uri = AgentVisualOutputPolicy.localHTMLPrefix + digest
    artifact.mimeType = "text/html"
    artifact.metadata = [
      "size_bytes": String(data.count), "sha256": digest, "storage": "app_private_file",
      "display_extension": "html"
    ]
    if readDeclaredHTML(artifact) == nil {
      do { try cipher.write(data, to: target, purpose: purpose) } catch { return nil }
    }
    return readDeclaredHTML(artifact) == block.text ? artifact : nil
  }

  private func readDeclaredHTML(_ block: AgentRichBlock) -> String? {
    guard block.type == .html, let digest = block.metadata["sha256"],
          digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
          block.uri == AgentVisualOutputPolicy.localHTMLPrefix + digest,
          let count = Int(block.metadata["size_bytes"] ?? ""), (1...AgentVisualOutputPolicy.maximumHTMLBytes).contains(count)
    else { return nil }
    let target = htmlURL(digest)
    let purpose = "rich-html:\(digest)"
    guard cipher.plaintextSize(of: target, purpose: purpose) == Int64(count),
          let data = try? cipher.read(from: target, purpose: purpose), data.count == count, Self.sha256(data) == digest,
          let html = String(data: data, encoding: .utf8), AgentVisualOutputPolicy.isCompleteHTML(html) else { return nil }
    return html
  }

  private func htmlURL(_ digest: String) -> URL {
    directoryURL.appendingPathComponent("\(digest).html", isDirectory: false)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func materializeBlock(_ block: AgentRichBlock) -> AgentRichBlock? {
    guard !block.dataB64.isEmpty,
          let data = Data(base64Encoded: block.dataB64, options: [.ignoreUnknownCharacters]),
          !data.isEmpty,
          data.count <= Self.maximumMaterializedBytes else {
      return nil
    }

    let digest = Self.sha256(data)
    let target = directoryURL.appendingPathComponent(
      "\(digest).saenc",
      isDirectory: false
    )
    let purpose = "rich-content:\(digest)"

    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let existingBytes = cipher.plaintextSize(of: target, purpose: purpose).map(Int.init)
      if existingBytes != data.count {
        try cipher.write(data, to: target, purpose: purpose)
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
        "storage": "app_private_file",
        "encryption_purpose": purpose,
        "display_extension": extensionFor(block)
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
    case "audio/ogg", "audio/opus": return "opus"
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
