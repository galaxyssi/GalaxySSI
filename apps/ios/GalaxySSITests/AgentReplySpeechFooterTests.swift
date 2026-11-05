import Combine
import XCTest
@testable import GalaxySSI

final class AgentReplySpeechFooterTests: XCTestCase {
  @MainActor
  func testPlaybackTransitionsPublishOnlyToTheOwningFooter() {
    let player = ControlledPlayer()
    let runtime = AgentReplySpeechRuntime(speech: player)
    let reply = target("current")
    var settings = VoiceSettings.default
    settings.textToSpeechEnabled = true
    var current: [AgentReplySpeechFooterState] = []
    var other: [AgentReplySpeechFooterState] = []
    var transcriptInvalidations = 0
    let observation = runtime.objectWillChange.sink { _ in transcriptInvalidations += 1 }
    let first = runtime.footerUpdates(entryId: reply.entryId).sink { current.append($0) }
    let second = runtime.footerUpdates(entryId: "unrelated").sink { other.append($0) }
    defer { [observation, first, second].forEach { $0.cancel() } }

    runtime.observe(reply, settings: settings, languagePolicy: .default)
    runtime.toggle(reply, settings: settings, languagePolicy: .default)
    player.complete(success: true)
    runtime.toggle(reply, settings: settings, languagePolicy: .default)
    XCTAssertTrue(runtime.stopPlaybackIfActive())
    XCTAssertFalse(runtime.stopPlaybackIfActive())

    XCTAssertEqual(current, [.init(), .init(active: true), .init(active: true, playing: true),
      .init(active: true), .init(active: true, playing: true), .init(active: true)])
    XCTAssertEqual(other, [.init()])
    XCTAssertEqual(transcriptInvalidations, 0)
  }

  @MainActor
  func testReattachedMergedFooterReadsCurrentStateAndRejectsOldCompletion() {
    let player = ControlledPlayer()
    let runtime = AgentReplySpeechRuntime(speech: player)
    let previous = target("original")
    let merged = target("merged")
    var settings = VoiceSettings.default
    settings.textToSpeechEnabled = true
    runtime.toggle(previous, settings: settings, languagePolicy: .default)
    let old = player.completion
    runtime.toggle(merged, settings: settings, languagePolicy: .default)
    old?(false, "stale failure")

    var reattached: [AgentReplySpeechFooterState] = []
    let subscription = runtime.footerUpdates(entryId: merged.entryId).sink { reattached.append($0) }
    defer { subscription.cancel() }
    XCTAssertEqual(runtime.footerState(entryId: previous.entryId), .init())
    XCTAssertEqual(reattached, [.init(active: true, playing: true)])

    player.complete(success: false, error: "read failed")
    XCTAssertEqual(reattached.last, .init(active: true, error: "read failed"))
    XCTAssertEqual(runtime.footerState(entryId: previous.entryId).error, "")
  }

  private func target(_ id: String) -> AgentReplySpeechTarget {
    .init(responseId: "shared-turn", entryId: id, text: "Speak this sentence.", complete: true)
  }

  @MainActor
  private final class ControlledPlayer: AgentReplySpeechPlaying {
    var completion: ((Bool, String?) -> Void)?

    func beginProgressive(_ request: VoiceReplyPlaybackRequest,
      onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
      onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void) {
      completion = { onDone(request, $0, $1) }
    }

    func appendProgressive(_ text: String, isFinal: Bool) {}
    func finishProgressive() {}
    func commitProgressive() {}

    func stop() -> Bool {
      guard completion != nil else { return false }
      complete(success: false, error: "cancelled")
      return true
    }

    func complete(success: Bool, error: String? = nil) {
      let callback = completion
      completion = nil
      callback?(success, error)
    }
  }
}
