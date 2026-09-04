import SwiftUI

struct GalaxySSINativeToolCatalogView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  private var tools: [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors()
      .sorted {
        if $0.location != $1.location {
          return locationOrder($0.location) < locationOrder($1.location)
        }
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
  }

  private var availableCount: Int {
    tools.filter { effectiveStatus($0) == .available }.count
  }

  private var highRiskCount: Int {
    tools.filter { $0.risk == .high }.count
  }

  private var groupedTools: [NativeToolLocationGroup] {
    AgentNativeToolLocation.allCases
      .sorted { locationOrder($0) < locationOrder($1) }
      .compactMap { location in
        let items = tools.filter { $0.location == location }
        return items.isEmpty ? nil : NativeToolLocationGroup(location: location, tools: items)
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.native_tool_catalog.title", "Native Tools"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          NativeToolCatalogHeroView(
            title: t("galaxyssi.native_tool_catalog.hero_title", "Phone native tool catalog"),
            subtitle: t(
              "galaxyssi.native_tool_catalog.hero_subtitle",
              "Review iOS tool availability, risk, runtime scope, permissions, and consent boundaries"
            ),
            metrics: [
              NativeToolMetric(
                value: "\(tools.count)",
                label: t("galaxyssi.native_tool_catalog.metric_tools", "Native tools")
              ),
              NativeToolMetric(
                value: "\(availableCount)",
                label: t("galaxyssi.native_tool_catalog.metric_available", "Available")
              ),
              NativeToolMetric(
                value: "\(highRiskCount)",
                label: t("galaxyssi.native_tool_catalog.metric_high_risk", "High risk")
              )
            ]
          )

          ForEach(groupedTools) { group in
            sectionTitle(locationLabel(group.location))
            VStack(spacing: 8) {
              ForEach(group.tools) { tool in
                NavigationLink(destination: GalaxySSINativeToolDetailView(tool: tool)) {
                  NativeToolCatalogRow(
                    tool: tool,
                    subtitle: tool.description,
                    icon: locationIcon(tool.location),
                    status: statusLabel(effectiveStatus(tool)),
                    statusTint: statusTint(effectiveStatus(tool), risk: tool.risk),
                    risk: riskLabel(tool.risk),
                    riskTint: riskTint(tool.risk)
                  )
                }
                .buttonStyle(.plain)
              }
            }
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

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func locationLabel(_ location: AgentNativeToolLocation) -> String {
    switch location {
    case .phone: return t("galaxyssi.native_tool_catalog.location_phone", "Phone")
    case .desktop: return t("galaxyssi.native_tool_catalog.location_desktop", "Desktop")
    case .application: return t("galaxyssi.native_tool_catalog.location_application", "Application")
    case .androidSystem: return t("galaxyssi.native_tool_catalog.location_ios_system", "iOS System")
    case .accessibilityService: return t("galaxyssi.native_tool_catalog.location_accessibility", "Accessibility")
    case .unknown: return t("galaxyssi.native_tool_catalog.location_other", "Other")
    }
  }

  private func riskLabel(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low: return t("galaxyssi.native_tool_catalog.risk_low", "Low")
    case .medium: return t("galaxyssi.native_tool_catalog.risk_medium", "Medium")
    case .high: return t("galaxyssi.native_tool_catalog.risk_high", "High")
    case .blocked: return t("galaxyssi.native_tool_catalog.risk_blocked", "Blocked")
    }
  }

  private func statusLabel(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available: return t("galaxyssi.native_tool_catalog.status_available", "Available")
    case .requiresSetup: return t("galaxyssi.native_tool_catalog.status_requires_setup", "Set up")
    case .unavailable: return t("galaxyssi.native_tool_catalog.status_unavailable", "Unavailable")
    }
  }
}

struct GalaxySSINativeToolDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var tool: AgentNativeToolDescriptor

  private var availabilityStatus: AgentNativeToolAvailabilityStatus {
    effectiveStatus(tool)
  }

  private var inputFields: [String] {
    schemaFields(tool.inputSchema)
  }

  private var outputFields: [String] {
    schemaFields(tool.outputSchema)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: tool.title,
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          NativeToolDetailHeroView(
            tool: tool,
            icon: locationIcon(tool.location),
            location: locationLabel(tool.location),
            risk: riskLabel(tool.risk),
            riskTint: riskTint(tool.risk),
            status: statusLabel(availabilityStatus),
            statusTint: statusTint(availabilityStatus, risk: tool.risk)
          )

          sectionTitle(t("galaxyssi.native_tool_catalog.section_details", "Details"))
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.tool_id", "Tool ID"),
            value: tool.id,
            systemImage: "link",
            tint: .galaxySSIInsightText,
            badge: "v\(tool.version)"
          )
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.run_scope", "Run scope"),
            value: locationLabel(tool.location),
            systemImage: "iphone",
            tint: .galaxySSIAccent,
            badge: ""
          )
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.permissions", "Permissions"),
            value: String(
              format: t("galaxyssi.native_tool_catalog.permission_count", "%d permissions / %d consents"),
              tool.requiredPermissions.count,
              tool.requiredConsents.count
            ),
            systemImage: "shield",
            tint: riskTint(tool.risk),
            badge: riskLabel(tool.risk)
          )
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.status", "Status"),
            value: tool.availability.reason.ifBlank(t("galaxyssi.native_tool_catalog.status_ready", "Ready for registered execution")),
            systemImage: "info.circle",
            tint: statusTint(availabilityStatus, risk: tool.risk),
            badge: statusLabel(availabilityStatus)
          )
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.execution_budget", "Execution budget"),
            value: String(
              format: t("galaxyssi.native_tool_catalog.timeout_value", "%@ timeout / %@"),
              duration(tool.timeoutMillis),
              idempotencyLabel(tool.idempotency)
            ),
            systemImage: "timer",
            tint: .blue,
            badge: ""
          )

          sectionTitle(t("galaxyssi.native_tool_catalog.section_capabilities", "Capabilities"))
          if tool.capabilities.isEmpty {
            NativeToolInfoRow(
              title: t("galaxyssi.native_tool_catalog.no_capabilities", "No declared capabilities"),
              value: t("galaxyssi.native_tool_catalog.no_capabilities_subtitle", "This tool is exposed by registry scope rather than a phone capability boundary."),
              systemImage: "square.grid.2x2",
              tint: .galaxySSITextSecondary,
              badge: ""
            )
          } else {
            NativeToolChipCloud(items: tool.capabilities.sorted())
          }

          sectionTitle(t("galaxyssi.native_tool_catalog.section_requirements", "Requirements"))
          requirementRows(
            permissions: tool.requiredPermissions,
            consents: tool.requiredConsents
          )

          sectionTitle(t("galaxyssi.native_tool_catalog.section_schema", "Schemas"))
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.input_schema", "Input schema"),
            value: schemaSummary(inputFields),
            systemImage: "tray.and.arrow.down",
            tint: .blue,
            badge: "\(inputFields.count)"
          )
          NativeToolInfoRow(
            title: t("galaxyssi.native_tool_catalog.output_schema", "Output schema"),
            value: schemaSummary(outputFields),
            systemImage: "tray.and.arrow.up",
            tint: .galaxySSIAccent,
            badge: "\(outputFields.count)"
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  @ViewBuilder
  private func requirementRows(
    permissions: [AgentNativePermissionRequirement],
    consents: [AgentNativeConsentRequirement]
  ) -> some View {
    let visiblePermissions = permissions.filter { $0.required }
    let visibleConsents = consents.filter { $0.required }
    if visiblePermissions.isEmpty && visibleConsents.isEmpty {
      NativeToolInfoRow(
        title: t("galaxyssi.native_tool_catalog.no_requirements", "No extra requirements"),
        value: t("galaxyssi.native_tool_catalog.no_requirements_subtitle", "This tool can run inside the existing GalaxySSI policy boundary."),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: ""
      )
    } else {
      VStack(spacing: 8) {
        ForEach(visiblePermissions) { permission in
          NativeToolInfoRow(
            title: permission.title,
            value: permission.description.ifBlank(permission.id),
            systemImage: "lock",
            tint: .orange,
            badge: t("galaxyssi.native_tool_catalog.permission", "Permission")
          )
        }
        ForEach(visibleConsents) { consent in
          NativeToolInfoRow(
            title: consent.title,
            value: consent.description.ifBlank(consent.id),
            systemImage: "hand.raised",
            tint: .red,
            badge: t("galaxyssi.native_tool_catalog.consent", "Consent")
          )
        }
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func schemaSummary(_ fields: [String]) -> String {
    guard !fields.isEmpty else {
      return t("galaxyssi.native_tool_catalog.no_schema_fields", "No named fields")
    }
    let visible = fields.prefix(10).joined(separator: " / ")
    if fields.count <= 10 {
      return visible
    }
    return String(
      format: t("galaxyssi.native_tool_catalog.more_fields", "%@ / +%d more"),
      visible,
      fields.count - 10
    )
  }

  private func duration(_ millis: Int64) -> String {
    guard millis > 0 else { return "-" }
    if millis % 1_000 == 0 {
      return String(format: t("galaxyssi.native_tool_catalog.seconds_value", "%@s"), "\(millis / 1_000)")
    }
    return String(format: t("galaxyssi.native_tool_catalog.millis_value", "%@ms"), "\(millis)")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func locationLabel(_ location: AgentNativeToolLocation) -> String {
    switch location {
    case .phone: return t("galaxyssi.native_tool_catalog.location_phone", "Phone")
    case .desktop: return t("galaxyssi.native_tool_catalog.location_desktop", "Desktop")
    case .application: return t("galaxyssi.native_tool_catalog.location_application", "Application")
    case .androidSystem: return t("galaxyssi.native_tool_catalog.location_ios_system", "iOS System")
    case .accessibilityService: return t("galaxyssi.native_tool_catalog.location_accessibility", "Accessibility")
    case .unknown: return t("galaxyssi.native_tool_catalog.location_other", "Other")
    }
  }

  private func riskLabel(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low: return t("galaxyssi.native_tool_catalog.risk_low", "Low")
    case .medium: return t("galaxyssi.native_tool_catalog.risk_medium", "Medium")
    case .high: return t("galaxyssi.native_tool_catalog.risk_high", "High")
    case .blocked: return t("galaxyssi.native_tool_catalog.risk_blocked", "Blocked")
    }
  }

  private func statusLabel(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available: return t("galaxyssi.native_tool_catalog.status_available", "Available")
    case .requiresSetup: return t("galaxyssi.native_tool_catalog.status_requires_setup", "Set up")
    case .unavailable: return t("galaxyssi.native_tool_catalog.status_unavailable", "Unavailable")
    }
  }

  private func idempotencyLabel(_ value: AgentNativeToolIdempotency) -> String {
    switch value {
    case .nonIdempotent: return t("galaxyssi.native_tool_catalog.idempotency_non", "non-idempotent")
    case .idempotent: return t("galaxyssi.native_tool_catalog.idempotency_yes", "idempotent")
    case .idempotencyKeyRequired: return t("galaxyssi.native_tool_catalog.idempotency_key", "idempotency key required")
    }
  }
}

private struct NativeToolMetric: Identifiable {
  var id: String { label }
  var value: String
  var label: String
}

private struct NativeToolLocationGroup: Identifiable {
  var id: String { location.rawValue }
  var location: AgentNativeToolLocation
  var tools: [AgentNativeToolDescriptor]
}

private struct NativeToolCatalogHeroView: View {
  var title: String
  var subtitle: String
  var metrics: [NativeToolMetric]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.galaxySSIAccent.opacity(0.14))
          Image(systemName: "cpu")
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
        }
        .frame(width: 52, height: 52)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
          Text(subtitle)
            .font(.system(size: 14))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack(spacing: 8) {
        ForEach(metrics) { metric in
          VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
              .font(.system(size: 17, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .monospacedDigit()
            Text(metric.label)
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(2)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
          .padding(.horizontal, 10)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct NativeToolCatalogRow: View {
  var tool: AgentNativeToolDescriptor
  var subtitle: String
  var icon: String
  var status: String
  var statusTint: Color
  var risk: String
  var riskTint: Color

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(statusTint.opacity(0.14))
        Image(systemName: icon)
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(statusTint)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 4) {
        Text(tool.title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 4) {
        Text(status)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(statusTint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(risk)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(riskTint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .frame(width: 72, alignment: .trailing)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct NativeToolDetailHeroView: View {
  var tool: AgentNativeToolDescriptor
  var icon: String
  var location: String
  var risk: String
  var riskTint: Color
  var status: String
  var statusTint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(statusTint.opacity(0.14))
          Image(systemName: icon)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(statusTint)
        }
        .frame(width: 52, height: 52)
        VStack(alignment: .leading, spacing: 4) {
          Text(tool.title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
          Text(tool.description)
            .font(.system(size: 14))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        NativeToolBadge(title: risk, tint: riskTint)
        NativeToolBadge(title: location, tint: .blue)
        NativeToolBadge(title: status, tint: statusTint)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct NativeToolInfoRow: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.14))
        Image(systemName: systemImage)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(value.ifBlank("-"))
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.horizontal, 8)
          .frame(minHeight: 26)
          .background(tint.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct NativeToolChipCloud: View {
  var items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(items, id: \.self) { item in
        HStack(spacing: 8) {
          Image(systemName: "square.grid.2x2")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
          Text(item)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }
}

private struct NativeToolBadge: View {
  var title: String
  var tint: Color

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .bold))
      .foregroundColor(tint)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 8)
      .frame(minHeight: 26)
      .background(tint.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private func effectiveStatus(_ tool: AgentNativeToolDescriptor) -> AgentNativeToolAvailabilityStatus {
  tool.risk == .blocked ? .unavailable : tool.availability.status
}

private func schemaFields(_ schema: AgentMcpJSONObject) -> [String] {
  schema["properties"]?.objectValue?.keys.sorted() ?? []
}

private func locationOrder(_ location: AgentNativeToolLocation) -> Int {
  switch location {
  case .phone: return 0
  case .application: return 1
  case .androidSystem: return 2
  case .accessibilityService: return 3
  case .desktop: return 4
  case .unknown: return 5
  }
}

private func locationIcon(_ location: AgentNativeToolLocation) -> String {
  switch location {
  case .phone: return "iphone"
  case .desktop: return "desktopcomputer"
  case .application: return "app.badge"
  case .androidSystem: return "gearshape.2"
  case .accessibilityService: return "hand.tap"
  case .unknown: return "questionmark.circle"
  }
}

private func riskTint(_ risk: AgentNativeToolRisk) -> Color {
  switch risk {
  case .low: return .galaxySSIAccent
  case .medium: return .orange
  case .high: return .red
  case .blocked: return .galaxySSITextSecondary
  }
}

private func statusTint(_ status: AgentNativeToolAvailabilityStatus, risk: AgentNativeToolRisk) -> Color {
  if risk == .blocked {
    return .galaxySSITextSecondary
  }
  switch status {
  case .available: return .galaxySSIAccent
  case .requiresSetup: return .orange
  case .unavailable: return .galaxySSITextSecondary
  }
}
