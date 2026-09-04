import ImageIO
import SwiftUI
import UIKit

enum GalaxySSIPeerImageThumbnailPolicy {
  static func cacheIdentity(_ block: AgentRichBlock) -> String {
    block.uri.ifBlank(block.metadata["artifact_source_uri"] ?? "")
      .ifBlank(block.metadata["transfer_id"] ?? "")
      .ifBlank(block.metadata["sha256"] ?? "")
      .ifBlank("\(block.title):\(block.metadata["size_bytes"] ?? "0")")
  }
}

final class GalaxySSIPeerImageThumbnailRepository {
  static let shared = GalaxySSIPeerImageThumbnailRepository()

  private final class Entry: NSObject {
    var data: Data
    var expiresAt: Date

    init(data: Data, expiresAt: Date) {
      self.data = data
      self.expiresAt = expiresAt
    }
  }

  private let cache = NSCache<NSString, Entry>()
  private let queue = DispatchQueue(
    label: "com.galaxyssi.ios.peer-image-thumbnail",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let lock = NSLock()
  private let thumbnailWriteLock = NSLock()
  private var pending: [String: [(Data?) -> Void]] = [:]
  private var generation = 0
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let fileManager: FileManager
  private var memoryWarningObserver: NSObjectProtocol?

  init(
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    fileManager: FileManager = .default
  ) {
    self.cipher = cipher
    self.fileManager = fileManager
    cache.totalCostLimit = 24 * 1024 * 1024
    cache.countLimit = 96
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.clearMemoryCache()
    }
  }

  deinit {
    if let memoryWarningObserver {
      NotificationCenter.default.removeObserver(memoryWarningObserver)
    }
  }

  func load(
    block: AgentRichBlock,
    maxPixelSize: Int = 512,
    completion: @escaping (Data?) -> Void
  ) {
    let key = cacheKey(block: block, maxPixelSize: maxPixelSize)
    if let entry = cache.object(forKey: key as NSString), entry.expiresAt > Date() {
      completion(entry.data)
      return
    }
    cache.removeObject(forKey: key as NSString)
    lock.lock()
    let currentGeneration = generation
    if pending[key] != nil {
      pending[key]?.append(completion)
      lock.unlock()
      return
    }
    pending[key] = [completion]
    lock.unlock()

    queue.async { [weak self] in
      guard let self else { return }
      let data = loadOrCreateThumbnail(block: block, maxPixelSize: maxPixelSize)
      lock.lock()
      guard generation == currentGeneration else {
        lock.unlock()
        return
      }
      let callbacks = pending.removeValue(forKey: key) ?? []
      lock.unlock()
      if let data {
        cache.setObject(
          Entry(data: data, expiresAt: Date().addingTimeInterval(Self.memoryTTL)),
          forKey: key as NSString,
          cost: data.count
        )
      }
      DispatchQueue.main.async {
        callbacks.forEach { $0(data) }
      }
    }
  }

  func clearMemoryCache() {
    cache.removeAllObjects()
    lock.lock()
    generation += 1
    pending.removeAll()
    lock.unlock()
  }

  private func loadOrCreateThumbnail(block: AgentRichBlock, maxPixelSize: Int) -> Data? {
    if let storedURL = storedThumbnailURL(for: block),
       fileManager.fileExists(atPath: storedURL.path),
       let stored = try? cipher.read(from: storedURL, purpose: thumbnailPurpose(block)) {
      return stored
    }
    guard let source = sourceData(for: block),
          let thumbnail = Self.encodeThumbnail(source, maxPixelSize: maxPixelSize) else {
      return nil
    }
    if let storedURL = storedThumbnailURL(for: block) {
      persistThumbnailIfNeeded(thumbnail, to: storedURL, purpose: thumbnailPurpose(block))
    }
    return thumbnail
  }

  private func persistThumbnailIfNeeded(_ thumbnail: Data, to url: URL, purpose: String) {
    thumbnailWriteLock.lock()
    defer { thumbnailWriteLock.unlock() }
    guard !cipher.isEncryptedFile(url) else { return }
    try? cipher.write(thumbnail, to: url, purpose: purpose)
  }

  private func sourceData(for block: AgentRichBlock) -> Data? {
    if let inline = GalaxySSIImageResourceDecoder.base64Data(block.dataB64) {
      return inline
    }
    guard let url = URL(string: block.uri),
          url.isFileURL,
          fileManager.fileExists(atPath: url.path) else { return nil }
    if block.metadata["storage"] == "attachment_aes_256_gcm",
       let purpose = block.metadata["encryption_purpose"],
       !purpose.isEmpty {
      return try? cipher.read(from: url, purpose: purpose)
    }
    return try? Data(contentsOf: url, options: [.mappedIfSafe])
  }

  private func storedThumbnailURL(for block: AgentRichBlock) -> URL? {
    guard block.metadata["storage"] == "attachment_aes_256_gcm",
          let url = URL(string: block.uri),
          url.isFileURL,
          fileManager.fileExists(atPath: url.path) else { return nil }
    return url.deletingLastPathComponent().appendingPathComponent(Self.thumbnailFileName)
  }

  private func thumbnailPurpose(_ block: AgentRichBlock) -> String {
    "peer-thumbnail:\(block.metadata["transfer_id"]?.ifBlank(block.metadata["sha256"] ?? "") ?? "image")"
  }

  private func cacheKey(block: AgentRichBlock, maxPixelSize: Int) -> String {
    "\(GalaxySSIPeerImageThumbnailPolicy.cacheIdentity(block))\u{0000}\(maxPixelSize)"
  }

  static func encodeThumbnail(_ source: Data, maxPixelSize: Int) -> Data? {
    guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
            ] as CFDictionary
          ) else { return nil }
    var current = UIImage(cgImage: image)
    for attempt in 0..<5 {
      if let data = opaqueJPEG(current, quality: max(0.42, 0.84 - CGFloat(attempt) * 0.1)),
         data.count <= maximumStoredBytes {
        return data
      }
      let nextSize = CGSize(
        width: max(1, current.size.width * 0.82),
        height: max(1, current.size.height * 0.82)
      )
      current = renderOpaque(current, size: nextSize)
    }
    return nil
  }

  private static func opaqueJPEG(_ image: UIImage, quality: CGFloat) -> Data? {
    renderOpaque(image, size: image.size).jpegData(compressionQuality: quality)
  }

  private static func renderOpaque(_ image: UIImage, size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = true
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private static let memoryTTL: TimeInterval = 30
  private static let maximumStoredBytes = 100_000
  private static let thumbnailFileName = ".peer-image-thumbnail-v1.saenc"
}

struct GalaxySSIPeerCachedImageView<Placeholder: View>: View {
  var block: AgentRichBlock
  var onLoaded: (Data) -> Void
  var placeholder: () -> Placeholder

  @State private var thumbnailData: Data?

  init(
    block: AgentRichBlock,
    onLoaded: @escaping (Data) -> Void,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.block = block
    self.onLoaded = onLoaded
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let thumbnailData {
        GalaxySSIAnimatedImageView(data: thumbnailData)
      } else {
        placeholder()
      }
    }
    .onAppear(perform: load)
    .onChange(of: GalaxySSIPeerImageThumbnailPolicy.cacheIdentity(block)) { _ in
      thumbnailData = nil
      load()
    }
  }

  private func load() {
    GalaxySSIPeerImageThumbnailRepository.shared.load(block: block) { data in
      thumbnailData = data
      if let data { onLoaded(data) }
    }
  }
}
