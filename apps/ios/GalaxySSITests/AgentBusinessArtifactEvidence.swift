import CryptoKit
import Foundation
import ImageIO
@testable import GalaxySSI

enum AgentBusinessArtifactEvidence {
  private static let images: Set<String> = ["png", "jpg", "jpeg"]
  private static let supported: Set<String> = images.union(["pdf", "docx", "xlsx", "pptx"])
  private static let maximumBytes = 64 * 1_024 * 1_024

  struct Expectation: Decodable {
    var text_only: Bool? = nil
    var extensions: [String]? = nil
    var name_prefix: String? = nil
    var preview_required: Bool? = nil
    var editable_office: Bool? = nil
    var max_image_count: Int? = nil
    var image_extensions: [String]? = nil
    var expected_dimensions: [Int]? = nil
  }

  struct Item: Codable {
    let id: String?
    var type: String
    var fileExtension: String? = nil
    var received = false
    var container_valid = false
    var version_name_matches = false
    var save_api_pass = false
    var download_hash_matches = false
    var sha256: String? = nil
    var image_width: Int? = nil
    var image_height: Int? = nil

    enum CodingKeys: String, CodingKey {
      case id, type, received, container_valid, version_name_matches, save_api_pass, download_hash_matches
      case sha256, image_width, image_height
      case fileExtension = "extension"
    }

    var isImage: Bool { type.lowercased() == "image" || fileExtension.map(images.contains) == true }
    var verified: Bool { received && container_valid && version_name_matches && save_api_pass && download_hash_matches }
  }

  struct Assessment: Codable {
    var correct = false
    var all_artifacts_present: Bool? = nil
    var all_artifacts_verified: Bool? = nil
    var unexpected_file_count: Int? = nil
    var artifacts: [Item]? = nil
    var missing_extensions: [String]? = nil
    var preview_received: Bool? = nil
    var content_verified = false
    var preview_fidelity_verified = false
    var ui_open_save_verified = false
    var requires_human_review = true
  }

  private struct RichDeclaration: Decodable {
    let version: Int
    let blocks: [AgentRichBlock]
  }

  private struct RecordedAssessment: Decodable {
    let correct: Bool
    let all_artifacts_present: Bool?
    let all_artifacts_verified: Bool?
    let unexpected_file_count: Int?
    let artifacts: [Item]?
  }

  static func collect(_ expected: Expectation, message: ChatMessage, conversation: String, turn: String,
                      store: AgentDesktopArtifactStore, directory: URL) throws -> Assessment {
    guard !conversation.isEmpty, !turn.isEmpty, message.conversationId == conversation,
          message.turnId == turn, !message.isMine, !message.isSystem, message.deliveryStatus == .delivered,
          let declared = declaredFiles(message) else { return Assessment() }
    if expected.text_only == true {
      return Assessment(correct: declared.isEmpty && !message.content.isBlank, unexpected_file_count: declared.count)
    }
    guard let prefix = expected.name_prefix, !prefix.isBlank,
          let extensions = expected.extensions, !extensions.isEmpty,
          extensions.allSatisfy(supported.contains), !declared.isEmpty else { return Assessment() }
    let fs = FileManager.default
    let capture = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fs.createDirectory(at: capture, withIntermediateDirectories: false)
    defer { try? fs.removeItem(at: capture) }
    let sources = capture.appendingPathComponent("sources", isDirectory: true)
    let items = declared.enumerated().map { index, block in
      inspect(block, index: index, prefix: prefix, store: store, sources: sources, destination: capture)
    }
    let requirements = requirementsCheck(expected, items: items)
    let present = items.allSatisfy(\.received)
    let verified = items.allSatisfy(\.verified)
    return Assessment(correct: present && verified && requirements.matches, all_artifacts_present: present,
      all_artifacts_verified: verified, artifacts: items, missing_extensions: requirements.missing,
      preview_received: requirements.preview)
  }

  static func recheck(_ expected: Expectation, original: Data) -> Bool {
    guard let assessment = try? JSONDecoder().decode(RecordedAssessment.self, from: original), assessment.correct else {
      return false
    }
    if expected.text_only == true { return assessment.unexpected_file_count == 0 }
    guard assessment.all_artifacts_present == true, assessment.all_artifacts_verified == true,
          let items = assessment.artifacts, !items.isEmpty, items.allSatisfy(\.verified) else { return false }
    return requirementsCheck(expected, items: items).matches
  }

  private static func declaredFiles(_ message: ChatMessage) -> [AgentRichBlock]? {
    let raw = message.richOutputJson
    if raw.isBlank {
      return AgentRichContentCodec.presentationBlocks(content: message.content, richOutputJson: "")
        .filter { $0.type == .file || $0.type == .image }
    }
    let bytes = Data(raw.utf8)
    guard bytes.count <= AgentRichContentCodec.maximumSerializedSize,
          let value = try? JSONDecoder().decode(RichDeclaration.self, from: bytes),
          value.version == AgentRichContentCodec.version, value.blocks.count <= AgentRichContentCodec.maximumBlocks else {
      return nil
    }
    // Use the declaration, not the display projection, which may collapse or omit blocks.
    return value.blocks.filter { $0.type == .file || $0.type == .image }
  }

  private static func inspect(_ block: AgentRichBlock, index: Int, prefix: String, store: AgentDesktopArtifactStore,
                              sources: URL, destination: URL) -> Item {
    var item = Item(id: block.id, type: block.type.rawValue)
    let resolved = store.resolveBlock(block)
    guard let name = resolved.metadata["artifact_name"], let digest = resolved.metadata["sha256"],
          AgentArtifactRequirement.validDigest(digest),
          let size = resolved.metadata["size_bytes"].flatMap(Int.init), (1...maximumBytes).contains(size),
          let file = store.localFile(for: block, materializationRoot: sources) else { return item }
    defer { try? FileManager.default.removeItem(at: file) }
    guard let bytes = try? read(file), bytes.count == size, sha256(bytes) == digest.lowercased() else { return item }
    item.received = true
    item.sha256 = sha256(bytes)
    let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
    item.fileExtension = ext
    let safeName = AgentDesktopArtifactStore.safeFileName(block.title.ifBlank(name))
    item.version_name_matches = matchesVersion(prefix, name: name) && matchesVersion(prefix, name: safeName) &&
      URL(fileURLWithPath: safeName).pathExtension.lowercased() == ext
    item.container_valid = supported.contains(ext) && (!item.isImage || images.contains(ext)) &&
      AgentVerifiedArtifactSnapshot.verifiesContainer(bytes, extension: ext)
    if images.contains(ext), item.container_valid,
       let image = CGImageSourceCreateWithData(bytes as CFData, nil),
       let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any] {
      item.image_width = properties[kCGImagePropertyPixelWidth] as? Int
      item.image_height = properties[kCGImagePropertyPixelHeight] as? Int
    }
    let saved = destination.appendingPathComponent("\(index)-\(safeName)")
    defer { try? FileManager.default.removeItem(at: saved) }
    do {
      try GalaxySSIArtifactDocument(data: bytes).exportFileWrapper()
        .write(to: saved, options: .atomic, originalContentsURL: nil)
      item.save_api_pass = true
      item.download_hash_matches = try sha256(read(saved)) == item.sha256
    } catch {}
    return item
  }

  private static func matchesVersion(_ version: String, name: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: version)
    return !version.isEmpty &&
      name.range(of: "(?:^|[._ -])" + escaped + "(?:$|[._ -])", options: .regularExpression) != nil
  }

  private static func requirementsCheck(_ expected: Expectation, items: [Item])
    -> (matches: Bool, missing: [String], preview: Bool) {
    let required = expected.extensions ?? []
    let missing = required.filter { ext in !items.contains { $0.fileExtension == ext && $0.verified } }
    let imageItems = items.filter(\.isImage)
    let preview = imageItems.contains { $0.verified && ($0.image_width ?? 0) >= 128 && ($0.image_height ?? 0) >= 128 }
    let validImages = imageItems.allSatisfy { item in
      guard let ext = item.fileExtension, images.contains(ext), item.container_valid,
            (item.image_width ?? 0) > 0, (item.image_height ?? 0) > 0 else { return false }
      return (expected.editable_office != true || ext == "png") && (expected.image_extensions?.contains(ext) ?? true)
    }
    let imageCountOK = expected.max_image_count.map { imageItems.count <= $0 } ?? true
    let dimensionsOK = expected.expected_dimensions.map { expected in
      expected.count == 2 && !imageItems.isEmpty && imageItems.allSatisfy {
        $0.image_width == expected[0] && $0.image_height == expected[1]
      }
    } ?? true
    let matches = !required.isEmpty && required.allSatisfy(supported.contains) && missing.isEmpty &&
      items.allSatisfy { $0.fileExtension.map(supported.contains) == true } &&
      (expected.preview_required == false || preview) && validImages && imageCountOK && dimensionsOK &&
      (expected.image_extensions == nil || !imageItems.isEmpty)
    return (matches, missing, preview)
  }

  private static func read(_ file: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard (1...maximumBytes).contains(bytes.count) else { throw CocoaError(.fileReadCorruptFile) }
    return bytes
  }

  private static func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
