import Foundation

final class AgentIOSAgentHomeActionBridge {
  static let shared = AgentIOSAgentHomeActionBridge()

  private let lock = NSLock()
  private var tapHandler: ((AgentAction) -> AgentActionResult)?

  private init() {}

  func installTapHandler(_ handler: @escaping (AgentAction) -> AgentActionResult) {
    lock.lock()
    tapHandler = handler
    lock.unlock()
  }

  func removeTapHandler() {
    lock.lock()
    tapHandler = nil
    lock.unlock()
  }

  func executeTap(action: AgentAction) -> AgentActionResult {
    lock.lock()
    let handler = tapHandler
    lock.unlock()

    guard let handler else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "The SignalASI Agent home page is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "signalasi_agent_home",
          "completion_verified": "false"
        ]
      )
    }

    if Thread.isMainThread {
      return handler(action)
    }

    var result: AgentActionResult?
    DispatchQueue.main.sync {
      result = handler(action)
    }
    return result ?? AgentActionResult(
      actionId: action.id,
      success: false,
      message: "The SignalASI Agent home action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "signalasi_agent_home",
        "completion_verified": "false"
      ]
    )
  }
}
