import SwiftUI

@MainActor
struct GalaxySSIHealthEncounterEditor: View {
  typealias Encounter = GalaxySSIHealthEncounter
  @Environment(\.dismiss) private var dismiss
  let language: String
  let onSave: (Encounter.Draft) -> Void
  private let editing: Bool
  private let zone: TimeZone
  @State private var draft: Encounter.Draft
  @State private var planned: WallTime
  @State private var attended: WallTime
  @State private var invalid = false

  private struct WallTime {
    var enabled: Bool
    var day: Date
    var hour: Int
    var minute: Int
    var offset: Int?

    init(_ date: Date?, zone: TimeZone) {
      enabled = date != nil
      day = date ?? Date()
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      hour = calendar.component(.hour, from: day)
      minute = calendar.component(.minute, from: day)
      offset = date.map { zone.secondsFromGMT(for: $0) }
    }

    func options(zone: TimeZone) -> [Date] {
      Encounter.possibleTimes(day: day, hour: hour, minute: minute, zone: zone)
    }

    func resolved(zone: TimeZone) -> Date? {
      guard enabled else { return nil }
      let dates = options(zone: zone)
      return dates.count == 1 ? dates.first : dates.first { zone.secondsFromGMT(for: $0) == offset }
    }
  }

  init(entry: Encounter.Entry?, language: String, onSave: @escaping (Encounter.Draft) -> Void) {
    let value = entry?.details ?? .init()
    let timeZone = TimeZone(identifier: value.zone) ?? .current
    editing = entry != nil
    zone = timeZone
    self.language = language
    self.onSave = onSave
    _draft = State(initialValue: value)
    _planned = State(initialValue: WallTime(value.plannedAt, zone: timeZone))
    _attended = State(initialValue: WallTime(value.attendedAt, zone: timeZone))
  }

  var body: some View {
    NavigationView {
      Form {
        Section {
          TextField(t("purpose", "Purpose"), text: $draft.purpose)
          TextField(t("facility", "Facility"), text: $draft.facility)
          Picker(t("state", "Status"), selection: $draft.state) {
            ForEach(Encounter.State.allCases) { state in Text(state.title(language)).tag(state) }
          }
        }
        Section {
          timeFields(t("planned_at", "Planned time"), time: $planned)
          if draft.state == .attended {
            timeFields(t("attended_at", "Actual visit time"), time: $attended)
          }
          Text(zone.identifier).foregroundColor(.secondary)
        }
        Section(t("note", "Note")) {
          TextEditor(text: $draft.note).frame(minHeight: 90).accessibilityLabel(t("note", "Note"))
        }
        Text(t("notice", "Self-reported. This is not a hospital booking or a clinical record."))
          .font(.footnote).foregroundColor(.secondary)
        if invalid {
          Text(t("invalid", "Check the purpose, required dates and text lengths. Actual visits cannot be in the future."))
            .foregroundColor(.secondary)
        }
      }
      .navigationTitle(editing ? t("edit", "Edit visit") : t("add", "Add visit"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button(t("save", "Save"), action: save) }
      }
    }.navigationViewStyle(.stack)
  }

  @ViewBuilder private func timeFields(_ title: String, time: Binding<WallTime>) -> some View {
    Toggle(title, isOn: time.enabled)
    if time.wrappedValue.enabled {
      let options = time.wrappedValue.options(zone: zone)
      DatePicker(t("date", "Date"), selection: time.day, displayedComponents: .date)
        .environment(\.timeZone, zone)
        .onChange(of: time.wrappedValue.day) { _ in time.offset.wrappedValue = nil }
      Picker(t("hour", "Hour"), selection: time.hour) {
        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
      }.onChange(of: time.wrappedValue.hour) { _ in time.offset.wrappedValue = nil }
      Picker(t("minute", "Minute"), selection: time.minute) {
        ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
      }.onChange(of: time.wrappedValue.minute) { _ in time.offset.wrappedValue = nil }
      if options.isEmpty {
        Text(t("invalid_time", "This local time does not exist in the selected time zone.")).foregroundColor(.secondary)
      } else if options.count > 1 {
        Picker(t("offset", "UTC offset"), selection: time.offset) {
          Text(t("choose_offset", "Select an offset")).tag(Int?.none)
          ForEach(options, id: \.self) { date in
            Text(GalaxySSIHealthEncounterView.offset(date, zone)).tag(Optional(zone.secondsFromGMT(for: date)))
          }
        }
      }
    }
  }

  private func save() {
    var value = draft
    value.plannedAt = planned.resolved(zone: zone)
    value.attendedAt = draft.state == .attended ? attended.resolved(zone: zone) : nil
    guard !planned.enabled || value.plannedAt != nil,
          let normalized = try? value.validated(now: Date()) else { invalid = true; return }
    onSave(normalized)
  }

  private func t(_ key: String, _ fallback: String) -> String { Encounter.text(key, fallback, language) }
}
