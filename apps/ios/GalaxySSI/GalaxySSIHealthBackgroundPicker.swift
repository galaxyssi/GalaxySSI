import SwiftUI

@MainActor
struct GalaxySSIHealthBackgroundPicker: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let apply: ([UUID: UUID]) -> Void
  @State private var draft: [UUID: UUID]
  @State private var profile: GalaxySSIHealthProfile?
  @State private var permission: UUID?
  @State private var category = GalaxySSIHealthProfile.BackgroundKind.history
  @State private var selectedOnly = false
  @State private var page = 0

  init(records: GalaxySSIHealthRecords, selection: [UUID: UUID], apply: @escaping ([UUID: UUID]) -> Void) {
    self.records = records
    self.apply = apply
    _draft = State(initialValue: selection)
  }

  var body: some View {
    NavigationView {
      List {
        if scene == .active, let profile {
          Toggle(t("background_selected", "Selected only"), isOn: $selectedOnly)
          if !selectedOnly {
            Picker(t("background_category", "Category"), selection: $category) {
              ForEach(GalaxySSIHealthProfile.BackgroundKind.allCases, id: \.self) { kind in
                Text(Self.title(kind, language: language)).tag(kind)
              }
            }
          }
          Text(String(format: t("background_count", "%lld of 30 selected"), Int64(draft.count)))
            .foregroundColor(.secondary)
          let filtered = profile.background.filter {
            selectedOnly ? draft[$0.id] != nil : $0.kind == category
          }
          let offset = min(page * 30, max(0, (filtered.count - 1) / 30 * 30))
          ForEach(filtered.dropFirst(offset).prefix(30)) { entry in
            row(entry, revision: profile.backgroundVersion(entry))
          }
          if selectedOnly {
            let existing = Set(profile.background.map(\.id))
            ForEach(draft.keys.filter { !existing.contains($0) }.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
              Button(role: .destructive) { draft.removeValue(forKey: id) } label: {
                Label(t("background_remove_missing", "Remove unavailable selection"), systemImage: "trash")
              }
            }
          } else {
            HStack {
              Button(t("background_previous", "Previous")) { page -= 1 }.disabled(offset == 0)
              Spacer()
              Button(t("background_next", "Next")) { page += 1 }.disabled(offset + 30 >= filtered.count)
            }
            .buttonStyle(.borderless)
          }
          if !profile.matchesBackground(draft) {
            Text(t("background_changed", "Remove or reselect changed entries before continuing.")).foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle(t("background_title", "Saved health background"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("background_cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("background_apply", "Apply"), action: confirm)
            .disabled(profile?.matchesBackground(draft) != true)
        }
      }
      .onAppear(perform: reload)
      .onChange(of: category) { _ in page = 0 }
      .onChange(of: selectedOnly) { _ in page = 0 }
      .onChange(of: scene) { if $0 != .active { draft = [:]; profile = nil; dismiss() } }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
        if $0.object as? String == records.owner { reload() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
        if $0.object as? String == records.owner { reload() }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func row(_ entry: GalaxySSIHealthProfile.Background, revision: UUID?) -> some View {
    Toggle(isOn: Binding(get: { draft[entry.id] != nil }, set: { enabled in
      if enabled, let revision, draft.count < 30 { draft[entry.id] = revision }
      else if !enabled { draft.removeValue(forKey: entry.id) }
    })) {
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.title)
        if !entry.notes.isEmpty { Text(entry.notes).foregroundColor(.secondary) }
        if let pinned = draft[entry.id], pinned != revision {
          Text(t("background_stale", "Selected version changed")).foregroundColor(.secondary)
        }
      }
    }
    .disabled(draft[entry.id] == nil && (draft.count >= 30 || revision == nil))
  }

  private func reload() {
    guard scene == .active, let archive = try? records.load(), archive.derivesOverview == true,
          let key = archive.profileAnalysisPermission, permission == nil || permission == key,
          let current = try? records.loadProfile() else {
      draft = [:]; profile = nil; dismiss(); return
    }
    permission = key
    profile = current
  }

  private func confirm() {
    reload()
    guard scene == .active, profile?.matchesBackground(draft) == true else { return }
    apply(draft)
    dismiss()
  }

  static func title(_ kind: GalaxySSIHealthProfile.BackgroundKind, language: String) -> String {
    let fallback: String
    switch kind {
    case .history: fallback = "History"
    case .medication: fallback = "Medication"
    case .allergy: fallback = "Allergies"
    }
    return GalaxySSILocalization.string("galaxyssi.health.assistant.background_" + kind.rawValue,
                                        fallback: fallback, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.assistant." + key, fallback: fallback, language: language)
  }
}
