import CryptoKit
import Foundation
import OSLog

// Successful creation diagnostics only; not a durability benchmark or UI latency.
enum AgentWorkspaceCreationTiming {
  enum Storage: String { case snapshot, indexedTransaction = "indexed_transaction" }
  struct Sample: Equatable {
    let taskHash: String
    let preparationMillis: Int64
    let commitMillis: Int64
    let storage: Storage
  }
  typealias Sink = (Sample) -> Void
  private static let logger = Logger(subsystem: "com.galaxyssi.ios", category: "workspace-latency")

  static func sample(taskId: String, started: Int64, commitStarted: Int64, committed: Int64,
    storage: Storage = .snapshot) -> Sample {
    Sample(taskHash: SHA256.hash(data: Data(taskId.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined(),
      preparationMillis: elapsed(from: started, to: commitStarted),
      commitMillis: elapsed(from: commitStarted, to: committed), storage: storage)
  }

  private static func elapsed(from start: Int64, to end: Int64) -> Int64 {
    let delta = end.subtractingReportingOverflow(start)
    return end <= start ? 0 : (delta.overflow ? Int64.max : delta.partialValue)
  }

  static func monotonicMillis() -> Int64 {
    Int64(clamping: DispatchTime.now().uptimeNanoseconds / 1_000_000)
  }

  static func log(_ sample: Sample) {
    if sample.storage == .indexedTransaction {
      logger.info("workspace_create task=\(sample.taskHash, privacy: .private(mask: .hash)) prepare_ms=\(sample.preparationMillis) commit_ms=\(sample.commitMillis) indexed_transactions=1")
      return
    }
    logger.info("workspace_create task=\(sample.taskHash, privacy: .private(mask: .hash)) prepare_ms=\(sample.preparationMillis) commit_ms=\(sample.commitMillis) snapshot_writes=1")
  }
}
