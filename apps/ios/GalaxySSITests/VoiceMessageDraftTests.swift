import XCTest
@testable import GalaxySSI

@MainActor
final class VoiceMessageDraftTests: XCTestCase {
  private let session = UUID()
  private let alice = VoiceMessageDraft.Person(id: "alice", name: "Alex", route: "route-a")
  private let bob = VoiceMessageDraft.Person(id: "bob", name: "Alex", route: "route-b")
  private func speaker(_ turn: String = "prepare") -> VoiceMessageDraft.Speaker {
    .init(owner: "fixture-owner", session: session, conversation: "fixture-chat", turn: turn)
  }
  private func revision(_ result: AgentNativeToolExecutionResult) throws -> String {
    try XCTUnwrap(result.output["revision"]?.stringValue)
  }

  func testCorrectionPreservesExactBodyAndInvalidatesOldRevision() throws {
    let draft = VoiceMessageDraft()
    let text = "  Exact body\nline two  "
    let old = try revision(draft.begin(speaker(), text: text, people: [alice]))
    let replacement = draft.change(speaker("correct"), revision: old, people: [bob])
    let fresh = try revision(replacement)
    XCTAssertNotEqual(fresh, old)
    XCTAssertEqual(replacement.output["text"]?.stringValue, text)
    XCTAssertNil(draft.claim(speaker("confirm"), revision: old, confirmed: true))
    XCTAssertNil(draft.claim(speaker("correct"), revision: fresh, confirmed: true))
    let claim = try XCTUnwrap(draft.claim(speaker("confirm"), revision: fresh, confirmed: true))
    XCTAssertEqual(claim.text, text)
    XCTAssertEqual(claim.recipient.id, "bob")
  }

  func testNewSpokenConfirmationClaimsOnlyOnceRegardlessOfToolKey() throws {
    let draft = VoiceMessageDraft()
    let rev = try revision(draft.begin(speaker(), text: "fixture", people: [alice]))
    XCTAssertNil(draft.claim(speaker(), revision: rev, confirmed: true))
    XCTAssertNil(draft.claim(speaker("later"), revision: rev, confirmed: false))
    let claim = try XCTUnwrap(draft.claim(speaker("later"), revision: rev, confirmed: true))
    XCTAssertNil(draft.claim(speaker("another-key"), revision: rev, confirmed: true))
    let result = draft.finish(claim, result: .success(output: ["status": .string("queued"), "message_id": .string("fixture-id")]))
    XCTAssertEqual(result.output["state"]?.stringValue, "queued")
    XCTAssertEqual(result.output["delivery_verified"]?.boolValue, false)
    XCTAssertNil(result.output["text"])
    XCTAssertEqual(draft.cancel(speaker("cancel"), revision: rev).output["state"]?.stringValue, "queued")
    XCTAssertEqual(draft.change(speaker("correct"), revision: rev, people: [bob]).output["state"]?.stringValue, "queued")
    XCTAssertEqual(try revision(draft.begin(speaker("later"), text: "replay", people: [bob])), rev)
  }

  func testNumberedChoiceMustMatchSpokenOrdinalAndWaitForAnotherTurn() throws {
    let draft = VoiceMessageDraft()
    let rev = try revision(draft.begin(speaker(), text: "unchanged", people: [alice, bob]))
    XCTAssertFalse(draft.choose(speaker(), revision: rev, id: "bob", spokenOption: 2).isSuccess)
    XCTAssertFalse(draft.choose(speaker("choice"), revision: rev, id: "alice", spokenOption: 2).isSuccess)
    XCTAssertFalse(draft.choose(speaker("choice"), revision: rev, id: "bob", spokenOption: 0).isSuccess)
    let chosen = draft.choose(speaker("choice"), revision: rev, id: "bob", spokenOption: 2)
    XCTAssertEqual(chosen.output["text"]?.stringValue, "unchanged")
    let fresh = try revision(chosen)
    XCTAssertNil(draft.claim(speaker("choice"), revision: fresh, confirmed: true))
    XCTAssertEqual(draft.claim(speaker("confirm"), revision: fresh, confirmed: true)?.recipient, bob)
  }

  func testUncertainQueueConsumesBodyAndDoesNotPermitRetry() throws {
    let draft = VoiceMessageDraft()
    let rev = try revision(draft.begin(speaker(), text: "private fixture", people: [alice]))
    let claim = try XCTUnwrap(draft.claim(speaker("confirm"), revision: rev, confirmed: true))
    let result = draft.finish(claim, result: .failure(code: "timeout", message: "Uncertain synthetic send"))
    XCTAssertEqual(result.output["state"]?.stringValue, "dispatch_uncertain")
    XCTAssertNil(result.output["text"])
    XCTAssertNil(draft.claim(speaker("retry"), revision: rev, confirmed: true))
  }

  func testMonotonicExpiryAndOwnerSessionConversationFences() throws {
    var time: TimeInterval = 1
    let draft = VoiceMessageDraft(now: { time })
    let rev = try revision(draft.begin(speaker(), text: "fixture", people: [alice]))
    for other in [VoiceMessageDraft.Speaker(owner: "other", session: session, conversation: "fixture-chat", turn: "later"),
      .init(owner: "fixture-owner", session: UUID(), conversation: "fixture-chat", turn: "later"),
      .init(owner: "fixture-owner", session: session, conversation: "other", turn: "later")] {
      XCTAssertNil(draft.claim(other, revision: rev, confirmed: true))
    }
    time = 181
    XCTAssertNil(draft.claim(speaker("later"), revision: rev, confirmed: true))
    XCTAssertEqual(draft.status(speaker())["state"]?.stringValue, "no_active_draft")
  }

  func testCancellationAndDelayedFinishCannotOverwriteFreshDraft() throws {
    let draft = VoiceMessageDraft()
    let rev = try revision(draft.begin(speaker(), text: "old", people: [alice]))
    let claim = try XCTUnwrap(draft.claim(speaker("confirm"), revision: rev, confirmed: true))
    draft.clear()
    let fresh = try revision(draft.begin(speaker("new"), text: "new", people: [bob]))
    _ = draft.finish(claim, result: .success(output: ["status": .string("queued")]))
    XCTAssertEqual(draft.status(speaker("new"))["revision"]?.stringValue, fresh)
    XCTAssertEqual(draft.cancel(speaker("new"), revision: fresh).output["state"]?.stringValue, "cancelled_before_send")
    XCTAssertNil(draft.status(speaker("new"))["text"])
  }

  func testExactConfirmationAndChoiceNeverAcceptModelProseOrNegation() {
    func parse(_ text: String) -> VoiceMessageSpeechEvidence {
      .parse(text, confirmations: ["send it"], ordinals: [], prefixes: [], suffixes: [])
    }
    XCTAssertTrue(parse(" Send it! ").confirmed)
    for text in ["do not send it", "please say send it", "confirmed=true", "send it to Alex"] {
      XCTAssertFalse(parse(text).confirmed)
    }
    XCTAssertEqual(parse("the second one").choice, 2)
    XCTAssertEqual(parse("option 2").choice, 2)
    XCTAssertEqual(parse("option 0").choice, 0)
    XCTAssertEqual(parse("option 501").choice, 0)
  }

  func testCaptureSessionSurvivesNextUtteranceButNotWindowOrConversationChange() throws {
    let contexts = VoiceAppContextStore()
    let first = try XCTUnwrap(contexts.capture(conversationID: "chat", surface: .agent))
    contexts.captureSpoken("send it", anchor: first)
    XCTAssertTrue(contexts.spoken(first)?.confirmed == true)
    contexts.invalidate(first, preserveDraft: true)
    let next = try XCTUnwrap(contexts.capture(conversationID: "chat", surface: .agent))
    XCTAssertEqual(first.draftSession, next.draftSession)
    XCTAssertNil(contexts.spoken(first))
    XCTAssertNil(contexts.spoken(next))
    contexts.invalidate(first)
    XCTAssertTrue(contexts.isForegroundOwner(next))
    contexts.invalidate(next)
    XCTAssertFalse(contexts.isForegroundOwner(next))
    let fresh = try XCTUnwrap(contexts.capture(conversationID: "chat", surface: .agent))
    XCTAssertNotEqual(fresh.draftSession, first.draftSession)
    let different = try XCTUnwrap(contexts.capture(conversationID: "other", surface: .agent))
    XCTAssertNotEqual(different.draftSession, fresh.draftSession)
    contexts.installNavigation(owner: UUID(), handle: { _ in .success(output: [:]) })
    XCTAssertFalse(contexts.isForegroundOwner(different))
    contexts.clear()
    XCTAssertNil(contexts.spoken(different))
  }
}
