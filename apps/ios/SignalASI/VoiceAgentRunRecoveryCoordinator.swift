import Combine
import Foundation
import UIKit

final class VoiceAgentRunRecoveryCoordinator: ObservableObject {
  static let shared = VoiceAgentRunRecoveryCoordinator()

  @Published private(set) var snapshots: [VoiceAgentRunSnapshot] = []

  private let bridge: VoiceAgentRunBridge
  private var observerTokens: [NSObjectProtocol] = []
  private var listenerId = ""
  private var started = false

  init(bridge: VoiceAgentRunBridge = VoiceAgentRunBridgeRegistry.shared) {
    self.bridge = bridge
  }

  var activeSnapshots: [VoiceAgentRunSnapshot] {
    snapshots.filter { !$0.state.isTerminal }
  }

  func start() {
    guard !started else {
      refresh()
      return
    }
    started = true
    let center = NotificationCenter.default
    observerTokens = [
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.refresh()
      },
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.refresh()
      }
    ]
    listenerId = bridge.addListener { [weak self] _ in
      DispatchQueue.main.async {
        self?.refresh()
      }
    }
    refresh()
  }

  func refresh() {
    guard started else { return }
    _ = bridge.reconcileStaleCancellations()
    snapshots = bridge.snapshots()
  }

  deinit {
    observerTokens.forEach(NotificationCenter.default.removeObserver)
    if !listenerId.isEmpty {
      bridge.removeListener(listenerId)
    }
  }
}
