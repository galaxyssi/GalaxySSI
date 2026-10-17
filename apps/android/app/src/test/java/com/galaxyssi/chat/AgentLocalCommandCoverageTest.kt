package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class AgentLocalCommandCoverageTest {
    @Test fun framingDoesNotRemoveNegationConditionsOrQuestions() {
        assertTrue(AgentLocalCommandText.matches(" Please open settings! ", "open settings"))
        assertTrue(AgentLocalCommandText.matches("\u8bf7\u6253\u5f00wifi\u3002", "\u6253\u5f00wifi"))
        assertTrue(AgentLocalCommandText.matches("\u8bf7\u6c42vpn\u6743\u9650", "\u8bf7\u6c42vpn\u6743\u9650"))
        for (goal in listOf("Don't open settings", "Please don't open settings", "If needed, open settings",
            "Explain open settings", "open settings?", "open settings and check Wi-Fi", "\"open settings\"")) {
            assertFalse(goal, AgentLocalCommandText.matches(goal, "open settings"))
        }
    }

    @Test fun systemCommandsDoNotDropQualifiersOrAdditionalActions() {
        for (goal in listOf("Don't open wifi settings", "Explain how to clear text", "Do not paste clipboard",
            "If needed, go home", "Show recent apps after saving", "copy screen text only if approved",
            "open browser and search for Android", "open notification settings then explain each switch",
            "Do not open contacts", "Don't install apk", "Open current app permissions and turn off location")) {
            assertNull(goal, AgentSystemToolPlanner.actionFor(request(goal)))
        }
    }

    @Test fun explicitSystemCommandsKeepTheirExistingActions() {
        mapOf("Please open settings!" to "open-settings", "open wifi settings" to "open-wifi-settings",
            "go home" to "go-home", "clear text" to "clear-focused-text",
            "open browser" to "open-browser", "paste clipboard" to "paste-clipboard").forEach { (goal, id) ->
            assertEquals(goal, id, AgentSystemToolPlanner.actionFor(request(goal))?.id)
        }
    }

    @Test fun specializedPickerCannotPreemptAnExplanationOrCompositeTask() {
        for (goal in listOf("Don't pick file", "Explain how to select PDF", "select image after asking me",
            "\u4e0d\u8981\u9009\u62e9\u6587\u4ef6", "\u9009\u62e9\u56fe\u7247\u540e\u5206\u6790\u5176\u5185\u5bb9")) {
            assertNull(goal, AgentSpecializedAppPlanner.plan(request(goal)))
        }
        assertEquals("files", AgentSpecializedAppPlanner.plan(request("Please select PDF!"))?.profile)
        assertEquals("files", AgentSpecializedAppPlanner.plan(request("\u9009\u62e9\u6587\u4ef6"))?.profile)
    }

    @Test fun parameterlessNativeCommandsConsumeTheWholeRequest() {
        for (goal in listOf("Don't reboot this phone", "Explain how to mute media", "lock device after saving",
            "If Bluetooth is on, scan bluetooth", "Do not request vpn permission", "Don't remove download 12",
            "remove download 12 only if it failed", "dial 12345 then hang up", "Don't send sms to 12345: hello",
            "read sensor", "read gyroscope sensor and light sensor", "Read device status and compare with yesterday")) {
            val request = request(goal)
            assertNull(goal, RuleBasedAgentPlanner().androidSystemNativeToolAction(request))
            assertNull(goal, RuleBasedAgentPlanner().deterministicLocalAction(request))
        }
    }

    @Test fun acceptedNativeCommandsKeepExactArguments() {
        val planner = RuleBasedAgentPlanner()
        mapOf("Please mute media!" to AgentAndroidSystemNativeTools.AUDIO_MUTE_SET,
            "reboot this phone" to AgentAndroidSystemNativeTools.DEVICE_POLICY_REBOOT,
            "read gyroscope sensor" to AgentHardwareNativeTools.SENSOR_SAMPLE,
            "download status 12" to AgentAndroidSystemNativeTools.DOWNLOAD_QUERY,
            "remove download 12" to AgentAndroidSystemNativeTools.DOWNLOAD_REMOVE,
            "download https://example.com/report.pdf" to AgentAndroidSystemNativeTools.DOWNLOAD_ENQUEUE,
            "Dial 12345" to AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF).forEach { (goal, id) ->
            assertEquals(goal, id, planner.androidSystemNativeToolAction(request(goal))?.parameters?.get("tool_id"))
        }
        val action = requireNotNull(planner.androidSystemNativeToolAction(request("read gyroscope sensor")))
        assertEquals("gyroscope", JSONObject(action.parameters.getValue("input_json")).getString("type"))
    }

    @Test fun urlsAreSingleValidatedArgumentsNotSubstringsOfInstructions() {
        assertEquals("https://example.com/a%20b?x=1", AgentLocalCommandText.httpUrl("example.com/a%20b?x=1"))
        assertEquals("https://example.com/a.pdf", AgentLocalCommandText.downloadUrl("download https://example.com/a.pdf"))
        for (goal in listOf("download https://example.com/a.pdf and summarize it", "Don't download https://example.com/a.pdf",
            "download https://example.com/a.pdf\nthen open it", "download https://")) {
            assertNull(goal, AgentLocalCommandText.downloadUrl(goal))
        }
        for (goal in listOf("open website example.com and summarize it", "open url https://", "browse example.com then close it")) {
            assertNull(goal, AgentSpecializedAppPlanner.plan(request(goal)))
            assertNull(goal, AgentSystemToolPlanner.actionFor(request(goal)))
        }
    }

    @Test fun namedAppSettingsRequireACompleteUniqueIdentity() {
        val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Agent", installedApps = listOf(
            InstalledAppInfo(packageName = "org.calc.one", label = "Calculator"), InstalledAppInfo(packageName = "org.calc.two", label = "Calculator Pro")))
        assertEquals("package:org.calc.one", AgentSystemToolPlanner.actionFor(request("open Calculator app settings", screen))?.parameters?.get("uri"))
        assertNull(AgentSystemToolPlanner.actionFor(request("open Calc app settings", screen)))
        assertNull(AgentSystemToolPlanner.actionFor(request("open Calculator app settings and revoke permissions", screen)))
        val duplicate = screen.copy(installedApps = screen.installedApps + InstalledAppInfo(packageName = "org.calc.three", label = "Calculator"))
        assertNull(AgentSystemToolPlanner.actionFor(request("open Calculator app settings", duplicate)))
    }

    @Test fun alarmTimeCannotOverrideNegationOrOtherParameters() {
        assertEquals("07", AgentSystemToolPlanner.actionFor(request("set alarm 07:30"))?.parameters?.get("hour")?.padStart(2, '0'))
        for (goal in listOf("Don't set alarm 07:30", "set alarm 07:30 every Monday", "set alarm 07:30 and 08:00",
            "set alarm at 25:00", "set alarm")) assertNull(goal, AgentSystemToolPlanner.actionFor(request(goal)))
    }

    @Test fun rejectedWholeCommandsReachTheProviderWithoutAnEagerLocalEffect() {
        for (goal in listOf("Don't open settings, just explain what it does", "Explain how to clear text",
            "Do not select PDF", "Don't reboot this phone", "Don't remove download 12",
            "open wifi settings and then report the actual network state", "Do not swipe up")) {
            val plan = RuleBasedAgentPlanner().plan(request(goal))
            assertTrue(goal, plan.actions.isNotEmpty())
            assertTrue(goal, plan.actions.all { it.kind == AgentActionKind.CALL_CONNECTOR })
            assertTrue(goal, plan.actions.all { it.parameters["connector_id"] == "test-provider" })
            assertTrue(goal, plan.actions.all { it.parameters["prompt"].orEmpty().contains(goal) })
        }
    }

    private fun request(goal: String, screen: ScreenContext = ScreenContext("com.galaxyssi.chat", pageTitle = "Agent")): AgentRequest {
        val targets = listOf(AgentCallableTarget("test-provider", "Selected model", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.REASONING)))
        val descriptors = listOf(AgentAndroidSystemNativeTools.AUDIO_MUTE_SET, AgentAndroidSystemNativeTools.DEVICE_POLICY_REBOOT,
            AgentAndroidSystemNativeTools.DEVICE_POLICY_LOCK, AgentHardwareNativeTools.SENSOR_SAMPLE,
            AgentAndroidSystemNativeTools.DOWNLOAD_QUERY, AgentAndroidSystemNativeTools.DOWNLOAD_REMOVE,
            AgentAndroidSystemNativeTools.DOWNLOAD_ENQUEUE, AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF,
            AgentAndroidSystemNativeTools.SMS_SEND, AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND,
            AgentAndroidSystemNativeTools.VPN_CONSENT_OPEN).map { AgentNativeToolDescriptor(it, "1.0.0", it, it,
                AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.MEDIUM) }
        return AgentRequest(goal, screen, targets, memories = emptyList(), runtimeContext = AgentRuntimeContextBuilder.build(
            sessionId = "command-coverage", goal = goal, screen = screen, permissionMode = PermissionMode.AUTO_LOW_RISK,
            highRiskGuard = true, memoryCapture = false, callableTargets = targets, memories = emptyList(), nativeTools = descriptors))
    }
}
