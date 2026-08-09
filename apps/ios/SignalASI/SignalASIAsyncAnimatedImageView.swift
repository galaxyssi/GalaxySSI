import Combine
import ImageIO
import SwiftUI
import UIKit

struct SignalASIAsyncAnimatedImageView<Failure: View>: View {
  let url: URL
  private let failure: () -> Failure
  @StateObject private var loader = SignalASIAsyncAnimatedImageLoader()

  init(url: URL, @ViewBuilder failure: @escaping () -> Failure) {
    self.url = url
    self.failure = failure
  }

  var body: some View {
    Group {
      switch loader.state {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 80)
      case .loaded(let data):
        SignalASIRemoteAnimatedImageView(data: data)
      case .failed:
        failure()
      }
    }
    .task(id: url) {
      await loader.load(url: url)
    }
  }
}

@MainActor
private final class SignalASIAsyncAnimatedImageLoader: ObservableObject {
  enum State {
    case loading
    case loaded(Data)
    case failed
  }

  @Published private(set) var state: State = .loading

  func load(url: URL) async {
    state = .loading
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.cachePolicy = .returnCacheDataElseLoad

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard data.count <= Self.maximumImageBytes,
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            SignalASIRemoteAnimatedImageDecoder.canDecode(data) else {
        state = .failed
        return
      }
      state = .loaded(data)
    } catch is CancellationError {
      return
    } catch {
      state = .failed
    }
  }

  private static let maximumImageBytes = 12 * 1024 * 1024
}

private struct SignalASIRemoteAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    imageView.stopAnimating()
    imageView.animationImages = nil

    if let frames = SignalASIRemoteAnimatedImageDecoder.frames(from: data), frames.count > 1 {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      imageView.startAnimating()
    } else {
      imageView.image = UIImage(data: data)
    }
  }
}

private enum SignalASIRemoteAnimatedImageDecoder {
  struct Frames {
    var images: [UIImage]
    var duration: TimeInterval
  }

  static func canDecode(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 0
  }

  static func frames(from data: Data) -> Frames? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else { return nil }

    var images: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<count {
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
      images.append(UIImage(cgImage: image))
      duration += frameDelay(source: source, index: index)
    }
    guard !images.isEmpty else { return nil }
    return Frames(images: images, duration: max(duration, 0.08 * Double(images.count)))
  }

  private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
          let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
      return 0.08
    }
    let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let clamped = (gif[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0
    let delay = unclamped > 0 ? unclamped : clamped
    return delay > 0.01 ? delay : 0.08
  }
}
