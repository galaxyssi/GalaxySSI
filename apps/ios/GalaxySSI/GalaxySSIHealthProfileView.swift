import SwiftUI

struct GalaxySSIHealthProfile: Codable {
  enum ReferenceSex: String, Codable, CaseIterable { case unspecified, female, male, other }
  enum HeightUnit: String, Codable, CaseIterable { case cm, inches }
  enum BackgroundKind: String, Codable, CaseIterable { case history, medication, allergy }
  enum AnalysisField: String, Codable, CaseIterable, Identifiable {
    case birthDate, referenceSex, height, context
    var id: String { rawValue }

    func title(language: String) -> String {
      let label: (key: String, fallback: String)
      switch self {
      case .birthDate: label = ("birth", "Date of birth")
      case .referenceSex: label = ("sex", "Reference sex")
      case .height: label = ("height", "Height")
      case .context: label = ("physiological", "Physiological context")
      }
      return GalaxySSILocalization.string("galaxyssi.health.assistant.profile_" + label.key,
                                          fallback: label.fallback, language: language)
    }
  }

  enum AnalysisValue: Equatable {
    case date(Date), sex(ReferenceSex), height(Decimal, HeightUnit), context(String)
  }

  struct AnalysisContext {
    let permission: UUID
    let values: [AnalysisField: AnalysisValue]
    let fields: Set<AnalysisField>
    let versions: [AnalysisField: UUID]

    init(profile: GalaxySSIHealthProfile, permission: UUID, fields: Set<AnalysisField>) {
      self.permission = permission
      self.fields = fields
      values = Dictionary(uniqueKeysWithValues: fields.compactMap { field in
        profile.analysisValue(field).map { (field, $0) }
      })
      versions = Dictionary(uniqueKeysWithValues: fields.compactMap { field in
        profile.analysisVersion(field).map { (field, $0) }
      })
    }

    func isCurrent(profile: GalaxySSIHealthProfile, permission: UUID?) -> Bool {
      self.permission == permission && fields.allSatisfy {
        versions[$0] == profile.analysisVersion($0) && values[$0] == profile.analysisValue($0)
      }
    }
  }

  struct Background: Codable, Identifiable {
    var id = UUID()
    var kind: BackgroundKind
    var title: String
    var notes: String
  }

  var revision: UUID?
  var analysisVersions: [AnalysisField: UUID]?
  var name = ""
  var birthDate: Date?
  var referenceSex = ReferenceSex.unspecified
  var height: Decimal?
  var heightUnit = HeightUnit.cm
  var context = ""
  var background: [Background] = []

  func analysisValue(_ field: AnalysisField) -> AnalysisValue? {
    switch field {
    case .birthDate: return birthDate.map(AnalysisValue.date)
    case .referenceSex: return referenceSex == .unspecified ? nil : .sex(referenceSex)
    case .height: return height.map { .height($0, heightUnit) }
    case .context: return context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .context(context)
    }
  }

  func analysisVersion(_ field: AnalysisField) -> UUID? {
    if let analysisVersions { return analysisVersions[field] }
    return analysisValue(field) == nil ? nil : revision
  }

  var isValid: Bool {
    guard name.utf8.count <= 256, context.utf8.count <= 2048,
          birthDate.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 <= Date() }) ?? true,
          height.map({ !$0.isNaN && $0 > 0 }) ?? true,
          Set(background.map(\.id)).count == background.count else { return false }
    return background.allSatisfy {
      !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        $0.title.utf8.count <= 256 && $0.notes.utf8.count <= 2048
    }
  }
}

@MainActor
struct GalaxySSIHealthProfileView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  @State private var draft = GalaxySSIHealthProfile()
  @State private var height = ""
  @State private var loaded = false
  @State private var notice: Notice?
  @State private var backgroundEditor: GalaxySSIHealthProfile.Background?
  @State private var backgroundLimit = 30

  private enum Notice: String, Identifiable {
    case invalid, stale, unavailable, erase
    var id: String { rawValue }
  }

  var body: some View {
    Form {
      if scenePhase == .active && loaded {
        Section(t("personal", "Personal details")) {
          TextField(t("name", "Name"), text: $draft.name)
          Toggle(t("birth_date", "Include date of birth"), isOn: Binding(
            get: { draft.birthDate != nil }, set: { draft.birthDate = $0 ? Date() : nil }))
          if draft.birthDate != nil {
            DatePicker(t("date", "Date of birth"), selection: Binding(
              get: { draft.birthDate ?? Date() }, set: { draft.birthDate = $0 }), in: ...Date(), displayedComponents: .date)
          }
          Picker(t("sex", "Medical reference sex"), selection: $draft.referenceSex) {
            ForEach(GalaxySSIHealthProfile.ReferenceSex.allCases, id: \.self) { sex in
              Text(sexTitle(sex)).tag(sex)
            }
          }
          TextField(t("height", "Height"), text: $height).keyboardType(.decimalPad)
          Picker(t("unit", "Height unit"), selection: $draft.heightUnit) {
            Text("cm").tag(GalaxySSIHealthProfile.HeightUnit.cm)
            Text("in").tag(GalaxySSIHealthProfile.HeightUnit.inches)
          }
          TextField(t("context", "Physiological context"), text: $draft.context)
        }
        ForEach(GalaxySSIHealthProfile.BackgroundKind.allCases, id: \.self) { kind in
          Section(kindTitle(kind)) {
            let entries = draft.background.filter { $0.kind == kind }
            ForEach(entries.prefix(backgroundLimit)) { item in
              Button(item.title) { backgroundEditor = item }
            }
            if entries.count > backgroundLimit { Button(t("more", "Show more")) { backgroundLimit += 30 } }
            Button(t("add", "Add entry")) { backgroundEditor = .init(kind: kind, title: "", notes: "") }
          }
        }
        Button(t("save", "Save profile"), action: save)
        if draft.revision != nil {
          Button(t("erase", "Clear saved profile"), role: .destructive) { notice = .erase }
        }
      } else if scenePhase == .active {
        Text(t("unavailable", "Could not open the health profile."))
        Button(t("reload", "Reload profile"), action: reload)
      }
    }
    .navigationTitle(t("title", "Health Profile"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scenePhase) { phase in
      if phase == .active { reload() }
      else {
        loaded = false
        draft = GalaxySSIHealthProfile()
        height = ""
        backgroundEditor = nil
        notice = nil
      }
    }
    .sheet(item: $backgroundEditor) { entry in
      BackgroundEditor(entry: entry, alreadySaved: draft.background.contains(where: { $0.id == entry.id }),
                       update: updateBackground, remove: removeBackground)
    }
    .alert(item: $notice) { notice in
      switch notice {
      case .invalid: return Alert(title: Text(t("invalid", "Check the profile fields and lengths.")))
      case .stale: return Alert(title: Text(t("stale", "The profile changed. Reload before editing.")),
                                dismissButton: .default(Text(t("reload", "Reload profile")), action: reload))
      case .unavailable: return Alert(title: Text(t("unavailable", "Could not open the health profile.")))
      case .erase:
        return Alert(title: Text(t("erase", "Clear saved profile")),
                     message: Text(t("erase_scope", "Removes profile details and background entries. Measurements and exported files are kept.")),
                     primaryButton: .destructive(Text(t("remove", "Remove")), action: erase),
                     secondaryButton: .cancel())
      }
    }
  }

  private func updateBackground(_ entry: GalaxySSIHealthProfile.Background) {
    guard loaded, scenePhase == .active else { return }
    if let index = draft.background.firstIndex(where: { $0.id == entry.id }) {
      draft.background[index] = entry
    } else {
      draft.background.append(entry)
    }
    backgroundEditor = nil
  }

  private func removeBackground(_ id: UUID) {
    guard loaded, scenePhase == .active else { return }
    draft.background.removeAll { $0.id == id }
    backgroundEditor = nil
  }

  private func save() {
    let value = height.trimmingCharacters(in: .whitespacesAndNewlines)
    var updated = draft
    if value.isEmpty { updated.height = nil }
    else {
      guard let parsed = try? Decimal(value, format: .number.locale(locale), lenient: false)
      else { notice = .invalid; return }
      updated.height = parsed
    }
    persist(updated)
  }

  private func erase() {
    var empty = GalaxySSIHealthProfile()
    empty.revision = draft.revision
    persist(empty)
  }

  private func persist(_ value: GalaxySSIHealthProfile) {
    guard scenePhase == .active, loaded else { return }
    do { try records.writeProfile(value); reload() }
    catch GalaxySSIHealthRecords.Failure.stale { notice = .stale }
    catch GalaxySSIHealthRecords.Failure.invalid { notice = .invalid }
    catch { notice = .unavailable }
  }

  private func reload() {
    guard scenePhase == .active else { return }
    do {
      draft = try records.loadProfile()
      height = draft.height.map { NSDecimalNumber(decimal: $0).description(withLocale: locale) } ?? ""
      loaded = true
    } catch { loaded = false; notice = .unavailable }
  }

  private func kindTitle(_ kind: GalaxySSIHealthProfile.BackgroundKind) -> String {
    switch kind {
    case .history: return t("history", "Self-reported medical history")
    case .medication: return t("medication", "Medication and supplements")
    case .allergy: return t("allergy", "Allergies")
    }
  }

  private func sexTitle(_ sex: GalaxySSIHealthProfile.ReferenceSex) -> String {
    switch sex {
    case .unspecified: return t("unspecified", "Not specified")
    case .female: return t("female", "Female")
    case .male: return t("male", "Male")
    case .other: return t("other", "Other")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.profile." + key, fallback: fallback, language: language)
  }

  private struct BackgroundEditor: View {
    @Environment(\.galaxySSIInterfaceLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State var entry: GalaxySSIHealthProfile.Background
    let alreadySaved: Bool
    let update: (GalaxySSIHealthProfile.Background) -> Void
    let remove: (UUID) -> Void

    var body: some View {
      NavigationView {
        Form {
          TextField(t("entry", "Entry"), text: $entry.title)
          TextField(t("notes", "Notes"), text: $entry.notes)
          if alreadySaved { Button(t("remove", "Remove"), role: .destructive) { remove(entry.id) } }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(t("done", "Done")) { update(entry) }
              .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        entry.title.utf8.count > 256 || entry.notes.utf8.count > 2048)
          }
        }
      }
      .navigationViewStyle(.stack)
    }

    private func t(_ key: String, _ fallback: String) -> String {
      GalaxySSILocalization.string("galaxyssi.health.profile." + key, fallback: fallback, language: language)
    }
  }
}
