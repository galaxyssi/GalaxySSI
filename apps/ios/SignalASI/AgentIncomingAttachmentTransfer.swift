import CryptoKit
import Foundation

final class AgentIncomingAttachmentTransferStore {
  private static let manifestName = "manifest.json"
  private static let chunksName = "chunks"
  private static let dataName = "data.bin"
  private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
  private static let digestPattern = #"^[a-f0-9]{64}$"#

  private let rootURL: URL
  private let fileManager: FileManager
  private let now: () -> Date
  private let lock = NSLock()

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init
  ) {
    self.fileManager = fileManager
    self.now = now
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    self.rootURL = (rootURL ?? baseURL.appendingPathComponent(
      "peer-incoming-attachments-v1",
      isDirectory: true
    )).standardizedFileURL
  }

  func ingest(
    payload: [String: Any],
    sourceId: String,
    localSignalASIId: String,
    routes: SignalASILinkRoutes
  ) -> [String: Any]? {
    locked {
      try? pruneLocked()
      switch payload.string("type") {
      case "input_attachment_manifest":
        return ingestManifest(
          payload,
          sourceId: sourceId,
          localSignalASIId: localSignalASIId,
          routes: routes
        )
      case "input_attachment_chunk":
        return ingestChunk(
          payload,
          sourceId: sourceId,
          localSignalASIId: localSignalASIId,
          routes: routes
        )
      default:
        return nil
      }
    }
  }

  func resolveMessageAttachments(
    sourceId: String,
    payload: [String: Any]
  ) -> [[String: Any]]? {
    locked {
      guard let descriptors = payload["attachments"] as? [[String: Any]] else { return [] }
      var resolvedAttachments: [[String: Any]] = []
      for descriptor in descriptors {
        let transferId = descriptor.string("transfer_id").lowercased()
        guard let stored = storedAttachment(transferId: transferId, sourceId: sourceId),
              descriptor.string("sha256").lowercased() == stored.sha256,
              descriptor.int64("size", fallbackKey: "size_bytes") == stored.sizeBytes else {
          return nil
        }
        var resolved = descriptor
        resolved["name"] = stored.name
        resolved["mime_type"] = stored.mimeType
        resolved["size_bytes"] = stored.sizeBytes
        resolved["uri"] = stored.dataURL.absoluteString
        resolved["artifact_uri"] = stored.dataURL.absoluteString
        if stored.mimeType.hasPrefix("audio/") {
          let duration = payload.int64("duration_ms")
          if duration > 0 { resolved["duration_ms"] = duration }
        }
        resolvedAttachments.append(resolved)
      }
      return resolvedAttachments
    }
  }

  func deleteLocalCopies(for messages: [ChatMessage]) {
    let blocks = messages.flatMap { AgentRichContentCodec.decode($0.richOutputJson) }
    deleteLocalCopies(for: blocks)
  }

  func deleteLocalCopies(for blocks: [AgentRichBlock]) {
    locked {
      let privateRoots = localAttachmentRoots()
      for block in blocks where block.isArtifactBlock {
        if let transferId = block.metadata["transfer_id"]?.lowercased(), isDigest(transferId) {
          try? fileManager.removeItem(at: transferDirectory(transferId))
        }
        let candidates = [block.uri, block.metadata["artifact_source_uri"] ?? ""]
        for value in candidates where !value.isEmpty {
          guard let url = URL(string: value), url.isFileURL,
                privateRoots.contains(where: { contains(url, root: $0) }) else { continue }
          try? fileManager.removeItem(at: url)
        }
      }
    }
  }

  private func ingestManifest(
    _ payload: [String: Any],
    sourceId: String,
    localSignalASIId: String,
    routes: SignalASILinkRoutes
  ) -> [String: Any]? {
    guard let manifest = normalizedManifest(
      payload,
      sourceId: sourceId,
      localSignalASIId: localSignalASIId,
      routes: routes
    ) else { return nil }
    let transferId = manifest.string("transfer_id")
    let directory = transferDirectory(transferId)
    if let existing = readManifest(directory), !sameTransfer(existing, manifest) {
      try? fileManager.removeItem(at: directory)
    }
    try? fileManager.createDirectory(at: chunksDirectory(directory), withIntermediateDirectories: true)
    guard writeJSON(manifest, to: directory.appendingPathComponent(Self.manifestName)) else { return nil }
    if storedAttachment(transferId: transferId, sourceId: sourceId) != nil {
      return receipt(manifest, status: "stored", localSignalASIId: localSignalASIId)
    }
    guard payload.bool("resume") else { return nil }
    var value = receipt(manifest, status: "missing", localSignalASIId: localSignalASIId)
    value["missing_ranges"] = AgentAttachmentTransferProtocol.missingRanges(
      missingChunkIndices(directory: directory, manifest: manifest)
    )
    return value
  }

  private func ingestChunk(
    _ payload: [String: Any],
    sourceId: String,
    localSignalASIId: String,
    routes: SignalASILinkRoutes
  ) -> [String: Any]? {
    let transferId = payload.string("transfer_id").lowercased()
    guard isDigest(transferId) else { return nil }
    let directory = transferDirectory(transferId)
    guard let manifest = readManifest(directory),
          manifestMatches(
            manifest,
            payload: payload,
            sourceId: sourceId,
            localSignalASIId: localSignalASIId,
            routes: routes
          ) else { return nil }
    let chunkCount = manifest.int("chunk_count")
    let index = payload.int("chunk_index")
    guard (0..<chunkCount).contains(index),
          let bytes = Data(base64Encoded: payload.string("data_b64")) else { return nil }
    let expectedSize = expectedChunkSize(size: manifest.int64("size_bytes"), index: index)
    guard bytes.count == expectedSize,
          payload.int("chunk_size") == expectedSize,
          payload.string("chunk_sha256").lowercased() == sha256(bytes) else { return nil }
    let destination = chunkURL(directory: directory, index: index)
    try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard (try? bytes.write(to: destination, options: .atomic)) != nil else { return nil }
    if !missingChunkIndices(directory: directory, manifest: manifest).isEmpty { return nil }

    let assembling = directory.appendingPathComponent(".assembling")
    _ = fileManager.createFile(atPath: assembling.path, contents: nil)
    guard let output = try? FileHandle(forWritingTo: assembling) else { return nil }
    for chunkIndex in 0..<chunkCount {
      guard let data = try? Data(contentsOf: chunkURL(directory: directory, index: chunkIndex)) else {
        try? output.close()
        try? fileManager.removeItem(at: assembling)
        return nil
      }
      do {
        try output.write(contentsOf: data)
      } catch {
        try? output.close()
        try? fileManager.removeItem(at: assembling)
        return nil
      }
    }
    try? output.synchronize()
    try? output.close()
    guard fileSize(assembling) == manifest.int64("size_bytes"),
          sha256(assembling) == manifest.string("sha256") else {
      try? fileManager.removeItem(at: assembling)
      try? fileManager.removeItem(at: chunksDirectory(directory))
      try? fileManager.createDirectory(at: chunksDirectory(directory), withIntermediateDirectories: true)
      var value = receipt(manifest, status: "missing", localSignalASIId: localSignalASIId)
      value["missing_ranges"] = AgentAttachmentTransferProtocol.missingRanges(Array(0..<chunkCount))
      return value
    }
    let dataURL = directory.appendingPathComponent(Self.dataName)
    try? fileManager.removeItem(at: dataURL)
    do {
      try fileManager.moveItem(at: assembling, to: dataURL)
      try? fileManager.removeItem(at: chunksDirectory(directory))
      return receipt(manifest, status: "stored", localSignalASIId: localSignalASIId)
    } catch {
      try? fileManager.removeItem(at: assembling)
      return nil
    }
  }

  private func normalizedManifest(
    _ payload: [String: Any],
    sourceId: String,
    localSignalASIId: String,
    routes: SignalASILinkRoutes
  ) -> [String: Any]? {
    let transferId = payload.string("transfer_id").lowercased()
    let digest = payload.string("sha256").lowercased()
    let size = payload.int64("size_bytes")
    let chunkCount = payload.int("chunk_count")
    let expectedChunks = Int(
      (size + Int64(AgentOutboundAttachmentTransferStore.chunkBytes) - 1) /
        Int64(AgentOutboundAttachmentTransferStore.chunkBytes)
    )
    guard isDigest(transferId), isDigest(digest),
          (1...AgentOutboundAttachmentTransferStore.maxAttachmentBytes).contains(size),
          chunkCount == expectedChunks,
          (1...AgentOutboundAttachmentTransferStore.maxChunks).contains(chunkCount),
          payload.string("client_route_id") == routes.clientRouteId,
          payload.string("contact_id") == localSignalASIId,
          !sourceId.isEmpty else { return nil }
    var manifest = payload
    manifest["transfer_id"] = transferId
    manifest["sha256"] = digest
    manifest["source_id"] = sourceId
    manifest["received_at"] = Int64(now().timeIntervalSince1970 * 1_000)
    manifest["name"] = safeName(payload.string("name").ifBlank("attachment"))
    manifest["mime_type"] = payload.string("mime_type").ifBlank("application/octet-stream")
    return manifest
  }

  private func manifestMatches(
    _ manifest: [String: Any],
    payload: [String: Any],
    sourceId: String,
    localSignalASIId: String,
    routes: SignalASILinkRoutes
  ) -> Bool {
    manifest.string("source_id") == sourceId &&
      manifest.string("contact_id") == localSignalASIId &&
      manifest.string("client_route_id") == routes.clientRouteId &&
      manifest.string("transfer_id") == payload.string("transfer_id").lowercased() &&
      manifest.string("sha256") == payload.string("sha256").lowercased() &&
      manifest.int64("size_bytes") == payload.int64("size_bytes") &&
      manifest.int("chunk_count") == payload.int("chunk_count")
  }

  private func sameTransfer(_ first: [String: Any], _ second: [String: Any]) -> Bool {
    first.string("source_id") == second.string("source_id") &&
      first.string("sha256") == second.string("sha256") &&
      first.int64("size_bytes") == second.int64("size_bytes") &&
      first.int("chunk_count") == second.int("chunk_count")
  }

  private func receipt(
    _ manifest: [String: Any],
    status: String,
    localSignalASIId: String
  ) -> [String: Any] {
    [
      "type": "input_attachment_receipt",
      "status": status,
      "transfer_id": manifest.string("transfer_id"),
      "sha256": manifest.string("sha256"),
      "client_route_id": manifest.string("client_route_id"),
      "conversation_id": manifest.string("conversation_id"),
      "task_id": manifest.string("task_id"),
      "turn_id": manifest.string("turn_id"),
      "contact_id": localSignalASIId,
      "source_message_id": manifest.string("client_message_id"),
      "peer_chat": true,
      "time": Int64(now().timeIntervalSince1970 * 1_000)
    ]
  }

  private struct StoredAttachment {
    var name: String
    var mimeType: String
    var sizeBytes: Int64
    var sha256: String
    var dataURL: URL
  }

  private func storedAttachment(transferId: String, sourceId: String) -> StoredAttachment? {
    guard isDigest(transferId) else { return nil }
    let directory = transferDirectory(transferId)
    guard let manifest = readManifest(directory), manifest.string("source_id") == sourceId else { return nil }
    let dataURL = directory.appendingPathComponent(Self.dataName)
    guard fileSize(dataURL) == manifest.int64("size_bytes"),
          sha256(dataURL) == manifest.string("sha256") else { return nil }
    return StoredAttachment(
      name: manifest.string("name").ifBlank("attachment"),
      mimeType: manifest.string("mime_type").ifBlank("application/octet-stream"),
      sizeBytes: fileSize(dataURL),
      sha256: manifest.string("sha256"),
      dataURL: dataURL
    )
  }

  private func missingChunkIndices(directory: URL, manifest: [String: Any]) -> [Int] {
    (0..<manifest.int("chunk_count")).filter { index in
      fileSize(chunkURL(directory: directory, index: index)) !=
        Int64(expectedChunkSize(size: manifest.int64("size_bytes"), index: index))
    }
  }

  private func expectedChunkSize(size: Int64, index: Int) -> Int {
    Int(min(
      Int64(AgentOutboundAttachmentTransferStore.chunkBytes),
      size - Int64(index * AgentOutboundAttachmentTransferStore.chunkBytes)
    ))
  }

  private func readManifest(_ directory: URL) -> [String: Any]? {
    let url = directory.appendingPathComponent(Self.manifestName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private func writeJSON(_ object: [String: Any], to url: URL) -> Bool {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return false }
    return (try? data.write(to: url, options: .atomic)) != nil
  }

  private func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }

  private func sha256(_ url: URL) -> String {
    guard let input = InputStream(url: url) else { return "" }
    input.open()
    defer { input.close() }
    var hasher = SHA256()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 1024)
    defer { buffer.deallocate() }
    while input.hasBytesAvailable {
      let count = input.read(buffer, maxLength: 64 * 1024)
      if count < 0 { return "" }
      if count == 0 { break }
      hasher.update(data: Data(bytes: buffer, count: count))
    }
    return Data(hasher.finalize()).hexString()
  }

  private func safeName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
    return value.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(160)
      .description
      .ifBlank("attachment")
  }

  private func pruneLocked() throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let directories = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )
    for directory in directories where isDigest(directory.lastPathComponent) {
      let manifest = readManifest(directory)
      let receivedAt = manifest?.int64("received_at") ?? 0
      let date = receivedAt > 0
        ? Date(timeIntervalSince1970: TimeInterval(receivedAt) / 1_000)
        : ((try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
      if now().timeIntervalSince(date) > Self.maximumAge {
        try? fileManager.removeItem(at: directory)
      }
    }
  }

  private func transferDirectory(_ transferId: String) -> URL {
    rootURL.appendingPathComponent(transferId, isDirectory: true)
  }

  private func localAttachmentRoots() -> [URL] {
    var roots = [rootURL]
    for applicationSupport in fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ) {
      roots.append(applicationSupport.appendingPathComponent(
        AgentRichContentMaterializer.defaultDirectoryName,
        isDirectory: true
      ))
      roots.append(applicationSupport.appendingPathComponent(
        "peer-message-attachments-v1",
        isDirectory: true
      ))
    }
    for caches in fileManager.urls(for: .cachesDirectory, in: .userDomainMask) {
      roots.append(caches.appendingPathComponent("peer-voice-drafts", isDirectory: true))
      roots.append(caches.appendingPathComponent("peer-voice-recordings", isDirectory: true))
    }
    return roots.map(canonicalURL)
  }

  private func contains(_ candidate: URL, root: URL) -> Bool {
    let path = canonicalURL(candidate).path
    let rootPath = canonicalURL(root).path
    return path == rootPath || path.hasPrefix(rootPath + "/")
  }

  private func canonicalURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private func chunksDirectory(_ directory: URL) -> URL {
    directory.appendingPathComponent(Self.chunksName, isDirectory: true)
  }

  private func chunkURL(directory: URL, index: Int) -> URL {
    chunksDirectory(directory).appendingPathComponent(String(format: "chunk-%06d.bin", index))
  }

  private func fileSize(_ url: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else { return -1 }
    return size.int64Value
  }

  private func isDigest(_ value: String) -> Bool {
    value.range(of: Self.digestPattern, options: .regularExpression) != nil
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

private extension Dictionary where Key == String, Value == Any {
  func int64(_ key: String, fallbackKey: String = "") -> Int64 {
    if let value = self[key] as? NSNumber { return value.int64Value }
    if let value = self[key] as? String, let parsed = Int64(value) { return parsed }
    guard !fallbackKey.isEmpty else { return 0 }
    return int64(fallbackKey)
  }

  func int(_ key: String) -> Int {
    Int(int64(key))
  }

  func bool(_ key: String) -> Bool {
    if let value = self[key] as? Bool { return value }
    if let value = self[key] as? NSNumber { return value.boolValue }
    return (self[key] as? String)?.lowercased() == "true"
  }
}
