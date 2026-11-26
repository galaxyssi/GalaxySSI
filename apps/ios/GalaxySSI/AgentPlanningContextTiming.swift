import CryptoKit
import Foundation
import OSLog

enum AgentPlanningContextTiming {
  struct Sample: Equatable {
    let turnHash: String
    let metadataMillis: Int64
    let historyMillis: Int64
    let globalMillis: Int64
    let assemblyMillis: Int64
    let totalMillis: Int64
    let clockValid: Bool
  }
  private static let logger = Logger(subsystem: "com.galaxyssi.ios", category: "planning-context-latency")

  static func monotonicMillis() -> Int64 {
    Int64(clamping: DispatchTime.now().uptimeNanoseconds / 1_000_000)
  }

  static func sample(turnId: String, started: Int64, metadataRead: Int64, historyRead: Int64,
    globalRead: Int64, finished: Int64) -> Sample {
    let valid = started >= 0 && metadataRead >= started && historyRead >= metadataRead &&
      globalRead >= historyRead && finished >= globalRead
    return Sample(turnHash: SHA256.hash(data: Data(turnId.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined(),
      metadataMillis: valid ? metadataRead - started : 0,
      historyMillis: valid ? historyRead - metadataRead : 0,
      globalMillis: valid ? globalRead - historyRead : 0,
      assemblyMillis: valid ? finished - globalRead : 0,
      totalMillis: valid ? finished - started : 0, clockValid: valid)
  }

  static func log(_ sample: Sample) {
    logger.info("context_loaded turn=\(sample.turnHash, privacy: .private(mask: .hash)) metadata_ms=\(sample.metadataMillis) history_ms=\(sample.historyMillis) global_ms=\(sample.globalMillis) assembly_ms=\(sample.assemblyMillis) read_ms=\(sample.totalMillis) clock_valid=\(sample.clockValid)")
  }
}
