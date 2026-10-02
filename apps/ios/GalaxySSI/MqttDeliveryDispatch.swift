import Foundation

// Physical copies only. The durable business outbox still owns restart and logical retries.
actor MqttDeliveryDispatch {
  enum Failure: Error { case unavailable, capacity, invalidPacket }
  struct Delivery {
    let peer: String
    let message: MqttDeliveryEnvelope.Message
    let receiveTopics: Set<String>
    let sizeBound: Int
    // Returns the final pair-AEAD packet, including this physical attempt's metadata.
    let encodeAttempt: (MqttDeliveryEnvelope.Frame) throws -> Data
    let authorized: (String, Int64) -> Bool
  }
  struct Publication {
    let topic: String
    let payload: Data
    let frame: MqttDeliveryEnvelope.Frame
  }
  struct Diagnostics {
    let messages: Int
    let trackedAttempts: Int
    let queuedCopies: Int
    let bufferedBytes: Int
  }
  private struct Key: Hashable { let peer: String; let message: MqttDeliveryEnvelope.Message }
  private struct Scheduled { var due: Int64; let path: MqttMultipathPolicy.Dispatch }
  private final class Job {
    let key: Key
    let topic: String
    let delivery: Delivery
    let token = UUID().uuidString
    let started: Int64
    var scheduled: [Scheduled]
    var attempts = Set<String>()
    var accepted = false
    var publishing = false
    var finished = false

    init(topic: String, delivery: Delivery, at: Int64, plans: [MqttMultipathPolicy.Dispatch]) {
      self.key = Key(peer: delivery.peer, message: delivery.message)
      self.topic = topic
      self.delivery = delivery
      self.started = at
      self.scheduled = plans.map { Scheduled(due: at + $0.delayMillis, path: $0) }
    }
  }
  private struct Sent { let job: Job; let frame: MqttDeliveryEnvelope.Frame; var pending = true }
  private let policy: MqttMultipathPolicy
  private let publish: (Publication) async -> Bool
  private let completed: (String, Bool) -> Void
  private let now: () -> Int64
  private var jobs: [Key: Job] = [:]
  private var order: [Key] = []
  private var sent: [String: Sent] = [:]
  private var closed = false

  init(policy: MqttMultipathPolicy, publish: @escaping (Publication) async -> Bool,
       brokerCompleted: @escaping (String, Bool) -> Void,
       now: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) }) {
    self.policy = policy
    self.publish = publish
    self.completed = brokerCompleted
    self.now = now
  }

  func submit(topic: String, delivery: Delivery) async throws -> String {
    let at = now()
    guard !closed, at >= 0, at <= Int64.max - 30_000, !delivery.peer.isEmpty,
          (1...MqttRouteProtocol.packetBytes).contains(delivery.sizeBound) else { throw Failure.unavailable }
    _ = try Self.packetBytes(topic: topic, payloadBytes: 1)
    let key = Key(peer: delivery.peer, message: delivery.message)
    if let old = jobs[key], expired(old, at: at) { retire(old) }
    if let old = jobs[key] { return old.token }
    guard !jobs.values.contains(where: {
      $0.key.peer == delivery.peer && $0.key.message.messageID == delivery.message.messageID && $0.key.message != delivery.message
    }) else { throw Failure.invalidPacket }
    let plans = plan(delivery, at: at)
    guard !plans.isEmpty else { throw Failure.unavailable }
    let priority = Self.priority(delivery.message)
    guard jobs.count < (priority ? 4096 : 4094),
          jobs.values.reduce(0, { $0 + $1.delivery.sizeBound }) + delivery.sizeBound <= 8_388_608 - (priority ? 0 : 131_072) else {
      throw Failure.capacity
    }
    let job = Job(topic: topic, delivery: delivery, at: at, plans: plans)
    jobs[key] = job
    order.append(key)
    do { try await pump(job, at: at) }
    catch {
      if job.attempts.isEmpty { remove(job) }
      throw error
    }
    if !closed, job.accepted { return job.token }
    guard jobs[key] === job, !closed, !job.attempts.isEmpty else {
      if job.attempts.isEmpty { remove(job) }
      throw Failure.unavailable
    }
    return job.token
  }

  // An enqueue result is not a PUBACK. Call this only with an attributed transport completion.
  @discardableResult
  func published(attemptID: String, broker: String, generation: Int64, acknowledged: Bool) -> Bool {
    guard var item = sent[attemptID] else { return false }
    guard item.frame.attempt.brokerID == broker, item.frame.attempt.generation == generation else { return false }
    guard item.pending else { return true }
    item.pending = false
    sent[attemptID] = item
    let job = item.job
    if acknowledged {
      policy.brokerAck(attemptID: attemptID, broker: broker, generation: generation)
      finish(job, accepted: true)
    } else {
      discard(attemptID, from: job)
      expedite(job, at: now())
    }
    if job.accepted {
      discard(attemptID, from: job)
      if job.attempts.isEmpty && !job.publishing { remove(job) }
    }
    if !job.publishing && job.scheduled.isEmpty && !hasPending(job) { finish(job, accepted: false) }
    return true
  }

  // Current relationship AEAD validation precedes this call. Commit failure must leave hedges live.
  @discardableResult
  func acceptVerifiedReceipt(peer: String, frame: MqttDeliveryEnvelope.Frame, commit: () throws -> Void) throws -> Bool {
    guard !closed, let item = sent[frame.attempt.attemptID], item.frame == frame,
          item.job.key.peer == peer, !item.job.accepted else { return false }
    try commit()
    let accepted = policy.acceptVerifiedReceipt(peer: peer, messageID: frame.message.messageID,
      contentHash: frame.message.contentHash, attemptID: frame.attempt.attemptID, now: now())
    guard !accepted.isEmpty else { return false }
    item.job.accepted = true
    item.job.scheduled.removeAll()
    retire(item.job)
    return true
  }

  @discardableResult
  func acceptVerifiedMessage(peer: String, messageID: String, contentHash: String, commit: () throws -> Void) throws -> Bool {
    let matching = jobs.values.filter { $0.key.peer == peer && $0.key.message.messageID == messageID && $0.key.message.contentHash == contentHash }
    guard !closed, !matching.isEmpty, matching.contains(where: { !$0.accepted }) else { return false }
    try commit()
    policy.acceptVerifiedMessage(peer: peer, messageID: messageID, contentHash: contentHash)
    for job in matching { job.accepted = true; retire(job) }
    return true
  }

  func tick() async {
    guard !closed else { return }
    let at = now()
    let due = order.compactMap { jobs[$0] }.filter { expired($0, at: at) || $0.accepted || ($0.scheduled.first.map { $0.due <= at } ?? false) }
    let urgent = due.filter { Self.priority($0.delivery.message) }
    let ordinary = due.filter { !Self.priority($0.delivery.message) }
    var selected = Array(urgent.prefix(12)) + Array(ordinary.prefix(4))
    selected += (Array(urgent.dropFirst(12)) + Array(ordinary.dropFirst(4))).prefix(16 - selected.count)
    let keys = Set(selected.map(\.key))
    order.removeAll { keys.contains($0) }
    order.append(contentsOf: selected.map(\.key))
    for job in selected {
      guard !closed, jobs[job.key] === job else { continue }
      if expired(job, at: at) || job.accepted { retire(job) }
      else { try? await pump(job, at: at) }
    }
  }

  // The owner cancels the corresponding physical connections before closing this dispatcher.
  func close() {
    guard !closed else { return }
    closed = true
    for job in jobs.values {
      job.scheduled.removeAll()
      job.attempts.forEach { policy.discardAttempt($0) }
      finish(job, accepted: false)
    }
    jobs.removeAll()
    sent.removeAll()
    order.removeAll()
  }

  func diagnostics() -> Diagnostics {
    Diagnostics(messages: jobs.count, trackedAttempts: sent.count,
      queuedCopies: jobs.values.reduce(0) { $0 + $1.scheduled.count },
      bufferedBytes: jobs.values.reduce(0) { $0 + $1.delivery.sizeBound })
  }

  static func packetBytes(topic: String, payloadBytes: Int) throws -> Int {
    let topicBytes = topic.utf8.count
    guard topicBytes > 0, topicBytes <= 65_535, !topic.contains("\0"), !topic.contains("+"), !topic.contains("#"),
          (1...MqttRouteProtocol.packetBytes).contains(payloadBytes) else { throw Failure.invalidPacket }
    var remaining = 2 + topicBytes + 2 + payloadBytes
    let body = remaining
    var lengthBytes = 0
    repeat { lengthBytes += 1; remaining /= 128 } while remaining > 0
    let total = 1 + lengthBytes + body
    guard total <= MqttRouteProtocol.packetBytes else { throw Failure.invalidPacket }
    return total
  }

  private func pump(_ job: Job, at: Int64) async throws {
    guard !closed, !job.accepted, !job.publishing, jobs[job.key] === job else { return }
    job.publishing = true
    defer {
      job.publishing = false
      if job.scheduled.isEmpty && !hasPending(job) { finish(job, accepted: false) }
      if job.accepted { retire(job) }
    }
    do {
      while !closed, !job.accepted, jobs[job.key] === job,
            let next = job.scheduled.first, next.due <= at {
        job.scheduled.removeFirst()
        let delivery = job.delivery
        let path = next.path
        guard plan(delivery, at: now()).contains(where: { $0.brokerID == path.brokerID && $0.generation == path.generation }),
              delivery.authorized(path.brokerID, path.generation) else { continue }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let frame = try MqttDeliveryEnvelope.Frame(message: delivery.message,
          attempt: .init(attemptID: id, brokerID: path.brokerID, generation: path.generation))
        let payload = try delivery.encodeAttempt(frame)
        let bytes = try Self.packetBytes(topic: job.topic, payloadBytes: payload.count)
        guard bytes <= delivery.sizeBound else { throw Failure.invalidPacket }
        guard delivery.authorized(path.brokerID, path.generation) else { continue }
        guard policy.reserve(attemptID: id, attempt: .init(peer: delivery.peer, messageID: delivery.message.messageID,
          contentHash: delivery.message.contentHash, brokerID: path.brokerID, generation: path.generation,
          wireBytes: bytes, traffic: Self.traffic(delivery.message), startedAt: now())) else {
          job.scheduled.insert(Scheduled(due: at + 250, path: path), at: 0)
          break
        }
        job.attempts.insert(id)
        sent[id] = Sent(job: job, frame: frame)
        let queued = await publish(Publication(topic: job.topic, payload: payload, frame: frame))
        // A callback may have completed, or close() may have run, during the enqueue await.
        guard !closed, jobs[job.key] === job else { return }
        if !queued, sent[id]?.pending == true {
          discard(id, from: job)
          expedite(job, at: at)
        }
      }
    } catch {
      job.scheduled.removeAll()
      throw error
    }
  }

  private func plan(_ delivery: Delivery, at: Int64) -> [MqttMultipathPolicy.Dispatch] {
    policy.plan(peer: delivery.peer, messageID: delivery.message.messageID, traffic: Self.traffic(delivery.message),
                wireBytes: delivery.sizeBound, receiveTopics: delivery.receiveTopics, now: at)
  }
  private static func traffic(_ message: MqttDeliveryEnvelope.Message) -> MqttMultipathPolicy.Traffic {
    // Message construction already validates this closed wire enum.
    MqttMultipathPolicy.Traffic(rawValue: message.traffic)!
  }
  private static func priority(_ message: MqttDeliveryEnvelope.Message) -> Bool { ["control", "receipt", "final"].contains(message.traffic) }
  private func hasPending(_ job: Job) -> Bool { job.attempts.contains { sent[$0]?.pending == true } }
  private func expired(_ job: Job, at: Int64) -> Bool { at >= job.started && at - job.started >= 30_000 }
  private func finish(_ job: Job, accepted: Bool) {
    guard !job.finished else { return }
    job.finished = true
    completed(job.token, accepted)
  }
  private func expedite(_ job: Job, at: Int64) {
    for index in job.scheduled.indices { job.scheduled[index].due = at }
  }
  private func discard(_ id: String, from job: Job) {
    sent.removeValue(forKey: id)
    job.attempts.remove(id)
    policy.discardAttempt(id)
  }
  private func retire(_ job: Job) {
    job.scheduled.removeAll()
    guard !job.publishing else { return }
    for id in Array(job.attempts) where sent[id]?.pending == false { discard(id, from: job) }
    if job.attempts.isEmpty { finish(job, accepted: false); remove(job) }
  }
  private func remove(_ job: Job) {
    guard jobs[job.key] === job else { return }
    jobs.removeValue(forKey: job.key)
    order.removeAll { $0 == job.key }
  }
}
