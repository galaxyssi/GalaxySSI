package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentScreenObservationPolicyTest {
    @Test
    fun ordinaryCloudQuestionsDoNotCaptureThePhoneScreen() {
        assertFalse(AgentScreenObservationPolicy.requiresObservation("Hello, explain transformers briefly"))
        assertFalse(AgentScreenObservationPolicy.requiresObservation("What is the latest Shanghai weather?"))
        assertFalse(AgentScreenObservationPolicy.requiresObservation("\u4eca\u5929\u4e0a\u6d77\u5929\u6c14\u600e\u4e48\u6837"))
    }

    @Test
    fun visiblePhoneContextRequiresObservation() {
        assertTrue(AgentScreenObservationPolicy.requiresObservation("Summarize the current screen"))
        assertTrue(AgentScreenObservationPolicy.requiresObservation("\u5e2e\u6211\u70b9\u51fb\u5f53\u524d\u9875\u9762\u7684\u540c\u610f\u6309\u94ae"))
    }

    @Test
    fun phoneAppLaunchLoadsInstalledAppsButExplicitDesktopLaunchDoesNot() {
        assertTrue(AgentScreenObservationPolicy.requiresObservation("\u6253\u5f00\u5fae\u4fe1"))
        assertTrue(AgentScreenObservationPolicy.requiresObservation("Open Spotify"))
        assertFalse(AgentScreenObservationPolicy.requiresObservation("\u5728\u7535\u8111\u4e0a\u6253\u5f00\u5fae\u4fe1"))
        assertFalse(AgentScreenObservationPolicy.requiresObservation("Open WeChat on desktop"))
    }

    @Test
    fun selectedScreenActionRequiresObservationEvenForAmbiguousText() {
        val action = AgentAction(
            id = "tap",
            kind = AgentActionKind.TAP,
            target = "Continue",
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Continue"
        )

        assertTrue(AgentScreenObservationPolicy.requiresObservation("continue", action))
    }
}
