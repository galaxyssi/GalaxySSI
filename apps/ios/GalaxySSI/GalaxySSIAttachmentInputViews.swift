import PhotosUI
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentPreviewStrip: View {
  var attachments: [GalaxySSIDraftAttachment]
  var onRemove: (GalaxySSIDraftAttachment) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(attachments) { attachment in
            AttachmentPreviewChip(attachment: attachment) {
              onRemove(attachment)
            }
            .id(attachment.id)
          }
        }
        .frame(height: 74, alignment: .center)
        .padding(.top, 8)
      }
      .frame(height: 82, alignment: .top)
      .onAppear {
        scrollToLatest(using: proxy)
      }
      .onChange(of: attachments.map(\.id)) { _ in
        scrollToLatest(using: proxy)
      }
    }
  }

  private func scrollToLatest(using proxy: ScrollViewProxy) {
    guard let latestID = attachments.last?.id else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(latestID, anchor: .trailing)
    }
  }
}

struct AttachmentPreviewChip: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var attachment: GalaxySSIDraftAttachment
  var onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      if attachment.isImage {
        thumbnail
          .frame(width: 70, height: 66)
      } else {
        HStack(spacing: 8) {
          thumbnail
          VStack(alignment: .leading, spacing: 2) {
            Text(attachment.displayName)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(attachment.humanSize)
              .font(.system(size: 11))
              .foregroundColor(.galaxySSITextSecondary)
          }
          Spacer(minLength: 22)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(width: 190, height: 66)
      }
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .background(Circle().fill(Color.galaxySSISurface.opacity(0.88)))
      }
      .padding(5)
      .accessibilityLabel(Text(t("agent_attachment_remove", "Remove attachment")))
    }
    .background(Color.galaxySSISearchBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var thumbnail: some View {
    if attachment.isImage,
       let image = UIImage(data: attachment.data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .clipped()
    } else {
      Image(systemName: "doc")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .frame(width: 34, height: 34)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAttachmentMenuRow: View {
  var title: String
  var systemImage: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .frame(width: 28)
        Text(title)
          .font(.system(size: 17, weight: .regular))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 22)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSIAttachmentMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.galaxySSISeparator)
      .frame(height: 1)
      .padding(.leading, 62)
  }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
  var selectionLimit = GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount
  var dismissOnSelection = true
  var onAttachment: (GalaxySSIDraftAttachment) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = max(1, min(selectionLimit, GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount))
    let controller = PHPickerViewController(configuration: configuration)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(dismissOnSelection: dismissOnSelection, onAttachment: onAttachment)
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let onAttachment: (GalaxySSIDraftAttachment) -> Void
    private let dismissOnSelection: Bool

    init(dismissOnSelection: Bool, onAttachment: @escaping (GalaxySSIDraftAttachment) -> Void) {
      self.dismissOnSelection = dismissOnSelection
      self.onAttachment = onAttachment
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      if dismissOnSelection || results.isEmpty { picker.dismiss(animated: true) }
      results.forEach { result in
        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
          UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
          guard let data else { return }
          let name = provider.suggestedName.map { "\($0).jpg" } ?? "photo.jpg"
          let attachment = GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(
            data: data,
            suggestedName: name
          )
          DispatchQueue.main.async {
            self.onAttachment(attachment)
          }
        }
      }
    }
  }
}

struct GalaxySSIScreenshotInputView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var attachment: GalaxySSIDraftAttachment?
  @State private var preview: UIImage?
  @State private var selection: CGRect?
  @State private var failed = false
  var onAttachment: (GalaxySSIDraftAttachment) -> Void

  var body: some View {
    NavigationView {
      Group {
        if let preview {
          GeometryReader { geometry in
            let scale = min(geometry.size.width / preview.size.width, geometry.size.height / preview.size.height)
            let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
            Image(uiImage: preview).resizable().frame(width: size.width, height: size.height)
              .overlay {
                if let selection {
                  Rectangle().fill(Color.black.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: selection.width * size.width, height: selection.height * size.height)
                    .position(x: selection.midX * size.width, y: selection.midY * size.height)
                }
              }
              .contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                selection = Self.cropSelection(from: value.startLocation, to: value.location, size: size)
              })
              .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
          }
          .padding(12)
        } else {
          PhotoLibraryPickerView(selectionLimit: 1, dismissOnSelection: false) { selected in
            guard selected.data.count <= 64 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(selected.data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096
                  ] as CFDictionary) else { failed = true; return }
            attachment = selected
            preview = UIImage(cgImage: image)
          }
        }
      }
      .navigationTitle(t("galaxyssi.screen_assistant.analyze", "Analyze screenshot"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) { dismiss() }
        }
        ToolbarItemGroup(placement: .confirmationAction) {
          if preview != nil {
            Button { selection = nil } label: { Image(systemName: "arrow.counterclockwise") }
              .accessibilityLabel(t("galaxyssi.screen_assistant.reset_crop", "Reset crop"))
            Button(action: confirm) { Image(systemName: "checkmark") }
              .accessibilityLabel(t("galaxyssi.screen_assistant.use_image", "Use image"))
          }
        }
      }
      .alert(t("galaxyssi.screen_assistant.image_error", "Image could not be prepared"), isPresented: $failed) {
        Button(t("galaxyssi.common.done", "Done"), role: .cancel) {}
      }
    }
    .navigationViewStyle(.stack)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in dismiss() }
    .onDisappear { attachment = nil; preview = nil; selection = nil }
  }

  static func cropSelection(from start: CGPoint, to end: CGPoint, size: CGSize) -> CGRect? {
    guard size.width > 0, size.height > 0 else { return nil }
    let x1 = min(max(start.x / size.width, 0), 1)
    let x2 = min(max(end.x / size.width, 0), 1)
    let y1 = min(max(start.y / size.height, 0), 1)
    let y2 = min(max(end.y / size.height, 0), 1)
    guard abs(x2 - x1) * size.width >= 4, abs(y2 - y1) * size.height >= 4 else { return nil }
    return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
  }

  private func confirm() {
    guard let attachment else { return }
    if let selection, let source = preview?.cgImage {
      let rect = CGRect(x: selection.minX * CGFloat(source.width), y: selection.minY * CGFloat(source.height),
        width: selection.width * CGFloat(source.width), height: selection.height * CGFloat(source.height)).integral
      guard let cropped = source.cropping(to: rect), let data = UIImage(cgImage: cropped).pngData() else {
        failed = true; return
      }
      onAttachment(GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(data: data,
        suggestedName: "screenshot-crop.png", sourceDescription: "screenshot-crop"))
    } else {
      onAttachment(attachment)
    }
    dismiss()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

struct CameraAttachmentPickerView: UIViewControllerRepresentable {
  var onAttachment: (GalaxySSIDraftAttachment) -> Void
  var onCancel: () -> Void = {}

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.cameraCaptureMode = .photo
    controller.modalPresentationStyle = .fullScreen
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttachment: onAttachment, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onAttachment: (GalaxySSIDraftAttachment) -> Void
    private let onCancel: () -> Void

    init(
      onAttachment: @escaping (GalaxySSIDraftAttachment) -> Void,
      onCancel: @escaping () -> Void
    ) {
      self.onAttachment = onAttachment
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer { picker.dismiss(animated: true) }
      guard let image = info[.originalImage] as? UIImage,
            let data = image.jpegData(compressionQuality: 0.9) else {
        onCancel()
        return
      }
      let attachment = GalaxySSIAttachmentPayloadBuilder.makePhotoAttachment(
        data: data,
        suggestedName: "galaxyssi_\(Int(Date().timeIntervalSince1970)).jpg",
        sourceDescription: "camera"
      )
      onAttachment(attachment)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
      picker.dismiss(animated: true)
    }
  }
}
