import CryptoKit
import Foundation

struct AgentBlobArtifactTerminalPresentation: Sendable {
  var manifestData: Data
  var state: String
  var errorCode: String
}

enum AgentBlobArtifactContract {
  static let offerType = "artifact_blob_offer"
  static let receiptType = "artifact_blob_receipt"
  static let maximumControlBytes = 32 * 1_024

  private static let textLimits: [String: Int] = [
    "client_route_id": 256, "conversation_id": 256, "task_id": 256,
    "turn_id": 256, "contact_id": 256, "source_message_id": 256,
    "desktop_id": 256, "artifact_id": 64, "artifact_uri": 2_048,
    "name": 255, "relative_path": 2_048, "mime_type": 255,
    "sha256": 64, "original_sha256": 64
  ]
  private static let numberFields = [
    "size_bytes", "original_size_bytes", "execution_generation"
  ]
  private static let scopeFields = [
    "client_route_id", "conversation_id", "task_id", "turn_id",
    "contact_id", "source_message_id", "desktop_id"
  ]

  static func validateOffer(
    _ payload: [String: Any],
    link: ServerLink,
    configuration: AgentBlobRelayConfiguration
  ) throws -> [String: Any] {
    guard payload.string("type") == offerType,
          payload.int("version") == 1,
          payload.int64("transport_revision") > 0,
          let encoded = try? JSONSerialization.data(withJSONObject: payload),
          encoded.count <= maximumControlBytes,
          let rawManifest = payload["manifest"] as? [String: Any],
          let offer = payload["blob_offer"] as? [String: Any] else {
      throw AgentBlobFailure.invalid("invalid_artifact_blob_offer")
    }
    let manifest = try validateManifest(rawManifest)
    guard Set(offer.keys) == ["version", "relay", "private", "read_token"],
          manifest.string("client_route_id") == link.routes.clientRouteId,
          manifest.string("desktop_id") == link.desktopId,
          offer.int("version") == 1,
          offer.string("relay") == configuration.origin,
          AgentBlobProtocol.validHex(offer.string("read_token"), bytes: 32),
          let privatePayload = offer["private"] as? [String: Any] else {
      throw AgentBlobFailure.invalid("artifact_blob_route_mismatch")
    }
    guard Set(privatePayload.keys) == [
      "version", "blob_id", "key", "nonce_prefix", "size", "sha256",
      "binding_sha256", "manifest_sha256"
    ] else {
      throw AgentBlobFailure.invalid("invalid_private_descriptor")
    }
    let descriptor = try descriptor(privatePayload)
    guard descriptor.bindingSHA256 == (try AgentBlobProtocol.bindingHash(binding(manifest))),
          descriptor.size == manifest.int64("size_bytes"),
          descriptor.sha256 == manifest.string("sha256") else {
      throw AgentBlobFailure.invalid("artifact_blob_binding_mismatch")
    }
    return manifest
  }

  static func validateManifest(_ source: [String: Any]) throws -> [String: Any] {
    let fields = Set(textLimits.keys).union(numberFields).union(["peer_chat", "transfer_id"])
    guard Set(source.keys) == fields,
          source["peer_chat"] is Bool,
          source.string("client_route_id").range(
            of: "^[A-Za-z0-9_-]{22}$", options: .regularExpression
          ) != nil else {
      throw AgentBlobFailure.invalid("invalid_artifact_blob_manifest")
    }
    for (key, limit) in textLimits {
      let value = source.string(key)
      guard !value.isEmpty, value.unicodeScalars.count <= limit,
            !value.unicodeScalars.contains(where: { $0.value < 32 }) else {
        throw AgentBlobFailure.invalid("invalid_artifact_blob_manifest")
      }
    }
    let size = source.int64("size_bytes")
    let originalSize = source.int64("original_size_bytes")
    guard (1...AgentBlobProtocol.maximumFileBytes).contains(size),
          originalSize >= size,
          source.int64("execution_generation") > 0,
          AgentBlobProtocol.validHex(source.string("artifact_id"), bytes: 32),
          AgentBlobProtocol.validHex(source.string("sha256"), bytes: 32),
          AgentBlobProtocol.validHex(source.string("original_sha256"), bytes: 32),
          let components = URLComponents(string: source.string("artifact_uri")),
          components.scheme?.lowercased() == "galaxyssi-artifact",
          components.host?.isEmpty == false,
          components.query == nil, components.fragment == nil else {
      throw AgentBlobFailure.invalid("invalid_artifact_blob_manifest")
    }
    var metadata = source
    let transferId = metadata.removeValue(forKey: "transfer_id") as? String ?? ""
    guard AgentBlobProtocol.validHex(transferId, bytes: 32),
          transferId == AgentBlobProtocol.sha256(try AgentBlobProtocol.canonicalJSON(metadata)) else {
      throw AgentBlobFailure.invalid("artifact_blob_manifest_mismatch")
    }
    return source
  }

  static func binding(_ manifest: [String: Any]) -> [String: String] {
    var result = Dictionary(uniqueKeysWithValues: scopeFields.map { ($0, manifest.string($0)) })
    result["artifact_id"] = manifest.string("artifact_id")
    result["transfer_id"] = manifest.string("transfer_id")
    result["execution_generation"] = String(manifest.int64("execution_generation"))
    return result
  }

  static func descriptor(_ source: [String: Any]) throws -> AgentBlobPrivateDescriptor {
    let value = AgentBlobPrivateDescriptor(
      blobId: source.string("blob_id"),
      key: source.string("key"),
      noncePrefix: source.string("nonce_prefix"),
      size: source.int64("size"),
      sha256: source.string("sha256"),
      bindingSHA256: source.string("binding_sha256"),
      manifestSHA256: source.string("manifest_sha256")
    )
    guard source.int("version") == 1,
          (0...AgentBlobProtocol.maximumFileBytes).contains(value.size),
          AgentBlobProtocol.validHex(value.blobId, bytes: 16),
          AgentBlobProtocol.validHex(value.key, bytes: 32),
          AgentBlobProtocol.validHex(value.noncePrefix, bytes: 8),
          AgentBlobProtocol.validHex(value.sha256, bytes: 32),
          AgentBlobProtocol.validHex(value.bindingSHA256, bytes: 32),
          AgentBlobProtocol.validHex(value.manifestSHA256, bytes: 32) else {
      throw AgentBlobFailure.invalid("invalid_private_descriptor")
    }
    return value
  }

  static func storedReceipt(_ manifest: [String: Any]) -> [String: Any] {
    [
      "type": receiptType, "version": 1, "status": "stored",
      "transfer_id": manifest.string("transfer_id"),
      "client_route_id": manifest.string("client_route_id"),
      "artifact_id": manifest.string("artifact_id"),
      "sha256": manifest.string("sha256"),
      "size_bytes": manifest.int64("size_bytes"),
      "conversation_id": manifest.string("conversation_id"),
      "task_id": manifest.string("task_id"),
      "turn_id": manifest.string("turn_id"),
      "contact_id": manifest.string("contact_id"),
      "execution_generation": manifest.int64("execution_generation")
    ]
  }
}

actor AgentBlobArtifactReceiver {
  struct Identity: Equatable {
    var desktopId: String
    var clientRouteId: String
    var remoteFingerprint: String
    var origin: String
  }

  private struct Job: Codable, Equatable {
    var transferId: String
    var payload: Data
    var desktopId: String
    var clientRouteId: String
    var remoteFingerprint: String
    var origin: String
    var transportRevision: Int64
    var attempts: Int
    var nextAttemptAtMillis: Int64
  }

  private struct TerminalEvent: Codable, Equatable {
    var transferId: String
    var contactId: String
    var sourceMessageId: String
    var manifestData: Data
    var state: String
    var errorCode: String
    var storedAtMillis: Int64
  }

  typealias IdentityProvider = @Sendable (String) async -> Identity?
  typealias Progress = @Sendable ([String: Any], Int) async -> Void
  typealias Completion = @Sendable ([String: Any], Bool, String) async -> Void
  typealias ReceiptPublisher = @Sendable ([String: Any], String) async -> Bool

  private let rootURL: URL
  private let journalURL: URL
  private let terminalEventsURL: URL
  private let artifactStore: AgentDesktopArtifactStore
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let identityProvider: IdentityProvider
  private let progress: Progress
  private let completion: Completion
  private let publishReceipt: ReceiptPublisher
  private var drainTask: Task<Void, Never>?

  init(
    artifactStore: AgentDesktopArtifactStore,
    applicationSupportDirectory: URL? = nil,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    identityProvider: @escaping IdentityProvider,
    progress: @escaping Progress,
    completion: @escaping Completion,
    publishReceipt: @escaping ReceiptPublisher
  ) {
    let support = applicationSupportDirectory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    rootURL = support.appendingPathComponent("blob-artifact-receives-v1", isDirectory: true)
    journalURL = rootURL.appendingPathComponent("journal.saenc", isDirectory: false)
    terminalEventsURL = rootURL.appendingPathComponent("terminal-events.saenc", isDirectory: false)
    self.artifactStore = artifactStore
    self.cipher = cipher
    self.identityProvider = identityProvider
    self.progress = progress
    self.completion = completion
    self.publishReceipt = publishReceipt
  }

  func enqueue(
    payload: [String: Any],
    link: ServerLink,
    configuration: AgentBlobRelayConfiguration,
    conversationId: String
  ) throws {
    let manifest = try AgentBlobArtifactContract.validateOffer(
      payload, link: link, configuration: configuration
    )
    guard manifest.string("conversation_id") == conversationId,
          manifest["peer_chat"] as? Bool != true || manifest.string("contact_id") == link.desktopId,
          let encoded = try? JSONSerialization.data(withJSONObject: payload) else {
      throw AgentBlobFailure.invalid("artifact_blob_identity_mismatch")
    }
    var jobs = try loadJobs()
    let next = Job(
      transferId: manifest.string("transfer_id"), payload: encoded,
      desktopId: link.desktopId, clientRouteId: link.routes.clientRouteId,
      remoteFingerprint: link.routes.remoteFingerprint, origin: configuration.origin,
      transportRevision: payload.int64("transport_revision"),
      attempts: 0, nextAttemptAtMillis: 0
    )
    if let index = jobs.firstIndex(where: { $0.transferId == next.transferId }) {
      let existing = jobs[index]
      guard existing.transportRevision <= next.transportRevision,
            existing.desktopId == next.desktopId,
            existing.clientRouteId == next.clientRouteId,
            existing.remoteFingerprint == next.remoteFingerprint,
            existing.origin == next.origin else {
        throw AgentBlobFailure.invalid("artifact_blob_identity_mismatch")
      }
      if existing.transportRevision == next.transportRevision {
        guard existing.payload == next.payload else {
          throw AgentBlobFailure.invalid("artifact_blob_revision_conflict")
        }
      } else {
        jobs[index] = next
        try saveJobs(jobs)
      }
    } else {
      jobs.append(next)
      try saveJobs(jobs)
    }
    wake()
  }

  func wake() {
    guard drainTask == nil else { return }
    drainTask = Task { await drain() }
  }

  func terminalPresentations(
    contactIds: Set<String>,
    sourceMessageId: String,
    transferIds: Set<String>
  ) -> [AgentBlobArtifactTerminalPresentation] {
    guard !contactIds.isEmpty, !sourceMessageId.isEmpty, !transferIds.isEmpty else { return [] }
    return ((try? loadTerminalEvents()) ?? []).compactMap { event in
      guard contactIds.contains(event.contactId),
            event.sourceMessageId == sourceMessageId,
            transferIds.contains(event.transferId),
            let manifest = try? JSONSerialization.jsonObject(with: event.manifestData) as? [String: Any],
            (try? AgentBlobArtifactContract.validateManifest(manifest)) != nil,
            manifest.string("transfer_id") == event.transferId,
            contactIds.contains(manifest.string("contact_id")),
            manifest.string("source_message_id") == sourceMessageId else {
        return nil
      }
      return AgentBlobArtifactTerminalPresentation(
        manifestData: event.manifestData,
        state: event.state,
        errorCode: event.errorCode
      )
    }
  }

  private func drain() async {
    defer { drainTask = nil }
    while !Task.isCancelled {
      guard let jobs = try? loadJobs(), !jobs.isEmpty else { return }
      let now = nowMillis()
      guard let index = jobs.indices.min(by: {
        jobs[$0].nextAttemptAtMillis < jobs[$1].nextAttemptAtMillis
      }) else { return }
      if jobs[index].nextAttemptAtMillis > now {
        let delay = UInt64(jobs[index].nextAttemptAtMillis - now) * 1_000_000
        try? await Task.sleep(nanoseconds: min(delay, 60_000_000_000))
        continue
      }
      let job = jobs[index]
      do {
        try await process(job)
        var latest = (try? loadJobs()) ?? []
        latest.removeAll { $0.transferId == job.transferId }
        try? saveJobs(latest)
      } catch {
        let code = errorCode(error)
        var latest = (try? loadJobs()) ?? []
        if isTerminal(code) {
          latest.removeAll { $0.transferId == job.transferId }
          let value = (try? manifest(job)) ?? [:]
          try? storeTerminalEvent(manifest: value, completed: false, errorCode: code)
          await completion(value, false, code)
        } else if let current = latest.firstIndex(where: { $0.transferId == job.transferId }) {
          latest[current].attempts += 1
          let seconds = min(300, 2 << min(latest[current].attempts, 7))
          latest[current].nextAttemptAtMillis = nowMillis() + Int64(seconds * 1_000)
        }
        try? saveJobs(latest)
      }
    }
  }

  private func process(_ job: Job) async throws {
    guard let identity = await identityProvider(job.desktopId),
          identity == Identity(
            desktopId: job.desktopId,
            clientRouteId: job.clientRouteId,
            remoteFingerprint: job.remoteFingerprint,
            origin: job.origin
          ),
          let payload = try JSONSerialization.jsonObject(with: job.payload) as? [String: Any],
          let offer = payload["blob_offer"] as? [String: Any],
          let privatePayload = offer["private"] as? [String: Any],
          let origin = URL(string: job.origin) else {
      throw AgentBlobFailure.invalid("artifact_blob_identity_mismatch")
    }
    let manifest = try AgentBlobArtifactContract.validateManifest(
      payload["manifest"] as? [String: Any] ?? [:]
    )
    let descriptor = try AgentBlobArtifactContract.descriptor(privatePayload)
    guard descriptor.bindingSHA256 == (try AgentBlobProtocol.bindingHash(
      AgentBlobArtifactContract.binding(manifest)
    )) else {
      throw AgentBlobFailure.invalid("artifact_blob_binding_mismatch")
    }
    let client = AgentBlobHTTPClient(origin: origin)
    let path = "/v1/blobs/\(descriptor.blobId)"
    let token = offer.string("read_token")
    let relayManifest = try await client.json(method: "GET", path: path, token: token)
    let chunks = try AgentBlobProtocol.validateManifest(relayManifest)
    guard descriptor.manifestSHA256 == AgentBlobProtocol.sha256(
      try AgentBlobProtocol.canonicalJSON(relayManifest)
    ) else {
      throw AgentBlobFailure.invalid("manifest_hash_mismatch")
    }
    var plaintext = Data()
    plaintext.reserveCapacity(Int(min(descriptor.size, Int64(Int.max))))
    for (index, chunk) in chunks.enumerated() {
      guard !Task.isCancelled else { throw CancellationError() }
      let encrypted = try await client.binary(
        method: "GET", path: "\(path)/chunks/\(index)", token: token
      )
      guard encrypted.count == chunk.size,
            AgentBlobProtocol.sha256(encrypted) == chunk.sha256 else {
        throw AgentBlobFailure.invalid("ciphertext_hash_mismatch")
      }
      plaintext.append(try AgentBlobProtocol.open(encrypted, descriptor: descriptor, index: index))
      await progress(manifest, min(99, Int(Int64(plaintext.count) * 100 / max(1, descriptor.size))))
    }
    guard Int64(plaintext.count) == descriptor.size,
          AgentBlobProtocol.sha256(plaintext) == descriptor.sha256 else {
      throw AgentBlobFailure.invalid("plaintext_hash_mismatch")
    }
    try artifactStore.ingestBlobArtifact(manifest: manifest, plaintext: plaintext)
    try storeTerminalEvent(manifest: manifest, completed: true, errorCode: "")
    await completion(manifest, true, "")
    guard await publishReceipt(AgentBlobArtifactContract.storedReceipt(manifest), job.desktopId) else {
      throw AgentBlobFailure.invalid("artifact_blob_receipt_pending")
    }
  }

  private func manifest(_ job: Job) throws -> [String: Any] {
    let payload = try JSONSerialization.jsonObject(with: job.payload) as? [String: Any]
    return try AgentBlobArtifactContract.validateManifest(
      payload?["manifest"] as? [String: Any] ?? [:]
    )
  }

  private func loadJobs() throws -> [Job] {
    guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
    return try JSONDecoder().decode(
      [Job].self,
      from: cipher.read(from: journalURL, purpose: "blob-artifact-receive-journal-v1")
    )
  }

  private func saveJobs(_ jobs: [Job]) throws {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try cipher.write(
      try JSONEncoder().encode(jobs),
      to: journalURL,
      purpose: "blob-artifact-receive-journal-v1"
    )
  }

  private func storeTerminalEvent(
    manifest: [String: Any],
    completed: Bool,
    errorCode: String
  ) throws {
    let value = try AgentBlobArtifactContract.validateManifest(manifest)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    var events = try loadTerminalEvents()
    let transferId = value.string("transfer_id")
    if let index = events.firstIndex(where: { $0.transferId == transferId }) {
      if events[index].state == GalaxySSIPeerAttachmentTransferProgress.complete {
        return
      }
      events.remove(at: index)
    }
    events.append(TerminalEvent(
      transferId: transferId,
      contactId: value.string("contact_id"),
      sourceMessageId: value.string("source_message_id"),
      manifestData: data,
      state: completed
        ? GalaxySSIPeerAttachmentTransferProgress.complete
        : GalaxySSIPeerAttachmentTransferProgress.failed,
      errorCode: errorCode,
      storedAtMillis: nowMillis()
    ))
    if events.count > 1_024 {
      events = Array(events.sorted { $0.storedAtMillis > $1.storedAtMillis }.prefix(1_024))
    }
    try cipher.write(
      try JSONEncoder().encode(events),
      to: terminalEventsURL,
      purpose: "blob-artifact-terminal-events-v1"
    )
  }

  private func loadTerminalEvents() throws -> [TerminalEvent] {
    guard FileManager.default.fileExists(atPath: terminalEventsURL.path) else { return [] }
    return try JSONDecoder().decode(
      [TerminalEvent].self,
      from: cipher.read(from: terminalEventsURL, purpose: "blob-artifact-terminal-events-v1")
    )
  }

  private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

  private func errorCode(_ error: Error) -> String {
    if case AgentBlobFailure.invalid(let code) = error { return code }
    if case AgentBlobFailure.http(let code, _) = error { return code }
    return "artifact_blob_receive_failed"
  }

  private func isTerminal(_ code: String) -> Bool {
    [
      "artifact_blob_identity_mismatch", "artifact_blob_binding_mismatch",
      "artifact_blob_manifest_mismatch", "manifest_hash_mismatch",
      "ciphertext_hash_mismatch", "chunk_authentication_failed",
      "plaintext_hash_mismatch", "invalid_private_descriptor",
      "invalid_artifact_blob_manifest"
    ].contains(code)
  }
}
