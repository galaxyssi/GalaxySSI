import XCTest
@testable import GalaxySSI

final class CloudModelRequestRoutingPolicyTests: XCTestCase {
  func testManualRetryUsesOriginalModelAndRejectsChangedRoute() throws {
    let original = deepSeekContact()
    let binding = try XCTUnwrap(AgentManualCloudBinding(contact: original, hadAttachments: false))
    let key = "sk-valid-credential-for-testing-4c918"
    var contact = original
    contact.selectedCloudModelId = CloudModelRequestRoutingPolicy.deepSeekV4Flash
    XCTAssertEqual(binding.resolve(contact: contact) { _ in key }?.selectedCloudModel?.modelId,
                   CloudModelRequestRoutingPolicy.deepSeekV4Pro)
    XCTAssertNil(binding.resolve(contact: contact) { _ in nil })
    contact.cloudModels[0].endpoint = "https://different.example/v1/chat/completions"
    XCTAssertNil(binding.resolve(contact: contact) { _ in key })
    var message = ChatMessage(contactId: "hermes", content: "test", isMine: true)
    message.manualCloudBinding = binding
    let encoded = try JSONEncoder().encode(message)
    XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: encoded).manualCloudBinding, binding)
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("api.deepseek.com"))
  }

  func testDeepSeekProfileExposesAllSupportedModels() {
    let profile = CloudModelRequestRoutingPolicy.invocationProfile(deepSeekContact())

    XCTAssertEqual(profile.models.map(\.id), [
      CloudModelRequestRoutingPolicy.deepSeekV4Pro,
      CloudModelRequestRoutingPolicy.deepSeekFlash
    ])
    XCTAssertEqual(profile.defaultModelId, CloudModelRequestRoutingPolicy.deepSeekV4Pro)
  }

  func testImageTurnUsesCurrentFlashWithoutChangingSavedContact() {
    let original = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let resolved = CloudModelRequestRoutingPolicy.resolve(
      contact: original,
      requestedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash,
      hasImageInput: true
    )

    XCTAssertEqual(resolved.selectedCloudModel?.modelId, CloudModelRequestRoutingPolicy.deepSeekFlash)
    XCTAssertEqual(resolved.selectedCloudModel?.keychainAccount, "deepseek-key")
    XCTAssertEqual(original.selectedCloudModelId, CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    XCTAssertEqual(original.cloudModels.count, 1)
  }

  func testLegacyFlashAndVisionSelectionsUseCurrentFlash() {
    let flash = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let vision = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4FlashVision)

    XCTAssertEqual(
      CloudModelRequestRoutingPolicy.resolve(
        contact: flash,
        requestedModelId: flash.selectedCloudModelId,
        hasImageInput: false
      ).selectedCloudModel?.modelId,
      CloudModelRequestRoutingPolicy.deepSeekFlash
    )
    XCTAssertEqual(
      CloudModelRequestRoutingPolicy.resolve(
        contact: vision,
        requestedModelId: vision.selectedCloudModelId,
        hasImageInput: true
      ).selectedCloudModel?.modelId,
      CloudModelRequestRoutingPolicy.deepSeekFlash
    )
  }

  func testOtherProvidersDoNotGainDeepSeekModels() {
    var contact = deepSeekContact(selectedModelId: "qwen3.7-max")
    contact.cloudProvider = "Qwen"
    contact.name = "Qwen"
    contact.displayName = "Qwen"
    contact.cloudModels[0].provider = "Qwen"
    contact.cloudModels[0].modelId = "qwen3.7-max"
    contact.cloudModels[0].endpoint = "https://dashscope.aliyuncs.com/compatible/v1/chat/completions"

    XCTAssertEqual(
      CloudModelRequestRoutingPolicy.models(for: contact).map(\.modelId),
      ["qwen3.7-max"]
    )
  }

  func testAdvertisedAliasesDecodeWithoutChangingUnknownChoicesOrEffort() throws {
    let json = #"{"default_model":"old","models":[{"id":"current","display_name":"Current"}],"reasoning_efforts":["high"],"model_aliases":{"old":"current","current":"other","dangling":"absent","cycle":"cycle"}}"#
    let profile = try JSONDecoder().decode(AgentInvocationProfile.self, from: Data(json.utf8))
    XCTAssertEqual(profile.modelAliases, ["old": "current"])
    XCTAssertEqual(profile.defaultModelId, "current")
    XCTAssertEqual(profile.normalizedModelId(" old "), "current")
    XCTAssertEqual(profile.canonicalModelId("unknown"), "unknown")
    XCTAssertEqual(profile.reasoningEfforts, [.high])
    let roundTrip = try JSONDecoder().decode(AgentInvocationProfile.self, from: JSONEncoder().encode(profile))
    XCTAssertEqual(roundTrip, profile)
    let legacy = try JSONDecoder().decode(AgentInvocationProfile.self, from: Data(#"{"models":[]}"#.utf8))
    XCTAssertEqual(legacy.modelAliases, [:])
  }

  func testCatalogProtocolsAndOpenRouterOnlyGPT62() {
    let presets = CloudModelPreset.androidParity
    XCTAssertEqual(presets.count, 21)
    XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    XCTAssertEqual(presets.filter { $0.provider == "DeepSeek" }.map(\.modelId),
      ["deepseek-v4-pro", "deepseek-flash"])
    for preset in presets where preset.provider == "Google Gemini" {
      XCTAssertEqual(preset.apiStyle, .gemini)
      XCTAssertEqual(preset.endpoint, "https://generativelanguage.googleapis.com/v1beta/models/\(preset.modelId):generateContent")
    }
    for preset in presets where preset.provider == "Anthropic" {
      XCTAssertEqual(preset.apiStyle, .anthropic)
      XCTAssertEqual(preset.endpoint, "https://api.anthropic.com/v1/messages")
    }
    let gpt62 = presets.filter { $0.modelId.contains("gpt-6.2") }
    XCTAssertEqual(gpt62.map(\.modelId), ["openai/gpt-6.2-astra", "openai/gpt-6.2-sol"])
    XCTAssertTrue(gpt62.allSatisfy { $0.provider == "OpenRouter" && $0.apiStyle == .openAICompatible })
  }

  func testOfficialProviderPresetsInheritOnlyCurrentRouteKey() {
    for provider in ["OpenAI", "Anthropic", "Google Gemini", "Qwen", "OpenRouter"] {
      let presets = CloudModelPreset.androidParity.filter { $0.provider == provider }
      var contact = deepSeekContact()
      contact.cloudProvider = provider
      contact.cloudModels[0].provider = provider
      contact.cloudModels[0].modelId = "saved-older-model"
      contact.selectedCloudModelId = "saved-older-model"
      contact.cloudModels[0].apiStyle = presets[0].apiStyle
      contact.cloudModels[0].endpoint = provider == "Google Gemini"
        ? "https://generativelanguage.googleapis.com/v1beta/models/saved-older-model:generateContent"
        : presets[0].endpoint
      let original = contact
      let resolved = CloudModelRequestRoutingPolicy.resolve(
        contact: contact, requestedModelId: presets[1].modelId, hasImageInput: false)
      XCTAssertEqual(resolved.selectedCloudModel?.endpoint, presets[1].endpoint)
      XCTAssertEqual(resolved.selectedCloudModel?.keychainAccount, "deepseek-key")
      XCTAssertEqual(CloudModelRequestRoutingPolicy.invocationProfile(contact).defaultModelId, "saved-older-model")
      XCTAssertEqual(contact, original)
      contact.cloudModels[0].endpoint = "https://gateway.example/v1/chat/completions"
      XCTAssertEqual(CloudModelRequestRoutingPolicy.models(for: contact), contact.cloudModels)
    }
  }

  func testLookalikeInsecureAndCustomDeepSeekRoutesAreNotRewritten() {
    for endpoint in ["http://api.deepseek.com/chat/completions",
      "https://api.deepseek.com.example.org/chat/completions",
      "https://api.deepseek.com:8443/chat/completions",
      "https://user@api.deepseek.com/chat/completions",
      "https://gateway.example/v1/chat/completions"] {
      var contact = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
      contact.cloudModels[0].endpoint = endpoint
      let result = CloudModelRequestRoutingPolicy.resolve(
        contact: contact, requestedModelId: contact.selectedCloudModelId, hasImageInput: true)
      XCTAssertEqual(result, contact)
      XCTAssertTrue(CloudModelRequestRoutingPolicy.invocationProfile(contact).modelAliases.isEmpty)
    }
  }

  func testFlashImageKeyPriorityAndLegacyKeysStayInKeychain() {
    var contact = deepSeekContact()
    var vision = contact.cloudModels[0]
    vision.id = "vision"
    vision.modelId = CloudModelRequestRoutingPolicy.deepSeekV4FlashVision
    vision.keychainAccount = "vision-key-account"
    contact.cloudModels.append(vision)
    var result = CloudModelRequestRoutingPolicy.resolve(
      contact: contact, requestedModelId: contact.selectedCloudModelId, hasImageInput: true)
    XCTAssertEqual(result.selectedCloudModel?.modelId, CloudModelRequestRoutingPolicy.deepSeekFlash)
    XCTAssertEqual(result.selectedCloudModel?.keychainAccount, "vision-key-account")
    var flash = vision
    flash.id = "flash"
    flash.modelId = CloudModelRequestRoutingPolicy.deepSeekFlash
    flash.keychainAccount = "current-key-account"
    contact.cloudModels.append(flash)
    result = CloudModelRequestRoutingPolicy.resolve(
      contact: contact, requestedModelId: contact.selectedCloudModelId, hasImageInput: true)
    XCTAssertEqual(result.selectedCloudModel?.keychainAccount, "current-key-account")
    XCTAssertEqual(contact.selectedCloudModelId, CloudModelRequestRoutingPolicy.deepSeekV4Pro)
    contact.cloudModels.removeLast()
    contact.cloudModels[1].endpoint = "https://proxy.example/chat/completions"
    result = CloudModelRequestRoutingPolicy.resolve(
      contact: contact, requestedModelId: contact.selectedCloudModelId, hasImageInput: true)
    XCTAssertEqual(result.selectedCloudModel?.keychainAccount, "deepseek-key")
  }

  func testGeminiMalformedPathAndQueryDoNotInheritPresetCredentials() {
    for endpoint in [
      "https://generativelanguage.googleapis.com/v1beta/models/other:generateContent",
      "https://generativelanguage.googleapis.com/v1beta/models/current:generateContent?key=unexpected",
      "https://generativelanguage.googleapis.com/v1beta/models/current:generateContent#fragment"
    ] {
      var contact = deepSeekContact(selectedModelId: "current")
      contact.cloudProvider = "Google Gemini"
      contact.cloudModels[0].apiStyle = .gemini
      contact.cloudModels[0].endpoint = endpoint
      XCTAssertEqual(CloudModelRequestRoutingPolicy.models(for: contact), contact.cloudModels)
    }
  }

  func testExplicitLegacyRequestKeepsItsOwnKeyAheadOfOtherLegacyKeys() {
    var contact = deepSeekContact()
    for (id, account) in [
      (CloudModelRequestRoutingPolicy.deepSeekV4Flash, "flash-account"),
      (CloudModelRequestRoutingPolicy.deepSeekV4FlashVision, "vision-account")
    ] {
      var model = contact.cloudModels[0]
      model.id = id
      model.modelId = id
      model.keychainAccount = account
      contact.cloudModels.append(model)
    }
    for (id, account) in [
      (CloudModelRequestRoutingPolicy.deepSeekV4Flash, "flash-account"),
      (CloudModelRequestRoutingPolicy.deepSeekV4FlashVision, "vision-account")
    ] {
      let resolved = CloudModelRequestRoutingPolicy.resolve(
        contact: contact, requestedModelId: id, hasImageInput: true)
      XCTAssertEqual(resolved.selectedCloudModel?.keychainAccount, account)
      XCTAssertEqual(resolved.selectedCloudModel?.modelId, CloudModelRequestRoutingPolicy.deepSeekFlash)
    }
  }

  func testHeaderShowsCanonicalCloudSelectionNotStaleSavedLabel() {
    let contact = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let selection = AgentModelSelection(mode: .manual, targetId: contact.id,
      modelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash, displayName: "Old Flash Vision")
    let header = GalaxySSIAgentHomeHeaderPresentation.make(session: nil, contact: contact,
      selection: selection, liveExecutionTargetLabel: nil, contacts: [contact], language: "en")
    XCTAssertEqual(header.modelStatusLabel, CloudModelRequestRoutingPolicy.deepSeekFlash)
    XCTAssertEqual(selection.modelId, CloudModelRequestRoutingPolicy.deepSeekV4Flash)
  }

  func testChangedLegacyRetryBindingRequiresFreshRouteApproval() throws {
    let original = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let binding = try XCTUnwrap(AgentManualCloudBinding(contact: original, hadAttachments: true))
    XCTAssertNil(binding.resolve(contact: original) { _ in "sk-valid-credential-for-testing-4c918" })
  }

  private func deepSeekContact(
    selectedModelId: String = CloudModelRequestRoutingPolicy.deepSeekV4Pro
  ) -> GalaxySSIContact {
    let model = CloudModelConfig(
      id: "deepseek:\(selectedModelId)",
      displayName: selectedModelId,
      provider: "DeepSeek",
      modelId: selectedModelId,
      endpoint: "https://api.deepseek.com/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "deepseek-key",
      updatedAt: Date(timeIntervalSince1970: 1)
    )
    return GalaxySSIContact(
      id: "cloud-deepseek",
      galaxySSIId: "cloud-deepseek",
      name: "DeepSeek",
      displayName: "DeepSeek",
      type: "agent",
      agentKind: "cloud-api",
      deliveryMode: .cloudAPI,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "ready",
      setupDetail: "",
      cloudProvider: "DeepSeek",
      cloudModels: [model],
      selectedCloudModelId: selectedModelId,
      deleted: false,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }
}
