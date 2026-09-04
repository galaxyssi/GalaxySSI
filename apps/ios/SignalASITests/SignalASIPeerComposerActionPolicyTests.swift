import XCTest
@testable import SignalASI

final class SignalASIPeerComposerActionPolicyTests: XCTestCase {
  func testPeerTrayMatchesAgentFiveActionOrder() {
    XCTAssertEqual(
      SignalASIPeerComposerActionPolicy.actionIDs,
      [.newSession, .sessions, .scan, .camera, .file]
    )
  }

  func testExpandedTrayUsesMoreButtonAndHidesSendButton() {
    let state = SignalASIAgentComposerUiPolicy.resolve(
      hasInput: false,
      hasPendingPrimaryAction: false,
      textModeActive: false,
      actionTrayRequested: true
    )

    XCTAssertTrue(state.showActionTray)
    XCTAssertTrue(state.showMoreButton)
    XCTAssertFalse(state.showSendButton)
    XCTAssertTrue(state.showPrimaryActionSlot)
  }

  func testInputClosesTrayPresentationInFavorOfSend() {
    let state = SignalASIAgentComposerUiPolicy.resolve(
      hasInput: true,
      hasPendingPrimaryAction: false,
      textModeActive: true,
      actionTrayRequested: true
    )

    XCTAssertFalse(state.showActionTray)
    XCTAssertFalse(state.showMoreButton)
    XCTAssertTrue(state.showSendButton)
  }

  func testPendingTaskWithEmptyInputDoesNotExposeSendAction() {
    let state = SignalASIAgentComposerUiPolicy.resolve(
      hasInput: false,
      hasPendingPrimaryAction: true,
      textModeActive: false,
      actionTrayRequested: false
    )

    XCTAssertFalse(state.showSendButton)
    XCTAssertTrue(state.showPendingActionButton)
    XCTAssertTrue(state.showPrimaryActionSlot)
  }

  func testBackConsumesExpandedTrayBeforeNavigation() {
    XCTAssertTrue(
      SignalASIPeerComposerActionPolicy.consumesBackAction(actionTrayPresented: true)
    )
    XCTAssertFalse(
      SignalASIPeerComposerActionPolicy.consumesBackAction(actionTrayPresented: false)
    )
  }

  func testParagraphSelectionIncludesTheWholeParagraphAroundCursor() {
    let text = "\u{7b2c}\u{4e00}\u{6bb5}\u{5185}\u{5bb9}\n\u{7b2c}\u{4e8c}\u{6bb5}\u{53ef}\u{4ee5}\u{8de8}\u{884c}\u{9009}\u{62e9}\n\u{7b2c}\u{4e09}\u{6bb5}"

    XCTAssertEqual(
      SignalASIParagraphSelectionPolicy.range(in: text, requestedUTF16Offset: 10),
      NSRange(location: 6, length: 9)
    )
  }

  func testParagraphSelectionAtNewlineUsesPreviousParagraph() {
    let text = "first paragraph\nsecond paragraph"

    XCTAssertEqual(
      SignalASIParagraphSelectionPolicy.range(in: text, requestedUTF16Offset: 15),
      NSRange(location: 0, length: 15)
    )
  }

  func testParagraphSelectionAtEndUsesLastParagraph() {
    let text = "first\nlast paragraph"

    XCTAssertEqual(
      SignalASIParagraphSelectionPolicy.range(
        in: text,
        requestedUTF16Offset: (text as NSString).length
      ),
      NSRange(location: 6, length: 14)
    )
  }

  func testParagraphSelectionForEmptyInputIsEmpty() {
    XCTAssertEqual(
      SignalASIParagraphSelectionPolicy.range(in: "", requestedUTF16Offset: 0),
      NSRange(location: 0, length: 0)
    )
  }
}
