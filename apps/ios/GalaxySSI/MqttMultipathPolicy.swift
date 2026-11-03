import Foundation

// Scheduling only. The caller authenticates and commits peer receipts before confirming them here.
final class MqttMultipathPolicy {
  enum Traffic: String, Codable { case control, message, `final`, progress, chunk, receipt }
  struct PeerRoute: Equatable {
    let epoch: Int64
    let receiveBrokers: Set<String>
    let packetBytes: Int
    let chunkACKs: Bool
    let expiresAt: Int64
  }
  struct Dispatch: Equatable { let brokerID: String; let generation: Int64; let delayMillis: Int64 }
  struct Attempt {
    let peer: String
    let messageID: String
    let contentHash: String
    let brokerID: String
    let generation: Int64
    let wireBytes: Int
    let traffic: Traffic
    let startedAt: Int64
    fileprivate var slotHeld = true
    fileprivate var peerAccepted = false

    init(peer: String, messageID: String, contentHash: String, brokerID: String, generation: Int64,
         wireBytes: Int, traffic: Traffic, startedAt: Int64) {
      self.peer = peer
      self.messageID = messageID
      self.contentHash = contentHash
      self.brokerID = brokerID
      self.generation = generation
      self.wireBytes = wireBytes
      self.traffic = traffic
      self.startedAt = startedAt
    }
  }
  struct DeliveryStats: Equatable { let samples: Int; let p50: Int64?; let p95: Int64?; let latest: Int64? }
  struct Diagnostics {
    let inflightPackets: Int
    let inflightBytes: Int
    let pendingAttempts: Int
    let verifiedDelivery: [String: DeliveryStats]
  }
  private struct Path {
    var generation: Int64 = 0
    var connected = false
    var packetBytes = MqttRouteProtocol.packetBytes
    var topics = Set<String>()
    var configurationID = ""
  }
  private struct PeerPath: Hashable { let peer: String; let broker: String }
  private struct Sample { let peer: String; let at: Int64; let elapsed: Int64 }
  private let lock = NSRecursiveLock()
  private let tieSeed: Data
  private var paths = Dictionary(uniqueKeysWithValues: MqttRouteProtocol.brokerIDs.map { ($0, Path()) })
  private var routes: [String: PeerRoute] = [:]
  private var attempts: [String: Attempt] = [:]
  private var rtt: [PeerPath: [Sample]] = [:]
  private var samplesByBroker: [String: [Sample]] = [:]
  private var network = ""
  private let chunks = MqttChunkThroughput()

  init(tieSeed: Data = Data(UUID().uuidString.utf8)) { self.tieSeed = tieSeed }

  // Called by the broker pool after it has fenced stale configuration/generation callbacks.
  func synchronize(_ snapshots: [String: MqttBrokerPathSnapshot]) {
    locked {
      for broker in MqttRouteProtocol.brokerIDs {
        guard var path = paths[broker] else { continue }
        guard let snapshot = snapshots[broker], snapshot.brokerID == broker else {
          releasePath(broker, generation: path.generation)
          path.connected = false
          path.topics.removeAll()
          paths[broker] = path
          continue
        }
        guard snapshot.generation >= path.generation, !snapshot.connected || snapshot.generation > 0 else { continue }
        if snapshot.generation != path.generation || snapshot.configurationID != path.configurationID || !snapshot.connected {
          releasePath(broker, generation: path.generation)
        }
        path.generation = snapshot.generation
        path.configurationID = snapshot.configurationID
        path.connected = snapshot.connected
        path.topics = snapshot.connected ? snapshot.subscriptions : []
        paths[broker] = path
      }
    }
  }

  func setNetwork(_ value: String) {
    locked {
      guard network != value else { return }
      network = value
      rtt.removeAll()
      samplesByBroker.removeAll()
      chunks.reset()
    }
  }

  @discardableResult
  func acceptVerifiedResume(peer: String, route: PeerRoute, now: Int64) -> Bool {
    locked {
      guard !peer.isEmpty, (1...MqttRouteProtocol.maximumInteger).contains(route.epoch),
            route.receiveBrokers.isSubset(of: MqttRouteProtocol.brokerIDs),
            (1...MqttRouteProtocol.packetBytes).contains(route.packetBytes), now >= 0,
            route.expiresAt > now, route.expiresAt - now <= MqttRouteProtocol.resumeTTL else { return false }
      if let previous = routes[peer], route.epoch <= previous.epoch { return route == previous }
      guard routes[peer] != nil || routes.count < 10_000 else { return false }
      routes[peer] = route
      return true
    }
  }

  func forgetPeer(_ peer: String) {
    locked {
      chunks.forget(peer: peer)
      routes.removeValue(forKey: peer)
      rtt = rtt.filter { $0.key.peer != peer }
      for broker in MqttRouteProtocol.brokerIDs { samplesByBroker[broker]?.removeAll { $0.peer == peer } }
      attempts = attempts.filter { $0.value.peer != peer }
    }
  }

  func readyBrokers(receiveTopics: Set<String>) -> Set<String> {
    locked { Set(paths.filter { $0.value.connected && !receiveTopics.isEmpty && $0.value.topics.isSuperset(of: receiveTopics) }.keys) }
  }

  func plan(peer: String, messageID: String, traffic: Traffic, wireBytes: Int, receiveTopics: Set<String>, now: Int64,
            ingress: String? = nil, attempted: Set<String> = []) -> [Dispatch] {
    locked {
      chunks.expire(now: now)
      guard now >= 0, !messageID.isEmpty, (1...MqttRouteProtocol.packetBytes).contains(wireBytes), let route = routes[peer],
            route.expiresAt > now, wireBytes <= route.packetBytes, traffic != .chunk || route.chunkACKs else { return [] }
      let common = readyBrokers(receiveTopics: receiveTopics).intersection(route.receiveBrokers)
        .filter { wireBytes <= (paths[$0]?.packetBytes ?? 0) }
      let unused = common.subtracting(attempted)
      var candidates = Array(unused.isEmpty ? common : unused).sorted {
        let left = score(peer: peer, broker: $0, traffic: traffic, bytes: wireBytes, now: now)
        let right = score(peer: peer, broker: $1, traffic: traffic, bytes: wireBytes, now: now)
        if left != right { return left < right }
        return tie(peer, messageID, $0) < tie(peer, messageID, $1)
      }
      if traffic == .receipt, let ingress, candidates.contains(ingress) {
        candidates.removeAll { $0 == ingress }
        candidates.insert(ingress, at: 0)
      }
      guard let first = candidates.first else { return [] }
      if traffic == .control, wireBytes <= 65_536 {
        return candidates.map { Dispatch(brokerID: $0, generation: paths[$0]!.generation, delayMillis: 0) }
      }
      var result = [Dispatch(brokerID: first, generation: paths[first]!.generation, delayMillis: 0)]
      if wireBytes <= 65_536, [Traffic.message, .final].contains(traffic), candidates.count > 1 {
        let primary = samples(peer: peer, broker: first, now: now)
        let values = (primary.count >= 20 ? primary : candidates.flatMap { samples(peer: peer, broker: $0, now: now) }).sorted()
        let delay: Int64 = values.count < 20 ? 2000 : Int64(min(2000, max(100, Double(values[Int(ceil(Double(values.count) * 0.9)) - 1]) * 1.5)))
        for (index, broker) in candidates.dropFirst().enumerated() {
          result.append(Dispatch(brokerID: broker, generation: paths[broker]!.generation, delayMillis: delay * Int64(index + 1)))
        }
      }
      return result
    }
  }

  @discardableResult
  func reserve(attemptID: String, attempt: Attempt) -> Bool {
    locked {
      let priority = [Traffic.control, .receipt, .final].contains(attempt.traffic)
      let reserveBytes = priority ? 0 : 2 * 65_536
      guard !attemptID.isEmpty, !attempt.peer.isEmpty, !attempt.messageID.isEmpty, attempt.startedAt >= 0,
            MqttRouteProtocol.hex(attempt.contentHash, count: 64), (1...MqttRouteProtocol.packetBytes).contains(attempt.wireBytes),
            let path = paths[attempt.brokerID], path.connected, path.generation == attempt.generation,
            attempt.wireBytes <= path.packetBytes, attempts[attemptID] == nil, attempts.count < (priority ? 4096 : 4094),
            !attempts.values.contains(where: { $0.peer == attempt.peer && $0.messageID == attempt.messageID && $0.contentHash != attempt.contentHash }) else { return false }
      let active = attempts.values.filter(\.slotHeld)
      guard active.count < (priority ? 12 : 10), active.reduce(0, { $0 + $1.wireBytes }) + attempt.wireBytes <= 8_388_608 - reserveBytes,
            active.filter({ $0.peer == attempt.peer }).reduce(0, { $0 + $1.wireBytes }) + attempt.wireBytes <= 2_097_152 - reserveBytes else { return false }
      var clean = attempt
      clean.slotHeld = true
      clean.peerAccepted = false
      attempts[attemptID] = clean
      return true
    }
  }

  @discardableResult
  func brokerAck(attemptID: String, broker: String, generation: Int64) -> Bool {
    locked {
      guard var attempt = attempts[attemptID], attempt.brokerID == broker, attempt.generation == generation else { return false }
      attempt.slotHeld = false
      if attempt.peerAccepted { attempts.removeValue(forKey: attemptID) }
      else { attempts[attemptID] = attempt }
      return true
    }
  }

  @discardableResult
  func acceptVerifiedReceipt(peer: String, messageID: String, contentHash: String, attemptID: String, now: Int64) -> Set<String> {
    locked {
      guard let accepted = attempts[attemptID], !accepted.peerAccepted, accepted.peer == peer,
            accepted.messageID == messageID, accepted.contentHash == contentHash else { return [] }
      if now >= accepted.startedAt {
        let sample = Sample(peer: peer, at: now, elapsed: now - accepted.startedAt)
        let key = PeerPath(peer: peer, broker: accepted.brokerID)
        var values = rtt[key, default: []]
        values.append(sample)
        rtt[key] = Array(values.suffix(32))
        var recent = samplesByBroker[accepted.brokerID, default: []]
        recent.append(sample)
        samplesByBroker[accepted.brokerID] = Array(recent.suffix(32))
      }
      return acceptVerifiedMessage(peer: peer, messageID: messageID, contentHash: contentHash)
    }
  }

  @discardableResult
  func acceptVerifiedMessage(peer: String, messageID: String, contentHash: String) -> Set<String> {
    locked {
      let completed = Set(attempts.filter { $0.value.peer == peer && $0.value.messageID == messageID && $0.value.contentHash == contentHash }.keys)
      for id in completed {
        guard var attempt = attempts[id] else { continue }
        attempt.peerAccepted = true
        if attempt.slotHeld { attempts[id] = attempt } else { attempts.removeValue(forKey: id) }
      }
      return completed
    }
  }

  func discardAttempt(_ id: String) { locked { _ = attempts.removeValue(forKey: id) } }
  func pending(peer: String, messageID: String) -> Bool {
    locked { attempts.values.contains { $0.peer == peer && $0.messageID == messageID && !$0.peerAccepted } }
  }
  @discardableResult
  func expireAttempts(before: Int64) -> Set<String> {
    locked {
      let expired = Set(attempts.filter { $0.value.startedAt < before }.keys)
      expired.forEach { attempts.removeValue(forKey: $0) }
      return expired
    }
  }

  func trackChunk(peer: String, chunk: MqttChunkThroughput.Chunk, broker: String, generation: Int64, bytes: Int, now: Int64) {
    locked {
      guard routes[peer] != nil, paths[broker]?.connected == true, paths[broker]?.generation == generation,
            (1...MqttRouteProtocol.packetBytes).contains(bytes), now >= 0 else { return }
      chunks.track(peer: peer, chunk: chunk, broker: broker, generation: generation, bytes: bytes, now: now)
    }
  }
  func discardChunk(peer: String, chunk: MqttChunkThroughput.Chunk) { locked { chunks.discard(peer: peer, chunk: chunk) } }
  func confirmChunkState(peer: String, transfer: String, request: String, indices: Set<Int>, now: Int64) {
    locked {
      chunks.confirmed(peer: peer, transfer: transfer, request: request, indices: indices,
                       generations: paths.filter { $0.value.connected }.mapValues(\.generation), now: now)
    }
  }

  func diagnostics(now: Int64) -> Diagnostics {
    locked {
      let summaries = Dictionary(uniqueKeysWithValues: MqttRouteProtocol.brokerIDs.map { broker in
        let fresh = samplesByBroker[broker, default: []].filter { now >= $0.at && now - $0.at <= 300_000 }
        let sorted = fresh.map(\.elapsed).sorted()
        let p50 = sorted.isEmpty ? nil : sorted[Int(ceil(Double(sorted.count) * 0.5)) - 1]
        let p95 = sorted.count < 30 ? nil : sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
        return (broker, DeliveryStats(samples: sorted.count, p50: p50, p95: p95, latest: fresh.last?.elapsed))
      })
      let active = attempts.values.filter(\.slotHeld)
      return Diagnostics(inflightPackets: active.count, inflightBytes: active.reduce(0) { $0 + $1.wireBytes },
                         pendingAttempts: attempts.count, verifiedDelivery: summaries)
    }
  }

  private func releasePath(_ broker: String, generation: Int64) {
    for id in Array(attempts.keys) {
      guard var attempt = attempts[id], attempt.brokerID == broker, attempt.generation == generation else { continue }
      attempt.slotHeld = false
      if attempt.peerAccepted { attempts.removeValue(forKey: id) } else { attempts[id] = attempt }
    }
  }
  private func samples(peer: String, broker: String, now: Int64) -> [Int64] {
    let key = PeerPath(peer: peer, broker: broker)
    let fresh = rtt[key, default: []].filter { now >= $0.at && now - $0.at <= 300_000 }
    if fresh.isEmpty { rtt.removeValue(forKey: key) } else { rtt[key] = fresh }
    return fresh.map(\.elapsed)
  }
  private func score(peer: String, broker: String, traffic: Traffic, bytes: Int, now: Int64) -> Double {
    let values = samples(peer: peer, broker: broker, now: now)
    let latency = values.isEmpty ? 500 : values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
    let load = attempts.values.filter { $0.brokerID == broker && $0.slotHeld }.reduce(0) { $0 + $1.wireBytes }
    if traffic == .chunk { return latency + Double(bytes + max(load, chunks.pendingBytes(broker: broker))) * 1000 / chunks.rate(peer: peer, broker: broker) }
    return latency * (1 + Double(load) / 2_097_152)
  }
  private func tie(_ peer: String, _ message: String, _ broker: String) -> String {
    MqttRouteProtocol.digest(tieSeed + Data("\(peer)\0\(message)\0\(broker)".utf8))
  }
  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}
