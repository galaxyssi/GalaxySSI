import Foundation

enum AgentIOSAgentSwipeDirection: String {
  case up
  case down
  case left
  case right

  static func resolve(parameters: [String: String]) -> AgentIOSAgentSwipeDirection? {
    if let rawDirection = parameters["direction"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
       let direction = AgentIOSAgentSwipeDirection(rawValue: rawDirection) {
      return direction
    }

    guard let fromX = Int(parameters["from_x"] ?? ""),
          let fromY = Int(parameters["from_y"] ?? ""),
          let toX = Int(parameters["to_x"] ?? ""),
          let toY = Int(parameters["to_y"] ?? "") else {
      return nil
    }
    let horizontalDistance = abs(toX - fromX)
    let verticalDistance = abs(toY - fromY)
    guard max(horizontalDistance, verticalDistance) > 0 else { return nil }
    if verticalDistance >= horizontalDistance {
      return toY < fromY ? .up : .down
    }
    return toX < fromX ? .left : .right
  }
}

final class AgentIOSAgentHomeSwipeBridge {
  static let shared = AgentIOSAgentHomeSwipeBridge()

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
        message: "The GalaxySSI Agent transcript is not currently visible.",
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_transcript",
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
      message: "The GalaxySSI Agent transcript action did not complete.",
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_transcript",
        "completion_verified": "false"
      ]
    )
  }
}
