import XCTest
@testable import GalaxySSI

final class CloudModelRequestRoutingPolicyTests: XCTestCase {
  func testDeepSeekProfileExposesAllSupportedModels() {
    let profile = CloudModelRequestRoutingPolicy.invocationProfile(deepSeekContact())

    XCTAssertEqual(profile.models.map(\.id), [
      CloudModelRequestRoutingPolicy.deepSeekV4Pro,
      CloudModelRequestRoutingPolicy.deepSeekV4Flash,
      CloudModelRequestRoutingPolicy.deepSeekV4FlashVision
    ])
    XCTAssertEqual(profile.defaultModelId, CloudModelRequestRoutingPolicy.deepSeekV4Pro)
  }

  func testImageTurnTemporarilyUsesVisionWithoutChangingSavedContact() {
    let original = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let resolved = CloudModelRequestRoutingPolicy.resolve(
      contact: original,
      requestedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash,
      hasImageInput: true
    )

    XCTAssertEqual(resolved.selectedCloudModel?.modelId, CloudModelRequestRoutingPolicy.deepSeekV4FlashVision)
    XCTAssertEqual(resolved.selectedCloudModel?.keychainAccount, "deepseek-key")
    XCTAssertEqual(original.selectedCloudModelId, CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    XCTAssertEqual(original.cloudModels.count, 1)
  }

  func testTextTurnAndExplicitVisionSelectionRemainUnchanged() {
    let flash = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4Flash)
    let vision = deepSeekContact(selectedModelId: CloudModelRequestRoutingPolicy.deepSeekV4FlashVision)

    XCTAssertEqual(
      CloudModelRequestRoutingPolicy.resolve(
        contact: flash,
        requestedModelId: flash.selectedCloudModelId,
        hasImageInput: false
      ).selectedCloudModel?.modelId,
      CloudModelRequestRoutingPolicy.deepSeekV4Flash
    )
    XCTAssertEqual(
      CloudModelRequestRoutingPolicy.resolve(
        contact: vision,
        requestedModelId: vision.selectedCloudModelId,
        hasImageInput: true
      ).selectedCloudModel?.modelId,
      CloudModelRequestRoutingPolicy.deepSeekV4FlashVision
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
