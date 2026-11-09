import CryptoKit
import Foundation
import ImageIO
import PDFKit
import UIKit

@MainActor
enum GalaxySSIHealthEncounterDocument {
  typealias Original = GalaxySSIHealthOriginalStore.Original
  static let pageSize = 30
  static let previewLifetime: TimeInterval = 600

  struct Link: Codable, Equatable, Identifiable {
    let id: UUID
    let concern: UUID
    let visit: UUID
    let visitRevision: Int
    let expectedConcernRevision: Int
    let revision: Int
    let originalID: UUID
    let fingerprint: Data
    let page: Int?
    let pageCount: Int
  }

  struct Item: Identifiable {
    let link: Link
    let original: Original?
    var id: UUID { link.id }
  }

  struct Scope: Equatable {
    let stamp: GalaxySSIHealthEncounter.Stamp
    let visit: GalaxySSIHealthEncounter.Entry
  }

  struct Preview {
    let scope: Scope
    let original: Original
    let page: Int
    let count: Int
    let image: UIImage
    let expires: Date
    let operation: UUID
  }

  struct Page {
    let scope: Scope
    let items: [Item]
    let next: Int?
  }

  struct LibraryPage {
    let originals: [Original]
    let next: Original?
  }

  static func fingerprint(_ original: Original, key: SymmetricKey) -> Data {
    let fields = ["galaxyssi.health.visit.original.v1", original.id.uuidString, original.kind.rawValue,
      original.fileExtension, String(original.bytes), original.sha256]
    return Data(HMAC<SHA256>.authenticationCode(for: Data(fields.joined(separator: "\u{0}").utf8), using: key))
  }

  static func matches(_ link: Link, original: Original, key: SymmetricKey) -> Bool {
    link.originalID == original.id && link.fingerprint == fingerprint(original, key: key)
  }

  static func render(_ data: Data, kind: GalaxySSIHealthOriginalStore.Kind, page: Int) throws -> (UIImage, Int) {
    switch kind {
    case .pdf:
      guard let pdf = PDFDocument(data: data), !pdf.isLocked, page > 0,
            page <= pdf.pageCount, let source = pdf.page(at: page - 1)
      else { throw GalaxySSIHealthRecords.Failure.stale }
      return (source.thumbnail(of: CGSize(width: 900, height: 1200), for: .cropBox), pdf.pageCount)
    case .image:
      guard page == 1, let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 1200
            ] as CFDictionary)
      else { throw GalaxySSIHealthRecords.Failure.stale }
      return (UIImage(cgImage: image), 1)
    }
  }
}
