import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentPreviewStrip: View {
  var attachments: [SignalASIDraftAttachment]
  var onRemove: (SignalASIDraftAttachment) -> Void

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
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var attachment: SignalASIDraftAttachment
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
              .foregroundColor(.signalASITextPrimary)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(attachment.humanSize)
              .font(.system(size: 11))
              .foregroundColor(.signalASITextSecondary)
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
          .foregroundColor(.signalASITextSecondary)
          .background(Circle().fill(Color.signalASISurface.opacity(0.88)))
      }
      .padding(5)
      .accessibilityLabel(Text(t("agent_attachment_remove", "Remove attachment")))
    }
    .background(Color.signalASISearchBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 1)
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
        .foregroundColor(.signalASITextSecondary)
        .frame(width: 34, height: 34)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIAttachmentMenuRow: View {
  var title: String
  var systemImage: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 28)
        Text(title)
          .font(.system(size: 17, weight: .regular))
          .foregroundColor(.signalASITextPrimary)
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

struct SignalASIAttachmentMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.signalASISeparator)
      .frame(height: 1)
      .padding(.leading, 62)
  }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
  var onAttachment: (SignalASIDraftAttachment) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = SignalASIAttachmentPayloadBuilder.maximumAttachmentCount
    let controller = PHPickerViewController(configuration: configuration)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttachment: onAttachment)
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let onAttachment: (SignalASIDraftAttachment) -> Void

    init(onAttachment: @escaping (SignalASIDraftAttachment) -> Void) {
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
          let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
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
  var onAttachment: (SignalASIDraftAttachment) -> Void
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
    private let onAttachment: (SignalASIDraftAttachment) -> Void
    private let onCancel: () -> Void

    init(
      onAttachment: @escaping (SignalASIDraftAttachment) -> Void,
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
      let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
        data: data,
        suggestedName: "signalasi_\(Int(Date().timeIntervalSince1970)).jpg",
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
