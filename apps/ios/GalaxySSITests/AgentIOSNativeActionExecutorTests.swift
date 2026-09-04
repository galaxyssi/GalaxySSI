import XCTest
@testable import GalaxySSI

final class AgentIOSNativeActionExecutorTests: XCTestCase {
  func testOpenURLUsesValidatedSystemHandoff() {
    let handoff = RecordingNativeActionHandoff()
    let executor = AgentIOSNativeActionExecutor(handoffProvider: handoff)

    let result = executor.execute(
      action: action(kind: .openURL, target: "https://example.com"),
      screen: screen()
    )

    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["handoff"], "ios_url")
    XCTAssertEqual(handoff.urls.map(\.absoluteString), ["https://example.com"])
  }

  func testOpenURLRejectsNonWebSchemes() {
    let handoff = RecordingNativeActionHandoff()
    let executor = AgentIOSNativeActionExecutor(handoffProvider: handoff)

    let result = executor.execute(
      action: action(kind: .openURL, target: "tel:+15551234567"),
      screen: screen()
    )

    XCTAssertFalse(result.success)
    XCTAssertEqual(result.metadata["error_code"], "invalid_url")
    XCTAssertTrue(handoff.urls.isEmpty)
  }

  func testOpenAppAllowsOnlyKnownIOSSystemSchemes() {
    let handoff = RecordingNativeActionHandoff()
    let executor = AgentIOSNativeActionExecutor(handoffProvider: handoff)

    let known = executor.execute(
      action: action(kind: .openApp, parameters: ["package": "com.apple.Maps"]),
      screen: screen()
    )
    let unknown = executor.execute(
      action: action(kind: .openApp, parameters: ["package": "com.example.other"]),
      screen: screen()
    )

    XCTAssertTrue(known.success)
    XCTAssertEqual(known.metadata["url_scheme"], "maps")
    XCTAssertFalse(unknown.success)
    XCTAssertEqual(unknown.metadata["error_code"], "arbitrary_app_launch_unavailable")
    XCTAssertEqual(handoff.urls.map(\.scheme), ["maps"])
  }

  private func action(
    kind: AgentActionKind,
    target: String = "",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: "native-action",
      kind: kind,
      target: target,
      risk: .medium,
      status: .running,
      description: "Native action",
      parameters: parameters,
      requiresConfirmation: false
    )
  }

  private func screen() -> AgentScreenContext {
    AgentScreenContext(foregroundApp: "GalaxySSI")
  }
}

private final class RecordingNativeActionHandoff: AgentIOSNativeActionHandoffProviding {
  private(set) var urls: [URL] = []

  func open(_ url: URL) -> Bool {
    urls.append(url)
    return true
  }
}
