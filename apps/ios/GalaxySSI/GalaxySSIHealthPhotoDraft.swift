import CoreGraphics
import Foundation
import ImageIO

enum GalaxySSIHealthPhotoDraft {
  static let maximumPages = 16

  enum Mode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case report, device
    var id: String { rawValue }
  }

  enum Hint: String, Codable, Equatable, Sendable { case small, dark, glare, lowDetail }

  struct Entry: Codable, Identifiable, Equatable {
    let id: UUID
    let original: GalaxySSIHealthOriginalStore.Original
    let hints: [Hint]
  }

  struct Batch: Codable, Equatable {
    var id = UUID()
    var version = UUID()
    let mode: Mode
    var pages: [Entry] = []

    mutating func install(_ original: GalaxySSIHealthOriginalStore.Original, hints: [Hint], replacing pageID: UUID?) throws {
      guard original.kind == .image,
            !pages.contains(where: { $0.id != pageID && $0.original.sha256 == original.sha256 })
      else { throw GalaxySSIHealthRecords.Failure.duplicate }
      let page = Entry(id: pageID ?? UUID(), original: original, hints: hints)
      if let pageID {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { throw GalaxySSIHealthRecords.Failure.stale }
        pages[index] = page
      } else {
        guard pages.count < GalaxySSIHealthPhotoDraft.maximumPages else { throw GalaxySSIHealthRecords.Failure.invalid }
        pages.append(page)
      }
      version = UUID()
    }

    mutating func edit(_ page: UUID, offset: Int?) throws {
      guard let index = pages.firstIndex(where: { $0.id == page }) else { throw GalaxySSIHealthRecords.Failure.stale }
      if let offset {
        guard offset == -1 || offset == 1, pages.indices.contains(index + offset)
        else { throw GalaxySSIHealthRecords.Failure.invalid }
        pages.swapAt(index, index + offset)
      } else { pages.remove(at: index) }
      version = UUID()
    }
  }

  struct Source: Codable, Hashable {
    let batchID: UUID
    let mode: Mode
    let order: Int
    let cropRevision: UUID?
  }

  static func thumbnail(_ bytes: Data, maximum: Int) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximum
    ]
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  static func inspect(_ bytes: Data) throws -> [Hint] {
    guard (1...GalaxySSIHealthOriginalStore.maximumFileBytes).contains(bytes.count),
          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          (1...16_384).contains(width), (1...16_384).contains(height),
          let image = thumbnail(bytes, maximum: 128) else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    let w = image.width, h = image.height
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let base = context.data?.assumingMemoryBound(to: UInt8.self) else { throw GalaxySSIHealthOriginalStore.Failure.invalid }
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    var hints: [Hint] = []
    if min(width, height) < 720 { hints.append(.small) }
    let pixels = UnsafeBufferPointer(start: base, count: w * h)
    let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
    if mean < 60 { hints.append(.dark) }
    if pixels.filter({ $0 > 249 }).count * 4 > pixels.count * 3 { hints.append(.glare) }
    if w > 2, h > 2 {
      var detail = 0
      for y in 1..<(h - 1) {
        for x in 1..<(w - 1) {
          let i = y * w + x
          detail += abs(4 * Int(pixels[i]) - Int(pixels[i - 1]) - Int(pixels[i + 1]) -
                        Int(pixels[i - w]) - Int(pixels[i + w]))
        }
      }
      if detail < 7 * (w - 2) * (h - 2) { hints.append(.lowDetail) }
    }
    return hints
  }
}
