import Foundation

extension GalaxySSIStore {
  func updateVoiceSettings(_ mutate: (inout VoiceSettings) -> Void) {
    var next = voiceSettings
    mutate(&next)
    voiceSettings = next.normalized
  }

  func updateLanguagePolicy(_ mutate: (inout LanguagePolicySettings) -> Void) {
    var next = languagePolicy
    mutate(&next)
    next = LanguagePolicySettings(
      interfaceLanguage: next.interfaceLanguage,
      responseLanguage: next.responseLanguage,
      asrLanguage: next.asrLanguage,
      ttsLanguage: next.ttsLanguage
    )
    languagePolicy = next
    if voiceSettings.preferredLocaleIdentifier != next.asrLocaleIdentifier {
      updateVoiceSettings {
        $0.preferredLocaleIdentifier = next.asrLocaleIdentifier
      }
    }
    let matchingVoice = LanguagePolicySettings.microsoftVoice(
      languageTag: next.ttsLanguage,
      configuredVoice: voiceSettings.microsoftVoice
    )
    if voiceSettings.microsoftVoice != matchingVoice {
      updateVoiceSettings {
        $0.microsoftVoice = matchingVoice
      }
    }
  }

  func updateDisplaySettings(_ mutate: (inout AppDisplaySettings) -> Void) {
    var next = displaySettings
    mutate(&next)
    displaySettings = AppDisplaySettings(textScale: next.textScale)
  }

  func updateAgentSafetySettings(_ mutate: (inout AgentSafetySettings) -> Void) {
    var next = agentSafetySettings
    mutate(&next)
    agentSafetySettings = next
  }

  func updateAgentPreferenceMode(_ mode: AgentPreferenceMode) {
    let profile = AgentPreferenceModePolicy.profile(mode)
    agentPreferenceMode = mode
    updateAgentSafetySettings {
      $0.taskExecutionMode = profile.taskExecutionMode
      $0.permissionMode = profile.permissionMode
      $0.highRiskGuard = profile.highRiskGuard
    }
  }

  func selectAgentTaskBudgetProfile(_ profile: AgentTaskBudgetProfile) {
    agentTaskBudget = AgentTaskBudget.forProfile(profile)
  }

  func updateAgentTaskBudget(_ mutate: (inout AgentTaskBudget) -> Void) {
    var next = agentTaskBudget
    mutate(&next)
    next.profile = .custom
    agentTaskBudget = next.normalized
  }



  func updateModelPlannerSettings(_ mutate: (inout AgentModelPlannerSettings) -> Void) {
    var next = modelPlannerSettings
    mutate(&next)
    modelPlannerSettings = next.normalized
  }

  func updateGlobalAgentSettings(_ mutate: (inout GlobalAgentSettings) -> Void) {
    var next = globalAgentSettings
    mutate(&next)
    globalAgentSettings = next.normalized
  }
}
