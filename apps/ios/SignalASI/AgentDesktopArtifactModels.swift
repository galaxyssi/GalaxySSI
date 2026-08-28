import CryptoKit
import Foundation

struct AgentDesktopArtifactRequestPayload: Equatable {
  var artifactURI: String
  var displayName: String
  var artifactID: String
  var taskID: String
  var sha256: String
  var desktopID: String
  var clientRouteID: String

  static func decode(_ raw: String) -> AgentDesktopArtifactRequestPayload? {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let artifactURI = string(object, keys: ["artifact_uri", "artifact_source_uri", "uri"])
    let sha256 = string(object, keys: ["sha256", "digest"]).lowercased()
    guard !artifactURI.isEmpty,
          sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
      return nil
    }
    return AgentDesktopArtifactRequestPayload(
      artifactURI: artifactURI,
      displayName: string(object, keys: ["display_name", "name"]).ifBlank("SignalASI-artifact"),
      artifactID: string(object, keys: ["artifact_id"]),
      taskID: string(object, keys: ["task_id"]),
      sha256: sha256,
      desktopID: string(object, keys: ["desktop_id"]),
      clientRouteID: string(object, keys: ["client_route_id"])
    )
  }

  var richBlock: AgentRichBlock {
    let metadata = [
      "artifact_id": artifactID,
      "artifact_source_uri": artifactURI,
      "client_route_id": clientRouteID,
      "desktop_id": desktopID,
      "sha256": sha256,
      "task_id": taskID
    ].filter { !$0.value.isEmpty }
    return AgentRichBlock(
      id: artifactID.ifBlank(artifactURI),
      type: .file,
      title: AgentDesktopArtifactStore.safeFileName(displayName),
      uri: artifactURI,
      mimeType: "application/octet-stream",
      metadata: metadata
    )
  }

  private init(
    artifactURI: String,
    displayName: String,
    artifactID: String,
    taskID: String,
    sha256: String,
    desktopID: String,
    clientRouteID: String
  ) {
    self.artifactURI = artifactURI.trimmingCharacters(in: .whitespacesAndNewlines)
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.artifactID = artifactID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.taskID = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.desktopID = desktopID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.clientRouteID = clientRouteID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func string(_ object: [String: Any], keys: [String]) -> String {
    for key in keys {
      if let value = object[key] as? String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
      }
    }
    return ""
  }
}

struct AgentDesktopArtifactIngestResult: Equatable {
  var completed: Bool
  var artifactId: String
  var artifactURI: String
  var sha256: String
  var taskId: String
}

enum AgentDesktopArtifactStoreError: Error, Equatable {
  case invalidPayload(String)
  case integrity(String)
  case unavailable(String)
}

final class AgentDesktopArtifactStore {
  static let defaultRootDirectoryName = "desktop-artifacts-v2"

  private let rootURL: URL
  private let fileManager: FileManager
  private let cipher: SignalASIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()

  init(
    rootURL: URL,
    fileManager: FileManager = .default,
    cipher: SignalASIAttachmentAtRestCipher = .shared
  ) {
    self.rootURL = rootURL
    self.fileManager = fileManager
    self.cipher = cipher
  }

  convenience init(
    applicationSupportDirectory: URL,
    fileManager: FileManager = .default,
    cipher: SignalASIAttachmentAtRestCipher = .shared
  ) {
    self.init(
      rootURL: applicationSupportDirectory.appendingPathComponent(Self.defaultRootDirectoryName, isDirectory: true),
      fileManager: fileManager,
      cipher: cipher
    )
  }

  func ingest(_ payload: [String: Any]) throws -> AgentDesktopArtifactIngestResult {
    try locked {
      let typed = try AgentDesktopArtifactChunkPayload(payload)
      if let record = try existingRecord(artifactURI: typed.artifactURI),
        record.artifactId == typed.artifactId,
        record.sha256 == typed.sha256,
        let file = try artifactFile(record: record),
        cipher.plaintextSize(
          of: file,
          purpose: artifactPurpose(record.artifactId)
        ) == record.sizeBytes {
        return AgentDesktopArtifactIngestResult(
          completed: true,
          artifactId: typed.artifactId,
          artifactURI: typed.artifactURI,
          sha256: typed.sha256,
          taskId: typed.taskId
        )
      }

      let incoming = incomingDirectory.appendingPathComponent(typed.artifactId, isDirectory: true)
      try fileManager.createDirectory(at: incoming, withIntermediateDirectories: true)
      let manifestURL = incoming.appendingPathComponent("manifest.json", isDirectory: false)
      let manifest = typed.manifest
      let manifestData = try stableJSONData(manifest)
      if fileManager.fileExists(atPath: manifestURL.path) {
        let existing = try Data(contentsOf: manifestURL)
        guard existing == manifestData else {
          throw AgentDesktopArtifactStoreError.invalidPayload("Artifact chunk metadata mismatch")
        }
      } else {
        try writeAtomic(manifestData, to: manifestURL)
      }

      let bytes = typed.chunkData
      let chunkURL = incoming.appendingPathComponent("\(typed.chunkIndex).chunk", isDirectory: false)
      if fileManager.fileExists(atPath: chunkURL.path) {
        let existing = try cipher.read(
          from: chunkURL,
          purpose: chunkPurpose(artifactId: typed.artifactId, index: typed.chunkIndex)
        )
        guard Int64(existing.count) == typed.chunkSizeBytes && sha256(existing) == typed.chunkSHA256 else {
          throw AgentDesktopArtifactStoreError.integrity("Conflicting artifact chunk duplicate")
        }
      } else {
        try cipher.write(
          bytes,
          to: chunkURL,
          purpose: chunkPurpose(artifactId: typed.artifactId, index: typed.chunkIndex)
        )
      }

      let complete = (0..<typed.chunkCount).allSatisfy {
        cipher.plaintextSize(
          of: incoming.appendingPathComponent("\($0).chunk", isDirectory: false),
          purpose: chunkPurpose(artifactId: typed.artifactId, index: $0)
        ) == Int64(expectedChunkSize(total: typed.sizeBytes, index: $0))
      }
      if !complete {
        return AgentDesktopArtifactIngestResult(
          completed: false,
          artifactId: typed.artifactId,
          artifactURI: typed.artifactURI,
          sha256: typed.sha256,
          taskId: typed.taskId
        )
      }

      try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
      let target = filesDirectory.appendingPathComponent("\(typed.artifactId).saenc", isDirectory: false)
      try assembleChunks(
        incoming: incoming,
        target: target,
        artifactId: typed.artifactId,
        chunkCount: typed.chunkCount,
        expectedSizeBytes: typed.sizeBytes,
        expectedSHA256: typed.sha256
      )

      let record = AgentDesktopArtifactRecord(
        artifactId: typed.artifactId,
        artifactURI: typed.artifactURI,
        taskId: typed.taskId,
        name: typed.name,
        mimeType: typed.mimeType,
        sizeBytes: typed.sizeBytes,
        sha256: typed.sha256,
        originalSizeBytes: typed.originalSizeBytes,
        originalSHA256: typed.originalSHA256,
        chunkCount: typed.chunkCount,
        relativeFile: try relativePath(from: rootURL, to: target),
        storedAtMillis: nowMillis(),
        savedToDownloads: false,
        savedURI: "",
        savedAtMillis: 0
      )
      try writeRecord(record, artifactURI: typed.artifactURI)
      try? fileManager.removeItem(at: incoming)
      return AgentDesktopArtifactIngestResult(
        completed: true,
        artifactId: typed.artifactId,
        artifactURI: typed.artifactURI,
        sha256: typed.sha256,
        taskId: typed.taskId
      )
    }
  }

  func resolveBlock(_ block: AgentRichBlock) -> AgentRichBlock {
    let sourceURI = (block.metadata["artifact_source_uri"] ?? "").ifBlank(block.uri)
    guard Self.isSignalASIArtifactURI(sourceURI),
      let record = try? existingRecord(artifactURI: sourceURI),
      let file = try? artifactFile(record: record),
      fileManager.fileExists(atPath: file.path) else {
      return block
    }
    let deliveredSize = record.sizeBytes
    let originalSize = max(record.originalSizeBytes, deliveredSize)
    let category = block.metadata["category"] ?? ""
    let generatedSizeText = !category.isEmpty && block.text.hasPrefix("\(category) \u{00B7} ")
    let safeURI = "signalasi-local-artifact://\(record.artifactId)"
    return AgentRichBlock(
      id: block.id,
      type: block.type,
      title: block.title,
      text: generatedSizeText ? "\(category) \u{00B7} \(Self.humanSize(deliveredSize))" : block.text,
      uri: safeURI,
      dataB64: block.dataB64,
      mimeType: record.mimeType.ifBlank(block.mimeType),
      language: block.language,
      columns: block.columns,
      rows: block.rows,
      value: block.value,
      maximum: block.maximum,
      fallbackText: block.fallbackText,
      actions: block.actions,
      fields: block.fields,
      metadata: block.metadata.merging([
        "artifact_id": record.artifactId,
        "artifact_source_uri": sourceURI,
        "artifact_reference": safeURI,
        "size": Self.humanSize(deliveredSize),
        "size_bytes": String(deliveredSize),
        "original_size": Self.humanSize(originalSize),
        "original_size_bytes": String(originalSize),
        "sha256": record.sha256,
        "transport": "encrypted-fragmented",
        "storage": "attachment_aes_256_gcm",
        "saved_to_downloads": record.savedToDownloads ? "true" : "false"
      ]) { _, new in new }
    )
  }

  func localFile(for block: AgentRichBlock) -> URL? {
    let resolved = resolveBlock(block)
    guard let sourceURI = resolved.metadata["artifact_source_uri"],
      let record = try? existingRecord(artifactURI: sourceURI),
      let file = try? artifactFile(record: record),
      fileManager.fileExists(atPath: file.path) else {
      return nil
    }
    return try? cipher.materializeTemporaryFile(
      from: file,
      purpose: artifactPurpose(record.artifactId),
      displayName: record.name
    )
  }

  func saveArtifactUriToDownloads(sourceURI: String) throws -> String {
    try locked {
      guard let record = try existingRecord(artifactURI: sourceURI),
            let source = try artifactFile(record: record),
            fileManager.fileExists(atPath: source.path) else {
        throw AgentDesktopArtifactStoreError.unavailable("Artifact is not available")
      }
      let fileName = Self.safeFileName(record.name).ifBlank("SignalASI-artifact")
      guard let downloadsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("Downloads", isDirectory: true)
        .appendingPathComponent("SignalASI", isDirectory: true) else {
        throw AgentDesktopArtifactStoreError.unavailable("Downloads directory is unavailable")
      }
      try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
      let destination = downloadsDirectory.appendingPathComponent(fileName, isDirectory: false)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      let plaintext = try cipher.read(
        from: source,
        purpose: artifactPurpose(record.artifactId)
      )
      try plaintext.write(to: destination, options: [.atomic])

      var updated = record
      updated.savedToDownloads = true
      updated.savedURI = destination.absoluteString
      updated.savedAtMillis = nowMillis()
      try writeRecord(updated, artifactURI: sourceURI)
      return "Downloads/SignalASI/\(fileName)"
    }
  }

  func markSavedToDownloads(sourceURI: String, savedURI: String) throws {
    try locked {
      var record = try existingRecord(artifactURI: sourceURI)
      guard record != nil else {
        throw AgentDesktopArtifactStoreError.unavailable("Artifact is not available")
      }
      record?.savedToDownloads = true
      record?.savedURI = savedURI
      record?.savedAtMillis = nowMillis()
      try record.map { try writeRecord($0, artifactURI: sourceURI) }
    }
  }

  func clear() throws {
    try locked {
      if fileManager.fileExists(atPath: rootURL.path) {
        try fileManager.removeItem(at: rootURL)
      }
    }
  }

  static func humanSize(_ bytes: Int64) -> String {
    if bytes < 1_024 {
      return "\(bytes) B"
    }
    if bytes < 1_024 * 1_024 {
      return String(format: "%.1f KB", Double(bytes) / 1_024.0)
    }
    return String(format: "%.1f MB", Double(bytes) / (1_024.0 * 1_024.0))
  }

  static func isSignalASIArtifactURI(_ value: String) -> Bool {
    URLComponents(string: value)?.scheme?.lowercased() == "signalasi-artifact"
  }

  static func stableID(uri: String, sha256: String) -> String {
    SHA256.hash(data: Data("\(uri)\0\(sha256)".utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func safeFileName(_ value: String) -> String {
    AgentRichFormatRegistry.safeFileName(value)
  }

  private func assembleChunks(
    incoming: URL,
    target: URL,
    artifactId: String,
    chunkCount: Int,
    expectedSizeBytes: Int64,
    expectedSHA256: String
  ) throws {
    var data = Data()
    data.reserveCapacity(Int(min(expectedSizeBytes, Int64(Int.max))))
    for index in 0..<chunkCount {
      let chunkURL = incoming.appendingPathComponent("\(index).chunk", isDirectory: false)
      data.append(try cipher.read(
        from: chunkURL,
        purpose: chunkPurpose(artifactId: artifactId, index: index)
      ))
    }
    guard Int64(data.count) == expectedSizeBytes && sha256(data) == expectedSHA256 else {
      try? fileManager.removeItem(at: target)
      throw AgentDesktopArtifactStoreError.integrity("Artifact integrity check failed")
    }
    try cipher.write(data, to: target, purpose: artifactPurpose(artifactId))
  }

  private func expectedChunkSize(total: Int64, index: Int) -> Int {
    Int(min(Int64(256 * 1_024), total - Int64(index * 256 * 1_024)))
  }

  private func chunkPurpose(artifactId: String, index: Int) -> String {
    "desktop-artifact-chunk:\(artifactId):\(index)"
  }

  private func artifactPurpose(_ artifactId: String) -> String {
    "desktop-artifact:\(artifactId)"
  }

  private func existingRecord(artifactURI: String) throws -> AgentDesktopArtifactRecord? {
    let url = try recordURL(artifactURI: artifactURI)
    guard fileManager.fileExists(atPath: url.path) else {
      return nil
    }
    return try JSONDecoder().decode(AgentDesktopArtifactRecord.self, from: Data(contentsOf: url))
  }

  private func writeRecord(_ record: AgentDesktopArtifactRecord, artifactURI: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(record)
    try writeAtomic(data, to: try recordURL(artifactURI: artifactURI))
  }

  private func recordURL(artifactURI: String) throws -> URL {
    try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    return metadataDirectory.appendingPathComponent("\(sha256(Data(artifactURI.utf8))).json", isDirectory: false)
  }

  private func artifactFile(record: AgentDesktopArtifactRecord) throws -> URL? {
    let relative = record.relativeFile.replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let parts = relative.split(separator: "/").map(String.init)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      return nil
    }
    let root = rootURL.standardizedFileURL
    let candidate = parts.reduce(root) { partial, segment in
      partial.appendingPathComponent(segment, isDirectory: false)
    }.standardizedFileURL
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
      return nil
    }
    return candidate
  }

  private func writeAtomic(_ data: Data, to url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic])
  }

  private func stableJSONData(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact manifest is not valid JSON")
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func relativePath(from base: URL, to child: URL) throws -> String {
    let basePath = base.standardizedFileURL.path
    let childPath = child.standardizedFileURL.path
    guard childPath.hasPrefix(basePath + "/") else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact path escaped private storage")
    }
    return String(childPath.dropFirst(basePath.count + 1)).replacingOccurrences(of: "\\", with: "/")
  }

  private func locked<T>(_ work: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    return try work()
  }

  private func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private var incomingDirectory: URL {
    rootURL.appendingPathComponent("incoming", isDirectory: true)
  }

  private var filesDirectory: URL {
    rootURL.appendingPathComponent("files", isDirectory: true)
  }

  private var metadataDirectory: URL {
    rootURL.appendingPathComponent("metadata", isDirectory: true)
  }
}

private struct AgentDesktopArtifactChunkPayload {
  var artifactId: String
  var artifactURI: String
  var taskId: String
  var name: String
  var mimeType: String
  var sizeBytes: Int64
  var sha256: String
  var originalSizeBytes: Int64
  var originalSHA256: String
  var chunkIndex: Int
  var chunkCount: Int
  var chunkSizeBytes: Int64
  var chunkSHA256: String
  var chunkData: Data

  init(_ payload: [String: Any]) throws {
    guard Self.string(payload["type"]) == "artifact_chunk" else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Unsupported artifact payload")
    }
    artifactId = Self.string(payload["artifact_id"]).lowercased()
    artifactURI = Self.string(payload["artifact_uri"])
    taskId = Self.string(payload["task_id"])
    name = AgentDesktopArtifactStore.safeFileName(Self.string(payload["name"]))
    mimeType = Self.string(payload["mime_type"]).ifBlank("application/octet-stream")
    sizeBytes = Self.int64(payload["size_bytes"])
    sha256 = Self.string(payload["sha256"]).lowercased()
    originalSizeBytes = Self.int64(payload["original_size_bytes"], fallback: sizeBytes)
    originalSHA256 = Self.string(payload["original_sha256"]).lowercased().ifBlank(sha256)
    chunkIndex = Self.int(payload["chunk_index"])
    chunkCount = Self.int(payload["chunk_count"])
    chunkSizeBytes = Self.int64(payload["chunk_size_bytes"])
    chunkSHA256 = Self.string(payload["chunk_sha256"]).lowercased()
    guard Self.hex64(artifactId),
      Self.hex64(sha256),
      Self.hex64(originalSHA256),
      Self.hex64(chunkSHA256) else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact digests must be lowercase SHA-256 hex")
    }
    guard AgentDesktopArtifactStore.isSignalASIArtifactURI(artifactURI) else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact URI must use signalasi-artifact")
    }
    guard sizeBytes >= 1 && sizeBytes <= Self.maximumArtifactBytes else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact size is outside the safety limit")
    }
    guard originalSizeBytes >= sizeBytes else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Original artifact size cannot be smaller than delivered size")
    }
    guard chunkCount >= 1 && chunkCount <= Self.maximumChunkCount && chunkIndex >= 0 && chunkIndex < chunkCount else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact chunk index is outside the safety limit")
    }
    guard chunkSizeBytes >= 1 && chunkSizeBytes <= Self.maximumChunkBytes else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact chunk size is outside the safety limit")
    }
    guard (sizeBytes + Self.maximumChunkBytes - 1) / Self.maximumChunkBytes == Int64(chunkCount) else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact chunk count does not match the delivered size")
    }
    guard let data = Data(base64Encoded: Self.string(payload["data_b64"]), options: [.ignoreUnknownCharacters]) else {
      throw AgentDesktopArtifactStoreError.invalidPayload("Artifact chunk data is not base64")
    }
    guard Int64(data.count) == chunkSizeBytes else {
      throw AgentDesktopArtifactStoreError.integrity("Artifact chunk size does not match metadata")
    }
    let chunkDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard chunkDigest == chunkSHA256 else {
      throw AgentDesktopArtifactStoreError.integrity("Artifact chunk digest does not match metadata")
    }
    chunkData = data
  }

  var manifest: [String: Any] {
    [
      "artifact_id": artifactId,
      "artifact_uri": artifactURI,
      "task_id": taskId,
      "name": name,
      "mime_type": mimeType,
      "size_bytes": sizeBytes,
      "sha256": sha256,
      "original_size_bytes": originalSizeBytes,
      "original_sha256": originalSHA256,
      "chunk_count": chunkCount
    ]
  }

  private static func string(_ value: Any?) -> String {
    switch value {
    case let value as String:
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    case let value as NSNumber:
      return value.stringValue
    case let value as AgentMcpJSONValue:
      return value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    default:
      return ""
    }
  }

  private static func int(_ value: Any?) -> Int {
    Int(int64(value))
  }

  private static func int64(_ value: Any?, fallback: Int64 = 0) -> Int64 {
    switch value {
    case let value as Int64:
      return value
    case let value as Int:
      return Int64(value)
    case let value as Double:
      return Int64(value)
    case let value as NSNumber:
      return value.int64Value
    case let value as String:
      return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    case let value as AgentMcpJSONValue:
      return value.intValue ?? fallback
    default:
      return fallback
    }
  }

  private static func hex64(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }

  private static let maximumArtifactBytes: Int64 = 64 * 1_024 * 1_024
  private static let maximumChunkBytes: Int64 = 256 * 1_024
  private static let maximumChunkCount = 256
}

private struct AgentDesktopArtifactRecord: Codable, Equatable {
  var artifactId: String
  var artifactURI: String
  var taskId: String
  var name: String
  var mimeType: String
  var sizeBytes: Int64
  var sha256: String
  var originalSizeBytes: Int64
  var originalSHA256: String
  var chunkCount: Int
  var relativeFile: String
  var storedAtMillis: Int64
  var savedToDownloads: Bool
  var savedURI: String
  var savedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case artifactId = "artifact_id"
    case artifactURI = "artifact_uri"
    case taskId = "task_id"
    case name
    case mimeType = "mime_type"
    case sizeBytes = "size_bytes"
    case sha256
    case originalSizeBytes = "original_size_bytes"
    case originalSHA256 = "original_sha256"
    case chunkCount = "chunk_count"
    case relativeFile = "relative_file"
    case storedAtMillis = "stored_at"
    case savedToDownloads = "saved_to_downloads"
    case savedURI = "saved_uri"
    case savedAtMillis = "saved_at"
  }

  init(
    artifactId: String,
    artifactURI: String,
    taskId: String,
    name: String,
    mimeType: String,
    sizeBytes: Int64,
    sha256: String,
    originalSizeBytes: Int64,
    originalSHA256: String,
    chunkCount: Int,
    relativeFile: String,
    storedAtMillis: Int64,
    savedToDownloads: Bool,
    savedURI: String,
    savedAtMillis: Int64
  ) {
    self.artifactId = artifactId
    self.artifactURI = artifactURI
    self.taskId = taskId
    self.name = name
    self.mimeType = mimeType
    self.sizeBytes = sizeBytes
    self.sha256 = sha256
    self.originalSizeBytes = originalSizeBytes
    self.originalSHA256 = originalSHA256
    self.chunkCount = chunkCount
    self.relativeFile = relativeFile
    self.storedAtMillis = storedAtMillis
    self.savedToDownloads = savedToDownloads
    self.savedURI = savedURI
    self.savedAtMillis = savedAtMillis
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      artifactId: try container.decodeIfPresent(String.self, forKey: .artifactId) ?? "",
      artifactURI: try container.decodeIfPresent(String.self, forKey: .artifactURI) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "SignalASI-artifact",
      mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream",
      sizeBytes: try container.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0,
      sha256: try container.decodeIfPresent(String.self, forKey: .sha256) ?? "",
      originalSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .originalSizeBytes) ?? 0,
      originalSHA256: try container.decodeIfPresent(String.self, forKey: .originalSHA256) ?? "",
      chunkCount: try container.decodeIfPresent(Int.self, forKey: .chunkCount) ?? 0,
      relativeFile: try container.decodeIfPresent(String.self, forKey: .relativeFile) ?? "",
      storedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .storedAtMillis) ?? 0,
      savedToDownloads: try container.decodeIfPresent(Bool.self, forKey: .savedToDownloads) ?? false,
      savedURI: try container.decodeIfPresent(String.self, forKey: .savedURI) ?? "",
      savedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .savedAtMillis) ?? 0
    )
  }
}
