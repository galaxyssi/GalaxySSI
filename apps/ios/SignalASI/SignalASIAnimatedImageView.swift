import SwiftUI
import UIKit

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
    if let frames = AgentAnimatedImageTiming.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      imageView.startAnimating()
    } else {
      imageView.animationImages = nil
      imageView.image = AgentAnimatedImageTiming.staticImage(from: data)
    }
  }
}

struct SignalASIImageViewerItem: Identifiable {
  let id: String
  let data: Data?
  let url: URL?
  let title: String
}

struct SignalASIImageLightboxView: View {
  let item: SignalASIImageViewerItem

  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
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
      SignalASIAnimatedImageView(data: data)
    } else if let url = item.url {
      SignalASIAsyncAnimatedImageView(url: url) {
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIImageThumbnailView: View {
  let item: SignalASIImageViewerItem
  let onTap: () -> Void

  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    imageContent
      .frame(width: 124, height: 92)
      .background(Color.signalASISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .onTapGesture(perform: onTap)
      .accessibilityLabel(
        item.title.isEmpty
          ? SignalASILocalization.string(
            "rich_output_type_image",
            fallback: "Image",
            language: interfaceLanguage
          )
          : item.title
      )
      .accessibilityAddTraits(.isButton)
  }

  @ViewBuilder
  private var imageContent: some View {
    if let data = item.data {
      SignalASIAnimatedImageView(data: data)
    } else if let url = item.url {
      SignalASIAsyncAnimatedImageView(url: url) {
        Image(systemName: "photo")
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      Image(systemName: "photo")
        .foregroundColor(.signalASITextSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
