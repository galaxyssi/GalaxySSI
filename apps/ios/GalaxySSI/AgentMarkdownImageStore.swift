import CryptoKit
import Foundation

protocol AgentMarkdownImageFetching: Sendable {
  func fetch(_ url: URL) async throws -> Data
}

enum AgentMarkdownImageFailure: Error { case invalidURL, invalidResponse, tooLarge, unsupportedImage, tooManyRedirects, capacity }

actor AgentMarkdownImageStore {
  static let shared = AgentMarkdownImageStore()
  static let maximumBytes = 12 * 1024 * 1024
  static let maximumCacheBytes = 64 * 1024 * 1024
  private struct Flight {
    var id: UUID
    var task: Task<Void, Never>
    var waiters: [UUID: Waiter]
  }
  private struct Waiter {
    var continuation: CheckedContinuation<Data, Error>
    var cancelled: ImagePreflightCancellation
  }
  private let root: URL
  private let transport: AgentMarkdownImageFetching
  private let cipher: GalaxySSILocalAttachmentStoring
  private let manager: FileManager
  private var flights: [String: Flight] = [:]

  init(root: URL = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
      .appendingPathComponent("GalaxySSI/markdown-images", isDirectory: true),
       transport: AgentMarkdownImageFetching = AgentMarkdownImageTransport(),
       cipher: GalaxySSILocalAttachmentStoring = GalaxySSIAttachmentAtRestCipher(keyAccount: "markdown-image.cache.aes256.v1"),
       fileManager: FileManager = .default) {
    self.root = root.standardizedFileURL
    self.transport = transport
    self.cipher = cipher
    manager = fileManager
  }

  static func publicURL(_ url: URL) throws -> URL {
    guard url.absoluteString.utf8.count <= 4096, url.port.map({ (1...65535).contains($0) }) ?? true,
      AgentIOSWebRenderURLPolicy.allows(url.absoluteString),
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw AgentMarkdownImageFailure.invalidURL }
    parts.fragment = nil
    guard let clean = parts.url else { throw AgentMarkdownImageFailure.invalidURL }
    return clean
  }

  func image(_ input: URL) async throws -> Data {
    try Task.checkCancellation()
    let url = try Self.publicURL(input)
    let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = root.appendingPathComponent(key + ".saenc")
    if let data = cached(file, key: key) { try Task.checkCancellation(); return data }
    let lease = UUID()
    let cancelled = ImagePreflightCancellation()
    let data = try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        add(url: url, key: key, lease: lease, waiter: Waiter(continuation: continuation, cancelled: cancelled))
      }
    }, onCancel: {
      cancelled.cancel()
      Task { await self.release(key: key, lease: lease) }
    })
    try Task.checkCancellation()
    return data
  }

  func clear() {
    for flight in flights.values {
      flight.task.cancel()
      for waiter in flight.waiters.values { waiter.continuation.resume(throwing: CancellationError()) }
    }
    flights.removeAll()
    for entry in cacheFiles() { try? manager.removeItem(at: entry.url) }
  }

  func activity() -> (resources: Int, waiters: Int) {
    (flights.count, flights.values.reduce(0) { $0 + $1.waiters.count })
  }

  private func add(url: URL, key: String, lease: UUID, waiter: Waiter) {
    guard !waiter.cancelled.value else { waiter.continuation.resume(throwing: CancellationError()); return }
    if var flight = flights[key] {
      guard flight.waiters.count < 64 else { waiter.continuation.resume(throwing: AgentMarkdownImageFailure.capacity); return }
      flight.waiters[lease] = waiter
      flights[key] = flight
      return
    }
    guard flights.count < 8 else { waiter.continuation.resume(throwing: AgentMarkdownImageFailure.capacity); return }
    let id = UUID()
    let transport = self.transport
    let task = Task.detached(priority: .userInitiated) {
      let result: Result<Data, Error>
      do {
        try Task.checkCancellation()
        let data = try await transport.fetch(url)
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= Self.maximumBytes else { throw AgentMarkdownImageFailure.tooLarge }
        guard GalaxySSIImageResourceDecoder.canDecode(data) else { throw AgentMarkdownImageFailure.unsupportedImage }
        result = .success(data)
      } catch { result = .failure(error) }
      await self.complete(key: key, id: id, result: result)
    }
    flights[key] = Flight(id: id, task: task, waiters: [lease: waiter])
  }

  private func complete(key: String, id: UUID, result: Result<Data, Error>) {
    guard let flight = flights[key], flight.id == id else { return }
    flights.removeValue(forKey: key)
    if case .success(let data) = result, flight.waiters.values.contains(where: { !$0.cancelled.value }) {
      do {
        try cipher.write(data, to: root.appendingPathComponent(key + ".saenc"), purpose: "markdown-image:" + key)
        prune()
      } catch { /* A cache failure does not invalidate downloaded bytes. */ }
    }
    for waiter in flight.waiters.values {
      if waiter.cancelled.value { waiter.continuation.resume(throwing: CancellationError()) }
      else { waiter.continuation.resume(with: result) }
    }
  }

  private func release(key: String, lease: UUID) {
    guard var flight = flights[key], let waiter = flight.waiters.removeValue(forKey: lease) else { return }
    waiter.continuation.resume(throwing: CancellationError())
    if flight.waiters.isEmpty { flights.removeValue(forKey: key); flight.task.cancel() }
    else { flights[key] = flight }
  }

  private func cached(_ file: URL, key: String) -> Data? {
    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size > 0, size <= Self.maximumBytes + 8192,
      let data = try? cipher.read(from: file, purpose: "markdown-image:" + key),
      !data.isEmpty, data.count <= Self.maximumBytes, GalaxySSIImageResourceDecoder.canDecode(data) else { return nil }
    try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    return data
  }

  private func cacheFiles() -> [(url: URL, size: Int, date: Date)] {
    guard let files = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
    return files.compactMap { url in
      let name = url.deletingPathExtension().lastPathComponent
      guard url.pathExtension == "saenc", name.count == 64, name.allSatisfy({ "0123456789abcdef".contains($0) }),
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
        values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { return nil }
      return (url, size, values.contentModificationDate ?? .distantPast)
    }
  }

  private func prune() {
    var total = 0
    for (index, entry) in cacheFiles().sorted(by: { $0.date > $1.date }).enumerated() {
      total += entry.size
      if index >= 128 || total > Self.maximumCacheBytes { try? manager.removeItem(at: entry.url) }
    }
  }
}

struct AgentMarkdownImageTransport: AgentMarkdownImageFetching {
  func fetch(_ input: URL) async throws -> Data {
    var url = try AgentMarkdownImageStore.publicURL(input)
    let started = ProcessInfo.processInfo.systemUptime
    for _ in 0..<6 {
      try Task.checkCancellation()
      let remaining = 30 - (ProcessInfo.processInfo.systemUptime - started)
      guard remaining > 0 else { throw URLError(.timedOut) }
      try await preflight(url, timeout: remaining)
      try Task.checkCancellation()
      let left = 30 - (ProcessInfo.processInfo.systemUptime - started)
      guard left > 0 else { throw URLError(.timedOut) }
      let response = try await AgentRemoteImageTransfer(url: url, timeout: left).run()
      if [301, 302, 303, 307, 308].contains(response.status) {
        guard let location = response.location, location.utf8.count <= 4096,
          let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw AgentMarkdownImageFailure.invalidURL }
        url = try AgentMarkdownImageStore.publicURL(next)
      } else { return response.data }
    }
    throw AgentMarkdownImageFailure.tooManyRedirects
  }

  private func preflight(_ url: URL, timeout: TimeInterval) async throws {
    let cancelled = ImagePreflightCancellation()
    try await withTaskCancellationHandler(operation: {
      let allowed = try await Task.detached {
        try AgentIOSWebRenderPreflight.resolve(deadline: .now() + timeout,
          isCancellationRequested: { cancelled.value }, checkpoint: {},
          resolver: { AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(url.absoluteString) })
      }.value
      guard allowed else { throw AgentMarkdownImageFailure.invalidURL }
    }, onCancel: { cancelled.cancel() })
  }
}

private final class ImagePreflightCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var value: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
