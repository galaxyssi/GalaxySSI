import Foundation

struct GlobalInterventionHistory: Codable, Equatable {
  var notificationTimestamps: [Int64]
  var lastTopicNotificationMillis: [String: Int64]
  var countedDeliveryGroupIds: [String]

  init(
    notificationTimestamps: [Int64] = [],
    lastTopicNotificationMillis: [String: Int64] = [:],
    countedDeliveryGroupIds: [String] = []
  ) {
    self.notificationTimestamps = notificationTimestamps.filter { $0 > 0 }
    self.lastTopicNotificationMillis = lastTopicNotificationMillis.filter { !$0.key.isBlank && $0.value > 0 }
    self.countedDeliveryGroupIds = countedDeliveryGroupIds.filter { !$0.isBlank }
  }

  enum CodingKeys: String, CodingKey {
    case notificationTimestamps = "notification_timestamps"
    case lastTopicNotificationMillis = "last_topic_notification_millis"
    case countedDeliveryGroupIds = "counted_delivery_group_ids"
  }
}

struct GlobalAgentAdaptiveProfile: Codable, Equatable {
  var sampleCount: Int
  var helpfulCount: Int
  var notRelevantCount: Int
  var tooFrequentCount: Int
  var globalAffinity: Double
  var frequencyPressure: Double
  var topicAffinity: [String: Double]

  init(
    sampleCount: Int = 0,
    helpfulCount: Int = 0,
    notRelevantCount: Int = 0,
    tooFrequentCount: Int = 0,
    globalAffinity: Double = 0,
    frequencyPressure: Double = 0,
    topicAffinity: [String: Double] = [:]
  ) {
    self.sampleCount = max(sampleCount, 0)
    self.helpfulCount = max(helpfulCount, 0)
    self.notRelevantCount = max(notRelevantCount, 0)
    self.tooFrequentCount = max(tooFrequentCount, 0)
    self.globalAffinity = clamp(globalAffinity, lower: -1, upper: 1)
    self.frequencyPressure = clamp(frequencyPressure, lower: 0, upper: 1)
    self.topicAffinity = topicAffinity.reduce(into: [String: Double]()) { result, entry in
      let key = GlobalAgentText.normalize(entry.key)
      if !key.isBlank {
        result[key] = clamp(entry.value, lower: -1, upper: 1)
      }
    }
  }

  func affinityFor(topic: String) -> Double {
    topicAffinity[GlobalAgentText.normalize(topic)] ?? 0
  }

  enum CodingKeys: String, CodingKey {
    case sampleCount = "sample_count"
    case helpfulCount = "helpful_count"
    case notRelevantCount = "not_relevant_count"
    case tooFrequentCount = "too_frequent_count"
    case globalAffinity = "global_affinity"
    case frequencyPressure = "frequency_pressure"
    case topicAffinity = "topic_affinity"
  }
}

enum GlobalAgentLearningPolicy {
  static func profile(
    feedback: [GlobalAgentFeedback],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalAgentAdaptiveProfile {
    let recent = feedback
      .filter { nowMillis - $0.createdAtMillis <= maximumFeedbackAgeMillis }
      .suffix(maximumProfileSamples)
    if recent.isEmpty { return GlobalAgentAdaptiveProfile() }

    var globalWeightedScore = 0.0
    var globalWeight = 0.0
    var frequencyWeight = 0.0
    var topicScores: [String: Double] = [:]
    var topicWeights: [String: Double] = [:]

    for item in recent {
      let age = max(nowMillis - item.createdAtMillis, 0)
      let recencyWeight = clamp(
        1.0 - Double(age) / Double(maximumFeedbackAgeMillis),
        lower: minimumRecencyWeight,
        upper: 1.0
      )
      let signal: Double
      switch item.kind {
      case .helpful:
        signal = 1.0
      case .notRelevant:
        signal = -1.0
      case .tooFrequent:
        signal = -0.45
      }
      globalWeightedScore += signal * recencyWeight
      globalWeight += recencyWeight
      if item.kind == .tooFrequent {
        frequencyWeight += recencyWeight
      }
      let topicKey = GlobalAgentText.normalize(item.topic)
      if !topicKey.isBlank {
        topicScores[topicKey, default: 0] += signal * recencyWeight
        topicWeights[topicKey, default: 0] += recencyWeight
      }
    }

    let topicAffinity = topicScores.reduce(into: [String: Double]()) { result, entry in
      result[entry.key] = clamp(
        entry.value / ((topicWeights[entry.key] ?? 0) + topicPriorWeight),
        lower: -1,
        upper: 1
      )
    }
    return GlobalAgentAdaptiveProfile(
      sampleCount: recent.count,
      helpfulCount: recent.filter { $0.kind == .helpful }.count,
      notRelevantCount: recent.filter { $0.kind == .notRelevant }.count,
      tooFrequentCount: recent.filter { $0.kind == .tooFrequent }.count,
      globalAffinity: clamp(globalWeightedScore / (globalWeight + globalPriorWeight), lower: -1, upper: 1),
      frequencyPressure: clamp(frequencyWeight / (globalWeight + frequencyPriorWeight), lower: 0, upper: 1),
      topicAffinity: topicAffinity
    )
  }

  static func scoreAdjustment(profile: GlobalAgentAdaptiveProfile, topic: String) -> Double {
    clamp(profile.globalAffinity * 0.06 + profile.affinityFor(topic: topic) * 0.14, lower: -0.18, upper: 0.14)
  }

  static func dailyMessageBudget(
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile
  ) -> Int {
    if settings.dailyMessageBudget <= 0 { return 0 }
    let adjustment: Int
    if profile.frequencyPressure >= 0.35 {
      adjustment = -2
    } else if profile.frequencyPressure >= 0.18 {
      adjustment = -1
    } else if profile.sampleCount >= 5 && profile.globalAffinity >= 0.35 {
      adjustment = 1
    } else {
      adjustment = 0
    }
    return min(max(settings.dailyMessageBudget + adjustment, 1), 12)
  }

  static func topicCooldownMillis(
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile,
    topic: String
  ) -> Int64 {
    let multiplier: Double
    if profile.frequencyPressure >= 0.35 {
      multiplier = 1.75
    } else if profile.affinityFor(topic: topic) <= -0.35 {
      multiplier = 1.50
    } else if profile.affinityFor(topic: topic) >= 0.45 {
      multiplier = 0.75
    } else {
      multiplier = 1.0
    }
    return min(max(Int64(Double(settings.topicCooldownMillis) * multiplier), minimumCooldownMillis), maximumCooldownMillis)
  }

  static func researchThreshold(profile: GlobalAgentAdaptiveProfile, topic: String) -> Double {
    clamp(0.34 - profile.affinityFor(topic: topic) * 0.07 - profile.globalAffinity * 0.03, lower: 0.24, upper: 0.48)
  }

  private static let maximumFeedbackAgeMillis: Int64 = 30 * 24 * 60 * 60 * 1_000
  private static let maximumProfileSamples = 200
  private static let minimumRecencyWeight = 0.20
  private static let globalPriorWeight = 2.0
  private static let frequencyPriorWeight = 3.0
  private static let topicPriorWeight = 1.5
  private static let minimumCooldownMillis: Int64 = 60 * 60 * 1_000
  private static let maximumCooldownMillis: Int64 = 7 * 24 * 60 * 60 * 1_000
}

enum GlobalProactiveDeliveryPolicy {
  static func isRecoverable(_ message: GlobalProactiveMessage, nowMillis: Int64) -> Bool {
    switch message.status {
    case .pending, .notified:
      return true
    case .delivering:
      return message.deliveryLeaseExpiresAtMillis <= 0 || message.deliveryLeaseExpiresAtMillis <= nowMillis
    case .delivered, .dismissed:
      return false
    }
  }

  static func canDeliver(
    message: GlobalProactiveMessage,
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile,
    history: GlobalInterventionHistory,
    nowMillis: Int64
  ) -> Bool {
    if message.urgent || message.deliveryBudgetCounted { return true }
    if !dailyBudgetAvailable(settings: settings, profile: profile, history: history, nowMillis: nowMillis) {
      return false
    }
    let topicKey = GlobalAgentText.normalize(message.topic)
    guard let lastTopicDelivery = history.lastTopicNotificationMillis[topicKey] else { return true }
    let cooldown = GlobalAgentLearningPolicy.topicCooldownMillis(settings: settings, profile: profile, topic: message.topic)
    let elapsed = nowMillis - lastTopicDelivery
    return !(elapsed >= 0 && elapsed < cooldown)
  }

  static func dailyBudgetAvailable(
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile,
    history: GlobalInterventionHistory,
    nowMillis: Int64
  ) -> Bool {
    let budget = GlobalAgentLearningPolicy.dailyMessageBudget(settings: settings, profile: profile)
    if budget <= 0 { return false }
    let used = history.notificationTimestamps.filter { timestamp in
      (0...dayMillis).contains(nowMillis - timestamp)
    }.count
    return used < budget
  }

  static func nextEligibleAtMillis(
    message: GlobalProactiveMessage,
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile,
    history: GlobalInterventionHistory,
    nowMillis: Int64
  ) -> Int64 {
    if message.urgent || message.deliveryBudgetCounted { return nowMillis }
    let budget = GlobalAgentLearningPolicy.dailyMessageBudget(settings: settings, profile: profile)
    if budget <= 0 { return 0 }
    let recent = history.notificationTimestamps
      .filter { (0...dayMillis).contains(nowMillis - $0) }
      .sorted()
    let budgetReadyAt = recent.count >= budget
      ? recent[recent.count - budget] + dayMillis + 1
      : nowMillis
    let topicKey = GlobalAgentText.normalize(message.topic)
    let lastTopicDelivery = history.lastTopicNotificationMillis[topicKey] ?? 0
    let topicReadyAt = lastTopicDelivery <= 0
      ? nowMillis
      : lastTopicDelivery +
        GlobalAgentLearningPolicy.topicCooldownMillis(settings: settings, profile: profile, topic: message.topic) + 1
    return max(nowMillis, max(budgetReadyAt, topicReadyAt))
  }

  static func digestBatch(
    messages: [GlobalProactiveMessage],
    settings: GlobalAgentSettings,
    profile: GlobalAgentAdaptiveProfile,
    history: GlobalInterventionHistory,
    nowMillis: Int64,
    minimumItems: Int,
    maximumItems: Int,
    maximumWaitMillis: Int64
  ) -> [GlobalProactiveMessage] {
    if !dailyBudgetAvailable(settings: settings, profile: profile, history: history, nowMillis: nowMillis) {
      return []
    }
    let eligible = messages
      .filter { $0.target == .globalDigest }
      .filter { isRecoverable($0, nowMillis: nowMillis) }
      .filter { canDeliver(message: $0, settings: settings, profile: profile, history: history, nowMillis: nowMillis) }
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
    let ready = eligible.count >= minimumItems ||
      eligible.first.map { nowMillis - $0.createdAtMillis >= maximumWaitMillis } == true
    if !ready { return [] }
    return Array(eligible.prefix(max(maximumItems, 1)))
  }

  private static let dayMillis: Int64 = 24 * 60 * 60 * 1_000
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
  min(max(value, lower), upper)
}
