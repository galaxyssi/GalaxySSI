import Foundation

// Process-local observations, accessed only while the multipath policy lock is held.
final class MqttChunkThroughput {
  struct Chunk {
    let transfer: String
    let request: String
    let index: Int
    let sampleEligible: Bool
  }
  private struct Key: Hashable { let peer: String; let transfer: String; let request: String; let index: Int }
  private struct PeerPath: Hashable { let peer: String; let broker: String }
  private struct Flight { let broker: String; let generation: Int64; let bytes: Int; let started: Int64; var eligible: Bool }
  private struct Rate { let updated: Int64; let bytesPerSecond: Double; let samples: Int; let window: Int }
  private static let initialWindow = 256 * 1024
  private static let minimumWindow = 128 * 1024
  private static let maximumWindow = 512 * 1024
  private var flights: [Key: Flight] = [:]
  private var rates: [PeerPath: Rate] = [:]

  func expire(now: Int64) {
    let expiredPaths = Set(flights.compactMap { key, flight -> PeerPath? in
      guard now >= flight.started, now - flight.started > 30_000 else { return nil }
      return PeerPath(peer: key.peer, broker: flight.broker)
    })
    for key in expiredPaths {
      let old = rates[key]
      rates[key] = Rate(updated: now, bytesPerSecond: old?.bytesPerSecond ?? 262_144,
        samples: old?.samples ?? 0, window: max(Self.minimumWindow, (old?.window ?? Self.initialWindow) / 2))
    }
    flights = flights.filter { now >= $0.value.started && now - $0.value.started <= 30_000 }
    rates = rates.filter { now >= $0.value.updated && now - $0.value.updated <= 300_000 }
  }

  func track(peer: String, chunk: Chunk, broker: String, generation: Int64, bytes: Int, now: Int64) {
    expire(now: now)
    flights = flights.filter { $0.key.peer != peer || $0.key.transfer != chunk.transfer || $0.key.request == chunk.request }
    let key = Key(peer: peer, transfer: chunk.transfer, request: chunk.request, index: chunk.index)
    if var previous = flights[key] {
      previous.eligible = false
      flights[key] = previous
    } else if flights.count < 4096 {
      flights[key] = Flight(broker: broker, generation: generation, bytes: bytes, started: now, eligible: chunk.sampleEligible)
    }
  }

  func discard(peer: String, chunk: Chunk) {
    flights.removeValue(forKey: Key(peer: peer, transfer: chunk.transfer, request: chunk.request, index: chunk.index))
  }
  func pending(peer: String, chunk: Chunk, now: Int64) -> Bool {
    expire(now: now)
    return flights[Key(peer: peer, transfer: chunk.transfer, request: chunk.request, index: chunk.index)] != nil
  }

  func confirmed(peer: String, transfer: String, request: String, indices: Set<Int>, generations: [String: Int64], now: Int64) {
    expire(now: now)
    let observed = indices.compactMap { flights.removeValue(forKey: Key(peer: peer, transfer: transfer, request: request, index: $0)) }
      .filter { $0.eligible && generations[$0.broker] == $0.generation }
    for (broker, values) in Dictionary(grouping: observed, by: \.broker) {
      guard let start = values.map(\.started).min(), now > start else { continue }
      let sample = Double(values.reduce(0) { $0 + $1.bytes }) * 1000 / Double(max(20, now - start))
      let key = PeerPath(peer: peer, broker: broker)
      let old = rates[key]
      let measured = old.map { $0.samples == 0 ? sample : $0.bytesPerSecond * 0.75 + sample * 0.25 } ?? sample
      rates[key] = Rate(updated: now, bytesPerSecond: measured,
        samples: min(32, (old?.samples ?? 0) + 1),
        window: min(Self.maximumWindow, (old?.window ?? Self.initialWindow) + values.reduce(0) { $0 + $1.bytes }))
    }
  }

  func pendingBytes(broker: String) -> Int { flights.values.filter { $0.broker == broker }.reduce(0) { $0 + $1.bytes } }
  func canSend(peer: String, broker: String, bytes: Int) -> Bool {
    guard bytes > 0 else { return false }
    let pending = pendingBytes(broker: broker)
    let window = rates[PeerPath(peer: peer, broker: broker)]?.window ?? Self.initialWindow
    // A persisted legacy fragment larger than the window can still make progress on an idle path.
    return pending == 0 || (pending <= window && bytes <= window - pending)
  }
  func rate(peer: String, broker: String) -> Double {
    guard let rate = rates[PeerPath(peer: peer, broker: broker)], rate.samples >= 3 else { return 262_144 }
    return rate.bytesPerSecond
  }
  func forget(peer: String) {
    flights = flights.filter { $0.key.peer != peer }
    rates = rates.filter { $0.key.peer != peer }
  }
  func reset() { flights.removeAll(); rates.removeAll() }
}
