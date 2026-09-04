package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentClarificationPolicyTest {
    @Test
    fun asksOneTargetedQuestionForMissingRequiredDetails() {
        val cases = listOf(
            "Help me" to AgentClarificationQuestion.TASK_GOAL,
            "Write a program" to AgentClarificationQuestion.CODE_OUTCOME,
            "Control my computer" to AgentClarificationQuestion.CONTROL_ACTION,
            "Research" to AgentClarificationQuestion.RESEARCH_TOPIC,
            "Process the file" to AgentClarificationQuestion.FILE_ACTION,
            "Remember this" to AgentClarificationQuestion.MEMORY_CONTENT,
            "Create an automation" to AgentClarificationQuestion.AUTOMATION_DETAILS,
            "\u5e2e\u6211\u5f04\u4e00\u4e0b" to AgentClarificationQuestion.TASK_GOAL,
            "\u5199\u4e2a\u7a0b\u5e8f" to AgentClarificationQuestion.CODE_OUTCOME,
            "\u63a7\u5236\u624b\u673a" to AgentClarificationQuestion.CONTROL_ACTION,
            "\u641c\u7d22" to AgentClarificationQuestion.RESEARCH_TOPIC,
            "\u8bb0\u4f4f\u8fd9\u4e2a" to AgentClarificationQuestion.MEMORY_CONTENT,
            "\u521b\u5efa\u81ea\u52a8\u5316" to AgentClarificationQuestion.AUTOMATION_DETAILS
        )

        cases.forEach { (goal, expectedQuestion) ->
            val decision = AgentClarificationPolicy.decide(goal)
            assertEquals(goal, AgentClarificationMode.ASK_LOCALLY, decision.mode)
            assertEquals(goal, expectedQuestion, decision.question)
        }
    }

    @Test
    fun clearLowRiskRequestsExecuteWithoutClarification() {
        val requests = listOf(
            "Hello",
            "What is the battery level?",
            "Turn on the flashlight",
            "Set a one minute timer",
            "Research today's AI news",
            "Remember that I prefer concise replies",
            "Build an Android calculator app",
            "\u4f60\u597d",
            "\u6253\u5f00\u624b\u7535\u7b52",
            "\u67e5\u4e00\u4e0b\u4eca\u5929\u4e0a\u6d77\u7684\u5929\u6c14",
            "\u8bb0\u4f4f\u6211\u559c\u6b22\u7b80\u6d01\u56de\u590d"
        )

        requests.forEach { goal ->
            assertEquals(
                goal,
                AgentClarificationMode.EXECUTE,
                AgentClarificationPolicy.decide(goal).mode
            )
        }
    }

    @Test
    fun contextualFollowUpsReuseConversationInsteadOfInterrupting() {
        val requests = listOf(
            "Continue",
            "Try again",
            "Handle this",
            "Make it better",
            "\u7ee7\u7eed",
            "\u518d\u8bd5\u8bd5",
            "\u5e2e\u6211\u5f04\u4e00\u4e0b",
            "\u6309\u4e0a\u9762\u7684\u505a"
        )

        requests.forEach { goal ->
            assertEquals(
                goal,
                AgentClarificationMode.EXECUTE,
                AgentClarificationPolicy.decide(
                    goal,
                    hasConversationContext = true
                ).mode
            )
        }
    }

    @Test
    fun attachmentOnlyAndVagueAttachmentTurnsExecuteWithoutClarification() {
        listOf("", "Take a look", "\u5904\u7406\u4e00\u4e0b").forEach { goal ->
            val decision = AgentClarificationPolicy.decide(
                goal,
                hasAttachments = true
            )

            assertEquals(goal, AgentClarificationMode.EXECUTE, decision.mode)
            assertEquals(goal, AgentClarificationQuestion.NONE, decision.question)
        }
    }

    @Test
    fun anExplicitAttachmentTaskExecutes() {
        val decision = AgentClarificationPolicy.decide(
            "Summarize this PDF and list the action items",
            hasAttachments = true
        )

        assertEquals(AgentClarificationMode.EXECUTE, decision.mode)
    }

    @Test
    fun fewerQuestionsAndAutomationSkipNonBlockingLocalClarifications() {
        listOf(
            AgentPreferenceMode.FEWER_QUESTIONS,
            AgentPreferenceMode.AUTOMATION
        ).forEach { mode ->
            assertEquals(
                mode.name,
                AgentClarificationMode.EXECUTE,
                AgentClarificationPolicy.decide(
                    goal = "Write a program",
                    preferenceMode = mode
                ).mode
            )
        }
    }

    @Test
    fun cautiousAndDeveloperModesKeepEssentialClarification() {
        listOf(
            AgentPreferenceMode.CAUTIOUS,
            AgentPreferenceMode.DEVELOPER
        ).forEach { mode ->
            assertEquals(
                mode.name,
                AgentClarificationMode.ASK_LOCALLY,
                AgentClarificationPolicy.decide(
                    goal = "Write a program",
                    preferenceMode = mode
                ).mode
            )
        }
    }

    @Test
    fun emptyTurnsStillAskButAttachmentOnlyTurnsExecuteForEveryPreference() {
        AgentPreferenceMode.entries.forEach { mode ->
            assertEquals(
                mode.name,
                AgentClarificationMode.ASK_LOCALLY,
                AgentClarificationPolicy.decide(
                    goal = "",
                    preferenceMode = mode
                ).mode
            )
            assertEquals(
                mode.name,
                AgentClarificationMode.EXECUTE,
                AgentClarificationPolicy.decide(
                    goal = "",
                    hasAttachments = true,
                    preferenceMode = mode
                ).mode
            )
        }
    }
}
