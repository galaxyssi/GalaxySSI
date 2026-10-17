package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentInstalledAppLaunchPolicyTest {
    @Test fun chinesePhoneQualifiersAreNotPartOfTheAppName() {
        listOf("\u6253\u5f00\u624b\u673a\u4e0a\u7684\u8ba1\u7b97\u5668", "\u6253\u5f00\u6211\u7684\u624b\u673a\u4e0a\u7684\u8ba1\u7b97\u5668",
            "\u8bf7\u6253\u5f00\u672c\u673a\u7684\u8ba1\u7b97\u5668", "\u5728\u624b\u673a\u4e0a\u6253\u5f00\u8ba1\u7b97\u5668",
            "\u6253\u958b\u624b\u6a5f\u4e0a\u7684\u8ba1\u7b97\u5668").forEach { goal ->
            assertEquals(goal, "\u8ba1\u7b97\u5668", AgentInstalledAppLaunchPolicy.query(goal))
            assertTrue(goal, AgentInstalledAppLaunchPolicy.isPhoneLocalRequest(goal))
        }
    }

    @Test fun englishPhoneQualifiersAndAppSuffixCanBeCombined() {
        listOf("Open Calculator on my phone", "Launch Calculator app on this device", "Please start Calculator on the phone").forEach {
            assertEquals(it, "Calculator", AgentInstalledAppLaunchPolicy.query(it))
        }
    }

    @Test fun legitimateAppNamePrefixesArePreserved() {
        assertEquals("\u624b\u673a\u94f6\u884c", AgentInstalledAppLaunchPolicy.query("\u6253\u5f00\u624b\u673a\u94f6\u884c"))
        assertEquals("Phone Link", AgentInstalledAppLaunchPolicy.query("Open Phone Link"))
        assertEquals("My Phone", AgentInstalledAppLaunchPolicy.query("Open My Phone"))
    }

    @Test fun desktopRequestsAndEmptyNamesDoNotBecomePhoneLaunches() {
        assertFalse(AgentInstalledAppLaunchPolicy.isPhoneLocalRequest("Open Calculator on my computer"))
        assertFalse(AgentInstalledAppLaunchPolicy.isPhoneLocalRequest("\u6253\u5f00\u7535\u8111\u4e0a\u7684\u8ba1\u7b97\u5668"))
        assertFalse(AgentInstalledAppLaunchPolicy.isPhoneLocalRequest("\u6253\u5f00\u624b\u673a\u4e0a\u7684"))
        assertFalse(AgentInstalledAppLaunchPolicy.isPhoneLocalRequest("What can Calculator do?"))
    }

    @Test fun qualifiedRequestResolvesTheActualInstalledPackage() {
        val goal = "\u6253\u5f00\u624b\u673a\u4e0a\u7684\u8ba1\u7b97\u5668"
        val screen = ScreenContext("GalaxySSI", pageTitle = "Agent", installedApps = listOf(
            InstalledAppInfo("\u8ba1\u7b97\u5668", "com.sec.android.app.popupcalculator")
        ))
        val request = AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "launch-test", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList()))
        val action = RuleBasedAgentPlanner().deterministicLocalAction(request)
        assertEquals(AgentActionKind.OPEN_APP, action?.kind)
        assertEquals("com.sec.android.app.popupcalculator", action?.parameters?.get("package"))
        assertEquals("android-local", action?.parameters?.get("execution_scope"))
    }
}
