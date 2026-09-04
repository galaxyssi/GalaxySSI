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
    onProgress: @escaping (AgentIOSRuntimePackDownloadProgress) -> Void = { _ in }
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
    let partial = downloadsRootURL.appendingPathComponent("\(baseName).partial", isDirectory: false)
    let metadata = downloadsRootURL.appendingPathComponent("\(baseName).partial.json", isDirectory: false)

    if try isValidArchive(completed, expectedSize: entry.archiveSizeBytes, expectedSha256: entry.archiveSha256) {
      onProgress(AgentIOSRuntimePackDownloadProgress(
        downloadedBytes: entry.archiveSizeBytes,
        totalBytes: entry.archiveSizeBytes,
        resumed: false
      ))
      return completed
    }
    try? fileManager.removeItem(at: completed)

    let saved = readResumeMetadata(metadata)
    if saved == nil || saved?.url != url.absoluteString ||
      saved?.sha256.caseInsensitiveCompare(entry.archiveSha256) != .orderedSame ||
      saved?.totalBytes != entry.archiveSizeBytes {
      resetPartial(partial, metadata: metadata)
    }
    var offset = (try? fileSize(partial)) ?? 0
    if offset > entry.archiveSizeBytes {
      resetPartial(partial, metadata: metadata)
      offset = 0
    }
    if offset == entry.archiveSizeBytes,
       try isValidArchive(partial, expectedSize: entry.archiveSizeBytes, expectedSha256: entry.archiveSha256) {
      try finalize(partial: partial, completed: completed, metadata: metadata)
      onProgress(AgentIOSRuntimePackDownloadProgress(
        downloadedBytes: entry.archiveSizeBytes,
        totalBytes: entry.archiveSizeBytes,
        resumed: true
      ))
      return completed
    }
    try ensureFreeSpace(requiredBytes: entry.archiveSizeBytes - offset)
    var resumed = offset > 0
    var restartAllowed = true
    var etag = readResumeMetadata(metadata)?.etag ?? ""
    onProgress(AgentIOSRuntimePackDownloadProgress(
      downloadedBytes: offset,
      totalBytes: entry.archiveSizeBytes,
      resumed: resumed
    ))

    while true {
      guard !isCancelled() else {
        throw AgentIOSRuntimePackDownloadError("Runtime pack download was cancelled")
      }
      writeResumeMetadata(
        metadata,
        value: ResumeMetadata(
          url: url.absoluteString,
          sha256: entry.archiveSha256,
          totalBytes: entry.archiveSizeBytes,
          etag: etag
        )
      )
      let response = try request(
        url: url,
        offset: offset,
        etag: etag,
        expectedBytes: entry.archiveSizeBytes,
        isCancelled: isCancelled,
        resumed: resumed,
        partial: partial,
        onProgress: { downloaded, wasResumed in
          onProgress(AgentIOSRuntimePackDownloadProgress(
            downloadedBytes: downloaded,
            totalBytes: entry.archiveSizeBytes,
            resumed: wasResumed
          ))
        }
      )

      if response.statusCode == 416 {
        if offset == entry.archiveSizeBytes,
           try isValidArchive(partial, expectedSize: entry.archiveSizeBytes, expectedSha256: entry.archiveSha256) {
          try finalize(partial: partial, completed: completed, metadata: metadata)
          return completed
        }
        guard restartAllowed else {
          throw AgentIOSRuntimePackDownloadError("Runtime pack server rejected a fresh download")
        }
        resetPartial(partial, metadata: metadata)
        offset = 0
        resumed = false
        etag = ""
        restartAllowed = false
        continue
      }

      if response.statusCode == 206 {
        guard let range = parseContentRange(response.contentRange),
              range.first == offset,
              range.total == entry.archiveSizeBytes else {
          guard restartAllowed else {
            throw AgentIOSRuntimePackDownloadError("Runtime pack server returned an invalid resume range")
          }
          resetPartial(partial, metadata: metadata)
          offset = 0
          resumed = false
          etag = ""
          restartAllowed = false
          continue
        }
      } else if response.statusCode == 200, offset > 0 {
        guard restartAllowed else {
          throw AgentIOSRuntimePackDownloadError("Runtime pack server ignored a fresh download request")
        }
        resetPartial(partial, metadata: metadata)
        offset = 0
        resumed = false
        etag = ""
        restartAllowed = false
        continue
      } else if response.statusCode < 200 || response.statusCode >= 300 {
        throw AgentIOSRuntimePackDownloadError("Runtime pack download returned HTTP \(response.statusCode)")
      }

      if offset > 0, !etag.isEmpty, !response.etag.isEmpty, etag != response.etag {
        guard restartAllowed else {
          throw AgentIOSRuntimePackDownloadError("Runtime pack changed while resuming")
        }
        resetPartial(partial, metadata: metadata)
        offset = 0
        resumed = false
        etag = ""
        restartAllowed = false
        continue
      }
      etag = response.etag
      writeResumeMetadata(
        metadata,
        value: ResumeMetadata(
          url: url.absoluteString,
          sha256: entry.archiveSha256,
          totalBytes: entry.archiveSizeBytes,
          etag: etag
        )
      )
      offset = (try? fileSize(partial)) ?? 0
      if offset == entry.archiveSizeBytes { break }
      guard offset > 0, offset < entry.archiveSizeBytes else {
        throw AgentIOSRuntimePackDownloadError("Runtime pack download ended without data")
      }
      resumed = true
    }

    guard try fileSize(partial) == entry.archiveSizeBytes else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download size does not match the signed catalog")
    }
    let digest = try sha256(file: partial)
    guard digest.caseInsensitiveCompare(entry.archiveSha256) == .orderedSame else {
      resetPartial(partial, metadata: metadata)
      throw AgentIOSRuntimePackDownloadError("Runtime pack download integrity check failed")
    }
    try finalize(partial: partial, completed: completed, metadata: metadata)
    return completed
  }

  private func request(
    url: URL,
    offset: Int64,
    etag: String,
    expectedBytes: Int64,
    isCancelled: @escaping () -> Bool,
    resumed: Bool,
    partial: URL,
    onProgress: @escaping (Int64, Bool) -> Void
  ) throws -> DownloadResponse {
    if !fileManager.fileExists(atPath: partial.path) {
      fileManager.createFile(atPath: partial.path, contents: nil)
    }
    let delegate = AgentIOSRuntimePackRangeDelegate(
      expectedBytes: expectedBytes,
      initialOffset: offset,
      partialURL: partial,
      isCancelled: isCancelled,
      onProgress: { downloaded in onProgress(downloaded, resumed) }
    )
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: delegate,
      delegateQueue: nil
    )
    var request = URLRequest(url: url)
    request.setValue("application/vnd.galaxyssi.runtime-pack+zip", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    if offset > 0 {
      request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
      if !etag.isEmpty {
        request.setValue(etag, forHTTPHeaderField: "If-Range")
      }
    }
    let task = session.dataTask(with: request)
    task.resume()
    delegate.wait()
    session.invalidateAndCancel()
    if isCancelled() {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download was cancelled")
    }
    if let error = delegate.error {
      throw error
    }
    guard let response = delegate.response else {
      throw AgentIOSRuntimePackDownloadError("Runtime pack download returned no response")
    }
    return DownloadResponse(
      statusCode: response.statusCode,
      etag: response.value(forHTTPHeaderField: "ETag")?.prefix(512).description ?? "",
      contentRange: response.value(forHTTPHeaderField: "Content-Range")
    )
  }

  private func finalize(partial: URL, completed: URL, metadata: URL) throws {
    if fileManager.fileExists(atPath: completed.path) {
      try fileManager.removeItem(at: completed)
    }
    try fileManager.moveItem(at: partial, to: completed)
    try? fileManager.removeItem(at: metadata)
  }

  private func resetPartial(_ partial: URL, metadata: URL) {
    try? fileManager.removeItem(at: partial)
    try? fileManager.removeItem(at: metadata)
  }

  private func readResumeMetadata(_ url: URL) -> ResumeMetadata? {
    guard let data = try? Data(contentsOf: url),
          data.count <= 64 * 1_024 else { return nil }
    return try? JSONDecoder().decode(ResumeMetadata.self, from: data)
  }

  private func writeResumeMetadata(_ url: URL, value: ResumeMetadata) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
    do {
      try data.write(to: temporary, options: [.atomic])
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
      try fileManager.moveItem(at: temporary, to: url)
    } catch {
      try? fileManager.removeItem(at: temporary)
    }
  }

  private func ensureFreeSpace(requiredBytes: Int64) throws {
    let attributes = try fileManager.attributesOfFileSystem(forPath: downloadsRootURL.path)
    let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    let minimumFreeBytes: Int64 = 256 * 1_024 * 1_024
    guard available >= requiredBytes + minimumFreeBytes else {
      throw AgentIOSRuntimePackDownloadError("Not enough storage to download the runtime pack")
    }
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

  private func parseContentRange(_ value: String?) -> ContentRange? {
    guard let value,
          let match = value.range(of: #"^bytes ([0-9]+)-([0-9]+)/([0-9]+)$"#, options: .regularExpression) else {
      return nil
    }
    let numbers = value[match].split { $0 == " " || $0 == "-" || $0 == "/" }
      .dropFirst()
      .compactMap { Int64(String($0)) }
    guard numbers.count == 3,
          numbers[0] >= 0,
          numbers[1] >= numbers[0],
          numbers[2] > numbers[1] else { return nil }
    return ContentRange(first: numbers[0], last: numbers[1], total: numbers[2])
  }

  private struct ResumeMetadata: Codable {
    var url: String
    var sha256: String
    var totalBytes: Int64
    var etag: String
  }

  private struct ContentRange {
    var first: Int64
    var last: Int64
    var total: Int64
  }

  private struct DownloadResponse {
    var statusCode: Int
    var etag: String
    var contentRange: String?
  }
}

private final class AgentIOSRuntimePackRangeDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
  let expectedBytes: Int64
  let initialOffset: Int64
  let partialURL: URL
  let isCancelled: () -> Bool
  let onProgress: (Int64) -> Void
  let semaphore = DispatchSemaphore(value: 0)
  var response: HTTPURLResponse?
  var error: Error?
  private var fileHandle: FileHandle?
  private var downloadedBytes: Int64

  init(
    expectedBytes: Int64,
    initialOffset: Int64,
    partialURL: URL,
    isCancelled: @escaping () -> Bool,
    onProgress: @escaping (Int64) -> Void
  ) {
    self.expectedBytes = expectedBytes
    self.initialOffset = initialOffset
    self.partialURL = partialURL
    self.isCancelled = isCancelled
    self.onProgress = onProgress
    self.downloadedBytes = initialOffset
  }

  func wait() { semaphore.wait() }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse,
          let finalURL = http.url,
          (try? AgentRuntimePackCatalogPolicy.validateHTTPSURL(finalURL.absoluteString)) != nil else {
      error = AgentIOSRuntimePackDownloadError("Runtime pack download returned an invalid HTTPS response")
      dataTask.cancel()
      completionHandler(.cancel)
      return
    }
    self.response = http
    guard http.statusCode == 416 else {
      guard (200..<300).contains(http.statusCode) else {
        error = AgentIOSRuntimePackDownloadError("Runtime pack download returned HTTP \(http.statusCode)")
        dataTask.cancel()
        completionHandler(.cancel)
        return
      }
      let expectedBodyBytes = http.statusCode == 206 ? expectedBytes - initialOffset : expectedBytes
      if http.expectedContentLength > expectedBodyBytes && http.expectedContentLength >= 0 {
        error = AgentIOSRuntimePackDownloadError("Runtime pack download exceeds its signed size")
        dataTask.cancel()
        completionHandler(.cancel)
        return
      }
      do {
        fileHandle = try FileHandle(forWritingTo: partialURL)
        if http.statusCode == 206 && initialOffset > 0 {
          try fileHandle?.seekToEnd()
        } else {
          try fileHandle?.truncate(atOffset: 0)
          downloadedBytes = 0
        }
      } catch {
        self.error = error
        dataTask.cancel()
        completionHandler(.cancel)
        return
      }
      completionHandler(.allow)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard !isCancelled() else {
      dataTask.cancel()
      return
    }
    let next = downloadedBytes + Int64(data.count)
    guard next <= expectedBytes else {
      error = AgentIOSRuntimePackDownloadError("Runtime pack download exceeds its signed size")
      dataTask.cancel()
      return
    }
    fileHandle?.write(data)
    downloadedBytes = next
    onProgress(downloadedBytes)
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
    try? fileHandle?.close()
    if self.error == nil {
      self.error = error
    }
    semaphore.signal()
  }
}
