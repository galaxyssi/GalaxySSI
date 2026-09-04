import CryptoKit
import Foundation

struct AgentAttachmentTransferScope: Codable, Equatable {
  var contactId: String
  var desktopId: String
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var clientMessageId: String?

  init(
    contactId: String,
    desktopId: String,
    clientRouteId: String,
    conversationId: String,
    taskId: String,
    turnId: String,
    clientMessageId: String? = nil
  ) throws {
    self.contactId = try Self.requireBounded(contactId, field: "contact_id")
    self.desktopId = try Self.requireBounded(desktopId, field: "desktop_id")
    guard GalaxySSILinkProtocol.validRouteId(clientRouteId) else {
      throw AgentAttachmentTransferError.invalidScope
    }
    self.clientRouteId = clientRouteId
    self.conversationId = try Self.requireBounded(conversationId, field: "conversation_id")
    self.taskId = try Self.requireBounded(taskId, field: "task_id")
    self.turnId = try Self.requireBounded(turnId, field: "turn_id")
    let cleanClientMessageId = clientMessageId?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    if let cleanClientMessageId, cleanClientMessageId.count > 256 {
      throw AgentAttachmentTransferError.invalidScope
    }
    self.clientMessageId = cleanClientMessageId
  }

  enum CodingKeys: String, CodingKey {
    case contactId = "contact_id"
    case desktopId = "desktop_id"
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case turnId = "turn_id"
    case clientMessageId = "client_message_id"
  }

  private static func requireBounded(_ value: String, field: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 256 else {
      throw AgentAttachmentTransferError.invalidScope
    }
    return trimmed
  }
}

struct AgentPreparedOutboundAttachment: Equatable {
  var transferId: String
  var attachmentId: String
  var ordinal: Int
  var name: String
  var originalName: String
  var mimeType: String
  var sizeBytes: Int64
  var originalSizeBytes: Int64
  var sha256: String
  var chunkCount: Int
  var transportProfile: String
  var requiresValidatedNetwork: Bool
  var scope: AgentAttachmentTransferScope
  fileprivate var chunkDirectoryURL: URL
  fileprivate var cipher: GalaxySSIAttachmentAtRestCipher

  func descriptor() -> [String: Any] {
    [
      "id": attachmentId,
      "transfer_id": transferId,
      "name": name,
      "original_name": originalName,
      "mime_type": mimeType,
      "size": sizeBytes,
      "transport_size": sizeBytes,
      "original_size": originalSizeBytes,
      "sha256": sha256,
      "chunk_count": chunkCount,
      "chunk_size_bytes": AgentOutboundAttachmentTransferStore.chunkBytes,
      "transport_profile": transportProfile,
      "transport_status": "chunked"
    ]
  }

  func manifestPayload(resume: Bool, nowMillis: Int64 = AgentOutboundAttachmentTransferStore.nowMillis()) -> [String: Any] {
    var payload = commonPayload(type: "input_attachment_manifest", nowMillis: nowMillis)
    payload["resume"] = resume
    return payload
  }

  func chunkPayload(index: Int, nowMillis: Int64 = AgentOutboundAttachmentTransferStore.nowMillis()) throws -> [String: Any] {
    guard (0..<chunkCount).contains(index) else {
      throw AgentAttachmentTransferError.invalidChunkRange
    }
    let start = index * AgentOutboundAttachmentTransferStore.chunkBytes
    let expected = min(
      AgentOutboundAttachmentTransferStore.chunkBytes,
      Int(sizeBytes) - start
    )
    guard expected > 0 else {
      throw AgentAttachmentTransferError.invalidChunkRange
    }
    let chunk = try cipher.read(
      from: AgentOutboundAttachmentTransferStore.chunkURL(
        directory: chunkDirectoryURL,
        index: index
      ),
      purpose: AgentOutboundAttachmentTransferStore.chunkPurpose(
        transferId: transferId,
        index: index
      )
    )
    guard chunk.count == expected else {
      throw AgentAttachmentTransferError.contentUnavailable
    }
    var payload = commonPayload(type: "input_attachment_chunk", nowMillis: nowMillis)
    payload["chunk_index"] = index
    payload["chunk_size"] = chunk.count
    payload["chunk_sha256"] = AgentAttachmentTransferProtocol.sha256(chunk)
    payload["data_b64"] = chunk.base64EncodedString()
    return payload
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.transferId == rhs.transferId &&
      lhs.attachmentId == rhs.attachmentId &&
      lhs.ordinal == rhs.ordinal &&
      lhs.name == rhs.name &&
      lhs.originalName == rhs.originalName &&
      lhs.mimeType == rhs.mimeType &&
      lhs.sizeBytes == rhs.sizeBytes &&
      lhs.originalSizeBytes == rhs.originalSizeBytes &&
      lhs.sha256 == rhs.sha256 &&
      lhs.chunkCount == rhs.chunkCount &&
      lhs.transportProfile == rhs.transportProfile &&
      lhs.requiresValidatedNetwork == rhs.requiresValidatedNetwork &&
      lhs.scope == rhs.scope &&
      lhs.chunkDirectoryURL == rhs.chunkDirectoryURL
  }

  private func commonPayload(type: String, nowMillis: Int64) -> [String: Any] {
    var payload: [String: Any] = [
      "type": type,
      "transfer_id": transferId,
      "attachment_id": attachmentId,
      "attachment_ordinal": ordinal,
      "name": name,
      "original_name": originalName,
      "mime_type": mimeType,
      "size_bytes": sizeBytes,
      "original_size_bytes": originalSizeBytes,
      "sha256": sha256,
      "chunk_count": chunkCount,
      "chunk_size_bytes": AgentOutboundAttachmentTransferStore.chunkBytes,
      "transport_profile": transportProfile,
      "contact_id": scope.contactId,
      "desktop_id": scope.desktopId,
      "client_route_id": scope.clientRouteId,
      "conversation_id": scope.conversationId,
      "task_id": scope.taskId,
      "turn_id": scope.turnId,
      "time": nowMillis
    ]
    if let clientMessageId = scope.clientMessageId {
      payload["client_message_id"] = clientMessageId
    }
    if requiresValidatedNetwork {
      payload["defer_media_upload"] = true
    }
    return payload
  }
}

enum AgentAttachmentTransferError: LocalizedError, Equatable {
  case invalidScope
  case tooManyAttachments
  case attachmentTooLarge
  case emptyAttachment
  case contentUnavailable
  case storageUnavailable
  case commitFailed
  case invalidChunkRange

  var errorDescription: String? {
    switch self {
    case .invalidScope:
      return "Attachment transfer scope is invalid."
    case .tooManyAttachments:
      return "Too many Agent attachments."
    case .attachmentTooLarge:
      return "Agent attachment exceeds the transfer limit."
    case .emptyAttachment:
      return "Agent attachment is empty."
    case .contentUnavailable:
      return "Attachment content is unavailable."
    case .storageUnavailable:
      return "Attachment transfer staging is unavailable."
    case .commitFailed:
      return "Attachment transfer data could not be committed."
    case .invalidChunkRange:
      return "Attachment chunk range is invalid."
    }
  }
}

enum AgentAttachmentTransferProtocol {
  static func transferId(
    scope: AgentAttachmentTransferScope,
    attachmentId: String,
    sha256: String
  ) throws -> String {
    let cleanAttachmentId = attachmentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let digest = sha256.lowercased()
    guard !cleanAttachmentId.isEmpty,
          cleanAttachmentId.count <= 256,
          digest.range(of: sha256Pattern, options: .regularExpression) != nil else {
      throw AgentAttachmentTransferError.contentUnavailable
    }
    let canonical = [
      scope.clientRouteId,
      scope.conversationId,
      scope.taskId,
      scope.turnId,
      cleanAttachmentId,
      digest
    ].joined(separator: "\u{0000}")
    return Self.sha256(Data(canonical.utf8))
  }

  static func missingRanges(_ indices: [Int]) -> [[Int]] {
    let ordered = Array(Set(indices.filter { $0 >= 0 })).sorted()
    var ranges: [[Int]] = []
    var start: Int?
    var previous: Int?
    for value in ordered {
      if start == nil {
        start = value
        previous = value
      } else if let last = previous, value == last + 1 {
        previous = value
      } else if let first = start, let last = previous {
        ranges.append([first, last])
        start = value
        previous = value
      }
    }
    if let first = start, let last = previous {
      ranges.append([first, last])
    }
    return ranges
  }

  static func expandMissingRanges(_ ranges: Any?, chunkCount: Int) throws -> [Int] {
    guard (1...AgentOutboundAttachmentTransferStore.maxChunks).contains(chunkCount) else {
      throw AgentAttachmentTransferError.invalidChunkRange
    }
    guard let rawRanges = ranges as? [Any] else {
      return []
    }
    var result: [Int] = []
    for rawRange in rawRanges {
      let pair = rawRange as? [Any] ?? []
      guard pair.count == 2,
            let start = int(pair[0]),
            let end = int(pair[1]),
            start >= 0,
            start < chunkCount,
            end >= start,
            end < chunkCount else {
        throw AgentAttachmentTransferError.invalidChunkRange
      }
      result.append(contentsOf: start...end)
    }
    return Array(Set(result)).sorted()
  }

  static func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }

  private static func int(_ value: Any) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    return nil
  }

  private static let sha256Pattern = #"^[a-f0-9]{64}$"#
}

final class AgentOutboundAttachmentTransferStore {
  struct StoredAcknowledgement: Equatable {
    var transferId: String
    var matchedMessages: Int
    var releasedMessages: Int
  }

  static let chunkBytes = 256 * 1024
  static let maxAttachmentBytes: Int64 = 64 * 1024 * 1024
  static let maxChunks = Int(maxAttachmentBytes / Int64(chunkBytes))

  private static let maxAttachmentsPerTurn = 10
  private static let maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60
  private static let manifestFile = "manifest.json"
  private static let chunksDirectoryName = "chunks"
  private static let sha256Pattern = #"^[a-f0-9]{64}$"#

  private let rootURL: URL
  private let fileManager: FileManager
  private let now: () -> Date
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSLock()

  init(
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared
  ) {
    self.fileManager = fileManager
    self.now = now
    self.cipher = cipher
    self.rootURL = (rootURL ?? Self.defaultRootURL(fileManager: fileManager)).standardizedFileURL
  }

  static func defaultRootURL(fileManager: FileManager = .default) -> URL {
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return baseURL.appendingPathComponent("agent-link-outgoing-attachments-v2", isDirectory: true)
  }

  static func nowMillis(_ date: Date = Date()) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  func prepare(
    scope: AgentAttachmentTransferScope,
    attachments: [GalaxySSIDraftAttachment],
    mediaProfile: AgentMediaDeliveryProfile,
    preserveOriginalBytes: Bool = false
  ) throws -> [AgentPreparedOutboundAttachment] {
    try locked {
      try pruneLocked()
      guard attachments.count <= Self.maxAttachmentsPerTurn else {
        throw AgentAttachmentTransferError.tooManyAttachments
      }
      return try attachments.enumerated().map { ordinal, attachment in
        try prepareOne(
          scope: scope,
          attachment: attachment,
          ordinal: ordinal,
          mediaProfile: mediaProfile,
          preserveOriginalBytes: preserveOriginalBytes
        )
      }
    }
  }

  func pending() -> [AgentPreparedOutboundAttachment] {
    locked {
      try? pruneLocked()
      return transferDirectories()
        .compactMap(readPrepared)
        .sorted { $0.transferId < $1.transferId }
    }
  }

  func find(_ transferId: String) -> AgentPreparedOutboundAttachment? {
    let normalized = transferId.lowercased()
    guard normalized.range(of: Self.sha256Pattern, options: .regularExpression) != nil else {
      return nil
    }
    return locked {
      try? pruneLocked()
      return readPrepared(directory: transferDirectory(normalized))
    }
  }

  @MainActor
  func discard(_ transferIds: some Collection<String>, deliveryStore: GalaxySSILinkDeliveryStore) {
    let normalized = Set(
      transferIds
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { $0.range(of: Self.sha256Pattern, options: .regularExpression) != nil }
    )
    guard !normalized.isEmpty else { return }
    locked {
      normalized.forEach { transferId in
        try? fileManager.removeItem(at: transferDirectory(transferId))
      }
    }
    _ = deliveryStore.discardBlockedByAttachmentTransfers(Array(normalized))
  }

  @discardableResult
  @MainActor
  func discard(desktopId: String, deliveryStore: GalaxySSILinkDeliveryStore) -> Int {
    let cleanDesktopId = desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDesktopId.isEmpty else { return 0 }
    let transferIds = pending()
      .filter { $0.scope.desktopId == cleanDesktopId }
      .map(\.transferId)
    discard(transferIds, deliveryStore: deliveryStore)
    return transferIds.count
  }

  @MainActor
  func acknowledgeStored(payload: [String: Any], deliveryStore: GalaxySSILinkDeliveryStore) -> StoredAcknowledgement? {
    let transferId = payload.string("transfer_id").lowercased()
    guard payload.string("status") == "stored",
          let transfer = find(transferId),
          payload.string("sha256").lowercased() == transfer.sha256,
          payload.string("client_route_id") == transfer.scope.clientRouteId,
          payload.string("conversation_id") == transfer.scope.conversationId,
          payload.string("task_id") == transfer.scope.taskId,
          payload.string("turn_id") == transfer.scope.turnId,
          payload.string("contact_id") == transfer.scope.contactId else {
      return nil
    }
    if let clientMessageId = transfer.scope.clientMessageId,
       payload.string("source_message_id") != clientMessageId {
      return nil
    }
    let release = deliveryStore.releaseAttachmentDependencyResult(transfer.transferId)
    guard release.matchedMessages > 0 else { return nil }
    locked {
      try? fileManager.removeItem(at: transferDirectory(transfer.transferId))
    }
    return StoredAcknowledgement(
      transferId: transfer.transferId,
      matchedMessages: release.matchedMessages,
      releasedMessages: release.releasedMessages
    )
  }

  func prune() -> [String] {
    locked {
      (try? pruneLocked()) ?? []
    }
  }

  private func prepareOne(
    scope: AgentAttachmentTransferScope,
    attachment: GalaxySSIDraftAttachment,
    ordinal: Int,
    mediaProfile: AgentMediaDeliveryProfile,
    preserveOriginalBytes: Bool
  ) throws -> AgentPreparedOutboundAttachment {
    let attachmentId = attachment.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !attachmentId.isEmpty, attachmentId.count <= 256 else {
      throw AgentAttachmentTransferError.contentUnavailable
    }
    guard Int64(attachment.sizeBytes) <= Self.maxAttachmentBytes else {
      throw AgentAttachmentTransferError.attachmentTooLarge
    }
    let preparing = rootURL.appendingPathComponent(".preparing-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: preparing, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: preparing) }

    let preparedPayload = transportPayload(
      for: attachment,
      mediaProfile: mediaProfile,
      preserveOriginalBytes: preserveOriginalBytes
    )
    let data = preparedPayload.data
    let transportSize = Int64(data.count)
    guard transportSize > 0 else {
      throw AgentAttachmentTransferError.emptyAttachment
    }
    guard transportSize <= Self.maxAttachmentBytes else {
      throw AgentAttachmentTransferError.attachmentTooLarge
    }
    let chunkCount = Int((transportSize + Int64(Self.chunkBytes) - 1) / Int64(Self.chunkBytes))
    guard (1...Self.maxChunks).contains(chunkCount) else {
      throw AgentAttachmentTransferError.attachmentTooLarge
    }
    let digest = AgentAttachmentTransferProtocol.sha256(data)
    let transferId = try AgentAttachmentTransferProtocol.transferId(
      scope: scope,
      attachmentId: attachmentId,
      sha256: digest
    )
    let destination = transferDirectory(transferId)
    if let existing = readPrepared(directory: destination) {
      return existing
    }
    try? fileManager.removeItem(at: destination)

    let preparingChunks = preparing.appendingPathComponent(Self.chunksDirectoryName, isDirectory: true)
    do {
      try fileManager.createDirectory(at: preparingChunks, withIntermediateDirectories: true)
      for index in 0..<chunkCount {
        let start = index * Self.chunkBytes
        let end = min(start + Self.chunkBytes, data.count)
        try cipher.write(
          Data(data[start..<end]),
          to: Self.chunkURL(directory: preparingChunks, index: index),
          purpose: Self.chunkPurpose(transferId: transferId, index: index)
        )
      }
      try fileManager.moveItem(at: preparing, to: destination)
    } catch {
      throw AgentAttachmentTransferError.commitFailed
    }
    let manifest = Manifest(
      transferId: transferId,
      attachmentId: attachmentId,
      attachmentOrdinal: ordinal,
      name: preparedPayload.name,
      originalName: attachment.displayName,
      mimeType: preparedPayload.mimeType,
      sizeBytes: transportSize,
      originalSizeBytes: Int64(attachment.sizeBytes),
      sha256: digest,
      chunkCount: chunkCount,
      transportProfile: preserveOriginalBytes ? "peer-original" : mediaProfile.id,
      requiresValidatedNetwork: !preserveOriginalBytes &&
        mediaProfile.deferMediaUpload &&
        attachment.isTransportMedia,
      scope: scope,
      createdAt: Self.nowMillis(now())
    )
    try writeManifest(manifest, directory: destination)
    guard let prepared = readPrepared(directory: destination) else {
      throw AgentAttachmentTransferError.commitFailed
    }
    return prepared
  }

  private func transportPayload(
    for attachment: GalaxySSIDraftAttachment,
    mediaProfile: AgentMediaDeliveryProfile,
    preserveOriginalBytes: Bool
  ) -> (data: Data, mimeType: String, name: String) {
    if attachment.isImage,
       !preserveOriginalBytes,
       let encoded = AgentMediaAttachmentTransportEncoder.inlinePayload(
        for: attachment,
        profile: mediaProfile,
        remainingBytes: mediaProfile.imageTargetBytes
       ) {
      return (
        encoded.data,
        encoded.mimeType,
        GalaxySSIAttachmentPayloadBuilder.sanitizeName(encoded.displayName)
      )
    }
    return (
      attachment.data,
      attachment.mimeType.ifBlank("application/octet-stream"),
      GalaxySSIAttachmentPayloadBuilder.sanitizeName(attachment.displayName)
    )
  }

  private func readPrepared(directory: URL) -> AgentPreparedOutboundAttachment? {
    guard directory.lastPathComponent.range(of: Self.sha256Pattern, options: .regularExpression) != nil,
          let directoryAttributes = try? fileManager.attributesOfItem(atPath: directory.path),
          let directoryType = directoryAttributes[.type] as? FileAttributeType,
          directoryType == .typeDirectory else {
      return nil
    }
    do {
      let manifestURL = directory.appendingPathComponent(Self.manifestFile, isDirectory: false)
      let chunkDirectory = directory.appendingPathComponent(Self.chunksDirectoryName, isDirectory: true)
      let transferId = directory.lastPathComponent
      let manifestData = try cipher.readMigratingPlaintext(
        from: manifestURL,
        purpose: Self.manifestPurpose(transferId)
      )
      let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
      guard manifest.transferId == directory.lastPathComponent,
            manifest.transferId.range(of: Self.sha256Pattern, options: .regularExpression) != nil,
            manifest.sha256.range(of: Self.sha256Pattern, options: .regularExpression) != nil,
            manifest.sizeBytes > 0,
            manifest.sizeBytes <= Self.maxAttachmentBytes,
            manifest.chunkCount == Int((manifest.sizeBytes + Int64(Self.chunkBytes) - 1) / Int64(Self.chunkBytes)),
            (1...Self.maxChunks).contains(manifest.chunkCount),
            (0..<manifest.chunkCount).allSatisfy({ index in
              cipher.plaintextSize(
                of: Self.chunkURL(directory: chunkDirectory, index: index),
                purpose: Self.chunkPurpose(transferId: transferId, index: index)
              ) == Int64(Self.expectedChunkSize(total: manifest.sizeBytes, index: index))
            }),
            try AgentAttachmentTransferProtocol.transferId(
              scope: manifest.scope,
              attachmentId: manifest.attachmentId,
              sha256: manifest.sha256
            ) == manifest.transferId else {
        return nil
      }
      return AgentPreparedOutboundAttachment(
        transferId: manifest.transferId,
        attachmentId: manifest.attachmentId,
        ordinal: manifest.attachmentOrdinal,
        name: manifest.name,
        originalName: manifest.originalName,
        mimeType: manifest.mimeType,
        sizeBytes: manifest.sizeBytes,
        originalSizeBytes: manifest.originalSizeBytes,
        sha256: manifest.sha256,
        chunkCount: manifest.chunkCount,
        transportProfile: manifest.transportProfile,
        requiresValidatedNetwork: manifest.requiresValidatedNetwork,
        scope: manifest.scope,
        chunkDirectoryURL: chunkDirectory,
        cipher: cipher
      )
    } catch {
      return nil
    }
  }

  private func writeManifest(_ manifest: Manifest, directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let target = directory.appendingPathComponent(Self.manifestFile, isDirectory: false)
    try cipher.write(
      encoder.encode(manifest),
      to: target,
      purpose: Self.manifestPurpose(manifest.transferId)
    )
  }

  private func pruneLocked() throws -> [String] {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let cutoff = now().addingTimeInterval(-Self.maxAgeSeconds)
    var discarded: [String] = []
    for entry in try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
      options: []
    ) {
      let name = entry.lastPathComponent
      if name.hasPrefix(".preparing-") {
        try? fileManager.removeItem(at: entry)
        continue
      }
      let entryValues = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
      let created = readCreatedAt(entry) ?? entryValues?.contentModificationDate ?? now()
      if created < cutoff || readPrepared(directory: entry) == nil {
        if name.range(of: Self.sha256Pattern, options: .regularExpression) != nil {
          discarded.append(name)
        }
        try? fileManager.removeItem(at: entry)
      }
    }
    return discarded
  }

  private func readCreatedAt(_ directory: URL) -> Date? {
    let manifestURL = directory.appendingPathComponent(Self.manifestFile, isDirectory: false)
    guard let data = try? cipher.readMigratingPlaintext(
            from: manifestURL,
            purpose: Self.manifestPurpose(directory.lastPathComponent)
          ),
          let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
      return nil
    }
    return Date(timeIntervalSince1970: Double(manifest.createdAt) / 1_000)
  }

  private func transferDirectories() -> [URL] {
    (try? fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []
  }

  private func transferDirectory(_ transferId: String) -> URL {
    rootURL.appendingPathComponent(transferId.lowercased(), isDirectory: true)
  }

  fileprivate static func chunkURL(directory: URL, index: Int) -> URL {
    directory.appendingPathComponent(String(format: "chunk-%06d.bin", index), isDirectory: false)
  }

  fileprivate static func chunkPurpose(transferId: String, index: Int) -> String {
    "outbound-chunk:\(transferId.lowercased()):\(index)"
  }

  private static func expectedChunkSize(total: Int64, index: Int) -> Int {
    Int(min(Int64(chunkBytes), total - Int64(index * chunkBytes)))
  }

  private static func manifestPurpose(_ transferId: String) -> String {
    "outbound-manifest:\(transferId.lowercased())"
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private struct Manifest: Codable {
    var transferId: String
    var attachmentId: String
    var attachmentOrdinal: Int
    var name: String
    var originalName: String
    var mimeType: String
    var sizeBytes: Int64
    var originalSizeBytes: Int64
    var sha256: String
    var chunkCount: Int
    var transportProfile: String
    var requiresValidatedNetwork: Bool
    var scope: AgentAttachmentTransferScope
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
      case transferId = "transfer_id"
      case attachmentId = "attachment_id"
      case attachmentOrdinal = "attachment_ordinal"
      case name
      case originalName = "original_name"
      case mimeType = "mime_type"
      case sizeBytes = "size_bytes"
      case originalSizeBytes = "original_size_bytes"
      case sha256
      case chunkCount = "chunk_count"
      case transportProfile = "transport_profile"
      case requiresValidatedNetwork = "requires_validated_network"
      case scope
      case createdAt = "created_at"
    }
  }
}
