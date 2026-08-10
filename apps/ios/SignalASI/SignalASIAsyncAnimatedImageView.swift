import Combine
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
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            httpResponse.expectedContentLength <= Int64(SignalASIImageResourceDecoder.maximumBytes) ||
              httpResponse.expectedContentLength < 0 else {
        state = .failed
        return
      }
      var data = Data()
      data.reserveCapacity(min(SignalASIImageResourceDecoder.maximumBytes, 256 * 1024))
      for try await byte in bytes {
        data.append(byte)
        guard data.count <= SignalASIImageResourceDecoder.maximumBytes else {
          state = .failed
          return
        }
      }
      guard SignalASIImageResourceDecoder.canDecode(data) else {
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

}

private struct SignalASIRemoteAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = SignalASIRichAnimatedImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    SignalASIRichAnimatedImagePlaybackCoordinator.shared.deactivate(imageView)
    imageView.animationImages = nil

    if let frames = SignalASIImageResourceDecoder.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      if imageView.window != nil {
        SignalASIRichAnimatedImagePlaybackCoordinator.shared.activate(imageView)
      }
    } else {
      imageView.image = SignalASIImageResourceDecoder.staticImage(from: data)
    }
  }
}
