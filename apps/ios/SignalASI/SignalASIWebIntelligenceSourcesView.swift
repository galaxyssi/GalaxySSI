import SwiftUI

struct SignalASIWebIntelligenceSourcesView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var selectedCredential: AgentIOSWebIntelligenceCredentialKey?
  @State private var credentialNotice: SignalASIWebCredentialNotice?
  @State private var credentialRefresh = 0

  private let credentials = AgentIOSWebIntelligenceCredentials()
  private let provider = AgentIOSURLSessionWebIntelligenceProvider()

  private var summary: AgentIOSWebIntelligenceSourceSummary {
    AgentIOSWebIntelligenceSourceCatalog.summary()
  }

  private var definitions: [AgentPhoneNativeToolDefinition] {
    AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
  }

  private var availableToolCount: Int {
    definitions.filter { $0.descriptor.availability.status == .available }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("web_sources_title", "Web intelligence sources"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          sourceCoverageSection
          credentialSection
          operationsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .id(credentialRefresh)
    .sheet(item: $selectedCredential) { credential in
      SignalASIWebCredentialEditorView(
        credential: credential,
        credentials: credentials
      ) { notice in
        credentialNotice = notice
        credentialRefresh += 1
      }
      .signalASIInterfaceLanguage(interfaceLanguage)
    }
  }

  private var hero: some View {
    SignalASISecurityHeroView(
      title: t("web_sources_hero_title", "SignalASI Web Intelligence"),
      subtitle: t(
        "web_sources_hero_subtitle",
        "Independent adapters with encrypted credentials and per-source health routing"
      ),
      systemImage: "network",
      tint: .signalASIAccent,
      badge: String(format: t("web_sources_count", "%d sources"), summary.sourceCount)
    )
  }

  private var sourceCoverageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("web_sources_title", "Web intelligence sources"))
      SignalASISecurityStatusRow(
        title: t("web_sources_domain_coverage", "Domain coverage"),
        subtitle: t(
          "web_sources_domain_coverage_subtitle",
          "Each domain has five to ten independently routed sources"
        ),
        systemImage: "square.grid.3x3",
        tint: .signalASIAccent,
        badge: String(
          format: t("web_sources_category_count", "%d categories"),
          summary.domainCategoryCount
        )
      )
      SignalASISecurityStatusRow(
        title: t("web_sources_learning", "Source learning"),
        subtitle: t(
          "web_sources_learning_subtitle",
          "New domains are promoted only after repeated independent evidence"
        ),
        systemImage: "arrow.triangle.branch",
        tint: .blue,
        badge: String(
          format: t("web_sources_learning_value", "%d verified / %d candidates"),
          summary.learningStats.verifiedLearnedSourceCount,
          summary.learningStats.candidateSourceCount
        )
      )
      SignalASISecurityStatusRow(
        title: t("web_sources_compatibility", "Wigolo source coverage"),
        subtitle: t(
          "web_sources_compatibility_subtitle",
          "All 18 public Wigolo adapters are available, plus SignalASI sources"
        ),
        systemImage: "checkmark.seal",
        tint: .signalASIAccent,
        badge: t("web_sources_compatibility_value", "18 / 18")
      )
      SignalASISecurityStatusRow(
        title: t("web_sources_catalog_breakdown", "Source catalog"),
        subtitle: t(
          "web_sources_catalog_breakdown_subtitle",
          "Android parity catalog with public engines and independently scoped indexed sources"
        ),
        systemImage: "tray.2",
        tint: .purple,
        badge: String(
          format: t("web_sources_catalog_breakdown_value", "%d + %d"),
          summary.baseSearchEngineCount,
          summary.indexedSourceCount
        )
      )
      SignalASISecurityStatusRow(
        title: t("web_sources_evidence_boundary", "Evidence boundary"),
        subtitle: t(
          "web_sources_evidence_boundary_subtitle",
          "Public web results stay untrusted until the selected model synthesizes them with citations"
        ),
        systemImage: "shield.lefthalf.filled",
        tint: .orange,
        badge: t("signalasi.status.protected", "Protected")
      )
    }
  }

  private var credentialSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("web_sources_credentials", "Source credentials"))
      ForEach(AgentIOSWebIntelligenceCredentialKey.allCases) { credential in
        SignalASISecurityActionRow(
          title: credentialTitle(credential),
          subtitle: credentialSubtitle(credential),
          systemImage: credential.systemImage,
          tint: credentials.configured(credential) ? .signalASIAccent : .orange,
          badge: webCredentialStatus(credentials.configured(credential))
        ) {
          selectedCredential = credential
        }
      }
      if let credentialNotice {
        SignalASIWebCredentialNoticeView(
          text: noticeText(credentialNotice),
          success: credentialNotice.success
        )
      }
    }
  }

  private var operationsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.advanced.web_operations", "Native Web Operations"))
      SignalASISecurityStatusRow(
        title: t("web_sources_native_pipeline", "Native invocation pipeline"),
        subtitle: t(
          "web_sources_native_pipeline_subtitle",
          "Search, fetch, crawl, extract, research, diff, cache, similar-source, and watch operations"
        ),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: availableToolCount == definitions.count ? .signalASIAccent : .orange,
        badge: String(
          format: t("web_sources_native_pipeline_value", "%d / %d available"),
          availableToolCount,
          definitions.count
        )
      )
      ForEach(definitions) { definition in
        let descriptor = definition.descriptor
        SignalASISecurityStatusRow(
          title: descriptor.title,
          subtitle: descriptor.description,
          systemImage: systemImage(for: descriptor.id),
          tint: tint(for: descriptor.availability.status),
          badge: statusLabel(descriptor.availability.status)
        )
      }
    }
  }

  private func credentialTitle(_ key: AgentIOSWebIntelligenceCredentialKey) -> String {
    t(key.titleKey, key.titleFallback)
  }

  private func credentialSubtitle(_ key: AgentIOSWebIntelligenceCredentialKey) -> String {
    t(key.subtitleKey, key.subtitleFallback)
  }

  private func webCredentialStatus(_ configured: Bool) -> String {
    t(
      configured ? "web_sources_configured" : "web_sources_not_configured",
      configured ? "Configured" : "Not configured"
    )
  }

  private func noticeText(_ notice: SignalASIWebCredentialNotice) -> String {
    switch notice.kind {
    case .saved:
      return t("web_sources_saved", "Source credential saved")
    case .cleared:
      return t("web_sources_cleared", "Source credential removed")
    case .failed:
      return notice.message
    }
  }

  private func systemImage(for id: String) -> String {
    if id.contains("search") { return "magnifyingglass" }
    if id.contains("fetch") || id.contains("extract") { return "doc.text.magnifyingglass" }
    if id.contains("crawl") || id.contains("research") || id.contains("agent") { return "globe" }
    if id.contains("cache") { return "externaldrive" }
    if id.contains("diff") || id.contains("watch") { return "eye" }
    return "network"
  }

  private func tint(for status: AgentNativeToolAvailabilityStatus) -> Color {
    switch status {
    case .available:
      return .signalASIAccent
    case .requiresSetup:
      return .orange
    case .unavailable:
      return .red
    }
  }

  private func statusLabel(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available:
      return t("signalasi.status.available", "Available")
    case .requiresSetup:
      return t("signalasi.status.needs_setup", "Needs Setup")
    case .unavailable:
      return t("signalasi.status.unavailable", "Unavailable")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIWebCredentialEditorView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  var credential: AgentIOSWebIntelligenceCredentialKey
  var credentials: AgentIOSWebIntelligenceCredentials
  var onChange: (SignalASIWebCredentialNotice) -> Void
  @State private var value = ""
  @State private var errorText = ""

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: title,
        leading: {
          Button {
            presentationMode.wrappedValue.dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: title,
            subtitle: subtitle,
            systemImage: credential.systemImage,
            tint: configured ? .signalASIAccent : .orange,
            badge: configured ? t("web_sources_configured", "Configured") : t("web_sources_not_configured", "Not configured")
          )
          SignalASISecuritySectionTitle(title: t("web_sources_credentials", "Source credentials"))
          SignalASIWebCredentialInputRow(
            title: title,
            placeholder: t("web_sources_secret_hint", "Enter a new value, or use Clear to remove the saved credential"),
            text: $value
          )
          if !errorText.isEmpty {
            Text(errorText)
              .font(.system(size: 13))
              .foregroundColor(.red)
              .padding(.horizontal, 4)
          }
          SignalASISecurityPrimaryButton(
            title: t("common_save", "Save"),
            systemImage: "checkmark",
            tint: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .signalASITextSecondary : .signalASIAccent
          ) {
            save()
          }
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          SignalASISecurityActionRow(
            title: t("web_sources_clear", "Clear"),
            subtitle: t("web_sources_clear_subtitle", "Remove the saved credential from this device"),
            systemImage: "trash",
            tint: .red,
            badge: configured ? t("web_sources_configured", "Configured") : t("web_sources_not_configured", "Not configured")
          ) {
            clear()
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var title: String {
    t(credential.titleKey, credential.titleFallback)
  }

  private var subtitle: String {
    t(credential.subtitleKey, credential.subtitleFallback)
  }

  private var configured: Bool {
    credentials.configured(credential)
  }

  private func save() {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    do {
      try credentials.setCredential(credential, value: clean)
      onChange(SignalASIWebCredentialNotice(kind: .saved))
      presentationMode.wrappedValue.dismiss()
    } catch {
      let message = error.localizedDescription
      errorText = message
      onChange(SignalASIWebCredentialNotice(kind: .failed, message: message))
    }
  }

  private func clear() {
    do {
      try credentials.setCredential(credential, value: "")
      value = ""
      onChange(SignalASIWebCredentialNotice(kind: .cleared))
      presentationMode.wrappedValue.dismiss()
    } catch {
      let message = error.localizedDescription
      errorText = message
      onChange(SignalASIWebCredentialNotice(kind: .failed, message: message))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIWebCredentialInputRow: View {
  var title: String
  var placeholder: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      SecureField(placeholder, text: $text)
        .font(.system(size: 15))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Color.signalASISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text(placeholder)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIWebCredentialNotice: Equatable {
  enum Kind: Equatable {
    case saved
    case cleared
    case failed
  }

  var kind: Kind
  var message: String = ""

  var success: Bool {
    kind != .failed
  }
}

private struct SignalASIWebCredentialNoticeView: View {
  var text: String
  var success: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundColor(success ? .signalASIAccent : .red)
      Text(text)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(10)
    .background((success ? Color.signalASIAccent : Color.red).opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
