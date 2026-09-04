import Foundation
import Network

#if canImport(UIKit)
import UIKit
#endif

enum AgentMediaNetworkState: String, Codable, Equatable {
  case normal = "NORMAL"
  case constrained = "CONSTRAINED"
  case offline = "OFFLINE"
}

struct AgentMediaNetworkProbe: Codable, Equatable {
  var networkPresent: Bool
  var internetCapable: Bool
  var validated: Bool
  var metered: Bool
  var roaming: Bool
  var restricted: Bool
  var congested: Bool
  var cellular: Bool
  var transports: [String]
  var downstreamKbps: Int
  var upstreamKbps: Int

  init(
    networkPresent: Bool = true,
    internetCapable: Bool = true,
    validated: Bool = true,
    metered: Bool = false,
    roaming: Bool = false,
    restricted: Bool = false,
    congested: Bool = false,
    cellular: Bool = false,
    transports: [String] = [],
    downstreamKbps: Int = 20_000,
    upstreamKbps: Int = 5_000
  ) {
    self.networkPresent = networkPresent
    self.internetCapable = internetCapable
    self.validated = validated
    self.metered = metered
    self.roaming = roaming
    self.restricted = restricted
    self.congested = congested
    self.cellular = cellular
    self.transports = transports
    self.downstreamKbps = downstreamKbps
    self.upstreamKbps = upstreamKbps
  }

  enum CodingKeys: String, CodingKey {
    case networkPresent = "network_present"
    case internetCapable = "internet_capable"
    case validated
    case metered
    case roaming
    case restricted
    case congested
    case cellular
    case transports
    case downstreamKbps = "downstream_kbps"
    case upstreamKbps = "upstream_kbps"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      networkPresent: try container.decodeIfPresent(Bool.self, forKey: .networkPresent) ?? true,
      internetCapable: try container.decodeIfPresent(Bool.self, forKey: .internetCapable) ?? true,
      validated: try container.decodeIfPresent(Bool.self, forKey: .validated) ?? true,
      metered: try container.decodeIfPresent(Bool.self, forKey: .metered) ?? false,
      roaming: try container.decodeIfPresent(Bool.self, forKey: .roaming) ?? false,
      restricted: try container.decodeIfPresent(Bool.self, forKey: .restricted) ?? false,
      congested: try container.decodeIfPresent(Bool.self, forKey: .congested) ?? false,
      cellular: try container.decodeIfPresent(Bool.self, forKey: .cellular) ?? false,
      transports: try container.decodeIfPresent([String].self, forKey: .transports) ?? [],
      downstreamKbps: try container.decodeIfPresent(Int.self, forKey: .downstreamKbps) ?? 20_000,
      upstreamKbps: try container.decodeIfPresent(Int.self, forKey: .upstreamKbps) ?? 5_000
    )
  }
}

struct AgentMediaDeliveryProfile: Codable, Equatable {
  var state: AgentMediaNetworkState
  var id: String
  var imageTargetBytes: Int
  var audioSampleRateHz: Int
  var audioBitRateBps: Int
  var deferMediaUpload: Bool

  var canUploadDeferredMedia: Bool {
    state != .offline
  }

  enum CodingKeys: String, CodingKey {
    case state
    case id
    case imageTargetBytes = "image_target_bytes"
    case audioSampleRateHz = "audio_sample_rate_hz"
    case audioBitRateBps = "audio_bit_rate_bps"
    case deferMediaUpload = "defer_media_upload"
  }
}

enum AgentMediaNetworkPolicy {
  static let normalImageBytes = 100_000
  static let constrainedImageBytes = 64 * 1024
  static let offlineImageBytes = 48 * 1024

  static func evaluate(_ probe: AgentMediaNetworkProbe) -> AgentMediaDeliveryProfile {
    let state: AgentMediaNetworkState
    if !probe.networkPresent || !probe.internetCapable || !probe.validated {
      state = .offline
    } else if probe.metered ||
      probe.roaming ||
      probe.restricted ||
      probe.congested ||
      probe.cellular ||
      knownLowBandwidth(probe.downstreamKbps, minimum: minimumNormalDownstreamKbps) ||
      knownLowBandwidth(probe.upstreamKbps, minimum: minimumNormalUpstreamKbps) {
      state = .constrained
    } else {
      state = .normal
    }
    return profile(for: state)
  }

  static func profile(for state: AgentMediaNetworkState) -> AgentMediaDeliveryProfile {
    switch state {
    case .normal:
      return AgentMediaDeliveryProfile(
        state: state,
        id: "normal",
        imageTargetBytes: normalImageBytes,
        audioSampleRateHz: 44_100,
        audioBitRateBps: 96_000,
        deferMediaUpload: false
      )
    case .constrained:
      return AgentMediaDeliveryProfile(
        state: state,
        id: "constrained",
        imageTargetBytes: constrainedImageBytes,
        audioSampleRateHz: 16_000,
        audioBitRateBps: 32_000,
        deferMediaUpload: false
      )
    case .offline:
      return AgentMediaDeliveryProfile(
        state: state,
        id: "offline",
        imageTargetBytes: offlineImageBytes,
        audioSampleRateHz: 16_000,
        audioBitRateBps: 24_000,
        deferMediaUpload: true
      )
    }
  }

  private static func knownLowBandwidth(_ kbps: Int, minimum: Int) -> Bool {
    (1..<minimum).contains(kbps)
  }

  private static let minimumNormalDownstreamKbps = 1_000
  private static let minimumNormalUpstreamKbps = 512
}

final class AgentMediaNetworkDetector {
  static let shared = AgentMediaNetworkDetector()

  private let monitor: NWPathMonitor
  private let deviceProfileProvider: () -> AgentDeviceProfile
  private let queue = DispatchQueue(label: "com.galaxyssi.ios.media-network")
  private let lock = NSLock()
  private var probe: AgentMediaNetworkProbe
  private var profile: AgentMediaDeliveryProfile

  init(
    monitor: NWPathMonitor = NWPathMonitor(),
    deviceProfileProvider: @escaping () -> AgentDeviceProfile = { AgentDeviceProfileDetector.detect() }
  ) {
    self.monitor = monitor
    self.deviceProfileProvider = deviceProfileProvider
    let initialProbe = AgentMediaNetworkProbe()
    self.probe = initialProbe
    self.profile = deviceProfileProvider().adaptMedia(AgentMediaNetworkPolicy.evaluate(initialProbe))
    self.monitor.pathUpdateHandler = { [weak self] path in
      self?.update(path: path)
    }
    self.monitor.start(queue: queue)
  }

  var currentProfile: AgentMediaDeliveryProfile {
    lock.lock()
    defer { lock.unlock() }
    return profile
  }

  var currentProbe: AgentMediaNetworkProbe {
    lock.lock()
    defer { lock.unlock() }
    return probe
  }

  func update(path: NWPath) {
    let nextProbe = Self.probe(for: path)
    let next = deviceProfileProvider().adaptMedia(AgentMediaNetworkPolicy.evaluate(nextProbe))
    lock.lock()
    probe = nextProbe
    profile = next
    lock.unlock()
  }

  static func probe(for path: NWPath) -> AgentMediaNetworkProbe {
    AgentMediaNetworkProbe(
      networkPresent: path.status != .unsatisfied,
      internetCapable: path.status == .satisfied,
      validated: path.status == .satisfied,
      metered: path.isExpensive,
      roaming: false,
      restricted: path.isConstrained,
      congested: false,
      cellular: path.usesInterfaceType(.cellular),
      transports: transports(for: path),
      downstreamKbps: 0,
      upstreamKbps: 0
    )
  }

  private static func transports(for path: NWPath) -> [String] {
    var transports: [String] = []
    if path.usesInterfaceType(.wifi) {
      transports.append("wifi")
    }
    if path.usesInterfaceType(.cellular) {
      transports.append("cellular")
    }
    if path.usesInterfaceType(.wiredEthernet) {
      transports.append("ethernet")
    }
    return transports
  }

  deinit {
    monitor.cancel()
  }
}

struct AgentMediaInlinePayload: Equatable {
  var data: Data
  var mimeType: String
  var displayName: String
  var lossless: Bool
}

enum AgentMediaAttachmentTransportEncoder {
  static func inlinePayload(
    for attachment: GalaxySSIDraftAttachment,
    profile: AgentMediaDeliveryProfile?,
    remainingBytes: Int
  ) -> AgentMediaInlinePayload? {
    let budget = inlineBudget(for: attachment, profile: profile, remainingBytes: remainingBytes)
    guard attachment.sizeBytes > 0, budget > 0 else { return nil }
    if attachment.sizeBytes <= budget {
      return AgentMediaInlinePayload(
        data: attachment.data,
        mimeType: attachment.mimeType,
        displayName: attachment.displayName,
        lossless: true
      )
    }
    #if canImport(UIKit)
    if attachment.isImage,
       let compressed = compressedImagePayload(for: attachment, targetBytes: budget) {
      return compressed
    }
    #endif
    return nil
  }

  static func inlineBudget(
    for attachment: GalaxySSIDraftAttachment,
    profile: AgentMediaDeliveryProfile?,
    remainingBytes: Int
  ) -> Int {
    let remaining = max(0, remainingBytes)
    guard let profile, attachment.isImage else {
      return remaining
    }
    return min(remaining, profile.imageTargetBytes)
  }

  #if canImport(UIKit)
  private static func compressedImagePayload(
    for attachment: GalaxySSIDraftAttachment,
    targetBytes: Int
  ) -> AgentMediaInlinePayload? {
    guard targetBytes > 0,
          let image = UIImage(data: attachment.data) else {
      return nil
    }
    let qualities: [CGFloat] = [0.82, 0.68, 0.54, 0.4, 0.28, 0.18]
    for quality in qualities {
      guard let data = image.jpegData(compressionQuality: quality) else { continue }
      if data.count <= targetBytes {
        return AgentMediaInlinePayload(
          data: data,
          mimeType: "image/jpeg",
          displayName: jpegTransportName(for: attachment.displayName),
          lossless: false
        )
      }
    }
    return nil
  }

  private static func jpegTransportName(for name: String) -> String {
    let clean = GalaxySSIAttachmentPayloadBuilder.sanitizeName(name)
    let base = (clean as NSString).deletingPathExtension.ifBlank("image")
    return "\(base).jpg"
  }
  #endif
}

enum AgentMediaLinkPayloadPolicy {
  static func payloadMetadata(
    attachments: [GalaxySSIDraftAttachment],
    profile: AgentMediaDeliveryProfile
  ) -> [String: Any] {
    guard containsTransportMedia(attachments) else { return [:] }
    return [
      "media_network_profile": profile.id,
      "defer_media_upload": profile.deferMediaUpload
    ]
  }

  static func requiresValidatedNetwork(
    attachments: [GalaxySSIDraftAttachment],
    profile: AgentMediaDeliveryProfile
  ) -> Bool {
    containsTransportMedia(attachments) && profile.deferMediaUpload
  }

  static func containsTransportMedia(_ attachments: [GalaxySSIDraftAttachment]) -> Bool {
    attachments.contains { $0.isTransportMedia }
  }
}

extension GalaxySSIDraftAttachment {
  var isVideo: Bool {
    mimeType.lowercased().hasPrefix("video/")
  }

  var isTransportMedia: Bool {
    isImage || isAudio || isVideo
  }
}
