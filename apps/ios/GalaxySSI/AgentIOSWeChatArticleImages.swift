import Foundation
import ImageIO

final class AgentIOSWeChatArticleImages {
  private enum Cached { case bytes(Data), missing }
  private var cache: [String: Cached] = [:]
  private var remaining = AgentIOSWeChatArticleLimits.allImageBytes
  private let clock: AgentIOSWeChatExportClock
  private let deadline: Int64
  private let provider: AgentIOSURLSessionWebMediaToolProvider
  init(clock: AgentIOSWeChatExportClock) {
    self.clock = clock; deadline = clock.now() + AgentIOSWeChatArticleLimits.imageBudget
    provider = .init(nowMillis: clock.now)
  }
  func image(_ address: String?) -> CGImage? {
    guard let address, !Task.isCancelled else { return nil }
    let data: Data?
    if address.lowercased().hasPrefix("data:image/") { data = Self.inline(address) }
    else if let cached = cache[address] { if case .bytes(let value) = cached { data = value } else { data = nil } }
    else {
      guard cache.count < AgentIOSWeChatArticleLimits.uniqueImages else { return nil }
      let time = min(AgentIOSWeChatArticleLimits.imageTimeout, deadline - clock.now())
      if remaining > 0, time > 0,
        let call = try? AgentIOSWeChatArticlePDF.invocation(clock: clock, duration: time),
        let bytes = try? provider.weChatPDFImage(address, maxBytes: min(remaining, AgentIOSWeChatArticleLimits.imageBytes),
          timeoutMillis: time, invocation: call) {
        remaining -= Int64(bytes.count); cache[address] = .bytes(bytes); data = bytes
      } else { cache[address] = .missing; data = nil }
    }
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
    let w = width.doubleValue, h = height.doubleValue
    guard w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
    let scale = min(1, 1600 / w, 2400 / h)
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(max(w, h) * scale)))
    ] as CFDictionary)
  }
  private static func inline(_ value: String) -> Data? {
    guard value.utf8.count < 12 * 1_024 * 1_024, let comma = value.firstIndex(of: ","),
      value[..<comma].lowercased().hasSuffix(";base64"),
      ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif"].contains(String(value.dropFirst(5).prefix { $0 != ";" }).lowercased()),
      let bytes = Data(base64Encoded: String(value[value.index(after: comma)...]), options: .ignoreUnknownCharacters),
      bytes.count <= AgentIOSWeChatArticleLimits.imageBytes else { return nil }
    return bytes
  }
}
