import Foundation

@MainActor
enum AgentLocalSkillCommandRouter {
  struct Result {
    let text: String
    let actionId: String
  }

  static func handle(
    _ input: String,
    store: GalaxySSIStore,
    conversationId: String,
    runtime: AgentPhoneNativeToolRuntime?,
    runStore: AgentRecordedRunStoring
  ) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard AgentSkillCommandParser.isSaveCommand(command) || AgentSkillCommandParser.isUpgradeCommand(command) else {
      return nil
    }
    guard let runtime else {
      return failure(store, actionId: "skill_command", detail: "The iOS native tool runtime is not available.")
    }
    let language = LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage)
    let skillRuntime = AgentSkillRuntime(
      store: UserDefaultsAgentSkillStore(),
      availableNativeToolIds: Array(runtime.registry.ids())
    )
    let conversationRuns = runStore.runs(for: conversationId).filter { $0.status == .completed }

    do {
      let installation: AgentSkillInstallation
      if AgentSkillCommandParser.isUpgradeCommand(command) {
        guard let run = conversationRuns.reversed().first(where: { !$0.activeSkillId.isBlank }) else {
          return failure(
            store,
            actionId: "skill_upgrade",
            detail: localized(language, zh: "\u{627e}\u{4e0d}\u{5230}\u{53ef}\u{5347}\u{7ea7}\u{7684}\u{5df2}\u{8fd0}\u{884c} Skill\u{3002}", en: "No previously executed Skill is available to upgrade.")
          )
        }
        guard let base = skillRuntime.list(enabledOnly: true)
          .filter({ $0.id == run.activeSkillId })
          .max(by: { versionParts($0.version).lexicographicallyPrecedes(versionParts($1.version)) }) else {
          return failure(
            store,
            actionId: "skill_upgrade",
            detail: localized(language, zh: "\u{5f53}\u{524d}\u{4efb}\u{52a1}\u{4f7f}\u{7528}\u{7684} Skill \u{672a}\u{5b89}\u{88c5}\u{3002}", en: "The Skill used by the current task is not installed.")
          )
        }
        let evidence = Array(conversationRuns.filter { $0.activeSkillId == base.id }.suffix(AgentLearningEngine.maxEvidenceRuns))
        installation = try AgentSkillVersionManager(skillRuntime).upgrade(
          base: base,
          improvedRuns: evidence.isEmpty ? [run] : evidence
        )
      } else {
        guard !conversationRuns.isEmpty else {
          return failure(
            store,
            actionId: "skill_save",
            detail: localized(language, zh: "\u{8bf7}\u{5148}\u{5b8c}\u{6210}\u{4e00}\u{6b21} Agent \u{4efb}\u{52a1}\u{ff0c}\u{518d}\u{4fdd}\u{5b58}\u{4e3a} Skill\u{3002}", en: "Complete an Agent task before saving it as a Skill.")
          )
        }
        installation = try AgentConversationSkillCompiler(
          skillRuntime,
          availableTools: { runtime.registry.descriptors() }
        ).install(Array(conversationRuns.suffix(AgentLearningEngine.maxEvidenceRuns)))
      }
      return Result(
        text: localized(
          language,
          zh: "\u{5df2}\u{4fdd}\u{5b58} Skill\u{ff1a}" + installation.manifest.name + " " + installation.version,
          en: "Saved Skill: " + installation.manifest.name + " " + installation.version
        ),
        actionId: AgentSkillCommandParser.isUpgradeCommand(command) ? "skill_upgrade" : "skill_save"
      )
    } catch {
      return failure(
        store,
        actionId: AgentSkillCommandParser.isUpgradeCommand(command) ? "skill_upgrade" : "skill_save",
        detail: errorMessage(error)
      )
    }
  }

  private static func failure(_ store: GalaxySSIStore, actionId: String, detail: String) -> Result {
    let language = LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage)
    return Result(
      text: localized(language, zh: "Skill \u{64cd}\u{4f5c}\u{5931}\u{8d25}\u{ff1a}" + detail, en: "Skill operation failed: " + detail),
      actionId: actionId
    )
  }

  private static func localized(_ language: String, zh: String, en: String) -> String {
    language.lowercased().hasPrefix("zh") ? zh : en
  }

  private static func errorMessage(_ error: Error) -> String {
    if let validation = error as? AgentSkillValidationError {
      return validation.result.issues.map { $0.path + " [" + $0.code + "] " + $0.message }.joined(separator: "; ")
    }
    if let conflict = error as? AgentSkillConflictError {
      return "Skill " + conflict.id + "@" + conflict.version + " conflicts with installed content"
    }
    return error.localizedDescription.ifBlank(String(describing: error))
  }

  private static func versionParts(_ version: String) -> [Int] {
    version.split(separator: ".").map { Int(String($0.filter(\.isNumber))) ?? 0 }
  }
}
