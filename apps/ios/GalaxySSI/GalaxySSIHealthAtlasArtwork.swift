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
  @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = 14
  @ScaledMetric(relativeTo: .subheadline) private var explanationSize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11
  @State private var subjectPoint: CGPoint?
  @State private var fullscreenSubject: CGPoint?
  @State private var sideNote = false
  @State private var fullscreenSide = false
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
    let candidates = entry == nil ? atlas.entries.filter { $0.kind == .system } :
      (plate?.markers.compactMap { atlas.entry($0.id) } ?? [])
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
  private func focus(side: Bool) -> CGPoint {
    if let marker = plate?.markers.first(where: { $0.id == entry?.id }) { return .init(x: marker.x, y: marker.y) }
    if plate?.owner == "cell-pancreatic-beta-cell" { return .init(x: 0.82, y: 0.44) }
    return .init(x: side ? 0.36 : 0.54, y: side ? 0.48 : 0.22)
  }
  private var overlayNote: Bool {
    plate?.hasLabels == true && entry != nil && plate?.splitCallouts != true &&
      (plate?.annotations.isEmpty ?? true) && (plate?.markers.count ?? 0) <= 3
  }
  var body: some View {
    Group {
      if let art {
        VStack(alignment: .leading, spacing: 8) {
          viewPicker
          GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-structure-figure", overlayNote: overlayNote,
            preferSideNote: plate?.hasLabels != true, subjectPoint: subjectPoint, onSideChanged: { sideNote = $0 },
            header: { controls }, artwork: {
            canvas(art)
          }, legend: { legend(title: entry == nil ? fullscreenCaption : caption, explanation: entry?.description, note: "illustration") })
        }
      } else if let entry {
        GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-concept-figure", preferSideNote: true,
          subjectAspectRatio: 1, header: { EmptyView() }, artwork: {
          Image(systemName: conceptSymbol).font(.system(size: 64)).foregroundColor(GalaxySSIHealthTheme.accent)
            .atlasAnnotationSubject("atlas-concept-figure")
            .frame(maxWidth: .infinity).frame(height: 132).accessibilityHidden(true)
        }, legend: { legend(title: GalaxySSIHealthAtlasText.get(entry.name, language),
          explanation: entry.description, note: "symbol_only") })
      }
    }
      .fullScreenCover(isPresented: $fullscreen) {
        NavigationView {
          VStack(alignment: .leading, spacing: 8) {
            GeometryReader { viewport in
            ScrollView {
              if let art {
                GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-fullscreen-figure", maximumHeight: viewport.size.height,
                  subjectPoint: fullscreenSubject, onSideChanged: { fullscreenSide = $0 }, header: { EmptyView() }, artwork: {
                  canvas(art, full: true).accessibilityIdentifier("atlas-fullscreen-image")
                }, legend: { legend(title: fullscreenCaption, explanation: nil, note: "illustration") })
              }
            }.id(fullscreenReset).accessibilityIdentifier("atlas-fullscreen-viewport")
            }
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
      .onChange(of: art) { _ in selectedFeature = nil; subjectPoint = nil; fullscreenSubject = nil }
      .onChange(of: selected) { id in
        if entry == nil, let id { state.rememberWholeSelection(id, in: atlas) }
      }
      .onDisappear { selectedFeature = nil }
  }
  private var controls: some View {
    HStack {
      if !choices.isEmpty || !(plate?.annotations.isEmpty ?? true) {
        Menu {
          Toggle(t("layers"), isOn: $layers)
          ForEach(choices) { target in
            Button(GalaxySSIHealthAtlasText.get(target.name, language)) { selected = target.id }.disabled(depth >= 32)
          }
          ForEach(plate?.annotations ?? []) { feature in
            Button(GalaxySSIHealthAtlasText.get(feature.title, language)) { selectedFeature = feature }
          }
        } label: { Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44) }
          .accessibilityLabel(t("layers")).help(t("layers"))
      }
      Spacer()
      if let source = plate?.source {
        Link(destination: source) { Image(systemName: "doc.text").frame(width: 44, height: 44) }
          .accessibilityLabel(t("plate_source")).help(t("plate_source")).accessibilityIdentifier("atlas-source-structure")
      }
      Button { zoom = 1 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
        .accessibilityLabel(t("reset")).help(t("reset"))
      Button {
        fullscreenLayers = true; fullscreenZoom = 1; fullscreenReset += 1; fullscreen = true
      } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
        .accessibilityLabel(bodyText("zoom")).help(bodyText("zoom"))
    }.padding(.horizontal, 8)
  }
  private var conceptSymbol: String {
    switch entry?.icon {
    case "brain": return "brain.head.profile"
    case "eye": return "eye"
    case "heart-pulse": return "heart"
    case "wind": return "wind"
    case "bone": return "figure.walk"
    case "shield-plus": return "cross.case"
    case "microscope": return "circle.hexagongrid"
    default: return entry?.kind == .cell || entry?.kind == .fragment ? "circle.hexagongrid" : "square.stack.3d.up"
    }
  }
  private func legend(title: String, explanation: String?, note: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.system(size: titleSize, weight: .bold)).foregroundColor(GalaxySSIHealthTheme.accent)
        .accessibilityIdentifier("atlas-art-caption")
      if let explanation {
        Text(GalaxySSIHealthAtlasText.get(explanation, language)).font(.system(size: explanationSize)).padding(.top, 3)
          .accessibilityIdentifier("atlas-art-explanation")
      }
      Text(t(note)).font(.system(size: noteSize)).foregroundColor(.secondary).padding(.top, 5)
    }.fixedSize(horizontal: false, vertical: true)
  }
  private func canvas(_ art: String, full: Bool = false) -> some View {
    let shown = full ? fullscreenLayers : layers
    let scale = full ? $fullscreenZoom : $zoom
    if shown, !spots.isEmpty {
      return AnyView(GalaxySSIHealthAtlasLabeledArtwork(asset: art, aspectRatio: plate?.aspectRatio ?? 1, zoom: scale,
        currentID: entry?.id, spots: spots, labels: labels, featureIDs: featureIDs, splitCallouts: plate?.splitCallouts ?? false,
        minimumHeight: entry == nil ? 366 : 266, subjectFocus: focus(side: full ? fullscreenSide : sideNote),
        onSubject: { if full { fullscreenSubject = $0 } else { subjectPoint = $0 } }, onSelect: choose)
        .anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) {
          [(full ? "atlas-fullscreen-figure" : "atlas-structure-figure") + ".viewport": $0]
        })
    }
    return AnyView(GalaxySSIHealthAtlasZoomCanvas(asset: art, zoom: scale, currentID: entry?.id, spots: shown ? spots : [],
      labels: labels, onSelect: choose, subjectFocus: focus(side: full ? fullscreenSide : sideNote),
      onSubject: { if full { fullscreenSubject = $0 } else { subjectPoint = $0 } })
      .anchorPreference(key: GalaxySSIHealthAtlasFigureAnchors.self, value: .bounds) {
        [(full ? "atlas-fullscreen-figure" : "atlas-structure-figure") + ".viewport": $0]
      }
      .aspectRatio(plate?.aspectRatio ?? 1, contentMode: .fit)
      .frame(minHeight: entry == nil ? 366 : 266))
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
  let subjectFocus: CGPoint
  let onSubject: (CGPoint) -> Void

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
    private let notePosition = GalaxySSIHealthAtlasNotePosition()
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
      reportSubject(scroll)
    }
    private func reportSubject(_ scroll: UIScrollView) {
      let local = content.convert(CGPoint(x: content.bounds.width * parent.subjectFocus.x,
        y: content.bounds.height * parent.subjectFocus.y), to: scroll)
      notePosition.report(CGPoint(x: local.x - scroll.bounds.minX, y: local.y - scroll.bounds.minY), identity: parent.asset) { [weak self] in
        self?.parent.onSubject($0)
      }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { reportSubject(scrollView) }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { reportSubject(scrollView) }
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
