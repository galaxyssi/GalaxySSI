import ImageIO
import SwiftUI
import UIKit

enum GalaxySSIImageResourceDecoder {
  static let maximumBytes = 12 * 1024 * 1024
  static let maximumPixelDimension = 2_048
  static let thumbnailWidth: CGFloat = 112
  static let thumbnailHeight: CGFloat = 168

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

  static func galleryThumbnailSize(from data: Data?) -> CGSize {
    let portrait = CGSize(width: thumbnailWidth, height: thumbnailHeight)
    guard let data,
          let image = staticImage(from: data),
          image.size.width > image.size.height else {
      return portrait
    }
    return CGSize(width: thumbnailHeight, height: thumbnailWidth)
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

struct GalaxySSIAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = GalaxySSIRichAnimatedImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    let identity = String(data.base64EncodedString().hashValue)
    guard imageView.accessibilityIdentifier != identity else { return }
    imageView.accessibilityIdentifier = identity
    GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.deactivate(imageView)
    if let frames = GalaxySSIImageResourceDecoder.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      if imageView.window != nil {
        GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.activate(imageView)
      }
    } else {
      imageView.animationImages = nil
      imageView.image = GalaxySSIImageResourceDecoder.staticImage(from: data)
    }
  }
}

struct GalaxySSIImageViewerItem: Identifiable {
  let id: String
  let data: Data?
  let url: URL?
  let title: String
}

struct GalaxySSIImageLightboxView: View {
  let item: GalaxySSIImageViewerItem

  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var scale: CGFloat = 1
  @State private var baseScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var baseOffset: CGSize = .zero

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      imageContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .offset(offset)
        .contentShape(Rectangle())
        .gesture(magnificationGesture)
        .simultaneousGesture(panGesture)
        .onTapGesture(count: 2, perform: reset)

      VStack {
        HStack(alignment: .top, spacing: 12) {
          if !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(item.title)
              .font(.caption.weight(.semibold))
              .foregroundColor(.white)
              .lineLimit(2)
              .padding(.horizontal, 10)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.55))
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
          Spacer(minLength: 8)
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.headline.weight(.semibold))
              .foregroundColor(.white)
              .frame(width: 44, height: 44)
              .background(Color.white.opacity(0.14))
              .clipShape(Circle())
          }
          .accessibilityLabel(t("common_close", "Close"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        Spacer()
      }
    }
    .statusBarHidden(true)
  }

  @ViewBuilder
  private var imageContent: some View {
    if let data = item.data {
      GalaxySSIAnimatedImageView(data: data)
    } else if let url = item.url {
      GalaxySSIAsyncAnimatedImageView(url: url) {
        VStack(spacing: 8) {
          Image(systemName: "photo")
            .font(.title2)
          Text(t("rich_output_load_failed", "Unable to display preview"))
            .font(.caption)
        }
        .foregroundColor(.white.opacity(0.8))
      }
    } else {
      Image(systemName: "photo")
        .font(.title2)
        .foregroundColor(.white.opacity(0.8))
    }
  }

  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = clampedScale(baseScale * value)
      }
      .onEnded { _ in
        baseScale = scale
        if scale <= 1 {
          resetOffset()
        }
      }
  }

  private var panGesture: some Gesture {
    DragGesture(minimumDistance: 8)
      .onChanged { value in
        guard scale > 1 else { return }
        offset = CGSize(
          width: baseOffset.width + value.translation.width,
          height: baseOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        baseOffset = offset
      }
  }

  private func reset() {
    withAnimation(.easeOut(duration: 0.18)) {
      scale = 1
      baseScale = 1
      resetOffset()
    }
  }

  private func resetOffset() {
    offset = .zero
    baseOffset = .zero
  }

  private func clampedScale(_ value: CGFloat) -> CGFloat {
    min(max(value, 1), 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIImageThumbnailView: View {
  let item: GalaxySSIImageViewerItem
  let onTap: () -> Void

  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var remoteThumbnailSize: CGSize?

  var body: some View {
    imageContent
      .frame(width: thumbnailSize.width, height: thumbnailSize.height)
      .background(Color.galaxySSISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .onTapGesture(perform: onTap)
      .accessibilityLabel(
        item.title.isEmpty
          ? GalaxySSILocalization.string(
            "rich_output_type_image",
            fallback: "Image",
            language: interfaceLanguage
          )
          : item.title
      )
      .accessibilityAddTraits(.isButton)
  }

  private var thumbnailSize: CGSize {
    if let data = item.data {
      return GalaxySSIImageResourceDecoder.galleryThumbnailSize(from: data)
    }
    return remoteThumbnailSize ?? CGSize(
      width: GalaxySSIImageResourceDecoder.thumbnailWidth,
      height: GalaxySSIImageResourceDecoder.thumbnailHeight
    )
  }

  @ViewBuilder
  private var imageContent: some View {
    if let data = item.data {
      GalaxySSIAnimatedImageView(data: data)
    } else if let url = item.url {
      GalaxySSIAsyncAnimatedImageView(
        url: url,
        onLoaded: { data in
          remoteThumbnailSize = GalaxySSIImageResourceDecoder.galleryThumbnailSize(from: data)
        }
      ) {
        Image(systemName: "photo")
          .foregroundColor(.galaxySSITextSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      Image(systemName: "photo")
        .foregroundColor(.galaxySSITextSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
