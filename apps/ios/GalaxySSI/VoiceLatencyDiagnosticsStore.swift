import Foundation

struct VoiceLatencyDiagnosticsExport: Codable, Equatable {
  static let schemaVersion = "galaxyssi.voice-latency/1.0"

  var schema: String
  var featureFlag: String
  var contentIncluded: Bool
  var generatedAtMs: Int64
  var summary: VoiceDiagnosticSummary
  var events: [VoiceTraceEvent]

  init(
    schema: String = VoiceLatencyDiagnosticsExport.schemaVersion,
    featureFlag: String = voiceLatencyTraceFlag,
    contentIncluded: Bool = false,
    generatedAtMs: Int64,
    summary: VoiceDiagnosticSummary,
    events: [VoiceTraceEvent]
  ) {
    self.schema = schema
    self.featureFlag = featureFlag
    self.contentIncluded = contentIncluded
    self.generatedAtMs = generatedAtMs
    self.summary = summary
    self.events = events
  }

  enum CodingKeys: String, CodingKey {
    case schema
    case featureFlag = "feature_flag"
    case contentIncluded = "content_included"
    case generatedAtMs = "generated_at_ms"
    case summary
    case events
  }
}

final class FileVoiceTraceEventStore: VoiceTraceEventSink {
  private let lock = NSLock()
  private let fileURL: URL
  private let rotatedFileURL: URL
  private let fileManager: FileManager
  private let maxEvents: Int
  private let rotationByteLimit: Int64
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var pending: [VoiceTraceEvent] = []

  init(
    fileURL: URL = FileVoiceTraceEventStore.defaultFileURL(),
    rotatedFileURL: URL? = nil,
    fileManager: FileManager = .default,
    maxEvents: Int = 8_000,
    rotationByteLimit: Int64 = 2 * 1024 * 1024
  ) {
    self.fileURL = fileURL
    self.rotatedFileURL = rotatedFileURL ?? FileVoiceTraceEventStore.defaultRotatedFileURL(fileURL: fileURL)
    self.fileManager = fileManager
    self.maxEvents = max(1, maxEvents)
    self.rotationByteLimit = max(1, rotationByteLimit)
    self.encoder = JSONEncoder.voiceLatencyDiagnostics
    self.decoder = JSONDecoder()
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("diagnostics", isDirectory: true)
      .appendingPathComponent("voice_latency_v1.jsonl")
  }

  static func defaultRotatedFileURL(fileURL: URL = defaultFileURL()) -> URL {
    fileURL
      .deletingLastPathComponent()
      .appendingPathComponent("voice_latency_v1.previous.jsonl")
  }

  static func destroyPersistentStore(
    fileURL: URL = defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    let rotatedFileURL = defaultRotatedFileURL(fileURL: fileURL)
    [fileURL, rotatedFileURL].forEach { url in
      if fileManager.fileExists(atPath: url.path) {
        try? fileManager.removeItem(at: url)
      }
    }
  }

  func append(_ event: VoiceTraceEvent) {
    lock.lock()
    defer { lock.unlock() }
    pending.append(event)
    trimPending()
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try rotateIfNeeded()
      try appendLine(event)
      let key = eventKey(event)
      pending.removeAll { eventKey($0) == key }
    } catch {
      trimPending()
    }
  }

  func snapshot() -> [VoiceTraceEvent] {
    lock.lock()
    defer { lock.unlock() }
    return deduplicateAndLimit(loadPersistedEvents() + pending)
  }

  private func rotateIfNeeded() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    guard let size = attributes[.size] as? NSNumber,
          size.int64Value >= rotationByteLimit else {
      return
    }
    if fileManager.fileExists(atPath: rotatedFileURL.path) {
      try fileManager.removeItem(at: rotatedFileURL)
    }
    try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
  }

  private func appendLine(_ event: VoiceTraceEvent) throws {
    var data = try encoder.encode(event)
    data.append(Data("\n".utf8))
    if fileManager.fileExists(atPath: fileURL.path) {
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { handle.closeFile() }
      handle.seekToEndOfFile()
      handle.write(data)
    } else {
      try data.write(to: fileURL, options: .atomic)
    }
  }

  private func loadPersistedEvents() -> [VoiceTraceEvent] {
    [rotatedFileURL, fileURL].flatMap { url -> [VoiceTraceEvent] in
      guard fileManager.fileExists(atPath: url.path),
            let raw = try? String(contentsOf: url, encoding: .utf8) else {
        return []
      }
      return raw
        .components(separatedBy: .newlines)
        .compactMap { line in
          guard !line.isEmpty,
                let data = line.data(using: .utf8),
                let decoded = try? decoder.decode(VoiceTraceEvent.self, from: data) else {
            return nil
          }
          return sanitize(decoded)
        }
    }
  }

  private func sanitize(_ event: VoiceTraceEvent) -> VoiceTraceEvent? {
    guard let traceId = VoiceTracePrivacy.safeIdentifier(event.traceId),
          let safeEvent = VoiceTracePrivacy.safeEvent(event.event) else {
      return nil
    }
    return VoiceTraceEvent(
      traceId: traceId,
      sessionId: VoiceTracePrivacy.safeIdentifier(event.sessionId) ?? traceId,
      event: safeEvent,
      elapsedRealtimeNs: max(0, event.elapsedRealtimeNs),
      wallClockMs: max(0, event.wallClockMs),
      attributes: VoiceTracePrivacy.sanitizeAttributes(event.attributes)
    )
  }

  private func trimPending() {
    if pending.count > maxEvents {
      pending.removeFirst(pending.count - maxEvents)
    }
  }

  private func deduplicateAndLimit(_ events: [VoiceTraceEvent]) -> [VoiceTraceEvent] {
    var seen: Set<String> = []
    var deduplicated: [VoiceTraceEvent] = []
    for event in events {
      guard seen.insert(eventKey(event)).inserted else { continue }
      deduplicated.append(event)
    }
    guard deduplicated.count > maxEvents else { return deduplicated }
    return Array(deduplicated.suffix(maxEvents))
  }

  private func eventKey(_ event: VoiceTraceEvent) -> String {
    "\(event.traceId):\(event.event):\(event.elapsedRealtimeNs)"
  }
}

enum VoiceLatencyDiagnosticsExporter {
  static func contentFreeDiagnostics(
    tracer: VoiceLatencyTracer = VoiceLatencyTelemetry.tracer(),
    generatedAtMs: Int64 = VoiceLatencyTelemetry.currentWallClockMs()
  ) -> VoiceLatencyDiagnosticsExport {
    VoiceLatencyDiagnosticsExport(
      generatedAtMs: generatedAtMs,
      summary: tracer.diagnosticSummary(),
      events: tracer.snapshot()
    )
  }

  static func defaultExportURL(
    generatedAtMs: Int64 = VoiceLatencyTelemetry.currentWallClockMs(),
    cacheRootURL: URL? = nil,
    fileManager: FileManager = .default
  ) -> URL {
    let root = cacheRootURL ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
      URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    return root
      .appendingPathComponent("diagnostics", isDirectory: true)
      .appendingPathComponent("voice_latency_\(generatedAtMs).json")
  }

  @discardableResult
  static func exportContentFreeDiagnostics(
    to fileURL: URL? = nil,
    tracer: VoiceLatencyTracer = VoiceLatencyTelemetry.tracer(),
    generatedAtMs: Int64 = VoiceLatencyTelemetry.currentWallClockMs(),
    fileManager: FileManager = .default
  ) throws -> URL {
    let outputURL = fileURL ?? defaultExportURL(generatedAtMs: generatedAtMs, fileManager: fileManager)
    try fileManager.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder.voiceLatencyDiagnosticsPretty.encode(
      contentFreeDiagnostics(tracer: tracer, generatedAtMs: generatedAtMs)
    )
    try data.write(to: outputURL, options: .atomic)
    return outputURL
  }
}

private extension JSONEncoder {
  static var voiceLatencyDiagnostics: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  static var voiceLatencyDiagnosticsPretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
