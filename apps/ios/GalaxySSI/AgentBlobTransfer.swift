import Foundation
import CryptoKit

struct AgentBlobCheckpoint: Codable, Equatable {
  var descriptor: AgentBlobPrivateDescriptor
  var chunks: [AgentBlobChunk]
  var relay: String
  var readToken: String
  var writeToken: String
  var remoteCreated: Bool
  var uploaded: Bool
}

private struct AgentBlobOutgoingJob: Codable, Equatable {
  var transferId: String
  var desktopId: String
  var desktopFingerprint: String
  var clientRouteId: String
  var origin: String
  var active: Bool
  var awaitingReceipt: Bool
  var attempts: Int
  var nextAttemptAt: Date
}

final class AgentBlobStaging {
  private static let checkpointName = "transfer.saenc"
  private let directoryURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let fileManager: FileManager
  private(set) var checkpoint: AgentBlobCheckpoint

  var manifest: [String: Any] { AgentBlobProtocol.manifest(checkpoint.chunks) }

  static func openOrPrepare(
    attachment: AgentPreparedOutboundAttachment,
    directoryURL: URL,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    fileManager: FileManager = .default
  ) throws -> AgentBlobStaging {
    let checkpointURL = directoryURL.appendingPathComponent(checkpointName)
    if fileManager.fileExists(atPath: checkpointURL.path) {
      let data = try cipher.read(
        from: checkpointURL,
        purpose: checkpointPurpose(attachment.transferId)
      )
      let checkpoint = try JSONDecoder().decode(AgentBlobCheckpoint.self, from: data)
      let staging = AgentBlobStaging(
        directoryURL: directoryURL,
        checkpoint: checkpoint,
        cipher: cipher,
        fileManager: fileManager
      )
      try staging.validate(attachment: attachment)
      return staging
    }
    guard attachment.sizeBytes >= 0,
          attachment.sizeBytes <= AgentBlobProtocol.maximumFileBytes else {
      throw AgentBlobFailure.invalid("file_too_large")
    }
    guard !fileManager.fileExists(atPath: directoryURL.path) else {
      throw AgentBlobFailure.invalid("invalid_transfer_checkpoint")
    }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    do {
      let bindingHash = try AgentBlobProtocol.bindingHash(
        AgentBlobProtocol.binding(for: attachment)
      )
      var descriptor = AgentBlobPrivateDescriptor(
        blobId: try AgentBlobProtocol.randomHex(bytes: 16),
        key: try AgentBlobProtocol.randomHex(bytes: 32),
        noncePrefix: try AgentBlobProtocol.randomHex(bytes: 8),
        size: attachment.sizeBytes,
        sha256: attachment.sha256,
        bindingSHA256: bindingHash,
        manifestSHA256: ""
      )
      let chunks = try prepareChunks(
        attachment: attachment,
        descriptor: descriptor,
        directoryURL: directoryURL
      )
      descriptor.manifestSHA256 = AgentBlobProtocol.sha256(
        try AgentBlobProtocol.canonicalJSON(AgentBlobProtocol.manifest(chunks))
      )
      let checkpoint = AgentBlobCheckpoint(
        descriptor: descriptor,
        chunks: chunks,
        relay: "",
        readToken: try AgentBlobProtocol.randomHex(bytes: 32),
        writeToken: try AgentBlobProtocol.randomHex(bytes: 32),
        remoteCreated: false,
        uploaded: false
      )
      let staging = AgentBlobStaging(
        directoryURL: directoryURL,
        checkpoint: checkpoint,
        cipher: cipher,
        fileManager: fileManager
      )
      try staging.save(transferId: attachment.transferId)
      return staging
    } catch {
      try? fileManager.removeItem(at: directoryURL)
      throw error
    }
  }

  func readChunk(index: Int) throws -> Data {
    guard checkpoint.chunks.indices.contains(index) else {
      throw AgentBlobFailure.invalid("invalid_chunk_index")
    }
    let expected = checkpoint.chunks[index]
    let url = chunkURL(index)
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          (attributes[.size] as? NSNumber)?.intValue == expected.size else {
      throw AgentBlobFailure.invalid("local_chunk_missing_or_corrupt")
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard AgentBlobProtocol.sha256(data) == expected.sha256 else {
      throw AgentBlobFailure.invalid("local_chunk_missing_or_corrupt")
    }
    return data
  }

  func updateRemote(
    relay: String? = nil,
    created: Bool? = nil,
    uploaded: Bool? = nil,
    transferId: String
  ) throws {
    if let relay { checkpoint.relay = relay }
    if let created { checkpoint.remoteCreated = created }
    if let uploaded { checkpoint.uploaded = uploaded }
    try save(transferId: transferId)
  }

  private init(
    directoryURL: URL,
    checkpoint: AgentBlobCheckpoint,
    cipher: GalaxySSIAttachmentAtRestCipher,
    fileManager: FileManager
  ) {
    self.directoryURL = directoryURL
    self.checkpoint = checkpoint
    self.cipher = cipher
    self.fileManager = fileManager
  }

  private func validate(attachment: AgentPreparedOutboundAttachment) throws {
    guard checkpoint.descriptor.size == attachment.sizeBytes,
          checkpoint.descriptor.sha256 == attachment.sha256,
          checkpoint.descriptor.bindingSHA256 == (try AgentBlobProtocol.bindingHash(
            AgentBlobProtocol.binding(for: attachment)
          )),
          checkpoint.descriptor.manifestSHA256 == AgentBlobProtocol.sha256(
            try AgentBlobProtocol.canonicalJSON(manifest)
          ),
          try AgentBlobProtocol.validateManifest(manifest) == checkpoint.chunks else {
      throw AgentBlobFailure.invalid("relay_checkpoint_mismatch")
    }
  }

  private func save(transferId: String) throws {
    let data = try JSONEncoder().encode(checkpoint)
    guard data.count <= 256 * 1_024 else {
      throw AgentBlobFailure.invalid("transfer_checkpoint_too_large")
    }
    try cipher.write(
      data,
      to: directoryURL.appendingPathComponent(Self.checkpointName),
      purpose: Self.checkpointPurpose(transferId)
    )
  }

  private func chunkURL(_ index: Int) -> URL {
    directoryURL.appendingPathComponent(
      String(format: "%08d.blob", index),
      isDirectory: false
    )
  }

  private static func checkpointPurpose(_ transferId: String) -> String {
    "blob-outgoing-checkpoint-v1:\(transferId)"
  }

  private static func prepareChunks(
    attachment: AgentPreparedOutboundAttachment,
    descriptor: AgentBlobPrivateDescriptor,
    directoryURL: URL
  ) throws -> [AgentBlobChunk] {
    var chunks: [AgentBlobChunk] = []
    var pending = Data(capacity: AgentBlobProtocol.chunkBytes)
    var sourceDigest = SHA256()
    var sourceBytes: Int64 = 0
    var outputIndex = 0

    func sealPending(_ plaintext: Data) throws {
      let encrypted = try AgentBlobProtocol.seal(
        plaintext,
        descriptor: descriptor,
        index: outputIndex
      )
      let destination = directoryURL.appendingPathComponent(
        String(format: "%08d.blob", outputIndex),
        isDirectory: false
      )
      try encrypted.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
      chunks.append(AgentBlobChunk(
        sha256: AgentBlobProtocol.sha256(encrypted),
        size: encrypted.count
      ))
      outputIndex += 1
    }

    for index in 0..<attachment.chunkCount {
      let source = try attachment.plaintextChunk(index: index)
      sourceDigest.update(data: source)
      sourceBytes += Int64(source.count)
      pending.append(source)
      while pending.count >= AgentBlobProtocol.chunkBytes {
        let plaintext = Data(pending.prefix(AgentBlobProtocol.chunkBytes))
        pending.removeFirst(AgentBlobProtocol.chunkBytes)
        try sealPending(plaintext)
      }
    }
    if !pending.isEmpty || attachment.sizeBytes == 0 {
      try sealPending(pending)
    }
    guard sourceBytes == attachment.sizeBytes,
          Data(sourceDigest.finalize()).hexString() == attachment.sha256 else {
      throw AgentBlobFailure.invalid("source_changed")
    }
    return chunks
  }
}

private final class AgentBlobURLSessionDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

final class AgentBlobHTTPClient {
  private let origin: URL
  private let session: URLSession
  private let delegate: AgentBlobURLSessionDelegate

  init(origin: URL) {
    self.origin = origin
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 300
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let delegate = AgentBlobURLSessionDelegate()
    self.delegate = delegate
    self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  func json(
    method: String,
    path: String,
    token: String,
    body: [String: Any]? = nil
  ) async throws -> [String: Any] {
    let data: Data?
    if let body {
      guard JSONSerialization.isValidJSONObject(body) else {
        throw AgentBlobFailure.invalid("invalid_json_body")
      }
      data = try JSONSerialization.data(withJSONObject: body)
    } else {
      data = nil
    }
    let response = try await request(method: method, path: path, token: token, body: data, json: true)
    guard response.count <= 128 * 1_024,
          let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
      throw AgentBlobFailure.invalid("invalid_relay_response")
    }
    return object
  }

  func binary(method: String, path: String, token: String, body: Data = Data()) async throws -> Data {
    try await request(method: method, path: path, token: token, body: body, json: false)
  }

  private func request(
    method: String,
    path: String,
    token: String,
    body: Data?,
    json: Bool
  ) async throws -> Data {
    guard AgentBlobProtocol.validHex(token, bytes: 32),
          path.hasPrefix("/"),
          let url = URL(string: path, relativeTo: origin)?.absoluteURL,
          url.scheme == "https",
          url.host == origin.host else {
      throw AgentBlobFailure.invalid("invalid_blob_request")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(json ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode),
          data.count <= AgentBlobProtocol.chunkBytes + 128 * 1_024 else {
      throw AgentBlobFailure.http("blob_relay_request_failed", (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    return data
  }
}

actor AgentBlobOutgoingCoordinator {
  typealias OfferPublisher = ([String: Any], AgentPreparedOutboundAttachment) async throws -> Void

  private let rootURL: URL
  private let journalURL: URL
  private let configurationStore: AgentBlobRelayConfigurationStore
  private let attachmentStore: AgentOutboundAttachmentTransferStore
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let fileManager: FileManager
  private let publishOffer: OfferPublisher
  private var running = false
  private var scheduledWake: Task<Void, Never>?

  init(
    configurationStore: AgentBlobRelayConfigurationStore,
    attachmentStore: AgentOutboundAttachmentTransferStore,
    applicationSupportDirectory: URL? = nil,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    fileManager: FileManager = .default,
    publishOffer: @escaping OfferPublisher
  ) {
    let support = applicationSupportDirectory ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    self.rootURL = support.appendingPathComponent("blob-outgoing-v1", isDirectory: true)
    self.journalURL = self.rootURL.appendingPathComponent("journal.saenc")
    self.configurationStore = configurationStore
    self.attachmentStore = attachmentStore
    self.cipher = cipher
    self.fileManager = fileManager
    self.publishOffer = publishOffer
  }

  func register(_ attachment: AgentPreparedOutboundAttachment, link: ServerLink) throws -> Bool {
    guard let configuration = configurationStore.configuration(for: link),
          let origin = configuration.originURL,
          origin.scheme == "https" else { return false }
    guard attachment.scope.desktopId == link.desktopId,
          attachment.scope.clientRouteId == link.routes.clientRouteId else {
      throw AgentBlobFailure.invalid("blob_outgoing_route_mismatch")
    }
    var jobs = try loadJobs()
    if let existing = jobs.first(where: { $0.transferId == attachment.transferId }) {
      guard existing.desktopId == link.desktopId,
            existing.desktopFingerprint == link.routes.remoteFingerprint,
            existing.clientRouteId == link.routes.clientRouteId,
            existing.origin == origin.absoluteString else {
        throw AgentBlobFailure.invalid("blob_outgoing_identity_conflict")
      }
      return true
    }
    jobs.append(AgentBlobOutgoingJob(
      transferId: attachment.transferId,
      desktopId: link.desktopId,
      desktopFingerprint: link.routes.remoteFingerprint,
      clientRouteId: link.routes.clientRouteId,
      origin: origin.absoluteString,
      active: false,
      awaitingReceipt: false,
      attempts: 0,
      nextAttemptAt: .distantPast
    ))
    try saveJobs(jobs)
    return true
  }

  func activate(_ transferIds: Set<String>) throws {
    guard !transferIds.isEmpty else { return }
    var jobs = try loadJobs()
    for index in jobs.indices where transferIds.contains(jobs[index].transferId) {
      jobs[index].active = true
      jobs[index].nextAttemptAt = .distantPast
    }
    try saveJobs(jobs)
    wake()
  }

  func cancel(_ transferIds: Set<String>) throws {
    var jobs = try loadJobs()
    let removed = jobs.filter { transferIds.contains($0.transferId) }
    jobs.removeAll { transferIds.contains($0.transferId) }
    try saveJobs(jobs)
    for job in removed {
      try? fileManager.removeItem(at: stagingURL(job.transferId))
    }
  }

  func owns(_ transferId: String) -> Bool {
    (try? loadJobs().contains { $0.transferId == transferId }) == true
  }

  func acceptStored(
    _ payload: [String: Any],
    link: ServerLink,
    attachment: AgentPreparedOutboundAttachment
  ) async throws -> Bool {
    var jobs = try loadJobs()
    guard let index = jobs.firstIndex(where: { $0.transferId == attachment.transferId }),
          jobs[index].desktopId == link.desktopId,
          jobs[index].desktopFingerprint == link.routes.remoteFingerprint,
          jobs[index].clientRouteId == link.routes.clientRouteId,
          AgentBlobProtocol.receiptMatches(attachment: attachment, receipt: payload) else {
      return false
    }
    let job = jobs[index]
    let staged = try AgentBlobStaging.openOrPrepare(
      attachment: attachment,
      directoryURL: stagingURL(job.transferId),
      cipher: cipher,
      fileManager: fileManager
    )
    if staged.checkpoint.remoteCreated,
       let origin = URL(string: job.origin) {
      do {
        _ = try await AgentBlobHTTPClient(origin: origin).binary(
          method: "DELETE",
          path: "/v1/blobs/\(staged.checkpoint.descriptor.blobId)",
          token: staged.checkpoint.writeToken
        )
      } catch AgentBlobFailure.http(_, let status) where status == 404 || status == 410 {
        // The relay already discarded the authenticated blob.
      }
    }
    _ = jobs.remove(at: index)
    try saveJobs(jobs)
    try? fileManager.removeItem(at: stagingURL(job.transferId))
    return true
  }

  func wake() {
    scheduledWake?.cancel()
    scheduledWake = nil
    guard !running else { return }
    running = true
    Task { await drain() }
  }

  private func drain() async {
    defer { running = false }
    while true {
      guard var jobs = try? loadJobs(),
            let index = jobs.indices.first(where: {
              jobs[$0].active && jobs[$0].nextAttemptAt <= Date()
            }) else { return }
      var job = jobs[index]
      do {
        try await process(job)
        job.awaitingReceipt = true
        job.attempts = 0
        job.nextAttemptAt = Date().addingTimeInterval(30)
      } catch {
        job.attempts += 1
        let delay = min(300.0, 2.0 * pow(2.0, Double(min(job.attempts, 8))))
        job.nextAttemptAt = Date().addingTimeInterval(delay)
      }
      jobs[index] = job
      try? saveJobs(jobs)
      if jobs.contains(where: { $0.active && $0.nextAttemptAt <= Date() }) { continue }
      if let next = jobs.filter(\.active).map(\.nextAttemptAt).min() {
        scheduleWake(at: next)
      }
      return
    }
  }

  private func scheduleWake(at date: Date) {
    let nanoseconds = UInt64(max(1, date.timeIntervalSinceNow) * 1_000_000_000)
    scheduledWake?.cancel()
    scheduledWake = Task { [weak self] in
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else { return }
      await self?.resumeScheduledWork()
    }
  }

  private func resumeScheduledWork() {
    running = false
    wake()
  }

  private func process(_ job: AgentBlobOutgoingJob) async throws {
    guard let attachment = attachmentStore.find(job.transferId) else {
      throw AgentBlobFailure.invalid("blob_source_missing")
    }
    let directory = stagingURL(job.transferId)
    let staged = try AgentBlobStaging.openOrPrepare(
      attachment: attachment,
      directoryURL: directory,
      cipher: cipher,
      fileManager: fileManager
    )
    guard let origin = URL(string: job.origin) else {
      throw AgentBlobFailure.invalid("invalid_blob_relay_origin")
    }
    let client = AgentBlobHTTPClient(origin: origin)
    let path = "/v1/blobs/\(staged.checkpoint.descriptor.blobId)"
    if !staged.checkpoint.remoteCreated {
      let configuration = configurationStore.configuration(for: ServerLink(
        desktopId: job.desktopId,
        desktopName: "",
        desktopFingerprint: job.desktopFingerprint,
        signalName: "",
        routes: GalaxySSILinkRoutes(
          clientRouteId: job.clientRouteId,
          linkSecret: "",
          localFingerprint: "local",
          remoteFingerprint: job.desktopFingerprint
        ),
        paired: true,
        accessProfile: "",
        accessScopes: [],
        updatedAt: Date()
      ))
      guard let configuration, configuration.origin == job.origin else {
        throw AgentBlobFailure.invalid("blob_relay_unavailable")
      }
      let response = try await client.json(
        method: "PUT",
        path: path,
        token: configuration.provisioningToken,
        body: [
          "manifest": staged.manifest,
          "read_token": staged.checkpoint.readToken,
          "write_token": staged.checkpoint.writeToken
        ]
      )
      guard response.string("root") == staged.checkpoint.descriptor.manifestSHA256 else {
        throw AgentBlobFailure.invalid("manifest_hash_mismatch")
      }
      try staged.updateRemote(relay: job.origin, created: true, transferId: job.transferId)
    }
    let status = try await client.json(
      method: "GET",
      path: "\(path)/missing",
      token: staged.checkpoint.writeToken
    )
    guard status.string("root") == staged.checkpoint.descriptor.manifestSHA256,
          status.int("chunk_count") == staged.checkpoint.chunks.count else {
      throw AgentBlobFailure.invalid("relay_checkpoint_mismatch")
    }
    let missing = try AgentBlobProtocol.missingIndices(
      bitmap: status.string("missing_bitmap"),
      count: staged.checkpoint.chunks.count
    )
    let offer = AgentBlobProtocol.offer(
      relay: origin,
      readToken: staged.checkpoint.readToken,
      descriptor: staged.checkpoint.descriptor
    )
    try await publishOffer(
      try AgentBlobProtocol.offerPayload(attachment: attachment, offer: offer),
      attachment
    )
    for index in missing {
      let response = try await client.binary(
        method: "PUT",
        path: "\(path)/chunks/\(index)",
        token: staged.checkpoint.writeToken,
        body: try staged.readChunk(index: index)
      )
      guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
            object["stored"] as? Bool == true else {
        throw AgentBlobFailure.invalid("invalid_chunk_receipt")
      }
    }
    let final = try await client.json(
      method: "GET",
      path: "\(path)/missing",
      token: staged.checkpoint.writeToken
    )
    guard final["complete"] as? Bool == true,
          try AgentBlobProtocol.missingIndices(
            bitmap: final.string("missing_bitmap"),
            count: staged.checkpoint.chunks.count
          ).isEmpty else {
      throw AgentBlobFailure.invalid("relay_upload_incomplete")
    }
    try staged.updateRemote(uploaded: true, transferId: job.transferId)
  }

  private func loadJobs() throws -> [AgentBlobOutgoingJob] {
    guard fileManager.fileExists(atPath: journalURL.path) else { return [] }
    let data = try cipher.read(from: journalURL, purpose: "blob-outgoing-journal-v1")
    return try JSONDecoder().decode([AgentBlobOutgoingJob].self, from: data)
  }

  private func saveJobs(_ jobs: [AgentBlobOutgoingJob]) throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try cipher.write(
      try JSONEncoder().encode(jobs),
      to: journalURL,
      purpose: "blob-outgoing-journal-v1"
    )
  }

  private func stagingURL(_ transferId: String) -> URL {
    rootURL.appendingPathComponent("staging", isDirectory: true)
      .appendingPathComponent(transferId, isDirectory: true)
  }
}
