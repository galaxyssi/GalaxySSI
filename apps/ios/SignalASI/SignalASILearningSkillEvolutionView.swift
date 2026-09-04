import Foundation
import SwiftUI

final class UserDefaultsAgentLearningProposalStore: AgentLearningProposalStoring {
  static let defaultKey = "signalasi-ios-agent-learning-proposals-v1"

  private let defaults: UserDefaults
  private let key: String
  private let lock = NSRecursiveLock()

  init(defaults: UserDefaults = .standard, key: String = UserDefaultsAgentLearningProposalStore.defaultKey) {
    self.defaults = defaults
    self.key = key
  }

  func loadProposals() -> [AgentLearningProposal] {
    locked {
      let raw = defaults.string(forKey: key) ?? "[]"
      return Array(AgentLearningProposalJSONCodec.decode(raw).prefix(AgentLearningEngine.maxProposals))
    }
  }

  func saveProposals(_ proposals: [AgentLearningProposal]) {
    locked {
      defaults.set(AgentLearningProposalJSONCodec.encode(proposals), forKey: key)
    }
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: key)
    }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

final class UserDefaultsAgentSkillStore: AgentSkillStore {
  static let defaultKey = "signalasi-ios-agent-skills-v1"

  private let defaults: UserDefaults
  private let secrets: SignalASISecretStore
  private let key: String
  private let encryptedKey: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentSkillStore.defaultKey,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.encryptedKey = "\(key)-encrypted-v2"
  }

  func list() -> [AgentSkillInstallation] {
    locked {
      AgentSkillStoreCodec.decode(loadDocument())
    }
  }

  func upsert(_ installation: AgentSkillInstallation) {
    locked {
      let current = list().filter { !($0.id == installation.id && $0.version == installation.version) }
      saveDocument(AgentSkillStoreCodec.encode(current + [installation]))
    }
  }

  func replaceAll(_ installations: [AgentSkillInstallation]) {
    locked {
      saveDocument(AgentSkillStoreCodec.encode(installations))
    }
  }

  func delete(id: String, version: String) -> Bool {
    locked {
      let current = list()
      let remaining = current.filter { installation in
        installation.id != id.trimmingCharacters(in: .whitespacesAndNewlines) ||
          installation.version != version.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard remaining.count != current.count else { return false }
      saveDocument(AgentSkillStoreCodec.encode(remaining))
      return true
    }
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: key)
      SignalASIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: encryptedKey,
        secrets: secrets
      )
    }
  }

  private func loadDocument() -> String {
    if let encrypted = SignalASIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    ), let document = String(data: encrypted, encoding: .utf8) {
      return document
    }
    let legacy = defaults.string(forKey: key) ?? AgentSkillStoreCodec.emptyDocument()
    if SignalASIEncryptedUserDefaultsStore.write(
      Data(legacy.utf8),
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    ) {
      defaults.removeObject(forKey: key)
    }
    return legacy
  }

  private func saveDocument(_ document: String) {
    if SignalASIEncryptedUserDefaultsStore.write(
      Data(document.utf8),
      defaults: defaults,
      key: encryptedKey,
      secrets: secrets
    ) {
      defaults.removeObject(forKey: key)
    }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

struct SignalASILearningSkillEvolutionView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var proposals: [AgentLearningProposal] = []
  @State private var selectedProposal: AgentLearningProposal?
  @State private var statusMessage = ""
  @State private var statusIsError = false

  private let proposalStore = UserDefaultsAgentLearningProposalStore()
  private let skillRuntime = AgentSkillRuntime(store: UserDefaultsAgentSkillStore())

  private var pendingProposals: [AgentLearningProposal] {
    proposals.filter { $0.status == .pending }
  }

  private var approvedProposals: [AgentLearningProposal] {
    proposals.filter { $0.status == .approved }
  }

  private var rejectedProposals: [AgentLearningProposal] {
    proposals.filter { $0.status == .rejected }
  }

  private var memoryCaptureBinding: Binding<Bool> {
    Binding(
      get: { store.agentSafetySettings.memoryCapture },
      set: { enabled in
        store.updateAgentSafetySettings { $0.memoryCapture = enabled }
      }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_learning_title", "Learning & Skill Evolution"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASILearningBanner(
            title: t("cc_learning_banner_title", "Learning stays under your control"),
            subtitle: t(
              "cc_learning_banner_subtitle",
              "Explicit preferences may become memory; generated Skills require review before activation"
            ),
            tint: pendingProposals.isEmpty ? .signalASIAccent : .purple
          )
          SignalASISecurityHeroView(
            title: t("cc_learning_overview_title", "Learning Workshop"),
            subtitle: t(
              "cc_learning_overview_subtitle",
              "Evidence from successful runs becomes reversible memory or a reviewed Skill proposal"
            ),
            systemImage: "sparkles.rectangle.stack",
            tint: .purple,
            badge: t("cc_learning_review", "Review")
          )
          SignalASILearningMetricStrip(metrics: learningMetrics)
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.learning.status_title", "Learning Status"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .orange : .signalASIAccent,
              badge: statusIsError ? t("cc_learning_review", "Review") : t("signalasi.status.ready", "Ready")
            )
          }
          proposalsSection
          policySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshProposals)
    .alert(
      selectedProposal?.title.ifBlank(t("signalasi.learning.proposal", "Learning proposal")) ??
        t("signalasi.learning.proposal", "Learning proposal"),
      isPresented: Binding(
        get: { selectedProposal != nil },
        set: { presented in
          if !presented { selectedProposal = nil }
        }
      )
    ) {
      Button(t("cc_learning_approve", "Approve Skill")) {
        if let proposal = selectedProposal {
          approve(proposal)
        }
        selectedProposal = nil
      }
      Button(t("cc_learning_reject", "Reject"), role: .destructive) {
        if let proposal = selectedProposal {
          reject(proposal)
        }
        selectedProposal = nil
      }
      Button(t("common_cancel", "Cancel"), role: .cancel) {
        selectedProposal = nil
      }
    } message: {
      if let proposal = selectedProposal {
        Text(
          String(
            format: t("cc_learning_dialog_message", "%@\n\nEvidence: %d successful runs"),
            proposal.summary.ifBlank(proposal.taskFamily),
            proposal.evidenceRunIds.count
          )
        )
      }
    }
  }

  private var learningMetrics: [SignalASILearningMetric] {
    [
      SignalASILearningMetric(
        value: "\(pendingProposals.count)",
        label: t("cc_learning_metric_pending", "Pending"),
        tint: .purple
      ),
      SignalASILearningMetric(
        value: "\(approvedProposals.count)",
        label: t("cc_learning_metric_approved", "Approved"),
        tint: .signalASIAccent
      ),
      SignalASILearningMetric(
        value: "\(rejectedProposals.count)",
        label: t("cc_learning_metric_rejected", "Rejected"),
        tint: .orange
      )
    ]
  }

  private var proposalsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_learning_section_proposals", "Skill Proposals"))
      if pendingProposals.isEmpty {
        SignalASISecurityStatusRow(
          title: t("cc_learning_no_proposals_title", "No proposal needs review"),
          subtitle: t(
            "cc_learning_no_proposals_subtitle",
            "SignalASI waits for repeated successful evidence instead of learning from one accidental result"
          ),
          systemImage: "sparkles.rectangle.stack",
          tint: .signalASIAccent,
          badge: t("signalasi.status.ready", "Ready")
        )
      } else {
        ForEach(pendingProposals) { proposal in
          SignalASISecurityActionRow(
            title: proposal.title,
            subtitle: String(
              format: t("cc_learning_evidence_subtitle", "Based on %d successful runs"),
              proposal.evidenceRunIds.count
            ),
            systemImage: "sparkles.rectangle.stack",
            tint: .purple,
            badge: t("cc_learning_review", "Review")
          ) {
            selectedProposal = proposal
          }
        }
      }
    }
  }

  private var policySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_learning_section_policy", "Learning Policy"))
      SignalASILearningToggleRow(
        title: t("cc_learning_memory_title", "Learn Explicit Preferences"),
        subtitle: t(
          "cc_learning_memory_subtitle",
          "Save stable, non-sensitive preferences when memory capture is enabled"
        ),
        systemImage: "brain.head.profile",
        tint: .signalASIAccent,
        badge: store.agentSafetySettings.memoryCapture ? t("signalasi.status.on", "On") : t("signalasi.status.off", "Off"),
        isOn: memoryCaptureBinding
      )
      SignalASISecurityStatusRow(
        title: t("cc_learning_review_policy_title", "Review Generated Skills"),
        subtitle: t(
          "cc_learning_review_policy_subtitle",
          "Automatic learning never activates a generated workflow without approval"
        ),
        systemImage: "checkmark.shield",
        tint: .blue,
        badge: t("cc_learning_review", "Review")
      )
    }
  }

  private func refreshProposals() {
    proposals = proposalStore.loadProposals()
  }

  private func approve(_ proposal: AgentLearningProposal) {
    guard let manifest = AgentSkillManifestCodec.decode(proposal.manifestJson) else {
      setStatus(t("cc_learning_action_failed", "The proposal could not be applied"), isError: true)
      return
    }
    do {
      _ = try skillRuntime.install(manifest, enabled: true)
      review(proposal, status: .approved)
      setStatus(t("cc_learning_approved", "Skill approved and enabled"), isError: false)
    } catch {
      setStatus(t("cc_learning_action_failed", "The proposal could not be applied"), isError: true)
    }
  }

  private func reject(_ proposal: AgentLearningProposal) {
    review(proposal, status: .rejected)
    setStatus(t("signalasi.learning.rejected_status", "Skill proposal rejected"), isError: false)
  }

  private func review(_ proposal: AgentLearningProposal, status: AgentLearningProposalStatus) {
    var current = proposalStore.loadProposals()
    guard let index = current.firstIndex(where: { $0.id == proposal.id && $0.status == .pending }) else {
      refreshProposals()
      return
    }
    current[index].status = status
    current[index].reviewedAtMillis = AgentMemoryClock.nowMillis()
    proposalStore.saveProposals(current)
    refreshProposals()
  }

  private func setStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASILearningBanner: View {
  var title: String
  var subtitle: String
  var tint: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: "sparkles")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(tint.opacity(0.09))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(tint.opacity(0.22), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASILearningMetric: Identifiable {
  var value: String
  var label: String
  var tint: Color

  var id: String { label }
}

private struct SignalASILearningMetricStrip: View {
  var metrics: [SignalASILearningMetric]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(metrics) { metric in
        VStack(alignment: .leading, spacing: 4) {
          Text(metric.value)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(metric.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          Text(metric.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }
}

private struct SignalASILearningToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .signalASIAccent))
        .frame(width: 52)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
