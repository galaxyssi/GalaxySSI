const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..", "..");

const requiredFiles = [
  "apps/ios/README.md",
  "apps/ios/SignalASI.xcodeproj/project.pbxproj",
  "apps/ios/SignalASI.xcodeproj/xcshareddata/xcschemes/SignalASI.xcscheme",
  "apps/ios/SignalASI/SignalASIModels.swift",
  "apps/ios/SignalASI/SignalASIContactExchange.swift",
  "apps/ios/SignalASI/SignalASIAttachments.swift",
  "apps/ios/SignalASI/SignalASILinkProtocol.swift",
  "apps/ios/SignalASI/SignalASILinkReliability.swift",
  "apps/ios/SignalASI/SignalASIBackup.swift",
  "apps/ios/SignalASI/SignalASIStore.swift",
  "apps/ios/SignalASI/SignalASIServices.swift",
  "apps/ios/SignalASI/SignalASIViews.swift",
  "apps/ios/SignalASITests/SignalASIAttachmentTests.swift",
  "apps/ios/SignalASITests/SignalASIContactExchangeTests.swift",
  "apps/ios/SignalASITests/SignalASILinkProtocolTests.swift",
  "apps/ios/SignalASITests/SignalASILinkReliabilityTests.swift",
  "apps/ios/SignalASITests/SignalASIBackupTests.swift",
  "apps/ios/SignalASITests/SignalASIStoreTests.swift",
];

function read(relativePath) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    throw new Error(`Missing required iOS file: ${relativePath}`);
  }
  return fs.readFileSync(absolutePath, "utf8");
}

for (const relativePath of requiredFiles) {
  read(relativePath);
}

const project = read("apps/ios/SignalASI.xcodeproj/project.pbxproj");
const readme = read("apps/ios/README.md");
const models = read("apps/ios/SignalASI/SignalASIModels.swift");
const contactExchange = read("apps/ios/SignalASI/SignalASIContactExchange.swift");
const attachments = read("apps/ios/SignalASI/SignalASIAttachments.swift");
const linkProtocol = read("apps/ios/SignalASI/SignalASILinkProtocol.swift");
const linkReliability = read("apps/ios/SignalASI/SignalASILinkReliability.swift");
const backup = read("apps/ios/SignalASI/SignalASIBackup.swift");
const store = read("apps/ios/SignalASI/SignalASIStore.swift");
const services = read("apps/ios/SignalASI/SignalASIServices.swift");
const views = read("apps/ios/SignalASI/SignalASIViews.swift");
const tests = [
  read("apps/ios/SignalASITests/SignalASIAttachmentTests.swift"),
  read("apps/ios/SignalASITests/SignalASIContactExchangeTests.swift"),
  read("apps/ios/SignalASITests/SignalASILinkProtocolTests.swift"),
  read("apps/ios/SignalASITests/SignalASILinkReliabilityTests.swift"),
  read("apps/ios/SignalASITests/SignalASIBackupTests.swift"),
  read("apps/ios/SignalASITests/SignalASIStoreTests.swift"),
].join("\n");

const requiredProjectSnippets = [
  "IPHONEOS_DEPLOYMENT_TARGET = 15.0",
  "PRODUCT_BUNDLE_IDENTIFIER = com.signalasi.chat.ios",
  "INFOPLIST_KEY_NSCameraUsageDescription",
  "INFOPLIST_KEY_NSMicrophoneUsageDescription",
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription",
  "SignalASIAttachments.swift in Sources",
  "SignalASIAttachmentTests.swift in Sources",
  "SignalASIContactExchange.swift in Sources",
  "SignalASIContactExchangeTests.swift in Sources",
  "SignalASITests.xctest",
  "SignalASIBackup.swift",
  "SignalASIBackupTests.swift",
];

const requiredSourceSnippets = [
  [readme, "iOS 15"],
  [readme, "Android-style app display text sizing"],
  [models, "static let androidParity"],
  [models, "SignalASIFriendRequest"],
  [models, "mqttInboxTopic"],
  [models, "CloudModelCredentialPolicy"],
  [models, "isAutoRoutableCredential"],
  [models, "var displayTitle"],
  [models, "LanguagePolicySettings"],
  [models, "voiceChoices"],
  [models, "modelLanguageName"],
  [models, "VoiceRoutingMode"],
  [models, "wakeThreshold"],
  [models, "defaultWelcomeText"],
  [models, "AppTextScaleMode"],
  [models, "extra_large"],
  [contactExchange, "signalasi_contact"],
  [contactExchange, "importContactQRCode"],
  [contactExchange, "makeContactQRText"],
  [attachments, "data_b64"],
  [attachments, "maximumInlineBytes = 320 * 1024"],
  [linkProtocol, "signalasi_pairing_ciphertext"],
  [linkProtocol, "signalasi.pairing-access/1.0"],
  [linkReliability, "SignalASIMqttWireChunking"],
  [linkReliability, "SignalASILinkDeliveryStore"],
  [linkReliability, "SignalASILinkDeliveryAckPolicy"],
  [backup, "static let iterations = 180_000"],
  [backup, "pbkdf2-hmac-sha256"],
  [backup, "aes-256-gcm"],
  [backup, "SignalASIBackupDocument"],
  [backup, "read_at_by_contact"],
  [backup, "language_policy"],
  [backup, "display_settings"],
  [backup, "includes_display_settings"],
  [store, "ContactConversationSummary"],
  [store, "readAtByContact"],
  [store, "languagePolicy"],
  [store, "displaySettings"],
  [store, "func updateLanguagePolicy"],
  [store, "func updateDisplaySettings"],
  [store, "func conversationSummary"],
  [store, "func markContactRead"],
  [store, "func renameContact"],
  [store, "func deleteContact"],
  [store, "func deleteMessage"],
  [store, "func destroyAllPrivateData"],
  [store, "func appendDeliveryTrace"],
  [store, "func visibleContacts(matching query"],
  [store, "func contactList(matching query"],
  [services, "CloudModelCredentialPolicy.isStoredCredential"],
  [services, "cloud_request"],
  [services, "cloud_reply"],
  [services, "cloud_error"],
  [services, "mqtt_published"],
  [services, "desktop_broker_ack"],
  [services, "systemPrompt(languagePolicy"],
  [services, "broker.emqx.io"],
  [services, "scheduleOutboxFlush"],
  [services, "UNUserNotificationCenter"],
  [services, "SFSpeechRecognizer"],
  [views, "PhotoLibraryPickerView"],
  [views, "MyContactQRCodeView"],
  [views, "FriendRequestDetailView"],
  [views, "ContactDetailView"],
  [views, "ResetPrivateDataView"],
  [views, "CloudModelProviderDetailView"],
  [views, "Delete Message"],
  [views, "Delete Chat?"],
  [views, "MessageDetailView"],
  [views, "Delivery Trace"],
  [views, "Security Status"],
  [views, "Search chats"],
  [views, "Search contacts"],
  [views, "No matching chats"],
  [views, "No matching contacts"],
  [views, "unread messages"],
  [views, "Model Response"],
  [views, "ASR locale"],
  [views, "Wake Words"],
  [views, "Wake Threshold"],
  [views, "Welcome Text"],
  [views, "Speak Replies"],
  [views, "Voice Routing"],
  [views, "Default Target"],
  [views, "Text Size"],
  [views, "signalASITextScale"],
  [views, "fileImporter"],
  [views, "AVCaptureMetadataOutput"],
  [tests, "testAttachmentDescriptorsMatchAndroidWireNames"],
  [tests, "testMyContactQRPayloadMatchesAndroidWireNames"],
  [tests, "testImportContactQRAddsPendingFriendRequest"],
  [tests, "testApprovingFriendRequestCreatesVerifiedContact"],
  [tests, "testContactSearchMatchesAndroidNameAndIdFiltering"],
  [views, "fileExporter"],
  [tests, "testValidatesAndroidCompatiblePairingQRCode"],
  [tests, "testChunkingRoundTripsLargeWirePayload"],
  [tests, "testPBKDF2SHA256MatchesKnownVector"],
  [tests, "testBackupRestoresCloudAPISecretsAndLocalState"],
  [tests, "testCloudModelContactsAreGroupedByProvider"],
  [tests, "testDeleteContactSoftDeletesAndOptionallyRemovesMessages"],
  [tests, "testDeleteMessageRemovesOnlyTargetMessage"],
  [tests, "testDeleteChatHistoryKeepsContact"],
  [tests, "testConversationSummaryTracksUnreadMessagesAndReadState"],
  [tests, "testLanguagePolicyNormalizesAndUpdatesVoiceLocale"],
  [tests, "testCloudSystemPromptUsesConfiguredResponseLanguage"],
  [tests, "testVoiceSettingsNormalizeAdvancedAndroidParityFields"],
  [tests, "testDisplaySettingsNormalizeAndroidTextScaleWireValues"],
  [tests, "testDeliveryTraceStageLabelsMatchAndroidActions"],
  [tests, "testMessageStatusUpdatesExposeReadableDeliveryTrace"],
  [tests, "testAppendDeliveryTraceUpdatesStatusAndKeepsPriorStages"],
  [tests, "testDestroyAllPrivateDataRegeneratesIdentityAndClearsSecrets"],
  [tests, "testSelectingCloudModelChangesProviderActiveModel"],
  [tests, "testDeletingSelectedCloudModelRemovesSecretAndFallsBack"],
  [tests, "testDeletingLastCloudModelHidesProviderContact"],
  [tests, "testCloudModelCredentialPolicyRejectsPlaceholders"],
];

for (const snippet of requiredProjectSnippets) {
  if (!project.includes(snippet)) {
    throw new Error(`iOS project is missing required setting: ${snippet}`);
  }
}

for (const [content, snippet] of requiredSourceSnippets) {
  if (!content.includes(snippet)) {
    throw new Error(`iOS source is missing required parity snippet: ${snippet}`);
  }
}

console.log("iOS project structure check passed.");
