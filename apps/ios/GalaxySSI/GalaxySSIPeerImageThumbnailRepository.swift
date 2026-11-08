import ImageIO
import SwiftUI
import UIKit

enum GalaxySSIPeerImageThumbnailPolicy {
  static func cacheIdentity(_ block: AgentRichBlock) -> String {
    let source = block.uri.ifBlank(block.metadata["artifact_source_uri"] ?? "")
      .ifBlank(block.metadata["transfer_id"] ?? "")
      .ifBlank(block.metadata["sha256"] ?? "")
      .ifBlank(block.id)
    let digest = (block.metadata["sha256"] ?? "").lowercased()
    let inlineIdentity = block.dataB64.isEmpty ? "" :
      AgentAttachmentTransferProtocol.sha256(Data(block.dataB64.utf8))
    return [source, digest, block.metadata["transfer_id"] ?? "", block.metadata["storage"] ?? "",
            block.metadata["encryption_purpose"] ?? "", inlineIdentity].joined(separator: "\u{0000}")
  }

  static func isPrivatePeerImage(_ block: AgentRichBlock) -> Bool {
    block.type == .image && block.dataB64.isBlank && block.metadata["source"] == "peer_message" &&
      ["attachment_aes_256_gcm", "app_private_file"].contains(block.metadata["storage"] ?? "") &&
      sourceURL(block) != nil
  }

  static func sourceURL(_ block: AgentRichBlock) -> URL? {
    guard let url = URL(string: block.uri), url.isFileURL else { return nil }
    return url.standardizedFileURL
  }

  static func variant(_ block: AgentRichBlock, maxPixelSize: Int) -> String {
    AgentAttachmentTransferProtocol.sha256(Data("\(cacheIdentity(block))\u{0000}\(maxPixelSize)".utf8))
  }
}

final class GalaxySSIPeerImageThumbnailRepository {
  static let shared = GalaxySSIPeerImageThumbnailRepository()

  private let cache = GalaxySSIRuntimeCache<String, Data>(maxCount: 96, maxCost: 24 * 1024 * 1024)
  private let queue = DispatchQueue(
    label: "com.galaxyssi.ios.peer-image-thumbnail",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let lock = NSLock()
  private let thumbnailWriteLock = NSLock()
  private var pending: [String: [(Data?) -> Void]] = [:]
  private var generation = 0
  private let cipher: any GalaxySSILocalAttachmentStoring
  private let fileManager: FileManager
  private var memoryWarningObserver: NSObjectProtocol?

  init(
    cipher: any GalaxySSILocalAttachmentStoring = GalaxySSIAttachmentAtRestCipher.shared,
    fileManager: FileManager = .default
  ) {
    self.cipher = cipher
    self.fileManager = fileManager
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
    let maxPixelSize = min(max(1, maxPixelSize), GalaxySSIImageResourceDecoder.maximumPixelDimension)
    let key = GalaxySSIPeerImageThumbnailPolicy.variant(block, maxPixelSize: maxPixelSize)
    lock.lock()
    let currentGeneration = generation
    let cacheRevision = cache.revision
    if block.dataB64.isEmpty, let original = GalaxySSIPeerImageThumbnailPolicy.sourceURL(block),
       !fileManager.fileExists(atPath: original.path) {
      cache.remove(key)
      lock.unlock()
      deliver([completion], data: nil, generation: currentGeneration)
      return
    }
    if let data = cache.value(for: key) {
      lock.unlock()
      deliver([completion], data: data, generation: currentGeneration)
      return
    }
    if pending[key] != nil {
      pending[key]?.append(completion)
      lock.unlock()
      return
    }
    pending[key] = [completion]
    lock.unlock()

    queue.async { [weak self] in
      guard let self else { return }
      let data = loadOrCreateThumbnail(block: block, variant: key, maxPixelSize: maxPixelSize)
      lock.lock()
      guard generation == currentGeneration else {
        lock.unlock()
        return
      }
      let callbacks = pending.removeValue(forKey: key) ?? []
      if let data {
        cache.insert(data, for: key, cost: data.count, revision: cacheRevision)
      }
      lock.unlock()
      deliver(callbacks, data: data, generation: currentGeneration)
    }
  }

  func clearMemoryCache() {
    lock.lock()
    generation &+= 1
    cache.clear()
    pending.removeAll()
    lock.unlock()
  }

  private func deliver(_ callbacks: [(Data?) -> Void], data: Data?, generation expected: Int) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      for callback in callbacks {
        lock.lock()
        let current = generation == expected && !GalaxySSIRuntimePlaintextProtection.isBoundaryActive
        lock.unlock()
        guard current else { return }
        callback(data)
      }
    }
  }

  private func loadOrCreateThumbnail(block: AgentRichBlock, variant: String, maxPixelSize: Int) -> Data? {
    let sourceURL = GalaxySSIPeerImageThumbnailPolicy.sourceURL(block)
    let storedURL = privateThumbnailURL(block, sourceURL: sourceURL, variant: variant)
    let purpose = "peer-thumbnail-v2:" + variant
    if let storedURL, let stored = try? cipher.read(from: storedURL, purpose: purpose),
       Self.isValidThumbnail(stored, maxPixelSize: maxPixelSize) {
      return stored
    }
    guard let source = originalData(for: block),
          let thumbnail = Self.encodeThumbnail(source, maxPixelSize: maxPixelSize) else {
      return nil
    }
    if let storedURL, let sourceURL {
      persistThumbnail(thumbnail, to: storedURL, sourceURL: sourceURL, purpose: purpose)
    }
    return thumbnail
  }

  private func persistThumbnail(_ thumbnail: Data, to url: URL, sourceURL: URL, purpose: String) {
    thumbnailWriteLock.lock()
    defer { thumbnailWriteLock.unlock() }
    guard sourceURL != url, fileManager.fileExists(atPath: sourceURL.path) else { return }
    do {
      try cipher.write(thumbnail, to: url, purpose: purpose)
      let legacy = sourceURL.deletingLastPathComponent().appendingPathComponent(Self.legacyThumbnailFileName)
      if legacy != sourceURL, (try? legacy.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        try? fileManager.removeItem(at: legacy)
      }
    } catch {
      // The generated thumbnail is still usable without a disk cache.
    }
  }

  func originalData(for block: AgentRichBlock) -> Data? {
    if let inline = GalaxySSIImageResourceDecoder.base64Data(block.dataB64) {
      return inline
    }
    guard let url = GalaxySSIPeerImageThumbnailPolicy.sourceURL(block),
          fileManager.fileExists(atPath: url.path) else { return nil }
    let source: Data?
    if block.metadata["storage"] == "attachment_aes_256_gcm",
       let purpose = block.metadata["encryption_purpose"],
       !purpose.isEmpty, cipher.isEncryptedFile(url) {
      source = try? cipher.read(from: url, purpose: purpose)
    } else {
      source = GalaxySSIImageResourceDecoder.fileData(url)
    }
    guard let source, source.count <= GalaxySSIImageResourceDecoder.maximumBytes else { return nil }
    let expected = block.metadata["sha256"]?.lowercased() ?? ""
    guard expected.isEmpty || AgentAttachmentTransferProtocol.sha256(source) == expected else { return nil }
    return source
  }

  private func privateThumbnailURL(_ block: AgentRichBlock, sourceURL: URL?, variant: String) -> URL? {
    guard ["attachment_aes_256_gcm", "app_private_file"].contains(block.metadata["storage"] ?? ""),
          let sourceURL, fileManager.fileExists(atPath: sourceURL.path) else { return nil }
    return sourceURL.deletingLastPathComponent().appendingPathComponent(".peer-image-thumbnail-v2-\(variant).saenc")
  }

  private static func isValidThumbnail(_ data: Data, maxPixelSize: Int) -> Bool {
    guard !data.isEmpty, data.count <= maximumStoredBytes,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetStatus(source) == .statusComplete,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
    return (1...maxPixelSize).contains(width) && (1...maxPixelSize).contains(height)
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

  private static let maximumStoredBytes = 100_000
  private static let legacyThumbnailFileName = ".peer-image-thumbnail-v1.saenc"
}

struct GalaxySSIPeerCachedImageView<Placeholder: View>: View {
  @Environment(\.scenePhase) private var scene
  var block: AgentRichBlock
  var onLoaded: (Data) -> Void
  var placeholder: () -> Placeholder

  @State private var loaded: Thumbnail?
  @State private var request: UUID?
  @State private var visible = false

  private struct Thumbnail {
    let identity: String
    let data: Data
  }

  private var identity: String { GalaxySSIPeerImageThumbnailPolicy.cacheIdentity(block) }

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
      if scene == .active, let loaded, loaded.identity == identity {
        GalaxySSIAnimatedImageView(data: loaded.data)
      } else {
        placeholder()
      }
    }
    .onAppear { visible = true; load() }
    .onDisappear { visible = false; clear() }
    .onChange(of: identity) { _ in clear(); load() }
    .onChange(of: scene) { phase in
      if phase == .active { load() } else { clear() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear() }
  }

  private func clear() { request = nil; loaded = nil }

  private func load() {
    guard visible, scene == .active else { return }
    let expected = identity
    let token = UUID()
    request = token
    GalaxySSIPeerImageThumbnailRepository.shared.load(block: block) { data in
      guard request == token, let data else { return }
      loaded = .init(identity: expected, data: data)
      onLoaded(data)
    }
  }
}
