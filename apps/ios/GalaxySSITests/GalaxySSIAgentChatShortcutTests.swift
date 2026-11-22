import SwiftUI
import UIKit
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIAgentChatShortcutTests: XCTestCase {
  typealias Layout = GalaxySSIAgentChatShortcutLayout

  func testOriginalFiveRemainFirstAndHealthScanAreAppended() {
    XCTAssertEqual(Layout.Action.allCases.map(\.rawValue), ["feed", "new", "chats", "photo", "files", "health", "scan"])
    XCTAssertEqual(Layout.initialActionCount, 5)
  }
  func testInitialFiveFillViewportWithoutIncludingNewActions() {
    let natural: [CGFloat] = [48, 62, 50, 58, 52, 60, 58]
    for available in [CGFloat(320), 375, 390, 430, 768] {
      let widths = Layout.widths(available: available, natural: natural, minimumTouch: 44)
      XCTAssertEqual(widths.count, 7)
      XCTAssertEqual(widths.prefix(5).reduce(0, +), available, accuracy: 0.001)
      for (actual, minimum) in zip(widths, natural) { XCTAssertGreaterThanOrEqual(actual, minimum) }
      XCTAssertGreaterThanOrEqual(widths[5], available / 5)
      XCTAssertGreaterThanOrEqual(widths[6], available / 5)
      XCTAssertGreaterThan(widths.prefix(6).reduce(0, +), available)
    }
  }
  func testNaturalLocalizedLabelsAndDynamicTypeNeverShrink() {
    let fallbacks = ["Feed", "New", "Chats", "Photo", "Files", "Health", "Scan"]
    for language in ["en", "zh-CN", "ar"] {
      let labels = zip(Layout.Action.allCases, fallbacks).map { action, fallback in
        GalaxySSILocalization.string("galaxyssi.agent.shortcuts." + action.rawValue, fallback: fallback, language: language)
      }
      for size in [CGFloat(12), 18, 28, 40] {
        let natural = labels.enumerated().map { index, title in
          Layout.naturalWidth(title: title, fontSize: size, showsUnread: index == 0 || index == 2)
        }
        for available in [CGFloat(280), 320, 390, 768] {
          let widths = Layout.widths(available: available, natural: natural, minimumTouch: 48)
          for (actual, measured) in zip(widths, natural) { XCTAssertGreaterThanOrEqual(actual, measured) }
          XCTAssertGreaterThanOrEqual(widths.prefix(5).reduce(0, +), available - 0.001)
          XCTAssertGreaterThan(widths.reduce(0, +), available)
        }
        XCTAssertGreaterThanOrEqual(Layout.height(fontSize: size, minimumTouch: 48), ceil(size * 1.4) + 16)
      }
    }
  }
  func testUnreadIndicatorAndLongLabelsKeepStableSpace() {
    let plain = Layout.naturalWidth(title: "Chats", fontSize: 12, showsUnread: false)
    let unread = Layout.naturalWidth(title: "Chats", fontSize: 12, showsUnread: true)
    XCTAssertEqual(unread - plain, 6)
    let widths = Layout.widths(available: 320, natural: [500, 49, 60, 70, 80, 90, 100], minimumTouch: 72)
    XCTAssertEqual(widths[0], 500)
    XCTAssertTrue(widths.allSatisfy { $0 >= 72 })
    XCTAssertGreaterThan(widths.prefix(5).reduce(0, +), 320)
  }
  func testInvalidMeasurementsAndEmptyContentRemainBounded() {
    XCTAssertTrue(Layout.widths(available: 320, natural: [], minimumTouch: 48).isEmpty)
    let widths = Layout.widths(available: .infinity, natural: [.nan, -10, 0], minimumTouch: .nan)
    XCTAssertEqual(widths, [48, 48, 48])
    XCTAssertEqual(Layout.startOffset(content: .nan, viewport: 320, left: 0, right: 0, rtl: true), 0)
  }
  func testStartOffsetHonorsRtlInsetsAndShortContent() {
    XCTAssertEqual(Layout.startOffset(content: 600, viewport: 320, left: 8, right: 12, rtl: false), -8)
    XCTAssertEqual(Layout.startOffset(content: 600, viewport: 320, left: 8, right: 12, rtl: true), 292)
    XCTAssertEqual(Layout.startOffset(content: 100, viewport: 320, left: 8, right: 12, rtl: true), -8)
  }
  func testNativeScrollResetsBeforeActionRatherThanOnReturn() {
    let view = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
    view.contentInsetAdjustmentBehavior = .never
    view.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
    view.contentSize = CGSize(width: 600, height: 200)
    let reference = GalaxySSIAgentShortcutScrollReference()
    for rtl in [false, true] {
      reference.bind(view, rtl: rtl)
      view.setContentOffset(CGPoint(x: 100, y: 13), animated: false)
      var observed: CGPoint?
      reference.activate { observed = view.contentOffset }
      XCTAssertEqual(observed?.x, rtl ? 292 : -8)
      XCTAssertEqual(observed?.y, 13)
    }
  }
  func testResolverUpdatesDoNotUndoManualSwipeAndDirectionChangeDoesReset() {
    let view = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
    view.contentInsetAdjustmentBehavior = .never
    view.contentSize = CGSize(width: 600, height: 48)
    let reference = GalaxySSIAgentShortcutScrollReference()
    reference.bind(view, rtl: false)
    view.setContentOffset(CGPoint(x: 100, y: 0), animated: false)
    reference.bind(view, rtl: false)
    XCTAssertEqual(view.contentOffset.x, 100)
    reference.bind(view, rtl: true)
    XCTAssertEqual(view.contentOffset.x, 280)
  }
  func testActivationWithoutNativeBindingStillRunsTheCommandOnce() {
    let reference = GalaxySSIAgentShortcutScrollReference()
    var count = 0
    reference.activate { count += 1 }
    XCTAssertEqual(count, 1)
  }
  func testNewChineseLabelsResolveFromResources() {
    XCTAssertEqual(GalaxySSILocalization.string("galaxyssi.agent.shortcuts.health", fallback: "Health", language: "zh-CN"), "\u{5065}\u{5EB7}")
    XCTAssertEqual(GalaxySSILocalization.string("galaxyssi.agent.shortcuts.scan", fallback: "Scan", language: "zh-CN"), "\u{626B}\u{4E00}\u{626B}")
  }
}
