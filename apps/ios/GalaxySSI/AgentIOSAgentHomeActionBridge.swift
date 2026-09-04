import Foundation

final class AgentIOSAgentHomeActionBridge {
  static let shared = AgentIOSAgentHomeActionBridge()

  private let lock = NSLock()
  private var tapHandler: ((AgentAction) -> AgentActionResult)?
  private var longPressHandler: ((AgentAction) -> AgentActionResult)?
  private var backHandler: ((AgentAction) -> AgentActionResult)?

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

  func installLongPressHandler(_ handler: @escaping (AgentAction) -> AgentActionResult) {
    lock.lock()
    longPressHandler = handler
    lock.unlock()
  }

  func removeLongPressHandler() {
    lock.lock()
    longPressHandler = nil
    lock.unlock()
  }

  func installBackHandler(_ handler: @escaping (AgentAction) -> AgentActionResult) {
    lock.lock()
    backHandler = handler
    lock.unlock()
  }

  func removeBackHandler() {
    lock.lock()
    backHandler = nil
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
        message: "The GalaxySSI Agent home page is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_home",
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
      message: "The GalaxySSI Agent home action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_home",
        "completion_verified": "false"
      ]
    )
  }

  func executeLongPress(action: AgentAction) -> AgentActionResult {
    lock.lock()
    let handler = longPressHandler
    lock.unlock()

    guard let handler else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "The GalaxySSI Agent home page is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_home",
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
      message: "The GalaxySSI Agent home long-press action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_home",
        "completion_verified": "false"
      ]
    )
  }

  func executeBack(action: AgentAction) -> AgentActionResult {
    lock.lock()
    let handler = backHandler
    lock.unlock()

    guard let handler else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "The GalaxySSI Agent home page is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_home",
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
      message: "The GalaxySSI Agent home back action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_home",
        "completion_verified": "false"
      ]
    )
  }
}
