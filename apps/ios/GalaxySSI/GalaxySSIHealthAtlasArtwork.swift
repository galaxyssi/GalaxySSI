import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthAtlasArtwork: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry?
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var layers = true
  @State private var zoom: Double = 1
  @State private var fullscreen = false
  @State private var selected: String?
  private var art: String? {
    guard let id = entry?.id else { return "HealthAtlasBody" }
    if ["heart", "cardio", "atria", "ventricles", "heart-valves", "coronary-vessels"].contains(id) { return "HealthAtlasHeart" }
    return id == "cell-pancreatic-beta-cell" ? "HealthAtlasBetaCell" : nil
  }
  private var spots: [(String, Double, Double)] {
    if entry == nil { return [("brain", 0.50, 0.045), ("heart", 0.54, 0.28), ("liver", 0.45, 0.34), ("small-intestine", 0.51, 0.44)] }
    return art == "HealthAtlasHeart" ? [("atria", 0.28, 0.46), ("coronary-vessels", 0.57, 0.68), ("ventricles", 0.61, 0.84)] : []
  }
  var body: some View {
    if let art {
      VStack(alignment: .leading, spacing: 8) {
        canvas(art)
        HStack {
          Toggle(t("layers"), isOn: $layers)
          Spacer()
          Button { zoom = 1 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
            .accessibilityLabel(t("reset")).help(t("reset"))
          Button { fullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
            .accessibilityLabel(bodyText("zoom")).help(bodyText("zoom"))
        }
        Slider(value: $zoom, in: 1...4).accessibilityLabel(bodyText("zoom"))
        if layers {
          ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in
            if let target = atlas.entry(spot.0) {
              Button { selected = target.id } label: {
                HStack { Text("\(index + 1)").monospacedDigit(); Text(GalaxySSIHealthAtlasText.get(target.name, language)); Spacer(); Image(systemName: "chevron.right") }
                  .frame(minHeight: 44)
              }.disabled(depth >= 32)
            }
          }
        }
        Text(t("illustration")).font(.caption).foregroundColor(.secondary)
        if entry != nil, art == "HealthAtlasHeart", entry?.id != "heart" {
          Text(String(format: t("related_process"), GalaxySSIHealthAtlasText.get(atlas.entry("heart")!.name, language)))
            .font(.caption).foregroundColor(.secondary)
        }
      }
      .sheet(isPresented: $fullscreen) {
        NavigationView {
          ScrollView { canvas(art).padding() }
            .navigationTitle(t("illustration")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
              Button { fullscreen = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))
            } }
        }.navigationViewStyle(.stack)
      }
      .background(NavigationLink(isActive: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
        if let selected, let target = atlas.entry(selected) {
          GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1)
        }
      } label: { EmptyView() }.hidden())
      .onAppear {
        if let entry { let value = state.binding(entry).wrappedValue; layers = value.layers; zoom = value.zoom }
      }
      .onChange(of: layers) { value in if let entry { state.binding(entry).wrappedValue.layers = value } }
      .onChange(of: zoom) { value in if let entry { state.binding(entry).wrappedValue.zoom = value } }
    }
  }
  private func canvas(_ art: String) -> some View {
    GalaxySSIHealthAtlasZoomCanvas(asset: art, zoom: $zoom, spots: layers ? spots : [], labels: spots.map {
      atlas.entry($0.0).map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? $0.0
    }, onSelect: { if depth < 32 { selected = $0; fullscreen = false } })
      .aspectRatio(art == "HealthAtlasBody" ? 2.0 / 3.0 : art == "HealthAtlasHeart" ? 3.0 / 4.0 : 1, contentMode: .fit)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  private func bodyText(_ key: String) -> String { GalaxySSIHealthBodyText.string(key, language: language) }
}

/// UIScrollView keeps image, markers, and pan bounds in the same zoom coordinate space.
private struct GalaxySSIHealthAtlasZoomCanvas: UIViewRepresentable {
  let asset: String
  @Binding var zoom: Double
  let spots: [(String, Double, Double)]
  let labels: [String]
  let onSelect: (String) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UIScrollView {
    let scroll = LayoutScrollView()
    scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
    scroll.delegate = context.coordinator
    scroll.clipsToBounds = true
    scroll.addSubview(context.coordinator.content)
    let coordinator = context.coordinator
    scroll.onLayout = { [weak coordinator] scroll in coordinator?.layout(scroll) }
    return scroll
  }
  func updateUIView(_ scroll: UIScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    coordinator.content.image = UIImage(named: asset)
    coordinator.content.isUserInteractionEnabled = true
    coordinator.content.contentMode = .scaleToFill
    coordinator.content.accessibilityLabel = GalaxySSIHealthAtlasText.get("health_atlas_illustration", Locale.current.identifier)
    coordinator.content.subviews.forEach { $0.removeFromSuperview() }
    for (index, spot) in spots.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle("\(index + 1)", for: .normal)
      button.setTitleColor(.label, for: .normal)
      button.backgroundColor = .systemBackground
      button.layer.cornerRadius = 22
      button.accessibilityLabel = labels.indices.contains(index) ? labels[index] : spot.0
      button.addAction(UIAction { _ in onSelect(spot.0) }, for: .touchUpInside)
      coordinator.content.addSubview(button)
    }
    coordinator.layout(scroll)
    scroll.setNeedsLayout()
  }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    var parent: GalaxySSIHealthAtlasZoomCanvas
    let content = UIImageView()
    var size = CGSize.zero
    private var layingOut = false
    init(_ parent: GalaxySSIHealthAtlasZoomCanvas) { self.parent = parent }
    func layout(_ scroll: UIScrollView) {
      guard !layingOut, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
      layingOut = true
      defer { layingOut = false }
      let nextSize = scroll.bounds.size
      if size != nextSize {
        scroll.setZoomScale(1, animated: false)
        size = nextSize
        content.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
      }
      for (index, view) in content.subviews.enumerated() where parent.spots.indices.contains(index) {
        let spot = parent.spots[index]
        view.frame = CGRect(x: max(0, min(size.width - 44, size.width * CGFloat(spot.1) - 22)),
          y: max(0, min(size.height - 44, size.height * CGFloat(spot.2) - 22)), width: 44, height: 44)
      }
      if !scroll.isZooming, abs(Double(scroll.zoomScale) - parent.zoom) > 0.01 {
        scroll.setZoomScale(CGFloat(parent.zoom), animated: false)
      }
      if parent.zoom == 1 { scroll.setContentOffset(.zero, animated: false) }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
      parent.zoom = Double(scale)
    }
  }
  private final class LayoutScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(self) }
  }
}
