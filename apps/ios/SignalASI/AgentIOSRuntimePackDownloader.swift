import CryptoKit
import Foundation

struct AgentIOSRuntimePackDownloadProgress: Equatable {
  var downloadedBytes: Int64
  var totalBytes: Int64
  var resumed: Bool
}

struct AgentIOSRuntimePackDownloadError: LocalizedError, Equatable {
  var message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

final class AgentIOSRuntimePackDownloader {
  private let downloadsRootURL: URL
  private let fileManager: FileManager
  private let sessionConfiguration: URLSessionConfiguration

  init(
    runtimeRootURL: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),
    fileManager: FileManager = .default,
    sessionConfiguration: URLSessionConfiguration = .ephemeral
  ) {
    self.downloadsRootURL = runtimeRootURL.appendingPathComponent("downloads", isDirectory: true)
    self.fileManager = fileManager
    sessionConfiguration.timeoutIntervalForRequest = 20
    sessionConfiguration.timeoutIntervalForResource = 60 * 60
    self.sessionConfiguration = sessionConfiguration
  }

  func download(
    entry: AgentRuntimePackCatalogEntry,
    from sourceURL: String,
    isCancelled: @escaping () -> Bool = { false },
    onProgress: (AgentIOSRuntimePackDownloadProgress) -> Void = {}
  ) throws -> URL {
    guard entry.archiveSizeBytes > 0,
          entry.archiveSizeBytes <= AgentRuntimePackArchiveReader.maximumArchiveBytes,
          entry.archiveSha256.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil,
          let validated = try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(sourceURL),
          let url = validated.url else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download metadata is invalid")
    }
    try fileManager.createDirectory(at: downloadsRootURL, withIntermediateDirectories: true)
    let baseName = "\(entry.packId)-\(entry.version)-\(entry.architecture)-\(entry.archiveSha256.prefix(12))"
    let completed = downloadsRootURL.appendingPathComponent("\(baseName).sarpack", isDirectory: false)
    if try isValidArchive(completed, expectedSize: entry.archiveSizeBytes, expectedSha256: entry.archiveSha256) {
      onProgress(AgentIOSRuntimePackDownloadProgress(
        downloadedBytes: entry.archiveSizeBytes,
        totalBytes: entry.archiveSizeBytes,
        resumed: false
      ))
      return completed
    }
    try? fileManager.removeItem(at: completed)
    guard !isCancelled() else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download was cancelled")
    }

    onProgress(AgentIOSRuntimePackDownloadProgress(
      downloadedBytes: 0,
      totalBytes: entry.archiveSizeBytes,
      resumed: false
    ))
    let temporary = try downloadToTemporaryFile(
      url: url,
      expectedBytes: entry.archiveSizeBytes,
      isCancelled: isCancelled,
      onProgress: { downloaded in
        onProgress(AgentIOSRuntimePackDownloadProgress(
          downloadedBytes: downloaded,
          totalBytes: entry.archiveSizeBytes,
          resumed: false
        ))
      }
    )
    defer { try? fileManager.removeItem(at: temporary) }
    guard try fileSize(temporary) == entry.archiveSizeBytes else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download size does not match the signed catalog")
    }
    let digest = try sha256(file: temporary)
    guard digest.caseInsensitiveCompare(entry.archiveSha256) == .orderedSame else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download integrity check failed")
    }
    if fileManager.fileExists(atPath: completed.path) {
      try fileManager.removeItem(at: completed)
    }
    try fileManager.moveItem(at: temporary, to: completed)
    return completed
  }

  private func downloadToTemporaryFile(
    url: URL,
    expectedBytes: Int64,
    isCancelled: @escaping () -> Bool,
    onProgress: @escaping (Int64) -> Void
  ) throws -> URL {
    let delegate = AgentIOSRuntimePackDownloadDelegate(
      expectedBytes: expectedBytes,
      isCancelled: isCancelled,
      onProgress: onProgress
    )
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: delegate,
      delegateQueue: nil
    )
    var request = URLRequest(url: url)
    request.setValue("application/vnd.signalasi.runtime-pack+zip", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let task = session.downloadTask(with: request)
    task.resume()
    delegate.wait()
    session.invalidateAndCancel()
    func cleanupTemporaryFile() {
      if let temporaryURL = delegate.temporaryURL {
        try? FileManager.default.removeItem(at: temporaryURL)
      }
    }
    if isCancelled() {
      cleanupTemporaryFile()
      throw AgentIOSRuntimePackDownloadError("Runtime pack download was cancelled")
    }
    if let error = delegate.error {
      cleanupTemporaryFile()
      throw error
    }
    guard let response = delegate.response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode),
          let finalURL = response.url,
          (try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(finalURL.absoluteString)) != nil else {
      cleanupTemporaryFile()
      throw AgentIOSRuntimePackDownloadError("Runtime pack download returned an invalid HTTPS response")
    }
    guard let temporaryURL = delegate.temporaryURL else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download did not produce a file")
    }
    return temporaryURL
  }

  private func isValidArchive(
    _ url: URL,
    expectedSize: Int64,
    expectedSha256: String
  ) throws -> Bool {
    guard fileManager.fileExists(atPath: url.path), try fileSize(url) == expectedSize else {
      return false
    }
    return try sha256(file: url).caseInsensitiveCompare(expectedSha256) == .orderedSame
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard let value = (attributes[.size] as? NSNumber)?.int64Value else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack file size is unavailable")
    }
    return value
  }

  private func sha256(file url: URL) throws -> String {
    guard let stream = InputStream(url: url) else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download could not be read")
    }
    stream.open()
    defer { stream.close() }
    var digest = SHA256()
    var buffer = [UInt8](repeating: 0, count: 256 * 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 {
        throw stream.streamError ?? AgentIOSRuntimePackDownloadError("Runtime pack download could not be read")
      }
      if count == 0 { break }
      digest.update(data: Data(buffer[0..<count]))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

private final class AgentIOSRuntimePackDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
  let expectedBytes: Int64
  let isCancelled: () -> Bool
  let onProgress: (Int64) -> Void
  let semaphore = DispatchSemaphore(value: 0)
  var temporaryURL: URL?
  var response: URLResponse?
  var error: Error?

  init(
    expectedBytes: Int64,
    isCancelled: @escaping () -> Bool,
    onProgress: @escaping (Int64) -> Void
  ) {
    self.expectedBytes = expectedBytes
    self.isCancelled = isCancelled
    self.onProgress = onProgress
  }

  func wait() {
    semaphore.wait()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    if isCancelled() || totalBytesWritten > expectedBytes {
      downloadTask.cancel()
      return
    }
    onProgress(totalBytesWritten)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("signalasi-runtime-\(UUID().uuidString).sarpack")
    do {
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      temporaryURL = destination
    } catch {
      self.error = error
    }
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
    response = task.response
    self.error = error
    semaphore.signal()
  }
}
