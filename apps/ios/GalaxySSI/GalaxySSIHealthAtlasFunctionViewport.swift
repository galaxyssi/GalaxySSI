import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasFunctionViewport: ViewModifier {
  let storyID: String
  @State private var windowHeight: CGFloat = 0
  static let cellCourses: Set<String> = [
    "NEUTROPHIL_DEFENSE", "EOSINOPHIL_RESPONSE", "BASOPHIL_SIGNALING", "MONOCYTE_RECRUITMENT",
    "DENDRITIC_PRESENTATION", "T_CELL_RESPONSE", "NK_SURVEILLANCE", "PLATELET_FORMATION", "MACROPHAGE_CLEARANCE"
  ]
  nonisolated static func limit(windowHeight: CGFloat, cellCourse: Bool) -> CGFloat {
    if cellCourse { return 390 }
    guard windowHeight.isFinite, windowHeight > 0 else { return 336 }
    return min(336, max(144, windowHeight - 410))
  }
  func body(content: Content) -> some View {
    content.frame(maxHeight: Self.limit(windowHeight: windowHeight, cellCourse: Self.cellCourses.contains(storyID)))
      .background(GalaxySSIHealthAtlasFunctionWindowHeight { height in
        if height != windowHeight { windowHeight = height }
      }.accessibilityHidden(true))
  }
}

private struct GalaxySSIHealthAtlasFunctionWindowHeight: UIViewControllerRepresentable {
  let changed: (CGFloat) -> Void
  func makeUIViewController(context: Context) -> Controller { Controller() }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.changed = changed
    controller.report()
  }
  final class Controller: UIViewController {
    var changed: ((CGFloat) -> Void)?
    private var reported: CGFloat = 0
    override func loadView() {
      view = UIView()
      view.backgroundColor = .clear
      view.isUserInteractionEnabled = false
      view.isAccessibilityElement = false
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); report() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); report() }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); report() }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
      super.viewWillTransition(to: size, with: coordinator)
      coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.report() }
    }
    func report() {
      guard let height = viewIfLoaded?.window?.bounds.height, height.isFinite, height > 0, height != reported else { return }
      reported = height
      // Layout callbacks must not synchronously mutate SwiftUI state.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.viewIfLoaded?.window?.bounds.height == height else { return }
        self.changed?(height)
      }
    }
  }
}
