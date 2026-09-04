import SwiftUI

struct GalaxySSIObsidianCandidatesView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var candidates: [AgentIOSObsidianEditCandidate] = []
  @State private var selected: AgentIOSObsidianEditCandidate?
  var onChange: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_obsidian_candidates_title", "Review Obsidian edits"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if candidates.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("cc_obsidian_no_candidates", "No edits are waiting for review"),
              subtitle: t("cc_obsidian_candidates_subtitle", "Approve or reject external edits before they enter Agent knowledge"),
              systemImage: "checkmark.shield",
              tint: .galaxySSIAccent,
              badge: "0"
            )
          } else {
            ForEach(candidates) { candidate in
              Button { selected = candidate } label: {
                GalaxySSISecurityRowContent(
                  title: candidate.title,
                  subtitle: candidate.relativePath,
                  systemImage: "doc.text",
                  tint: .orange,
                  badge: t("cc_obsidian_review", "Review"),
                  monospacedSubtitle: false,
                  showsDisclosure: true
                )
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(12)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: reload)
    .sheet(item: $selected) { candidate in
      NavigationView {
        VStack(alignment: .leading, spacing: 12) {
          ScrollView {
            Text(candidate.content)
              .font(.system(size: 14, design: .monospaced))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          HStack(spacing: 10) {
            Button(t("cc_obsidian_reject", "Reject")) { review(candidate, approve: false) }
              .buttonStyle(.bordered)
            Button(t("cc_obsidian_approve", "Approve")) { review(candidate, approve: true) }
              .buttonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .navigationTitle(candidate.title)
        .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  private func reload() {
    candidates = AgentIOSObsidianBridge.pendingCandidates()
  }

  private func review(_ candidate: AgentIOSObsidianEditCandidate, approve: Bool) {
    if approve {
      _ = AgentIOSObsidianBridge.approveCandidate(candidate.id, appStore: store)
    } else {
      _ = AgentIOSObsidianBridge.rejectCandidate(candidate.id)
    }
    selected = nil
    reload()
    onChange()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
