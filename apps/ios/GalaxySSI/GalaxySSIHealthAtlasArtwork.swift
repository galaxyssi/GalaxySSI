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
  private var plate: GalaxySSIHealthAtlas.Plate? { atlas.plate(for: entry?.id) }
  private var art: String? { plate?.asset }
  private var spots: [(String, Double, Double)] {
    plate?.markers.map { ($0.id, $0.x, $0.y) } ?? []
  }
  private var choices: [GalaxySSIHealthAtlas.Entry] {
    let candidates = entry.map { atlas.children($0) + atlas.cells($0) + spots.compactMap { atlas.entry($0.0) } }
      ?? atlas.entries.filter { $0.kind == .system }
    return candidates.reduce(into: []) { result, candidate in
      if candidate.id != entry?.id, !result.contains(where: { $0.id == candidate.id }) { result.append(candidate) }
    }
  }
  private var caption: String {
    guard let plate else { return t("illustration") }
    let view = GalaxySSIHealthAtlasText.get(plate.viewLabel, language)
    guard let owner = plate.owner, owner != entry?.id, let structure = atlas.entry(owner) else { return view }
    let name = GalaxySSIHealthAtlasText.get(structure.name, language)
    return plate.viewLabel == "health_atlas_illustration" ? String(format: t("related_process"), name) :
      String(format: t("plate_context"), name, view)
  }
  var body: some View {
    if let art {
      VStack(alignment: .leading, spacing: 8) {
        canvas(art)
        HStack {
          Menu {
            Toggle(t("layers"), isOn: $layers)
            ForEach(choices) { target in
              Button(GalaxySSIHealthAtlasText.get(target.name, language)) { selected = target.id }
                .disabled(depth >= 32)
            }
          } label: { Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44) }
            .accessibilityLabel(t("layers")).help(t("layers"))
          Spacer()
          Button { zoom = 1 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
            .accessibilityLabel(t("reset")).help(t("reset"))
          Button { fullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
            .accessibilityLabel(bodyText("zoom")).help(bodyText("zoom"))
        }
        Slider(value: $zoom, in: 1...4).accessibilityLabel(bodyText("zoom"))
        Text(caption).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(t("illustration")).font(.caption).foregroundColor(.secondary)
      }
      .sheet(isPresented: $fullscreen) {
        NavigationView {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              canvas(art)
              Text(caption).font(.subheadline).fixedSize(horizontal: false, vertical: true)
              Text(t("illustration")).font(.caption).foregroundColor(.secondary)
            }.padding()
          }
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
    if layers, !spots.isEmpty {
      return AnyView(GalaxySSIHealthAtlasLabeledArtwork(asset: art, aspectRatio: plate?.aspectRatio ?? 1, zoom: $zoom,
        currentID: entry?.id, spots: spots, labels: spots.map {
          atlas.entry($0.0).map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? $0.0
        }, onSelect: { if depth < 32, $0 != entry?.id { selected = $0; fullscreen = false } }))
    }
    return AnyView(GalaxySSIHealthAtlasZoomCanvas(asset: art, zoom: $zoom, currentID: entry?.id, spots: layers ? spots : [], labels: spots.map {
      atlas.entry($0.0).map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? $0.0
    }, onSelect: { if depth < 32, $0 != entry?.id { selected = $0; fullscreen = false } })
      .aspectRatio(plate?.aspectRatio ?? 1, contentMode: .fit))
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  private func bodyText(_ key: String) -> String { GalaxySSIHealthBodyText.string(key, language: language) }
}

/// UIScrollView keeps image, markers, and pan bounds in the same zoom coordinate space.
private struct GalaxySSIHealthAtlasZoomCanvas: UIViewRepresentable {
  let asset: String
  @Binding var zoom: Double
  let currentID: String?
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
      button.isSelected = spot.0 == currentID
      button.isEnabled = !button.isSelected
      if button.isSelected { button.accessibilityTraits.insert(.isSelected) }
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
