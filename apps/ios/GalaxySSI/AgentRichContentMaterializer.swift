import CryptoKit
import Foundation

enum AgentVisualOutputPolicy {
  static let maximumHTMLCharacters = 32_000
  static let maximumHTMLBytes = 128_000
  static let localHTMLPrefix = "galaxyssi-artifact://local-html/"
  static let localVideoPrefix = "galaxyssi-artifact://local-video/"
  static let prompt = "For a playable animation, use a galaxyssi-html fence with complete self-contained HTML, CSS, and JS (up to 32000 characters). No external assets, network, forms, or device APIs. Use ordinary html fences for requested source code. Video requires a real exported MP4 and verified playback; HTML and filenames are not video evidence."

  struct Reply: Sendable {
    var content: String
    var richOutput: String
  }

  enum DeliveryError: Error {
    case invalidPresentation, incompleteHTML, unavailableHTML, unverifiedVideo
  }

  static func envelope(_ raw: String) -> [String: Any]? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("```json"), value.hasSuffix("```") {
      value = String(value.dropFirst(7).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard value.first == "{", value.utf8.count <= AgentRichContentCodec.maximumSerializedSize,
          let json = try? JSONSerialization.jsonObject(with: Data(value.utf8)),
          let root = json as? [String: Any],
          (root["disposition"] as? String)?.lowercased() == "respond" else { return nil }
    return root
  }

  static func declaredBlocks(_ raw: Any) throws -> [AgentRichBlock] {
    guard let document = raw as? [String: Any], let input = document["blocks"] as? [[String: Any]],
          !input.isEmpty, input.count <= AgentRichContentCodec.maximumBlocks,
          (document["version"] as? Int ?? 1) == AgentRichContentCodec.version else {
      throw DeliveryError.invalidPresentation
    }
    for block in input where (block["type"] as? String)?.lowercased() == "html" {
      guard let source = block["text"] as? String, isCompleteHTML(source) else { throw DeliveryError.incompleteHTML }
    }
    let encoded = try JSONSerialization.data(withJSONObject: [
      "version": AgentRichContentCodec.version, "blocks": input
    ])
    let blocks = AgentRichContentCodec.decode(String(decoding: encoded, as: UTF8.self))
    guard !blocks.isEmpty else { throw DeliveryError.invalidPresentation }
    return blocks
  }

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
final class AgentRichContentMaterializer: @unchecked Sendable {
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

  func prepareVisualReply(_ raw: String) throws -> AgentVisualOutputPolicy.Reply? {
    let envelope = AgentVisualOutputPolicy.envelope(raw)
    let content = envelope?["final_response"] as? String ?? raw
    let declared = envelope?["presentation"]
    let presentation = declared as? String ?? ""
    let rich = envelope?["rich_output"]
    var requiredVideoPaths: [String] = []
    if let requirements = envelope?["completion_requirements"] {
      guard let scope = requirements as? [String: Any],
            scope["publication"] == nil || (scope["publication"] as? String) == "none",
            scope["phone_linux"] == nil || (scope["phone_linux"] as? Bool) == false else {
        throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
      }
      if let rawArtifacts = scope["artifacts"] {
        guard presentation == "video", let artifacts = rawArtifacts as? [[String: Any]],
              (1...4).contains(artifacts.count) else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
        requiredVideoPaths = try artifacts.map { item in
          guard let path = item["path"] as? String,
                case .success(let segments) = AgentWorkspaceFilePathPolicy.normalizeRelativePath(path, allowRoot: false),
                segments.last?.lowercased().hasSuffix(".mp4") == true else {
            throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo
          }
          return segments.joined(separator: "/")
        }
        guard Set(requiredVideoPaths).count == requiredVideoPaths.count else {
          throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo
        }
      }
    }
    guard declared == nil || ["inline_html", "source", "video"].contains(presentation) else {
      throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
    }
    if presentation == "video" && requiredVideoPaths.isEmpty { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
    let declaresRichFence = content.range(of: "(?im)^[ \\t]*`{3}galaxyssi-rich[ \\t]*$", options: .regularExpression) != nil
    let declaresHTMLFence = content.range(of: "(?im)^[ \\t]*`{3}galaxyssi-html[ \\t]*$", options: .regularExpression) != nil
    guard envelope != nil || declaresHTMLFence || declaresRichFence else { return nil }
    let textBlocks = AgentRichContentCodec.fromText(content)
    if textBlocks.contains(where: { $0.type == .code && $0.language == "galaxyssi-html" }) {
      throw AgentVisualOutputPolicy.DeliveryError.incompleteHTML
    }
    if textBlocks.contains(where: { $0.type == .code && $0.language == "galaxyssi-rich" }) {
      throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
    }
    var blocks = textBlocks
    if let rich { blocks.append(contentsOf: try AgentVisualOutputPolicy.declaredBlocks(rich)) }
    if presentation == "video" {
      guard !blocks.contains(where: { $0.type == .html }) else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
      let videoIndices = blocks.indices.filter { blocks[$0].type == .video }
      guard videoIndices.count == requiredVideoPaths.count else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
      var remaining = Set(requiredVideoPaths)
      for index in videoIndices {
        let path = blocks[index].metadata["relative_path"] ?? blocks[index].title
        guard remaining.remove(path) != nil, let verified = storeDeclaredVideo(blocks[index], path: path) else {
          throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo
        }
        blocks[index] = verified
      }
    }
    if presentation == "inline_html", !blocks.contains(where: { $0.type == .html }) {
      let source = blocks.indices.filter {
        blocks[$0].type == .code && blocks[$0].language == "html" &&
          AgentVisualOutputPolicy.isDocumentSource(blocks[$0].text)
      }
      guard source.count == 1, let index = source.first,
            AgentVisualOutputPolicy.isCompleteHTML(blocks[index].text) else {
        throw AgentVisualOutputPolicy.DeliveryError.incompleteHTML
      }
      blocks[index].type = .html
      blocks[index].mimeType = "text/html"
    }
    if presentation == "source" && blocks.contains(where: { $0.type == .html }) {
      throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
    }
    if rich == nil, presentation.isEmpty, !declaresRichFence, !blocks.contains(where: { $0.type == .html }) {
      guard let envelope else { return nil }
      guard envelope["final_response"] is String, !content.isBlank else {
        throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
      }
      return AgentVisualOutputPolicy.Reply(content: content, richOutput: "")
    }
    for index in blocks.indices where blocks[index].type == .html {
      guard !blocks[index].text.isEmpty, let saved = storeDeclaredHTML(blocks[index]) else {
        throw AgentVisualOutputPolicy.DeliveryError.unavailableHTML
      }
      blocks[index] = saved
    }
    let encoded = AgentRichContentCodec.encode(blocks)
    guard !encoded.isEmpty, AgentRichContentCodec.decode(encoded).count == blocks.count else {
      throw AgentVisualOutputPolicy.DeliveryError.invalidPresentation
    }
    let prose = blocks.filter { [.text, .heading, .quote].contains($0.type) }.map(\.text).joined(separator: "\n\n")
    return AgentVisualOutputPolicy.Reply(content: prose, richOutput: encoded)
  }

  private func storeDeclaredVideo(_ block: AgentRichBlock, path: String) -> AgentRichBlock? {
    locked {
      guard block.mimeType.lowercased() == "video/mp4", block.uri.isEmpty,
            let data = Data(base64Encoded: block.dataB64), (16...315_000).contains(data.count) else { return nil }
      let digest = Self.sha256(data)
      let purpose = "rich-video:\(digest)"
      let url = directoryURL.appendingPathComponent("\(digest).mp4", isDirectory: false)
      do {
        if cipher.plaintextSize(of: url, purpose: purpose) != Int64(data.count) ||
            (try? cipher.read(from: url, purpose: purpose)) != data {
          try cipher.write(data, to: url, purpose: purpose)
        }
        guard try cipher.read(from: url, purpose: purpose) == data,
              let evidence = AgentIOSMP4Openability.inspect(url) else {
          try? fileManager.removeItem(at: url)
          return nil
        }
        return Self.videoBlock(id: block.id, path: path, digest: digest, size: Int64(data.count),
                               evidence: evidence, fallback: block.fallbackText)
      } catch {
        return nil
      }
    }
  }

  func loadDeclaredHTML(_ block: AgentRichBlock) -> String? {
    locked { readDeclaredHTML(block) }
  }

  func loadDeclaredVideoURL(_ block: AgentRichBlock) -> URL? {
    guard block.type == .video, let digest = block.metadata["sha256"],
          digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
          block.uri == AgentVisualOutputPolicy.localVideoPrefix + digest,
          let size = Int64(block.metadata["size_bytes"] ?? "") else { return nil }
    let file = directoryURL.appendingPathComponent("\(digest).mp4")
    guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
          values.isRegularFile == true, values.isSymbolicLink != true,
          let actualSize = values.fileSize, Int64(actualSize) == size else { return nil }
    return file
  }

  func prepareWorkspaceVideos(_ receipts: [AgentVerifiedWorkspaceVideo], root: URL) throws -> [AgentRichBlock] {
    try locked {
      try receipts.map { receipt in
        guard let artifact = AgentVideoArtifactRequirement(workspaceId: receipt.workspaceId, path: receipt.path),
              artifact.path == receipt.path,
              receipt.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              (16...268_435_456).contains(receipt.size) else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let workspace = resolvedRoot.appendingPathComponent(receipt.workspaceId, isDirectory: true)
        let source = workspace.appendingPathComponent(receipt.path).standardizedFileURL
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.resolvingSymlinksInPath().path == source.path, source.path.hasPrefix(workspace.path + "/"),
              values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize.map(Int64.init) == receipt.size else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let temporary = directoryURL.appendingPathComponent(".\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        guard try Self.digestOfVideo(temporary, size: receipt.size) == receipt.sha256,
              let evidence = AgentIOSMP4Openability.inspect(temporary) else {
          throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo
        }
        let final = directoryURL.appendingPathComponent("\(receipt.sha256).mp4")
        try (temporary as NSURL).setResourceValue(FileProtectionType.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
        var protectedURL = temporary
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resources)
        if fileManager.fileExists(atPath: final.path) {
          if (try? Self.digestOfVideo(final, size: receipt.size)) != receipt.sha256 {
            _ = try fileManager.replaceItemAt(final, withItemAt: temporary)
          }
        } else {
          try fileManager.moveItem(at: temporary, to: final)
        }
        let pathId = Self.sha256(Data(receipt.path.utf8)).prefix(16)
        return Self.videoBlock(id: "workspace-video:\(receipt.sha256.prefix(24)):\(pathId)", path: receipt.path,
          digest: receipt.sha256, size: receipt.size, evidence: evidence)
      }
    }
  }

  private static func digestOfVideo(_ file: URL, size: Int64) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var digest = SHA256()
    var total: Int64 = 0
    while let chunk = try handle.read(upToCount: 256 * 1_024), !chunk.isEmpty {
      total += Int64(chunk.count)
      guard total <= size else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
      digest.update(data: chunk)
    }
    guard total == size else { throw AgentVisualOutputPolicy.DeliveryError.unverifiedVideo }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func videoBlock(id: String, path: String, digest: String, size: Int64,
                                 evidence: AgentIOSMP4Openability.Evidence, fallback: String = "") -> AgentRichBlock {
    AgentRichBlock(id: id, type: .video, title: URL(fileURLWithPath: path).lastPathComponent,
      uri: AgentVisualOutputPolicy.localVideoPrefix + digest, mimeType: "video/mp4", fallbackText: fallback,
      metadata: [
        "size_bytes": String(size), "sha256": digest, "storage": "app_private_file",
        "relative_path": path, "display_extension": "mp4", "duration_ms": String(evidence.durationMillis),
        "decoded_frame_width": String(evidence.frameWidth), "decoded_frame_height": String(evidence.frameHeight)
      ])
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
