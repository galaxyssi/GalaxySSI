import Combine
import SwiftUI
import UIKit

struct GalaxySSIAsyncAnimatedImageView<Failure: View>: View {
  let url: URL
  private let onLoaded: ((Data) -> Void)?
  private let decodeOffMain: Bool
  private let publicWebImage: Bool
  private let failure: () -> Failure
  @StateObject private var loader = GalaxySSIAsyncAnimatedImageLoader()
  @Environment(\.scenePhase) private var scene
  private struct LoadID: Hashable { var url: URL; var publicWebImage: Bool; var active: Bool }

  init(
    url: URL,
    onLoaded: ((Data) -> Void)? = nil,
    decodeOffMain: Bool = false,
    publicWebImage: Bool = false,
    @ViewBuilder failure: @escaping () -> Failure
  ) {
    self.url = url
    self.onLoaded = onLoaded
    self.decodeOffMain = decodeOffMain
    self.publicWebImage = publicWebImage
    self.failure = failure
  }

  var body: some View {
    Group {
      switch loader.state {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 80)
      case .loaded(let data):
        Group {
          if !loader.represents(url: url, publicWebImage: publicWebImage) { ProgressView() }
          else if decodeOffMain { Color.clear }
          else { GalaxySSIRemoteAnimatedImageView(data: data) }
        }
        .onAppear {
          if loader.represents(url: url, publicWebImage: publicWebImage) { onLoaded?(data) }
        }
      case .failed:
        failure()
      }
    }
    .task(id: LoadID(url: url, publicWebImage: publicWebImage, active: scene == .active)) {
      guard scene == .active else { loader.cancel(); return }
      await loader.load(url: url, publicWebImage: publicWebImage)
    }
    .onDisappear { loader.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in loader.cancel() }
  }
}

@MainActor
final class GalaxySSIAsyncAnimatedImageLoader: ObservableObject {
  enum State: Equatable {
    case loading
    case loaded(Data)
    case failed
  }

  @Published private(set) var state: State = .loading
  private let fetch: @Sendable (URL, Bool) async throws -> Data
  private var generation = UUID()
  private var activeTask: Task<Data, Error>?
  private var loadedURL: URL?
  private var loadedPublicWebImage = false

  init(fetch: @escaping @Sendable (URL, Bool) async throws -> Data = GalaxySSIAsyncAnimatedImageLoader.download) {
    self.fetch = fetch
  }

  func cancel() {
    generation = UUID()
    activeTask?.cancel()
    activeTask = nil
    loadedURL = nil
    state = .loading
  }

  func represents(url: URL, publicWebImage: Bool) -> Bool {
    loadedURL == url && loadedPublicWebImage == publicWebImage
  }

  func load(url: URL, publicWebImage: Bool = false) async {
    cancel()
    let current = generation
    let fetch = self.fetch
    let task = Task.detached(priority: .userInitiated) { try await fetch(url, publicWebImage) }
    activeTask = task
    defer { if generation == current { activeTask = nil } }
    do {
      let data = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
      try Task.checkCancellation()
      guard generation == current else { return }
      loadedURL = url
      loadedPublicWebImage = publicWebImage
      state = .loaded(data)
    } catch {
      guard generation == current, !Task.isCancelled, !(error is CancellationError),
        (error as? URLError)?.code != .cancelled else { return }
      state = .failed
    }
  }

  nonisolated private static func download(_ url: URL, publicWebImage: Bool) async throws -> Data {
    if publicWebImage { return try await AgentMarkdownImageStore.shared.image(url) }
    let response = try await AgentRemoteImageTransfer(url: url, timeout: 20, followsRedirects: true).run()
    try Task.checkCancellation()
    guard !response.data.isEmpty, GalaxySSIImageResourceDecoder.canDecode(response.data) else { throw AgentMarkdownImageFailure.unsupportedImage }
    return response.data
  }
}

private struct GalaxySSIRemoteAnimatedImageView: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> UIImageView {
    let imageView = GalaxySSIRichAnimatedImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.clipsToBounds = true
    imageView.accessibilityTraits = .image
    return imageView
  }

  func updateUIView(_ imageView: UIImageView, context: Context) {
    GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.deactivate(imageView)
    imageView.animationImages = nil

    if let frames = GalaxySSIImageResourceDecoder.frames(from: data) {
      imageView.animationImages = frames.images
      imageView.animationDuration = frames.duration
      imageView.animationRepeatCount = 0
      imageView.image = frames.images.first
      if imageView.window != nil {
        GalaxySSIRichAnimatedImagePlaybackCoordinator.shared.activate(imageView)
      }
    } else {
      imageView.image = GalaxySSIImageResourceDecoder.staticImage(from: data)
    }
  }
}
