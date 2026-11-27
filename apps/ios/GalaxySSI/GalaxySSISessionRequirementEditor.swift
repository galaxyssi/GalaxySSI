import SwiftUI

struct AgentSessionRequirementDraft: Identifiable {
  let id: String
  let owner: String
  let generation: UInt64
  let expected: String
  let seed: String
}

struct GalaxySSISessionRequirementEditor: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.dismiss) private var dismiss
  let draft: AgentSessionRequirementDraft
  let t: (String, String) -> String
  @State private var text: String
  @State private var failed = false

  init(draft: AgentSessionRequirementDraft, t: @escaping (String, String) -> String) {
    self.draft = draft
    self.t = t
    _text = State(initialValue: draft.expected.isEmpty ? AgentSessionRequirement.seed(draft.seed) : draft.expected)
  }

  var body: some View {
    NavigationView {
      Form {
        TextEditor(text: $text)
          .frame(minHeight: 120)
          .accessibilityLabel(t("agent_session_requirement", "Session requirements"))
          .accessibilityIdentifier("ios.agent.session-requirement.text")
          .onChange(of: text) { value in
            if value.utf16.count > AgentSessionRequirement.maximumUTF16 { text = AgentSessionRequirement.seed(value) }
          }
        Text("\(text.utf16.count)/\(AgentSessionRequirement.maximumUTF16)")
          .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        if !draft.expected.isEmpty {
          Button(role: .destructive) { save("") } label: {
            Label(t("agent_session_requirement_remove", "Remove requirement"), systemImage: "trash")
          }
          .accessibilityIdentifier("ios.agent.session-requirement.remove")
        }
      }
      .navigationTitle(t("agent_session_requirement", "Session requirements"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.common.save", "Save")) { save(text) }
            .disabled(AgentSessionRequirement.normalize(text) == nil)
            .accessibilityIdentifier("ios.agent.session-requirement.save")
        }
      }
      .alert(t("agent_session_requirement_unavailable", "This conversation changed or is unavailable."), isPresented: $failed) {
        Button(t("galaxyssi.common.ok", "OK"), role: .cancel) {}
      }
    }
    .navigationViewStyle(.stack)
    .onChange(of: store.activeAgentConversationId) { _ in dismiss() }
    .onChange(of: store.profile.identityFingerprint) { _ in dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in dismiss() }
  }

  private func save(_ value: String) {
    guard store.runtimePlaintextGeneration == draft.generation,
          store.setAgentSessionRequirement(id: draft.id, expected: draft.expected, text: value, owner: draft.owner) else {
      failed = true
      return
    }
    dismiss()
  }
}
