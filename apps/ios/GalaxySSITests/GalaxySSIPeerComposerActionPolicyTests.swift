import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIPeerComposerActionPolicyTests: XCTestCase {
  func testPeerTrayMatchesAgentFiveActionOrder() {
    XCTAssertEqual(
      GalaxySSIPeerComposerActionPolicy.actionIDs,
      [.newSession, .sessions, .scan, .camera, .file]
    )
  }

  func testExpandedTrayUsesMoreButtonAndHidesSendButton() {
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
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
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
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
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
      hasInput: false,
      hasPendingPrimaryAction: true,
      textModeActive: false,
      actionTrayRequested: false
    )

    XCTAssertFalse(state.showSendButton)
    XCTAssertTrue(state.showPendingActionButton)
    XCTAssertTrue(state.showPrimaryActionSlot)
  }

  func testAgentIdleComposerShowsVoiceAsTheOnlyPrimaryAction() {
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
      hasInput: false,
      hasPendingPrimaryAction: false,
      textModeActive: false,
      actionTrayRequested: false,
      voiceEntryAvailable: true
    )

    XCTAssertTrue(state.showVoiceButton)
    XCTAssertFalse(state.showMoreButton)
    XCTAssertFalse(state.showSendButton)
    XCTAssertTrue(state.showPrimaryActionSlot)
  }

  func testAgentTextModeReplacesVoiceWithMore() {
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
      hasInput: false,
      hasPendingPrimaryAction: false,
      textModeActive: true,
      actionTrayRequested: false,
      voiceEntryAvailable: true
    )

    XCTAssertFalse(state.showVoiceButton)
    XCTAssertTrue(state.showMoreButton)
    XCTAssertFalse(state.showSendButton)
  }

  func testAgentInputReplacesVoiceAndMoreWithSend() {
    let state = GalaxySSIAgentComposerUiPolicy.resolve(
      hasInput: true,
      hasPendingPrimaryAction: false,
      textModeActive: true,
      actionTrayRequested: true,
      voiceEntryAvailable: true
    )

    XCTAssertFalse(state.showVoiceButton)
    XCTAssertFalse(state.showMoreButton)
    XCTAssertTrue(state.showSendButton)
    XCTAssertFalse(state.showActionTray)
  }

  func testBackConsumesExpandedTrayBeforeNavigation() {
    XCTAssertTrue(
      GalaxySSIPeerComposerActionPolicy.consumesBackAction(actionTrayPresented: true)
    )
    XCTAssertFalse(
      GalaxySSIPeerComposerActionPolicy.consumesBackAction(actionTrayPresented: false)
    )
  }

  func testAgentComposerReturnsToVoiceWhenTrayClosesWithoutInput() {
    let tray = GalaxySSIAgentComposerUiPolicy.resolve(hasInput: false, hasPendingPrimaryAction: false,
      textModeActive: false, actionTrayRequested: true, voiceEntryAvailable: true)
    let closed = GalaxySSIAgentComposerUiPolicy.resolve(hasInput: false, hasPendingPrimaryAction: false,
      textModeActive: false, actionTrayRequested: false, voiceEntryAvailable: true)
    XCTAssertTrue(tray.showMoreButton)
    XCTAssertFalse(tray.showVoiceButton)
    XCTAssertFalse(closed.showActionTray)
    XCTAssertFalse(closed.showMoreButton)
    XCTAssertTrue(closed.showVoiceButton)
  }

  func testAgentPendingTaskTakesPriorityOverAnExpandedTray() {
    let state = GalaxySSIAgentComposerUiPolicy.resolve(hasInput: false, hasPendingPrimaryAction: true,
      textModeActive: false, actionTrayRequested: true, voiceEntryAvailable: true)
    XCTAssertTrue(state.showPendingActionButton)
    XCTAssertFalse(state.showActionTray)
    XCTAssertFalse(state.showMoreButton)
    XCTAssertFalse(state.showVoiceButton)
  }

  func testParagraphSelectionIncludesTheWholeParagraphAroundCursor() {
    let text = "\u{7b2c}\u{4e00}\u{6bb5}\u{5185}\u{5bb9}\n\u{7b2c}\u{4e8c}\u{6bb5}\u{53ef}\u{4ee5}\u{8de8}\u{884c}\u{9009}\u{62e9}\n\u{7b2c}\u{4e09}\u{6bb5}"

    XCTAssertEqual(
      GalaxySSIParagraphSelectionPolicy.range(in: text, requestedUTF16Offset: 10),
      NSRange(location: 6, length: 9)
    )
  }

  func testParagraphSelectionAtNewlineUsesPreviousParagraph() {
    let text = "first paragraph\nsecond paragraph"

    XCTAssertEqual(
      GalaxySSIParagraphSelectionPolicy.range(in: text, requestedUTF16Offset: 15),
      NSRange(location: 0, length: 15)
    )
  }

  func testParagraphSelectionAtEndUsesLastParagraph() {
    let text = "first\nlast paragraph"

    XCTAssertEqual(
      GalaxySSIParagraphSelectionPolicy.range(
        in: text,
        requestedUTF16Offset: (text as NSString).length
      ),
      NSRange(location: 6, length: 14)
    )
  }

  func testParagraphSelectionForEmptyInputIsEmpty() {
    XCTAssertEqual(
      GalaxySSIParagraphSelectionPolicy.range(in: "", requestedUTF16Offset: 0),
      NSRange(location: 0, length: 0)
    )
  }

  func testParagraphExpansionRequiresNativeSelectionOnThePressedGlyph() {
    let text = "first line\nsecond line"
    let word = NSRange(location: 11, length: 6)
    XCTAssertEqual(GalaxySSIParagraphSelectionPolicy.expansion(in: text, glyphOffset: 12, nativeSelection: word),
                   NSRange(location: 11, length: 11))
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.expansion(in: text, glyphOffset: 12,
      nativeSelection: NSRange(location: 12, length: 0)))
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.expansion(in: text, glyphOffset: 3, nativeSelection: word))
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.expansion(in: text, glyphOffset: 12,
      nativeSelection: NSRange(location: 0, length: 22)))
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.expansion(in: text, glyphOffset: 12,
      nativeSelection: NSRange(location: NSNotFound, length: 0)))
  }

  @MainActor
  func testComposerHitTestingSeparatesGlyphsFromLineEndsAndBlankRows() {
    let view = UITextView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
    view.font = .systemFont(ofSize: 15)
    view.text = "abc\n\nlast"
    view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
    view.textContainer.lineFragmentPadding = 0
    let layout = view.layoutManager
    let container = view.textContainer
    layout.ensureLayout(for: container)
    let rect = layout.boundingRect(forGlyphRange: NSRange(location: 1, length: 1), in: container)
    let textPoint = CGPoint(x: rect.midX + 12, y: rect.midY + 14)
    XCTAssertEqual(GalaxySSIParagraphSelectionPolicy.glyphOffset(at: textPoint, in: view), 1)
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.glyphOffset(at: CGPoint(x: 210, y: textPoint.y), in: view))
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.glyphOffset(at: CGPoint(x: 24, y: 160), in: view))
    view.text = ""
    XCTAssertNil(GalaxySSIParagraphSelectionPolicy.glyphOffset(at: textPoint, in: view))
  }
}
