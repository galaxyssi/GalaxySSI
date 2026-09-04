import Foundation

final class AgentIOSComposerInputBridge {
  static let shared = AgentIOSComposerInputBridge()

  private let lock = NSLock()
  private var handler: ((AgentAction) -> AgentActionResult)?

  private init() {}

  func install(handler: @escaping (AgentAction) -> AgentActionResult) {
    lock.lock()
    self.handler = handler
    lock.unlock()
  }

  func removeHandler() {
    lock.lock()
    handler = nil
    lock.unlock()
  }

  func execute(action: AgentAction) -> AgentActionResult {
    lock.lock()
    let handler = self.handler
    lock.unlock()

    guard let handler else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "The GalaxySSI Agent composer is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_composer",
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
      message: "The GalaxySSI Agent composer action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_composer",
        "completion_verified": "false"
      ]
    )
  }
}
