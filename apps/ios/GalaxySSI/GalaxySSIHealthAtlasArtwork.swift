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
  @State private var fullscreenLayers = true
  @State private var fullscreenZoom: Double = 1
  @State private var fullscreenReset = 0
  @State private var selected: String?
  @State private var selectedFeature: GalaxySSIHealthAtlas.Feature?
  private var plate: GalaxySSIHealthAtlas.Plate? {
    atlas.plate(for: entry?.id, viewKey: entry.map { state.binding($0).wrappedValue.artworkView } ?? nil)
  }
  private var artworkView: Binding<String> {
    Binding(get: { plate?.viewKey ?? "" }, set: { key in
      guard let entry, atlas.views(for: entry.id).contains(where: { $0.viewKey == key }) else { return }
      state.binding(entry).wrappedValue.artworkView = key
      zoom = 1
    })
  }
  @ViewBuilder private var viewPicker: some View {
    let views = atlas.views(for: entry?.id)
    if views.count > 1 {
      Picker(t("illustration"), selection: artworkView) {
        ForEach(Array(views.enumerated()), id: \.element.id) { index, view in
          Text(view.selectorLabel.map { GalaxySSIHealthAtlasText.get($0, language) } ??
            t(index == 0 ? "view_front" : "view_back")).tag(view.viewKey ?? "")
        }
      }.pickerStyle(.segmented).accessibilityIdentifier("atlas-artwork-view")
    }
  }
  private var art: String? { plate?.asset }
  private var spots: [(String, Double, Double)] {
    let markers = plate?.markers.map { ($0.id, $0.x, $0.y) } ?? []
    let features = plate?.annotations.map { ($0.id, $0.marker.x, $0.marker.y) } ?? []
    return features.isEmpty ? markers : (markers + features).sorted { $0.2 < $1.2 }
  }
  private var featureIDs: Set<String> { Set(plate?.annotations.map(\.id) ?? []) }
  private var labels: [String] {
    spots.map { spot in
      if let feature = plate?.annotations.first(where: { $0.id == spot.0 }) {
        return GalaxySSIHealthAtlasText.get(feature.title, language)
      }
      return atlas.entry(spot.0).map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? spot.0
    }
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
    return atlas.caption(plate, selected: entry, language: language)
  }
  private var fullscreenCaption: String {
    let name = entry.map { GalaxySSIHealthAtlasText.get($0.name, language) } ?? t("whole")
    return name + " \u{00b7} " + caption
  }
  var body: some View {
    if let art, entry.map({ state.binding($0).wrappedValue.tab != .simulation || !GalaxySSIHealthAtlasGasExchange.supports($0.id) }) ?? true {
      VStack(alignment: .leading, spacing: 8) {
        viewPicker
        canvas(art)
        HStack {
          Menu {
            Toggle(t("layers"), isOn: $layers)
            ForEach(choices) { target in
              Button(GalaxySSIHealthAtlasText.get(target.name, language)) { selected = target.id }
                .disabled(depth >= 32)
            }
            ForEach(plate?.annotations ?? []) { feature in
              Button(GalaxySSIHealthAtlasText.get(feature.title, language)) { selectedFeature = feature }
            }
          } label: { Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44) }
            .accessibilityLabel(t("layers")).help(t("layers"))
          Spacer()
          Button { zoom = 1 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
            .accessibilityLabel(t("reset")).help(t("reset"))
          Button {
            fullscreenLayers = true; fullscreenZoom = 1; fullscreenReset += 1; fullscreen = true
          } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
            .accessibilityLabel(bodyText("zoom")).help(bodyText("zoom"))
        }
        Slider(value: $zoom, in: 1...4).accessibilityLabel(bodyText("zoom"))
        Text(caption).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(t("illustration")).font(.caption).foregroundColor(.secondary)
      }
      .fullScreenCover(isPresented: $fullscreen) {
        NavigationView {
          VStack(alignment: .leading, spacing: 8) {
            Text(fullscreenCaption).font(.subheadline).fixedSize(horizontal: false, vertical: true).padding(.horizontal)
            ScrollView {
              canvas(art, full: true).padding(.horizontal)
                .accessibilityIdentifier("atlas-fullscreen-image")
            }.id(fullscreenReset).accessibilityIdentifier("atlas-fullscreen-viewport")
            HStack {
              Spacer()
              if plate?.hasLabels == true {
                Button { fullscreenLayers.toggle() } label: {
                  Image(systemName: fullscreenLayers ? "eye" : "eye.slash")
                    .frame(width: 44, height: 44)
                }.accessibilityLabel(t(fullscreenLayers ? "hide_labels" : "show_labels"))
                  .help(t(fullscreenLayers ? "hide_labels" : "show_labels"))
                  .accessibilityIdentifier("atlas-fullscreen-labels")
              }
              Button { fullscreenZoom = 1; fullscreenReset += 1 } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
              }.accessibilityLabel(t("reset")).help(t("reset"))
                .accessibilityIdentifier("atlas-fullscreen-reset")
            }.padding(.horizontal)
          }
            .navigationTitle(bodyText("title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
              Button { fullscreen = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))
            } }
        }.navigationViewStyle(.stack)
          .alert(item: featureSelection(inSheet: true), content: featureAlert)
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
      .alert(item: featureSelection(inSheet: false), content: featureAlert)
      .onChange(of: fullscreen) { _ in selectedFeature = nil }
      .onChange(of: art) { _ in selectedFeature = nil }
      .onDisappear { selectedFeature = nil }
    }
  }
  private func canvas(_ art: String, full: Bool = false) -> some View {
    let shown = full ? fullscreenLayers : layers
    let scale = full ? $fullscreenZoom : $zoom
    if shown, !spots.isEmpty {
      return AnyView(GalaxySSIHealthAtlasLabeledArtwork(asset: art, aspectRatio: plate?.aspectRatio ?? 1, zoom: scale,
        currentID: entry?.id, spots: spots, labels: labels, featureIDs: featureIDs, splitCallouts: plate?.splitCallouts ?? false, onSelect: choose))
    }
    return AnyView(GalaxySSIHealthAtlasZoomCanvas(asset: art, zoom: scale, currentID: entry?.id, spots: shown ? spots : [],
      labels: labels, onSelect: choose)
      .aspectRatio(plate?.aspectRatio ?? 1, contentMode: .fit))
  }
  private func choose(_ id: String) {
    switch plate?.labelTarget(id, in: atlas) {
    case .feature(let feature): selectedFeature = feature
    case .anatomy(let target):
      guard depth < 32, target != entry?.id else { return }
      selected = target; fullscreen = false
    case nil: break
    }
  }
  private func featureSelection(inSheet: Bool) -> Binding<GalaxySSIHealthAtlas.Feature?> {
    Binding(get: { fullscreen == inSheet ? selectedFeature : nil }, set: { selectedFeature = $0 })
  }
  private func featureAlert(_ feature: GalaxySSIHealthAtlas.Feature) -> Alert {
    Alert(title: Text(GalaxySSIHealthAtlasText.get(feature.title, language)),
      message: Text(GalaxySSIHealthAtlasText.get(feature.explanation, language)),
      dismissButton: .default(Text(GalaxySSILocalization.string("galaxyssi.close", fallback: "Close", language: language))))
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
    override func touchesShouldCancel(in view: UIView) -> Bool {
      view is UIButton || super.touchesShouldCancel(in: view)
    }
  }
}
