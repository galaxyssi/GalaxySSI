import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasEnlargedFrame: Identifiable {
  let id: String
  let phase: Double
}

@MainActor
struct GalaxySSIHealthAtlasFunctionEnlargement<Artwork: View>: View {
  let title: String
  let language: String
  let artwork: Artwork
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    NavigationView {
      GalaxySSIAtlasDrawingZoom(content: AnyView(artwork.frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.galaxySSIInterfaceLanguage, language).environment(\.colorScheme, scheme)
        .accessibilityIdentifier("atlas-function-enlarged-art")))
        .accessibilityIdentifier("atlas-function-enlarged-viewport")
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
              .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))
          }
        }
    }.navigationViewStyle(.stack).galaxySSIHealthTheme()
  }
}

private struct GalaxySSIAtlasDrawingZoom: UIViewControllerRepresentable {
  let content: AnyView
  func makeUIViewController(context: Context) -> Controller { Controller(content: content) }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.host.rootView = content
  }
  static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.scroll.delegate = nil }
  final class Controller: UIViewController, UIScrollViewDelegate {
    let scroll = UIScrollView()
    let host: UIHostingController<AnyView>
    private var size = CGSize.zero
    private var layingOut = false
    init(content: AnyView) { host = UIHostingController(rootView: content); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .systemBackground
      scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4; scroll.delegate = self
      scroll.contentInsetAdjustmentBehavior = .never
      view.addSubview(scroll)
      addChild(host); scroll.addSubview(host.view); host.didMove(toParent: self)
      host.view.backgroundColor = .clear; host.view.isOpaque = false
    }
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      guard !layingOut, view.bounds.width > 0, view.bounds.height > 0 else { return }
      layingOut = true
      defer { layingOut = false }
      scroll.frame = view.bounds
      let next = scroll.bounds.size
      if size != next {
        scroll.setZoomScale(1, animated: false)
        size = next; host.view.frame = CGRect(origin: .zero, size: next)
        scroll.contentSize = next; scroll.setContentOffset(.zero, animated: false)
      }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
  }
}
