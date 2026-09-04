const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const workspaceRoot = path.resolve(root, "..");
const backendDir = path.join(root, "core", "galaxyssi-link", "backend");
const required = [
  "package.json",
  "src/main.js",
  "src/preload.js",
  "src/peer_hold_to_talk.js",
  "src/peer_conversation_preview.js",
  "src/renderer/index.html",
  "src/renderer/connecting-animation.js",
  "src/renderer/renderer.js",
  "src/renderer/workspace.js",
  "src/renderer/evolution-v2-panel.js",
  "src/renderer/evolution-v2-panel.css",
  "src/renderer/locales/zh-CN.json",
  "src/renderer/locales/en.json",
  "src/renderer/styles.css",
  "core/galaxyssi-link/backend/desktop_control.py",
  "core/galaxyssi-link/backend/device_identity.py",
  "core/galaxyssi-link/backend/desktop_run_control.py",
  "core/galaxyssi-link/backend/acp_runtime.py",
  "core/galaxyssi-link/backend/pairing_access.py",
  "core/galaxyssi-link/backend/desktop_agent_loop.py",
  "core/galaxyssi-link/backend/desktop_super_agent.py",
  "core/galaxyssi-link/backend/desktop_memory.py",
  "core/galaxyssi-link/backend/desktop_mcp.py",
  "core/galaxyssi-link/backend/mcp_config_import.py",
  "core/galaxyssi-link/backend/mcp_security.py",
  "core/galaxyssi-link/backend/desktop_runtime.py",
  "core/galaxyssi-link/backend/edge_tts_service.py",
  "core/galaxyssi-link/backend/desktop_skills.py",
  "core/galaxyssi-link/backend/evolution_manager.py",
  "core/galaxyssi-link/backend/evolution_v2/__init__.py",
  "core/galaxyssi-link/backend/evolution_v2/api.py",
  "core/galaxyssi-link/backend/evolution_v2/manager.py",
  "core/galaxyssi-link/backend/agent_reputation_ledger.py",
  "core/galaxyssi-link/backend/agent_collaboration_channels.py",
  "core/galaxyssi-link/backend/agent_file_access_ledger.py",
  "core/galaxyssi-link/backend/agent_performance_lab.py",
  "core/galaxyssi-link/backend/provider_profiles.py",
  "core/galaxyssi-link/backend/response_self_check.py",
  "core/galaxyssi-link/backend/run_timeline.py",
  "scripts/package-win.js",
  "scripts/android-adb.js",
  "scripts/android-secure-state-probe.js",
  "scripts/smoke.js",
  "scripts/smoke-pairing.js",
  "scripts/smoke-ui.js",
  "scripts/smoke-android-ui.js",
  "scripts/smoke-android-friends.js",
  "scripts/smoke-android-contact-rename.js",
  "scripts/smoke-android-contact-tags.js",
  "scripts/smoke-android-language.js",
  "scripts/smoke-android-cloud-models.js",
  "scripts/smoke-android-background-message.js",
  "scripts/smoke-android-agent-replies.js",
  "scripts/smoke-android-backup-roundtrip.js",
  "scripts/smoke-android-voice-reply.js",
  "scripts/smoke-android-voice-settings.js",
  "scripts/smoke-android-reset.js",
  "scripts/smoke-mqtt-persistence.js",
  "scripts/smoke-agent-push.js",
  "scripts/smoke-voice-stt.js",
  "scripts/smoke-e2e.js",
  "scripts/smoke-packaged.js",
  "scripts/smoke-lock.js",
  "scripts/connector-status.js",
  "scripts/peer-hold-to-talk.test.js",
  "scripts/peer-conversation-preview.test.js",
  "docs/CONNECTOR_STATUS.md"
];

for (const file of required) {
  const full = path.join(root, file);
  if (!fs.existsSync(full)) {
    throw new Error(`Missing ${file}`);
  }
}

function listFilesRecursive(dir) {
  const result = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      result.push(...listFilesRecursive(full));
    } else {
      result.push(full);
    }
  }
  return result;
}

const main = fs.readFileSync(path.join(root, "src/main.js"), "utf8");
const preload = fs.readFileSync(path.join(root, "src/preload.js"), "utf8");
const html = fs.readFileSync(path.join(root, "src/renderer/index.html"), "utf8");
const connectingAnimation = fs.readFileSync(path.join(root, "src/renderer/connecting-animation.js"), "utf8");
const renderer = fs.readFileSync(path.join(root, "src/renderer/renderer.js"), "utf8");
const workspaceRenderer = fs.readFileSync(path.join(root, "src/renderer/workspace.js"), "utf8");
const evolutionV2Panel = fs.readFileSync(path.join(root, "src/renderer/evolution-v2-panel.js"), "utf8");
const styles = fs.readFileSync(path.join(root, "src/renderer/styles.css"), "utf8");
const localeZh = JSON.parse(fs.readFileSync(path.join(root, "src", "renderer", "locales", "zh-CN.json"), "utf8"));
const localeEn = JSON.parse(fs.readFileSync(path.join(root, "src", "renderer", "locales", "en.json"), "utf8"));
const packageJson = fs.readFileSync(path.join(root, "package.json"), "utf8");
const packager = fs.readFileSync(path.join(root, "scripts/package-win.js"), "utf8");
const androidAdb = fs.readFileSync(path.join(root, "scripts/android-adb.js"), "utf8");
const smoke = fs.readFileSync(path.join(root, "scripts/smoke.js"), "utf8");
const smokePairing = fs.readFileSync(path.join(root, "scripts/smoke-pairing.js"), "utf8");
const smokeUi = fs.readFileSync(path.join(root, "scripts/smoke-ui.js"), "utf8");
const smokeAndroidUi = fs.readFileSync(path.join(root, "scripts/smoke-android-ui.js"), "utf8");
const smokeAndroidFriends = fs.readFileSync(path.join(root, "scripts/smoke-android-friends.js"), "utf8");
const smokeAndroidContactRename = fs.readFileSync(path.join(root, "scripts/smoke-android-contact-rename.js"), "utf8");
const smokeAndroidContactTags = fs.readFileSync(path.join(root, "scripts/smoke-android-contact-tags.js"), "utf8");
const smokeAndroidLanguage = fs.readFileSync(path.join(root, "scripts/smoke-android-language.js"), "utf8");
const smokeAndroidCloudModels = fs.readFileSync(path.join(root, "scripts/smoke-android-cloud-models.js"), "utf8");
const smokeAndroidBackground = fs.readFileSync(path.join(root, "scripts/smoke-android-background-message.js"), "utf8");
const smokeAndroidAgentReplies = fs.readFileSync(path.join(root, "scripts/smoke-android-agent-replies.js"), "utf8");
const smokeAndroidBackup = fs.readFileSync(path.join(root, "scripts/smoke-android-backup-roundtrip.js"), "utf8");
const smokeAndroidVoiceReply = fs.readFileSync(path.join(root, "scripts/smoke-android-voice-reply.js"), "utf8");
const smokeAndroidVoiceSettings = fs.readFileSync(path.join(root, "scripts/smoke-android-voice-settings.js"), "utf8");
const smokeAndroidReset = fs.readFileSync(path.join(root, "scripts/smoke-android-reset.js"), "utf8");
const smokeMqttPersistence = fs.readFileSync(path.join(root, "scripts/smoke-mqtt-persistence.js"), "utf8");
const smokeAgentPush = fs.readFileSync(path.join(root, "scripts/smoke-agent-push.js"), "utf8");
const smokeAgentLifecycle = fs.readFileSync(path.join(root, "scripts/smoke-agent-lifecycle.py"), "utf8");
const smokeVoiceStt = fs.readFileSync(path.join(root, "scripts/smoke-voice-stt.js"), "utf8");
const smokeE2e = fs.readFileSync(path.join(root, "scripts/smoke-e2e.js"), "utf8");
const smokePackaged = fs.readFileSync(path.join(root, "scripts/smoke-packaged.js"), "utf8");
const smokeLock = fs.readFileSync(path.join(root, "scripts/smoke-lock.js"), "utf8");
const connectorStatus = fs.readFileSync(path.join(root, "scripts/connector-status.js"), "utf8");
const statusDoc = fs.readFileSync(path.join(root, "docs/CONNECTOR_STATUS.md"), "utf8");
const backendMain = fs.readFileSync(path.join(backendDir, "main.py"), "utf8");
const backendModels = fs.readFileSync(path.join(backendDir, "models.py"), "utf8");
const backendMqtt = fs.readFileSync(path.join(backendDir, "mqtt_bridge.py"), "utf8");
const backendPairing = fs.readFileSync(path.join(backendDir, "pairing_state.py"), "utf8");
const backendPairingAccess = fs.readFileSync(path.join(backendDir, "pairing_access.py"), "utf8");
const backendLinkProtocol = fs.readFileSync(path.join(backendDir, "link_protocol.py"), "utf8");
const backendLinkDelivery = fs.readFileSync(path.join(backendDir, "link_delivery.py"), "utf8");
const backendSignalClient = fs.readFileSync(path.join(backendDir, "galaxyssi_client.py"), "utf8");
const backendAgentReputation = fs.readFileSync(path.join(backendDir, "agent_reputation_ledger.py"), "utf8");
const backendAgentCollaboration = fs.readFileSync(path.join(backendDir, "agent_collaboration_channels.py"), "utf8");
const backendAgentFileAccess = fs.readFileSync(path.join(backendDir, "agent_file_access_ledger.py"), "utf8");
const backendAgentPerformanceLab = fs.readFileSync(path.join(backendDir, "agent_performance_lab.py"), "utf8");
const backendProviderProfiles = fs.readFileSync(path.join(backendDir, "provider_profiles.py"), "utf8");
const backendGateway = fs.readFileSync(path.join(backendDir, "agent_gateway.py"), "utf8");
const backendAcpRuntime = fs.readFileSync(path.join(backendDir, "acp_runtime.py"), "utf8");
const backendTaskManager = fs.readFileSync(path.join(backendDir, "agent_task_manager.py"), "utf8");
const backendExecutionHarness = fs.readFileSync(path.join(backendDir, "agent_execution_harness.py"), "utf8");
const backendAgentConfig = fs.readFileSync(path.join(backendDir, "agent_config.py"), "utf8");
const backendCustomAgent = fs.readFileSync(path.join(backendDir, "custom_agent_stdio.py"), "utf8");
const backendDesktopFileTools = fs.readFileSync(path.join(backendDir, "desktop_file_tools.py"), "utf8");
const backendDesktopControl = fs.readFileSync(path.join(backendDir, "desktop_control.py"), "utf8");
const backendDesktopRunControl = fs.readFileSync(path.join(backendDir, "desktop_run_control.py"), "utf8");
const backendDesktopAgentLoop = fs.readFileSync(path.join(backendDir, "desktop_agent_loop.py"), "utf8");
const backendAgentFailureRecovery = fs.readFileSync(path.join(backendDir, "agent_failure_recovery.py"), "utf8");
const backendResponseSelfCheck = fs.readFileSync(path.join(backendDir, "response_self_check.py"), "utf8");
const backendDesktopNativeTools = fs.readFileSync(path.join(backendDir, "desktop_native_tools.py"), "utf8");
const backendDesktopMemory = fs.readFileSync(path.join(backendDir, "desktop_memory.py"), "utf8");
const backendDesktopMcp = fs.readFileSync(path.join(backendDir, "desktop_mcp.py"), "utf8");
const backendMcpSecurity = fs.readFileSync(path.join(backendDir, "mcp_security.py"), "utf8");
const backendDesktopRuntime = fs.readFileSync(path.join(backendDir, "desktop_runtime.py"), "utf8");
const backendDesktopSkills = fs.readFileSync(path.join(backendDir, "desktop_skills.py"), "utf8");
const backendDesktopSuperAgent = fs.readFileSync(path.join(backendDir, "desktop_super_agent.py"), "utf8");
const backendEvolutionManager = fs.readFileSync(path.join(backendDir, "evolution_manager.py"), "utf8");
const backendEvolutionLegacy = fs.readFileSync(path.join(backendDir, "evolution_v2", "legacy.py"), "utf8");
const backendEvolutionV2Manager = fs.readFileSync(path.join(backendDir, "evolution_v2", "manager.py"), "utf8");
const backendEvolutionV2Api = fs.readFileSync(path.join(backendDir, "evolution_v2", "api.py"), "utf8");
const backendEvolutionV2Scheduler = fs.readFileSync(path.join(backendDir, "evolution_v2", "scheduler.py"), "utf8");
const backendMcpWrapper = fs.readFileSync(path.join(backendDir, "mcp_agent_wrapper.py"), "utf8");
const backendMcpTransport = fs.readFileSync(path.join(backendDir, "mcp_transport.py"), "utf8");
const backendTaskWorkspace = fs.readFileSync(path.join(backendDir, "task_workspace.py"), "utf8");
const backendPushAuth = fs.readFileSync(path.join(backendDir, "push_auth.py"), "utf8");
const backendGalaxySSINotify = fs.readFileSync(path.join(backendDir, "galaxyssi_notify.py"), "utf8");
const backendApiResponse = fs.readFileSync(path.join(backendDir, "api_response.py"), "utf8");
const backendStt = fs.readFileSync(path.join(backendDir, "stt_bridge.py"), "utf8");
const backendTts = fs.readFileSync(path.join(backendDir, "edge_tts_service.py"), "utf8");
const sidecarDir = path.join(backendDir, "signal_sidecar");
const sidecarSourceDir = path.join(sidecarDir, "src", "main", "java");
const sidecarMainSource = fs.readFileSync(path.join(sidecarSourceDir, "com", "galaxyssi", "link", "SignalSidecar.java"), "utf8");
const sidecarStoreSource = fs.readFileSync(path.join(sidecarSourceDir, "com", "galaxyssi", "link", "PersistentSignalProtocolStore.java"), "utf8");
const sidecarBuildGradle = fs.readFileSync(path.join(sidecarDir, "build.gradle.kts"), "utf8");
const sidecarSettingsGradle = fs.readFileSync(path.join(sidecarDir, "settings.gradle.kts"), "utf8");
const backendSecureState = fs.readFileSync(path.join(backendDir, "secure_state.py"), "utf8");
const backendToolPermissions = fs.readFileSync(path.join(backendDir, "tool_permission_policy.py"), "utf8");
const androidMainActivity = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "MainActivity.kt"), "utf8");
const androidChatSources = listFilesRecursive(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat"))
  .filter((file) => file.endsWith(".kt"))
  .map((file) => fs.readFileSync(file, "utf8"))
  .join("\n");
const androidMessageService = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "MessageService.kt"), "utf8");
const androidChatHistoryStore = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "ChatHistoryStore.kt"), "utf8");
const androidChatHistoryDatabase = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "ChatHistoryDatabase.kt"), "utf8");
const androidDebugChatHistoryProbe = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "DebugChatHistoryProbe.kt"), "utf8");
const androidChatHistoryProbeScript = fs.readFileSync(path.join(__dirname, "android-chat-history-probe.js"), "utf8");
const androidDebugSecureStateProbe = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "DebugSecureStateProbe.kt"), "utf8");
const androidSecureStateProbeScript = fs.readFileSync(path.join(__dirname, "android-secure-state-probe.js"), "utf8");
const androidSignalStore = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AndroidPersistentSignalStore.kt"), "utf8");
const androidForegroundTracker = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AppForegroundTracker.kt"), "utf8");
const androidAppStore = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AppStore.kt"), "utf8");
const androidCrypto = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSICrypto.kt"), "utf8");
const androidMqtt = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSIMqttClient.kt"), "utf8");
const androidLinkProtocol = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSILinkProtocol.kt"), "utf8");
const androidLinkDelivery = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "GalaxySSILinkDeliveryStore.kt"), "utf8");
const androidVoiceSettings = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "VoiceAssistantSettings.kt"), "utf8");
const androidLocalWhisper = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "LocalWhisperAsr.kt"), "utf8");
const androidWhisperModels = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "WhisperModelManager.kt"), "utf8");
const androidCloudModelClient = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "CloudModelClient.kt"), "utf8");
const androidMcpSecurity = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentMcpSecurity.kt"), "utf8");
const androidMcpRuntime = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentMcpRuntime.kt"), "utf8");
const androidExecutionPresentation = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentExecutionPresentation.kt"), "utf8");
const androidTaskIntent = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentTaskIntent.kt"), "utf8");
const androidTaskBudget = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentTaskBudget.kt"), "utf8");
const androidAgentFailureRecovery = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentFailureRecovery.kt"), "utf8");
const androidResponseSelfCheck = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "java", "com", "galaxyssi", "chat", "AgentResponseSelfCheck.kt"), "utf8");
const androidStringsZh = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "res", "values-zh-rCN", "strings.xml"), "utf8");
const androidStringsEn = fs.readFileSync(path.join(workspaceRoot, "android", "app", "src", "main", "res", "values", "strings.xml"), "utf8");
const androidSourceRoot = path.join(workspaceRoot, "android", "app", "src", "main");

if (!html.includes('id="startupConnecting"') ||
    !html.includes('src="./connecting-animation.js"') ||
    !connectingAnimation.includes("function frameAt") ||
    !workspaceRenderer.includes("window.galaxyssiConnecting?.finish()")) {
  throw new Error("Desktop startup must show and dismiss the animated CONNECTING readout");
}

if (!styles.includes(".utility-drawer.open") ||
    !styles.includes("box-shadow: none; pointer-events: none") ||
    !styles.includes("pointer-events: auto")) {
  throw new Error("Closed utility drawers must not cast a shadow or intercept pointer input");
}
if (html.includes('id="peerContactToggle"') ||
    html.includes('id="peerContactList"') ||
    !workspaceRenderer.includes("unifiedConversationGroups") ||
    !workspaceRenderer.includes('data-peer-route=')) {
  throw new Error("Desktop tasks and paired devices must share one conversation history");
}
if (!html.includes('id="conversationListMenuButton"') ||
    !html.includes('id="conversationSelectionBar"') ||
    !html.includes('data-i18n="Select conversations to delete"') ||
    !workspaceRenderer.includes("deleteConversationIds") ||
    !workspaceRenderer.includes("hiddenEvolutionConversationIds") ||
    !main.includes("Desktop bulk conversation deletion failed") ||
    !workspaceRenderer.includes("galaxyssi-desktop-pinned-conversations") ||
    !workspaceRenderer.includes("data-pin-conversation") ||
    !workspaceRenderer.includes("data-delete-conversation")) {
  throw new Error("Desktop conversation history must support persistent pinning and bulk deletion");
}
if (html.includes('id="deleteAllConversationsButton"') ||
    workspaceRenderer.includes("function deleteAllConversations") ||
    workspaceRenderer.includes('$("#deleteAllConversationsButton")') ||
    localeZh["Delete all conversations"] ||
    localeZh["Delete all conversations? Contacts and paired devices will remain."] ||
    localeZh["Select conversations to delete"] !== "\u9009\u62e9\u5220\u6389\u5bf9\u8bdd") {
  throw new Error("Desktop conversation menu must only open explicit conversation deletion selection");
}
if (!main.includes('ipcMain.handle("peer-conversations:delete"') ||
    !preload.includes("deletePeerConversation") ||
    !backendMain.includes('@app.delete("/api/peer/conversations/{client_route_id}")') ||
    !workspaceRenderer.includes('const selecting = state.conversationSelectionMode;') ||
    !workspaceRenderer.includes('window.galaxyssi.deletePeerConversation(id)') ||
    workspaceRenderer.includes('group.kind === "agent" && !selecting') ||
    !styles.includes('grid-template-columns: 278px minmax(0, 1fr)')) {
  throw new Error("Desktop device chats must share selection, menus, deletion, and sidebar width with task conversations");
}
if (!html.includes('id="voiceButton"') ||
    !workspaceRenderer.includes("function startVoiceInput()") ||
    !workspaceRenderer.includes('voiceButton.addEventListener("click"') ||
    styles.includes(".peer-mode #voiceButton { display: none")) {
  throw new Error("Desktop device chats must share the standard conversation voice input control and transcription flow");
}
if (!html.includes('id="peerVoiceHoldOverlay"') ||
    !html.includes('src="../peer_hold_to_talk.js"') ||
    !workspaceRenderer.includes('voiceButton.addEventListener("pointerdown"') ||
    !workspaceRenderer.includes("voiceButton.setPointerCapture(event.pointerId)") ||
    !workspaceRenderer.includes("updatePeerVoiceHoldPointer(event.clientY)") ||
    !workspaceRenderer.includes("finishPeerVoiceHold(true)") ||
    !workspaceRenderer.includes("window.galaxyssiPeerHoldToTalk.completion") ||
    workspaceRenderer.includes("togglePeerVoiceMessage") ||
    !styles.includes(".peer-voice-hold-overlay.cancel-pending") ||
    !styles.includes("@keyframes peer-hold-wave")) {
  throw new Error("Desktop device voice messages must use hold-to-record, swipe-to-cancel, and release-to-send interaction");
}
if (!html.includes('id="routeStatusDot"') ||
    !workspaceRenderer.includes('elements.route.textContent = t("GalaxySSI Link encrypted")') ||
    !styles.includes('.peer-mode .workspace-title p .route-status-dot') ||
    !styles.includes('width: 7px; height: 7px;') ||
    localeZh["GalaxySSI Link encrypted"] !== "GalaxySSI Link \u5df2\u52a0\u5bc6") {
  throw new Error("Desktop device chats must show GalaxySSI Link encrypted with the shared green 7px indicator");
}
if (!workspaceRenderer.includes("const PEER_TIME_DIVIDER_GAP_MS = 30 * 60 * 1000") ||
    !workspaceRenderer.includes("function shouldShowPeerTimeDivider(messages, index)") ||
    !workspaceRenderer.includes('class="peer-time-divider"') ||
    !workspaceRenderer.includes('class="peer-message-delivery"') ||
    !workspaceRenderer.includes('elements.prompt.placeholder = state.activePeerRouteId ? "" : label') ||
    workspaceRenderer.includes('<small>${escapeHtml(relativeTime(message.created_at_ms))}') ||
    !styles.includes(".peer-time-divider") ||
    !styles.includes(".peer-message-delivery")) {
  throw new Error("Desktop device chats must group timestamps outside compact bubbles and hide the peer composer placeholder");
}
if (!styles.includes('.new-task-row:hover .sidebar-more-button') ||
    !styles.includes('.history-item-shell:hover .history-more') ||
    !styles.includes('.new-task-row:focus-within .sidebar-more-button') ||
    !styles.includes('.history-item-shell:focus-within .history-more') ||
    !styles.includes('.new-task-row { position: relative; display: block; }') ||
    !styles.includes('.history-item-shell { position: relative; display: block; }') ||
    !styles.includes('.history-item-shell:hover .history-title-row time') ||
    !styles.includes('position: absolute; top: 50%; right: 0;') ||
    !styles.includes('position: absolute; top: 0; right: 0; bottom: 0;') ||
    !styles.includes('box-shadow: -5px 0 currentColor, 5px 0 currentColor') ||
    !styles.includes('transform: translate(-50%, -50%)')) {
  throw new Error("Desktop conversation menus must overlay full-width rows and replace the trailing date on interaction");
}
if (!main.includes("width: 864") || !main.includes("height: 576")) {
  throw new Error("Desktop window must default to 864 x 576");
}
if (main.includes("minWidth:") || main.includes("minHeight:")) {
  throw new Error("Desktop window must not impose a minimum size");
}
if (!main.includes("fetch(`${BACKEND_ORIGIN}/health`")) {
  throw new Error("Desktop liveness checks must use the lightweight health endpoint");
}

for (const resource of ["colors.xml", "styles.xml"]) {
  const localizedResource = path.join(androidSourceRoot, "res", "values-zh-rCN", resource);
  if (fs.existsSync(localizedResource)) {
    throw new Error(`${resource} must not be localized; locale-specific copies override Android night resources`);
  }
}

if (!smokeAndroidReset.includes("GALAXYSSI_ALLOW_DESTRUCTIVE_RESET")) {
  throw new Error("Android destructive reset smoke must require an explicit disposable-device opt-in");
}

for (const [name, source, forbidden] of [
  ["Agent config", backendAgentConfig, "LEGACY_CONFIG_PATH"],
  ["Desktop database", backendModels, "Path(__file__).with_name(\"galaxyssi.db\")"],
  ["Desktop STT", backendStt, "HERMESCHAT_WHISPER_"],
  ["Windows package", packager, "galaxyssi_agents.json"],
  ["Desktop smoke", smoke, "galaxyssi_agents.json"],
  ["Desktop e2e", smokeE2e, "galaxyssi_agents.json"]
]) {
  if (source.includes(forbidden)) {
    throw new Error(`${name} must not fall back to source-tree or Hermes-era data`);
  }
}

for (const marker of [
  "galaxyssi-packaged-smoke-",
  "GALAXYSSI_STATE_DIR",
  "GALAXYSSI_DATABASE_PATH",
  "GALAXYSSI_CONFIG_PATH",
  "GALAXYSSI_DISABLE_EXTERNAL_SERVICES"
]) {
  if (!smokePackaged.includes(marker)) {
    throw new Error(`Packaged smoke must isolate current runtime state: ${marker}`);
  }
}

for (const [name, source] of [
  ["contact tags", smokeAndroidContactTags],
  ["friends", smokeAndroidFriends],
  ["voice settings", smokeAndroidVoiceSettings]
]) {
  if (source.includes("hermes_app_store.xml")) {
    throw new Error(`Android ${name} smoke must use only the current GalaxySSI app store`);
  }
}
if (
  !androidChatSources.includes("galaxyssi_debug_secure_state_probe_b64")
  || !androidDebugSecureStateProbe.includes("android-keystore-aes-gcm")
  || !androidDebugSecureStateProbe.includes("ApplicationInfo.FLAG_DEBUGGABLE")
  || !androidSecureStateProbeScript.includes("snapshotSecureState")
  || !smokeAndroidUi.includes("snapshotSecureState")
  || !smokeAndroidFriends.includes("snapshotSecureState")
  || !smokeAndroidContactRename.includes("snapshotSecureState")
  || !smokeAndroidContactTags.includes("replaceSecureAppStore")
  || !smokeAndroidCloudModels.includes("patchSecureContact")
  || !smokeAndroidAgentReplies.includes("snapshotSecureState")
  || !smokeAndroidVoiceReply.includes("snapshotSecureState")
  || !smokeAndroidReset.includes("snapshotSecureState")
) {
  throw new Error("Android smoke tests must use the debuggable encrypted-state probe instead of parsing plaintext security preferences");
}
for (const [name, source] of [
  ["Contacts", smokeAndroidContactTags],
  ["Cloud models", smokeAndroidCloudModels],
  ["Friends", smokeAndroidFriends],
  ["UI", smokeAndroidUi],
  ["Agent replies", smokeAndroidAgentReplies],
  ["Voice replies", smokeAndroidVoiceReply],
  ["Reset", smokeAndroidReset],
  ["Contact rename", smokeAndroidContactRename]
]) {
  if (source.includes("function appStoreXml(") || source.includes('prefString(xml, "contacts"')) {
    throw new Error(`${name} Android smoke must not synthesize or parse plaintext encrypted preference XML`);
  }
}

if (!main.includes("/galaxyssi/verify")) {
  throw new Error("Electron desktop must use /galaxyssi/verify");
}

const oldRoutes = ["/signal/verify", "/signalagi/verify"];
if (oldRoutes.some((route) => main.includes(route) || html.includes(route))) {
  throw new Error("Old pairing routes must not be used by desktop");
}

if (!backendSignalClient.includes('"type": "galaxyssi_verify"')) {
  throw new Error("Pairing QR payload must use galaxyssi_verify");
}

if (
  !backendMqtt.includes("decrypt_pairing_claim")
  || !backendMqtt.includes("pairing_session_for_topic")
  || !backendLinkProtocol.includes("pairing_topic")
  || !backendLinkProtocol.includes("seal_wire_packet")
) {
  throw new Error("MQTT pairing must use the encrypted opaque Link v2 rendezvous");
}

for (const required of [
  "desktop.executor.full",
  "desktop.control",
  "desktop.native_tools",
  "desktop.files.external",
  "apply_restricted_agent_boundary"
]) {
  if (!backendPairingAccess.includes(required)) {
    throw new Error(`Pairing access profiles missing: ${required}`);
  }
}
if (
  !html.includes('id="pairingDesktopExecutorEnabled"')
  || !preload.includes('ipcRenderer.invoke("pairing:qr", Boolean(grantDesktopExecutor))')
  || !main.includes("desktop_executor=${grantDesktopExecutor")
  || !backendMain.includes("grant_desktop_executor")
  || !backendMqtt.includes("desktop_executor_scope_required")
) {
  throw new Error("Desktop pairing UI and backend must enforce the two access profiles");
}

for (const source of [backendMqtt, backendPairing, backendLinkProtocol, androidMqtt, androidAppStore, androidLinkProtocol]) {
  for (const forbidden of ["galaxyssichat/", "server_route_id", "mqtt_inbox_topic", "reply_topic"]) {
    if (source.includes(forbidden)) {
      throw new Error(`Semantic public transport marker is forbidden by GalaxySSI Link v2: ${forbidden}`);
    }
  }
}

for (const required of ["relationship_topic", "pairing_topic", "seal_wire_packet", "open_wire_packet"]) {
  if (!backendLinkProtocol.includes(required)) {
    throw new Error(`Desktop opaque Link v2 implementation must include ${required}`);
  }
}
for (const required of ["relationshipTopic", "pairingTopic", "sealWirePacket", "openWirePacket"]) {
  if (!androidLinkProtocol.includes(required)) {
    throw new Error(`Android opaque Link v2 implementation must include ${required}`);
  }
}
if (backendMqtt.includes("retain=True") || androidMqtt.includes("isRetained = true")) {
  throw new Error("GalaxySSI Link v2 must never publish retained MQTT packets");
}

for (const required of ["inbound_messages", "outbound_messages", "claim_message", "queue_outbound"]) {
  if (!backendLinkDelivery.includes(required)) {
    throw new Error(`Desktop reliable delivery store missing ${required}`);
  }
}

for (const required of ["enqueue", "claimIncoming", "acknowledge", "pending"]) {
  if (!androidLinkDelivery.includes(required)) {
    throw new Error(`Android reliable delivery store missing ${required}`);
  }
}

if (!backendSignalClient.includes("galaxyssi-link-sidecar") || !main.includes("galaxyssi-link-sidecar") || !packager.includes("galaxyssi-link-sidecar") || !smokePackaged.includes("galaxyssi-link-sidecar")) {
  throw new Error("Desktop runtime, packager, and packaged smoke must use galaxyssi-link-sidecar");
}

if (
  !packager.includes("Synchronizing GalaxySSI Link sidecar runtime")
  || packager.includes("if (fs.existsSync(sidecarRuntimeDir)) return;")
) {
  throw new Error("Windows packaging must rebuild the GalaxySSI Link sidecar before copying it");
}

if (!sidecarMainSource.includes("package com.galaxyssi.link;") || !sidecarBuildGradle.includes("com.galaxyssi.link.SignalSidecar") || !sidecarSettingsGradle.includes('rootProject.name = "galaxyssi-link-sidecar"')) {
  throw new Error("Signal sidecar source and Gradle metadata must use GalaxySSI Link naming");
}
if (
  !backendSecureState.includes("CryptProtectData")
  || !backendSecureState.includes("AESGCM")
  || !backendSecureState.includes("AESSIV")
  || !backendPairing.includes("write_secure_json")
  || !backendDesktopControl.includes("CONTROL_STATE_PURPOSE")
  || !backendLinkDelivery.includes("seal_identifier")
  || !backendSignalClient.includes("GALAXYSSI_LINK_STORAGE_KEY")
  || !sidecarMainSource.includes('"encryptedStorage", true')
  || !sidecarStoreSource.includes('Cipher.getInstance("AES/GCM/NoPadding")')
) {
  throw new Error("Desktop pairing identities, routes, and authorization state must be encrypted at rest");
}
if (
  !backendToolPermissions.includes("read_secure_json")
  || !backendToolPermissions.includes("write_secure_json")
  || !backendToolPermissions.includes("DENY_ALWAYS")
  || !backendToolPermissions.includes("action_hash")
) {
  throw new Error("Scoped tool permission decisions must remain encrypted and bound to exact action fingerprints");
}
for (const [name, source] of [
  ["Signal store", androidSignalStore],
  ["Link routes", androidLinkProtocol],
  ["Link delivery", androidLinkDelivery],
  ["contacts and provider credentials", androidAppStore],
  ["identity trust", androidCrypto]
]) {
  if (!source.includes("AgentEncryptedPreferences")) {
    throw new Error(`Android ${name} must use Android Keystore-backed encrypted persistence`);
  }
}
if (
  !sidecarMainSource.includes('server.createContext("/sign"')
  || !sidecarMainSource.includes('server.createContext("/verify"')
  || !sidecarMainSource.includes(".calculateSignature(")
  || !backendSignalClient.includes("def sign_signal_identity(")
  || !backendAgentReputation.includes("class AgentReputationLedger")
) {
  throw new Error("Desktop package must include signed Agent reputation receipts");
}
for (const providerId of [
  "openai",
  "anthropic",
  "gemini",
  "deepseek",
  "qwen",
  "ollama",
  "lm-studio",
  "openrouter"
]) {
  if (!backendProviderProfiles.includes(`"${providerId}"`)) {
    throw new Error(`Unified Provider Profile catalog missing ${providerId}`);
  }
}
if (
  !backendMain.includes('@app.get("/api/provider-profiles")')
  || !backendMqtt.includes('"provider_profile_v1"')
  || !backendGateway.includes("provider_metrics_store().record")
) {
  throw new Error("Provider Profiles must expose durable metrics through Desktop and GalaxySSI Link");
}
if (
  !backendMain.includes('@app.get("/api/agents/performance-lab")')
  || !backendAgentPerformanceLab.includes("local_anonymous_execution_metrics")
  || !backendAgentPerformanceLab.includes("CORE_AGENT_DEFINITIONS")
  || !main.includes('"agents:performance-lab"')
  || !preload.includes("getAgentPerformanceLab")
  || !workspaceRenderer.includes("refreshAgentPerformance")
  || !html.includes('id="agentPerformanceList"')
  || !styles.includes(".agent-performance-lab")
) {
  throw new Error("Desktop must expose the privacy-preserving Agent performance lab");
}

if (fs.existsSync(path.join(sidecarSourceDir, "com", "hermes", "signal"))) {
  throw new Error("Signal sidecar source path must not use com/hermes/signal");
}

if (fs.existsSync(path.join(sidecarDir, "build", "install", "hermes-signal-sidecar"))) {
  throw new Error("Signal sidecar build output must not contain hermes-signal-sidecar");
}

if (renderer.includes("const I18N_ZH")) {
  throw new Error("Desktop renderer translations must live in locale files, not an inline I18N_ZH object");
}

if (!main.includes("function loadLocale") || !main.includes('ipcMain.handle("i18n:load"') || !preload.includes("loadLocale") || !workspaceRenderer.includes("await window.galaxyssi.loadLocale")) {
  throw new Error("Desktop i18n must load locale JSON through preload IPC");
}

if (
  !backendMain.includes('@app.websocket("/ws/desktop/tasks")')
  || !backendTaskManager.includes("def subscribe(")
  || !backendTaskManager.includes("def unsubscribe(")
  || !main.includes('ipcMain.handle("desktop-tasks:stream-config"')
  || !main.includes("GALAXYSSI_DESKTOP_TASK_STREAM_TOKEN")
  || !preload.includes("desktopTaskStreamConfig")
  || !workspaceRenderer.includes("new WebSocket(stream.url, stream.protocols)")
  || !html.includes("connect-src 'self' ws://127.0.0.1:8765")
) {
  throw new Error("Desktop task progress must use the loopback real-time event stream");
}
if (workspaceRenderer.includes("setInterval(() => refreshTasks(false), 1500)")) {
  throw new Error("Desktop task progress must not use the legacy 1.5 second full-list polling loop");
}
for (const pauseContract of [
  [backendTaskManager, "def continue_task("],
  [backendTaskManager, "execution_generation"],
  [backendDesktopRunControl, "class DesktopRunControlCoordinator"],
  [backendDesktopControl, "TASK_CONTROL_TOOLS"],
  [backendMain, '/api/desktop/tasks/{task_id}/pause'],
  [backendMain, '/api/desktop/tasks/{task_id}/takeover'],
  [backendMain, '/api/desktop/tasks/{task_id}/continue'],
  [main, 'ipcMain.handle("desktop-tasks:pause"'],
  [preload, "pauseDesktopTask"],
  [workspaceRenderer, "data-takeover-task"],
  [workspaceRenderer, "data-continue-task"]
]) {
  if (!pauseContract[0].includes(pauseContract[1])) {
    throw new Error(`Desktop pause/takeover/continue integration missing: ${pauseContract[1]}`);
  }
}

for (const requiredLocaleKey of [
  "Language",
  "Desktop Connector",
  "{done}/{total} setup steps complete",
  "Detecting",
  "Super agent",
  "Font size",
  "Adjust all text in GalaxySSI Desktop"
]) {
  if (!localeZh[requiredLocaleKey]) {
    throw new Error(`Chinese desktop locale missing key: ${requiredLocaleKey}`);
  }
}

if (!html.includes('<div class="sidebar-brand-copy"><strong>GalaxySSI</strong><span data-i18n="Super agent">Super agent</span></div>')) {
  throw new Error("Desktop sidebar brand must use the localized Super agent subtitle");
}

if (!html.includes("media-src 'self' blob:")) {
  throw new Error("Desktop CSP must allow in-memory Blob URLs for encrypted media playback");
}

if (
  !html.includes('class="sidebar-action sidebar-settings-row"')
  || !html.includes('id="desktopVersion"')
  || !main.includes('ipcMain.handle("app:version"')
  || !preload.includes("getAppVersion")
  || !workspaceRenderer.includes("window.galaxyssi.getAppVersion()")
) {
  throw new Error("Desktop sidebar settings row must show the runtime app version");
}

if (
  !html.includes('class="lucide lucide-square-pen"')
  || !html.includes('class="sidebar-settings-icon"')
  || !html.includes('id="fontScaleSelect"')
  || !html.includes('value="130" data-i18n="Large (130%)"')
  || html.includes('class="line-icon settings-icon"')
  || !/\.new-task-button\s*\{[^}]*height:\s*34px;[^}]*justify-content:\s*flex-start;[^}]*background:\s*#eef5f8;/s.test(styles)
  || !/\.new-task-button b\s*\{[^}]*font-size:\s*1rem;[^}]*font-weight:\s*400;/s.test(styles)
  || !/\.sidebar-settings-icon\s*\{[^}]*stroke-width:\s*1\.7;/s.test(styles)
  || !/\.sidebar-version\s*\{[^}]*font-size:\s*1\.2rem;/s.test(styles)
  || !/:root\s*\{[^}]*font-size:\s*13px;/s.test(styles)
  || !workspaceRenderer.includes('localStorage.getItem("galaxyssi-desktop-font-scale")')
  || !workspaceRenderer.includes("document.documentElement.style.fontSize")
) {
  throw new Error("Desktop typography and sidebar controls must preserve the configurable 130% default");
}

if (
  !/\.workspace-title h1\s*\{[^}]*font-size:\s*1\.12rem;[^}]*font-weight:\s*400;/s.test(styles)
  || !/\.empty-state h2\s*\{[^}]*font-size:\s*1\.12rem;[^}]*font-weight:\s*400;/s.test(styles)
  || !/\.pairing-qr-surface img\s*\{[^}]*width:\s*min\(320px,\s*100%\);/s.test(styles)
) {
  throw new Error("Desktop task headings must use the reduced regular weight and the Gateway QR must stay scannable");
}

if (
  html.includes('id="headerAgentCount"')
  || html.includes('id="headerGatewayCount"')
  || html.includes('id="backendDot"')
  || html.includes('<div id="emptyState" class="empty-state">\n          <img')
) {
  throw new Error("Desktop workspace must not duplicate backend status or the empty-state brand mark");
}

const computerNavIndex = html.indexOf('data-open-panel="computer"');
const agentNavIndex = html.indexOf('data-open-panel="agents"');
const capabilityNavIndex = html.indexOf('data-open-panel="capabilities"');
const gatewayNavIndex = html.indexOf('data-open-panel="gateway"');
const menuNavIndex = html.indexOf('id="workspaceMenuButton"');
if (
  !html.includes('<div class="sidebar-footer">\n        <button class="sidebar-action sidebar-settings-row"')
  || !html.includes('id="sidebarTaskSummary"')
  || !html.includes('<button data-open-panel="commands" data-i18n="Commands">Commands</button>')
  || html.includes('class="sidebar-action" data-open-panel="commands"')
  || html.includes('class="sidebar-action" data-open-panel="agents"')
  || html.includes('class="sidebar-action" data-open-panel="capabilities"')
  || html.includes('class="sidebar-action" data-open-panel="gateway"')
  || computerNavIndex !== -1
  || !(
    agentNavIndex >= 0
    && agentNavIndex < capabilityNavIndex
    && capabilityNavIndex < gatewayNavIndex
    && gatewayNavIndex < menuNavIndex
  )
) {
  throw new Error("Desktop navigation must prioritize task status while keeping commands in the workspace menu");
}

if (
  !html.includes('id="workspaceMenuButton" class="icon-button more-button"')
  || !/\.more-button::before\s*\{[^}]*box-shadow:\s*6px 0 currentColor,\s*12px 0 currentColor;/s.test(styles)
) {
  throw new Error("Desktop workspace menu must use a centered three-dot control");
}

for (const iconClass of ["lucide-bot", "lucide-sparkles", "lucide-smartphone"]) {
  if (!html.includes(`class="lucide ${iconClass}"`)) {
    throw new Error(`Desktop precision header icon missing: ${iconClass}`);
  }
}
if (
  !/\.compact-status svg\s*\{[^}]*stroke-width:\s*1\.65;/s.test(styles)
  || html.includes('class="lucide lucide-monitor"')
  || styles.includes(".computer-symbol::before")
  || styles.includes(".agent-symbol::before")
  || styles.includes(".capability-symbol::before")
  || styles.includes(".gateway-symbol::before")
) {
  throw new Error("Desktop header controls must use the selected precision line icon set");
}

if (
  html.includes('id="computerPanel"')
  || html.includes('id="desktopToolList"')
  || html.includes('id="desktopExecutorEnabled"')
  || html.includes('id="desktopControlRequireUnlocked"')
  || html.includes('id="desktopControlPendingList"')
  || html.includes('id="desktopControlAuthorizedList"')
  || !html.includes('id="pairingDesktopExecutorEnabled"')
  || !html.includes('class="drawer-details gateway-access-history"')
  || !html.includes('id="desktopControlAuditList"')
  || workspaceRenderer.includes("getDesktopTools")
  || workspaceRenderer.includes("invokeDesktopTool")
  || preload.includes("desktop-tools:list")
  || preload.includes("desktop-tools:invoke")
  || preload.includes("desktop-control:update")
  || preload.includes("desktop-control:authorization")
  || main.includes('ipcMain.handle("desktop-tools:list"')
  || main.includes('ipcMain.handle("desktop-tools:invoke"')
  || main.includes('ipcMain.handle("desktop-control:update"')
  || main.includes('ipcMain.handle("desktop-control:authorization"')
) {
  throw new Error("Mobile Gateway must own pairing and recent access history without duplicate Computer controls or renderer-only tool IPC");
}

if (
  !/\.sidebar-brand-copy\s*\{[^}]*width:\s*64px;[^}]*text-align:\s*center;/s.test(styles)
  || !/\.sidebar-brand strong,\s*\.sidebar-brand span\s*\{[^}]*width:\s*100%;[^}]*text-align:\s*center;/s.test(styles)
) {
  throw new Error("Desktop sidebar brand title and subtitle must share one fixed centered text column");
}

if (Object.keys(localeEn).length !== 0) {
  throw new Error("English desktop locale should rely on source strings until explicit translations are needed");
}

for (const requiredApiResponseText of [
  "def api_error",
  "def api_ok",
  "\"code\"",
  "\"params\"",
  "phone_not_paired",
  "agent_push_token_invalid"
]) {
  if (!backendApiResponse.includes(requiredApiResponseText)) {
    throw new Error(`Backend API response helper missing: ${requiredApiResponseText}`);
  }
}

for (const requiredBackendCode of [
  "api_error(\"agent_push_token_invalid\"",
  "api_error(\"mobile_status_publish_failed\"",
  "api_error(\"phone_not_paired\"",
  "api_error(\"mqtt_not_initialized\"",
  "api_error(\"mqtt_not_connected\"",
  "api_ok(\"mobile_test_published\"",
  "api_ok(\"agent_push_published\""
]) {
  if (![backendMain, backendMqtt].some((content) => content.includes(requiredBackendCode))) {
    throw new Error(`Backend API code/params response missing: ${requiredBackendCode}`);
  }
}

for (const packageDiscoveryContract of [
  "fs.readdirSync(backendSrc, { withFileTypes: true })",
  'entry.name.endsWith(".py")',
  '!entry.name.startsWith("test_")',
  "entry.isDirectory()",
  '"__init__.py"',
  'const backendDataEntries = ["web_source_sites.tsv"]',
  "...backendDataEntries",
  "for (const entry of backendEntries)"
]) {
  if (!packager.includes(packageDiscoveryContract)) {
    throw new Error(`Packaged Desktop backend auto-discovery is incomplete: ${packageDiscoveryContract}`);
  }
}

for (const capabilityContract of [
  [backendDesktopAgentLoop, "class AgentLoopPhase"],
  [backendDesktopAgentLoop, "class AgentLoopBudget"],
  [backendDesktopAgentLoop, "class AgentLoopObservation"],
  [backendDesktopControl, "class DesktopControlManager"],
  [backendDesktopMemory, "class DesktopMemoryStore"],
  [backendDesktopMcp, "class DesktopMcpRegistry"],
  [backendMcpSecurity, "class McpAuditStore"],
  [backendMcpSecurity, "sanitize_mcp_parameters"],
  [backendDesktopMcp, "explicit_user_selection"],
  [backendDesktopRuntime, "class DesktopRuntimeManager"],
  [backendDesktopSkills, "class DesktopSkillRegistry"],
  [backendDesktopSuperAgent, "Using relevant long-term memory"]
]) {
  if (!capabilityContract[0].includes(capabilityContract[1])) {
    throw new Error(`Desktop super-agent capability is incomplete: ${capabilityContract[1]}`);
  }
}

for (const mcpGovernanceContract of [
  [backendMcpSecurity, "class McpPermissionMode"],
  [backendMcpSecurity, "class McpAuditStore"],
  [backendDesktopMcp, "permission_mode"],
  [backendDesktopMcp, "parameter_preview"],
  [androidMcpSecurity, "enum class AgentMcpPermissionMode"],
  [androidMcpSecurity, "class EncryptedAgentMcpAuditStore"],
  [androidMcpRuntime, "explicit_user_approval"],
  [workspaceRenderer, "mcpAudit"],
  [html, "mcpPermissionMode"]
]) {
  if (!mcpGovernanceContract[0].includes(mcpGovernanceContract[1])) {
    throw new Error(`MCP permission and audit governance is incomplete: ${mcpGovernanceContract[1]}`);
  }
}

for (const executionPresentationContract of [
  [backendTaskManager, "\"execution_view\""],
  [backendMqtt, "\"execution_view\""],
  [workspaceRenderer, "function taskExecutionView"],
  [workspaceRenderer, "data-cancel-task"],
  [androidExecutionPresentation, "data class AgentExecutionPresentation"],
  [androidExecutionPresentation, "fun isCancellable"],
  [androidMainActivity, "agentExecutionPresentations"],
  [androidChatSources, "agent_execution_cancel"]
]) {
  if (!executionPresentationContract[0].includes(executionPresentationContract[1])) {
    throw new Error(`Unified Agent execution presentation is incomplete: ${executionPresentationContract[1]}`);
  }
}

for (const taskIntentContract of [
  [backendExecutionHarness, "class AgentTaskIntent"],
  [backendExecutionHarness, "def classify_task_intent"],
  [backendExecutionHarness, "\"task_intent\""],
  [androidTaskIntent, "enum class AgentTaskIntent"],
  [androidTaskIntent, "object AgentTaskIntentClassifier"],
  [androidTaskIntent, "PHONE_CONTROL"],
  [androidTaskIntent, "DESKTOP_CONTROL"]
]) {
  if (!taskIntentContract[0].includes(taskIntentContract[1])) {
    throw new Error(`Unified task intent classification is incomplete: ${taskIntentContract[1]}`);
  }
}

for (const taskBudgetContract of [
  [backendExecutionHarness, "class AgentTaskBudget"],
  [backendExecutionHarness, "requested_task_budget"],
  [backendExecutionHarness, "\"task_budget\""],
  [backendMain, "task_budget: dict"],
  [backendMain, "requested_task_budget=req.task_budget"],
  [backendMqtt, "payload.get(\"task_budget\")"],
  [main, "task_budget:"],
  [workspaceRenderer, "taskBudget: state.taskBudget"],
  [html, 'id="taskBudgetSettingsProfile"'],
  [androidTaskBudget, "data class AgentTaskBudget"],
  [androidTaskBudget, "object AgentTaskBudgetPolicy"],
  [androidMqtt, ".put(\"task_budget\""]
]) {
  if (!taskBudgetContract[0].includes(taskBudgetContract[1])) {
    throw new Error(`Cross-platform task budget is incomplete: ${taskBudgetContract[1]}`);
  }
}

for (const runtimeContract of [
  "galaxyssi.desktop-runtime/1.0",
  "code.python.run",
  "media.video.process",
  "browser.automate",
  "speech.transcribe",
  "speech.synthesize",
  "def resolve_executable("
]) {
  if (!backendDesktopRuntime.includes(runtimeContract)) {
    throw new Error(`Desktop runtime manager contract missing: ${runtimeContract}`);
  }
}
for (const runtimeIntegration of [
  [backendMain, '@app.get("/api/desktop-runtime")'],
  [backendDesktopNativeTools, "galaxyssi.desktop.runtime.status"],
  [main, "/api/desktop-runtime?refresh="],
  [preload, "getRuntimeDiagnostics: (refresh = false)"],
  [html, 'id="runtimeManagerList"'],
  [workspaceRenderer, "refreshRuntimeManager"],
  [packager, "fs.readdirSync(backendSrc, { withFileTypes: true })"]
]) {
  if (!runtimeIntegration[0].includes(runtimeIntegration[1])) {
    throw new Error(`Desktop runtime manager integration missing: ${runtimeIntegration[1]}`);
  }
}

for (const phase of ["PLAN", "ACT", "OBSERVE", "REPLAN", "VERIFY", "FINALIZE", "LEARN"]) {
  if (!backendDesktopAgentLoop.includes(`${phase} =`)) {
    throw new Error(`Desktop Agent loop phase is missing: ${phase}`);
  }
}

if (!backendMqtt.includes("warm_codex_app_server") || !backendMqtt.includes("_trace_metrics")) {
  throw new Error("Desktop task bridge must prewarm Codex and preserve millisecond latency metrics");
}

if (!backendDesktopFileTools.includes("try_execute_explicit_file_task") || !backendDesktopFileTools.includes("Excel.Application")) {
  throw new Error("Desktop explicit file conversion tool is incomplete");
}

for (const contract of [
  "galaxyssi.desktop-native-tools/1.2",
  "galaxyssi.desktop.windows.system.status",
  "galaxyssi.desktop.windows.app.list",
  "galaxyssi.desktop.windows.app.launch",
  "galaxyssi.desktop.files.search",
  "galaxyssi.desktop.browser.open",
  "galaxyssi.desktop.web.fetch",
  "galaxyssi.desktop.workspace.file.write.text",
  "galaxyssi.desktop.terminal.run",
  "galaxyssi.desktop.office.document.convert",
  "canonical_input_sha256",
  "idempotency_key_required"
]) {
  if (!backendDesktopNativeTools.includes(contract)) {
    throw new Error(`Desktop native tool contract missing: ${contract}`);
  }
}

for (const taskContract of [
  "/api/desktop/tasks/{task_id}/retry",
  "/api/desktop/tasks/{task_id}/recover",
  "attachments=attachments",
  "retry_of=str(req.retry_of",
  "desktop_native_tool_registry().cancel_task",
  "AgentFailureRecoveryAction.SWITCH_AGENT",
  "AgentFailureRecoveryAction.DEGRADE"
]) {
  if (!backendMain.includes(taskContract)) {
    throw new Error(`Desktop task recovery contract missing: ${taskContract}`);
  }
}

for (const rendererContract of ["recoverDesktopTask", "data-recovery-task", "task.attachments"]) {
  if (!workspaceRenderer.includes(rendererContract) && !preload.includes(rendererContract)) {
    throw new Error(`Desktop task recovery UI missing: ${rendererContract}`);
  }
}

for (const recoveryContract of [
  [backendAgentFailureRecovery, "class AgentFailureRecoveryAction"],
  [backendAgentFailureRecovery, "def recovery_choices("],
  [backendAgentFailureRecovery, "def failure_diagnostic("],
  [backendMqtt, "\"recovery_actions\""],
  [androidAgentFailureRecovery, "enum class AgentFailureRecoveryAction"],
  [androidAgentFailureRecovery, "object AgentFailureRecoveryPolicy"],
  [androidChatSources, "\"recover_agent_task\""]
]) {
  if (!recoveryContract[0].includes(recoveryContract[1])) {
    throw new Error(`Cross-platform failure recovery is incomplete: ${recoveryContract[1]}`);
  }
}

for (const responseSelfCheckContract of [
  [backendResponseSelfCheck, "def evaluate_response("],
  [backendResponseSelfCheck, "def response_repair_prompt("],
  [backendGateway, "response_self_check_contract("],
  [backendMqtt, "schedule_response_repair("],
  [backendDesktopSuperAgent, "\"response_self_check\""],
  [androidResponseSelfCheck, "object AgentResponseSelfCheck"],
  [androidChatSources, "AgentResponseSelfCheck.evaluate("]
]) {
  if (!responseSelfCheckContract[0].includes(responseSelfCheckContract[1])) {
    throw new Error(`Cross-platform latest-request response self-check is incomplete: ${responseSelfCheckContract[1]}`);
  }
}

for (const collaborationContract of [
  [backendAgentCollaboration, "class AgentCollaborationBus"],
  [backendAgentCollaboration, "direct_messages"],
  [backendAgentCollaboration, "scoped_broadcasts"],
  [backendAgentCollaboration, "repository_channels"],
  [backendGateway, "collaboration_channel_ids"],
  [backendMain, "/api/agent-runtime/channels"],
  [backendMain, "agent_collaboration_bus().health()"]
]) {
  if (!collaborationContract[0].includes(collaborationContract[1])) {
    throw new Error(`Desktop Agent collaboration contract is incomplete: ${collaborationContract[1]}`);
  }
}

for (const fileAccessContract of [
  [backendAgentFileAccess, "class AgentFileAccessLedger"],
  [backendAgentFileAccess, "read_sets"],
  [backendAgentFileAccess, "write_sets"],
  [backendAgentFileAccess, "conflict_notifications"],
  [backendMain, "/api/agent-runtime/file-access"],
  [backendMain, "/api/agent-runtime/file-conflicts"]
]) {
  if (!fileAccessContract[0].includes(fileAccessContract[1])) {
    throw new Error(`Desktop Agent file access contract is incomplete: ${fileAccessContract[1]}`);
  }
}

for (const routeContract of [
  "desktop_tool_call_request",
  "desktop_tool_call_result",
  "DESKTOP_TOOL_REQUEST_SLOTS",
  "scoped_workspace_id"
]) {
  if (!backendMqtt.includes(routeContract)) {
    throw new Error(`Encrypted Desktop tool routing missing: ${routeContract}`);
  }
}

if (!backendMain.includes("custom_agent: dict[str, str]") || !backendAgentConfig.includes("def custom_agent_config") || !backendAgentConfig.includes("def custom_agent_configs")) {
  throw new Error("Agent config API must persist Custom Agent display metadata");
}

if (!backendAgentConfig.includes('"name": "Local LLM"')) {
  throw new Error("Agent config must persist Local model display name");
}

if (
  !backendCustomAgent.includes("def read_prompt")
  || !backendMcpWrapper.includes("call_mcp_tool")
  || !backendMcpTransport.includes('"tools/call"')
  || !backendMcpTransport.includes("streamable_http")
) {
  throw new Error("Backend must include runnable Custom Agent and MCP wrapper scripts");
}

for (const capability of ["model_display_names", "local_model_endpoint_probe", "mobile_cloud_models", "mcp_stdio_wrapper", "multiple_custom_agents", "agent_execution_log", "api_response_codes", "agent_diagnostics_codes"]) {
  if (!backendMain.includes("/api/agents/diagnostics") || !backendGateway.includes(capability)) {
    throw new Error(`Backend diagnostics must advertise capability: ${capability}`);
  }
}

for (const acpContract of [
  [backendAcpRuntime, "class AcpRuntime"],
  [backendAcpRuntime, "spawn_agent_process"],
  [backendAcpRuntime, "request_permission"],
  [backendAcpRuntime, "load_session"],
  [backendGateway, "managed_acp_runtime"],
  [backendMain, "/api/acp-runtime"],
  [workspaceRenderer, "saveAcpRuntimeSettings"],
  [html, 'id="acpRuntimeList"']
]) {
  if (!acpContract[0].includes(acpContract[1])) {
    throw new Error(`Desktop ACP runtime contract is incomplete: ${acpContract[1]}`);
  }
}

for (const diagnosticsField of ["detail_code", "detail_params", "setup_code", "setup_params", "pairing_code", "pairing_params"]) {
  if (!backendGateway.includes(`"${diagnosticsField}"`)) {
    throw new Error(`Agent diagnostics must include structured i18n field: ${diagnosticsField}`);
  }
}

for (const selfTestField of ['"code": "agent_call_test_disabled"', '"code": "mobile_delivery_test_disabled"', '"code": "agent_not_ready"']) {
  if (!backendGateway.includes(selfTestField)) {
    throw new Error(`Agent self-test must include structured result code: ${selfTestField}`);
  }
}

for (const removedDefaultCloudUi of ['contact: cloud-model', '<option value="cloud-model">']) {
  if (html.includes(removedDefaultCloudUi)) {
    throw new Error(`Desktop must not expose Cloud Model as a default phone contact: ${removedDefaultCloudUi}`);
  }
}

if (renderer.includes("my_agent.py") || html.includes("my_agent.py")) {
  throw new Error("Custom Agent templates must point to packaged runnable scripts, not my_agent.py");
}

for (const oldProtocolType of ["hermes_signal_verify", "hermes_pairing_claim"]) {
  if (backendSignalClient.includes(oldProtocolType) || backendMqtt.includes(oldProtocolType)) {
    throw new Error(`Old protocol type must not be used: ${oldProtocolType}`);
  }
}

for (const requiredText of [
  "/api/agents/config",
  "/api/agents/diagnostics",
  "/api/agents/self-test",
  "/api/mobile/test-message",
  "/api/agent/push",
  "AgentPushReq",
  "verify_agent_push_token",
  "publish_agent_push_message",
  "agent_push_token",
  "galaxyssi_notify.py",
  "galaxyssi-notify.bat",
  "X-GalaxySSI-Token",
  "/api/agents/sync-mobile-status",
  "runtime:diagnostics",
  "getRuntimeDiagnostics",
  "getPairingStatus",
  "clearPairing",
  "saveAgentConfig",
  "getAgentDiagnostics",
  "getAgentExecutionLog",
  "runAgentSelfTest",
  "testAgent",
  "sendMobileTest",
  "syncMobileStatus",
  "Sync phone status",
  "Super agent",
  "New task",
  "Mobile Gateway",
  "conversationStream",
  "promptInput",
  "/api/pairing/status",
  "/api/pairing/clear",
  "pairedClientList",
  "galaxyssi_verify",
  "opaque_pairing",
  "connector_agents",
  "publish_connector_status",
  "publish_pairing_revoked",
  "forgotten_by_desktop",
  "GALAXYSSI_ALLOW_UNPAIRED_MQTT",
  "Phone is not paired",
  "agentContactList",
  "desktopControlAuditList",
  "Recent access history",
  "agent-execution.jsonl",
  "/api/agents/execution-log",
  "prompt_sha256",
  "local_process",
  "startDesktopTask",
  "listDesktopTasks",
  "cancelDesktopTask",
  "deleteDesktopConversation",
  "/api/desktop/tasks",
  "DesktopTaskStartReq",
  "conversation_messages",
  "customAgentId",
  "saveCustomAgentButton",
  "multiple_custom_agents",
  "Ollama Local",
  "LM Studio",
  "custom_agent_stdio.py",
  "mcp_agent_wrapper.py",
  "custom_agent",
  "clipboard:write",
  "backend dependencies",
  "custom-agent",
  "CUSTOM_AGENT_OK",
  "package:win",
  "package:win:python",
  "smoke",
  "smoke:pairing",
  "smoke:ui",
  "smoke:android-ui",
  "smoke:android-friends",
  "smoke:android-contact-rename",
  "smoke:android-contact-tags",
  "smoke:android-language",
  "smoke:android-cloud-models",
  "smoke:android-background",
  "smoke:android-agent-replies",
  "smoke:android-backup",
  "smoke:android-voice-reply",
  "smoke:android-voice-settings",
  "smoke:android-reset",
  "smoke:mqtt-persistence",
  "smoke:agent-push",
  "smoke:voice-stt",
  "smoke:e2e",
  "smoke:packaged",
  "status:connectors",
  "GalaxySSI Connector Status",
  "Connector Matrix",
  "GalaxySSI Link Protocol v1.0.3",
  "CLAUDE_SMOKE_OK",
  "LOCAL_E2E_OK",
  "MCP_E2E_OK",
  "requiredBackendCapabilities",
  "local_model_endpoint_probe",
  "mobile_cloud_models",
  "OpenAI-compatible models API",
  "Local model should not be ready when configured endpoint is unreachable",
  "stale backend detected",
  "fake_mcp_server.py",
  "LOCAL_SMOKE_OK",
  "assertNoSmokeConfigLeak",
  "assertNoE2eConfigLeak",
  "Execution log missing contact",
  "restoreConfigSnapshot",
  "withGalaxySSILock",
  "acquireGalaxySSILock",
  "Run these scripts sequentially",
  "packageDir",
  "--bundle-python",
  "ensureSignalSidecarRuntime",
  "runGradle",
  "installDist",
  "copyRecursive(path.join(root, \"docs\")",
  "Packaged connector status doc",
  "Packaged UI smoke screenshot",
  "android-agent-page.xml",
  "galaxyssi_debug_service_payload",
  "galaxyssi_debug_open_contact",
  "galaxyssi_debug_open_contact_detail",
  "galaxyssi_debug_open_new_friends",
  "galaxyssi_debug_open_group",
  "galaxyssi_debug_open_create_group",
  "galaxyssi_debug_open_device",
  "galaxyssi_debug_open_automation",
  "galaxyssi_debug_open_local_model",
  "galaxyssi_debug_open_cloud_providers",
  "galaxyssi_debug_open_cloud_provider",
  "ChatHistoryStore.appendIncoming",
  "ChatHistoryStore.markNotified",
  "AppForegroundTracker.isForeground",
  "galaxyssi_chat_history.db",
  "galaxyssi_debug_chat_history_probe_b64",
  "encrypted_sqlite",
  "galaxyssi_app_store",
  "galaxyssi_signal_trust",
  "galaxyssi_signal_store",
  "ChatHistoryStore.updatedVersion",
  "reloadChatHistoryIfChanged",
  "android-background-message.xml",
  "BG_SERVICE_",
  "background_history",
  "system_notification",
  "markContactRead",
  "clean_session_recovery_ok",
  "clean_session=True",
  "subscription_ack_timeout",
  "MAX_ATTACHMENT_OUTBOX_DELIVERY_ATTEMPTS",
  "newClientId()",
  "client_message_id",
  "delivery_trace",
  "delivery_ack",
  "build_delivery_ack_payload",
  "applyDeliveryAck",
  "desktop_reply_publish_queued",
  "desktop_reply_broker_ack",
  "desktop_broker_ack",
  "desktop_agent_push_queued",
  "deliveryTrace",
  "galaxyssi_debug_pairing",
  "galaxyssi_debug_open_agents",
  "galaxyssi_debug_approve_friend",
  "galaxyssi_debug_delete_contact",
  "approveFriendRequestForGalaxySSIId",
  "previously_deleted",
  "readd_required",
  "re-added contact did not store readded_at evidence",
  "galaxyssi_debug_rename_contact",
  "galaxyssi_debug_rename_name_b64",
  "user_renamed",
  "smoke:android-contact-rename",
  "galaxyssi_debug_open_contacts",
  "Tag Agent Smoke",
  "Tag Model Smoke",
  "Tag Device Smoke",
  "smoke:android-contact-tags",
  "galaxyssi_debug_open_language_settings",
  "android-language-default.xml",
  "smoke:android-language",
  "galaxyssi_debug_cloud_models_roundtrip",
  "cloud_models_roundtrip_result",
  "CLOUD_API_REPLY_",
  "direct_mobile_cloud_api",
  "adb([\"reverse\"",
  "deepseek-v4-flash",
  "smoke:android-cloud-models",
  "galaxyssi_debug_open_voice_settings",
  "galaxyssi_debug_open_backup_export",
  "galaxyssi_debug_open_backup_import",
  "galaxyssi_debug_open_destroy_data",
  "galaxyssi_debug_destroy_all_data",
  "smoke:android-agent-replies",
  "AGENT_REPLY_TAIL",
  "galaxyssi_debug_backup_roundtrip",
  "BACKUP_ROUNDTRIP_MESSAGE",
  "ADB transient failure",
  "galaxyssi_debug_open_messages",
  "hasTraceStage(message, \"read\")",
  "unread badge 1",
  "list timestamp",
  "bubble or divider timestamp",
  "smoke:android-backup",
  "smoke:android-reset",
  "smoke:android-voice-reply",
  "VOICE_REPLY_TAIL",
  "galaxyssi_debug_voice_settings_roundtrip",
  "voice_settings_roundtrip_result",
  "zh-CN-XiaoxiaoNeural",
  "smoke:android-voice-settings",
  "Destructive reset did not rotate the local Signal identity store",
  "GALAXYSSI_WHISPER_MODEL",
  "GALAXYSSI_WHISPER_DEVICE",
  "GALAXYSSI_WHISPER_COMPUTE_TYPE",
  "VOICE_STT_SMOKE",
  "clean_audio_reply",
  "galaxyssi_debug_open_protocol_quality",
  "galaxyssi_debug_open_signal_link_protocol",
  "galaxyssi_debug_open_advanced_options",
  "galaxyssi_backup",
  "Research Agent",
  "GALAXYSSI_UI_SMOKE_DIR",
  "app.setPath(\"userData\"",
  "desktop-language-en.png",
  "desktop-language-zh.png",
  "Desktop did not follow the system language by default",
  "Desktop Simplified Chinese language switch failed",
  "responseLanguageSelect",
  "asrLanguageSelect",
  "ttsLanguageSelect",
  "response_language",
  "GALAXYSSI_PYTHON",
  "GALAXYSSI_PYTHON_VENV",
  "resources\\\\python\\\\venv\\\\Scripts\\\\python.exe",
  "win-x64",
  "install-backend-deps.bat",
  "scripts/smoke.js",
  "GalaxySSI Link Protocol",
  "agent_task_manager.py",
  "/api/agent/tasks",
  "agent_task_event",
  "agent_task_cancel",
  "status_seq",
  "pending_task_events",
  "taskStatusSeq",
  "smoke:agent-lifecycle"
]) {
if (![main, preload, html, renderer, workspaceRenderer, packageJson, packager, androidAdb, smoke, smokePairing, smokeUi, smokeAndroidUi, smokeAndroidFriends, smokeAndroidContactTags, smokeAndroidLanguage, smokeAndroidCloudModels, smokeAndroidBackground, smokeAndroidAgentReplies, smokeAndroidBackup, smokeAndroidVoiceReply, smokeAndroidReset, smokeMqttPersistence, smokeAgentPush, smokeAgentLifecycle, smokeVoiceStt, smokeE2e, smokePackaged, smokeLock, connectorStatus, statusDoc, backendMain, backendMqtt, backendPairing, backendLinkProtocol, backendGateway, backendTaskManager, backendAgentConfig, backendPushAuth, backendGalaxySSINotify, backendStt, androidChatSources, androidMqtt, androidMessageService, androidChatHistoryStore, androidChatHistoryDatabase, androidDebugChatHistoryProbe, androidChatHistoryProbeScript, androidSignalStore, androidForegroundTracker, androidAppStore].some((content) => content.includes(requiredText))) {
    throw new Error(`Missing desktop connector capability: ${requiredText}`);
  }
}

for (const smokeSource of [
  smokeAndroidUi,
  smokeAndroidCloudModels,
  smokeAndroidBackground,
  smokeAndroidAgentReplies,
  smokeAndroidBackup,
  smokeAndroidVoiceReply,
  smokeAndroidReset
]) {
  if (smokeSource.includes("galaxyssi_chat_history.xml")) {
    throw new Error("Android smoke tests must not read the removed legacy chat history XML");
  }
}

for (const mojibake of ["\u95ba", "\u95c1", "\u95c2", "\u5a75", "\u7f02", "\u6fde\u5b58\u7c8d\u9368", "\u95b8", "\u95b9"]) {
  if (html.includes(mojibake) || renderer.includes(mojibake) || workspaceRenderer.includes(mojibake)) {
    throw new Error(`Renderer contains mojibake text: ${mojibake}`);
  }
}

for (const cloudSettingId of [
  "cloudProvider",
  "cloudDisplayName",
  "cloudEndpoint",
  "cloudModelId",
  "cloudApiKey",
  "cloudContextWindow",
  "cloudOutputReserve",
  "cloudModelSummary",
  "saveCloudModelButton",
  "testCloudModelButton"
]) {
  if (!html.includes(`id="${cloudSettingId}"`)) {
    throw new Error(`Desktop cloud API setting is missing: ${cloudSettingId}`);
  }
}

for (const cloudSettingContract of [
  "CLOUD_PROVIDER_PRESETS",
  "validateCloudModelSettings",
  "saveCloudModelSettings",
  "context_window_tokens",
  "max_output_tokens",
  "context_model_summary",
  'testAgent("cloud-model"'
]) {
  if (!workspaceRenderer.includes(cloudSettingContract)) {
    throw new Error(`Desktop cloud API behavior is missing: ${cloudSettingContract}`);
  }
}

if (main.includes('id: "claude-code"')) {
  throw new Error("Claude contact id must be claude");
}

if (
  !main.includes('ipcMain.handle("tts:synthesize"')
  || !preload.includes('ipcRenderer.invoke("tts:synthesize"')
  || !backendMain.includes('@app.post("/api/tts/synthesize")')
  || !backendMain.includes("require_desktop_api_token(request)")
  || !backendTts.includes('"zh-CN-XiaoxiaoNeural"')
  || !workspaceRenderer.includes("window.galaxyssi.synthesizeSpeech")
  || workspaceRenderer.includes("window.speechSynthesis.speak(utterance)")
) {
  throw new Error("Desktop reply playback must use authenticated Microsoft Edge TTS");
}

if (backendGateway.includes("return [*command, text], None")) {
  throw new Error("Desktop connector must not append prompt text to command-line arguments by default");
}

if (backendCustomAgent.includes("Received: {prompt}")) {
  throw new Error("Custom Agent template must not echo the full user prompt");
}

if (androidMainActivity.includes("publishGroupTextMessage(") || androidMainActivity.includes("AppStore.createGroup(") || androidMainActivity.includes("createGroupWithMembers(")) {
  throw new Error("Group chat is deferred and must not be callable from Android UI");
}

if (androidMainActivity.includes("AppStore.ensureIncomingGroup(") || androidChatHistoryStore.includes("AppStore.ensureIncomingGroup(")) {
  throw new Error("Group chat is deferred; incoming messages must not auto-create group contacts");
}

for (const requiredDeferredGroupText of [
  "badge_unavailable",
  "group_feature_status_subtitle",
  "Group chat implementation is not enabled in this version"
]) {
  if (![androidChatSources, androidStringsEn].some((content) => content.includes(requiredDeferredGroupText))) {
    throw new Error(`Deferred group UI marker missing: ${requiredDeferredGroupText}`);
  }
}

for (const promptPrivacyText of [
  "Prompt text is sent through stdin by default",
  "Request received. Custom Agent is connected."
]) {
  if (![html, renderer, backendGateway, backendCustomAgent].some((content) => content.includes(promptPrivacyText))) {
    throw new Error(`Missing prompt privacy marker: ${promptPrivacyText}`);
  }
}

for (const [label, content] of [
  ["MainActivity", androidMainActivity],
  ["AppStore", androidAppStore],
  ["GalaxySSIMqttClient", androidMqtt]
]) {
  if (content.includes('.put("hermes_id"')) {
    throw new Error(`${label} must not write hermes_id; use galaxyssi_id`);
  }
}

if (androidMainActivity.includes("Hermes ID")) {
  throw new Error("Android UI must display GalaxySSI ID, not Hermes ID");
}

if (androidMqtt.includes("hermeschat-android")) {
  throw new Error("Android MQTT client id must use GalaxySSI naming");
}

if ([androidChatSources, androidAppStore, androidStringsZh, androidStringsEn].some((content) => content.includes("hermes_backup"))) {
  throw new Error("New Android backup artifacts must use GalaxySSI naming, not hermes_backup");
}

for (const file of listFilesRecursive(androidSourceRoot)) {
  const relative = path.relative(workspaceRoot, file).replace(/\\/g, "/");
  const oldBrandToken = "signal" + "ai";
  if (relative.toLowerCase().includes(oldBrandToken)) {
    throw new Error(`Android resource path must use GalaxySSI naming: ${relative}`);
  }
  if (!/\.(kt|xml|gradle|properties|txt)$/i.test(file)) continue;
  const content = fs.readFileSync(file, "utf8");
  if (content.toLowerCase().includes(oldBrandToken)) {
    throw new Error(`Android source must use GalaxySSI naming: ${relative}`);
  }
  for (const oldAndroidInternalName of ["hermes_dark", "DEFAULT_HERMES_SEND_TOPIC"]) {
    if (content.includes(oldAndroidInternalName)) {
      throw new Error(`Android internal resource/constant must use GalaxySSI naming: ${relative}`);
    }
  }
}

for (const requiredAndroidGalaxySSIText of [
  "galaxyssi_id",
  "localGalaxySSIId",
  "opaque_contact",
  "GalaxySSI ID"
]) {
  if (![androidChatSources, androidAppStore, androidCrypto, androidMqtt, androidStringsZh, androidStringsEn].some((content) => content.includes(requiredAndroidGalaxySSIText))) {
    throw new Error(`Android GalaxySSI identity implementation missing: ${requiredAndroidGalaxySSIText}`);
  }
}

for (const requiredVoicePipelineText of [
  "sendVoiceRecordingThroughPipeline",
  "ASR_PROVIDER_LOCAL_WHISPER",
  "LocalWhisperAsr.transcribe",
  "WhisperModelManager",
  "voice_asr_provider",
  "SUPPORTED_WAKE_MODELS",
  "DEFAULT_WAKE_MODEL"
]) {
  if (![androidChatSources, androidVoiceSettings, androidLocalWhisper, androidWhisperModels, androidStringsZh, androidStringsEn].some((content) => content.includes(requiredVoicePipelineText))) {
    throw new Error(`Android voice pipeline missing: ${requiredVoicePipelineText}`);
  }
}

for (const requiredWorkspaceText of [
  "GalaxySSI_Workspace",
  "task_workspace(task_id, spec.id)",
  "cwd=str(execution_directory)",
  "restricted_workspace=True",
  "GALAXYSSI_OUTPUT_DIR",
  "task_workspace(task.task_id, agent_id)"
]) {
  if (![backendTaskWorkspace, backendGateway, backendMqtt].some((content) => content.includes(requiredWorkspaceText))) {
    throw new Error(`Agent task workspace isolation missing: ${requiredWorkspaceText}`);
  }
}

if (backendMqtt.includes("server.start_task(task.task_id, content, os.getcwd())")) {
  throw new Error("Codex tasks must not run in the backend source directory");
}

for (const requiredEvolutionText of [
  "class EvolutionHealth",
  "def evolution_health(",
  "\"candidate_changed_after_review\"",
  "\"candidate_dirty_after_review\"",
  "\"health\": manager.health(limit=500).public()"
]) {
  if (![backendEvolutionManager, backendEvolutionLegacy, backendEvolutionV2Manager, backendMain]
    .some((content) => content.includes(requiredEvolutionText))) {
    throw new Error(`Evolution audit or candidate integrity guard missing: ${requiredEvolutionText}`);
  }
}

for (const requiredEvolutionV2Text of [
  "class EvolutionManager(legacy.EvolutionManager)",
  "class TechnologyRadar",
  "class RoadmapPlanner",
  "class AuditLedger",
  "loopback_required",
  "auto_merge",
  "recover_interrupted"
]) {
  if (![backendEvolutionV2Manager, backendEvolutionV2Api,
    ...fs.readdirSync(path.join(backendDir, "evolution_v2"))
      .filter((name) => name.endsWith(".py"))
      .map((name) => fs.readFileSync(path.join(backendDir, "evolution_v2", name), "utf8"))]
    .some((content) => content.includes(requiredEvolutionV2Text))) {
    throw new Error(`Self-evolution V2 contract missing: ${requiredEvolutionV2Text}`);
  }
}

for (const requiredEvolutionUiText of [
  "evolutionHealthSummary",
  "renderEvolutionHealth",
  "gate_pass_percent",
  "attention_tasks"
]) {
  if (![html, workspaceRenderer].some((content) => content.includes(requiredEvolutionUiText))) {
    throw new Error(`Evolution health UI missing: ${requiredEvolutionUiText}`);
  }
}

for (const requiredSchedulerText of [
  "SchedulerConfigReq",
  "/scheduler/config",
  "evolutions_per_day",
  "execution_mode",
  "max_parallel_evolutions",
  "saveEvolutionScheduleButton",
  "runEvolutionNowButton"
]) {
  if (![main, backendEvolutionV2Api, backendEvolutionV2Scheduler, evolutionV2Panel]
    .some((content) => content.includes(requiredSchedulerText))) {
    throw new Error(`Self-evolution scheduler contract missing: ${requiredSchedulerText}`);
  }
}

if ([androidChatSources, androidVoiceSettings].some((content) => content.includes("galaxyssi.onnx"))) {
  throw new Error("Android voice wake settings must not expose unbundled wake model galaxyssi.onnx");
}

for (const requiredCloudModelText of [
  "sendOpenAiCompatible",
  "sendAnthropic",
  "sendGemini",
  "\"Authorization\" to \"Bearer",
  "\"x-api-key\"",
  "\"anthropic-version\"",
  "anthropic-dangerous-direct-browser-access",
  "URLEncoder.encode(contact.getString(\"cloud_api_key\")",
  "\"system_instruction\"",
  "\"contents\"",
  "\"generationConfig\"",
  "\"HTTP-Referer\"",
  "\"X-Title\""
]) {
  if (!androidCloudModelClient.includes(requiredCloudModelText)) {
    throw new Error(`Android direct cloud model client missing: ${requiredCloudModelText}`);
  }
}

console.log("GalaxySSI Desktop structure OK");
