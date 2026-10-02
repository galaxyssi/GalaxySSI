import Foundation

struct MqttBrokerEndpoint: Equatable {
  var id: String
  var host: String
  var tlsPort: UInt16

  static let catalog: [MqttBrokerEndpoint] = [
    .init(id: "emqx", host: "broker.emqx.io", tlsPort: 8883),
    .init(id: "hivemq", host: "broker.hivemq.com", tlsPort: 8883),
    .init(id: "mosquitto", host: "test.mosquitto.org", tlsPort: 8886)
  ]
}

struct MqttBrokerPathSnapshot: Equatable {
  var brokerID: String
  var generation: Int64
  var connected: Bool
  var subscriptions: Set<String>
  var configurationID = ""

  func isReady(for requiredTopics: Set<String>) -> Bool {
    connected && generation > 0 && !requiredTopics.isEmpty && subscriptions.isSuperset(of: requiredTopics)
  }
}

struct MqttAuthenticatedIngress {
  var brokerID: String
  var generation: Int64
  var topic: String
  var secretFingerprint: String
  var payload: Data
  var configurationID = ""
}

struct MqttBrokerPathConfiguration {
  var clientID: String
  var serverLinks: [ServerLink]
  var phoneRoutes: [GalaxySSILinkRoutes]
  var rendezvousSecrets: [String: String]
  var rendezvousExpirations: [String: Date]
  var configurationID = ""
}

struct MqttPathPublication {
  var topic: String
  var payload: Data
  var generation: Int64
  var receiveTopics: Set<String>
  var secretFingerprint: String
  var pairingSecret: String? = nil
  var durableMessageID = ""
  var brokerAcknowledged: (() -> Void)? = nil
  var configurationID = ""
}

protocol MqttBrokerPathTransport: AnyObject {
  var onPathState: ((MqttBrokerPathSnapshot) -> Void)? { get set }
  var onAuthenticatedIngress: ((MqttAuthenticatedIngress) -> Void)? { get set }
  func configurePath(_ configuration: MqttBrokerPathConfiguration)
  func publishOnPath(_ publication: MqttPathPublication) async -> MqttPublishResult
  func outstandingDurableMessageIds() async -> Set<String>
  func disconnect()
}

enum MqttBrokerPathPolicy {
  static func readyGenerations(_ snapshots: [String: MqttBrokerPathSnapshot], topics: Set<String>) -> [String: Int64] {
    snapshots.filter { MqttRouteProtocol.brokerIDs.contains($0.key) && $0.value.isReady(for: topics) }
      .mapValues(\.generation)
  }

  static func accepts(_ publication: MqttPathPublication, snapshot: MqttBrokerPathSnapshot,
                      currentSecretFingerprint: String) -> Bool {
    publication.configurationID == snapshot.configurationID &&
      publication.generation == snapshot.generation && snapshot.isReady(for: publication.receiveTopics) &&
      !publication.secretFingerprint.isEmpty && publication.secretFingerprint == currentSecretFingerprint
  }

  static func acknowledgedTopics(_ codes: [UInt8], requested: Set<String>) -> Set<String>? {
    guard codes.count == requested.count, codes.allSatisfy({ [0, 1, 2, 0x80].contains($0) }) else { return nil }
    return Set(zip(requested.sorted(), codes).filter { $0.1 != 0x80 }.map(\.0))
  }

  static func expiredSubscriptionIDs(_ sentAt: [UInt16: Int64], now: Int64) -> [UInt16] {
    sentAt.filter { now >= $0.value && now - $0.value >= 15_000 }.map(\.key).sorted()
  }
}

struct MqttConnectionLiveness {
  enum Action: Equatable { case none, ping, reconnect }
  private(set) var lastOutbound: Int64 = 0
  private(set) var pingSentAt: Int64?

  mutating func connected(at now: Int64) { lastOutbound = now; pingSentAt = nil }
  mutating func sent(at now: Int64) { lastOutbound = now }
  mutating func received(at now: Int64, pingResponse: Bool) {
    if pingResponse { pingSentAt = nil }
  }
  mutating func check(at now: Int64) -> Action {
    if let pingSentAt { return now - pingSentAt >= 30_000 ? .reconnect : .none }
    guard now - lastOutbound >= 15_000 else { return .none }
    pingSentAt = now
    lastOutbound = now
    return .ping
  }
}

// Shared by all fragments and their reconnect retries, confined to the path queue.
final class MqttPublishAckGroup {
  private var remaining: Set<Int>

  init(packetCount: Int) { remaining = Set(0..<max(0, packetCount)) }

  func acknowledge(_ index: Int) -> Bool {
    guard remaining.remove(index) != nil else { return false }
    return remaining.isEmpty
  }
}
