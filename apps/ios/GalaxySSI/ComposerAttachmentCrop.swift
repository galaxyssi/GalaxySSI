import ImageIO
import UIKit

struct ComposerAttachmentCrop: Equatable, Sendable {
  enum Aspect: String, CaseIterable, Identifiable, Sendable {
    case free, original, square, fourThree, sixteenNine
    var id: Self { self }

    func ratio(source: CGSize) -> CGFloat? {
      switch self {
      case .free: return nil
      case .original: return source.width / source.height
      case .square: return 1
      case .fourThree: return 4.0 / 3
      case .sixteenNine: return 16.0 / 9
      }
    }
  }

  var aspect: Aspect = .free
  var rotation: Int = 0
  var fineRotation: Double = 0
  var mirrored = false
  var zoom: CGFloat = 1
  var freeSelection: CGRect?

  var radians: CGFloat {
    CGFloat(Double(rotation % 360) + min(45, max(-45, fineRotation))) * .pi / 180
  }

  func canvas(for source: CGSize) -> CGSize {
    let sine = abs(sin(radians)), cosine = abs(cos(radians))
    return CGSize(width: ceil(source.width * cosine + source.height * sine - 0.000_001),
                  height: ceil(source.width * sine + source.height * cosine - 0.000_001))
  }

  func selection(in canvas: CGSize, source: CGSize) -> CGRect {
    guard canvas.width > 0, canvas.height > 0, source.width > 0, source.height > 0 else { return .zero }
    let full = CGRect(origin: .zero, size: canvas)
    let base: CGRect
    if aspect == .free, let freeSelection {
      let normalized = freeSelection.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
      if !normalized.isNull, normalized.width >= 0.02, normalized.height >= 0.02 {
        base = CGRect(x: normalized.minX * canvas.width, y: normalized.minY * canvas.height,
                      width: normalized.width * canvas.width, height: normalized.height * canvas.height)
      } else {
        base = full
      }
    } else if let ratio = aspect.ratio(source: source) {
      let width = min(canvas.width, canvas.height * ratio)
      let height = width / ratio
      base = CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2,
                    width: width, height: height)
    } else {
      base = full
    }
    let scale = min(4, max(1, zoom))
    return CGRect(x: base.midX - base.width / scale / 2, y: base.midY - base.height / scale / 2,
                  width: base.width / scale, height: base.height / scale)
  }

  static func image(from data: Data, maxPixelSize: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }

  func render(_ image: UIImage, crop: Bool) -> UIImage? {
    let canvas = canvas(for: image.size)
    let rect = crop ? selection(in: canvas, source: image.size) : CGRect(origin: .zero, size: canvas)
    guard rect.width >= 1, rect.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: rect.width.rounded(.down), height: rect.height.rounded(.down)),
                                   format: format).image { context in
      let cg = context.cgContext
      cg.translateBy(x: canvas.width / 2 - rect.minX, y: canvas.height / 2 - rect.minY)
      cg.rotate(by: radians)
      cg.scaleBy(x: mirrored ? -1 : 1, y: 1)
      image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                            width: image.size.width, height: image.size.height))
    }
  }

  func derivative(from data: Data) -> Data? {
    guard let image = Self.image(from: data, maxPixelSize: 3_072),
          let output = render(image, crop: true)?.pngData(),
          output.count <= GalaxySSIAttachmentPayloadBuilder.maximumAttachmentBytes else { return nil }
    return output
  }
}

struct ComposerAttachmentOriginal: Equatable, Sendable {
  let displayName: String
  let mimeType: String
  var data: Data
}

extension GalaxySSIDraftAttachment {
  var composerSourceData: Data { composerOriginal?.data ?? data }
  var requiresInitialComposerImageReview: Bool {
    isImage && composerImageQuality == nil &&
      (sourceDescription == "camera" || sourceDescription == "photo-library" || sourceDescription.hasPrefix("file:"))
  }

  func applyingComposerImageQuality(_ quality: ComposerImageQuality) -> Self? {
    guard isImage else { return nil }
    var edited = self
    if quality == .original {
      if composerCrop == nil { edited = restoringComposerOriginal() }
      guard !edited.data.isEmpty, edited.data.count <= ComposerImageQuality.maximumOriginalBytes else { return nil }
    } else if composerCrop == nil {
      let source = composerSourceData
      let normalized = AgentAnimatedImageTiming.normalizeZeroFrameDelays(source)
      if normalized != source {
        edited.composerOriginal = composerOriginal ?? .init(displayName: displayName, mimeType: mimeType, data: source)
        edited.data = normalized
      }
    }
    edited.composerImageQuality = quality
    return edited
  }

  func applyingComposerCrop(_ crop: ComposerAttachmentCrop, derivative: Data) -> Self? {
    guard isImage, !derivative.isEmpty,
          derivative.count <= GalaxySSIAttachmentPayloadBuilder.maximumAttachmentBytes else { return nil }
    var edited = self
    let original = composerOriginal ?? ComposerAttachmentOriginal(
      displayName: displayName, mimeType: mimeType, data: data
    )
    edited.composerOriginal = original
    edited.composerCrop = crop
    edited.displayName = (original.displayName as NSString).deletingPathExtension + "-crop.png"
    edited.mimeType = "image/png"
    edited.data = derivative
    return edited
  }

  func restoringComposerOriginal() -> Self {
    guard let composerOriginal else { return self }
    var restored = self
    restored.displayName = composerOriginal.displayName
    restored.mimeType = composerOriginal.mimeType
    restored.data = composerOriginal.data
    restored.composerOriginal = nil
    restored.composerCrop = nil
    return restored
  }
}

extension Array where Element == GalaxySSIDraftAttachment {
  @discardableResult
  mutating func replaceComposerAttachment(_ expected: Element, with edited: Element) -> Bool {
    guard expected.id == edited.id, let index = firstIndex(where: { $0.id == expected.id }),
          self[index] == expected else { return false }
    var previous = self[index]
    self[index] = edited
    previous.wipeSensitive()
    return true
  }
}
