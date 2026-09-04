import CryptoKit
import Foundation
import Network
import SwiftUI

enum MqttPublishResult: Equatable {
  case published
  case queued
  case failed

  var accepted: Bool {
    switch self {
    case .published, .queued:
      return true
    case .failed:
      return false
    }
  }
}

protocol GalaxySSILinkTransport: AnyObject {
  var onMessage: ((String, Data) -> Void)? { get set }
  func connect(clientId: String, serverLinks: [ServerLink])
  func publish(topic: String, payload: Data) async -> MqttPublishResult
}

final class GalaxySSIMqttClient: ObservableObject, GalaxySSILinkTransport {
  @Published private(set) var isConnected = false
  var onMessage: ((String, Data) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onTransportRecovery: (() -> Void)?
  var onRelationshipSubscriptionsReady: (() -> Void)?

  private static let reconnectDelays: [TimeInterval] = [2, 5, 10, 20, 30]
  private static let maximumMqttInflight = 12
  private static let maximumFragmentInflight = 8
  private static let maximumFragmentInflightPerTransfer = 4
  private let host = NWEndpoint.Host("broker.emqx.io")
  private let port = NWEndpoint.Port(rawValue: 8883)!
  private let queue = DispatchQueue(label: "com.galaxyssi.ios.mqtt")
  private let inboundChunkAssembler = GalaxySSIMqttChunkAssembler()
  private let diagnosticLedger: GalaxySSILinkDiagnosticLedger
  private let brokerAckWatchdog = MqttBrokerAckWatchdog(
    timeoutSeconds: MqttBrokerAckTimeoutPolicy.defaultTimeoutSeconds
  )
  private struct PendingPublish {
    var topic: String
    var payload: Data
    var transferId: String?
    var relationshipBound: Bool
    var brokerAckTimeoutSeconds: TimeInterval
  }
  private var connection: NWConnection?
  private var brokerAckWorkItem: DispatchWorkItem?
  private var reconnectWorkItem: DispatchWorkItem?
  private var topicRotationWorkItem: DispatchWorkItem?
  private var reconnectAttempt = 0
  private var transportRecoveryInProgress = false
  private var subscriptions: [String] = []
  private var activeSubscriptions: Set<String> = []
  private var pendingSubscriptions: [UInt16: Set<String>] = [:]
  private var serverLinks: [ServerLink] = []
  private var phoneRoutes: [GalaxySSILinkRoutes] = []
  private var rendezvousSecrets: [String: String] = [:]
  private var rendezvousExpirations: [String: Date] = [:]
  private var receiveBuffer = Data()
  private var packetIdentifier: UInt16 = 1
  private var pendingPacketPublishes: [PendingPublish] = []
  private var inFlightPublishes: [UInt16: PendingPublish] = [:]
  private var fragmentTransferByPacketId: [UInt16: String] = [:]
  private var fragmentInflightByTransfer: [String: Int] = [:]
  private var fragmentInflight = 0
  private var mqttInflightPacketIds: Set<UInt16> = []
  private var connected = false
  private var clientId = GalaxySSIMqttClientId.opaque(from: "galaxyssi-ios")

  init(diagnosticLedger: GalaxySSILinkDiagnosticLedger = GalaxySSILinkTransportDiagnostics.runtimeLedger()) {
    self.diagnosticLedger = diagnosticLedger
  }

  func connect(clientId: String, serverLinks: [ServerLink]) {
    connect(
      clientId: clientId,
      serverLinks: serverLinks,
      phoneContactInboxTopic: ""
    )
  }

  func connect(
    clientId: String,
    serverLinks: [ServerLink],
    phoneContactInboxTopic: String,
    phoneRoutes: [GalaxySSILinkRoutes] = [],
    rendezvousSecrets: [String: String] = [:],
    rendezvousExpirations: [String: Date] = [:]
  ) {
    let nextClientId = GalaxySSIMqttClientId.opaque(from: clientId)
    updateSubscriptions(
      serverLinks: serverLinks,
      phoneContactInboxTopic: phoneContactInboxTopic,
      phoneRoutes: phoneRoutes,
      rendezvousSecrets: rendezvousSecrets,
      rendezvousExpirations: rendezvousExpirations
    )
    queue.async {
      let clientIdChanged = self.clientId != nextClientId
      self.clientId = nextClientId
      if self.connection != nil {
        if clientIdChanged {
          self.connection?.cancel()
        }
        return
      }
      self.reconnectWorkItem?.cancel()
      self.reconnectWorkItem = nil
      self.start()
    }
  }

  func updateSubscriptions(
    serverLinks: [ServerLink],
    phoneContactInboxTopic: String? = nil,
    phoneRoutes: [GalaxySSILinkRoutes]? = nil,
    rendezvousSecrets: [String: String]? = nil,
    rendezvousExpirations: [String: Date]? = nil
  ) {
    queue.async {
      self.serverLinks = serverLinks.filter { $0.routes.isOpaqueV2Valid }
      if let phoneRoutes { self.phoneRoutes = phoneRoutes.filter(\.isOpaqueV2Valid) }
      if let rendezvousSecrets {
        self.rendezvousSecrets = rendezvousSecrets.filter {
          GalaxySSILinkProtocol.validTopic($0.key) && GalaxySSILinkProtocol.validLinkSecret($0.value)
        }
      }
      if let rendezvousExpirations { self.rendezvousExpirations = rendezvousExpirations }
      self.refreshRotatingSubscriptions()
    }
  }

  func publish(topic: String, payload: Data) async -> MqttPublishResult {
    await withCheckedContinuation { continuation in
      queue.async {
        guard let secret = self.relationshipSecret(forSendingTopic: topic),
              self.sendWirePayload(topic: topic, payload: payload, secret: secret) else {
          continuation.resume(returning: .failed)
          return
        }
        continuation.resume(returning: self.connected ? .published : .queued)
      }
    }
  }

  func publishPairing(topic: String, secret: String, payload: Data) async -> MqttPublishResult {
    await withCheckedContinuation { continuation in
      queue.async {
        guard GalaxySSILinkProtocol.validTopic(topic),
              GalaxySSILinkProtocol.validLinkSecret(secret),
              let sealed = try? GalaxySSILinkProtocol.sealWirePacket(payload, secret: secret) else {
          continuation.resume(returning: .failed)
          return
        }
        self.pendingPacketPublishes.append(
          PendingPublish(
            topic: topic,
            payload: sealed,
            transferId: nil,
            relationshipBound: false,
            brokerAckTimeoutSeconds: MqttBrokerAckTimeoutPolicy.defaultTimeoutSeconds
          )
        )
        self.pumpPendingPublishes()
        continuation.resume(returning: self.connected ? .published : .queued)
      }
    }
  }

  func unsubscribe(topics: [String]) {
    let cleanTopics = topics
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !cleanTopics.isEmpty else { return }
    queue.async {
      guard self.connected, self.connection != nil else { return }
      self.sendUnsubscribe(cleanTopics)
      self.activeSubscriptions.subtract(cleanTopics)
    }
  }

  private func start() {
    guard connection == nil else { return }
    let parameters = NWParameters.tls
    let mqttConnection = NWConnection(host: host, port: port, using: parameters)
    connection = mqttConnection
    mqttConnection.stateUpdateHandler = { [weak self, weak mqttConnection] state in
      guard let self, let mqttConnection, self.connection === mqttConnection else { return }
      switch state {
      case .ready:
        self.reconnectAttempt = 0
        self.reconnectWorkItem?.cancel()
        self.reconnectWorkItem = nil
        self.sendConnect()
        self.receiveLoop(for: mqttConnection)
      case .failed, .cancelled:
        self.handleTransportFailure(for: mqttConnection)
      default:
        break
      }
    }
    mqttConnection.start(queue: queue)
  }

  private func sendConnect() {
    var variableHeader = Data()
    variableHeader.appendUTF8("MQTT")
    variableHeader.append(0x04)
    variableHeader.append(0x00)
    variableHeader.appendUInt16(30)

    var payload = Data()
    payload.appendUTF8(clientId)
    sendFrame(typeAndFlags: 0x10, variableHeader + payload)
  }

  private func subscribeToCurrentTopics() {
    let expected = Set(subscriptions)
    let stale = activeSubscriptions.subtracting(expected)
    if !stale.isEmpty {
      sendUnsubscribe(Array(stale).sorted())
      activeSubscriptions.subtract(stale)
    }
    let pending = pendingSubscriptions.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    let missing = expected.subtracting(activeSubscriptions).subtracting(pending)
    guard !missing.isEmpty else { return }
    let packetId = nextPacketIdentifier()
    var payload = Data()
    payload.appendUInt16(packetId)
    missing.sorted().forEach { topic in
      payload.appendUTF8(topic)
      payload.append(0x01)
    }
    sendFrame(typeAndFlags: 0x82, payload)
    pendingSubscriptions[packetId] = missing
  }

  private func sendUnsubscribe(_ topics: [String]) {
    guard !topics.isEmpty else { return }
    var body = Data()
    body.appendUInt16(nextPacketIdentifier())
    topics.forEach { body.appendUTF8($0) }
    sendFrame(typeAndFlags: 0xA2, body)
  }

  private func sendPublish(topic: String, payload: Data) -> UInt16 {
    let packetId = nextPacketIdentifier()
    var body = Data()
    body.appendUTF8(topic)
    body.appendUInt16(packetId)
    body.append(payload)
    sendFrame(typeAndFlags: 0x32, body)
    return packetId
  }

  private func sendWirePayload(topic: String, payload: Data, secret: String) -> Bool {
    let wirePayload = String(decoding: payload, as: UTF8.self)
    guard let packets = try? GalaxySSIMqttWireChunking.encode(wirePayload: wirePayload) else {
      return false
    }
    let transferId = packets.count > 1 ? Self.transferId(from: packets[0]) : nil
    let brokerAckTimeoutSeconds = MqttBrokerAckTimeoutPolicy.timeoutSeconds(
      wirePayloadBytes: payload.count
    )
    guard let sealedPackets = try? packets.map({ packet in
      try GalaxySSILinkProtocol.sealWirePacket(Data(packet.utf8), secret: secret)
    }) else {
      return false
    }
    pendingPacketPublishes.append(contentsOf: sealedPackets.map { packet in
      PendingPublish(
        topic: topic,
        payload: packet,
        transferId: transferId,
        relationshipBound: true,
        brokerAckTimeoutSeconds: brokerAckTimeoutSeconds
      )
    })
    pumpPendingPublishes()
    if connected {
      scheduleBrokerAckWatchdog()
    }
    return true
  }

  private func pumpPendingPublishes() {
    guard connected, connection != nil else { return }
    while mqttInflightPacketIds.count < Self.maximumMqttInflight {
      guard let index = pendingPacketPublishes.firstIndex(where: { canSend($0) }) else {
        break
      }
      let pending = pendingPacketPublishes.remove(at: index)
      let packetId = sendPublish(topic: pending.topic, payload: pending.payload)
      mqttInflightPacketIds.insert(packetId)
      inFlightPublishes[packetId] = pending
      brokerAckWatchdog.onPublished(
        packetId: packetId,
        timeoutSeconds: pending.brokerAckTimeoutSeconds
      )
      if let transferId = pending.transferId {
        fragmentInflight += 1
        fragmentInflightByTransfer[transferId, default: 0] += 1
        fragmentTransferByPacketId[packetId] = transferId
      }
    }
  }

  private func canSend(_ pending: PendingPublish) -> Bool {
    guard let transferId = pending.transferId else { return true }
    guard fragmentInflight < Self.maximumFragmentInflight else { return false }
    return fragmentInflightByTransfer[transferId, default: 0] < Self.maximumFragmentInflightPerTransfer
  }

  private static func transferId(from packet: String) -> String? {
    guard let data = packet.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          GalaxySSIMqttWireChunking.isChunk(object),
          let transferId = object["transfer_id"] as? String,
          !transferId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return transferId
  }

  private func sendPubAck(_ packetId: UInt16) {
    var body = Data()
    body.appendUInt16(packetId)
    sendFrame(typeAndFlags: 0x40, body)
  }

  private func sendFrame(typeAndFlags: UInt8, _ payload: Data) {
    var frame = Data([typeAndFlags])
    frame.appendEncodedRemainingLength(payload.count)
    frame.append(payload)
    guard let connection else { return }
    connection.send(content: frame, completion: .contentProcessed { [weak self, weak connection] error in
      guard let self, let connection, error != nil else { return }
      self.queue.async {
        guard self.connection === connection else { return }
        self.handleTransportFailure(for: connection)
      }
    })
  }

  private func receiveLoop(for connection: NWConnection) {
    guard self.connection === connection else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, _ in
      guard let self, let connection, self.connection === connection else { return }
      if let data, !data.isEmpty {
        self.receiveBuffer.append(data)
        self.consumePackets()
      }
      if isComplete {
        self.handleTransportFailure(for: connection)
      } else {
        self.receiveLoop(for: connection)
      }
    }
  }

  private func consumePackets() {
    while let packet = receiveBuffer.readMQTTPacket() {
      handle(packet)
    }
  }

  private func handle(_ packet: MQTTPacket) {
    let packetType = packet.header >> 4
    switch packetType {
    case 2:
      reconnectAttempt = 0
      setConnected(true)
      subscribeToCurrentTopics()
      flushQueuedPublishes()
    case 3:
      handlePublish(packet)
    case 4:
      var index = 0
      if let packetId = packet.payload.readUInt16(at: &index) {
        brokerAckWatchdog.onAcknowledged(packetId: packetId)
        if mqttInflightPacketIds.remove(packetId) != nil {
          inFlightPublishes.removeValue(forKey: packetId)
          if let transferId = fragmentTransferByPacketId.removeValue(forKey: packetId) {
            fragmentInflight = max(0, fragmentInflight - 1)
            let remaining = max(0, fragmentInflightByTransfer[transferId, default: 0] - 1)
            if remaining == 0 {
              fragmentInflightByTransfer.removeValue(forKey: transferId)
            } else {
              fragmentInflightByTransfer[transferId] = remaining
            }
          }
        }
        pumpPendingPublishes()
        scheduleBrokerAckWatchdog()
      }
    case 9:
      var index = 0
      guard let packetId = packet.payload.readUInt16(at: &index),
            let topics = pendingSubscriptions.removeValue(forKey: packetId) else { break }
      let codes = packet.payload.suffix(from: index)
      if codes.contains(0x80) {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
          self?.subscribeToCurrentTopics()
        }
      } else {
        activeSubscriptions.formUnion(topics.intersection(Set(subscriptions)))
        let expected = Set(subscriptions)
        if !expected.isEmpty, activeSubscriptions.isSuperset(of: expected) {
          DispatchQueue.main.async {
            self.onRelationshipSubscriptionsReady?()
          }
        }
      }
    case 11, 13:
      break
    default:
      break
    }
  }

  private func handlePublish(_ packet: MQTTPacket) {
    var index = 0
    guard let topic = packet.payload.readUTF8(at: &index) else { return }
    let qos = (packet.header >> 1) & 0x03
    if qos > 0, let packetId = packet.payload.readUInt16(at: &index) {
      sendPubAck(packetId)
    }
    let opaquePayload = Data(packet.payload.suffix(from: index))
    guard let secret = relationshipSecret(forReceivingTopic: topic),
          let payload = try? GalaxySSILinkProtocol.openWirePacket(opaquePayload, secret: secret) else {
      return
    }
    if let rawObject = try? JSONSerialization.jsonObject(with: payload),
       let object = rawObject as? [String: Any],
       GalaxySSIMqttWireChunking.isChunk(object) {
      do {
        guard let assembled = try inboundChunkAssembler.accept(scope: topic, wire: object) else {
          return
        }
        DispatchQueue.main.async {
          self.onMessage?(topic, Data(assembled.utf8))
        }
      } catch {
        diagnosticLedger.record(
          kind: GalaxySSILinkTransportDiagnostics.classifyFragmentFailure(error),
          endpointIdentity: topic,
          messageIdentity: object.string("transfer_id"),
          detailCode: String(describing: type(of: error))
        )
        return
      }
      return
    }
    DispatchQueue.main.async {
      self.onMessage?(topic, Data(payload))
    }
  }

  private func flushQueuedPublishes() {
    pumpPendingPublishes()
  }

  private func relationshipSecret(forSendingTopic topic: String) -> String? {
    serverLinks.first { $0.routes.sendWindow.contains(topic) }?.routes.linkSecret
      ?? phoneRoutes.first { $0.sendWindow.contains(topic) }?.linkSecret
  }

  private func relationshipSecret(forReceivingTopic topic: String) -> String? {
    rendezvousSecrets[topic]
      ?? serverLinks.first { $0.routes.receiveWindow.contains(topic) }?.routes.linkSecret
      ?? phoneRoutes.first { $0.receiveWindow.contains(topic) }?.linkSecret
  }

  private func refreshRotatingSubscriptions() {
    let now = Date()
    let expiredRendezvous = Set(rendezvousExpirations.filter { $0.value <= now }.keys)
    expiredRendezvous.forEach {
      rendezvousSecrets.removeValue(forKey: $0)
      rendezvousExpirations.removeValue(forKey: $0)
    }
    subscriptions = Array(serverLinks.reduce(into: Set<String>()) { topics, link in
      topics.formUnion(link.routes.receiveWindow)
    }.union(phoneRoutes.reduce(into: Set<String>()) { topics, routes in
      topics.formUnion(routes.receiveWindow)
    }).union(rendezvousSecrets.keys)).sorted()
    let validSendTopics = serverLinks.reduce(into: Set<String>()) { topics, link in
      topics.formUnion(link.routes.sendWindow)
    }.union(phoneRoutes.reduce(into: Set<String>()) { topics, routes in
      topics.formUnion(routes.sendWindow)
    })
    pendingPacketPublishes.removeAll {
      $0.relationshipBound && !validSendTopics.contains($0.topic)
    }
    if connected {
      subscribeToCurrentTopics()
    }
    scheduleTopicRotationRefresh()
  }

  private func scheduleTopicRotationRefresh() {
    topicRotationWorkItem?.cancel()
    guard connection != nil else { return }
    let item = DispatchWorkItem { [weak self] in
      self?.refreshRotatingSubscriptions()
    }
    topicRotationWorkItem = item
    let rendezvousDelay = rendezvousExpirations.values.min().map {
      max(1, $0.timeIntervalSinceNow + 1)
    }
    let delay = min(GalaxySSILinkProtocol.topicRefreshDelay(), rendezvousDelay ?? .infinity)
    queue.asyncAfter(
      deadline: .now() + delay,
      execute: item
    )
  }

  private func nextPacketIdentifier() -> UInt16 {
    packetIdentifier = packetIdentifier == UInt16.max ? 1 : packetIdentifier + 1
    return packetIdentifier
  }

  private func setConnected(_ value: Bool) {
    connected = value
    if value {
      scheduleTopicRotationRefresh()
    } else {
      topicRotationWorkItem?.cancel()
      topicRotationWorkItem = nil
      activeSubscriptions.removeAll()
      pendingSubscriptions.removeAll()
    }
    DispatchQueue.main.async {
      self.isConnected = value
      self.onConnectionChanged?(value)
    }
  }

  private func scheduleBrokerAckWatchdog() {
    brokerAckWorkItem?.cancel()
    guard connected, let delay = brokerAckWatchdog.nextCheckDelay() else {
      brokerAckWorkItem = nil
      return
    }
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.brokerAckWorkItem = nil
      self.checkBrokerAckWatchdog()
    }
    brokerAckWorkItem = workItem
    queue.asyncAfter(deadline: .now() + max(0.1, delay), execute: workItem)
  }

  private func checkBrokerAckWatchdog() {
    guard connected else { return }
    if brokerAckWatchdog.oldestTimedOutPendingAge() != nil {
      recoverStalledTransport()
    } else {
      scheduleBrokerAckWatchdog()
    }
  }

  private func recoverStalledTransport() {
    guard !transportRecoveryInProgress else { return }
    transportRecoveryInProgress = true
    let stalledConnection = connection
    connection = nil
    brokerAckWorkItem?.cancel()
    brokerAckWorkItem = nil
    brokerAckWatchdog.clear()
    resetOutboundInflightForReconnect()
    receiveBuffer.removeAll()
    inboundChunkAssembler.clear()
    setConnected(false)
    stalledConnection?.cancel()
    onTransportRecovery?()
    queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self else { return }
      self.transportRecoveryInProgress = false
      self.scheduleReconnect()
    }
  }

  private func handleTransportFailure(for failedConnection: NWConnection) {
    guard connection === failedConnection else { return }
    connection = nil
    inboundChunkAssembler.clear()
    receiveBuffer.removeAll()
    brokerAckWorkItem?.cancel()
    brokerAckWorkItem = nil
    brokerAckWatchdog.clear()
    resetOutboundInflightForReconnect()
    setConnected(false)
    scheduleReconnect()
  }

  private func resetOutboundInflightForReconnect() {
    if !inFlightPublishes.isEmpty {
      pendingPacketPublishes.insert(contentsOf: inFlightPublishes.values, at: 0)
    }
    inFlightPublishes.removeAll()
    fragmentTransferByPacketId.removeAll()
    fragmentInflightByTransfer.removeAll()
    fragmentInflight = 0
    mqttInflightPacketIds.removeAll()
  }

  private func scheduleReconnect() {
    guard connection == nil, !transportRecoveryInProgress, reconnectWorkItem == nil else { return }
    let index = min(reconnectAttempt, Self.reconnectDelays.count - 1)
    let delay = Self.reconnectDelays[index]
    reconnectAttempt += 1
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.reconnectWorkItem = nil
      self.start()
    }
    reconnectWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }
}

enum GalaxySSIMqttClientId {
  static func opaque(from source: String) -> String {
    let clean = source.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("galaxyssi-ios")
    let digest = SHA256.hash(data: Data(clean.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "gsi-\(digest.prefix(32))"
  }
}

struct MQTTPacket {
  var header: UInt8
  var payload: Data
}
