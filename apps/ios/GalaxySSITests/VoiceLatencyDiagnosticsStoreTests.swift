import XCTest
@testable import GalaxySSI

final class VoiceLatencyDiagnosticsStoreTests: XCTestCase {
  func testFileStorePersistsSanitizedEventsAcrossInstances() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("voice_latency_v1.jsonl")
    let store = FileVoiceTraceEventStore(fileURL: fileURL)
    store.append(
      event(
        traceId: "trace-1",
        name: VoiceTraceEvents.sessionFailed,
        elapsedNs: 100,
        attributes: [
          "error_code": "SIGSEGV",
          "prompt": "private command",
        ]
      )
    )

    let reloaded = FileVoiceTraceEventStore(fileURL: fileURL).snapshot()

    XCTAssertEqual(reloaded.count, 1)
    XCTAssertEqual(reloaded.first?.traceId, "trace-1")
    XCTAssertEqual(reloaded.first?.attributes["error_code"], "SIGSEGV")
    XCTAssertNil(reloaded.first?.attributes["prompt"])
  }

  func testFileStoreRotatesAndKeepsBoundedSnapshot() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("voice_latency_v1.jsonl")
    let rotatedURL = root.appendingPathComponent("voice_latency_v1.previous.jsonl")
    let store = FileVoiceTraceEventStore(
      fileURL: fileURL,
      rotatedFileURL: rotatedURL,
      maxEvents: 2,
      rotationByteLimit: 1
    )

    store.append(event(traceId: "trace-1", name: VoiceTraceEvents.sessionCreated, elapsedNs: 1))
    store.append(event(traceId: "trace-2", name: VoiceTraceEvents.sessionCreated, elapsedNs: 2))
    store.append(event(traceId: "trace-3", name: VoiceTraceEvents.sessionCreated, elapsedNs: 3))

    XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedURL.path))
    XCTAssertEqual(store.snapshot().map(\.traceId), ["trace-2", "trace-3"])
  }

  func testContentFreeDiagnosticsExportUsesAndroidWireNames() throws {
    var elapsedNs: Int64 = 0
    let tracer = VoiceLatencyTracer(
      elapsedSource: {
        elapsedNs += 50_000_000
        return elapsedNs
      },
      wallClockSource: { 123 },
      sink: InMemoryVoiceTraceEventSink()
    )
    let traceId = tracer.startSession(attributes: ["prompt": "private", "ios_version": "15.0"])
    tracer.record(traceId: traceId, event: VoiceTraceEvents.modelRequestStarted)
    tracer.record(traceId: traceId, event: VoiceTraceEvents.modelFirstDelta)
    tracer.record(traceId: traceId, event: VoiceTraceEvents.sessionCompleted)

    let export = VoiceLatencyDiagnosticsExporter.contentFreeDiagnostics(
      tracer: tracer,
      generatedAtMs: 456
    )
    let data = try JSONEncoder().encode(export)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertEqual(object?["schema"] as? String, VoiceLatencyDiagnosticsExport.schemaVersion)
    XCTAssertEqual(object?["feature_flag"] as? String, voiceLatencyTraceFlag)
    XCTAssertEqual(object?["content_included"] as? Bool, false)
    XCTAssertEqual((object?["generated_at_ms"] as? NSNumber)?.int64Value, 456)
    XCTAssertNotNil(object?["summary"])
    XCTAssertNotNil(object?["events"])
    XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("private") ?? true)
  }

  func testExporterWritesContentFreeDiagnosticsFile() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outputURL = root.appendingPathComponent("diagnostics/export.json")
    let tracer = VoiceLatencyTracer(
      elapsedSource: { 1 },
      wallClockSource: { 2 },
      sink: InMemoryVoiceTraceEventSink()
    )
    let traceId = tracer.startSession()
    tracer.record(traceId: traceId, event: VoiceTraceEvents.sessionCompleted)

    let writtenURL = try VoiceLatencyDiagnosticsExporter.exportContentFreeDiagnostics(
      to: outputURL,
      tracer: tracer,
      generatedAtMs: 789
    )
    let data = try Data(contentsOf: writtenURL)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let events = object?["events"] as? [[String: Any]]

    XCTAssertEqual(writtenURL, outputURL)
    XCTAssertEqual(object?["content_included"] as? Bool, false)
    XCTAssertEqual(events?.last?["event"] as? String, VoiceTraceEvents.sessionCompleted)
  }

  private func event(
    traceId: String,
    name: String,
    elapsedNs: Int64,
    attributes: [String: String] = [:]
  ) -> VoiceTraceEvent {
    VoiceTraceEvent(
      traceId: traceId,
      sessionId: traceId,
      event: name,
      elapsedRealtimeNs: elapsedNs,
      wallClockMs: elapsedNs / 1_000_000,
      attributes: VoiceTracePrivacy.sanitizeAttributes(attributes)
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoiceLatencyDiagnosticsStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
