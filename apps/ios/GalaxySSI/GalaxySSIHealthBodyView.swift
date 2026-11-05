import SwiftUI

private struct BodyLesson {
  let topic: String
  let key: String
  let nodes: [String]
  let path: [Int]
  let source: String
  let link: String

  var steps: Int { path.count - 1 }

  static let topics = [
    Self(topic: "circulation", key: "circ", nodes: ["right_heart", "lungs", "left_heart", "body_tissues"],
         path: [0, 1, 2, 3, 0], source: "heart", link: "https://www.nhlbi.nih.gov/health/heart/blood-flow"),
    Self(topic: "breathing", key: "breath", nodes: ["air", "alveoli", "blood", "breath_out"],
         path: [0, 1, 2, 1, 3], source: "lung", link: "https://www.nhlbi.nih.gov/health/lungs/respiratory-system"),
    Self(topic: "metabolism", key: "metabolic", nodes: ["nutrients", "mitochondria", "atp", "cell_work"],
         path: [0, 1, 2, 3], source: "metabolism", link: "https://openstax.org/books/anatomy-and-physiology/pages/24-1-overview-of-metabolic-reactions"),
    Self(topic: "nerves", key: "nerve", nodes: ["cell_body", "axon", "synapse", "target_cell"],
         path: [0, 1, 2, 3], source: "nerves", link: "https://openstax.org/books/anatomy-and-physiology/pages/12-5-communication-between-neurons"),
    Self(topic: "digestion", key: "digest", nodes: ["mouth", "stomach", "intestine", "circulation"],
         path: [0, 1, 2, 3], source: "digestion", link: "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works"),
    Self(topic: "kidneys", key: "kidney", nodes: ["blood", "glomerulus", "tubule", "urine"],
         path: [0, 1, 2, 0], source: "kidneys", link: "https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work")
  ]

  static let oxygen = Self(topic: "breathing", key: "oxygen", nodes: ["alveoli", "hemoglobin", "body_tissues"],
    path: [0, 1, 2], source: "oxygen", link: "https://openstax.org/books/anatomy-and-physiology/pages/22-5-transport-of-gases")

  func edge(_ index: Int) -> (String, String) {
    if topic == "kidneys", index == 3 { return (nodes[2], nodes[3]) }
    return (nodes[path[index]], nodes[path[index + 1]])
  }

  var stepCount: Int { topic == "kidneys" ? 4 : steps }
}

struct GalaxySSIHealthBodyView<Personal: View>: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let personal: () -> Personal
  @State private var topic = 0
  @State private var layer = "organ"
  @State private var step = 0
  @State private var playing = false
  @State private var slow = false
  @State private var zoomed = false
  @State private var zoom = 1.0
  @State private var beats = 75.0
  @State private var stroke = 60.0

  private var selected: BodyLesson { BodyLesson.topics[topic] }
  private var lesson: BodyLesson { layer == "molecule" && topic < 2 ? .oxygen : selected }

  var body: some View {
    List {
      Section(t("heading")) {
        Button {
          playing = false
          zoom = 1
          zoomed = true
        } label: {
          Image("HealthBodyConcept").resizable().scaledToFit().frame(maxHeight: 290)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(t("concept_alt")))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(t("zoom")))
        Text(t("concept_note")).font(.footnote).foregroundColor(.secondary)
        Picker(t("more"), selection: $topic) {
          ForEach(BodyLesson.topics.indices, id: \.self) { index in
            Text(t(BodyLesson.topics[index].topic)).tag(index)
          }
        }
        Picker(t("model_caption"), selection: $layer) {
          ForEach(["organ", "tissue", "cell", "molecule"], id: \.self) { key in Text(t(key)).tag(key) }
        }
        Text(t(selected.key + "_" + layer))
      }
      Section(t("mechanism")) {
        Text(t(lesson.key + "_title")).font(.headline)
        Text(t(lesson.key + "_summary"))
        diagram
        Text(t("model_caption")).font(.caption).foregroundColor(.secondary)
        Text(String(format: t("step_count"), Int64(step + 1), Int64(lesson.stepCount),
                    t(lesson.key + "_s" + String(step + 1)))).font(.headline)
        Text(t(lesson.key + "_d" + String(step + 1)))
        HStack(spacing: 20) {
          control("backward.end.fill", label: "previous_step") { jump(-1) }.disabled(step == 0)
          control(playing ? "pause.fill" : "play.fill", label: playing ? "pause" : "play") {
            if !playing && step == lesson.stepCount - 1 { step = 0 }
            playing.toggle()
          }
          .disabled(reduceMotion)
          control("forward.end.fill", label: "next_step") { jump(1) }.disabled(step == lesson.stepCount - 1)
        }
        .buttonStyle(.borderless)
        Toggle(t("slow"), isOn: $slow).disabled(reduceMotion)
        if reduceMotion { Text(t("motion_disabled")).font(.footnote) }
      }
      Section(t("reference_title")) {
        Text(t(lesson.key + "_reference"))
        if let url = URL(string: lesson.link) { Link(t("source_" + lesson.source), destination: url) }
      }
      if topic == 0 {
        Section(t("experiment")) {
          Text(t("example_only")).font(.headline)
          Text(String(format: t("rate"), Int64(beats)))
          Slider(value: $beats, in: 40...140, step: 1).accessibilityLabel(Text(String(format: t("rate"), Int64(beats))))
          Text(String(format: t("stroke"), Int64(stroke)))
          Slider(value: $stroke, in: 20...120, step: 1).accessibilityLabel(Text(String(format: t("stroke"), Int64(stroke))))
          Text(String(format: t("output"), (beats * stroke / 1000).formatted(.number.precision(.fractionLength(2)))))
            .font(.title3.monospacedDigit())
          Text(t("formula"))
          Text(t("experiment_boundary")).font(.footnote).foregroundColor(.secondary)
          Button(t("reset_experiment")) { beats = 75; stroke = 60 }
        }
        Section(t("personal")) {
          Text(t("personal_boundary")).font(.footnote).foregroundColor(.secondary)
          NavigationLink(destination: personal()) { Text(t("open_bp")) }
            .simultaneousGesture(TapGesture().onEnded { playing = false })
        }
      }
    }
    .navigationTitle(t("title"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: topic) { _ in reset() }
    .onChange(of: layer) { _ in reset() }
    .onChange(of: scene) { if $0 != .active { playing = false } }
    .onChange(of: reduceMotion) { if $0 { playing = false } }
    .onDisappear { playing = false }
    .task(id: playing && !reduceMotion ? (slow ? 2 : 1) : 0) {
      guard playing, !reduceMotion else { return }
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: slow ? 4_700_000_000 : 2_350_000_000) }
        catch { return }
        guard !Task.isCancelled, playing, scene == .active else { return }
        if step >= lesson.stepCount - 1 { playing = false; return }
        withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
      }
    }
    .sheet(isPresented: $zoomed) {
      VStack(spacing: 12) {
        ScrollView([.horizontal, .vertical]) {
          Image("HealthBodyConcept").resizable().scaledToFit()
            .frame(width: 280 * zoom).accessibilityLabel(Text(t("concept_alt")))
        }
        Slider(value: $zoom, in: 1...3).accessibilityLabel(Text(t("zoom")))
        Button { zoomed = false } label: { Image(systemName: "xmark.circle").font(.title2) }
          .accessibilityLabel(Text(GalaxySSILocalization.string("galaxyssi.health.cancel", fallback: "Close", language: language)))
      }
      .padding()
    }
  }

  private var diagram: some View {
    let edge = lesson.edge(min(step, lesson.stepCount - 1))
    return VStack(alignment: .leading, spacing: 10) {
      Label(t(edge.0), systemImage: "circle.fill")
      Image(systemName: "arrow.down").accessibilityHidden(true)
      Label(t(edge.1), systemImage: "circle.fill")
    }
    .foregroundColor(.accentColor)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .id(step)
    .transition(.opacity)
  }

  private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: icon).frame(minWidth: 44, minHeight: 44) }
      .accessibilityLabel(Text(t(label)))
  }

  private func jump(_ delta: Int) {
    playing = false
    step = min(max(0, step + delta), lesson.stepCount - 1)
  }

  private func reset() { playing = false; step = 0 }
  private func t(_ key: String) -> String { GalaxySSIHealthBodyText.string(key, language: language) }
}
