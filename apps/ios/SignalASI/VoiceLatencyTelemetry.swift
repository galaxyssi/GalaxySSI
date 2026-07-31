import Foundation

enum VoiceLatencyTelemetry {
  private static let lock = NSLock()
  private static var runtimeTracer: VoiceLatencyTracer?

  static func tracer() -> VoiceLatencyTracer {
    lock.lock()
    defer { lock.unlock() }
    if let runtimeTracer = runtimeTracer {
      return runtimeTracer
    }
    let tracer = VoiceLatencyTracer(
      elapsedSource: {
        Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
      },
      wallClockSource: {
        currentWallClockMs()
      },
      enabled: {
        VoiceLatencyFeatureFlags.isEnabled()
      },
      sink: FileVoiceTraceEventStore()
    )
    runtimeTracer = tracer
    return tracer
  }

  static func startSession(attributes: [String: String] = [:]) -> String {
    guard VoiceLatencyFeatureFlags.isEnabled() else { return "" }
    return tracer().startSession(attributes: deviceAttributes().merging(attributes) { _, incoming in incoming })
  }

  @discardableResult
  static func record(
    traceId: String,
    event: String,
    attributes: [String: String] = [:],
    once: Bool = false
  ) -> VoiceTraceEvent? {
    tracer().record(
      traceId: traceId,
      sessionId: traceId,
      event: event,
      attributes: attributes,
      once: once
    )
  }

  static func contentFreeDiagnostics(
    generatedAtMs: Int64 = currentWallClockMs()
  ) -> VoiceLatencyDiagnosticsExport {
    VoiceLatencyDiagnosticsExporter.contentFreeDiagnostics(
      tracer: tracer(),
      generatedAtMs: generatedAtMs
    )
  }

  @discardableResult
  static func exportContentFreeDiagnostics(
    to fileURL: URL? = nil,
    generatedAtMs: Int64 = currentWallClockMs(),
    fileManager: FileManager = .default
  ) throws -> URL {
    try VoiceLatencyDiagnosticsExporter.exportContentFreeDiagnostics(
      to: fileURL,
      tracer: tracer(),
      generatedAtMs: generatedAtMs,
      fileManager: fileManager
    )
  }

  static func currentWallClockMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  static func resetForTests(_ tracer: VoiceLatencyTracer? = nil) {
    lock.lock()
    runtimeTracer = tracer
    lock.unlock()
  }

  private static func deviceAttributes() -> [String: String] {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    var attributes: [String: String] = [
      "ios_version": "\(version.majorVersion).\(version.minorVersion)",
      "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
    ]
    if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
       !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      attributes["native_version"] = build
    }
    return VoiceTracePrivacy.sanitizeAttributes(attributes)
  }
}
