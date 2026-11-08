import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareProfileScopeView: View {
  typealias Scope = GalaxySSIHealthCareProfileScope
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: GalaxySSIHealthCare.Concern
  @State private var selection: Scope.Selection
  @State private var profile: GalaxySSIHealthProfile?
  @State private var category = GalaxySSIHealthProfile.BackgroundKind.history
  @State private var selectedOnly = false
  @State private var page = 0
  @State private var failed = false

  init(records: GalaxySSIHealthRecords, concern: GalaxySSIHealthCare.Concern) {
    self.records = records
    self.concern = concern
    _selection = State(initialValue: concern.profileScope?.selection ?? .init())
  }

  var body: some View {
    NavigationView {
      List {
        if canRead, let profile {
          Section(t("fields", "Saved profile fields")) {
            ForEach(Scope.Field.allCases) { field in
              Toggle(field.title(language: language), isOn: Binding(get: { selection.fields.contains(field) }, set: {
                if $0 { selection.fields.insert(field) } else { selection.fields.remove(field) }
              }))
            }
          }
          Section(t("entries", "Saved background entries")) {
            Toggle(t("selected", "Selected only"), isOn: $selectedOnly)
            if !selectedOnly {
              Picker(t("category", "Category"), selection: $category) {
                ForEach(GalaxySSIHealthProfile.BackgroundKind.allCases, id: \.self) {
                  Text(GalaxySSIHealthBackgroundPicker.title($0, language: language)).tag($0)
                }
              }
            }
            Text(String(format: t("count", "%lld of 30 selected"), Int64(selection.entries.count)))
              .foregroundColor(.secondary)
            let filtered = profile.background.filter { selectedOnly ? selection.entries.contains($0.id) : $0.kind == category }
            let offset = min(page * 30, max(0, (filtered.count - 1) / 30 * 30))
            ForEach(filtered.dropFirst(offset).prefix(30)) { entry in
              Toggle(entry.title, isOn: Binding(get: { selection.entries.contains(entry.id) }, set: {
                if $0, selection.entries.count < 30 { selection.entries.insert(entry.id) }
                else if !$0 { selection.entries.remove(entry.id) }
              })).disabled(selection.entries.count >= 30 && !selection.entries.contains(entry.id))
            }
            if selectedOnly {
              let unavailable = selection.entries.subtracting(profile.background.map(\.id))
              ForEach(unavailable.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                Button(t("remove_unavailable", "Remove unavailable entry"), role: .destructive) {
                  selection.entries.remove(id)
                }
              }
            } else {
              HStack {
                Button(t("previous", "Previous")) { page -= 1 }.disabled(offset == 0)
                Spacer()
                Button(t("next", "Next")) { page += 1 }.disabled(offset + 30 >= filtered.count)
              }.buttonStyle(.borderless)
            }
          }
          Text(t("boundary", "Only this concern can use the selection after you review and send a request. A changed selection starts a new private discussion."))
            .foregroundColor(.secondary)
        }
        if failed { Text(t("stale", "The saved profile or concern changed. Reopen the selection to review it.")) }
      }
      .navigationTitle(t("title", "Profile sharing scope"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("apply", "Apply"), action: apply).disabled(profile == nil || !canRead)
        }
      }
      .onAppear { profile = canRead ? (try? records.loadProfile()) : nil }
      .onChange(of: category) { _ in page = 0 }
      .onChange(of: selectedOnly) { _ in page = 0 }
      .onChange(of: scene) { if $0 != .active { clear() } }
      .onChange(of: store.profile.identityFingerprint) { _ in clear() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    }.navigationViewStyle(.stack)
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func apply() {
    guard canRead, let profile else { return }
    do {
      let link = selection.isEmpty ? nil : try Scope.Link(selection, profile: profile)
      try records.setLocalCareProfileScope(concern, link: link)
      clear()
    } catch { failed = true }
  }

  private func clear() {
    profile = nil
    selection = .init()
    dismiss()
  }

  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.care_profile." + key, fallback: fallback, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language: language) }
}
