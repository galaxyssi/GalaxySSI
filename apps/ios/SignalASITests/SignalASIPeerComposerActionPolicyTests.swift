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
}
