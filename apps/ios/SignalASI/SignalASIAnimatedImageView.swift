import ImageIO
import SwiftUI
import UIKit

enum SignalASIImageResourceDecoder {
  static let maximumBytes = 12 * 1024 * 1024
  static let maximumPixelDimension = 2_048

  static func base64Data(_ value: String) -> Data? {
    var encoded = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let comma = encoded.firstIndex(of: ",") {
      encoded = String(encoded[encoded.index(after: comma)...])
    }
    guard !encoded.isEmpty,
          encoded.utf8.count <= maximumEncodedCharacters,
          let data = Data(base64Encoded: encoded),
          data.count <= maximumBytes else {
      return nil
    }
    return data
  }

  static func fileData(_ url: URL) -> Data? {
    guard url.isFileURL,
          let stream = InputStream(url: url) else {
      return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    data.reserveCapacity(min(maximumBytes, 256 * 1024))
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { return nil }
      guard count > 0 else { break }
      data.append(contentsOf: buffer[0..<count])
      guard data.count <= maximumBytes else { return nil }
    }
    guard stream.streamError == nil else { return nil }
    return data.isEmpty ? nil : data
  }

  static func canDecode(_ data: Data) -> Bool {
    guard data.count <= maximumBytes,
          let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return false
    }
    return CGImageSourceGetCount(source) > 0
  }

  static func frames(from source: Data) -> AgentAnimatedImageFrames? {
    let data = AgentAnimatedImageTiming.normalizeZeroFrameDelays(source)
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(imageSource)
    guard count > 1 else { return nil }

    var images: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<count {
      guard let image = thumbnail(imageSource: imageSource, index: index) else { continue }
      images.append(UIImage(cgImage: image))
      duration += frameDelay(imageSource: imageSource, index: index)
    }
    guard images.count > 1 else { return nil }
    return AgentAnimatedImageFrames(
      images: images,
      duration: max(0.08 * Double(images.count), duration)
    )
  }

  static func staticImage(from source: Data) -> UIImage? {
    let data = AgentAnimatedImageTiming.normalizeZeroFrameDelays(source)
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
          let image = thumbnail(imageSource: imageSource, index: 0) else {
      return nil
    }
    return UIImage(cgImage: image)
  }

  private static func thumbnail(imageSource: CGImageSource, index: Int) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
      kCGImageSourceCreateThumbnailWithTransform: true
    ]
    return CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary)
  }

  private static func frameDelay(imageSource: CGImageSource, index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
          let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
      return 0.08
    }
    let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let clamped = (gif[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let delay = unclamped > 0 ? unclamped : clamped
    return delay > 0 ? min(delay, 5) : 0.08
  }

  private static let maximumEncodedCharacters = ((maximumBytes + 2) / 3) * 4 + 4
}

struct SignalASIAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    let identity = String(data.base64EncodedString().hashValue)
    guard imageView.accessibilityIdentifier != identity else { return }
    imageView.accessibilityIdentifier = identity
    imageView.stopAnimating()
    if let frames = SignalASIImageResourceDecoder.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      imageView.startAnimating()
    } else {
      imageView.animationImages = nil
      imageView.image = SignalASIImageResourceDecoder.staticImage(from: data)
    }
  }
}
