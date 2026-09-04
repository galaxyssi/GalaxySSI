import PhotosUI
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
  var onAttachment: (GalaxySSIDraftAttachment) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount
    let controller = PHPickerViewController(configuration: configuration)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttachment: onAttachment)
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let onAttachment: (GalaxySSIDraftAttachment) -> Void

    init(onAttachment: @escaping (GalaxySSIDraftAttachment) -> Void) {
      self.onAttachment = onAttachment
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      picker.dismiss(animated: true)
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
