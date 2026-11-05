import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class GalaxySSIImagePastingTextView: UITextView {
  var onImagePaste: (() -> Void)?

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)), onImagePaste != nil, UIPasteboard.general.hasImages { return true }
    return super.canPerformAction(action, withSender: sender)
  }

  override func paste(_ sender: Any?) {
    if let onImagePaste, UIPasteboard.general.hasImages { onImagePaste() }
    else { super.paste(sender) }
  }
}

enum GalaxySSIImageClipboard {
  static let maximumBytes = 32 * 1024 * 1024

  static func validated(_ data: Data) -> UTType? {
    guard data.count <= maximumBytes, let type = GalaxySSIImageResourceDecoder.originalType(data),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 16_384, height <= 16_384,
          Int64(width) * Int64(height) <= 40_000_000 else { return nil }
    return type
  }

  @MainActor
  static func read() -> Data? {
    for item in UIPasteboard.general.items {
      for (identifier, value) in item {
        guard UTType(identifier)?.conforms(to: .image) == true else { continue }
        if let data = value as? Data, validated(data) != nil { return data }
      }
    }
    if let image = UIPasteboard.general.image,
       image.size.width * image.scale <= 16_384, image.size.height * image.scale <= 16_384,
       image.size.width * image.size.height * image.scale * image.scale <= 40_000_000,
       let data = image.pngData(), validated(data) != nil { return data }
    return nil
  }

  @MainActor
  @discardableResult
  static func copy(_ data: Data) -> Bool {
    guard let type = validated(data) else { return false }
    UIPasteboard.general.setItems([[type.identifier: data]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
    return true
  }

  static func preview(_ data: Data) -> UIImage? {
    guard validated(data) != nil, let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
          ] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }

  static func prepared(_ data: Data, original: Bool, crop: CGRect?) -> Data? {
    guard validated(data) != nil else { return nil }
    if original && crop == nil { return data }
    guard let image = original ? UIImage(data: data) : preview(data) else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let upright = UIGraphicsImageRenderer(size: size, format: format).image {
      _ in image.draw(in: CGRect(origin: .zero, size: size))
    }
    var result = upright
    if let crop, let source = upright.cgImage {
      let bounded = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
      guard !bounded.isNull, bounded.width > 0, bounded.height > 0,
            let cropped = source.cropping(to: CGRect(x: bounded.minX * CGFloat(source.width),
              y: bounded.minY * CGFloat(source.height), width: bounded.width * CGFloat(source.width),
              height: bounded.height * CGFloat(source.height)).integral) else { return nil }
      result = UIImage(cgImage: cropped)
    }
    return original ? result.pngData() : result.jpegData(compressionQuality: 0.85)
  }
}

struct GalaxySSIClipboardImageReview: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let data: Data
  let onAdd: (GalaxySSIDraftAttachment) -> Void
  @State private var image: UIImage?
  @State private var original = false
  @State private var busy = false
  @State private var cropping = false
  @State private var crop: CGRect?

  var body: some View {
    NavigationView {
      VStack(spacing: 16) {
        if let image {
          GeometryReader { proxy in
            Image(uiImage: image).resizable().scaledToFit()
              .overlay {
                if let crop {
                  Rectangle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: crop.width * proxy.size.width, height: crop.height * proxy.size.height)
                    .position(x: crop.midX * proxy.size.width, y: crop.midY * proxy.size.height)
                }
              }
              .contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                guard cropping else { return }
                crop = GalaxySSIScreenshotInputView.cropSelection(from: value.startLocation, to: value.location, size: proxy.size)
              })
          }
          .aspectRatio(image.size, contentMode: .fit)
          HStack {
            Button { cropping.toggle() } label: { Image(systemName: "crop").frame(width: 44, height: 44) }
              .foregroundColor(cropping ? .accentColor : .primary)
              .accessibilityLabel(t("clipboard_image_crop", "Crop"))
            Button { crop = nil; cropping = false } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
              .disabled(crop == nil)
              .accessibilityLabel(t("clipboard_image_reset", "Reset crop"))
          }
          Picker(t("clipboard_image_quality", "Image quality"), selection: $original) {
            Text(t("clipboard_image_compressed", "Compressed")).tag(false)
            Text(t("clipboard_image_original", "Original")).tag(true)
          }.pickerStyle(.segmented)
        } else { ProgressView().frame(maxHeight: .infinity) }
      }
      .padding()
      .navigationTitle(t("clipboard_image_preview", "Image preview"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("clipboard_image_add", "Add attachment")) { add() }
            .disabled(image == nil || busy)
        }
      }
    }
    .navigationViewStyle(.stack)
    .task {
      let result = await Task.detached(priority: .userInitiated) { GalaxySSIImageClipboard.preview(data) }.value
      guard !Task.isCancelled else { return }
      image = result
    }
    .onDisappear { image = nil }
  }

  private func add() {
    guard image != nil, !busy else { return }
    busy = true
    Task { @MainActor in
      let bytes = await Task.detached(priority: .userInitiated) { [data, original, crop] in
        GalaxySSIImageClipboard.prepared(data, original: original, crop: crop)
      }.value
      if let bytes, let type = GalaxySSIImageClipboard.validated(bytes) {
        onAdd(GalaxySSIDraftAttachment(displayName: "clipboard." + (type.preferredFilenameExtension ?? "png"),
          mimeType: type.preferredMIMEType ?? "image/png", data: bytes, sourceDescription: "clipboard"))
      }
      dismiss()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
