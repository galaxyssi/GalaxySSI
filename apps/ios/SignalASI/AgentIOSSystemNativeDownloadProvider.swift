import Foundation

protocol AgentIOSDownloadManaging {
  func enqueueDownload(
    url: String,
    title: String,
    description: String,
    context: AgentIOSDownloadContext,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult
  func queryDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func removeDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDownloadContext {
  var contactId: String
  var conversationId: String
  var turnId: String
  var languageTag: String

  init(contactId: String = "", conversationId: String = "", turnId: String = "", languageTag: String = "") {
    self.contactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.turnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.languageTag = languageTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

struct AgentIOSDownloadCompletion {
  var id: Int64
  var succeeded: Bool
  var title: String
  var reason: Int64
  var bytesDownloaded: Int64
  var totalBytes: Int64
  var localFileURL: URL?
  var mediaType: String
  var contactId: String
  var conversationId: String
  var turnId: String
  var languageTag: String
}

protocol AgentIOSDownloadCompletionReporting: AnyObject {
  func setCompletionHandler(_ handler: @escaping (AgentIOSDownloadCompletion) -> Void)
  func pendingCompletions() -> [AgentIOSDownloadCompletion]
  func markCompletionDelivered(id: Int64, nowMillis: Int64)
}

private final class AgentIOSDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
  weak var owner: AgentIOSDefaultDownloadProvider?

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    owner?.backgroundDownloadFinished(task: downloadTask, location: location)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    owner?.backgroundDownloadCompleted(task: task, error: error)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    owner?.backgroundSessionDidFinishEvents()
  }
}

final class AgentIOSDefaultDownloadProvider: AgentIOSDownloadManaging, AgentIOSDownloadCompletionReporting {
  static let shared = AgentIOSDefaultDownloadProvider()
  static let backgroundSessionIdentifier = "com.signalasi.chat.ios.agent-downloads"

  private struct DownloadRecord: Codable {
    var id: Int64
    var url: String
    var title: String
    var description: String
    var status: Int64
    var reason: Int64
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var localFileURL: URL?
    var mediaType: String
    var createdAtEpochMillis: Int64
    var updatedAtEpochMillis: Int64
    var contactId: String?
    var conversationId: String?
    var turnId: String?
    var languageTag: String?
    var completionDeliveredAtEpochMillis: Int64?

    func output(observedAtEpochMillis: Int64) -> AgentMcpJSONObject {
      [
        "download_id": .int(id),
        "url": .string(url),
        "status": .int(status),
        "reason": .int(reason),
        "bytes_downloaded": .int(bytesDownloaded),
        "total_bytes": .int(totalBytes),
        "local_uri": .string(localFileURL?.absoluteString ?? ""),
        "media_type": .string(mediaType),
        "title": .string(title),
        "description": .string(description),
        "platform": .string("ios"),
        "scope": .string("ios_app_cache_download"),
        "created_at_epoch_ms": .int(createdAtEpochMillis),
        "updated_at_epoch_ms": .int(updatedAtEpochMillis),
        "observed_at_epoch_ms": .int(observedAtEpochMillis)
      ]
    }
  }

  private struct PersistentState: Codable {
    var nextId: Int64
    var records: [DownloadRecord]
  }

  private enum Status {
    static let pending: Int64 = 1
    static let running: Int64 = 2
    static let paused: Int64 = 4
    static let successful: Int64 = 8
    static let failed: Int64 = 16
  }

  private let queue = DispatchQueue(label: "signalasi.ios.system.downloads")
  private let session: URLSession
  private let sessionDelegate: AgentIOSDownloadSessionDelegate?
  private let storageDirectory: URL
  private let stateURL: URL
  private var nextId: Int64 = 1
  private var records: [Int64: DownloadRecord] = [:]
  private var tasks: [Int64: URLSessionDownloadTask] = [:]
  private var completionHandler: ((AgentIOSDownloadCompletion) -> Void)?
  private var backgroundCompletionHandler: (() -> Void)?

  init(
    session: URLSession? = nil,
    storageDirectory: URL? = nil
  ) {
    if let session {
      self.session = session
      self.sessionDelegate = nil
    } else {
      let delegate = AgentIOSDownloadSessionDelegate()
      let configuration = URLSessionConfiguration.background(
        withIdentifier: Self.backgroundSessionIdentifier
      )
      configuration.sessionSendsLaunchEvents = true
      configuration.discretionary = false
      configuration.allowsCellularAccess = true
      if #available(iOS 13.0, *) {
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
      }
      self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
      self.sessionDelegate = delegate
    }
    if let storageDirectory {
      self.storageDirectory = storageDirectory
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      self.storageDirectory = base.appendingPathComponent("SignalASIDownloads", isDirectory: true)
    }
    self.stateURL = self.storageDirectory.appendingPathComponent("downloads.json", isDirectory: false)
    queue.sync {
      restoreStateLocked()
    }
    sessionDelegate?.owner = self
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      self.queue.async {
        tasks.compactMap { task -> (Int64, URLSessionDownloadTask)? in
          guard let downloadTask = task as? URLSessionDownloadTask,
                let id = self.downloadID(for: downloadTask) else {
            return nil
          }
          return (id, downloadTask)
        }.forEach { id, task in
          self.tasks[id] = task
        }
      }
    }
  }

  func handleBackgroundEvents(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == Self.backgroundSessionIdentifier else {
      completionHandler()
      return
    }
    queue.async {
      self.backgroundCompletionHandler = completionHandler
    }
  }

  func enqueueDownload(
    url: String,
    title: String,
    description: String,
    context: AgentIOSDownloadContext,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    let suppliedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let downloadURL = AgentIOSPublicDownloadPolicy.normalizeHTTPSURL(suppliedURL) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_download_url",
        message: "A valid public HTTPS download URL is required"
      )
    }

    let downloadId = queue.sync { () -> Int64 in
      let id = nextId
      nextId += 1
      records[id] = DownloadRecord(
        id: id,
        url: downloadURL.absoluteString,
        title: bounded(title, 240),
        description: bounded(description, 500),
        status: Status.pending,
        reason: 0,
        bytesDownloaded: 0,
        totalBytes: -1,
        localFileURL: nil,
        mediaType: "",
        createdAtEpochMillis: nowMillis,
        updatedAtEpochMillis: nowMillis,
        contactId: context.contactId.nilIfEmpty,
        conversationId: context.conversationId.nilIfEmpty,
        turnId: context.turnId.nilIfEmpty,
        languageTag: context.languageTag.nilIfEmpty,
        completionDeliveredAtEpochMillis: nil
      )
      persistLocked()
      return id
    }

    var request = URLRequest(url: downloadURL)
    for (name, value) in AgentIOSPublicArticleRequestPolicy.headers(for: downloadURL) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    let task: URLSessionDownloadTask
    if sessionDelegate != nil {
      task = session.downloadTask(with: request)
      task.taskDescription = String(downloadId)
    } else {
      task = session.downloadTask(with: request) { [weak self] temporaryURL, response, error in
        self?.finishDownload(
          id: downloadId,
          originalURL: downloadURL,
          temporaryURL: temporaryURL,
          response: response,
          error: error
        )
      }
    }
    queue.sync {
      tasks[downloadId] = task
      records[downloadId]?.status = Status.running
      records[downloadId]?.updatedAtEpochMillis = currentMillis()
      persistLocked()
    }
    task.resume()

    let record = queue.sync { records[downloadId] }
    var output = record?.output(observedAtEpochMillis: nowMillis) ?? [
        "download_id": .int(downloadId),
        "url": .string(downloadURL.absoluteString)
      ]
    output["url_normalized"] = .bool(downloadURL.absoluteString != suppliedURL)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: "Download enqueued",
      metadata: [
        "implementation": .string("URLSession"),
        "storage_scope": .string("ios_app_caches"),
        "android_status_compatible": .bool(true)
      ]
    )
  }

  func queryDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    guard id > 0 else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_download_id",
        message: "Download id must be positive."
      )
    }
    guard let record = queue.sync(execute: { records[id] }) else {
      return AgentNativeToolExecutionResult.failure(
        code: "download_not_found",
        message: "Download record was not found"
      )
    }
    return AgentNativeToolExecutionResult.success(
      output: record.output(observedAtEpochMillis: nowMillis),
      message: "Download status read",
      metadata: [
        "implementation": .string("URLSession"),
        "storage_scope": .string("ios_app_caches"),
        "android_status_compatible": .bool(true)
      ]
    )
  }

  func removeDownload(id: Int64, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    guard id > 0 else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_download_id",
        message: "Download id must be positive."
      )
    }
    let removed = queue.sync { () -> (count: Int64, task: URLSessionDownloadTask?, fileURL: URL?) in
      guard let record = records.removeValue(forKey: id) else {
        return (0, nil, nil)
      }
      persistLocked()
      return (1, tasks.removeValue(forKey: id), record.localFileURL)
    }
    removed.task?.cancel()
    if let fileURL = removed.fileURL {
      try? FileManager.default.removeItem(at: fileURL)
    }
    return AgentNativeToolExecutionResult.success(
      output: [
        "download_id": .int(id),
        "removed": .int(removed.count),
        "platform": .string("ios"),
        "scope": .string("ios_app_cache_download"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "Download remove completed",
      metadata: [
        "implementation": .string("URLSession"),
        "storage_scope": .string("ios_app_caches"),
        "file_deleted": .bool(removed.fileURL != nil)
      ]
    )
  }

  func setCompletionHandler(_ handler: @escaping (AgentIOSDownloadCompletion) -> Void) {
    queue.sync {
      completionHandler = handler
    }
    notifyPendingCompletions()
  }

  func pendingCompletions() -> [AgentIOSDownloadCompletion] {
    queue.sync {
      records.values.compactMap(completion(for:))
    }
  }

  func markCompletionDelivered(id: Int64, nowMillis: Int64) {
    queue.sync {
      guard var record = records[id], completion(for: record) != nil else { return }
      record.completionDeliveredAtEpochMillis = max(0, nowMillis)
      record.updatedAtEpochMillis = max(record.updatedAtEpochMillis, max(0, nowMillis))
      records[id] = record
      persistLocked()
    }
  }

  fileprivate func backgroundDownloadFinished(task: URLSessionDownloadTask, location: URL) {
    guard let id = downloadID(for: task),
          let originalURL = queue.sync(execute: { records[id]?.url }).flatMap(URL.init(string:)) else {
      return
    }
    finishDownload(
      id: id,
      originalURL: originalURL,
      temporaryURL: location,
      response: task.response,
      error: nil
    )
  }

  fileprivate func backgroundDownloadCompleted(task: URLSessionTask, error: Error?) {
    guard let error,
          let id = downloadID(for: task),
          let originalURL = queue.sync(execute: { records[id]?.url }).flatMap(URL.init(string:)) else {
      return
    }
    finishDownload(
      id: id,
      originalURL: originalURL,
      temporaryURL: nil,
      response: task.response,
      error: error
    )
  }

  fileprivate func backgroundSessionDidFinishEvents() {
    let handler = queue.sync { () -> (() -> Void)? in
      let handler = backgroundCompletionHandler
      backgroundCompletionHandler = nil
      return handler
    }
    guard let handler else { return }
    DispatchQueue.main.async {
      handler()
    }
  }

  private func finishDownload(
    id: Int64,
    originalURL: URL,
    temporaryURL: URL?,
    response: URLResponse?,
    error: Error?
  ) {
    queue.async {
      guard var record = self.records[id],
            record.status != Status.successful,
            record.status != Status.failed else {
        return
      }
      record.updatedAtEpochMillis = self.currentMillis()
      record.mediaType = self.bounded(response?.mimeType ?? "", 255)

      if let error {
        record.status = Status.failed
        record.reason = Int64((error as NSError).code)
        self.records[id] = record
      } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        record.status = Status.failed
        record.reason = Int64(http.statusCode)
        self.records[id] = record
      } else if temporaryURL == nil {
        record.status = Status.failed
        record.reason = -1
        self.records[id] = record
      } else if let temporaryURL {
        do {
          try FileManager.default.createDirectory(
            at: self.storageDirectory,
            withIntermediateDirectories: true
          )
          let destination = self.storageDirectory.appendingPathComponent(
            self.safeFilename(
              id: id,
              title: record.title,
              response: response,
              originalURL: originalURL
            ),
            isDirectory: false
          )
          if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
          }
          try FileManager.default.moveItem(at: temporaryURL, to: destination)
          let size = self.fileSize(destination)
          record.status = Status.successful
          record.reason = 0
          record.bytesDownloaded = size
          let expected = response?.expectedContentLength ?? -1
          record.totalBytes = expected >= 0 ? expected : size
          record.localFileURL = destination
          self.records[id] = record
        } catch {
          record.status = Status.failed
          record.reason = Int64((error as NSError).code)
          self.records[id] = record
        }
      }
      self.persistLocked()
      self.tasks.removeValue(forKey: id)
      self.notifyCompletionLocked(for: record)
    }
  }

  private func completion(for record: DownloadRecord) -> AgentIOSDownloadCompletion? {
    guard record.completionDeliveredAtEpochMillis == nil,
          record.status == Status.successful || record.status == Status.failed,
          let conversationId = record.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !conversationId.isEmpty else {
      return nil
    }
    return AgentIOSDownloadCompletion(
      id: record.id,
      succeeded: record.status == Status.successful,
      title: record.title,
      status: record.status,
      reason: record.reason,
      bytesDownloaded: record.bytesDownloaded,
      totalBytes: record.totalBytes,
      localFileURL: record.localFileURL,
      mediaType: record.mediaType,
      contactId: record.contactId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      conversationId: conversationId,
      turnId: record.turnId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      languageTag: record.languageTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    )
  }

  private func downloadID(for task: URLSessionTask) -> Int64? {
    guard let taskDescription = task.taskDescription,
          let id = Int64(taskDescription),
          id > 0 else {
      return nil
    }
    return id
  }

  private func notifyPendingCompletions() {
    let notification = queue.sync { () -> ([AgentIOSDownloadCompletion], ((AgentIOSDownloadCompletion) -> Void)?) in
      (records.values.compactMap(completion(for:)), completionHandler)
    }
    guard let handler = notification.1 else { return }
    for completion in notification.0 {
      DispatchQueue.main.async {
        handler(completion)
      }
    }
  }

  private func notifyCompletionLocked(for record: DownloadRecord) {
    guard let completion = completion(for: record), let handler = completionHandler else { return }
    DispatchQueue.main.async {
      handler(completion)
    }
  }

  private func safeFilename(
    id: Int64,
    title: String,
    response: URLResponse?,
    originalURL: URL
  ) -> String {
    let suppliedTitle = bounded(title, 160)
    let genericTitle = ["download", "signalasi download"].contains {
      $0.caseInsensitiveCompare(suppliedTitle) == .orderedSame
    }
    let sourceFilename = response?.suggestedFilename ?? originalURL.lastPathComponent
    let sourceExtension = sourceFilename.range(
      of: #"\.[A-Za-z0-9]{1,10}$"#,
      options: .regularExpression
    ).map { String(sourceFilename[$0]).lowercased() } ?? ""
    let titleExtension = suppliedTitle.range(
      of: #"\.[A-Za-z0-9]{1,10}$"#,
      options: .regularExpression
    ).map { String(suppliedTitle[$0]).lowercased() } ?? ""
    let titleHasExtension = !titleExtension.isEmpty
    let baseCandidate: String
    if !suppliedTitle.isEmpty && !genericTitle {
      baseCandidate = titleHasExtension
        ? suppliedTitle.replacingOccurrences(
          of: #"\.[A-Za-z0-9]{1,10}$"#,
          with: "",
          options: .regularExpression
        )
        : suppliedTitle
    } else if !sourceFilename.isEmpty {
      baseCandidate = sourceExtension.isEmpty
        ? sourceFilename
        : String(sourceFilename.dropLast(sourceExtension.count))
    } else {
      baseCandidate = "download"
    }
    let sanitized = bounded(baseCandidate, 160)
      .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    let base = sanitized.isEmpty ? "download" : String(sanitized.prefix(120))
    let `extension` = titleExtension.isEmpty ? sourceExtension : titleExtension
    return "download-\(id)-\(base)\(extension)"
  }

  private func fileSize(_ url: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = attributes?[.size] as? NSNumber
    return max(0, size?.int64Value ?? 0)
  }

  private func currentMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  private func restoreStateLocked() {
    guard let data = try? Data(contentsOf: stateURL),
          let state = try? JSONDecoder().decode(PersistentState.self, from: data) else {
      return
    }

    records = state.records.reduce(into: [Int64: DownloadRecord]()) { result, record in
      guard record.id > 0 else { return }
      result[record.id] = record
    }
    nextId = max(state.nextId, (records.keys.max() ?? 0) + 1, 1)

    var changed = false
    for id in records.keys {
      guard var record = records[id] else { continue }
      if record.status == Status.pending || record.status == Status.running {
        record.status = Status.paused
        record.updatedAtEpochMillis = currentMillis()
        changed = true
      }
      if let localFileURL = record.localFileURL,
         !FileManager.default.fileExists(atPath: localFileURL.path) {
        record.localFileURL = nil
        if record.status == Status.successful {
          record.status = Status.failed
          record.reason = -2
        }
        changed = true
      }
      records[id] = record
    }
    if changed {
      persistLocked()
    }
  }

  private func persistLocked() {
    let state = PersistentState(
      nextId: max(nextId, (records.keys.max() ?? 0) + 1, 1),
      records: records.values.sorted { $0.id < $1.id }
    )
    guard let data = try? JSONEncoder().encode(state) else { return }
    do {
      try FileManager.default.createDirectory(
        at: storageDirectory,
        withIntermediateDirectories: true
      )
      try data.write(to: stateURL, options: [.atomic])
    } catch {
      // Download results remain usable in memory when persistence is unavailable.
    }
  }

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
