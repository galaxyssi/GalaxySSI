import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasResearch: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @ObservedObject var state: GalaxySSIHealthAtlasState
  let records: GalaxySSIHealthRecords
  let depth: Int
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  private var selection: Binding<GalaxySSIHealthAtlasState.Selection> { state.binding(entry) }
  private var drugState: Binding<GalaxySSIHealthAtlasDrugState> {
    Binding(get: { GalaxySSIHealthAtlasDrugState.restore(selection.wrappedValue.drugInputs) ?? .init() },
      set: { selection.wrappedValue.drugInputs = $0.encoded })
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Picker(t("research"), selection: selection.research) {
          ForEach(GalaxySSIHealthAtlasState.Research.allCases, id: \.self) { Text(t($0.rawValue)).tag($0) }
        }.pickerStyle(.segmented)
        switch selection.wrappedValue.research {
        case .physiology:
          GalaxySSIHealthAtlasSimulationPanel(atlas: atlas, entry: entry, model: atlas.model(entry), simulation: selection.simulation,
            physiologyInputs: selection.physiologyInputs, previewPresented: $state.previewPresented,
            destination: { id in
              if let target = atlas.entry(id), depth < 32 {
                return AnyView(GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1))
              }
              return AnyView(EmptyView())
            }, mechanismFirst: true)
        case .drugs:
          drugs
        case .aging:
          aging
        }
        Link(t(atlas.model(entry).reference == nil ? "structure_source" : "reference_pubmed"), destination: atlas.model(entry).source)
      }.padding()
    }
    .navigationTitle(t("research")).navigationBarTitleDisplayMode(.inline).galaxySSIHealthTheme()
    .environmentObject(state.playback)
    .safeAreaInset(edge: .bottom) {
      GalaxySSIHealthAtlasAsk(atlas: atlas, entry: entry, selection: selection.wrappedValue, includesResearch: true,
        selectionSnapshot: { selection.wrappedValue }, onPreviewStateChange: {
          if $0 { state.playback.pause() }
          state.previewPresented = $0
        })
        .padding(.horizontal)
    }
  }
  private var drugs: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(t("adme_title")).font(.headline)
      Text(t("drug_note")); Text(t("adme_scope")).font(.footnote).foregroundColor(.secondary)
      ForEach(["absorption", "distribution", "metabolism", "excretion"], id: \.self) { stage in
        VStack(alignment: .leading, spacing: 6) {
          Text(t(stage)).font(.headline); Text(t(stage + "_note"))
          if let target = atlas.entry(admeEntry(stage)), depth < 32 {
            NavigationLink(destination: GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1)) {
              GalaxySSIHealthAtlasRow(entry: target)
            }
          }
        }
      }
      Divider()
      Text(t("drug_models")).font(.headline)
      GalaxySSIHealthAtlasModelTabs(options: [t("drug_single"), t("drug_two"), t("compare_title")], selected: Binding(
        get: { drugState.wrappedValue.mode.rawValue }, set: { value in
          if let mode = GalaxySSIHealthAtlasDrugState.Mode(rawValue: value) { drugState.wrappedValue.mode = mode }
        }), identifier: "atlas-drug-model")
      if drugState.wrappedValue.mode == .comparison {
        GalaxySSIHealthAtlasComparisonPanel(model: drugState.comparison, showTotals: drugState.showComparisonTotals, language: language)
      } else if drugState.wrappedValue.mode == .two {
        GalaxySSIHealthAtlasDistributionPanel(model: drugState.distribution, language: language)
      } else {
      Text(t("elimination_assumptions")).font(.footnote)
      hours("half_life", value: selection.elimination.halfLife, range: 1...24)
      hours("elapsed", value: selection.elimination.elapsed, range: 0...48)
      curve
      Text(String(format: t("elimination_summary"), Int64(selection.wrappedValue.elimination.halfLife),
        Int64(selection.wrappedValue.elimination.elapsed), String(format: "%.1f", selection.wrappedValue.elimination.percent(at: selection.wrappedValue.elimination.elapsed))))
      Text(t("elimination_formula")).font(.footnote)
      Button { selection.wrappedValue.elimination = .init() } label: {
        Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
      }.accessibilityLabel(t("reset")).help(t("reset"))
      }
      Link(t("pharmacology_source"), destination: URL(string: "https://openstax.org/books/pharmacology/pages/2-2-pharmacokinetics-and-pharmacodynamics")!)
      Link(t("kinetics_source"), destination: URL(string: "https://pharmacologyeducation.org/clinical-pharmacokinetics/")!)
    }
  }
  private var aging: some View {
    GalaxySSIHealthAtlasAgingPanel(atlas: atlas, entry: entry, saved: selection.aging, language: language,
      destination: { id in
        if let target = atlas.entry(id), depth < 32 {
          return AnyView(GalaxySSIHealthAtlasDetail(atlas: atlas, entry: target, state: state, records: records, depth: depth + 1))
        }
        return AnyView(EmptyView())
      })
  }
  private var curve: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("100%")
      GeometryReader { proxy in
        Path { path in
          for tick in 0...192 {
            let hours = Double(tick) / 4
            let point = CGPoint(x: proxy.size.width * hours / 48,
              y: proxy.size.height * (1 - selection.wrappedValue.elimination.percent(at: hours) / 100))
            if tick == 0 { path.move(to: point) } else { path.addLine(to: point) }
          }
        }.stroke(Color.accentColor, lineWidth: 2)
      }.frame(height: 160).accessibilityHidden(true)
      HStack { Text("0% · 0 h"); Spacer(); Text("48 h") }.font(.caption)
      Text(t("hours_axis")).font(.caption)
    }.padding(8).overlay(Rectangle().stroke(Color.secondary.opacity(0.3)))
  }
  private func hours(_ key: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading) {
      Text(String(format: t("hours_value"), t(key), Int64(value.wrappedValue)))
      Slider(value: value, in: range, step: 1).accessibilityLabel(t(key))
    }
  }
  private func admeEntry(_ stage: String) -> String {
    ["absorption": "small-intestine", "distribution": "blood-vessels", "metabolism": "liver", "excretion": "kidneys"][stage]!
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}
