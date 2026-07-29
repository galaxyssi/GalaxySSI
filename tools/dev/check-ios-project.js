const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..", "..");

const requiredFiles = [
  "apps/ios/README.md",
  "apps/ios/SignalASI.xcodeproj/project.pbxproj",
  "apps/ios/SignalASI.xcodeproj/xcshareddata/xcschemes/SignalASI.xcscheme",
  "apps/ios/SignalASI/SignalASIModels.swift",
  "apps/ios/SignalASI/SignalASILinkProtocol.swift",
  "apps/ios/SignalASI/SignalASILinkReliability.swift",
  "apps/ios/SignalASI/SignalASIStore.swift",
  "apps/ios/SignalASI/SignalASIServices.swift",
  "apps/ios/SignalASI/SignalASIViews.swift",
  "apps/ios/SignalASITests/SignalASILinkProtocolTests.swift",
  "apps/ios/SignalASITests/SignalASILinkReliabilityTests.swift",
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
const linkProtocol = read("apps/ios/SignalASI/SignalASILinkProtocol.swift");
const linkReliability = read("apps/ios/SignalASI/SignalASILinkReliability.swift");
const services = read("apps/ios/SignalASI/SignalASIServices.swift");
const views = read("apps/ios/SignalASI/SignalASIViews.swift");
const tests = [
  read("apps/ios/SignalASITests/SignalASILinkProtocolTests.swift"),
  read("apps/ios/SignalASITests/SignalASILinkReliabilityTests.swift"),
  read("apps/ios/SignalASITests/SignalASIStoreTests.swift"),
].join("\n");

const requiredProjectSnippets = [
  "IPHONEOS_DEPLOYMENT_TARGET = 15.0",
  "PRODUCT_BUNDLE_IDENTIFIER = com.signalasi.chat.ios",
  "INFOPLIST_KEY_NSCameraUsageDescription",
  "INFOPLIST_KEY_NSMicrophoneUsageDescription",
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription",
  "SignalASITests.xctest",
];

const requiredSourceSnippets = [
  [readme, "iOS 15"],
  [models, "static let androidParity"],
  [linkProtocol, "signalasi_pairing_ciphertext"],
  [linkProtocol, "signalasi.pairing-access/1.0"],
  [linkReliability, "SignalASIMqttWireChunking"],
  [linkReliability, "SignalASILinkDeliveryStore"],
  [linkReliability, "SignalASILinkDeliveryAckPolicy"],
  [services, "broker.emqx.io"],
  [services, "scheduleOutboxFlush"],
  [services, "UNUserNotificationCenter"],
  [services, "SFSpeechRecognizer"],
  [views, "AVCaptureMetadataOutput"],
  [tests, "testValidatesAndroidCompatiblePairingQRCode"],
  [tests, "testChunkingRoundTripsLargeWirePayload"],
  [tests, "testCloudModelContactsAreGroupedByProvider"],
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
