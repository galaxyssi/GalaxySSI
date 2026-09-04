import SwiftUI

struct GalaxySSIWebIntelligenceSourcesView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var selectedCredential: AgentIOSWebIntelligenceCredentialKey?
  @State private var credentialNotice: GalaxySSIWebCredentialNotice?
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
      GalaxySSITopBar(
        title: t("web_sources_title", "Web intelligence sources"),
        leading: {
          GalaxySSIBackButton()
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .id(credentialRefresh)
    .sheet(item: $selectedCredential) { credential in
      GalaxySSIWebCredentialEditorView(
        credential: credential,
        credentials: credentials
      ) { notice in
        credentialNotice = notice
        credentialRefresh += 1
      }
      .galaxySSIInterfaceLanguage(interfaceLanguage)
    }
  }

  private var hero: some View {
    GalaxySSISecurityHeroView(
      title: t("web_sources_hero_title", "GalaxySSI Web Intelligence"),
      subtitle: t(
        "web_sources_hero_subtitle",
        "Independent adapters with encrypted credentials and per-source health routing"
      ),
      systemImage: "network",
      tint: .galaxySSIAccent,
      badge: String(format: t("web_sources_count", "%d sources"), summary.sourceCount)
    )
  }

  private var sourceCoverageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("web_sources_title", "Web intelligence sources"))
      GalaxySSISecurityStatusRow(
        title: t("web_sources_domain_coverage", "Domain coverage"),
        subtitle: t(
          "web_sources_domain_coverage_subtitle",
          "Each domain has five to ten independently routed sources"
        ),
        systemImage: "square.grid.3x3",
        tint: .galaxySSIAccent,
        badge: String(
          format: t("web_sources_category_count", "%d categories"),
          summary.domainCategoryCount
        )
      )
      GalaxySSISecurityStatusRow(
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
      GalaxySSISecurityStatusRow(
        title: t("web_sources_compatibility", "Wigolo source coverage"),
        subtitle: t(
          "web_sources_compatibility_subtitle",
          "All 18 public Wigolo adapters are available, plus GalaxySSI sources"
        ),
        systemImage: "checkmark.seal",
        tint: .galaxySSIAccent,
        badge: t("web_sources_compatibility_value", "18 / 18")
      )
      GalaxySSISecurityStatusRow(
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
      GalaxySSISecurityStatusRow(
        title: t("web_sources_evidence_boundary", "Evidence boundary"),
        subtitle: t(
          "web_sources_evidence_boundary_subtitle",
          "Public web results stay untrusted until the selected model synthesizes them with citations"
        ),
        systemImage: "shield.lefthalf.filled",
        tint: .orange,
        badge: t("galaxyssi.status.protected", "Protected")
      )
    }
  }

  private var credentialSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("web_sources_credentials", "Source credentials"))
      ForEach(AgentIOSWebIntelligenceCredentialKey.allCases) { credential in
        GalaxySSISecurityActionRow(
          title: credentialTitle(credential),
          subtitle: credentialSubtitle(credential),
          systemImage: credential.systemImage,
          tint: credentials.configured(credential) ? .galaxySSIAccent : .orange,
          badge: webCredentialStatus(credentials.configured(credential))
        ) {
          selectedCredential = credential
        }
      }
      if let credentialNotice {
        GalaxySSIWebCredentialNoticeView(
          text: noticeText(credentialNotice),
          success: credentialNotice.success
        )
      }
    }
  }

  private var operationsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.advanced.web_operations", "Native Web Operations"))
      GalaxySSISecurityStatusRow(
        title: t("web_sources_native_pipeline", "Native invocation pipeline"),
        subtitle: t(
          "web_sources_native_pipeline_subtitle",
          "Search, fetch, crawl, extract, research, diff, cache, similar-source, and watch operations"
        ),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: availableToolCount == definitions.count ? .galaxySSIAccent : .orange,
        badge: String(
          format: t("web_sources_native_pipeline_value", "%d / %d available"),
          availableToolCount,
          definitions.count
        )
      )
      ForEach(definitions) { definition in
        let descriptor = definition.descriptor
        GalaxySSISecurityStatusRow(
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

  private func noticeText(_ notice: GalaxySSIWebCredentialNotice) -> String {
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
      return .galaxySSIAccent
    case .requiresSetup:
      return .orange
    case .unavailable:
      return .red
    }
  }

  private func statusLabel(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available:
      return t("galaxyssi.status.available", "Available")
    case .requiresSetup:
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    case .unavailable:
      return t("galaxyssi.status.unavailable", "Unavailable")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIWebCredentialEditorView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  var credential: AgentIOSWebIntelligenceCredentialKey
  var credentials: AgentIOSWebIntelligenceCredentials
  var onChange: (GalaxySSIWebCredentialNotice) -> Void
  @State private var value = ""
  @State private var errorText = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: title,
        leading: {
          Button {
            presentationMode.wrappedValue.dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: title,
            subtitle: subtitle,
            systemImage: credential.systemImage,
            tint: configured ? .galaxySSIAccent : .orange,
            badge: configured ? t("web_sources_configured", "Configured") : t("web_sources_not_configured", "Not configured")
          )
          GalaxySSISecuritySectionTitle(title: t("web_sources_credentials", "Source credentials"))
          GalaxySSIWebCredentialInputRow(
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
          GalaxySSISecurityPrimaryButton(
            title: t("common_save", "Save"),
            systemImage: "checkmark",
            tint: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .galaxySSITextSecondary : .galaxySSIAccent
          ) {
            save()
          }
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          GalaxySSISecurityActionRow(
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
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
      onChange(GalaxySSIWebCredentialNotice(kind: .saved))
      presentationMode.wrappedValue.dismiss()
    } catch {
      let message = error.localizedDescription
      errorText = message
      onChange(GalaxySSIWebCredentialNotice(kind: .failed, message: message))
    }
  }

  private func clear() {
    do {
      try credentials.setCredential(credential, value: "")
      value = ""
      onChange(GalaxySSIWebCredentialNotice(kind: .cleared))
      presentationMode.wrappedValue.dismiss()
    } catch {
      let message = error.localizedDescription
      errorText = message
      onChange(GalaxySSIWebCredentialNotice(kind: .failed, message: message))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIWebCredentialInputRow: View {
  var title: String
  var placeholder: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      SecureField(placeholder, text: $text)
        .font(.system(size: 15))
        .foregroundColor(.galaxySSITextPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Color.galaxySSISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text(placeholder)
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSIWebCredentialNotice: Equatable {
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

private struct GalaxySSIWebCredentialNoticeView: View {
  var text: String
  var success: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundColor(success ? .galaxySSIAccent : .red)
      Text(text)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(10)
    .background((success ? Color.galaxySSIAccent : Color.red).opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
