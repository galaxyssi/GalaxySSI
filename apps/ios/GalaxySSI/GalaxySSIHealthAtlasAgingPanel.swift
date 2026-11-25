import SwiftUI

struct GalaxySSIHealthAtlasAgingPanel: View {
  let atlas: GalaxySSIHealthAtlas
  let entry: GalaxySSIHealthAtlas.Entry
  @Binding var saved: GalaxySSIHealthAtlasAgingSelection?
  let language: String
  let destination: (String) -> AnyView
  @ScaledMetric(relativeTo: .footnote) private var explanationSize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11
  private var selection: GalaxySSIHealthAtlasAgingSelection { .resolved(saved, entryID: entry.id) }
  private var topic: Binding<GalaxySSIHealthAtlasAgingTopic> {
    Binding(get: { selection.topic }, set: { if $0 != selection.topic { saved = .init(topic: $0) } })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(GalaxySSIHealthAtlasText.get(entry.name, language)).font(.headline)
      Text(t("scope")).font(.footnote).foregroundColor(.secondary)
      Picker(t("picker"), selection: topic) {
        ForEach(GalaxySSIHealthAtlasAgingTopic.allCases, id: \.self) { value in
          Text(t("topic_" + value.rawValue)).tag(value)
        }
      }.pickerStyle(.menu).accessibilityIdentifier("atlas-aging-picker")
      // The diagram is a conceptual sequence, not an animation of measured time.
      GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-aging-figure", header: { EmptyView() }, artwork: {
      VStack(spacing: 0) {
        ForEach(0..<4) { index in
          if index > 0 { Image(systemName: "arrow.down").foregroundColor(.secondary).accessibilityHidden(true) }
          Button { saved = .init(topic: selection.topic, step: index) } label: {
            HStack(alignment: .top, spacing: 12) {
              Text(String(index + 1)).bold().frame(width: 28)
              Text(selection.stages(language: language)[index]).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
              Image(systemName: selection.step == index ? "checkmark.circle.fill" : "circle")
            }.padding(10).frame(maxWidth: .infinity, minHeight: 44)
              .background(selection.step == index ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
              .cornerRadius(8)
          }.buttonStyle(.plain)
            .accessibilityAddTraits(selection.step == index ? .isSelected : [])
            .accessibilityIdentifier("atlas-aging-step-" + String(index))
        }
      }
      }, legend: {
        VStack(alignment: .leading, spacing: 4) {
          GalaxySSIHealthAtlasReservedCaption(values: (0..<4).map {
            GalaxySSIHealthAtlasAgingSelection(topic: selection.topic, step: $0).stageLabel(language: language)
          }, selected: selection.step, identifier: "atlas-aging-stage").font(.subheadline.bold())
          Text(selection.explanation(language: language)).font(.system(size: explanationSize))
            .fixedSize(horizontal: false, vertical: true)
          Text(t("diagram_scope")).font(.system(size: noteSize)).foregroundColor(.secondary).padding(.top, 1)
        }
      })
      if let study = selection.topic.study {
        VStack(alignment: .leading, spacing: 8) {
          Text(t("human_study")).font(.headline)
          Text(study.text("sample", language: language)).bold()
          Text(study.text("result", language: language))
          Text(study.text("limits", language: language)).font(.footnote).foregroundColor(.secondary)
          Link(study.text("study", language: language), destination: study.source).frame(minHeight: 44)
        }.fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-aging-study")
      }
      Text(t("evidence")).font(.footnote).foregroundColor(.secondary)
      if selection.topic.exampleID != entry.id, let target = atlas.entry(selection.topic.exampleID) {
        NavigationLink(destination: destination(target.id)) {
          VStack(alignment: .leading, spacing: 4) {
            Text(GalaxySSIHealthAtlasText.get(target.name, language))
            Text(t("related")).font(.caption).foregroundColor(.secondary)
          }.frame(minHeight: 44)
        }.accessibilityIdentifier("atlas-aging-related")
      }
      Link(t("source"), destination: GalaxySSIHealthAtlasAgingTopic.source).frame(minHeight: 44)
    }
    .onAppear { saved = selection }
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasAgingSelection.text(key, language: language) }
}
