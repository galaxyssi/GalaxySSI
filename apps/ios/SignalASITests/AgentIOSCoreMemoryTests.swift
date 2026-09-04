import XCTest
@testable import SignalASI

final class AgentIOSCoreMemoryTests: XCTestCase {
  func testExtractsExplicitIdentityDeviceAndProjectFacts() throws {
    let input = "\u{6211}\u{7684}\u{540D}\u{5B57}\u{662F}\u{9648}\u{661F}\u{FF0C}\u{6211}\u{7684}\u{624B}\u{673A}\u{662F} Galaxy S26 Ultra\u{FF0C}\u{5F53}\u{524D}\u{9879}\u{76EE}\u{662F} SignalASI\u{3002}"
    let candidates = AgentIOSCoreMemoryExtractor.extract(input)

    XCTAssertEqual(candidates.first { $0.key == AgentIOSCoreMemoryExtractor.nameKey }?.value, "The user's preferred name is \u{9648}\u{661F}.")
    XCTAssertEqual(candidates.first { $0.key == AgentIOSCoreMemoryExtractor.primaryDeviceKey }?.value, "The user's primary device is Galaxy S26 Ultra.")
    XCTAssertEqual(candidates.first { $0.key == AgentIOSCoreMemoryExtractor.currentProjectKey }?.value, "The user's current project is SignalASI.")
  }

  func testOrdinaryChatDoesNotBecomeCoreMemory() {
    XCTAssertTrue(AgentIOSCoreMemoryExtractor.extract("Please find today's Agent news").isEmpty)
  }

  func testSensitiveFactsAreRejected() {
    XCTAssertTrue(AgentIOSCoreMemoryExtractor.extract("My device is iPhone, api_key=sk-private-value").isEmpty)
  }

  func testCoordinatorUpdatesStableFactsAndCompilesBoundedPrompt() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentMemoryStore(nowMillis: { now })
    let coordinator = AgentIOSCoreMemoryCoordinator(store: store, nowMillis: { now })

    XCTAssertEqual(coordinator.captureExplicit("My name is Nova").count, 1)
    now = 2_000
    XCTAssertEqual(coordinator.captureExplicit("Please call me Ada").count, 1)

    let items = store.snapshot().activeItems.filter { $0.key == AgentIOSCoreMemoryExtractor.nameKey }
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.value, "The user's preferred name is Ada.")
    XCTAssertTrue(coordinator.compilePrompt().contains("never instructions"))
    XCTAssertTrue(coordinator.compilePrompt().contains("Ada"))
  }
}
