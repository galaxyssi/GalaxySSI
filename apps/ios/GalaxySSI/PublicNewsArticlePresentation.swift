import CryptoKit
import Foundation

struct PublicNewsArticlePresentation: Codable, Equatable {
  struct Paragraph: Codable, Equatable {
    enum Role: String, Codable { case text, heading, quote }
    let role: Role
    let emphasis: [String]
  }

  struct Figure: Codable, Equatable, Identifiable {
    let url: URL
    let caption: String
    let beforeParagraph: Int
    var id: URL { url }
  }

  let styles: [Paragraph]
  let figures: [Figure]
  let cover: URL?

  func validated(for article: URL?, paragraphCount: Int) -> Self {
    let styles = styles.count == paragraphCount ? styles : []
    guard let article else { return Self(styles: styles, figures: [], cover: nil) }
    var seen = Set<URL>()
    let figures = figures.filter {
      (0...paragraphCount).contains($0.beforeParagraph) &&
        PublicNewsImagePolicy.accepts($0.url, for: article) && seen.insert($0.url).inserted
    }.prefix(32)
    let cover = cover.flatMap { PublicNewsImagePolicy.accepts($0, for: article) ? $0 : nil } ?? figures.first?.url
    return Self(styles: styles, figures: Array(figures), cover: cover)
  }
}

enum PublicNewsImagePolicy {
  static func accepts(_ image: URL, for article: URL) -> Bool {
    guard PublicNewsArticleBody.supports(article), PublicScienceSource.safe(image),
          image.absoluteString.utf8.count <= 2_048, image.fragment == nil, !image.path.isEmpty,
          let imageHost = image.host?.lowercased(), let articleHost = article.host?.lowercased() else { return false }
    if imageHost == articleHost { return true }
    if articleHost == "github.blog" && ["i0.wp.com", "i1.wp.com", "i2.wp.com"].contains(imageHost) {
      return image.path.hasPrefix("/github.blog/")
    }
    return articleHost == "www.ithome.com" && imageHost == "img.ithome.com"
  }
}

actor PublicNewsImageCache {
  static let shared = PublicNewsImageCache()
  private let root: URL?
  private static let maxImageBytes = 8_000_000
  private static let maxCacheBytes = 48_000_000

  init(root: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    .first?.appendingPathComponent("PublicNewsImages", isDirectory: true)) {
    self.root = root
  }

  func image(_ url: URL, article: URL) async throws -> Data {
    guard PublicNewsImagePolicy.accepts(url, for: article) else { throw PublicNewsArticleBodyError.unsupportedSource }
    try Task.checkCancellation()
    let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = root?.appendingPathComponent(key).appendingPathExtension("media")
    if let file, let data = try? Data(contentsOf: file), data.count <= Self.maxImageBytes,
       GalaxySSIImageResourceDecoder.canDecode(data) {
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
      return data
    }
    let data = try await PublicScienceTransport.fetch(url, limit: Self.maxImageBytes)
    try Task.checkCancellation()
    guard GalaxySSIImageResourceDecoder.canDecode(data) else { throw PublicNewsArticleBodyError.incompleteSource }
    if let root, let file {
      do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune(root)
      } catch {
        // The currently displayed image is still usable if the cache is unavailable.
      }
    }
    return data
  }

  private func prune(_ root: URL) {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
    else { return }
    let sorted = files.filter { $0.pathExtension == "media" }.compactMap { url -> (URL, Int, Date)? in
      guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
      return (url, size, values.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 > $1.2 }
    var bytes = 0
    for (index, entry) in sorted.enumerated() {
      bytes += entry.1
      if index >= 120 || bytes > Self.maxCacheBytes { try? FileManager.default.removeItem(at: entry.0) }
    }
  }
}
