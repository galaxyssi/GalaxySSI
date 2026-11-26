import CryptoKit
import Foundation
import OSLog

// Local diagnostics only. These spans describe provider activity, not first
// visible UI text, completed tools, accepted citations or end-to-end performance.
final class CloudModelRoundTiming {
  enum Route: String { case streaming, compatibility }
  enum Stage: String { case request, firstActivity = "first_activity", finished, citationValidation = "citation_validation" }
  enum Activity: String { case text, tool }
  enum Completion: String { case completed, failed, cancelled, interrupted }
  struct Sample: Equatable {
    let requestHash: String
    let round: Int
    let route: Route
    let finalRound: Bool
    let stage: Stage
    let elapsedMillis: Int64
    var inputCharacters: Int? = nil
    var activity: Activity? = nil
    var completion: Completion? = nil
    var requiresRepair: Bool? = nil
  }
  typealias Sink = (Sample) -> Void
  private static let logger = Logger(subsystem: "com.galaxyssi.ios", category: "web-latency")
  private let lock = NSLock()
  private let requestHash: String
  private let round: Int
  private let route: Route
  private let finalRound: Bool
  private let clock: () -> Int64
  private let sink: Sink
  private let started: Int64
  private var requested = false
  private var firstActivity = false
  private var finished = false

  init(requestId: String, round: Int, route: Route, finalRound: Bool,
    clock: @escaping () -> Int64, sink: @escaping Sink = CloudModelRoundTiming.log) {
    requestHash = SHA256.hash(data: Data(requestId.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    self.round = max(round, 0)
    self.route = route
    self.finalRound = finalRound
    self.clock = clock
    self.sink = sink
    started = clock()
  }

  func request(inputCharacters: Int) {
    lock.lock()
    guard !requested, !finished else { lock.unlock(); return }
    requested = true
    var sample = self.sample(.request, from: started)
    sample.inputCharacters = max(inputCharacters, 0)
    lock.unlock()
    sink(sample)
  }

  func activity(_ activity: Activity) {
    lock.lock()
    guard requested, !firstActivity, !finished else { lock.unlock(); return }
    firstActivity = true
    var sample = self.sample(.firstActivity, from: started)
    sample.activity = activity
    lock.unlock()
    sink(sample)
  }

  func finish(completed: Bool, failed: Bool, cancelled: Bool) {
    lock.lock()
    guard !finished else { lock.unlock(); return }
    finished = true
    var sample = self.sample(.finished, from: started)
    sample.completion = cancelled ? .cancelled : (failed ? .failed : (completed ? .completed : .interrupted))
    lock.unlock()
    sink(sample)
  }

  // Citation validation happens after the provider span has ended, and measures
  // only this validation call, rather than reusing model-round elapsed time.
  func citationValidation(startedAtMillis: Int64, requiresRepair: Bool) {
    var sample = self.sample(.citationValidation, from: startedAtMillis)
    sample.requiresRepair = requiresRepair
    sink(sample)
  }

  private func sample(_ stage: Stage, from start: Int64) -> Sample {
    let end = clock()
    let delta = end.subtractingReportingOverflow(start)
    let elapsed = end <= start ? 0 : (delta.overflow ? Int64.max : delta.partialValue)
    return Sample(requestHash: requestHash, round: round, route: route, finalRound: finalRound,
      stage: stage, elapsedMillis: elapsed)
  }

  static func log(_ sample: Sample) {
    let activity = sample.activity?.rawValue ?? "none"
    let completion = sample.completion?.rawValue ?? "none"
    let input = sample.inputCharacters ?? -1
    let repair = sample.requiresRepair.map { $0 ? "true" : "false" } ?? "none"
    logger.info("model_round request=\(sample.requestHash, privacy: .private(mask: .hash)) round=\(sample.round) route=\(sample.route.rawValue, privacy: .public) final=\(sample.finalRound) stage=\(sample.stage.rawValue, privacy: .public) elapsed_ms=\(sample.elapsedMillis) input_chars=\(input) kind=\(activity, privacy: .public) outcome=\(completion, privacy: .public) repair=\(repair, privacy: .public)")
  }

  static func monotonicMillis() -> Int64 {
    Int64(clamping: DispatchTime.now().uptimeNanoseconds / 1_000_000)
  }
}
