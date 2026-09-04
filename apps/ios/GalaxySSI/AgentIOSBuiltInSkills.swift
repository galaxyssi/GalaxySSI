import Foundation

enum AgentIOSBuiltInSkills {
  static let statusEntries: [AgentSkillCatalogEntry] = [
    statusSkill(
      id: "galaxyssi.builtin.battery-health",
      title: "Battery health",
      summary: "Read the phone battery level, charging state, temperature, voltage, and health.",
      toolId: AgentIOSHardwareNativeToolCatalog.batteryStatus,
      triggers: [
        "Check my phone battery",
        "Show battery health",
        "\u{67E5}\u{770B}\u{624B}\u{673A}\u{7535}\u{91CF}",
        "\u{68C0}\u{67E5}\u{7535}\u{6C60}\u{5065}\u{5EB7}"
      ]
    ),
    statusSkill(
      id: "galaxyssi.builtin.network-status",
      title: "Network status",
      summary: "Inspect the phone's current app-visible network capabilities.",
      toolId: AgentIOSHardwareNativeToolCatalog.networkStatus,
      triggers: [
        "Check my phone network",
        "Show network status",
        "\u{67E5}\u{770B}\u{624B}\u{673A}\u{7F51}\u{7EDC}",
        "\u{68C0}\u{67E5}\u{7F51}\u{7EDC}\u{72B6}\u{6001}"
      ]
    ),
    statusSkill(
      id: "galaxyssi.builtin.storage-status",
      title: "Storage status",
      summary: "Read total and available phone storage visible to GalaxySSI.",
      toolId: AgentIOSHardwareNativeToolCatalog.storageStatus,
      triggers: [
        "Check phone storage",
        "Show free storage",
        "\u{67E5}\u{770B}\u{624B}\u{673A}\u{5B58}\u{50A8}",
        "\u{8FD8}\u{6709}\u{591A}\u{5C11}\u{5B58}\u{50A8}\u{7A7A}\u{95F4}"
      ]
    ),
    statusSkill(
      id: "galaxyssi.builtin.device-power",
      title: "Power status",
      summary: "Inspect screen, power-save, interactive, and idle state on this phone.",
      toolId: AgentIOSHardwareNativeToolCatalog.powerStatus,
      triggers: [
        "Check phone power state",
        "Show power saving status",
        "\u{67E5}\u{770B}\u{624B}\u{673A}\u{7535}\u{6E90}\u{72B6}\u{6001}",
        "\u{68C0}\u{67E5}\u{7701}\u{7535}\u{72B6}\u{6001}"
      ]
    )
  ]

  static let manifests: [AgentSkillManifest] = statusEntries.map(\.manifest)

  private static func statusSkill(
    id: String,
    title: String,
    summary: String,
    toolId: String,
    triggers: [String]
  ) -> AgentSkillCatalogEntry {
    let manifest = AgentSkillManifest(
      id: id,
      name: title,
      version: "1.0.0",
      summary: summary,
      instructions: "Read the current phone-local status with the declared native tool and render the complete structured result.",
      nativeTools: Set([toolId]),
      permissions: Set([toolId]),
      parameters: AgentSkillParameterSchema.objectSchema(
        properties: ["request": .string(maxLength: AgentSkillLimits.maxRequestCharacters)],
        required: []
      ),
      steps: [AgentSkillStep(id: "read", toolId: toolId)],
      source: "built_in",
      autoInvoke: false,
      triggerExamples: triggers,
      negativeExamples: ["Check desktop status", "Run a server diagnostic"],
      renderSpec: ["type": .string("key_value"), "title": .string(title)],
      tests: [AgentSkillTestCase(id: "registered_tool", expectedToolIds: Set([toolId]))]
    )
    return AgentSkillCatalogEntry(
      id: id,
      name: title,
      summary: summary,
      requiredNativeTools: Set([toolId]),
      requiredMcpCatalogIds: [],
      featured: true,
      manifest: manifest
    )
  }
}
