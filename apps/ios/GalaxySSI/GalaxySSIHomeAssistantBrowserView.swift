import Foundation
import SwiftUI

enum GalaxySSIHomeAssistantCollection {
  case entities
  case automations

  var titleKey: String {
    switch self {
    case .entities: return "cc_home_entities_title"
    case .automations: return "cc_home_automations_title"
    }
  }

  var titleFallback: String {
    switch self {
    case .entities: return "Entities & Rooms"
    case .automations: return "Scenes & Automations"
    }
  }

  var subtitleKey: String {
    switch self {
    case .entities: return "cc_home_entities_subtitle"
    case .automations: return "cc_home_automations_subtitle"
    }
  }

  var subtitleFallback: String {
    switch self {
    case .entities: return "Browse lights, climate, media, sensors, and scenes"
    case .automations: return "Run approved Home Assistant workflows"
    }
  }

  var domains: [String] {
    switch self {
    case .entities: return []
    case .automations: return ["automation"]
    }
  }

  var systemImage: String {
    switch self {
    case .entities: return "square.grid.2x2"
    case .automations: return "sparkles"
    }
  }
}

struct GalaxySSIHomeAssistantBrowserView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  let collection: GalaxySSIHomeAssistantCollection

  @State private var isLoading = false
  @State private var loadGeneration = 0
  @State private var entities: [GalaxySSIHomeAssistantEntityRow] = []
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var totalMatched = 0
  @State private var truncated = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: title,
        leading: { GalaxySSIBackButton() },
        trailing: {
          Button(action: loadEntities) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(isLoading ? .galaxySSITextSecondary : .galaxySSITextPrimary)
          }
          .buttonStyle(.plain)
          .disabled(isLoading)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !store.homeAssistantSettings.configured {
            configureSection
          }
          stateSection
          entitiesSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      if entities.isEmpty && !isLoading {
        loadEntities()
      }
    }
  }

  private var hero: some View {
    GalaxySSISecurityHeroView(
      title: title,
      subtitle: t(collection.subtitleKey, collection.subtitleFallback),
      systemImage: collection.systemImage,
      tint: store.homeAssistantSettings.configured ? .galaxySSIAccent : .orange,
      badge: heroBadge
    )
    .padding(.horizontal, 4)
  }

  private var configureSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_home_assistant_title", "Home Assistant"))
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.common.configure", "Configure"),
        subtitle: t("cc_home_assistant_not_configured", "Configure a local URL and access token"),
        systemImage: "gearshape",
        tint: .orange,
        badge: t("galaxyssi.status.needs_setup", "Needs Setup")
      ) {
        HomeAssistantSettingsView()
      }
    }
  }

  @ViewBuilder
  private var stateSection: some View {
    if isLoading {
      GalaxySSISecurityStatusRow(
        title: t("cc_loading", "Loading..."),
        subtitle: t("cc_home_assistant_connected", "Configured and enabled; connectivity is checked when data is requested"),
        systemImage: "arrow.clockwise",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.refresh", "Refresh")
      )
    } else if statusIsError {
      GalaxySSISecurityStatusRow(
        title: t("cc_home_load_failed", "Could not load Home Assistant data"),
        subtitle: statusMessage.ifBlank(t("galaxyssi.status.needs_setup", "Needs Setup")),
        systemImage: "exclamationmark.triangle",
        tint: .orange,
        badge: t("galaxyssi.common.retry", "Retry")
      )
    } else if entities.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("cc_home_empty", "No matching Home Assistant items"),
        subtitle: statusMessage.ifBlank(t("cc_home_assistant_not_configured", "Configure a local URL and access token")),
        systemImage: "tray",
        tint: .galaxySSITextSecondary,
        badge: t("galaxyssi.common.status", "Status")
      )
    } else {
      GalaxySSISecurityStatusRow(
        title: title,
        subtitle: resultSummary,
        systemImage: "list.bullet",
        tint: .galaxySSIAccent,
        badge: truncated ? t("galaxyssi.common.truncated", "Truncated") : "\(entities.count)"
      )
    }
  }

  private var entitiesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: title)
      ForEach(entities) { entity in
        NavigationLink(
          destination: GalaxySSIHomeAssistantEntityDetailView(entityId: entity.entityId, initialEntity: entity)
        ) {
          GalaxySSISecurityRowContent(
            title: entity.friendlyName,
            subtitle: entity.entityId,
            systemImage: entity.systemImage,
            tint: entity.tint,
            badge: entity.state,
            monospacedSubtitle: true,
            showsDisclosure: true
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var title: String {
    t(collection.titleKey, collection.titleFallback)
  }

  private var heroBadge: String {
    if !store.homeAssistantSettings.credentialsConfigured {
      return t("cc_status_not_configured", "Not configured")
    }
    if store.homeAssistantSettings.configured {
      return t("status_enabled", "Enabled")
    }
    return t("galaxyssi.status.off", "Off")
  }

  private var resultSummary: String {
    let matched = max(totalMatched, entities.count)
    return String(
      format: t("cc_home_result_summary", "%d shown / %d matched"),
      entities.count,
      matched
    )
  }

  private func loadEntities() {
    let settings = store.homeAssistantSettings.normalized
    loadGeneration += 1
    let generation = loadGeneration

    guard settings.configured else {
      isLoading = false
      entities = []
      totalMatched = 0
      truncated = false
      statusIsError = true
      statusMessage = t("cc_home_assistant_not_configured", "Configure a local URL and access token")
      return
    }

    isLoading = true
    statusIsError = false
    statusMessage = ""

    let collection = self.collection
    DispatchQueue.global(qos: .userInitiated).async {
      let provider = AgentIOSConfiguredHomeAssistantToolProvider(settingsProvider: { settings })
      let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      let result = provider.listEntities(
        query: "",
        domains: collection.domains,
        limit: 80,
        nowMillis: now
      )
      let nextEntities = Self.parseEntities(result.output["entities"]?.arrayValue ?? [])
      let nextTotalMatched = Int(result.output["total_matched"]?.intValue ?? Int64(nextEntities.count))
      let nextTruncated = result.output["truncated"]?.boolValue ?? false
      let nextMessage = result.error?.message ?? result.message
      let nextIsError = !result.isSuccess

      DispatchQueue.main.async {
        guard generation == loadGeneration else { return }
        isLoading = false
        entities = nextIsError ? [] : nextEntities
        totalMatched = nextTotalMatched
        truncated = nextTruncated
        statusIsError = nextIsError
        statusMessage = nextMessage
      }
    }
  }

  private static func parseEntities(_ values: [AgentMcpJSONValue]) -> [GalaxySSIHomeAssistantEntityRow] {
    values.compactMap { value in
      guard let object = value.objectValue else { return nil }
      return GalaxySSIHomeAssistantEntityRow(object: object)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIHomeAssistantEntityDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  let entityId: String
  let initialEntity: GalaxySSIHomeAssistantEntityRow?

  @State private var isLoading = false
  @State private var loadGeneration = 0
  @State private var entity: GalaxySSIHomeAssistantEntityRow?
  @State private var statusMessage = ""
  @State private var statusIsError = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: currentEntity?.friendlyName ?? entityId,
        leading: { GalaxySSIBackButton() },
        trailing: {
          Button(action: loadEntity) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(isLoading ? .galaxySSITextSecondary : .galaxySSITextPrimary)
          }
          .buttonStyle(.plain)
          .disabled(isLoading)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          stateSection
          detailsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      if entity == nil {
        entity = initialEntity
      }
      if !isLoading {
        loadEntity()
      }
    }
  }

  private var hero: some View {
    let item = currentEntity
    return GalaxySSISecurityHeroView(
      title: item?.friendlyName ?? entityId,
      subtitle: entityId,
      systemImage: item?.systemImage ?? "house",
      tint: item?.tint ?? .galaxySSIAccent,
      badge: item?.state ?? t("cc_loading", "Loading...")
    )
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private var stateSection: some View {
    if isLoading {
      GalaxySSISecurityStatusRow(
        title: t("cc_loading", "Loading..."),
        subtitle: entityId,
        systemImage: "arrow.clockwise",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.refresh", "Refresh")
      )
    } else if statusIsError {
      GalaxySSISecurityStatusRow(
        title: t("cc_home_load_failed", "Could not load Home Assistant data"),
        subtitle: statusMessage.ifBlank(entityId),
        systemImage: "exclamationmark.triangle",
        tint: .orange,
        badge: t("galaxyssi.common.retry", "Retry")
      )
    } else if let item = currentEntity {
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.common.status", "Status"),
        subtitle: String(format: t("cc_entity_state", "State: %@"), item.state),
        systemImage: "info.circle",
        tint: item.tint,
        badge: item.protected ? t("galaxyssi.status.protected", "Protected") : item.domain
      )
    }
  }

  private var detailsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("section_details", "Details"))
      ForEach(detailRows) { row in
        GalaxySSISecurityStatusRow(
          title: row.title,
          subtitle: row.subtitle,
          systemImage: row.systemImage,
          tint: row.tint,
          badge: row.badge,
          monospacedSubtitle: row.monospaced
        )
      }
    }
  }

  private var currentEntity: GalaxySSIHomeAssistantEntityRow? {
    entity ?? initialEntity
  }

  private var detailRows: [GalaxySSIHomeAssistantDetailRow] {
    guard let item = currentEntity else { return [] }
    return [
      GalaxySSIHomeAssistantDetailRow(
        title: t("galaxyssi.device.home_assistant_default_entity", "Default Entity"),
        subtitle: item.entityId,
        systemImage: "number",
        tint: .galaxySSIAccent,
        badge: item.domain,
        monospaced: true
      ),
      GalaxySSIHomeAssistantDetailRow(
        title: t("galaxyssi.common.status", "Status"),
        subtitle: item.state,
        systemImage: "info.circle",
        tint: item.tint,
        badge: item.protected ? t("galaxyssi.status.protected", "Protected") : item.domain
      ),
      GalaxySSIHomeAssistantDetailRow(
        title: t("galaxyssi.common.type", "Type"),
        subtitle: item.domain,
        systemImage: item.systemImage,
        tint: item.tint,
        badge: item.protected ? t("galaxyssi.status.protected", "Protected") : ""
      )
    ]
  }

  private func loadEntity() {
    let settings = store.homeAssistantSettings.normalized
    loadGeneration += 1
    let generation = loadGeneration

    guard settings.configured else {
      isLoading = false
      statusIsError = true
      statusMessage = t("cc_home_assistant_not_configured", "Configure a local URL and access token")
      return
    }

    isLoading = true
    statusIsError = false
    statusMessage = ""
    let targetEntityId = entityId

    DispatchQueue.global(qos: .userInitiated).async {
      let provider = AgentIOSConfiguredHomeAssistantToolProvider(settingsProvider: { settings })
      let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      let result = provider.readEntity(entityId: targetEntityId, nowMillis: now)
      let nextEntity = result.output["entity"]?.objectValue.flatMap(GalaxySSIHomeAssistantEntityRow.init)
      let nextMessage = result.error?.message ?? result.message
      let nextIsError = !result.isSuccess

      DispatchQueue.main.async {
        guard generation == loadGeneration else { return }
        isLoading = false
        if let nextEntity {
          entity = nextEntity
        }
        statusIsError = nextIsError
        statusMessage = nextMessage
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIHomeAssistantEntityRow: Identifiable, Equatable {
  var entityId: String
  var friendlyName: String
  var state: String
  var domain: String
  var protected: Bool

  var id: String { entityId }

  init?(object: AgentMcpJSONObject) {
    let entityId = object["entity_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !entityId.isEmpty else { return nil }
    self.entityId = entityId
    self.friendlyName = object["friendly_name"]?.stringValue?.ifBlank(entityId) ?? entityId
    self.state = object["state"]?.stringValue?.ifBlank("unknown") ?? "unknown"
    self.domain = object["domain"]?.stringValue?.ifBlank(entityId.split(separator: ".").first.map(String.init) ?? "unknown") ?? "unknown"
    self.protected = object["protected"]?.boolValue ?? false
  }

  var systemImage: String {
    switch domain {
    case "light": return "lightbulb"
    case "climate": return "thermometer"
    case "media_player": return "play.rectangle"
    case "sensor", "binary_sensor": return "waveform.path.ecg"
    case "automation": return "bolt"
    case "scene": return "sparkles"
    case "script": return "terminal"
    case "switch": return "power"
    case "lock": return "lock"
    default: return "house"
    }
  }

  var tint: Color {
    if state.lowercased() == "unavailable" {
      return .orange
    }
    if protected {
      return .red
    }
    switch domain {
    case "automation", "scene", "script":
      return .blue
    case "light", "switch":
      return .galaxySSIAccent
    default:
      return .galaxySSIInsightText
    }
  }
}

private struct GalaxySSIHomeAssistantDetailRow: Identifiable {
  var id: String { "\(title)-\(subtitle)" }
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospaced: Bool = false
}
