import Foundation

final class AgentIOSRuntimePackCatalogStore {
  static let maximumCatalogBytes = 1 * 1_024 * 1_024

  private let fileURL: URL
  private let fileManager: FileManager

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = runtimeRootURL.appendingPathComponent("verified-runtime-catalog.json", isDirectory: false)
    self.fileManager = fileManager
  }

  func save(_ catalog: AgentRuntimePackCatalog) throws {
    let data = try JSONEncoder().encode(catalog)
    guard data.count <= Self.maximumCatalogBytes else {
      throw AgentRuntimePackArchiveError("Runtime catalog exceeds the size limit")
    }
    try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = fileURL.appendingPathExtension("tmp-\(UUID().uuidString)")
    try data.write(to: temporary, options: [.atomic])
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    try fileManager.moveItem(at: temporary, to: fileURL)
  }

  func load() -> AgentRuntimePackCatalog? {
    guard fileManager.fileExists(atPath: fileURL.path),
          let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
          let size = (attributes[.size] as? NSNumber)?.intValue,
          size > 0, size <= Self.maximumCatalogBytes,
          let data = try? Data(contentsOf: fileURL),
          data.count <= Self.maximumCatalogBytes else {
      return nil
    }
    return try? JSONDecoder().decode(AgentRuntimePackCatalog.self, from: data)
  }

  func clear() {
    try? fileManager.removeItem(at: fileURL)
  }
}

final class AgentIOSRuntimePackCatalogManager {
  private let store: AgentIOSRuntimePackCatalogStore
  private let downloader: AgentIOSRuntimePackDownloader
  private let installer: AgentIOSRuntimePackInstaller
  private let languageTag: String
  private let hostVersionCode: Int64
  private let nowMillis: () -> Int64
  private let signatureVerifier: (AgentRuntimePackCatalog) -> Bool

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    languageTag: String = Locale.current.identifier,
    hostVersionCode: Int64 = AgentIOSRuntimePackInstaller.defaultHostVersionCode(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    signatureVerifier: @escaping (AgentRuntimePackCatalog) -> Bool = { catalog in
      AgentIOSRuntimePackTrust.verify(catalog: catalog)
    }
  ) {
    self.store = AgentIOSRuntimePackCatalogStore(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager
    )
    self.downloader = AgentIOSRuntimePackDownloader(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager
    )
    self.installer = AgentIOSRuntimePackInstaller(
      runtimeRootURL: runtimeRootURL,
      fileManager: fileManager,
      hostVersionCode: hostVersionCode
    )
    self.languageTag = languageTag
    self.hostVersionCode = max(hostVersionCode, 1)
    self.nowMillis = nowMillis
    self.signatureVerifier = signatureVerifier
  }

  func refresh(
    url: String? = nil,
    checkpoint: @escaping () throws -> Void = {}
  ) throws -> AgentRuntimePackCatalog {
    let previous = store.load().flatMap { cached in
      try? AgentRuntimePackCatalogPolicy.validate(
        cached,
        nowMillis: cached.generatedAtMillis,
        verifier: signatureVerifier
      )
    }
    let candidates = (url.map { [$0] } ?? AgentRuntimeDistributionSources.catalogCandidates(languageTag: languageTag))
      .filter { !$0.isEmpty }
    var lastError: Error?
    for candidate in candidates {
      do {
        try checkpoint()
        let data = try fetchCatalog(candidate, checkpoint: checkpoint)
        let catalog = try JSONDecoder().decode(AgentRuntimePackCatalog.self, from: data)
        try AgentRuntimePackCatalogPolicy.validate(
          catalog,
          nowMillis: nowMillis(),
          verifier: signatureVerifier
        )
        try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: catalog)
        try store.save(catalog)
        return catalog
      } catch {
        try checkpoint()
        lastError = error
      }
    }
    throw lastError ?? AgentRuntimePackArchiveError("Runtime catalog is unavailable from configured sources")
  }

  func cachedVerified() -> AgentRuntimePackCatalog? {
    guard let catalog = store.load() else { return nil }
    return try? AgentRuntimePackCatalogPolicy.validate(
      catalog,
      nowMillis: nowMillis(),
      verifier: signatureVerifier
    )
  }

  func cachedCompatible() -> [AgentRuntimePackCatalogEntry] {
    guard let catalog = cachedVerified() else { return [] }
    return AgentRuntimePackCatalogPolicy.compatibleEntries(
      in: catalog,
      hostVersionCode: hostVersionCode
    )
  }

  func installationPlan(
    for entry: AgentRuntimePackCatalogEntry,
    catalog: AgentRuntimePackCatalog? = nil
  ) throws -> [AgentRuntimePackCatalogEntry] {
    let selectedCatalog: AgentRuntimePackCatalog
    if let catalog {
      selectedCatalog = catalog
    } else if let cached = cachedVerified() {
      selectedCatalog = cached
    } else {
      throw AgentRuntimePackArchiveError("Runtime catalog is not available")
    }
    let available = AgentRuntimePackCatalogPolicy.compatibleEntries(
      in: selectedCatalog,
      hostVersionCode: hostVersionCode
    ).filter { $0.architecture == entry.architecture }
    let byId = Dictionary(uniqueKeysWithValues: available.map { ($0.packId, $0) })
    guard let current = byId[entry.packId],
          current.version == entry.version,
          current.archiveSha256.caseInsensitiveCompare(entry.archiveSha256) == .orderedSame else {
      throw AgentRuntimePackArchiveError("Runtime pack is not present in the current verified catalog")
    }
    var ordered: [AgentRuntimePackCatalogEntry] = []
    var visiting = Set<String>()
    var visited = Set<String>()
    func visit(_ item: AgentRuntimePackCatalogEntry) throws {
      if visited.contains(item.packId) { return }
      guard visiting.insert(item.packId).inserted else {
        throw AgentRuntimePackArchiveError("Runtime pack dependency cycle detected")
      }
      for dependency in item.dependencies {
        guard let dependencyEntry = byId[dependency] else {
          throw AgentRuntimePackArchiveError("Runtime pack dependency is unavailable: \(dependency)")
        }
        try visit(dependencyEntry)
      }
      visiting.remove(item.packId)
      visited.insert(item.packId)
      ordered.append(item)
    }
    try visit(current)
    return ordered
  }

  func downloadAndInstall(
    entry: AgentRuntimePackCatalogEntry,
    checkpoint: @escaping () throws -> Void = {},
    onDownloadProgress: @escaping (AgentIOSRuntimePackDownloadProgress) -> Void = { _ in },
    onInstallProgress: @escaping (AgentRuntimePackInstallProgress) -> Void = { _ in }
  ) throws -> [AgentRuntimePackInstallResult] {
    let verifiedCatalog: AgentRuntimePackCatalog
    if let cached = cachedVerified() {
      verifiedCatalog = cached
    } else {
      verifiedCatalog = try refresh(checkpoint: checkpoint)
    }
    let plan = try installationPlan(for: entry, catalog: verifiedCatalog)
    var results: [AgentRuntimePackInstallResult] = []
    for item in plan {
      try checkpoint()
      if let installed = installer.installedManifest(packId: item.packId),
         installed.version == item.version {
        results.append(AgentRuntimePackInstallResult(
          packId: item.packId,
          version: installed.version,
          state: .ready,
          installedBytes: 0,
          replacedExisting: false,
          reason: "already_ready"
        ))
        continue
      }
      var lastError: Error?
      let candidates = AgentRuntimeDistributionSources.downloadCandidates(
        url: item.downloadUrl,
        languageTag: languageTag
      )
      for candidate in candidates {
        do {
          let archive = try downloader.download(
            entry: item,
            from: candidate,
            isCancelled: {
              (try? checkpoint()) != nil ? false : true
            },
            onProgress: onDownloadProgress
          )
          defer { try? FileManager.default.removeItem(at: archive) }
          let result = try installer.install(source: archive, onProgress: onInstallProgress)
          results.append(result)
          lastError = nil
          break
        } catch {
          try checkpoint()
          lastError = error
        }
      }
      if let lastError { throw lastError }
    }
    return results
  }

  func install(
    packId: String,
    checkpoint: @escaping () throws -> Void = {},
    onDownloadProgress: @escaping (AgentIOSRuntimePackDownloadProgress) -> Void = { _ in },
    onInstallProgress: @escaping (AgentRuntimePackInstallProgress) -> Void = { _ in }
  ) throws -> [AgentRuntimePackInstallResult] {
    let catalog: AgentRuntimePackCatalog
    if let cached = cachedVerified() {
      catalog = cached
    } else {
      catalog = try refresh(checkpoint: checkpoint)
    }
    guard let entry = AgentRuntimePackCatalogPolicy.compatibleEntries(
      in: catalog,
      hostVersionCode: hostVersionCode
    ).first(where: { $0.packId == packId }) else {
      throw AgentRuntimePackArchiveError("No compatible signed runtime pack is available for \(packId)")
    }
    return try downloadAndInstall(
      entry: entry,
      checkpoint: checkpoint,
      onDownloadProgress: onDownloadProgress,
      onInstallProgress: onInstallProgress
    )
  }

  func clearCache() {
    store.clear()
  }

  private func fetchCatalog(
    _ source: String,
    checkpoint: @escaping () throws -> Void
  ) throws -> Data {
    guard let components = try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(source),
          let url = components.url else {
      throw AgentRuntimePackArchiveError("Runtime catalog URL must be public HTTPS")
    }
    let delegate = AgentIOSRuntimeCatalogDataDelegate(
      maximumBytes: AgentIOSRuntimePackCatalogStore.maximumCatalogBytes,
      isCancelled: {
        (try? checkpoint()) != nil ? false : true
      }
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 60
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let task = session.dataTask(with: request)
    task.resume()
    delegate.wait()
    session.invalidateAndCancel()
    try checkpoint()
    if let error = delegate.error { throw error }
    let data = delegate.data
    guard let response = delegate.response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode),
          let finalURL = response.url,
          (try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(finalURL.absoluteString)) != nil,
          !data.isEmpty,
          data.count <= AgentIOSRuntimePackCatalogStore.maximumCatalogBytes else {
      throw AgentRuntimePackArchiveError("Runtime catalog response is invalid")
    }
    return data
  }
}

private final class AgentIOSRuntimeCatalogDataDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
  let maximumBytes: Int
  let isCancelled: () -> Bool
  let semaphore = DispatchSemaphore(value: 0)
  var data = Data()
  var response: URLResponse?
  var error: Error?

  init(maximumBytes: Int, isCancelled: @escaping () -> Bool) {
    self.maximumBytes = maximumBytes
    self.isCancelled = isCancelled
  }

  func wait() { semaphore.wait() }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    self.response = response
    if response.expectedContentLength > Int64(maximumBytes) || isCancelled() {
      dataTask.cancel()
      completionHandler(.cancel)
    } else {
      completionHandler(.allow)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard !isCancelled(), self.data.count <= maximumBytes - data.count else {
      dataTask.cancel()
      return
    }
    self.data.append(data)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let url = request.url,
          (try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(url.absoluteString)) != nil else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    response = task.response ?? response
    self.error = error
    semaphore.signal()
  }
}
