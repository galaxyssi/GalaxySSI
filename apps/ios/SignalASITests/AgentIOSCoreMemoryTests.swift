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

  func testAcceptsExpandedExplicitIdentityDeviceAndProjectPhrases() {
    [
      "My name is Nova",
      "You can call me Nova",
      "I'm called Nova",
      "I go by Nova",
      "\u{6211}\u{7684}\u{540d}\u{5b57}\u{53eb} Nova",
      "\u{6211}\u{7684}\u{59d3}\u{540d}\u{662f} Nova",
      "\u{4f60}\u{53ef}\u{4ee5}\u{53eb}\u{6211} Nova"
    ].forEach { message in
      XCTAssertEqual(
        AgentIOSCoreMemoryExtractor.extract(message)
          .first { $0.key == AgentIOSCoreMemoryExtractor.nameKey }?.value,
        "The user's preferred name is Nova.",
        message
      )
    }
    XCTAssertEqual(
      AgentIOSCoreMemoryExtractor.extract("My phone model is iPhone 17")
        .first { $0.key == AgentIOSCoreMemoryExtractor.primaryDeviceKey }?.value,
      "The user's primary device is iPhone 17."
    )
    XCTAssertEqual(
      AgentIOSCoreMemoryExtractor.extract("\u{5f53}\u{524d}\u{624b}\u{673a}\u{662f} iPhone 17")
        .first { $0.key == AgentIOSCoreMemoryExtractor.primaryDeviceKey }?.value,
      "The user's primary device is iPhone 17."
    )
    XCTAssertEqual(
      AgentIOSCoreMemoryExtractor.extract("I am working on SignalASI")
        .first { $0.key == AgentIOSCoreMemoryExtractor.currentProjectKey }?.value,
      "The user's current project is SignalASI."
    )
    XCTAssertEqual(
      AgentIOSCoreMemoryExtractor.extract("\u{6211}\u{5728}\u{505a}\u{7684}\u{9879}\u{76ee}\u{662f} SignalASI")
        .first { $0.key == AgentIOSCoreMemoryExtractor.currentProjectKey }?.value,
      "The user's current project is SignalASI."
    )
  }

  func testPreservesCanonicalKeySeparatorsAndMigratesLegacyCoreKeys() {
    XCTAssertEqual(AgentMemoryKeyPolicy.normalize("CORE:Identity:Name"), AgentIOSCoreMemoryExtractor.nameKey)
    let store = InMemoryAgentMemoryStore(items: [
      AgentMemoryItem(kind: .identity, value: "The user's preferred name is Nova.", key: "coreidentityname"),
      AgentMemoryItem(kind: .identity, value: "The user's primary device is iPhone.", key: "coredeviceprimary"),
      AgentMemoryItem(kind: .task, value: "The user's current project is SignalASI.", key: "coreprojectcurrent"),
      AgentMemoryItem(kind: .preference, value: "The user prefers concise replies.", key: "corepreferenceconcise")
    ])
    let coordinator = AgentIOSCoreMemoryCoordinator(store: store)

    let prompt = coordinator.compilePrompt()
    let activeKeys = Set(store.snapshot().activeItems.map(\.key))

    XCTAssertTrue(prompt.contains("preferred name is Nova"))
    XCTAssertTrue(activeKeys.contains(AgentIOSCoreMemoryExtractor.nameKey))
    XCTAssertTrue(activeKeys.contains(AgentIOSCoreMemoryExtractor.primaryDeviceKey))
    XCTAssertTrue(activeKeys.contains(AgentIOSCoreMemoryExtractor.currentProjectKey))
    XCTAssertTrue(activeKeys.contains("core:preference:concise"))
    XCTAssertFalse(activeKeys.contains("coreidentityname"))
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
