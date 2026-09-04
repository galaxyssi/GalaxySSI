import Foundation
import Network
import UIKit

struct AgentIOSEvalProcessSession: Codable, Equatable {
  var processInstanceId: String
  var bootEpochMillis: Int64
  var startedAtMillis: Int64
}

final class AgentIOSEvalProcessSessionStore {
  static let defaultKey = "galaxyssi-ios-eval-process-session-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentIOSEvalProcessSessionStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func load() -> AgentIOSEvalProcessSession? {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets) else { return nil }
    return try? JSONDecoder().decode(AgentIOSEvalProcessSession.self, from: data)
  }

  func save(_ value: AgentIOSEvalProcessSession) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }
}

final class AgentIOSEvalReliabilityHarness {
  static let shared = AgentIOSEvalReliabilityHarness()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "galaxyssi.agent.eval.reliability")
  private let sessionStore = AgentIOSEvalProcessSessionStore()
  private let lock = NSRecursiveLock()
  private var started = false
  private var networkWasAvailable: Bool?
  private var observers: [NSObjectProtocol] = []

  private init() {}

  func start() {
    guard locked({
      guard !started else { return false }
      started = true
      return true
    }) else { return }
    recoverPreviousSession()
    monitor.pathUpdateHandler = { [weak self] path in
      self?.observeNetwork(path.status == .satisfied)
    }
    monitor.start(queue: queue)
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: nil
    ) { _ in
      AgentEvalOpsService.observeConditionEntered(.doze, reason: "iOS application entered the background")
    })
    observers.append(center.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: nil
    ) { _ in
      AgentEvalOpsService.observeConditionRecovered(.doze)
    })
    observers.append(center.addObserver(
      forName: Notification.Name.NSProcessInfoPowerStateDidChange,
      object: nil,
      queue: nil
    ) { _ in
      if ProcessInfo.processInfo.isLowPowerModeEnabled {
        AgentEvalOpsService.observeConditionEntered(.doze, reason: "iOS Low Power Mode enabled")
      } else {
        AgentEvalOpsService.observeConditionRecovered(.doze)
      }
    })
  }

  private func recoverPreviousSession() {
    let now = AgentEvalClock.nowMillis()
    let bootEpoch = now - Int64((ProcessInfo.processInfo.systemUptime * 1_000).rounded())
    let previous = sessionStore.load()
    let condition: AgentEvalCondition = previous.map {
      abs($0.bootEpochMillis - bootEpoch) > 120_000 ? .reboot : .processDeath
    } ?? .normal
    sessionStore.save(AgentIOSEvalProcessSession(
      processInstanceId: UUID().uuidString,
      bootEpochMillis: bootEpoch,
      startedAtMillis: now
    ))
    guard condition != .normal else { return }

    let labStore = AgentLabStore()
    let interruptedLabRunIds = Set(labStore.list().flatMap { campaign in
      campaign.trials.filter { $0.status == .running }.map(\.runId)
    })
    UserDefaultsAgentRecordedRunStore().runs(for: "")
      .filter { $0.status == .running && !interruptedLabRunIds.contains($0.runId) }
      .forEach {
        _ = AgentEvalOpsService.observeRunInterrupted(
          runId: $0.runId,
          condition: condition,
          reason: condition == .reboot ? "Run interrupted by an iOS device reboot" : "Run interrupted by an iOS process restart"
        )
      }
    guard let runtime = AgentEvolutionLabRuntimeRegistry.shared.current() else { return }
    for campaign in labStore.list().filter({ $0.status == .running }) {
      try? runtime.resumeInterrupted(campaignId: campaign.id, condition: condition)
    }
  }

  private func observeNetwork(_ available: Bool) {
    let previous = locked { () -> Bool? in
      let previous = networkWasAvailable
      networkWasAvailable = available
      return previous
    }
    guard let previous, previous != available else { return }
    if available {
      AgentEvalOpsService.observeConditionRecovered(.networkLoss)
    } else {
      AgentEvalOpsService.observeConditionEntered(.networkLoss, reason: "Network path became unavailable")
    }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}
