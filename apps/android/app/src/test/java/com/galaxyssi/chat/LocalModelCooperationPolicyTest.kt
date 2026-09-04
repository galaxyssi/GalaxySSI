package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelCooperationPolicyTest {
    @Test
    fun `manual local selection locks execution to the requested profile`() {
        val profiles = listOf(
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT,
            LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN
        )

        val eligible = LocalModelCooperationPolicy.eligibleProfiles(
            profiles,
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT.id
        )

        assertEquals(listOf(LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT), eligible)
    }

    @Test
    fun `automatic local selection keeps all available profiles`() {
        val profiles = listOf(
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT,
            LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN
        )

        assertEquals(profiles, LocalModelCooperationPolicy.eligibleProfiles(profiles, ""))
    }

    private val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
    private val qwenQairt = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT
    private val gemma = LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN
    private val fallback = LocalModelRuntimeProfiles.GEMMA_3_1B_Q4

    @Test
    fun simpleTaskUsesQwenWithoutThinkingWhenBothModelsAreEnabled() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.LOW),
            availableProfiles = listOf(qwen, gemma),
            fallbackProfile = fallback
        )

        assertNull(plan.plannerProfile)
        assertEquals(qwen.id, plan.answerProfile.id)
        assertEquals(LocalModelThinkingMode.NO_THINK, plan.answerThinkingMode)
        assertFalse(plan.cooperative)
    }

    @Test
    fun qairtQwenIsPreferredOverGgufQwen() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.LOW),
            availableProfiles = listOf(qwen, qwenQairt, gemma),
            fallbackProfile = fallback
        )

        assertEquals(qwenQairt.id, plan.answerProfile.id)
        assertEquals(LocalModelThinkingMode.NO_THINK, plan.answerThinkingMode)
    }

    @Test
    fun qairtFailureFallsBackToGgufBeforeGemma() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.LOW),
            availableProfiles = listOf(qwenQairt, qwen, gemma),
            fallbackProfile = fallback
        )

        assertEquals(
            listOf(qwen.id, gemma.id),
            LocalModelCooperationPolicy.fallbackProfiles(
                plan,
                listOf(qwenQairt, qwen, gemma)
            ).map(LocalModelRuntimeProfile::id)
        )
    }

    @Test
    fun complexTaskUsesThinkingQwenPlannerAndGemmaAnswer() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.MEDIUM),
            availableProfiles = listOf(qwen, gemma),
            fallbackProfile = fallback
        )

        assertEquals(qwen.id, plan.plannerProfile?.id)
        assertEquals(LocalModelThinkingMode.THINK, plan.plannerThinkingMode)
        assertEquals(gemma.id, plan.answerProfile.id)
        assertTrue(plan.cooperative)
    }

    @Test
    fun complexTaskUsesThinkingQwenWhenGemmaIsUnavailable() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.HIGH),
            availableProfiles = listOf(qwen),
            fallbackProfile = fallback
        )

        assertNull(plan.plannerProfile)
        assertEquals(qwen.id, plan.answerProfile.id)
        assertEquals(LocalModelThinkingMode.THINK, plan.answerThinkingMode)
    }

    @Test
    fun gemmaCanAnswerAloneWhenQwenIsUnavailable() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.MEDIUM),
            availableProfiles = listOf(gemma),
            fallbackProfile = fallback
        )

        assertEquals(gemma.id, plan.answerProfile.id)
        assertNull(plan.plannerProfile)
    }

    @Test
    fun legacySelectionIsPreservedWhenNoQnnModelIsEnabled() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.LOW),
            availableProfiles = listOf(fallback),
            fallbackProfile = fallback
        )

        assertEquals(fallback.id, plan.answerProfile.id)
        assertEquals(LocalModelThinkingMode.AUTOMATIC, plan.answerThinkingMode)
    }

    @Test
    fun structuredMultiStepChatIsPromotedToCooperativeReasoning() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.LOW),
            availableProfiles = listOf(qwen, gemma),
            fallbackProfile = fallback,
            userPrompt = "1. Inspect the input\n2. Compare the options\n3. Verify the result"
        )

        assertTrue(plan.cooperative)
        assertEquals(gemma.id, plan.answerProfile.id)
    }

    @Test
    fun qwenIsTheFirstFallbackWhenGemmaCannotCompleteAComplexTask() {
        val plan = LocalModelCooperationPolicy.plan(
            executionProfile = executionProfile(AgentExecutionReasoningEffort.MEDIUM),
            availableProfiles = listOf(qwen, gemma, fallback),
            fallbackProfile = fallback
        )

        assertEquals(
            listOf(qwen.id, fallback.id),
            LocalModelCooperationPolicy.fallbackProfiles(
                plan,
                listOf(qwen, gemma, fallback)
            ).map(LocalModelRuntimeProfile::id)
        )
    }

    private fun executionProfile(effort: AgentExecutionReasoningEffort) = AgentExecutionProfile(
        taskKind = if (effort == AgentExecutionReasoningEffort.LOW) {
            AgentExecutionTaskKind.CHAT
        } else {
            AgentExecutionTaskKind.RESEARCH
        },
        reasoningEffort = effort,
        noProgressTimeoutMillis = 60_000L
    )
}
