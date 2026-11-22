import SwiftUI

@MainActor
struct GalaxySSIConversationRenameView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @FocusState private var focused: Bool
  let target: GalaxySSIConversationRenameTarget
  let save: (String) async -> Bool
  @State private var value: String
  @State private var saving = false
  @State private var failed = false
  @State private var validationRequested = false
  @State private var attempt = UUID()
  @State private var work: Task<Void, Never>?

  init(target: GalaxySSIConversationRenameTarget, save: @escaping (String) async -> Bool) {
    self.target = target; self.save = save; _value = State(initialValue: target.initialName)
  }
  private var name: String? { GalaxySSIConversationRenamePolicy.normalize(value) }
  private var canSave: Bool { name != nil && name != target.initialName.trimmingCharacters(in: .whitespacesAndNewlines) && !saving }
  var body: some View {
    NavigationView {
      VStack(alignment: .leading, spacing: 12) {
        Text(scene == .active ? target.title : "").font(.subheadline).foregroundColor(.secondary).lineLimit(2)
        TextField(target.kind == .contact ? t("contact_remark_name", "Remark name") : t("galaxyssi.conversation_actions.hint", "Conversation name"), text: $value)
          .textInputAutocapitalization(.sentences).disableAutocorrection(true).focused($focused)
          .submitLabel(.done).onSubmit(submit).padding(12).frame(minHeight: 48)
          .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
          .disabled(saving).accessibilityIdentifier("conversation-rename-input")
        Text("\(value.utf16.count)/\(GalaxySSIConversationRenamePolicy.maximumCharacters)")
          .font(.caption).foregroundColor(name == nil && !value.isEmpty ? .red : .secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
        if name == nil && (!value.isEmpty || validationRequested) {
          Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? t("galaxyssi.conversation_actions.required", "Enter a name.")
            : t("galaxyssi.conversation_actions.invalid", "Use at most 72 characters on a single line."))
            .font(.caption).foregroundColor(.secondary)
        }
        if failed { Text(t("galaxyssi.conversation_actions.failed", "The name could not be saved. Please try again.")).foregroundColor(.red) }
        if saving { ProgressView().accessibilityLabel(t("galaxyssi.conversation_actions.saving", "Saving name")) }
        Spacer(minLength: 0)
      }.padding(16)
        .navigationTitle(target.kind == .contact ? t("contact_edit_remark_title", "Edit remark") : t("galaxyssi.conversation_actions.rename", "Rename conversation"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
              .accessibilityLabel(t("galaxyssi.common.cancel", "Cancel")).disabled(saving)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(action: beginSave) { Image(systemName: "checkmark") }
              .accessibilityLabel(t("galaxyssi.common.save", "Save")).disabled(!canSave)
          }
        }
    }.navigationViewStyle(.stack).privacySensitive().interactiveDismissDisabled(saving)
      .onAppear { focused = true }
      .onChange(of: value) { _ in failed = false; validationRequested = false }
      .onChange(of: scene) { if $0 != .active { clear(); dismiss() } }
      .onDisappear(perform: clear)
  }
  private func beginSave() {
    guard scene == .active, canSave, let name else { return }
    saving = true; failed = false; let ticket = UUID(); attempt = ticket
    work = Task { @MainActor in
      let saved = await save(name)
      guard !Task.isCancelled, scene == .active, attempt == ticket else { return }
      saving = false
      if saved { dismiss() } else { failed = true; focused = true }
    }
  }
  private func submit() {
    guard !saving else { return }
    guard let name else { validationRequested = true; return }
    if name == target.initialName.trimmingCharacters(in: .whitespacesAndNewlines) { dismiss() } else { beginSave() }
  }
  private func clear() { attempt = UUID(); work?.cancel(); work = nil; value = ""; saving = false; failed = false; validationRequested = false; focused = false }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSILocalization.string(key, fallback: fallback, language: language) }
}
