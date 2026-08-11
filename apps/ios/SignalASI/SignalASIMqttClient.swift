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

protocol SignalASILinkTransport: AnyObject {
  var onMessage: ((String, Data) -> Void)? { get set }
  func connect(clientId: String, serverLinks: [ServerLink])
  func publish(topic: String, payload: Data) async -> MqttPublishResult
}

final class SignalASIMqttClient: ObservableObject, SignalASILinkTransport {
  @Published private(set) var isConnected = false
  var onMessage: ((String, Data) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onTransportRecovery: (() -> Void)?

  private static let brokerAckTimeoutSeconds: TimeInterval = 12
  private static let reconnectDelays: [TimeInterval] = [2, 5, 10, 20, 30]
  private let host = NWEndpoint.Host("broker.emqx.io")
  private let port = NWEndpoint.Port(rawValue: 8883)!
  private let queue = DispatchQueue(label: "com.signalasi.ios.mqtt")
  private let inboundChunkAssembler = SignalASIMqttChunkAssembler()
  private let diagnosticLedger: SignalASILinkDiagnosticLedger
  private let brokerAckWatchdog = MqttBrokerAckWatchdog(timeoutSeconds: Self.brokerAckTimeoutSeconds)
  private var connection: NWConnection?
  private var brokerAckWorkItem: DispatchWorkItem?
  private var reconnectWorkItem: DispatchWorkItem?
  private var reconnectAttempt = 0
  private var transportRecoveryInProgress = false
  private var clientId = ""
  private var subscriptions: [String] = []
  private var receiveBuffer = Data()
  private var packetIdentifier: UInt16 = 1
  private var queuedPublishes: [(topic: String, payload: Data)] = []
  private var connected = false

  init(diagnosticLedger: SignalASILinkDiagnosticLedger = SignalASILinkTransportDiagnostics.runtimeLedger()) {
    self.diagnosticLedger = diagnosticLedger
  }

  func connect(clientId: String, serverLinks: [ServerLink]) {
    self.clientId = clientId
    subscriptions = serverLinks.flatMap { [$0.routes.downTopic, $0.routes.controlTopic] }
    queue.async {
      if self.connection != nil {
        self.subscribeToCurrentTopics()
        return
      }
      self.reconnectWorkItem?.cancel()
      self.reconnectWorkItem = nil
      self.start()
    }
  }

  func publish(topic: String, payload: Data) async -> MqttPublishResult {
    await withCheckedContinuation { continuation in
      queue.async {
        guard self.connection != nil, self.connected else {
          self.queuedPublishes.append((topic, payload))
          continuation.resume(returning: .queued)
          return
        }
        continuation.resume(returning: self.sendWirePayload(topic: topic, payload: payload) ? .published : .failed)
      }
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
    payload.appendUTF8(clientId.ifBlank("signalasi-ios-\(UUID().uuidString)"))
    sendFrame(typeAndFlags: 0x10, variableHeader + payload)
  }

  private func subscribeToCurrentTopics() {
    guard !subscriptions.isEmpty else { return }
    let packetId = nextPacketIdentifier()
    var payload = Data()
    payload.appendUInt16(packetId)
    subscriptions.forEach { topic in
      payload.appendUTF8(topic)
      payload.append(0x01)
    }
    sendFrame(typeAndFlags: 0x82, payload)
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

  private func sendWirePayload(topic: String, payload: Data) -> Bool {
    let wirePayload = String(decoding: payload, as: UTF8.self)
    guard let packets = try? SignalASIMqttWireChunking.encode(wirePayload: wirePayload) else {
      return false
    }
    packets.forEach { packet in
      let packetId = sendPublish(topic: topic, payload: Data(packet.utf8))
      brokerAckWatchdog.onPublished(packetId: packetId)
    }
    scheduleBrokerAckWatchdog()
    return true
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
        scheduleBrokerAckWatchdog()
      }
    case 9, 13:
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
    let payload = Data(packet.payload.suffix(from: index))
    if let rawObject = try? JSONSerialization.jsonObject(with: payload),
       let object = rawObject as? [String: Any],
       SignalASIMqttWireChunking.isChunk(object) {
      do {
        guard let assembled = try inboundChunkAssembler.accept(scope: topic, wire: object) else {
          return
        }
        DispatchQueue.main.async {
          self.onMessage?(topic, Data(assembled.utf8))
        }
      } catch {
        diagnosticLedger.record(
          kind: SignalASILinkTransportDiagnostics.classifyFragmentFailure(error),
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
    let pending = queuedPublishes
    queuedPublishes.removeAll()
    pending.forEach { _ = sendWirePayload(topic: $0.topic, payload: $0.payload) }
  }

  private func nextPacketIdentifier() -> UInt16 {
    packetIdentifier = packetIdentifier == UInt16.max ? 1 : packetIdentifier + 1
    return packetIdentifier
  }

  private func setConnected(_ value: Bool) {
    connected = value
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
    if let age = brokerAckWatchdog.oldestPendingAge(),
       age >= Self.brokerAckTimeoutSeconds {
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
    setConnected(false)
    scheduleReconnect()
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

private struct MQTTPacket {
  var header: UInt8
  var payload: Data
}
