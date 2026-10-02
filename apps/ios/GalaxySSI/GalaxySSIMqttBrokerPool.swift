import Foundation

// Each path owns a TLS connection, packet IDs, SUBACKs and PUBACKs. All aggregate
// state is confined to queue; an old path callback cannot authorize a new path.
final class GalaxySSIMqttBrokerPool {
  let policy: MqttMultipathPolicy
  private let queue = DispatchQueue(label: "com.galaxyssi.ios.mqtt.pool")
  private var paths: [String: MqttBrokerPathTransport] = [:]
  private var snapshots: [String: MqttBrokerPathSnapshot] = [:]
  private var configurationID = ""
  private var running = false
  var onPathState: (([String: MqttBrokerPathSnapshot]) -> Void)?
  var onAuthenticatedIngress: ((MqttAuthenticatedIngress) -> Void)?

  init(policy: MqttMultipathPolicy = MqttMultipathPolicy(),
       factory: (MqttBrokerEndpoint) -> MqttBrokerPathTransport = { GalaxySSIMqttClient(endpoint: $0) }) {
    self.policy = policy
    for endpoint in MqttBrokerEndpoint.catalog {
      let path = factory(endpoint)
      paths[endpoint.id] = path
      path.onPathState = { [weak self] snapshot in
        self?.queue.async { [weak self] in
          guard let self, self.running, snapshot.brokerID == endpoint.id,
                snapshot.configurationID == self.configurationID,
                !snapshot.connected || snapshot.generation > 0,
                snapshot.generation >= (self.snapshots[endpoint.id]?.generation ?? 0) else { return }
          self.snapshots[endpoint.id] = snapshot
          self.policy.synchronize(self.snapshots)
          self.onPathState?(self.snapshots)
        }
      }
      path.onAuthenticatedIngress = { [weak self] ingress in
        self?.queue.async { [weak self] in
          guard let self, self.running, ingress.brokerID == endpoint.id,
                ingress.configurationID == self.configurationID,
                let snapshot = self.snapshots[endpoint.id], snapshot.connected,
                snapshot.generation == ingress.generation,
                snapshot.subscriptions.contains(ingress.topic) else { return }
          self.onAuthenticatedIngress?(ingress)
        }
      }
    }
  }

  func connect(_ configuration: MqttBrokerPathConfiguration) {
    queue.async {
      self.running = true
      self.configurationID = UUID().uuidString
      self.snapshots.removeAll()
      self.policy.synchronize([:])
      self.onPathState?([:])
      for (id, path) in self.paths {
        var scoped = configuration
        scoped.clientID = configuration.clientID + ":" + id
        scoped.configurationID = self.configurationID
        path.configurePath(scoped)
      }
    }
  }

  func readyGenerations(for receiveTopics: Set<String>) async -> [String: Int64] {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: self.running
          ? MqttBrokerPathPolicy.readyGenerations(self.snapshots, topics: receiveTopics) : [:])
      }
    }
  }

  // The route session chooses a broker and generation; the pool never silently reroutes it.
  func publish(_ publication: MqttPathPublication, brokerID: String) async -> MqttPublishResult {
    let selected: (MqttBrokerPathTransport, MqttPathPublication)? = await withCheckedContinuation { continuation in
      queue.async {
        guard self.running, let snapshot = self.snapshots[brokerID],
              snapshot.generation == publication.generation,
              snapshot.isReady(for: publication.receiveTopics) else {
          continuation.resume(returning: nil)
          return
        }
        guard let path = self.paths[brokerID] else {
          continuation.resume(returning: nil)
          return
        }
        var scoped = publication
        scoped.configurationID = self.configurationID
        continuation.resume(returning: (path, scoped))
      }
    }
    // The path repeats authorization on its own queue and again immediately before writing.
    guard let (path, scoped) = selected else { return .failed }
    return await path.publishOnPath(scoped)
  }

  func outstandingDurableMessageIds() async -> Set<String> {
    let current: [MqttBrokerPathTransport] = await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: Array(self.paths.values)) }
    }
    var result = Set<String>()
    for path in current { result.formUnion(await path.outstandingDurableMessageIds()) }
    return result
  }

  func disconnect() {
    queue.async {
      self.running = false
      self.configurationID = UUID().uuidString
      self.snapshots.removeAll()
      self.policy.synchronize([:])
      self.paths.values.forEach { $0.disconnect() }
      self.onPathState?([:])
    }
  }

  deinit {
    policy.synchronize([:])
    paths.values.forEach {
      $0.onPathState = nil
      $0.onAuthenticatedIngress = nil
      $0.disconnect()
    }
  }
}
